# Two process types from the same image — this is how Dokku runs the web server
# AND the background job worker. Scale both: dokku ps:scale broadcast web=1 worker=1
#
# The web line MUST end in exactly "bin/rails server", with no flags after it.
# The image's ENTRYPOINT (/rails/bin/docker-entrypoint) gates its startup work on
#   [ "${@: -2:1}" == "bin/rails" ] && [ "${@: -1:1}" == "server" ]
# and that block runs db:prepare *and* recreates the solid_cable_messages table
# missing from installs upgraded through v1.24.0–v1.27.7. Appending "-b 0.0.0.0
# -p $PORT" moves the last two args to "-p" and "<port>", so the guard silently
# fails and neither runs. Bind/port therefore go through the environment instead
# (dokku config: BINDING=0.0.0.0, PORT=3000), which Rails reads natively.
#
# We deliberately do NOT use the image's default CMD (thrust bin/rails server):
# Thruster would see TLS_DOMAIN and start its own ACME/TLS listener on 80/443,
# colliding with Dokku's nginx, which already terminates TLS in front.
web: bin/rails server
# Solid Queue runner — REQUIRED for Broadcast to send anything. The guard above
# does not match "bin/jobs", so the worker never races the web container to migrate.
worker: bin/jobs
