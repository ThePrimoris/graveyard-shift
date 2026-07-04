extends PanelContainer

@export var minion_card_scene: PackedScene
@onready var card_container = %MinionCardContainer

func _ready() -> void:
	add_to_group("ui_updates")
	
	# Connect to the updated manager signal for automated reactive updates
	if NecromancyManager.has_signal("necromancy_updated"):
		NecromancyManager.necromancy_updated.connect(update_ui)
	
	_initialize_undercroft()
	update_ui()

func _initialize_undercroft() -> void:
	for child in card_container.get_children():
		child.queue_free()
		
	# Instantiates a card view dynamically for every auto-discovered minion profile
	for minion in NecromancyManager.minion_templates:
		if not minion: continue
		
		var card = minion_card_scene.instantiate()
		card_container.add_child(card)
		
		card.setup_card(minion.name, minion.description)
		card.buy_triggered.connect(_on_feed_materials_pressed.bind(minion.id))

func update_ui() -> void:
	var index = 0
	
	for minion in NecromancyManager.minion_templates:
		if not minion: continue
		if index >= card_container.get_child_count(): break
		
		var card = card_container.get_child(index)
		var progress_state = NecromancyManager.minion_progress.get(minion.id, {"level": 1, "progress": {}})
		var current_lvl = progress_state["level"]
		
		# 1. Update card descriptions dynamically to show current level scaling metrics
		var max_hp = minion.base_hp + ((current_lvl - 1) * minion.hp_per_level)
		var current_atk = minion.base_atk + ((current_lvl - 1) * minion.atk_per_level)
		var stat_desc = "HP: %d | ATK: %.1f\n%s" % [max_hp, current_atk, minion.description]
		
		if card.has_method("update_description"):
			card.update_description(stat_desc)
		
		# 2. Process and aggregate the requirements list layout
		var cost_lines: Array[String] = []
		var player_has_any_valid_materials = false
		
		for item_id in minion.requirements:
			var base_amt = minion.requirements[item_id]
			if base_amt <= 0: continue
			
			var required_amt = NecromancyManager.get_required_amount(minion, item_id, current_lvl)
			var current_progress = progress_state["progress"].get(item_id, 0.0)
			var inventory_count = InventoryManager.get_item_count(item_id)
			
			cost_lines.append("%s: %d / %d (Have: %d)" % [item_id.capitalize(), current_progress, required_amt, inventory_count])
			
			if inventory_count > 0 and current_progress < required_amt:
				player_has_any_valid_materials = true
				
		var complete_cost_string = "\n".join(cost_lines)
		if complete_cost_string == "":
			complete_cost_string = "Fully optimized."
			
		# 3. Commit states down to the display card instance
		card.update_card_state(
			true, 
			current_lvl,
			"Feed Materials",
			complete_cost_string,
			player_has_any_valid_materials
		)
		index += 1

func _on_feed_materials_pressed(minion_id: String) -> void:
	var minion = NecromancyManager._find_template(minion_id)
	if not minion: return
	
	# Leverages your existing purchase increments selection from GameManager
	var feed_amount = GameManager.get("buy_amount") if "buy_amount" in GameManager else 10
	
	# Feeds all required resources matching the minion profile layout criteria
	for item_id in minion.requirements:
		if minion.requirements[item_id] > 0:
			NecromancyManager.feed_material_to_minion(minion_id, item_id, feed_amount)
