# Shared helpers for the scripts in this repo. Source it, don't run it.
# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_FILE="$REPO_ROOT/apps.conf"
CERT_DIR="$REPO_ROOT/certbot/conf"
GENERATED_DIR="$REPO_ROOT/generated/conf.d"
NETWORK="proxy-network"

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
else
    COMPOSE=(docker-compose)
fi

# Every non-comment, non-blank line of apps.conf, one app per line.
# Read it as: while read -r domain upstream health flags; do ...; done < <(apps)
apps() {
    if [ ! -f "$APPS_FILE" ]; then
        echo "❌ $APPS_FILE not found" >&2
        return 1
    fi
    grep -Ev '^[[:space:]]*(#|$)' "$APPS_FILE"
}

# has_flag "websocket,ratelimit" websocket
has_flag() {
    case ",${1:--}," in
        *",$2,"*) return 0 ;;
        *) return 1 ;;
    esac
}

cert_exists() {
    [ -f "$CERT_DIR/live/$1/fullchain.pem" ]
}

# Optional per-app config fragment: nginx/snippets/extra-<domain>.conf
extra_snippet() {
    [ -f "$REPO_ROOT/nginx/snippets/extra-$1.conf" ]
}

compose() {
    (cd "$REPO_ROOT" && "${COMPOSE[@]}" "$@")
}
