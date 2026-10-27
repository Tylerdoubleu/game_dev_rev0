# First-Person Paintball (`game_dev_rev0`) — v0.3 Feature Proposals & Roadmap

**Milestone:** [`v0.3.0-proposals`](https://github.com/Tylerdoubleu/game_dev_rev0/milestone/1)  
**Target Base:** `v0.2.4` (`e1d54eb`) — Gritty 2000s Tournament Speedball Prototype  

This document compiles each studio discipline's **Top 3 Feature Proposals** for **v0.3**, paired with tracked GitHub Issues so we can review, prioritize, and kick off implementation tomorrow.

---

## 1. Bluey (Gameplay Director — Core Loop, Gunplay, Movement & Field Tactics)

1. **[#19 (`PB-15`) — Center-50 Flag Pull & Hang Objective + Live Breakout Horn Countdown](https://github.com/Tylerdoubleu/game_dev_rev0/issues/19)**
   - **10-Second Start-Box Breakout Horn (`BARREL ON NET — 3... 2... 1... BUZZER!`):** Players hold their marker barrel on the starting gate net; timing the horn grants a `1.15x` initial 1.5s breakout sprint burst toward the Snake or Dorito corners, while jumping early triggers a false-start penalty.
   - **Physical Center-50 Flag Pull, Drop & Hang:** High-visibility neon tournament flag at `(0, 0, 0)` between the Center 50 bunkers. Snatching it (`[E]`/`[F]` or sprint-through) alerts both teams, shows the flag cloth in your off-hand, drops at your spot if you get hit, and hanging it on the opposing Breakout Gate scores an instant Round Win (or `-3` team deaths / `+2` bonus pods in Continuous Attrition mode).

2. **[#20 (`PB-16`) — Variable Analog Snap-Lean, Bunker-Rub Self-Check & Hopper/Marker Profile Hitboxes](https://github.com/Tylerdoubleu/game_dev_rev0/issues/20)**
   - **Two-Stage Tap-Snap vs. Analog Wheel Lean:** Quick-tapping `Q`/`E` executes a crisp `0.35s` snap-shot pop-out and auto-tuck; holding `Q`/`E` + `Mouse Wheel` (or `Alt + Mouse X`) adjusts exposure depth from a tight `35%` sliver angle to a `100%` bunker wrap.
   - **Exposed Hopper, Marker & Pack Sub-Hitboxes:** Separate collision zones for **Mask/Torso**, **Hopper/Loader**, and **Marker/Pack** that shift with `is_left_handed` (`X`)—peeking the wrong side without swapping hands exposes `2.4x` more loader profile before your barrel clears the bunker edge.
   - **Surface-Hardness Bounce Math:** Hard polycarbonate mask/hopper hits break far more reliably (`cos >= 0.28`) than glancing shots on padded jersey/slide pants (`cos >= 0.48`).

3. **[#21 (`PB-17`) — Named Bunker Callout System ('Dorito 2', 'Snake 50'), Lane Suppression HUD & Staged Pod Top-Off](https://github.com/Tylerdoubleu/game_dev_rev0/issues/21)**
   - **Automatic Named Bunker Callouts (`[F]`):** Tag all 36 arena bunkers with authentic 2000s tournament callouts (`Home`, `Back Center`, `Snake 1`, `Snake 50`, `Dorito 2`, `50 Aztec`, `Can L/R`). Pinging a bunker broadcasts the exact callout (`"OPFOR @ DORITO 2 (LOOKING INSIDE)"`) and marks a 4.0s live threat icon on the **Tactical Respawn Map** so respawning teammates know which of the 5 re-entry zones are hot.
   - **Paint-Lane Suppression ("Pinned" Feedback) & Staged Pod Pour (`[R]`):** 3+ enemy paintballs whizzing within `1.8m` or hammering your bunker trigger high-velocity paintball snap/whiz audio and a directional lane indicator; holding `[R]` pours rounds continuously (`12 rounds/sec`) so you can release early to snap-shoot mid-reload without losing the rest of the pod.

---

## 2. Ren (Artist — 2000s Tournament Art Direction, Visor Shaders & Silhouettes)

1. **[#13 (`PB-12`) — Visor Paint Obstruction, Squeegee Wipe Mechanic (`[G]`) & Thermal Lens Fogging](https://github.com/Tylerdoubleu/game_dev_rev0/issues/13)**
   - Near-miss (`<1.2m`) and wet-bunker rub splatter droplets on the outer edges of the first-person thermal visor, an interactive `[G]` microfiber glove/squeegee wipe animation (`0.6s`), a multi-layered gelatin shell crack shader on `"YOU'VE BEEN HIT!"`, and heavy-breathing thermal lens condensation after hard sprints and dives.

2. **[#15 (`PB-13`) — Soft-Body Inflatable Bunker Deformation, Turf Slide Trenches & 2004 Broadcast Sideline Props](https://github.com/Tylerdoubleu/game_dev_rev0/issues/15)**
   - Reactive vertex-displacement vinyl bunker flex & pop when knee-sliding into cover or hammering a bunker with a 10.5 BPS string, persistent muddy turf slide trenches behind Snake & Dorito highways, and authentic 2004 NPPL/X-Games sideline props (Chronograph & HPA fill station, Center-50 camera crane, sponsor scrims, and live 3D LED scoreboard digits).

3. **[#16 (`PB-14`) — Articulated 2000s Pro Player Silhouettes, Exposed Hopper/Pack Hitboxes & Period-Authentic Marker Models](https://github.com/Tylerdoubleu/game_dev_rev0/issues/16)**
   - Articulated 2000s tournament player rigs (baggy jerseys, padded slide pants, 4+3 vertical pod pack, JT Proflex mask, tilting Halo loader + HPA tank) and 3 distinct first-person marker viewmodels: **Speedball** (`2004 Intimidator/Shocker/Autococker` dual-tube electro), **Woodsball** (`Tippmann A-5` mechanical carbine), and **Stock Pump** (animated under-barrel `RMB` pump handle + 10-round feed tube).

---

## 3. Grok Bot (Build, Netcode, Server Isolation & Release Engineering)

1. **[#14 (`PB-12`) — Multi-Room Server Isolation & Lateral 5v5 Breakout Gate Slots](https://github.com/Tylerdoubleu/game_dev_rev0/issues/14)**
   - Scope `rpc_sync_player_state`, `rpc_fire_paintball`, `rpc_notify_player_hit`, and `sync_lobby_state` strictly to peers in the same `room`, add a live **Active Room Browser** in the `[TAB]` staging menu, and assign each teammate a dedicated lateral breakout slot (`x = -3.6m, -1.8m, 0.0m, +1.8m, +3.6m`) along the starting gate.

2. **[#17 (`PB-13`) — Server-Authoritative Hit Validation & Lag-Compensated Rewind](https://github.com/Tylerdoubleu/game_dev_rev0/issues/17)**
   - Maintain a 500ms (10-frame) 20Hz snapshot ring buffer on the dedicated server for lag-compensated hit verification and single-source-of-truth elimination state (blocking post-elimination trade kills and enforcing the 2.8s spawn-protection window).

3. **[#18 (`PB-14`) — Automated Multi-Platform Release Pipeline (Windows, macOS, Linux, WebGL2 & Edgegap Watchdog)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/18)**
   - One-command release packager (`deploy/build_all_releases.py`) publishing downloadable Windows `.exe`, macOS `.zip`, and Linux `.x86_64` bundles to GitHub Releases alongside the GitHub Pages WebGL2 client, plus an in-HUD RTT ping (`ms`) readout and Edgegap health watchdog.

---

## 4. Earlier Tracked Core Backlog (`PB-01` – `PB-06`)

- **[#5 (`PB-05`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/5):** Center Flag / CTF Objectives, `NavigationAgent3D` Tactical Bot AI & Multiplayer Lobbies
- **[#4 (`PB-04`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/4):** Bunker Callout Zones, LOS Silhouettes & Pinned Suppression HUD
- **[#1 (`PB-01`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/1):** Analog Peeking & Hopper/Elbow Hitboxes
- **[#3 (`PB-03`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/3):** Staged Manual Pod Pour, Physical Spills & Spatial Audio Cues
- **[#2 (`PB-02`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/2):** Bounce-vs-Break Physics, Wind Drift & Splat Decals
- **[#6 (`PB-06`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/6):** Map-Enforced `GearRuleEnforcer`, Woodsball/Pump Maps & Horizontal Loadouts
