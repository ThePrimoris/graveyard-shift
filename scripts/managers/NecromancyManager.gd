extends Node

signal necromancy_updated # Broadcasts to the UI when levels, progress, or essence changes

# --- Configurable Path ---
const MINION_RESOURCES_PATH = "res://data/minions/"

# --- Core Currencies ---
var essence: int = 0

# --- Auto-Populated Runtime Storage ---
var minion_templates: Array[Minion] = []
var minion_progress: Dictionary = {}

# --- Altar Sacrifice Conversion Values ---
# Defines how much Necromancy XP and Essence 1 unit of an item gives when sacrificed
var sacrifice_values: Dictionary = {
	"bone": {"xp": 2.0, "essence": 1},
	"flesh": {"xp": 4.0, "essence": 2},
	"ectoplasm": {"xp": 8.0, "essence": 5}
}

func _ready() -> void:
	_auto_load_minion_resources()
	_initialize_minion_tracking()

## Scans the resources directory and loads all Minion resources automatically
func _auto_load_minion_resources() -> void:
	minion_templates.clear()
	
	if not DirAccess.dir_exists_absolute(MINION_RESOURCES_PATH):
		push_error("NecromancyManager: Target directory does not exist: " + MINION_RESOURCES_PATH)
		return
		
	var dir = DirAccess.open(MINION_RESOURCES_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				# Avoid reading .remap files in exported release builds
				var clean_name = file_name.replace(".remap", "")
				var full_path = MINION_RESOURCES_PATH + clean_name
				var resource = load(full_path)
				
				if resource is Minion:
					minion_templates.append(resource)
					
			file_name = dir.get_next()
		dir.list_dir_end()
		
		# Keep cards alphabetically or numerically ordered by internal ID string
		minion_templates.sort_custom(func(a, b): return a.id < b.id)
		print("NecromancyManager: Successfully auto-loaded %d minion profiles." % minion_templates.size())
	else:
		push_error("NecromancyManager: Failed to open directory at: " + MINION_RESOURCES_PATH)

## Sets up dynamic run-time trackers (levels and materials fed) based on loaded items
func _initialize_minion_tracking() -> void:
	minion_progress.clear()
	for minion in minion_templates:
		if not minion: continue
		
		var item_progress: Dictionary = {}
		for item_id in minion.requirements:
			if minion.requirements[item_id] > 0:
				item_progress[item_id] = 0
				
		minion_progress[minion.id] = {
			"level": 1,
			"progress": item_progress
		}

# --- Scaled Requirement & Stat Getters ---

func get_required_amount(minion: Minion, item_id: String, current_level: int) -> int:
	var base = minion.requirements.get(item_id, 0)
	return int(base * pow(current_level, 1.2))

func get_minion_hp(minion_id: String) -> int:
	var minion = _find_template(minion_id)
	if not minion or not minion_progress.has(minion_id): return 0
	var current_lvl = minion_progress[minion_id]["level"]
	return minion.base_hp + ((current_lvl - 1) * minion.hp_per_level)

func get_minion_atk(minion_id: String) -> float:
	var minion = _find_template(minion_id)
	if not minion or not minion_progress.has(minion_id): return 0.0
	var current_lvl = minion_progress[minion_id]["level"]
	return minion.base_atk + ((current_lvl - 1) * minion.atk_per_level)

# --- Core Gameplay Functionality ---

## 1. Ritual Altar Sacrifice Logic
func sacrifice_resource(item_id: String, amount: int) -> bool:
	if not sacrifice_values.has(item_id): return false
	
	var current_count = InventoryManager.get_item_count(item_id)
	if current_count < amount: return false
	
	InventoryManager.remove_item(item_id, amount)
	
	var total_xp = sacrifice_values[item_id]["xp"] * amount
	var total_essence = sacrifice_values[item_id]["essence"] * amount
	
	essence += total_essence
	GameManager.add_xp("necromancy", total_xp)
	
	necromancy_updated.emit()
	get_tree().call_group("ui_updates", "update_ui")
	return true

## 2. Material Feeding Progress Bar Logic
func feed_material_to_minion(minion_id: String, item_id: String, amount: int) -> void:
	var minion = _find_template(minion_id)
	if not minion or not minion_progress.has(minion_id): return
	
	var state = minion_progress[minion_id]
	if not state["progress"].has(item_id): return
	
	var available = InventoryManager.get_item_count(item_id)
	var current_lvl = state["level"]
	var max_needed = get_required_amount(minion, item_id, current_lvl)
	var current_filled = state["progress"][item_id]
	
	var room_left = max_needed - current_filled
	if room_left <= 0: return
	
	var amount_to_spend = mini(amount, mini(available, int(room_left)))
	if amount_to_spend <= 0: return
	
	InventoryManager.remove_item(item_id, amount_to_spend)
	state["progress"][item_id] += amount_to_spend
	
	_check_level_up(minion, state)
	
	necromancy_updated.emit()
	get_tree().call_group("ui_updates", "update_ui")

func _check_level_up(minion: Minion, state: Dictionary) -> void:
	var current_lvl = state["level"]
	var all_requirements_met = true
	
	for item_id in minion.requirements:
		if minion.requirements[item_id] > 0:
			var needed = get_required_amount(minion, item_id, current_lvl)
			if state["progress"][item_id] < needed:
				all_requirements_met = false
				break
				
	if all_requirements_met:
		# Consume item totals allocated to this level bracket milestone
		for item_id in minion.requirements:
			if minion.requirements[item_id] > 0:
				var needed = get_required_amount(minion, item_id, current_lvl)
				state["progress"][item_id] -= needed
				
		state["level"] += 1
		
		# Award global Necromancy XP based on minion scaling weight
		var xp_reward = (minion.base_hp + minion.base_atk) * state["level"]
		GameManager.add_xp("necromancy", xp_reward)
		
		# Recursively call check again to catch bulk multi-level dumps safely
		_check_level_up(minion, state)

func _find_template(minion_id: String) -> Minion:
	for m in minion_templates:
		if m and m.id == minion_id: return m
	return null