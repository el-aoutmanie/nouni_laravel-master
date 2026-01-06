# Production Deployment Guide

This guide covers deploying the Nouni Laravel application to production using Docker with HTTPS (Let's Encrypt).

## Prerequisites

- A server with Docker and Docker Compose installed
- A domain name pointing to your server's IP address
- Ports 80 and 443 open on your firewall

## Quick Start

```bash
# 1. Clone or copy your project to the server
cd /path/to/nouni_laravel

# 2. Copy and configure environment file
cp .env.production .env

# 3. Edit the .env file with your settings
nano .env

# 4. Generate APP_KEY manually (see below)

# 5. Make scripts executable
chmod +x scripts/*.sh

# 6. Deploy the application
./scripts/deploy.sh

# 7. Set up SSL certificate
./scripts/init-ssl.sh
```

## Detailed Setup

### Step 1: Environment Configuration

Copy `.env.production` to `.env` and configure these critical settings:

```bash
# Your domain
DOMAIN=your-domain.com
APP_URL=https://your-domain.com

# Email for SSL certificate notifications
CERTBOT_EMAIL=admin@your-domain.com

# Database credentials (use strong passwords!)
DB_DATABASE=nouni_db
DB_USERNAME=nouni_user
DB_PASSWORD=YOUR_STRONG_DB_PASSWORD
DB_ROOT_PASSWORD=YOUR_STRONG_ROOT_PASSWORD

# Redis password
REDIS_PASSWORD=YOUR_STRONG_REDIS_PASSWORD
```

### Step 2: Generate APP_KEY Manually

**Important:** The APP_KEY is NOT generated automatically in production for security reasons.

**Option 1 - Using PHP locally:**
```bash
php artisan key:generate --show
```

**Option 2 - Using Docker:**
```bash
docker run --rm -v $(pwd):/app -w /app php:8.2-cli php -r "echo 'base64:'.base64_encode(random_bytes(32)).PHP_EOL;"
```

Copy the generated key to your `.env` file:
```
APP_KEY=base64:YOUR_GENERATED_KEY_HERE
```

### Step 3: Deploy Application

Run the deployment script:

```bash
./scripts/deploy.sh
```

This will:
- Build Docker images
- Start all services
- Run database migrations
- Cache configurations
- Create storage symlinks

### Step 4: SSL Certificate Setup

Run the SSL initialization script:

```bash
./scripts/init-ssl.sh
```

This will:
- Obtain SSL certificates from Let's Encrypt
- Configure nginx for HTTPS
- Set up automatic certificate renewal

**Testing with Staging Certificates:**
Set `CERTBOT_STAGING=1` in your `.env` file to use Let's Encrypt's staging server for testing (to avoid rate limits).

## File Structure

```
├── Dockerfile.prod              # Production Docker image
├── docker-compose.prod.yml      # Production compose file
├── .env.production              # Production env template
├── docker/
│   ├── nginx/
│   │   ├── nginx.prod.conf           # Initial nginx config
│   │   ├── nginx.prod.conf.template  # SSL nginx config template
│   │   └── ssl-params.conf           # SSL security parameters
│   ├── php/
│   │   ├── php.ini                   # PHP production settings
│   │   └── opcache.ini               # OPcache settings
│   └── mysql/
│       └── my.cnf                    # MySQL optimization
└── scripts/
    ├── deploy.sh                # Main deployment script
    └── init-ssl.sh              # SSL certificate setup
```

## Docker Services

| Service | Description | Internal Port | External Port |
|---------|-------------|---------------|---------------|
| app | PHP-FPM application | 9000 | - |
| nginx | Web server | 80, 443 | 80, 443 |
| db | MySQL database | 3306 | - (internal only) |
| redis | Cache & sessions | 6379 | - (internal only) |
| queue | Queue worker | - | - |
| scheduler | Task scheduler | - | - |
| certbot | SSL certificate renewal | - | - |

## Network Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           External Network              │
                    │         (nouni_external)                │
                    └────────────────┬────────────────────────┘
                                     │
                    ┌────────────────┴────────────────────────┐
                    │                                         │
              ┌─────▼─────┐                           ┌───────▼───────┐
              │   nginx   │                           │    certbot    │
              │  :80/:443 │                           │               │
              └─────┬─────┘                           └───────────────┘
                    │
     ┌──────────────┼──────────────────────────────────────┐
     │              │       Internal Network               │
     │              │      (nouni_internal)                │
     │   ┌──────────▼──────────┐                           │
     │   │        app          │                           │
     │   │    (PHP-FPM)        │                           │
     │   └──────────┬──────────┘                           │
     │              │                                      │
     │   ┌──────────┼──────────┬───────────────┐          │
     │   │          │          │               │          │
     │   ▼          ▼          ▼               ▼          │
     │ ┌────┐   ┌───────┐  ┌───────┐    ┌───────────┐     │
     │ │ db │   │ redis │  │ queue │    │ scheduler │     │
     │ └────┘   └───────┘  └───────┘    └───────────┘     │
     └────────────────────────────────────────────────────┘
```

## Security Features

### Nginx Protection

- ✅ HTTP to HTTPS redirect
- ✅ `.env` files blocked
- ✅ Hidden files blocked (except `.well-known`)
- ✅ Sensitive directories blocked (vendor, node_modules, storage/app, etc.)
- ✅ Backup/config files blocked (.sql, .log, .yml, etc.)
- ✅ Security headers (X-Frame-Options, CSP, HSTS, etc.)

### Network Security

- ✅ Database not exposed externally
- ✅ Redis not exposed externally
- ✅ Internal network isolation
- ✅ Services communicate only through internal network

### SSL/TLS

- ✅ TLS 1.2 and 1.3 only
- ✅ Strong cipher suites
- ✅ OCSP stapling enabled
- ✅ Automatic certificate renewal

## Common Commands

```bash
# View all service logs
docker compose -f docker-compose.prod.yml logs -f

# View specific service logs
docker compose -f docker-compose.prod.yml logs -f app

# Run artisan commands
docker compose -f docker-compose.prod.yml exec app php artisan <command>

# Clear caches
docker compose -f docker-compose.prod.yml exec app php artisan cache:clear
docker compose -f docker-compose.prod.yml exec app php artisan config:clear

# Rebuild and restart
docker compose -f docker-compose.prod.yml up -d --build

# Stop all services
docker compose -f docker-compose.prod.yml down

# Stop and remove volumes (WARNING: deletes data)
docker compose -f docker-compose.prod.yml down -v

# Force SSL certificate renewal
docker compose -f docker-compose.prod.yml run --rm certbot renew --force-renewal
```

## Troubleshooting

### SSL Certificate Issues

1. **Rate Limited**: If you hit Let's Encrypt rate limits, wait or use staging:
   ```bash
   CERTBOT_STAGING=1 ./scripts/init-ssl.sh
   ```

2. **Domain Validation Failed**: Ensure your domain points to the server and ports 80/443 are open.

3. **Certificate Not Found**: Check if certificate was issued:
   ```bash
   docker compose -f docker-compose.prod.yml exec nginx ls -la /etc/letsencrypt/live/
   ```

### Database Connection Issues

1. Check if database is healthy:
   ```bash
   docker compose -f docker-compose.prod.yml ps db
   ```

2. Check database logs:
   ```bash
   docker compose -f docker-compose.prod.yml logs db
   ```

### Permission Issues

If you see permission errors:
```bash
docker compose -f docker-compose.prod.yml exec app chown -R www-data:www-data storage bootstrap/cache
```

## Backup & Restore

### Database Backup
```bash
docker compose -f docker-compose.prod.yml exec db mysqldump -u root -p nouni_db > backup.sql
```

### Database Restore
```bash
docker compose -f docker-compose.prod.yml exec -T db mysql -u root -p nouni_db < backup.sql
```

### Full Backup (including uploads)
```bash
tar -czvf backup-$(date +%Y%m%d).tar.gz storage/app/public .env
```

## Updating the Application

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
docker compose -f docker-compose.prod.yml up -d --build

# Run migrations
docker compose -f docker-compose.prod.yml exec app php artisan migrate --force

# Clear caches
docker compose -f docker-compose.prod.yml exec app php artisan config:cache
docker compose -f docker-compose.prod.yml exec app php artisan route:cache
docker compose -f docker-compose.prod.yml exec app php artisan view:cache
```
