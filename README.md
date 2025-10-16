# Nginx Reverse Proxy

This project provides a unified nginx reverse proxy for routing traffic to multiple Docker applications on the same server.

## Setup

1. Create the shared Docker network (run once):
   ```bash
   docker network create proxy-network
   ```

2. The domains are hardcoded in the configuration:
   - `temps.mittn.ca` - House temperature tracker
   - `camera.mittn.ca` - Camera viewer

3. Update your applications:
   - Both `house-temp-tracker` and `camera-viewer` have been modified to:
     - Remove nginx and certbot services
     - Connect to the shared `proxy-network`
     - Only expose ports internally (not bind to host ports)

4. Start your applications:
   ```bash
   cd ../house-temp-tracker && docker-compose up -d
   cd ../camera-viewer && docker-compose up -d
   ```

5. Initialize SSL certificates:
   ```bash
   cd ../nginx-reverse-proxy
   # Edit init-letsencrypt.sh to add your email address (recommended)
   ./init-letsencrypt.sh
   ```

6. Start the reverse proxy:
   ```bash
   docker-compose up -d
   ```

## Architecture

- Single nginx instance handles SSL termination and routing for both domains
- Each application runs in its own container without exposing ports to the host
- All containers communicate via the shared `proxy-network`
- Certbot handles automatic SSL certificate renewal

## Deployment

### Manual Deployment

1. Run the deployment script:
   ```bash
   ./deploy.sh
   ```

### Automated Deployment (GitHub Actions)

The project includes GitHub Actions workflow for automated deployment:

1. Set up GitHub secrets in your repository:
   - `SERVER_HOST` - Your server's IP address or hostname
   - `SERVER_USER` - SSH username (usually `root`)
   - `SERVER_SSH_KEY` - Private SSH key for server access

2. Push to `main` branch to trigger deployment

Note: Domains are hardcoded as `temps.mittn.ca` and `camera.mittn.ca`

### Using Makefile

The project includes a Makefile for common operations:

```bash
# Show available commands
make help

# Validate configuration
make validate

# Deploy the reverse proxy
make deploy

# Check service health
make health-check

# View SSL certificate status
make ssl-status

# Initialize SSL certificates
make ssl-init

# View logs
make logs

# Clean up resources
make clean
```

## Troubleshooting

- Ensure the `proxy-network` exists before starting any services
- Check that container names match those in the nginx upstream configuration
- Verify domains are correctly set in the `.env` file
- Check nginx logs: `docker-compose logs nginx`
- Use `make health-check` to test if services are responding
- Use `make ssl-status` to check SSL certificate status
- 
