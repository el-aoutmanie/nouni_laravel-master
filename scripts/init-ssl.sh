#!/bin/bash

# ============================================================
# SSL Certificate Initialization Script
# This script obtains SSL certificates from Let's Encrypt
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.prod.yml"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please copy .env.production to .env and configure it first."
    exit 1
fi

# Source the .env file to get variables
export $(grep -v '^#' .env | xargs)

# Validate required variables
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: DOMAIN is not set in .env file!${NC}"
    exit 1
fi

if [ -z "$CERTBOT_EMAIL" ]; then
    echo -e "${RED}Error: CERTBOT_EMAIL is not set in .env file!${NC}"
    exit 1
fi

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}SSL Certificate Setup for $DOMAIN${NC}"
echo -e "${GREEN}======================================${NC}"

# Check if certificate already exists
if [ -d "./certbot/conf/live/$DOMAIN" ]; then
    echo -e "${YELLOW}Certificate already exists for $DOMAIN${NC}"
    read -p "Do you want to renew/recreate it? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting without changes."
        exit 0
    fi
fi

# Create directories if they don't exist
echo -e "${GREEN}Creating required directories...${NC}"
mkdir -p ./certbot/conf
mkdir -p ./certbot/www

# Stop any running containers
echo -e "${GREEN}Stopping existing containers...${NC}"
docker compose -f $COMPOSE_FILE down 2>/dev/null || true

# Start only nginx for initial certificate request
echo -e "${GREEN}Starting nginx for certificate verification...${NC}"
docker compose -f $COMPOSE_FILE up -d nginx

# Wait for nginx to start
echo -e "${GREEN}Waiting for nginx to start...${NC}"
sleep 5

# Check if this is a staging/test run
STAGING_ARG=""
if [ "$CERTBOT_STAGING" = "1" ] || [ "$CERTBOT_STAGING" = "true" ]; then
    echo -e "${YELLOW}Using Let's Encrypt staging server (test certificates)${NC}"
    STAGING_ARG="--staging"
fi

# Request certificate using certbot
echo -e "${GREEN}Requesting SSL certificate from Let's Encrypt...${NC}"
docker compose -f $COMPOSE_FILE run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email $CERTBOT_EMAIL \
    --agree-tos \
    --no-eff-email \
    $STAGING_ARG \
    -d $DOMAIN \
    -d www.$DOMAIN

# Check if certificate was obtained successfully
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Certificate obtained successfully!${NC}"
    
    # Generate the production nginx config with domain substitution
    echo -e "${GREEN}Generating production nginx configuration...${NC}"
    envsubst '${DOMAIN}' < ./docker/nginx/nginx.prod.conf.template > ./docker/nginx/nginx.prod.conf
    
    # Restart nginx to apply SSL configuration
    echo -e "${GREEN}Restarting nginx with SSL configuration...${NC}"
    docker compose -f $COMPOSE_FILE restart nginx
    
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}SSL Setup Complete!${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo -e "Your site is now available at:"
    echo -e "  ${GREEN}https://$DOMAIN${NC}"
    echo -e "  ${GREEN}https://www.$DOMAIN${NC}"
    echo ""
    echo -e "${YELLOW}Note: Certificates will be automatically renewed by the certbot container.${NC}"
else
    echo -e "${RED}Failed to obtain certificate!${NC}"
    echo "Please check the error messages above."
    exit 1
fi
