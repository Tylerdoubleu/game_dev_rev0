# v0.5 network events API (Tim, PB-12 / PB-13)

This is for Bluey (gameplay and HUD) and Ren (UI). The server in `scripts/autoload/network_lobby.gd`, running as `godot --headless -- --server`, owns the following:
- rooms
- teams
- the match rules: kills, rounds, flags, and who is alive
- hit validation

Clients send intents. The server sends facts back, and only to the members of the sender's room.

## Rooms
- There are 10 permanent public lobbies, `lobby_01` to `lobby_10`, each 5 v 5. There are also ad-hoc private rooms (any other `?room=`), which are removed when empty.
- Teams are `ALPHA` (red, base and gate at z = +45.5) and `BRAVO` (blue, z = -45.5). Events also give `red`/`blue` for display.
- Auto-balance:
  - A joiner goes to the smaller team. Ties go to red.
  - A `team=` request is honoured only if it doesn't make that team bigger than the other one.
  - Players can't switch teams during a match.
  - At match start and between CTF rounds, the server moves the latest joiners until the teams differ by at most 1 (`teams_rebalanced`).
- Settings (map/mode): any player may change them while the room is `waiting` (`srv_set_room_settings`). They lock at match start. Brackets (speedball, woodsball, pump) stay per player.

## Entry flow (web)
- A bare `https://tylerdoubleu.github.io/game_dev_rev0/` link doesn't connect. The `LobbyEntryFlow` autoload shows Ren's `LobbyBrowser`, using `GET https://play.jeetball.com/api/lobbies`. `?server=` overrides the server.
- **JOIN** navigates to `join_url`, which is `...?server=wss://.../ws&room=lobby_NN&map=...`. That page then auto-connects to the room.
- **SOLO TEST VS BOTS** runs the offline flow: NPC presence ON, then DROP IN.
- The arena lobby menu has a **BROWSE ONLINE LOBBIES** button, added at runtime.

## HTTP
`GET /api/lobbies` returns:
```json
{"lobbies":[{"id":"lobby_01","name":"Lobby 01","map":"speedball","mode":"deathmatch",
  "players":{"red":2,"blue":1},"max_per_team":5,"status":"waiting|in_match|full","bots":false,
  "join_url":"https://tylerdoubleu.github.io/game_dev_rev0/?server=wss://play.jeetball.com/ws&room=lobby_01&map=speedball&mode=deathmatch"}]}
```
- `GET /api/quickjoin` returns the waiting lobby with the most players that still has room, as `{lobby, join_url}`. With `?redirect=1` it returns a 302 instead.
- If the Godot state is stale, the response is 503.

## RPCs
Client → server (always `rpc_id(1)`):

| RPC | Purpose |
|---|---|
| `register_player_info(callsign, team, bracket, ready, room, map, mode)` | Join or update. The server picks the team. |
| `srv_player_state(pos, yaw, pitch, lean, packed_stance, eliminated)` | About 20 Hz movement and stance (bracket bits included). |
| `srv_fire(origin, dir, speed_fps)` | Shot intent. Validated, then relayed to the room as `rpc_fire_paintball`. |
| `srv_report_hit(victim_peer, hit_pos)` | The shooter's local hit. The server validates it and may emit `player_eliminated`. |
| `srv_bot_eliminated(name)`, `srv_flag_event(...)` | Cosmetic relays (legacy centre flag). |
| `srv_set_room_settings(map, mode)` | Change the lobby map or mode (waiting only). |
| `request_start_match(room, bracket, fill_bots)` | Start the room's match after a 5 s countdown (`match_starting`, then `match_countdown` 5,4,3,2,1, then `round_started`). It does not wait for READY. A second press during the countdown is ignored.<br>If a team is still empty after auto-balance, the requester gets `start_rejected` (reason `team_empty`). That check is skipped when the mode is `bots_test` or the `fill_bots` arg is true.<br>Online clients don't drop in on the press; they wait for `notify_match_start`. |
| `srv_cancel_start()` | Any player in the room cancels a running countdown. Use `NetworkLobby.cancel_start()`. The settings unlock, the room stays `waiting`, and the server emits `match_start_cancelled`. |
| `srv_set_ready(ready)` | The READY toggle. Use `NetworkLobby.set_ready(bool)`. It is informational only and resets to false after each match. |

Client helpers:
- `NetworkLobby.set_ready(bool)` sends `srv_set_ready` when online, or updates the offline roster.
- `NetworkLobby.leave_room()` disconnects cleanly (the server drops the peer from its room) and clears room, match and ready state. On web it strips `room`, `team`, `map` and `mode` from the URL. It then emits `left_room(room_id)`, and LobbyEntryFlow reopens the lobby list.

Server → client (authority, per peer): `sync_lobby_state(state)`, `notify_match_start(room, bracket, fill_bots)`, `cl_room_event(name, data)`, `rpc_sync_player_state(...)`, `rpc_fire_paintball(...)`, `rpc_notify_bot_eliminated`, `rpc_broadcast_flag_event`.

Client signals: `match_starting(data)`, `match_countdown(seconds_left, data)`, `match_start_cancelled(data)` and `start_rejected(reason, data)`. These names are stable, and the HUD countdown banner hooks them. `room_roster_changed(roster)` fires on every `sync_lobby_state`, and `left_room(room_id)` fires after `leave_room()`.

Listen to `NetworkLobby.room_event(event_name, data)`. It fires on clients for every `cl_room_event`, and on the server for every room event.

## `sync_lobby_state` → `room_state.match`
```
{phase: "waiting"|"live"|"intermission", mode: "deathmatch"|"ctf"|"bots_test", round, best_of: 5,
 target (10 kills or 3 rounds), score:{red,blue} (CTF rounds won), kills:{red,blue},
 flags:{red:{team:"ALPHA",state:"home"|"carried"|"dropped",carrier,pos}, blue:{...}}}
```
Each player has `team`, `alive`, `kills`, `deaths`, `bracket` and `ready`.

The snapshot also carries the following fields:
- `room_roster`: rows in join order, `[{peer, name, team, color:"red"|"blue", ready, alive, kills, deaths, bracket}]`.
- `ready_count`.
- `countdown_ms_left`: 0 unless a countdown is running.

## Room events (`cl_room_event` / `room_event`)

Every room event includes `room`.

| Event | Data | When |
|---|---|---|
| `room_settings_changed` | map, mode, by, by_name | A player changed settings (waiting only). |
| `settings_rejected` (to one peer) | reason=`match_in_progress` / `match_starting`, map, mode | A settings change arrived after match start or during the countdown. |
| `player_ready_changed` | peer, name, ready, team, color | A player toggled READY. Pressing READY takes a team spot: the side with fewer READY players (ties keep your side; a `teams_rebalanced` with `reason: "ready"` is sent if you moved). The roster is re-synced too. |
| `match_starting` | in_ms (5000), seconds (5), by, by_name, mode, map | Someone pressed Start Match. Settings lock now. |
| `match_countdown` | seconds_left (5, 4, 3, 2, 1), ms_left | Sent once per second during the countdown. `round_started` follows at 0. The countdown is cancelled if the room empties. |
| `match_start_cancelled` | by, by_name | A player called `cancel_start()` during the countdown. The settings unlock and the room is back to `waiting`. |
| `start_rejected` (to the requester) | room, reason=`team_empty`, red, blue | Start Match was refused. |
| `teams_rebalanced` | moves:[{peer,name,from,to}], red, blue | Auto-balance moved players. |
| `join_rejected` (to one peer) | room, reason=`full`/`unknown_lobby` | The join was refused. |
| `round_started` | round, mode, score, kills, target, reset_positions:true | The match starts (round 1), or the next CTF round starts after a 4 s intermission. **Clients respawn at their team gate.** NetworkLobby already does this via `respawn_at_team_gate`. |
| `player_eliminated` | victim, victim_name, victim_team, shooter, shooter_name, shooter_team, victim/shooter_kills/deaths, reason, scored | A validated hit. `scored=false` while waiting (practice). |
| `hit_rejected` (to the shooter) | victim, reason | The hit failed validation (see below). |
| `flag_state_changed` | flag_team, flag (red/blue), state, action, carrier, carrier_name, by, by_name, pos | CTF actions: `picked_up`, `dropped` / `carrier_eliminated` / `carrier_left`, `returned`, `auto_returned` (after 30 s), `captured`, `reset`. |
| `round_ended` | round, winner, winner_color, reason (`capture` / `elimination` / `double_elimination` / `time`), by, by_name, score{red,blue}, target, best_of, next_round_in_ms (8000, or 0 when it decided the match), match_point, scoreboard | A CTF round is over. Show the round winner + scoreboard for `next_round_in_ms`; `round_started` follows. Client signal: `round_results(data)`. |
| `match_ended` | winner, winner_color, winner_names, reason (`kills` / `rounds`), mode, score{red,blue}, kills, rounds, scoreboard, return_to_lobby_in_ms (12000) | The match is won. Show the congrats + scoreboard recap; READY resets. Client signal: `match_results(data)`. |
| `returned_to_lobby` | room | Sent `return_to_lobby_in_ms` after `match_ended`: everyone goes back to the waiting room (LobbyEntryFlow opens it). Client signal: `returned_to_lobby(room_id)`. |

Round timer / respawn (v0.5): CTF rounds last `CTF_ROUND_TIME_MS` = 180000 ms. On time-out the team with more players alive wins the round (`reason: "time"`); equal = draw (no point). `round_started` carries `round_time_ms` and `respawn_ms`; `sync_lobby_state.match` carries `round_time_ms`, `round_ms_left` (0 outside a live CTF round) and `respawn_ms` (DM 1000, practice 1000, CTF 0 = none until next round); `player_eliminated` carries `respawn_in_ms`. `room_roster` rows and `players` entries carry live `captures`.

`scoreboard` rows: `{peer, name, team, color, kills, deaths, captures}`, red first, then blue, each sorted by kills, captures, fewest deaths.

## Modes
- **deathmatch**: first team to 10 kills. Respawn after 1 s.
- **ctf**: one life per round, best of 5 (first to 3).
  - Each base has one flag. The enemy flag is picked up within 2.35 m of it, and captured by bringing it within 4.2 m of your own base.
  - A round ends on a capture or a full team elimination. Late joiners sit out the current round.
- **bots_test**: bots on, kills counted, no win condition.

## PB-13 hit validation
Shot (`srv_fire`) rejections:
- `shooter_dead`
- `fire_lock` (sliding/diving, or the 0.10 s recovery)
- `origin_mismatch` (more than 3 m from the last state)

The speed is clamped to 150–300 fps. Accepted shots are kept for 3 s.

Hit (`srv_report_hit`) rejections, in order:
1. `friendly_fire`, `victim_dead`
2. `no_matching_shot`, `aim_mismatch` (more than 12°, drop-compensated, and at most 90 m)
3. `outside_hitbox`: the stance box from victim history (standing 1.95 m, crouch 1.30 m, prone or dive 0.80 m, slide 1.0 m; radius 0.9 m, or 1.3 m prone or dive)
4. `no_line_of_sight`: the chord or the gravity+drag arc is blocked by static arena geometry. The server builds a collision-only copy of each map.

## Notes for Bluey and Ren
- **CTF visuals are still the legacy single centre flag.** Please render the two base flags from `flag_state_changed` and `room_state.match.flags`.
- In CTF, a local death still respawns the player locally, but the server keeps them dead until `round_started`, so their shots and hits are rejected. That calls for a spectate/dead HUD state, driven by `players[me].alive == false`.
- Ren: `LobbyBrowser.MODE_LABELS` has no `bots_test` key. The API sends `bots_test`.

## v0.6: the break (3-2-1 + horn) and callout pings

**Phases:** `waiting` → `break` → `live` → `intermission` → … The server runs the break; clients only display it.

| Event | Scope | Fields | Client signal |
|---|---|---|---|
| `round_started` | room | adds `break_ms` (3000; 0 in bots_test) and `break_line_z` (40.0) | `round_started` |
| `break_countdown` | room | `round`, `seconds_left` (3, 2, 1), `ms_left` | `break_countdown(seconds_left, data)` |
| `break_horn` | room | `round`, `mode` | `break_horn(data)`, play the horn and release the start line |
| `break_line_reset` | the player who pushed past the line | `room`, `team`, `gate`, `line_z` | `break_line_reset(data)`, the client clamps the player back onto the line (hard hold, no false-start penalty) |
| `callout_pinged` | pinger's team only (pinger included) | `room`, `peer`, `name`, `team`, `color`, `callout` (≤24 chars), `count` (0..5), `pos` | `callout_pinged(data)` |

- Start lines: ALPHA must stay at `z >= 40`, BRAVO at `z <= -40` until the horn. Jumping early is simply prevented: the server pushes anyone over the line back onto it (at most every 150 ms). No FALSE START, no penalty.
- Shots and hit reports during the break are rejected with reason `before_horn`, and during the round recap (intermission) with `round_over`.
- The CTF round clock (`round_ms_left`) starts at the horn, not at `round_started`.
- Client API: `NetworkLobby.ping_callout(callout: String, world_pos: Vector3, count := 1)`. Alive players only, with a 1.2 s cooldown per player. Extra pings are dropped silently.
- Tests set `NetworkLobby.break_countdown_ms = 0` to skip the break.

## v0.7 profile API (anonymous profiles, callsigns, clout)

Code: `server/profile_store.js` (store + HTTP handlers, mounted by `server/server.js`), client helper
`scripts/systems/profile_api.gd` (`ProfileApi`), server hook in `scripts/autoload/network_lobby.gd`.
Tests: `cd server && node --test test` (`test/profile_api.test.js`) and
`godot --headless --path . -s res://scripts/systems/test_profile_hook.gd`.

No sign-up: the client creates a profile once and keeps the private token in `user://profile.cfg`
(browser storage on the web build; clearing site data loses the profile). All bodies are JSON. CORS is the same
allow-list as `/api/lobbies` (`CORS_ORIGINS`); preflight allows `GET, POST, PUT, OPTIONS` and
`Content-Type, Authorization`. Authenticated calls send `Authorization: Bearer <token>`.

| Request | Success | Errors |
|---|---|---|
| `POST /api/profile` (no body) | `201 {profile_id, token, callsign:null, clout:0, career:null}`. `token` = 64 hex chars, shown only here. | `429 {error:"rate_limited"}` after 10 creates per IP per hour |
| `GET /api/profile` | `200 {profile_id, callsign, clout, stats:{matches,wins,eliminations,flags,rounds_won}, career, created_at}` | `401 {error:"unauthorized"}` |
| `PUT /api/profile/callsign` `{callsign}` | `200` same shape as GET. Display case is kept; uniqueness is case-insensitive; the old name is released. | `400 {error:"invalid_callsign"}` unless 3-16 of `A-Z a-z 0-9 _ -`; `409 {error:"callsign_taken"}`; `401` |
| `PUT /api/profile/career` `{career:<object or null>}` | `200` same shape as GET. Opaque blob for career mode. | `413 {error:"career_too_large"}` if `JSON.stringify(career)` > 32 KB (any body > 64 KB is `413 {error:"too_large"}`); `400 {error:"invalid_career"}` if not an object; `401` |
| `GET /api/profile/public/<callsign>` (case-insensitive) | `200 {callsign, clout, stats}` (never id/token) | `404 {error:"not_found"}` |

Clout is **never client-writable** (there is no clout endpoint; extra fields in bodies are ignored).

### Server-awarded clout

At match end (deathmatch / ctf only; `bots_test` earns nothing) the headless Godot server POSTs
`http://127.0.0.1:<PORT>/internal/match_result` with header `X-Internal-Key: <INTERNAL_KEY>`:

```json
{"room":"lobby_03","mode":"ctf","match_id":"lobby_03_1793462400000_123",
 "results":[{"token":"<64 hex>","won":true,"eliminations":3,"flags":1,"rounds_won":3}]}
```

A row may use `profile_id` instead of `token`. Rejected with `403` unless the TCP peer is loopback, there is no
`X-Forwarded-For` / `Forwarded` / `X-Forwarded-Host` header (so nothing through Caddy is accepted), and the key
matches. `400` for a body without `results`. Response `200 {awarded:[{profile_id, clout}], ignored, duplicate}`.
Unknown tokens/ids are ignored, each profile counts once per report, a repeated `match_id` is ignored
(`duplicate:true`), at most 10 rows are read. Per match each player is clamped to eliminations <= 50,
flags <= 5, rounds_won <= 5. Values (`CLOUT` in `server/profile_store.js`, the one place to change them):

| Online, server-awarded | Clout |
|---|---|
| elimination | +5 |
| flag hang (capture) | +25 |
| CTF round won by your team | +25 |
| match win | +75 |

There is no "match played" bonus. `rounds_won` is your team's CTF round score (0 in deathmatch);
`eliminations` / `flags` are your room `kills` / `captures`.

**Token handling in the game socket:** the client sends its token only with `srv_set_profile_token(token)`
(client -> server, after `register_player_info`, or when `NetworkLobby.set_profile_token()` is called while
online). The server keeps it in `_peer_profile_tokens` (peer -> token), drops it on disconnect, and never puts it in
`rooms[...]["players"]`, rosters, `sync_lobby_state`, room events or the lobby state file.

### Env vars (server.js)

- `DATA_DIR`: folder for `profiles.json`. Default `os.tmpdir()/paintball_data`. Must be outside the checkout
  (the update script resets it) and different per instance (test vs live).
- `INTERNAL_KEY`: shared secret for `/internal/match_result`. If unset, server.js generates one per run and passes it
  (with `PROFILE_API_URL=http://127.0.0.1:<PORT>`) to the Godot server it spawns with `AUTO_START_GODOT=1`. Set it
  explicitly only if Godot is started some other way (then also set `PROFILE_API_URL` for Godot).
- `PROFILE_CREATE_LIMIT_PER_HOUR`: optional, default 10. Behind Caddy the rate-limit IP is the right-most
  `X-Forwarded-For` entry.

### TODO (needs a separate decision)

Solo rewards (stars, challenges, tiers vs bots) are **not** part of this API. They would be client-reported, so they
cannot be trusted like online clout; decide whether they stay in the career blob only or get their own capped,
clearly-separate counter.
