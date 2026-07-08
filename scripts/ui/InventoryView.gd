# InventoryView.gd
extends PanelContainer

@export var inventory_slot_scene: PackedScene # Assign your InventorySlot.tscn here in Inspector

@onready var details_panel: VBoxContainer = %DetailsPanel
@onready var details_content: VBoxContainer = %DetailsContent
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_icon_rect: TextureRect = %ItemIconRect
@onready var item_description_label: Label = %ItemDescriptionLabel
@onready var sell_button: Button = %SellButton
@onready var sell_all_button: Button = %SellAllButton
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

func _ready() -> void:
	add_to_group("ui_updates")

	sell_button.pressed.connect(_on_sell_pressed)
	sell_all_button.pressed.connect(_on_sell_all_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	destroy_button.pressed.connect(_on_destroy_pressed)

	for i in range(tool_slot_buttons.size()):
		tool_slot_buttons[i].pressed.connect(_on_tool_slot_pressed.bind(i))

	# The panel keeps its reserved width at all times so selecting an item
	# never shifts the rest of the layout; only its content toggles.
	details_content.visible = false

	# Rebuild the grid only when the inventory actually changes, not on every UI tick
	InventoryManager.inventory_updated.connect(refresh_inventory_grid)

	refresh_inventory_grid()
	update_ui()

# This is the "Engine" that builds the slots from the InventoryManager data
func refresh_inventory_grid() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()

	for i in range(InventoryManager.slots.size()):
		var slot_data = InventoryManager.slots[i]

		var slot_instance = inventory_slot_scene.instantiate()
		inventory_grid.add_child(slot_instance)

		# Ensure we assign the index so dragging works
		slot_instance.slot_index = i

		if slot_data != null:
			slot_instance.setup(slot_data["item"], slot_data["quantity"])
			slot_instance.slot_clicked.connect(_on_item_selected)
		else:
			slot_instance.clear_slot()

	update_ui()

func update_ui() -> void:
	_refresh_tool_slots()

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

func _refresh_tool_slots() -> void:
	for i in range(tool_slot_buttons.size()):
		var btn: Button = tool_slot_buttons[i]
		var tool = GameManager.get_equipped_tool(i)
		var type_name = ToolData.ToolType.keys()[i].capitalize()

		if tool:
			# Icon-only, sized like a regular inventory slot; details go in the tooltip
			btn.text = "" if tool.icon else tool.name.left(6)
			btn.icon = tool.icon
			btn.tooltip_text = "%s — %.2fx speed%s\nClick to inspect / unequip." % [
				tool.name, tool.speed_multiplier,
				(", +%d yield" % tool.yield_bonus) if tool.yield_bonus > 0 else ""
			]
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
	_display_item_details(item)

func _get_unit_sell_value(item: Item) -> int:
	return maxi(1, item.sell_value)

func _display_item_details(item: Item) -> void:
	details_content.visible = true
	item_name_label.text = item.name
	item_icon_rect.texture = item.icon

	if item.description != "":
		item_description_label.text = item.description
	else:
		item_description_label.text = "No description available."

	var is_tool = item is ToolData
	equip_button.visible = is_tool
	if is_tool:
		equip_button.text = "Unequip" if selected_is_equipped else "Equip"
	sell_button.visible = item.is_sellable and not selected_is_equipped
	sell_all_button.visible = item.is_sellable and not selected_is_equipped
	destroy_button.visible = not selected_is_equipped and not is_tool

	if item.is_sellable:
		var unit_value = _get_unit_sell_value(item)
		sell_button.text = "Sell (%d g)" % unit_value
		sell_all_button.text = "Sell All (%d g)" % (unit_value * InventoryManager.get_item_count(item.id))

func _clear_selection() -> void:
	selected_item = null
	selected_is_equipped = false
	details_content.visible = false

func _on_sell_pressed() -> void:
	if selected_item and selected_item.is_sellable and not selected_is_equipped:
		# Cache before removing: remove_item clears the selection mid-call
		# when the last copy leaves the inventory.
		var item = selected_item
		var value = _get_unit_sell_value(item)
		if InventoryManager.remove_item(item.id, 1):
			GameManager.gold_coins += value
		get_tree().call_group("ui_updates", "update_ui")

func _on_sell_all_pressed() -> void:
	if selected_item and selected_item.is_sellable and not selected_is_equipped:
		var item = selected_item
		var value = _get_unit_sell_value(item)
		var count = InventoryManager.get_item_count(item.id)
		if count > 0 and InventoryManager.remove_item(item.id, count):
			GameManager.gold_coins += value * count
		get_tree().call_group("ui_updates", "update_ui")

func _on_equip_pressed() -> void:
	if not (selected_item is ToolData): return

	if selected_is_equipped:
		if GameManager.unequip_tool(selected_item.tool_type):
			_clear_selection()
	else:
		if GameManager.equip_tool(selected_item):
			selected_is_equipped = true
	get_tree().call_group("ui_updates", "update_ui")

func _on_destroy_pressed() -> void:
	if selected_item and not selected_is_equipped:
		var total_count = InventoryManager.get_item_count(selected_item.id)
		InventoryManager.remove_item(selected_item.id, total_count)
		get_tree().call_group("ui_updates", "update_ui")
