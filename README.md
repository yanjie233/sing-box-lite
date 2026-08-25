# sing-box-lite

面向小内存 Linux VPS 的 sing-box 一键安装与管理脚本，支持 **VLESS + Reality** 和 **Hysteria2**。

## 快速开始

```sh
curl -fsSL https://raw.githubusercontent.com/yanjie233/sing-box-lite/main/install-singbox-lite.sh -o install-singbox-lite.sh
chmod +x install-singbox-lite.sh
./install-singbox-lite.sh
```

安装完成后，脚本会创建快捷菜单命令：

```sh
singbox
```

## 菜单功能

```text
1. 一键快捷安装       Reality + Hysteria2，使用默认端口和自签名证书
2. 自定义安装         选择全部、仅 Reality 或仅 Hysteria2
3. 状态查询及管理     分别查看、开启、关闭、重启两个协议
4. 节点信息           查看导入链接和客户端配置文件
5. 升级脚本与 singbox   更新管理脚本和 sing-box 二进制
6. 完全卸载           删除服务、配置、证书、节点信息和快捷命令
0. 退出
```

## 自定义安装

自定义安装可以选择：

- Reality + Hysteria2
- 仅 VLESS Reality
- 仅 Hysteria2

端口分别使用 TCP 和 UDP，脚本会为实际安装的协议创建独立服务：

| 协议 | 服务名 | 配置文件 | 默认端口 |
| --- | --- | --- | --- |
| VLESS Reality | `sing-box-reality` | `/etc/sing-box/config-reality.json` | TCP `55667` |
| Hysteria2 | `sing-box-hysteria2` | `/etc/sing-box/config-hysteria2.json` | UDP `55668` |

两个协议现在可以独立管理，不再必须一起启动或停止。

## 证书申请与部署

安装 Hysteria2 时可选择：

1. **自签名证书**：无需域名，节点链接会带 `insecure=1`。
2. **域名证书**：通过 `acme.sh` 自动申请并部署到 sing-box。
3. **IP 证书**：调用当前 acme.sh 的 IP 证书流程申请并部署。

申请证书时可以输入：

- 域名（域名证书模式）
- ACME 账户邮箱
- HTTP 验证端口，默认 `80`

验证端口必须能从公网访问；如果前面有端口转发，请把公网验证端口转发到脚本设置的本地端口。证书申请失败时脚本会停止，不会用不完整证书启动 Hysteria2。

## 服务管理

菜单中的“状态查询及管理”会显示：

- Reality 是否运行
- Hysteria2 是否运行
- 两个协议的监听协议和端口
- 监听端口及服务状态

并提供以下操作：

```text
开启 Reality / 关闭 Reality / 重启 Reality
开启 Hysteria2 / 关闭 Hysteria2 / 重启 Hysteria2
开启全部 / 关闭全部 / 重启全部
```

脚本优先使用 systemd；Alpine 等环境使用 OpenRC。

## 安装文件

| 文件 | 用途 |
| --- | --- |
| `/etc/sing-box/config.json` | 当前安装模式的合并配置 |
| `/etc/sing-box/config-reality.json` | Reality 独立服务配置 |
| `/etc/sing-box/config-hysteria2.json` | Hysteria2 独立服务配置 |
| `/etc/sing-box/clients/links.txt` | 节点导入链接 |
| `/etc/sing-box/clients/reality.json` | Reality 客户端出站模板 |
| `/etc/sing-box/clients/hysteria2.json` | Hysteria2 客户端出站模板 |
| `/etc/sing-box/install-info.txt` | 安装信息和端口记录 |
| `/etc/sing-box/state.env` | 状态查询使用的安装状态 |
| `/etc/sing-box/server.crt` | Hysteria2 证书 |
| `/etc/sing-box/server.key` | Hysteria2 私钥 |
| `/usr/local/bin/singbox` | 全局快捷菜单命令 |
| `/usr/local/lib/sing-box-lite/install-singbox-lite.sh` | 持久化管理脚本 |

节点链接和私钥属于敏感信息，脚本会限制相关文件权限，请不要提交到公开仓库。

## 地址选择

安装时脚本会过滤内网和保留地址（包括 LXD 常见的 `fd00::/8`、`fc00::/7`），只使用可路由地址生成节点：

- 同时检测到可用 IPv4 和公网 IPv6：询问节点使用 IPv4 还是 IPv6。
- 只有公网 IPv6：自动按 IPv6-only 处理，监听 IPv6 并生成 `[IPv6]` 格式链接。
- 只有 IPv4：使用 IPv4。
- IPv4 只是 WARP、NAT 或 LXD 共享出口时，选择 IPv4 需要自行确认端口转发；否则请选择 IPv6。
- 如果自动检测不准确，可运行前设置 `PUBLIC_IP=公网地址` 覆盖检测结果。

IPv6 证书申请会自动使用对应的 IPv6 参数。

## 防火墙和安全组

根据实际安装协议放行对应端口：

```text
Reality：TCP <Reality端口>
Hysteria2：UDP <Hysteria2端口>
```

脚本不会自动修改云厂商安全组规则，也不会自动开放服务器本机防火墙。

## 支持环境

脚本面向 Linux VPS，支持：

- Debian / Ubuntu / Linux Mint / Raspbian
- Alpine Linux
- Alibaba Cloud Linux / CentOS / RHEL 系
- systemd 或 OpenRC

基础依赖为 `openssl`、`tar` 和 `curl` 或 `wget`。脚本会优先使用系统包管理器安装 sing-box，失败时回退到 GitHub Releases。
