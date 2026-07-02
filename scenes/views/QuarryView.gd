# QuarryView.gd
extends PanelContainer

@onready var limestone_card = %LimestoneCard
@onready var slate_card = %SlateCard
@onready var granite_card = %GraniteCard

func _ready() -> void:
	add_to_group("ui_updates")
	
	limestone_card.setup_card("Limestone Quarry", "Heave chunks of raw stone from the sediment layer.", "Mine", GameManager.current_quarry_duration)
	slate_card.setup_card("Slate Quarry", "Extract slate from the metamorphic rock layer.", "Mine", GameManager.current_quarry_duration)
	granite_card.setup_card("Granite Quarry", "Mine granite from the igneous rock layer.", "Mine", GameManager.current_quarry_duration)
	
	limestone_card.action_triggered.connect(_on_toggle_mining)
	slate_card.action_triggered.connect(_on_toggle_mining)
	granite_card.action_triggered.connect(_on_toggle_mining)
	
	update_ui()

func _process(delta: float) -> void:
	if GameManager.active_action_source == limestone_card:
		var progress = limestone_card.progress_bar.value + delta
		
		if progress >= GameManager.current_quarry_duration:
			progress = 0.0
			_award_mining_rewards()
			
		limestone_card.update_progress(progress)
	else:
		if limestone_card.progress_bar.value > 0.0:
			limestone_card.update_progress(0.0)

func _on_toggle_mining() -> void:
	GameManager.register_activity(limestone_card)

func _award_mining_rewards() -> void:
	GameManager.stone += 1.0
	
	GameManager.add_xp("spelunking", 12.0)
	
	var fossil_chance = 0.05 + (GameManager.skills["spelunking"]["level"] * 0.01)
	if randf() <= fossil_chance:
		GameManager.bones += 1.0
		print("Unearthed a fossilized bone shard inside the limestone!")
		
	get_tree().call_group("ui_updates", "update_ui")

func update_ui() -> void:
	for card in [limestone_card, slate_card, granite_card]:
		if card:
			card.progress_bar.max_value = GameManager.current_quarry_duration
			var is_running = (GameManager.active_action_source == card)
			card.set_button_text(is_running)