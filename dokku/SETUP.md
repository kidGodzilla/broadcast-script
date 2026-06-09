# Running Broadcast on Dokku (native app)

This deploys Broadcast as a real Dokku app — you get Dokku's vhost, automatic
Let's Encrypt TLS, `dokku config:set`, scaling, and `git push`-to-deploy — while
running the **same prebuilt private image** the official installer uses. You do
**not** fork Broadcast and you do **not** build the app yourself.

## How this differs from the official root installer

The official [`broadcast.sh install`](../broadcast.sh) sets up a whole Ubuntu box:
the `broadcast` user, UFW, fail2ban, swap, Docker, a systemd unit running
[`docker-compose.yml`](../docker-compose.yml) (app + job + postgres), the app's
**built-in Thruster TLS on 80/443**, plus `monitor`/`trigger`/`update` crons that
phone host metrics back to your dashboard.

On Dokku you replace that orchestration layer with Dokku itself:

| Concern            | Official installer            | This Dokku setup                          |
|--------------------|-------------------------------|-------------------------------------------|
| Web + worker       | compose `app` + `job`         | one Dokku app, `web` + `worker` processes |
| TLS / vhost        | app's Thruster (80/443)       | Dokku nginx + `letsencrypt` plugin        |
| Database           | compose `postgres` (3 dbs)    | standalone Postgres container (3 dbs)     |
| App config         | `app/.env` file               | `dokku config:set`                        |
| Lifecycle          | systemd + `broadcast.sh`      | `dokku ps:*`, `git push`                  |
| Host metrics / triggers / log-stream | crons + systemd watchers | **not wired** (managed-host features) |

The last row is the trade-off: the dashboard "host metrics", remote `trigger`s,
and live log streaming are tied to the managed layout and are skipped here. The
core product (web app + sending + jobs) is fully functional.

---

## Prerequisites

- A working Dokku host (this guide assumes Dokku ≥ 0.30) with the **letsencrypt**
  plugin installed (`sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git`).
- DNS for your domain pointed at the Dokku host.
- Your Broadcast **license key** and the **registry credentials** for the private
  image. Get the registry creds either from your dashboard or by running, anywhere:
  ```bash
  curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"key":"YOUR_LICENSE_KEY","domain":"broadcast.example.com"}' \
    https://sendbroadcast.net/license/check
  # -> { "registry_url": ..., "registry_login": ..., "registry_password": ... }
  ```
- This repo cloned on the Dokku host (so `git pull` updates the DB init script and
  these files):
  ```bash
  git clone https://github.com/send-broadcast/broadcast-script.git /opt/broadcast-dokku
  cd /opt/broadcast-dokku
  ```

---

## 1. Authenticate to the private registry (build-time pull)

Dokku builds with the host Docker daemon, so a host-level `docker login` is enough
for the `FROM` pull in our wrapper Dockerfile:

```bash
docker login <registry_url> -u <registry_login> -p <registry_password>
```

## 2. Create the shared network

The app and the Postgres container talk over a user-defined Docker network:

```bash
dokku network:create broadcast
```

## 3. Start Postgres (3 databases)

```bash
cd dokku/postgres
cp .env.sample .env
# edit .env: set a strong POSTGRES_PASSWORD (remember it for step 5)
docker compose up -d
docker compose logs -f postgres   # wait for "Multiple databases created"
```

This reuses the vendor's own [init script](../../db/init-scripts/create-multiple-databases.sh),
so it creates exactly the db names the app expects. It listens only on the
`broadcast` network as host `broadcast-postgres` (no public port).

## 4. Create the Dokku app

```bash
dokku apps:create broadcast
# Join the shared network for both the predeploy (db:prepare) and runtime containers:
dokku network:set broadcast attach-post-create broadcast
dokku network:set broadcast attach-post-deploy broadcast
```

Persistent storage shared by both `web` and `worker` processes:

```bash
mkdir -p /var/lib/dokku/data/storage/broadcast/{storage,uploads}
chown -R dokku:dokku /var/lib/dokku/data/storage/broadcast
dokku storage:mount broadcast /var/lib/dokku/data/storage/broadcast/storage:/rails/storage
dokku storage:mount broadcast /var/lib/dokku/data/storage/broadcast/uploads:/rails/uploads
```

## 5. Set configuration

Generate secrets and set them as Dokku config. Fill in real values (see
[`broadcast.env.sample`](broadcast.env.sample) for the full list and notes):

```bash
dokku config:set --no-restart broadcast \
  RAILS_ENV=production \
  SECRET_KEY_BASE="$(openssl rand -hex 64)" \
  DATABASE_HOST=broadcast-postgres \
  DATABASE_USERNAME=broadcast \
  DATABASE_PASSWORD='<same as POSTGRES_PASSWORD from step 3>' \
  TLS_DOMAIN=broadcast.example.com \
  LICENSE_KEY='<your license key>' \
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="$(openssl rand -hex 16)" \
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="$(openssl rand -hex 16)" \
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="$(openssl rand -hex 16)"
```

> Save those three encryption keys somewhere safe. If you ever lose them you lose
> access to every encrypted column (API keys, etc.).

## 6. Deploy the image

Deploy the thin wrapper in [`dokku/deploy/`](deploy/) (Dockerfile + Procfile).
Push it as a tiny git repo to Dokku:

```bash
cd dokku/deploy
git init && git add -A && git commit -m "Broadcast deploy wrapper"
git remote add dokku dokku@<your-dokku-host>:broadcast
git push dokku master   # Dokku builds (just pulls the base image) and boots `web`
```

Then run the worker too:

```bash
dokku ps:scale broadcast web=1 worker=1
```

Map the public port to the container's HTTP port. The `web` process binds whatever
`$PORT` Dokku injects, so map to that exact value rather than guessing:

```bash
PORT=$(dokku config:get broadcast PORT)   # e.g. 5000
dokku ports:set broadcast http:80:${PORT}
```

If `dokku config:get` returns nothing, check `dokku ports:report broadcast` for the
container port Dokku detected and map `http:80:<that-port>`. (The letsencrypt step
below adds the `https:443` mapping on top of this.)

## 7. Domain + TLS

```bash
dokku domains:set broadcast broadcast.example.com
dokku letsencrypt:set broadcast email you@example.com
dokku letsencrypt:enable broadcast
dokku letsencrypt:cron-job --add
```

Visit `https://broadcast.example.com` and create your admin account.

---

## Updating

Two independent streams — **neither requires a fork or a rebuild of the app code:**

**App image (new Broadcast release):** the wrapper's `FROM` tracks `:latest`, so pull
the new base and re-deploy:

```bash
docker login <registry_url> -u <registry_login> -p <registry_password>   # if creds rotated
docker pull gitea.hostedapp.org/broadcast/broadcast:latest
dokku ps:rebuild broadcast        # rebuilds wrapper from the freshly pulled base
```

To pin/upgrade to a specific version instead of `:latest`, build with a build-arg:

```bash
dokku docker-options:add broadcast build '--build-arg BROADCAST_IMAGE=gitea.hostedapp.org/broadcast/broadcast:1.2.3'
dokku ps:rebuild broadcast
```

DB migrations run automatically on each deploy via the `predeploy` hook in
[`app.json`](deploy/app.json) (`bin/rails db:prepare`).

**This tooling (scripts, init script, these files):**

```bash
cd /opt/broadcast-dokku && git pull
```

Your secrets live in Dokku config and in `postgres/.env` (gitignored), so pulls
never conflict with your customizations.

---

## Backups

Dump only the primary db (queue/cable are ephemeral, same policy as the vendor's
[`backup.sh`](../scripts/backup.sh)):

```bash
docker exec broadcast-postgres pg_dump -U broadcast broadcast_primary_production \
  | gzip > dokku/postgres/backups/primary-$(date +%F).sql.gz
```

Restore:

```bash
gunzip -c backup.sql.gz | docker exec -i broadcast-postgres \
  psql -U broadcast broadcast_primary_production
```

## Useful commands

```bash
dokku logs broadcast -t                 # tail web logs
dokku logs broadcast -t -p worker       # tail worker logs
dokku run broadcast bin/rails console   # Rails console
dokku ps:report broadcast               # process / scale status
```
