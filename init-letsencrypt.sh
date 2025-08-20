#!/bin/bash

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

domains=("temps.mittn.ca" "camera.mittn.ca" "dragonball.mittn.ca" "jirald.mittn.ca")
rsa_key_size=4096
data_path="./certbot"
email="" # Adding a valid address is strongly recommended
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

# Check which domains need certificates
missing_domains=()
for domain in "${domains[@]}"; do
  if [ ! -f "$data_path/conf/live/$domain/fullchain.pem" ] && [ ! -f "$data_path/conf/live/$domain-0001/fullchain.pem" ]; then
    missing_domains+=("$domain")
    echo "📝 Need certificate for: $domain"
  else
    echo "✅ Certificate already exists for: $domain"
  fi
done

if [ ${#missing_domains[@]} -eq 0 ]; then
  echo "✅ All domains already have certificates!"
  exit 0
fi

echo "🔧 Will generate certificates for: ${missing_domains[*]}"

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificates for missing domains ..."
for domain in "${missing_domains[@]}"; do
  path="/etc/letsencrypt/live/$domain"
  mkdir -p "$data_path/conf/live/$domain"
  docker-compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
      -keyout '$path/privkey.pem' \
      -out '$path/fullchain.pem' \
      -subj '/CN=localhost'" certbot
  echo
done

echo "### Starting nginx with initial config ..."
docker-compose up -d nginx
echo

echo "### Deleting dummy certificates for missing domains ..."
for domain in "${missing_domains[@]}"; do
  docker-compose run --rm --entrypoint "\
    rm -Rf /etc/letsencrypt/live/$domain && \
    rm -Rf /etc/letsencrypt/archive/$domain && \
    rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
  echo
done

echo "### Requesting Let's Encrypt certificates for missing domains ..."
for domain in "${missing_domains[@]}"; do
  # Select appropriate email arg
  case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
  esac

  # Enable staging mode if needed
  if [ $staging != "0" ]; then staging_arg="--staging"; fi

  echo "🔒 Requesting certificate for $domain..."
  docker-compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      -d $domain \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot
  echo
done

echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload

echo "✅ Certificate generation complete!"
echo "📝 Generated certificates for: ${missing_domains[*]}"