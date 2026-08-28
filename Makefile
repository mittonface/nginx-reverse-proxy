.PHONY: help generate validate network up down restart reload logs status deploy health-check ssl-init ssl-status clean

help:
	@echo "Available targets:"
	@echo "  generate     - Render generated/conf.d/ from apps.conf"
	@echo "  validate     - Render the config and check it with 'nginx -t'"
	@echo "  network      - Create the shared Docker network"
	@echo "  up           - Start the reverse proxy services"
	@echo "  down         - Stop the reverse proxy services"
	@echo "  restart      - Restart the reverse proxy services"
	@echo "  reload       - Re-render the config and reload nginx (no downtime)"
	@echo "  logs         - Follow container logs"
	@echo "  status       - Show container status"
	@echo "  deploy       - Full deploy (./deploy.sh)"
	@echo "  health-check - Check that every app in apps.conf responds"
	@echo "  ssl-init     - Issue certificates for any domain that lacks one"
	@echo "  ssl-status   - Show certificate status for every domain in apps.conf"
	@echo "  clean        - Stop services and prune unused images/containers"

generate:
	@SKIP_VALIDATE=1 scripts/generate-config.sh

validate:
	@scripts/generate-config.sh

network:
	@docker network inspect proxy-network >/dev/null 2>&1 \
		|| docker network create proxy-network

up: network validate
	@echo "🚀 Starting reverse proxy services..."
	docker compose up -d

down:
	@echo "🛑 Stopping reverse proxy services..."
	docker compose down --timeout 30

restart: down up

reload: validate
	@docker compose exec -T nginx nginx -s reload && echo "✅ nginx reloaded"

logs:
	docker compose logs --tail=50 -f

status:
	docker compose ps

deploy:
	@./deploy.sh

health-check:
	@scripts/health-check.sh

ssl-init:
	@scripts/ensure-certs.sh

ssl-status:
	@echo "🔒 Certificate status:"
	@grep -Ev '^[[:space:]]*(#|$$)' apps.conf | while read -r domain rest; do \
		cert="certbot/conf/live/$$domain/fullchain.pem"; \
		if [ -f "$$cert" ]; then \
			expiry=$$(openssl x509 -in "$$cert" -noout -enddate | cut -d= -f2); \
			echo "  ✅ $$domain — expires $$expiry"; \
		else \
			echo "  ❌ $$domain — no certificate"; \
		fi; \
	done

clean:
	@echo "🧹 Cleaning up..."
	-docker compose down --timeout 30
	docker image prune -f
	docker container prune -f
	@echo "✅ Cleanup complete"
