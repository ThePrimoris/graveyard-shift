# Audio

All audio here is **procedurally synthesised** (see the generator script this
was built with) — no samples, no AI audio, so it's fully original and
licence-free. Regenerating is deterministic (seeded).

- `sfx/*.wav` — 44.1 kHz mono one-shots. Ids live in `scripts/Ids.gd`
  (`SFX_*`); `AudioManager.play_sfx(id)` plays them.
- `music/*.wav` — 22.05 kHz stereo ambient loops, ~16 s, fold-crossfaded so they
  loop seamlessly. `AudioManager` loops them per view.

## Triggers (wired in `AudioManager` + one-liners at the source)

| Sound | When |
|---|---|
| `harvest_tick` | each harvest resolves (`GameManager.harvest_completed`) |
| `item_pickup` | a breakable node cracks open (`GameManager.node_broken`) |
| `build` | a structure tier is raised (`GroundsManager.build`) |
| `level_up` | a gathering skill levels up (`GameManager.add_xp`) |
| `combat_hit` | any hit lands in combat (`CombatView`) |
| `ui_click` | a sidebar navigation button (`NavigationPanel`) |

## Music by view

`amb_graveyard` (graveyard / inventory / shop), `amb_forest` (forest),
`amb_quarry` (quarry), `amb_combat` (combat). Overlays (Grounds / Settings /
Necronomicon) keep whatever bed is playing.

## Volume

Master / SFX / Music sliders live in Settings; values persist in
`SettingsManager`'s own file (they survive a hard reset).

## Replacing an asset

Drop a same-named `.wav` in the right folder — the ids and wiring don't change.
To add a new SFX: add a `SFX_*` const in `Ids.gd`, drop `sfx/<id>.wav`, and call
`AudioManager.play_sfx(Ids.SFX_<NAME>)`.
