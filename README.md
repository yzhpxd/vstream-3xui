# vstream-3xui

一键部署 **Caddy 视频伪装真站 + WebSocket 路径分流 (`/stream/v1`) + 3x-ui 自动配置**脚本。支持多站点无损追加，不覆盖现有 Caddy 配置。

## ⚠️ 运行前必看（划重点）

1. **必须拥有自己的域名**（如 `xxx.xyz`）。
2. **先新建并解析分流新域名**：在域名后台（如 Cloudflare）添加 **A 记录** 指向本机 IP（例如 `id.xxx.xyz`），**务必关闭小云朵（仅 DNS）**，否则无法自动申请 HTTPS 证书。

## 🚀 一键运行

域名解析生效后，以 `root` 权限执行：

```bash
bash <(curl -sL [https://raw.githubusercontent.com/yzhpxd/vstream-3xui/main/install.sh](https://raw.githubusercontent.com/yzhpxd/vstream-3xui/main/install.sh))
