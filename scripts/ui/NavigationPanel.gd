extends PanelContainer

@onready var inv_btn: Button = %InventoryNavButton
@onready var shop_btn: Button = %ShopNavButton
@onready var grave_btn: Button = %Graverobbing
@onready var lumber_btn: Button = %Lumbering
@onready var spelunk_btn: Button = %Spelunking

@onready var grave_xp: Label = %GraverobbingXPLabel
@onready var lumber_xp: Label = %LumberingXPLabel
@onready var spelunk_xp: Label = %SpelunkingXPLabel

@onready var gold_lbl: Label = %GoldValueLabel

func _ready() -> void:
	add_to_group(Ids.GROUP_UI_UPDATES)

	shop_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_SHOP))
	inv_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_INVENTORY))
	grave_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_GRAVEYARD))
	lumber_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_FOREST))
	spelunk_btn.pressed.connect(_on_nav_pressed.bind(Ids.VIEW_QUARRY))

	update_ui()

func update_ui() -> void:
	_update_row(Ids.SKILL_GRAVEROBBING, grave_btn, grave_xp)
	_update_row(Ids.SKILL_LUMBERING, lumber_btn, lumber_xp)
	_update_row(Ids.SKILL_SPELUNKING, spelunk_btn, spelunk_xp)

	if gold_lbl:
		gold_lbl.text = "Gold: %d" % GameManager.gold_coins

func _update_row(skill_id: String, btn: Button, lbl: Label) -> void:
	var data = GameManager.skills[skill_id]
	btn.text = skill_id.capitalize()

	lbl.text = "(%d/%d)" % [data["level"], GameManager.MAX_LEVEL]
	if data["level"] >= GameManager.MAX_LEVEL:
		lbl.tooltip_text = "Mastered!"
	else:
		var needed = GameManager.get_xp_needed(data["level"])
		lbl.tooltip_text = "%.0f / %.0f XP to next level" % [data["xp"], needed]

func _on_nav_pressed(target: String) -> void:
	AudioManager.play_sfx(Ids.SFX_UI_CLICK)
	get_tree().call_group(Ids.GROUP_VIEW_MANAGER, "switch_view", target)
