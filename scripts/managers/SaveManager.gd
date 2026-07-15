# SaveManager.gd
# Persists the run to disk (save format v2). Old saves are UPGRADED forward by
# _migrate rather than discarded, so a SAVE_VERSION bump no longer wipes
# progress; a save from a NEWER build than this one is backed up, not clobbered.
extends Node

const SAVE_PATH: String = "user://graveyard_shift_save.json"
const SAVE_VERSION: int = 2
const AUTOSAVE_INTERVAL: float = 30.0

## Offline progress: free window everyone gets, plus a minimum gap before it's
## worth granting. The Grave-Lantern structure extends the cap (offline_hours).
const OFFLINE_BASE_HOURS: float = 1.0
const OFFLINE_MIN_SECONDS: float = 60.0

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
	GroundsManager.reset_state()
	TutorialManager.reset_state()
	save_game()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
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
		"minions": MinionManager.get_save_data(),
		"grounds": GroundsManager.get_save_data()
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
	var from_version := int(data.get("version", 1))

	# A save written by a NEWER build than this one. Its fields may have changed
	# meaning, so reading it could corrupt the run — and letting the game start
	# fresh would let the next autosave overwrite it. Preserve it, then start fresh.
	if from_version > SAVE_VERSION:
		_backup_save("newer")
		push_warning("SaveManager: save is from a newer version (v%d > v%d); backed up a copy and starting fresh." \
			% [from_version, SAVE_VERSION])
		return

	# An OLDER save: upgrade it field-by-field instead of throwing it away.
	var migrated_now := false
	if from_version < SAVE_VERSION:
		var upgraded := _migrate(data, from_version)
		if upgraded.is_empty():
			push_warning("SaveManager: a v%d save can't be carried forward; starting fresh." % from_version)
			return
		data = upgraded
		migrated_now = true
		push_warning("SaveManager: migrated save from v%d to v%d." % [from_version, SAVE_VERSION])

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
	GroundsManager.restore_from_save(data.get("grounds", {}))
	_ensure_default_equipment()

	# Pick the previous node back up so the player doesn't have to re-click it
	var last_node_id = str(data.get("active_node_id", ""))
	if last_node_id != "":
		get_tree().call_group(Ids.GROUP_HARVEST_VIEWS, "resume_node", last_node_id)
		_accrue_offline(last_node_id, int(data.get("timestamp", 0)))

	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

	# Persist the upgraded save so the file itself moves to the current format
	# now, rather than waiting for the next autosave (which might not come if the
	# game closes first).
	if migrated_now:
		save_game()

# --- Save migration ----------------------------------------------------
# Old saves are UPGRADED, not discarded. Each SAVE_VERSION bump adds exactly one
# _migrate_v<N>_to_v<N+1> step; _migrate chains them from the save's version up
# to the current one. A step returns {} to signal "unrecoverable — start fresh".
# To add the next version: bump SAVE_VERSION, write _migrate_v2_to_v3, and add a
# `2:` case to the match below. The loaders already default any missing field
# (via .get), so a step only needs to handle fields that MOVED or CHANGED shape.

## Upgrades a parsed save dict from `from_version` up to SAVE_VERSION. Returns
## the migrated dict, or {} when the save can't be carried forward (the caller
## then starts fresh). Pure — no side effects — so it is unit-testable.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var migrated: Dictionary = data.duplicate(true)
	var v := from_version
	while v < SAVE_VERSION:
		match v:
			1:
				migrated = _migrate_v1_to_v2(migrated)
			# 2:
			#     migrated = _migrate_v2_to_v3(migrated)   # <- next bump slots in here
			_:
				push_warning("SaveManager: no migration step for v%d." % v)
				return {}
		if migrated.is_empty():
			return {}
		v += 1
		migrated["version"] = v
	return migrated

## v1 (pre-reboot) → v2. The reboot replaced the skill set, item ids, and node
## ids wholesale, so a v1 save has nothing that maps cleanly onto v2 — it is
## intentionally unrecoverable. Kept as an explicit step (rather than a blanket
## discard) so the migration chain is complete and the decision is documented.
func _migrate_v1_to_v2(_data: Dictionary) -> Dictionary:
	return {}

## Copies the current save to a timestamped .bak so an incompatible file (e.g. a
## save from a newer build) is never silently overwritten.
func _backup_save(reason: String) -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var stamp := str(int(Time.get_unix_time_from_system()))
	var backup_path := "%s.%s.%s.bak" % [SAVE_PATH, reason, stamp]
	var err := DirAccess.copy_absolute(SAVE_PATH, backup_path)
	if err != OK:
		push_warning("SaveManager: could not back up save (error %d)." % err)

## Grants offline harvesting for the node the player left running, capped by
## the base window plus any Grave-Lantern tiers built.
func _accrue_offline(node_id: String, saved_ts: int) -> void:
	if saved_ts <= 0: return
	var node = GameManager.find_node_by_id(node_id)
	if node == null: return
	var elapsed = Time.get_unix_time_from_system() - float(saved_ts)
	if elapsed < OFFLINE_MIN_SECONDS: return
	var cap_hours = OFFLINE_BASE_HOURS + GroundsManager.get_bonus(Ids.EFFECT_OFFLINE_HOURS)
	var capped = clampf(elapsed, 0.0, cap_hours * 3600.0)

	var result = GameManager.accrue_offline(node, capped)
	if result.is_empty() or int(result.get("harvests", 0)) <= 0: return

	var total_items := 0
	for item_id in result["gains"]:
		total_items += int(result["gains"][item_id])
	NotificationManager.show_item("Welcome back — the grounds worked %s while you were gone: +%d materials, +%d XP" \
		% [_fmt_duration(capped), total_items, int(result["xp"])], 1)

func _fmt_duration(seconds: float) -> String:
	var h = int(seconds) / 3600
	var m = (int(seconds) % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % maxi(m, 1)

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
