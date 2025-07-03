# Nginx Reverse Proxy

This project provides a unified nginx reverse proxy for routing traffic to multiple Docker applications on the same server.

## Setup

1. Create the shared Docker network (run once):
   ```bash
   docker network create proxy-network
   ```

2. Copy the environment file and configure your domains:
   ```bash
   cp .env.example .env
   ```
   Edit `.env` to set your actual domains:
   - `HOUSE_TEMP_DOMAIN` - Domain for the house temperature tracker
   - `CAMERA_DOMAIN` - Domain for the camera viewer

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

## Troubleshooting

- Ensure the `proxy-network` exists before starting any services
- Check that container names match those in the nginx upstream configuration
- Verify domains are correctly set in the `.env` file
- Check nginx logs: `docker-compose logs nginx`