# First-Person Paintball (`game_dev_rev0`)

Lightweight 3D First-Person Paintball prototype in **Godot 4.7.2-stable (`Forward+`)**, inspired by *Greg Hastings' Tournament Paintball*.

## Quick Start (Playtest `v0.1.0-playtest`)
1. Open **Godot Engine 4.7.2** and import `project.godot`, or run from terminal:
   ```bash
   godot --path .
   ```
2. Press **F5 (Play)** to drop directly into **`speedball_arena_01`** (3v3 symmetrical Speedball greybox arena with Dorito, Snake, Can, and Center-50 inflatable bunkers).

## Playtest Controls
| Action | Key / Mouse | Prototype Notes |
|---|---|---|
| **Move / Strafe** | `W` `A` `S` `D` | Standard first-person movement |
| **Breakout Sprint** | `Shift` (hold) | Cancels and **spills** an active pod reload if you sprint mid-pour |
| **Knee-Slide / Crouch** | `Ctrl` or `C` | Tap while sprinting for a fast knee-slide into Snake/Dorito cover; toggles crouch otherwise |
| **Snap-Lean Left / Right** | `Q` / `E` | Smoothly leans around bunkers and **auto-swaps marker hand** (`LEFT` / `RIGHT` shoulder) to minimize hopper exposure |
| **Manual Shoulder Swap** | `X` or `Middle Mouse` | Manually switches marker between left and right hand |
| **Fire / Trigger Walk / Pump** | `LMB` / `RMB` | **Speedball (`1`)**: 10.5 BPS ramp + LMB/RMB walk. **Woodsball (`2`)**: strict 1-pull semi (RMB disabled). **Pump (`3`)**: LMB fires, RMB racks pump handle |
| **Pod Reload** | `R` | Opens a pod and pours into the hopper (2.0s). Overfilling early or sprinting/sliding mid-pour spills remaining paintballs! |
| **Ping / Spot Intel** | `F` | Marks enemy or bunker under crosshair for 3.0s on `IntelBus` |
| **Switch Gear Bracket** | `1` / `2` / `3` | Live playtest toggle between **Speedball**, **Woodsball**, and **Stock & Pump** rulesets |
| **Next / Reset Round** | `T` | Clears paint splats and resets OpFor snap-shooting bots |

## Architecture (`res://`)
- `scripts/autoload/game_manager.gd` (`GameManager`) — Round state, timer, OpFor elimination counter, and runtime InputMap binding.
- `scripts/autoload/gear_rule_enforcer.gd` (`GearRuleEnforcer`) — Enforces map-locked horizontal gear brackets (`speedball`, `woodsball`, `pump`).
- `scripts/autoload/intel_bus.gd` (`IntelBus`) — Signals for team-wide spotting and bunker suppression.
- `scripts/autoload/paint_ballistics.gd` (`PaintBallistics`) — Pooled 3D paintball simulation with gravity, drag, bounce-vs-break angle checks, and surface-aligned splat meshes.
- `docs/BACKLOG_AND_VERSIONING.md` — Tracked shortcuts/simplifications in `v0.1.0-playtest` and our playtest version-control workflow.
