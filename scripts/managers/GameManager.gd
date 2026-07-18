# GameManager.gd
extends Node

signal harvest_completed(node_id: String)
signal node_broken(node_id: String)

@export_group("Game Meta")
@export var game_title: String = "Graveyard Shift"
@export var game_version: String = "0.11.2"
@export var game_author: String = "Matthew"

@export_group("Inventory & Equipment")
@export var inventory: Array[Item] = []

# One tool of each type can be equipped at once: { ToolData.ToolType (int) -> ToolData }
var equipped_tools: Dictionary = {}

const PATH_SHOVEL = "res://data/items/tools/rusty_shovel.tres"
const PATH_HATCHET = "res://data/items/tools/rusty_hatchet.tres"
const PATH_PICKAXE = "res://data/items/tools/rusty_pickaxe.tres"

const ITEM_DIRS: Array[String] = [
	"res://data/items/materials/",
	"res://data/items/tools/",
	"res://data/items/consumables/",
	"res://data/items/gear/"
]
const NODE_DIRS: Array[String] = [
	"res://data/nodes/graves/",
	"res://data/nodes/trees/",
	"res://data/nodes/mines/"
]
const ENCOUNTER_DIRS: Array[String] = ["res://data/encounters/"]

var active_action_source: Node = null
var active_node_data: HarvestNode = null

var gold_coins: int = 0

# Auto-populated registries so any system can look content up by id.
var item_db: Dictionary = {}          # item_id -> Item resource
var node_db: Dictionary = {}          # node_id -> HarvestNode resource
var encounter_db: Dictionary = {}     # encounter_id -> Encounter resource

enum SkillType { GRAVEROBBING, LUMBERING, SPELUNKING }

const MAX_LEVEL: int = 100

var skills: Dictionary = {
	Ids.SKILL_GRAVEROBBING: {"level": 1, "xp": 0.0},
	Ids.SKILL_LUMBERING: {"level": 1, "xp": 0.0},
	Ids.SKILL_SPELUNKING: {"level": 1, "xp": 0.0},
	# Production skills (P3/P5): leveled via crafting stations, not nodes.
	Ids.SKILL_ALCHEMY: {"level": 1, "xp": 0.0},
	Ids.SKILL_FORGE: {"level": 1, "xp": 0.0}
}

## Gather elixirs (P3): effect id -> {"magnitude": float, "until": unix ts}.
## One buff per effect channel; drinking again refreshes/replaces it.
var active_buffs: Dictionary = {}

func _ready() -> void:
	_build_item_database()
	_build_node_registry()
	_build_encounter_registry()
	call_deferred("_setup_starting_equipment")
	# Debug-only: surface broken content / unknown affix + effect ids at boot so
	# typos in a new .tres show up immediately instead of silently doing nothing.
	# Stripped from release builds (OS.is_debug_build() is false there).
	if OS.is_debug_build():
		call_deferred("_validate_content_debug")

## Runs the QA-2 content pass and routes any problems to the Godot warning log.
func _validate_content_debug() -> void:
	var errors := ContentValidator.validate()
	for err in errors:
		push_warning("[ContentValidator] " + err)
	if not errors.is_empty():
		push_warning("[ContentValidator] %d content problem(s) found — see warnings above." % errors.size())

## Wipes all run progress back to a fresh start (used by the Settings hard reset).
func reset_state() -> void:
	gold_coins = 0
	active_action_source = null
	active_node_data = null
	inventory.clear()
	equipped_tools.clear()
	active_buffs.clear()
	for skill_name in skills.keys():
		skills[skill_name] = {"level": 1, "xp": 0.0}
	_setup_starting_equipment()

# --- Content Registries ---

func _build_item_database() -> void:
	item_db.clear()
	for dir_path in ITEM_DIRS:
		for res in _load_resources_in_dir(dir_path):
			if res is Item and res.id != "":
				item_db[res.id] = res

func _build_node_registry() -> void:
	node_db.clear()
	for dir_path in NODE_DIRS:
		for res in _load_resources_in_dir(dir_path):
			if res is HarvestNode and res.id != "":
				node_db[res.id] = res

func _load_resources_in_dir(dir_path: String) -> Array:
	var result: Array = []
	var dir = DirAccess.open(dir_path)
	if not dir:
		push_warning("GameManager: Could not open resource directory: " + dir_path)
		return result
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# Exported builds list text resources as "<name>.tres.remap"; trim the
		# suffix so they still match, and load the original path (Godot remaps it).
		var res_file = file_name.trim_suffix(".remap")
		if not dir.current_is_dir() and res_file.ends_with(".tres"):
			var res = load(dir_path + res_file)
			if res:
				result.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result

func _build_encounter_registry() -> void:
	encounter_db.clear()
	for dir_path in ENCOUNTER_DIRS:
		for res in _load_resources_in_dir(dir_path):
			if res is Encounter and res.id != "":
				encounter_db[res.id] = res

func find_encounter_by_id(encounter_id: String) -> Encounter:
	return encounter_db.get(encounter_id, null)

func find_item_by_id(item_id: String) -> Item:
	return item_db.get(item_id, null)

func find_node_by_id(node_id: String) -> HarvestNode:
	return node_db.get(node_id, null)

func get_skill_key(node: HarvestNode) -> String:
	return SkillType.keys()[node.required_skill].to_lower()

# --- Equipment ---

## Registers a tool as owned. Tools live in equipment slots, not the grid.
func add_tool_to_inventory(tool: ToolData) -> void:
	if not inventory.has(tool):
		inventory.append(tool)
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

func _setup_starting_equipment() -> void:
	for path in [PATH_SHOVEL, PATH_HATCHET, PATH_PICKAXE]:
		var tool = load(path)
		if tool:
			add_tool_to_inventory(tool)
			equipped_tools[tool.tool_type] = tool

func get_equipped_tool(type_enum: int) -> ToolData:
	return equipped_tools.get(type_enum, null)

## The tool that represents this type's current progression tier.
func get_current_tool_of_type(type_enum: int) -> ToolData:
	var equipped = equipped_tools.get(type_enum, null)
	if equipped: return equipped
	var best: ToolData = null
	for t in inventory:
		if t is ToolData and t.tool_type == type_enum:
			if best == null or t.tool_tier > best.tool_tier:
				best = t
	return best

## The next tier's tool for this type, or null when already at max tier.
func get_next_tool_upgrade(type_enum: int) -> ToolData:
	var current = get_current_tool_of_type(type_enum)
	var next_tier = (current.tool_tier + 1) if current else ToolData.ToolTier.RUSTED
	for item_id in item_db:
		var item = item_db[item_id]
		if item is ToolData and item.tool_type == type_enum and item.tool_tier == next_tier:
			return item
	return null

## Swaps the type's tool for the next tier. The old tool is consumed.
func upgrade_tool(type_enum: int) -> bool:
	var next = get_next_tool_upgrade(type_enum)
	if next == null: return false

	var current = get_current_tool_of_type(type_enum)
	if current:
		inventory.erase(current)
		if InventoryManager.get_item_count(current.id) > 0:
			InventoryManager.remove_item(current.id, 1)

	add_tool_to_inventory(next)
	equipped_tools[type_enum] = next
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Equips an owned tool into its type slot; any previous tool of that type
## returns to the backpack grid.
func equip_tool(tool: ToolData) -> bool:
	if not inventory.has(tool): return false
	var old = equipped_tools.get(tool.tool_type, null)
	if old == tool: return true
	if old and not InventoryManager.has_room_for(old):
		NotificationManager.show_item("Inventory full — cannot swap tools", 1)
		return false
	if InventoryManager.get_item_count(tool.id) > 0:
		InventoryManager.remove_item(tool.id, 1)
	equipped_tools[tool.tool_type] = tool
	if old:
		InventoryManager.add_item(old, 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Moves an equipped tool back into the backpack grid.
func unequip_tool(type_enum: int) -> bool:
	var tool = equipped_tools.get(type_enum, null)
	if tool == null: return false
	if not InventoryManager.has_room_for(tool):
		NotificationManager.show_item("Inventory full — cannot unequip", 1)
		return false
	equipped_tools.erase(type_enum)
	InventoryManager.add_item(tool, 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

# === Gather bonuses (the "Access & Yield" model) =====================
# Every source pushes a DIFFERENT lever, and speed sources stack ADDITIVELY
# (1 + a + b) rather than multiplicatively, so combining them never explodes:
#   Tools  -> a little speed + a chance to double the haul (yield).
#   Levels -> a small, diminishing speed bump (unlocks are the real reward).
#   Minions-> pure spice: bonus XP and rare-find chance, never speed.
# The whole loop's rhythm is meant to stay recognisable end to end, so total
# speed is capped hard and the pieces are deliberately modest.

## Master switch. Flip off to park every gather bonus (used to isolate bugs).
const SPEED_BONUSES_ENABLED: bool = true

## Hard ceiling on assembled speed: a node can never harvest faster than this
## multiple of its base rate, no matter how much is stacked. Keeps old nodes
## brisk-but-not-trivial once you outgrow them.
const SPEED_CAP: float = 1.6

## Level speed: a diminishing curve that approaches LEVEL_SPEED_MAX. Front
## loaded (half the bonus is banked by ~level 26) then flattens, so leveling
## always helps a touch without ever running away.
const LEVEL_SPEED_MAX: float = 0.25
const LEVEL_SPEED_HALFLIFE: float = 25.0

## Speed can never sink below this share of base (sticky affixes bite, but a
## node stays workable).
const SPEED_FLOOR: float = 0.3

# --- Node affixes ------------------------------------------------------
# `active` affixes change harvesting here and now (handled below / in the
# harvest view). The rest are FLAVOUR: they read as threats on the card but do
# nothing yet, because they target minions deployed onto nodes — a system that
# doesn't exist yet. They're a ready-made spec for that future feature.
#   power: sticky_sap = speed lost; others use their own handlers.
# NOTE: keys are string literals (not Ids.AFFIX_*) because this is a `const`
# dict — keys must be constant expressions, and this is the affix registry's
# canonical definition. Ids.AFFIX_* mirror these, and ContentValidator asserts
# the two stay in lockstep, so a drift here still surfaces loudly.
const AFFIXES: Dictionary = {
	"sticky_sap": {
		"name": "Sticky Sap", "active": true, "power": 0.3,
		"blurb": "Resin clings to the blade — every harvest here drags slower.",
	},
	"blind_canopies": {
		"name": "Blind Canopies", "active": true, "power": 0.0,
		"blurb": "The choking canopy hides the richest boughs — no double hauls here.",
	},
	"unstable_seams": {
		"name": "Unstable Seams", "active": true, "power": 0.0,
		"blurb": "Volatile gas builds with every strike; a break vents it and seals the seam for a spell.",
	},
	"thorn_veil": {
		"name": "Thorn Veil", "active": false, "power": 0.0,
		"blurb": "Barbs lash any minion set to work here. (Awaits the rite of deployment.)",
	},
	"toxic_roots": {
		"name": "Toxic Roots", "active": false, "power": 0.0,
		"blurb": "Creeping venom stacks on deployed minions over time. (Awaits deployment.)",
	},
	"sonic_resonance": {
		"name": "Sonic Resonance", "active": false, "power": 0.0,
		"blurb": "Echoing tremors disrupt a deployed minion's automation. (Awaits deployment.)",
	},
	"subterranean_chill": {
		"name": "Subterranean Chill", "active": false, "power": 0.0,
		"blurb": "A deep cold saps deployed minions' efficiency. (Awaits deployment.)",
	},
	"volcanic_gas": {
		"name": "Volcanic Gas Venting", "active": false, "power": 0.0,
		"blurb": "Periodic fire bursts scald any deployed party. (Awaits deployment.)",
	},
}

## Affix metadata for `affix_id`, or {} when there is no such affix.
func get_affix_info(affix_id: String) -> Dictionary:
	return AFFIXES.get(affix_id, {})

func _level_speed_bonus(level: int) -> float:
	if level <= 1: return 0.0
	return LEVEL_SPEED_MAX * (1.0 - pow(0.5, (level - 1) / LEVEL_SPEED_HALFLIFE))

## The single source of truth for every gather bonus applied to `node`.
## Returns:
##   speed_mult    - divides base_duration (>= 1.0, capped at SPEED_CAP)
##   double_chance - 0..1 odds the common/hit haul is doubled
##   rare_add      - flat fraction added to the node's rare_chance (0..1)
##   xp_mult       - multiplier on harvest XP (>= 1.0)
func get_gather_modifiers(node: HarvestNode) -> Dictionary:
	var mods := {"speed_mult": 1.0, "double_chance": 0.0, "rare_add": 0.0, "xp_mult": 1.0}
	if not SPEED_BONUSES_ENABLED:
		return mods

	# Tools: small additive speed, plus a double-haul chance from yield.
	var tool = equipped_tools.get(node.required_tool_type, null)
	if tool:
		mods.speed_mult += maxf(0.0, tool.speed_multiplier - 1.0)
		mods.double_chance += maxf(0.0, float(tool.yield_bonus)) / 100.0

	# Levels: diminishing speed only.
	var skill_key = get_skill_key(node)
	var level = skills[skill_key]["level"] if skill_key in skills else 1
	mods.speed_mult += _level_speed_bonus(level)

	# Minion passives (magnitudes are percentage points): spice, no speed.
	mods.xp_mult += MinionManager.get_passive_bonus(Ids.EFFECT_HARVEST_XP_PCT) / 100.0
	mods.rare_add += MinionManager.get_passive_bonus(Ids.EFFECT_RARE_CHANCE_PCT) / 100.0
	mods.double_chance += MinionManager.get_passive_bonus(Ids.EFFECT_DOUBLE_DROP_PCT) / 100.0

	# Graveyard structures (the Grounds): global build bonuses, same spice
	# channels — never raw speed.
	mods.xp_mult += GroundsManager.get_bonus(Ids.EFFECT_HARVEST_XP_PCT) / 100.0
	mods.rare_add += GroundsManager.get_bonus(Ids.EFFECT_RARE_CHANCE_PCT) / 100.0
	mods.double_chance += GroundsManager.get_bonus(Ids.EFFECT_DOUBLE_DROP_PCT) / 100.0

	# Brewed buffs (P3): short-lived elixir/incense channels, same spice again.
	mods.xp_mult += get_buff_bonus(Ids.EFFECT_HARVEST_XP_PCT) / 100.0
	mods.rare_add += get_buff_bonus(Ids.EFFECT_RARE_CHANCE_PCT) / 100.0
	mods.double_chance += get_buff_bonus(Ids.EFFECT_DOUBLE_DROP_PCT) / 100.0

	# Node affix: a penalty the node imposes on the loop (applied after bonuses,
	# so a rich tool can soften but not erase it). (if/elif rather than match so
	# the Ids.AFFIX_* constants are plain runtime comparisons, not const patterns.)
	if node.affix == Ids.AFFIX_STICKY_SAP:
		mods.speed_mult -= float(AFFIXES[Ids.AFFIX_STICKY_SAP]["power"])
	elif node.affix == Ids.AFFIX_BLIND_CANOPIES:
		mods.double_chance = 0.0
	# unstable_seams is stateful (lockout) and handled in the harvest view.

	mods.speed_mult = clampf(mods.speed_mult, SPEED_FLOOR, SPEED_CAP)
	mods.double_chance = clampf(mods.double_chance, 0.0, 1.0)
	return mods

## The real time one harvest of this node takes, after all speed bonuses.
func get_effective_duration(node: HarvestNode) -> float:
	if not SPEED_BONUSES_ENABLED:
		return node.base_duration
	return node.base_duration / get_gather_modifiers(node).speed_mult

# --- Timed gather buffs (P3 elixirs) ---

## Lays a timed buff on an effect channel (replacing any previous one there).
## `source` names the consumable that laid it, for the sidebar readout.
func apply_timed_buff(effect: String, magnitude: float, minutes: float, source: String = "") -> void:
	active_buffs[effect] = {
		"magnitude": magnitude,
		"until": Time.get_unix_time_from_system() + minutes * 60.0,
		"source": source,
	}
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

## The live buff magnitude for an effect channel; expired buffs are pruned.
func get_buff_bonus(effect: String) -> float:
	if not active_buffs.has(effect):
		return 0.0
	var buff = active_buffs[effect]
	if Time.get_unix_time_from_system() >= float(buff.get("until", 0.0)):
		active_buffs.erase(effect)
		return 0.0
	return float(buff.get("magnitude", 0.0))

## Seconds a channel's buff has left (0 = none) — for UI readouts.
func buff_seconds_left(effect: String) -> float:
	if not active_buffs.has(effect):
		return 0.0
	return maxf(0.0, float(active_buffs[effect].get("until", 0.0)) - Time.get_unix_time_from_system())

# --- Skills / XP ---

## The skill curve's slow-burn ramp: early levels run at the classic RS pace
## (EARLY scale), then the requirement stretches linearly until it reaches
## the LATE scale at RAMP_END_LEVEL. Early levels feel brisk; the grind
## arrives with the mid-game.
const SKILL_XP_SCALE_EARLY: float = 1.0
const SKILL_XP_SCALE_LATE: float = 2.5
const SKILL_XP_RAMP_END_LEVEL: int = 30

## XP to advance FROM `level`: the classic RuneScape/Melvor curve shape,
## scaled by the level-ramped slow-burn factor above.
func get_xp_needed(level: int) -> float:
	var t = clampf((level - 1) / float(SKILL_XP_RAMP_END_LEVEL - 1), 0.0, 1.0)
	var scale = lerpf(SKILL_XP_SCALE_EARLY, SKILL_XP_SCALE_LATE, t)
	return floor((level + 300.0 * pow(2.0, level / 7.0)) / 4.0 * scale)

func add_xp(skill_name: String, amount: float) -> void:
	if not skills.has(skill_name): return
	var skill = skills[skill_name]
	if skill["level"] >= MAX_LEVEL: return
	var start_level: int = skill["level"]
	skill["xp"] += amount
	var xp_needed = get_xp_needed(skill["level"])
	while skill["xp"] >= xp_needed and skill["level"] < MAX_LEVEL:
		skill["xp"] -= xp_needed
		skill["level"] += 1
		xp_needed = get_xp_needed(skill["level"])
	if skill["level"] >= MAX_LEVEL:
		skill["xp"] = 0.0
	if skill["level"] > start_level:
		AudioManager.play_sfx(Ids.SFX_LEVEL_UP)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

# --- Node Accessibility ---

func is_node_accessible(node: HarvestNode) -> bool:
	var skill_key = get_skill_key(node)
	var s_level = skills[skill_key]["level"] if skill_key in skills else 1
	return s_level >= node.required_level

func get_node_requirement_text(node: HarvestNode) -> String:
	return "Requires level %d %s" % [node.required_level, get_skill_key(node).capitalize()]

# --- Active Action Tracking ---

func register_activity(calling_node: Node, node_data: HarvestNode = null) -> bool:
	if active_action_source == calling_node:
		active_action_source = null
		active_node_data = null
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
		return false
	# Gathering and crafting are exclusive: taking up the spade stops the vat.
	for station in [AlchemyManager, ForgeManager]:
		if station.active_recipe != null:
			NotificationManager.show_item("%s halts — the shift turns to gathering" % station.active_recipe.name, 1)
			station.stop_brew()
	active_action_source = calling_node
	active_node_data = node_data
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Halts any running gather. Combat and the crafting stations call this when
## they start — the caretaker can't swing a spade and mind a vat or a battle
## at the same time.
func stop_gathering() -> void:
	if active_action_source == null:
		return
	active_action_source = null
	active_node_data = null
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

# --- Harvest Resolution ---
# One code path resolves every harvest, so future bonuses apply consistently.

## One roll on a Hit Chance table, where weights are literal percentages out
## of 100. Returns the winning row, or null when the roll lands in the
## "nothing shakes loose" remainder (or the table is empty).
func roll_chance_table(pool: Array) -> LootDrop:
	var roll = randf() * 100.0
	for entry in pool.slice(0, HarvestNode.MAX_LOOT_ENTRIES):
		if entry == null or entry.item == null or entry.weight <= 0.0:
			continue
		roll -= entry.weight
		if roll <= 0.0:
			return entry
	return null

## One weighted roll on a drop table. Returns the winning row, or null for
## an empty/weightless table. Row share = weight / total table weight.
func roll_drop_table(pool: Array) -> LootDrop:
	var entries = pool.slice(0, HarvestNode.MAX_LOOT_ENTRIES)
	var total := 0.0
	for entry in entries:
		if entry != null and entry.item != null and entry.weight > 0.0:
			total += entry.weight
	if total <= 0.0:
		return null
	var roll = randf() * total
	for entry in entries:
		if entry == null or entry.item == null or entry.weight <= 0.0:
			continue
		roll -= entry.weight
		if roll <= 0.0:
			return entry
	return null

## One roll of a common + rare table pair. `double_chance` can double the
## common haul (the everyday take); rare finds are never doubled.
func _roll_loot(common_pool: Array, rare_chance: float, rare_pool: Array, double_chance: float) -> Dictionary:
	var gains: Dictionary = {}

	var common = roll_drop_table(common_pool)
	if common:
		var amount = randi_range(common.min_amount, maxi(common.min_amount, common.max_amount))
		if double_chance > 0.0 and randf() < double_chance:
			amount *= 2
		gains[common.item.id] = gains.get(common.item.id, 0) + amount

	if rare_chance > 0.0 and randf() <= rare_chance:
		var rare = roll_drop_table(rare_pool)
		if rare:
			var amount = randi_range(rare.min_amount, maxi(rare.min_amount, rare.max_amount))
			gains[rare.item.id] = gains.get(rare.item.id, 0) + amount
	return gains

## One unmodified roll of a node's common/rare pair — the node's raw tables,
## no player double/rare bonuses. Deployed minions (DEP-8) gather with this:
## their pace and haul must not swing with the player's loadout.
func roll_plain_loot(node: HarvestNode) -> Dictionary:
	return _roll_loot(node.common_pool, node.rare_chance, node.rare_pool, 0.0)

## Banks rolled gains into the inventory, optionally with pickup toasts.
func _bank_gains(gains: Dictionary, notify: bool) -> void:
	for item_id in gains:
		var item = find_item_by_id(item_id)
		if item:
			InventoryManager.add_item(item, gains[item_id])
			if notify:
				NotificationManager.show_item(item.name, gains[item_id], item)

## Whether a node is worn down over several bars (each a "hit") before it yields
## its guaranteed break haul, rather than paying a common/rare pull every bar.
## Covers BOTH Spelunking breakables (hit_damage) and Lumbering dig-layers
## (dig_sections): they share the hit-per-bar + break-on-empty model.
func is_breakable(node: HarvestNode) -> bool:
	return node.hit_damage > 0.0 or node.dig_sections > 0

## The share of a node's integrity one completed bar removes. A dig node spends
## 1/dig_sections per bar (so it falls after `dig_sections` chops); a hit_damage
## node uses its authored value; a common/rare node returns 0.
func per_hit_damage(node: HarvestNode) -> float:
	if node.hit_damage > 0.0:
		return node.hit_damage
	if node.dig_sections > 0:
		return 1.0 / float(node.dig_sections)
	return 0.0

## Resolves a completed bar on `node`. Returns { item_id: amount } gained.
## Common/rare nodes (graves): exactly one common row plus a possible rare roll.
## Breakable nodes (Spelunking hit_damage, Lumbering dig): one roll of the Hit
## Chance table — which may pay nothing; the guaranteed haul waits for the break.
func resolve_harvest(node: HarvestNode, notify: bool = true) -> Dictionary:
	var mods = get_gather_modifiers(node)

	var gains: Dictionary = {}
	if is_breakable(node):
		var hit = roll_chance_table(node.hit_pool)
		if hit:
			var amount = randi_range(hit.min_amount, maxi(hit.min_amount, hit.max_amount))
			if mods.double_chance > 0.0 and randf() < mods.double_chance:
				amount *= 2
			gains[hit.item.id] = amount
	else:
		gains = _roll_loot(node.common_pool, node.rare_chance + mods.rare_add, node.rare_pool, mods.double_chance)
	_bank_gains(gains, notify)

	add_xp(get_skill_key(node), node.base_xp * mods.xp_mult)
	harvest_completed.emit(node.id)
	return gains

## Resolves a node breaking (its health hitting zero): one GUARANTEED roll
## of the Break table. No XP — the hits that broke it already paid theirs.
func resolve_break(node: HarvestNode, notify: bool = true) -> Dictionary:
	var gains: Dictionary = {}
	var haul = roll_drop_table(node.break_pool)
	if haul:
		gains[haul.item.id] = randi_range(haul.min_amount, maxi(haul.min_amount, haul.max_amount))
	_bank_gains(gains, notify)
	node_broken.emit(node.id)
	return gains

# --- Offline progress -------------------------------------------------
# "The grounds don't sleep." When the player returns, whatever node they left
# running is worked in bulk for the (capped) elapsed time. This runs the loot
# math directly instead of resolve_harvest so it banks ONCE and never fires a
# UI refresh per harvest. Minion/structure "grounds_yield_pct" bonuses stretch
# the effective time worked.

## Simulates `seconds` of offline harvesting on `node`. Banks the haul in one
## pass and grants the XP. Returns { gains, xp, harvests, seconds }.
func accrue_offline(node: HarvestNode, seconds: float) -> Dictionary:
	var dur = get_effective_duration(node)
	if dur <= 0.0:
		return {}
	var mods = get_gather_modifiers(node)
	var yield_pct = MinionManager.get_passive_bonus(Ids.EFFECT_GROUNDS_YIELD_PCT) \
		+ GroundsManager.get_bonus(Ids.EFFECT_GROUNDS_YIELD_PCT)
	var effective = seconds * (1.0 + yield_pct / 100.0)
	var harvests = int(effective / dur)
	if harvests <= 0:
		return {}

	var gains: Dictionary = {}
	var xp_total := 0.0
	var damage := 0.0
	var per_hit := per_hit_damage(node)
	for i in range(harvests):
		if is_breakable(node):
			var hit = roll_chance_table(node.hit_pool)
			if hit:
				var amt = randi_range(hit.min_amount, maxi(hit.min_amount, hit.max_amount))
				if mods.double_chance > 0.0 and randf() < mods.double_chance:
					amt *= 2
				gains[hit.item.id] = gains.get(hit.item.id, 0) + amt
			damage += per_hit
			if damage >= 0.999:
				var haul = roll_drop_table(node.break_pool)
				if haul:
					gains[haul.item.id] = gains.get(haul.item.id, 0) \
						+ randi_range(haul.min_amount, maxi(haul.min_amount, haul.max_amount))
				damage = 0.0
		else:
			var loot = _roll_loot(node.common_pool, node.rare_chance + mods.rare_add, node.rare_pool, mods.double_chance)
			for item_id in loot:
				gains[item_id] = gains.get(item_id, 0) + loot[item_id]
		xp_total += node.base_xp * mods.xp_mult

	# Bank in one pass, then grant the XP once. Overflow past a full pack is
	# lost (a reason to raise the Ossuary) but COUNTED, so the welcome-back
	# summary can say so instead of losing it silently.
	var lost := 0
	for item_id in gains:
		var item = find_item_by_id(item_id)
		if item:
			var overflow = InventoryManager.add_item(item, gains[item_id])
			if overflow > 0:
				lost += overflow
				gains[item_id] -= overflow
	add_xp(get_skill_key(node), xp_total)
	return {"gains": gains, "xp": xp_total, "harvests": harvests, "seconds": seconds, "lost": lost}
