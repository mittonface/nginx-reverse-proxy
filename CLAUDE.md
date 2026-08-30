# nginx-reverse-proxy

## The one rule

`apps.conf` is the single source of truth for which applications this proxy
serves. To add, remove, or change an app, edit that file and nothing else. The
nginx server blocks, certificate issuance, health checks, Makefile targets and
the GitHub Actions workflow all read it.

Never hand-edit `generated/conf.d/` — it is rendered by
`scripts/generate-config.sh` and overwritten on every deploy.

## Layout

- `apps.conf` — one line per app: `domain  container:port  health_path  flags`
- `nginx/nginx.conf` — static `http {}` boilerplate; not app-specific
- `nginx/snippets/` — shared includes, plus `extra-<domain>.conf` escape hatches
  for per-app oddities (picked up automatically if the file exists)
- `scripts/generate-config.sh` — renders `generated/conf.d/` and runs `nginx -t`
- `scripts/ensure-certs.sh` — issues certificates for domains that lack one
- `scripts/health-check.sh` — curls every app through the local proxy
- `scripts/lib.sh` — shared parsing helpers; source it rather than reimplementing
- `deploy.sh` — orchestrates the above

## Conventions

- Certificates always live at `certbot/conf/live/<domain>/`; issuance passes
  `--cert-name "$domain"` to ask for that. There is no `-0001` suffix handling
  anywhere, and none should be reintroduced -- the fix for a suffixed lineage is
  to free the name and re-issue, not to teach the generator about suffixes.
- `--cert-name` is a request, not a guarantee: certbot ignores it and appends
  `-0001`, `-0002`, ... if `renewal/<domain>.conf` already exists, even when that
  config is broken and unusable. `ensure-certs.sh` refuses to issue in that case
  and verifies on the filesystem afterwards rather than trusting certbot's exit
  code.
- Scripts must not modify tracked files. Rendered output goes to `generated/`,
  which is gitignored.
- Deploys reload nginx rather than restarting it. Avoid adding a
  `docker compose down` to the deploy path.
- Use `docker compose` (v2). Scripts get it from `lib.sh` as `compose`.
