#!/bin/bash
set -e

echo "======================================"
echo "SSL Certificate Setup for fhmaison.fr"
echo "======================================"

COMPOSE_FILE="docker-compose.prod.yml"

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

DOMAIN=${DOMAIN:-fhmaison.fr}
EMAIL=${CERTBOT_EMAIL:-admin@fhmaison.fr}
STAGING=${CERTBOT_STAGING:-0}

echo "Domain: $DOMAIN"
echo "Email: $EMAIL"

# Make sure nginx is running
echo "Ensuring nginx is running..."
docker compose -f $COMPOSE_FILE up -d nginx
sleep 3

# Test if domain is reachable
echo "Testing domain accessibility..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://${DOMAIN}/ || echo "Could not reach domain (this might be OK)"

# Prepare staging flag
STAGING_FLAG=""
if [ "$STAGING" = "1" ]; then
    STAGING_FLAG="--staging"
    echo "Using Let's Encrypt STAGING server (test certificates)"
fi

# Request certificate
echo ""
echo "Requesting SSL certificate from Let's Encrypt..."
echo ""

docker compose -f $COMPOSE_FILE run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email ${EMAIL} \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d ${DOMAIN} \
    -d www.${DOMAIN} \
    ${STAGING_FLAG}

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ SSL certificate obtained successfully!"
    echo ""
    echo "Now updating nginx configuration for HTTPS..."
    
    # Create HTTPS nginx config
    cat > docker/nginx/nginx.prod.conf << 'NGINXEOF'
# HTTP - Redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name fhmaison.fr www.fhmaison.fr;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        allow all;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name fhmaison.fr www.fhmaison.fr;

    ssl_certificate /etc/letsencrypt/live/fhmaison.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/fhmaison.fr/privkey.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    root /var/www/html/public;
    index index.php index.html;
    charset utf-8;

    # Block sensitive files
    location ~ /\.env { deny all; return 404; }
    location ~ /\.(git|svn|htaccess) { deny all; return 404; }
    location ~* \.(bak|config|sql|log|sh|yml|yaml|lock)$ { deny all; return 404; }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location /storage {
        alias /var/www/html/storage/app/public;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
}
NGINXEOF

    # Restart nginx with new config
    echo "Restarting nginx..."
    docker compose -f $COMPOSE_FILE restart nginx
    
    echo ""
    echo "======================================"
    echo "SSL Setup Complete!"
    echo "======================================"
    echo ""
    echo "Your site is now available at:"
    echo "  https://fhmaison.fr"
    echo "  https://www.fhmaison.fr"
    echo ""
    echo "HTTP automatically redirects to HTTPS"
    echo ""
else
    echo ""
    echo "ERROR: Failed to obtain SSL certificate!"
    echo ""
    echo "Common issues:"
    echo "1. Domain DNS not pointing to this server"
    echo "2. Port 80 blocked by firewall"
    echo "3. Rate limit exceeded (try CERTBOT_STAGING=1)"
    echo ""
    exit 1
fi
