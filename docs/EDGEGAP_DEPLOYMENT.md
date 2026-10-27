# Edgegap Arbitrium Deployment Guide (`v0.2.2-multiplayer`)

## Architecture Overview
- **Single-Port Unified HTTP + WebSocket Gateway (`server/server.js`)**:
  - Listens on `ARBITRIUM_PORT_HTTP_INTERNAL` / `ARBITRIUM_PORT_GAMEPORT_INTERNAL` / `PORT` (default `8080`).
  - Serves the HTML5 WebGL2 client (`build/web/`) with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`.
  - Exposes `/healthz` for Edgegap readiness checks.
  - Upgrades WebSocket connections (`ws://` or `wss://` on `/ws` or `/`) and proxies raw TCP frames to the authoritative headless Godot 4.7.2 server on `127.0.0.1:9080` (`WS_PORT`).
- **Headless Godot 4.7.2 Dedicated Server (`scripts/autoload/network_lobby.gd`)**:
  - Automatically starts when launched with `--server` or `DEDICATED_SERVER=1`.
  - Synchronizes room rosters, team selection (`TEAM ALPHA` South Gate vs. `TEAM BRAVO` North Gate), gear bracket selection (`Speedball`, `Woodsball`, `Stock Pump`), OpFor bot fill toggle, 20Hz player 3D avatars, and networked paintball trajectories/eliminations.

## Edgegap Arbitrium Port Configuration
When creating your Application Version in the Edgegap Dashboard:
1. **Docker Image**: Build and push from the root `Dockerfile`:
   ```bash
   docker build -t registry.edgegap.com/<your-namespace>/paintball-rev0:v0.2.2 .
   docker push registry.edgegap.com/<your-namespace>/paintball-rev0:v0.2.2
   ```
2. **Ports**:
   - **Port**: `8080`
   - **Protocol**: `WS` (or `HTTP` / `TCP` with TLS Upgrade enabled)
   - **Port Name**: `gameport` (maps to `ARBITRIUM_PORT_GAMEPORT_INTERNAL`)
3. **Connecting from Desktop or Browser**:
   - **Desktop Client (`MSI` PC)**: In the **Tournament Staging Pits — Click-to-Lobby** overlay (`[TAB]` / `[ESC]`), paste your Edgegap deployment's public `host:port` or `wss://...` URL into **SERVER WS**, choose **TEAM ALPHA** or **TEAM BRAVO**, and click **CONNECT / SYNC WS**, then **>> DROP IN TO ARENA (PLAY NOW) <<**.
   - **Browser Client**: Open the Edgegap HTTP/HTTPS URL directly, or pass `?room=alpha&team=ALPHA&bracket=speedball&server=wss://<edgegap-host>:<port>/ws`.
