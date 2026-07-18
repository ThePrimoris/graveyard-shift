# GroundsManager.gd
# The Grounds: buildable graveyard structures, the game's big material sink.
# Each structure is a tiered upgrade track; every built tier adds its magnitude
# to the structure's effect. Other systems read those effects here:
#   harvest bonuses -> GameManager.get_gather_modifiers (xp / double / rare)
#   storage         -> InventoryManager.refresh_capacity
extends Node

signal grounds_updated

const STRUCTURE_DIRS: Array[String] = ["res://data/structures/"]
const PARCEL_DIRS: Array[String] = ["res://data/parcels/"]

## structure_id -> Structure resource, auto-loaded from STRUCTURE_DIRS.
var structure_db: Dictionary = {}

## structure_id -> current level (0 = unbuilt, up to structure.max_level()).
var levels: Dictionary = {}

## parcel_id -> GroundsParcel resource, auto-loaded from PARCEL_DIRS.
var parcel_db: Dictionary = {}

## parcel_id -> true for parcels bought this run (free land needs no entry).
var unlocked_parcels: Dictionary = {}

func _ready() -> void:
	_build_structure_database()
	_build_parcel_database()

func reset_state() -> void:
	levels.clear()
	unlocked_parcels.clear()
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
			# Exported builds list text resources as "<name>.tres.remap".
			var res_file = file_name.trim_suffix(".remap")
			if not dir.current_is_dir() and res_file.ends_with(".tres"):
				var res = load(dir_path + res_file)
				if res is Structure and res.id != "":
					structure_db[res.id] = res
			file_name = dir.get_next()
		dir.list_dir_end()

func _build_parcel_database() -> void:
	parcel_db.clear()
	for dir_path in PARCEL_DIRS:
		var dir = DirAccess.open(dir_path)
		if not dir:
			push_warning("GroundsManager: Could not open resource directory: " + dir_path)
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var res_file = file_name.trim_suffix(".remap")
			if not dir.current_is_dir() and res_file.ends_with(".tres"):
				var res = load(dir_path + res_file)
				if res is GroundsParcel and res.id != "":
					parcel_db[res.id] = res
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

## The tier that would be built NEXT, or null when already maxed.
func next_tier(structure_id: String) -> StructureTier:
	var s = find_structure(structure_id)
	if s == null: return null
	var lvl = get_level(structure_id)
	if lvl >= s.max_level(): return null
	return s.tiers[lvl]

# --- Parcels (the land itself) ---

## Parcel ids in display order (sort_order, then name).
func sorted_parcel_ids() -> Array:
	var ids: Array = parcel_db.keys()
	ids.sort_custom(func(a, b):
		var pa: GroundsParcel = parcel_db[a]
		var pb: GroundsParcel = parcel_db[b]
		if pa.sort_order != pb.sort_order:
			return pa.sort_order < pb.sort_order
		return pa.name < pb.name)
	return ids

func find_parcel(parcel_id: String) -> GroundsParcel:
	return parcel_db.get(parcel_id, null)

## Free land is always unlocked; priced land must have been bought.
func is_parcel_unlocked(parcel_id: String) -> bool:
	var p: GroundsParcel = find_parcel(parcel_id)
	if p == null: return false
	return p.cost_gold <= 0 or unlocked_parcels.has(parcel_id)

func can_afford_parcel(parcel_id: String) -> bool:
	var p: GroundsParcel = find_parcel(parcel_id)
	return p != null and not is_parcel_unlocked(parcel_id) and GameManager.gold_coins >= p.cost_gold

## Buys a locked parcel outright (gold only).
func buy_parcel(parcel_id: String) -> bool:
	if not can_afford_parcel(parcel_id):
		return false
	var p: GroundsParcel = find_parcel(parcel_id)
	GameManager.gold_coins -= p.cost_gold
	unlocked_parcels[parcel_id] = true
	NotificationManager.show_item("The grounds grow — %s surveyed" % p.name, 1)
	AudioManager.play_sfx(Ids.SFX_BUILD)
	grounds_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## The parcel a structure stands on (by its anchor cell), or null for none.
func parcel_for_structure(structure_id: String) -> GroundsParcel:
	var s = find_structure(structure_id)
	if s == null: return null
	for parcel_id in parcel_db:
		if parcel_db[parcel_id].contains_cell(s.grid_cell):
			return parcel_db[parcel_id]
	return null

## True when the structure's land is owned, so its tiers may be raised.
func is_structure_land_owned(structure_id: String) -> bool:
	var p := parcel_for_structure(structure_id)
	# Structures on no parcel (should not happen; validator guards) stay buildable.
	return p == null or is_parcel_unlocked(p.id)

# --- Building ---

func can_afford(structure_id: String) -> bool:
	var tier = next_tier(structure_id)
	if tier == null: return false
	if not is_structure_land_owned(structure_id):
		return false
	if GameManager.gold_coins < tier.gold:
		return false
	for item_id in tier.cost:
		if InventoryManager.get_item_count(item_id) < tier.cost[item_id]:
			return false
	return true

## Pays the next tier's cost (materials + gold) and raises the structure a level.
func build(structure_id: String) -> bool:
	var tier = next_tier(structure_id)
	if tier == null or not can_afford(structure_id):
		return false
	GameManager.gold_coins -= tier.gold
	for item_id in tier.cost:
		if tier.cost[item_id] > 0:
			InventoryManager.remove_item(item_id, tier.cost[item_id])
	levels[structure_id] = get_level(structure_id) + 1
	var s = find_structure(structure_id)
	if s:
		NotificationManager.show_item("%s raised to tier %d" % [s.name, get_level(structure_id)], 1)
	AudioManager.play_sfx(Ids.SFX_BUILD)
	grounds_updated.emit()
	# Storage structures may have just grown the backpack.
	InventoryManager.refresh_capacity()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Debug-only: set a structure straight to `level`, ignoring cost. Used by the
## console (`grounds raise|max|reset`) to preview tiers without grinding.
func debug_set_level(structure_id: String, level: int) -> int:
	var s = find_structure(structure_id)
	if s == null:
		return -1
	levels[structure_id] = clampi(level, 0, s.max_level())
	grounds_updated.emit()
	InventoryManager.refresh_capacity()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return get_level(structure_id)

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
	return int(round(get_bonus(Ids.EFFECT_INVENTORY_SLOTS)))

# --- Save / Load ---

func get_save_data() -> Dictionary:
	return {"levels": levels.duplicate(), "parcels": unlocked_parcels.keys()}

func restore_from_save(data: Dictionary) -> void:
	levels.clear()
	var saved = data.get("levels", {})
	for structure_id in saved:
		if structure_db.has(structure_id):
			var s: Structure = structure_db[structure_id]
			levels[structure_id] = clampi(int(saved[structure_id]), 0, s.max_level())
	unlocked_parcels.clear()
	for parcel_id in data.get("parcels", []):
		if parcel_db.has(parcel_id):
			unlocked_parcels[parcel_id] = true
	# Migration: saves from before parcels existed may hold structures standing
	# on land they never bought — grandfather that land in for free.
	for structure_id in levels:
		if levels[structure_id] > 0:
			var p := parcel_for_structure(structure_id)
			if p != null and not is_parcel_unlocked(p.id):
				unlocked_parcels[p.id] = true
	grounds_updated.emit()
	InventoryManager.refresh_capacity()
