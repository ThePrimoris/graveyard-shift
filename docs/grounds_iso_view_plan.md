# The Grounds — Isometric View: Implementation Plan

Locked direction: replace the current list-style Grounds overlay with an
isometric, zoomable map of the graveyard. Structures sit on a tiled plot, each
is clickable, a docked right-hand panel inspects and upgrades the selected
structure, and every building's art visibly grows through its five tiers. This
mirrors the approved mockup (`graveyard_grounds_iso_tiers_rightpanel`).

The important framing: this is a **new presentation layer** over systems that
already exist. None of the economy, bonus, save, or offline logic needs to
change. We are building a view, not a feature.

---

## 1. What already exists (reuse, don't rebuild)

- `GroundsManager` autoload — loads `data/structures/*.tres` into `structure_db`,
  tracks `levels`, and exposes `next_tier()`, `can_afford()`, `build()`,
  `get_structure_value()`, `get_bonus()`, plus the `grounds_updated` signal and
  save/load. **This is the whole model. The iso view only reads from it and
  calls `build()`.**
- `Structure` / `StructureTier` resources, with four structures authored:
  `ossuary`, `chapel`, `wardens_grove`, `grave_lantern`.
- Bonus wiring already consumes structure effects: `get_gather_modifiers`
  (xp / double / rare), inventory slot bonus, and offline hours. Untouched here.
- Entry point: the "Grounds" nav button and `Control.gd`'s `_on_grounds_pressed`
  toggle. We keep this and just point it at the new scene.

The list `GroundsView.gd` overlay is what we retire.

---

## 2. Target node architecture

Godot's isometric tooling (isometric `TileMapLayer`, `Y`-sorting, `Area2D`
picking, `Camera2D`) does the heavy lifting the mockup faked in JS. Proposed
tree:

```
GroundsView            (CanvasLayer overlay, layer 58 — same as today)
└─ Root                (Control, full-rect, dim background)
   ├─ TopBar           (Control) — resource chips (gold + key materials)
   └─ Body             (HBoxContainer)
      ├─ WorldFrame    (SubViewportContainer, stretch, fills remaining width)
      │  └─ SubViewport
      │     └─ GroundsWorld            (Node2D)
      │        ├─ Camera2D             (framing + optional pan/zoom)
      │        ├─ GroundTiles          (TileMapLayer, isometric)
      │        ├─ Props                (Node2D, y_sort_enabled) — graves, fence,
      │        │                         dead tree, ritual circle, candles
      │        └─ Structures           (Node2D, y_sort_enabled)
      │           └─ StructureBuilding × N   (one per Structure resource)
      └─ InspectPanel  (Control, fixed ~248px, docked right)
```

Why a `SubViewport`: it gives a clean, self-contained 2D world we can pan/zoom
and frame independently of the surrounding UI, and it keeps the game's
otherwise Control-based UI cleanly separated from its first Node2D scene.
`y_sort_enabled` on `Props` and `Structures` gives correct back-to-front overlap
natively — replacing the manual depth-sort the mockup does by hand.

A simpler fallback (no SubViewport, a bare `Node2D` under the Control with a
fixed transform) is viable for a static frame, but the SubViewport is worth it
the moment we want zoom, which the mockup already implies.

---

## 3. Data additions

Placement and per-tier art belong on the data, so structures stay fully
data-driven (adding a wave-two building is a `.tres`, not code).

Extend `data/StructureData.gd`:

- `@export var grid_cell: Vector2i` — the tile the building's footprint anchors to.
- `@export var footprint: Vector2i = Vector2i(2, 2)` — size in tiles (drives the
  click area and the iso box base).
- `@export var tier_art: Array[Texture2D] = []` — sprite per built level
  (index `level - 1`). Empty ⇒ use the procedural placeholder (see §5).
- `@export var build_site_art: Texture2D` — optional tier-0 "build site" sprite.

Then set `grid_cell` / `footprint` on each of the four existing `.tres` files to
match the mockup layout (chapel top-left, ossuary top-right, grove bottom-left,
grave-lantern bottom-right, ritual circle centre).

---

## 4. `StructureBuilding` node

One reusable scene, `scenes/views/grounds/StructureBuilding.tscn` +
`scripts/ui/StructureBuilding.gd`:

- Root `Node2D`, positioned from `grid_cell` via a shared iso helper.
- `Area2D` + `CollisionPolygon2D` shaped to the footprint diamond, for picking.
- A visual child — either a `Sprite2D` (final art) or a procedurally drawn
  building (placeholder).
- Holds `structure_id`; connects to `GroundsManager.grounds_updated`.
- `refresh()` reads `GroundsManager.get_level(id)` and either swaps
  `Sprite2D.texture = tier_art[level-1]` (or `build_site_art` at level 0) or
  re-runs the procedural draw for that level.
- Emits `selected(structure_id)` on `input_event` (mouse click) so the view can
  update the panel and the highlight.

A tiny `scripts/ui/IsoUtil.gd` holds the projection (`cell_to_world`,
`footprint_polygon`, tile size constants) so the building, highlight, and any
props share one source of truth.

---

## 5. Per-tier visuals (the "leveling" the mockup sells)

Two tracks, same architecture — art can land later without rework:

- **Placeholder (build now):** port the mockup's per-tier draw functions
  (`drawChapel`, `drawOssuary`, `drawGrove`, `drawLantern`) to GDScript `_draw()`
  using `draw_polygon` / `draw_colored_polygon`. Height, window count, columns,
  tree count, spire, flag, and lantern glow all key off the current level exactly
  as they do in the mock. This gives day-one parity with the approved look and no
  dependency on an artist.
- **Final (drop-in later):** author five sprites per structure and assign
  `tier_art`; `refresh()` swaps the texture. No structural change.

The lantern's growing glow is best as a `PointLight2D` (or a soft radial sprite)
whose `energy`/`scale` scales with level — it also sets up cleanly for a future
day/night pass, where that light finally earns its keep.

---

## 6. Inspect / upgrade panel

Reuse the logic already written in the list `GroundsView.gd`, refactored into a
single `_show_detail(structure_id)` on the right panel:

- Name, effect label chip, description.
- Tier pips + `Tier X / max`.
- Effect `now → next` (derived from tier × step of the tier magnitudes).
- Cost rows with have/need, coloured green/red via `InventoryManager.get_item_count`.
- Build button → `GroundsManager.build(id)`; disabled when unaffordable; a
  "fully raised" terminal state.
- Rebuilds on `grounds_updated` and on selection.

This is a straight lift — the model calls are identical to what ships today.

---

## 7. Interaction

- Click a building → select it → draw a gold footprint outline in the world +
  populate the panel.
- Click empty ground → deselect.
- Camera: a fixed framed view first (a set `Camera2D.zoom`/position that fits the
  plot, matching the mock's tight framing). Drag-pan and scroll-zoom are a small,
  optional follow-up.

---

## 8. Wiring & migration

- `Control.gd`: change the grounds toggle to instantiate the new
  `GroundsView.tscn` (a `PackedScene`) instead of `GROUNDS_VIEW_SCRIPT.new()`.
  The nav button, open/close toggle, and layer stay the same.
- Retire the list `GroundsView.gd` (or keep it behind a debug flag briefly).
- Save/load, bonus aggregation, and offline progress are untouched — they read
  `GroundsManager`, which is unchanged.

---

## 9. Art & asset needs (the real variable)

Called out honestly, because this is where scope lives:

- Isometric ground tile(s): 1–2 variants, or a procedural checker.
- Building art: 4 structures × ~5 tiers ≈ 20 sprites — **or** procedural
  placeholders (recommended to unblock).
- Props: a few headstone variants, iron fence segment, dead tree, ritual-circle
  decal, candle, lantern glow.

Recommendation: ship **procedural placeholders** first (they already look like
the approved mock), and treat real sprite art as a parallel track that swaps in
via `tier_art` with zero code churn.

---

## 10. Milestones

- **M1 — Skeleton.** SubViewport + isometric ground + framed camera, opened from
  the nav button, replacing the overlay. Empty plot, no structures yet.
- **M2 — Structures + panel.** Place `StructureBuilding`s from data (placeholder
  art), click-to-select, right panel wired to `GroundsManager` inspect + build.
  Fully playable loop.
- **M3 — Leveling.** Per-tier procedural growth so buildings visibly rise as they
  tier up (ports the mock's draw functions).
- **M4 — Atmosphere.** Graveyard props (graves, fence, dead tree, ritual circle,
  candles), selection highlight, on-map tier pips, a small build-feedback beat.
- **M5 — Future.** Real sprite art swap-in; pan/zoom; day/night with the lantern
  light; and the wave-two structures (Mausoleum = offering potency, Counting
  House = sell value, Reliquary = rare-find) added purely as new `.tres` +
  placement.

M1–M4 with placeholders is a few focused sessions; real art is the main unknown.

---

## 11. File checklist

Created:
- `scenes/views/grounds/GroundsView.tscn` (+ `scripts/ui/GroundsView.gd`, replacing the list one)
- `scenes/views/grounds/StructureBuilding.tscn` (+ `scripts/ui/StructureBuilding.gd`)
- `scripts/ui/IsoUtil.gd`
- `art/grounds/...` tiles / props / structure sprites (or procedural, deferred)

Modified:
- `data/StructureData.gd` — add `grid_cell`, `footprint`, `tier_art`, `build_site_art`
- `data/structures/*.tres` — set placement (and art when available)
- `Control.gd` — toggle the new `GroundsView.tscn`
- `tests/SmokeTest.gd` — instantiate the new view; assert the build/afford loop
  and `grounds_updated` refresh still hold (assert model state, not pixels)

Retired:
- the current list-style `GroundsView.gd`

---

## 12. Risks & notes

- **Overlap:** lean on `y_sort_enabled` rather than manual depth sorting.
- **Picking:** `Area2D` with a diamond `CollisionPolygon2D` per footprint.
- **Headless tests:** the SubViewport/Node2D world must instantiate in headless
  runs; keep SmokeTest assertions on manager/build state, guard any purely
  visual checks.
- **Window fit:** the game's min window is 1160×660 — panel is fixed width, the
  world scales to fill the rest.
- **Stay data-driven:** placement + art on the resource means wave-two structures
  slot in without touching the view code.
