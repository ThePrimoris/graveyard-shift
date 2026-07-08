# ActionCard.gd
# One node/recipe card. Supports three harvest feels:
#  FILL     - a bar fills smoothly (digging graves)
#  DEPLETE  - a full bar loses a chunk per "hit" (mining strikes)
#  SEGMENTS - several bars deplete chunk by chunk, one after another (chopping)
class_name ActionCard
extends PanelContainer

signal action_triggered

enum ProgressMode { FILL, DEPLETE, SEGMENTS }

const HITS_PER_BAR: int = 4

@onready var icon_rect: TextureRect = %IconRect
@onready var title_label: Label = %TitleLabel
@onready var desc_label: Label = %DescLabel
@onready var drops_box: VBoxContainer = %DropsBox
@onready var stats_label: Label = %StatsLabel
@onready var action_button: Button = %ActionButton
@onready var progress_stack: VBoxContainer = %ProgressStack
@onready var segment_box: VBoxContainer = %SegmentBox

# The dig-layer meter (Graverobbing) is a distinct rusty colour from the smooth bar.
const SEGMENT_COLOR := Color("#b5623a")

var action_verb: String = "Start"
var mode: int = ProgressMode.FILL
var bar_color: Color = Color("#c8a24d")
var bars: Array = []
var segments: Array = []

func _ready() -> void:
	action_button.pressed.connect(_on_button_pressed)
	if bars.is_empty():
		_build_bars(1)

## Locked card: icon, name, description, and the unlock requirement.
func show_locked(desc_text: String, requirement_text: String) -> void:
	desc_label.visible = true
	desc_label.text = desc_text
	drops_box.visible = false
	stats_label.text = requirement_text
	stats_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5))
	action_button.visible = false
	progress_stack.visible = false
	segment_box.visible = false

## Unlocked card: icon, name, drops, XP/time, buttons, and progress bars.
func show_unlocked() -> void:
	desc_label.visible = false
	drops_box.visible = true
	stats_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.45))
	action_button.visible = true
	progress_stack.visible = true
	segment_box.visible = not segments.is_empty()

## Boss card: flavour text and a single "Confront" button, no harvesting.
func show_boss(desc_text: String, button_label: String) -> void:
	desc_label.visible = true
	desc_label.text = desc_text
	drops_box.visible = false
	stats_label.text = "☠ Boss Encounter"
	stats_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.45))
	action_button.visible = true
	action_button.text = button_label
	progress_stack.visible = false
	segment_box.visible = false

func setup_card(title_text: String, desc_text: String, verb: String, _max_duration: float) -> void:
	title_label.text = title_text
	desc_label.text = desc_text
	action_verb = verb
	action_button.text = action_verb

func set_icon(tex: Texture2D) -> void:
	if icon_rect:
		icon_rect.texture = tex

## Makes this card span two normal slots (used for boss nodes like the Crypt).
func set_large() -> void:
	custom_minimum_size = Vector2(538, 420)
	icon_rect.custom_minimum_size = Vector2(96, 96)

## Builds the right-side VERTICAL "dig-layer" meter (Graverobbing).
## `count` stacked sections; each full sweep of the horizontal bar removes the
## top one, until all are dug and the harvest completes. Pass 0 to hide it.
func set_dig_sections(count: int) -> void:
	for child in segment_box.get_children():
		child.queue_free()
	segments.clear()
	segment_box.visible = count > 0
	if count <= 0:
		return
	for i in range(count):
		var cell = Panel.new()
		cell.custom_minimum_size = Vector2(20, 34)
		cell.size_flags_horizontal = Control.SIZE_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = SEGMENT_COLOR
		style.set_corner_radius_all(3)
		style.set_border_width_all(1)
		style.border_color = Color(0.75, 0.42, 0.24)
		cell.add_theme_stylebox_override("panel", style)
		segment_box.add_child(cell)
		segments.append(cell)

## One tidy row per drop: [icon] Name ..... XX%. No wrapping, no ellipsis.
## entries: Array of { "item": Item, "chance": float }
func set_drops(entries: Array) -> void:
	for child in drops_box.get_children():
		child.queue_free()
	for entry in entries:
		var item: Item = entry["item"]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var pic = TextureRect.new()
		pic.custom_minimum_size = Vector2(22, 22)
		pic.expand_mode = 1
		pic.stretch_mode = 5
		pic.texture = item.icon
		row.add_child(pic)

		var name_lbl = Label.new()
		name_lbl.text = item.name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.7))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_lbl)

		var pct_lbl = Label.new()
		pct_lbl.text = "%d%%" % int(round(entry["chance"] * 100))
		pct_lbl.add_theme_font_size_override("font_size", 14)
		pct_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.8))
		row.add_child(pct_lbl)

		row.tooltip_text = "%s — %d%% chance per harvest" % [item.name, int(round(entry["chance"] * 100))]
		drops_box.add_child(row)

## XP and time readout, in its own reserved row so it never crowds the button.
func set_stats(xp: float, seconds: float) -> void:
	if stats_label:
		stats_label.text = "%.0f XP  •  %.1fs" % [xp, seconds]

func clear_stats() -> void:
	if stats_label:
		stats_label.text = ""

func set_progress_color(color: Color) -> void:
	bar_color = color
	_apply_bar_styles()

## Chooses the harvest feel. segment_count only matters for SEGMENTS mode.
func set_progress_mode(new_mode: int, segment_count: int = 1) -> void:
	mode = new_mode
	_build_bars(maxi(segment_count, 1) if new_mode == ProgressMode.SEGMENTS else 1)
	reset_progress()

func _build_bars(count: int) -> void:
	for child in progress_stack.get_children():
		child.queue_free()
	bars.clear()
	for i in range(count):
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 12 if count == 1 else 8)
		bar.max_value = 1.0
		bar.show_percentage = false
		progress_stack.add_child(bar)
		bars.append(bar)
	_apply_bar_styles()

func _apply_bar_styles() -> void:
	for bar in bars:
		var style := StyleBoxFlat.new()
		style.bg_color = bar_color
		style.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", style)

## Chunks t (0..1) into `steps` discrete notches, so bars visibly "take hits".
func _stepped(t: float, steps: int) -> float:
	return floor(clampf(t, 0.0, 1.0) * steps) / float(steps)

func update_progress(elapsed: float, duration: float) -> void:
	if duration <= 0.0: return
	var t = clampf(elapsed / duration, 0.0, 1.0)

	# Dig-layer nodes: the horizontal bar fills once PER section, and each full
	# sweep removes the top section from the vertical meter.
	var sn = segments.size()
	if sn > 0:
		var scaled = t * sn
		var dug = int(floor(scaled))
		if not bars.is_empty():
			bars[0].value = scaled - dug  # 0..1 within the current section
		for i in range(sn):
			# Top section (index 0) is removed first, then downward.
			segments[i].modulate.a = 0.14 if i < dug else 1.0
		return

	if not bars.is_empty():
		match mode:
			ProgressMode.FILL:
				bars[0].value = t
			ProgressMode.DEPLETE:
				bars[0].value = 1.0 - _stepped(t, HITS_PER_BAR + 1)
			ProgressMode.SEGMENTS:
				var n = bars.size()
				for i in range(n):
					var seg_t = clampf(t * n - i, 0.0, 1.0)
					bars[i].value = 1.0 - _stepped(seg_t, HITS_PER_BAR)

func reset_progress() -> void:
	for bar in bars:
		bar.value = 0.0 if mode == ProgressMode.FILL else 1.0
	for seg in segments:
		seg.modulate.a = 1.0

func set_button_text(is_active: bool) -> void:
	if action_button:
		action_button.text = "Stop" if is_active else "Start " + action_verb

func set_card_visibility(is_unlocked: bool) -> void:
	visible = is_unlocked

func _on_button_pressed() -> void:
	action_triggered.emit()
