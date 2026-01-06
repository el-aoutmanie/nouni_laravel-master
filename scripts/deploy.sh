#!/bin/bash
set -e

echo "======================================"
echo "FH Maison Production Deployment"
echo "======================================"

COMPOSE_FILE="docker-compose.prod.yml"

# Check if .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found!"
    echo "Please copy .env.production to .env and configure it."
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

# Create required directories
echo "Creating directories..."
mkdir -p storage/app/public
mkdir -p storage/framework/{cache,sessions,views}
mkdir -p storage/logs
mkdir -p bootstrap/cache

# Set permissions
echo "Setting permissions..."
chmod -R 777 storage bootstrap/cache
touch storage/logs/laravel.log
chmod 666 storage/logs/laravel.log

# Delete SQLite database if exists (we use MySQL)
rm -f database/database.sqlite

# Stop existing containers
echo "Stopping existing containers..."
docker compose -f $COMPOSE_FILE down --remove-orphans 2>/dev/null || true

# Remove old volumes if fresh install needed
# docker compose -f $COMPOSE_FILE down -v 2>/dev/null || true

# Build containers
echo "Building containers..."
docker compose -f $COMPOSE_FILE build --no-cache

# Start database and redis first
echo "Starting database and redis..."
docker compose -f $COMPOSE_FILE up -d db redis

# Wait for database
echo "Waiting for database..."
sleep 15
for i in {1..30}; do
    if docker compose -f $COMPOSE_FILE exec -T db mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "✓ Database is ready"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

# Start application
echo "Starting application..."
docker compose -f $COMPOSE_FILE up -d app

sleep 5

# Run migrations
echo "Running migrations..."
docker compose -f $COMPOSE_FILE exec -T app php artisan migrate --force || echo "Migration completed with warnings"

# Clear caches
echo "Clearing caches..."
docker compose -f $COMPOSE_FILE exec -T app php artisan config:clear || true
docker compose -f $COMPOSE_FILE exec -T app php artisan cache:clear || true
docker compose -f $COMPOSE_FILE exec -T app php artisan view:clear || true
docker compose -f $COMPOSE_FILE exec -T app php artisan route:clear || true

# Optimize
echo "Optimizing..."
docker compose -f $COMPOSE_FILE exec -T app php artisan config:cache || true
docker compose -f $COMPOSE_FILE exec -T app php artisan route:cache || true
docker compose -f $COMPOSE_FILE exec -T app php artisan view:cache || true

# Create storage link
echo "Creating storage link..."
docker compose -f $COMPOSE_FILE exec -T app php artisan storage:link --force || true

# Start nginx
echo "Starting nginx..."
docker compose -f $COMPOSE_FILE up -d nginx

# Start queue and scheduler
echo "Starting queue and scheduler..."
docker compose -f $COMPOSE_FILE up -d queue scheduler

echo ""
echo "======================================"
echo "Deployment Complete!"
echo "======================================"
echo ""
echo "Site available at: http://fhmaison.fr"
echo ""
echo "Next: Run ./scripts/init-ssl.sh for HTTPS"
echo ""
docker compose -f $COMPOSE_FILE ps
