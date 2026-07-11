# GroundsManager.gd
# The Grounds: buildable graveyard structures, the game's big material sink.
# Each structure is a tiered upgrade track; every built tier adds its magnitude
# to the structure's effect. Other systems read those effects here:
#   harvest bonuses -> GameManager.get_gather_modifiers (xp / double / rare)
#   storage         -> InventoryManager.refresh_capacity
extends Node

signal grounds_updated

const STRUCTURE_DIRS: Array[String] = ["res://data/structures/"]

## structure_id -> Structure resource, auto-loaded from STRUCTURE_DIRS.
var structure_db: Dictionary = {}

## structure_id -> current level (0 = unbuilt, up to structure.max_level()).
var levels: Dictionary = {}

func _ready() -> void:
	_build_structure_database()

func reset_state() -> void:
	levels.clear()
	grounds_updated.emit()
	InventoryManager.refresh_capacity()

# --- Database ---

func _build_structure_database() -> void:
	structure_db.clear()
	for dir_path in STRUCTURE_DIRS:
		var dir = DirAccess.open(dir_path)
		if not dir:
			push_warning("GroundsManager: Could not open resource directory: " + dir_path)
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var res = load(dir_path + file_name.replace(".remap", ""))
				if res is Structure and res.id != "":
					structure_db[res.id] = res
			file_name = dir.get_next()
		dir.list_dir_end()

## Structure ids in display order (sort_order, then name).
func sorted_ids() -> Array:
	var ids: Array = structure_db.keys()
	ids.sort_custom(func(a, b):
		var sa: Structure = structure_db[a]
		var sb: Structure = structure_db[b]
		if sa.sort_order != sb.sort_order:
			return sa.sort_order < sb.sort_order
		return sa.name < sb.name)
	return ids

func find_structure(structure_id: String) -> Structure:
	return structure_db.get(structure_id, null)

func get_level(structure_id: String) -> int:
	return int(levels.get(structure_id, 0))

func is_max(structure_id: String) -> bool:
	var s = find_structure(structure_id)
	return s != null and get_level(structure_id) >= s.max_level()

## The tier that would be built NEXT, or null when already maxed.
func next_tier(structure_id: String) -> StructureTier:
	var s = find_structure(structure_id)
	if s == null: return null
	var lvl = get_level(structure_id)
	if lvl >= s.max_level(): return null
	return s.tiers[lvl]

# --- Building ---

func can_afford(structure_id: String) -> bool:
	var tier = next_tier(structure_id)
	if tier == null: return false
	for item_id in tier.cost:
		if InventoryManager.get_item_count(item_id) < tier.cost[item_id]:
			return false
	return true

## Pays the next tier's cost and raises the structure a level.
func build(structure_id: String) -> bool:
	var tier = next_tier(structure_id)
	if tier == null or not can_afford(structure_id):
		return false
	for item_id in tier.cost:
		if tier.cost[item_id] > 0:
			InventoryManager.remove_item(item_id, tier.cost[item_id])
	levels[structure_id] = get_level(structure_id) + 1
	var s = find_structure(structure_id)
	if s:
		NotificationManager.show_item("%s raised to tier %d" % [s.name, get_level(structure_id)], 1)
	grounds_updated.emit()
	# Storage structures may have just grown the backpack.
	InventoryManager.refresh_capacity()
	get_tree().call_group("ui_updates", "update_ui")
	return true

# --- Effects (read by the rest of the game) ---

## This structure's own accumulated effect from the tiers built so far.
func get_structure_value(structure_id: String) -> float:
	var s = find_structure(structure_id)
	if s == null: return 0.0
	var total := 0.0
	for i in range(mini(get_level(structure_id), s.tiers.size())):
		total += s.tiers[i].magnitude
	return total

## Cumulative magnitude of an effect across EVERY built structure.
## e.g. get_bonus("harvest_xp_pct") -> 15.0 for +15% harvest XP.
func get_bonus(effect: String) -> float:
	var total := 0.0
	for structure_id in structure_db:
		if structure_db[structure_id].effect == effect:
			total += get_structure_value(structure_id)
	return total

## Extra backpack slots granted by storage structures.
func get_inventory_slot_bonus() -> int:
	return int(round(get_bonus("inventory_slots")))

# --- Save / Load ---

func get_save_data() -> Dictionary:
	return {"levels": levels.duplicate()}

func restore_from_save(data: Dictionary) -> void:
	levels.clear()
	var saved = data.get("levels", {})
	for structure_id in saved:
		if structure_db.has(structure_id):
			var s: Structure = structure_db[structure_id]
			levels[structure_id] = clampi(int(saved[structure_id]), 0, s.max_level())
	grounds_updated.emit()
	InventoryManager.refresh_capacity()
