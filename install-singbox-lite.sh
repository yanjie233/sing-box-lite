#!/bin/sh
# sing-box-lite: one-port installer for VLESS-Reality + Hysteria2
SCRIPT_VERSION="2.0.1"
REMOTE_SCRIPT_URL="${REMOTE_SCRIPT_URL:-https://raw.githubusercontent.com/yanjie233/sing-box-lite/main/install-singbox-lite.sh}"
# Supports Debian/Ubuntu, Alpine, and Alibaba Linux/RHEL-like systems.
# It only prompts for the port; all credentials and the server IP are generated/detected automatically.

set -eu

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
CLIENT_DIR="$CONFIG_DIR/clients"
CERT_FILE="$CONFIG_DIR/server.crt"
KEY_FILE="$CONFIG_DIR/server.key"
REALITY_SNI="${REALITY_SNI:-www.cloudflare.com}"
HY2_SNI="${HY2_SNI:-www.example.com}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-firefox}"
NODE_REGION_CODE="${NODE_REGION_CODE:-}"
NODE_REGION_EMOJI="${NODE_REGION_EMOJI:-}"
REALITY_PORT=""
HY2_PORT=""
DEFAULT_REALITY_PORT="55667"
DEFAULT_HY2_PORT="55668"
ACTION=""

log() { printf '[sing-box-lite] %s\n' "$*"; }
warn() { printf '[sing-box-lite][WARN] %s\n' "$*" >&2; }
die() { printf '[sing-box-lite][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

download_file() {
    url="$1"
    destination="$2"
    if have curl; then
        curl -4fsSL --max-time 30 "$url" -o "$destination"
    elif have wget; then
        wget -q --timeout=30 -O "$destination" "$url"
    else
        return 1
    fi
}

show_menu() {
    printf '\n\033[1;36m╔══════════════════════════════════════════════╗\033[0m\n'
    printf '\033[1;36m║\033[0m       \033[1;32msing-box-lite\033[0m  \033[1;33mv%s\033[0m              \033[1;36m║\033[0m\n' "$SCRIPT_VERSION"
    printf '\033[1;36m╠══════════════════════════════════════════════╣\033[0m\n'
    printf '\033[1;36m║\033[0m  1) 安装 / 更新                         \033[1;36m║\033[0m\n'
    printf '\033[1;36m║\033[0m  2) 卸载                                 \033[1;36m║\033[0m\n'
    printf '\033[1;36m║\033[0m  3) 查看节点                             \033[1;36m║\033[0m\n'
    printf '\033[1;36m║\033[0m  4) 运行状态查询                         \033[1;36m║\033[0m\n'
    printf '\033[1;36m║\033[0m  5) 状态管理（关闭 / 重启 / 开启）       \033[1;36m║\033[0m\n'
    printf '\033[1;36m║\033[0m  0) 退出                                 \033[1;36m║\033[0m\n'
    printf '\033[1;36m╚══════════════════════════════════════════════╝\033[0m\n'
    printf '请选择操作：'
    read -r menu_choice
    case "$menu_choice" in
        1) ACTION="install" ;;
        2) ACTION="uninstall" ;;
        3) ACTION="nodes" ;;
        4) ACTION="status" ;;
        5) ACTION="manage" ;;
        0) exit 0 ;;
        *) die "无效选项。" ;;
    esac
}

service_status() {
    if have systemctl; then
        systemctl is-active sing-box 2>/dev/null || true
    elif have rc-service; then
        rc-service sing-box status >/dev/null 2>&1 && printf 'started' || printf 'stopped'
    else
        printf 'unknown'
    fi
}

show_status() {
    [ "$(id -u)" -eq 0 ] || die "查询状态请使用 root 运行。"
    printf '\n\033[1;36m==== sing-box-lite 运行状态 ====\033[0m\n'
    if have systemctl; then
        systemctl status sing-box --no-pager -l || true
    elif have rc-service; then
        rc-service sing-box status || true
    else
        warn "未检测到 systemd 或 OpenRC。"
    fi
    if have ss; then
        printf '\n监听端口：\n'
        ss -lntup 2>/dev/null | grep -E 'sing-box|LISTEN' || true
    fi
    [ -f "$CONFIG_DIR/install-info.txt" ] && {
        printf '\n安装信息：\n'
        sed -n '1,18p' "$CONFIG_DIR/install-info.txt"
    }
}

manage_service() {
    [ "$(id -u)" -eq 0 ] || die "管理服务请使用 root 运行。"
    printf '\n\033[1;36m==== 状态管理 ====\033[0m\n'
    printf '1) 关闭服务\n2) 重启服务\n3) 开启服务\n0) 返回\n请选择操作：'
    read -r service_choice
    case "$service_choice" in
        0) return 0 ;;
        1) service_action="stop" ;;
        2) service_action="restart" ;;
        3) service_action="start" ;;
        *) die "无效选项。" ;;
    esac
    if have systemctl; then
        systemctl "$service_action" sing-box
        [ "$service_action" = "start" ] && systemctl enable sing-box >/dev/null 2>&1 || true
    elif have rc-service; then
        rc-service sing-box "$service_action"
        [ "$service_action" = "start" ] && rc-update add sing-box default >/dev/null 2>&1 || true
    else
        die "未检测到 systemd 或 OpenRC。"
    fi
    printf '\n当前状态：%s\n' "$(service_status)"
}


view_nodes() {
    [ "$(id -u)" -eq 0 ] || die "查看节点请使用 root 运行。"
    if [ -f "$CLIENT_DIR/links.txt" ]; then
        printf '\n==== 节点链接 ====\n'
        cat "$CLIENT_DIR/links.txt"
        printf '\n节点文件目录：%s\n' "$CLIENT_DIR"
    else
        die "未找到节点文件：$CLIENT_DIR/links.txt。请先安装。"
    fi
}

uninstall_singbox() {
    [ "$(id -u)" -eq 0 ] || die "卸载请使用 root 运行。"
    printf '此操作将停止服务并删除 sing-box 配置、证书、节点链接和本地二进制。输入 yes 确认：'
    read -r confirm
    [ "$confirm" = "yes" ] || { log "已取消卸载。"; return 0; }

    if have systemctl; then
        systemctl disable --now sing-box >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if have rc-service; then
        rc-service sing-box stop >/dev/null 2>&1 || true
        rc-update del sing-box default >/dev/null 2>&1 || true
        rm -f /etc/init.d/sing-box
    fi

    if [ -x /usr/local/bin/sing-box ]; then
        rm -f /usr/local/bin/sing-box
    elif [ -x /usr/bin/sing-box ] && [ -r /etc/os-release ]; then
        # Remove a package-managed binary through its package manager instead of
        # deleting the file directly and leaving a broken package database.
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
            alpine)
                apk del sing-box >/dev/null 2>&1 || warn "未能通过 apk 删除 sing-box，请手动执行：apk del sing-box"
                ;;
            debian|ubuntu|linuxmint|raspbian)
                export DEBIAN_FRONTEND=noninteractive
                apt-get remove -y -qq sing-box >/dev/null 2>&1 || warn "未能通过 apt 删除 sing-box，请手动执行：apt-get remove sing-box"
                ;;
            alinux|alibabacloudlinux|centos|rhel|rocky|almalinux|fedora)
                if have dnf; then
                    dnf remove -y sing-box >/dev/null 2>&1 || warn "未能通过 dnf 删除 sing-box。"
                elif have yum; then
                    yum remove -y sing-box >/dev/null 2>&1 || warn "未能通过 yum 删除 sing-box。"
                fi
                ;;
            *) warn "检测到 /usr/bin/sing-box，但无法判断包管理器；请手动卸载该二进制。" ;;
        esac
    fi
    rm -rf "$CONFIG_DIR" /var/lib/sing-box
    log "卸载完成。未删除 curl、wget、openssl、tar 等系统依赖。"
}

if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    printf 'sing-box-lite %s\n' "$SCRIPT_VERSION"
    exit 0
fi

case "${1:-}" in
    install)
        ACTION="install"
        shift
        REALITY_PORT="${1:-}"
        HY2_PORT="${2:-}"
        ;;
    uninstall|remove)
        ACTION="uninstall"
        ;;
    nodes|node|view|show)
        ACTION="nodes"
        ;;
    status|state|check)
        ACTION="status"
        ;;
    manage|service)
        ACTION="manage"
        ;;
    '')
        show_menu
        ;;
    *[!0-9]*)
        die "用法：$0 [install [Reality端口] [Hy2端口] | uninstall | nodes | --version]"
        ;;
    *)
        # Backward compatibility: ./install-singbox-lite.sh 443
        ACTION="install"
        REALITY_PORT="$1"
        HY2_PORT="${2:-}"
        ;;
esac

if [ "$ACTION" = "uninstall" ]; then
    uninstall_singbox
    exit 0
fi
if [ "$ACTION" = "nodes" ]; then
    view_nodes
    exit 0
fi
if [ "$ACTION" = "status" ]; then
    show_status
    exit 0
fi
if [ "$ACTION" = "manage" ]; then
    manage_service
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "安装请使用 root 运行。"

if [ -z "$REALITY_PORT" ]; then
    printf '请输入 Reality TCP 监听端口（默认 %s，直接回车使用默认）：' "$DEFAULT_REALITY_PORT"
    read -r REALITY_PORT
    [ -n "$REALITY_PORT" ] || REALITY_PORT="$DEFAULT_REALITY_PORT"
fi
if [ -z "$HY2_PORT" ]; then
    printf '请输入 Hysteria2 UDP 监听端口（默认 %s，直接回车使用默认）：' "$DEFAULT_HY2_PORT"
    read -r HY2_PORT
    [ -n "$HY2_PORT" ] || HY2_PORT="$DEFAULT_HY2_PORT"
fi
if [ -z "${REALITY_SNI_INPUT:-}" ]; then
    printf '请输入 Reality 自定义域名（直接回车使用默认 www.cloudflare.com）：'
    read -r REALITY_SNI_INPUT
fi
if [ -n "$REALITY_SNI_INPUT" ]; then
    REALITY_SNI="$REALITY_SNI_INPUT"
fi

validate_domain() {
    domain="$1"
    case "$domain" in
        ''|*[!A-Za-z0-9.-]*) die "Reality 域名格式无效：$domain" ;;
        .*|*.|*..*) die "Reality 域名格式无效：$domain" ;;
    esac
}
validate_domain "$REALITY_SNI"

validate_port() {
    port="$1"
    label="$2"
    case "$port" in
        ''|*[!0-9]*) die "$label 必须是 1-65535 的数字。" ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "$label 必须是 1-65535。"
}
validate_port "$REALITY_PORT" "Reality TCP 端口"
validate_port "$HY2_PORT" "Hysteria2 UDP 端口"
[ "$REALITY_PORT" != "$HY2_PORT" ] || die "Reality TCP 和 Hysteria2 UDP 不能使用同一个端口，请重新输入。"

# Read distro information without requiring lsb_release.
OS_ID=""
OS_LIKE=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
fi

install_base_packages() {
    case "$OS_ID" in
        alpine)
            have apk || warn "未找到 apk，将尝试从 GitHub 下载 sing-box。"
            if have apk && ! apk add --no-cache ca-certificates curl openssl tar >/dev/null; then
                warn "Alpine 软件源请求或安装依赖失败，将尝试从 GitHub 下载 sing-box。"
            fi
            update-ca-certificates >/dev/null 2>&1 || true
            ;;
        debian|ubuntu|linuxmint|raspbian)
            have apt-get || warn "未找到 apt-get，将尝试从 GitHub 下载 sing-box。"
            export DEBIAN_FRONTEND=noninteractive
            if have apt-get && ! (apt-get update -qq && apt-get install -y -qq ca-certificates curl openssl tar >/dev/null); then
                warn "Debian 软件源请求或安装依赖失败，将尝试从 GitHub 下载 sing-box。"
            fi
            rm -rf /var/lib/apt/lists/*
            ;;
        *)
            if have dnf; then
                dnf install -y ca-certificates curl openssl tar >/dev/null || warn "dnf 安装依赖失败，将尝试从 GitHub 下载 sing-box。"
            elif have yum; then
                yum install -y ca-certificates curl openssl tar >/dev/null || warn "yum 安装依赖失败，将尝试从 GitHub 下载 sing-box。"
            else
                warn "未找到可用的软件包管理器，将尝试从 GitHub 下载 sing-box。"
            fi
            ;;
    esac

    have openssl || die "缺少 openssl，无法生成 UUID、证书和密钥。请先手动安装 openssl。"
    if ! have curl && ! have wget; then
        die "缺少 curl 或 wget，无法从 GitHub 下载文件。请先安装其中一个。"
    fi
    have tar || die "缺少 tar，无法解压 GitHub 发布包。请先手动安装 tar。"
}

install_sing_box_from_github() {
    log "从 GitHub Releases 下载 sing-box。"
    release_json="$(mktemp)"
    if ! download_file "https://api.github.com/repos/SagerNet/sing-box/releases/latest" "$release_json"; then
        rm -f "$release_json"
        die "无法访问 GitHub Releases，也没有可用的 sing-box 安装包。"
    fi

    tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_json" | head -n 1)"
    rm -f "$release_json"
    [ -n "$tag" ] || die "无法从 GitHub Releases 获取 sing-box 版本。"
    version="${tag#v}"

    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armv7) arch="armv7" ;;
        armv6l) arch="armv6" ;;
        armv5l) arch="armv5" ;;
        i386|i686) arch="386" ;;
        ppc64le) arch="ppc64le" ;;
        riscv64) arch="riscv64" ;;
        s390x) arch="s390x" ;;
        *) die "GitHub 发布包暂不支持当前架构：$(uname -m)" ;;
    esac

    libc="glibc"
    if [ "$OS_ID" = "alpine" ] || (have ldd && ldd --version 2>&1 | grep -qi musl); then
        libc="musl"
    fi
    asset="sing-box-${version}-linux-${arch}-${libc}.tar.gz"
    url="https://github.com/SagerNet/sing-box/releases/download/${tag}/${asset}"
    archive="$(mktemp)"
    if ! download_file "$url" "$archive"; then
        # Some architectures only publish the generic archive.
        fallback_asset="sing-box-${version}-linux-${arch}.tar.gz"
        fallback_url="https://github.com/SagerNet/sing-box/releases/download/${tag}/${fallback_asset}"
        warn "未找到 $asset，尝试通用包 $fallback_asset。"
        if ! download_file "$fallback_url" "$archive"; then
            rm -f "$archive"
            die "无法下载 sing-box：$asset"
        fi
    fi

    extract_dir="$(mktemp -d)"
    if ! tar -xzf "$archive" -C "$extract_dir"; then
        rm -f "$archive"
        rm -rf "$extract_dir"
        die "sing-box 发布包解压失败。"
    fi
    rm -f "$archive"
    binary="$(find "$extract_dir" -type f -name sing-box -perm -u+x | head -n 1)"
    [ -n "$binary" ] || binary="$(find "$extract_dir" -type f -name sing-box | head -n 1)"
    [ -n "$binary" ] || { rm -rf "$extract_dir"; die "发布包中未找到 sing-box 可执行文件。"; }
    mkdir -p /usr/local/bin
    cp "$binary" /usr/local/bin/sing-box
    chmod 755 /usr/local/bin/sing-box
    rm -rf "$extract_dir"
}

install_sing_box() {
    if have sing-box; then
        log "检测到已有 sing-box：$(sing-box version | head -n 1)"
        return
    fi

    package_ok=0
    case "$OS_ID" in
        alpine)
            if have apk && apk add --no-cache sing-box >/dev/null 2>&1; then
                package_ok=1
            else
                warn "Alpine APK 安装失败，切换到 GitHub Releases。"
            fi
            ;;
        debian|ubuntu|linuxmint|raspbian|alinux|alibabacloudlinux|centos|rhel|rocky|almalinux|fedora)
            tmp_install="$(mktemp)"
            if download_file "https://sing-box.app/install.sh" "$tmp_install" && sh "$tmp_install"; then
                package_ok=1
            else
                warn "官方安装器请求或执行失败，切换到 GitHub Releases。"
            fi
            rm -f "$tmp_install"
            ;;
        *)
            warn "当前发行版未匹配官方安装方式，切换到 GitHub Releases。"
            ;;
    esac

    if [ "$package_ok" -ne 1 ] || ! have sing-box; then
        install_sing_box_from_github
    fi
    have sing-box || die "sing-box 安装后仍未找到可执行文件。"
}

get_public_ip() {
    ip=""
    if have curl; then
        ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ip" ] || ip="$(curl -4fsS --max-time 5 https://ifconfig.me/ip 2>/dev/null || true)"
    elif have wget; then
        ip="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ip" ] || ip="$(wget -qO- --timeout=5 https://ifconfig.me/ip 2>/dev/null || true)"
    fi
    if [ -z "$ip" ] && have ip; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i==\"src\") {print $(i+1); exit}}')"
    fi
    if [ -z "$ip" ] && have hostname; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    printf '%s' "$ip"
}


version_gt() {
    awk -v a="$1" -v b="$2" '
        function part(v, n, x) { split(v, x, "."); return x[n] + 0 }
        BEGIN {
            for (i = 1; i <= 3; i++) {
                ai = part(a, i)
                bi = part(b, i)
                if (ai > bi) exit 0
                if (ai < bi) exit 1
            }
            exit 1
        }
    '
}

self_update() {
    [ "${SINGBOX_LITE_SKIP_UPDATE:-0}" = "1" ] && return 0
    [ "${SINGBOX_LITE_UPDATE_DONE:-0}" = "1" ] && return 0
    if ! have curl && ! have wget; then
        return 0
    fi

    self_path="$0"
    case "$self_path" in
        /dev/*|/proc/*|/sys/*)
            warn "当前脚本来自管道或临时文件，跳过自动更新。"
            return 0
            ;;
    esac
    [ -f "$self_path" ] || return 0
    [ -w "$self_path" ] || {
        warn "当前脚本不可写，跳过自动更新：$self_path"
        return 0
    }

    tmp_update="$(mktemp)"
    if ! download_file "$REMOTE_SCRIPT_URL" "$tmp_update"; then
        rm -f "$tmp_update"
        warn "无法检查最新版本，继续使用当前版本 $SCRIPT_VERSION。"
        return 0
    fi

    remote_version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9.]*\)".*/\1/p' "$tmp_update" | head -n 1)"
    if [ -z "$remote_version" ] || ! printf '%s' "$remote_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        rm -f "$tmp_update"
        warn "远程脚本版本信息无效，继续使用当前版本 $SCRIPT_VERSION。"
        return 0
    fi

    if version_gt "$remote_version" "$SCRIPT_VERSION"; then
        update_backup="$self_path.bak.$SCRIPT_VERSION"
        cp -p "$self_path" "$update_backup"
        cp "$tmp_update" "$self_path"
        chmod +x "$self_path"
        rm -f "$tmp_update"
        log "发现新版本：$SCRIPT_VERSION -> $remote_version，已覆盖当前脚本并重新执行。"
        export SINGBOX_LITE_UPDATE_DONE=1
        exec sh "$self_path" install "$@"
    fi

    rm -f "$tmp_update"
}

get_node_region() {
    geo=""
    if have curl && { [ -z "$NODE_REGION_CODE" ] || [ -z "$NODE_REGION_EMOJI" ]; }; then
        # ipwho.is returns both ISO country code and flag emoji. If unavailable,
        # use ipapi.co for the code and fall back to a globe emoji.
        geo="$(curl -4fsS --max-time 5 "https://ipwho.is/${PUBLIC_IP}?fields=country_code,flag" 2>/dev/null || true)"
        [ -n "$NODE_REGION_CODE" ] || NODE_REGION_CODE="$(printf '%s' "$geo" | sed -n 's/.*"country_code"[[:space:]]*:[[:space:]]*"\([A-Za-z][A-Za-z]\)".*/\1/p' | head -n 1 | tr '[:lower:]' '[:upper:]')"
        [ -n "$NODE_REGION_EMOJI" ] || NODE_REGION_EMOJI="$(printf '%s' "$geo" | sed -n 's/.*"emoji"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    fi
    if [ -z "$NODE_REGION_CODE" ]; then
        if have curl; then
            NODE_REGION_CODE="$(curl -4fsS --max-time 5 "https://ipapi.co/${PUBLIC_IP}/country/" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]' || true)"
        elif have wget; then
            NODE_REGION_CODE="$(wget -qO- --timeout=5 "https://ipapi.co/${PUBLIC_IP}/country/" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]' || true)"
        fi
    fi
    [ -n "$NODE_REGION_CODE" ] || NODE_REGION_CODE="XX"
    [ -n "$NODE_REGION_EMOJI" ] || NODE_REGION_EMOJI="🌐"
}

make_uuid() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
        return
    fi
    h="$(openssl rand -hex 16)"
    printf '%s-%s-%s-%s-%s\n' \
        "$(printf '%s' "$h" | cut -c1-8)" \
        "$(printf '%s' "$h" | cut -c9-12)" \
        "4$(printf '%s' "$h" | cut -c14-16)" \
        "8$(printf '%s' "$h" | cut -c18-20)" \
        "$(printf '%s' "$h" | cut -c21-32)"
}

make_cert() {
    log "生成轻量 ECDSA 自签名证书（Hysteria2 客户端使用 insecure=1）。"
    openssl ecparam -name prime256v1 -genkey -noout -out "$KEY_FILE"
    openssl req -new -x509 -sha256 -key "$KEY_FILE" -out "$CERT_FILE" \
        -days 3650 -subj "/CN=$HY2_SNI" >/dev/null 2>&1
    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
}

install_base_packages
self_update "$@"
install_sing_box
SING_BOX="$(command -v sing-box)"

PUBLIC_IP="${PUBLIC_IP:-$(get_public_ip)}"
[ -n "$PUBLIC_IP" ] || die "无法自动获取公网 IPv4，请检查网络后重试。"
get_node_region
NODE_NAME_BASE="${NODE_REGION_EMOJI}${NODE_REGION_CODE}"

mkdir -p "$CONFIG_DIR" "$CLIENT_DIR" /var/lib/sing-box
chmod 700 "$CONFIG_DIR" "$CLIENT_DIR"

if [ -f "$CONFIG_FILE" ]; then
    backup="$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$CONFIG_FILE" "$backup"
    warn "已备份旧配置：$backup"
fi

UUID="$(make_uuid)"
HY2_PASSWORD="$(openssl rand -hex 24)"

KEYPAIR="$($SING_BOX generate reality-keypair)"
REALITY_PRIVATE_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F': ' '/PrivateKey/ {print $2; exit}')"
REALITY_PUBLIC_KEY="$(printf '%s\n' "$KEYPAIR" | awk -F': ' '/PublicKey/ {print $2; exit}')"
[ -n "$REALITY_PRIVATE_KEY" ] || die "Reality 私钥生成失败。"
[ -n "$REALITY_PUBLIC_KEY" ] || die "Reality 公钥生成失败。"

make_cert

cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "0.0.0.0",
      "listen_port": $REALITY_PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_SNI",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$REALITY_SNI",
            "server_port": 443
          },
          "private_key": "$REALITY_PRIVATE_KEY",
          "short_id": [""]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "0.0.0.0",
      "listen_port": $HY2_PORT,
      "users": [
        {
          "name": "default",
          "password": "$HY2_PASSWORD"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$HY2_SNI",
        "certificate_path": "$CERT_FILE",
        "key_path": "$KEY_FILE"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
chmod 600 "$CONFIG_FILE"

if printf '%s' "$PUBLIC_IP" | grep -q ':'; then
    URL_HOST="[$PUBLIC_IP]"
else
    URL_HOST="$PUBLIC_IP"
fi

cat > "$CLIENT_DIR/reality.json" <<EOF
{
  "log": { "level": "warn" },
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "$PUBLIC_IP",
      "server_port": $REALITY_PORT,
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_SNI",
        "utls": {
          "enabled": true,
          "fingerprint": "$REALITY_FINGERPRINT"
        },
        "reality": {
          "enabled": true,
          "public_key": "$REALITY_PUBLIC_KEY"
        }
      }
    }
  ]
}
EOF

cat > "$CLIENT_DIR/hysteria2.json" <<EOF
{
  "log": { "level": "warn" },
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "$PUBLIC_IP",
      "server_port": $HY2_PORT,
      "password": "$HY2_PASSWORD",
      "tls": {
        "enabled": true,
        "server_name": "$HY2_SNI",
        "insecure": true
      }
    }
  ]
}
EOF

REALITY_LINK="vless://${UUID}@${URL_HOST}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&type=tcp&headerType=none#${NODE_NAME_BASE}-Vless"
HY2_LINK="hysteria2://${HY2_PASSWORD}@${URL_HOST}:${HY2_PORT}/?insecure=1&sni=${HY2_SNI}#${NODE_NAME_BASE}-Hy2"

cat > "$CLIENT_DIR/links.txt" <<EOF
# ${NODE_NAME_BASE}-Vless
$REALITY_LINK

# ${NODE_NAME_BASE}-Hy2（自签名证书，客户端必须允许 insecure）
$HY2_LINK
EOF
chmod 600 "$CLIENT_DIR"/*.json "$CLIENT_DIR/links.txt"

# Validate before asking the service manager to start anything.
$SING_BOX check -c "$CONFIG_FILE" >/dev/null || die "配置校验失败，请检查：$CONFIG_FILE"

# Use a small, self-contained service instead of relying on package-specific defaults.
if have systemctl; then
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box minimal Reality/Hysteria2 service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SING_BOX run -c $CONFIG_FILE
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
    systemctl daemon-reload
    systemctl enable sing-box >/dev/null 2>&1 || true
    systemctl restart sing-box
    SERVICE_STATUS="systemd: systemctl status sing-box"
elif have rc-service; then
    cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
command="$SING_BOX"
command_args="run -c $CONFIG_FILE"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.err"

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default >/dev/null 2>&1 || true
    rc-service sing-box restart || rc-service sing-box start
    SERVICE_STATUS="OpenRC: rc-service sing-box"
else
    warn "未检测到 systemd/OpenRC，已生成配置但未自动启动。"
    SERVICE_STATUS="手动运行: $SING_BOX run -c $CONFIG_FILE"
fi


cat > "$CONFIG_DIR/install-info.txt" <<EOF
sing-box-lite 安装完成
脚本版本: $SCRIPT_VERSION

服务器 IPv4: $PUBLIC_IP
节点名称前缀: $NODE_NAME_BASE
Reality TCP 端口: $REALITY_PORT
Hysteria2 UDP 端口: $HY2_PORT
默认端口: Reality $DEFAULT_REALITY_PORT / Hy2 $DEFAULT_HY2_PORT
Reality SNI/握手站点: $REALITY_SNI
Reality TLS 指纹: $REALITY_FINGERPRINT
Reality Short ID: 空（兼容更多客户端）
Hysteria2 SNI: $HY2_SNI（自签名证书）
服务管理: $SERVICE_STATUS

客户端文件:
- $CLIENT_DIR/reality.json
- $CLIENT_DIR/hysteria2.json
- $CLIENT_DIR/links.txt

云厂商安全组/防火墙必须放行:
- TCP $REALITY_PORT（Reality）
- UDP $HY2_PORT（Hysteria2）

注意:
- 本脚本不申请域名、不申请 ACME 证书；Hysteria2 使用自签名证书并要求客户端 insecure=1。
- 重跑脚本会备份旧配置并生成新凭据，旧客户端将失效。
- 如服务器位于 NAT 后，客户端地址不能使用脚本检测到的内网地址，需改为公网映射地址。
- 节点名称格式：地区 Emoji地区缩写-Vless 或 地区 Emoji地区缩写-Hy2。
- Reality 使用空 Short ID，并在链接中省略 sid 参数，以兼容 Clash.Meta、Xray 等客户端。
- 如果系统软件源不可用，sing-box 会自动从 GitHub Releases 下载。
EOF
chmod 600 "$CONFIG_DIR/install-info.txt"

view_nodes

printf '
\033[1;32m╔══════════════════════════════════════════════╗\033[0m\n'
printf '\033[1;32m║              安装完成 / 节点已生成           ║\033[0m\n'
printf '\033[1;32m╚══════════════════════════════════════════════╝\033[0m\n'
log "客户端文件目录：$CLIENT_DIR"
log "请放行 TCP $REALITY_PORT 和 UDP $HY2_PORT。"
