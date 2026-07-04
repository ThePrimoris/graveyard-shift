extends PanelContainer

@onready var resource_button_container = %AltarResourceContainer
@onready var essence_label = %EssenceLabel
@onready var sacrifice_progress_bar = %SacrificeProgressBar

func _ready() -> void:
	add_to_group("ui_updates")
	
	# Reactive tracking connection
	if NecromancyManager.has_signal("necromancy_updated"):
		NecromancyManager.necromancy_updated.connect(update_ui)
		
		
	_initialize_altar_slots()
	update_ui()

func _initialize_altar_slots() -> void:
	for child in resource_button_container.get_children():
		child.queue_free()
		
	# Dynamically populate buttons from NecromancyManager configuration mapping
	for item_id in NecromancyManager.sacrifice_values:
		var btn = Button.new()
		btn.name = item_id
		resource_button_container.add_child(btn)
		btn.pressed.connect(_on_sacrifice_button_pressed.bind(item_id))

func update_ui() -> void:
	if essence_label:
		essence_label.text = "Necromantic Essence: %d" % NecromancyManager.essence
		
	for btn in resource_button_container.get_children():
		var item_id = btn.name
		var current_stock = InventoryManager.get_item_count(item_id)
		var values = NecromancyManager.sacrifice_values[item_id]
		
		# Pull your core bulk increment select count from GameManager
		var sacrifice_amt = GameManager.get("buy_amount") if "buy_amount" in GameManager else 10
		
		btn.text = "Sacrifice x%d %s\n(+%.1f XP, +%d Essence) [Owned: %d]" % [
			sacrifice_amt,
			item_id.capitalize(),
			values["xp"] * sacrifice_amt,
			values["essence"] * sacrifice_amt,
			current_stock
		]
		
		btn.disabled = current_stock < sacrifice_amt

func _on_sacrifice_button_pressed(item_id: String) -> void:
	var sacrifice_amt = GameManager.get("buy_amount") if "buy_amount" in GameManager else 10
	var success = NecromancyManager.sacrifice_resource(item_id, sacrifice_amt)
	
	if success and sacrifice_progress_bar:
		_juice_altar_bar()

func _juice_altar_bar() -> void:
	var tween = create_tween()
	sacrifice_progress_bar.value = 0
	tween.tween_property(sacrifice_progress_bar, "value", 100, 0.12)
	tween.tween_property(sacrifice_progress_bar, "value", 0, 0.08)

func _on_close_pressed() -> void:
	# Cleanly delete this instantiated scene from memory, returning control to Undercroft
	queue_free()
