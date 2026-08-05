# sing-box-lite

一个面向 **64MB / 128MB 小内存 VPS** 的极简 sing-box 安装脚本，自动配置：

- **VLESS + Reality**：TCP
- **Hysteria2**：UDP

脚本只需要询问监听端口，其余参数会自动生成或检测。

> 适合个人测试、小型 VPS 和低内存环境。脚本不会安装面板、数据库、Docker、DNS、TUN 或统计服务，但最终内存占用仍取决于操作系统和 VPS 上运行的其他服务。

## 功能

- 自动获取公网 IPv4 地址
- 自动生成 UUID、Reality 密钥对、Short ID 和 Hysteria2 密码
- 使用同一个数字端口同时监听 TCP 和 UDP
- Hysteria2 默认使用轻量 ECDSA 自签名证书，不需要域名或 ACME
- 自动识别并适配：
  - Debian / Ubuntu
  - Alpine Linux
  - Alibaba Cloud Linux / RHEL 系
- 自动创建 systemd 或 OpenRC 服务
- 生成 sing-box 客户端出站模板和 VLESS / Hysteria2 导入链接
- 重复执行时自动备份旧配置
- 每次运行自动检查 GitHub 最新脚本版本，发现新版本后自动覆盖并重新执行
- 自动更新前会备份旧脚本

## 支持环境

脚本面向 Linux VPS，需要 root 权限和可用的包管理器。推荐使用：

- Debian 或 Ubuntu 最小化系统
- Alpine Linux
- Alibaba Cloud Linux

建议 64MB 机器关闭不必要的 Web 面板、Docker、监控和日志服务，并预留少量磁盘交换空间。

## 快速开始

### 方式一：克隆仓库

```sh
git clone https://github.com/yanjie233/sing-box-lite.git
cd sing-box-lite
chmod +x install-singbox-lite.sh
./install-singbox-lite.sh
```

### （推荐）方式二：下载脚本

```sh
curl -fsSL https://raw.githubusercontent.com/yanjie233/sing-box-lite/main/install-singbox-lite.sh -o install-singbox-lite.sh
chmod +x install-singbox-lite.sh
./install-singbox-lite.sh
```

脚本只会询问一次端口：

```text
请输入监听端口（TCP+UDP，例如 443）：
```

也可以直接传入端口，跳过交互：

```sh
sudo ./install-singbox-lite.sh 443
```

## 版本与自动更新

当前脚本版本：`1.1.0`

查看版本：

```sh
./install-singbox-lite.sh --version
```

脚本在安装开始前会检查 GitHub 上的最新 `install-singbox-lite.sh`。如果远程版本号高于本地版本号，脚本会：

1. 备份当前脚本，例如 `install-singbox-lite.sh.bak.1.0.0`
2. 下载并覆盖当前脚本
3. 使用原有参数重新执行安装流程

如果脚本是通过管道执行，或当前文件不可写，则会跳过自动更新。也可以手动关闭更新：

```sh
SINGBOX_LITE_SKIP_UPDATE=1 sudo -E ./install-singbox-lite.sh 443
```

如果你把脚本复制到了自己的仓库，可以覆盖更新地址：

```sh
REMOTE_SCRIPT_URL=https://raw.githubusercontent.com/你的用户名/你的仓库/main/install-singbox-lite.sh \
  sudo -E ./install-singbox-lite.sh 443
```

更新失败不会中断安装，脚本会继续使用当前版本。

## 安全组和防火墙

安装完成后，请在云厂商安全组和服务器防火墙中放行同一个端口的两种协议：

| 协议 | 用途 |
| --- | --- |
| TCP | VLESS Reality |
| UDP | Hysteria2 |

例如使用 `443` 时，需要放行：

```text
TCP 443
UDP 443
```

脚本不会替你修改云厂商安全组规则。如果服务器位于 NAT 后，请确认自动检测出的地址确实是客户端可访问的公网地址。

## 安装后的文件

| 文件 | 说明 |
| --- | --- |
| `/etc/sing-box/config.json` | 服务端主配置 |
| `/etc/sing-box/clients/reality.json` | Reality 客户端出站模板 |
| `/etc/sing-box/clients/hysteria2.json` | Hysteria2 客户端出站模板 |
| `/etc/sing-box/clients/links.txt` | VLESS Reality 和 Hysteria2 导入链接 |
| `/etc/sing-box/install-info.txt` | 安装信息和服务管理提示 |
| `/etc/sing-box/server.crt` | Hysteria2 自签名证书 |
| `/etc/sing-box/server.key` | Hysteria2 私钥 |

客户端凭据属于敏感信息，脚本会将相关文件设置为仅 root 可读。请不要把 `links.txt` 提交到公开仓库或发送给不可信的人。

## 客户端说明

### VLESS Reality

脚本生成的链接包含：

- 服务器地址和端口
- UUID
- Reality 公钥
- Short ID
- SNI / 握手站点
- `xtls-rprx-vision` 流控

将 `/etc/sing-box/clients/links.txt` 中的 VLESS 链接导入支持 Reality 的客户端即可。

### Hysteria2

脚本默认生成自签名证书，因此 Hysteria2 链接包含：

```text
insecure=1
```

这表示客户端不校验证书。它便于无需域名快速部署，但安全性不如受信任证书。生产环境建议使用域名和正规 CA 证书，并相应修改服务端 TLS 配置。

## 服务管理

### systemd

```sh
systemctl status sing-box
systemctl restart sing-box
journalctl -u sing-box -e --no-pager
```

### OpenRC / Alpine

```sh
rc-service sing-box status
rc-service sing-box restart
tail -f /var/log/sing-box.log
```

## 常见问题

### 1. 服务启动失败

先检查配置：

```sh
sing-box check -c /etc/sing-box/config.json
```

再查看日志：

```sh
journalctl -u sing-box -e --no-pager
```

Alpine / OpenRC 使用：

```sh
tail -n 100 /var/log/sing-box.log
tail -n 100 /var/log/sing-box.err
```

### 2. 客户端无法连接

按以下顺序检查：

1. 云安全组是否同时放行 TCP 和 UDP 端口
2. VPS 本机防火墙是否放行端口
3. 客户端地址是否为公网地址
4. Reality 的 SNI、公钥和 Short ID 是否来自同一次安装
5. Hysteria2 客户端是否启用了 `insecure=1`
6. 端口是否已被其他服务占用

### 3. 重跑脚本后旧链接失效

这是正常行为。脚本重跑会备份旧配置，并重新生成 UUID、密钥和密码。旧配置备份文件类似：

```text
/etc/sing-box/config.json.bak.20260805-120000
```

如不需要更换凭据，请不要重复执行安装脚本。

## 可选环境变量

脚本默认只询问端口；在特殊网络环境下，可以在执行前覆盖自动检测值：

```sh
PUBLIC_IP=203.0.113.10 NODE_REGION_CODE=HK NODE_REGION_EMOJI=🇭🇰 sudo -E ./install-singbox-lite.sh 443
```

通常不需要设置这些变量。

## 节点链接格式

脚本会将公网 IP 的地区信息用于生成节点名称。默认格式为：

```text
地区 Emoji-地区缩写-Vless
地区 Emoji-地区缩写-Hy2
```

例如香港服务器会生成类似下面的链接：

```text
vless://UUID@SERVER:443/?...#🇭🇰-HK-Vless
hysteria2://PASSWORD@SERVER:443/?...#🇭🇰-HK-Hy2
```

实际完整链接会保存在：

```text
/etc/sing-box/clients/links.txt
```

如果地区接口不可用，脚本会使用 `🌐-XX` 作为兜底名称。也可以手动指定地区，避免自动识别：

```sh
NODE_REGION_CODE=HK NODE_REGION_EMOJI=🇭🇰 sudo -E ./install-singbox-lite.sh 443
```

其中 `NODE_REGION_CODE` 建议使用两位地区缩写，例如 `HK`、`US`、`JP`、`SG`；`NODE_REGION_EMOJI` 使用对应的国旗或地区 Emoji。
## 免责声明

请只在你拥有或获授权管理的服务器上使用。使用前请确认所在地法律、云服务商条款和网络运营商政策。
