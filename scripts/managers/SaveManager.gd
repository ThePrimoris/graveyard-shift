# SaveManager.gd
# Persists the run to disk. Fresh-slate save format (version 2).
extends Node

const SAVE_PATH: String = "user://graveyard_shift_save.json"
const SAVE_VERSION: int = 2
const AUTOSAVE_INTERVAL: float = 30.0

var _autosave_accum: float = 0.0
var _loaded: bool = false

func _ready() -> void:
	call_deferred("_late_init")

func _late_init() -> void:
	await get_tree().process_frame
	load_game()
	_loaded = true
	# First run (or wiped save): Mortimer takes it from here
	TutorialManager.maybe_start()

func _process(delta: float) -> void:
	if not _loaded: return
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _loaded:
		save_game()

## Deletes the save and resets every manager to a brand-new game.
func hard_reset() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	InventoryManager.reset_state()
	GameManager.reset_state()
	MinionManager.reset_state()
	TutorialManager.reset_state()
	save_game()
	get_tree().call_group("ui_updates", "update_ui")
	NotificationManager.show_item("Progress reset — fresh graveyard", 1)

# --- Saving ---

func save_game() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"gold": GameManager.gold_coins,
		"skills": GameManager.skills,
		"equipped_tools": _get_equipped_tool_ids(),
		"owned_tools": _get_owned_tool_ids(),
		"active_node_id": GameManager.active_node_data.id if GameManager.active_node_data else "",
		"purchased_slots": InventoryManager.purchased_slots,
		"tutorial_complete": TutorialManager.tutorial_complete,
		"inventory": InventoryManager.get_save_data(),
		"minions": MinionManager.get_save_data()
	}

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Could not open save file for writing.")
		return
	file.store_string(JSON.stringify(data))
	file.close()

func _get_owned_tool_ids() -> Array:
	var ids: Array = []
	for t in GameManager.inventory:
		if t is ToolData:
			ids.append(t.id)
	return ids

func _get_equipped_tool_ids() -> Dictionary:
	var result: Dictionary = {}
	for type_enum in GameManager.equipped_tools:
		var tool = GameManager.equipped_tools[type_enum]
		if tool:
			result[str(type_enum)] = tool.id
	return result

# --- Loading ---

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed == null or not (parsed is Dictionary):
		push_warning("SaveManager: Save file was unreadable; starting fresh.")
		return

	var data: Dictionary = parsed

	# Pre-reboot saves are incompatible with the fresh slate: start over.
	if int(data.get("version", 1)) < SAVE_VERSION:
		push_warning("SaveManager: Old save format detected; starting fresh.")
		return

	GameManager.gold_coins = int(data.get("gold", 0))

	var saved_skills = data.get("skills", {})
	for skill_name in saved_skills:
		if GameManager.skills.has(skill_name):
			GameManager.skills[skill_name]["level"] = int(saved_skills[skill_name].get("level", 1))
			GameManager.skills[skill_name]["xp"] = float(saved_skills[skill_name].get("xp", 0.0))

	GameManager.inventory.clear()
	for tool_id in data.get("owned_tools", []):
		var tool = GameManager.find_item_by_id(tool_id)
		if tool is ToolData:
			GameManager.inventory.append(tool)

	var saved_equipped = data.get("equipped_tools", {})
	GameManager.equipped_tools.clear()
	for type_key in saved_equipped:
		var tool = GameManager.find_item_by_id(saved_equipped[type_key])
		if tool is ToolData and GameManager.inventory.has(tool):
			GameManager.equipped_tools[int(type_key)] = tool

	InventoryManager.purchased_slots = int(data.get("purchased_slots", 0))
	TutorialManager.tutorial_complete = bool(data.get("tutorial_complete", false))
	InventoryManager.restore_from_save(data.get("inventory", []))
	InventoryManager.refresh_capacity()
	MinionManager.restore_from_save(data.get("minions", {}))
	_ensure_default_equipment()

	# Pick the previous node back up so the player doesn't have to re-click it
	var last_node_id = str(data.get("active_node_id", ""))
	if last_node_id != "":
		get_tree().call_group("harvest_views", "resume_node", last_node_id)

	get_tree().call_group("ui_updates", "update_ui")

## Fills any empty equipment slot with an owned tool of that type,
## and makes sure no tool sits in both an equipment slot and the grid.
func _ensure_default_equipment() -> void:
	for t in GameManager.inventory:
		if not (t is ToolData): continue
		if GameManager.equipped_tools.get(t.tool_type, null) == null:
			GameManager.equipped_tools[t.tool_type] = t
	for type_enum in GameManager.equipped_tools:
		var tool = GameManager.equipped_tools[type_enum]
		if tool and InventoryManager.get_item_count(tool.id) > 0:
			InventoryManager.remove_item(tool.id, 1)
