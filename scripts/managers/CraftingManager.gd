# CraftingManager.gd
# Shared engine for the production skills (P3 Alchemy, P5 Forge): a recipe
# registry plus one timed craft slot on the harvest-progress pattern. Inputs
# are paid when a craft STARTS; the output, skill XP, and a possible
# auto-repeat land when it completes.
#
# Subclasses (autoloads) set `recipe_dirs`, `skill_key`, and optionally
# `speed_effect` (a GroundsManager bonus channel) in _init. Method names keep
# Alchemy's original brew_* vocabulary so existing callers stay untouched;
# read "brew" as "craft" for the Forge.
class_name CraftingManager
extends Node

signal brew_completed(recipe_id: String)
signal brew_state_changed
signal recipe_learned(recipe_id: String)

## Where this skill's Recipe .tres files live. Set by the subclass.
var recipe_dirs: Array[String] = []
## The GameManager.skills key this station levels. Set by the subclass.
var skill_key: String = ""
## Grounds effect id that speeds this station ("" = none).
var speed_effect: String = ""
## SFX played when a craft completes (the station's voice).
var finish_sfx: String = Ids.SFX_BUILD

## recipe_id -> Recipe resource, auto-loaded from recipe_dirs.
var recipe_db: Dictionary = {}

## The recipe currently on the burner/anvil, or null. Inputs already consumed.
var active_recipe: Recipe = null
var brew_progress: float = 0.0
## Scroll-taught recipe ids the player has learned (id -> true). Persisted by
## SaveManager under "known_recipes", keyed by skill_key.
var known_recipe_ids: Dictionary = {}
## When set, a finished craft re-starts itself while inputs last (idle-style).
var auto_repeat: bool = true

func _ready() -> void:
	_build_recipe_database()

func reset_state() -> void:
	active_recipe = null
	brew_progress = 0.0
	known_recipe_ids.clear()
	brew_state_changed.emit()

func _build_recipe_database() -> void:
	recipe_db.clear()
	for dir_path in recipe_dirs:
		var dir = DirAccess.open(dir_path)
		if not dir:
			push_warning("%s: Could not open resource directory: %s" % [name, dir_path])
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# Exported builds list text resources as "<name>.tres.remap".
			var res_file = file_name.trim_suffix(".remap")
			if not dir.current_is_dir() and res_file.ends_with(".tres"):
				var res = load(dir_path + res_file)
				if res is Recipe and res.id != "":
					recipe_db[res.id] = res
			file_name = dir.get_next()
		dir.list_dir_end()

func find_recipe_by_id(recipe_id: String) -> Recipe:
	return recipe_db.get(recipe_id, null)

## Recipe ids in display order: required_level first, then name.
func sorted_ids() -> Array:
	var ids: Array = recipe_db.keys()
	ids.sort_custom(func(a, b):
		var ra: Recipe = recipe_db[a]
		var rb: Recipe = recipe_db[b]
		if ra.required_level != rb.required_level:
			return ra.required_level < rb.required_level
		return ra.name < rb.name)
	return ids

func get_level() -> int:
	return int(GameManager.skills[skill_key]["level"])

func is_unlocked(recipe: Recipe) -> bool:
	return get_level() >= recipe.required_level

## Level alone doesn't teach a scroll recipe; its scroll must have been studied.
func is_learned(recipe: Recipe) -> bool:
	return not recipe.scroll_taught or known_recipe_ids.has(recipe.id)

## Teaches a recipe (from a studied scroll). False if the id isn't this
## station's or it's already known — callers keep the scroll in that case.
func learn_recipe(recipe_id: String) -> bool:
	var recipe: Recipe = find_recipe_by_id(recipe_id)
	if recipe == null or known_recipe_ids.has(recipe_id):
		return false
	known_recipe_ids[recipe_id] = true
	recipe_learned.emit(recipe_id)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

func get_known_recipes() -> Array:
	return known_recipe_ids.keys()

func load_known_recipes(ids: Array) -> void:
	known_recipe_ids.clear()
	for recipe_id in ids:
		if recipe_db.has(recipe_id):
			known_recipe_ids[String(recipe_id)] = true

func has_inputs(recipe: Recipe) -> bool:
	for item_id in recipe.inputs:
		if InventoryManager.get_item_count(item_id) < int(recipe.inputs[item_id]):
			return false
	return true

func can_brew(recipe: Recipe) -> bool:
	return recipe != null and is_unlocked(recipe) and is_learned(recipe) and has_inputs(recipe)

## Real craft time after any structure speed bonus on this station's channel.
func get_effective_seconds(recipe: Recipe) -> float:
	var speed := 1.0
	if speed_effect != "":
		speed += GroundsManager.get_bonus(speed_effect) / 100.0
	return recipe.base_seconds / maxf(speed, 0.01)

## Puts a recipe on the station, paying its inputs now. Starting a different
## craft abandons the current one (its inputs stay spent). Clicking the active
## recipe again stops it instead.
func start_brew(recipe: Recipe) -> bool:
	if not can_brew(recipe):
		return false
	for item_id in recipe.inputs:
		InventoryManager.remove_item(item_id, int(recipe.inputs[item_id]))
	# Crafting and gathering are exclusive — the station demands full attention.
	if GameManager.active_action_source != null:
		NotificationManager.show_item("The gathering halts — the station demands attention", 1)
		GameManager.stop_gathering()
	active_recipe = recipe
	brew_progress = 0.0
	brew_state_changed.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

func stop_brew() -> void:
	if active_recipe == null:
		return
	active_recipe = null
	brew_progress = 0.0
	brew_state_changed.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

func _process(delta: float) -> void:
	if active_recipe == null:
		return
	brew_progress += delta
	if brew_progress >= get_effective_seconds(active_recipe):
		_finish_brew()

## Pays out the finished craft: output item, skill XP, and either an
## auto-repeat (inputs permitting) or a cold station.
func _finish_brew() -> void:
	var recipe = active_recipe
	active_recipe = null
	brew_progress = 0.0
	if recipe.output_item != null:
		var overflow = InventoryManager.add_item(recipe.output_item, recipe.output_amount)
		if overflow > 0:
			NotificationManager.show_item("The pack is full — %d %s lost" % [overflow, recipe.output_item.name], 1)
		else:
			NotificationManager.show_item(recipe.output_item.name, recipe.output_amount, recipe.output_item)
	GameManager.add_xp(skill_key, recipe.base_xp)
	AudioManager.play_sfx(finish_sfx)
	brew_completed.emit(recipe.id)
	# The station keeps working while the shelves hold out.
	if auto_repeat and can_brew(recipe):
		for item_id in recipe.inputs:
			InventoryManager.remove_item(item_id, int(recipe.inputs[item_id]))
		active_recipe = recipe
	brew_state_changed.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
