# InventoryView.gd
# Bank-style inventory: header strip (slots used, total value, equipped tools),
# the item grid in an elevated panel, and a persistent "Selected Item" card on
# the right with a quantity slider + presets for selling, Melvor-style.
extends PanelContainer

@export var inventory_slot_scene: PackedScene # Assign your InventorySlot.tscn here in Inspector

@onready var slots_used_label: Label = %SlotsUsedLabel
@onready var bank_value_label: Label = %BankValueLabel

@onready var details_panel: VBoxContainer = %DetailsPanel
@onready var details_content: VBoxContainer = %DetailsContent
@onready var no_selection_label: Label = %NoSelectionLabel
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_count_label: Label = %ItemCountLabel
@onready var item_icon_rect: TextureRect = %ItemIconRect
@onready var item_description_label: Label = %ItemDescriptionLabel
@onready var stack_value_label: Label = %StackValueLabel

@onready var sell_panel: PanelContainer = %SellPanel
@onready var sell_slider: HSlider = %SellSlider
@onready var qty_label: Label = %QtyLabel
@onready var all_but1_button: Button = %AllBut1Button
@onready var all_button: Button = %AllButton
@onready var sell_button: Button = %SellButton
@onready var equip_button: Button = %EquipButton
@onready var destroy_button: Button = %DestroyButton

@onready var inventory_grid: GridContainer = %InventoryGrid

# Equipment slots, one per tool type, indexed to match ToolData.ToolType
@onready var tool_slot_buttons: Array = [
	%ToolSlotShovel,
	%ToolSlotHatchet,
	%ToolSlotPickaxe
]

var selected_item: Item = null
# True when the selected item is sitting in an equipment slot (not the grid)
var selected_is_equipped: bool = false
## Code-built "Drink" button for gather elixirs (P3), inserted above Destroy.
var use_button: Button
## Code-built rules line under the flavor text: what the item actually does
## (Item.effect_line()), kept visually distinct from the description prose.
var effect_label: Label
## Which backpack tab (page of page_size() slots) the grid is showing.
var current_page: int = 0
var tab_bar: HBoxContainer
var tab_group := ButtonGroup.new()
var sort_option: OptionButton
## Right-click context menu for splitting stacks; targets this slot index.
var split_menu: PopupMenu
var split_target: int = -1
## Tab-rename dialog (right-click on a tab button).
var rename_dialog: AcceptDialog
var rename_edit: LineEdit
var rename_target: int = -1

## A backpack tab button: click to open the tab, drop a dragged stack on it
## to move that stack over, or right-click to rename the tab.
class TabButton:
	extends Button
	signal rename_requested(page: int)
	var page: int = 0
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			rename_requested.emit(page)
			accept_event()
	func _can_drop_data(_at: Vector2, data) -> bool:
		var ok = typeof(data) == TYPE_INT
		modulate = Color(1.35, 1.35, 1.05) if ok else Color.WHITE
		return ok
	func _drop_data(_at: Vector2, data) -> void:
		modulate = Color.WHITE
		if InventoryManager.move_to_page(int(data), page):
			AudioManager.play_sfx(Ids.SFX_UI_CLICK)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
			modulate = Color.WHITE
## Sticky "All" preset: once chosen, each newly selected item starts at its
## full stack until the player picks a smaller quantity.
var sell_all_mode: bool = false
## True while code (not the player) is moving the slider.
var _slider_guard: bool = false

func _ready() -> void:
	add_to_group(Ids.GROUP_UI_UPDATES)

	sell_button.pressed.connect(_on_sell_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	destroy_button.pressed.connect(_on_destroy_pressed)

	effect_label = Label.new()
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.visible = false
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_color", Color("#8fd0b2"))
	var desc_parent = item_description_label.get_parent()
	desc_parent.add_child(effect_label)
	desc_parent.move_child(effect_label, item_description_label.get_index() + 1)

	use_button = Button.new()
	use_button.theme_type_variation = &"ActionButton"
	use_button.visible = false
	use_button.pressed.connect(_on_use_pressed)
	destroy_button.get_parent().add_child(use_button)
	destroy_button.get_parent().move_child(use_button, destroy_button.get_index())
	sell_slider.value_changed.connect(_on_sell_qty_changed)
	all_but1_button.pressed.connect(func():
		sell_all_mode = false
		_set_slider(maxf(1.0, sell_slider.max_value - 1.0)))
	all_button.pressed.connect(func():
		sell_all_mode = true
		_set_slider(sell_slider.max_value))

	for i in range(tool_slot_buttons.size()):
		tool_slot_buttons[i].pressed.connect(_on_tool_slot_pressed.bind(i))

	inventory_grid.columns = InventoryManager.GRID_COLUMNS
	_build_toolbar()

	split_menu = PopupMenu.new()
	add_child(split_menu)
	split_menu.id_pressed.connect(_on_split_menu_chosen)

	rename_dialog = AcceptDialog.new()
	rename_dialog.title = "Name the tab"
	rename_edit = LineEdit.new()
	rename_edit.placeholder_text = "Tab name (blank resets)"
	rename_edit.max_length = 16
	rename_dialog.add_child(rename_edit)
	rename_dialog.register_text_enter(rename_edit)
	rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(rename_dialog)

	# The card keeps its reserved width at all times so selecting an item
	# never shifts the rest of the layout; only its content toggles.
	details_content.visible = false
	no_selection_label.visible = true

	# Rebuild the grid only when the inventory actually changes, not on every UI tick
	InventoryManager.inventory_updated.connect(refresh_inventory_grid)

	refresh_inventory_grid()
	update_ui()

## The toolbar between the header and the grid: backpack tabs on the left,
## sort controls on the right. All code-built so Main.tscn stays untouched.
func _build_toolbar() -> void:
	# BankColumn sits four levels above the grid (Scroll > Margin > Panel > it).
	var bank_column = inventory_grid.get_parent().get_parent().get_parent().get_parent()
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	bank_column.add_child(toolbar)
	bank_column.move_child(toolbar, 1)

	tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	toolbar.add_child(tab_bar)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	sort_option = OptionButton.new()
	sort_option.add_item("Name", 0)
	sort_option.add_item("Stack size", 1)
	sort_option.add_item("Value", 2)
	sort_option.tooltip_text = "What the sort orders by."
	toolbar.add_child(sort_option)

	var sort_tab_btn = Button.new()
	sort_tab_btn.text = "Sort tab"
	sort_tab_btn.tooltip_text = "Sort and merge the stacks on this tab only."
	sort_tab_btn.pressed.connect(_on_sort_pressed.bind(false))
	toolbar.add_child(sort_tab_btn)

	var sort_all_btn = Button.new()
	sort_all_btn.text = "Sort all"
	sort_all_btn.tooltip_text = "Sort and merge every tab into one ordered pack."
	sort_all_btn.pressed.connect(_on_sort_pressed.bind(true))
	toolbar.add_child(sort_all_btn)

## One button per backpack tab; rebuilt when capacity changes the count, and
## re-labelled every refresh so renames show immediately.
func _refresh_tabs() -> void:
	var page_count = maxi(1, int(ceil(InventoryManager.slots.size() / float(InventoryManager.page_size()))))
	current_page = clampi(current_page, 0, page_count - 1)
	if tab_bar.get_child_count() != page_count:
		for child in tab_bar.get_children():
			tab_bar.remove_child(child)
			child.queue_free()
		for i in range(page_count):
			var btn := TabButton.new()
			btn.page = i
			btn.toggle_mode = true
			btn.button_group = tab_group
			btn.pressed.connect(_on_tab_pressed.bind(i))
			btn.rename_requested.connect(_on_tab_rename_requested)
			tab_bar.add_child(btn)
	for i in range(tab_bar.get_child_count()):
		var btn: Button = tab_bar.get_child(i)
		btn.text = InventoryManager.tab_name(i)
		btn.tooltip_text = "Open %s. Drag a stack here to move it over; right-click to rename." % InventoryManager.tab_name(i)
		btn.set_pressed_no_signal(i == current_page)
	tab_bar.visible = page_count > 1

func _on_tab_rename_requested(page: int) -> void:
	rename_target = page
	rename_edit.text = "" if page >= InventoryManager.tab_names.size() \
		else String(InventoryManager.tab_names[page])
	rename_dialog.popup_centered()
	rename_edit.grab_focus.call_deferred()

func _on_rename_confirmed() -> void:
	if rename_target >= 0:
		InventoryManager.set_tab_name(rename_target, rename_edit.text)

func _on_tab_pressed(page: int) -> void:
	if current_page == page: return
	current_page = page
	AudioManager.play_sfx(Ids.SFX_UI_CLICK)
	refresh_inventory_grid()

# This is the "Engine" that builds the slots from the InventoryManager data
func refresh_inventory_grid() -> void:
	_refresh_tabs()
	for child in inventory_grid.get_children():
		inventory_grid.remove_child(child)
		child.queue_free()

	var start = current_page * InventoryManager.page_size()
	var end = mini(start + InventoryManager.page_size(), InventoryManager.slots.size())
	for i in range(start, end):
		var slot_data = InventoryManager.slots[i]

		var slot_instance = inventory_slot_scene.instantiate()
		inventory_grid.add_child(slot_instance)

		# Ensure we assign the index so dragging works
		slot_instance.slot_index = i
		slot_instance.slot_right_clicked.connect(_on_slot_right_clicked)

		if slot_data != null:
			slot_instance.setup(slot_data["item"], slot_data["quantity"])
			slot_instance.slot_clicked.connect(_on_item_selected)
		else:
			slot_instance.clear_slot()

	update_ui()

# --- Stack splitting (right-click menu) ---

func _on_slot_right_clicked(index: int) -> void:
	var slot_data = InventoryManager.slots[index]
	if slot_data == null: return
	# Right-click also inspects, so the details card matches the menu.
	_on_item_selected(slot_data["item"])
	if not slot_data["item"].is_stackable: return
	split_target = index
	var qty := int(slot_data["quantity"])
	split_menu.clear()
	split_menu.add_item("Split half (%d)" % int(qty / 2.0), int(qty / 2.0))
	split_menu.set_item_disabled(0, qty < 2)
	split_menu.add_item("Split 1", 1)
	split_menu.set_item_disabled(1, qty < 2)
	split_menu.add_item("Split 10", 10)
	split_menu.set_item_disabled(2, qty <= 10)
	split_menu.position = Vector2i(get_global_mouse_position())
	split_menu.popup()

## The menu item id doubles as the amount to split off.
func _on_split_menu_chosen(amount: int) -> void:
	if not InventoryManager.split_stack(split_target, amount):
		NotificationManager.show_item("No empty slot to split into", 1)

func _on_sort_pressed(all_tabs: bool) -> void:
	AudioManager.play_sfx(Ids.SFX_UI_CLICK)
	var key: String = ["name", "count", "value"][sort_option.selected]
	if all_tabs:
		InventoryManager.sort_range(0, InventoryManager.slots.size(), key)
	else:
		var start = current_page * InventoryManager.page_size()
		InventoryManager.sort_range(start, start + InventoryManager.page_size(), key)

func update_ui() -> void:
	_refresh_tool_slots()
	_refresh_bank_header()

	if selected_item:
		if selected_is_equipped:
			# Deselect if the tool has since left the equipment slot
			if GameManager.get_equipped_tool(selected_item.tool_type) != selected_item:
				_clear_selection()
			else:
				_display_item_details(selected_item)
		elif InventoryManager.get_item_count(selected_item.id) <= 0:
			_clear_selection()
		else:
			_display_item_details(selected_item)

## Header chips: slots used and the sell value of everything carried.
func _refresh_bank_header() -> void:
	var used := 0
	var total_value := 0
	for slot_data in InventoryManager.slots:
		if slot_data != null:
			used += 1
			var item: Item = slot_data["item"]
			if item.is_sellable:
				total_value += _get_unit_sell_value(item) * int(slot_data["quantity"])
	slots_used_label.text = "%d / %d" % [used, InventoryManager.slots.size()]
	bank_value_label.text = "Value: %s g" % _fmt_gold(total_value)

func _fmt_gold(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	if value >= 10000:
		return "%.1fK" % (value / 1000.0)
	return str(value)

func _refresh_tool_slots() -> void:
	for i in range(tool_slot_buttons.size()):
		var btn: Button = tool_slot_buttons[i]
		var tool = GameManager.get_equipped_tool(i)
		var type_name = ToolData.ToolType.keys()[i].capitalize()

		if tool:
			# Icon-only, sized like a regular inventory slot; details go in the tooltip
			btn.text = "" if tool.icon else tool.name.left(6)
			btn.icon = tool.icon
			var bits: Array[String] = []
			var sp := int(round((tool.speed_multiplier - 1.0) * 100))
			if sp > 0: bits.append("+%d%% speed" % sp)
			if tool.yield_bonus > 0: bits.append("+%d%% double haul" % tool.yield_bonus)
			var stat_line := ", ".join(bits) if not bits.is_empty() else "baseline"
			btn.tooltip_text = "%s — %s\nClick to inspect / unequip." % [tool.name, stat_line]
		else:
			btn.text = type_name
			btn.icon = null
			btn.tooltip_text = "No %s equipped." % type_name.to_lower()

func _on_tool_slot_pressed(type_index: int) -> void:
	var tool = GameManager.get_equipped_tool(type_index)
	if tool:
		selected_item = tool
		selected_is_equipped = true
		_display_item_details(tool)

func _on_item_selected(item: Item) -> void:
	selected_item = item
	selected_is_equipped = false
	# Fresh selection starts at "sell 1" — unless "All" is armed, which sticks
	# across items until a smaller quantity is chosen.
	if not sell_all_mode:
		_set_slider(1)
	_display_item_details(item)

func _get_unit_sell_value(item: Item) -> int:
	# Counting House (P4): built tiers raise every sale's take.
	var mult := 1.0 + GroundsManager.get_bonus(Ids.EFFECT_SELL_PCT) / 100.0
	return maxi(1, int(round(item.sell_value * mult)))

func _display_item_details(item: Item) -> void:
	details_content.visible = true
	no_selection_label.visible = false
	item_name_label.text = item.name
	item_icon_rect.texture = item.icon

	var count := InventoryManager.get_item_count(item.id)
	if selected_is_equipped:
		item_count_label.text = "Equipped"
	else:
		item_count_label.text = "Owned: %d" % count

	if item.description != "":
		item_description_label.text = item.description
	else:
		item_description_label.text = "No description available."

	# The rules line, separate from the flavor prose above it.
	var effect := item.effect_line()
	effect_label.text = effect
	effect_label.visible = effect != ""

	var is_tool = item is ToolData
	equip_button.visible = is_tool
	if is_tool:
		equip_button.text = "Unequip" if selected_is_equipped else "Equip"
	destroy_button.visible = not selected_is_equipped and not is_tool

	# Gather elixirs (P3) are drunk from here and incense burned from here;
	# combat potions from battle. Recipe scrolls are studied from here too.
	var drinkable = item is Consumable and item.is_gather_elixir() and count > 0
	var burnable = item is Consumable and item.is_incense() and count > 0
	var studyable = item is Consumable and item.is_recipe_scroll() and count > 0
	use_button.visible = drinkable or burnable or studyable
	use_button.disabled = false
	if drinkable:
		use_button.text = "Drink (%d min buff)" % int(item.buff_minutes)
	elif burnable:
		use_button.text = "Burn (%d min)" % int(item.buff_minutes)
	elif studyable:
		var station := _scroll_station(item)
		var known = station != null and station.known_recipe_ids.has(item.taught_recipe_id)
		use_button.text = "Already studied" if known else "Study"
		use_button.disabled = known

	var can_sell = item.is_sellable and not selected_is_equipped and count > 0
	sell_panel.visible = can_sell
	stack_value_label.get_parent().visible = item.is_sellable
	if item.is_sellable:
		stack_value_label.text = "%s g" % _fmt_gold(_get_unit_sell_value(item) * maxi(count, 1))
	if can_sell:
		sell_slider.max_value = count
		if sell_all_mode:
			_set_slider(count)
		else:
			_set_slider(clampf(sell_slider.value, 1, count))
		_refresh_sell_row()

## Keeps the qty readout and the sell button's total in step with the slider.
func _refresh_sell_row() -> void:
	if selected_item == null: return
	var qty := int(sell_slider.value)
	qty_label.text = str(qty)
	sell_button.text = "Sell %d for %s g" % [qty, _fmt_gold(_get_unit_sell_value(selected_item) * qty)]

## Moves the slider from code without it reading as a player choice.
func _set_slider(value: float) -> void:
	_slider_guard = true
	sell_slider.value = value
	_slider_guard = false
	_refresh_sell_row()

func _on_sell_qty_changed(_value: float) -> void:
	# A player drag speaks for itself: topping the slider out arms "All",
	# anything less disarms it.
	if not _slider_guard:
		sell_all_mode = sell_slider.value >= sell_slider.max_value
	_refresh_sell_row()

func _clear_selection() -> void:
	selected_item = null
	selected_is_equipped = false
	details_content.visible = false
	no_selection_label.visible = true

func _on_sell_pressed() -> void:
	if selected_item and selected_item.is_sellable and not selected_is_equipped:
		# Cache before removing: remove_item clears the selection mid-call
		# when the last copy leaves the inventory.
		var item = selected_item
		var value = _get_unit_sell_value(item)
		var qty = mini(int(sell_slider.value), InventoryManager.get_item_count(item.id))
		if qty > 0 and InventoryManager.remove_item(item.id, qty):
			GameManager.gold_coins += value * qty
			StatsManager.bump(StatsManager.STAT_GOLD_EARNED, value * qty)
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

func _on_equip_pressed() -> void:
	if not (selected_item is ToolData): return

	if selected_is_equipped:
		if GameManager.unequip_tool(selected_item.tool_type):
			_clear_selection()
	else:
		if GameManager.equip_tool(selected_item):
			selected_is_equipped = true
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

## The crafting station whose recipe_db holds this scroll's taught recipe.
func _scroll_station(scroll: Consumable) -> CraftingManager:
	for station in [AlchemyManager, ForgeManager]:
		if station.find_recipe_by_id(scroll.taught_recipe_id) != null:
			return station
	return null

## Studies a recipe scroll: teaches its recipe and consumes one from the pack.
func _study_scroll(scroll: Consumable) -> void:
	var station := _scroll_station(scroll)
	if station == null or not station.learn_recipe(scroll.taught_recipe_id):
		return
	InventoryManager.remove_item(scroll.id, 1)
	AudioManager.play_sfx(Ids.SFX_LEVEL_UP)
	var recipe = station.find_recipe_by_id(scroll.taught_recipe_id)
	NotificationManager.show_item("Recipe learned — %s" % recipe.name, 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

## Burns an incense: lays its grounds-wide timed buff and consumes one.
func _burn_incense(incense: Consumable) -> void:
	var effect := incense.incense_channel()
	if effect == "": return
	InventoryManager.remove_item(incense.id, 1)
	AudioManager.play_sfx(Ids.SFX_POTION)
	GameManager.apply_timed_buff(effect, incense.magnitude, incense.buff_minutes, incense.name)
	# Lighting a Corpse-Candle also stirs minions already resting.
	if incense.use_effect == Ids.CONSUME_INCENSE_EXHAUST:
		MinionManager.hasten_exhaustion(incense.magnitude)
	NotificationManager.show_item("%s burns — %d minutes" % [incense.name, int(incense.buff_minutes)], 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

## Drinks a gather elixir: lays its timed buff and consumes one from the pack.
func _on_use_pressed() -> void:
	if not (selected_item is Consumable) or selected_is_equipped: return
	var elixir: Consumable = selected_item
	if InventoryManager.get_item_count(elixir.id) <= 0: return
	if elixir.is_recipe_scroll():
		_study_scroll(elixir)
		return
	if elixir.is_incense():
		_burn_incense(elixir)
		return
	var effect := ""
	if elixir.use_effect == Ids.CONSUME_GATHER_XP_BUFF:
		effect = Ids.EFFECT_HARVEST_XP_PCT
	elif elixir.use_effect == Ids.CONSUME_GATHER_RARE_BUFF:
		effect = Ids.EFFECT_RARE_CHANCE_PCT
	if effect == "": return
	InventoryManager.remove_item(elixir.id, 1)
	AudioManager.play_sfx(Ids.SFX_POTION)
	GameManager.apply_timed_buff(effect, elixir.magnitude, elixir.buff_minutes, elixir.name)
	NotificationManager.show_item("%s — +%.0f%% for %d minutes" % [elixir.name, elixir.magnitude, int(elixir.buff_minutes)], 1)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

func _on_destroy_pressed() -> void:
	if selected_item and not selected_is_equipped:
		var total_count = InventoryManager.get_item_count(selected_item.id)
		InventoryManager.remove_item(selected_item.id, total_count)
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
