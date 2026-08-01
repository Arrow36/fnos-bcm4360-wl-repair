#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# fnOS BCM94360CS2 / BCM4360 (PCI ID 14e4:43a0) 一键安装与开机自愈脚本
#
# 默认执行 install：
#   sudo bash fnos-bcm4360-oneclick.sh
#
# 其他命令：
#   sudo bash fnos-bcm4360-oneclick.sh repair
#   sudo bash fnos-bcm4360-oneclick.sh repair --force
#   bash fnos-bcm4360-oneclick.sh status
#   sudo bash fnos-bcm4360-oneclick.sh install --deb /path/to/package.deb
#
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

readonly PROJECT_VERSION="1.0.0"
readonly PROJECT_URL="https://github.com/Arrow36/fnos-bcm4360-wl-repair"
readonly DRIVER_NAME="broadcom-sta"
readonly DRIVER_VERSION="6.30.223.271"
readonly MODULE_NAME="wl"
readonly TARGET_PCI_ID="14e4:43a0"

readonly PACKAGE_NAME="broadcom-sta-dkms_6.30.223.271-30_amd64.deb"
readonly PACKAGE_URL="https://deb.debian.org/debian/pool/non-free/b/broadcom-sta/${PACKAGE_NAME}"
readonly PACKAGE_SHA256="34917b5662cb03c453d28c834c229f20ace9fecd481c7bd9d8a789e1cc87fec5"

readonly STATE_DIR="/var/lib/fnos-bcm4360-wl"
readonly CACHE_DEB="${STATE_DIR}/${PACKAGE_NAME}"
readonly SOURCE_DIR="/usr/src/${DRIVER_NAME}-${DRIVER_VERSION}"
readonly INSTALLED_SCRIPT="/usr/local/sbin/fnos-bcm4360-wl"
readonly SERVICE_FILE="/etc/systemd/system/fnos-bcm4360-wl.service"
readonly MODPROBE_FILE="/etc/modprobe.d/fnos-bcm4360-wl.conf"
readonly MODULES_LOAD_FILE="/etc/modules-load.d/fnos-bcm4360-wl.conf"
readonly LOCK_FILE="/run/lock/fnos-bcm4360-wl.lock"

ACTION="install"
ACTION_SEEN=0
FORCE_REBUILD=0
BOOT_MODE=0
INSTALL_SERVICE=1
DEB_OVERRIDE=""
KERNEL_VERSION="$(uname -r)"
BUILD_LOG="/var/lib/dkms/${DRIVER_NAME}/${DRIVER_VERSION}/build/make.log"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "错误：$*"
    exit 1
}

on_error() {
    local rc=$?
    local line="${1:-未知}"
    set +e
    log "失败：第 ${line} 行命令返回 ${rc}。"
    if [[ -f "$BUILD_LOG" ]]; then
        log "DKMS 编译日志末尾如下：${BUILD_LOG}"
        tail -n 80 "$BUILD_LOG"
    fi
    log "可运行以下命令再次诊断："
    log "  sudo ${INSTALLED_SCRIPT} status"
    log "  sudo ${INSTALLED_SCRIPT} repair --force"
    exit "$rc"
}
trap 'on_error "$LINENO"' ERR

usage() {
    cat <<'EOF'
用法：
  sudo bash fnos-bcm4360-oneclick.sh [install]
  sudo bash fnos-bcm4360-oneclick.sh repair [--force]
  bash fnos-bcm4360-oneclick.sh status

选项：
  install             首次安装/重新部署，并启用开机自愈（默认）
  repair              修复当前内核；正常时快速退出
  status              只检查，不改动系统
  --force             即使当前 wl 可用，也强制重编译
  --deb FILE          使用本地 Debian 驱动包，适合离线安装
  --no-service        只修复当前内核，不安装 systemd 自愈服务
  --boot              供 systemd 服务内部使用；不应手工使用
  -V, --version       显示版本
  -h, --help          显示本帮助
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            install|repair|status)
                (( ACTION_SEEN == 0 )) || die "只能指定一个操作。"
                ACTION="$1"
                ACTION_SEEN=1
                ;;
            --force)
                FORCE_REBUILD=1
                ;;
            --boot)
                BOOT_MODE=1
                ;;
            --no-service)
                INSTALL_SERVICE=0
                ;;
            --deb)
                shift
                (($#)) || die "--deb 后面需要一个文件路径。"
                DEB_OVERRIDE="$1"
                ;;
            -V|--version)
                printf 'fnos-bcm4360-wl %s\n' "$PROJECT_VERSION"
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "未知参数：$1（使用 --help 查看帮助）"
                ;;
        esac
        shift
    done
}

need_root() {
    (( EUID == 0 )) || die "此操作必须使用 root 权限，请在命令前加 sudo。"
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

acquire_lock() {
    need_command flock
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "已有另一个修复进程正在运行。"
}

check_architecture() {
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) die "此驱动包只适用于 x86_64/amd64，当前架构：$(uname -m)" ;;
    esac
}

hardware_present() {
    lspci -Dn 2>/dev/null | grep -qi "$TARGET_PCI_ID"
}

kernel_config_has_cfg80211() {
    local config
    for config in \
        "/boot/config-${KERNEL_VERSION}" \
        "/lib/modules/${KERNEL_VERSION}/build/.config"
    do
        if [[ -r "$config" ]] &&
           grep -qE '^CONFIG_CFG80211=(y|m)$' "$config"; then
            return 0
        fi
    done
    return 1
}

cfg80211_available() {
    modinfo -k "$KERNEL_VERSION" cfg80211 >/dev/null 2>&1 ||
        kernel_config_has_cfg80211
}

module_available() {
    modinfo -k "$KERNEL_VERSION" "$MODULE_NAME" >/dev/null 2>&1
}

cache_valid() {
    local file="$1"
    local actual
    [[ -f "$file" ]] || return 1
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [[ "$actual" == "$PACKAGE_SHA256" ]]
}

preflight() {
    need_command grep
    need_command lspci
    need_command modinfo
    need_command modprobe
    check_architecture

    hardware_present ||
        die "未找到目标网卡 ${TARGET_PCI_ID}（BCM4360），为避免误操作已停止。"

    cfg80211_available ||
        die "当前内核 ${KERNEL_VERSION} 没有可用的 cfg80211。"
}

build_preflight() {
    need_command awk
    need_command depmod
    need_command dkms
    need_command dpkg-deb
    need_command sha256sum

    [[ -e "/lib/modules/${KERNEL_VERSION}/build" ]] ||
        die "缺少当前内核头文件：/lib/modules/${KERNEL_VERSION}/build"
}

obtain_package() {
    local download_tmp
    mkdir -p "$STATE_DIR"

    if [[ -n "$DEB_OVERRIDE" ]]; then
        [[ -f "$DEB_OVERRIDE" ]] ||
            die "指定的本地驱动包不存在：${DEB_OVERRIDE}"
        cache_valid "$DEB_OVERRIDE" ||
            die "本地驱动包 SHA-256 不匹配；要求 ${PACKAGE_SHA256}"

        if [[ "$(readlink -f "$DEB_OVERRIDE")" != "$(readlink -f "$CACHE_DEB" 2>/dev/null || true)" ]]; then
            install -m 0644 "$DEB_OVERRIDE" "$CACHE_DEB"
        fi
        log "已校验并缓存本地驱动包。"
        return
    fi

    if cache_valid "$CACHE_DEB"; then
        log "使用已校验的本地缓存：${CACHE_DEB}"
        return
    fi

    if [[ -e "$CACHE_DEB" ]]; then
        mv "$CACHE_DEB" "${CACHE_DEB}.bad.$(date '+%Y%m%d-%H%M%S')"
        log "已隔离校验失败的旧缓存。"
    fi

    (( BOOT_MODE == 0 )) ||
        die "开机修复所需的本地驱动缓存不存在；请手工重新运行 install。"

    download_tmp="$(mktemp "${STATE_DIR}/.download.XXXXXX")"
    log "首次安装：从 Debian 官方镜像下载驱动包……"
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 3 --connect-timeout 20 \
            --output "$download_tmp" "$PACKAGE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=3 --timeout=20 --output-document="$download_tmp" \
            "$PACKAGE_URL"
    else
        die "缺少 curl 或 wget，无法下载驱动包。"
    fi

    cache_valid "$download_tmp" ||
        die "下载包的 SHA-256 校验失败，已拒绝安装。"
    chmod 0644 "$download_tmp"
    mv "$download_tmp" "$CACHE_DEB"
    log "驱动包下载及 SHA-256 校验完成。"
}

source_tree_valid() {
    local root="$1"
    local required
    for required in \
        "src/include/lib80211.h" \
        "src/include/typedefs.h" \
        "lib/wlc_hybrid.o_amd64" \
        "Makefile" \
        "dkms.conf"
    do
        [[ -f "${root}/${required}" ]] || return 1
    done
    return 0
}

validate_source_tree() {
    local root="$1"
    source_tree_valid "$root" ||
        die "驱动源码不完整：${root}"
}

restore_clean_source() {
    local extract_dir
    local reference_source
    local backup_source

    need_command dpkg-deb
    extract_dir="$(mktemp -d "${STATE_DIR}/extract.XXXXXX")"
    dpkg-deb -x "$CACHE_DEB" "$extract_dir"
    reference_source="${extract_dir}/usr/src/${DRIVER_NAME}-${DRIVER_VERSION}"
    validate_source_tree "$reference_source"

    if [[ -e "$SOURCE_DIR" || -L "$SOURCE_DIR" ]]; then
        backup_source="${STATE_DIR}/source-backup.$(date '+%Y%m%d-%H%M%S')"
        mv "$SOURCE_DIR" "$backup_source"
        log "原驱动源码已备份至：${backup_source}"
    fi

    cp -a "$reference_source" "$SOURCE_DIR"
    rm -rf -- "$extract_dir"
    validate_source_tree "$SOURCE_DIR"
    log "已恢复完整的 Debian ${DRIVER_VERSION}-30 驱动源码。"
}

write_module_config() {
    cat >"$MODPROBE_FILE" <<'EOF'
# Managed by fnos-bcm4360-wl. Do not blacklist b44 or ssb here:
# they may be used by a wired NIC and unloading them can break SSH.
blacklist b43
blacklist b43legacy
blacklist brcmsmac
blacklist brcmfmac
blacklist bcma
EOF
    printf '%s\n' "$MODULE_NAME" >"$MODULES_LOAD_FILE"
}

dkms_registered() {
    if [[ -e "/var/lib/dkms/${DRIVER_NAME}/${DRIVER_VERSION}/source" ]]; then
        return 0
    fi
    dkms status -m "$DRIVER_NAME" -v "$DRIVER_VERSION" 2>/dev/null |
        grep -q .
}

build_for_current_kernel() {
    restore_clean_source

    # 只清理当前内核的失败/旧构建，保留其他内核，方便回滚启动。
    dkms remove \
        -m "$DRIVER_NAME" \
        -v "$DRIVER_VERSION" \
        -k "$KERNEL_VERSION" \
        --force >/dev/null 2>&1 || true

    if ! dkms_registered; then
        log "向 DKMS 注册驱动源码。"
        dkms add -m "$DRIVER_NAME" -v "$DRIVER_VERSION"
    fi

    log "为内核 ${KERNEL_VERSION} 编译 wl（可能需要几分钟）……"
    dkms build \
        -m "$DRIVER_NAME" \
        -v "$DRIVER_VERSION" \
        -k "$KERNEL_VERSION"

    dkms install \
        -m "$DRIVER_NAME" \
        -v "$DRIVER_VERSION" \
        -k "$KERNEL_VERSION"

    depmod -a "$KERNEL_VERSION"
    module_available ||
        die "DKMS 已返回成功，但当前内核仍找不到 wl 模块。"
}

try_load_driver() {
    # 不卸载 b44、ssb 或已加载的 wl，避免不必要地中断有线网络/SSH。
    modprobe -r b43 b43legacy brcmsmac brcmfmac bcma \
        >/dev/null 2>&1 || true
    modprobe cfg80211 || return 1
    modprobe "$MODULE_NAME" || return 1
    grep -qE "^${MODULE_NAME}[[:space:]]" /proc/modules
}

load_driver() {
    if ! try_load_driver; then
        die "wl 模块文件存在，但加载失败。请检查 dmesg（常见原因是模块签名/Secure Boot）。"
    fi
}

show_summary() {
    printf '\n===== DKMS =====\n'
    dkms status -m "$DRIVER_NAME" -v "$DRIVER_VERSION" 2>/dev/null || true
    printf '\n===== BCM4360 PCI 驱动 =====\n'
    lspci -nnk -d "$TARGET_PCI_ID" 2>/dev/null || true
    printf '\n===== 网络接口 =====\n'
    ip -br link 2>/dev/null || true
}

repair_current_kernel() {
    preflight
    write_module_config

    if (( FORCE_REBUILD == 0 )) && module_available; then
        log "内核 ${KERNEL_VERSION} 已有 wl 模块，无需重编译。"
        if try_load_driver; then
            log "驱动自检通过。"
            return
        fi
        log "现有 wl 无法加载，尝试从本地缓存重新编译。"
    fi

    build_preflight
    obtain_package
    build_for_current_kernel
    load_driver
    log "内核 ${KERNEL_VERSION} 的 wl 驱动已安装并加载。"
}

install_boot_service() {
    if (( INSTALL_SERVICE == 0 )); then
        log "按 --no-service 要求跳过开机自愈服务。"
        return
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        log "警告：系统没有 systemctl，已完成驱动修复，但无法启用开机自愈。"
        return
    fi

    install -m 0755 "$0" "$INSTALLED_SCRIPT"
    cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Repair Broadcom BCM4360 wl driver for the running fnOS kernel
Documentation=${PROJECT_URL}
After=local-fs.target systemd-modules-load.service
Before=network-pre.target
Wants=network-pre.target
ConditionPathExists=${CACHE_DEB}

[Service]
Type=oneshot
ExecStart=${INSTALLED_SCRIPT} repair --boot
TimeoutStartSec=15min

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable fnos-bcm4360-wl.service >/dev/null
    log "已启用开机自愈服务：fnos-bcm4360-wl.service"
}

status_report() {
    local module_file=""

    printf 'fnOS BCM4360/wl %s 状态检查\n' "$PROJECT_VERSION"
    printf '%-18s %s\n' "当前内核:" "$KERNEL_VERSION"
    printf '%-18s %s\n' "机器架构:" "$(uname -m)"

    if command -v lspci >/dev/null 2>&1 && hardware_present; then
        printf '%-18s %s\n' "BCM4360 硬件:" "已找到 (${TARGET_PCI_ID})"
    else
        printf '%-18s %s\n' "BCM4360 硬件:" "未找到"
    fi

    if [[ -e "/lib/modules/${KERNEL_VERSION}/build" ]]; then
        printf '%-18s %s\n' "当前内核头文件:" "正常"
    else
        printf '%-18s %s\n' "当前内核头文件:" "缺失"
    fi

    if command -v modinfo >/dev/null 2>&1 && cfg80211_available; then
        printf '%-18s %s\n' "cfg80211:" "可用"
    else
        printf '%-18s %s\n' "cfg80211:" "不可用/无法确认"
    fi

    if command -v sha256sum >/dev/null 2>&1 && cache_valid "$CACHE_DEB"; then
        printf '%-18s %s\n' "离线驱动缓存:" "校验通过"
    else
        printf '%-18s %s\n' "离线驱动缓存:" "不存在或校验失败"
    fi

    if source_tree_valid "$SOURCE_DIR"; then
        printf '%-18s %s\n' "驱动源码:" "完整"
    else
        printf '%-18s %s\n' "驱动源码:" "缺失/不完整"
    fi

    if command -v modinfo >/dev/null 2>&1 && module_available; then
        module_file="$(modinfo -k "$KERNEL_VERSION" -F filename "$MODULE_NAME" 2>/dev/null || true)"
        printf '%-18s %s\n' "当前内核 wl:" "已安装 (${module_file})"
    else
        printf '%-18s %s\n' "当前内核 wl:" "未安装"
    fi

    if grep -qE "^${MODULE_NAME}[[:space:]]" /proc/modules; then
        printf '%-18s %s\n' "wl 加载状态:" "已加载"
    else
        printf '%-18s %s\n' "wl 加载状态:" "未加载"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        printf '%-18s %s\n' "开机自愈服务:" \
            "$(systemctl is-enabled fnos-bcm4360-wl.service 2>/dev/null || true)"
    fi

    if command -v dkms >/dev/null 2>&1; then
        printf '\n===== DKMS =====\n'
        dkms status -m "$DRIVER_NAME" -v "$DRIVER_VERSION" 2>/dev/null || true
    fi
    if command -v lspci >/dev/null 2>&1; then
        printf '\n===== PCI =====\n'
        lspci -nnk -d "$TARGET_PCI_ID" 2>/dev/null || true
    fi
    if command -v ip >/dev/null 2>&1; then
        printf '\n===== 网络接口 =====\n'
        ip -br link 2>/dev/null || true
    fi
}

main() {
    parse_args "$@"

    case "$ACTION" in
        status)
            status_report
            ;;
        install)
            need_root
            acquire_lock
            preflight
            build_preflight
            obtain_package
            install_boot_service
            FORCE_REBUILD=1
            repair_current_kernel
            show_summary
            log "全部完成。以后 fnOS 升级并重启时，服务会自动检查新内核。"
            ;;
        repair)
            need_root
            acquire_lock
            repair_current_kernel
            show_summary
            ;;
    esac
}

main "$@"
