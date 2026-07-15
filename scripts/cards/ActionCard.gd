# ActionCard.gd
# One node/recipe card in the Lanternlight design system: an elevated dark
# card with a skill-coloured accent frame, bonus chips and an XP chip up top,
# a centred title, a Common / Rare drop ledger, the node art in a well with
# the action button beneath it, and a full-width progress bar with inline %
# and a timer chip along the bottom.
# The horizontal bar always fills left to right, one sweep per harvest.
# Two optional vertical meters sit at the card's right edge:
#  dig_sections > 0  - a stacked layer meter; the bar fills once per layer
#                      and layers pop top-first (Lumbering).
#  hit_damage > 0    - a damage meter that fills a little per completed hit;
#                      at full the node breaks and it resets (Spelunking).
class_name ActionCard
extends PanelContainer

signal action_triggered

# Lanternlight tokens (mirror theme/graveyard_theme.tres).
const COL_CARD_BG := Color(0.078, 0.071, 0.11, 0.97)
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_RUST := Color(0.76, 0.353, 0.29)
const COL_RARE_TEXT := Color(0.88, 0.64, 0.6)
const COL_GREEN_TEXT := Color(0.55, 0.82, 0.5)
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
@onready var damage_meter: Panel = %DamageMeter
@onready var damage_fill: Panel = %DamageFill

var action_verb: String = "Harvest"
var node_title: String = ""
var bar_color: Color = Color("#d4a445")
var bars: Array = []
var segments: Array = []
var has_rare_table: bool = false
var has_damage_meter: bool = false
var damage_value: float = 0.0

# Change-detection keys: update_ui runs every game tick, and rebuilding
# children mid-hover destroys the control a tooltip is anchored to (the
# "tooltips vanish after a second" bug). Skip rebuilds when nothing changed.
var _drops_key: String = ""
var _bonus_key: String = ""

## The node's affix metadata (from GameManager.get_affix_info), or {} for none.
## Rendered as the first chip in the top row by set_bonuses.
var _affix_info: Dictionary = {}

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
	damage_meter.visible = false
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
	damage_meter.visible = has_damage_meter
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
	damage_meter.visible = false
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
	custom_minimum_size = Vector2(1014, 0)
	icon_rect.custom_minimum_size = Vector2(120, 120)

# --- Bonus chips (top-left row) ---

## Stores the node's affix metadata so the next set_bonuses renders its chip.
## Pass {} to clear. The chip only rebuilds when the affix name changes.
func set_affix(info: Dictionary) -> void:
	_affix_info = info

## Renders one small "glyph +X%" pill per ACTIVE gather bonus, straight from
## GameManager.get_gather_modifiers(node). Only non-zero bonuses show, so a
## fresh-start card is bare and chips appear as the player earns them.
func set_bonuses(mods: Dictionary) -> void:
	var speed_pct := int(round((float(mods.get("speed_mult", 1.0)) - 1.0) * 100))
	var double_pct := int(round(float(mods.get("double_chance", 0.0)) * 100))
	var xp_pct := int(round((float(mods.get("xp_mult", 1.0)) - 1.0) * 100))
	var rare_pct := float(mods.get("rare_add", 0.0)) * 100.0

	var key = "%d|%d|%d|%.2f|%s" % [speed_pct, double_pct, xp_pct, rare_pct, str(_affix_info.get("name", ""))]
	if key == _bonus_key:
		chips_row.visible = columns.visible and chips_row.get_child_count() > 0
		return
	_bonus_key = key
	_clear_children(chips_row)

	if not _affix_info.is_empty():
		var live: bool = bool(_affix_info.get("active", false))
		chips_row.add_child(_make_stat_chip("⚠", str(_affix_info.get("name", "")),
			COL_RUST if live else COL_TEXT_MID, str(_affix_info.get("blurb", ""))))

	if speed_pct > 0:
		chips_row.add_child(_make_stat_chip("⚡", "+%d%%" % speed_pct, COL_TEXT_HI,
			"Harvest speed — this node finishes %d%% faster" % speed_pct))
	if double_pct > 0:
		chips_row.add_child(_make_stat_chip("⧉", "+%d%%" % double_pct, COL_TEXT_HI,
			"Yield — %d%% chance for double the everyday haul" % double_pct))
	if xp_pct > 0:
		chips_row.add_child(_make_stat_chip("✦", "+%d%%" % xp_pct, COL_GREEN_TEXT,
			"Bonus skill XP from slotted minions"))
	if rare_pct > 0.0:
		chips_row.add_child(_make_stat_chip("◆", "+%s" % _fmt_pct(rare_pct), COL_RARE_TEXT,
			"Added rare-find chance from slotted minions"))

	chips_row.visible = columns.visible and chips_row.get_child_count() > 0

func _make_stat_chip(glyph: String, value_text: String, value_color: Color, tip: String) -> PanelContainer:
	var chip = PanelContainer.new()
	chip.theme_type_variation = &"ChipPanel"
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)

	var tag = Label.new()
	tag.text = glyph
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", COL_TEXT_MID)
	row.add_child(tag)

	var val = Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", value_color)
	row.add_child(val)

	chip.tooltip_text = tip
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
## Default columns: "Common" and "Rare — X%" (rare_chance feeds the header).
## break_mode (Spelunking's breakable nodes) relabels them: "Hit Chance"
## (per-hit odds, may pay nothing) and "Break" (guaranteed haul on break).
func set_drops(common: Array, rare: Array, rare_chance: float = 0.0, break_mode: bool = false) -> void:
	var key = "%s|%s|%.4f|%s" % [str(common), str(rare), rare_chance, str(break_mode)]
	if key == _drops_key:
		return
	_drops_key = key

	_clear_children(common_box)
	_clear_children(rare_box)

	if break_mode:
		common_header.text = "Hit Chance"
		common_header.tooltip_text = "Each completed %s has these odds to shake loot loose" \
			% String(VERB_NOUNS.get(action_verb, "harvest")).to_lower()
	else:
		common_header.text = "Common"
		common_header.tooltip_text = ""

	if common.is_empty():
		common_box.add_child(_make_empty_row())
	for entry in common:
		common_box.add_child(_make_drop_row(entry, false, "chance per hit" if break_mode else "of this table's drops"))

	if break_mode:
		has_rare_table = not rare.is_empty()
		rare_header.text = "Break"
		rare_header.tooltip_text = "Guaranteed haul when the node's health breaks"
		for entry in rare:
			rare_box.add_child(_make_drop_row(entry, true, "of the break haul"))
	else:
		has_rare_table = not rare.is_empty() and rare_chance > 0.0
		if has_rare_table:
			rare_header.text = "Rare — %s" % _fmt_pct(rare_chance * 100.0)
			rare_header.tooltip_text = "%s chance per %s to also roll this table" \
				% [_fmt_pct(rare_chance * 100.0), String(VERB_NOUNS.get(action_verb, "harvest")).to_lower()]
			for entry in rare:
				rare_box.add_child(_make_drop_row(entry, true, "of this table's drops"))
	divider.visible = has_rare_table and columns.visible
	rare_col.visible = has_rare_table and columns.visible

## One ledger row: "1–3  [icon]  27%". The item name lives in the tooltip.
func _make_drop_row(entry: Dictionary, is_rare: bool, context: String = "of this table's drops") -> Control:
	var item: Item = entry["item"]
	var pct: float = entry["pct"]
	var qty := _fmt_amount(entry.get("min_amount", 1), entry.get("max_amount", 1))

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = "%s ×%s — %s %s" % [item.name, qty, _fmt_pct(pct), context]

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

## Shows the vertical damage meter for breakable nodes. `hit_damage` is the
## share of the node's health one completed bar removes (0 hides the meter).
func set_damage_meter(hit_damage: float) -> void:
	has_damage_meter = hit_damage > 0.0
	damage_meter.visible = has_damage_meter and columns.visible
	if has_damage_meter:
		var hits = int(ceil(1.0 / hit_damage))
		damage_meter.tooltip_text = "Node integrity — each %s deals %d%% damage; it breaks after %d and pays its break haul." \
			% [String(VERB_NOUNS.get(action_verb, "harvest")).to_lower(), int(round(hit_damage * 100)), hits]

## Fills the damage meter bottom-to-top: 0.25 dealt = the bottom 25% of the
## track. Called by the view as hits land; a break resets it to 0.
func update_damage(dealt: float) -> void:
	damage_value = clampf(dealt, 0.0, 1.0)
	# Dig-layer nodes (Lumbering): the discrete section meter falls as the node
	# is chopped down — one section per completed bar, top removed first, and it
	# springs back to full when the node falls and break progress resets to 0.
	if not segments.is_empty():
		var sn = segments.size()
		var gone = int(floor(damage_value * sn + 0.0001))
		for i in range(sn):
			segments[i].modulate.a = 0.14 if i < gone else 1.0
		return
	# Breakable nodes (Spelunking): a continuous vertical integrity meter.
	if damage_fill:
		damage_fill.anchor_top = 1.0 - damage_value
		damage_fill.offset_top = 2.0 if damage_value >= 0.999 else 0.0
		damage_fill.visible = damage_value > 0.0

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

## Bar backgrounds come from the theme; only the fills take the skill colour.
func _apply_bar_styles() -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = bar_color
	fill.set_corner_radius_all(5)
	for bar in bars:
		bar.add_theme_stylebox_override("fill", fill)
	if damage_fill:
		var dmg_style := StyleBoxFlat.new()
		dmg_style.bg_color = Color(bar_color.r, bar_color.g, bar_color.b).lightened(0.15)
		dmg_style.set_corner_radius_all(4)
		damage_fill.add_theme_stylebox_override("panel", dmg_style)

func update_progress(elapsed: float, duration: float) -> void:
	if duration <= 0.0: return
	var t = clampf(elapsed / duration, 0.0, 1.0)
	if pct_label:
		pct_label.text = "%d%%" % int(round(t * 100))

	# One filled bar = one chop/hit. Section depletion (dig nodes) is driven by
	# break progress in update_damage, not within-bar progress, so the bar just
	# shows the current chop's fill for every node type.
	if not bars.is_empty():
		bars[0].value = t

func reset_progress() -> void:
	for bar in bars:
		bar.value = 0.0
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
