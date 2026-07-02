# InventorySlot.gd
extends PanelContainer

signal slot_clicked(item: Item)

var current_item: Item = null
var slot_index: int = -1

# Unique name handles
@onready var icon_rect: TextureRect = %IconRect
@onready var count_label: Label = %CountLabel
@onready var select_button = $Button

func _ready() -> void:
	select_button.pressed.connect(_on_button_pressed)

# --- ADDED: Helper to match InventoryView calls ---
func setup(item: Item, quantity: int) -> void:
	print("DEBUG: Setting up slot index ", slot_index, " with item: ", item.name)
	current_item = item
	icon_rect.texture = item.icon
	count_label.text = str(quantity) if quantity > 1 else ""
	select_button.disabled = false

# --- ADDED: Helper to match InventoryView calls ---
func clear_slot() -> void:
	current_item = null
	icon_rect.texture = null
	count_label.text = ""
	select_button.disabled = true

# Keep your existing logic for logic compatibility
func display_slot_data(slot_data) -> void:
	if icon_rect == null or count_label == null: return 
	
	if slot_data == null:
		clear_slot()
	else:
		setup(slot_data["item"], slot_data["quantity"])

func _on_button_pressed() -> void:
	if current_item:
		slot_clicked.emit(current_item)

func _get_drag_data(_at_position: Vector2):
	if InventoryManager.slots[slot_index] == null: return null
	
	var drag_preview = TextureRect.new()
	drag_preview.texture = icon_rect.texture
	drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_preview.custom_minimum_size = Vector2(64, 64)
	set_drag_preview(drag_preview)
	
	return slot_index

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return typeof(data) == TYPE_INT

func _drop_data(_at_position: Vector2, data) -> void:
	var from_slot_index = data
	InventoryManager.swap_slots(from_slot_index, slot_index)