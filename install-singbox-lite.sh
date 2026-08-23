#!/bin/sh
# sing-box-lite: VLESS-Reality + Hysteria2 one-click installer and manager
SCRIPT_VERSION="3.0.0"
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
REALITY_SNI="${REALITY_SNI:-www.cloudflare.com}"
HY2_SNI="${HY2_SNI:-www.example.com}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-firefox}"
NODE_REGION_CODE="${NODE_REGION_CODE:-}"
NODE_REGION_EMOJI="${NODE_REGION_EMOJI:-}"
DEFAULT_REALITY_PORT="55667"
DEFAULT_HY2_PORT="55668"
DEFAULT_ACME_HTTP_PORT="80"
INSTALL_MODE="both"
REALITY_PORT=""
HY2_PORT=""
CERT_MODE="self"
CERT_DOMAIN=""
CERT_EMAIL=""
CERT_HTTP_PORT="$DEFAULT_ACME_HTTP_PORT"
HY2_HOST=""
PUBLIC_IP=""
CONFIG_SCOPE="all"
SING_BOX_PATH="/usr/local/bin/sing-box"

log() { printf '[sing-box-lite] %s\n' "$*"; }
warn() { printf '[sing-box-lite][WARN] %s\n' "$*" >&2; }
die() { printf '[sing-box-lite][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
pause() { printf '\n按回车返回菜单...'; read -r _pause || true; }
clear_screen() { if have clear; then clear 2>/dev/null || printf '\n\n'; else printf '\n\n'; fi; }

download_file() {
    url="$1"; destination="$2"
    if have curl; then curl -4fsSL --max-time 60 "$url" -o "$destination"
    elif have wget; then wget -q --timeout=60 -O "$destination" "$url"
    else return 1; fi
}

validate_domain() {
    domain="$1"
    case "$domain" in ''|*[!A-Za-z0-9.-]*|.*|*.|*..*) return 1 ;; esac
    return 0
}
validate_port() {
    port="$1"; label="$2"
    case "$port" in ''|*[!0-9]*) die "$label 必须是 1-65535 的数字。" ;; esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "$label 必须是 1-65535。"
}

is_protocol_enabled() {
    case "${CONFIG_SCOPE:-all}:$1" in
        reality:reality|hy2:hy2) return 0 ;;
        all:reality) [ "$INSTALL_MODE" = both ] || [ "$INSTALL_MODE" = reality ] ;;
        all:hy2) [ "$INSTALL_MODE" = both ] || [ "$INSTALL_MODE" = hy2 ] ;;
        *) return 1 ;;
    esac
}

service_status() {
    service="$1"
    if have systemctl; then systemctl is-active "$service" 2>/dev/null || printf 'inactive'
    elif have rc-service; then rc-service "$service" status >/dev/null 2>&1 && printf 'active' || printf 'inactive'
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
print_status_row() {
    label="$1"; service="$2"; port="$3"; transport="$4"
    if service_exists "$service"; then status="$(service_status "$service")"; else status='未安装'; fi
    case "$status" in active) mark='运行中' ;; inactive) mark='已停止' ;; unknown) mark='未知' ;; *) mark="$status" ;; esac
    printf '  %-14s %-8s %-7s %s\n' "$label" "$mark" "$transport" "${port:-未设置}"
}
read_state_value() {
    key="$1"; [ -f "$STATE_FILE" ] || return 0
    sed -n "s/^${key}=//p" "$STATE_FILE" | head -n 1
}
show_status_summary() {
    [ "$(id -u)" -eq 0 ] || die '查询状态请使用 root 运行。'
    mode="$(read_state_value INSTALL_MODE)"; [ -n "$mode" ] || mode="$INSTALL_MODE"
    reality_port="$(read_state_value REALITY_PORT)"; hy2_port="$(read_state_value HY2_PORT)"
    printf '\n\033[1;36m┌────────────── sing-box-lite 状态 ──────────────┐\033[0m\n'
    printf '  安装模式：%s\n' "$mode"
    printf '\033[1;36m├─────────────────────────────────────────────────┤\033[0m\n'
    print_status_row 'VLESS Reality' "$REALITY_SERVICE" "$reality_port" TCP
    print_status_row 'Hysteria2' "$HY2_SERVICE" "$hy2_port" UDP
    printf '\033[1;36m└─────────────────────────────────────────────────┘\033[0m\n'
}
show_status() {
    show_status_summary
    if have ss; then
        printf '\n监听端口：\n'
        ss -lntup 2>/dev/null | grep -E 'sing-box|LISTEN|UNCONN' || true
    fi
    if have systemctl; then
        printf '\n服务状态：\n'
        systemctl --no-pager --full status "$REALITY_SERVICE" "$HY2_SERVICE" 2>/dev/null | sed -n '1,80p' || true
    elif have rc-service; then
        rc-service "$REALITY_SERVICE" status 2>/dev/null || true
        rc-service "$HY2_SERVICE" status 2>/dev/null || true
    fi
    [ -f "$CONFIG_DIR/install-info.txt" ] && { printf '\n安装信息：\n'; sed -n '1,80p' "$CONFIG_DIR/install-info.txt"; }
}

manage_services() {
    [ "$(id -u)" -eq 0 ] || die '管理服务请使用 root 运行。'
    while :; do
        clear_screen; show_status_summary
        printf '\n\033[1;33m状态管理\033[0m\n'
        printf '  1) 开启 Reality       2) 关闭 Reality       3) 重启 Reality\n'
        printf '  4) 开启 Hysteria2     5) 关闭 Hysteria2     6) 重启 Hysteria2\n'
        printf '  7) 开启全部           8) 关闭全部           9) 重启全部\n'
        printf '  0) 返回\n请选择操作：'
        read -r choice || return 0
        case "$choice" in
            1) service_action "$REALITY_SERVICE" start || true ;;
            2) service_action "$REALITY_SERVICE" stop || true ;;
            3) service_action "$REALITY_SERVICE" restart || true ;;
            4) service_action "$HY2_SERVICE" start || true ;;
            5) service_action "$HY2_SERVICE" stop || true ;;
            6) service_action "$HY2_SERVICE" restart || true ;;
            7) service_action "$REALITY_SERVICE" start || true; service_action "$HY2_SERVICE" start || true ;;
            8) service_action "$REALITY_SERVICE" stop || true; service_action "$HY2_SERVICE" stop || true ;;
            9) service_action "$REALITY_SERVICE" restart || true; service_action "$HY2_SERVICE" restart || true ;;
            0) return 0 ;;
            *) warn '无效选项。' ;;
        esac
        printf '\n当前状态：\n'; show_status_summary; pause
    done
}

view_nodes() {
    [ "$(id -u)" -eq 0 ] || die '查看节点请使用 root 运行。'
    [ -f "$CLIENT_DIR/links.txt" ] || die '未找到节点信息，请先安装。'
    printf '\n\033[1;36m==== 节点信息与导入链接 ====\033[0m\n'
    cat "$CLIENT_DIR/links.txt"
    printf '\n客户端文件目录：%s\n' "$CLIENT_DIR"
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
    printf '此操作将停止并删除两个协议服务、配置、证书、节点信息、快捷命令和本地 sing-box。\n输入 yes 确认：'
    read -r confirm || true
    [ "$confirm" = yes ] || { log '已取消卸载。'; return 0; }
    remove_service_files
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
    rm -rf "$CONFIG_DIR" /var/lib/sing-box "$SCRIPT_INSTALL_DIR" "$SHORTCUT_PATH" /usr/local/bin/singbox-lite
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
    install_base_packages; FORCE_SING_BOX_UPDATE=1 install_sing_box
    if is_protocol_enabled reality; then service_action "$REALITY_SERVICE" restart || true; fi
    if is_protocol_enabled hy2; then service_action "$HY2_SERVICE" restart || true; fi
    log "sing-box 已更新：$(sing-box version | head -n 1)"
}

get_public_ip() {
    ip=''
    if have curl; then
        ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ip" ] || ip="$(curl -4fsS --max-time 5 https://ifconfig.me/ip 2>/dev/null || true)"
    elif have wget; then
        ip="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ip" ] || ip="$(wget -qO- --timeout=5 https://ifconfig.me/ip 2>/dev/null || true)"
    fi
    if [ -z "$ip" ] && have ip; then ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"; fi
    if [ -z "$ip" ] && have hostname; then ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
    printf '%s' "$ip"
}
get_node_region() {
    geo=''
    if have curl && { [ -z "$NODE_REGION_CODE" ] || [ -z "$NODE_REGION_EMOJI" ]; }; then
        geo="$(curl -4fsS --max-time 5 "https://ipwho.is/${PUBLIC_IP}?fields=country_code,flag" 2>/dev/null || true)"
        [ -n "$NODE_REGION_CODE" ] || NODE_REGION_CODE="$(printf '%s' "$geo" | sed -n 's/.*"country_code"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' | head -n 1 | tr '[:lower:]' '[:upper:]')"
        [ -n "$NODE_REGION_EMOJI" ] || NODE_REGION_EMOJI="$(printf '%s' "$geo" | sed -n 's/.*"emoji"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    fi
    [ -n "$NODE_REGION_CODE" ] || NODE_REGION_CODE=XX; [ -n "$NODE_REGION_EMOJI" ] || NODE_REGION_EMOJI='🌐'
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
issue_acme_certificate() {
    [ "$CERT_MODE" = domain ] || [ "$CERT_MODE" = ip ] || return 0
    install_acme_sh
    acme="${ACME_HOME:-/root/.acme.sh}/acme.sh"
    validate_port "$CERT_HTTP_PORT" '证书验证端口'
    service_action "$HY2_SERVICE" stop || true
    log "申请 $CERT_MODE 证书，验证端口：$CERT_HTTP_PORT"
    if [ "$CERT_MODE" = domain ]; then
        validate_domain "$CERT_DOMAIN" || die "证书域名格式无效：$CERT_DOMAIN"
        "$acme" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        "$acme" --issue --standalone -d "$CERT_DOMAIN" --httpport "$CERT_HTTP_PORT" || die '域名证书申请失败。请确认域名解析、验证端口可达且无其他程序占用。'
        "$acme" --install-cert -d "$CERT_DOMAIN" --fullchain-file "$CERT_FILE" --key-file "$KEY_FILE" || die '域名证书部署失败。'
        HY2_SNI="$CERT_DOMAIN"; HY2_HOST="$CERT_DOMAIN"
    else
        "$acme" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        "$acme" --issue --standalone --ip "$PUBLIC_IP" --httpport "$CERT_HTTP_PORT" || die 'IP 证书申请失败。请确认当前 acme.sh/CA 支持 IP 证书，且公网 IP 与验证端口可达。'
        "$acme" --install-cert -d "$PUBLIC_IP" --fullchain-file "$CERT_FILE" --key-file "$KEY_FILE" || die 'IP 证书部署失败。'
        HY2_SNI="$PUBLIC_IP"; HY2_HOST="$PUBLIC_IP"
    fi
    chmod 600 "$KEY_FILE"; chmod 644 "$CERT_FILE"
    log "证书已部署到：$CERT_FILE / $KEY_FILE"
}
backup_file() {
    file="$1"; [ -f "$file" ] || return 0
    backup="$file.bak.$(date +%Y%m%d-%H%M%S)"; cp -p "$file" "$backup"; warn "已备份旧文件：$backup"
}

write_reality_inbound() {
    cat <<EOF
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "0.0.0.0",
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
      "listen": "0.0.0.0",
      "listen_port": $HY2_PORT,
      "users": [{"name": "default", "password": "$HY2_PASSWORD"}],
      "tls": {"enabled": true, "server_name": "$HY2_SNI", "certificate_path": "$CERT_FILE", "key_path": "$KEY_FILE"}
    }
EOF
}
write_config() {
    destination="$1"
    {
        cat <<EOF
{
  "log": {"level": "warn", "timestamp": true},
  "inbounds": [
EOF
        first=1
        if is_protocol_enabled reality; then write_reality_inbound; first=0; fi
        if is_protocol_enabled hy2; then [ "$first" -eq 1 ] || printf ',\n'; write_hy2_inbound; fi
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
    URL_HOST="$PUBLIC_IP"; case "$PUBLIC_IP" in *:*) URL_HOST="[$PUBLIC_IP]" ;; esac
    rm -f "$CLIENT_DIR/reality.json" "$CLIENT_DIR/hysteria2.json" "$CLIENT_DIR/links.txt"
    : > "$CLIENT_DIR/links.txt"
    node_name="${NODE_REGION_EMOJI}${NODE_REGION_CODE}"
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
  "outbounds": [{"type": "hysteria2", "tag": "proxy", "server": "$HY2_HOST", "server_port": $HY2_PORT, "password": "$HY2_PASSWORD", "tls": {"enabled": true, "server_name": "$HY2_SNI", "insecure": $insecure}}]
}
EOF
        HY2_LINK="hysteria2://${HY2_PASSWORD}@${HY2_HOST}:${HY2_PORT}/?${query}#${node_name}-Hy2"
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
write_services() {
    mkdir -p /var/lib/sing-box
    if have systemctl; then
        systemctl disable --now sing-box "$REALITY_SERVICE" "$HY2_SERVICE" >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/sing-box.service "/etc/systemd/system/$REALITY_SERVICE.service" "/etc/systemd/system/$HY2_SERVICE.service"
        if is_protocol_enabled reality; then write_systemd_unit "$REALITY_SERVICE" "$REALITY_CONFIG_FILE" 'sing-box VLESS Reality'; fi
        if is_protocol_enabled hy2; then write_systemd_unit "$HY2_SERVICE" "$HY2_CONFIG_FILE" 'sing-box Hysteria2'; fi
        systemctl daemon-reload
        if is_protocol_enabled reality; then systemctl enable --now "$REALITY_SERVICE"; fi
        if is_protocol_enabled hy2; then systemctl enable --now "$HY2_SERVICE"; fi
        SERVICE_STATUS='systemd: sing-box-reality / sing-box-hysteria2'
    elif have rc-service; then
        rc-service "$REALITY_SERVICE" stop >/dev/null 2>&1 || true
        rc-service "$HY2_SERVICE" stop >/dev/null 2>&1 || true
        rc-update del "$REALITY_SERVICE" default >/dev/null 2>&1 || true
        rc-update del "$HY2_SERVICE" default >/dev/null 2>&1 || true
        rm -f "/etc/init.d/$REALITY_SERVICE" "/etc/init.d/$HY2_SERVICE"
        if is_protocol_enabled reality; then
            write_openrc_service "$REALITY_SERVICE" "$REALITY_CONFIG_FILE"; rc-update add "$REALITY_SERVICE" default >/dev/null 2>&1 || true
            rc-service "$REALITY_SERVICE" restart || rc-service "$REALITY_SERVICE" start
        else rm -f "/etc/init.d/$REALITY_SERVICE"; fi
        if is_protocol_enabled hy2; then
            write_openrc_service "$HY2_SERVICE" "$HY2_CONFIG_FILE"; rc-update add "$HY2_SERVICE" default >/dev/null 2>&1 || true
            rc-service "$HY2_SERVICE" restart || rc-service "$HY2_SERVICE" start
        else rm -f "/etc/init.d/$HY2_SERVICE"; fi
        SERVICE_STATUS='OpenRC: sing-box-reality / sing-box-hysteria2'
    else
        warn '未检测到 systemd/OpenRC，配置已生成但未自动启动。'
        SERVICE_STATUS='请手动运行 sing-box run -c /etc/sing-box/config-*.json'
    fi
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
PUBLIC_IP=$PUBLIC_IP
HY2_HOST=$HY2_HOST
HY2_SNI=$HY2_SNI
EOF
    chmod 600 "$STATE_FILE"
    {
        printf '%s\n' 'sing-box-lite 安装完成'
        printf '脚本版本: %s\n' "$SCRIPT_VERSION"
        printf '安装模式: %s\n' "$INSTALL_MODE"
        printf '服务器地址: %s\n' "$PUBLIC_IP"
        if is_protocol_enabled reality; then printf 'Reality TCP 端口: %s\n' "$REALITY_PORT"; fi
        if is_protocol_enabled hy2; then printf 'Hysteria2 UDP 端口: %s\n' "$HY2_PORT"; fi
        printf 'Reality SNI/握手站点: %s\n' "$REALITY_SNI"
        if is_protocol_enabled hy2; then printf 'Hysteria2 SNI: %s\n' "$HY2_SNI"; fi
        printf '证书模式: %s\n' "$CERT_MODE"
        if [ "$CERT_MODE" != self ]; then printf '证书验证端口: %s\n' "$CERT_HTTP_PORT"; fi
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
install_shortcut() {
    source="$1"
    [ -f "$source" ] || return 0
    mkdir -p "$SCRIPT_INSTALL_DIR" /usr/local/bin
    cp -p "$source" "$SCRIPT_INSTALL_PATH"
    chmod 755 "$SCRIPT_INSTALL_PATH"
    cat > "$SHORTCUT_PATH" <<'EOF'
#!/bin/sh
exec /usr/local/lib/sing-box-lite/install-singbox-lite.sh "$@"
EOF
    chmod 755 "$SHORTCUT_PATH"
}
current_script_path() {
    case "$0" in
        */*) [ -f "$0" ] && printf '%s' "$0" || true ;;
        *) [ -f "$PWD/install-singbox-lite.sh" ] && printf '%s' "$PWD/install-singbox-lite.sh" || true ;;
    esac
}
upgrade_script() {
    [ "$(id -u)" -eq 0 ] || die '升级脚本请使用 root 运行。'
    tmp_update="$(mktemp)"
    download_file "$REMOTE_SCRIPT_URL" "$tmp_update" || { rm -f "$tmp_update"; die '无法下载最新脚本。'; }
    remote_version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9.]*\)".*/\1/p' "$tmp_update" | head -n 1)"
    [ -n "$remote_version" ] || { rm -f "$tmp_update"; die '远程脚本版本无效。'; }
    if [ "$remote_version" = "$SCRIPT_VERSION" ]; then rm -f "$tmp_update"; log "脚本已是最新版本 $SCRIPT_VERSION。"; return 0; fi
    if [ -f "$SCRIPT_INSTALL_PATH" ]; then cp -p "$SCRIPT_INSTALL_PATH" "$SCRIPT_INSTALL_PATH.bak.$SCRIPT_VERSION"; fi
    mkdir -p "$SCRIPT_INSTALL_DIR"; cp "$tmp_update" "$SCRIPT_INSTALL_PATH"; chmod 755 "$SCRIPT_INSTALL_PATH"; rm -f "$tmp_update"
    cat > "$SHORTCUT_PATH" <<'EOF'
#!/bin/sh
exec /usr/local/lib/sing-box-lite/install-singbox-lite.sh "$@"
EOF
    chmod 755 "$SHORTCUT_PATH"
    log "脚本已更新到版本 $remote_version。快捷命令：singbox"
}
prompt_port() {
    label="$1"; default="$2"; current="$3"
    if [ -n "$current" ]; then printf '%s：%s\n' "$label" "$current" >&2; printf '%s' "$current"; return; fi
    printf '%s（回车使用默认 %s）：' "$label" "$default" >&2; read -r value || value=''; [ -n "$value" ] || value="$default"; printf '%s' "$value"
}
prompt_install_options() {
    printf '\n安装协议：\n  1) Reality + Hysteria2（推荐）\n  2) 仅 Reality\n  3) 仅 Hysteria2\n请选择：'
    read -r protocol_choice || protocol_choice=1
    case "$protocol_choice" in 1) INSTALL_MODE=both ;; 2) INSTALL_MODE=reality ;; 3) INSTALL_MODE=hy2 ;; *) die '无效协议选项。' ;; esac
    if is_protocol_enabled reality; then
        REALITY_PORT="$(prompt_port 'Reality TCP 端口' "$DEFAULT_REALITY_PORT" "$REALITY_PORT")"
        printf 'Reality 握手域名（默认 %s）：' "$REALITY_SNI"; read -r value || value=''; [ -n "$value" ] && REALITY_SNI="$value"
    else REALITY_PORT=''; fi
    if is_protocol_enabled hy2; then
        HY2_PORT="$(prompt_port 'Hysteria2 UDP 端口' "$DEFAULT_HY2_PORT" "$HY2_PORT")"
        printf '\nHysteria2 证书：\n  1) 自签名证书（无需域名）\n  2) 自动申请域名证书\n  3) 自动申请 IP 证书\n请选择（回车使用默认 1）：'
        read -r cert_choice || cert_choice=1
        case "$cert_choice" in
            1|'') CERT_MODE=self ;;
            2) CERT_MODE=domain; printf '证书域名：'; read -r CERT_DOMAIN; printf 'ACME 账户邮箱（可留空）：'; read -r CERT_EMAIL || CERT_EMAIL=''; CERT_HTTP_PORT="$(prompt_port 'HTTP 验证端口' "$DEFAULT_ACME_HTTP_PORT" "$CERT_HTTP_PORT")" ;;
            3) CERT_MODE=ip; printf 'ACME 账户邮箱（可留空）：'; read -r CERT_EMAIL || CERT_EMAIL=''; CERT_HTTP_PORT="$(prompt_port 'HTTP 验证端口' "$DEFAULT_ACME_HTTP_PORT" "$CERT_HTTP_PORT")" ;;
            *) die '无效证书选项。' ;;
        esac
    else HY2_PORT=''; CERT_MODE=self; CERT_DOMAIN=''; CERT_EMAIL=''; fi
}
prepare_install() {
    [ "$(id -u)" -eq 0 ] || die '安装请使用 root 运行。'
    if is_protocol_enabled reality; then validate_port "$REALITY_PORT" 'Reality TCP 端口'; fi
    if is_protocol_enabled hy2; then validate_port "$HY2_PORT" 'Hysteria2 UDP 端口'; fi
    if is_protocol_enabled reality && is_protocol_enabled hy2 && [ "$REALITY_PORT" = "$HY2_PORT" ]; then die 'Reality TCP 和 Hysteria2 UDP 不能使用同一个端口。'; fi
    if [ "$CERT_MODE" = domain ]; then validate_domain "$CERT_DOMAIN" || die "证书域名格式无效：$CERT_DOMAIN"; fi
    install_base_packages; install_sing_box; SING_BOX="$(command -v sing-box)"; SING_BOX_PATH="$SING_BOX"
    PUBLIC_IP="${PUBLIC_IP:-$(get_public_ip)}"; [ -n "$PUBLIC_IP" ] || die '无法获取公网 IPv4，请设置 PUBLIC_IP 后重试。'
    get_node_region; HY2_HOST="$PUBLIC_IP"
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
    if is_protocol_enabled reality; then CONFIG_SCOPE=reality; write_config "$REALITY_CONFIG_FILE"; else rm -f "$REALITY_CONFIG_FILE"; fi
    if is_protocol_enabled hy2; then CONFIG_SCOPE=hy2; write_config "$HY2_CONFIG_FILE"; else rm -f "$HY2_CONFIG_FILE"; fi
    CONFIG_SCOPE=all
    "$SING_BOX" check -c "$CONFIG_FILE" >/dev/null || die "配置校验失败：$CONFIG_FILE"
    if is_protocol_enabled reality; then "$SING_BOX" check -c "$REALITY_CONFIG_FILE" >/dev/null || die 'Reality 配置校验失败。'; fi
    if is_protocol_enabled hy2; then "$SING_BOX" check -c "$HY2_CONFIG_FILE" >/dev/null || die 'Hysteria2 配置校验失败。'; fi
    write_client_files; write_services; write_state
    source_path="$(current_script_path)"; [ -n "$source_path" ] && install_shortcut "$source_path" || true
    view_nodes
    printf '\n\033[1;32m安装完成\033[0m\n'
    log '快捷菜单：singbox（或 ./singbox）'
    firewall_hint=''
    if is_protocol_enabled reality; then firewall_hint="放行 Reality TCP $REALITY_PORT"; fi
    if is_protocol_enabled hy2; then
        [ -n "$firewall_hint" ] && firewall_hint="$firewall_hint，"
        firewall_hint="${firewall_hint}放行 Hysteria2 UDP $HY2_PORT"
    fi
    [ -n "$firewall_hint" ] && log "请$firewall_hint。"
}
upgrade_all() { upgrade_sing_box; upgrade_script; }
show_menu() {
    while :; do
        clear_screen
        printf '\033[1;36m╔══════════════════════════════════════════════╗\033[0m\n'
        printf '\033[1;36m║\033[0m       \033[1;32msing-box-lite\033[0m  \033[1;33mv%s\033[0m              \033[1;36m║\033[0m\n' "$SCRIPT_VERSION"
        printf '\033[1;36m╠══════════════════════════════════════════════╣\033[0m\n'
        printf '\033[1;36m║\033[0m  1) 一键快捷安装（Reality + Hy2）          \033[1;36m║\033[0m\n'
        printf '\033[1;36m║\033[0m  2) 自定义安装（仅 Reality / 仅 Hy2）      \033[1;36m║\033[0m\n'
        printf '\033[1;36m║\033[0m  3) 状态查询及管理                         \033[1;36m║\033[0m\n'
        printf '\033[1;36m║\033[0m  4) 节点信息                               \033[1;36m║\033[0m\n'
        printf '\033[1;36m║\033[0m  5) 升级脚本与 singbox                     \033[1;36m║\033[0m\n'
        printf '\033[1;36m║\033[0m  6) 完全卸载                               \033[1;36m║\033[0m\n'
        printf '\033[1;36m║\033[0m  0) 退出                                   \033[1;36m║\033[0m\n'
        printf '\033[1;36m╚══════════════════════════════════════════════╝\033[0m\n'
        printf '请选择操作：'
        read -r choice || exit 0
        case "$choice" in
            1) INSTALL_MODE=both; REALITY_PORT=''; HY2_PORT=''; CERT_MODE=self; prepare_install; pause ;;
            2) prompt_install_options; prepare_install; pause ;;
            3) manage_services ;;
            4) view_nodes; pause ;;
            5) upgrade_all; pause ;;
            6) uninstall_singbox; pause ;;
            0) exit 0 ;;
            *) warn '无效选项。'; pause ;;
        esac
    done
}

OS_ID=''; OS_LIKE=''
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"; OS_LIKE="${ID_LIKE:-}"
fi

if [ "${1:-}" = '--version' ] || [ "${1:-}" = '-v' ]; then
    printf 'sing-box-lite %s\n' "$SCRIPT_VERSION"; exit 0
fi
case "${1:-}" in
    install)
        shift
        case "${1:-}" in
            both|reality|hy2) INSTALL_MODE="$1"; shift ;;
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
        prepare_install ;;
    uninstall|remove) uninstall_singbox ;;
    nodes|node|view|show) view_nodes ;;
    status|state|check) show_status ;;
    manage|service) manage_services ;;
    upgrade|update) upgrade_all ;;
    '') show_menu ;;
    *[!0-9]*) die "用法：$0 [install [both|reality|hy2] [Reality端口] [Hy2端口] | status | manage | nodes | upgrade | uninstall]" ;;
    *) INSTALL_MODE=both; REALITY_PORT="$1"; HY2_PORT="${2:-}"; prepare_install ;;
esac

