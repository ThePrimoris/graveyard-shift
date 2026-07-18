# CraftingView.gd
# Shared presentation for the production skills (P3 Alchemy, P5 Forge): a
# header strip (skill icon, level badge, XP bar) over a card grid of recipes,
# on the same page grammar as the harvest views. Cards are built ONCE and
# refreshed in place (labels/buttons/bars), so tooltips never vanish mid-hover
# (the ActionCard lesson). Crafting itself lives in the station's
# CraftingManager; this is presentation.
#
# Subclasses set the config vars in _init: station, view_title, view_subtitle,
# verb, accent, ambience_color, icon_path.
class_name CraftingView
extends PanelContainer

const COL_CARD_BG := Color(0.078, 0.071, 0.11, 0.97)
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_GOLD := Color(0.83, 0.64, 0.27)
const COL_RUST := Color(0.76, 0.353, 0.29)
const COL_GREEN := Color(0.55, 0.82, 0.5)

## Tab order for the category shelves; categories not listed (the subclass's
## fallback_category among them) come after these, in first-seen order.
const CATEGORY_ORDER: Array[String] = ["Potions", "Elixirs", "Candles & Incense", "Relics", "Trinkets"]

## Config — set by the subclass in _init.
var station: CraftingManager = null
var view_title: String = "Crafting"
var view_subtitle: String = ""
var verb: String = "Craft"
var accent := Color("#5fae8f")
var ambience_color := Color(0.043, 0.039, 0.063)
var icon_path: String = ""
## The painted scene behind the station (theme/backdrops/*.png; "" = tint).
var backdrop: String = ""
## Section name for recipes whose output fits no shared category (Alchemy's
## vat-work materials, for instance).
var fallback_category: String = "Other Works"

var header_level_label: Label
var header_bar: ProgressBar
var header_xp_label: Label
var grid: HFlowContainer
## recipe_id -> {card, need_labels: {item_id: Label}, button, bar, pct,
## lock_label, unknown_lbl}
var rows: Dictionary = {}
## One shelf per output category, shown one at a time behind a tab row
## (a Still with many recipes shouldn't be a scroll marathon).
var category_grids: Dictionary = {}   # category -> HFlowContainer
var tab_buttons: Dictionary = {}      # category -> Button
var current_category: String = ""

func _ready() -> void:
	add_to_group(Ids.GROUP_UI_UPDATES)
	_apply_ambience()
	_build()
	station.brew_state_changed.connect(update_ui)
	update_ui()

func _apply_ambience() -> void:
	var style: StyleBox
	if backdrop != "" and ResourceLoader.exists(backdrop):
		var tex := StyleBoxTexture.new()
		tex.texture = load(backdrop)
		style = tex
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = ambience_color
		style = flat
	var previous := get_theme_stylebox("panel")
	if previous:
		style.content_margin_left = previous.content_margin_left
		style.content_margin_top = previous.content_margin_top
		style.content_margin_right = previous.content_margin_right
		style.content_margin_bottom = previous.content_margin_bottom
	add_theme_stylebox_override("panel", style)

func _build() -> void:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	# Header strip: skill icon + name left, level badge + XP bar right.
	var header = PanelContainer.new()
	var hstyle := StyleBoxFlat.new()
	hstyle.bg_color = COL_CARD_BG
	hstyle.set_border_width_all(1)
	hstyle.border_width_left = 4
	hstyle.border_color = Color(accent.r * 0.6, accent.g * 0.6, accent.b * 0.6)
	hstyle.set_corner_radius_all(10)
	hstyle.content_margin_left = 14
	hstyle.content_margin_right = 14
	hstyle.content_margin_top = 10
	hstyle.content_margin_bottom = 10
	header.add_theme_stylebox_override("panel", hstyle)
	vbox.add_child(header)

	var hrow = HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	header.add_child(hrow)

	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = 1
	icon.stretch_mode = 5
	if icon_path != "":
		icon.texture = load(icon_path)
	hrow.add_child(icon)

	var title_col = VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(title_col)
	var title = Label.new()
	title.text = view_title
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_TEXT_HI)
	title_col.add_child(title)
	var subtitle = Label.new()
	subtitle.text = view_subtitle
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COL_TEXT_MID)
	title_col.add_child(subtitle)

	var level_col = VBoxContainer.new()
	level_col.custom_minimum_size = Vector2(220, 0)
	level_col.add_theme_constant_override("separation", 4)
	hrow.add_child(level_col)
	header_level_label = Label.new()
	header_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_level_label.add_theme_font_size_override("font_size", 15)
	header_level_label.add_theme_color_override("font_color", COL_GOLD)
	level_col.add_child(header_level_label)
	header_bar = ProgressBar.new()
	header_bar.custom_minimum_size = Vector2(0, 10)
	header_bar.show_percentage = false
	header_bar.max_value = 1.0
	level_col.add_child(header_bar)
	header_xp_label = Label.new()
	header_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_xp_label.add_theme_font_size_override("font_size", 11)
	header_xp_label.add_theme_color_override("font_color", COL_TEXT_MID)
	level_col.add_child(header_xp_label)

	# The recipe shelves: one tab per output category (potions, incense, gear
	# slots...), one shown at a time — a shelf you flip to, not a scroll
	# marathon. Cards are still all built once so refresh-in-place holds.

	# category -> recipes, keeping the station's sort inside each shelf.
	var by_category: Dictionary = {}
	for recipe_id in station.sorted_ids():
		var recipe: Recipe = station.find_recipe_by_id(recipe_id)
		var cat := _category_of(recipe)
		if not by_category.has(cat):
			by_category[cat] = []
		by_category[cat].append(recipe)

	var ordered: Array[String] = []
	for cat in CATEGORY_ORDER:
		if by_category.has(cat):
			ordered.append(cat)
	for cat in by_category:
		if cat not in ordered:
			ordered.append(cat)

	# The tab row, in the zone-selector's mold: toggle buttons, one pressed.
	var tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tab_row)
	for cat in ordered:
		var tab = Button.new()
		tab.text = "%s (%d)" % [cat, by_category[cat].size()]
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(0, 34)
		tab.add_theme_font_size_override("font_size", 13)
		tab.pressed.connect(_select_category.bind(cat))
		tab_row.add_child(tab)
		tab_buttons[cat] = tab

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var section_col = VBoxContainer.new()
	section_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_col.add_theme_constant_override("separation", 8)
	scroll.add_child(section_col)

	for cat in ordered:
		grid = HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		grid.visible = false
		section_col.add_child(grid)
		category_grids[cat] = grid
		for recipe in by_category[cat]:
			_build_recipe_card(recipe)

	if not ordered.is_empty():
		_select_category(ordered[0])

## Shows one category's shelf and presses its tab.
func _select_category(cat: String) -> void:
	current_category = cat
	for c in category_grids:
		category_grids[c].visible = c == cat
	for c in tab_buttons:
		tab_buttons[c].set_pressed_no_signal(c == cat)

## The hint shown on a scroll recipe that hasn't been studied yet: that it's
## unknown, and where its scroll can actually be found (shop stock and enemy
## loot pools are both checked, so the hint never lies).
func _unknown_hint(recipe: Recipe) -> String:
	var scroll: Consumable = null
	for item_id in GameManager.item_db:
		var item = GameManager.item_db[item_id]
		if item is Consumable and item.taught_recipe_id == recipe.id:
			scroll = item
			break
	var sources: Array[String] = []
	if scroll != null:
		if preload("res://scenes/views/ShopView.gd").SCROLL_PRICES.has(scroll.id):
			sources.append("sold at the Shop")
		var droppers: Array[String] = []
		for encounter_id in GameManager.encounter_db:
			for enemy in GameManager.encounter_db[encounter_id].enemies:
				if enemy == null: continue
				for drop in enemy.loot_pool:
					if drop != null and drop.item != null and drop.item.id == scroll.id \
							and not droppers.has(enemy.name):
						droppers.append(enemy.name)
		if not droppers.is_empty():
			sources.append("dropped by %s" % " and ".join(droppers))
	if sources.is_empty():
		return "Recipe unknown — find its scroll and study it."
	return "Recipe unknown — its scroll is %s." % " or ".join(sources)

## The shelf a recipe's product belongs on, read off the output item.
func _category_of(recipe: Recipe) -> String:
	var out = recipe.output_item
	if out is Consumable:
		if out.is_incense(): return "Candles & Incense"
		if out.is_gather_elixir(): return "Elixirs"
		return "Potions"
	if out is Gear:
		return "Relics" if out.slot == Gear.GearSlot.RELIC else "Trinkets"
	return fallback_category

func _build_recipe_card(recipe: Recipe) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_CARD_BG
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.border_color = Color(accent.r * 0.6, accent.g * 0.6, accent.b * 0.6)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	grid.add_child(card)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	card.add_child(col)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	var pic = TextureRect.new()
	pic.custom_minimum_size = Vector2(36, 36)
	pic.expand_mode = 1
	pic.stretch_mode = 5
	if recipe.output_item:
		pic.texture = recipe.output_item.icon
	top.add_child(pic)
	var name_col = VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_col)
	var name_lbl = Label.new()
	name_lbl.text = recipe.name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", COL_TEXT_HI)
	name_lbl.tooltip_text = recipe.description + ("\n\n" + recipe.output_item.description if recipe.output_item else "")
	name_col.add_child(name_lbl)
	var meta_lbl = Label.new()
	meta_lbl.text = "%.0fs · +%.0f XP" % [recipe.base_seconds, recipe.base_xp]
	meta_lbl.add_theme_font_size_override("font_size", 11)
	meta_lbl.add_theme_color_override("font_color", COL_TEXT_MID)
	name_col.add_child(meta_lbl)

	# What the product actually does, stated on the card — the hover tooltip
	# keeps the flavor prose, but the rules never hide behind it.
	if recipe.output_item and recipe.output_item.effect_line() != "":
		var effect_lbl = Label.new()
		effect_lbl.text = recipe.output_item.effect_line()
		effect_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_lbl.add_theme_font_size_override("font_size", 11)
		effect_lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b).lightened(0.25))
		col.add_child(effect_lbl)

	# Why a scroll recipe can't be brewed yet, and where its scroll is found.
	# Hidden once learned (update_ui toggles it).
	var unknown_lbl = Label.new()
	unknown_lbl.visible = false
	unknown_lbl.text = _unknown_hint(recipe)
	unknown_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unknown_lbl.add_theme_font_size_override("font_size", 11)
	unknown_lbl.add_theme_color_override("font_color", COL_RUST)
	col.add_child(unknown_lbl)

	var lock_label = Label.new()
	lock_label.text = "Lv %d" % recipe.required_level
	lock_label.add_theme_font_size_override("font_size", 12)
	top.add_child(lock_label)

	# Ingredient ledger: one "have/need name" row per input.
	var need_labels: Dictionary = {}
	for item_id in recipe.inputs:
		var item = GameManager.find_item_by_id(item_id)
		var irow = HBoxContainer.new()
		irow.add_theme_constant_override("separation", 6)
		col.add_child(irow)
		var iicon = TextureRect.new()
		iicon.custom_minimum_size = Vector2(18, 18)
		iicon.expand_mode = 1
		iicon.stretch_mode = 5
		if item:
			iicon.texture = item.icon
		irow.add_child(iicon)
		var ilbl = Label.new()
		ilbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ilbl.add_theme_font_size_override("font_size", 12)
		irow.add_child(ilbl)
		need_labels[item_id] = ilbl

	var bar_row = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	col.add_child(bar_row)
	var bar = ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	bar_row.add_child(bar)

	var button = Button.new()
	button.custom_minimum_size = Vector2(0, 32)
	button.theme_type_variation = &"ActionButton"
	button.pressed.connect(_on_craft_pressed.bind(recipe))
	col.add_child(button)

	rows[recipe.id] = {"card": card, "need_labels": need_labels, "button": button,
		"bar": bar, "lock_label": lock_label, "unknown_lbl": unknown_lbl}

func _on_craft_pressed(recipe: Recipe) -> void:
	AudioManager.play_sfx(Ids.SFX_UI_CLICK)
	if station.active_recipe == recipe:
		station.stop_brew()
	else:
		station.start_brew(recipe)

func _process(_delta: float) -> void:
	if not visible: return
	var recipe = station.active_recipe
	for recipe_id in rows:
		var row = rows[recipe_id]
		if recipe != null and recipe_id == recipe.id:
			var t = clampf(station.brew_progress / station.get_effective_seconds(recipe), 0.0, 1.0)
			row["bar"].value = t
		elif row["bar"].value != 0.0:
			row["bar"].value = 0.0

func update_ui() -> void:
	if header_level_label == null: return
	var skill = GameManager.skills[station.skill_key]
	header_level_label.text = "Level %d / %d" % [skill["level"], GameManager.MAX_LEVEL]
	if skill["level"] >= GameManager.MAX_LEVEL:
		header_bar.value = 1.0
		header_xp_label.text = "Mastered"
	else:
		var needed = GameManager.get_xp_needed(skill["level"])
		header_bar.value = clampf(skill["xp"] / needed, 0.0, 1.0)
		header_xp_label.text = "%.0f / %.0f XP" % [skill["xp"], needed]

	var level: int = skill["level"]
	for recipe_id in rows:
		var recipe: Recipe = station.find_recipe_by_id(recipe_id)
		var row = rows[recipe_id]
		var unlocked = level >= recipe.required_level
		var learned = station.is_learned(recipe)
		row["card"].modulate.a = 1.0 if (unlocked and learned) else 0.55
		row["unknown_lbl"].visible = not learned
		row["lock_label"].text = ("Lv %d" % recipe.required_level) if learned else "Scroll"
		row["lock_label"].add_theme_color_override("font_color", COL_GREEN if (unlocked and learned) else COL_RUST)
		for item_id in row["need_labels"]:
			var item = GameManager.find_item_by_id(item_id)
			var have = InventoryManager.get_item_count(item_id)
			var need = int(recipe.inputs[item_id])
			var lbl: Label = row["need_labels"][item_id]
			lbl.text = "%d / %d  %s" % [have, need, item.name if item else item_id]
			lbl.add_theme_color_override("font_color", COL_GREEN if have >= need else COL_RUST)
		var crafting = station.active_recipe != null and station.active_recipe.id == recipe_id
		row["button"].text = "Stop" if crafting else verb
		row["button"].theme_type_variation = &"DangerButton" if crafting else &"ActionButton"
		row["button"].disabled = not crafting and not station.can_brew(recipe)
		if not learned:
			row["button"].tooltip_text = row["unknown_lbl"].text
		elif not unlocked:
			row["button"].tooltip_text = "Requires %s level %d" % [station.skill_key.capitalize(), recipe.required_level]
		else:
			row["button"].tooltip_text = ""
