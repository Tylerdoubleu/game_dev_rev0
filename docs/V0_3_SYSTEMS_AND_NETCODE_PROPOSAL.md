# v0.3 Systems, Netcode & Field Intelligence Proposal — Tim (Thinker / Researcher)

**Author:** Tim (Thinker / Researcher)  
**Repository:** [`Tylerdoubleu/game_dev_rev0`](https://github.com/Tylerdoubleu/game_dev_rev0)  
**Milestone:** [`v0.3.0-proposals`](https://github.com/Tylerdoubleu/game_dev_rev0/milestone/1)  
**Baseline:** `v0.2.4` (`e1d54eb`) — Gritty 2000s Tournament Speedball  

---

## Executive Summary

With **Grok Bot** covering server-side room isolation & lateral 5v5 breakout gate slots ([#14](https://github.com/Tylerdoubleu/game_dev_rev0/issues/14)), 500 ms server-side rewind validation ([#17](https://github.com/Tylerdoubleu/game_dev_rev0/issues/17)), and automated desktop/web release packaging ([#18](https://github.com/Tylerdoubleu/game_dev_rev0/issues/18)), **Bluey** covering the Center-50 Flag objective ([#19](https://github.com/Tylerdoubleu/game_dev_rev0/issues/19)), variable analog snap-peeking ([#20](https://github.com/Tylerdoubleu/game_dev_rev0/issues/20)), and named bunker callouts ([#21](https://github.com/Tylerdoubleu/game_dev_rev0/issues/21)), and **Ren** covering thermal visor squeegee mechanics ([#13](https://github.com/Tylerdoubleu/game_dev_rev0/issues/13)), soft-body vinyl bunker deformation ([#15](https://github.com/Tylerdoubleu/game_dev_rev0/issues/15)), and articulated 2000s pro silhouettes ([#16](https://github.com/Tylerdoubleu/game_dev_rev0/issues/16)), my **Top 3 Systems & Netcode Architecture Proposals for `v0.3.0`** focus on:

1. **[Issue #22 (`PB-18`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/22): Binary Snapshot Compression (`24-Byte PackedByteArray`) & WebRTC Unreliable UDP DataChannel Transport**
2. **[Issue #23 (`PB-19`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/23): Post-Match & Respawn Tactical Telemetry Analytics (Lane Control Heatmap, Accuracy %, Breakout Survival & Ping/Jitter Graph)**
3. **[Issue #24 (`PB-20`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/24): Acoustic & Visual Field Intelligence, Goggle-Splat Directional Vector & 3-Second Killcam / Tactical AI Bridge**

---

## Feature 1: Binary Snapshot Compression (24-Byte `PackedByteArray`) & WebRTC Unreliable UDP DataChannel Transport
- **GitHub Ticket:** [Issue #22 (`PB-18`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/22)
- **Problem:** `rpc_sync_player_state` in `scripts/autoload/network_lobby.gd` currently sends 8 separate Variant arguments (including repeated `team` and `callsign` strings, ~96–120 bytes/tick) over a single WebSocket (`TCP`) stream. On Wi-Fi or cellular links with 1–2% packet loss, TCP head-of-line blocking holds back newer movement frames for 120–250 ms until the dropped TCP segment is retransmitted, and unbuffered linear `lerp(pos, 0.45)` causes visible micro-stutters.
- **v0.3 Architecture & Implementation:**
  1. **24-Byte Binary Frame (`scripts/autoload/network_lobby.gd`):** Pack `uint16 seq`, `uint16 server_tick_ms`, quantized arena coordinates `int16 pos_x, pos_y, pos_z` (`2mm` precision across `±65m`), `int16 vel_x, vel_z`, `int16 body_yaw, head_pitch`, `int8 lean_q`, `uint8 flags` (`stance_idx`, `is_left_handed`, `eliminated`, `is_firing`, `sprinting`), and `uint32 peer_id` into a compact `PackedByteArray` (~75% bandwidth reduction).
  2. **60 ms Hermite Interpolation & Extrapolation Buffer (`scripts/player/remote_player_avatar.gd`):** Add a 4-slot timestamped ring buffer per remote avatar rendering at `render_time = now - 60ms` with velocity-based dead-reckoning up to `120ms`.
  3. **WebRTC Unreliable UDP DataChannel (`WebRTCMultiplayerPeer`) + `/lobbies` Endpoint (`deploy/edgegap_bootstrap.js`):** Use the existing WebSocket strictly for SDP/ICE signaling to negotiate an unreliable, unordered (`maxPacketLifeTime = 0, ordered = false`) SCTP-over-DTLS-over-UDP DataChannel in browser and native builds (with automatic fallback to WebSocket if UDP is blocked), and expose `GET /lobbies` on `edgegap_bootstrap.js` for live room directory inspection.

---

## Feature 2: Post-Match & Respawn Tactical Telemetry Analytics (Lane Control Heatmap, Accuracy %, Breakout Survival & Ping/Jitter Graph)
- **GitHub Ticket:** [Issue #23 (`PB-19`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/23)
- **Problem:** `GameManager` currently tracks only aggregate `Kills`, `Deaths`, and `Remaining OpFor`. Players have no visibility into their paint accuracy %, hit-zone breakdown (`Visor`, `Hopper`, `Torso`), spilled vs. poured pods, which lanes (`Snake`, `Center 50`, `Dorito`) are hot during respawn selection, or whether a missed snap-shot coincided with a network jitter spike.
- **v0.3 Architecture & Implementation:**
  1. **Per-Life & Per-Match Combat Telemetry (`scripts/autoload/game_manager.gd` & `scripts/autoload/paint_ballistics.gd`):** Record `balls_fired`, `balls_broken_on_target`, `balls_bounced_off_target`, hit-zone percentages, `rounds_spilled_on_turf`, and `breakout_survival_time_sec`.
  2. **2D Top-Down Lane Control & Elimination Heatmap (`scripts/systems/speedball_arena_builder.gd`):** Quantize the `108m × 132m` arena into a `27 × 33` grid (`4m × 4m` cells) and render a live **Lane Control & Threat Heatmap** onto both the **5-Zone Tactical Respawn Map** (`[1]–[5]`) and the **Post-Match Victory/Defeat Stat Card**.
  3. **Live RTT Ping, Jitter & Packet Delivery Sparkline (`scripts/autoload/network_lobby.gd`):** Add a 1 Hz ping/pong probe computing rolling RTT (`ms`), Jitter (`±ms`), and Packet Loss (`%`) with a color-coded HUD badge and a 30-second graph in `[TAB]` / `[M]`.

---

## Feature 3: Acoustic & Visual Field Intelligence, Goggle-Splat Directional Vector & 3-Second Killcam / Tactical AI Bridge
- **GitHub Ticket:** [Issue #24 (`PB-20`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/24)
- **Problem:** When eliminated (`"YOU'VE BEEN HIT!"`), players cannot immediately tell which bunker angle clipped them, and `SnapTargetBot` AI (`PB-05`) does not yet consume networked team callouts or acoustic reload cues to shift crossfire lanes.
- **v0.3 Architecture & Implementation:**
  1. **4-Way Radial Callout Wheel (`Hold [F]`) & Networked `IntelBus` (`scripts/autoload/intel_bus.gd`):** Tapping `[F]` pings the aimed bunker; holding `[F]` opens a 4-way tournament callout wheel (`Spot/Count`, `Lock Lane`, `Bump Up`, `Pinned/Help`) synced across same-room teammates via `rpc_broadcast_team_intel`.
  2. **Tactical Bot AI Integration (`scripts/systems/snap_target_bot.gd` — `PB-05` Bridge):** Connect `SnapTargetBot` to `IntelBus` and acoustic triggers (pod reload rattle `[R]` within `18m`) so bots dynamically suppress pinned bunkers or advance up the tape when a lane opens.
  3. **Directional Impact Vector & 3-Second Ring-Buffer Killcam (`scripts/player/player_controller_3d.gd`):** Display the exact shooter bunker callout, distance (`m`), hit zone (`Visor`, `Hopper`, `Torso`), and a glowing 3D neon trajectory ribbon on the `"YOU'VE BEEN HIT!"` / Respawn Map screen, backed by a 60-frame (`3.0s @ 20Hz`) local transform/projectile ring buffer for instant elimination replay.
