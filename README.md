# nginx-reverse-proxy

One nginx instance that terminates TLS and routes each `*.mittn.ca` hostname to
the right Docker container. The apps themselves publish no host ports; they only
listen on the shared `proxy-network` Docker network.

## How it works

[`apps.conf`](apps.conf) is the only file that lists applications. Everything
else is derived from it:

```
apps.conf ──> scripts/generate-config.sh ──> generated/conf.d/<domain>.conf ──> nginx
         └──> scripts/ensure-certs.sh (issues missing Let's Encrypt certificates)
         └──> scripts/health-check.sh (checks every app end to end)
         └──> Makefile targets, GitHub Actions
```

`generated/` is rendered output and is not checked in. `nginx/nginx.conf` holds
the static `http {}` boilerplate and never changes when apps come and go.

A domain gets an HTTPS server block only once its certificate exists. Until then
it is served over plain HTTP, which is also what lets certbot complete the ACME
challenge for a brand new domain. Certificates are therefore per-app: one domain
missing a certificate no longer affects any of the others.

## Adding an application

1. Add one line to `apps.conf`:

   ```
   myapp.mittn.ca    myapp-web-1:8080    /health    -
   ```

   The upstream is the container name from `docker ps` and the port the app
   listens on *inside* the container.

2. Point a DNS A record for the domain at the server.

3. In the app's own `docker-compose.yml`, join the shared network and stop
   publishing host ports:

   ```yaml
   services:
     web:
       networks: [proxy-network]
   networks:
     proxy-network:
       external: true
   ```

4. Push to `main`, or run `./deploy.sh` on the server. The certificate is issued
   automatically on that same deploy.

### Per-app extras

The `flags` column covers the common cases:

| Flag | Effect |
| --- | --- |
| `websocket` | Proxy `Upgrade`/`Connection` headers and use a 24 hour read timeout |
| `ratelimit` | Apply the shared 10 req/s limit with a burst of 20 |
| `-` | Neither |

For anything else, create `nginx/snippets/extra-<domain>.conf`. It is included in
that domain's server blocks automatically — see
`nginx/snippets/extra-camera.mittn.ca.conf`, which widens the timeouts and sets a
Content-Security-Policy that allows S3 media.

## First-time server setup

```bash
docker network create proxy-network   # once, before any app starts
export LETSENCRYPT_EMAIL=you@example.com
./deploy.sh
```

`LETSENCRYPT_EMAIL` is optional but recommended: without it, Let's Encrypt has no
address to warn about upcoming expiry. In CI it comes from the
`LETSENCRYPT_EMAIL` repository secret.

## Deploying

`./deploy.sh` is idempotent and, in the normal case, has no downtime: it
re-renders the config, validates it with `nginx -t` before applying it, then
reloads nginx in place rather than restarting it.

Pushing to `main` runs the same script over SSH. Required repository secrets:

| Secret | Purpose |
| --- | --- |
| `SERVER_HOST` | Server IP or hostname |
| `SERVER_USER` | SSH user (usually `root`) |
| `SERVER_SSH_KEY` | Private key for that user |
| `LETSENCRYPT_EMAIL` | Optional; expiry warnings from Let's Encrypt |

## Common commands

```bash
make validate      # render the config and check it with nginx -t
make reload        # re-render and reload nginx, no downtime
make health-check  # curl every app in apps.conf through the proxy
make ssl-status    # certificate expiry per domain
make logs
make deploy
```

## Certificates

The `certbot` container renews certificates every 12 hours; the `nginx`
container reloads every 6 hours so renewed certificates are actually picked up.
Certificates are issued with `--cert-name <domain>` so they land at
`certbot/conf/live/<domain>/`, which is the only path the generator looks at.

Note that `--cert-name` is a request rather than a guarantee: if
`certbot/conf/renewal/<domain>.conf` already exists — even as leftover broken
state with no `live/` directory — certbot ignores the requested name and issues
at `<domain>-0001`, `-0002`, and so on instead. `ensure-certs.sh` refuses to
issue when it sees that, rather than spending a certificate the proxy would not
use, and tells you which files to remove to free the name.

To issue certificates for domains that are missing them without a full deploy:

```bash
make ssl-init
```

Set `LETSENCRYPT_STAGING=1` to test against Let's Encrypt's staging CA, which has
much looser rate limits but issues untrusted certificates.

## Troubleshooting

**A domain returns 502.** Its container is down, or is not attached to the
network. Check with `docker ps --format '{{.Names}}'` and
`docker network inspect proxy-network`; attach one with
`docker network connect proxy-network <container>`.

**A domain returns an empty reply.** No server block matched the hostname, so the
catch-all rejected it. Confirm the domain is in `apps.conf` and that the last
deploy actually re-rendered the config (`make generate`, then inspect
`generated/conf.d/`).

**A certificate will not issue.** DNS must resolve to this server and port 80
must be reachable from the internet before the ACME challenge can succeed. Run
`make ssl-init` again once DNS has propagated.

**Config changes did not take effect.** `generated/` is rebuilt on every deploy;
if you edited it directly, your changes were overwritten. Edit `apps.conf` or a
snippet in `nginx/snippets/` instead.
