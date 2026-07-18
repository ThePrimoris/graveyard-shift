# AlmanacPanel.gd
# The Almanac: a codex of everything the run has uncovered, opened from the
# top navigation bar (CanvasLayer overlay, same pattern as Settings and the
# achievement book). Three chapters:
#   Materials — every material/consumable; unheld items are dark "???"
#   Bestiary  — every foe, with a slain tally; unmet foes are dark "???"
#   Grounds   — every harvest node, with times worked; unworked rows are dim
# Reads StatsManager's discovery ledgers; nothing here mutates game state.
extends CanvasLayer

const COL_CARD := Color(0.078, 0.071, 0.11, 0.98)
const COL_ROW := Color("#171226")
const COL_BORDER := Color(0.83, 0.64, 0.27, 0.55)
const COL_GOLD := Color(0.83, 0.64, 0.27)
const COL_TEXT_HI := Color(0.91, 0.886, 0.83)
const COL_TEXT_MID := Color(0.6, 0.565, 0.66)
const COL_LOCKED := Color(0.36, 0.34, 0.42)
const COL_VIOLET := Color(0.663, 0.61, 0.867)

const ENEMY_DIRS: Array[String] = ["res://data/enemies/"]

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
	vbox.custom_minimum_size = Vector2(620, 0)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "ALMANAC"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 440)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	tabs.add_child(_materials_tab())
	tabs.add_child(_bestiary_tab())
	tabs.add_child(_grounds_tab())

	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 36)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	vbox.add_child(close)

# --- Chapters ---

func _materials_tab() -> Control:
	var items: Array = []
	for item_id in GameManager.item_db:
		var item: Item = GameManager.item_db[item_id]
		if item.type == Item.ItemType.MATERIAL or item.type == Item.ItemType.CONSUMABLE:
			items.append(item)
	items.sort_custom(func(a, b): return a.name < b.name)

	var found := 0
	for item in items:
		if StatsManager.discovered_items.has(item.id):
			found += 1

	var page := _page("Materials", "%d of %d discovered" % [found, items.size()])
	var grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	page["list"].add_child(grid)

	for item in items:
		var known: bool = StatsManager.discovered_items.has(item.id)
		var tile = PanelContainer.new()
		var ts := StyleBoxFlat.new()
		ts.bg_color = COL_ROW
		ts.set_corner_radius_all(8)
		ts.set_border_width_all(1)
		ts.border_color = COL_GOLD if known else Color("#2f2745")
		ts.content_margin_left = 6
		ts.content_margin_right = 6
		ts.content_margin_top = 6
		ts.content_margin_bottom = 6
		tile.add_theme_stylebox_override("panel", ts)
		var pic = TextureRect.new()
		pic.custom_minimum_size = Vector2(44, 44)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = item.icon
		# Unknowns show only a silhouette; the name stays a mystery.
		pic.modulate = Color.WHITE if known else Color(0.1, 0.09, 0.14)
		tile.add_child(pic)
		var tip := "%s\n%s" % [item.name, item.description]
		if item.effect_line() != "":
			tip += "\n\n%s" % item.effect_line()
		tile.tooltip_text = tip if known else "??? — not yet found"
		grid.add_child(tile)
	return page["root"]

func _bestiary_tab() -> Control:
	var enemies: Array = []
	for dir_path in ENEMY_DIRS:
		var dir = DirAccess.open(dir_path)
		if dir == null: continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var res_file = file_name.trim_suffix(".remap")
			if not dir.current_is_dir() and res_file.ends_with(".tres"):
				var res = load(dir_path + res_file)
				if res is Enemy and res.id != "":
					enemies.append(res)
			file_name = dir.get_next()
		dir.list_dir_end()
	enemies.sort_custom(func(a, b): return a.base_hp < b.base_hp)

	var met := 0
	for enemy in enemies:
		if StatsManager.slain_enemies.has(enemy.id):
			met += 1

	var page := _page("Bestiary", "%d of %d laid to rest" % [met, enemies.size()])
	for enemy in enemies:
		var slain: int = int(StatsManager.slain_enemies.get(enemy.id, 0))
		var known := slain > 0
		var row = _row_base(known)
		var h = HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var pic = TextureRect.new()
		pic.custom_minimum_size = Vector2(36, 36)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = enemy.icon
		pic.modulate = Color.WHITE if known else Color(0.1, 0.09, 0.14)
		h.add_child(pic)
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		var name_lbl = Label.new()
		name_lbl.text = enemy.name if known else "???"
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", COL_TEXT_HI if known else COL_LOCKED)
		col.add_child(name_lbl)
		var desc = Label.new()
		desc.text = (enemy.description if enemy.description != "" else "A tenant of the dark.") if known \
			else "Something out there has not yet met the warband."
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", COL_TEXT_MID if known else COL_LOCKED)
		col.add_child(desc)
		var tally = Label.new()
		tally.text = "slain %d" % slain if known else ""
		tally.add_theme_font_size_override("font_size", 12)
		tally.add_theme_color_override("font_color", COL_GOLD)
		h.add_child(tally)
		page["list"].add_child(row)
	return page["root"]

func _grounds_tab() -> Control:
	var node_ids: Array = GameManager.node_db.keys()
	node_ids.sort_custom(func(a, b):
		var na: HarvestNode = GameManager.node_db[a]
		var nb: HarvestNode = GameManager.node_db[b]
		if na.required_skill != nb.required_skill:
			return na.required_skill < nb.required_skill
		return na.required_level < nb.required_level)

	var worked := 0
	for node_id in node_ids:
		if StatsManager.harvested_nodes.has(node_id):
			worked += 1

	var page := _page("Grounds", "%d of %d sites worked" % [worked, node_ids.size()])
	for node_id in node_ids:
		var node: HarvestNode = GameManager.node_db[node_id]
		var count: int = int(StatsManager.harvested_nodes.get(node_id, 0))
		var known := count > 0
		var row = _row_base(known)
		var h = HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var skill_lbl = Label.new()
		skill_lbl.text = str(GameManager.SkillType.keys()[node.required_skill]).capitalize()
		skill_lbl.custom_minimum_size = Vector2(110, 0)
		skill_lbl.add_theme_font_size_override("font_size", 12)
		skill_lbl.add_theme_color_override("font_color", COL_VIOLET if known else COL_LOCKED)
		h.add_child(skill_lbl)
		var name_lbl = Label.new()
		name_lbl.text = "%s (Lv %d)" % [node.name, node.required_level] if known else "??? (Lv %d)" % node.required_level
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", COL_TEXT_HI if known else COL_LOCKED)
		h.add_child(name_lbl)
		var tally = Label.new()
		tally.text = "worked %d" % count if known else ""
		tally.add_theme_font_size_override("font_size", 12)
		tally.add_theme_color_override("font_color", COL_GOLD)
		h.add_child(tally)
		page["list"].add_child(row)
	return page["root"]

# --- Shared page scaffolding ---

## A tab page: header tally + scrollable list. Returns {root, list}.
func _page(tab_name: String, tally_text: String) -> Dictionary:
	var root = VBoxContainer.new()
	root.name = tab_name
	root.add_theme_constant_override("separation", 8)
	var tally = Label.new()
	tally.text = tally_text
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tally.add_theme_font_size_override("font_size", 12)
	tally.add_theme_color_override("font_color", COL_TEXT_MID)
	root.add_child(tally)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return {"root": root, "list": list}

func _row_base(known: bool) -> PanelContainer:
	var row = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = COL_ROW
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = COL_GOLD if known else Color("#2f2745")
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", style)
	return row
