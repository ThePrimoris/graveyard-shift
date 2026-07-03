# ForestView.gd
extends PanelContainer

var forest_progress: float = 0.0
const WOOD_ITEM = preload("res://data/items/wood_log.tres")

@onready var gravewood_tree_card = %GravewoodTreeCard
@onready var blackthorn_tree_card = %BlackthornTreeCard
@onready var ashwood_tree_card = %AshTreeCard
@onready var angelwood_tree_card = %AngelwoodTreeCard
@onready var walnut_tree_card = %WalnutTreeCard

func _ready() -> void:
	add_to_group("ui_updates")
	
	gravewood_tree_card.setup_card("Withered Trees", "Chop down brittle, decaying trees for basic wood logs.", "Chop", GameManager.current_tree_duration)
	blackthorn_tree_card.setup_card("Thornwood Grove", "Chop down flexible willow trees for better wood logs.", "Chop", GameManager.current_tree_duration)
	ashwood_tree_card.setup_card("Shrouded Ashwoods", "Chop down dark, dense black oak trees for premium wood logs.", "Chop", GameManager.current_tree_duration)
	angelwood_tree_card.setup_card("Hallowed Thicket", "Chop down ethereal angelwood trees for the finest wood logs.", "Chop", GameManager.current_tree_duration)
	walnut_tree_card.setup_card("Tangled Ridge", "Chop down sturdy walnut trees for durable wood logs.", "Chop", GameManager.current_tree_duration)

	gravewood_tree_card.action_triggered.connect(_on_toggle_chopping)
	blackthorn_tree_card.action_triggered.connect(_on_toggle_chopping)
	ashwood_tree_card.action_triggered.connect(_on_toggle_chopping)
	angelwood_tree_card.action_triggered.connect(_on_toggle_chopping)
	walnut_tree_card.action_triggered.connect(_on_toggle_chopping)

	for card in [
	gravewood_tree_card,
	blackthorn_tree_card,
	ashwood_tree_card,
	angelwood_tree_card,
	walnut_tree_card
	]:
		card.set_progress_color("#4c9a47")

	update_ui()

func _process(delta: float) -> void:
	if GameManager.active_action_source == gravewood_tree_card:
		forest_progress += delta
		
		if forest_progress >= GameManager.current_tree_duration:
			forest_progress = 0.0
			_award_forest_rewards()
			
		gravewood_tree_card.update_progress(forest_progress)
	else:
		if forest_progress > 0.0:
			forest_progress = 0.0
			gravewood_tree_card.update_progress(0.0)

func _on_toggle_chopping() -> void:
	GameManager.register_activity(gravewood_tree_card)

func _award_forest_rewards() -> void:
	InventoryManager.add_item(WOOD_ITEM, 1)
	
	GameManager.add_xp("lumbering", 15.0)
	
	var sap_chance = 0.10 + (GameManager.skills["lumbering"]["level"] * 0.01)
	if randf() <= sap_chance:
		GameManager.tree_sap += 1.0
		print("Found some sticky Tree Sap!")
		
	get_tree().call_group("ui_updates", "update_ui")

func update_ui() -> void:
		for card in [gravewood_tree_card, blackthorn_tree_card, ashwood_tree_card, angelwood_tree_card, walnut_tree_card]:
			if card:
				card.progress_bar.max_value = GameManager.current_tree_duration
				var is_running = (GameManager.active_action_source == card)
				card.set_button_text(is_running)
