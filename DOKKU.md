# Deploying Broadcast on Dokku

This fork deploys [Broadcast](https://sendbroadcast.net) as a native Dokku app from
its prebuilt **private** image — instead of the official root installer that takes
over a whole Ubuntu box. You get Dokku's vhost, scaling, and `git push` deploys.

No app source lives here. The [`Dockerfile`](Dockerfile) just re-tags the vendor
image; the [`Procfile`](Procfile) runs the web server + job worker. **This repo is
public — every secret below goes into `dokku config`, never into git.**

What the official installer does that this does **not**: dashboard host-metrics,
remote triggers, and live log streaming (they're tied to the managed host layout).
The core product — web app, sending, background jobs, upgrades — works fully.

---

## Prerequisites

- A Dokku host, DNS for your domain pointed at it.
- Your Broadcast **license key** + **registry credentials**. Get the creds from
  your dashboard, or:
  ```bash
  curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"key":"YOUR_LICENSE_KEY","domain":"broadcast.example.com"}' \
    https://sendbroadcast.net/license/check
  # -> { registry_url, registry_login, registry_password }
  ```

## 1. Log the host into the private registry

Dokku builds with the host Docker daemon, so the build-time `FROM` pull needs:

```bash
dokku registry:login <registry_url> <registry_login> <registry_password>
```

## 2. Postgres + the queue and cable databases

Broadcast is a Rails 8 app whose `config/database.yml` declares three production
databases — `primary`, `queue` (Solid Queue), and `cable` (Solid Cable). Solid
Cache is not among them.

Only two of them need creating. `postgres:link` (step 3) injects `DATABASE_URL`,
Rails merges that into the `primary` entry, and primary therefore lands in the
plugin's own database — `broadcast_db`. The `broadcast_primary_production` named
in `database.yml` is overridden and never used, so don't create it and don't go
looking for it.

```bash
dokku postgres:create broadcast-db
dokku postgres:connect broadcast-db <<'SQL'
CREATE DATABASE broadcast_queue_production;
CREATE DATABASE broadcast_cable_production;
SQL
```

This matters for backups. `broadcast_db` holds subscribers, broadcasts, users —
everything you cannot regenerate — and it is exactly what `dokku postgres:export
broadcast-db` dumps, so the plugin's default export is the backup you want. Queue
and cable hold job and cable rows and can be rebuilt.

## 3. Create the app

```bash
dokku apps:create broadcast
dokku postgres:link broadcast-db broadcast        # joins networks + injects DATABASE_URL

# Persistent storage, shared by both web and worker processes.
# nobody:nogroup + 777 sidesteps matching the image's runtime uid — sloppy but it
# always works regardless of which user the container runs as:
mkdir -p /var/lib/dokku/data/storage/broadcast/{storage,uploads}
chown -R nobody:nogroup /var/lib/dokku/data/storage/broadcast
chmod -R 777 /var/lib/dokku/data/storage/broadcast
dokku storage:mount broadcast /var/lib/dokku/data/storage/broadcast/storage:/rails/storage
dokku storage:mount broadcast /var/lib/dokku/data/storage/broadcast/uploads:/rails/uploads

# File descriptors. Docker starts containers at soft nofile 1024 no matter how high
# the host's limits are — raising DefaultLimitNOFILE or the docker unit's LimitNOFILE
# lifts the *hard* ceiling only, so containers still get 1024 soft unless you ask.
# Upstream shipped this in compose after a customer outage: ~65 webhooks/s exhausted
# the descriptors, Puma logged Errno::EMFILE, and the site served 502s for 31 minutes
# while every health signal still read green. Verify with:
#   docker inspect -f '{{.State.Pid}}' <container>  # then grep 'Max open files' /proc/<pid>/limits
dokku docker-options:add broadcast deploy '--ulimit nofile=65536:65536'
dokku docker-options:add broadcast run '--ulimit nofile=65536:65536'
```

## 4. Configuration

Broadcast reads `DATABASE_HOST/USERNAME/PASSWORD` to reach the `queue` and `cable`
databases; the `DATABASE_URL` that `postgres:link` already injected is what points
`primary` at `broadcast_db`. Leave that variable alone and add the rest — the values
come from `dokku postgres:info broadcast-db`:

```bash
dokku config:set --no-restart broadcast \
  RAILS_ENV=production \
  SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  BINDING=0.0.0.0 \
  PORT=3000 \
  DATABASE_HOST=dokku-postgres-broadcast-db \
  DATABASE_USERNAME=postgres \
  DATABASE_PASSWORD='<from postgres:info>' \
  TLS_DOMAIN=broadcast.example.com \
  LICENSE_KEY='<your license key>' \
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="$(openssl rand -hex 16)" \
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="$(openssl rand -hex 16)" \
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="$(openssl rand -hex 16)"
```

Notes:
- **Save the three encryption keys.** Lose them and you lose every encrypted column
  (API keys, etc.). The official installer auto-generates these; here you own them.
- `BINDING`/`PORT` are how the web process gets its bind address, and they are not
  optional. The [`Procfile`](Procfile) must end in exactly `bin/rails server` for
  the image's entrypoint to run `db:prepare` and its `solid_cable_messages` repair,
  so the usual `-b 0.0.0.0 -p $PORT` flags cannot be used — Rails reads both from
  the environment instead. Pair with `dokku ports:set <app> http:80:3000`.
- `TLS_DOMAIN` is used for link generation / host auth even though Dokku (not the
  app) serves TLS. Keep the Procfile off the image's default `thrust` CMD: Thruster
  reads `TLS_DOMAIN` and would start its own ACME listener on 80/443, fighting nginx.
- Don't set `BROADCAST_MANAGED` or `STORAGE_PATH` — those drive the managed host
  features and the app's built-in TLS, both bypassed here.

## 5. Deploy

```bash
git remote add dokku dokku@<your-dokku-host>:broadcast
git push dokku main
dokku ps:scale broadcast web=1 worker=1
```

DB migrations run automatically on each deploy via the `predeploy` hook in
[`app.json`](app.json).

## 6. Domain + TLS

```bash
dokku domains:set broadcast broadcast.example.com
```

TLS is yours to wire up however you already do it. The two common paths are
mutually exclusive in one important way — **they need opposite DNS settings**, so
pick before you create the record:

**A. Behind a proxying CDN (Cloudflare orange-cloud, Fastly, etc.)** — install an
origin certificate and let the CDN terminate TLS at its edge:
```bash
dokku certs:add broadcast < origin-cert-and-key.tar
```
The DNS record must be **proxied**. Origin certs are trusted only by the CDN, so a
DNS-only record makes browsers hit the origin directly and see an untrusted cert.
Wildcard origin certs cover every subdomain at once and last years, so there is no
renewal cron to forget.

**B. Let's Encrypt, direct to the host** — only when nothing proxies in front:
```bash
sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
dokku letsencrypt:set broadcast email you@example.com
dokku letsencrypt:enable broadcast
dokku letsencrypt:cron-job --add        # auto-renew, every 90 days
```
The HTTP-01 challenge needs port 80 to reach *this* host, so the record must be
**DNS-only**. Enabling this behind a proxy fails the challenge; turning the proxy
off to satisfy it silently gives up whatever the CDN was providing.

If routing 502s, check the container port Dokku detected and map it:

```bash
dokku ports:report broadcast
dokku ports:set broadcast http:80:$(dokku config:get broadcast PORT)
```

Then open your domain and create the admin account.

---

## Upgrades

ssh in, then:

**New Broadcast release** (`FROM` tracks `:latest`):
```bash
docker pull gitea.hostedapp.org/broadcast/broadcast:latest
dokku ps:rebuild broadcast        # rebuilds the wrapper from the fresh base image
```
To pin a version instead, see the build-arg note in [`Dockerfile`](Dockerfile).

**This repo's deploy files / docs:**
```bash
git pull upstream main   # then resolve as needed, push to your fork + dokku
```

## Backups

Only the primary db matters (queue/cable are ephemeral):

```bash
dokku postgres:export broadcast-db > broadcast-$(date +%F).dump
```
(`dokku postgres:import broadcast-db < file.dump` to restore.) Note this dumps the
plugin's default database; to back up `broadcast_primary_production` specifically,
`dokku postgres:connect` + `pg_dump` that database by name.

## Handy

```bash
dokku logs broadcast -t                 # web logs
dokku logs broadcast -t -p worker       # worker logs
dokku run broadcast bin/rails console   # console
```
