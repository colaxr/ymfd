#!/bin/bash
# ==============================================
# VPS 一键添加 CF Worker 反代（保留现有 Nginx 配置）
# 支持 HTTPS (Let’s Encrypt certonly)
# ==============================================

echo "======================================="
echo " VPS 添加 CF Worker 反代脚本"
echo "======================================="

# -------------------------------
# 交互输入
# -------------------------------
read -p "请输入新 VPS 域名 (例: xt.wong.pp.ua): " VPS_DOMAIN
read -p "请输入 CF Worker 域名 (例: xiutu.bhlc.de5.net): " CF_WORKER_DOMAIN
read -p "是否开启 HTTPS? (y/n): " USE_HTTPS_INPUT

if [[ "$USE_HTTPS_INPUT" =~ ^[Yy]$ ]]; then
    USE_HTTPS=true
    read -p "请输入你的邮箱，用于 HTTPS 证书注册: " EMAIL
else
    USE_HTTPS=false
fi

# -------------------------------
# 创建 ACME 验证目录
# -------------------------------
if [ "$USE_HTTPS" = true ]; then
    mkdir -p /var/www/certbot
    chown -R www-data:www-data /var/www/certbot
fi

# -------------------------------
# 生成独立 Nginx 配置
# -------------------------------
NGINX_CONF="/etc/nginx/conf.d/cf-worker-${VPS_DOMAIN}.conf"

echo "生成 Nginx 配置..."
cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name $VPS_DOMAIN;

EOF

if [ "$USE_HTTPS" = true ]; then
cat >> $NGINX_CONF <<EOF
    # 放行 ACME 验证目录
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
EOF
fi

cat >> $NGINX_CONF <<EOF
    # 反代 CF Worker
    location / {
        proxy_pass https://$CF_WORKER_DOMAIN;
        proxy_set_header Host $CF_WORKER_DOMAIN;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_ssl_server_name on;
        proxy_ssl_verify off;
    }
}
EOF

# -------------------------------
# 测试 Nginx 配置
# -------------------------------
nginx -t || { echo "Nginx 配置错误，请检查"; exit 1; }

# -------------------------------
# 重载 Nginx
# -------------------------------
systemctl reload nginx

# -------------------------------
# HTTPS 证书申请（Let’s Encrypt certonly）
# -------------------------------
if [ "$USE_HTTPS" = true ]; then
    echo "使用 Let’s Encrypt 申请证书..."
    certbot certonly --webroot -w /var/www/certbot -d $VPS_DOMAIN --non-interactive --agree-tos -m $EMAIL

    CERT_PATH="/etc/letsencrypt/live/$VPS_DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$VPS_DOMAIN/privkey.pem"

    echo "生成 HTTPS Nginx 配置..."
    cat > $NGINX_CONF <<EOF
# HTTP 重定向到 HTTPS
server {
    listen 80;
    server_name $VPS_DOMAIN;
    return 301 https://\$host\$request_uri;
}

# HTTPS 反代 CF Worker
server {
    listen 443 ssl http2;
    server_name $VPS_DOMAIN;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://$CF_WORKER_DOMAIN;
        proxy_set_header Host $CF_WORKER_DOMAIN;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_ssl_server_name on;
        proxy_ssl_verify off;
    }
}
EOF

    nginx -t && systemctl reload nginx
fi

# -------------------------------
# 完成
# -------------------------------
echo "======================================="
echo "CF Worker 反代部署完成!"
echo "VPS 域名: http://$VPS_DOMAIN"
if [ "$USE_HTTPS" = true ]; then
    echo "HTTPS 已启用: https://$VPS_DOMAIN"
fi
echo "反代目标 CF Worker: https://$CF_WORKER_DOMAIN"
echo "======================================="
