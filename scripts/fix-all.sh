#!/bin/bash
set -e

echo "======================================"
echo "Fixing All Application Issues"
echo "======================================"

COMPOSE_FILE="docker-compose.prod.yml"

echo "1. Stopping containers..."
sudo docker compose -f $COMPOSE_FILE down

echo ""
echo "2. Fixing file ownership in storage and public (host)..."
sudo chown -R 33:33 storage bootstrap/cache public
sudo chmod -R 775 storage bootstrap/cache

echo ""
echo "3. Removing old storage link..."
sudo rm -f public/storage

echo ""
echo "4. Starting containers..."
sudo docker compose -f $COMPOSE_FILE up -d

echo ""
echo "5. Waiting for app to be healthy..."
sleep 10

echo ""
echo "6. Creating storage link..."
sudo docker compose -f $COMPOSE_FILE exec app php artisan storage:link --force

echo ""
echo "7. Clearing all caches..."
sudo docker compose -f $COMPOSE_FILE exec app php artisan config:clear || true
sudo docker compose -f $COMPOSE_FILE exec app php artisan route:clear || true
sudo docker compose -f $COMPOSE_FILE exec app php artisan view:clear || true
sudo docker compose -f $COMPOSE_FILE exec app php artisan cache:clear || true

echo ""
echo "8. Optimizing for production..."
sudo docker compose -f $COMPOSE_FILE exec app php artisan config:cache || true
sudo docker compose -f $COMPOSE_FILE exec app php artisan route:cache || true
sudo docker compose -f $COMPOSE_FILE exec app php artisan view:cache || true

echo ""
echo "9. Restarting nginx..."
sudo docker compose -f $COMPOSE_FILE restart nginx

echo ""
echo "======================================"
echo "✓ All fixes applied!"
echo "======================================"
echo ""
echo "Testing the application..."
sleep 2
curl -I https://fhmaison.fr 2>&1 | head -10
echo ""
echo "Check your site at: https://fhmaison.fr"
echo ""