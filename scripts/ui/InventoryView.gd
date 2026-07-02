# InventoryView.gd
extends PanelContainer

@export var inventory_slot_scene: PackedScene # Assign your InventorySlot.tscn here in Inspector

@onready var details_panel: VBoxContainer = %DetailsPanel
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_icon_rect: TextureRect = %ItemIconRect
@onready var item_description_label: Label = %ItemDescriptionLabel
@onready var sell_button: Button = %SellButton
@onready var destroy_button: Button = %DestroyButton

@onready var inventory_grid: GridContainer = %InventoryGrid 

var selected_item: Item = null

func _ready() -> void:
	add_to_group("ui_updates")
	
	sell_button.pressed.connect(_on_sell_pressed)
	destroy_button.pressed.connect(_on_destroy_pressed)
	
	details_panel.visible = false 
	
	# Initial fill
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

func update_ui() -> void:
	refresh_inventory_grid()
	
	if selected_item:
		# Check if the item still exists in inventory
		if InventoryManager.get_item_count(selected_item.id) <= 0:
			_clear_selection()
		else:
			_display_item_details(selected_item)

func _on_item_selected(item: Item) -> void:
	selected_item = item
	_display_item_details(item)

func _display_item_details(item: Item) -> void:
	details_panel.visible = true
	item_name_label.text = item.name
	item_icon_rect.texture = item.icon
	
	if item.description != "":
		item_description_label.text = item.description
	else:
		item_description_label.text = "No description available."

func _clear_selection() -> void:
	selected_item = null
	details_panel.visible = false

func _on_sell_pressed() -> void:
	if selected_item:
		InventoryManager.remove_item(selected_item.id, 1)
		get_tree().call_group("ui_updates", "update_ui")

func _on_destroy_pressed() -> void:
	if selected_item:
		var total_count = InventoryManager.get_item_count(selected_item.id)
		InventoryManager.remove_item(selected_item.id, total_count)
		get_tree().call_group("ui_updates", "update_ui")
