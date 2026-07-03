# GraveyardView.gd
extends PanelContainer

var fresh_grave_progress: float = 0.0
var desc_crypt_progress: float = 0.0
var forgot_trench_progress: float = 0.0

const BONE_ITEM = preload("res://data/items/bones.tres")
const FLESH_ITEM = preload("res://data/items/flesh.tres")
const GRAVE_DUST_ITEM = preload("res://data/items/grave_dust.tres")

@onready var fresh_grave_card = %FleshGraveCard
@onready var desc_crypt_card = %BoneGraveCard
@onready var forgot_trench_card = %MeatGraveCard
@onready var bedlam_wards_card = %ChainsGraveCard
@onready var silent_sepulcher_card = %WaxGraveCard

func _ready() -> void:
	add_to_group("ui_updates")
	
	fresh_grave_card.setup_card("Fresh Grave", "A freshly dug grave.", "Dig", GameManager.current_grave_duration)
	desc_crypt_card.setup_card("Desecrated Crypt", "Ominous", "Dig", GameManager.current_grave_duration)
	forgot_trench_card.setup_card("Forgotten Trenches", "Mass graves, from a long forgotten battle.", "Dig", GameManager.current_grave_duration)
	bedlam_wards_card.setup_card("Bedlam Wards", "Ancient barriers that protect the dead.", "Dig", GameManager.current_grave_duration)
	silent_sepulcher_card.setup_card("Silent Sepulchers", "Sealed resting places, untouched by time.", "Dig", GameManager.current_grave_duration)

	fresh_grave_card.action_triggered.connect(_on_toggle_fresh_grave)
	desc_crypt_card.action_triggered.connect(_on_toggle_desc_crypt)
	forgot_trench_card.action_triggered.connect(_on_toggle_forgot_trench)
	bedlam_wards_card.action_triggered.connect(_on_toggle_bedlam_wards)
	silent_sepulcher_card.action_triggered.connect(_on_toggle_silent_sepulcher)

	for card in [
	fresh_grave_card,
	desc_crypt_card,
	forgot_trench_card,
	bedlam_wards_card,
	silent_sepulcher_card
	]:
		card.set_progress_color("#c8a24d")

	update_ui()

func _process(delta: float) -> void:
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
			
	if GameManager.active_action_source == desc_crypt_card:
		desc_crypt_progress += delta
		if desc_crypt_progress >= GameManager.current_grave_duration:
			desc_crypt_progress = 0.0
			_award_desc_crypt_rewards()
		desc_crypt_card.update_progress(desc_crypt_progress)
	else:
		if desc_crypt_progress > 0.0:
			desc_crypt_progress = 0.0
			desc_crypt_card.update_progress(0.0)
		
	if GameManager.active_action_source == forgot_trench_card:
		forgot_trench_progress += delta
		if forgot_trench_progress >= GameManager.current_grave_duration:
			forgot_trench_progress = 0.0
			_award_forgot_trench_rewards()
		forgot_trench_card.update_progress(forgot_trench_progress)
	else:
		if forgot_trench_progress > 0.0:
			forgot_trench_progress = 0.0
			forgot_trench_card.update_progress(0.0)

func _on_toggle_fresh_grave() -> void: GameManager.register_activity(fresh_grave_card)
func _on_toggle_desc_crypt() -> void: GameManager.register_activity(desc_crypt_card)
func _on_toggle_forgot_trench() -> void: GameManager.register_activity(forgot_trench_card)
func _on_toggle_bedlam_wards() -> void: GameManager.register_activity(bedlam_wards_card)
func _on_toggle_silent_sepulcher() -> void: GameManager.register_activity(silent_sepulcher_card)

func _award_fresh_grave_rewards() -> void:
	var minion_bonus = (GameManager.minions[0]["count"] * GameManager.minions[0]["production"]) + (GameManager.minions[2]["count"] * GameManager.minions[2]["production"])
	var gained = 1 + floor(minion_bonus)
	InventoryManager.add_item(BONE_ITEM, gained)
	NotificationManager.show_item("Bone", gained)
	GameManager.add_xp("graverobbing", 10.0)

func _award_desc_crypt_rewards() -> void:
	var minion_bonus = (GameManager.minions[1]["count"] * GameManager.minions[1]["production"]) + (GameManager.minions[2]["count"] * GameManager.minions[2]["production"])
	var gained = 1 + floor(minion_bonus)
	InventoryManager.add_item(FLESH_ITEM, gained)
	GameManager.add_xp("graverobbing", 25.0)
	
func _award_forgot_trench_rewards() -> void:
	var minion_bonus = (GameManager.minions[3]["count"] * GameManager.minions[3]["production"])
	var gained = 1 + floor(minion_bonus)
	InventoryManager.add_item(GRAVE_DUST_ITEM, gained)
	GameManager.add_xp("graverobbing", 60.0)

func update_ui() -> void:
	var g_level = GameManager.skills["graverobbing"]["level"]
	var tool = GameManager.active_tool
	
	var has_required_tool = (tool != null and 
							 tool.tool_type == ToolData.ToolType.SHOVEL and 
							 tool.tool_tier >= ToolData.ToolTier.GALVANIZED)

	if fresh_grave_card:
		fresh_grave_card.progress_bar.max_value = GameManager.current_grave_duration
		fresh_grave_card.set_button_text(GameManager.active_action_source == fresh_grave_card)
		fresh_grave_card.action_button.disabled = g_level < 1
		
	if desc_crypt_card:
		desc_crypt_card.progress_bar.max_value = GameManager.current_grave_duration
		desc_crypt_card.set_button_text(GameManager.active_action_source == desc_crypt_card)
		var crypt_unlocked = (g_level >= 3)
		desc_crypt_card.action_button.disabled = not crypt_unlocked
		desc_crypt_card.desc_label.text = "Requires level 3 Graverobbing." if not crypt_unlocked else "Freshly buried. The smell of Rotting Flesh fills the air."

		if forgot_trench_card:
			var trench_unlocked = (g_level >= 5)

			forgot_trench_card.progress_bar.max_value = GameManager.current_grave_duration
			forgot_trench_card.set_button_text(GameManager.active_action_source == forgot_trench_card)

			if not has_required_tool and not trench_unlocked:
				forgot_trench_card.desc_label.text = "Requires level 5 Graverobbing and a Galvanized Tool."
				forgot_trench_card.action_button.disabled = true
			elif not has_required_tool:
				forgot_trench_card.desc_label.text = "Requires a Galvanized Tool."
				forgot_trench_card.action_button.disabled = true
			elif not trench_unlocked:
				forgot_trench_card.desc_label.text = "Requires level 5 Graverobbing."
				forgot_trench_card.action_button.disabled = true
			else:
				forgot_trench_card.desc_label.text = "A Spooky Grave, what could this contain?"
				forgot_trench_card.action_button.disabled = false
