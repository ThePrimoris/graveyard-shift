# UndercroftView.gd
extends PanelContainer

@export var minion_card_scene: PackedScene
@onready var card_container = %MinionCardContainer

func _ready() -> void:
	add_to_group("ui_updates")
	GameManager.calculate_necromancy_unlocks()
	_initialize_undercroft()
	update_ui()

func _initialize_undercroft() -> void:
	for child in card_container.get_children():
		child.queue_free()
		
	for minion_data in GameManager.minions:
		var card = minion_card_scene.instantiate()
		card_container.add_child(card)
		card.setup_card(minion_data["name"], "A loyal unholy construct.")
		card.buy_triggered.connect(_on_buy_minion_pressed.bind(minion_data))

func update_ui() -> void:
	GameManager.calculate_necromancy_unlocks()
	
	# 🌟 MATCHED TO YOUR EXACT INVENTORY ID: 'bone'
	var current_bones = InventoryManager.get_item_count("bone")
	var current_flesh = InventoryManager.get_item_count("flesh")
	var current_ecto = InventoryManager.get_item_count("ectoplasm")
	
	var index = 0
	for minion_data in GameManager.minions:
		if index < card_container.get_child_count():
			var card = card_container.get_child(index)
			var bulk_cost = GameManager.get_bulk_cost(minion_data, GameManager.buy_amount)
			
			var cost_string = "Bones: %d" % bulk_cost["bones"]
			if minion_data.get("cost_flesh", 0) > 0:
				cost_string += "  Flesh: %d" % bulk_cost["flesh"]
			if minion_data.get("cost_ectoplasm", 0) > 0:
				cost_string += "  Ectoplasm: %d" % bulk_cost["ectoplasm"]
			
			var can_afford = true
			if bulk_cost["bones"] > 0 and current_bones < bulk_cost["bones"]: can_afford = false
			if bulk_cost["flesh"] > 0 and current_flesh < bulk_cost["flesh"]: can_afford = false
			if bulk_cost["ectoplasm"] > 0 and current_ecto < bulk_cost["ectoplasm"]: can_afford = false
			
			card.update_card_state(
				minion_data["unlocked"],
				minion_data["count"],
				"Summon",
				cost_string,
				can_afford
			)
		index += 1

func _on_buy_minion_pressed(minion_data: Dictionary) -> void:
	var amt = GameManager.buy_amount
	var costs = GameManager.get_bulk_cost(minion_data, amt)
	
	# 🌟 MATCHED TO YOUR EXACT INVENTORY ID: 'bone'
	var current_bones = InventoryManager.get_item_count("bone")
	var current_flesh = InventoryManager.get_item_count("flesh")
	var current_ecto = InventoryManager.get_item_count("ectoplasm")
	
	var can_afford = true
	if costs["bones"] > 0 and current_bones < costs["bones"]: can_afford = false
	if costs["flesh"] > 0 and current_flesh < costs["flesh"]: can_afford = false
	if costs["ectoplasm"] > 0 and current_ecto < costs["ectoplasm"]: can_afford = false
	
	if can_afford:
		# Deduct items using your clean inventory string IDs
		if costs["bones"] > 0: InventoryManager.remove_item("bone", costs["bones"])
		if costs["flesh"] > 0: InventoryManager.remove_item("flesh", costs["flesh"])
		if costs["ectoplasm"] > 0: InventoryManager.remove_item("ectoplasm", costs["ectoplasm"])
		
		minion_data["count"] += amt
		
		var xp_reward = 15.0
		match minion_data["id"]:
			"zombie": xp_reward = 40.0
			"hound": xp_reward = 60.0
			"wraith": xp_reward = 100.0
			
		GameManager.add_xp("necromancy", xp_reward * amt)
		get_tree().call_group("ui_updates", "update_ui")
