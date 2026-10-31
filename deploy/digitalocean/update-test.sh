#!/usr/bin/env bash
# Installed at /opt/paintball-test/update.sh; run by paintball-test-update.timer every 5 min.
# If origin/test moved: hard-reset the TEST clone to it and restart ONLY paintball-test-server.
# Never touches the live clone, the live service, or Caddy (Caddy config is owned by main's update.sh).
set -euo pipefail
APP=/opt/paintball-test/app
BRANCH=test
as_pb() { runuser -u paintball -- "$@"; }
as_pb git -C "$APP" fetch --quiet origin "$BRANCH"
LOCAL=$(as_pb git -C "$APP" rev-parse HEAD)
REMOTE=$(as_pb git -C "$APP" rev-parse "origin/$BRANCH")
if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi
echo "$BRANCH moved ${LOCAL:0:7} -> ${REMOTE:0:7}; updating test"
as_pb git -C "$APP" reset --hard --quiet "origin/$BRANCH"
as_pb git -C "$APP" lfs pull >/dev/null 2>&1 || true
# Pick up changes to the test unit itself (from the test branch).
if [ -f "$APP/deploy/digitalocean/paintball-test-server.service" ]; then
  install -m 0644 "$APP/deploy/digitalocean/paintball-test-server.service" /etc/systemd/system/
fi
systemctl daemon-reload
systemctl restart paintball-test-server
echo "restarted paintball-test-server at ${REMOTE:0:7}"
