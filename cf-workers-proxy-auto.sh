#!/usr/bin/env bash
set -e

### ========= 只改这里 =========
VPS_DOMAIN="vps-domain.com"
WORKERS_DOMAIN="workers-bound-domain.com"
EMAIL="admin@example.com"
### ============================

CONF_DIR="/etc/nginx/conf.d"
CERT_DIR="/etc/ssl/$VPS_DOMAIN"
CONF_FILE="$CONF_DIR/$VPS_DOMAIN.conf"

echo "=== CF Workers Reverse Proxy Auto ==="
echo "VPS DOMAIN     : $VPS_DOMAIN"
echo "WORKERS DOMAIN : $WORKERS_DOMAIN"
echo "===================================="

# 1. 检查 nginx
if ! command -v nginx >/dev/null 2>&1; then
  echo "❌ Nginx not found, please install nginx first"
  exit 1
fi

# 2. 安装 acme.sh（如果没有）
if [ ! -d "$HOME/.acme.sh" ]; then
  curl https://get.acme.sh | sh -s email=$EMAIL
fi

# 3. 申请证书（不影响其他站点）
mkdir -p "$CERT_DIR"

~/.acme.sh/acme.sh --issue -d "$VPS_DOMAIN" --nginx

~/.acme.sh/acme.sh --install-cert -d "$VPS_DOMAIN" \
  --key-file       "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --reloadcmd     "true"

# 4. 写反代配置（独立文件）
cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $VPS_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $VPS_DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;

    location / {
        proxy_pass https://$WORKERS_DOMAIN;

        proxy_set_header Host $WORKERS_DOMAIN;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Accept-Encoding "";

        proxy_read_timeout 300;
    }
}
EOF

# 5. 测试并 reload
nginx -t
systemctl reload nginx

echo "===================================="
echo "✅ 部署完成"
echo "访问地址: https://$VPS_DOMAIN"
echo "反代目标: https://$WORKERS_DOMAIN"
echo "===================================="
