# TutorialManager.gd
# First-run tutorial, narrated by Mortimer, the graveyard's late caretaker.
# A CanvasLayer autoload: draws the speech bubble and a pulsing highlight over
# whatever the current step points at, and advances on harvests / view changes.
extends CanvasLayer

const MENTOR_NAME = "MORTIMER, THE LATE CARETAKER"
const PORTRAIT_PATH = "res://icons/ui/mortimer.png"

# wait kinds: "continue" (button), "harvest" (node + count), "view" (view name),
#             "event" (a named beat fired via notify_event — book opened,
#             minion raised, minion slotted, offering made)
const STEPS: Array[Dictionary] = [
	{
		"id": "intro", "wait": "continue", "button": "Show me around",
		"text": "Ah — the new tenant, at last. Mortimer: caretaker of these grounds for forty years, and considerably longer since my burial. This graveyard is yours now... once it's cleared. Every empire of bone begins with a shovel."
	},
	{
		"id": "dig", "wait": "harvest", "node": "fresh_grave", "count": 5,
		"highlight": "node:fresh_grave", "objective": "Still Flesh dug: %d / %d",
		"text": "Start with the fresh graves. Dig them open — the Still Flesh you uncover will fuel your necromancy, in time. Set your shovel working and it carries on without you. That is rather the point."
	},
	{
		"id": "to_forest", "wait": "view", "view": "forest",
		"highlight": "sidebar:Lumbering", "objective": "Open Lumbering from the sidebar",
		"text": "Well dug — the former occupants weren't using it. Now: those dead trees crowd the ground where your workshop will one day stand. Take your hatchet to the Lumbering grounds."
	},
	{
		"id": "chop", "wait": "harvest", "node": "withered_trees", "count": 5,
		"highlight": "node:withered_trees", "objective": "Withered Trees felled: %d / %d",
		"text": "Bring one down. Gravewood Logs burn poorly but build well enough — fences, coffins, scaffolds. The essentials."
	},
	{
		"id": "to_quarry", "wait": "view", "view": "quarry",
		"highlight": "sidebar:Spelunking", "objective": "Open Spelunking from the sidebar",
		"text": "The catacomb walls beneath us are crumbling anyway; we may as well help them along. Your pickaxe, please — down to the Spelunking tunnels."
	},
	{
		"id": "mine", "wait": "harvest", "node": "verdigris_seams", "count": 5,
		"highlight": "node:verdigris_seams", "objective": "Verdigris Seams mined: %d / %d",
		"text": "Knock the loose stone free. Foundations want good bones — architecturally speaking."
	},
	{
		"id": "tome", "wait": "continue", "button": "Take the tome",
		"text": "You've the arms for the honest work — now for the art. From beneath the circle's stones I give you what I guarded forty years: the NECRONOMICON. Every servant you will ever raise sleeps between its covers."
	},
	{
		"id": "open_book", "wait": "event", "event": "book_opened",
		"highlight": "circle", "objective": "Open the Necronomicon at the circle",
		"text": "The circle at the grounds' heart holds the book now — that is why it glows. Go and press your hand to the stone."
	},
	{
		"id": "raise", "wait": "event", "event": "minion_raised",
		"highlight": "book:raise:zombie", "objective": "Raise the Zombie from its Unwritten Page",
		"text": "The index: your raised servants on the left page, the unwritten on the right. I have left Still Flesh and Coagulated Blood on the slab — find the Zombie among the unwritten and speak its rite."
	},
	{
		"id": "slot", "wait": "event", "event": "minion_slotted",
		"highlight": "plot:1", "objective": "Slot your minion into a graveyard plot",
		"text": "It stands! Ghastly, isn't it. Now close the book and look to the plots along the grounds' edge — click one and put the creature in it. An idle minion is a wasted corpse."
	},
	{
		"id": "growth", "wait": "continue", "button": "Understood",
		"text": "A slotted minion's inked runes do their work from the plot — and when war comes, your four slotted dead are your warband. The creature itself grows on what you feed it: offerings at the altar become its experience, levels grant skill points, and points buy runes in its page of the book. Actives wait for war."
	},
	{
		"id": "altar", "wait": "event", "event": "offering_made",
		"highlight": "book:altar", "objective": "Make an offering at the Ritual Altar",
		"text": "One final art. Open the tome to the ALTAR chapter. What you lay upon the stone becomes strength in your servants — I have left a pile of bones. Offer them, and watch the creature swell."
	},
	{
		"id": "outro", "wait": "continue", "button": "Begin your shift",
		"text": "And that is the whole of it: dig, chop, mine — raise, slot, offer. The grounds are yours now, keeper, and the book with them. Mind the old crypt at the row's end... it has begun minding you back."
	}
]

var tutorial_complete: bool = false
var active: bool = false
var step_index: int = -1
var step_progress: int = 0

var _root: Control
var bubble: PanelContainer
var name_label: Label
var text_label: Label
var objective_label: Label
var continue_button: Button
var skip_button: Button
var highlight_rect: Panel
var _pulse_time: float = 0.0

func _ready() -> void:
	# Above the Necronomicon (55) and settings (60) so Mortimer can keep
	# talking while the book is open; below the debug console (100).
	layer = 70
	visible = false
	add_to_group("view_manager")  # receives switch_view group calls
	_build_ui()
	GameManager.harvest_completed.connect(_on_harvest_completed)

## Starts the tutorial on fresh runs. Called by SaveManager once loading settles.
func maybe_start() -> void:
	if tutorial_complete or active: return
	begin()

func begin() -> void:
	active = true
	visible = true
	step_index = -1
	_advance()

func reset_state() -> void:
	tutorial_complete = false
	active = false
	visible = false
	step_index = -1
	begin()

func finish(skipped: bool = false) -> void:
	tutorial_complete = true
	active = false
	visible = false
	# The tome is the tutorial's reward — skipping must not lock the player
	# out of the minion system, so it is granted either way.
	if not MinionManager.necronomicon_unlocked:
		MinionManager.necronomicon_unlocked = true
		NotificationManager.show_item("The Necronomicon is yours — the circle glows", 1)
		get_tree().call_group("ui_updates", "update_ui")
	if not skipped:
		NotificationManager.show_item("The grounds are yours. Mortimer will be watching.", 1)
	SaveManager.save_game()

func current_step() -> Dictionary:
	if step_index >= 0 and step_index < STEPS.size():
		return STEPS[step_index]
	return {}

func _advance() -> void:
	step_index += 1
	step_progress = 0
	if step_index >= STEPS.size():
		finish()
		return
	if _enter_step_effects():
		_advance()
		return
	_show_step()

## Runs a step's entry side effects. Returns true when the step is already
## satisfied (e.g. a returning player raised a minion before the lesson)
## and should be skipped outright.
func _enter_step_effects() -> bool:
	match current_step().get("id", ""):
		"tome":
			MinionManager.necronomicon_unlocked = true
			NotificationManager.show_item("The Necronomicon is yours — the circle glows", 1)
			get_tree().call_group("ui_updates", "update_ui")
		"raise":
			if not MinionManager.roster.is_empty():
				return true
			_grant_rite_materials("zombie")
		"slot":
			for occupant in MinionManager.plots:
				if occupant != "":
					return true
		"altar":
			_grant_offering_materials("bones", 5)
	return false

## Mortimer tops the pack up to a minion's full raising rite.
func _grant_rite_materials(minion_id: String) -> void:
	var minion = MinionManager.find_minion_by_id(minion_id)
	if minion == null: return
	for item_id in minion.raise_cost:
		var missing = minion.raise_cost[item_id] - InventoryManager.get_item_count(item_id)
		if missing > 0:
			var item = GameManager.find_item_by_id(item_id)
			if item:
				InventoryManager.add_item(item, missing)
	NotificationManager.show_item("Mortimer left materials on the slab", 1)

## Mortimer leaves something worth burning at the altar.
func _grant_offering_materials(item_id: String, amount: int) -> void:
	var missing = amount - InventoryManager.get_item_count(item_id)
	if missing <= 0: return
	var item = GameManager.find_item_by_id(item_id)
	if item:
		InventoryManager.add_item(item, missing)

# --- Step conditions ---

func _on_harvest_completed(node_id: String) -> void:
	if not active: return
	var step = current_step()
	if step.get("wait", "") == "harvest" and step.get("node", "") == node_id:
		step_progress += 1
		if step_progress >= step.get("count", 1):
			_advance()
		else:
			_update_objective()

## Group "view_manager" hook: fired alongside Control.switch_view.
func switch_view(target_view: String) -> void:
	if not active: return
	var step = current_step()
	if step.get("wait", "") == "view" and step.get("view", "") == target_view:
		_advance()

func _on_continue_pressed() -> void:
	if current_step().get("wait", "") == "continue":
		_advance()

## Named tutorial beats fired by other systems (the book opening, a minion
## being raised or slotted, an offering being made). Safe to call any time.
func notify_event(event_id: String) -> void:
	if not active: return
	var step = current_step()
	if step.get("wait", "") == "event" and step.get("event", "") == event_id:
		_advance()

# --- UI ---

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Pulsing outline that tracks the current step's target
	highlight_rect = Panel.new()
	var hl_style = StyleBoxFlat.new()
	hl_style.bg_color = Color(0, 0, 0, 0)
	hl_style.border_color = Color(0.92, 0.78, 0.38)
	hl_style.set_border_width_all(3)
	hl_style.set_corner_radius_all(12)
	highlight_rect.add_theme_stylebox_override("panel", hl_style)
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_rect.visible = false
	_root.add_child(highlight_rect)

	# Mortimer's speech bubble, top center
	bubble = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.095, 0.125, 0.97)
	style.set_corner_radius_all(12)
	style.border_color = Color(0.38, 0.55, 0.68)
	style.set_border_width_all(2)
	bubble.add_theme_stylebox_override("panel", style)
	bubble.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bubble.anchor_left = 0.5
	bubble.anchor_right = 0.5
	bubble.offset_left = -330.0
	bubble.offset_right = 330.0
	bubble.offset_top = 16.0
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bubble)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	bubble.add_child(margin)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var portrait_well = PanelContainer.new()
	var well_style = StyleBoxFlat.new()
	well_style.bg_color = Color(0.05, 0.07, 0.1, 1)
	well_style.set_corner_radius_all(10)
	well_style.border_color = Color(0.23, 0.31, 0.39)
	well_style.set_border_width_all(1)
	portrait_well.add_theme_stylebox_override("panel", well_style)
	portrait_well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait_well)

	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(72, 72)
	portrait.expand_mode = 1
	portrait.stretch_mode = 5
	if ResourceLoader.exists(PORTRAIT_PATH):
		portrait.texture = load(PORTRAIT_PATH)
	portrait_well.add_child(portrait)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	var top_row = HBoxContainer.new()
	col.add_child(top_row)

	name_label = Label.new()
	name_label.text = MENTOR_NAME
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.78, 0.38))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_label)

	skip_button = Button.new()
	skip_button.text = "Skip"
	skip_button.add_theme_font_size_override("font_size", 11)
	skip_button.tooltip_text = "Skip the tutorial. Mortimer will pretend not to be hurt."
	skip_button.pressed.connect(func(): finish(true))
	top_row.add_child(skip_button)

	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 14)
	col.add_child(text_label)

	objective_label = Label.new()
	objective_label.add_theme_font_size_override("font_size", 13)
	objective_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))
	col.add_child(objective_label)

	continue_button = Button.new()
	continue_button.custom_minimum_size = Vector2(180, 34)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	continue_button.pressed.connect(_on_continue_pressed)
	col.add_child(continue_button)

func _show_step() -> void:
	var step = current_step()
	text_label.text = step.get("text", "")
	continue_button.visible = step.get("wait", "") == "continue"
	continue_button.text = step.get("button", "Continue")
	_update_objective()

func _update_objective() -> void:
	var step = current_step()
	var objective = step.get("objective", "")
	if objective == "":
		objective_label.visible = false
		return
	objective_label.visible = true
	if step.get("wait", "") == "harvest":
		objective_label.text = "▸ " + objective % [step_progress, step.get("count", 1)]
	else:
		objective_label.text = "▸ " + objective

## The control the current step points at, or null.
func _resolve_highlight_target() -> Control:
	var h: String = current_step().get("highlight", "")
	if h.begins_with("node:"):
		var node_id = h.substr(5)
		for view in get_tree().get_nodes_in_group("harvest_views"):
			for i in range(view.display_nodes.size()):
				if view.display_nodes[i] and view.display_nodes[i].id == node_id and i < view.cards.size():
					return view.cards[i]
	elif h.begins_with("sidebar:"):
		var found = get_tree().root.find_child(h.substr(8), true, false)
		if found is Control:
			return found
	elif h == "circle":
		var circle = get_tree().root.find_child("CircleButton", true, false)
		if circle is Control:
			return circle
	elif h.begins_with("plot:"):
		var plot = get_tree().root.find_child("PlotButton" + h.substr(5), true, false)
		if plot is Control:
			return plot
	elif h.begins_with("book:"):
		# Targets inside the Necronomicon overlay; null while the book is shut,
		# which leaves the circle un-highlighted but the objective text standing.
		for book in get_tree().get_nodes_in_group("necronomicon"):
			var target = book.tutorial_target(h.substr(5))
			if target is Control:
				return target
	return null

func _process(delta: float) -> void:
	if not active:
		return
	_pulse_time += delta

	var target = _resolve_highlight_target()
	if target and target.is_visible_in_tree():
		var rect = target.get_global_rect().grow(7.0)
		highlight_rect.visible = true
		highlight_rect.global_position = rect.position
		highlight_rect.size = rect.size
		highlight_rect.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_pulse_time * 4.0))
	else:
		highlight_rect.visible = false
