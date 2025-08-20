# Adding New Applications - Guide for Claude Code

This is a comprehensive checklist for Claude Code to follow when adding new applications to the nginx reverse proxy.

## Required Information to Collect First

Before starting, get these details from the user:
- **Container name**: Exact name from `docker ps` (e.g., `jirald-mcp-server-jirald-github-app-1`)
- **Port**: Internal container port the app listens on (e.g., `8000`)
- **Domain**: Desired domain name (e.g., `jirald.mittn.ca`)
- **Health endpoint**: App-specific health check path (default: `/`, alternatives: `/health`, `/api/status`)

## Files to Update (in order)

### 1. nginx.conf (SSL configuration)
```nginx
# Add domain to HTTP redirect server (line ~32):
server_name temps.mittn.ca camera.mittn.ca dragonball.mittn.ca NEW_DOMAIN.mittn.ca;

# Add new SSL server block before final closing brace:
server {
    listen 443 ssl;
    http2 on;
    server_name NEW_DOMAIN.mittn.ca;

    ssl_certificate /etc/letsencrypt/live/NEW_DOMAIN.mittn.ca/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/NEW_DOMAIN.mittn.ca/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location / {
        set $upstream_newapp CONTAINER_NAME:PORT;
        proxy_pass http://$upstream_newapp;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

### 2. nginx-initial.conf (HTTP configuration)
```nginx
# Add domain to server_name (line ~30):
server_name temps.mittn.ca camera.mittn.ca dragonball.mittn.ca NEW_DOMAIN.mittn.ca;

# Add routing if block before existing proxy_pass (around line ~46):
if ($host = NEW_DOMAIN.mittn.ca) {
    set $upstream_host CONTAINER_NAME:PORT;
}
```

### 3. deploy.sh (multiple sections)

#### 3a. Update domain list (line ~6):
```bash
echo "✅ Using hardcoded domains: temps.mittn.ca, camera.mittn.ca, dragonball.mittn.ca, and NEW_DOMAIN.mittn.ca"
```

#### 3b. Add container check (after line ~36):
```bash
if ! docker ps | grep -q "CONTAINER_NAME"; then
    echo "⚠️  Warning: CONTAINER_NAME is not running"
    echo "   Please ensure NEW_APP_NAME is deployed first"
    services_ready=false
fi
```

#### 3c. Add SSL certificate variables (after line ~62):
```bash
newapp_cert=""
```

#### 3d. Add certificate detection (after dragonball cert check ~line 81):
```bash
if [ -f "certbot/conf/live/NEW_DOMAIN.mittn.ca/fullchain.pem" ]; then
    newapp_cert="NEW_DOMAIN.mittn.ca"
elif [ -f "certbot/conf/live/NEW_DOMAIN.mittn.ca-0001/fullchain.pem" ]; then
    newapp_cert="NEW_DOMAIN.mittn.ca-0001"
fi
```

#### 3e. Update SSL condition (line ~83):
```bash
if [ -n "$temps_cert" ] && [ -n "$camera_cert" ] && [ -n "$dragonball_cert" ] && [ -n "$newapp_cert" ]; then
```

#### 3f. Add certificate output (after line ~87):
```bash
echo "   newapp: $newapp_cert"
```

#### 3g. Add certificate path sed command (after line ~92):
```bash
sed -i "s|/etc/letsencrypt/live/NEW_DOMAIN.mittn.ca/|/etc/letsencrypt/live/$newapp_cert/|g" nginx.conf
```

#### 3h. Add missing cert output (after line ~98):
```bash
echo "   newapp: ${newapp_cert:-\"missing\"}"
```

#### 3i. Add health check variable (line ~125):
```bash
newapp_ok=false
```

#### 3j. Add health check logic (after dragonball check ~line 149):
```bash
# Check NEW_APP domain
if curl -f -s --max-time 10 -H "Host: NEW_DOMAIN.mittn.ca" http://localhost/HEALTH_ENDPOINT >/dev/null 2>&1; then
    newapp_ok=true
    echo "  ⭐ NEW_DOMAIN.mittn.ca responding"
else
    echo "  ❌ NEW_DOMAIN.mittn.ca not responding"
fi
```

#### 3k. Update final health check condition (line ~151):
```bash
if [ "$temps_ok" = true ] && [ "$camera_ok" = true ] && [ "$dragonball_ok" = true ] && [ "$newapp_ok" = true ]; then
```

#### 3l. Add HTTPS health check (in HTTPS section ~line 157):
```bash
curl -f -s -k --max-time 10 https://NEW_DOMAIN.mittn.ca/HEALTH_ENDPOINT >/dev/null 2>&1 && \
```

#### 3m. Add to output section (after dragonball output ~line 202):
```bash
echo ""
echo "   New App Name:"
echo "     HTTP:  http://NEW_DOMAIN.mittn.ca"
if [ -n "$newapp_cert" ]; then
    echo "     HTTPS: https://NEW_DOMAIN.mittn.ca"
fi
```

#### 3n. Update final SSL check (line ~206):
```bash
if [ -z "$temps_cert" ] || [ -z "$camera_cert" ] || [ -z "$dragonball_cert" ] || [ -z "$newapp_cert" ]; then
```

### 4. init-letsencrypt.sh
```bash
# Update domains array (line 8):
domains=("temps.mittn.ca" "camera.mittn.ca" "dragonball.mittn.ca" "NEW_DOMAIN.mittn.ca")
```

### 5. .github/workflows/deploy.yml
```yaml
# Update domain list (line 92):
for domain in "temps.mittn.ca" "camera.mittn.ca" "dragonball.mittn.ca" "NEW_DOMAIN.mittn.ca"; do

# Add certificate check (line 102-104):
[ ! -f "certbot/conf/live/NEW_DOMAIN.mittn.ca/fullchain.pem" ] || \
```

## Post-Update Actions Required

After updating all files, remind user to:

1. **Connect container to network**:
   ```bash
   docker network connect proxy-network CONTAINER_NAME
   ```

2. **Configure DNS**: Add A record for NEW_DOMAIN.mittn.ca → server IP

3. **Deploy**: Run `./deploy.sh`

4. **Generate SSL** (if DNS configured): Run `./init-letsencrypt.sh`

## Common Issues to Watch For

- **Container not found**: Exact container name mismatch from `docker ps`
- **Port mismatch**: Using external port instead of internal container port
- **Network connectivity**: Container must be on proxy-network
- **DNS not ready**: SSL will fail until DNS propagates
- **Health check endpoint**: App might need `/health` instead of `/`

## Testing Commands

After deployment, suggest these tests:
```bash
# Test container connectivity
docker exec nginx-reverse-proxy-nginx-1 nslookup CONTAINER_NAME

# Test HTTP routing
curl -H "Host: NEW_DOMAIN.mittn.ca" http://SERVER_IP/

# Test DNS (if configured)
dig NEW_DOMAIN.mittn.ca

# Test HTTPS (if SSL configured)
curl https://NEW_DOMAIN.mittn.ca/
```

## Variables to Replace

When using this guide:
- `NEW_DOMAIN` → actual domain (e.g., `jirald`)
- `CONTAINER_NAME` → full container name from docker ps
- `PORT` → internal container port
- `HEALTH_ENDPOINT` → health check path (default `/`)
- `NEW_APP_NAME` → human readable app name
- `SERVER_IP` → actual server IP address