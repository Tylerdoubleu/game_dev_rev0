# Always-on multiplayer server (DigitalOcean)

One always-on DigitalOcean droplet runs the same stack Edgegap ran, minus the
time limit:

```
browser (GitHub Pages client)
   │  wss://<host>/ws , https://<host>/healthz , https://<host>/api/*
   ▼
Caddy :443 (auto TLS via Let's Encrypt / ZeroSSL, CORS on /api/*)
   ▼
node server/server.js :8080  (HTTP + WS gateway, AUTO_START_GODOT=1)
   ▼
godot --headless ... -- --server --port=9080  (DEDICATED_SERVER=1)
```

| Item | Value |
|---|---|
| Droplet | `paintball-server`, Basic `s-2vcpu-2gb` (2 vCPU / 2 GB / 60 GB), `sfo2`, Ubuntu 24.04, ~$18/mo |
| Reserved IP | `134.199.181.82` (free while attached; survives rebuilds) |
| Hostname | `134-199-181-82.sslip.io` |
| Firewall | DO cloud firewall `paintball-fw`: inbound 22, 80, 443 only |
| Invite link | https://tylerdoubleu.github.io/game_dev_rev0/?map=woodsball_crash&server=wss://134-199-181-82.sslip.io/ws |

The web client is **not** exported on the server; players load it from GitHub Pages.

## Files

- `setup.sh`: idempotent provisioning for a fresh Ubuntu 24.04 droplet (2 GB swap,
  unattended-upgrades, Node 20, Caddy, Godot 4.7.2 headless, `paintball` user,
  clone of `main` at `/opt/paintball/app`, units below).
  `PAINTBALL_HOST=<ip-with-dashes>.sslip.io bash setup.sh`
- `paintball-server.service`: runs `node server/server.js` with `Restart=always`;
  enabled at boot.
- `paintball-update.timer` / `paintball-update.service` / `update.sh`: auto-deploy.
- `Caddyfile`: TLS + reverse proxy to `127.0.0.1:8080` + CORS for `/api/*`.

## Auto-update from main

Every 5 minutes `paintball-update.timer` runs `/opt/paintball/update.sh`, which does
`git fetch origin main`. If `origin/main` moved, it hard-resets the server clone,
pulls LFS files, re-installs the service unit/Caddyfile from this folder if they
changed, and restarts `paintball-server`. So a push to main goes live within about
5 minutes. A restart drops any match in progress, so avoid pushing mid-playtest.
No GitHub Actions are involved.

## Operating it

```bash
ssh root@134.199.181.82
journalctl -u paintball-server -f          # game server logs
journalctl -u paintball-update -n 50       # auto-update history
systemctl restart paintball-server         # manual restart
/opt/paintball/update.sh                   # force an update check now
curl -s https://134-199-181-82.sslip.io/healthz
```
