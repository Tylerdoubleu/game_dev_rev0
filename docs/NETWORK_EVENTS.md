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
| `request_start_match(room, bracket, fill_bots)` | Start the room's match after a 3 s countdown (`match_starting`, then `match_countdown` 3,2,1, then `round_started`). It does not wait for READY. A second press during the countdown is ignored. |
| `srv_set_ready(ready)` | The READY toggle. Use `NetworkLobby.set_ready(bool)`. It is informational only and resets to false after each match. |

Client helpers:
- `NetworkLobby.set_ready(bool)` sends `srv_set_ready` when online, or updates the offline roster.
- `NetworkLobby.leave_room()` disconnects cleanly (the server drops the peer from its room) and clears room, match and ready state. On web it strips `room`, `team`, `map` and `mode` from the URL. It then emits `left_room(room_id)`, and LobbyEntryFlow reopens the lobby list.

Server → client (authority, per peer): `sync_lobby_state(state)`, `notify_match_start(room, bracket, fill_bots)`, `cl_room_event(name, data)`, `rpc_sync_player_state(...)`, `rpc_fire_paintball(...)`, `rpc_notify_bot_eliminated`, `rpc_broadcast_flag_event`.

Client signals: `match_starting(data)` and `match_countdown(seconds_left, data)`. These names are stable, and the HUD countdown banner hooks them. `room_roster_changed(roster)` fires on every `sync_lobby_state`, and `left_room(room_id)` fires after `leave_room()`.

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
| `player_ready_changed` | peer, name, ready | A player toggled READY. The roster is re-synced too. |
| `match_starting` | in_ms (3000), seconds (3), by, by_name, mode, map | Someone pressed Start Match. Settings lock now. |
| `match_countdown` | seconds_left (3, 2, 1), ms_left | Sent once per second during the countdown. `round_started` follows at 0. The countdown is cancelled if the room empties. |
| `teams_rebalanced` | moves:[{peer,name,from,to}], red, blue | Auto-balance moved players. |
| `join_rejected` (to one peer) | room, reason=`full`/`unknown_lobby` | The join was refused. |
| `round_started` | round, mode, score, kills, target, reset_positions:true | The match starts (round 1), or the next CTF round starts after a 4 s intermission. **Clients respawn at their team gate.** NetworkLobby already does this via `respawn_at_team_gate`. |
| `player_eliminated` | victim, victim_name, victim_team, shooter, shooter_name, shooter_team, victim/shooter_kills/deaths, reason, scored | A validated hit. `scored=false` while waiting (practice). |
| `hit_rejected` (to the shooter) | victim, reason | The hit failed validation (see below). |
| `flag_state_changed` | flag_team, flag (red/blue), state, action, carrier, carrier_name, by, by_name, pos | CTF actions: `picked_up`, `dropped` / `carrier_eliminated` / `carrier_left`, `returned`, `auto_returned` (after 30 s), `captured`, `reset`. |
| `round_ended` | round, winner, winner_color, reason (`capture` / `elimination` / `double_elimination`), by, score{red,blue}, next_round_in_ms | A CTF round is over. |
| `match_ended` | winner, winner_color, reason (`kills` / `rounds`), mode, score{red,blue}, kills, rounds | The match is won. The room goes back to `waiting`, and everyone is alive again. |

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
