# HarvestView.gd
# Shared base for the Graveyard / Forest / Quarry screens.
# Each skill holds a list of zones; the selector on the left picks the active
# zone and the card grid shows that zone's nodes, four to a row.
class_name HarvestView
extends PanelContainer

const ACTION_CARD_SCENE = preload("res://scenes/cards/ActionCard.tscn")

## The skill's zones, in unlock order. Assign zone .tres files here.
@export var zones: Array[HarvestZone] = []

var action_verb: String = "Harvest"
var progress_color: Color = Color("#c8a24d")
var progress_mode: int = ActionCard.ProgressMode.FILL

var current_zone: int = 0
var display_nodes: Array = []
var zone_buttons: Array = []

var node_progress: Dictionary = {}
var cards: Array = []

var header_title: Label
var header_bar: ProgressBar
var header_xp_label: Label

## Subclasses may vary bar count per node (used by SEGMENTS mode).
func _segments_for(_node: HarvestNode) -> int:
	return 1

func _ready() -> void:
	add_to_group("ui_updates")
	add_to_group("harvest_views")
	_build_header()
	_build_zone_selector()
	_select_zone(0)

func _get_skill_key() -> String:
	for zone in zones:
		if zone == null: continue
		for node in zone.nodes:
			if node != null:
				return GameManager.get_skill_key(node)
	return ""

# --- Zones ---

func _build_zone_selector() -> void:
	var list = get_node_or_null("VBoxContainer/ContentRow/ZonePanel/ZoneVBox/ZoneList")
	if list == null: return
	for child in list.get_children():
		child.queue_free()
	zone_buttons.clear()

	for i in range(zones.size()):
		var zone = zones[i]
		if zone == null: continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.text = zone.name
		btn.toggle_mode = true
		btn.tooltip_text = zone.description
		btn.pressed.connect(_on_zone_pressed.bind(i))
		list.add_child(btn)
		zone_buttons.append(btn)

func _on_zone_pressed(index: int) -> void:
	_select_zone(index)

func _select_zone(index: int) -> void:
	if zones.is_empty(): return
	current_zone = clampi(index, 0, zones.size() - 1)

	display_nodes.clear()
	if zones[current_zone] != null:
		for node in zones[current_zone].nodes:
			if node != null:
				display_nodes.append(node)

	_build_cards()
	_update_zone_buttons()
	update_ui()

func _update_zone_buttons() -> void:
	var skill_key = _get_skill_key()
	var level = GameManager.skills[skill_key]["level"] if skill_key in GameManager.skills else 1
	for i in range(zone_buttons.size()):
		var btn: Button = zone_buttons[i]
		btn.set_pressed_no_signal(i == current_zone)
		var zone = zones[i]
		if zone and level < zone.required_level:
			btn.disabled = true
			btn.tooltip_text = "Requires level %d %s" % [zone.required_level, skill_key.capitalize()]
		else:
			btn.disabled = false

# --- Cards ---

func _build_cards() -> void:
	var flow = get_node_or_null("VBoxContainer/ContentRow/ScrollContainer")
	if flow == null or flow.get_child_count() == 0: return
	flow = flow.get_child(0)

	for child in flow.get_children():
		child.queue_free()
	cards.clear()

	for node_data in display_nodes:
		var card = ACTION_CARD_SCENE.instantiate()
		flow.add_child(card)

		card.setup_card(node_data.name, node_data.description, action_verb, node_data.base_duration)
		var entries = _drop_entries(node_data)
		if not entries.is_empty():
			card.set_icon(entries[0]["item"].icon)
		card.set_progress_color(progress_color)
		card.set_progress_mode(progress_mode, _segments_for(node_data))
		card.set_dig_sections(node_data.dig_sections)
		if node_data.is_boss:
			card.set_large()
		if not node_progress.has(node_data.id):
			node_progress[node_data.id] = 0.0

		if node_data.is_boss:
			card.action_triggered.connect(_on_boss_confront.bind(node_data))
		else:
			card.action_triggered.connect(func():
				GameManager.register_activity(card, node_data)
			)
		cards.append(card)

## Placeholder until combat is implemented.
func _on_boss_confront(node_data: HarvestNode) -> void:
	NotificationManager.show_item("%s stirs... but combat isn't ready yet. Soon." % node_data.name, 1)

## Page header: skill icon, name, level, XP bar.
func _build_header() -> void:
	var vbox = get_node_or_null("VBoxContainer")
	if vbox == null: return

	var header = PanelContainer.new()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	header.add_child(margin)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var skill_key = _get_skill_key()
	var icon_path = "res://icons/skills/%s.png" % skill_key
	if ResourceLoader.exists(icon_path):
		var icon = TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = 1
		icon.stretch_mode = 5
		row.add_child(icon)

	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	header_title = Label.new()
	header_title.add_theme_font_size_override("font_size", 22)
	col.add_child(header_title)

	header_bar = ProgressBar.new()
	header_bar.custom_minimum_size = Vector2(0, 14)
	header_bar.show_percentage = false
	col.add_child(header_bar)

	header_xp_label = Label.new()
	header_xp_label.add_theme_font_size_override("font_size", 12)
	header_xp_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	col.add_child(header_xp_label)

	vbox.add_child(header)
	vbox.move_child(header, 0)

func _update_header() -> void:
	if header_title == null: return
	var skill_key = _get_skill_key()
	if skill_key == "": return

	var skill = GameManager.skills[skill_key]
	header_title.text = "%s — Level %d / %d" % [skill_key.capitalize(), skill["level"], GameManager.MAX_LEVEL]

	if skill["level"] >= GameManager.MAX_LEVEL:
		header_bar.max_value = 1
		header_bar.value = 1
		header_xp_label.text = "Skill mastered!"
	else:
		var needed = GameManager.get_xp_needed(skill["level"])
		header_bar.max_value = needed
		header_bar.value = skill["xp"]
		header_xp_label.text = "%.0f / %.0f XP to next level" % [skill["xp"], needed]

## Called by SaveManager after loading: restart the node that was being worked,
## switching to its zone if needed.
func resume_node(node_id: String) -> void:
	if node_id == "": return
	for zi in range(zones.size()):
		var zone = zones[zi]
		if zone == null: continue
		for node in zone.nodes:
			if node == null or node.id != node_id: continue
			if zi != current_zone:
				_select_zone(zi)
			for i in range(display_nodes.size()):
				if display_nodes[i].id == node_id and i < cards.size():
					if GameManager.active_action_source != cards[i] and GameManager.is_node_accessible(node):
						GameManager.register_activity(cards[i], node)
					return
			return

func _process(delta: float) -> void:
	for i in range(display_nodes.size()):
		var node_data = display_nodes[i]
		var card = cards[i] if i < cards.size() else null

		if not node_data or not card: continue

		if GameManager.active_action_source == card:
			node_progress[node_data.id] += delta

			var duration = GameManager.get_effective_duration(node_data)
			if node_progress[node_data.id] >= duration:
				node_progress[node_data.id] = 0.0
				GameManager.resolve_harvest(node_data)

			card.update_progress(node_progress[node_data.id], duration)
		else:
			if node_progress[node_data.id] > 0.0:
				node_progress[node_data.id] = 0.0
				card.reset_progress()

## Drop rows for the card, most common first.
func _drop_entries(node: HarvestNode) -> Array:
	var entries: Array = []
	for entry in node.loot_pool.slice(0, HarvestNode.MAX_LOOT_ENTRIES):
		if entry != null and entry.item != null and entry.chance > 0.0:
			entries.append({"item": entry.item, "chance": entry.chance})
	entries.sort_custom(func(a, b): return a["chance"] > b["chance"])
	return entries

func update_ui() -> void:
	_update_header()
	_update_zone_buttons()

	for i in range(cards.size()):
		var card = cards[i]
		if not card: continue

		card.set_button_text(GameManager.active_action_source == card)

		if i < display_nodes.size() and display_nodes[i] != null:
			var node = display_nodes[i]

			if not GameManager.is_node_accessible(node):
				card.show_locked(node.description, GameManager.get_node_requirement_text(node))
			elif node.is_boss:
				card.show_boss(node.description, "Confront")
				card.action_button.disabled = false
			else:
				card.show_unlocked()
				card.set_stats(node.base_xp, GameManager.get_effective_duration(node))
				card.set_drops(_drop_entries(node))
				card.action_button.disabled = false
