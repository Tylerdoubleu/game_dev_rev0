#!/usr/bin/env bash
# Installed at /opt/paintball/update.sh; run by paintball-update.timer every 5 min.
# If origin/main moved: hard-reset the server clone to it and restart the game server.
set -euo pipefail
APP=/opt/paintball/app
as_pb() { runuser -u paintball -- "$@"; }
as_pb git -C "$APP" fetch --quiet origin main
LOCAL=$(as_pb git -C "$APP" rev-parse HEAD)
REMOTE=$(as_pb git -C "$APP" rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi
echo "main moved ${LOCAL:0:7} -> ${REMOTE:0:7}; updating"
as_pb git -C "$APP" reset --hard --quiet origin/main
as_pb git -C "$APP" lfs pull >/dev/null 2>&1 || true
# Pick up any changes to the deploy files themselves.
install -m 0644 "$APP/deploy/digitalocean/paintball-server.service" /etc/systemd/system/ 2>/dev/null || true
if [ -f "$APP/deploy/digitalocean/Caddyfile" ] && ! cmp -s "$APP/deploy/digitalocean/Caddyfile" /etc/caddy/Caddyfile; then
  install -m 0644 "$APP/deploy/digitalocean/Caddyfile" /etc/caddy/Caddyfile
  systemctl reload caddy || systemctl restart caddy
fi
systemctl daemon-reload
systemctl restart paintball-server
echo "restarted paintball-server at ${REMOTE:0:7}"
