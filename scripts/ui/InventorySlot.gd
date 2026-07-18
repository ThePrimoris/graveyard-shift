# InventorySlot.gd
extends PanelContainer

signal slot_clicked(item: Item)
## Right-click on a filled slot: the view opens its context menu here.
signal slot_right_clicked(slot_index: int)

const DROP_TINT := Color(1.35, 1.35, 1.05)

var current_item: Item = null
var slot_index: int = -1

# Unique name handles
@onready var icon_rect: TextureRect = %IconRect
@onready var count_label: Label = %CountLabel
@onready var select_button = $Button

func _ready() -> void:
	select_button.pressed.connect(_on_button_pressed)
	select_button.gui_input.connect(_on_button_gui_input)
	select_button.mouse_exited.connect(func(): _set_drop_highlight(false))
	# The full-size Button eats mouse input before this panel's drag hooks can
	# run, so forward its drag queries here — this is what makes items movable.
	select_button.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)

# --- ADDED: Helper to match InventoryView calls ---
func setup(item: Item, quantity: int) -> void:
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

func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if current_item:
			slot_right_clicked.emit(slot_index)
			accept_event()

func _get_drag_data(_at_position: Vector2):
	if InventoryManager.slots[slot_index] == null: return null

	# Ghost of the stack under the cursor: icon + count, centered on the mouse.
	var preview_root = Control.new()
	var drag_icon = TextureRect.new()
	drag_icon.texture = icon_rect.texture
	drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_icon.custom_minimum_size = Vector2(56, 56)
	drag_icon.size = Vector2(56, 56)
	drag_icon.position = Vector2(-28, -28)
	drag_icon.modulate = Color(1, 1, 1, 0.85)
	preview_root.add_child(drag_icon)
	if count_label.text != "":
		var drag_count = Label.new()
		drag_count.text = count_label.text
		drag_count.position = Vector2(6, 6)
		drag_count.add_theme_font_size_override("font_size", 12)
		drag_icon.add_child(drag_count)
	set_drag_preview(preview_root)

	return slot_index

func _can_drop_data(_at_position: Vector2, data) -> bool:
	var ok = typeof(data) == TYPE_INT and int(data) != slot_index
	_set_drop_highlight(ok)
	return ok

func _drop_data(_at_position: Vector2, data) -> void:
	_set_drop_highlight(false)
	var from_slot_index = data
	InventoryManager.merge_or_swap(from_slot_index, slot_index)

## Brightens the slot while a valid drag hovers it, so the drop target reads.
func _set_drop_highlight(active: bool) -> void:
	modulate = DROP_TINT if active else Color.WHITE

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_drop_highlight(false)
