#!/bin/bash
set -euo pipefail

# ============================================================
#  下载 ISO → 分卷(<2GiB) → 发布 GitHub Release
#  用法: ./publish.sh <xp|7u|tiny11>   （CI workflow_dispatch 调用）
#
#  release tag 按类型固定:
#    xp     → win-isos-xp      (2 卷, 602MB)
#    7u     → win-isos-win7    (2 卷, 3.2GB)
#    tiny11 → win-isos-tiny11  (2 卷, 3.0GB)
#
#  资产: ${FILE}.part00..NN (split -b 1800m, cat 可重组)
#        SHA256SUMS.txt (原始 ISO + 各分卷校验和)
#
#  重跑即覆盖(--clobber)——release 可变,sha256 是唯一 integrity 锚点。
# ============================================================

TYPE="${1:-}"
case "$TYPE" in
    xp)                 TAG="win-isos-xp";     DL_ARG="xp" ;;
    7u|7|win7)          TAG="win-isos-win7";   DL_ARG="7u" ;;
    tiny11)             TAG="win-isos-tiny11"; DL_ARG="tiny11" ;;
    *) echo "用法: $0 <xp|7u|tiny11>"; exit 1 ;;
esac

command -v gh >/dev/null 2>&1 || { echo "[ERROR] 需要 gh CLI"; exit 1; }
# gh 需要仓库上下文 —— 下面会 cd 到临时目录, 显式指定 repo(本地/CI 通用)
export GH_REPO="${GITHUB_REPOSITORY:-quickwinlabs/assets}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── 下载(带镜像源 fallback + SHA 校验)──
"$SCRIPT_DIR/download-iso.sh" "$DL_ARG" "$WORK"

ISO=$(ls "$WORK"/*.iso)
FILE=$(basename "$ISO")
SHA=$(sha256sum "$ISO" | awk '{print $1}')
SIZE=$(stat -c%s "$ISO")
echo "[INFO] $FILE  size=$SIZE  sha256=$SHA"

# ── 分卷(<2GiB 硬限; 1800m ≈ 1.76GiB 留余量)──
cd "$WORK"
split -b 1800m -d -a 2 "$FILE" "${FILE}.part"
sha256sum "${FILE}".part* > PARTS.sha256
{ echo "$SHA  $FILE"; cat PARTS.sha256; } > SHA256SUMS.txt

# ── release notes ──
cat > notes.md <<EOF
Automated release of \`$FILE\` (type: \`$TYPE\`) as split volumes.

- **Size**: $SIZE bytes
- **SHA256**: \`$SHA\`
- **Reassemble**: \`cat ${FILE}.part* > ${FILE}\`
- **Verify**: \`sha256sum -c SHA256SUMS.txt\` (parts + reassembled ISO)

Rebuilt by CI from the public mirrors declared in \`scripts/download-iso.sh\`;
re-running the workflow re-publishes and replaces assets in place (\`--clobber\`).
EOF

# ── 发布(存在则更新 notes,不存在则创建;资产一律 --clobber 覆盖)──
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release edit "$TAG" --notes-file notes.md
else
    gh release create "$TAG" --title "$TAG" --notes-file notes.md
fi
gh release upload "$TAG" --clobber "${FILE}".part* SHA256SUMS.txt

echo "[INFO] published: $TAG"
gh release view "$TAG" --json assets --jq '.assets[] | "\(.name)  \(.size)"'
