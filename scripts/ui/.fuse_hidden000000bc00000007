# PlotsBar.gd
# The Graveyard Plots dock at the bottom center of the screen: a central
# circle flanked by plots 1-2 on the left and 3-4 on the right.
# Clicking a plot opens a grid of raised minions to slot into it; slotted
# minions earn XP from every harvest (see MinionManager).
extends Control

const COL_ACCENT := Color("#8a6fbe")
const NECRONOMICON_SCRIPT = preload("res://scripts/ui/NecronomiconPanel.gd")

var plot_buttons: Array = []
var picker: PopupPanel = null
var open_book: Node = null

@onready var circle_button: Button = %CircleButton

func _ready() -> void:
	add_to_group("ui_updates")

	for i in range(1, 5):
		var btn: Button = get_node("%%PlotButton%d" % i)
		plot_buttons.append(btn)
		btn.pressed.connect(_on_plot_pressed.bind(i - 1))

	circle_button.pressed.connect(_on_circle_pressed)
	MinionManager.minions_updated.connect(update_ui)
	update_ui()

func _on_plot_pressed(index: int) -> void:
	if MinionManager.roster.is_empty():
		if MinionManager.necronomicon_unlocked:
			NotificationManager.show_item("No minions raised yet — open the Necronomicon at the circle", 1)
		else:
			NotificationManager.show_item("The plots wait for occupants that do not yet exist", 1)
		return
	_open_picker(index)

## The circle opens the Necronomicon once it has been found.
func _on_circle_pressed() -> void:
	if not MinionManager.necronomicon_unlocked:
		NotificationManager.show_item("The circle lies dormant... for now.", 1)
		return
	if is_instance_valid(open_book):
		open_book.queue_free()
		open_book = null
		return
	open_book = NECRONOMICON_SCRIPT.new()
	get_tree().root.add_child(open_book)

# --- Minion picker: a grid of raised minions for this plot ---

func _open_picker(plot_index: int) -> void:
	_close_picker()

	picker = PopupPanel.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.078, 0.071, 0.11, 0.99)
	pstyle.set_border_width_all(1)
	pstyle.border_color = Color(COL_ACCENT.r * 0.6, COL_ACCENT.g * 0.6, COL_ACCENT.b * 0.6)
	pstyle.set_corner_radius_all(10)
	pstyle.content_margin_left = 12
	pstyle.content_margin_right = 12
	pstyle.content_margin_top = 10
	pstyle.content_margin_bottom = 12
	picker.add_theme_stylebox_override("panel", pstyle)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	picker.add_child(col)

	var title = Label.new()
	title.text = "PLOT %d" % (plot_index + 1)
	title.theme_type_variation = &"SectionLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)

	for minion_id in MinionManager.sorted_ids(true):
		grid.add_child(_make_minion_tile(minion_id, plot_index))

	if MinionManager.plots[plot_index] != "":
		var vacate = Button.new()
		vacate.text = "Vacate plot"
		vacate.theme_type_variation = &"DangerButton"
		vacate.custom_minimum_size = Vector2(0, 30)
		vacate.pressed.connect(func():
			MinionManager.vacate_plot(plot_index)
			_close_picker())
		col.add_child(vacate)

	add_child(picker)
	picker.popup_hide.connect(_close_picker)

	# Sit the picker just above the clicked plot button.
	var btn: Button = plot_buttons[plot_index]
	picker.reset_size()
	var size = picker.get_contents_minimum_size() + Vector2(24, 22)
	var pos = btn.get_screen_position() + Vector2(btn.size.x * 0.5 - size.x * 0.5, -size.y - 10)
	picker.popup(Rect2i(Vector2i(pos), Vector2i(size)))

## One tile in the picker grid: the minion's icon (or initial), name, level.
## Gold-edged when it already occupies the plot being edited.
func _make_minion_tile(minion_id: String, plot_index: int) -> Button:
	var minion = MinionManager.find_minion_by_id(minion_id)
	var tile = Button.new()
	tile.custom_minimum_size = Vector2(104, 88)

	var here = MinionManager.plots[plot_index] == minion_id
	var elsewhere = MinionManager.plot_of(minion_id)
	var suffix = ""
	if here: suffix = "  (here)"
	elif elsewhere != -1: suffix = "  (Plot %d)" % (elsewhere + 1)

	tile.text = "%s\nLv %d%s" % [minion.name, MinionManager.get_level(minion_id), suffix]
	if minion.icon:
		tile.icon = minion.icon
		tile.expand_icon = true
		tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_theme_font_size_override("font_size", 12)
	tile.tooltip_text = "%s — HP %d, ATK %.1f" % [minion.name, MinionManager.get_hp(minion_id), MinionManager.get_atk(minion_id)]

	if here:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.125, 0.113, 0.17)
		s.set_border_width_all(1)
		s.border_color = Color(0.83, 0.64, 0.27)
		s.set_corner_radius_all(8)
		tile.add_theme_stylebox_override("normal", s)

	tile.pressed.connect(func():
		MinionManager.assign_to_plot(minion_id, plot_index)
		_close_picker())
	return tile

func _close_picker() -> void:
	if is_instance_valid(picker):
		picker.queue_free()
	picker = null

# --- Plot button faces ---

func update_ui() -> void:
	if circle_button:
		circle_button.tooltip_text = "The Necronomicon" if MinionManager.necronomicon_unlocked \
			else "The graveyard's heart. Its purpose will be revealed."
	for i in range(plot_buttons.size()):
		var btn: Button = plot_buttons[i]
		var occupant: String = MinionManager.plots[i] if i < MinionManager.plots.size() else ""
		if occupant == "":
			btn.text = str(i + 1)
			btn.icon = null
			btn.tooltip_text = "Graveyard Plot %d — empty. Click to slot a minion." % (i + 1)
		else:
			var minion = MinionManager.find_minion_by_id(occupant)
			if minion and minion.icon:
				btn.icon = minion.icon
				btn.expand_icon = true
				btn.text = ""
			else:
				btn.icon = null
				btn.text = minion.name.left(1) if minion else "?"
			btn.tooltip_text = "Graveyard Plot %d — %s (Lv %d). Click to change." \
				% [i + 1, minion.name if minion else occupant, MinionManager.get_level(occupant)]
