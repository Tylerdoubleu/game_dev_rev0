#!/usr/bin/env bash
# One-shot, idempotent provisioning for a fresh Ubuntu 24.04 droplet.
# Usage (as root on the droplet):  PAINTBALL_HOST="play.jeetball.com, 1-2-3-4.sslip.io" bash setup.sh
set -euo pipefail
: "${PAINTBALL_HOST:?set PAINTBALL_HOST, e.g. 134-199-181-82.sslip.io}"
REPO=https://github.com/Tylerdoubleu/game_dev_rev0.git
GODOT_VER=4.7.2
export DEBIAN_FRONTEND=noninteractive

# 2 GB swap
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 && echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
fi

apt-get update -q
apt-get install -y -q ca-certificates curl gnupg git git-lfs unzip libfontconfig1 unattended-upgrades \
  debian-keyring debian-archive-keyring apt-transport-https
dpkg-reconfigure -f noninteractive unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'X'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
X

# Node 20 (NodeSource)
if ! node -v 2>/dev/null | grep -q '^v20'; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -q nodejs
fi

# Caddy (official repo)
if ! command -v caddy >/dev/null; then
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q && apt-get install -y -q caddy
fi

# Godot headless runtime
if ! /usr/local/bin/godot --version 2>/dev/null | grep -q "^${GODOT_VER}"; then
  curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip" -o /tmp/godot.zip
  unzip -q -o /tmp/godot.zip -d /tmp/
  install -m 0755 "/tmp/Godot_v${GODOT_VER}-stable_linux.x86_64" /usr/local/bin/godot
  rm -f /tmp/godot.zip "/tmp/Godot_v${GODOT_VER}-stable_linux.x86_64"
fi

# Service user + clone of main
id paintball >/dev/null 2>&1 || useradd --system --home /opt/paintball --create-home --shell /usr/sbin/nologin paintball
if [ ! -d /opt/paintball/app/.git ]; then
  runuser -u paintball -- git clone --branch main "$REPO" /opt/paintball/app
fi
runuser -u paintball -- git -C /opt/paintball/app lfs install --local >/dev/null 2>&1 || true
runuser -u paintball -- git -C /opt/paintball/app lfs pull >/dev/null 2>&1 || true
runuser -u paintball -- env HOME=/opt/paintball /usr/local/bin/godot --headless --path /opt/paintball/app --import >/dev/null 2>&1 || true

D=/opt/paintball/app/deploy/digitalocean
SRC=${DEPLOY_SRC:-$D}
install -m 0755 "$SRC/update.sh" /opt/paintball/update.sh
install -m 0644 "$SRC/paintball-server.service" "$SRC/paintball-update.service" "$SRC/paintball-update.timer" /etc/systemd/system/
install -m 0644 "$SRC/Caddyfile" /etc/caddy/Caddyfile
install -m 0755 "$SRC/backup-live.sh" /usr/local/sbin/paintball-backup-live.sh
install -m 0644 "$SRC/paintball-backup.service" "$SRC/paintball-backup.timer" /etc/systemd/system/
mkdir -p /etc/systemd/system/caddy.service.d
printf '[Service]\nEnvironment=PAINTBALL_HOST=%s\n' "$PAINTBALL_HOST" > /etc/systemd/system/caddy.service.d/paintball.conf

systemctl daemon-reload
systemctl enable --now paintball-server.service paintball-update.timer paintball-backup.timer
systemctl enable caddy && systemctl restart caddy
echo "done: https://${PAINTBALL_HOST}/healthz  wss://${PAINTBALL_HOST}/ws"
