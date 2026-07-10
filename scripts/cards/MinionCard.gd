# MinionCard.gd
# One minion in the Undercroft, Lanternlight style. Two states:
#  Unraised - shows the raising rite's material costs and a Raise button.
#  Raised   - shows level, HP/ATK, the XP-to-next bar, and plot status.
class_name MinionCard
extends PanelContainer

signal raise_pressed

const COL_CARD_BG := Color(0.078, 0.071, 0.11, 0.97)
const COL_ACCENT := Color("#8a6fbe")
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_GOOD := Color(0.62, 0.85, 0.55)
const COL_BAD := Color(0.76, 0.353, 0.29)

@onready var title_label: Label = %TitleLabel
@onready var level_chip: PanelContainer = %LevelChip
@onready var level_label: Label = %LevelLabel
@onready var desc_label: Label = %DescLabel
@onready var stats_row: HBoxContainer = %StatsRow
@onready var hp_label: Label = %HPLabel
@onready var atk_label: Label = %ATKLabel
@onready var points_chip: PanelContainer = %PointsChip
@onready var points_label: Label = %PointsLabel
@onready var cost_box: VBoxContainer = %CostBox
@onready var xp_box: VBoxContainer = %XPBox
@onready var xp_bar: ProgressBar = %XPBar
@onready var xp_label: Label = %XPLabel
@onready var plot_label: Label = %PlotLabel
@onready var icon_rect: TextureRect = %IconRect
@onready var initial_label: Label = %InitialLabel
@onready var raise_button: Button = %RaiseButton

var minion_id: String = ""

func _ready() -> void:
	raise_button.pressed.connect(func(): raise_pressed.emit())
	_apply_frame()
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_ACCENT
	fill.set_corner_radius_all(5)
	xp_bar.add_theme_stylebox_override("fill", fill)

## Undercroft cards share one violet accent frame.
func _apply_frame() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD_BG
	s.set_border_width_all(1)
	s.border_width_top = 3
	s.border_color = Color(COL_ACCENT.r * 0.6, COL_ACCENT.g * 0.6, COL_ACCENT.b * 0.6)
	s.set_corner_radius_all(10)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", s)

func setup_card(minion: Minion) -> void:
	minion_id = minion.id
	title_label.text = minion.name
	desc_label.text = minion.description
	if minion.icon:
		icon_rect.texture = minion.icon
		initial_label.visible = false
	else:
		initial_label.text = minion.name.left(1)
	update_card(minion)

## Refreshes every dynamic field from the manager's state.
func update_card(minion: Minion) -> void:
	var raised = MinionManager.is_raised(minion.id)

	level_chip.visible = raised
	stats_row.visible = raised
	xp_box.visible = raised
	plot_label.visible = raised
	cost_box.visible = not raised
	raise_button.visible = not raised

	hp_label.text = "HP %d" % MinionManager.get_hp(minion.id)
	atk_label.text = "ATK %.1f" % MinionManager.get_atk(minion.id)

	if raised:
		var state = MinionManager.roster[minion.id]
		level_label.text = "Lv %d / %d" % [state["level"], MinionManager.MAX_LEVEL]
		var points = MinionManager.get_skill_points(minion.id)
		points_chip.visible = points > 0
		points_label.text = "%d pt%s" % [points, "" if points == 1 else "s"]

		if state["level"] >= MinionManager.MAX_LEVEL:
			xp_bar.max_value = 1
			xp_bar.value = 1
			xp_label.text = "Fully grown"
		else:
			var needed = MinionManager.get_xp_needed(state["level"])
			xp_bar.max_value = needed
			xp_bar.value = state["xp"]
			xp_label.text = "%.0f / %.0f XP" % [state["xp"], needed]

		var plot = MinionManager.plot_of(minion.id)
		if plot != -1:
			plot_label.text = "Working Plot %d — earning XP from your harvests" % (plot + 1)
			plot_label.add_theme_color_override("font_color", COL_GOOD)
		else:
			plot_label.text = "Idle — click a graveyard plot below to put it to work"
			plot_label.remove_theme_color_override("font_color")
	else:
		_rebuild_cost_rows(minion)
		raise_button.disabled = not MinionManager.can_afford_raise(minion)
		raise_button.tooltip_text = "" if not raise_button.disabled else "You lack the materials for this rite"

## One "icon  name  have / need" row per rite material.
func _rebuild_cost_rows(minion: Minion) -> void:
	for child in cost_box.get_children():
		cost_box.remove_child(child)
		child.queue_free()

	var header = Label.new()
	header.text = "RAISING RITE"
	header.theme_type_variation = &"SectionLabel"
	cost_box.add_child(header)

	for item_id in minion.raise_cost:
		var needed: int = minion.raise_cost[item_id]
		if needed <= 0: continue
		var item = GameManager.find_item_by_id(item_id)
		var have = InventoryManager.get_item_count(item_id)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		if item and item.icon:
			var pic = TextureRect.new()
			pic.custom_minimum_size = Vector2(18, 18)
			pic.expand_mode = 1
			pic.stretch_mode = 5
			pic.texture = item.icon
			row.add_child(pic)

		var name_lbl = Label.new()
		name_lbl.text = item.name if item else item_id.capitalize()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", COL_TEXT_HI)
		row.add_child(name_lbl)

		var count_lbl = Label.new()
		count_lbl.text = "%d / %d" % [have, needed]
		count_lbl.add_theme_font_size_override("font_size", 12)
		count_lbl.add_theme_color_override("font_color", COL_GOOD if have >= needed else COL_BAD)
		row.add_child(count_lbl)

		cost_box.add_child(row)
