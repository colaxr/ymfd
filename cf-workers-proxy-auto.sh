#!/usr/bin/env bash
set -e

### ========= 配置区（只改这里） =========
VPS_DOMAIN="vps-domain.com"
WORKERS_DOMAIN="workers-bound-domain.com"
EMAIL="admin@example.com"
### ======================================

CONF_DIR="/etc/nginx/conf.d"
CERT_DIR="/etc/ssl/${VPS_DOMAIN}"
CONF_FILE="${CONF_DIR}/${VPS_DOMAIN}.conf"

echo "=== CF Workers Reverse Proxy Auto ==="
echo "VPS DOMAIN     : ${VPS_DOMAIN}"
echo "WORKERS DOMAIN : ${WORKERS_DOMAIN}"
echo "===================================="

if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "❌ 未检测到 nginx，请先安装 nginx"
  exit 1
fi

if [ ! -d "/root/.acme.sh" ]; then
  echo "==> Installing acme.sh"
  curl https://get.acme.sh | sh -s email="${EMAIL}"
fi

export PATH="/root/.acme.sh:${PATH}"

echo "==> Issuing SSL certificate (standalone mode)"
mkdir -p "${CERT_DIR}"

~/.acme.sh/acme.sh --issue -d "${VPS_DOMAIN}" --standalone

~/.acme.sh/acme.sh --install-cert -d "${VPS_DOMAIN}" \
  --key-file       "${CERT_DIR}/privkey.pem" \
  --fullchain-file "${CERT_DIR}/fullchain.pem" \
  --reloadcmd     "true"

echo "==> Writing nginx config"

cat > "${CONF_FILE}" <<EOF
server {
    listen 80;
    server_name ${VPS_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${VPS_DOMAIN};

    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;

    location / {
        proxy_pass https://${WORKERS_DOMAIN};

        proxy_set_header Host ${WORKERS_DOMAIN};
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

echo "==> Testing nginx config"
nginx -t

echo "==> Reloading nginx"
systemctl reload nginx

echo "===================================="
echo "✅ 部署完成"
echo "访问地址: https://${VPS_DOMAIN}"
echo "反代目标: https://${WORKERS_DOMAIN}"
echo "===================================="
