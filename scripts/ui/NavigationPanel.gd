extends PanelContainer

# UI Handles for your Buttons
@onready var inv_btn: Button = %InventoryNavButton
@onready var shop_btn: Button = %ShopNavButton
@onready var ritual_btn: Button = %RitualNavButton
@onready var grave_btn: Button = %Graverobbing
@onready var necro_btn: Button = %Necromancy
@onready var lumber_btn: Button = %Lumbering
@onready var spelunk_btn: Button = %Spelunking

# UI Handles for your Level Indicators
@onready var grave_xp: Label = %GraverobbingXPLabel
@onready var necro_xp: Label = %NecromancyXPLabel
@onready var lumber_xp: Label = %LumberingXPLabel
@onready var spelunk_xp: Label = %SpelunkingXPLabel

func _ready() -> void:
	add_to_group("ui_updates")
	
	shop_btn.pressed.connect(_on_nav_pressed.bind("shop"))
	inv_btn.pressed.connect(_on_nav_pressed.bind("inventory"))
	ritual_btn.pressed.connect(_on_nav_pressed.bind("ritual_altar"))
	
	# Wire buttons to the switch_view group
	grave_btn.pressed.connect(_on_nav_pressed.bind("graveyard"))
	necro_btn.pressed.connect(_on_nav_pressed.bind("undercroft"))
	lumber_btn.pressed.connect(_on_nav_pressed.bind("forest"))
	spelunk_btn.pressed.connect(_on_nav_pressed.bind("quarry"))
	
	update_ui()

func update_ui() -> void:
	_update_row("graverobbing", grave_btn, grave_xp)
	_update_row("necromancy", necro_btn, necro_xp)
	_update_row("lumbering", lumber_btn, lumber_xp)
	_update_row("spelunking", spelunk_btn, spelunk_xp)

func _update_row(skill_id: String, btn: Button, lbl: Label) -> void:
	var data = GameManager.skills[skill_id]
	btn.text = skill_id.capitalize()
	lbl.text = "(%d/100)" % data["level"]

func _on_nav_pressed(target: String) -> void:
	# Sends the command to Control.gd
	get_tree().call_group("view_manager", "switch_view", target)
