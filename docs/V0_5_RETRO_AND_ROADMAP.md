# v0.5 Retro and Long-Range Roadmap

Collected from the Indie Game Studio chat on 2026-10-30, after Tyler called v0.5 (`v0.5.0-playtest`, tagged at `3924647`) a success. Nothing here is committed scope yet; it's the list to review when planning v0.6 and beyond.

Already carried into the v0.6.0 milestone: per-map gun-class rules (PB-06), lag-compensated rewind (#17), bounced shots failing the server's line-of-sight check, and 20 Hz network batching.

## Part 1: One fix and two ideas each

### Ren (Artist)
- **Fix:** The lobby browser and waiting room still look like flat placeholder panels with default fonts. Reskin both in the Gritty 2000s Tournament style: stenciled team names, taped bracket cards, a grimy LED countdown.
- **Idea (Art): paint that stays.** Team-colored splats on bunkers, ground and jerseys build up through a round, then a quick "field crew" wash resets them between CTF rounds.
- **Idea (Core Gameplay): custom jerseys and callsigns.** Pick a jersey pattern and colorway in the waiting room, with your callsign printed across your back.

### Grok Bot
- **Fix:** Every push to main restarts the live server and drops matches in progress. Update only when no one is in a match, or only on tagged releases.
- **Idea (Technical): no more stale builds.** Version numbers in build file names, and the server tells an out-of-date client to reload.
- **Idea (Technical): separate live and test servers.** `play.jeetball.com` serves tagged releases only, `test.jeetball.com` runs latest main, and the game page moves onto `jeetball.com`.

### Tim (Thinker / Researcher)
- **Fix:** Same restart problem as above. Update only on a release tag, or wait until all rooms are empty before restarting.
- **Idea (Technical): fairer hit detection.** Rewind both players to the moment of the shot and trace the paintball's real path, bounces included. This is the rest of #17.
- **Idea (Core Gameplay): parties.** Friends join a lobby together and stay on the same team; auto-balance moves a whole party at once.

### Bluey (Gameplay Director)
- **Fix:** CTF time-outs currently go to the team with more players alive, which rewards camping. Make the flag decide it instead (holding the enemy flag, or the carrier who got it furthest), with players alive only as a tiebreaker.
- **Idea (Core Gameplay): a real break.** Teams wait behind their start line for a 3-2-1 horn, then sprint for their first bunkers.
- **Idea (Core Gameplay): bunker callouts.** Every bunker gets a name ("Snake 2", "Home Can"), and one key pings the bunker you're aiming at to your team ("1 in Snake 2").

## Part 2: Stretch goals

### Art
- **Full tournament venue** (Ren): netting, pit tents, sponsor banners, chrono stations, bleachers with a crowd, and a PA announcer calling eliminations and flag pulls.
- **Gear locker with real cosmetics** (Ren): era-style masks, jerseys, pants, packs, hopper colorways and marker milling, plus a team logo builder. Earned by playing, never pay-to-win.

### Core Gameplay
- **Career mode like Greg Hastings had** (Bluey): rookie on a local team up through amateur divisions to a pro league, with sponsors, gear unlocks, lineup management and rivalries.
- **Bot teammates you can give orders to** (Bluey): bots that take smart bunkers off the break, call out enemies, and follow "push left", "hold", "cover me".
- **Real tournament formats** (Bluey): X-Ball races with a game clock, standard 7-man, and woodsball scenario games, with a rotating set of official field layouts.
- **Tournament mode** (Tim): brackets for 4 to 16 teams, best-of-5 CTF series, a self-advancing bracket screen, and spectator seats for knocked-out teams.
- **Gear that matters** (Bluey): markers, barrels, hoppers and packs with real tradeoffs (rate of fire vs accuracy, paint capacity vs weight, feed speed vs silhouette) instead of fixed gun classes.
- **Persistent player profiles** (Tim): lifetime stats (accuracy, eliminations, flags, best bunker) and earned unlocks like jerseys and marker skins.
- **Ranked play and seasons** (Bluey, Tim, Grok Bot): skill-based matchmaking, a season ladder, team rankings and stat pages.
- **Instant replay and highlight cam** (Ren): the round's best elimination or flag pull replayed from a broadcast angle with paint trails, leading into a spectator/caster mode.

### Technical
- **Ship on Steam and itch.io** (Grok Bot): automatic Windows, Mac and Linux builds on every release, Steam friend invites, achievements and a store page.
- **Accounts and ranked matchmaking** (Grok Bot, Tim): logins, saved stats and match history, a hidden skill rating, and a Find Match / Play button that fills a 5v5 queue.
- **Servers in several regions** (Grok Bot, Tim): US East, US West, Europe and more, picked by ping, with match servers that start automatically as lobbies fill. Today's single server tops out around 10 lobbies on the West Coast, and slow paintballs make 150 ms of lag very noticeable.
- **Match replays and cheat detection** (Grok Bot, Tim): the server already decides hits, so it can record every match for replays, highlight reels, balance debates and flagging impossible aim.
- **Woodsball and scenario map pipeline** (Ren): a modular kit of bunkers, terrain, foliage and props for building larger 10v10 objective fields quickly.
