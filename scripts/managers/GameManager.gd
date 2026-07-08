# GameManager.gd
extends Node

signal harvest_completed(node_id: String)

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
	"res://data/items/tools/"
]
const NODE_DIRS: Array[String] = [
	"res://data/nodes/graves/",
	"res://data/nodes/trees/",
	"res://data/nodes/mines/"
]

var active_action_source: Node = null
var active_node_data: HarvestNode = null

var gold_coins: int = 0

# Auto-populated registries so any system can look content up by id.
var item_db: Dictionary = {}          # item_id -> Item resource
var node_db: Dictionary = {}          # node_id -> HarvestNode resource
var nodes_by_skill: Dictionary = {}   # skill_key -> Array[HarvestNode]

enum SkillType { GRAVEROBBING, LUMBERING, SPELUNKING }

const MAX_LEVEL: int = 100

var skills: Dictionary = {
	"graverobbing": {"level": 1, "xp": 0.0},
	"lumbering": {"level": 1, "xp": 0.0},
	"spelunking": {"level": 1, "xp": 0.0}
}

func _ready() -> void:
	_build_item_database()
	_build_node_registry()
	call_deferred("_setup_starting_equipment")

## Wipes all run progress back to a fresh start (used by the Settings hard reset).
func reset_state() -> void:
	gold_coins = 0
	active_action_source = null
	active_node_data = null
	inventory.clear()
	equipped_tools.clear()
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
	nodes_by_skill.clear()
	for dir_path in NODE_DIRS:
		for res in _load_resources_in_dir(dir_path):
			if res is HarvestNode and res.id != "":
				node_db[res.id] = res
				var skill_key = get_skill_key(res)
				if not nodes_by_skill.has(skill_key):
					nodes_by_skill[skill_key] = []
				nodes_by_skill[skill_key].append(res)

func _load_resources_in_dir(dir_path: String) -> Array:
	var result: Array = []
	var dir = DirAccess.open(dir_path)
	if not dir:
		push_warning("GameManager: Could not open resource directory: " + dir_path)
		return result
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res = load(dir_path + file_name.replace(".remap", ""))
			if res:
				result.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result

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
		get_tree().call_group("ui_updates", "update_ui")

func _setup_starting_equipment() -> void:
	for path in [PATH_SHOVEL, PATH_HATCHET, PATH_PICKAXE]:
		var tool = load(path)
		if tool:
			add_tool_to_inventory(tool)
			equipped_tools[tool.tool_type] = tool

func get_equipped_tool(type_enum: int) -> ToolData:
	return equipped_tools.get(type_enum, null)

func owns_tool(tool_id: String) -> bool:
	for t in inventory:
		if t is ToolData and t.id == tool_id:
			return true
	return false

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
	get_tree().call_group("ui_updates", "update_ui")
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
	get_tree().call_group("ui_updates", "update_ui")
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
	get_tree().call_group("ui_updates", "update_ui")
	return true

func get_tool_bonus(type_enum: ToolData.ToolType) -> float:
	var tool = equipped_tools.get(type_enum, null)
	if tool: return tool.speed_multiplier
	return 1.0

## The real time one harvest of this node takes, after tool speed and skill level.
func get_effective_duration(node: HarvestNode) -> float:
	var skill_key = get_skill_key(node)
	var skill_mod = 1.0 + (skills[skill_key]["level"] * 0.02)
	return node.base_duration / (get_tool_bonus(node.required_tool_type) * skill_mod)

# --- Skills / XP ---

## XP to advance FROM `level`, on the classic RuneScape/Melvor curve.
func get_xp_needed(level: int) -> float:
	return floor((level + 300.0 * pow(2.0, level / 7.0)) / 4.0)

func add_xp(skill_name: String, amount: float) -> void:
	if not skills.has(skill_name): return
	var skill = skills[skill_name]
	if skill["level"] >= MAX_LEVEL: return
	skill["xp"] += amount
	var xp_needed = get_xp_needed(skill["level"])
	while skill["xp"] >= xp_needed and skill["level"] < MAX_LEVEL:
		skill["xp"] -= xp_needed
		skill["level"] += 1
		xp_needed = get_xp_needed(skill["level"])
	if skill["level"] >= MAX_LEVEL:
		skill["xp"] = 0.0
	get_tree().call_group("ui_updates", "update_ui")

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
		get_tree().call_group("ui_updates", "update_ui")
		return false
	active_action_source = calling_node
	active_node_data = node_data
	get_tree().call_group("ui_updates", "update_ui")
	return true

# --- Harvest Resolution ---
# One code path resolves every harvest, so future bonuses apply consistently.

## Resolves a completed harvest of `node`. Returns { item_id: amount } gained.
## Every loot pool entry rolls independently against its own chance.
func resolve_harvest(node: HarvestNode, notify: bool = true) -> Dictionary:
	var gains: Dictionary = {}

	var yield_bonus = 0
	var equipped = get_equipped_tool(node.required_tool_type)
	if equipped:
		yield_bonus = equipped.yield_bonus

	var entries = node.loot_pool.slice(0, HarvestNode.MAX_LOOT_ENTRIES)
	for entry in entries:
		if entry == null or entry.item == null or entry.chance <= 0.0:
			continue
		if randf() <= entry.chance:
			var amount = 1
			# Tool yield bonuses boost the guaranteed core drops, not rare finds
			if entry.chance >= 1.0:
				amount += yield_bonus
			gains[entry.item.id] = gains.get(entry.item.id, 0) + amount

	for item_id in gains:
		var item = find_item_by_id(item_id)
		if item:
			InventoryManager.add_item(item, gains[item_id])
			if notify:
				NotificationManager.show_item(item.name, gains[item_id], item)

	add_xp(get_skill_key(node), node.base_xp)
	harvest_completed.emit(node.id)
	return gains
