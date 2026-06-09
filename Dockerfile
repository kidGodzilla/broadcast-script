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
# Update Broadcast by pulling a newer base image and rebuilding (see DOKKU.md).
# Pin a specific version (or the arm64 image) by overriding the build arg:
#   dokku docker-options:add broadcast build \
#     '--build-arg BROADCAST_IMAGE=gitea.hostedapp.org/broadcast/broadcast:1.2.3'
ARG BROADCAST_IMAGE=gitea.hostedapp.org/broadcast/broadcast:latest
FROM ${BROADCAST_IMAGE}
