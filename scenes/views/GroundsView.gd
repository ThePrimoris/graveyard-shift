# GroundsView.gd
# The Grounds overlay: rebuild and upgrade the graveyard's structures, the
# game's main material sink. Built in code on a CanvasLayer like the Settings
# and Necronomicon overlays, opened from the "Grounds" nav button.
extends CanvasLayer

const COL_GOLD := Color(0.83, 0.64, 0.27)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_GREEN := Color(0.55, 0.82, 0.5)
const COL_RUST := Color(0.76, 0.353, 0.29)

## structure_id -> { "tier": Label, "effect": Label, "cost": Label, "button": Button }
var rows: Dictionary = {}

func _ready() -> void:
	layer = 58
	add_to_group("ui_updates")
	_build_ui()
	update_ui()

func _build_ui() -> void:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.078, 0.071, 0.11, 0.98)
	style.set_corner_radius_all(12)
	style.border_color = Color(0.83, 0.64, 0.27, 0.55)
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(680, 0)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "THE GROUNDS"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Rebuild what the earth has taken. Every structure is a standing boon."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", COL_TEXT_MID)
	subtitle.add_theme_font_size_override("font_size", 13)
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	for structure_id in GroundsManager.sorted_ids():
		vbox.add_child(_build_row(structure_id))

	vbox.add_child(HSeparator.new())

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(160, 36)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)

func _build_row(structure_id: String) -> Control:
	var s: Structure = GroundsManager.find_structure(structure_id)

	var card = PanelContainer.new()
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.055, 0.05, 0.082)
	cstyle.set_corner_radius_all(8)
	cstyle.set_border_width_all(1)
	cstyle.border_color = Color(0.83, 0.64, 0.27, 0.25)
	cstyle.content_margin_left = 14
	cstyle.content_margin_right = 14
	cstyle.content_margin_top = 10
	cstyle.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", cstyle)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)

	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	info.add_child(head)

	var name_lbl = Label.new()
	name_lbl.text = s.name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", COL_TEXT_HI)
	head.add_child(name_lbl)

	var tier_lbl = Label.new()
	tier_lbl.add_theme_font_size_override("font_size", 13)
	tier_lbl.add_theme_color_override("font_color", COL_GOLD)
	tier_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tier_lbl)

	var desc = Label.new()
	desc.text = s.description
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", COL_TEXT_MID)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(430, 0)
	info.add_child(desc)

	var effect_lbl = Label.new()
	effect_lbl.add_theme_font_size_override("font_size", 13)
	effect_lbl.add_theme_color_override("font_color", COL_GREEN)
	info.add_child(effect_lbl)

	var cost_lbl = Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", COL_TEXT_MID)
	cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_lbl.custom_minimum_size = Vector2(430, 0)
	info.add_child(cost_lbl)

	var build_btn = Button.new()
	build_btn.custom_minimum_size = Vector2(180, 46)
	build_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	build_btn.pressed.connect(_on_build_pressed.bind(structure_id))
	row.add_child(build_btn)

	rows[structure_id] = {"tier": tier_lbl, "effect": effect_lbl, "cost": cost_lbl, "button": build_btn}
	return card

func _on_build_pressed(structure_id: String) -> void:
	GroundsManager.build(structure_id)
	update_ui()

func _describe_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id in cost:
		var item = GameManager.find_item_by_id(item_id)
		var display = item.name if item else item_id.capitalize()
		var have = InventoryManager.get_item_count(item_id)
		parts.append("%d %s (have %d)" % [cost[item_id], display, have])
	return ", ".join(parts)

func _fmt_value(s: Structure, value: float) -> String:
	if s.effect_unit == "%":
		return "+%d%%" % int(round(value))
	return "%d%s" % [int(round(value)), s.effect_unit]

func update_ui() -> void:
	for structure_id in rows:
		var s: Structure = GroundsManager.find_structure(structure_id)
		var r = rows[structure_id]
		var lvl = GroundsManager.get_level(structure_id)
		var current = GroundsManager.get_structure_value(structure_id)

		r["tier"].text = "Tier %d / %d" % [lvl, s.max_level()]

		var tier = GroundsManager.next_tier(structure_id)
		if tier == null:
			r["effect"].text = "%s %s — fully raised." % [_fmt_value(s, current), s.effect_label]
			r["cost"].text = ""
			r["button"].text = "COMPLETE"
			r["button"].disabled = true
		else:
			var after = current + tier.magnitude
			r["effect"].text = "%s  →  %s  %s" % [_fmt_value(s, current), _fmt_value(s, after), s.effect_label]
			r["cost"].text = "Cost: %s" % _describe_cost(tier.cost)
			r["button"].text = "Build Tier %d" % (lvl + 1)
			r["button"].disabled = not GroundsManager.can_afford(structure_id)
