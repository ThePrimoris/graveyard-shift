extends PanelContainer

@onready var inv_btn: Button = %InventoryNavButton
@onready var shop_btn: Button = %ShopNavButton
@onready var grave_btn: Button = %Graverobbing
@onready var lumber_btn: Button = %Lumbering
@onready var spelunk_btn: Button = %Spelunking
@onready var alchemy_btn: Button = %Alchemy
@onready var forge_btn: Button = %Forge

@onready var grave_xp: Label = %GraverobbingXPLabel
@onready var lumber_xp: Label = %LumberingXPLabel
@onready var spelunk_xp: Label = %SpelunkingXPLabel
@onready var alchemy_xp: Label = %AlchemyXPLabel
@onready var forge_xp: Label = %ForgeXPLabel

@onready var gold_lbl: Label = %GoldValueLabel
@onready var restoration_lbl: Label = %RestorationLabel

## Timed-buff channels (elixirs drunk, incense burned) worth a sidebar line,
## with the short name each line shows.
const BUFF_CHANNELS := {
	Ids.EFFECT_HARVEST_XP_PCT: "harvest XP",
	Ids.EFFECT_RARE_CHANCE_PCT: "rare finds",
	Ids.EFFECT_DOUBLE_DROP_PCT: "double harvests",
	Ids.EFFECT_EXHAUST_HASTE_PCT: "rest haste",
	Ids.EFFECT_OFFLINE_GAIN_PCT: "offline gains",
}

## effect channel -> its code-built row {name: Label, info: Label, box}.
var buff_rows: Dictionary = {}
## Row container inside the reserved buffs section.
var buffs_box: VBoxContainer
var buffs_empty: Label

func _ready() -> void:
	add_to_group(Ids.GROUP_UI_UPDATES)
	_build_buffs_section()

## The dedicated "Active Buffs" home under the currency block. Its height is
## reserved up front so buffs coming and going never reflow the sidebar.
func _build_buffs_section() -> void:
	var currency_margin = restoration_lbl.get_parent().get_parent()
	var side_vbox = currency_margin.get_parent()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	side_vbox.add_child(margin)
	side_vbox.move_child(margin, currency_margin.get_index() + 1)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	margin.add_child(col)

	var header = Label.new()
	header.text = "ACTIVE BUFFS"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.6, 0.565, 0.66))
	col.add_child(header)

	buffs_box = VBoxContainer.new()
	# Room for three name+effect rows, held even while empty.
	buffs_box.custom_minimum_size = Vector2(0, 112)
	buffs_box.add_theme_constant_override("separation", 6)
	col.add_child(buffs_box)

	buffs_empty = Label.new()
	buffs_empty.text = "None — drink an elixir\nor burn an incense."
	buffs_empty.add_theme_font_size_override("font_size", 11)
	buffs_empty.add_theme_color_override("font_color", Color(0.45, 0.42, 0.5))
	buffs_box.add_child(buffs_empty)

	shop_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_SHOP))
	inv_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_INVENTORY))
	grave_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_GRAVEYARD))
	lumber_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_FOREST))
	spelunk_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_QUARRY))
	alchemy_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_ALCHEMY))
	forge_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_FORGE))

	update_ui()

func update_ui() -> void:
	_update_row(Ids.SKILL_GRAVEROBBING, grave_btn, grave_xp)
	_update_row(Ids.SKILL_LUMBERING, lumber_btn, lumber_xp)
	_update_row(Ids.SKILL_SPELUNKING, spelunk_btn, spelunk_xp)
	_update_row(Ids.SKILL_ALCHEMY, alchemy_btn, alchemy_xp)
	_update_row(Ids.SKILL_FORGE, forge_btn, forge_xp)

	if gold_lbl:
		gold_lbl.text = "Gold: %d" % GameManager.gold_coins
	if restoration_lbl:
		restoration_lbl.text = "Restored: %.1f%%" % StatsManager.get_restoration_pct()
	_update_buff_lines()

## The live countdowns need a clock, not just update_ui events.
func _process(_delta: float) -> void:
	_update_buff_lines()

func _update_buff_lines() -> void:
	if buffs_box == null: return
	var live: Array = []
	for effect in BUFF_CHANNELS:
		if GameManager.buff_seconds_left(effect) > 0.0:
			live.append(effect)

	# Rebuild the rows only when the set of live buffs changes.
	var changed: bool = live.size() != buff_rows.size()
	for effect in live:
		if not buff_rows.has(effect):
			changed = true
	if changed:
		for effect in buff_rows:
			buff_rows[effect]["box"].queue_free()
		buff_rows.clear()
		for effect in live:
			var box = VBoxContainer.new()
			box.add_theme_constant_override("separation", 0)
			var name_lbl = Label.new()
			name_lbl.add_theme_font_size_override("font_size", 12)
			name_lbl.add_theme_color_override("font_color", Color(0.83, 0.64, 0.27))
			name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			box.add_child(name_lbl)
			var info_lbl = Label.new()
			info_lbl.add_theme_font_size_override("font_size", 11)
			info_lbl.add_theme_color_override("font_color", Color("#8fd0b2"))
			box.add_child(info_lbl)
			buffs_box.add_child(box)
			buff_rows[effect] = {"box": box, "name": name_lbl, "info": info_lbl}
	buffs_empty.visible = live.is_empty()

	for effect in buff_rows:
		var buff: Dictionary = GameManager.active_buffs.get(effect, {})
		var source := String(buff.get("source", ""))
		buff_rows[effect]["name"].text = source if source != "" else BUFF_CHANNELS[effect].capitalize()
		buff_rows[effect]["info"].text = "+%.0f%% %s — %s" % [
			GameManager.get_buff_bonus(effect), BUFF_CHANNELS[effect],
			_fmt_time_left(GameManager.buff_seconds_left(effect))]

func _fmt_time_left(seconds: float) -> String:
	var s := int(ceil(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d:%02d" % [s / 60, s % 60]
	return "%ds" % s

func _update_row(skill_id: String, btn: Button, lbl: Label) -> void:
	var data = GameManager.skills[skill_id]
	btn.text = skill_id.capitalize()

	lbl.text = "(%d/%d)" % [data["level"], GameManager.MAX_LEVEL]
	if data["level"] >= GameManager.MAX_LEVEL:
		lbl.tooltip_text = "Mastered!"
	else:
		var needed = GameManager.get_xp_needed(data["level"])
		lbl.tooltip_text = "%.0f / %.0f XP to next level" % [data["xp"], needed]

func _on_nav_pressed(target: String) -> void:
	AudioManager.play_sfx(Ids.SFX_UI_CLICK)
	get_tree().call_group(Ids.GROUP_VIEW_MANAGER, "switch_view", target)
