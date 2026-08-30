#!/usr/bin/env bash
# Issue Let's Encrypt certificates for any domain in apps.conf that does not
# have one yet, then re-render the config so those domains start serving HTTPS.
#
# Renewal is handled separately by the certbot container in docker-compose.yml;
# this script only fills in what is missing.
#
# nginx must already be running: certbot answers the ACME challenge over HTTP
# through the proxy, and the generated config serves /.well-known/acme-challenge/
# for every domain whether or not it has a certificate yet.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Let's Encrypt emails you before a certificate expires, but only if it has an
# address. Set LETSENCRYPT_EMAIL in the environment (or as a GitHub secret) to
# get those warnings.
EMAIL="${LETSENCRYPT_EMAIL:-}"
# Set LETSENCRYPT_STAGING=1 to use the staging CA while testing, which has far
# looser rate limits and issues untrusted certificates.
STAGING="${LETSENCRYPT_STAGING:-0}"
RSA_KEY_SIZE=4096

missing=()
while read -r domain _ _ _; do
    if cert_exists "$domain"; then
        echo "✅ Certificate present for $domain"
    else
        echo "📝 Certificate missing for $domain"
        missing+=("$domain")
    fi
done < <(apps)

if [ ${#missing[@]} -eq 0 ]; then
    echo "✅ Every domain in apps.conf already has a certificate"
    exit 0
fi

# certbot does NOT force the lineage name with --cert-name if that name is
# already claimed by a renewal config: it silently falls back to <domain>-0001,
# -0002, and so on. A renewal config whose live/ directory is missing is dead
# state that squats the name, and issuing against it burns a real certificate
# and still leaves nothing at live/<domain>/. Refuse before spending it.
squatted=()
for domain in "${missing[@]}"; do
    if [ -f "$CERT_DIR/renewal/$domain.conf" ]; then
        squatted+=("$domain")
    fi
done

if [ ${#squatted[@]} -gt 0 ]; then
    echo "❌ These domains have a renewal config but no certificate at live/<domain>/:" >&2
    for domain in "${squatted[@]}"; do
        echo "     $domain  ($CERT_DIR/renewal/$domain.conf)" >&2
    done
    echo "   certbot would ignore --cert-name and issue at $domain-000N instead," >&2
    echo "   spending a real certificate that this proxy would then not use." >&2
    echo >&2
    echo "   Back up certbot/conf, then free the names and re-run:" >&2
    for domain in "${squatted[@]}"; do
        echo "     rm -f  certbot/conf/renewal/$domain.conf" >&2
        echo "     rm -rf certbot/conf/archive/$domain" >&2
    done
    exit 1
fi

echo "🔐 Requesting certificates for: ${missing[*]}"

mkdir -p "$CERT_DIR" "$REPO_ROOT/certbot/www"

certbot_args=(
    --webroot -w /var/www/certbot
    --rsa-key-size "$RSA_KEY_SIZE"
    --agree-tos
    --non-interactive
    --keep-until-expiring
)

if [ -n "$EMAIL" ]; then
    certbot_args+=(--email "$EMAIL" --no-eff-email)
else
    certbot_args+=(--register-unsafely-without-email)
    echo "⚠️  LETSENCRYPT_EMAIL is not set: registering without an email address,"
    echo "   which means no expiry warnings from Let's Encrypt."
fi

if [ "$STAGING" != "0" ]; then
    echo "⚠️  Using the Let's Encrypt STAGING environment (certificates will not be trusted)"
    certbot_args+=(--staging)
fi

issued=0
failed=()
for domain in "${missing[@]}"; do
    echo "🔒 Requesting certificate for $domain..."
    # --cert-name asks for live/<domain>/. It is honoured only when that name is
    # free, which the preflight above guarantees; the check after this call is
    # what catches it being ignored anyway.
    if compose run --rm --entrypoint certbot certbot certonly \
        --cert-name "$domain" -d "$domain" "${certbot_args[@]}"; then
        # Trust the filesystem, not the exit code: certbot reports success even
        # when it has written the certificate to a different lineage name.
        if cert_exists "$domain"; then
            issued=$((issued + 1))
            echo "✅ Issued certificate for $domain"
        else
            failed+=("$domain")
            echo "❌ certbot reported success for $domain but nothing landed at" >&2
            echo "   $CERT_DIR/live/$domain/ -- it most likely wrote a suffixed" >&2
            echo "   lineage instead. Check: certbot certificates" >&2
        fi
    else
        failed+=("$domain")
        echo "❌ Could not issue a certificate for $domain"
        echo "   Usually this means DNS for $domain does not point at this server yet,"
        echo "   or port 80 is not reachable from the internet."
    fi
done

if [ "$issued" -gt 0 ]; then
    echo "🔄 Re-rendering configuration so the new certificates are used..."
    "$REPO_ROOT/scripts/generate-config.sh"
    compose exec -T nginx nginx -s reload
    echo "✅ nginx reloaded with the new certificates"
fi

if [ ${#failed[@]} -gt 0 ]; then
    echo "⚠️  Still without a certificate: ${failed[*]}"
    echo "   Those domains are being served over plain HTTP for now."
fi
