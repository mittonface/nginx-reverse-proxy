.PHONY: help build up down restart logs status clean validate deploy health-check ssl-init ssl-status

# Default target
help:
	@echo "Available targets:"
	@echo "  help         - Show this help message"
	@echo "  validate     - Validate nginx configuration"
	@echo "  up           - Start the reverse proxy services"
	@echo "  down         - Stop the reverse proxy services"
	@echo "  restart      - Restart the reverse proxy services"
	@echo "  logs         - Show container logs"
	@echo "  status       - Show container status"
	@echo "  deploy       - Deploy the reverse proxy (run deploy.sh)"
	@echo "  health-check - Check if services are responding"
	@echo "  ssl-init     - Initialize SSL certificates"
	@echo "  ssl-status   - Show SSL certificate status"
	@echo "  clean        - Clean up old images and containers"
	@echo "  network      - Create the shared Docker network"

# Validate nginx configuration
validate:
	@echo "🔍 Validating nginx configuration..."
	docker run --rm -v ${PWD}/nginx.conf:/etc/nginx/nginx.conf:ro nginx:alpine nginx -t
	docker run --rm -v ${PWD}/nginx-initial.conf:/etc/nginx/nginx.conf:ro nginx:alpine nginx -t
	docker-compose config -q
	@echo "✅ Configuration is valid"

# Create shared network
network:
	@echo "🔧 Creating shared Docker network..."
	docker network create proxy-network 2>/dev/null || echo "Network already exists"

# Start services
up: network
	@echo "🚀 Starting reverse proxy services..."
	docker-compose up -d

# Stop services
down:
	@echo "🛑 Stopping reverse proxy services..."
	docker-compose down --timeout 30

# Restart services
restart: down up

# Show logs
logs:
	@echo "📋 Container logs:"
	docker-compose logs --tail=50 -f

# Show status
status:
	@echo "📊 Container status:"
	docker-compose ps

# Deploy using script
deploy:
	@echo "🚀 Deploying reverse proxy..."
	./deploy.sh

# Health check
health-check:
	@echo "🏥 Performing health check..."
	@echo "Testing temps.mittn.ca (via nginx proxy)..."
	@curl -f -s --max-time 10 -H "Host: temps.mittn.ca" http://localhost/health >/dev/null && echo "✅ House Temp Tracker: OK" || echo "❌ House Temp Tracker: Failed"
	@echo "Testing camera.mittn.ca (via nginx proxy)..."
	@curl -f -s --max-time 10 -H "Host: camera.mittn.ca" http://localhost/health >/dev/null && echo "✅ Camera Viewer: OK" || echo "❌ Camera Viewer: Failed"
	@echo "Testing direct port access..."
	@curl -f -s --max-time 10 http://localhost:5003/health >/dev/null && echo "✅ House Temp Tracker (port 5003): OK" || echo "❌ House Temp Tracker (port 5003): Failed"
	@curl -f -s --max-time 10 http://localhost:5002/health >/dev/null && echo "✅ Camera Viewer (port 5002): OK" || echo "❌ Camera Viewer (port 5002): Failed"

# Initialize SSL certificates
ssl-init:
	@echo "🔒 Initializing SSL certificates..."
	./init-letsencrypt.sh

# Show SSL certificate status
ssl-status:
	@echo "🔒 SSL Certificate Status:"
	@for domain in temps.mittn.ca camera.mittn.ca; do \
		if [ -f "certbot/conf/live/$$domain/fullchain.pem" ]; then \
			echo "✅ $$domain: Certificate exists"; \
			openssl x509 -in "certbot/conf/live/$$domain/fullchain.pem" -text -noout | grep -A 2 "Validity" || true; \
		else \
			echo "❌ $$domain: No certificate found"; \
		fi; \
	done

# Clean up
clean:
	@echo "🧹 Cleaning up..."
	docker-compose down --timeout 30 || true
	docker image prune -f
	docker container prune -f
	@echo "✅ Cleanup complete"