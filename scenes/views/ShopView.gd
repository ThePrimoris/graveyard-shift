# ShopView.gd
# The Undertaker's Emporium: one systematic upgrade path per tool type
# (the old tool is melted down and replaced), plus purchasable backpack slots.
extends PanelContainer

# Cost to upgrade INTO each tier: gold plus Lumbering + Spelunking materials.
const TIER_COSTS: Dictionary = {
	ToolData.ToolTier.GALVANIZED: {"gold": 100, "materials": {"rotten_logs": 15, "stone_debris": 10}},
	ToolData.ToolTier.REINFORCED: {"gold": 500, "materials": {"rotten_logs": 45, "stone_debris": 30}},
	ToolData.ToolTier.TEMPERED: {"gold": 1000, "materials": {"rotten_logs": 90, "stone_debris": 60}}
}

# Recipe scrolls (Alchemy rework): one-time gold sinks that teach a crafting
# recipe when studied from the backpack. The shop never sells finished potions —
# brewing is the player's job. item_id -> gold price.
const SCROLL_PRICES: Dictionary = {
	"scroll_war_draught": 150,
	"scroll_vigil_incense": 300,
	"scroll_surgeons_paste": 500,
	"scroll_requiem_incense": 2000,
}

var gold_label: Label
# tool_type (int) -> {"icon": TextureRect, "label": Label, "button": Button}
var upgrade_rows: Dictionary = {}
# item_id -> {"label": Label, "button": Button}
var scroll_rows: Dictionary = {}
var slot_label: Label
var slot_button: Button

func _ready() -> void:
	add_to_group(Ids.GROUP_UI_UPDATES)
	_build_shop()
	update_ui()

func _build_shop() -> void:
	var panel = get_node_or_null("%ShopPanel")
	if panel == null: return
	var vbox: VBoxContainer = panel.get_node_or_null("VBoxContainer")
	if vbox == null: return

	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "THE UNDERTAKER'S EMPORIUM"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	gold_label = Label.new()
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.3))
	vbox.add_child(gold_label)

	vbox.add_child(HSeparator.new())

	var tools_header = Label.new()
	tools_header.text = "TOOL UPGRADES"
	tools_header.theme_type_variation = &"SectionLabel"
	tools_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(tools_header)

	var tools_hint = Label.new()
	tools_hint.text = "Upgrading melts the old tool down — the new one takes its place."
	tools_hint.add_theme_font_size_override("font_size", 12)
	tools_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	vbox.add_child(tools_hint)

	upgrade_rows.clear()
	for type_enum in [ToolData.ToolType.SHOVEL, ToolData.ToolType.HATCHET, ToolData.ToolType.PICKAXE]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		vbox.add_child(row)

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = 1
		icon.stretch_mode = 5
		row.add_child(icon)

		var info = Label.new()
		info.custom_minimum_size = Vector2(500, 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(200, 44)
		btn.pressed.connect(_on_upgrade_pressed.bind(type_enum))
		row.add_child(btn)

		upgrade_rows[type_enum] = {"icon": icon, "label": info, "button": btn}

	vbox.add_child(HSeparator.new())

	var scrolls_header = Label.new()
	scrolls_header.text = "RECIPES & CURIOS"
	scrolls_header.theme_type_variation = &"SectionLabel"
	scrolls_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(scrolls_header)

	var scrolls_hint = Label.new()
	scrolls_hint.text = "Formulae for the Caretaker's Still. Buy the scroll, study it from the backpack, and the recipe is yours for good."
	scrolls_hint.add_theme_font_size_override("font_size", 12)
	scrolls_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.72))
	vbox.add_child(scrolls_hint)

	scroll_rows.clear()
	for item_id in SCROLL_PRICES:
		var item = GameManager.find_item_by_id(item_id)
		if item == null: continue
		var srow = HBoxContainer.new()
		srow.add_theme_constant_override("separation", 14)
		vbox.add_child(srow)

		var sicon = TextureRect.new()
		sicon.custom_minimum_size = Vector2(36, 36)
		sicon.expand_mode = 1
		sicon.stretch_mode = 5
		sicon.texture = item.icon
		srow.add_child(sicon)

		var sinfo = Label.new()
		sinfo.custom_minimum_size = Vector2(500, 0)
		sinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sinfo.tooltip_text = item.description
		srow.add_child(sinfo)

		var sbtn = Button.new()
		sbtn.custom_minimum_size = Vector2(200, 36)
		sbtn.pressed.connect(_on_buy_scroll_pressed.bind(item_id))
		srow.add_child(sbtn)

		scroll_rows[item_id] = {"label": sinfo, "button": sbtn}

	vbox.add_child(HSeparator.new())

	var pack_header = Label.new()
	pack_header.text = "BACKPACK"
	pack_header.theme_type_variation = &"SectionLabel"
	pack_header.add_theme_font_size_override("font_size", 15)
	vbox.add_child(pack_header)

	var pack_row = HBoxContainer.new()
	pack_row.add_theme_constant_override("separation", 14)
	vbox.add_child(pack_row)

	slot_label = Label.new()
	slot_label.custom_minimum_size = Vector2(500, 0)
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_row.add_child(slot_label)

	slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(200, 44)
	slot_button.pressed.connect(_on_buy_slot_pressed)
	pack_row.add_child(slot_button)

func _tool_stats(tool: ToolData) -> String:
	var parts: Array[String] = []
	var sp := int(round((tool.speed_multiplier - 1.0) * 100))
	if sp > 0: parts.append("+%d%% speed" % sp)
	if tool.yield_bonus > 0: parts.append("+%d%% double haul" % tool.yield_bonus)
	return ", ".join(parts) if not parts.is_empty() else "baseline gear"

func _describe_cost(cost: Dictionary) -> String:
	var parts: Array[String] = ["%d Gold" % cost["gold"]]
	for item_id in cost["materials"]:
		var item = GameManager.find_item_by_id(item_id)
		var display = item.name if item else item_id.capitalize()
		parts.append("%d %s (have %d)" % [cost["materials"][item_id], display, InventoryManager.get_item_count(item_id)])
	return ", ".join(parts)

func _can_afford(cost: Dictionary) -> bool:
	if GameManager.gold_coins < cost["gold"]:
		return false
	for item_id in cost["materials"]:
		if InventoryManager.get_item_count(item_id) < cost["materials"][item_id]:
			return false
	return true

## Pays the upgrade cost and swaps the tool. Exposed for headless tests.
func try_upgrade(type_enum: int) -> bool:
	var next = GameManager.get_next_tool_upgrade(type_enum)
	if next == null: return false
	var cost = TIER_COSTS.get(next.tool_tier, null)
	if cost == null or not _can_afford(cost): return false

	GameManager.gold_coins -= cost["gold"]
	for item_id in cost["materials"]:
		InventoryManager.remove_item(item_id, cost["materials"][item_id])

	if GameManager.upgrade_tool(type_enum):
		NotificationManager.show_item("Upgraded to %s" % next.name, 1, next)
		return true
	return false

func _on_upgrade_pressed(type_enum: int) -> void:
	try_upgrade(type_enum)

## True once the recipe a scroll teaches has been studied.
func _scroll_recipe_known(scroll: Consumable) -> bool:
	for station in [AlchemyManager, ForgeManager]:
		if station.find_recipe_by_id(scroll.taught_recipe_id) != null:
			return station.known_recipe_ids.has(scroll.taught_recipe_id)
	return false

## Buys one recipe scroll for gold. Refuses once the recipe is learned or a
## copy is already in the pack — no dupe-traps. Exposed for headless tests.
func try_buy_scroll(item_id: String) -> bool:
	var price = int(SCROLL_PRICES.get(item_id, 0))
	var item = GameManager.find_item_by_id(item_id)
	if not (item is Consumable) or price <= 0 or GameManager.gold_coins < price:
		return false
	if _scroll_recipe_known(item) or InventoryManager.get_item_count(item_id) > 0:
		return false
	if not InventoryManager.has_room_for(item):
		NotificationManager.show_item("Inventory full", 1)
		return false
	GameManager.gold_coins -= price
	InventoryManager.add_item(item, 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

func _on_buy_scroll_pressed(item_id: String) -> void:
	if try_buy_scroll(item_id):
		var item = GameManager.find_item_by_id(item_id)
		NotificationManager.show_item(item.name, 1, item)

func _on_buy_slot_pressed() -> void:
	if InventoryManager.purchase_slot():
		NotificationManager.show_item("Backpack expanded (+1 slot)", 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

func update_ui() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % GameManager.gold_coins

	for type_enum in upgrade_rows:
		var row = upgrade_rows[type_enum]
		var current = GameManager.get_current_tool_of_type(type_enum)
		var next = GameManager.get_next_tool_upgrade(type_enum)

		if current:
			row["icon"].texture = current.icon

		if next == null:
			row["label"].text = "%s — %s\nMaximum tier reached." % [current.name if current else "?", _tool_stats(current) if current else ""]
			row["button"].text = "MAX TIER"
			row["button"].disabled = true
			row["button"].tooltip_text = ""
		else:
			var cost = TIER_COSTS.get(next.tool_tier, {"gold": 0, "materials": {}})
			var current_line = "%s (%s)" % [current.name, _tool_stats(current)] if current else "No tool"
			row["label"].text = "%s  →  %s (%s)\nCost: %s" % [current_line, next.name, _tool_stats(next), _describe_cost(cost)]
			row["button"].text = "Upgrade (%d g)" % cost["gold"]
			row["button"].disabled = not _can_afford(cost)
			row["button"].tooltip_text = "The %s will be melted down." % current.name if current else ""

	for item_id in scroll_rows:
		var srow = scroll_rows[item_id]
		var item = GameManager.find_item_by_id(item_id)
		var price = int(SCROLL_PRICES.get(item_id, 0))
		var known = _scroll_recipe_known(item)
		var in_pack = InventoryManager.get_item_count(item_id) > 0
		if known:
			srow["label"].text = "%s — already studied" % item.name
		elif in_pack:
			srow["label"].text = "%s — in your pack, study it from the backpack" % item.name
		else:
			srow["label"].text = item.name
		srow["button"].text = "Learned" if known else "Buy (%d g)" % price
		srow["button"].disabled = known or in_pack or GameManager.gold_coins < price

	if slot_label:
		var extra = InventoryManager.purchased_slots
		if extra >= InventoryManager.MAX_PURCHASED_SLOTS:
			slot_label.text = "Backpack: %d slots (%d purchased)\nFully expanded." % [InventoryManager.slots.size(), extra]
			slot_button.text = "MAX SIZE"
			slot_button.disabled = true
		else:
			slot_label.text = "Backpack: %d slots (%d of %d purchased)\nEach slot costs more than the last." % [
				InventoryManager.slots.size(), extra, InventoryManager.MAX_PURCHASED_SLOTS]
			slot_button.text = "Buy Slot (%d g)" % InventoryManager.get_next_slot_cost()
			slot_button.disabled = not InventoryManager.can_purchase_slot()
