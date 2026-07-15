# Graveyard Shift — Developer Reference

A working map of the whole codebase: what every manager, resource, and view
does, how the pieces talk to each other, and how to extend it. Written to be
read top-to-bottom once, then used as a lookup.

> Companion doc: `docs/grounds_iso_view_plan.md` covers the isometric Grounds
> view in depth (M1–M5).

---

## 1. What the game is

Graveyard Shift is an idle / incremental RPG built in **Godot 4.7** (Forward+,
Jolt physics). You are the new caretaker of a graveyard, reclaiming it through
three gathering skills, raising undead minions, fighting bosses, and rebuilding
the grounds. The core loop:

**gather → sell / offer / craft → raise & grow minions → fight → rebuild the grounds → gather faster**

- Main scene: `Main.tscn` (a `Control` root running `Control.gd`).
- Theme: `theme/graveyard_theme.tres` — the dark "Lanternlight" style.
- Window: 1920×1080 design size, `canvas_items` stretch, min window 1160×660.
- Clear color: `#0b0a10`.

---

## 2. Architecture & conventions

### Autoload managers (singletons)

Registered in `project.godot`, in this load order:

| Autoload | Script | Responsibility |
|---|---|---|
| `SettingsManager` | `scripts/managers/SettingsManager.gd` | Window mode/size prefs (survive hard reset). |
| `GameManager` | `scripts/managers/GameManager.gd` | Skills/XP, item+node+encounter registries, equipment, gather bonuses, harvest resolution, offline sim. |
| `InventoryManager` | `scripts/managers/InventoryManager.gd` | The backpack grid: slots, stacking, capacity. |
| `NotificationManager` | `scripts/managers/NotificationManager.gd` | Spawns toast popups. |
| `MinionManager` | `scripts/managers/MinionManager.gd` | Minion roster, levels/XP, skill trees, plots, offerings. |
| `GroundsManager` | `scripts/managers/GroundsManager.gd` | Buildable structures (the Grounds) + their bonuses. |
| `AudioManager` | `scripts/managers/AudioManager.gd` | SFX pool + per-view ambient music; volumes via SettingsManager. |
| `SaveManager` | `scripts/managers/SaveManager.gd` | Save/load JSON, autosave, offline progress, hard reset. |
| `TutorialManager` | `scripts/managers/TutorialManager.gd` | Mortimer's first-run tutorial (a `CanvasLayer`). |
| `DebugConsole` | `scripts/managers/DebugConsole.gd` | `~`-toggled console (a `CanvasLayer`). |

Load order matters only for autoloads that reference each other at `_ready`.
`GameManager`, `InventoryManager`, `MinionManager`, `GroundsManager` build their
`*_db` registries at `_ready`. `SaveManager._late_init` runs after a frame, then
loads the save and kicks off the tutorial.

### The "groups + tick" UI pattern

There is **no central UI controller**. UI nodes join Godot groups and the game
broadcasts to them:

- `%GameTickTimer` (in `Main.tscn`, driven by `Control._on_game_tick`) fires
  `get_tree().call_group("ui_updates", "update_ui")` every tick. Any node in the
  `ui_updates` group implements `update_ui()` and refreshes itself.
- State changes also call `call_group("ui_updates", "update_ui")` on demand
  (after a build, a harvest, equipment change, etc.).
- View switching: `call_group("view_manager", "switch_view", name)`. `Control`
  and `TutorialManager` are in `view_manager`.
- `harvest_views` (the three skill screens) receive `resume_node` on load.
- `combat_views` and `necronomicon` groups let systems find those views.

**Groups in use:** `ui_updates`, `view_manager`, `harvest_views`,
`combat_views`, `necronomicon`.

### Signals

| Signal | Emitter | Meaning |
|---|---|---|
| `harvest_completed(node_id)` | GameManager | one harvest resolved (tutorial listens). |
| `node_broken(node_id)` | GameManager | a breakable node hit 0 health. |
| `inventory_updated` | InventoryManager | slots changed (InventoryView rebuilds grid). |
| `minions_updated` | MinionManager | roster/plots/XP changed. |
| `grounds_updated` | GroundsManager | a structure leveled (view + buildings refresh). |
| `action_triggered` | ActionCard | a harvest card's button pressed. |
| `selected(structure_id)` | StructureBuilding | a Grounds building clicked. |
| `slot_clicked(item)` | InventorySlot | an inventory slot clicked. |

### Conventions

- **Data-driven content.** Items, tools, nodes, zones, minions, enemies,
  encounters, and structures are `Resource` subclasses (`.tres`) auto-loaded
  from directories into `*_db` dictionaries keyed by `id`. Add content by
  dropping a `.tres` in the right folder — no code.
- **Code-built overlays.** Settings, the Necronomicon, the Grounds view, and the
  minion picker are built entirely in GDScript on `CanvasLayer`s (created via
  `.new()` + `add_child`), not `.tscn` files.
- **`id` is the key everywhere.** Registries, saves, tutorial steps, affixes,
  and effects all reference string `id`s.

---

## 3. Project layout

```
Main.tscn                     Root scene (Control.gd)
Control.gd                    Root: view switching, game tick, overlays
PopUp.gd                      Item-notification toast
project.godot / theme/        Config + Lanternlight theme

data/                         Resource CLASSES (*.gd) + CONTENT (*.tres)
  ItemData.gd (Item)          ToolData.gd (ToolData : Item)
  HarvestNodeData.gd          ZoneData.gd (HarvestZone)  LootDropData.gd
  MinionData.gd  MinionAbilityData.gd
  EnemyData.gd  EncounterData.gd
  StructureData.gd  StructureTierData.gd
  items/materials/ (40)  items/tools/ (12)
  nodes/graves/ (5)  nodes/trees/ (15)  nodes/mines/ (15)
  zones/ (12)  minions/ (4)  enemies/ (3)  encounters/ (2)  structures/ (4)

scripts/
  managers/                   The 10 autoloads (incl. AudioManager)
  ui/                         NavigationPanel, PlotsBar, InventorySlot,
                              InventoryView, SettingsPanel, NecronomiconPanel,
                              GroundsView helpers (IsoUtil, GroundsWorld,
                              StructureBuilding)
  cards/ActionCard.gd         The harvest card

scenes/
  views/                      HarvestView (base) + Graveyard/Forest/Quarry,
                              ShopView, CombatView, GroundsView
  cards/  inventory/  *.tscn  Reusable scenes

tests/SmokeTest.gd            Headless integration test
audio/                        sfx/ one-shots + music/ ambient loops (synthesised)
docs/                         This file + the iso Grounds plan
icons/                        items/, skills/, ui/ art
```

---

## 4. Data model (Resource classes)

All live in `data/` and use `class_name`, so they're global types.

### `Item` (`ItemData.gd`)
`id, name, type (MATERIAL/TOOL/QUEST/MISC), icon, description, sell_value,
is_sellable, rarity (COMMON..LEGENDARY), max_stack (250), is_stackable,
required_level, item_effect`.

### `ToolData : Item` (`ToolData.gd`)
Adds `speed_multiplier, yield_bonus, tool_type (SHOVEL/HATCHET/PICKAXE),
tool_tier (RUSTED/GALVANIZED/REINFORCED/TEMPERED)`. See §6 for how these feed
the bonus model.

### `HarvestNode` (`HarvestNodeData.gd`)
The thing you harvest. `id, name, description; required_skill (SkillType),
required_level, required_tool_type; base_duration, base_xp, dig_sections;
affix; is_boss, encounter_id`. Loot is split across three models:
- **Common/rare** (graves, trees): `common_pool` (one weighted row per harvest)
  + `rare_chance` roll into `rare_pool`.
- **Breakable** (mines): `hit_damage > 0` → `hit_pool` (per-hit % chances) plus
  a guaranteed `break_pool` roll when health reaches 0.
- **Dig-layer** (trees): `dig_sections > 0` draws a stacked meter (cosmetic bar
  behavior), still uses common/rare loot.
- `MAX_LOOT_ENTRIES = 5` — only the first 5 rows of any table are honored.

### `HarvestZone` (`ZoneData.gd`)
`id, name, description, required_level, nodes: Array[HarvestNode]`. A view holds
an ordered list of zones; the left selector picks one.

### `LootDrop` (`LootDropData.gd`)
One table row: `item, weight, min_amount, max_amount`. In common/break tables
weight is a relative share; in hit tables weight is a literal percentage.

### `Minion` (`MinionData.gd`)
`id, name, description, icon, sort_order; base_hp, base_atk; hp_per_level,
atk_per_level; speed (combat charge rate); raise_cost: Dictionary[String,int];
abilities: Array[MinionAbility]`. `find_ability(id)` helper.

### `MinionAbility` (`MinionAbilityData.gd`)
A skill-tree node: `id, name, description, icon; kind (PASSIVE/ACTIVE); tier;
cost; prerequisites: Array[String]; effect; magnitude`. Passive `effect` strings
recognised by code: `harvest_xp_pct`, `rare_chance_pct`, `double_drop_pct`,
`grounds_yield_pct`. Actives use free-form ids (`active_*`) — see §11 (parked).

### `Enemy` (`EnemyData.gd`)
`id, name, glyph, description; base_hp, atk, speed; is_boss, telegraph_name,
enrage_per_segment; xp_reward, gold_min, gold_max, loot_pool`.

### `Encounter` (`EncounterData.gd`)
`id, name, enemies: Array[Enemy]`. `is_boss_encounter()` = single `is_boss` foe.

### `Structure` (`StructureData.gd`)
A buildable Grounds structure: `id, name, description, icon, sort_order;
effect, effect_unit, effect_label; grid_cell: Vector2i, footprint: Vector2i;
tiers: Array[StructureTier]`. `max_level()` = `tiers.size()`.

### `StructureTier` (`StructureTierData.gd`)
One upgrade step: `cost: Dictionary[String,int], magnitude, blurb`.

---

## 5. Content inventory

| Folder | Count | Notes |
|---|---|---|
| `data/items/materials/` | 40 | graverobbing mats + 30 lumber/mine mats. |
| `data/items/tools/` | 12 | 3 types × 4 tiers (rusty→tempered). |
| `data/nodes/graves/` | 5 | fresh/old/sunken/forgotten graves + old_crypt (boss). |
| `data/nodes/trees/` | 15 | 5 zones × (primary/secondary/treasure). |
| `data/nodes/mines/` | 15 | 5 zones × (primary/secondary/treasure). |
| `data/zones/` | 12 | 2 grave zones, 5 tree zones, 5 mine zones. |
| `data/minions/` | 4 | zombie, skeleton, ghoul, undead_hound. |
| `data/enemies/` | 3 | grave_rat, restless_spirit, crypt_warden (boss). |
| `data/encounters/` | 2 | restless_dead, old_crypt. |
| `data/structures/` | 4 | ossuary, chapel, wardens_grove, grave_lantern. |

Registries are built at `_ready`: GameManager (`item_db`, `node_db`,
`nodes_by_skill`, `encounter_db`), MinionManager (`minion_db`), GroundsManager
(`structure_db`). A node's skill key comes from `GameManager.get_skill_key`
(the `SkillType` enum name lowercased: `graverobbing`/`lumbering`/`spelunking`).

---

## 6. Systems

### 6.1 Harvesting loop

`HarvestView` (`scenes/views/HarvestView.gd`, `class_name HarvestView`) is the
base for the three skill screens. `GraveyardView`/`ForestView`/`QuarryView` are
6-line subclasses that only set `action_verb`, `progress_color`, and `ambience`.
Each view owns `zones: Array[HarvestZone]` (assigned in `Main.tscn`), builds a
zone selector and a grid of `ActionCard`s (four per row).

Flow:
1. Player clicks a card → `ActionCard.action_triggered` →
   `GameManager.register_activity(card, node)`. Only one node is active at a time
   (`active_action_source`). Clicking the active card again stops it.
2. `HarvestView._process(delta)` accumulates `node_progress[id]` for the active
   card. When it reaches `get_effective_duration(node)`, it resolves the harvest
   and resets.
3. `GameManager.resolve_harvest(node)` rolls loot (§6.2), banks it, and awards
   `base_xp × xp_mult`. Breakable nodes accumulate damage on the card's meter;
   at full, `resolve_break` pays the break table.
4. `harvest_completed` / `node_broken` signals fire (tutorial + affix lockout).

`ActionCard` (`scripts/cards/ActionCard.gd`) is a rich card: bonus chips, a
Common/Rare (or Hit/Break) drop ledger, node art, the action button, a progress
bar, and optional vertical meters (dig-layer segments, break-damage). It uses
change-detection keys (`_drops_key`, `_bonus_key`) so `update_ui` (every tick)
only rebuilds children when data actually changes — avoiding the "tooltip
vanishes mid-hover" bug.

### 6.2 Loot resolution

All in `GameManager`:
- `roll_drop_table(pool)` — one weighted pick (share = weight / total).
- `roll_chance_table(pool)` — one roll where weights are literal percentages;
  may return null (nothing).
- `_roll_loot(common, rare_chance, rare, double_chance)` — one common row (+
  possible double) plus an optional rare roll.
- `resolve_harvest` / `resolve_break` — apply gather modifiers, bank via
  `_bank_gains`, emit signals.

### 6.3 Gather bonuses — the "Access & Yield" model

`GameManager.get_gather_modifiers(node) -> {speed_mult, double_chance, rare_add,
xp_mult}` is the **single source of truth** for every bonus. Design rule: each
source pushes a different lever, and speed stacks **additively** (never
multiplicatively) so it can't explode.

- **Tools:** small additive speed = `speed_multiplier - 1.0`; yield =
  `yield_bonus%` chance to double the haul.
- **Levels:** speed only, a diminishing curve approaching `LEVEL_SPEED_MAX`
  (0.25) with `LEVEL_SPEED_HALFLIFE` (25). No yield/xp.
- **Minion passives:** `harvest_xp_pct`, `rare_chance_pct`, `double_drop_pct`
  (via `MinionManager.get_passive_bonus`, only slotted minions count).
- **Grounds structures:** same three spice channels via `GroundsManager.get_bonus`.
- **Affixes:** node penalties applied last (see §6.4).

Speed is clamped to `[SPEED_FLOOR 0.3, SPEED_CAP 1.6]`. `SPEED_BONUSES_ENABLED`
is a master switch. `get_effective_duration(node)` = `base_duration / speed_mult`.

### 6.4 Node affixes

`GameManager.AFFIXES` is a registry: id → `{name, active, power, blurb}`.
`get_affix_info(id)` reads it. A node's `affix` string (from its `.tres`) is
applied inside `get_gather_modifiers`:
- **Active, loop-safe:** `sticky_sap` (−speed), `blind_canopies` (double_chance
  → 0), `unstable_seams` (stateful lockout, handled in `HarvestView`: a break
  seals the node for `UNSTABLE_LOCKOUT_SECONDS` = 120s).
- **Flavor (inert):** `thorn_veil`, `toxic_roots`, `sonic_resonance`,
  `subterranean_chill`, `volcanic_gas`. They render as warning chips but do
  nothing — they target a future "deploy minions to nodes" system. See §11.

### 6.5 Skills & XP

`GameManager.skills` = `{graverobbing/lumbering/spelunking: {level, xp}}`,
`MAX_LEVEL = 100`. `get_xp_needed(level)` is a RuneScape/Melvor-shaped curve
scaled by a slow-burn ramp (`SKILL_XP_SCALE_EARLY 1.0` → `LATE 2.5` by
`RAMP_END_LEVEL 30`). `add_xp(skill, amount)` handles level-ups and the cap.
Nodes gate on `required_level`; zones gate on their own `required_level`.

### 6.6 Inventory & equipment

`InventoryManager` holds `slots: Array` (`{item, quantity}` or null). `BASE_SLOTS
= 24`, up to `MAX_PURCHASED_SLOTS = 24` more bought with gold (`get_next_slot_cost`
grows 35%/purchase), plus Ossuary structure slots. `refresh_capacity()` sizes the
array to `BASE + purchased + GroundsManager.get_inventory_slot_bonus()`.
`add_item` stacks then fills empties (returns overflow). Emits `inventory_updated`.

Equipment lives on `GameManager.equipped_tools` (one per `ToolType`), separate
from the grid. Tools: `equip_tool`, `unequip_tool`, `upgrade_tool`,
`get_current_tool_of_type`, `get_next_tool_upgrade`. `InventoryView` is the
bank UI: header chips, the slot grid (`InventorySlot` scenes, drag-swappable),
3 equipment slots, and a "selected item" panel with a sell slider.

### 6.7 Shop

`ShopView` (`scenes/views/ShopView.gd`) — the Undertaker's Emporium. Two things:
linear **tool upgrades** (`TIER_COSTS` per `ToolTier`: gold + materials; the old
tool is consumed) and **backpack slots** (`InventoryManager.purchase_slot`).
Tool upgrade materials are `rotten_logs` (Gravewood Log) + `stone_debris` (Dense
Limestone) — the tier-1 primaries.

### 6.8 Minions & the Necronomicon

`MinionManager`:
- `roster`: `id → {level, xp, abilities: Array[String]}`. `PLOT_COUNT = 4`,
  `MAX_LEVEL = 50`.
- `plots`: 4-slot array of minion ids (`""` = empty). **Slotted = active for
  passives AND the combat warband.** The 4-cap is deliberate — it bounds passive
  power and equals party size.
- Raising: `raise_minion` pays `raise_cost`. Growth: `offer_materials` at the
  altar converts item sell-value to XP (`OFFERING_XP_PER_GOLD = 1.5`), or combat.
- Skill tree: 1 point per level; `unlock_ability` checks cost + prerequisites.
  `get_passive_bonus(effect)` sums an effect across slotted minions' unlocked
  passives.
- `necronomicon_unlocked` gates the book UI (granted by the tutorial).

`NecronomiconPanel` (`scripts/ui/NecronomiconPanel.gd`, `class_name`) is the
book overlay opened from the central circle in `PlotsBar`. Three chapters:
**index** (raised vs unwritten minions), per-**minion** spreads (statline +
skill-tree runes), and the **altar** (offer materials for XP). `PlotsBar`
(`scripts/ui/PlotsBar.gd`) is the bottom dock: the circle (opens the book) plus
4 plot buttons (open a minion picker to slot into a plot).

### 6.9 Combat

`CombatView` (`scenes/views/CombatView.gd`, ~1066 lines) is an ATB "wait-mode"
battle, Final-Fantasy style:
- `party` (4 slotted minions) vs `enemies`. Each combatant has a charge gauge;
  `TURN_SECONDS = 2.4` for a speed-1.0 gauge. When a minion's gauge fills, time
  stops for a command menu (unless AUTO is on). Enemies act when their hidden
  gauges fill. `BEAT_SECONDS = 0.75` pause after each action.
- Commands: Attack (`ATK ± DMG_VARIANCE 0.15`), Guard (`GUARD_REDUCTION 0.5`
  until next turn), inked active runes (`ACTIVE_RUNE_MULT 1.6`, once per fight),
  Flee. Bosses telegraph an all-party slam (`BOSS_SLAM_CHANCE 0.3`,
  `BOSS_SLAM_MULT 0.75`) and enrage as health quarters break.
- `party` member = `{minion_id, hp, max_hp, charge, speed, guarding}`; foe =
  `{name, glyph, hp, max_hp, atk, speed, charge, rage, is_boss, slam_name,
  telegraph, segments_broken, xp, gold_min, gold_max, loot_pool}`.
- Entry: harvest boss nodes call `combat_view.start_encounter_res(encounter)`
  then switch to the combat view. `_enter_victory` pays each foe's gold + loot
  roll and awards `xp_reward` to surviving minions; defeat is non-permanent.

### 6.10 The Grounds (isometric build view)

Data & logic: `GroundsManager` (`levels: id → int`, `build`, `can_afford`,
`next_tier`, `get_structure_value`, `get_bonus`, `debug_set_level`). Bonuses feed
`get_gather_modifiers` (xp/double/rare) and inventory slots. Structures are
placed on an iso plot; effects: `ossuary → inventory_slots`, `chapel →
harvest_xp_pct`, `wardens_grove → double_drop_pct`, `grave_lantern →
offline_hours`.

View: `GroundsView.gd` (a `CanvasLayer` overlay opened from the Grounds nav
button via `Control._on_grounds_pressed`) frames a `SubViewport` world:
- `IsoUtil.gd` — projection math (`TILE_W 96, TILE_H 48, GRID 5`,
  `cell_to_world`, `tile_diamond`, `footprint_polygon`, `plot_center`).
- `GroundsWorld.gd` — draws the dark plot, iso tiles, ritual circle, and
  atmosphere (fence, candles, surrounding headstones + dead trees) via `_draw`.
- `StructureBuilding.gd` — one Node2D per structure; positioned from
  `grid_cell`/`footprint`, click-picked via an `Area2D` footprint, Y-sorted, and
  drawn with **per-tier procedural art** (dispatched by id: chapel/ossuary/
  grove/lantern; plain-box fallback) that grows as it's raised. Emits `selected`.
- The docked right panel inspects the selected structure and calls
  `GroundsManager.build`. A brief flash plays when a structure's own tier changes.

### 6.11 Offline progress

Save stores `timestamp` + `active_node_id`. On load, `SaveManager._accrue_offline`
computes elapsed time (capped by `OFFLINE_BASE_HOURS 1.0` + Grave-Lantern
`offline_hours`), calls `GameManager.accrue_offline(node, seconds)` to simulate
harvests in one bulk pass (respecting yield/xp/double and break tables), banks
the haul (overflow past a full pack is lost), and shows a welcome-back summary.
Minion rune `grounds_yield_pct` and structure bonuses scale the effective time.

### 6.12 Tutorial

`TutorialManager` (a `CanvasLayer`, layer 70) runs a 13-step first-run tutorial
narrated by Mortimer. `STEPS` is a data array; steps wait on `continue`,
`harvest` (node + count), `view` (switch), or `event` (named beats via
`notify_event`: `book_opened`, `minion_raised`, `minion_slotted`,
`offering_made`). It draws a speech bubble + a pulsing highlight over the current
target (resolved by `_resolve_highlight_target`). Grants the Necronomicon on
finish/skip. Intro nodes referenced: `withered_trees`, `verdigris_seams`,
`fresh_grave`.

### 6.13 Save / load

`SaveManager`, `SAVE_PATH = user://graveyard_shift_save.json`, `SAVE_VERSION = 2`,
`AUTOSAVE_INTERVAL = 30s`, plus save-on-quit. Old (v1) saves are discarded.
Save keys: `version, timestamp, gold, skills, equipped_tools, owned_tools,
active_node_id, purchased_slots, tutorial_complete, inventory, minions, grounds`.
Each manager provides `get_save_data` / `restore_from_save`. `hard_reset` deletes
the file and resets every manager (Settings survive — they're a separate file).

### 6.14 Debug console

`DebugConsole` (`~` toggles it, layer 100). Commands: `level <skill> <amount>`,
`spawn <item_id> <amount>`, `grounds <list|raise|max|reset> [id]` (preview
structures free via `GroundsManager.debug_set_level`), `necronomicon <on|off>`,
`combat [boss]`, `help`.

### 6.15 Settings

`SettingsManager` persists a window mode/size choice **and the audio volumes**
(master/SFX/music) to its own file (`user://graveyard_shift_settings.json`) so
they survive hard resets. `SettingsPanel.gd` is the overlay (opened from the nav)
with the dropdown, the three volume sliders, a manual save, and the two-step
hard-reset button.

### 6.16 Audio (DEP-5)

`AudioManager` (autoload) owns all sound. Assets are **procedurally synthesised**
WAVs under `audio/` (see `audio/README.md`): `sfx/<id>.wav` one-shots (ids in
`Ids.SFX_*`) and `music/amb_<view>.wav` seamless ambient loops.

- **SFX** play through a small round-robin `AudioStreamPlayer` pool via
  `play_sfx(id)`. AudioManager wires the zero-coupling triggers itself by
  subscribing to `harvest_completed` (→ tick) and `node_broken` (→ pickup);
  level-up (`GameManager.add_xp`), build (`GroundsManager.build`), combat hits
  (`CombatView`), and nav clicks (`NavigationPanel`) are one-line `play_sfx`
  calls at the source.
- **Music** follows the view: AudioManager is in the `view_manager` group and
  implements `switch_view`, crossfading a two-player bed to the track mapped for
  that view. Loops are forced on at load (`AudioStreamWAV.LOOP_FORWARD`).
- **Volume** is master × category, read from `SettingsManager`; `set_*_volume`
  applies live and persists. 0 maps to a silence floor, not −∞ dB.

---

## 7. UI / theme

- `theme/graveyard_theme.tres` — the "Lanternlight" theme: dark elevated cards,
  gold/violet/rust accents, custom type variations (`HeaderLabel`, `MutedLabel`,
  `ChipPanel`, `ActionButton`, `DangerButton`).
- Views live under `MainViewContainer` in `Main.tscn` and toggle visibility via
  `Control.switch_view` (graveyard/forest/quarry/inventory/shop/combat). The
  Grounds, Settings, and Necronomicon are code-built overlays, not switched views.
- `NavigationPanel` (left sidebar, instanced in `Main.tscn`) has the three skill
  buttons + Inventory/Shop; Grounds/Settings buttons live in `Main.tscn`'s
  `TopNav` and are wired in `Control.gd`.
- `NotificationManager` + `PopUp.gd`/`ItemNotification.tscn` — toasts that ignore
  mouse and self-free (max 8 on screen).

---

## 8. Testing

`tests/SmokeTest.gd` (`SmokeTest.tscn`) is a headless integration test: loads the
main scene, exercises settings, loot tables, XP curve/cap, equipment, the
dig-layer and break meters, the tutorial walk, minion passives, and
notifications. It asserts **model/state**, not pixels. Run it in-editor. Note it
depends on node ids `withered_trees` (lumber primary, `dig_sections 2`) and
`verdigris_seams` (mine primary, `hit_damage 0.25`) staying stable.

---

## 9. How to add things (recipes)

**A material item:** drop a `.tres` in `data/items/materials/` with script
`ItemData.gd`, set `id`/`name`/`sell_value`/`icon`. It's auto-registered in
`item_db`.

**A harvest node:** `.tres` in `data/nodes/<graves|trees|mines>/` with
`HarvestNodeData.gd`. Set `required_skill`, `required_tool_type`, timings, and
loot pools (common+rare, or `hit_damage`+hit/break). Reference it from a zone's
`nodes` array.

**A zone:** `.tres` in `data/zones/` with `ZoneData.gd`; list its nodes and
`required_level`. Add it to a view's `zones` export in `Main.tscn`.

**A minion:** `.tres` in `data/minions/` with `MinionData.gd`; set stats,
`raise_cost`, and `abilities` (sub-resource `MinionAbilityData.gd` each). Passive
effects must be one of the recognised strings to do anything (§4).

**A structure:** `.tres` in `data/structures/` with `StructureData.gd`; set
`effect` (must be handled — currently `inventory_slots`/`harvest_xp_pct`/
`double_drop_pct`/`rare_chance_pct`/`offline_hours`), `grid_cell`/`footprint`
(so it places on the iso plot), and 5 `StructureTier` sub-resources. For custom
per-tier art, add a `_draw_<id>` branch in `StructureBuilding._draw`; otherwise
it uses the plain-box fallback.

**A gather-bonus effect:** add a channel to `get_gather_modifiers` and read it
via `MinionManager.get_passive_bonus` / `GroundsManager.get_bonus`.

**An affix:** add an entry to `GameManager.AFFIXES`; if active, handle it in
`get_gather_modifiers` (modifier) or `HarvestView` (stateful). Set the string on
a node's `affix`.

---

## 10. Tuning constants (quick index)

- Bonus caps: `GameManager.SPEED_CAP 1.6`, `SPEED_FLOOR 0.3`,
  `LEVEL_SPEED_MAX 0.25`, `LEVEL_SPEED_HALFLIFE 25`.
- Skill curve: `SKILL_XP_SCALE_EARLY/LATE 1.0/2.5`, `RAMP_END_LEVEL 30`,
  `MAX_LEVEL 100`.
- Inventory: `BASE_SLOTS 24`, `MAX_PURCHASED_SLOTS 24`, `SLOT_BASE_COST 250`,
  `SLOT_COST_GROWTH 1.35`.
- Minions: `PLOT_COUNT 4`, `MAX_LEVEL 50`, `OFFERING_XP_PER_GOLD 1.5`.
- Combat: `TURN_SECONDS 2.4`, `BEAT_SECONDS 0.75`, `DMG_VARIANCE 0.15`,
  `ACTIVE_RUNE_MULT 1.6`, `GUARD_REDUCTION 0.5`, `BOSS_SLAM_MULT 0.75`,
  `BOSS_SLAM_CHANCE 0.3`.
- Affix: `HarvestView.UNSTABLE_LOCKOUT_SECONDS 120`.
- Save/offline: `SAVE_VERSION 2`, `AUTOSAVE_INTERVAL 30`, `OFFLINE_BASE_HOURS 1`,
  `OFFLINE_MIN_SECONDS 60`.

---

## 11. Parked / incomplete (deliberate)

- **Flavor affixes** (thorn_veil, toxic_roots, sonic_resonance,
  subterranean_chill, volcanic_gas) are inert; they spec a future "deploy minions
  to harvest nodes with hazards" feature.
- **Minion active abilities** (`active_*`) exist as skill-tree entries but their
  combat effects aren't fully wired — combat power belongs in the Necronomicon,
  not in buildings.
- **Wave-two structures** (Mausoleum = offering potency, Counting House = sell
  value, Reliquary = rare-find) are designed but unbuilt; they slot in as `.tres`
  + placement now that the Grounds are data-driven.
- **Refining chain** (logs→planks, stone→bricks) is a proposed deeper sink.
- **Grounds M5 graphics** (lighting/day-night, shaders, richer buildings,
  animation) are scoped in `docs/grounds_iso_view_plan.md` but not built.
- No raster sprite art exists for the 30 deeper materials or the Grounds — the
  game leans on procedural/vector rendering and icon PNGs.
