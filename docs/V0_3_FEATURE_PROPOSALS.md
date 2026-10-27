# First-Person Paintball (`game_dev_rev0`) — v0.3 Feature Proposals & Roadmap

**Milestone:** [`v0.3.0-proposals`](https://github.com/Tylerdoubleu/game_dev_rev0/milestone/1)  
**Target Base:** `v0.2.4` (`e1d54eb`) — Gritty 2000s Tournament Speedball Prototype  

This document compiles each studio discipline's **Top 3 Feature Proposals** for **v0.3**, paired with tracked GitHub Issues so we can review, prioritize, and kick off implementation tomorrow.

---

## 1. Grok Bot (Build, Netcode, Integration & Deployment)

1. **[#14 — Multi-Room Server Isolation & Lateral 5v5 Breakout Gate Slots](https://github.com/Tylerdoubleu/game_dev_rev0/issues/14)**
   - **What it solves:** Right now all connected peers on our Edgegap relay share a single physical broadcast domain regardless of `?room=`, and teammates on the same side spawn at `x = 0.0`.
   - **v0.3 Upgrade:** Scope `rpc_sync_player_state`, `rpc_fire_paintball`, `rpc_notify_player_hit`, and `sync_lobby_state` strictly to peers in the same `room`, add a live **Active Room Browser** in the `[TAB]` staging menu, and assign each teammate a dedicated lateral breakout slot (`x = -3.6m, -1.8m, 0.0m, +1.8m, +3.6m`) along the starting gate.

2. **[#17 — Server-Authoritative Hit Validation & Lag-Compensated Rewind](https://github.com/Tylerdoubleu/game_dev_rev0/issues/17)**
   - **What it solves:** Client-side hit detection can allow mutual post-death "trade kills" or missed breaks when ping fluctuates between 30–110ms.
   - **v0.3 Upgrade:** Maintain a 500ms (10-frame) 20Hz snapshot ring buffer on the dedicated server for lag-compensated hit verification and single-source-of-truth elimination state (blocking post-elimination shots and respecting the 2.8s spawn-protection window).

3. **[#18 — Automated Multi-Platform Release Pipeline (Windows, macOS, Linux, WebGL2 & Edgegap Watchdog)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/18)**
   - **What it solves:** Browser playtests are super convenient for instant links, while native desktop builds deliver zero browser-shortcut friction and locked 144Hz+ frame pacing.
   - **v0.3 Upgrade:** Add a one-command release packager (`deploy/build_all_releases.py`) that publishes downloadable Windows `.exe`, macOS `.zip`, and Linux `.x86_64` bundles to GitHub Releases alongside the GitHub Pages WebGL2 client, plus an in-HUD RTT ping (`ms`) readout and Edgegap health watchdog.

---

## 2. Ren (Art Direction, Shaders, Silhouettes & 2000s Stadium Atmosphere)

1. **[#13 — Visor Paint Obstruction, Squeegee Wipe Mechanic & Thermal Lens Fogging](https://github.com/Tylerdoubleu/game_dev_rev0/issues/13)**
   - Persistent oily neon goggle-splat shader from near-misses/rubs, active `[G]` squeegee/microfiber wipe animation (risk vs. reward with one hand off the marker), and dynamic thermal lens breath fogging when sprinting hard.

2. **[#15 — Soft-Body Inflatable Bunker Deformation, Turf Slide Trenches & 2004 Broadcast Sideline Props](https://github.com/Tylerdoubleu/game_dev_rev0/issues/15)**
   - Vertex-shader vinyl bunker dents on knee-slides/paintball impacts, persistent muddy turf slide trenches behind Snake & Dorito lanes, and 2004 NPPL/PSP pit tents, HPA fill stations, and sideline refs.

3. **[#16 — Articulated 2000s Pro Player Silhouettes, Exposed Hopper/Pack Hitboxes & Period-Authentic Marker Models](https://github.com/Tylerdoubleu/game_dev_rev0/issues/16)**
   - Baggy 2000s pro jerseys, thermal masks, 4+3 horizontal pod packs, distinct sub-hitboxes for the exposed hopper/marker/pack (extending PB-01), and distinct 3D silhouettes for Speedball, Woodsball, and Stock-Class Pump markers.

---

## 3. Core Gameplay & Tactical Systems Backlog (PB-01 – PB-06)

- **[#5 — PB-05 [v0.3]: Center Flag / Buzzer Objective, Breakout Countdown & Tactical Bot AI](https://github.com/Tylerdoubleu/game_dev_rev0/issues/5)**
- **[#4 — PB-04 [v0.3]: Bunker Callout Tape Zones ("Snake 1", "Dorito 2", "50 Aztec") & Pinned Suppression HUD](https://github.com/Tylerdoubleu/game_dev_rev0/issues/4)**
- **[#1 — PB-01: Analog Edge-Peeking & Exposed Hopper/Elbow Sub-Hitboxes](https://github.com/Tylerdoubleu/game_dev_rev0/issues/1)**
- **[#3 — PB-03: Staged Manual Pod Pour & Spatial 3D Pneumatic Audio Cues](https://github.com/Tylerdoubleu/game_dev_rev0/issues/3)**
