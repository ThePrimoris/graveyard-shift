# GraveyardView.gd
extends PanelContainer

var old_grave_progress: float = 0.0
var fresh_grave_progress: float = 0.0
var spooky_grave_progress: float = 0.0

const BONE_ITEM = preload("res://data/items/bones.tres")
const FLESH_ITEM = preload("res://data/items/flesh.tres")
const ECTOPLASM_ITEM = preload("res://data/items/ectoplasm.tres")

@onready var old_grave_card = %OldGraveCard
@onready var fresh_grave_card = %FreshGraveCard
@onready var spooky_grave_card = %SpookyGraveCard

func _ready() -> void:
	add_to_group("ui_updates")
	
	old_grave_card.setup_card("Forgotten Graves", "An Old Grave, only Bones remain.", "Dig", GameManager.current_grave_duration)
	fresh_grave_card.setup_card("Fresh Graves", "Freshly buried. The smell of Rotting Flesh fills the air.", "Dig", GameManager.current_grave_duration)
	spooky_grave_card.setup_card("Haunted Grave", "A Spooky Grave, what could this contain?", "Dig", GameManager.current_grave_duration)
	
	old_grave_card.action_triggered.connect(_on_toggle_old_grave)
	fresh_grave_card.action_triggered.connect(_on_toggle_fresh_grave)
	spooky_grave_card.action_triggered.connect(_on_toggle_spooky_grave)
	
	update_ui()

func _process(delta: float) -> void:
	if GameManager.active_action_source == old_grave_card:
		old_grave_progress += delta
		if old_grave_progress >= GameManager.current_grave_duration:
			old_grave_progress = 0.0
			_award_old_grave_rewards()
		old_grave_card.update_progress(old_grave_progress)
	else:
		if old_grave_progress > 0.0:
			old_grave_progress = 0.0
			old_grave_card.update_progress(0.0)
			
	if GameManager.active_action_source == fresh_grave_card:
		fresh_grave_progress += delta
		if fresh_grave_progress >= GameManager.current_grave_duration:
			fresh_grave_progress = 0.0
			_award_fresh_grave_rewards()
		fresh_grave_card.update_progress(fresh_grave_progress)
	else:
		if fresh_grave_progress > 0.0:
			fresh_grave_progress = 0.0
			fresh_grave_card.update_progress(0.0)
		
	if GameManager.active_action_source == spooky_grave_card:
		spooky_grave_progress += delta
		if spooky_grave_progress >= GameManager.current_grave_duration:
			spooky_grave_progress = 0.0
			_award_spooky_grave_rewards()
		spooky_grave_card.update_progress(spooky_grave_progress)
	else:
		if spooky_grave_progress > 0.0:
			spooky_grave_progress = 0.0
			spooky_grave_card.update_progress(0.0)

func _on_toggle_old_grave() -> void: GameManager.register_activity(old_grave_card)
func _on_toggle_fresh_grave() -> void: GameManager.register_activity(fresh_grave_card)
func _on_toggle_spooky_grave() -> void: GameManager.register_activity(spooky_grave_card)

func _award_old_grave_rewards() -> void:
	var minion_bonus = (GameManager.minions[0]["count"] * GameManager.minions[0]["production"]) + (GameManager.minions[2]["count"] * GameManager.minions[2]["production"])
	var gained = 1 + floor(minion_bonus)
	InventoryManager.add_item(BONE_ITEM, gained)
	NotificationManager.show_item("Bone", gained)
	GameManager.add_xp("graverobbing", 10.0)

func _award_fresh_grave_rewards() -> void:
	var minion_bonus = (GameManager.minions[1]["count"] * GameManager.minions[1]["production"]) + (GameManager.minions[2]["count"] * GameManager.minions[2]["production"])
	var gained = 1 + floor(minion_bonus)
	InventoryManager.add_item(FLESH_ITEM, gained)
	GameManager.add_xp("graverobbing", 25.0)
	
func _award_spooky_grave_rewards() -> void:
	var minion_bonus = (GameManager.minions[3]["count"] * GameManager.minions[3]["production"])
	var gained = 1 + floor(minion_bonus)
	InventoryManager.add_item(ECTOPLASM_ITEM, gained)
	GameManager.add_xp("graverobbing", 60.0)

func update_ui() -> void:
	var g_level = GameManager.skills["graverobbing"]["level"]
	var tool = GameManager.active_tool
	
	# Determine if the currently equipped tool meets the "Bloodforged" requirement
	var has_required_tool = (tool != null and 
							 tool.tool_type == ToolData.ToolType.SHOVEL and 
							 tool.tool_tier >= ToolData.ToolTier.BLOODFORGED)

	if old_grave_card:
		old_grave_card.progress_bar.max_value = GameManager.current_grave_duration
		old_grave_card.set_button_text(GameManager.active_action_source == old_grave_card)
		old_grave_card.action_button.disabled = g_level < 1
		
	if fresh_grave_card:
		fresh_grave_card.progress_bar.max_value = GameManager.current_grave_duration
		fresh_grave_card.set_button_text(GameManager.active_action_source == fresh_grave_card)
		var is_unlocked = (g_level >= 3)
		fresh_grave_card.action_button.disabled = not is_unlocked
		fresh_grave_card.desc_label.text = "Requires level 3 Graverobbing." if not is_unlocked else "Freshly buried. The smell of Rotting Flesh fills the air."
		
	if spooky_grave_card:
		var is_unlocked = (g_level >= 5)
		spooky_grave_card.progress_bar.max_value = GameManager.current_grave_duration
		spooky_grave_card.set_button_text(GameManager.active_action_source == spooky_grave_card)
		
		if not has_required_tool:
			spooky_grave_card.desc_label.text = "Requires a Bloodforged Shovel."
			spooky_grave_card.action_button.disabled = true
		elif not is_unlocked:
			spooky_grave_card.desc_label.text = "Requires level 5 Graverobbing."
			spooky_grave_card.action_button.disabled = true
		else:
			spooky_grave_card.desc_label.text = "A Spooky Grave, what could this contain?"
			spooky_grave_card.action_button.disabled = false
