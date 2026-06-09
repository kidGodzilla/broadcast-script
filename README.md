# Broadcast on Dokku

A fork of [send-broadcast/broadcast-script](https://github.com/send-broadcast/broadcast-script)
that deploys [Broadcast](https://sendbroadcast.net) as a native **Dokku** app from
its prebuilt private image — instead of the official root installer that provisions
a whole dedicated Ubuntu server.

**→ See [DOKKU.md](DOKKU.md) for the full setup guide.**

This repo is public. It contains **no secrets** — the license key, registry
credentials, and app config all live in `dokku config` on your server, never in git.

## What's here

- [`Dockerfile`](Dockerfile) / [`Procfile`](Procfile) / [`app.json`](app.json) —
  the tiny deploy wrapper Dokku builds. The `Dockerfile` only re-tags the vendor
  image (`FROM`); the `Procfile` runs the `web` server and `worker` (job runner).
- [`DOKKU.md`](DOKKU.md) — step-by-step: registry login, Postgres, config, deploy,
  upgrades.
- The original installer (`broadcast.sh`, `scripts/`, `docker-compose*.yml`, …) is
  left intact from upstream for reference. It is **not** used by the Dokku flow.

## Updating from upstream

```bash
git pull upstream main     # upstream = send-broadcast/broadcast-script
```

## License

Broadcast is commercial software for licensed customers. This fork only adds Dokku
deployment glue; refer to the license that came with your Broadcast product for the
terms of use of the application itself.
