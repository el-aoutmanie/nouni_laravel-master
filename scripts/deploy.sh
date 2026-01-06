#!/bin/bash

# ============================================================
# Production Deployment Script
# This script handles the complete production deployment
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

COMPOSE_FILE="docker-compose.prod.yml"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   Production Deployment Script${NC}"
echo -e "${BLUE}======================================${NC}"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please copy .env.production to .env and configure it:"
    echo "  cp .env.production .env"
    echo "  nano .env"
    exit 1
fi

# Source the .env file
export $(grep -v '^#' .env | xargs)

# Validate required environment variables
REQUIRED_VARS=("DB_DATABASE" "DB_USERNAME" "DB_PASSWORD" "DB_ROOT_PASSWORD" "REDIS_PASSWORD" "DOMAIN")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var is not set in .env file!${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ Environment variables validated${NC}"

# Check if APP_KEY is set
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:YOUR_APP_KEY_HERE" ]; then
    echo -e "${YELLOW}Warning: APP_KEY is not set!${NC}"
    echo "Please generate an APP_KEY manually:"
    echo ""
    echo "  Option 1 - Generate locally (if PHP is installed):"
    echo "    php artisan key:generate --show"
    echo ""
    echo "  Option 2 - Generate using Docker:"
    echo "    docker run --rm -v \$(pwd):/app -w /app php:8.2-cli php artisan key:generate --show"
    echo ""
    echo "Then add the generated key to your .env file."
    exit 1
fi

echo -e "${GREEN}✓ APP_KEY is set${NC}"

# Function to wait for a service to be healthy
wait_for_service() {
    local service=$1
    local max_attempts=$2
    local attempt=1
    
    echo -e "${YELLOW}Waiting for $service to be ready...${NC}"
    while [ $attempt -le $max_attempts ]; do
        if docker compose -f $COMPOSE_FILE ps $service | grep -q "healthy"; then
            echo -e "${GREEN}✓ $service is ready${NC}"
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts..."
        sleep 5
        ((attempt++))
    done
    
    echo -e "${RED}✗ $service failed to become healthy${NC}"
    return 1
}

# Stop any existing containers
echo -e "${GREEN}Stopping existing containers...${NC}"
docker compose -f $COMPOSE_FILE down 2>/dev/null || true

# Build images
echo -e "${GREEN}Building Docker images...${NC}"
docker compose -f $COMPOSE_FILE build --no-cache

# Start database and redis first
echo -e "${GREEN}Starting database and Redis...${NC}"
docker compose -f $COMPOSE_FILE up -d db redis

# Wait for database to be ready
wait_for_service "db" 12

# Start the application
echo -e "${GREEN}Starting application containers...${NC}"
docker compose -f $COMPOSE_FILE up -d app

# Wait for app to be ready
sleep 10

# Run database migrations
echo -e "${GREEN}Running database migrations...${NC}"
docker compose -f $COMPOSE_FILE exec -T app php artisan migrate --force

# Clear and cache configurations
echo -e "${GREEN}Optimizing application...${NC}"
docker compose -f $COMPOSE_FILE exec -T app php artisan config:cache
docker compose -f $COMPOSE_FILE exec -T app php artisan route:cache
docker compose -f $COMPOSE_FILE exec -T app php artisan view:cache

# Create storage link
echo -e "${GREEN}Creating storage link...${NC}"
docker compose -f $COMPOSE_FILE exec -T app php artisan storage:link 2>/dev/null || true

# Start remaining services
echo -e "${GREEN}Starting all services...${NC}"
docker compose -f $COMPOSE_FILE up -d

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "Services status:"
docker compose -f $COMPOSE_FILE ps
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. If SSL is not configured, run: ./scripts/init-ssl.sh"
echo "2. Check logs with: docker compose -f $COMPOSE_FILE logs -f"
echo "3. Access your application at: http://$DOMAIN (or https://$DOMAIN after SSL setup)"
