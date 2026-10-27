#!/bin/bash
set -e

# ============================================================
#  自动下载 Windows ISO
#  用法: ./download-iso.sh <xp|7u|10|11|tiny11|tiny11std|tiny10> [目标目录]
#
#  镜像源: download.testip.xyz (主), archive.org (备); 10/11 仍用 bobpony/files.dog
#           tiny11/tiny11std 走 archive.org(NTDEV 官方 item 的 Nov25 批次)
#           tiny10 走 archive.org(NTDEV 官方 item, 单源)
#  注: SourceForge 对 GitHub runner IP 段间歇 403(Cloudflare 反爬),不作主源
#  下载完成后校验 SHA256
# ============================================================

VERSION="${1:-}"
DEST="${2:-.}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ts() { date '+%H:%M:%S'; }
info()  { echo -e "${GREEN}[$(ts)] [INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[$(ts)] [WARN]${NC} $*"; }
error() { echo -e "${RED}[$(ts)] [ERROR]${NC} $*"; exit 1; }

if [ -z "$VERSION" ]; then
    echo "用法: $0 <xp|7u|10|11|tiny11|tiny11std|tiny10> [目标目录]"
    echo ""
    echo "  xp       - Windows XP Professional SP3 中文 VL (601MB)"
    echo "  7u       - Windows 7 Ultimate SP1 x64 中文 (3.2GB)"
    echo "  10       - Windows 10 22H2 x64 (5.7GB)"
    echo "  11       - Windows 11 25H2 x64 (7.9GB)"
    echo "  tiny11   - Tiny11 Core 25H2 Pro x64 英文 (3.3GB, 不可服务化精简版)"
    echo "  tiny11std- Tiny11 25H2 Pro x64 英文 标准版 (5.3GB, 可服务化, 自带 Defender)"
    echo "  tiny10   - Tiny10 23H2 x64 英文 (3.6GB, 可服务化, 基于 Win10 LTSC 2021)"
    exit 1
fi

# ── 检查依赖 ──
command -v wget >/dev/null 2>&1 || error "需要安装 wget"
command -v curl >/dev/null 2>&1 || error "需要安装 curl"
command -v sha256sum >/dev/null 2>&1 || error "需要安装 coreutils (sha256sum)"

# ── ISO 定义 ──
# 从 dockur/windows define.sh 提取的镜像源和校验值
get_iso_info() {
    local version="$1"

    case "${version,,}" in
        "xp" )
            FILE="zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso"
            SIZE="630237184"
            SHA="39430c2b8dd5c21bbd5af9116573f8c574ae896ce31d47280914ef268f01e33f"
            # 镜像源：testip 直链（约 17MB/s），archive.org 备源
            URLS=(
                "https://download.testip.xyz/windows/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso"
                "https://archive.org/download/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070/zh-hans_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-74070.iso"
            )
            ;;
        "7u" | "7" )
            FILE="cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso"
            SIZE="3420557312"
            SHA="70cdfb0cdcbeb2659163e9417d5c242b37ae564da810e7da21dac5c8492ab72f"
            # 镜像源列表（按优先级排序）
            # 注: 原 item(cn_windows_7_..._u_677408)已被微软 DMCA 撤除、testip 源站 521
            #     —— 换用 archive.org 上仍存活的同文件 item(多备几个, SHA256 兜底错文件)
            URLS=(
                "https://archive.org/download/Win7UltimateSP1CHS/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso"
                "https://archive.org/download/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408_202011/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso"
                "https://archive.org/download/windows_7_Ult_wit_sp1_10_lang/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso"
                "https://download.testip.xyz/windows/cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso"
            )
            ;;
        "10" )
            FILE="en-us_windows_10_22h2_x64.iso"
            SIZE="6140975104"
            SHA="a6f470ca6d331eb353b815c043e327a347f594f37ff525f17764738fe812852e"
            URLS=(
                "https://dl.bobpony.com/windows/10/en-us_windows_10_22h2_x64.iso"
                "https://files.dog/MSDN/Windows%2010/en-us_windows_10_22h2_x64.iso"
                "https://archive.org/download/en-us_windows_10_22h2_x64/en-us_windows_10_22h2_x64.iso"
            )
            ;;
        "11" )
            FILE="en-us_windows_11_25h2_x64.iso"
            SIZE="7736125440"
            SHA="d141f6030fed50f75e2b03e1eb2e53646c4b21e5386047cb860af5223f102a32"
            URLS=(
                "https://dl.bobpony.com/windows/11/en-us_windows_11_25h2_x64.iso"
                "https://files.dog/MSDN/Windows%2011/en-us_windows_11_25h2_x64.iso"
                "https://archive.org/download/en-us_windows_11_25h2_x64/en-us_windows_11_25h2_x64.iso"
            )
            ;;
        "tiny11" )
            # canonical = archive.org NTDEV 官方镜像 Nov25 core(2026-10 探测: item 仍存活)。
            # SF 上的 2026-08-23 构建对 GitHub runner IP 段间歇 403(Cloudflare 反爬)、
            # 且文件名/内容与 archive.org 盘不同 —— 为避免"资产名与内容不符",统一用
            # Nov25 单源(发布后的消费方走本仓 release,镜像源只影响重建)。
            FILE="tiny11core_25H2_Nov25.iso"
            SIZE="3304132608"
            SHA=""
            URLS=(
                "https://archive.org/download/tiny11_25H2/tiny11core_25H2_Nov25.iso"
            )
            ;;
        "tiny11std" | "tiny11-std" )
            # 标准盘(可服务化, 自带 Windows Update/Defender) —— 与 core 同一 archive.org
            # item、同一 Nov25 批次, 资产名即 tiny11_25H2_Nov25.iso。
            # 不设 SF 备源: 那边是另一份构建(名字/内容都不同), 当 fallback 会"资产名与
            # 内容不符"; 且 SF 对 runner IP 段间歇 403。SIZE/SHA 留空 —— 精确值由发布时
            # 实测写入 release 的 SHA256SUMS.txt, 消费方门禁在 quickwin 仓(OWN_SIZE/OWN_SHA)。
            FILE="tiny11_25H2_Nov25.iso"
            SIZE=""
            SHA=""
            URLS=(
                "https://archive.org/download/tiny11_25H2/tiny11_25H2_Nov25.iso"
            )
            ;;
        "tiny10" )
            # NTDEV tiny10 23H2 x64 —— 基于 Win10 LTSC 2021(21H2 / 19044), 可服务化,
            # 面向低配机; 与 tiny11 不同, 没有 core/标准盘之分, 只有这一条主线。
            # archive.org 上的原始文件名带空格("tiny10 x64 23h2.iso"), 用 wget -O 落成本地名。
            # 第三方单源, SIZE/SHA 留空 —— 精确值由发布时实测写入 release 的 SHA256SUMS.txt。
            FILE="tiny10_23H2_x64.iso"
            SIZE=""
            SHA=""
            URLS=(
                "https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso"
            )
            ;;
        * )
            error "不支持的版本: $version (支持: xp, 7u, 10, 11, tiny11, tiny11std, tiny10)"
            ;;
    esac
}

# ── 校验 ──
verify_sha() {
    local f="$1" expect="$2" actual
    [ -z "$expect" ] && return 0
    actual=$(sha256sum "$f" | awk '{print $1}')
    if [ "$actual" != "$expect" ]; then
        rm -f "$f"
        error "SHA256 校验失败: $f
  期望: $expect
  实际: $actual
  （文件已删除）"
    fi
    info "SHA256 校验通过: $actual"
}

# ── SourceForge 中转页解析 ──
# SourceForge 对所有镜像主机（含 <mirror>.dl.sourceforge.net 和 use_mirror=xxx）
# 都先回一张 text/html 的中转页，真实地址在其 <noscript> 的 meta refresh 里，
# 且带时效签名 ts=。直接 wget 那个 URL 只会存下一个 HTML 文件。
resolve_url() {
    local url="$1" ctype resolved
    ctype=$(curl -sIL -A "$UA" --connect-timeout=20 --max-time=30 \
                 -o /dev/null -w '%{content_type}' "$url" 2>/dev/null)
    case "$ctype" in
        text/html*)
            resolved=$(curl -sL -A "$UA" --connect-timeout=20 --max-time=30 "$url" 2>/dev/null \
                | grep -o 'http-equiv="refresh" content="[^"]*url=[^"]*"' \
                | head -1 | sed 's/.*url=//; s/"$//; s/&amp;/\&/g')
            if [ -n "$resolved" ]; then
                # 注意：本函数结果会被 $(...) 捕获，日志必须走 stderr，否则会被混进 URL
                info "已解析 SourceForge 签名直链" >&2
                echo "$resolved"
                return 0
            fi
            warn "中转页里没找到签名直链，回退到原始 URL" >&2
            ;;
    esac
    echo "$url"
}

# ── 主逻辑 ──
get_iso_info "$VERSION"

mkdir -p "$DEST"
OUTPUT="$DEST/$FILE"

# 已存在则不重复下载，但仍校验完整性（否则跳过就成了完整性盲区）
if [ -f "$OUTPUT" ]; then
    info "文件已存在，校验完整性: $OUTPUT"
    verify_sha "$OUTPUT" "$SHA"
    exit 0
fi

# 尝试所有镜像源
# 注: bobpony/files.dog 等源不带浏览器 UA 会返回 403/拒连，必须带 UA
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
SUCCESS=false
for URL in "${URLS[@]}"; do
    URL=$(resolve_url "$URL")
    info "尝试下载: $URL"
    wget -q -U "$UA" --connect-timeout=20 --timeout=120 --tries=2 \
         -O "$OUTPUT" "$URL" &
    WGET_PID=$!
    # 后台运行 wget，主循环每 10 秒打印一次进度，避免 --show-progress 刷屏
    while kill -0 "$WGET_PID" 2>/dev/null; do
        sleep 10
        if [ -f "$OUTPUT" ]; then
            sz=$(du -h "$OUTPUT" 2>/dev/null | cut -f1)
            [ -n "$sz" ] && info "已下载: $sz"
        fi
    done
    # set -e 下 wait 遇到非零子进程会直接终止脚本（退出码=子进程退出码），
    # 下面的 fallback 判断永远执行不到。必须用 || 捕获退出码。
    RC=0
    wait "$WGET_PID" || RC=$?
    if [ "$RC" -eq 0 ]; then
        SUCCESS=true
        break
    else
        warn "下载失败 (wget 退出码 $RC): $URL"
        rm -f "$OUTPUT"
    fi
done

if [ "$SUCCESS" = false ]; then
    error "所有镜像源均下载失败"
fi

# 大小不符先报出来，便于区分"下到 HTML 中转页"和"真的下全了"
ACTUAL_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || echo 0)
if [ -n "$SIZE" ] && [ "$ACTUAL_SIZE" != "$SIZE" ]; then
    rm -f "$OUTPUT"
    error "大小不符: 期望 $SIZE 字节，实际 $ACTUAL_SIZE 字节（文件已删除）"
fi

verify_sha "$OUTPUT" "$SHA"

info "下载完成: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
