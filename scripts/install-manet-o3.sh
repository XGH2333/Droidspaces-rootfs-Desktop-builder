#!/usr/bin/env bash
set -euo pipefail

# install-manet-o3 — 玄戒 O3 / Mali GPU 驱动安装器（mesa-manet PanVK/Zink）
# 上游: https://github.com/DsoTsin/mesa-manet （分支 manet-v15-magni-g2-ultra-nx）
# 经真机验证: Xiaomi Pad 9 Pro Max (玄戒 O3, Mali-G2-Ultra MC16, kbase /dev/mali0)
#   - vulkaninfo 枚举 Mali-G2-Ultra MC16, OpenGL 经 Zink 正常
#   - Chrome WebGL 实测 ANGLE(Vulkan) 真实光栅化
# 仅支持 Debian 13 / Ubuntu 24.04+（manet 以 deb 分发）。
#
# 用法:
#   install-manet-o3 [-1|--1 | -2|--2] [-V pinned|latest] [--no-verify] [--uninstall]
#     -1/--1        使用 GitHub 下载（默认）
#     -2/--2        使用 gh-proxy.com 镜像下载
#     -V            版本模式: pinned=固定 v1.0（默认）, latest=GitHub 最新 release
#     --no-verify   跳过 SHA256 校验（不推荐；pinned 模式下校验值内置，latest 模式下从
#                   release 的 SHA256SUMS 读取）
#     --uninstall   卸载并恢复到安装前状态

readonly RELEASE_REPOSITORY="DsoTsin/mesa-manet"
readonly RELEASE_API_LATEST="https://api.github.com/repos/${RELEASE_REPOSITORY}/releases/latest"
readonly GITHUB_URL="https://github.com"
readonly GH_PROXY_URL="https://gh-proxy.com/https://github.com"
readonly PINNED_TAG="v1.0"
readonly PINNED_DEB="manet-a2a7103fc7f.deb"
readonly PINNED_SHA256="b27232b44a1b82d09cb67437ff6573f105ab412f1bbad7e2121630ad0d8069e1"
readonly MANET_ROOT="/opt/mesa-manet"
readonly MANET_ENV="${MANET_ROOT}/env.sh"
readonly MANET_ICD="${MANET_ROOT}/share/vulkan/icd.d/manet_icd.armv8-a.json"
readonly ANLAND_SESSION="/usr/bin/anland-session"
readonly ANLAND_SESSION_BAK="/usr/bin/anland-session.pre-manet"
readonly CHROME_WRAPPER="/usr/local/bin/google-chrome"
readonly CHROME_WRAPPER_BAK="/usr/local/bin/google-chrome.pre-manet"
readonly ENV_FILE="/etc/environment"
readonly STATE_DIR="/var/lib/droidspaces-tui/components"
readonly STATE_FILE="${STATE_DIR}/manet-o3.version"
readonly MAX_DEB_BYTES=$((512 * 1024 * 1024))

UI_LANG="zh"
DOWNLOAD_SOURCE="1"
VERSION_MODE="pinned"
VERIFY=true
UNINSTALL=false
WORK_DIR=""
DEB_FILE=""
DEB_NAME=""
RESOLVED_TAG=""
RESOLVED_SHA256=""

detect_language() {
    local locale_name="${LC_ALL:-${LC_MESSAGES:-${LANG:-C}}}"
    locale_name="${locale_name,,}"
    if [[ "$locale_name" == zh* ]]; then
        UI_LANG="zh"
    fi
}

msg() {
    if [[ "$UI_LANG" == "zh" ]]; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

log() { printf '[install-manet-o3] %s\n' "$(msg "$1" "$2")"; }

die() {
    printf '[install-manet-o3] %s: %s\n' \
        "$(msg '错误' 'Error')" "$(msg "$1" "$2")" >&2
    exit 1
}

usage() {
    cat <<EOF
$(msg '用法' 'Usage'): $0 [-1|--1 | -2|--2] [-V pinned|latest] [--no-verify] [--uninstall]

  -1, --1       $(msg '使用 GitHub 下载（默认）' 'Download from GitHub (default)')
  -2, --2       $(msg '使用 gh-proxy.com 镜像下载' 'Download via the gh-proxy.com mirror')
  -V            $(msg '版本模式: pinned=固定 v1.0, latest=最新 release' 'Version mode: pinned=v1.0, latest=newest release')
  --no-verify   $(msg '跳过 SHA256 校验（不推荐）' 'Skip SHA256 verification (not recommended)')
  --uninstall   $(msg '卸载并恢复安装前状态' 'Uninstall and restore the pre-install state')
EOF
}

cleanup() {
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

parse_arguments() {
    while (($#)); do
        case "$1" in
            -1|--1) DOWNLOAD_SOURCE="1"; shift ;;
            -2|--2) DOWNLOAD_SOURCE="2"; shift ;;
            -V)
                (( $# >= 2 )) || die \
                    "-V 需要紧跟版本模式（pinned|latest）。" \
                    "-V requires a mode argument (pinned|latest)."
                VERSION_MODE="$2"; shift 2 ;;
            -V*) VERSION_MODE="${1#-V}"; shift ;;
            --no-verify) VERIFY=false; shift ;;
            --uninstall) UNINSTALL=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *)
                die "不支持的参数：$1。" "Unsupported argument: $1."
                ;;
        esac
    done
    case "$VERSION_MODE" in
        pinned|latest) ;;
        *) die "无效的版本模式：${VERSION_MODE}（pinned|latest）。" \
               "Invalid version mode: ${VERSION_MODE} (pinned|latest)." ;;
    esac
}

require_root() {
    (( EUID == 0 )) && return
    command -v sudo >/dev/null 2>&1 || die \
        "请使用 root 运行此脚本。" "Please run this script as root."
    exec sudo --preserve-env=LANG,LC_ALL,LC_MESSAGES -- bash "${BASH_SOURCE[0]}" "$@"
}

check_environment() {
    [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。" \
        "Unable to read /etc/os-release."
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID,,}" in
        debian|ubuntu) ;;
        *)
            die "manet 仅提供 Debian/Ubuntu deb 包，当前系统为 ${PRETTY_NAME:-unknown}。" \
                "manet ships Debian/Ubuntu .deb packages only; current system is ${PRETTY_NAME:-unknown}."
            ;;
    esac
    case "$(uname -m)" in
        aarch64|arm64) ;;
        *)
            die "manet 仅支持 ARM64，当前架构为 $(uname -m)。" \
                "manet supports ARM64 only; current architecture is $(uname -m)."
            ;;
    esac
    command -v apt-get >/dev/null 2>&1 || die "未找到 apt-get。" \
        "apt-get was not found."
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        die "未找到 curl 或 wget。" "Neither curl nor wget was found."
    fi
}

download_stdout() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 120 "$url"
    else
        wget -q --tries=5 --timeout=20 --waitretry=3 -O - "$url"
    fi
}

download_file() {
    local url="$1" destination="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 5 --retry-all-errors --connect-timeout 20 --max-time 600 \
            --continue-at - "$url" -o "$destination"
    else
        wget --continue --tries=5 --timeout=20 --waitretry=3 -O "$destination" "$url"
    fi
}

source_url_prefix() {
    case "$DOWNLOAD_SOURCE" in
        1) printf '%s' "$GITHUB_URL" ;;
        2) printf '%s' "$GH_PROXY_URL" ;;
        *) return 1 ;;
    esac
}

asset_url() {
    local tag="$1" asset="$2"
    printf '%s/%s/releases/download/%s/%s' \
        "$(source_url_prefix)" "$RELEASE_REPOSITORY" "$tag" "$asset"
}

resolve_latest_release() {
    local metadata deb_url sums_url

    log "正在查询 ${RELEASE_REPOSITORY} 最新 release..." \
        "Querying the newest release of ${RELEASE_REPOSITORY}..."
    metadata="$(download_stdout "$RELEASE_API_LATEST")" || die \
        "无法访问 GitHub API（可能触发限流）。可改用 -V pinned。" \
        "Unable to reach the GitHub API (rate limit possible). Use -V pinned instead."

    RESOLVED_TAG="$(printf '%s' "$metadata" | grep -oE '"tag_name": *"[^"]+"' \
        | head -1 | sed 's/.*"tag_name": *"//; s/"$//')"
    [[ -n "$RESOLVED_TAG" ]] || die \
        "最新 release 没有有效的 tag_name。" \
        "The newest release has no valid tag_name."

    deb_url="$(printf '%s' "$metadata" \
        | grep -oE '"browser_download_url": *"https://github.com/[^"]+/manet-[0-9a-f]+\.deb"' \
        | head -1 | sed 's/.*"browser_download_url": *"//; s/"$//')"
    [[ -n "$deb_url" ]] || die \
        "最新 release 没有 Linux deb 资产（manet-*.deb）。" \
        "The newest release has no Linux .deb asset (manet-*.deb)."
    DEB_NAME="${deb_url##*/}"

    if [[ "$VERIFY" == true ]]; then
        sums_url="$(asset_url "$RESOLVED_TAG" "SHA256SUMS")"
        log "正在读取 ${RESOLVED_TAG} 的 SHA256SUMS..." \
            "Reading SHA256SUMS for ${RESOLVED_TAG}..."
        RESOLVED_SHA256="$(download_stdout "$sums_url" \
            | awk -v name="$DEB_NAME" '$2 == name { print tolower($1) }')" || true
        [[ "$RESOLVED_SHA256" =~ ^[0-9a-f]{64}$ ]] || die \
            "SHA256SUMS 中找不到 ${DEB_NAME} 的校验值。可用 --no-verify 跳过。" \
            "SHA256SUMS has no digest for ${DEB_NAME}. --no-verify skips this check."
    fi
    log "已选择: ${RESOLVED_TAG}/${DEB_NAME}" "Selected: ${RESOLVED_TAG}/${DEB_NAME}"
}

resolve_pinned_release() {
    RESOLVED_TAG="$PINNED_TAG"
    DEB_NAME="$PINNED_DEB"
    RESOLVED_SHA256="$PINNED_SHA256"
    log "使用固定版本: ${RESOLVED_TAG}/${DEB_NAME}" \
        "Using the pinned version: ${RESOLVED_TAG}/${DEB_NAME}"
}

download_deb() {
    local url size

    WORK_DIR="$(mktemp -d -t install-manet-o3.XXXXXXXX)"
    DEB_FILE="${WORK_DIR}/${DEB_NAME}"
    url="$(asset_url "$RESOLVED_TAG" "$DEB_NAME")"
    log "正在从 $( [[ "$DOWNLOAD_SOURCE" == 1 ]] && printf 'GitHub' || printf 'gh-proxy.com' ) 下载 ${DEB_NAME}..." \
        "Downloading ${DEB_NAME} from $( [[ "$DOWNLOAD_SOURCE" == 1 ]] && printf 'GitHub' || printf 'gh-proxy.com' )..."
    download_file "$url" "$DEB_FILE" || die \
        "下载失败: ${url}" "Download failed: ${url}"
    [[ -f "$DEB_FILE" ]] || die "下载文件不存在。" \
        "The downloaded file does not exist."
    size="$(stat -c '%s' "$DEB_FILE")"
    [[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 && "$size" -le "$MAX_DEB_BYTES" ]] || die \
        "下载文件大小无效（${size} 字节）。" "Downloaded file size is invalid (${size} bytes)."
}

verify_deb() {
    local actual

    [[ "$VERIFY" == true ]] || {
        log "警告: 已跳过 SHA256 校验。" "Warning: SHA256 verification was skipped."
        return 0
    }
    [[ "$RESOLVED_SHA256" =~ ^[0-9a-f]{64}$ ]] || die \
        "内部错误: 没有可用的 SHA256 校验值。" \
        "Internal error: no SHA256 digest is available."
    command -v sha256sum >/dev/null 2>&1 || die \
        "未找到 sha256sum，无法校验。" "sha256sum was not found; verification is impossible."
    actual="$(sha256sum "$DEB_FILE" | awk '{print tolower($1)}')"
    [[ "$actual" == "$RESOLVED_SHA256" ]] || die \
        "SHA256 校验失败（期望 ${RESOLVED_SHA256}，实际 ${actual}）。" \
        "SHA256 verification failed (expected ${RESOLVED_SHA256}, got ${actual})."
    log "SHA256 校验通过。" "SHA256 verification passed."
}

install_deb() {
    log "正在安装 mesa-manet..." "Installing mesa-manet..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$DEB_FILE"; then
        # apt 索引可能在镜像瘦身时被清理；刷新后重试，最后退回 dpkg。
        log "apt 安装失败，刷新索引后重试..." \
            "apt install failed; refreshing package indexes and retrying..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$DEB_FILE" \
            || dpkg -i "$DEB_FILE" \
            || die "deb 安装失败。" "The .deb install failed."
    fi
    dpkg -s mesa-manet-rock5b >/dev/null 2>&1 || die \
        "安装后未找到 mesa-manet-rock5b 包。" \
        "The mesa-manet-rock5b package was not found after installation."
    [[ -f "$MANET_ENV" && -f "$MANET_ICD" ]] || die \
        "安装后缺少 manet 运行时文件。" "manet runtime files are missing after installation."
    command -v ldconfig >/dev/null 2>&1 && ldconfig || true
}

disable_foreign_icds() {
    local dir json

    # 禁用其他 Vulkan ICD（freedreno/lvp 等），确保加载器只看到 manet。
    for dir in /usr/share/vulkan/icd.d /etc/vulkan/icd.d; do
        [[ -d "$dir" ]] || continue
        for json in "$dir"/*.json; do
            [[ -e "$json" ]] || continue
            case "$json" in *manet*) continue ;; esac
            if [[ -e "${json}.disabled" ]]; then
                rm -f -- "$json"
            else
                mv -n -- "$json" "${json}.disabled"
            fi
        done
    done
}

write_environment() {
    local tmp

    # 用 manet 配置替换所有 GPU 相关环境变量；同时清掉高通/kgsl 残留。
    install -d -m 0755 "$(dirname "$ENV_FILE")"
    touch "$ENV_FILE"
    tmp="$(mktemp -t install-manet-o3-env.XXXXXXXX)"
    grep -vE '^(VK_DRIVER_FILES|VK_ICD_FILENAMES|MESA_LOADER_DRIVER_OVERRIDE|GALLIUM_DRIVER|PAN_USE_KRAID|RUSTICL_ENABLE|FD_FORCE_KGSL|TU_DEBUG)=' \
        "$ENV_FILE" > "$tmp" || true
    cat >> "$tmp" <<EOF
VK_DRIVER_FILES=${MANET_ICD}
VK_ICD_FILENAMES=${MANET_ICD}
MESA_LOADER_DRIVER_OVERRIDE=zink
GALLIUM_DRIVER=zink
PAN_USE_KRAID=all
RUSTICL_ENABLE=zink,llvmpipe
EOF
    install -m 0644 "$tmp" "$ENV_FILE"
    rm -f -- "$tmp"
}

patch_anland_session() {
    [[ -f "$ANLAND_SESSION" ]] || {
        log "未找到 anland-session，跳过补丁。" \
            "anland-session was not found; skipping the patch."
        return 0
    }
    if ! grep -q 'MESA_LOADER_DRIVER_OVERRIDE:-kgsl' "$ANLAND_SESSION"; then
        log "anland-session 无需修改（可能已打过补丁）。" \
            "anland-session needs no changes (possibly already patched)."
        return 0
    fi
    [[ -f "$ANLAND_SESSION_BAK" ]] || cp -p -- "$ANLAND_SESSION" "$ANLAND_SESSION_BAK"
    # 默认驱动 kgsl(高通) → zink(Mali/manet)，并移除 FD_FORCE_KGSL 注入。
    sed -i \
        -e 's/MESA_LOADER_DRIVER_OVERRIDE:-kgsl/MESA_LOADER_DRIVER_OVERRIDE:-zink/' \
        -e 's/GALLIUM_DRIVER:-kgsl/GALLIUM_DRIVER:-zink/' \
        -e '/export FD_FORCE_KGSL=/d' \
        "$ANLAND_SESSION"
    # 合并 set-environment 的续行，摘除 FD_FORCE_KGSL 参数（GNU sed：N 累积后 \n 匹配换行）。
    sed -i ':a;N;$!ba;s|"GALLIUM_DRIVER=\$GALLIUM_DRIVER" \\\n[[:space:]]*"FD_FORCE_KGSL=\$FD_FORCE_KGSL"; then|"GALLIUM_DRIVER=\$GALLIUM_DRIVER"; then|' "$ANLAND_SESSION"
    if grep -q 'FD_FORCE_KGSL' "$ANLAND_SESSION"; then
        die "anland-session 补丁未完全移除 FD_FORCE_KGSL，已中止。" \
            "The anland-session patch did not fully remove FD_FORCE_KGSL; aborting."
    fi
    bash -n "$ANLAND_SESSION" || die \
        "anland-session 补丁后语法错误，已中止。" \
        "anland-session has a syntax error after patching; aborting."
    log "anland-session 已改为 zink 默认值。" \
        "anland-session now defaults to zink."
}

fix_chrome_wrapper() {
    [[ -f "$CHROME_WRAPPER" ]] || {
        log "未找到 Chrome 包装器，跳过（仅 anland 构建会创建）。" \
            "No Chrome wrapper found; skipping (only Anland builds create one)."
        return 0
    }
    [[ -f "$CHROME_WRAPPER_BAK" ]] || cp -p -- "$CHROME_WRAPPER" "$CHROME_WRAPPER_BAK"
    # Mali 无 renderD128 节点（走 kbase /dev/mali0），也没有 Mali VA-API 驱动：
    # 移除 --render-node-override 与 VAAPI 开关，改为加载 manet 环境。
    cat > "$CHROME_WRAPPER" <<'EOF'
#!/bin/sh
set -eu

# Mali G2-Ultra NX (Xring O3) — mesa-manet PanVK/Zink 栈。
if [ -r /opt/mesa-manet/env.sh ]; then
    . /opt/mesa-manet/env.sh
fi

exec /opt/google/chrome/google-chrome \
    --ozone-platform=wayland \
    --ignore-gpu-blocklist \
    --use-gl=angle \
    --use-angle=vulkan \
    "$@"
EOF
    chmod 0755 "$CHROME_WRAPPER"
    log "Chrome 包装器已改为 manet 配置。" \
        "The Chrome wrapper now uses the manet configuration."
}

record_version() {
    local version="${RESOLVED_TAG}"
    [[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+:~_-]{0,63}$ ]] || return 0
    mkdir -p -- "$STATE_DIR" 2>/dev/null || return 0
    printf '%s\n' "$version" > "$STATE_FILE" 2>/dev/null && chmod 0644 "$STATE_FILE" || true
}

do_uninstall() {
    local dir json

    log "正在卸载 mesa-manet..." "Uninstalling mesa-manet..."
    apt-get remove -y mesa-manet-rock5b 2>/dev/null || \
        dpkg -r mesa-manet-rock5b 2>/dev/null || \
        log "警告: 未能移除包，继续清理。" \
            "Warning: could not remove the package; continuing cleanup."
    rm -f -- "$STATE_FILE"

    for dir in /usr/share/vulkan/icd.d /etc/vulkan/icd.d; do
        [[ -d "$dir" ]] || continue
        for json in "$dir"/*.json.disabled; do
            [[ -e "$json" ]] || continue
            mv -n -- "$json" "${json%.disabled}"
        done
    done

    if [[ -f "$ENV_FILE" ]]; then
        local tmp
        tmp="$(mktemp -t install-manet-o3-env.XXXXXXXX)"
        grep -vE '^(VK_DRIVER_FILES|VK_ICD_FILENAMES|MESA_LOADER_DRIVER_OVERRIDE|GALLIUM_DRIVER|PAN_USE_KRAID|RUSTICL_ENABLE)=' \
            "$ENV_FILE" > "$tmp" || true
        install -m 0644 "$tmp" "$ENV_FILE"
        rm -f -- "$tmp"
    fi

    [[ -f "$ANLAND_SESSION_BAK" ]] && install -m 0755 "$ANLAND_SESSION_BAK" "$ANLAND_SESSION" && rm -f -- "$ANLAND_SESSION_BAK"
    [[ -f "$CHROME_WRAPPER_BAK" ]] && install -m 0755 "$CHROME_WRAPPER_BAK" "$CHROME_WRAPPER" && rm -f -- "$CHROME_WRAPPER_BAK"
    command -v ldconfig >/dev/null 2>&1 && ldconfig || true
    log "卸载完成，已恢复安装前状态（若有备份）。" \
        "Uninstall finished; the pre-install state was restored from backups where available."
}

main() {
    detect_language
    parse_arguments "$@"
    require_root "$@"
    check_environment

    if [[ "$UNINSTALL" == true ]]; then
        do_uninstall
        exit 0
    fi

    if [[ "$VERSION_MODE" == latest ]]; then
        resolve_latest_release
    else
        resolve_pinned_release
    fi
    download_deb
    verify_deb
    install_deb
    disable_foreign_icds
    write_environment
    patch_anland_session
    fix_chrome_wrapper
    record_version

    log "安装完成。GPU 栈: manet PanVK/Zink; OpenCL: rusticl(zink,llvmpipe)。" \
        "Install complete. GPU stack: manet PanVK/Zink; OpenCL: rusticl(zink,llvmpipe)."
    log "提示: 该 Mali 驱动无 VA-API，浏览器视频为软解；GPU OpenCL 需要内核 render 节点（当前不可用）。" \
        "Note: this Mali driver has no VA-API (browser video decodes in software); GPU OpenCL needs a kernel render node (currently unavailable)."
}

main "$@"
