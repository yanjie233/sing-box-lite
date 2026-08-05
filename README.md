# sing-box-lite

这是一个面向 64MB/128MB 小内存 Linux VPS 的极简安装脚本：

- 自动获取公网 IPv4
- 只询问监听端口
- 同一个数字端口同时提供 TCP Reality 与 UDP Hysteria2（TCP/UDP 命名空间独立）
- 自动生成 UUID、Reality 密钥、Short ID、Hysteria2 密码
- Hysteria2 使用轻量 ECDSA 自签名证书，不需要域名和 ACME
- 自动识别 Debian/Ubuntu、Alpine、Alibaba Cloud Linux/RHEL 系
- 自动生成 systemd 或 OpenRC 服务
- 不安装面板、不启用 DNS/TUN/统计 API，尽量减少内存占用

## 使用

```sh
chmod +x install-singbox-lite.sh
sudo ./install-singbox-lite.sh
# 或直接传入端口，跳过唯一的交互问题
sudo ./install-singbox-lite.sh 443
```

安装完成后：

- 服务端配置：`/etc/sing-box/config.json`
- Reality 客户端出站模板：`/etc/sing-box/clients/reality.json`
- Hysteria2 客户端出站模板：`/etc/sing-box/clients/hysteria2.json`
- 导入链接：`/etc/sing-box/clients/links.txt`
- 安装信息：`/etc/sing-box/install-info.txt`

## 注意

1. 必须在云厂商安全组放行 `TCP 端口` 和 `UDP 端口`；Hysteria2 只需要 UDP。
2. Hysteria2 是自签名证书，客户端必须设置允许不验证证书（`insecure=1`）。生产环境若有域名，建议替换成受信任证书。
3. 64MB 机器建议使用 Debian 最小化系统或 Alpine，关闭不需要的 Web 面板、Docker、监控和日志服务；脚本本身不会主动修改内核参数。
4. 脚本重跑会备份旧配置，但会生成新凭据，旧客户端链接会失效。
5. 仅在你拥有或获授权管理的服务器上使用。
