# sing-box-lite

一个面向 **64MB / 128MB 小内存 VPS** 的极简 sing-box 安装脚本，自动配置：

**VLESS + Reality** 和 **Hysteria2**

你只需要准备好两个可用的端口，里面就能体验畅快的网络！

## 快速开始

### Debian/Ubuntu

```sh
curl -fsSL https://raw.githubusercontent.com/yanjie233/sing-box-lite/main/install-singbox-lite.sh -o install-singbox-lite.sh
chmod +x install-singbox-lite.sh
sudo ./install-singbox-lite.sh
```
### Alpine
```sh
apk update && apk add --no-cache curl wget openssl tar
curl -fsSL https://raw.githubusercontent.com/yanjie233/sing-box-lite/main/install-singbox-lite.sh -o install-singbox-lite.sh
chmod +x install-singbox-lite.sh
./install-singbox-lite.sh
```

---

## Codex的废话

> 适合个人测试、小型 VPS 和低内存环境。脚本不会安装面板、数据库、Docker、DNS、TUN 或统计服务，但最终内存占用仍取决于操作系统和 VPS 上运行的其他服务。

## 功能

- 自动获取公网 IPv4 地址
- 自动生成 UUID、Reality 密钥对、Short ID 和 Hysteria2 密码
- Reality 默认使用空 Short ID，并在链接中省略 `sid` 参数，以兼容 Clash.Meta、Xray 等客户端
- Reality 和 Hysteria2 使用分开的端口，避免端口占用或部署环境差异造成冲突
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

脚本会分别询问两个端口（默认 Reality TCP `55667`、Hysteria2 UDP `55668`），然后询问 Reality 握手域名：

```text
请输入 Reality TCP 监听端口（默认 55667，直接回车使用默认）：
请输入 Hysteria2 UDP 监听端口（默认 55668，直接回车使用默认）：
请输入 Reality 自定义域名（直接回车使用默认 www.cloudflare.com）：
```

也可以直接传入端口，跳过交互：

```sh
sudo ./install-singbox-lite.sh 443 8443
```

第一个端口是 Reality TCP，第二个端口是 Hysteria2 UDP；两个端口可以不同。Reality 域名直接回车时使用 `www.cloudflare.com`。

## Reality 自定义域名

安装时可以为 Reality 指定握手域名：

```text
请输入 Reality 自定义域名（直接回车使用默认 www.cloudflare.com）：
```

- 直接回车：使用 `www.cloudflare.com`
- 输入域名：使用你指定的域名，例如 `www.microsoft.com`
- 该域名必须支持 TLS，并且从服务器网络可以访问
- 修改域名后会生成新的 Reality 配置和新的节点链接

命令行环境也可以通过环境变量预设：

```sh
REALITY_SNI=www.microsoft.com \
  sudo -E ./install-singbox-lite.sh install 55667 55668
```

## 菜单功能

不带参数运行脚本会显示菜单：

```text
1) 安装 / 更新
2) 卸载
3) 查看节点
4) 运行状态查询
5) 状态管理（关闭 / 重启 / 开启）
0) 退出
```

也可以直接使用命令：

```sh
# 安装或更新，分别询问 TCP 和 UDP 端口
sudo ./install-singbox-lite.sh install 443 8443

# 卸载服务、配置、证书、节点链接和本地 sing-box 二进制
sudo ./install-singbox-lite.sh uninstall

# 查看已生成的 VLESS / Hysteria2 节点链接
sudo ./install-singbox-lite.sh nodes

# 查询运行状态
sudo ./install-singbox-lite.sh status

# 进入关闭 / 重启 / 开启菜单
sudo ./install-singbox-lite.sh manage
```

卸载操作需要输入 `yes` 确认，并且不会删除 `curl`、`wget`、`openssl`、`tar` 等系统依赖。

## 运行状态与状态管理

菜单中提供：

- **运行状态查询**：查看 systemd / OpenRC 状态、进程、监听端口和安装信息
- **状态管理**：关闭、重启或开启 sing-box 服务

也可以直接执行：

```sh
sudo ./install-singbox-lite.sh status
sudo ./install-singbox-lite.sh manage
```

## 版本与自动更新

当前脚本版本：`2.0.1`

查看版本：

```sh
./install-singbox-lite.sh --version
```

脚本在安装开始前会检查 GitHub 上的最新 `install-singbox-lite.sh`。如果远程版本号高于本地版本号，脚本会：

1. 备份当前脚本，例如 `install-singbox-lite.sh.bak.1.2.0`
2. 下载并覆盖当前脚本
3. 使用原有参数重新执行安装流程

如果脚本是通过管道执行，或当前文件不可写，则会跳过自动更新。也可以手动关闭更新：

```sh
SINGBOX_LITE_SKIP_UPDATE=1 sudo -E ./install-singbox-lite.sh 443 8443
```

如果你把脚本复制到了自己的仓库，可以覆盖更新地址：

```sh
REMOTE_SCRIPT_URL=https://raw.githubusercontent.com/你的用户名/你的仓库/main/install-singbox-lite.sh \
  sudo -E ./install-singbox-lite.sh 443 8443
```

更新失败不会中断安装，脚本会继续使用当前版本。

## 安装方式和 GitHub 回退

安装时会按以下顺序尝试获取 sing-box：

1. Alpine 使用 APK；Debian / Ubuntu 等系统使用官方安装器
2. 如果软件源、官方安装器或网络请求失败，自动切换到 GitHub Releases
3. 根据当前 CPU 架构和 glibc / musl 环境选择对应的压缩包
4. 解压后安装到 `/usr/local/bin/sing-box`

GitHub 下载失败时，脚本会显示明确错误并停止，不会生成不完整的服务配置。基础依赖仍需要系统中存在 `openssl`、`tar` 以及 `curl` 或 `wget`；如果系统软件源完全不可用且这些依赖也不存在，请先手动安装它们。

## 安全组和防火墙

安装完成后，脚本会直接在终端打印节点链接；同时请在云厂商安全组和服务器防火墙中分别放行两个端口：

| 协议 | 用途 |
| --- | --- |
| TCP | VLESS Reality |
| UDP | Hysteria2 |

例如 Reality 使用 `443`、Hysteria2 使用 `8443` 时，需要放行：

```text
TCP 443
UDP 8443
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

为兼容 Clash.Meta、Xray 等客户端，本项目默认使用空 Short ID：服务端配置为 `"short_id": [""]`，VLESS 链接不带 `sid` 参数。重新安装后必须使用新生成的链接。

脚本生成的链接包含：

- 服务器地址和端口
- Chrome 浏览器 TLS 指纹（`fp=firefox`）
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

脚本会询问两个端口；在特殊网络环境下，可以在执行前覆盖自动检测值：

```sh
PUBLIC_IP=203.0.113.10 NODE_REGION_CODE=HK NODE_REGION_EMOJI=🇭🇰 sudo -E ./install-singbox-lite.sh 443 8443
```

通常不需要设置这些变量。

## 节点链接格式

脚本会将公网 IP 的地区信息用于生成节点名称。默认格式为：

```text
地区 Emoji地区缩写-Vless
地区 Emoji地区缩写-Hy2
```

例如香港服务器会生成类似下面的链接：

```text
vless://UUID@SERVER:443/?...#🇭🇰HK-Vless
hysteria2://PASSWORD@SERVER:8443/?...#🇭🇰HK-Hy2
```

实际完整链接会保存在：

```text
/etc/sing-box/clients/links.txt
```

安装成功时，脚本会自动把这两个链接直接打印到终端，不需要用户再手动执行 `cat`。

如果地区接口不可用，脚本会使用 `🌐XX` 作为兜底名称。也可以手动指定地区，避免自动识别：

```sh
NODE_REGION_CODE=HK NODE_REGION_EMOJI=🇭🇰 sudo -E ./install-singbox-lite.sh 443 8443
```

其中 `NODE_REGION_CODE` 建议使用两位地区缩写，例如 `HK`、`US`、`JP`、`SG`；`NODE_REGION_EMOJI` 使用对应的国旗或地区 Emoji。
## 免责声明

请只在你拥有或获授权管理的服务器上使用。使用前请确认所在地法律、云服务商条款和网络运营商政策。
