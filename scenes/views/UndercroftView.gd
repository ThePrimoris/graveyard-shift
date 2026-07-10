# UndercroftView.gd
# The minion screen: a header strip and one MinionCard per minion type.
# Raising happens here; slotting happens on the graveyard plots below.
extends PanelContainer

const MINION_CARD_SCENE = preload("res://scenes/cards/MinionCard.tscn")
const ACCENT := Color("#8a6fbe")

var cards: Array = []
var roster_chip_label: Label

func _ready() -> void:
	add_to_group("ui_updates")
	_apply_ambience()
	_build_header()
	_build_cards()
	MinionManager.minions_updated.connect(update_ui)
	update_ui()

## Same page-tint treatment as the harvest views, in undercroft violet.
func _apply_ambience() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.045, 0.075)
	var previous := get_theme_stylebox("panel")
	if previous:
		style.content_margin_left = previous.content_margin_left
		style.content_margin_top = previous.content_margin_top
		style.content_margin_right = previous.content_margin_right
		style.content_margin_bottom = previous.content_margin_bottom
	add_theme_stylebox_override("panel", style)

## Header strip: title on the left, raised-count chip on the right.
func _build_header() -> void:
	var vbox = get_node_or_null("VBoxContainer")
	if vbox == null: return

	var header = PanelContainer.new()
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = Color(0.078, 0.071, 0.11, 0.97)
	hstyle.set_border_width_all(1)
	hstyle.border_width_left = 4
	hstyle.border_color = Color(ACCENT.r * 0.6, ACCENT.g * 0.6, ACCENT.b * 0.6)
	hstyle.set_corner_radius_all(10)
	hstyle.shadow_color = Color(0, 0, 0, 0.35)
	hstyle.shadow_size = 8
	hstyle.shadow_offset = Vector2(0, 3)
	header.add_theme_stylebox_override("panel", hstyle)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	header.add_child(margin)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var title = Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "The Undercroft"
	col.add_child(title)

	var subtitle = Label.new()
	subtitle.theme_type_variation = &"MutedLabel"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.text = "Raise minions from the remains you gather. Slot them into graveyard plots and they earn XP from your harvests."
	col.add_child(subtitle)

	var chip = PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = "Minions raised"
	roster_chip_label = Label.new()
	roster_chip_label.add_theme_font_size_override("font_size", 13)
	roster_chip_label.add_theme_color_override("font_color", ACCENT)
	chip.add_child(roster_chip_label)
	row.add_child(chip)

	vbox.add_child(header)
	vbox.move_child(header, 0)

func _build_cards() -> void:
	var flow = get_node_or_null("VBoxContainer/ScrollContainer/MinionGrid")
	if flow == null: return
	for child in flow.get_children():
		child.queue_free()
	cards.clear()

	var ids = MinionManager.minion_db.keys()
	ids.sort()
	for minion_id in ids:
		var minion = MinionManager.minion_db[minion_id]
		var card = MINION_CARD_SCENE.instantiate()
		flow.add_child(card)
		card.setup_card(minion)
		card.raise_pressed.connect(_on_raise_pressed.bind(minion_id))
		cards.append(card)

func _on_raise_pressed(minion_id: String) -> void:
	MinionManager.raise_minion(minion_id)

func update_ui() -> void:
	if roster_chip_label:
		roster_chip_label.text = "%d / %d raised" % [MinionManager.roster.size(), MinionManager.minion_db.size()]
	for card in cards:
		if card and card.minion_id != "":
			var minion = MinionManager.find_minion_by_id(card.minion_id)
			if minion:
				card.update_card(minion)
