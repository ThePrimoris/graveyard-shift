# ActionCard.gd
# One node/recipe card in the Lanternlight design system: an elevated dark
# card with a skill-coloured accent frame, bonus chips and an XP chip up top,
# a centred title, a Common / Rare drop ledger, the node art in a well with
# the action button beneath it, and a full-width progress bar with inline %
# and a timer chip along the bottom.
# Supports two harvest feels:
#  FILL     - the bar fills smoothly (digging, chopping)
#  DEPLETE  - a full bar loses a chunk per "hit" (mining strikes)
# Nodes with dig_sections > 0 additionally show a vertical layer meter on the
# right; the bottom bar then fills once per layer (used by Lumbering).
class_name ActionCard
extends PanelContainer

signal action_triggered

enum ProgressMode { FILL, DEPLETE }

const HITS_PER_BAR: int = 4

# Lanternlight tokens (mirror theme/graveyard_theme.tres).
const COL_CARD_BG := Color(0.078, 0.071, 0.11, 0.97)
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_RUST := Color(0.76, 0.353, 0.29)
const COL_RARE_TEXT := Color(0.88, 0.64, 0.6)
const SEGMENT_COLOR := Color("#b5623a")

# Gerund the views hand us -> the noun used in headers and on the button.
const VERB_NOUNS := {"Chopping": "Cut", "Mining": "Break", "Digging": "Dig"}

@onready var top_row: HBoxContainer = %TopRow
@onready var chips_row: HBoxContainer = %ChipsRow
@onready var xp_chip: PanelContainer = %XPChip
@onready var xp_label: Label = %XPLabel
@onready var title_label: Label = %TitleLabel
@onready var body: HBoxContainer = %Body
@onready var info_col: VBoxContainer = %InfoCol
@onready var desc_label: Label = %DescLabel
@onready var stats_label: Label = %StatsLabel
@onready var columns: HBoxContainer = %Columns
@onready var common_header: Label = %CommonHeader
@onready var common_box: VBoxContainer = %CommonBox
@onready var divider: Panel = %Divider
@onready var rare_col: VBoxContainer = %RareCol
@onready var rare_header: Label = %RareHeader
@onready var rare_box: VBoxContainer = %RareBox
@onready var bottom_row: HBoxContainer = %BottomRow
@onready var progress_stack: VBoxContainer = %ProgressStack
@onready var pct_label: Label = %PctLabel
@onready var time_label: Label = %TimeLabel
@onready var icon_rect: TextureRect = %IconRect
@onready var action_button: Button = %ActionButton
@onready var segment_box: VBoxContainer = %SegmentBox

var action_verb: String = "Harvest"
var node_title: String = ""
var mode: int = ProgressMode.FILL
var bar_color: Color = Color("#d4a445")
var bars: Array = []
var segments: Array = []
var has_rare_table: bool = false

func _ready() -> void:
	action_button.pressed.connect(_on_button_pressed)
	if bars.is_empty():
		_build_bar()

# --- Card states ---

## Locked card: rust "Locked" title, flavour text and the requirement on the
## left, the node art dimmed to a silhouette on the right.
func show_locked(desc_text: String, requirement_text: String) -> void:
	title_label.text = "Locked"
	title_label.add_theme_color_override("font_color", COL_RUST)
	desc_label.visible = true
	desc_label.text = desc_text
	stats_label.visible = true
	stats_label.text = requirement_text
	top_row.visible = false
	columns.visible = false
	bottom_row.visible = false
	segment_box.visible = false
	action_button.visible = false
	icon_rect.self_modulate = Color(0.1, 0.1, 0.12)

## Unlocked card: chips, drop ledger, art, button, and the bottom bar.
func show_unlocked() -> void:
	title_label.text = node_title
	title_label.remove_theme_color_override("font_color")
	desc_label.visible = false
	stats_label.visible = false
	top_row.visible = true
	chips_row.visible = chips_row.get_child_count() > 0
	columns.visible = true
	divider.visible = has_rare_table
	rare_col.visible = has_rare_table
	bottom_row.visible = true
	segment_box.visible = not segments.is_empty()
	action_button.visible = true
	icon_rect.self_modulate = Color.WHITE

## Boss card: flavour text and a single "Confront" button, no harvesting.
func show_boss(desc_text: String, button_label: String) -> void:
	title_label.text = node_title
	title_label.remove_theme_color_override("font_color")
	desc_label.visible = true
	desc_label.text = desc_text
	stats_label.visible = true
	stats_label.text = "☠ Boss Encounter"
	stats_label.add_theme_color_override("font_color", COL_RUST)
	top_row.visible = false
	columns.visible = false
	bottom_row.visible = false
	segment_box.visible = false
	action_button.visible = true
	action_button.text = button_label
	action_button.theme_type_variation = &"DangerButton"
	icon_rect.self_modulate = Color.WHITE

# --- Setup ---

func setup_card(title_text: String, desc_text: String, verb: String, _max_duration: float) -> void:
	node_title = title_text
	title_label.text = title_text
	desc_label.text = desc_text
	action_verb = verb
	action_button.text = String(VERB_NOUNS.get(verb, "Harvest"))

func set_icon(tex: Texture2D) -> void:
	if icon_rect:
		icon_rect.texture = tex

## Makes this card span two normal slots (used for boss nodes like the Crypt).
func set_large() -> void:
	custom_minimum_size = Vector2(954, 0)
	icon_rect.custom_minimum_size = Vector2(120, 120)

# --- Bonus chips (top-left row) ---

## Small "icon +X%" pills for the active tool and skill speed bonuses.
## Pass a null texture to fall back to a text tag.
func set_bonuses(tool_icon: Texture2D, tool_pct: int, skill_icon: Texture2D, skill_pct: int) -> void:
	_clear_children(chips_row)
	chips_row.add_child(_make_chip(tool_icon, "Tool", "+%d%%" % tool_pct))
	chips_row.add_child(_make_chip(skill_icon, "Skill", "+%d%%" % skill_pct))
	chips_row.visible = columns.visible

func _make_chip(icon: Texture2D, fallback: String, value_text: String) -> PanelContainer:
	var chip = PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	if icon:
		var pic = TextureRect.new()
		pic.custom_minimum_size = Vector2(20, 20)
		pic.expand_mode = 1
		pic.stretch_mode = 5
		pic.texture = icon
		row.add_child(pic)
	else:
		var tag = Label.new()
		tag.text = fallback
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", COL_TEXT_MID)
		row.add_child(tag)

	var val = Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", COL_TEXT_HI)
	row.add_child(val)
	chip.tooltip_text = "%s bonus: %s speed" % [fallback, value_text]
	return chip

# --- Dig-layer meter (Lumbering) ---

## Builds the right-side VERTICAL layer meter. `count` stacked sections;
## the meter loses its top section at each 1/n mark of the harvest. Pass 0 to hide.
func set_dig_sections(count: int) -> void:
	_clear_children(segment_box)
	segments.clear()
	segment_box.visible = count > 0
	if count <= 0:
		return
	for i in range(count):
		var cell = Panel.new()
		cell.custom_minimum_size = Vector2(16, 22)
		cell.size_flags_horizontal = Control.SIZE_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = SEGMENT_COLOR
		style.set_corner_radius_all(3)
		style.set_border_width_all(1)
		style.border_color = Color(0.75, 0.42, 0.24)
		cell.add_theme_stylebox_override("panel", style)
		segment_box.add_child(cell)
		segments.append(cell)

# --- Drop ledger: Common column + Rare column ---

## common / rare: Arrays of { "item": Item, "pct": float (0..100),
## "min_amount": int, "max_amount": int }, already sorted by share.
## rare_chance (0..1) feeds the rare column header, e.g. "Rare — 1%".
func set_drops(common: Array, rare: Array, rare_chance: float = 0.0) -> void:
	_clear_children(common_box)
	_clear_children(rare_box)

	if common.is_empty():
		common_box.add_child(_make_empty_row())
	for entry in common:
		common_box.add_child(_make_drop_row(entry, false))

	has_rare_table = not rare.is_empty() and rare_chance > 0.0
	if has_rare_table:
		rare_header.text = "Rare — %s" % _fmt_pct(rare_chance * 100.0)
		rare_header.tooltip_text = "%s chance per %s to also roll this table" \
			% [_fmt_pct(rare_chance * 100.0), String(VERB_NOUNS.get(action_verb, "harvest")).to_lower()]
		for entry in rare:
			rare_box.add_child(_make_drop_row(entry, true))
	divider.visible = has_rare_table and columns.visible
	rare_col.visible = has_rare_table and columns.visible

## One ledger row: "1–3  [icon]  27%". The item name lives in the tooltip.
func _make_drop_row(entry: Dictionary, is_rare: bool) -> Control:
	var item: Item = entry["item"]
	var pct: float = entry["pct"]
	var qty := _fmt_amount(entry.get("min_amount", 1), entry.get("max_amount", 1))

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = "%s ×%s — %s of this table's drops" % [item.name, qty, _fmt_pct(pct)]

	var qty_lbl = Label.new()
	qty_lbl.text = qty
	qty_lbl.custom_minimum_size = Vector2(26, 0)
	qty_lbl.add_theme_font_size_override("font_size", 12)
	qty_lbl.add_theme_color_override("font_color", COL_TEXT_MID)
	row.add_child(qty_lbl)

	var pic = TextureRect.new()
	pic.custom_minimum_size = Vector2(20, 20)
	pic.expand_mode = 1
	pic.stretch_mode = 5
	pic.texture = item.icon
	row.add_child(pic)

	var name_lbl = Label.new()
	name_lbl.text = item.name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", COL_RARE_TEXT if is_rare else COL_TEXT_HI)
	row.add_child(name_lbl)

	var pct_lbl = Label.new()
	pct_lbl.text = _fmt_pct(pct)
	pct_lbl.add_theme_font_size_override("font_size", 12)
	pct_lbl.add_theme_color_override("font_color", COL_TEXT_MID)
	row.add_child(pct_lbl)
	return row

func _make_empty_row() -> Control:
	var lbl = Label.new()
	lbl.text = "—"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", COL_TEXT_MID)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl

func _fmt_amount(min_a: int, max_a: int) -> String:
	return str(min_a) if max_a <= min_a else "%d–%d" % [min_a, max_a]

func _fmt_pct(pct: float) -> String:
	return "%.2f%%" % pct if pct < 1.0 else "%d%%" % int(round(pct))

# --- Stats chips ---

## XP goes in the green chip on the top row; time in the timer chip.
## `base_seconds` (if given) feeds the tooltip that explains speed bonuses.
func set_stats(xp: float, seconds: float, base_seconds: float = 0.0) -> void:
	if xp_label:
		xp_label.text = "+%d XP" % int(round(xp))
	if time_label:
		time_label.text = "%.2fs" % seconds
	if %TimeChip and base_seconds > 0.0:
		if base_seconds > seconds + 0.005:
			%TimeChip.tooltip_text = "Base %.2fs — %d%% faster from tool & skill bonuses" \
				% [base_seconds, int(round((base_seconds / seconds - 1.0) * 100))]
		else:
			%TimeChip.tooltip_text = "Base %.2fs" % base_seconds

func clear_stats() -> void:
	if stats_label:
		stats_label.text = ""

# --- Progress ---

## Also frames the card with the skill's accent colour (thicker top edge).
func set_progress_color(color: Color) -> void:
	bar_color = color
	_apply_bar_styles()
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD_BG
	s.set_border_width_all(1)
	s.border_width_top = 3
	s.border_color = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6)
	s.set_corner_radius_all(10)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", s)

## Chooses the harvest feel.
func set_progress_mode(new_mode: int) -> void:
	mode = new_mode
	if bars.is_empty():
		_build_bar()
	reset_progress()

func _build_bar() -> void:
	_clear_children(progress_stack)
	bars.clear()
	var bar = ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progress_stack.add_child(bar)
	bars.append(bar)
	_apply_bar_styles()

## Bar backgrounds come from the theme; only the fill takes the skill colour.
func _apply_bar_styles() -> void:
	for bar in bars:
		var fill := StyleBoxFlat.new()
		fill.bg_color = bar_color
		fill.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("fill", fill)

## Chunks t (0..1) into `steps` discrete notches, so bars visibly "take hits".
func _stepped(t: float, steps: int) -> float:
	return floor(clampf(t, 0.0, 1.0) * steps) / float(steps)

func update_progress(elapsed: float, duration: float) -> void:
	if duration <= 0.0: return
	var t = clampf(elapsed / duration, 0.0, 1.0)
	if pct_label:
		pct_label.text = "%d%%" % int(round(t * 100))

	# Dig-layer nodes: the bottom bar fills once per section, and a section
	# only pops off the vertical meter when the bar completes a full sweep.
	# The % label still reads overall harvest progress.
	var sn = segments.size()
	if sn > 0:
		var scaled = t * sn
		var done = int(floor(scaled))
		if not bars.is_empty():
			bars[0].value = 1.0 if done >= sn else scaled - done  # 0..1 within the current section
		for i in range(sn):
			# Top section (index 0) is removed first, then downward.
			segments[i].modulate.a = 0.14 if i < done else 1.0
		return

	if not bars.is_empty():
		match mode:
			ProgressMode.FILL:
				bars[0].value = t
			ProgressMode.DEPLETE:
				bars[0].value = 1.0 - _stepped(t, HITS_PER_BAR + 1)

func reset_progress() -> void:
	for bar in bars:
		bar.value = 0.0 if mode == ProgressMode.FILL else 1.0
	for seg in segments:
		seg.modulate.a = 1.0
	if pct_label:
		pct_label.text = "0%"

# --- Misc ---

## Short verbs ("Cut" / "Break" / "Dig") in green; rust "Stop" while active.
func set_button_text(is_active: bool) -> void:
	if action_button:
		action_button.text = "Stop" if is_active else String(VERB_NOUNS.get(action_verb, "Harvest"))
		action_button.theme_type_variation = &"DangerButton" if is_active else &"ActionButton"

func set_card_visibility(is_unlocked: bool) -> void:
	visible = is_unlocked

## remove_child before queue_free so a rebuild within the same frame
## never counts soon-to-die nodes.
func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _on_button_pressed() -> void:
	action_triggered.emit()
