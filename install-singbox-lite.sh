#!/bin/sh
# sing-box-lite: VLESS-Reality + Hysteria2 one-click installer and manager
SCRIPT_VERSION="3.3.0"
REMOTE_SCRIPT_URL="${REMOTE_SCRIPT_URL:-https://raw.githubusercontent.com/yanjie233/sing-box-lite/main/install-singbox-lite.sh}"
set -eu
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
REALITY_CONFIG_FILE="$CONFIG_DIR/config-reality.json"
HY2_CONFIG_FILE="$CONFIG_DIR/config-hysteria2.json"
CLIENT_DIR="$CONFIG_DIR/clients"
STATE_FILE="$CONFIG_DIR/state.env"
CERT_FILE="$CONFIG_DIR/server.crt"
KEY_FILE="$CONFIG_DIR/server.key"
SCRIPT_INSTALL_DIR="/usr/local/lib/sing-box-lite"
SCRIPT_INSTALL_PATH="$SCRIPT_INSTALL_DIR/install-singbox-lite.sh"
SHORTCUT_PATH="/usr/local/bin/singbox"
REALITY_SERVICE="sing-box-reality"
HY2_SERVICE="sing-box-hysteria2"
REALITY_SNI_ALT="bing.com"
DEFAULT_REALITY_SNI="academy.nvidia.com"
REALITY_SNI_FROM_ENV=0
if [ -n "${REALITY_SNI:-}" ]; then REALITY_SNI_FROM_ENV=1; fi
REALITY_SNI="${REALITY_SNI:-$DEFAULT_REALITY_SNI}"
HY2_SNI="${HY2_SNI:-www.example.com}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-firefox}"
NODE_REGION_CODE="${NODE_REGION_CODE:-}"
NODE_REGION_EMOJI="${NODE_REGION_EMOJI:-}"
DEFAULT_REALITY_PORT="55667"
DEFAULT_HY2_PORT="55668"
DEFAULT_ACME_HTTP_PORT="80"
INSTALL_MODE="both"
LISTEN_IPV6="0"
V6_ONLY="0"
REALITY_PORT=""
HY2_PORT=""
CERT_MODE="self"
CERT_DOMAIN=""
CERT_EMAIL=""
CERT_HTTP_PORT="${ACME_HTTP_PORT:-}"
HY2_HOST=""
PUBLIC_IP=""
IP_FAMILY=""
SING_BOX_PATH="/usr/local/bin/sing-box"

log() { printf '[sing-box-lite] %s\n' "$*" || true; }
warn() { printf '[sing-box-lite][WARN] %s\n' "$*" >&2 || true; }
die() {
    printf '[sing-box-lite][ERROR] %s\n' "$*" >&2
    if [ "${INSTALL_STARTED:-0}" = 1 ] && [ "${INSTALL_OK:-0}" != 1 ]; then
        printf '[sing-box-lite][ERROR] 本次操作未完成，%s 内可能残留部分文件；可重新运行本脚本，或执行完全卸载。\n' "$CONFIG_DIR" >&2
    fi
    exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
pause() { printf '\n按回车返回菜单...' >&2; read -r _pause || true; }
clear_screen() {
    [ -t 1 ] || return 0
    if have clear; then clear 2>/dev/null || printf '\n\n'; else printf '\n\n'; fi
}

# 终端配色：非 TTY 输出或设置 NO_COLOR 时自动关闭颜色
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _esc="$(printf '\033')"
    C_RESET="${_esc}[0m"; C_BOLD="${_esc}[1m"; C_DIM="${_esc}[2m"
    C_RED="${_esc}[1;31m"; C_GREEN="${_esc}[1;32m"; C_YELLOW="${_esc}[1;33m"
    C_BLUE="${_esc}[1;34m"; C_CYAN="${_esc}[1;36m"
    unset _esc
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

# 边框内宽度（终端列数），供 box_line / pad_right 对齐使用
BOX_INNER=46
BOX_HLINE=''
_box_i=0
while [ "$_box_i" -lt "$BOX_INNER" ]; do BOX_HLINE="${BOX_HLINE}─"; _box_i=$((_box_i + 1)); done
unset _box_i

# 计算终端显示宽度：中日韩/全角字符按 2 列，ANSI 颜色序列不计
display_width() {
    printf '%s' "$1" | LC_ALL=C awk '
        BEGIN { w = 0; for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
        {
            n = length($0); i = 1
            while (i <= n) {
                b = ord[substr($0, i, 1)] + 0
                if (b == 27) { while (i <= n && (ord[substr($0, i, 1)] + 0) != 109) i++; i++; continue }
                if (b < 128) { w += 1; i += 1 }
                else if (b < 224) { w += 1; i += 2 }
                else if (b < 240) { if (b >= 227) w += 2; else w += 1; i += 3 }
                else { w += 2; i += 4 }
            }
        }
        END { print w + 0 }'
}

# 按终端列宽补齐右侧空格：pad_right <文本> <目标宽度>
pad_right() {
    _text="$1"
    _target="${2:-0}"
    _width="$(display_width "$1")"
    _pad=$((_target - _width))
    if [ "$_pad" -gt 0 ]; then printf '%s%*s' "$_text" "$_pad" ''; else printf '%s' "$_text"; fi
}

box_top() { printf '%s┌%s┐%s\n' "$C_CYAN" "$BOX_HLINE" "$C_RESET"; }
box_mid() { printf '%s├%s┤%s\n' "$C_CYAN" "$BOX_HLINE" "$C_RESET"; }
box_bottom() { printf '%s└%s┘%s\n' "$C_CYAN" "$BOX_HLINE" "$C_RESET"; }
box_line() { printf '%s│%s│%s\n' "$C_CYAN" "$(pad_right "$1" "$BOX_INNER")" "$C_RESET"; }

# 原始状态 → 带颜色的中文标签
status_display() {
    case "$1" in
        active) printf '%s运行中%s' "$C_GREEN" "$C_RESET" ;;
        activating|reloading) printf '%s启动中%s' "$C_BLUE" "$C_RESET" ;;
        inactive|dead|stopped) printf '%s已停止%s' "$C_YELLOW" "$C_RESET" ;;
        failed) printf '%s异常%s' "$C_RED" "$C_RESET" ;;
        unknown) printf '%s未知%s' "$C_YELLOW" "$C_RESET" ;;
        未安装) printf '%s未安装%s' "$C_DIM" "$C_RESET" ;;
        *) printf '%s%s%s' "$C_YELLOW" "$1" "$C_RESET" ;;
    esac
}
service_state_label() {
    if service_exists "$1"; then status_display "$(service_status "$1")"; else status_display '未安装'; fi
}
print_ok() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*" || true; }
print_fail() { printf '%s[失败]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2 || true; }

download_file() {
    # IPv6-only 机器上 `curl -4` 会直接失败，先试 IPv4 再回退到默认协议族
    url="$1"; destination="$2"
    if have curl; then
        curl -4fsSL --max-time 60 "$url" -o "$destination" 2>/dev/null && return 0
        curl -fsSL --max-time 60 "$url" -o "$destination"
    elif have wget; then
        wget -q --timeout=60 -O "$destination" "$url"
    else return 1; fi
}


validate_domain() {
    domain="$1"
    case "$domain" in ''|*[!A-Za-z0-9.-]*|.*|*.|*..*) return 1 ;; esac
    return 0
}
validate_port() {
    port="$1"; label="$2"
    is_valid_port "$port" || die "$label 必须是 1-65535 的数字。"
}
is_valid_port() {
    case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
    [ "${#1}" -le 5 ] || return 1
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}


is_protocol_enabled() {
    case "$1" in
        reality) [ "$INSTALL_MODE" = both ] || [ "$INSTALL_MODE" = reality ] ;;
        hy2) [ "$INSTALL_MODE" = both ] || [ "$INSTALL_MODE" = hy2 ] ;;
        *) return 1 ;;
    esac
}

service_status() {
    service="$1"
    if have systemctl; then
        # systemctl is-active 即使失败也会输出状态（failed/inactive 等），不能用 || 再打印一次
        _st="$(systemctl is-active "$service" 2>/dev/null || true)"
        if [ -n "$_st" ]; then printf '%s' "$_st"; else printf 'unknown'; fi
    elif have rc-service; then
        if rc-service "$service" status >/dev/null 2>&1; then printf 'active'; else printf 'inactive'; fi
    else printf 'unknown'; fi
}
service_exists() {
    service="$1"
    if have systemctl; then [ -f "/etc/systemd/system/$service.service" ]
    elif have rc-service; then [ -x "/etc/init.d/$service" ]
    else return 1; fi
}
service_action() {
    service="$1"; action="$2"
    service_exists "$service" || { warn "未安装协议服务：$service"; return 1; }
    if have systemctl; then
        case "$action" in
            start|stop|restart) systemctl "$action" "$service" ;;
            enable) systemctl enable "$service" >/dev/null 2>&1 || true ;;
            disable) systemctl disable "$service" >/dev/null 2>&1 || true ;;
            *) return 1 ;;
        esac
    elif have rc-service; then
        case "$action" in
            start|stop|restart) rc-service "$service" "$action" ;;
            enable) rc-update add "$service" default >/dev/null 2>&1 || true ;;
            disable) rc-update del "$service" default >/dev/null 2>&1 || true ;;
            *) return 1 ;;
        esac
    else warn '未检测到 systemd 或 OpenRC。'; return 1; fi
}
status_row() {
    label="$1"; service="$2"; port="$3"; transport="$4"
    if service_exists "$service"; then status="$(service_status "$service")"; else status='未安装'; fi
    box_line "  $(pad_right "$label" 16)$(pad_right "$(status_display "$status")" 10)$(pad_right "$transport" 6)${port:-—}"
}
read_state_value() {
    key="$1"; [ -f "$STATE_FILE" ] || return 0
    sed -n "s/^${key}=//p" "$STATE_FILE" | head -n 1
}
# 从状态文件恢复安装参数（端口/模式/证书），用于状态展示、服务管理与升级
load_state() {
    [ -f "$STATE_FILE" ] || return 1
    _v="$(read_state_value INSTALL_MODE)"; if [ -n "$_v" ]; then INSTALL_MODE="$_v"; fi
    REALITY_PORT="$(read_state_value REALITY_PORT)"
    HY2_PORT="$(read_state_value HY2_PORT)"
    _v="$(read_state_value CERT_MODE)"; if [ -n "$_v" ]; then CERT_MODE="$_v"; fi
    CERT_DOMAIN="$(read_state_value CERT_DOMAIN)"
    CERT_HTTP_PORT="$(read_state_value CERT_HTTP_PORT)"
    _v="$(read_state_value HY2_SNI)"; if [ -n "$_v" ]; then HY2_SNI="$_v"; fi
    return 0
}
show_status_summary() {
    if [ ! -f "$STATE_FILE" ]; then
        printf '\n'; box_top
        box_line "  ${C_YELLOW}尚未安装${C_RESET}：可选择 1) 一键快捷安装 开始部署"
        box_bottom; printf '\n'
        return 0
    fi
    mode="$(read_state_value INSTALL_MODE)"; [ -n "$mode" ] || mode="$INSTALL_MODE"
    reality_port="$(read_state_value REALITY_PORT)"; hy2_port="$(read_state_value HY2_PORT)"
    listen_v6="$(read_state_value LISTEN_IPV6)"; v6only="$(read_state_value V6_ONLY)"
    if [ "$v6only" = 1 ]; then net='IPv6-only'
    elif [ "$listen_v6" = 1 ]; then net='双栈（监听 IPv6）'
    else net='IPv4'
    fi
    printf '\n'; box_top
    box_line "  ${C_GREEN}sing-box-lite${C_RESET} 状态    ${C_DIM}脚本 v${SCRIPT_VERSION}${C_RESET}"
    box_mid
    box_line "  安装模式：${mode}    网络：${net}"
    box_mid
    box_line "  $(pad_right '协议' 16)$(pad_right '状态' 10)$(pad_right '传输' 6)端口"
    status_row 'VLESS Reality' "$REALITY_SERVICE" "$reality_port" TCP
    status_row 'Hysteria2' "$HY2_SERVICE" "$hy2_port" UDP
    box_mid
    if have sing-box; then
        box_line "  ${C_DIM}sing-box $(sing-box version 2>/dev/null | awk 'NR==1{print $3}')${C_RESET}"
    else
        box_line "  ${C_DIM}sing-box 未安装${C_RESET}"
    fi
    box_bottom
    printf '\n'
    return 0
}
show_status() {
    [ "$(id -u)" -eq 0 ] || die '查询状态请使用 root 运行。'
    show_status_summary
    [ -f "$STATE_FILE" ] || return 0
    reality_port="$(read_state_value REALITY_PORT)"; hy2_port="$(read_state_value HY2_PORT)"
    ports=''
    [ -n "$reality_port" ] && ports="$reality_port"
    [ -n "$hy2_port" ] && ports="${ports:+$ports|}$hy2_port"
    if have ss && [ -n "$ports" ]; then
        printf '监听端口：\n'
        ss -lntup 2>/dev/null | grep -E "[:.](${ports})([^0-9]|$)" || printf '  未检测到监听，相关服务可能未运行。\n'
        printf '\n'
    fi
    printf '服务状态：\n'
    svc_printed=0
    for _svc in "$REALITY_SERVICE" "$HY2_SERVICE"; do
        if service_exists "$_svc"; then
            printf '  %s %s\n' "$(pad_right "$_svc" 24)" "$(status_display "$(service_status "$_svc")")"
            svc_printed=1
        fi
    done
    [ "$svc_printed" = 1 ] || printf '  暂无已安装的服务。\n'
    [ -f "$CONFIG_DIR/install-info.txt" ] && { printf '\n安装信息：\n'; sed -n '1,60p' "$CONFIG_DIR/install-info.txt"; }
    return 0
}

run_service_action() {
    action="$1"; service="$2"; name="$3"
    case "$action" in start) act='开启' ;; stop) act='关闭' ;; restart) act='重启' ;; *) act="$action" ;; esac
    if ! service_exists "$service"; then warn "${name} 服务未安装。"; return 1; fi
    if service_action "$service" "$action"; then
        print_ok "${name} ${act}成功"
    else
        print_fail "${name} ${act}失败"
        return 1
    fi
}
all_service_action() {
    rc=0
    if is_protocol_enabled reality; then
        if service_exists "$REALITY_SERVICE"; then run_service_action "$1" "$REALITY_SERVICE" 'Reality' || rc=1
        else warn 'Reality 服务未安装，已跳过。'; fi
    fi
    if is_protocol_enabled hy2; then
        if service_exists "$HY2_SERVICE"; then run_service_action "$1" "$HY2_SERVICE" 'Hysteria2' || rc=1
        else warn 'Hysteria2 服务未安装，已跳过。'; fi
    fi
    [ "$rc" -eq 0 ]
}
manage_services() {
    [ "$(id -u)" -eq 0 ] || { warn '管理服务请使用 root 运行。'; return 1; }
    if [ ! -f "$STATE_FILE" ]; then warn '尚未安装，请先执行安装。'; return 1; fi
    load_state || true
    while :; do
        clear_screen; show_status_summary
        printf '%s状态管理%s\n' "$C_BOLD" "$C_RESET"
        printf '  1) 开启 Reality       2) 关闭 Reality       3) 重启 Reality\n'
        printf '  4) 开启 Hysteria2     5) 关闭 Hysteria2     6) 重启 Hysteria2\n'
        printf '  7) 开启全部           8) 关闭全部           9) 重启全部\n'
        printf '  0) 返回上一级菜单\n'
        printf '请选择操作：' >&2
        read -r choice || return 0
        case "$choice" in
            1) run_service_action start "$REALITY_SERVICE" 'Reality' || true ;;
            2) run_service_action stop "$REALITY_SERVICE" 'Reality' || true ;;
            3) run_service_action restart "$REALITY_SERVICE" 'Reality' || true ;;
            4) run_service_action start "$HY2_SERVICE" 'Hysteria2' || true ;;
            5) run_service_action stop "$HY2_SERVICE" 'Hysteria2' || true ;;
            6) run_service_action restart "$HY2_SERVICE" 'Hysteria2' || true ;;
            7) all_service_action start || true ;;
            8) all_service_action stop || true ;;
            9) all_service_action restart || true ;;
            0) return 0 ;;
            *) warn '无效选项。' ;;
        esac
        pause
    done
}


view_nodes() {
    [ "$(id -u)" -eq 0 ] || { warn '查看节点请使用 root 运行。'; return 1; }
    [ -f "$CLIENT_DIR/links.txt" ] || { warn '未找到节点信息，请先安装。'; return 1; }
    printf '\n%s==== 节点信息与导入链接 ====%s\n' "$C_CYAN" "$C_RESET"
    cat "$CLIENT_DIR/links.txt"
    printf '\n%s客户端文件目录：%s%s\n' "$C_DIM" "$CLIENT_DIR" "$C_RESET"
    return 0
}


remove_service_files() {
    if have systemctl; then
        systemctl disable --now "$REALITY_SERVICE" "$HY2_SERVICE" sing-box >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/$REALITY_SERVICE.service" "/etc/systemd/system/$HY2_SERVICE.service" /etc/systemd/system/sing-box.service
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if have rc-service; then
        rc-service "$REALITY_SERVICE" stop >/dev/null 2>&1 || true
        rc-service "$HY2_SERVICE" stop >/dev/null 2>&1 || true
        rc-update del "$REALITY_SERVICE" default >/dev/null 2>&1 || true
        rc-update del "$HY2_SERVICE" default >/dev/null 2>&1 || true
        rm -f "/etc/init.d/$REALITY_SERVICE" "/etc/init.d/$HY2_SERVICE" /etc/init.d/sing-box
    fi
}
uninstall_singbox() {
    [ "$(id -u)" -eq 0 ] || die '卸载请使用 root 运行。'
    printf '此操作将停止并删除两个协议服务、配置、证书、节点信息、快捷命令和本地 sing-box。\n输入 yes 确认：' >&2
    read -r confirm || true
    [ "$confirm" = yes ] || { log '已取消卸载。'; return 0; }
    INSTALL_STARTED=0; INSTALL_OK=0
    remove_service_files
    remove_acme_renewal_cron

    if [ -x /usr/local/bin/sing-box ]; then rm -f /usr/local/bin/sing-box
    elif [ -x /usr/bin/sing-box ] && [ -r /etc/os-release ]; then
        # Remove package-managed binaries through the package manager.
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
            alpine) apk del sing-box >/dev/null 2>&1 || warn '未能通过 apk 删除 sing-box。' ;;
            debian|ubuntu|linuxmint|raspbian)
                export DEBIAN_FRONTEND=noninteractive
                apt-get remove -y -qq sing-box >/dev/null 2>&1 || warn '未能通过 apt 删除 sing-box。' ;;
            alinux|alibabacloudlinux|centos|rhel|rocky|almalinux|fedora)
                if have dnf; then dnf remove -y sing-box >/dev/null 2>&1 || true; elif have yum; then yum remove -y sing-box >/dev/null 2>&1 || true; fi ;;
            *) warn '检测到 /usr/bin/sing-box，但无法判断包管理器；请手动卸载。' ;;
        esac
    fi
    rm -rf "$CONFIG_DIR" /var/lib/sing-box "$SCRIPT_INSTALL_DIR" "$SHORTCUT_PATH" /usr/local/bin/singbox-lite /var/log/sing-box-lite-acme.log
    log '完全卸载完成；未删除 curl、wget、openssl、tar 等系统依赖。'
}

install_base_packages() {
    case "$OS_ID" in
        alpine)
            if have apk; then apk add --no-cache ca-certificates curl openssl tar >/dev/null || warn 'Alpine 依赖安装失败。'; fi
            update-ca-certificates >/dev/null 2>&1 || true ;;
        debian|ubuntu|linuxmint|raspbian)
            if have apt-get; then
                export DEBIAN_FRONTEND=noninteractive
                (apt-get update -qq && apt-get install -y -qq ca-certificates curl openssl tar >/dev/null) || warn 'Debian 依赖安装失败。'
                rm -rf /var/lib/apt/lists/*
            fi ;;
        *)
            if have dnf; then dnf install -y ca-certificates curl openssl tar >/dev/null || true
            elif have yum; then yum install -y ca-certificates curl openssl tar >/dev/null || true; fi ;;
    esac
    have openssl || die '缺少 openssl，无法生成凭据和证书。'
    if ! have curl && ! have wget; then die '缺少 curl 或 wget，无法下载文件。'; fi
    have tar || die '缺少 tar，无法解压 sing-box。'
}
install_sing_box_from_github() {
    log '从 GitHub Releases 下载 sing-box。'
    release_json="$(mktemp)"
    download_file 'https://api.github.com/repos/SagerNet/sing-box/releases/latest' "$release_json" || { rm -f "$release_json"; die '无法访问 GitHub Releases。'; }
    tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" | head -n 1)"
    rm -f "$release_json"; [ -n "$tag" ] || die '无法获取 sing-box 版本。'
    version="${tag#v}"
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; armv7l|armv7) arch=armv7 ;;
        armv6l) arch=armv6 ;; armv5l) arch=armv5 ;; i386|i686) arch=386 ;; ppc64le) arch=ppc64le ;;
        riscv64) arch=riscv64 ;; s390x) arch=s390x ;; *) die "不支持当前架构：$(uname -m)" ;;
    esac
    libc=glibc
    if [ "$OS_ID" = alpine ] || (have ldd && ldd --version 2>&1 | grep -qi musl); then libc=musl; fi
    asset="sing-box-${version}-linux-${arch}-${libc}.tar.gz"
    archive="$(mktemp)"
    if ! download_file "https://github.com/SagerNet/sing-box/releases/download/${tag}/${asset}" "$archive"; then
        asset="sing-box-${version}-linux-${arch}.tar.gz"
        download_file "https://github.com/SagerNet/sing-box/releases/download/${tag}/${asset}" "$archive" || { rm -f "$archive"; die '无法下载 sing-box 发布包。'; }
    fi
    extract_dir="$(mktemp -d)"
    tar -xzf "$archive" -C "$extract_dir" || { rm -f "$archive"; rm -rf "$extract_dir"; die 'sing-box 发布包解压失败。'; }
    rm -f "$archive"
    binary="$(find "$extract_dir" -type f -name sing-box -perm -u+x | head -n 1)"
    [ -n "$binary" ] || binary="$(find "$extract_dir" -type f -name sing-box | head -n 1)"
    [ -n "$binary" ] || { rm -rf "$extract_dir"; die '发布包中未找到 sing-box。'; }
    mkdir -p /usr/local/bin; cp "$binary" /usr/local/bin/sing-box; chmod 755 /usr/local/bin/sing-box
    rm -rf "$extract_dir"
}
install_sing_box() {
    force="${FORCE_SING_BOX_UPDATE:-0}"
    if have sing-box && [ "$force" != 1 ]; then log "检测到已有 sing-box：$(sing-box version | head -n 1)"; return 0; fi
    package_ok=0
    case "$OS_ID" in
        alpine) if have apk && apk add --no-cache sing-box >/dev/null 2>&1; then package_ok=1; fi ;;
        debian|ubuntu|linuxmint|raspbian|alinux|alibabacloudlinux|centos|rhel|rocky|almalinux|fedora)
            tmp_install="$(mktemp)"
            if download_file 'https://sing-box.app/install.sh' "$tmp_install" && sh "$tmp_install"; then package_ok=1; fi
            rm -f "$tmp_install" ;;
    esac
    if [ "$package_ok" -ne 1 ] || ! have sing-box; then install_sing_box_from_github; fi
    have sing-box || die 'sing-box 安装后仍未找到可执行文件。'
}
upgrade_sing_box() {
    [ "$(id -u)" -eq 0 ] || die '升级 sing-box 请使用 root 运行。'
    # 按已安装模式恢复状态，避免升级时错误地重启未安装的协议服务
    load_state || warn '未找到安装状态文件，按全部协议处理。'
    install_base_packages; FORCE_SING_BOX_UPDATE=1 install_sing_box
    if is_protocol_enabled reality && service_exists "$REALITY_SERVICE"; then
        service_action "$REALITY_SERVICE" restart || warn 'Reality 服务重启失败。'
    fi
    if is_protocol_enabled hy2 && service_exists "$HY2_SERVICE"; then
        service_action "$HY2_SERVICE" restart || warn 'Hysteria2 服务重启失败。'
    fi
    log "sing-box 已更新：$(sing-box version | head -n 1)"
}


get_local_ipv4() {
    # 本机网络接口上用于访问公网的 IPv4 地址（无则空，可能是 WARP/NAT/LXD 环境）
    local_ip=''
    if have ip; then
        local_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    fi
    if [ -z "$local_ip" ] && have hostname; then local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
    printf '%s' "$local_ip"
}
is_private_ipv4() {
    ip="$1"
    case "$ip" in
        0.*|10.*|127.*|169.254.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|100.6[4-9].*|100.7[0-9].*|100.8[0-9].*|100.9[0-9].*|100.1[01][0-9].*|100.12[0-7].*|192.0.0.*|198.18.*|198.19.*) return 0 ;;
        *) return 1 ;;
    esac
}
is_private_ipv6() {
    # 过滤 ULA、链路本地、组播、文档地址和未指定地址。LXD 常见的 fd00::/8 必须排除。
    ip6="$1"
    ip6="$(printf '%s' "$ip6" | sed 's#/.*##; s#%.*$##' | tr '[:upper:]' '[:lower:]')"
    case "$ip6" in
        ''|'::'|'::1'|fc*:*|fd*:*|fe8*:*|fe9*:*|fea*:*|feb*:*|ff*:*|2001:db8:*|2001:10:*|::ffff:*) return 0 ;;
        *) return 1 ;;
    esac
}
has_native_ipv4() {
    # 本机是否拥有属于自己的公网 IPv4（可在该地址上监听）
    v4="$(get_local_ipv4)"
    [ -n "$v4" ] || return 1
    is_private_ipv4 "$v4" && return 1
    return 0
}
get_external_ipv4() {
    # 外部可见的 IPv4 出口（可能是本机公网 IP、NAT 端口转发入口，或 WARP 共享出口）
    ext=''
    if have curl; then
        ext="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ext" ] || ext="$(curl -4fsS --max-time 5 https://ifconfig.me/ip 2>/dev/null || true)"
    elif have wget; then
        ext="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ext" ] || ext="$(wget -qO- --timeout=5 https://ifconfig.me/ip 2>/dev/null || true)"
    fi
    printf '%s' "$ext"
}
is_warp_v4_egress() {
    # 判断是否存在 WARP 风格的 v4 出口：本机无公网 IPv4，但 curl -4 有出口
    has_native_ipv4 && return 1
    ext="$(get_external_ipv4)"
    [ -n "$ext" ] || return 1
    is_private_ipv4 "$ext" && return 1
    # 有 WireGuard 接口（wgcf/wg*）进一步佐证是 WARP
    if have wg && wg show interfaces 2>/dev/null | grep -qE 'wgcf|wg[0-9]+'; then return 0; fi
    # 没有 wg 佐证时也算“非本机 v4 出口”（可能 WARP 或无公网 v4 的 NAT）
    return 0
}
get_public_ip() {
    case "$IP_FAMILY" in
        6) get_public_ipv6 ;;
        4)
            v4="$(get_local_ipv4)"
            if [ -n "$v4" ] && ! is_private_ipv4 "$v4"; then printf '%s' "$v4"; else get_external_ipv4; fi
            ;;
        *)
            v4="$(get_local_ipv4)"
            if [ -n "$v4" ] && ! is_private_ipv4 "$v4"; then printf '%s' "$v4"; else get_public_ipv6; fi
            ;;
    esac
}
prompt_ip_family() {
    # 只把真正可路由的地址当作节点地址；LXD 的 fd00::/8 等地址不能用于公网节点。
    detect_ipv6_support

    if [ -n "$PUBLIC_IP" ]; then
        case "$PUBLIC_IP" in
            *:*)
                is_private_ipv6 "$PUBLIC_IP" && die "PUBLIC_IP 不是公网 IPv6：$PUBLIC_IP"
                IP_FAMILY=6; V6_ONLY=1; LISTEN_IPV6=1
                ;;
            *)
                is_private_ipv4 "$PUBLIC_IP" && die "PUBLIC_IP 不是公网 IPv4：$PUBLIC_IP"
                IP_FAMILY=4; V6_ONLY=0; LISTEN_IPV6=0
                ;;
        esac
        return 0
    fi

    local_v4="$(get_local_ipv4)"
    public_v4=''
    if [ -n "$local_v4" ] && ! is_private_ipv4 "$local_v4"; then
        public_v4="$local_v4"
    else
        external_v4="$(get_external_ipv4)"
        if [ -n "$external_v4" ] && ! is_private_ipv4 "$external_v4"; then public_v4="$external_v4"; fi
    fi
    public_v6="$(get_public_ipv6)"

    if [ -n "$public_v4" ] && [ -n "$public_v6" ]; then
        native_v4=0
        if has_native_ipv4; then native_v4=1; fi
        if [ "$native_v4" = 1 ]; then
            default_choice=1
            printf '\n检测到可用 IPv4 和公网 IPv6，请选择节点地址：\n  1) IPv4（默认）\n  2) IPv6\n请选择：' >&2
        else
            default_choice=2
            printf '\n检测到 IPv4 出口和公网 IPv6，请选择节点地址：\n  1) IPv4（需要端口转发）\n  2) IPv6（默认）\n请选择：' >&2
        fi
        while :; do
            read -r ip_choice || ip_choice=''
            [ -n "$ip_choice" ] || ip_choice="$default_choice"
            case "$ip_choice" in
                1)
                    PUBLIC_IP="$public_v4"; IP_FAMILY=4; V6_ONLY=0; LISTEN_IPV6=0
                    if [ "$native_v4" = 0 ]; then
                        warn '当前 IPv4 不是本机网卡地址，可能是 WARP/NAT/LXD 共享出口；选择 IPv4 前请确认端口转发。'
                    fi
                    break
                    ;;
                2)
                    PUBLIC_IP="$public_v6"; IP_FAMILY=6; V6_ONLY=1; LISTEN_IPV6=1
                    break
                    ;;
                *) warn '无效选项，请输入 1 或 2。' ;;
            esac
        done
    elif [ -n "$public_v4" ]; then
        PUBLIC_IP="$public_v4"; IP_FAMILY=4; V6_ONLY=0; LISTEN_IPV6=0
        if ! has_native_ipv4; then
            warn '检测到 IPv4 出口但不是本机网卡地址，可能需要额外端口转发。'
        fi
    elif [ -n "$public_v6" ]; then
        PUBLIC_IP="$public_v6"; IP_FAMILY=6; V6_ONLY=1; LISTEN_IPV6=1
        log '仅检测到公网 IPv6，将按 IPv6-only 处理。'
    else
        if [ "$HAS_IPV6" = 1 ]; then
            warn '检测到 IPv6，但地址属于内网/保留范围（例如 fd00::/8），不会生成 IPv6 节点。'
        fi
        IP_FAMILY=''
        V6_ONLY=0; LISTEN_IPV6=0
    fi

    if [ "$IP_FAMILY" = 6 ]; then
        is_warp_v4_egress && warn '检测到 WARP 风格的 IPv4 出口：当前节点使用 IPv6，客户端请勿使用该 v4 出口地址。' || true
    fi
    return 0
}
detect_ipv6_support() {
    # 检测本机是否存在 IPv6 地址；公网地址另由 get_public_ipv6 过滤。
    if have ip; then
        ip -6 addr show scope global 2>/dev/null | grep -q 'inet6' && { HAS_IPV6=1; return 0; }
    fi
    if [ -d /proc/net/if_inet6 ]; then
        awk '{ if ($1 !~ /^fe80/) found=1 } END { exit found ? 0 : 1 }' /proc/net/if_inet6 2>/dev/null && { HAS_IPV6=1; return 0; }
    fi
    HAS_IPV6=0
}
get_public_ipv6() {
    # 获取本机真正可路由的 IPv6；不要把 LXD 的 fdxx::、fe80:: 等地址写入节点。
    ip6=''
    if have ip; then
        ip6="$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
        if [ -n "$ip6" ] && ! is_private_ipv6 "$ip6"; then printf '%s' "$ip6"; return; fi
        for candidate in $(ip -6 addr show scope global 2>/dev/null | awk '$1=="inet6" {sub("/.*", "", $2); print $2}'); do
            if ! is_private_ipv6 "$candidate"; then printf '%s' "$candidate"; return; fi
        done
    fi
    if [ -r /proc/net/if_inet6 ]; then
        # 按 if_inet6 拼接，跳过 fe80:: 和其他保留地址。
        for hex in $(awk '$1 !~ /^fe80/ {print $1}' /proc/net/if_inet6 2>/dev/null); do
            candidate="$(printf '%s' "$hex" | sed 's/..../&:/g; s/:$//')"
            if ! is_private_ipv6 "$candidate"; then printf '%s' "$candidate"; return; fi
        done
    fi
    printf '%s' ''
}
make_uuid() {
    if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid; return; fi
    h="$(openssl rand -hex 16)"
    printf '%s-%s-%s-%s-%s\n' "$(printf '%s' "$h" | cut -c1-8)" "$(printf '%s' "$h" | cut -c9-12)" "4$(printf '%s' "$h" | cut -c14-16)" "8$(printf '%s' "$h" | cut -c18-20)" "$(printf '%s' "$h" | cut -c21-32)"
}
make_self_signed_cert() {
    log '生成 Hysteria2 ECDSA 自签名证书。'
    openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_FILE"
    openssl req -new -x509 -sha256 -key "$KEY_FILE" -out "$CERT_FILE" -days 3650 -subj "/CN=$HY2_SNI" >/dev/null 2>&1
    chmod 600 "$KEY_FILE"; chmod 644 "$CERT_FILE"
}
install_acme_sh() {
    ACME_HOME="${ACME_HOME:-/root/.acme.sh}"
    if [ -x "$ACME_HOME/acme.sh" ]; then return 0; fi
    tmp_acme="$(mktemp)"
    download_file 'https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh' "$tmp_acme" || { rm -f "$tmp_acme"; die '无法下载 acme.sh。'; }
    if [ -n "$CERT_EMAIL" ]; then sh "$tmp_acme" --install --home "$ACME_HOME" --no-cron --accountemail "$CERT_EMAIL"; else sh "$tmp_acme" --install --home "$ACME_HOME" --no-cron; fi
    rm -f "$tmp_acme"
    [ -x "$ACME_HOME/acme.sh" ] || die 'acme.sh 安装后未找到可执行文件。'
}
ACME_CRON_MARKER='# sing-box-lite-acme-renewal'
install_acme_renewal_cron() {
    # acme.sh 安装时使用了 --no-cron，这里补一条每日续期任务，避免 90 天后证书过期
    ACME_HOME="${ACME_HOME:-/root/.acme.sh}"
    if ! have crontab; then
        warn '未找到 crontab，无法安装证书自动续期任务；证书约 90 天过期，请手动执行 acme.sh --cron 续期。'
        return 0
    fi
    renew_log="/var/log/sing-box-lite-acme.log"
    remove_acme_renewal_cron
    cron_line="17 3 * * * L=$renew_log; [ -f \$L ] && [ \$(wc -c < \$L) -gt 1048576 ] && : > \$L; $ACME_HOME/acme.sh --home $ACME_HOME --cron >> \$L 2>&1 $ACME_CRON_MARKER"
    tmp_cron="$(mktemp)"
    { crontab -l 2>/dev/null | grep -vF "$ACME_CRON_MARKER" || true; printf '%s\n' "$cron_line"; } > "$tmp_cron"
    if crontab "$tmp_cron" 2>/dev/null; then
        log "已添加证书自动续期任务（每日 03:17），日志：$renew_log"
        log '请确认 cron/crond 服务正在运行，否则证书不会自动续期。'
    else
        warn '写入 crontab 失败，证书不会自动续期；请手动添加 acme.sh --cron 任务。'
    fi
    rm -f "$tmp_cron"
    return 0
}
remove_acme_renewal_cron() {
    have crontab || return 0
    current_cron="$(crontab -l 2>/dev/null || true)"
    case "$current_cron" in *"$ACME_CRON_MARKER"*) ;; *) return 0 ;; esac
    tmp_cron="$(mktemp)"
    printf '%s\n' "$current_cron" | grep -vF "$ACME_CRON_MARKER" > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
    return 0
}
issue_acme_certificate() {
    [ "$CERT_MODE" = domain ] || [ "$CERT_MODE" = ip ] || return 0
    install_acme_sh
    acme="${ACME_HOME:-/root/.acme.sh}/acme.sh"
    validate_port "$CERT_HTTP_PORT" '证书验证端口'
    hy2_was_running=0
    if service_exists "$HY2_SERVICE" && [ "$(service_status "$HY2_SERVICE")" = active ]; then
        hy2_was_running=1
        service_action "$HY2_SERVICE" stop || true
    fi
    reload_cmd="systemctl restart $HY2_SERVICE 2>/dev/null || rc-service $HY2_SERVICE restart 2>/dev/null || true"
    log "申请 $CERT_MODE 证书，验证端口：$CERT_HTTP_PORT"
    if [ "$CERT_MODE" = domain ]; then
        validate_domain "$CERT_DOMAIN" || die "证书域名格式无效：$CERT_DOMAIN"
        listen_v6_flag=''
        [ "$V6_ONLY" = 1 ] && listen_v6_flag='--listen-v6'
        "$acme" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        "$acme" --issue --standalone -d "$CERT_DOMAIN" --httpport "$CERT_HTTP_PORT" $listen_v6_flag || die '域名证书申请失败。请确认域名解析、验证端口可达且无其他程序占用。'
        "$acme" --install-cert -d "$CERT_DOMAIN" --fullchain-file "$CERT_FILE" --key-file "$KEY_FILE" --reloadcmd "$reload_cmd" || die '域名证书部署失败。'
        HY2_SNI="$CERT_DOMAIN"; HY2_HOST="$CERT_DOMAIN"
    else
        ip_flag='--ip'; [ "$V6_ONLY" = 1 ] && ip_flag='--ipv6 --ip'
        "$acme" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        "$acme" --issue --standalone $ip_flag "$PUBLIC_IP" --httpport "$CERT_HTTP_PORT" || die 'IP 证书申请失败。请确认当前 acme.sh/CA 支持 IP 证书，且公网 IP 与验证端口可达。'
        "$acme" --install-cert -d "$PUBLIC_IP" --fullchain-file "$CERT_FILE" --key-file "$KEY_FILE" --reloadcmd "$reload_cmd" || die 'IP 证书部署失败。'
        HY2_SNI="$PUBLIC_IP"; HY2_HOST="$PUBLIC_IP"
    fi
    chmod 600 "$KEY_FILE"; chmod 644 "$CERT_FILE"
    install_acme_renewal_cron
    if [ "$hy2_was_running" = 1 ]; then service_action "$HY2_SERVICE" start || true; fi
    log "证书已部署到：$CERT_FILE / $KEY_FILE"
}

backup_file() {
    file="$1"; [ -f "$file" ] || return 0
    backup="$file.bak.$(date +%Y%m%d-%H%M%S)"; cp -p "$file" "$backup"; warn "已备份旧文件：$backup"
}

get_listen_addr() {
    if [ "$V6_ONLY" = 1 ] || [ "$LISTEN_IPV6" = 1 ]; then printf '%s' '::'; else printf '%s' '0.0.0.0'; fi
}
write_reality_inbound() {
    cat <<EOF
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "$(get_listen_addr)",
      "listen_port": $REALITY_PORT,
      "users": [{"uuid": "$UUID", "flow": "xtls-rprx-vision"}],
      "tls": {"enabled": true, "server_name": "$REALITY_SNI", "reality": {
        "enabled": true, "handshake": {"server": "$REALITY_SNI", "server_port": 443},
        "private_key": "$REALITY_PRIVATE_KEY", "short_id": [""]
      }}
    }
EOF
}
write_hy2_inbound() {
    cat <<EOF
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "$(get_listen_addr)",
      "listen_port": $HY2_PORT,
      "users": [{"name": "default", "password": "$HY2_PASSWORD"}],
      "tls": {"enabled": true, "server_name": "$HY2_SNI", "certificate_path": "$CERT_FILE", "key_path": "$KEY_FILE"}
    }
EOF
}
write_config() {
    destination="$1"; force="${2:-all}"
    enable_reality=0; enable_hy2=0
    # force: reality / hy2 / all（默认 all，按 INSTALL_MODE 决定启用哪些入站）
    if [ "$force" = reality ] || [ "$force" = all ]; then
        if is_protocol_enabled reality; then enable_reality=1; fi
    fi
    if [ "$force" = hy2 ] || [ "$force" = all ]; then
        if is_protocol_enabled hy2; then enable_hy2=1; fi
    fi
    {
        cat <<EOF
{
  "log": {"level": "warn", "timestamp": true},
  "inbounds": [
EOF
        first=1
        if [ "$enable_reality" -eq 1 ]; then write_reality_inbound; first=0; fi
        if [ "$enable_hy2" -eq 1 ]; then [ "$first" -eq 1 ] || printf ',\n'; write_hy2_inbound; fi
        cat <<EOF
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"}
}
EOF
    } > "$destination"
    chmod 600 "$destination"
}
write_client_files() {
    URL_HOST="$PUBLIC_IP"; case "$URL_HOST" in *:*) URL_HOST="[$URL_HOST]" ;; esac
    HOST_ADDR="${HY2_HOST:-$PUBLIC_IP}"; case "$HOST_ADDR" in *:*) HOST_ADDR="[$HOST_ADDR]" ;; esac
    rm -f "$CLIENT_DIR/reality.json" "$CLIENT_DIR/hysteria2.json" "$CLIENT_DIR/links.txt"
    : > "$CLIENT_DIR/links.txt"
    node_name="${NODE_REGION_EMOJI}${NODE_REGION_CODE}"
    [ -n "$node_name" ] || node_name="$PUBLIC_IP"
    if is_protocol_enabled reality; then
        cat > "$CLIENT_DIR/reality.json" <<EOF
{
  "log": {"level": "warn"},
  "outbounds": [{"type": "vless", "tag": "proxy", "server": "$PUBLIC_IP", "server_port": $REALITY_PORT, "uuid": "$UUID", "flow": "xtls-rprx-vision", "tls": {"enabled": true, "server_name": "$REALITY_SNI", "utls": {"enabled": true, "fingerprint": "$REALITY_FINGERPRINT"}, "reality": {"enabled": true, "public_key": "$REALITY_PUBLIC_KEY", "short_id": ""}}}]
}
EOF
        REALITY_LINK="vless://${UUID}@${URL_HOST}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&type=tcp&headerType=none#${node_name}-Vless"
        printf '# %s-Vless\n%s\n\n' "$node_name" "$REALITY_LINK" >> "$CLIENT_DIR/links.txt"
        chmod 600 "$CLIENT_DIR/reality.json"
    fi
    if is_protocol_enabled hy2; then
        insecure=0; query="sni=${HY2_SNI}"; note='受信证书，客户端 insecure=0'
        if [ "$CERT_MODE" = self ]; then insecure=1; query="insecure=1&sni=${HY2_SNI}"; note='自签名证书，客户端必须允许 insecure=1'; fi
        cat > "$CLIENT_DIR/hysteria2.json" <<EOF
{
  "log": {"level": "warn"},
  "outbounds": [{"type": "hysteria2", "tag": "proxy", "server": "$HOST_ADDR", "server_port": $HY2_PORT, "password": "$HY2_PASSWORD", "tls": {"enabled": true, "server_name": "$HY2_SNI", "insecure": $insecure}}]
}
EOF
        HY2_LINK="hysteria2://${HY2_PASSWORD}@${HOST_ADDR}:${HY2_PORT}/?${query}#${node_name}-Hy2"
        printf '# %s-Hy2（%s）\n%s\n' "$node_name" "$note" "$HY2_LINK" >> "$CLIENT_DIR/links.txt"
        chmod 600 "$CLIENT_DIR/hysteria2.json"
    fi
    chmod 600 "$CLIENT_DIR/links.txt"
}

write_systemd_unit() {
    service="$1"; config="$2"; description="$3"
    cat > "/etc/systemd/system/$service.service" <<EOF
[Unit]
Description=$description
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SING_BOX_PATH run -c $config
Restart=on-failure
RestartSec=2
LimitNOFILE=65535
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
WorkingDirectory=/var/lib/sing-box

[Install]
WantedBy=multi-user.target
EOF
}
write_openrc_service() {
    service="$1"; config="$2"
    cat > "/etc/init.d/$service" <<EOF
#!/sbin/openrc-run
name="$service"
command="$SING_BOX_PATH"
command_args="run -c $config"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/$service.log"
error_log="/var/log/$service.err"

depend() { need net; after firewall; }
EOF
    chmod +x "/etc/init.d/$service"
}
enabled_services() {
    _svcs=''
    if is_protocol_enabled reality; then _svcs="$REALITY_SERVICE"; fi
    if is_protocol_enabled hy2; then _svcs="${_svcs:+$_svcs }$HY2_SERVICE"; fi
    printf '%s' "$_svcs"
}
start_service_quiet() {
    # 启动失败只提示不中断安装，配置已通过 sing-box check 校验
    service="$1"; config="$2"; manager="$3"
    if [ "$manager" = systemd ]; then
        systemctl enable "$service" >/dev/null 2>&1 || warn "无法设置 $service 开机自启。"
        systemctl restart "$service" || warn "启动 $service 失败，请检查配置 $config 与 journalctl -u $service。"
    else
        rc-update add "$service" default >/dev/null 2>&1 || true
        rc-service "$service" restart || rc-service "$service" start || warn "启动 $service 失败，请查看 /var/log/$service.err。"
    fi
    return 0
}
write_services() {
    mkdir -p /var/lib/sing-box
    svcs="$(enabled_services)"
    if have systemctl; then
        systemctl disable --now sing-box "$REALITY_SERVICE" "$HY2_SERVICE" >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/sing-box.service "/etc/systemd/system/$REALITY_SERVICE.service" "/etc/systemd/system/$HY2_SERVICE.service"
        if is_protocol_enabled reality; then write_systemd_unit "$REALITY_SERVICE" "$REALITY_CONFIG_FILE" 'sing-box VLESS Reality'; fi
        if is_protocol_enabled hy2; then write_systemd_unit "$HY2_SERVICE" "$HY2_CONFIG_FILE" 'sing-box Hysteria2'; fi
        systemctl daemon-reload || warn 'systemd daemon-reload 失败。'
        if is_protocol_enabled reality; then start_service_quiet "$REALITY_SERVICE" "$REALITY_CONFIG_FILE" systemd; fi
        if is_protocol_enabled hy2; then start_service_quiet "$HY2_SERVICE" "$HY2_CONFIG_FILE" systemd; fi
        SERVICE_STATUS="systemd: $svcs"
    elif have rc-service; then
        rc-service "$REALITY_SERVICE" stop >/dev/null 2>&1 || true
        rc-service "$HY2_SERVICE" stop >/dev/null 2>&1 || true
        rc-update del "$REALITY_SERVICE" default >/dev/null 2>&1 || true
        rc-update del "$HY2_SERVICE" default >/dev/null 2>&1 || true
        rm -f "/etc/init.d/$REALITY_SERVICE" "/etc/init.d/$HY2_SERVICE"
        if is_protocol_enabled reality; then
            write_openrc_service "$REALITY_SERVICE" "$REALITY_CONFIG_FILE"
            start_service_quiet "$REALITY_SERVICE" "$REALITY_CONFIG_FILE" openrc
        else rm -f "/etc/init.d/$REALITY_SERVICE"; fi
        if is_protocol_enabled hy2; then
            write_openrc_service "$HY2_SERVICE" "$HY2_CONFIG_FILE"
            start_service_quiet "$HY2_SERVICE" "$HY2_CONFIG_FILE" openrc
        else rm -f "/etc/init.d/$HY2_SERVICE"; fi
        SERVICE_STATUS="OpenRC: $svcs"
    else
        warn '未检测到 systemd/OpenRC，配置已生成但未自动启动。'
        SERVICE_STATUS='请手动运行 sing-box run -c /etc/sing-box/config-*.json'
    fi
    return 0
}
verify_services() {
    # 安装收尾自检：应运行的服务是否真的在跑
    if ! have systemctl && ! have rc-service; then return 0; fi
    if is_protocol_enabled reality && service_exists "$REALITY_SERVICE"; then
        [ "$(service_status "$REALITY_SERVICE")" = active ] || warn "Reality 服务未运行，请运行 singbox 在菜单 3 中查看，或执行 journalctl -u $REALITY_SERVICE。"
    fi
    if is_protocol_enabled hy2 && service_exists "$HY2_SERVICE"; then
        [ "$(service_status "$HY2_SERVICE")" = active ] || warn "Hysteria2 服务未运行，请运行 singbox 在菜单 3 中查看，或检查 /var/log/$HY2_SERVICE.err。"
    fi
    return 0
}
write_state() {
    cat > "$STATE_FILE" <<EOF
SCRIPT_VERSION=$SCRIPT_VERSION
INSTALL_MODE=$INSTALL_MODE
REALITY_PORT=$REALITY_PORT
HY2_PORT=$HY2_PORT
CERT_MODE=$CERT_MODE
CERT_DOMAIN=$CERT_DOMAIN
CERT_HTTP_PORT=$CERT_HTTP_PORT
REALITY_SNI=$REALITY_SNI
PUBLIC_IP=$PUBLIC_IP
HY2_HOST=$HY2_HOST
HY2_SNI=$HY2_SNI
LISTEN_IPV6=$LISTEN_IPV6
V6_ONLY=$V6_ONLY
IP_FAMILY=$IP_FAMILY
EOF
    chmod 600 "$STATE_FILE"
    {
        printf '%s\n' 'sing-box-lite 安装完成'
        printf '脚本版本: %s\n' "$SCRIPT_VERSION"
        printf '安装模式: %s\n' "$INSTALL_MODE"
        printf '服务器地址: %s\n' "$PUBLIC_IP"
        if [ "$V6_ONLY" = 1 ]; then printf '网络类型: IPv6-only\n'; else
            if [ "$LISTEN_IPV6" = 1 ]; then printf '网络类型: 双栈（IPv4 + IPv6）\n'; else printf '网络类型: IPv4\n'; fi
        fi
        if is_protocol_enabled reality; then printf 'Reality TCP 端口: %s\n' "$REALITY_PORT"; fi
        if is_protocol_enabled hy2; then printf 'Hysteria2 UDP 端口: %s\n' "$HY2_PORT"; fi
        printf 'Reality SNI/握手站点: %s\n' "$REALITY_SNI"
        if is_protocol_enabled hy2; then printf 'Hysteria2 SNI: %s\n' "$HY2_SNI"; fi
        printf '证书模式: %s\n' "$CERT_MODE"
        if [ "$CERT_MODE" != self ]; then
            printf '证书验证端口: %s\n' "$CERT_HTTP_PORT"
            printf '证书自动续期: cron 每日 03:17（%s）\n' "/var/log/sing-box-lite-acme.log"
        fi
        printf '服务管理: %s\n' "$SERVICE_STATUS"
        printf '\n配置文件:\n'
        if is_protocol_enabled reality; then printf -- '- %s\n' "$REALITY_CONFIG_FILE"; fi
        if is_protocol_enabled hy2; then printf -- '- %s\n' "$HY2_CONFIG_FILE"; fi
        printf '\n客户端文件:\n- %s\n' "$CLIENT_DIR/links.txt"
        if is_protocol_enabled reality; then printf -- '- %s\n' "$CLIENT_DIR/reality.json"; fi
        if is_protocol_enabled hy2; then printf -- '- %s\n' "$CLIENT_DIR/hysteria2.json"; fi
        printf '\n防火墙/安全组:\n'
        if is_protocol_enabled reality; then printf -- '- Reality 需要 TCP %s\n' "$REALITY_PORT"; fi
        if is_protocol_enabled hy2; then printf -- '- Hysteria2 需要 UDP %s\n' "$HY2_PORT"; fi
        printf '\n快捷菜单:\n- 命令: singbox\n- 文件: %s\n' "$SHORTCUT_PATH"
    } > "$CONFIG_DIR/install-info.txt"
    chmod 600 "$CONFIG_DIR/install-info.txt"
}
write_shortcut() {
    mkdir -p "$SCRIPT_INSTALL_DIR" /usr/local/bin || return 1
    cat > "$SHORTCUT_PATH" <<EOF || return 1
#!/bin/sh
exec $SCRIPT_INSTALL_PATH "\$@"
EOF
    chmod 755 "$SHORTCUT_PATH" || return 1
}
install_shortcut() {
    source="$1"
    [ -f "$source" ] || return 0
    mkdir -p "$SCRIPT_INSTALL_DIR" /usr/local/bin || { warn "无法创建目录：$SCRIPT_INSTALL_DIR"; return 1; }
    # 脚本本身就是持久化路径（例如通过 singbox 快捷命令运行）时跳过复制，避免 cp 复制同一文件报错
    if ! cmp -s "$source" "$SCRIPT_INSTALL_PATH" 2>/dev/null; then
        cp -p "$source" "$SCRIPT_INSTALL_PATH" || { warn "无法写入：$SCRIPT_INSTALL_PATH"; return 1; }
    fi
    chmod 755 "$SCRIPT_INSTALL_PATH" || true
    write_shortcut || { warn "无法写入：$SHORTCUT_PATH"; return 1; }
    return 0
}
current_script_path() {
    case "$0" in
        */*) [ -f "$0" ] && printf '%s' "$0" || true ;;
        *) [ -f "$PWD/install-singbox-lite.sh" ] && printf '%s' "$PWD/install-singbox-lite.sh" || true ;;
    esac
}
# 判断点分数字版本号 $1 >= $2
version_ge() {
    [ "$1" = "$2" ] && return 0
    left="$1"; right="$2"
    while [ -n "$left" ] || [ -n "$right" ]; do
        left_part="${left%%.*}"; right_part="${right%%.*}"
        if [ "$left" = "$left_part" ]; then left=''; else left="${left#*.}"; fi
        if [ "$right" = "$right_part" ]; then right=''; else right="${right#*.}"; fi
        case "${left_part}${right_part}" in *[!0-9]*) return 1 ;; esac
        left_part="${left_part:-0}"; right_part="${right_part:-0}"
        if [ "$left_part" -gt "$right_part" ]; then return 0; fi
        if [ "$left_part" -lt "$right_part" ]; then return 1; fi
    done
    return 0
}
upgrade_script() {
    [ "$(id -u)" -eq 0 ] || die '升级脚本请使用 root 运行。'
    tmp_update="$(mktemp)"
    download_file "$REMOTE_SCRIPT_URL" "$tmp_update" || { rm -f "$tmp_update"; die '无法下载最新脚本。'; }
    remote_version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9.]*\)".*/\1/p' "$tmp_update" | head -n 1)"
    [ -n "$remote_version" ] || { rm -f "$tmp_update"; die '远程脚本版本无效。'; }
    if version_ge "$SCRIPT_VERSION" "$remote_version" && [ "${FORCE_SCRIPT_UPDATE:-0}" != 1 ]; then
        rm -f "$tmp_update"
        log "本地脚本已是最新（本地 $SCRIPT_VERSION，远程 $remote_version）；如需强制更新请设置 FORCE_SCRIPT_UPDATE=1。"
        return 0
    fi
    if [ -f "$SCRIPT_INSTALL_PATH" ] && ! cmp -s "$SCRIPT_INSTALL_PATH" "$tmp_update"; then
        cp -p "$SCRIPT_INSTALL_PATH" "$SCRIPT_INSTALL_PATH.bak.$SCRIPT_VERSION"
        warn "已备份旧脚本：$SCRIPT_INSTALL_PATH.bak.$SCRIPT_VERSION"
    fi
    mkdir -p "$SCRIPT_INSTALL_DIR"; cp "$tmp_update" "$SCRIPT_INSTALL_PATH"; chmod 755 "$SCRIPT_INSTALL_PATH"; rm -f "$tmp_update"
    write_shortcut || warn "无法写入快捷命令：$SHORTCUT_PATH"
    log "脚本已更新到版本 $remote_version。快捷命令：singbox"
}
prompt_port() {
    label="$1"; default="$2"; current="$3"
    while :; do
        if [ -n "$current" ]; then
            printf '%s（回车保持当前 %s）：' "$label" "$current" >&2
        else
            printf '%s（回车使用默认 %s）：' "$label" "$default" >&2
        fi
        read -r value || value=''
        [ -n "$value" ] || value="${current:-$default}"
        if is_valid_port "$value"; then printf '%s' "$value"; return 0; fi
        warn "无效端口「$value」，请输入 1-65535 的数字。"
        current=''
    done
}
prompt_install_options() {
    # 自定义安装：从状态文件回填上次使用的端口与证书设置
    load_state || true
    while :; do
        printf '\n安装协议：\n  1) Reality + Hysteria2（推荐）\n  2) 仅 Reality\n  3) 仅 Hysteria2\n请选择（回车使用 1）：' >&2
        read -r protocol_choice || protocol_choice=''
        [ -n "$protocol_choice" ] || protocol_choice=1
        case "$protocol_choice" in
            1) INSTALL_MODE=both; break ;;
            2) INSTALL_MODE=reality; break ;;
            3) INSTALL_MODE=hy2; break ;;
            *) warn '无效选项，请输入 1-3。' ;;
        esac
    done
    if is_protocol_enabled reality; then
        REALITY_PORT="$(prompt_port 'Reality TCP 端口' "$DEFAULT_REALITY_PORT" "$REALITY_PORT")"
        while :; do
            printf '\nReality 握手域名：\n  1) %s（默认）\n  2) %s\n  3) 自定义域名\n请选择（回车保持当前 %s）：\n' \
                "$DEFAULT_REALITY_SNI" "$REALITY_SNI_ALT" "$REALITY_SNI" >&2
            read -r value || value=''
            case "$value" in
                '') break ;;
                1) REALITY_SNI="$DEFAULT_REALITY_SNI"; break ;;
                2) REALITY_SNI="$REALITY_SNI_ALT"; break ;;
                3)
                    while :; do
                        printf '自定义握手域名（回车使用 %s）：' "$REALITY_SNI" >&2
                        read -r candidate || candidate=''
                        candidate="${candidate:-$REALITY_SNI}"
                        if validate_domain "$candidate"; then REALITY_SNI="$candidate"; break; fi
                        warn "域名格式无效：${candidate:-（空）}"
                    done
                    break ;;
                *)
                    # 单个字符按无效菜单项处理，其余按域名校验（也允许直接输入域名）
                    case "$value" in
                        ?) warn '无效选项，请输入 1-3，或直接输入域名。' ;;
                        *)
                            if validate_domain "$value"; then REALITY_SNI="$value"; break; fi
                            warn "域名格式无效：$value" ;;
                    esac
                    ;;
            esac
        done
    else
        REALITY_PORT=''
    fi
    if is_protocol_enabled hy2; then
        HY2_PORT="$(prompt_port 'Hysteria2 UDP 端口' "$DEFAULT_HY2_PORT" "$HY2_PORT")"
        default_cert_choice=1
        case "$CERT_MODE" in domain) default_cert_choice=2 ;; ip) default_cert_choice=3 ;; esac
        while :; do
            printf '\nHysteria2 证书：\n  1) 自签名证书（无需域名）\n  2) 自动申请域名证书\n  3) 自动申请 IP 证书\n请选择（回车使用 %s）：' "$default_cert_choice" >&2
            read -r cert_choice || cert_choice=''
            [ -n "$cert_choice" ] || cert_choice="$default_cert_choice"
            case "$cert_choice" in
                1) CERT_MODE=self; CERT_DOMAIN=''; break ;;
                2)
                    CERT_MODE=domain
                    while :; do
                        if [ -n "$CERT_DOMAIN" ]; then
                            printf '证书域名（回车保持 %s）：' "$CERT_DOMAIN" >&2
                        else
                            printf '证书域名：' >&2
                        fi
                        read -r value || value=''
                        candidate="${value:-$CERT_DOMAIN}"
                        if validate_domain "$candidate"; then CERT_DOMAIN="$candidate"; break; fi
                        warn "域名格式无效：${candidate:-（空）}"
                    done
                    printf 'ACME 账户邮箱（可留空）：' >&2; read -r CERT_EMAIL || CERT_EMAIL=''
                    CERT_HTTP_PORT="$(prompt_port 'HTTP 验证端口' "$DEFAULT_ACME_HTTP_PORT" "$CERT_HTTP_PORT")"
                    break ;;
                3)
                    CERT_MODE=ip
                    printf 'ACME 账户邮箱（可留空）：' >&2; read -r CERT_EMAIL || CERT_EMAIL=''
                    CERT_HTTP_PORT="$(prompt_port 'HTTP 验证端口' "$DEFAULT_ACME_HTTP_PORT" "$CERT_HTTP_PORT")"
                    break ;;
                *) warn '无效选项，请输入 1-3。' ;;
            esac
        done
    else
        HY2_PORT=''; CERT_MODE=self; CERT_DOMAIN=''; CERT_EMAIL=''
    fi
    return 0
}
prepare_install() {
    [ "$(id -u)" -eq 0 ] || die '安装请使用 root 运行。'
    if [ -f "$STATE_FILE" ] && [ -t 0 ]; then
        old_mode="$(read_state_value INSTALL_MODE)"; old_rp="$(read_state_value REALITY_PORT)"; old_hp="$(read_state_value HY2_PORT)"
        printf '\n%s检测到已有安装%s（模式 %s，Reality TCP %s，Hysteria2 UDP %s）。\n重新安装会重新生成密钥、证书与节点链接，并覆盖现有配置。\n是否继续？[y/N]：' \
            "$C_YELLOW" "$C_RESET" "${old_mode:-both}" "${old_rp:-默认}" "${old_hp:-默认}" >&2
        read -r confirm_install || confirm_install=''
        case "$confirm_install" in
            y|Y|yes|YES|是) ;;
            *) log '已取消安装。'; return 0 ;;
        esac
    fi
    INSTALL_STARTED=1
    if is_protocol_enabled reality; then [ -n "$REALITY_PORT" ] || REALITY_PORT="$DEFAULT_REALITY_PORT"; validate_port "$REALITY_PORT" 'Reality TCP 端口'; fi
    if is_protocol_enabled hy2; then [ -n "$HY2_PORT" ] || HY2_PORT="$DEFAULT_HY2_PORT"; validate_port "$HY2_PORT" 'Hysteria2 UDP 端口'; fi
    if is_protocol_enabled reality && is_protocol_enabled hy2 && [ "$REALITY_PORT" = "$HY2_PORT" ]; then die 'Reality TCP 和 Hysteria2 UDP 不能使用同一个端口。'; fi
    if [ "$CERT_MODE" != self ]; then
        [ -n "$CERT_HTTP_PORT" ] || CERT_HTTP_PORT="$DEFAULT_ACME_HTTP_PORT"
        validate_port "$CERT_HTTP_PORT" '证书验证端口'
    fi
    if [ "$CERT_MODE" = domain ]; then validate_domain "$CERT_DOMAIN" || die "证书域名格式无效：$CERT_DOMAIN"; fi
    install_base_packages; install_sing_box; SING_BOX="$(command -v sing-box)"; SING_BOX_PATH="$SING_BOX"
    # 选择节点地址族；同时存在 IPv4 和公网 IPv6 时交给用户选择。
    prompt_ip_family
    PUBLIC_IP="${PUBLIC_IP:-$(get_public_ip)}"
    if [ -z "$PUBLIC_IP" ]; then
        if [ "$V6_ONLY" = 1 ]; then
            die '无法获取公网 IPv6。v6-only 机器请先设置环境变量 PUBLIC_IP=<你的公网IPv6> 再运行。'
        fi
        die '无法获取公网 IP，请设置 PUBLIC_IP 后重试。'
    fi
    # 节点地区名称为可选环境变量；未设置时使用公网地址作为节点名，不阻断安装。
    HY2_HOST="$PUBLIC_IP"
    mkdir -p "$CONFIG_DIR" "$CLIENT_DIR" /var/lib/sing-box; chmod 700 "$CONFIG_DIR" "$CLIENT_DIR"
    backup_file "$CONFIG_FILE"; backup_file "$REALITY_CONFIG_FILE"; backup_file "$HY2_CONFIG_FILE"
    UUID=''; HY2_PASSWORD=''; REALITY_PRIVATE_KEY=''; REALITY_PUBLIC_KEY=''
    if is_protocol_enabled reality; then
        UUID="$(make_uuid)"; KEYPAIR="$($SING_BOX generate reality-keypair)"
        REALITY_PRIVATE_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F': ' '/PrivateKey/ {print $2; exit}')"
        REALITY_PUBLIC_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F': ' '/PublicKey/ {print $2; exit}')"
        [ -n "$REALITY_PRIVATE_KEY" ] && [ -n "$REALITY_PUBLIC_KEY" ] || die 'Reality 密钥生成失败。'
    fi
    if is_protocol_enabled hy2; then
        HY2_PASSWORD="$(openssl rand -hex 24)"
        if [ "$CERT_MODE" = self ]; then make_self_signed_cert; else issue_acme_certificate; fi
    fi
    write_config "$CONFIG_FILE"
    if is_protocol_enabled reality; then write_config "$REALITY_CONFIG_FILE" reality; else rm -f "$REALITY_CONFIG_FILE"; fi
    if is_protocol_enabled hy2; then write_config "$HY2_CONFIG_FILE" hy2; else rm -f "$HY2_CONFIG_FILE"; fi
    "$SING_BOX" check -c "$CONFIG_FILE" >/dev/null || die "配置校验失败：$CONFIG_FILE"
    if is_protocol_enabled reality; then "$SING_BOX" check -c "$REALITY_CONFIG_FILE" >/dev/null || die 'Reality 配置校验失败。'; fi
    if is_protocol_enabled hy2; then "$SING_BOX" check -c "$HY2_CONFIG_FILE" >/dev/null || die 'Hysteria2 配置校验失败。'; fi
    write_client_files; write_services; verify_services; write_state
    source_path="$(current_script_path)"
    if [ -n "$source_path" ]; then
        install_shortcut "$source_path" || warn '快捷菜单安装失败（需要 root 写入 /usr/local/bin）。'
    fi
    INSTALL_OK=1
    view_nodes || true
    printf '\n%s安装完成%s\n' "$C_GREEN" "$C_RESET"
    log '快捷菜单：singbox（或 ./singbox）'
    firewall_hint=''
    if is_protocol_enabled reality; then firewall_hint="放行 Reality TCP $REALITY_PORT"; fi
    if is_protocol_enabled hy2; then
        [ -n "$firewall_hint" ] && firewall_hint="$firewall_hint，"
        firewall_hint="${firewall_hint}放行 Hysteria2 UDP $HY2_PORT"
    fi
    [ -n "$firewall_hint" ] && log "请$firewall_hint。"
    return 0
}
upgrade_all() {
    upgrade_sing_box
    upgrade_script
    print_ok '升级流程结束'
}
print_menu() {
    box_top
    box_line "  ${C_GREEN}sing-box-lite${C_RESET}  ${C_YELLOW}v${SCRIPT_VERSION}${C_RESET}"
    box_mid
    box_line "  1) 一键快捷安装（Reality + Hysteria2）"
    box_line "  2) 自定义安装（仅 Reality / 仅 Hysteria2）"
    box_line "  3) 状态查询及管理"
    box_line "  4) 节点信息"
    box_line "  5) 升级脚本与 sing-box"
    box_line "  6) 完全卸载"
    box_line "  0) 退出"
    box_bottom
    if [ -f "$STATE_FILE" ]; then
        _mode="$(read_state_value INSTALL_MODE)"; [ -n "$_mode" ] || _mode='both'
        printf '  %s已安装%s 模式 %s ｜ Reality %s ｜ Hysteria2 %s\n\n' \
            "$C_DIM" "$C_RESET" "$_mode" "$(service_state_label "$REALITY_SERVICE")" "$(service_state_label "$HY2_SERVICE")"
    else
        printf '  %s尚未安装%s：选择 1) 一键快捷安装 开始部署\n\n' "$C_DIM" "$C_RESET"
    fi
}
show_menu() {
    [ "$(id -u)" -eq 0 ] || die '请使用 root 运行本脚本（安装与服务管理均需要 root 权限）。'
    while :; do
        clear_screen
        print_menu
        printf '请选择操作：' >&2
        read -r choice || exit 0
        case "$choice" in
            1)
                ( INSTALL_MODE=both; REALITY_PORT=''; HY2_PORT=''; CERT_MODE=self; CERT_DOMAIN=''; CERT_HTTP_PORT=''; prepare_install ) || warn '安装未完成。'
                pause ;;
            2)
                ( prompt_install_options && prepare_install ) || warn '安装未完成。'
                pause ;;
            3) manage_services || pause ;;
            4) view_nodes || true; pause ;;
            5) ( upgrade_all ) || warn '升级未完成。'; pause ;;
            6) ( uninstall_singbox ) || warn '卸载未完成。'; pause ;;
            0) exit 0 ;;
            *) warn '无效选项。'; pause ;;
        esac
    done
}

restore_state_install_defaults() {
    # 未显式给出的参数回填上次安装的端口、握手域名与证书设置
    [ -f "$STATE_FILE" ] || return 0
    if is_protocol_enabled reality; then
        [ -n "$REALITY_PORT" ] || REALITY_PORT="$(read_state_value REALITY_PORT)"
        if [ "$REALITY_SNI_FROM_ENV" != 1 ]; then
            _v="$(read_state_value REALITY_SNI)"; if [ -n "$_v" ]; then REALITY_SNI="$_v"; fi
        fi
    fi
    if is_protocol_enabled hy2; then
        [ -n "$HY2_PORT" ] || HY2_PORT="$(read_state_value HY2_PORT)"
        _v="$(read_state_value CERT_MODE)"; [ -n "$_v" ] && CERT_MODE="$_v"
        _v="$(read_state_value CERT_HTTP_PORT)"; [ -n "$_v" ] && CERT_HTTP_PORT="$_v"
        CERT_DOMAIN="$(read_state_value CERT_DOMAIN)"
        if [ "$CERT_MODE" = domain ] && [ -z "$CERT_DOMAIN" ]; then CERT_MODE=self; fi
    fi
    return 0
}
OS_ID=''; OS_LIKE=''
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"; OS_LIKE="${ID_LIKE:-}"
fi

usage() {
    cat <<EOF
用法：$0 [命令]

命令：
  install [both|reality|hy2] [Reality端口] [Hy2端口]   安装；无参数时进入交互安装
  status                                                查看运行状态、监听端口与安装信息
  manage                                                服务开启 / 关闭 / 重启菜单
  nodes                                                 查看节点导入链接与客户端配置
  upgrade                                               升级 sing-box 与本脚本
  uninstall                                             完全卸载
  help | --help                                         显示本帮助
  version | --version                                   显示脚本版本
  （无参数）                                             进入交互菜单

环境变量：
  PUBLIC_IP=地址        覆盖公网地址检测结果
  REALITY_SNI=域名      指定 Reality 握手域名（默认 academy.nvidia.com）
  REMOTE_SCRIPT_URL=URL 指定脚本升级地址
  ACME_HTTP_PORT=端口   预填证书 HTTP 验证端口
  NODE_REGION_EMOJI=X   节点名称前缀（表情，可选）
  NODE_REGION_CODE=X    节点名称后缀（地区码，可选）
  FORCE_SCRIPT_UPDATE=1 脚本升级时忽略版本比较，强制覆盖
  NO_COLOR=1            关闭彩色输出
EOF
}

if [ "${1:-}" = '--version' ] || [ "${1:-}" = '-v' ] || [ "${1:-}" = 'version' ]; then
    printf 'sing-box-lite %s\n' "$SCRIPT_VERSION"; exit 0
fi
case "${1:-}" in
    install)
        shift
        mode_explicit=0
        case "${1:-}" in
            both|reality|hy2) INSTALL_MODE="$1"; mode_explicit=1; shift ;;
            '') INSTALL_MODE=both ;;
            *[!0-9]*) die '用法：install [both|reality|hy2] [Reality端口] [Hy2端口]' ;;
        esac
        if [ "$INSTALL_MODE" = reality ]; then
            [ $# -gt 1 ] && die '仅安装 Reality 只需一个端口：install reality <Reality端口>'
            REALITY_PORT="${1:-}"; HY2_PORT=''
        elif [ "$INSTALL_MODE" = hy2 ]; then
            [ $# -gt 1 ] && die '仅安装 Hysteria2 只需一个端口：install hy2 <Hy2端口>'
            REALITY_PORT=''; HY2_PORT="${1:-}"
        else
            REALITY_PORT="${1:-}"; HY2_PORT="${2:-}"
            [ $# -gt 2 ] && die 'install both 最多接受两个端口：install both <Reality端口> <Hy2端口>'
        fi
        if [ "$mode_explicit" = 0 ]; then
            _saved_mode="$(read_state_value INSTALL_MODE)"
            if [ -n "$_saved_mode" ]; then INSTALL_MODE="$_saved_mode"; fi
        fi
        restore_state_install_defaults
        prepare_install ;;
    uninstall|remove) uninstall_singbox ;;
    nodes|node|view|show) view_nodes ;;
    status|state|check) show_status ;;
    manage|service) manage_services ;;
    upgrade|update) upgrade_all ;;
    help|-h|--help) usage ;;
    '') show_menu ;;
    *[!0-9]*) usage >&2; exit 1 ;;
    *) INSTALL_MODE=both; REALITY_PORT="$1"; HY2_PORT="${2:-}"; restore_state_install_defaults; prepare_install ;;
esac

