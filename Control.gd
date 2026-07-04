extends Control

const SLOT_SCENE = preload("res://scenes/inventory/InventorySlot.tscn")

@onready var inventory_grid: GridContainer = %InventoryGrid
@onready var timer: Timer = %GameTickTimer

# Full Screen View Containers
@onready var graveyard_view: PanelContainer = %GraveyardView
@onready var undercroft_view: PanelContainer = %UndercroftView
@onready var forest_view: PanelContainer = %ForestView        
@onready var quarry_view: PanelContainer = %QuarryView
@onready var inventory_view: PanelContainer = %InventoryView
@onready var shop_view: PanelContainer = %ShopView
@onready var ritual_altar_view: PanelContainer = %RitualView

func _ready() -> void:
	add_to_group("ui_updates")
	add_to_group("view_manager")
	
	InventoryManager.inventory_updated.connect(update_ui)
	
	if timer.timeout.is_connected(_on_game_tick):
		timer.timeout.disconnect(_on_game_tick)
	timer.timeout.connect(_on_game_tick)
	
	_build_inventory_slots()
	
	switch_view("graveyard")
	update_ui()

func _build_inventory_slots() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
		
	for i in range(InventoryManager.TOTAL_SLOTS):
		var slot_instance = SLOT_SCENE.instantiate()
		inventory_grid.add_child(slot_instance)
		slot_instance.slot_index = i

func _on_game_tick() -> void:
	var hound_count = GameManager.minions[2]["count"]
	if hound_count > 0:
		if randf() <= 0.02:
			GameManager.gold_coins += (1 + floor(hound_count / 5))
			
	get_tree().call_group("ui_updates", "update_ui")

func switch_view(target_view: String) -> void:
	if graveyard_view: graveyard_view.visible = (target_view == "graveyard")
	if undercroft_view: undercroft_view.visible = (target_view == "undercroft")
	if shop_view: shop_view.visible = (target_view == "shop")
	if forest_view: forest_view.visible = (target_view == "forest") 
	if quarry_view: quarry_view.visible = (target_view == "quarry") 
	if inventory_view: inventory_view.visible = (target_view == "inventory")
	if ritual_altar_view: ritual_altar_view.visible = (target_view == "ritual_altar")

	get_tree().call_group("ui_updates", "update_ui")

func update_ui() -> void:
	if inventory_grid == null: return
	
	var slots_ui = inventory_grid.get_children()
	for i in range(slots_ui.size()):
		if i < InventoryManager.slots.size():
			slots_ui[i].display_slot_data(InventoryManager.slots[i])

func create_floating_text(text_content: String, start_position: Vector2, text_color: Color) -> void:
	var popup = Label.new()
	popup.text = text_content
	popup.global_position = start_position
	popup.add_theme_color_override("font_color", text_color)
	popup.add_theme_font_size_override("font_size", 18)
	add_child(popup)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(popup, "global_position", start_position + Vector2(randf_range(-20, 20), -60), 0.6)
	tween.tween_property(popup, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(popup.queue_free)
