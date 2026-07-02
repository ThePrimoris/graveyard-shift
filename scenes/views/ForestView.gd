# ForestView.gd
extends PanelContainer

var forest_progress: float = 0.0
const WOOD_ITEM = preload("res://data/items/wood_log.tres")

@onready var dead_tree_card = %DeadTreeCard
@onready var willow_tree_card = %WillowTreeCard
@onready var black_oak_tree_card = %BlackOakTreeCard

func _ready() -> void:
	add_to_group("ui_updates")
	
	dead_tree_card.setup_card("Withered Trees", "Chop down brittle, decaying trees for basic wood logs.", "Chop", GameManager.current_tree_duration)
	willow_tree_card.setup_card("Weeping Willow Trees", "Chop down flexible willow trees for better wood logs.", "Chop", GameManager.current_tree_duration)
	black_oak_tree_card.setup_card("Black Oak Trees", "Chop down dark, dense black oak trees for premium wood logs.", "Chop", GameManager.current_tree_duration)

	dead_tree_card.action_triggered.connect(_on_toggle_chopping)
	willow_tree_card.action_triggered.connect(_on_toggle_chopping)
	black_oak_tree_card.action_triggered.connect(_on_toggle_chopping)

	update_ui()

func _process(delta: float) -> void:
	if GameManager.active_action_source == dead_tree_card:
		forest_progress += delta
		
		if forest_progress >= GameManager.current_tree_duration:
			forest_progress = 0.0
			_award_forest_rewards()
			
		dead_tree_card.update_progress(forest_progress)
	else:
		if forest_progress > 0.0:
			forest_progress = 0.0
			dead_tree_card.update_progress(0.0)

func _on_toggle_chopping() -> void:
	GameManager.register_activity(dead_tree_card)

func _award_forest_rewards() -> void:
	InventoryManager.add_item(WOOD_ITEM, 1)
	
	GameManager.add_xp("lumbering", 15.0)
	
	var sap_chance = 0.10 + (GameManager.skills["lumbering"]["level"] * 0.01)
	if randf() <= sap_chance:
		GameManager.tree_sap += 1.0
		print("Found some sticky Tree Sap!")
		
	get_tree().call_group("ui_updates", "update_ui")

func update_ui() -> void:
		for card in [dead_tree_card, willow_tree_card, black_oak_tree_card]:
			if card:
				card.progress_bar.max_value = GameManager.current_tree_duration
				var is_running = (GameManager.active_action_source == card)
				card.set_button_text(is_running)
