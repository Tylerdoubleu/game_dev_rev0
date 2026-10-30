# Source recordings

- `marker_shots_tyler_raw.wav`: real paintball marker shot recording supplied by Tyler on 2026-10-30 (24-bit stereo, 15.5 s, recorded in REAPER). It has five single shots, then rapid-fire bursts from about 11 to 14 s.
  - `assets/audio/paint/marker_fire_1.wav` through `marker_fire_5.wav` (Ren, v0.6): five shots from the rapid-fire run (11.10, 11.83, 12.10, 12.52, 13.67 s), because those are all at the same distance and level. Mono, 44.1 kHz, about 0.24 s each with a short fade-out, peak-normalized. `PaintImpactAudio` rotates through them without repeats and with only a light pitch wobble.
  - `marker_fire.wav` is single shot #2, kept as a fallback.
- `bunker_hit_cc0_raw.wav`: paintball-on-bunker hit supplied by Tyler on 2026-10-30. The file's metadata says "CC0 Public domain, Recorded on Zoom H2n XY."
  - It now replaces both `assets/audio/paint/splat_vinyl.wav` and `splat_wood.wav` (mono, 44.1 kHz, peak -1 dB).
- `slide_dive_voicebosch_first6s.wav`: the first 6 s of a 65 s slide and dive recording supplied by Tyler on 2026-10-30. Its metadata points to voicebosch.com/soundbiter, and the license still needs confirming before a commercial release.
  - The first four sounds are cut into `assets/audio/movement/slide_dive_1.wav` through `slide_dive_4.wav` (0.6 s each).
  - They're Tyler's effort vocals for slides and dives. `MovementFoley` rotates all four without repeats as the slide sound and the dive sound (Ren, v0.6). The synthesized scrape, effort and dive thud no longer play.
- `dry_grass_steps_cc0_raw.wav`: "Dry Grass Steps", supplied by Tyler on 2026-10-30. It mixes the CC0 Freesound sounds jordir/360561 and Mystikuum/377323 and contains two footsteps.
  - Those two steps, pitched by up to ±6%, make `step_turf_1.wav` through `step_turf_4.wav`.
  - Shorter cuts of the same two steps make `step_sprint_1.wav` and `step_sprint_2.wav`.
  - Ren, v0.6: every step is trimmed to start right on the footfall (no lead-in silence) and to end before the next step, 0.26 s for walking and 0.21 s for sprinting, with a short fade, so steps don't lag or pile up at sprint pace.
- `menu_music_greater_vantage_raw.mp3`: menu music supplied by Tyler on 2026-10-30. The tags read "14 metal", Greater Vantage Music, album "demo reel", and the track is 56 s long. The license still needs confirming before a commercial release.
  - Converted to `assets/audio/music/menu_loop.ogg`: OGG Vorbis, leading and trailing silence trimmed, -3 dB. It's meant to loop on the menus.
  - Ren, v0.6: `MovementAudioDirector` loops it at -12 dB while the lobby browser or waiting room is open and fades it out over about a second when a match starts.
