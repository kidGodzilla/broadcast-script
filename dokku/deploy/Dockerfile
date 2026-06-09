# Thin wrapper around Broadcast's private prebuilt image.
#
# This adds NOTHING to the app — it only re-tags the vendor image so Dokku can
# deploy it with a Procfile (web + worker) and its own start commands instead of
# the image's default Thruster-on-80/443 entrypoint.
#
# To update Broadcast: pull a newer base image and re-deploy (see dokku/SETUP.md).
# Pin a version tag for reproducible deploys, or use :latest to always track newest.
ARG BROADCAST_IMAGE=gitea.hostedapp.org/broadcast/broadcast:latest
FROM ${BROADCAST_IMAGE}

# The vendor image already contains the full Rails app at /rails.
# We deliberately do not override ENTRYPOINT — the Procfile supplies the command.
