#!/bin/bash
set -e

echo "======================================"
echo "Fixing All Application Issues"
echo "======================================"

COMPOSE_FILE="docker-compose.prod.yml"

echo "1. Stopping containers..."
sudo docker compose -f $COMPOSE_FILE down

echo ""
echo "2. Fixing file ownership in storage and public..."
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
echo "6. Fixing permissions inside container..."
sudo docker compose -f $COMPOSE_FILE exec app chown -R www-data:www-data /var/www/html
sudo docker compose -f $COMPOSE_FILE exec app chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

echo ""
echo "7. Creating storage link..."
sudo docker compose -f $COMPOSE_FILE exec app php artisan storage:link --force

echo ""
echo "8. Clearing all caches..."
sudo docker compose -f $COMPOSE_FILE exec app php artisan config:clear
sudo docker compose -f $COMPOSE_FILE exec app php artisan route:clear
sudo docker compose -f $COMPOSE_FILE exec app php artisan view:clear
sudo docker compose -f $COMPOSE_FILE exec app php artisan cache:clear

echo ""
echo "9. Optimizing for production..."
sudo docker compose -f $COMPOSE_FILE exec app php artisan config:cache
sudo docker compose -f $COMPOSE_FILE exec app php artisan route:cache
sudo docker compose -f $COMPOSE_FILE exec app php artisan view:cache

echo ""
echo "10. Restarting all services..."
sudo docker compose -f $COMPOSE_FILE restart

echo ""
echo "======================================"
echo "✓ All fixes applied!"
echo "======================================"
echo ""
echo "Testing the application..."
curl -I https://fhmaison.fr 2>&1 | head -5
echo ""