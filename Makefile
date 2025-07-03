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
	@if [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs); \
		echo "Testing $$HOUSE_TEMP_DOMAIN..."; \
		curl -f -s --max-time 10 -H "Host: $$HOUSE_TEMP_DOMAIN" http://localhost >/dev/null && echo "✅ House Temp Tracker: OK" || echo "❌ House Temp Tracker: Failed"; \
		curl -f -s --max-time 10 -H "Host: $$CAMERA_DOMAIN" http://localhost >/dev/null && echo "✅ Camera Viewer: OK" || echo "❌ Camera Viewer: Failed"; \
	else \
		echo "❌ .env file not found"; \
	fi

# Initialize SSL certificates
ssl-init:
	@echo "🔒 Initializing SSL certificates..."
	./init-letsencrypt.sh

# Show SSL certificate status
ssl-status:
	@echo "🔒 SSL Certificate Status:"
	@if [ -f .env ]; then \
		export $$(cat .env | grep -v '^#' | xargs); \
		for domain in $$HOUSE_TEMP_DOMAIN $$CAMERA_DOMAIN; do \
			if [ -f "certbot/conf/live/$$domain/fullchain.pem" ]; then \
				echo "✅ $$domain: Certificate exists"; \
				openssl x509 -in "certbot/conf/live/$$domain/fullchain.pem" -text -noout | grep -A 2 "Validity" || true; \
			else \
				echo "❌ $$domain: No certificate found"; \
			fi; \
		done; \
	else \
		echo "❌ .env file not found"; \
	fi

# Clean up
clean:
	@echo "🧹 Cleaning up..."
	docker-compose down --timeout 30 || true
	docker image prune -f
	docker container prune -f
	@echo "✅ Cleanup complete"