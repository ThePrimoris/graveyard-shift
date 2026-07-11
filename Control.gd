extends Control

const SETTINGS_PANEL_SCRIPT = preload("res://scripts/ui/SettingsPanel.gd")
const GROUNDS_VIEW_SCRIPT = preload("res://scenes/views/GroundsView.gd")

@onready var timer: Timer = %GameTickTimer

# Full Screen View Containers
@onready var graveyard_view: PanelContainer = %GraveyardView
@onready var forest_view: PanelContainer = %ForestView
@onready var quarry_view: PanelContainer = %QuarryView
@onready var inventory_view: PanelContainer = %InventoryView
@onready var shop_view: PanelContainer = %ShopView
@onready var combat_view: PanelContainer = %CombatView

var open_settings_panel: Node = null
var open_grounds_panel: Node = null

func _ready() -> void:
	add_to_group("ui_updates")
	add_to_group("view_manager")

	# Layout reflows with the window (cards re-wrap, panels stretch); this
	# floor just stops the window shrinking past the point where UI would squish.
	get_window().min_size = Vector2i(1160, 660)

	if timer.timeout.is_connected(_on_game_tick):
		timer.timeout.disconnect(_on_game_tick)
	timer.timeout.connect(_on_game_tick)

	%SettingsNavButton.pressed.connect(_on_settings_pressed)

	# The Grounds nav button lives beside Shop/Inventory; guard the hookup so a
	# missing button degrades gracefully instead of crashing the scene.
	var grounds_btn = get_node_or_null("%GroundsNavButton")
	if grounds_btn:
		grounds_btn.pressed.connect(_on_grounds_pressed)

	switch_view("graveyard")
	update_ui()

func _on_settings_pressed() -> void:
	if is_instance_valid(open_settings_panel):
		open_settings_panel.queue_free()
		open_settings_panel = null
		return
	open_settings_panel = SETTINGS_PANEL_SCRIPT.new()
	add_child(open_settings_panel)

func _on_grounds_pressed() -> void:
	if is_instance_valid(open_grounds_panel):
		open_grounds_panel.queue_free()
		open_grounds_panel = null
		return
	open_grounds_panel = GROUNDS_VIEW_SCRIPT.new()
	add_child(open_grounds_panel)

func _on_game_tick() -> void:
	get_tree().call_group("ui_updates", "update_ui")

func switch_view(target_view: String) -> void:
	if graveyard_view: graveyard_view.visible = (target_view == "graveyard")
	if forest_view: forest_view.visible = (target_view == "forest")
	if quarry_view: quarry_view.visible = (target_view == "quarry")
	if inventory_view: inventory_view.visible = (target_view == "inventory")
	if shop_view: shop_view.visible = (target_view == "shop")
	if combat_view: combat_view.visible = (target_view == "combat")

	get_tree().call_group("ui_updates", "update_ui")

func update_ui() -> void:
	pass

func create_floating_text(text_content: String, start_position: Vector2, text_color: Color) -> void:
	var popup = Label.new()
	popup.text = text_content
	popup.global_position = start_position
	popup.add_theme_color_override("font_color", text_color)
	popup.add_theme_font_size_override("font_size", 18)
	add_child(popup)

	var tween = create_tween().set_parallel(true)
	tween.tween_property(popup, "global_position", start_position + Vector2(randf_range(-20, 20), -60), 0.6)
	tween.tween_property(popup, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(popup.queue_free)
