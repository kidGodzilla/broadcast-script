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

## 2. Postgres + the three databases

Broadcast is a Rails 8 app using Solid Queue / Cache / Cable, which each want their
own database. The plugin makes one; create the other two:

```bash
dokku postgres:create broadcast-db
dokku postgres:connect broadcast-db <<'SQL'
CREATE DATABASE broadcast_primary_production;
CREATE DATABASE broadcast_queue_production;
CREATE DATABASE broadcast_cable_production;
SQL
```

## 3. Create the app

```bash
dokku apps:create broadcast
dokku postgres:link broadcast-db broadcast        # joins networks + injects DATABASE_URL

# Persistent storage, shared by both web and worker processes:
mkdir -p /var/lib/dokku/data/storage/broadcast/{storage,uploads}
chown -R dokku:dokku /var/lib/dokku/data/storage/broadcast
dokku storage:mount broadcast /var/lib/dokku/data/storage/broadcast/storage:/rails/storage
dokku storage:mount broadcast /var/lib/dokku/data/storage/broadcast/uploads:/rails/uploads
```

## 4. Configuration

Broadcast wants `DATABASE_HOST/USERNAME/PASSWORD` (it derives the three db names
itself), not the `DATABASE_URL` the plugin injects. Pull the values from the linked
service (`dokku postgres:info broadcast-db`) and set everything:

```bash
dokku config:set --no-restart broadcast \
  RAILS_ENV=production \
  SECRET_KEY_BASE="$(openssl rand -hex 64)" \
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
- `TLS_DOMAIN` is used for link generation / host auth even though Dokku (not the
  app) serves TLS.
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

TLS is yours to wire up however you already do it (e.g. `dokku certs:add` with your
cert, Dokku global certs, or an upstream proxy / Cloudflare).

> **Optional — automatic TLS via Let's Encrypt.** If you don't already have certs
> and just want Dokku to handle them, install the plugin and enable it:
> ```bash
> sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
> dokku letsencrypt:set broadcast email you@example.com
> dokku letsencrypt:enable broadcast
> dokku letsencrypt:cron-job --add        # auto-renew
> ```
> Requires the domain's DNS to already point at the Dokku host (port 80 reachable).

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
