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
| Hostname | `play.jeetball.com` (also still answers on `134-199-181-82.sslip.io`) |
| Firewall | DO cloud firewall `paintball-fw`: inbound 22, 80, 443 only |
| Invite link | https://tylerdoubleu.github.io/game_dev_rev0/?map=woodsball_crash&server=wss://play.jeetball.com/ws |

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
curl -s https://play.jeetball.com/healthz
```

## Test environment (test.jeetball.com)

A second, independent server runs the `test` branch on the same droplet.
Push to `test` → only the test server restarts. Merge `test` into `main` → live restarts.

| | Live | Test |
|---|---|---|
| Branch | `main` | `test` |
| Checkout | `/opt/paintball/app` | `/opt/paintball-test/app` |
| Service | `paintball-server` | `paintball-test-server` |
| Ports (Node / Godot) | 8080 / 9080 | 8081 / 9081 |
| Auto-pull | `paintball-update.timer` → `/opt/paintball/update.sh` | `paintball-test-update.timer` → `/opt/paintball-test/update.sh` (`update-test.sh`) |
| Web client | GitHub Pages (`main`'s `docs/`) | Caddy serves the test checkout's committed `docs/` (same web root as Pages) at https://test.jeetball.com |
| WebSocket / API | `wss://play.jeetball.com/ws`, `/api/*` | `wss://test.jeetball.com/ws`, `/api/*` |

- DNS: `test.jeetball.com` is a DNS-only (grey cloud) Cloudflare A record → `134.199.181.82`.
- The test unit sets `PORT=8081`, `WS_PORT=9081`, `LOBBY_STATE_FILE=/opt/paintball-test/lobbies.json`,
  `GAME_CLIENT_URL=https://test.jeetball.com/`, `PUBLIC_WS_URL=wss://test.jeetball.com/ws`,
  `CORS_ORIGINS=https://test.jeetball.com`, `WEB_ROOT=/opt/paintball-test/app/docs`, and `LOBBY_COUNT=2`.
  It is capped at `MemoryMax=700M` with `CPUWeight=50` so a bad test build can't starve live.
- `update-test.sh` never touches the live clone, the live service, or Caddy. The Caddyfile (both
  sites) is owned by `main`: live `update.sh` installs it when `main` changes it.
- The test page is plain `no-cache`, so a hard refresh is not needed after a test push.
  Commit a fresh `tools/export_web.sh` build on `test` for client changes to show up there; on the
  `test` branch it bakes in `wss://test.jeetball.com/ws` automatically.

Install on the droplet (one time, as root):

```bash
mkdir -p /opt/paintball-test && cp -a /opt/paintball/app /opt/paintball-test/app
chown -R paintball:paintball /opt/paintball-test && chmod 0755 /opt/paintball-test
runuser -u paintball -- git -C /opt/paintball-test/app checkout -B test origin/test
D=/opt/paintball-test/app/deploy/digitalocean
install -m 0755 $D/update-test.sh /opt/paintball-test/update.sh
install -m 0644 $D/paintball-test-*.service $D/paintball-test-update.timer /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now paintball-test-server paintball-test-update.timer
journalctl -u paintball-test-server -f
```
