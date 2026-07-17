# Alchemy Redesign

Status: **implemented** (2026-07-16). Replaces the old six-recipe Alchemy set.
Implementation notes at the bottom record where the build diverged from the
original sketch.

## Why

The old design had three faults:

1. **Inverted progression.** The level-1 recipe (Embalmer's Salve) required Velvet Moss
   (Lumbering 35); the level-5 recipe required Nightshade Vine (Lumbering 55). Alchemy
   could not earn its first XP until deep into Lumbering.
2. **Shop undercut the skill.** The Emporium sold 4 of 6 potions for flat gold, so
   brewing them was pointless.
3. **Grab-bag effects.** Six one-off effects, no families, no tiers, nothing that
   scaled with Alchemy 1–100.

## Design rules

- **Level-matched ingredients**: an Alchemy-N recipe only uses nodes at or below
  ~level N in their source skill. Level-1 recipes use fresh-grave organics only.
- **Potions are never sold in the shop.** The shop sells *recipe scrolls* instead
  (one-time gold sinks); Requiem Incense scroll is priced as a late-game sink.
- **Recipe acquisition is mixed**: early recipes unlock by leveling, mid recipes are
  shop scrolls, special recipes drop from thematically matching encounters.
- **All minion enhancement is timed** (turns, battles, or minutes). No permanent
  stat creep. The one "forever" reward is the Homunculus capstone — a minion,
  not a stat.

## Product lines

| Line | Fantasy |
|---|---|
| Salves | Patching up the dead (in-battle minion healing) |
| Draughts | Battle chemistry, buffs |
| Phials | Poisons and debuffs |
| Incense & Candles | Grounds-wide timed effects, burned at a structure |
| Rites | Minion care — exhaustion, revival |
| The Great Work | Multi-stage capstone → the Homunculus, a vat-grown 5th minion |

Cut: Gravedigger's Brew and Prospector's Elixir (gathering-buff drinks). Their
effect hooks (`consume_gather_xp_buff`, `consume_gather_rare_buff`) may be reused
by Incense later or removed.

## The ladder

| Alch lvl | Recipe | Line | Effect | Inputs (source skill/level) | Learned via |
|---|---|---|---|---|---|
| 1 | Embalmer's Salve | Salve I | Heal minion 25% max HP | flesh ×2, blood ×2 (GR 1) | Known from start |
| 5 | Corpse-Candle | Incense I | 15 min: exhausted minions recover 2× faster | flesh ×2, grave_dust ×1, amber_droplet ×1 (Lum 1–4) | Level-up |
| 10 | Venom Phial | Phial I | Poison: 4 dmg × 3 turns | poison_thorns ×2 (Lum 10), blood ×2 | Level-up |
| 14 | Grave Tonic | Rite | Instantly rouse one exhausted minion | grave_dust ×3, bone_marrow ×1 (GR 6), blood ×2 | Level-up |
| 18 | War Draught | Draught I | +30% ATK, 3 turns | bone_marrow ×1, briar_blossom ×2 (Lum 13), blood ×3 | Shop scroll (~150g) |
| 22 | Vigil Incense | Incense II | 20 min: +15% double-harvest chance | pale_lichen ×2, silken_husk ×1 (Lum 20), grave_dust ×2 | Shop scroll (300g) |
| 27 | Surgeon's Paste | Salve II | Heal minion 60% max HP | flesh ×3, pale_lichen ×2, blood ×2 | Shop scroll (~500g) |
| 32 | Widow's Phial | Phial II | Heavy poison + reduces target ATK | poison_thorns ×2, pale_silkgland ×1 (silkmoth drop), blood ×2 | Drop: Skittering Dark / Silk-Choked |
| 36 | Sexton's Ashes | Rite | This battle: minion revives once at 30% HP | bones ×3, withered_heart ×1 (GR 6), ash_burl ×1 (Lum 20) | Drop: Restless Dead |
| 40 | Warden's Draught | Draught II | +ATK and damage resist, 4 turns | bone_marrow ×2, tungsten_lump ×1 (Spel 20), withered_heart ×1 | Drop: Old Crypt |
| 45 | Requiem Incense | Incense III | 30 min: offline/idle gains boosted | velvet_moss ×2, angel_oak ×1 (Lum 35), grave_dust ×3 | Shop scroll (expensive, ~2000g) |
| 50 | Lich's Balm | Salve III | Full heal + cleanse poison | velvet_moss ×3, bone_marrow ×2, beryl_cluster ×1 (Spel 23) | Drop: high-tier encounter |
| 55 | The Vat (Prima Materia) | Capstone 1 | Crafts *Prima Materia* (inert item) | Bulk sink: flesh ×20, blood ×20, grave_dust ×20, quartz_geode ×5, nickel_granule ×5 | Hinted by Apothecary at 55 |
| 70 | Seed of Flesh | Capstone 2 | Crafts *Seed of Flesh* | prima_materia ×1, withered_heart ×3, dryads_heartstone ×1, living_jade_core ×1, pale_silkgland ×3 | Boss drops assemble it |
| 85 | The Quickening | Capstone 3 | Births the **Homunculus** (5th minion) | seed_of_flesh ×1, obsidian_wyrm_scale ×1, nightshade_vine ×3 (Lum 55), cobalt_powder ×3 (Spel 55) | Final brew |

Cadence: a recipe every ~4–5 levels to 50, then three capstone stages spanning 55–85.
15 recipes total.

## Implementation notes (as built)

- **Recipe learning**: `Recipe.scroll_taught` flag + `CraftingManager.known_recipe_ids`
  (persisted in the save under `known_recipes`, keyed per station). Scrolls are
  Consumables with `use_effect = "consume_learn_recipe"` and a `taught_recipe_id`;
  they're studied from the backpack's details panel. The shop refuses dupes and
  retires a scroll once its recipe is learned; drop scrolls can dupe (they sell).
- **Shop**: `SUPPLY_PRICES` (finished potions) replaced by `SCROLL_PRICES` —
  War Draught 150g, Vigil Incense 300g, Surgeon's Paste 500g, Requiem Incense 2000g.
- **Incense** burns from the backpack onto `GameManager.apply_timed_buff` channels:
  Corpse-Candle → `exhaust_haste_pct` (also rebates current rests via
  `MinionManager.hasten_exhaustion`), Vigil → `double_drop_pct` (nodes don't
  respawn in this game, so the effect was remapped to double-harvest chance),
  Requiem → `offline_gain_pct` (SaveManager credits the covered offline window).
- **New combat effects**: `consume_atk_def_pct` (Warden's Draught: surge +
  damage-resist turns), `consume_poison_weaken` (Widow's Phial: poison + the foe's
  blows land `secondary_magnitude`% softer), `consume_revive_once` (Sexton's
  Ashes: the anointed rise once at magnitude% HP).
- **Drop scrolls** ride enemy loot pools: Bloated Silkmoth → Widow's Phial,
  Restless Spirit → Sexton's Ashes, Crypt Warden → Warden's Draught,
  Petrified Dryad → Lich's Balm (8% on bosses, 4% on the spirit).
- **The Great Work** is three plain level-gated recipes (55/70/85) whose final
  output, the unsellable `homunculus_heart`, is simply the Homunculus's
  `raise_cost` — the existing Ritual Altar flow births it, no new mechanics.
  The Homunculus is a fifth minion for four plots: slotting becomes a choice.
- **Cut**: gravediggers_brew and prospectors_elixir (items, recipes, icons);
  their `consume_gather_*` effect hooks remain in code but no item uses them.
- Lich's Balm's "cleanse" was dropped — minions have no poison status to cleanse;
  it's a full heal (`consume_heal_pct` at 100).
