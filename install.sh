#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}错误：请使用 root 权限运行此脚本 (sudo bash $0)${NC}"
  exit 1
fi

echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}  自建真站 (Caddy 无损追加) + 3x-ui 一键部署脚本     ${NC}"
echo -e "${CYAN}=====================================================${NC}"

read -p "1. 请输入已解析到本机的分流新域名 (例如 id.xxx.xyz): " DOMAIN </dev/tty
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}错误：域名不能为空！${NC}"
  exit 1
fi

read -p "2. 请输入 3x-ui 节点备注 [默认: ${DOMAIN}]: " NODE_REMARK </dev/tty
NODE_REMARK=${NODE_REMARK:-"$DOMAIN"}

INSTALL_3XUI="n"
DEL_OLD="n"

if command -v x-ui &> /dev/null || [ -d "/usr/local/x-ui" ] || [ -f "/etc/x-ui/x-ui.db" ]; then
  read -p "3. 检测到已安装 3x-ui，是否删除原有的所有旧节点？(y/n) [默认: n]: " DEL_OLD </dev/tty
  DEL_OLD=${DEL_OLD:-"n"}
else
  read -p "3. 检测到未安装 3x-ui，是否自动安装 v2.9.4？(y/n) [默认: y]: " INSTALL_3XUI </dev/tty
  INSTALL_3XUI=${INSTALL_3XUI:-"y"}
fi

echo -e "\n${YELLOW}[1/6] 正在检查并安装 Caddy、ffmpeg 与基础依赖...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg ffmpeg wget sqlite3 python3

if ! command -v caddy &> /dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt update -y && apt install -y caddy
else
  echo -e "${GREEN}检测到系统已安装 Caddy，跳过重复安装。${NC}"
fi

echo -e "\n${YELLOW}[2/6] 处理 3x-ui 面板...${NC}"
NEW_INSTALL_3XUI=false

if [[ "$INSTALL_3XUI" =~ ^[Yy]$ ]]; then
  echo -e "${CYAN}正在自动安装 3x-ui v2.9.4...${NC}"
  PANEL_USER=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 8 | head -n 1)
  PANEL_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | fold -w 12 | head -n 1)
  PANEL_PORT=$((RANDOM % 10000 + 20000))
  PANEL_PATH=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)

  # 适配新版 3x-ui 交互顺序：1(SQLite) -> 4(跳过SSL)
  printf "1\n4\n" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) v2.9.4
  sleep 2
  # 直接通过官方 CLI 命令强制写入确定的账号、密码、端口与路径
  /usr/local/x-ui/x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" -port "$PANEL_PORT" -webBasePath "$PANEL_PATH"
  systemctl restart x-ui
  
  NEW_INSTALL_3XUI=true
  sleep 2
elif command -v x-ui &> /dev/null || [ -d "/usr/local/x-ui" ]; then
  echo -e "${GREEN}使用现有 3x-ui 面板。${NC}"
else
  echo -e "${YELLOW}已跳过 3x-ui 安装。${NC}"
fi

echo -e "\n${YELLOW}[3/6] 正在部署静态视频伪装站与测试视频...${NC}"
mkdir -p /var/www/video/videos
wget -qO /var/www/video/index.html https://raw.githubusercontent.com/yzhpxd/vstream-3xui/main/index.html

wget -q --connect-timeout=15 --tries=3 -O /var/www/video/videos/sample1.mp4 "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"
wget -q --connect-timeout=15 --tries=3 -O /var/www/video/videos/sample2.mp4 "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4"
wget -q --connect-timeout=15 --tries=3 -O /var/www/video/videos/sample3.mp4 "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"

for i in 1 2 3; do
  if [ ! -s "/var/www/video/videos/sample${i}.mp4" ]; then
    ffmpeg -y -f lavfi -i testsrc=duration=15:size=1280x720:rate=24 -c:v libx264 -pix_fmt yuv420p "/var/www/video/videos/sample${i}.mp4" >/dev/null 2>&1
  fi
done

chmod -R 755 /var/www/video

echo -e "\n${YELLOW}[4/6] 正在无损更新 Caddyfile 配置...${NC}"
CADDY_FILE="/etc/caddy/Caddyfile"
mkdir -p /etc/caddy

if [ -f "$CADDY_FILE" ]; then
  cp "$CADDY_FILE" "${CADDY_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  
  if grep -q "${DOMAIN} {" "$CADDY_FILE"; then
    echo -e "${YELLOW}检测到 Caddyfile 中已存在 ${DOMAIN} 的配置，为避免冲突，跳过追加。${NC}"
  else
    cat >> "$CADDY_FILE" << EOF

${DOMAIN} {
    tls cnuopp@gmail.com
    reverse_proxy /stream/v1* 127.0.0.1:10000

    root * /var/www/video

    handle /videos/* {
        file_server browse
    }

    file_server
}
EOF
    echo -e "${GREEN}已将 ${DOMAIN} 无损追加到原有 Caddyfile 末尾（原有站点不受影响）。${NC}"
  fi
else
  cat > "$CADDY_FILE" << EOF
${DOMAIN} {
    tls cnuopp@gmail.com
    reverse_proxy /stream/v1* 127.0.0.1:10000

    root * /var/www/video

    handle /videos/* {
        file_server browse
    }

    file_server
}
EOF
fi

caddy fmt --overwrite "$CADDY_FILE"
if caddy validate --config "$CADDY_FILE" > /dev/null 2>&1; then
  systemctl enable --now caddy
  systemctl reload caddy
  echo -e "${GREEN}Caddy 配置校验通过并已平滑重载！${NC}"
else
  echo -e "${RED}错误：Caddyfile 语法校验失败，正在自动还原备份以保护现有网站...${NC}"
  LATEST_BAK=$(ls -t ${CADDY_FILE}.bak.* 2>/dev/null | head -n 1)
  [ -n "$LATEST_BAK" ] && cp "$LATEST_BAK" "$CADDY_FILE" && systemctl reload caddy
  exit 1
fi

echo -e "\n${YELLOW}[5/6] 正在向 3x-ui 数据库写入分流节点...${NC}"
NODE_UUID=$(cat /proc/sys/kernel/random/uuid)
SUB_ID=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 16 | head -n 1)
SAFE_REMARK=$(echo "$NODE_REMARK" | sed "s/'/''/g")

DB_PATH="/etc/x-ui/x-ui.db"
if [ ! -f "$DB_PATH" ]; then
  DB_PATH=$(find /etc /usr/local -name "x-ui.db" 2>/dev/null | head -n 1)
fi

if [ -n "$DB_PATH" ] && [ -f "$DB_PATH" ]; then
  cp "$DB_PATH" "${DB_PATH}.bak"

  if [[ "$DEL_OLD" =~ ^[Yy]$ ]]; then
    sqlite3 "$DB_PATH" "DELETE FROM inbounds;"
    sqlite3 "$DB_PATH" "DELETE FROM client_traffics;" 2>/dev/null
    echo -e "${YELLOW}已清空 3x-ui 原有的旧节点。${NC}"
  else
    sqlite3 "$DB_PATH" "DELETE FROM inbounds WHERE port = 10000;"
  fi

  SETTINGS="{\"clients\":[{\"id\":\"${NODE_UUID}\",\"flow\":\"\",\"email\":\"${SAFE_REMARK}\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0,\"enable\":true,\"tgId\":\"\",\"subId\":\"${SUB_ID}\",\"reset\":0}],\"decryption\":\"none\",\"fallbacks\":[]}"
  STREAM_SETTINGS="{\"network\":\"ws\",\"security\":\"none\",\"externalProxy\":[],\"wsSettings\":{\"acceptProxyProtocol\":false,\"path\":\"/stream/v1\",\"host\":\"\",\"headers\":{}}}"
  SNIFFING="{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"],\"metadataOnly\":false,\"routeOnly\":false}"

  sqlite3 "$DB_PATH" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, '${SAFE_REMARK}', 1, 0, '127.0.0.1', 10000, 'vless', '${SETTINGS}', '${STREAM_SETTINGS}', 'inbound-10000', '${SNIFFING}');"
  
  systemctl restart x-ui
  echo -e "${GREEN}成功：已自动将新节点写入 3x-ui 并重启生效！${NC}"
else
  echo -e "${YELLOW}未检测到 3x-ui 数据库，跳过自动写入节点。${NC}"
fi

ENCODED_REMARK=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''${NODE_REMARK}'''))" 2>/dev/null || echo "$NODE_REMARK")
SERVER_IP=$(curl -s4 ifconfig.me || echo "你的服务器IP")

echo -e "\n${YELLOW}[6/6] 部署完成！${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "1. 伪装站地址: ${CYAN}https://${DOMAIN}${NC}"

if [ "$NEW_INSTALL_3XUI" = true ]; then
  echo -e "2. 新安装的 3x-ui (v2.9.4) 面板登录信息："
  echo -e "   - 面板地址: ${CYAN}http://${SERVER_IP}:${PANEL_PORT}/${PANEL_PATH}${NC}"
  echo -e "   - 用户名:   ${CYAN}${PANEL_USER}${NC}"
  echo -e "   - 密码:     ${CYAN}${PANEL_PASS}${NC}"
fi

echo -e "3. 节点参数: 备注=${CYAN}${NODE_REMARK}${NC} | 端口=${CYAN}10000${NC} | 路径=${CYAN}/stream/v1${NC}"
echo -e "4. 最终节点链接 (已内置 alpn=http/1.1)："
echo -e "${GREEN}vless://${NODE_UUID}@${DOMAIN}:443?type=ws&encryption=none&security=tls&sni=${DOMAIN}&fp=chrome&alpn=http%2F1.1&host=${DOMAIN}&path=%2Fstream%2Fv1#${ENCODED_REMARK}${NC}"
echo -e "${GREEN}=====================================================${NC}"
