# Graveyard Shift — Backlog

Derived from the full codebase scan (see `docs/DEVELOPER_REFERENCE.md`). Items
are grouped by category and prioritized; **possible fixes / approaches are in a
separate section at the bottom**, keyed by the same IDs. Completed items move to
the **Done** section (with a note on what landed) and drop out of the live
tables, so the tables always read as "what's left".

**Priority:** P1 (do soon) · P2 (worth doing) · P3 (nice to have)
**Effort:** S (< half a day) · M (1–2 sessions) · L (multi-session)

---

## ✅ Done

- **COR-3 — magic strings centralized.** New `scripts/Ids.gd` holds the wiring
  strings (effects, actives, affixes, skill keys, groups, views, tutorial
  events) as flat constants with `*_ALL` lists; raw literals replaced across
  managers, views, and tests. A typo is now a parse error, not a silent no-op.
- **QA-2 — content validation.** New `scripts/ContentValidator.gd` loads every
  `.tres` and asserts loot/zone/cost/encounter references resolve and every
  affix/effect id is known, reporting the offending file. Wired into a headless
  `tools/ValidateContent.tscn`, into `SmokeTest`, and into a debug-boot warning
  in `GameManager`.
- **COR-2 / DEP-1 — distinct active runes.** `CombatView` now resolves each
  inked active differently (Lurch = heavy, Rattling Volley = cleave-all, Rending
  Claws = sunder, Savage Pounce = gauge-drain) via a `_active_defs` table, with a
  light Sunder status layer, enemy/boss UI tags, and effect-specific tooltips.
  Damage split into `_strike_foe` + `_end_member_turn` helpers.
- **ARC-3 — save migration.** `SaveManager._migrate(data, from_version)` chains
  per-version upgrade steps instead of discarding old saves; newer-than-current
  saves are backed up (not overwritten); the file is re-saved after a successful
  migration. `SmokeTest` covers the contract.
- **DEP-5 — audio.** `AudioManager` autoload with a round-robin SFX pool and a
  per-view crossfading ambient bed. Six synthesised SFX + four seamless ambient
  loops under `audio/` (procedural, licence-free). Triggers wired via existing
  signals + one-line calls; master/SFX/music volume sliders in Settings, persisted
  in `SettingsManager`. (Also delivers the volume half of DEP-7.)

---

### Top picks (highest value for the effort)
- **QA-1** — widen automated coverage (combat, offline accrual, save round-trip).
  Combat and saves both just changed; lock them in before building further.
- **DEP-2** — combat stakes (status effects, consumables/heal, defeat cost).
  Builds directly on the new Sunder status layer and active runes.
> DEP-3 is reconceived (no crafting layer) and parked pending the future
> Forge/Alchemy skills — see its note below. A material-catalog audit is the
> only near-term slice.

**Quick wins** (P3/S, grab opportunistically): COR-1, COR-4, COR-5, COR-6,
DEP-7, DEP-9, DOC-1/2/3.

---

## Correctness & cleanup

| ID | Item | Pri | Effort |
|---|---|---|---|
| COR-1 | `nodes_by_skill` registry is built but never read | P3 | S |
| COR-4 | Dead helpers: `get_total_slots`, `is_max`, `owns_tool` | P3 | S |
| COR-5 | Minion offering-XP is coupled to item `sell_value` (price changes shift leveling) | P3 | S |
| COR-6 | Offline overflow past a full pack is silently lost | P3 | S |

## Testing & tooling

| ID | Item | Pri | Effort |
|---|---|---|---|
| QA-1 | No automated coverage for combat, Necronomicon, offline accrual, or save round-trip | P2 | M |

## Systems & depth

| ID | Item | Pri | Effort |
|---|---|---|---|
| DEP-2 | Combat stakes: healing/consumables, status effects, defeat consequences | P2 | L |
| DEP-3 | Material purpose — most of the ~40 materials have no sink; reserve fits for future Forge/Alchemy skills, cull/re-theme the rest (no crafting UI) | P2 | M |
| DEP-4 | Gold sinks beyond tool tiers + backpack slots | P3 | M |
| DEP-6 | Stats/tracking (totals gathered, playtime) + goals/achievements | P3 | M |
| DEP-7 | Settings depth — volume sliders now done; autosave interval/toggle remains | P3 | S |
| DEP-8 | "Deploy minions to nodes" system that activates the 5 flavor affixes | P3 | L |
| DEP-9 | Wave-two structures: Mausoleum, Counting House, Reliquary | P3 | S each |

## Architecture & performance

| ID | Item | Pri | Effort |
|---|---|---|---|
| ARC-1 | UI rebuilds a lot every tick; spread ActionCard's change-detection pattern | P3 | M |
| ARC-2 | Managers form a tight cross-reference web (hard to unit-test in isolation) | P3 | M |

## Commenting & readability

| ID | Item | Pri | Effort |
|---|---|---|---|
| DOC-1 | Section headers inside the dense UI-building functions in CombatView / NecronomiconPanel | P3 | S |
| DOC-2 | A one-line "responsibilities / talks to" header on the few files that lack one | P3 | S |
| DOC-3 | Tighten type hints on untyped vars/dictionaries | P3 | S |

> Note: overall commenting is already strong — DOC items are targeted polish, not
> a rewrite. Now that COR-3 landed, `scripts/Ids.gd` is the model for
> self-documenting constants elsewhere.

---

## Possible fixes / approaches

**COR-1 — dead `nodes_by_skill`.** Decide intent: if a "list nodes for a skill"
lookup is wanted (e.g. an almanac/collection screen), keep it and add a
`nodes_for_skill(key)` accessor; otherwise delete the field and its build loop in
`GameManager._build_node_registry`.

**COR-4 — dead helpers.** Remove `get_total_slots`, `is_max`, `owns_tool` (or
keep `is_max`/`owns_tool` if a near-term feature will use them — otherwise cut).

**COR-5 — decouple offering-XP.** Add an explicit `offering_value` (or
`offer_xp`) field to `Item` rather than deriving from `sell_value` in
`MinionManager.get_offering_xp`, so economy and minion-progression tuning are
independent. Default it to `sell_value` for back-compat.

**COR-6 — offline overflow.** Either (a) surface it in the welcome-back summary
("N items lost — pack was full"), or (b) stop the offline sim once the pack fills
so nothing is silently discarded. (a) is cheaper and clearer.

**QA-1 — widen tests.** Add headless `SmokeTest` cases: run a scripted combat to
`_enter_victory`/`_enter_defeat` and assert rewards/XP; drive each of the four
active runes and assert their distinct effect (heavy damage, all-foes cleave,
sunder flag set + bonus damage taken, pounce charge drain); raise/offer/slot a
minion and assert roster/plots/passives; call `GameManager.accrue_offline` and
assert banked gains + XP. (Save round-trip and the migration contract already
have coverage — extend, don't duplicate.) Keep assertions on model state, not
pixels.

**DEP-2 — combat stakes.** Options, in rising scope: a between-fights heal or a
consumable item type (`ItemType` already has room); more status effects on the
now-existing model (the `sunder` field is the template — add poison/guard buffs
the same way); and defeat consequences (temporary minion "exhaustion" that must
be rested off, rather than free retry). Pairs naturally with the active runes.

**DEP-3 — material purpose (reconceived — NOT a crafting layer).** Decision: no
standalone crafting/refining view. Materials find purpose as inputs to two future
production skills:
- **Forge** — one skill with two subsets under a shared curve: *metalworking*
  (weapons/armor from ores — nickel/tungsten/cobalt/sphalerite/pyrite) and
  *jewelry/trinkets* (gems — quartz/beryl/malachite/obsidian/imperial jade, +
  amber). Jewelry outputs are passive-granting trinkets, distinct from smith gear.
- **Alchemy** — organics: necromantic matter (flesh/blood/bones/grave dust/marrow/
  skull/sinew/fangs/withered heart) + herbs (lichen/moss/thorns/nightshade/briar).
  Natural fit for combat consumables (pairs with DEP-2).

Wood and stone already sink into the Grounds structures, so they stay building
materials — no new skill needed. Orphans (grave_dust, bone_marrow, malachite_flake,
peridotite_chunk, pyrite_dust, slate_slab) all get homes under the above;
`nincompoops_tome` is flavor, not a material. Also worth a pass: the `rarity`
field is unused (150g obsidian is flagged "Common") — align it with tier/value.

**DEP-4 — gold sinks.** Make some structure tiers cost gold alongside materials;
add a gold-priced cosmetic or convenience (faster autosave, extra loadout);
or a merchant that sells rare reagents for gold.

**DEP-6 — stats/goals.** A lightweight `StatsManager` accumulating counters
(items gathered by id, harvests, gold earned, playtime) saved with the run; a
simple goals list that reads those counters. Feeds a future achievements screen.

**DEP-7 — settings depth.** Volume (master/SFX/music) is done (DEP-5). What
remains: an autosave-interval or autosave-on/off toggle in `SettingsManager` +
`SettingsPanel`.

**DEP-8 / DEP-9 — deployment + wave-two.** DEP-8 is scoped as the feature the
flavor affixes wait on. DEP-9 structures slot in as `.tres` + `grid_cell`
placement + (optionally) a `_draw_<id>` in `StructureBuilding`; effects
`offering_pct` (Mausoleum), `sell_pct` (Counting House), `rare_chance_pct`
(Reliquary — already a supported channel). New effect ids go in `scripts/Ids.gd`
and `ContentValidator` will then enforce them.

**ARC-1 — tick cost.** Give per-tick `update_ui` implementations the same
change-detection guard ActionCard uses (hash the displayed state, skip rebuild
when unchanged), or move rarely-changing UI off the tick and onto the relevant
signal (`inventory_updated`, `minions_updated`, `grounds_updated`).

**ARC-2 — coupling.** Low-priority at this scale. If it bites, introduce a thin
event bus (an autoload with signals) so managers emit/subscribe instead of
calling each other directly, and pass dependencies into functions where testing
in isolation matters.

**DOC-1/2/3 — readability polish.** Add `# --- <section> ---` banners inside the
long `_build_*` functions in CombatView/NecronomiconPanel; add a two-line header
comment (purpose + who it talks to) to files missing one; and annotate untyped
`var`s and `Dictionary` shapes with their element types where it aids the reader.
