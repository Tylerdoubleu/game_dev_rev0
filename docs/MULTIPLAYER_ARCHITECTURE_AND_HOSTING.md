# First-Person Paintball — Multiplayer Networking, Steamworks & Dedicated Server Hosting Guide

**Prepared for:** Tyler White | **Project:** First-Person Paintball · repo game_dev_rev0 | **Engine:** Godot 4.7.2 (gl_compatibility / WebGL2 + native desktop) | **Current build:** v0.2.4 (commit e1d54eb) | **Date:** October 26, 2026

---

## Contents

- [Executive Summary](#executive-summary)
- [1. Current Live Architecture — Where the Game Runs Today](#1-current-live-architecture--where-the-game-runs-today)
- [2. Networking Protocols — WebSockets (TCP) vs. UDP & AAA Netcode](#2-networking-protocols--websockets-tcp-vs-udp--aaa-netcode)
- [3. Steamworks Developer Services Summary](#3-steamworks-developer-services-summary)
- [4. Dedicated Server Hosting Options & Scaling Roadmap](#4-dedicated-server-hosting-options--scaling-roadmap)
- [5. Recommendations & Next Steps](#5-recommendations--next-steps)

## Executive Summary

This guide consolidates the full architectural discussion for **First-Person Paintball** — where the game runs today, why the current WebSocket-over-TCP transport behaves the way it does, how AAA shooters solve the same problem with UDP, what Steamworks provides for a $100 Steam Direct fee, and which dedicated-server hosts and architectures fit each growth stage from a handful of playtest lobbies to 10,000 concurrent matches.

| Topic | Bottom line |
|---|---|
| Where it runs today | Static WebGL2 client on GitHub Pages CDN + one Edgegap Arbitrium container in Chicago (Node.js WSS gateway → headless Godot 4.7.2, Peer #1). |
| What limits the current netcode | Not graphics. Per-lobby player count (N × (N−1) × tick rate) and, above all, TCP head-of-line blocking on lossy Wi-Fi. |
| How AAA shooters do it | 100% UDP in-match with a dual-lane “reliable UDP” layer (unreliable transforms + reliable events) and input redundancy. |
| Getting UDP in the browser | WebRTC unreliable DataChannels (WebRTCMultiplayerPeer) today; WebTransport (HTTP/3 datagrams) as the emerging option. |
| Steam | $100 one-time, 30% revenue share. Free SDR relay/DDoS/NAT traversal, lobbies, voice, SteamPipe CDN, playtests, auth. Dedicated server compute is still yours to rent. |
| Hosting recommendation | Stay on Edgegap/one VPS now → multi-room Godot on Hetzner/OVH (or Edgegap/Hathora per-match) at Early Access → Hybrid at scale: Steam P2P / lightweight relay for casual, bare metal + Edgegap burst for Ranked. |

> [!TIP]
> **Key takeaway** — Graphics fidelity and network cost are decoupled: shaders, textures and meshes never cross the wire. The architecture decisions that matter are **transport (TCP vs. UDP)**, **players per lobby**, and **how many lobbies share one server process**.

## 1. Current Live Architecture — Where the Game Runs Today

![Figure 1 — Live deployment: static client on GitHub Pages, authoritative relay on Edgegap Arbitrium.](architecture_diagrams/architecture.png)
*Figure 1 — Live deployment: static client on GitHub Pages, authoritative relay on Edgegap Arbitrium.*

### 1.1 Client Layer — Static WebGL2 + Native Desktop

- **Browser build** exported from Godot 4.7.2 with the `gl_compatibility` renderer (WebGL2) and hosted on the **GitHub Pages CDN** at `https://tylerdoubleu.github.io/game_dev_rev0/` (served from the repo’s `docs/` folder).
- On load the page downloads the `.wasm` engine and the `.pck` game asset pack into browser memory. The `.pck` request uses cache-busting (`index.pck?v=024_altw_guard`) and `fetch(..., { cache: 'no-store' })` so every playtester always gets the latest build.
- **All 3D rendering, the procedural Gritty 2000s Tournament textures, bunker collisions, and local player physics run 100% on the player’s own CPU/GPU.** Nothing visual is streamed from a server.
- A **native desktop export** of the same project uses identical scenes and RPCs and connects to the same server URL.

### 1.2 Dedicated Server Layer — Edgegap Arbitrium Container

| Property | Value |
|---|---|
| Provider / region | Edgegap Arbitrium — Chicago |
| Public FQDN | `36e244223bd4.pr.edgegap.net` |
| Public IP / external port | `172.237.138.250` : `32553` |
| Container size | 0.125 vCPU / 256 MB RAM |
| Gateway process | `deploy/edgegap_bootstrap.js` — Node.js TLS/WebSocket gateway on `:8080` |
| Gateway endpoints | `/healthz` (health probe) · `/reload` (hot update: pull & restart without redeploy) |
| Game process | Headless Godot 4.7.2: `--headless --server-port=9080`, acting as authority **Peer #1** |
| Proxying | Binary WebSocket frames piped :8080 ⇄ :9080 with `setNoDelay(true)` on both sockets |

### 1.3 How Players Interact — Star Topology Relay via Peer #1

Clients never talk to each other directly. Every client connects to Peer #1, which validates and relays traffic to the other peers in the same `room_id`.

- **Auto-join from the URL.** `scripts/autoload/network_lobby.gd` parses query parameters such as `?server=wss://...&room=1v1&team=auto&bracket=speedball&bots=off` (`server`, `room`, `team`, `bracket`, `bots`, `name`).
- **Team auto-balance.** On `register_player_info`, Peer #1 places a new human in a room onto the opposite side of any human already there — **Team ALPHA vs. Team BRAVO**.
- **20 Hz state relay.** `rpc_sync_player_state` carries position, body yaw, head pitch, lean, stance, team, callsign and eliminated flag (`unreliable_ordered`).
- **Paintball shots.** Shots are relayed reliably; each receiving client spawns the paintball locally with its own ballistics (spin, wobble, stadium wind).
- **Hit adjudication & match end.** Hit reports go to Peer #1, which updates kills/deaths, rebroadcasts lobby state, and when a player reaches **10 eliminations** announces the winner to the room.

![Figure 2 — In-match RPC flow through Peer #1 (names as implemented in network_lobby.gd).](architecture_diagrams/rpc.png)
*Figure 2 — In-match RPC flow through Peer #1 (names as implemented in network_lobby.gd).*

> [!NOTE]
> **RPC naming: discussion vs. code** — During the discussion the flow was described as `rpc_spawn_paintball`, `rpc_report_player_hit` → `rpc_confirm_player_hit`, and `rpc_declare_match_winner`. In the current v0.2.4 code the equivalent functions are `rpc_fire_paintball`, `rpc_notify_player_hit` (server then rebroadcasts lobby state as the confirmation), and `rpc_announce_match_over` (triggered when the victim reaches 10 deaths). Behavior is identical; use the code names when searching the repo.

| Concern | Function (v0.2.4) | Mode | Sent by → to |
|---|---|---|---|
| Movement / stance / lean | `rpc_sync_player_state` | `any_peer`, `unreliable_ordered`, 20 Hz | Client → Peer #1 → room |
| Paintball shot | `rpc_fire_paintball` | `any_peer`, `reliable` | Shooter → Peer #1 → room |
| Hit / elimination | `rpc_notify_player_hit` | `any_peer`, `reliable` | Client → Peer #1 (score update) |
| Lobby state / scores | `_broadcast_lobby_state_from_server` | `authority`, `reliable` | Peer #1 → room |
| Match winner (10 elims) | `rpc_announce_match_over` | `authority`, `reliable` | Peer #1 → room |

## 2. Networking Protocols — WebSockets (TCP) vs. UDP & AAA Netcode

### 2.1 What Edgegap Uses Today

The live build uses **WebSockets over TCP with TLS (WSS)**. Nagle’s algorithm is disabled (`tcp_no_delay = true`, implemented as `setNoDelay(true)` in the Node gateway) so small state packets are flushed immediately instead of being batched. WebSockets are used because **web browsers prohibit raw UDP sockets** — WSS is the one bidirectional transport every browser supports with zero setup.

> [!NOTE]
> **Why “unreliable_ordered” still behaves reliably today** — `rpc_sync_player_state` is declared `unreliable_ordered`, but on `WebSocketMultiplayerPeer` every byte still rides a single TCP stream, so it is delivered reliably and in order. The RPC mode only becomes meaningful once the transport is swapped to ENet, WebRTC, or Steam (see §2.5 and §3.1).

### 2.2 What Limits WebSockets over TCP

#### ① Graphics complexity — zero impact

Rendering, shaders, lighting and meshes stay entirely on the client GPU. Network packets only carry compact state numbers — roughly **80–120 bytes per update** (position, angles, stance, flags). A 4K texture pack and a flat-shaded prototype cost exactly the same bandwidth.

#### ② Concurrent users per lobby — quadratic broadcast scaling

With a relay server, every player’s update must be forwarded to every other player: **packets/sec = N × (N − 1) × tick_rate**. At 20 Hz and ~100 bytes per update:

| Lobby size | Players (N) | Formula | Packets / sec | Bandwidth (~100 B) | Verdict |
|---|---|---|---|---|---|
| 1v1 | 2 | 2 × 1 × 20 | 40 | ~4 KB/s | Trivial |
| 5v5 | 10 | 10 × 9 × 20 | 1,800 | ~180 KB/s | Effortless |
| 16v16 | 32 | 32 × 31 × 20 | 19,840 | ~2 MB/s | Fine on 1 vCPU |
| 50v50 | 100 | 100 × 99 × 20 | 198,000 | ~20 MB/s | Saturates framing & TCP send buffers |

> [!WARNING]
> **Large-lobby threshold** — At 50v50 a single-threaded WebSocket relay spends most of its time framing tiny messages. The fix is to stop sending one RPC per player per tick and instead pack **all** players into one binary snapshot per recipient per tick (`PackedByteArray`, quantized floats, delta compression) — turning N×(N−1) messages into N messages.

#### ③ The real TCP bottleneck in fast shooters — Head-of-Line (HoL) blocking

TCP guarantees strict in-order delivery. If packet `#101` drops on Wi-Fi while `#102` and `#103` arrive on time, the OS kernel **holds `#102` and `#103` back from Godot** until `#101` is retransmitted — typically a **100–250 ms stall**. Remote players freeze and then fast-forward (“rubberband”), even though fresher data was already sitting in the receive buffer.

![Figure 3 — Head-of-line blocking on TCP vs. loss-tolerant delivery on UDP.](architecture_diagrams/hol.png)
*Figure 3 — Head-of-line blocking on TCP vs. loss-tolerant delivery on UDP.*

### 2.3 How AAA Multiplayer Shooters Work

*Counter-Strike 2*, *Valorant*, *Call of Duty*, *Apex Legends* and *Overwatch* all follow the same pattern:

- **100% UDP for in-match gameplay.** TCP / HTTPS / WSS are used only on the side for matchmaking, chat, inventory, store and login.
- **“Reliable UDP” dual-lane architecture** (Valve `GameNetworkingSockets`, Unreal `NetDriver`, Godot `ENetMultiplayerPeer` channels) multiplexes two kinds of traffic over one UDP socket.
- **Input redundancy instead of retransmission.** Every outgoing packet piggybacks the last 2–3 frames of player input, so a single lost packet is reconstructed from the next one immediately — with zero round-trip wait.

![Figure 4 — Dual-lane “reliable UDP” used by AAA shooters.](architecture_diagrams/dual.png)
*Figure 4 — Dual-lane “reliable UDP” used by AAA shooters.*

| Lane | Delivery | Typical rate | Carries | On loss |
|---|---|---|---|---|
| Unreliable + Unordered (fire-and-forget) | No ack, no resend, sequence-numbered | 60–128 Hz | Player transforms, velocity, aim angles, inputs | Ignored as soon as a newer packet arrives |
| Reliable + Ordered (guaranteed) | Acked & resent by the protocol layer | Event-driven | Hit confirmations, eliminations, respawn-zone selection, match state | Resent — but only this lane waits, never the movement lane |

### 2.4 How to Get UDP Behavior in Web Browsers

| Option | How it works | Godot 4 support | Notes |
|---|---|---|---|
| WebRTC unreliable DataChannels | SCTP over DTLS over UDP; channel created with `ordered = false` and `maxPacketLifeTime = 0` (or `maxRetransmits = 0`) for true fire-and-forget | Built in: `WebRTCMultiplayerPeer` (native via webrtc-native GDExtension) | Keep the existing WSS connection for the ~1-second signaling handshake (SDP/ICE), then move gameplay to the DataChannel. Works in Chrome, Firefox and Safari; needs STUN/TURN for strict NATs. |
| WebTransport (HTTP/3 over QUIC/UDP) | Modern browser API with unreliable datagrams plus reliable streams on one QUIC connection | No built-in peer — requires a JavaScriptBridge shim or custom MultiplayerPeerExtension | Simpler client-server model than WebRTC (no ICE). Server needs an HTTP/3 stack (e.g. Go/Rust). Verify current Safari support before committing. |

### 2.5 Recommended Transport Evolution

![Figure 5 — Godot’s MultiplayerPeer abstraction lets the transport change without rewriting game RPCs.](architecture_diagrams/peers.png)
*Figure 5 — Godot’s MultiplayerPeer abstraction lets the transport change without rewriting game RPCs.*

1. **Now:** keep WSS for reach and simplicity; pack state into binary snapshots; add client-side interpolation (~100 ms buffer) to mask HoL stalls.
2. **Web upgrade:** add `WebRTCMultiplayerPeer` with an unreliable channel for `rpc_sync_player_state`, using the existing WSS gateway for signaling.
3. **Desktop / Steam:** use `ENetMultiplayerPeer` for self-hosted UDP servers and `SteamMultiplayerPeer` (GodotSteam) for SDR-relayed sessions.

## 3. Steamworks Developer Services Summary

> [!TIP]
> **Cost of entry** — **$100 one-time Steam Direct fee per app** (recoupable once the game earns $1,000 in adjusted gross revenue) and a **30% store revenue share** (Valve’s tiers drop to 25% above $10M and 20% above $50M lifetime revenue). Almost every service below is included at no extra charge.

### 3.1 Multiplayer & Networking Infrastructure

| Service | What it gives First-Person Paintball |
|---|---|
| Steam Networking Sockets + Steam Datagram Relay (SDR) | Routes UDP traffic over Valve’s global private backbone. Free NAT traversal and relay, DDoS protection, IP masking for both players and dedicated servers, and lower-latency routing than the public internet. |
| Steam Lobbies, Matchmaking & Rich Presence | Lobby creation, metadata filters (`bracket`, `room`), skill matching, server-browser lists, and one-click “Join Game” invites through Steam Friends and Discord. |
| Steam Voice API | Low-latency team and proximity voice chat. |
| GodotSteam GDExtension | Exposes `SteamMultiplayerPeer`, so Godot 4.7 can swap between `WebSocketMultiplayerPeer`, `ENetMultiplayerPeer` and Steam UDP relays **without rewriting game RPCs**. |

### 3.2 Build Distribution, Patching & Playtesting

| Service | Details |
|---|---|
| SteamPipe CDN | Binary delta patching — a code-only change is typically a ~4 MB download. Unlimited bandwidth at no cost. |
| Beta branches | Password-protected branches such as `default`, `staging`, `tournament-test`. |
| Steam Playtest | Separate storefront “Request Access” queue; Valve manages invites and waves — no key-distribution headaches. |
| SteamCMD dedicated-server redistribution | Ship headless Linux/Windows server binaries as a separate depot so community hosts or cloud VMs can install and update them. |

### 3.3 Player Identity, Social, Community & Monetization

- **Verified identity:** `AuthSessionTickets` let your server confirm each player’s SteamID.
- **Anti-cheat:** VAC plus Easy Anti-Cheat or BattlEye integration.
- **Steam Input:** controllers, Steam Deck and gyro aiming with user-remappable bindings.
- **Steam Cloud** saves, **Leaderboards, Stats & Achievements**.
- **Steam Workshop:** player-made bunker layouts and maps.
- **Steam Inventory Service:** cosmetic marker skins and jerseys, tradable on the Community Market.

### 3.4 What Steam Covers for Free vs. What Still Costs Money

| Model | What Valve provides | What you pay | Best for |
|---|---|---|---|
| Listen servers (player-hosted P2P via SDR) | Relay, NAT punch-through, DDoS shielding, IP masking, lobbies | **$0 / month server bill — forever** | Casual, custom and private matches on PC |
| Dedicated servers | Server browser, auth, SDR DDoS/routing layer | You still rent the CPU/RAM instances (Edgegap, Hetzner, OVH…) | Ranked, tournaments, anti-cheat-sensitive play |

> [!WARNING]
> **Steam does not reach the browser** — Steam networking only works in the native Steam client. The GitHub Pages WebGL build will keep needing its own server path (WSS today, WebRTC/WebTransport later) — which is why the recommended architecture in §4.3 is a hybrid.

## 4. Dedicated Server Hosting Options & Scaling Roadmap

### 4.1 Most Common Dedicated Server Hosts for Godot Games on Steam

#### Category 1 — Managed session / container orchestrators

Pay-per-minute, auto-scaling across global regions; best when demand is spiky or matches are short-lived.

| Host | Highlights | Best fit |
|---|---|---|
| Edgegap (Arbitrium) | **Current host.** Native Docker/Godot support, 615+ edge locations, deploys per-match containers close to players | On-demand matches, regional playtests, burst capacity |
| Hathora | Top Edgegap competitor for indie session-based Godot games; simple `createRoom` API; predictable compute pricing | Session-based matches with a small team |
| Rivet | Open-source orchestrator with a Godot 4 plugin, matchmaking and DDoS protection | Teams that want self-hostable orchestration |
| PlayFab Multiplayer Servers (Azure) / AWS GameLift | Enterprise tier with fleet management and global regions | Studios holding cloud credits |

#### Category 2 — Raw bare-metal & VPS providers

Lowest cost per lobby for steady 24/7 traffic; you run the processes yourself.

| Host | Highlights | Indicative cost |
|---|---|---|
| Hetzner Cloud & Dedicated (#1 indie favorite) | Locations in Ashburn, Hillsboro, Falkenstein; 20 TB bandwidth included; roughly 1/10th the cost of managed game clouds | ~$5–$15/mo VPS · ~$60–$110/mo bare metal |
| OVHcloud Game Dedicated Servers | Hardware L4 UDP DDoS mitigation tuned for FPS / ENet / Source-style game ports | Bare metal, mid-range |
| Fly.io / DigitalOcean | Fast multi-region container deployment (repo already has `fly.toml`) | ~$5–$7/mo per small instance |

> [!NOTE]
> **Pricing caveat** — Prices are indicative figures from the discussion and change frequently; confirm current rates on each provider’s pricing page before committing.

### 4.2 Scaling Tiers (1 → 100 → 10,000 Concurrent Lobbies)

![Figure 6 — Hosting roadmap by growth stage.](architecture_diagrams/roadmap.png)
*Figure 6 — Hosting roadmap by growth stage.*

| Stage | Concurrency | Architecture | Monthly cost | Pros | Cons |
|---|---|---|---|---|---|
| 1 · Prototype & early playtests | 1–5 lobbies / 10–50 players | Current Edgegap container, or one $5–$7 Fly.io/Hetzner VPS with `room_id` isolation in `network_lobby.gd` | ~$0–$10 | Already live; zero ops; same code | Single region; no redundancy |
| 2A · Early Access (self-hosted) | 50–100 lobbies / 500–1,000 players | Multi-room headless Godot on 1–2 Hetzner/OVH VPS nodes, ~50 isolated `room_id` state tables per process | $15–$40 | Cheapest; full control; GDScript server | You own uptime, deploys, regions |
| 2B · Early Access (managed) | 50–100 lobbies / 500–1,000 players | Edgegap / Hathora per-match containers + lightweight Cloudflare Worker matchmaker | ~$100–$300 (utilization-dependent) | Auto-scale; global regions; isolation per match | Higher per-match cost; vendor lock-in |
| 3 · Breakout hit | 10,000 5v5 lobbies / 100,000 players | Path A, B, or C below | $300–$4,500+ | See §4.3 | See §4.3 |

### 4.3 Stage 3 — Breakout-Hit Scale

**Load profile:** 10,000 concurrent 5v5 lobbies × 1,800 packets/sec = **18 million packets/sec**, roughly **14–20 Gbps** of aggregate traffic.

> [!WARNING]
> **Why 10,000 separate Godot containers is prohibitive** — One headless Godot process per match at ~75–80 MB RAM and 0.125 vCPU means **~750 GB RAM and ~1,250 vCPUs** across 10,000 containers — about **$15,000–$35,000 per month** on managed game clouds. Most of that capacity idles, because a 10-player relay needs a tiny fraction of an engine instance.

| Path | Architecture | Footprint | Monthly cost | Trade-offs |
|---|---|---|---|---|
| A · Lightweight room relay fleet | Go or Rust (`uWebSockets`) relay, or Cloudflare Durable Objects; rooms are just routing tables | ~50 KB RAM per room (vs. ~80 MB); ~10 bare-metal/VPS nodes for all 10,000 lobbies | **$300–$1,200** | Cheapest by far; relay is not physics-authoritative, so hit validation must be lighter or client-trusted |
| B · Multi-tenant headless Godot on bare metal + Agones/Rivet | 50–100 rooms per headless Godot process; ~25 Hetzner AX102 / OVH bare-metal nodes | Keeps 100% GDScript server code; optional `SubViewport` server-authoritative raycasts | **$2,500–$4,500** | Authoritative and anti-cheat friendly; more ops work (orchestration, room packing) |
| C · Hybrid (recommended) | Steam P2P on PC or lightweight relay on web for casual/custom lobbies; dedicated bare metal + Edgegap burst only for Ranked Tournament Brackets | Pays for authoritative compute only where competitive integrity matters | **$0–$500** casual + ranked fleet sized to demand | Best cost/quality balance; two server paths to maintain |

![Figure 7 — Path C: recommended hybrid architecture.](architecture_diagrams/hybrid.png)
*Figure 7 — Path C: recommended hybrid architecture.*

## 5. Recommendations & Next Steps

| Priority | Action | Why |
|---|---|---|
| Now | Keep Edgegap for playtests; add a `room_id` lobby list and per-room isolation tests | Supports 1–5 lobbies with no new spend |
| Now | Pack per-tick state into one binary `PackedByteArray` snapshot per recipient; add ~100 ms interpolation buffer | Cuts message count from N×(N−1) to N and hides TCP stalls |
| Next | Prototype `WebRTCMultiplayerPeer` unreliable channel for movement, signaled over the existing WSS gateway | Removes head-of-line blocking for browser players |
| Next | Integrate GodotSteam; ship a Steam Playtest with `SteamMultiplayerPeer` listen servers | $0 server bill for PC casual play; free SDR DDoS/NAT |
| Launch | Move the server to multi-room headless Godot on a Hetzner/OVH node (Stage 2A), with Edgegap as burst (Stage 2B) | ~$15–$40/mo baseline with managed overflow |
| Scale | Adopt Path C hybrid; reserve authoritative bare metal for Ranked brackets | Keeps 10,000-lobby scale in the low thousands per month |

### Glossary

| Term | Meaning |
|---|---|
| Peer #1 | Godot’s ID for the server/authority in the high-level multiplayer API |
| HoL blocking | Head-of-line blocking: a lost TCP segment delays delivery of all later data |
| SDR | Steam Datagram Relay — Valve’s relay network for UDP game traffic |
| Listen server | A player’s game client also acts as the match host |
| Tick rate | How many state updates per second the simulation sends (20 Hz today) |
| Snapshot | One packed message containing all relevant entity state for a tick |
