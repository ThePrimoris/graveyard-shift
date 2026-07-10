extends PanelContainer

@onready var inv_btn: Button = %InventoryNavButton
@onready var shop_btn: Button = %ShopNavButton
@onready var undercroft_btn: Button = %UndercroftNavButton
@onready var grave_btn: Button = %Graverobbing
@onready var lumber_btn: Button = %Lumbering
@onready var spelunk_btn: Button = %Spelunking

@onready var grave_xp: Label = %GraverobbingXPLabel
@onready var lumber_xp: Label = %LumberingXPLabel
@onready var spelunk_xp: Label = %SpelunkingXPLabel

@onready var gold_lbl: Label = %GoldValueLabel

func _ready() -> void:
	add_to_group("ui_updates")

	shop_btn.pressed.connect(_on_nav_pressed.bind("shop"))
	inv_btn.pressed.connect(_on_nav_pressed.bind("inventory"))
	undercroft_btn.pressed.connect(_on_nav_pressed.bind("undercroft"))
	grave_btn.pressed.connect(_on_nav_pressed.bind("graveyard"))
	lumber_btn.pressed.connect(_on_nav_pressed.bind("forest"))
	spelunk_btn.pressed.connect(_on_nav_pressed.bind("quarry"))

	update_ui()

func update_ui() -> void:
	_update_row("graverobbing", grave_btn, grave_xp)
	_update_row("lumbering", lumber_btn, lumber_xp)
	_update_row("spelunking", spelunk_btn, spelunk_xp)

	# Once the Necronomicon is found, the book replaces the Undercroft.
	if undercroft_btn:
		undercroft_btn.visible = not MinionManager.necronomicon_unlocked

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
	get_tree().call_group("view_manager", "switch_view", target)
