#!/bin/sh
# sing-box-lite: one-port installer for VLESS-Reality + Hysteria2
# Supports Debian/Ubuntu, Alpine, and Alibaba Linux/RHEL-like systems.
# It only prompts for the port; all credentials and the server IP are generated/detected automatically.

set -eu

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
CLIENT_DIR="$CONFIG_DIR/clients"
CERT_FILE="$CONFIG_DIR/server.crt"
KEY_FILE="$CONFIG_DIR/server.key"
REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"
HY2_SNI="${HY2_SNI:-www.example.com}"
PORT="${1:-}"

log() { printf '[sing-box-lite] %s\n' "$*"; }
warn() { printf '[sing-box-lite][WARN] %s\n' "$*" >&2; }
die() { printf '[sing-box-lite][ERROR] %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "请使用 root 运行。"

if [ -z "$PORT" ]; then
    printf '请输入监听端口（TCP+UDP，例如 443）：'
    read -r PORT
fi

case "$PORT" in
    ''|*[!0-9]*) die "端口必须是 1-65535 的数字。" ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "端口必须是 1-65535。"

# Read distro information without requiring lsb_release.
OS_ID=""
OS_LIKE=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
fi

have() { command -v "$1" >/dev/null 2>&1; }

install_base_packages() {
    case "$OS_ID" in
        alpine)
            have apk || die "未找到 apk。"
            apk add --no-cache ca-certificates curl openssl >/dev/null
            update-ca-certificates >/dev/null 2>&1 || true
            ;;
        debian|ubuntu|linuxmint|raspbian)
            have apt-get || die "未找到 apt-get。"
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl openssl >/dev/null
            rm -rf /var/lib/apt/lists/*
            ;;
        *)
            if have dnf; then
                dnf install -y ca-certificates curl openssl >/dev/null
            elif have yum; then
                yum install -y ca-certificates curl openssl >/dev/null
            else
                die "不支持的发行版：ID=$OS_ID ID_LIKE=$OS_LIKE"
            fi
            ;;
    esac
}

install_sing_box() {
    if have sing-box; then
        log "检测到已有 sing-box：$(sing-box version | head -n 1)"
        return
    fi

    case "$OS_ID" in
        alpine)
            log "通过 Alpine APK 安装 sing-box。"
            apk add --no-cache sing-box >/dev/null || die "apk 安装 sing-box 失败。"
            ;;
        debian|ubuntu|linuxmint|raspbian|alinux|alibabacloudlinux|centos|rhel|rocky|almalinux|fedora)
            log "通过 sing-box 官方安装器安装。"
            tmp_install="$(mktemp)"
            curl -fsSL https://sing-box.app/install.sh -o "$tmp_install"
            sh "$tmp_install"
            rm -f "$tmp_install"
            ;;
        *)
            case "$OS_LIKE" in
                *debian*|*rhel*|*fedora*)
                    tmp_install="$(mktemp)"
                    curl -fsSL https://sing-box.app/install.sh -o "$tmp_install"
                    sh "$tmp_install"
                    rm -f "$tmp_install"
                    ;;
                *) die "暂不支持此系统：ID=$OS_ID ID_LIKE=$OS_LIKE" ;;
            esac
            ;;
    esac
    have sing-box || die "sing-box 安装后仍未找到可执行文件。"
}

get_public_ip() {
    ip=""
    if have curl; then
        ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
        [ -n "$ip" ] || ip="$(curl -4fsS --max-time 5 https://ifconfig.me/ip 2>/dev/null || true)"
    fi
    if [ -z "$ip" ] && have ip; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i==\"src\") {print $(i+1); exit}}')"
    fi
    if [ -z "$ip" ] && have hostname; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    printf '%s' "$ip"
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
install_sing_box
SING_BOX="$(command -v sing-box)"

PUBLIC_IP="${PUBLIC_IP:-$(get_public_ip)}"
[ -n "$PUBLIC_IP" ] || die "无法自动获取公网 IPv4，请检查网络后重试。"

mkdir -p "$CONFIG_DIR" "$CLIENT_DIR" /var/lib/sing-box
chmod 700 "$CONFIG_DIR" "$CLIENT_DIR"

if [ -f "$CONFIG_FILE" ]; then
    backup="$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$CONFIG_FILE" "$backup"
    warn "已备份旧配置：$backup"
fi

UUID="$(make_uuid)"
HY2_PASSWORD="$(openssl rand -hex 24)"
SHORT_ID="$(openssl rand -hex 8)"

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
      "listen_port": $PORT,
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
          "short_id": "$SHORT_ID"
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
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
      "server_port": $PORT,
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_SNI",
        "reality": {
          "enabled": true,
          "public_key": "$REALITY_PUBLIC_KEY",
          "short_id": "$SHORT_ID"
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
      "server_port": $PORT,
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

REALITY_LINK="vless://${UUID}@${URL_HOST}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&pbk=${REALITY_PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#sing-box-Reality"
HY2_LINK="hysteria2://${HY2_PASSWORD}@${URL_HOST}:${PORT}/?insecure=1&sni=${HY2_SNI}#sing-box-Hysteria2"

cat > "$CLIENT_DIR/links.txt" <<EOF
# VLESS Reality
$REALITY_LINK

# Hysteria2（自签名证书，客户端必须允许 insecure）
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

服务器 IPv4: $PUBLIC_IP
监听端口: $PORT/TCP + $PORT/UDP
Reality SNI/握手站点: $REALITY_SNI
Hysteria2 SNI: $HY2_SNI（自签名证书）
服务管理: $SERVICE_STATUS

客户端文件:
- $CLIENT_DIR/reality.json
- $CLIENT_DIR/hysteria2.json
- $CLIENT_DIR/links.txt

云厂商安全组/防火墙必须放行:
- TCP $PORT（Reality）
- UDP $PORT（Hysteria2）

注意:
- 本脚本不申请域名、不申请 ACME 证书；Hysteria2 使用自签名证书并要求客户端 insecure=1。
- 重跑脚本会备份旧配置并生成新凭据，旧客户端将失效。
- 如服务器位于 NAT 后，客户端地址不能使用脚本检测到的内网地址，需改为公网映射地址。
EOF
chmod 600 "$CONFIG_DIR/install-info.txt"

log "安装完成。"
log "客户端链接和 JSON：$CLIENT_DIR"
log "请确认云安全组放行 TCP $PORT 和 UDP $PORT。"
