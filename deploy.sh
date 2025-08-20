#!/bin/bash
set -e

echo "🚀 Starting nginx-reverse-proxy deployment..."

echo "✅ Using hardcoded domains: temps.mittn.ca, camera.mittn.ca, dragonball.mittn.ca, and jirald.mittn.ca"

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

if ! docker ps | grep -q "led-control-server"; then
    echo "⚠️  Warning: led-control-server is not running"
    echo "   Please ensure dragonball-control is deployed first"
    services_ready=false
fi

if ! docker ps | grep -q "jirald-mcp-server-jirald-github-app-1"; then
    echo "⚠️  Warning: jirald-mcp-server-jirald-github-app-1 is not running"
    echo "   Please ensure jirald-mcp-server is deployed first"
    services_ready=false
fi

if [ "$services_ready" = false ]; then
    # In CI/CD or with --force flag, continue anyway
    if [ "$CI" = "true" ] || [ "$1" = "--force" ]; then
        echo "⚠️  Continuing deployment despite missing services (CI/force mode)"
    else
        read -p "Continue deployment anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Deployment cancelled"
            exit 1
        fi
    fi
fi

# Stop existing containers
echo "🛑 Stopping existing containers..."
docker-compose down --timeout 30

# Run certificate generation for any missing domains
echo "🔐 Checking and generating SSL certificates..."
if [ -f "init-letsencrypt.sh" ]; then
    chmod +x init-letsencrypt.sh
    ./init-letsencrypt.sh
else
    echo "⚠️  init-letsencrypt.sh not found, skipping certificate generation"
fi

# Backup original nginx.conf
cp nginx.conf nginx.conf.backup

# Configure SSL based on certificate availability
temps_cert=""
camera_cert=""
dragonball_cert=""
jirald_cert=""

# Find actual certificate paths (they may have suffixes like -0001)
if [ -f "certbot/conf/live/temps.mittn.ca/fullchain.pem" ]; then
    temps_cert="temps.mittn.ca"
elif [ -f "certbot/conf/live/temps.mittn.ca-0001/fullchain.pem" ]; then
    temps_cert="temps.mittn.ca-0001"
fi

if [ -f "certbot/conf/live/camera.mittn.ca/fullchain.pem" ]; then
    camera_cert="camera.mittn.ca"
elif [ -f "certbot/conf/live/camera.mittn.ca-0001/fullchain.pem" ]; then
    camera_cert="camera.mittn.ca-0001"
fi

if [ -f "certbot/conf/live/dragonball.mittn.ca/fullchain.pem" ]; then
    dragonball_cert="dragonball.mittn.ca"
elif [ -f "certbot/conf/live/dragonball.mittn.ca-0001/fullchain.pem" ]; then
    dragonball_cert="dragonball.mittn.ca-0001"
fi

if [ -f "certbot/conf/live/jirald.mittn.ca/fullchain.pem" ]; then
    jirald_cert="jirald.mittn.ca"
elif [ -f "certbot/conf/live/jirald.mittn.ca-0001/fullchain.pem" ]; then
    jirald_cert="jirald.mittn.ca-0001"
fi

if [ -n "$temps_cert" ] && [ -n "$camera_cert" ] && [ -n "$dragonball_cert" ] && [ -n "$jirald_cert" ]; then
    echo "✅ SSL certificates found for all domains, using HTTPS configuration"
    echo "   temps: $temps_cert"
    echo "   camera: $camera_cert" 
    echo "   dragonball: $dragonball_cert"
    echo "   jirald: $jirald_cert"
    
    # Update nginx.conf with actual certificate paths
    sed -i "s|/etc/letsencrypt/live/temps.mittn.ca/|/etc/letsencrypt/live/$temps_cert/|g" nginx.conf
    sed -i "s|/etc/letsencrypt/live/camera.mittn.ca/|/etc/letsencrypt/live/$camera_cert/|g" nginx.conf
    sed -i "s|/etc/letsencrypt/live/dragonball.mittn.ca/|/etc/letsencrypt/live/$dragonball_cert/|g" nginx.conf
    sed -i "s|/etc/letsencrypt/live/jirald.mittn.ca/|/etc/letsencrypt/live/$jirald_cert/|g" nginx.conf
else
    echo "ℹ️  SSL certificates not found for all domains, using HTTP configuration"
    echo "   temps: ${temps_cert:-"missing"}"
    echo "   camera: ${camera_cert:-"missing"}"
    echo "   dragonball: ${dragonball_cert:-"missing"}"
    echo "   jirald: ${jirald_cert:-"missing"}"
    cp nginx-initial.conf nginx.conf
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
    
    # Try health check on all four domains (via nginx proxy)
    temps_ok=false
    camera_ok=false
    dragonball_ok=false
    jirald_ok=false
    
    # Check temps domain
    if curl -f -s --max-time 10 -H "Host: temps.mittn.ca" http://localhost/ >/dev/null 2>&1; then
        temps_ok=true
        echo "  ⭐ temps.mittn.ca responding"
    else
        echo "  ❌ temps.mittn.ca not responding"
    fi
    
    # Check camera domain using /health endpoint
    if curl -f -s --max-time 10 -H "Host: camera.mittn.ca" http://localhost/health >/dev/null 2>&1; then
        camera_ok=true
        echo "  ⭐ camera.mittn.ca responding"
    else
        echo "  ❌ camera.mittn.ca not responding"
    fi
    
    # Check dragonball domain with its API endpoint
    if curl -f -s --max-time 10 -H "Host: dragonball.mittn.ca" http://localhost/api/status >/dev/null 2>&1; then
        dragonball_ok=true
        echo "  ⭐ dragonball.mittn.ca API responding"
    else
        echo "  ❌ dragonball.mittn.ca API not responding"
    fi
    
    # Check jirald domain
    if curl -f -s --max-time 10 -H "Host: jirald.mittn.ca" http://localhost/ >/dev/null 2>&1; then
        jirald_ok=true
        echo "  ⭐ jirald.mittn.ca responding"
    else
        echo "  ❌ jirald.mittn.ca not responding"
    fi
    
    if [ "$temps_ok" = true ] && [ "$camera_ok" = true ] && [ "$dragonball_ok" = true ] && [ "$jirald_ok" = true ]; then
        echo "✅ HTTP health check successful for all domains!"
        health_check_passed=true
        
        # Check HTTPS if certificates exist
        if [ -n "$temps_cert" ] && [ -n "$camera_cert" ] && [ -n "$dragonball_cert" ] && [ -n "$jirald_cert" ]; then
            if curl -f -s -k --max-time 10 https://temps.mittn.ca >/dev/null 2>&1 && \
               curl -f -s -k --max-time 10 https://camera.mittn.ca/health >/dev/null 2>&1 && \
               curl -f -s -k --max-time 10 https://dragonball.mittn.ca/api/status >/dev/null 2>&1 && \
               curl -f -s -k --max-time 10 https://jirald.mittn.ca >/dev/null 2>&1; then
                echo "✅ HTTPS health check successful for all domains!"
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

# Restore original nginx.conf if we're not in CI
if [ "$CI" != "true" ] && [ -f "nginx.conf.backup" ]; then
    echo "🔄 Restoring original nginx.conf..."
    mv nginx.conf.backup nginx.conf
fi

echo ""
echo "🌐 Your applications are accessible at:"
echo "   House Temp Tracker:"
echo "     HTTP:  http://temps.mittn.ca"
if [ -n "$temps_cert" ]; then
    echo "     HTTPS: https://temps.mittn.ca"
fi
echo ""
echo "   Camera Viewer:"
echo "     HTTP:  http://camera.mittn.ca"
if [ -n "$camera_cert" ]; then
    echo "     HTTPS: https://camera.mittn.ca"
fi
echo ""
echo "   DragonBall LED Controller:"
echo "     HTTP:  http://dragonball.mittn.ca"
if [ -n "$dragonball_cert" ]; then
    echo "     HTTPS: https://dragonball.mittn.ca"
fi
echo ""
echo "   Jirald MCP Server:"
echo "     HTTP:  http://jirald.mittn.ca"
if [ -n "$jirald_cert" ]; then
    echo "     HTTPS: https://jirald.mittn.ca"
fi
echo ""
if [ -z "$temps_cert" ] || [ -z "$camera_cert" ] || [ -z "$dragonball_cert" ] || [ -z "$jirald_cert" ]; then
    echo "📝 Some SSL certificates are missing. They should have been generated automatically."
    echo "   If you need to manually generate certificates, run: ./init-letsencrypt.sh"
fi