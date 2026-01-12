#!/bin/bash
# ==============================================
# VPS 交互式部署 CF Worker 反代
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

# 安装 Certbot (如果开启 HTTPS)
if [ "$USE_HTTPS" = true ]; then
    add-apt-repository universe -y
    apt install -y certbot python3-certbot-nginx
fi

# -------------------------------
# 备份旧配置
# -------------------------------
if [ -f /etc/nginx/sites-available/default ]; then
    cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
fi

# -------------------------------
# 生成 Nginx 配置
# -------------------------------
echo "生成 Nginx 配置..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80;
    server_name $VPS_DOMAIN;

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

# 测试 Nginx 配置
nginx -t || { echo "Nginx 配置错误，请检查"; exit 1; }

# 启动并设置开机自启
systemctl restart nginx
systemctl enable nginx

# -------------------------------
# 如果开启 HTTPS，自动申请证书
# -------------------------------
if [ "$USE_HTTPS" = true ]; then
    echo "申请 HTTPS 证书..."
    certbot --nginx -d $VPS_DOMAIN --non-interactive --agree-tos -m $EMAIL
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
