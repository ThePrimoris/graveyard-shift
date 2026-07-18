# AchievementsPanel.gd
# The achievement book, opened from the top navigation bar. Built in code on a
# CanvasLayer like the Settings overlay. Lists every achievement in
# StatsManager.ACHIEVEMENTS in order: earned ones lit gold, locked ones dimmed
# with a progress readout toward their counter.
extends CanvasLayer

const COL_CARD := Color(0.078, 0.071, 0.11, 0.98)
const COL_ROW := Color("#171226")
const COL_ROW_EARNED := Color("#1d1830")
const COL_BORDER := Color(0.83, 0.64, 0.27, 0.55)
const COL_GOLD := Color(0.83, 0.64, 0.27)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_LOCKED := Color(0.42, 0.395, 0.48)

func _ready() -> void:
	layer = 60

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
	style.bg_color = COL_CARD
	style.set_corner_radius_all(12)
	style.border_color = COL_BORDER
	style.set_border_width_all(1)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin = MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 26)
	for m in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 20)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(460, 0)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "ACHIEVEMENTS"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var earned_count := 0
	for entry in StatsManager.ACHIEVEMENTS:
		if StatsManager.has_achievement(entry["id"]):
			earned_count += 1
	var tally = Label.new()
	tally.text = "%d of %d earned" % [earned_count, StatsManager.ACHIEVEMENTS.size()]
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tally.add_theme_color_override("font_color", COL_TEXT_MID)
	vbox.add_child(tally)

	vbox.add_child(HSeparator.new())

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for entry in StatsManager.ACHIEVEMENTS:
		list.add_child(_make_row(entry))

	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 36)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	vbox.add_child(close)

func _make_row(entry: Dictionary) -> PanelContainer:
	var earned := StatsManager.has_achievement(entry["id"])
	var current := StatsManager.get_stat(entry["stat"])
	var goal := float(entry["at"])

	var row = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COL_ROW_EARNED if earned else COL_ROW
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = COL_GOLD if earned else Color("#2f2745")
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	var head = HBoxContainer.new()
	col.add_child(head)
	var name_lbl = Label.new()
	name_lbl.text = entry["name"] if earned else "%s (locked)" % entry["name"]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_GOLD if earned else COL_LOCKED)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	var mark = Label.new()
	mark.text = "✓" if earned else "%d / %d" % [int(minf(current, goal)), int(goal)]
	mark.add_theme_font_size_override("font_size", 12)
	mark.add_theme_color_override("font_color", COL_GOLD if earned else COL_TEXT_MID)
	head.add_child(mark)

	var blurb = Label.new()
	blurb.text = entry["blurb"]
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.add_theme_color_override("font_color", COL_TEXT_MID if earned else COL_LOCKED)
	col.add_child(blurb)

	if not earned:
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 6)
		bar.show_percentage = false
		bar.max_value = goal
		bar.value = minf(current, goal)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.55)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		col.add_child(bar)

	return row
