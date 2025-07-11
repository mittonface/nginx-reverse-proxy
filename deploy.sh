#!/bin/bash
set -e

echo "🚀 Starting nginx-reverse-proxy deployment..."

echo "✅ Using hardcoded domains: temps.mittn.ca and camera.mittn.ca"

# Check if shared network exists
if ! docker network ls | grep -q "proxy-network"; then
    echo "🔧 Creating shared Docker network..."
    docker network create proxy-network
else
    echo "✅ Shared network 'proxy-network' already exists"
fi

# Check if dependent services are running
echo "🔍 Checking dependent services..."
services_ready=true

if ! docker ps | grep -q "house-temp-tracker-web-1"; then
    echo "⚠️  Warning: house-temp-tracker-web-1 is not running"
    echo "   Please ensure house-temp-tracker is deployed first"
    services_ready=false
fi

if ! docker ps | grep -q "camera-viewer-camera-viewer-1"; then
    echo "⚠️  Warning: camera-viewer-camera-viewer-1 is not running"
    echo "   Please ensure camera-viewer is deployed first"
    services_ready=false
fi

if [ "$services_ready" = false ]; then
    read -p "Continue deployment anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        exit 1
    fi
fi

# Stop existing containers
echo "🛑 Stopping existing containers..."
docker-compose down --timeout 30

# Configure SSL based on certificate availability
if [ -f "certbot/conf/live/temps.mittn.ca/fullchain.pem" ] && [ -f "certbot/conf/live/camera.mittn.ca/fullchain.pem" ]; then
    echo "✅ SSL certificates found for both domains, using HTTPS configuration"
    cp nginx.conf nginx.conf.active
else
    echo "ℹ️  SSL certificates not found for all domains, using HTTP configuration"
    cp nginx-initial.conf nginx.conf.active
fi

# Start services
echo "🚀 Starting reverse proxy services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to initialize..."
sleep 10

# Check if services are running
echo "🔍 Checking service status..."
docker-compose ps

# Health check
echo "🏥 Performing health check..."
health_check_passed=false

for i in {1..6}; do
    echo "Health check attempt $i/6..."
    
    # Try health check on both domains (via nginx proxy)
    if curl -f -s --max-time 10 -H "Host: temps.mittn.ca" http://localhost/health >/dev/null 2>&1 && \
       curl -f -s --max-time 10 -H "Host: camera.mittn.ca" http://localhost/health >/dev/null 2>&1; then
        echo "✅ HTTP health check successful for both domains!"
        health_check_passed=true
        
        # Check HTTPS if certificates exist
        if [ -f "certbot/conf/live/temps.mittn.ca/fullchain.pem" ]; then
            if curl -f -s -k --max-time 10 https://temps.mittn.ca >/dev/null 2>&1 && \
               curl -f -s -k --max-time 10 https://camera.mittn.ca >/dev/null 2>&1; then
                echo "✅ HTTPS health check successful for both domains!"
            fi
        fi
        break
    elif [ $i -eq 6 ]; then
        echo "❌ Health check failed after 6 attempts!"
        echo "Service logs:"
        docker-compose logs --tail=30
        echo ""
        echo "Container status:"
        docker-compose ps
        exit 1
    else
        echo "Service not ready yet, waiting 10 seconds..."
        sleep 10
    fi
done

echo "✅ Deployment completed!"
echo ""
echo "🌐 Your applications are accessible at:"
echo "   House Temp Tracker:"
echo "     HTTP:  http://temps.mittn.ca"
if [ -f "certbot/conf/live/temps.mittn.ca/fullchain.pem" ]; then
    echo "     HTTPS: https://temps.mittn.ca"
fi
echo ""
echo "   Camera Viewer:"
echo "     HTTP:  http://camera.mittn.ca"
if [ -f "certbot/conf/live/camera.mittn.ca/fullchain.pem" ]; then
    echo "     HTTPS: https://camera.mittn.ca"
fi
echo ""
if [ ! -f "certbot/conf/live/temps.mittn.ca/fullchain.pem" ] || [ ! -f "certbot/conf/live/camera.mittn.ca/fullchain.pem" ]; then
    echo "📝 To set up SSL certificates, run: ./init-letsencrypt.sh"
fi