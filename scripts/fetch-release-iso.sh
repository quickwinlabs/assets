#!/bin/bash
set -euo pipefail

# ============================================================
#  从本仓的 win-isos-* release 拉一份 ISO（分卷 + SHA256SUMS 校验）
#  用法: ./fetch-release-iso.sh <xp|7u|tiny11|tiny11std> [目标目录]
#
#  供 images/setup-*.sh 装机使用 —— 装机只吃本仓已发布的 ISO，
#  装出来的盘与发布出去的盘是同一份，和上游镜像源当前是否可达无关。
#
#  方向说明: publish.sh（发布侧）用 download-iso.sh 拉**上游**镜像源；
#           本脚本拉**已发布的 release**。两者方向相反，不要互相调用。
# ============================================================

TYPE="${1:-}"
DEST="${2:-.}"
case "$TYPE" in
    xp)          TAG="win-isos-xp" ;;
    7u|7|win7)   TAG="win-isos-win7" ;;
    tiny11)      TAG="win-isos-tiny11" ;;
    tiny11std)   TAG="win-isos-tiny11-std" ;;
    *) echo "用法: $0 <xp|7u|tiny11|tiny11std> [目标目录]"; exit 1 ;;
esac

command -v gh >/dev/null 2>&1 || { echo "[ERROR] 需要 gh CLI"; exit 1; }
# gh 需要仓库上下文 —— 显式指定 repo（本地/CI 通用）
export GH_REPO="${GITHUB_REPOSITORY:-quickwinlabs/assets}"

mkdir -p "$DEST"
cd "$DEST"

# 已拉过就跳过（装机脚本常被重跑，不必重复下 5.7GB）
if ls ./*.iso >/dev/null 2>&1; then
    echo "[INFO] ISO 已存在，跳过下载: $(ls ./*.iso)"
    exit 0
fi

# ── 下载该 release 的全部资产（分卷 + SHA256SUMS.txt）──
echo "[INFO] 从 release 拉取: $TAG"
gh release download "$TAG" --dir . --clobber
[ -f SHA256SUMS.txt ] || { echo "[ERROR] $TAG 里没有 SHA256SUMS.txt"; exit 1; }

# ── 校验分卷 → 拼接 → 校验整盘 ──
# SHA256SUMS.txt 第一行是整盘，其余是各分卷。按第二列精确比对，
# 免得 "foo.iso" 误匹配 "foo.iso.part00"。
FILE="$(awk 'NR==1{print $2}' SHA256SUMS.txt)"
awk -v f="$FILE" '$2!=f' SHA256SUMS.txt > .parts.sums
awk -v f="$FILE" '$2==f'  SHA256SUMS.txt > .whole.sums
[ -s .whole.sums ] || { echo "[ERROR] SHA256SUMS.txt 里没有整盘记录: $FILE"; exit 1; }

echo "[INFO] 校验分卷..."
sha256sum -c .parts.sums

echo "[INFO] 拼接分卷 → $FILE"
cat "${FILE}".part* > "$FILE"

echo "[INFO] 校验拼回的整盘..."
sha256sum -c .whole.sums
rm -f .parts.sums .whole.sums

# 分卷不再需要（装机只用整盘），删掉把磁盘留给安装盘
rm -f "${FILE}".part*

echo "[INFO] ISO 就绪: $(pwd)/$FILE  ($(stat -c%s "$FILE") 字节)"
