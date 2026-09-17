# Dokku deploy wrapper for Broadcast (sendbroadcast.net).
#
# This adds NOTHING to the app. It only re-tags Broadcast's prebuilt private image
# so Dokku can run it with the Procfile in this repo (web + worker) instead of the
# image's default entrypoint (its built-in Thruster TLS server on 80/443, which
# would collide with Dokku terminating TLS in front).
#
# The real app source lives in the image and is pulled at build time via FROM.
# Nothing secret is baked in — registry auth happens on the host (see DOKKU.md).
#
# Upgrade by bumping the tag below and redeploying (see DOKKU.md). The tag is
# pinned, not "latest", so a rebuild can never move the app to a release nobody
# chose — releases carry database migrations, and those do not roll back.
# Override per-host (e.g. for the arm64 image) with:
#   dokku docker-options:add broadcast build \
#     '--build-arg BROADCAST_IMAGE=gitea.hostedapp.org/broadcast/broadcast-arm:2.35.0'
ARG BROADCAST_IMAGE=gitea.hostedapp.org/broadcast/broadcast:2.35.0
FROM ${BROADCAST_IMAGE}
