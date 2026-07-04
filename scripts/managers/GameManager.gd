# GameManager.gd
extends Node

@export_group("Game Meta")
@export var game_title: String = "Graveyard Shift"
@export var game_version: String = "0.1.5"
@export var game_author: String = "Matthew"

@export_group("Inventory & Equipment")
@export var inventory: Array[Item] = [] 
@export var active_tool: ToolData = null

const PATH_SHOVEL = "res://data/items/tools/rusty_shovel.tres"
const PATH_HATCHET = "res://data/items/tools/rusty_hatchet.tres"
const PATH_PICKAXE = "res://data/items/tools/rusty_pickaxe.tres"

var active_action_source: Node = null

var bones: float = 0.0
var flesh: float = 0.0
var ectoplasm: float = 0.0
var gold_coins: int = 0
var wood_logs: float = 0.0
var tree_sap: float = 0.0
var stone: float = 0.0
var opal_gem: float = 0.0

enum SkillType { GRAVEROBBING, LUMBERING, SPELUNKING }

var skills: Dictionary = {
	"graverobbing": {"level": 1, "xp": 0.0},
	"necromancy": {"level": 1, "xp": 0.0},
	"lumbering": {"level": 1, "xp": 0.0},
	"spelunking": {"level": 1, "xp": 0.0}
}

var buy_amount: int = 1
const BASE_GRAVE_DURATION: float = 10.0 
var current_grave_duration: float = 10.0
const BASE_TREE_DURATION: float = 10.0
var current_tree_duration: float = 10.0
const BASE_QUARRY_DURATION: float = 10.0
var current_quarry_duration: float = 10.0

var minions: Array[Dictionary] = [
	{"id": "skeleton", "name": "Skeleton", "cost_bones": 3.0, "cost_ectoplasm": 0.0, "production": 0.2, "multiplier": 1.15, "count": 0, "unlocked": true, "req_necro_level": 1},
	{"id": "zombie", "name": "Zombie", "cost_bones": 5.0, "cost_flesh": 10.0, "production": 0.5, "multiplier": 1.15, "count": 0, "unlocked": false, "req_necro_level": 3},
	{"id": "hound", "name": "Undead Hound", "cost_bones": 3.0, "cost_flesh": 5.0, "production": 0.2, "multiplier": 1.15, "count": 0, "unlocked": false, "req_necro_level": 5},
	{"id": "wraith", "name": "Wraith", "cost_ectoplasm": 10.0, "production": 0.3, "multiplier": 1.15, "count": 0, "unlocked": false, "req_necro_level": 8}
]

func _ready() -> void:
	call_deferred("_setup_starting_equipment")
	recalculate_all_speeds()

func add_tool_to_inventory(tool: ToolData) -> void:
	if not inventory.has(tool):
		inventory.append(tool)
		InventoryManager.add_tool(tool)
		get_tree().call_group("ui_updates", "update_ui")

func _setup_starting_equipment() -> void:
	var shovel = load(PATH_SHOVEL)
	var hatchet = load(PATH_HATCHET)
	var pickaxe = load(PATH_PICKAXE)
	
	if shovel: add_tool_to_inventory(shovel)
	if hatchet: add_tool_to_inventory(hatchet)
	if pickaxe: add_tool_to_inventory(pickaxe)
	
	if shovel: set_active_tool(shovel)

func set_active_tool(tool: ToolData) -> void:
	if inventory.has(tool):
		active_tool = tool
		recalculate_all_speeds()
		get_tree().call_group("ui_updates", "update_ui")
	else:
		push_warning("Attempted to equip item not in inventory!")

func recalculate_all_speeds() -> void:
	var grave_skill_mod = 1.0 + (skills["graverobbing"]["level"] * 0.02)
	current_grave_duration = BASE_GRAVE_DURATION / (_get_bonus(ToolData.ToolType.SHOVEL) * grave_skill_mod)
	var lumber_skill_mod = 1.0 + (skills["lumbering"]["level"] * 0.02)
	current_tree_duration = BASE_TREE_DURATION / (_get_bonus(ToolData.ToolType.HATCHET) * lumber_skill_mod)
	var spelunk_skill_mod = 1.0 + (skills["spelunking"]["level"] * 0.02)
	current_quarry_duration = BASE_QUARRY_DURATION / (_get_bonus(ToolData.ToolType.PICKAXE) * spelunk_skill_mod)

func _get_bonus(type_enum: ToolData.ToolType) -> float:
	if active_tool and active_tool.tool_type == type_enum:
		return active_tool.speed_multiplier
	return 1.0

func get_xp_needed(level: int) -> float:
	return floor(100.0 * pow(float(level), 1.5))

func add_xp(skill_name: String, amount: float) -> void:
	if not skills.has(skill_name): return
	var skill = skills[skill_name]
	skill["xp"] += amount
	var xp_needed = get_xp_needed(skill["level"])
	while skill["xp"] >= xp_needed:
		skill["xp"] -= xp_needed
		skill["level"] += 1
		if skill_name == "necromancy": calculate_necromancy_unlocks()
		xp_needed = get_xp_needed(skill["level"])
	recalculate_all_speeds()
	get_tree().call_group("ui_updates", "update_ui")

func calculate_necromancy_unlocks() -> void:
	for minion in minions:
		if skills["necromancy"]["level"] >= minion.get("req_necro_level", 1):
			minion["unlocked"] = true

func register_activity(calling_node: Node) -> bool:
	if active_action_source == calling_node:
		active_action_source = null
		get_tree().call_group("ui_updates", "update_ui")
		return false
	active_action_source = calling_node
	get_tree().call_group("ui_updates", "update_ui")
	return true

func get_bulk_cost(minion: Dictionary, amount: int) -> Dictionary:
	var total_bones = 0; var total_flesh = 0; var total_ectoplasm = 0
	var temp_bones = minion.get("cost_bones", 0)
	var temp_flesh = minion.get("cost_flesh", 0)
	var temp_ecto = minion.get("cost_ectoplasm", 0)
	var multiplier = minion.get("multiplier", 1.15)
	for i in range(amount):
		total_bones += temp_bones
		total_flesh += temp_flesh
		total_ectoplasm += temp_ecto
		temp_bones = ceil(temp_bones * multiplier)
		temp_flesh = ceil(temp_flesh * multiplier)
		temp_ecto = ceil(temp_ecto * multiplier)
	return {"bones": total_bones, "flesh": total_flesh, "ectoplasm": total_ectoplasm}
