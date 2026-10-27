# Prototype Shortcuts, Backlog Tickets & Playtest Versioning

To get a playable 3D prototype up quickly (`v0.1.0-playtest`), we deliberately simplified specific systems and tagged each shortcut in code with `TODO(PB-XX)` and matching GitHub Issues on `Tylerdoubleu/game_dev_rev0`.

## 1. Tracked Prototype Shortcuts (`v0.1` -> `v0.2` / `v0.3` / `v0.4`)

| Ticket | System | What Is Live in `v0.1.0-playtest` | Target Upgrade Milestone | Code Location |
|---|---|---|---|---|
| **[PB-01 (Issue #1)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/1)** | **Movement & Peeking** | Discrete `Q`/`E` snap-lean with automatic left/right hand marker swap (`X`/`MMB`) and sprint knee-slide (`Shift` + `Ctrl`/`C`). | **`v0.2`:** Smooth `Alt + Mouse X` analog lean and separate hopper/elbow hitboxes. | `scripts/player/player_controller_3d.gd` |
| **[PB-02 (Issue #2)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/2)** | **Paint Ballistics & Decals** | Pooled 3D projectiles with gravity, air drag, surface-angle bounce-vs-break check (`cos < 0.42`), and surface-aligned splat meshes. | **`v0.2`:** Magnus backspin lift, crosswind drift, and projected `Decal` normal maps. | `scripts/autoload/paint_ballistics.gd` |
| **[PB-03 (Issue #3)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/3)** | **Punishing Pod Reloads** | Timed 2.0s `R` reload bar that spills/deletes the remaining pod paint if interrupted by sprinting or sliding, plus overfill spill math. | **`v0.2`:** Staged manual pod pour animations, physical spilled paintballs on turf, and spatial 3D rattle audio. | `scripts/player/player_controller_3d.gd` |
| **[PB-04 (Issue #4)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/4)** | **Shared Team Intel** | Crosshair raycast ping (`F`) that highlights spotted OpFor bots with an emissive outline for 3.0s and updates the HUD Intel Feed. | **`v0.3`:** Bunker callout zones ("Dorito 1", "Snake 50"), line-of-sight silhouettes, and "Pinned" suppression HUD. | `scripts/autoload/intel_bus.gd` |
| **[PB-05 (Issue #5)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/5)** | **Opponents & Modes** | 3v3 Speedball elimination loop against 3 peeking/shooting OpFor bots (`OpFor_BackCenter`, `OpFor_Dorito`, `OpFor_Snake`). | **`v0.3`:** Center Flag / CTF objectives, `NavigationAgent3D` tactical bot AI, and multiplayer lobbies. | `scripts/systems/snap_target_bot.gd`, `scripts/autoload/game_manager.gd` |
| **[PB-06 (Issue #6)](https://github.com/Tylerdoubleu/game_dev_rev0/issues/6)** | **Map Gear Brackets** | Live playtest toggle (`1`/`2`/`3`) switching `GearRuleEnforcer` between **Speedball** (10.5 BPS), **Woodsball** (strict 1-pull semi), and **Pump** (manual RMB rack). | **`v0.4`:** Map-enforced `.tres` brackets, Woodsball/Pump maps, and pre-round horizontal loadout selector. | `scripts/autoload/gear_rule_enforcer.gd` |

---

## 2. Version Control Workflow Between Playtests

1. **Playtest Tags (`v0.1.0-playtest`, `v0.2.0-playtest`, ...):**
   - Every playable milestone is tagged in Git so we can compare feel or roll back cleanly between playtest sessions.
2. **Feature Branches per Backlog Ticket:**
   - Work on one ticket at a time on a branch named after its issue (e.g., `feat/pb-01-analog-lean` or `feat/pb-02-ballistics-wind`).
3. **Headless Smoke Verification Before Merge:**
   - Run `godot --headless --path . -s res://scripts/systems/smoke_test_runner.gd` to verify all singletons, scenes, and ballistics compile and pass before merging to `main`.
