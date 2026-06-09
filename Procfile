# Two process types from the same image — this is how Dokku runs the web server
# AND the background job worker. Scale both: dokku ps:scale broadcast web=1 worker=1
#
# web:    plain HTTP on Dokku's $PORT (Dokku/nginx terminates TLS in front).
# worker: Solid Queue job runner — REQUIRED for Broadcast to send email.
web: bin/rails server -b 0.0.0.0 -p ${PORT:-3000}
worker: bin/jobs
