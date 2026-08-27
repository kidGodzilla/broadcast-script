# Dokku deploy wrapper for Broadcast (sendbroadcast.net).
#
# Beyond one patched view (bottom of this file), this adds nothing to the app. It
# only re-tags Broadcast's prebuilt private image so Dokku can run it with the
# Procfile in this repo (web + worker) instead of the image's default entrypoint
# (its built-in Thruster TLS server on 80/443, which would collide with Dokku
# terminating TLS in front).
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

# ---------------------------------------------------------------------------
# Patch: "System Permissions" form posts to a non-existent URL (PATCH → 404).
#
# app/views/user_system_permissions/edit.html.erb calls a SINGULAR-resource
# helper with one argument too many:
#
#   user_user_system_permission_path(@user, @user_system_permission)
#
# The route is `resource :user_system_permission` nested in `resources :users`,
# all inside `scope 'c/:channel_slug'`, so the path has exactly two dynamic
# segments: :channel_slug and :user_email. With two positional args Rails fills
# them in order — channel_slug gets the user (to_param = email), user_email gets
# the permission record (to_param = id):
#
#   /c/thomas@example.com/users/2/system_permissions   → No route matches [PATCH]
#
# (:channel_slug has no constraint, so the dots in the email can't match it
# either way.) One argument is correct: :channel_slug then comes from
# default_url_options, which is why the edit link — edit_user_user_system_
# permission_path(@user) — builds the right URL on the same page.
#
# Remove this block when upstream fixes it; the grep guard fails the build then.
USER root
RUN set -eux; \
    f=/rails/app/views/user_system_permissions/edit.html.erb; \
    grep -q 'user_user_system_permission_path(@user, @user_system_permission)' "$f"; \
    sed -i 's/user_user_system_permission_path(@user, @user_system_permission)/user_user_system_permission_path(@user)/' "$f"; \
    grep -q 'user_user_system_permission_path(@user),' "$f"
USER rails
