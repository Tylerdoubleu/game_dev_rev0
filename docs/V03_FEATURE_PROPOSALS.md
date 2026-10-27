# v0.3 Feature Proposals & Ticket Backlog (`Tylerdoubleu/game_dev_rev0`)

Compiled studio proposals for **`v0.3`**, building on the **`v0.2.4` Gritty 2000s Tournament** baseline (`e1d54eb`).

---

## 1. Ren (Artist) — Top 3 Art, Immersion & Visual Polish Features

### 1. [Issue #13 (`PB-12`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/13): Visor Paint Obstruction, Squeegee Wipe Mechanic (`[G]`) & Thermal Lens Fogging
- **Near-Miss & Bunker-Rub Lens Splatter:** Paintballs breaking within `1.2m` of the player's head or rubbing against a freshly painted bunker cast translucent neon yellow/pink mist droplets onto the outer edges of the first-person thermal visor without eliminating the player.
- **Interactive Squeegee / Microfiber Glove Wipe (`[G]`):** Pressing **`[G]`** triggers a quick `0.6s` left-hand microfiber glove wipe animation across the screen that smears and clears paint mist off your lens.
- **Upgraded `"YOU'VE BEEN HIT!"` Visor-Break Jump-Scare & Heavy-Breathing Lens Fog:** Multi-layered high-gloss gelatin shell crack + viscous dripping paint shader across the curved lens on direct hit, plus subtle thermal condensation along the bottom goggle bezel after hard sprints, knee-slides, and superman dives.

### 2. [Issue #15 (`PB-13`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/15): Soft-Body Inflatable Bunker Deformation, Turf Slide Trenches & 2004 Broadcast Sideline Props
- **Reactive Inflatable Vinyl Bunker Flex & Pop:** Vertex-displacement / spring-impulse shader and scale punch on `StaticBody3D` air bunkers (`Doritos`, `Cans`, `Aztecs`, `Snake Beams`) so knee-sliding or diving into cover—or hammering a bunker with a 10.5 BPS string—visibly dents, shudders, and rebounds the vinyl skin.
- **Persistent Muddy Turf Slide Trenches & Cleat Spray:** Knee-slides (`Shift + C`) and Superman Dives (`Shift + Z/Alt/Ctrl`) kick up pooled 3D mud/turf chunks and leave dark, wet mud skid marks along the Snake and Dorito highways so players can visually read where opponents just slid.
- **2004 Tournament Broadcast Sideline Atmosphere:** Populate the outer perimeter (strictly outside the `±54m × ±66m` safety netting) with a **Chronograph Station & HPA Fill Table**, **Center-50 Broadcast Camera Crane**, **Sponsor Scrim Banners**, and live **3D LED Match Clock / Score Digits** on the North & South stadium scoreboards.

### 3. [Issue #16 (`PB-14`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/16): Articulated 2000s Pro Player Silhouettes, Exposed Hopper/Pack Hitboxes & Period-Authentic Marker Models
- **Articulated 2000s Tournament Player Avatars (`RemotePlayer_*` & `OpFor_*`):** Upgrade capsule avatars to articulated 2000s pro rigs with baggy tournament jerseys (Team Alpha Blue/Gold vs. Team Bravo Red/Black), padded slide pants, a rear **4+3 vertical pod pack harness**, **JT Proflex-style goggle mask**, and an **off-center motorized Halo/Reloader hopper + carbon-fiber HPA tank** that tilts with `Q`/`E` snap-leaning and left/right hand swaps (`X`).
- **Distinct Gear-Pack Hit Zones (Hopper, Marker & Pod Pack Breaks):** Accurate sub-colliders on the protruding hopper and marker profile so tight snap-shooters can clip an opponent's exposed loader or barrel tip when peeking a bunker edge.
- **3 Distinct Period-Authentic First-Person Marker Viewmodels per Bracket:**
  - **Speedball (`1`):** Milled Gloss-Anno Dual-Tube Electropneumatic (`2004 Intimidator / Shocker / Autococker` silhouette) with animated reciprocating bolt & LED board indicator.
  - **Woodsball (`2`):** Matte Olive/Black Tactical Mechanical Carbine (`Tippmann A-5 / Cyclone Feed` silhouette).
  - **Stock Pump (`3`):** Classic Pump Sniper with an animated under-barrel pump handle that slides back and forth when pressing `RMB` to rack a round, plus a visible 10-round feed tube.

---

## 2. Grok Bot — Top 3 Multiplayer Infrastructure & Release Engineering Features

1. **[Issue #14 (`PB-12`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/14): Multi-Room Server Isolation & Lateral 5v5 Breakout Gate Slots**
2. **[Issue #17 (`PB-13`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/17): Server-Authoritative Hit Validation & Lag-Compensated Rewind**
3. **[Issue #18 (`PB-14`)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/18): Automated Multi-Platform Release Pipeline (Windows, macOS, Linux, WebGL2 & Edgegap Health Monitor)**
