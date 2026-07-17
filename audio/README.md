# Audio

All audio here is **procedurally synthesised** by `tools/generate_audio.py`
(committed, deterministic, seeded) — no samples, no AI audio, fully original
and licence-free. Regenerate with `python3 tools/generate_audio.py` from the
project root (needs numpy).

- `sfx/*.wav` — 44.1 kHz mono one-shots. Ids live in `scripts/Ids.gd`
  (`SFX_*`); `AudioManager.play_sfx(id)` plays them.
- `music/*.wav` — 22.05 kHz stereo ambient loops, ~16 s, fold-crossfaded so
  they loop seamlessly. `AudioManager` crossfades them per view.

## SFX identities (v2 — every sound has its own voice)

| Sound | Character | When |
|---|---|---|
| `ui_click` | soft parchment tick | sidebar navigation (`NavigationPanel`, `CraftingView`) |
| `harvest_tick` | shovel biting earth | each harvest resolves (`GameManager.harvest_completed`) |
| `item_pickup` | two-note glass chime | a breakable node cracks open (`GameManager.node_broken`) |
| `build` | stone thud + mallet knock | a structure tier rises (`GroundsManager.build`) |
| `level_up` | rising candle-lit arpeggio | any skill levels up (`GameManager.add_xp`) |
| `combat_hit` | punchy body blow | any hit lands in combat (`CombatView`) |
| `brew` | the still bubbling over | an Alchemy brew completes (`AlchemyManager`) |
| `smith` | hammer on anvil, metal ring | a Forge smith completes (`ForgeManager`) |
| `potion` | two gulps and a splash | any consumable is used (`CombatView`, `InventoryView`) |
| `victory_sting` | three notes lifting from the dark | combat won (`CombatView`) |
| `defeat_sting` | a low falling groan | combat lost (`CombatView`) |

## Music by view (each loop is a distinct scene)

| Track | Scene | Views |
|---|---|---|
| `amb_graveyard` | low wind, distant D-minor bell, buried choir | graveyard / inventory / shop |
| `amb_forest` | leafy breeze, sparse bird calls, a wooden creak | forest |
| `amb_quarry` | cavern rumble, echoing drips, a far-off pick | quarry / forge |
| `amb_combat` | 72 bpm heartbeat under a dark detuned drone | combat |
| `amb_alchemy` | soft bubbling, glassy E-minor partials | alchemy |

Overlays (Grounds / Settings / Necronomicon) keep whatever bed is playing.

## Volume

Master / SFX / Music sliders live in Settings; values persist in
`SettingsManager`'s own file (they survive a hard reset).

## Replacing an asset

Drop a same-named `.wav` in the right folder — the ids and wiring don't
change. To add a new SFX: add a `SFX_*` const in `Ids.gd`, add a synth
function + table entry in `tools/generate_audio.py` (or drop a wav in
`sfx/<id>.wav`), and call `AudioManager.play_sfx(Ids.SFX_<NAME>)`.
