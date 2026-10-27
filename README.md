# First-Person Paintball (`game_dev_rev0`)

Lightweight 3D First-Person Paintball prototype in **Godot 4.7.2-stable (`Forward+`)**, inspired by *Greg Hastings' Tournament Paintball*.

## Quick Start (Playtest `v0.1.1-playtest`)
1. Open **Godot Engine 4.7.2** and import `project.godot`, or run from terminal:
   ```bash
   godot --path .
   ```
2. Press **F5 (Play)** to drop directly into **`speedball_arena_01`** (Full-scale 108m × 132m Speedball arena with dense symmetrical bunkers, Dorito highway, Center-50 cluster, and a multi-knuckle Snake along the far-left 50s).

## Playtest Controls (`v0.1.1-playtest`)
| Action | Key / Mouse | Prototype Notes |
|---|---|---|
| **Move / Strafe** | `W` `A` `S` `D` | First-person movement with stance-scaled view & marker head-bobbing |
| **Breakout Sprint** | `Shift` (hold) | Cancels and **spills** an active pod reload if you sprint mid-pour |
| **Crouch / Knee-Slide** | `C` / `Shift + C` | Press `C` to toggle crouch; press **`Shift + C`** while sprinting for a high-velocity knee-slide with FOV kick |
| **Prone / Superman Dive** | `Ctrl` / `Shift + Ctrl` | Press `Ctrl` to toggle prone (crawl in the Snake); press **`Shift + Ctrl`** while sprinting for a Superman dive into prone |
| **Snap-Lean Left / Right** | `Q` / `E` | Smoothly leans around bunkers and **auto-swaps marker hand** (`LEFT` / `RIGHT` shoulder) |
| **Manual Shoulder Swap** | `X` or `Middle Mouse` | Manually switches marker between left and right hand |
| **Speedball (`1`) Trigger Walk** | `LMB` & `RMB` | `LMB` and `RMB` act as **two independent triggers**—alternate clicks to walk the trigger up to the **10.5 BPS** cap (40-round hopper + 3×30 pods) |
| **Woodsball (`2`) 1-Pull Semi** | `LMB + RMB` together | Requires **holding/pressing both `LMB` and `RMB` together** to pull the heavy mechanical trigger once (25-round hopper + 3×20 pods) |
| **Pump (`3`) Manual Cycle** | `LMB` then `RMB` | `LMB` fires, `RMB` racks the pump handle before the next shot (10-round stick feed + 4×10 tubes) |
| **Animated Pod Reload** | `R` | Opens the hopper lid, brings a 3D pod into view, and pours paint stream into the hopper (2.1s). Sprinting, sliding, or diving mid-pour spills the pod! |
| **Ping / Spot Intel** | `F` | Marks enemy or bunker under crosshair for 3.5s on `IntelBus` |
| **Next / Reset Round** | `T` | Clears paint splats and resets all 5 OpFor snap-shooting bots |
