#!/bin/bash
# ==============================================
# VPS 一键部署 CF Worker 反代 + HTTPS（Let’s Encrypt 自动切换）
# GitHub: colaxr/ymfd/cf-workers-proxy-auto.sh
# ==============================================

echo "======================================="
echo " VPS 反代 CF Worker 一键部署脚本"
echo "======================================="

# -------------------------------
# 交互输入
# -------------------------------
read -p "请输入你的 VPS 域名 (例: proxy.yourdomain.com): " VPS_DOMAIN
read -p "请输入原 CF Worker 域名 (例: worker.example.com): " CF_WORKER_DOMAIN
read -p "是否开启 HTTPS? (y/n): " USE_HTTPS_INPUT

if [[ "$USE_HTTPS_INPUT" =~ ^[Yy]$ ]]; then
    USE_HTTPS=true
    read -p "请输入你的邮箱，用于 HTTPS 证书注册: " EMAIL
else
    USE_HTTPS=false
fi

# -------------------------------
# 系统更新 & 安装 Nginx
# -------------------------------
echo "更新系统并安装 Nginx..."
apt update && apt install -y nginx curl git software-properties-common

# -------------------------------
# 安装 Certbot（HTTPS 选项）
# -------------------------------
if [ "$USE_HTTPS" = true ]; then
    echo "安装 Snap Certbot..."
    apt remove -y certbot python3-certbot-nginx
    apt install -y snapd
    snap install core; snap refresh core
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot
fi

# -------------------------------
# 创建 ACME 验证目录
# -------------------------------
if [ "$USE_HTTPS" = true ]; then
    mkdir -p /var/www/certbot
    chown -R www-data:www-data /var/www/certbot
fi

# -------------------------------
# 生成 Nginx 配置（HTTP 初始）
# -------------------------------
NGINX_CONF="/etc/nginx/conf.d/cf-worker-proxy.conf"

echo "生成 Nginx 配置..."
cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name $VPS_DOMAIN;

    # ACME 验证目录放行
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他全部反代到 CF Worker
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
# 启动 Nginx 并开机自启
# -------------------------------
systemctl restart nginx
systemctl enable nginx

# -------------------------------
# HTTPS 证书申请（Let’s Encrypt certonly）
# -------------------------------
if [ "$USE_HTTPS" = true ]; then
    echo "开始使用 Let’s Encrypt 申请证书..."
    certbot certonly --webroot -w /var/www/certbot -d $VPS_DOMAIN --non-interactive --agree-tos -m $EMAIL

    CERT_PATH="/etc/letsencrypt/live/$VPS_DOMAIN/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$VPS_DOMAIN/privkey.pem"

    echo "生成 Nginx 配置启用 HTTPS..."
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

    systemctl restart nginx
fi

# -------------------------------
# 完成
# -------------------------------
echo "======================================="
echo "反代部署完成!"
echo "VPS 域名: http://$VPS_DOMAIN"
if [ "$USE_HTTPS" = true ]; then
    echo "HTTPS 已启用: https://$VPS_DOMAIN"
fi
echo "反代目标 CF Worker: https://$CF_WORKER_DOMAIN"
echo "======================================="
