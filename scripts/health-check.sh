#!/usr/bin/env bash
# Check every app in apps.conf end to end: through the local nginx, to the app,
# on whichever scheme that domain is actually serving.
#
# Usage: health-check.sh [--retries N] [--delay SECONDS]
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

retries=1
delay=10

while [ $# -gt 0 ]; do
    case "$1" in
        --retries) retries="$2"; shift 2 ;;
        --delay) delay="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# --resolve pins the hostname to the local nginx while still sending the right
# Host header and TLS SNI, so this exercises the same server block a real
# visitor would hit rather than whatever the default server happens to be.
check_app() {
    local domain=$1 health=$2
    if cert_exists "$domain"; then
        curl -fsS -k --max-time 10 --resolve "$domain:443:127.0.0.1" \
            "https://$domain$health" -o /dev/null
    else
        curl -fsS --max-time 10 --resolve "$domain:80:127.0.0.1" \
            "http://$domain$health" -o /dev/null
    fi
}

for attempt in $(seq 1 "$retries"); do
    if [ "$retries" -gt 1 ]; then
        echo "🏥 Health check attempt $attempt/$retries..."
    else
        echo "🏥 Health check..."
    fi

    failed=()
    while read -r domain upstream health flags; do
        : "${health:=/}"
        if check_app "$domain" "$health"; then
            echo "   ✅ $domain$health"
        else
            echo "   ❌ $domain$health"
            failed+=("$domain")
        fi
    done < <(apps)

    if [ ${#failed[@]} -eq 0 ]; then
        echo "✅ All applications are responding"
        exit 0
    fi

    if [ "$attempt" -lt "$retries" ]; then
        echo "   Waiting ${delay}s before retrying..."
        sleep "$delay"
    fi
done

echo "❌ Not responding: ${failed[*]}"
echo "   Check that each app's container is running and attached to $NETWORK:"
echo "     docker ps --format '{{.Names}}'"
echo "     docker network inspect $NETWORK"
exit 1
