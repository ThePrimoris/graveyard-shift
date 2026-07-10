# SettingsPanel.gd
# Settings overlay, opened from the top navigation bar. Built in code on a
# CanvasLayer so it centers on screen above everything, like the passive tree.
extends CanvasLayer

var reset_button: Button
var saved_label: Label
var _reset_armed: bool = false

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
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(360, 0)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var version = Label.new()
	version.text = "%s v%s" % [GameManager.game_title, GameManager.game_version]
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(version)

	vbox.add_child(HSeparator.new())

	var save_btn = Button.new()
	save_btn.text = "Save Now"
	save_btn.custom_minimum_size = Vector2(0, 40)
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)

	saved_label = Label.new()
	saved_label.text = " "
	saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	saved_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	vbox.add_child(saved_label)

	vbox.add_child(HSeparator.new())

	var reset_warning = Label.new()
	reset_warning.text = "Danger zone: wipes all skills, minions,\nitems, essence, and the save file."
	reset_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset_warning.add_theme_font_size_override("font_size", 12)
	reset_warning.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
	vbox.add_child(reset_warning)

	reset_button = Button.new()
	reset_button.text = "Hard Reset Progress"
	reset_button.custom_minimum_size = Vector2(0, 40)
	reset_button.pressed.connect(_on_reset_pressed)
	vbox.add_child(reset_button)

	vbox.add_child(HSeparator.new())

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(160, 36)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)

func _on_save_pressed() -> void:
	SaveManager.save_game()
	saved_label.text = "Game saved."

func _on_reset_pressed() -> void:
	if not _reset_armed:
		# Two-step confirmation so a stray click can't wipe the run
		_reset_armed = true
		reset_button.text = "Are you SURE? Click again to wipe"
		reset_button.modulate = Color(1.0, 0.45, 0.45)
		return

	SaveManager.hard_reset()
	queue_free()
