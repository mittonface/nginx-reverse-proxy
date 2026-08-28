#!/usr/bin/env bash
# Deploy the reverse proxy. Safe to run repeatedly: it re-renders the config
# from apps.conf and reloads nginx in place rather than restarting it, so
# ordinary deploys do not drop connections.
#
# Usage: ./deploy.sh [--force]
#   --force   do not prompt when an app's container is missing (implied by CI=true)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/lib.sh"
cd "$REPO_ROOT"

force=false
[ "${1:-}" = "--force" ] && force=true
[ "${CI:-}" = "true" ] && force=true

echo "🚀 Deploying nginx-reverse-proxy"

# 1. The shared network the apps and the proxy meet on.
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    echo "✅ Network '$NETWORK' exists"
else
    echo "🔧 Creating network '$NETWORK'..."
    docker network create "$NETWORK"
fi

mkdir -p certbot/conf certbot/www

# 2. Warn about apps whose container is not running. A missing container only
#    502s its own domain, so this is a warning rather than a hard stop.
echo "🔍 Checking upstream containers..."
running="$(docker ps --format '{{.Names}}')"
missing_containers=()
while read -r domain upstream _ _; do
    container="${upstream%%:*}"
    if grep -qx -- "$container" <<<"$running"; then
        echo "   ✅ $container (for $domain)"
    else
        echo "   ⚠️  $container is not running (for $domain)"
        missing_containers+=("$container")
    fi
done < <(apps)

if [ ${#missing_containers[@]} -gt 0 ] && [ "$force" = false ]; then
    read -r -p "Continue anyway? (y/N) " -n 1 reply
    echo
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        exit 1
    fi
fi

# 3. Render and validate the config before it touches the running proxy.
scripts/generate-config.sh

# 4. Start (or update) the proxy itself.
echo "🚀 Starting proxy services..."
compose up -d

# 5. Apply the freshly rendered config without dropping connections.
echo "🔄 Reloading nginx..."
for attempt in $(seq 1 15); do
    if compose exec -T nginx nginx -s reload >/dev/null 2>&1; then
        echo "✅ nginx reloaded"
        break
    fi
    if [ "$attempt" -eq 15 ]; then
        echo "❌ nginx did not become ready" >&2
        compose logs --tail=30 nginx
        exit 1
    fi
    sleep 1
done

# 6. Fill in any missing certificates; this re-renders and reloads if it issues
#    anything, so newly added domains come up on HTTPS in the same deploy.
scripts/ensure-certs.sh

# 7. Confirm every app actually answers through the proxy.
if ! scripts/health-check.sh --retries 6 --delay 10; then
    echo
    echo "Proxy logs:"
    compose logs --tail=30 nginx
    exit 1
fi

echo
echo "✅ Deployment complete. Serving:"
while read -r domain _ _ _; do
    if cert_exists "$domain"; then
        echo "   https://$domain"
    else
        echo "   http://$domain  (no certificate yet)"
    fi
done < <(apps)
