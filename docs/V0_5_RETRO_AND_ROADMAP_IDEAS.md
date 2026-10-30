# v0.5 Retro & Roadmap Ideas (for later review)

Collected in the Indie Game Studio room on 2026-10-30, right after Tyler called v0.5 (`v0.5.0-playtest`, `3924647`) a success.
Nothing here is committed scope yet: it is a menu to pick v0.6+ work from. Each item names who suggested it.

Categories: **Art**, **Core Gameplay**, **Technical**.

---

## 1. One fix each (existing state of the game)

| Who | Category | Fix | Why |
|---|---|---|---|
| Tim | Technical | Stop the live server restarting on every push to main (update only on a tagged release, or wait until no room has a match). | Every push currently drops everyone mid-match. |
| Grok Bot | Technical | Same as above: update the server only when nobody is in a match, or only on release tags. | On a busy dev night that is a disconnect every few minutes. |
| Ren | Art | Reskin the lobby browser and waiting room in the worn "Gritty 2000s Tournament" style: stenciled team names, taped bracket cards, a grimy LED countdown. | They are the first screens players see and still look like flat placeholder panels with default fonts. |
| Bluey | Core Gameplay | Decide a timed-out CTF round by the flag: the team holding the enemy flag, or whose carrier got it furthest, wins, and players alive only break ties. | "More players alive wins" rewards sitting in a bunker over pushing for the flag. |

Carry-over from v0.5 (Bluey): **per-map gun-class rules (PB-06)** were never started. They are at the top of the v0.6 list.
Open server items (Tim): shots that bounce fail the server's line-of-sight check, and the optional 20 updates-per-second snapshot batching (phase 7) was never done.

---

## 2. Near-term improvement ideas (two each)

### Art
- **Paint that stays where it lands** (Ren): team-colored splats on bunkers, the ground and jerseys build up over a round. A quick "field crew" wash between CTF rounds resets them, so you can read the fight after it's over.

### Core Gameplay
- **Play with friends as a party** (Tim): a group joins a lobby together and stays on one team. Auto-balance moves a whole party at once instead of splitting friends.
- **Custom team jersey and callsign** (Ren): pick a jersey pattern and colorway in the waiting room, with your callsign printed across your back. Teammates are easier to tell apart, and spectating feels more personal.
- **A real "break" at round start** (Bluey): both teams wait behind their start line for a 3-2-1 horn, then sprint for their first bunkers. This rewards good dives and lane shooting.
- **Bunker callouts** (Bluey): every bunker gets a name ("Snake 2", "Home Can"), and one key pings the bunker you're aiming at to your team, for example "1 in Snake 2". It builds on the stick-to-bunker cover.

### Technical
- **Fairer hit detection** (Tim): the server rewinds both players to when the shot was fired and traces the real paintball path, bounces included. This is the remaining part of [#17](https://github.com/Tylerdoubleu/game_dev_rev0/issues/17).
- **Make stale builds impossible** (Grok Bot): put a version number in the build file names, and have the server tell an out-of-date game to reload. That would have caught the leave-site scare and the mismatched `srv_flag_event` call.
- **Separate live and test servers** (Grok Bot): `play.jeetball.com` serves only tagged releases for friends, `test.jeetball.com` runs the latest main for the team, and the game page moves to `jeetball.com`.

---

## 3. Stretch goals (longer range)

### Art
- **A full tournament venue** (Ren): netting, pit tents, sponsor banners, chrono stations, bleachers with a crowd, and a PA announcer calling eliminations and flag pulls, so it feels like the NPPL finals.
- **A gear locker with real cosmetics** (Ren): era-style masks, jerseys, pants, packs, hopper colorways and marker milling, plus a team logo builder for the whole squad. Unlocked by playing, never pay-to-win.

### Core Gameplay
- **Tournament mode** (Tim): brackets for 4 to 16 teams, best-of-5 CTF series, a bracket screen that advances by itself, and spectator seats for knocked-out teams.
- **Persistent player profiles** (Tim): lifetime accuracy, eliminations, flags and best bunker, with earned (not bought) unlocks. Pairs with Ren's jersey and gear ideas.
- **Instant replay and highlight cam** (Ren): the best elimination or flag pull of each round replays from a broadcast angle with paint trails. This is also the base for a caster or spectator mode.
- **Career mode like Greg Hastings** (Bluey): go from rookie on a local team up through amateur divisions to a pro league, with sponsors, gear unlocks, lineup management and rivalries.
- **Bot teammates you can give orders to** (Bluey): bots that take the right bunkers off the break, call out enemies, and follow "push left", "hold" or "cover me", so short-handed matches feel like 5v5.
- **Real tournament formats** (Bluey): X-Ball (race to a set number of points with a game clock), standard 7-man, and woodsball scenario games with objectives, plus a rotating set of official field layouts.
- **Ranked play and seasons** (Bluey, Tim, Grok Bot): skill-based matchmaking, a season ladder, team rankings, and stat pages (eliminations, flags, accuracy by gun class).
- **Gear that matters** (Bluey): markers, barrels, hoppers and packs with real tradeoffs (rate of fire against accuracy, more paint against more weight, faster feeding against a bigger silhouette), replacing fixed gun classes with loadouts.

### Technical
- **Ranked matchmaking with accounts** (Tim, Grok Bot): logins, saved stats and match history, a hidden skill rating, a "Find Match" queue that fills a 5v5, and season leaderboards on `jeetball.com`.
- **Servers in several regions that grow with demand** (Tim, Grok Bot): US East, US West and Europe, with new match servers starting automatically as lobbies fill and each player sent to the closest one by ping. Paintballs are slow, so lag is easy to feel. Today's single server tops out at about 10 lobbies on the West Coast.
- **Match replays and a cheat-resistant server** (Tim, Grok Bot): the server already decides hits, so it can record each match for replays and highlight reels, and flag aim that looks impossible.
- **Ship on Steam and itch.io** (Grok Bot): automatic Windows, Mac and Linux builds on every release, Steam friend invites, achievements and a store page.
- **Woodsball and scenario map pipeline** (Ren): a modular kit of bunkers, terrain, foliage and props for building bigger 10v10 objective fields quickly, like the heli crash at a much larger scale.

---

## 4. Overlaps worth noticing
- **Ranked play and accounts** came up three times (Tim, Grok Bot, Bluey). They also underpin profiles, unlocks, seasons and the gear locker.
- **Replays** came up three times (Tim, Grok Bot, Ren): server recording, highlight cam and anti-cheat all come from the same match log.
- **Server stability** was the top fix for both Tim and Grok Bot, together with stale builds and the live/test split. It's the cheapest win before the next playtest.
