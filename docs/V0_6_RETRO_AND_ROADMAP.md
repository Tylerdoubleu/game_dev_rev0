# v0.5 Retro and Roadmap Ideas

Collected on Oct 30, 2026, after Tyler called v0.5 ([v0.5.0-playtest](https://github.com/Tylerdoubleu/game_dev_rev0/releases/tag/v0.5.0-playtest)) a success. This is for review only. Nothing here is committed to a release until Tyler picks it.

Categories: **Art**, **Core Gameplay**, **Technical**.

---

## 1. One fix each for the current game

| Who | Category | Fix |
|---|---|---|
| Grok Bot | Technical | Every push to main restarts the live server and drops anyone mid-match. The server should update only when no match is running, or only when a release is tagged. |
| Tim | Technical | Same problem as above, found separately. Update on release tags, or wait until all rooms are empty before restarting. |
| Ren | Art | The lobby browser and waiting room are flat placeholder panels with default fonts. Reskin both as a worn tournament scoreboard with stenciled team names, taped bracket cards, and a grimy LED countdown. |
| Bluey | Core Gameplay | When a CTF round times out, the team with more players alive wins, which rewards camping. Decide it by flag progress instead (holding the enemy flag, or the carrier who got furthest), and use players alive only to break a tie. |

Known carryover from v0.5:
- Per-map gun-class rules (PB-06) were never started.
- The server rejects legitimate shots that bounce off cover.
- 20 Hz snapshot batching isn't done.

## 2. Near-term ideas (two each)

### Grok Bot
- **Technical: no more stale builds.** Put a version number in each build's file names, and have the server tell an out-of-date game to reload itself.
- **Technical: separate live and test versions.** `play.jeetball.com` serves only tagged releases, `test.jeetball.com` tracks main, and the game page moves onto `jeetball.com`.

### Tim
- **Technical: fairer hit detection.** Rewind both players to the moment a shot was fired and trace the paintball's real path, bounces included. This is the rest of [#17](https://github.com/Tylerdoubleu/game_dev_rev0/issues/17).
- **Core Gameplay: parties.** Friends join a lobby together and stay on the same team. Auto-balance moves a whole party at once instead of splitting it.

### Ren
- **Art: paint that stays.** Team-colored splats build up on bunkers, the ground, and jerseys during a round. A quick "field crew" wash resets them between CTF rounds.
- **Core Gameplay: your own jersey and callsign.** Pick a jersey pattern and colorway in the waiting room, with your callsign printed on your back.

### Bluey
- **Core Gameplay: a proper break.** Teams wait behind their start lines for a 3-2-1 horn, then sprint for their first bunkers.
- **Core Gameplay: bunker callouts.** Every bunker gets a name ("Snake 2", "Home Can"), and one key pings the bunker you're aiming at to your team ("1 in Snake 2").

## 3. Stretch goals

### Art
- **A full tournament venue** (Ren). Netting, pit tents, sponsor banners, chrono stations, bleachers with a crowd, and a PA announcer calling eliminations and flag pulls.
- **A gear locker with cosmetics** (Ren). 2000s-era masks, jerseys, pants, packs, hopper colorways, and marker milling, plus a team logo builder. Cosmetics are earned by playing, never pay-to-win.

### Core Gameplay
- **Career mode like Greg Hastings had** (Bluey). Start as a rookie on a local team and climb through amateur divisions to a pro league, with sponsors, gear unlocks, lineup management, and rivalries.
- **Bot teammates you can give orders to** (Bluey). Smart bots take the right bunkers off the break, call out enemies, and follow orders like "push left", "hold", and "cover me".
- **Real tournament formats** (Bluey). X-Ball races to a set number of points, standard 7-man, and woodsball scenario games, with rotating official field layouts.
- **Gear that matters** (Bluey). Markers, barrels, hoppers, and packs with real tradeoffs (rate of fire against accuracy, paint load against weight, feed speed against silhouette) replace fixed gun classes.
- **Tournament mode** (Tim). Brackets for 4 to 16 teams with best-of-5 CTF series, a bracket screen that advances itself, and spectator seats for eliminated teams.
- **Persistent player profiles** (Tim). Lifetime stats such as accuracy, eliminations, flags captured, and favorite bunker, with earned unlocks. Pairs with Ren's gear locker.
- **Instant replay and highlight cam** (Ren). Replay the round's best moment from a broadcast angle with paint trails. This is also the base for a spectator and caster mode.

### Technical
- **Ship on Steam and itch.io** (Grok Bot). Automated Windows, Mac, and Linux builds on every release, Steam friends invites, achievements, and a store page.
- **Accounts and ranked matchmaking** (Grok Bot, Tim; also Bluey's ranked seasons). Logins, saved stats and match history, a hidden skill rating, and a Play button that queues a 5v5, with season leaderboards on `jeetball.com`.
- **Servers in several regions that grow with demand** (Grok Bot, Tim). Locations in US West, US East, and Europe, with lobbies sent to the closest one by ping and new servers starting as lobbies fill. Today's single $18/mo server holds about 10 lobbies.
- **Match replays and cheat checks** (Grok Bot, Tim). The server already decides hits, so it can record every match for replays, settling balance arguments, and flagging impossible aim.
- **A woodsball and scenario map pipeline** (Ren). A modular kit of bunkers, terrain, foliage, and props for building bigger 10v10 objective fields quickly.

## Themes that came up more than once
- The server restarting mid-match (Grok Bot, Tim). This is the easiest win for v0.6.
- Ranked play, accounts, and persistent profiles (Grok Bot, Tim, Bluey).
- Replays and spectating (Grok Bot, Tim, Ren).
- Earned cosmetics and identity: jerseys, callsigns, the gear locker (Ren, Tim).
- The 2000s tournament fantasy: the break, callouts, formats, the venue, career mode (Bluey, Ren, Tim).
