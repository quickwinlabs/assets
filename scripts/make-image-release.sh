#!/bin/bash
set -euo pipefail

# ============================================================
#  预装系统盘 → 压缩(qcow2 zstd) → 分卷(<2GiB) → 发布 GitHub Release
#  用法: ./make-image-release.sh <xp|win7|win11|win11core> <tag> [输入盘路径]
#  例:   ./make-image-release.sh win7 win-images-win7
#
#  输入盘默认取 images/snapshots/<name>_ready.qcow2（setup-*.sh 的产物）。
#
#  为什么压缩: 盘 12.5GB 级别的数据里仍有可观的可压部分,压缩后上传/下载都省;
#              压缩簇是 qcow2 原生特性,qemu 能直接读,不必先解压。
#  为什么分卷: GitHub 单个 release 资产硬限 2GiB。
#
#  消费方注意: 压缩盘是只读形态,必须叠 overlay 使用(run.sh 就是这么用的)。
# ============================================================

TYPE="${1:-}"
TAG="${2:-}"
case "$TYPE" in
    xp)       NAME="xp_ready.qcow2"        ; ISO_TAG="win-isos-xp"         ;;
    win7)     NAME="win7_ready.qcow2"      ; ISO_TAG="win-isos-win7"       ;;
    win11)    NAME="win11_ready.qcow2"     ; ISO_TAG="win-isos-tiny11-std" ;;
    win11core) NAME="win11_ready-core.qcow2"; ISO_TAG="win-isos-tiny11"     ;;
    *) echo "用法: $0 <xp|win7|win11|win11core> <tag> [输入盘路径]"; exit 1 ;;
esac
[ -n "$TAG" ] || { echo "用法: $0 <$TYPE> <tag> [输入盘路径]"; exit 1; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN="${3:-$REPO_ROOT/images/snapshots/$NAME}"
[ -f "$IN" ] || { echo "[ERROR] 输入盘不存在: $IN"; exit 1; }

for c in qemu-img split sha256sum gh; do
    command -v "$c" >/dev/null || { echo "[ERROR] 需要 $c"; exit 1; }
done
export GH_REPO="${GITHUB_REPOSITORY:-quickwinlabs/assets}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── 压缩（-c = 压缩簇；zstd 需要 qemu >= 5.4，老版本回落到默认 zlib）──
SRC_SIZE=$(stat -c%s "$IN")
VIRT=$(qemu-img info --output=json "$IN" | python3 -c 'import sys,json; print(json.load(sys.stdin)["virtual-size"])')
echo "[INFO] 输入: $IN  实际 $SRC_SIZE 字节  虚拟 $VIRT 字节"
echo "[INFO] 压缩中（qemu-img convert -c，zstd 压缩簇）..."
qemu-img convert -O qcow2 -c -o compression_type=zstd "$IN" "$WORK/$NAME"

cd "$WORK"
OUT_SIZE=$(stat -c%s "$NAME")
SHA=$(sha256sum "$NAME" | awk '{print $1}')
PCT=$(awk -v a="$OUT_SIZE" -v b="$SRC_SIZE" 'BEGIN{printf "%.1f%%", a*100/b}')
echo "[INFO] 压缩后: $OUT_SIZE 字节（$PCT）"
echo "[INFO] SHA256: $SHA"

# ── 分卷（<2GiB 硬限；1800m ≈ 1.76GiB 留余量，与 ISO 发布同一套规则）──
# PART_SIZE 可覆盖（测试用，例如 PART_SIZE=20m 验多卷拼接）
PART_SIZE="${PART_SIZE:-1800m}"
split -b "$PART_SIZE" -d -a 2 "$NAME" "${NAME}.part"
sha256sum "${NAME}".part* > PARTS.sha256
{ echo "$SHA  $NAME"; cat PARTS.sha256; } > SHA256SUMS.txt
rm -f PARTS.sha256
PARTS_N=$(ls "${NAME}".part* | wc -l)
echo "[INFO] 分卷: $PARTS_N 个 × $PART_SIZE"

# ── release notes ──
cat > notes.md <<EOF
Prebuilt Windows disk image for testing (\`$TYPE\`), as a compressed qcow2 split into volumes.

- **Source**: installed from scratch by this repo's \`build-image\` workflow on a
  GitHub runner, using the ISO from the \`$ISO_TAG\` release.
- **Built at**: $(date -u '+%Y-%m-%d %H:%M:%S UTC') (commit \`${GITHUB_SHA:-local}\`)
- **Compressed size**: $OUT_SIZE bytes (uncompressed qcow2 was $SRC_SIZE bytes)
- **Parts**: $PARTS_N × $PART_SIZE
- **SHA256**: \`$SHA\`
- **Reassemble**: \`cat ${NAME}.part* > ${NAME}\`
- **Verify**: \`sha256sum -c SHA256SUMS.txt\` (run **after** reassembling — it covers the parts and the image)

Using it (qemu >= 5.4 required for zstd compression clusters):

\`\`\`sh
cat ${NAME}.part* > ${NAME}
sha256sum -c SHA256SUMS.txt
# the image is read-only in this form — stack an overlay to run it
qemu-img create -f qcow2 -b ${NAME} -F qcow2 overlay.qcow2
\`\`\`

Re-running the workflow re-publishes and replaces assets in place (old assets are
deleted first, so a shrinking volume count cannot leave stale parts behind).
EOF

# ── 发布: 先删旧资产（分卷数变化时避免孤儿卷污染 cat *.part*），再上传 ──
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "[INFO] release $TAG 已存在，先清空旧资产..."
    # 先取列表再循环：管道里的 while 会把 gh 的失败吞掉（管道状态取末尾命令），
    # 那样一旦读不到资产列表就会静默跳过清理、再 --clobber 上传 → 留下孤儿卷。
    OLD_ASSETS="$(gh release view "$TAG" --json assets --jq '.assets[].name')"
    while IFS= read -r a; do
        [ -n "$a" ] && gh release delete-asset "$TAG" "$a" -y >/dev/null
    done <<< "$OLD_ASSETS"
    gh release edit "$TAG" --notes-file notes.md
else
    gh release create "$TAG" --title "$TAG" --notes-file notes.md
fi
gh release upload "$TAG" --clobber "${NAME}".part* SHA256SUMS.txt

echo "[INFO] 已发布: $TAG"
gh release view "$TAG" --json assets --jq '.assets[] | "\(.name)  \(.size)"'
