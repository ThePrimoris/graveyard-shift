extends Control

@onready var drawer_toggle_button: Button = %DrawerToggleButton
@onready var drawer_slots_container: VBoxContainer = %DrawerSlotsContainer

@export var slide_duration: float = 0.3
@export var slide_distance: float = 68.0
@export var transition_type: Tween.TransitionType = Tween.TRANS_CUBIC
@export var ease_type: Tween.EaseType = Tween.EASE_OUT

# State variables
var is_open: bool = false
var closed_position_x: float = 0.0
var open_position_x: float = 0.0
var tween: Tween

func _ready() -> void:
	await get_tree().process_frame
	setup_positions()

func setup_positions() -> void:
	closed_position_x = position.x
	
	open_position_x = closed_position_x - slide_distance

	is_open = false

func toggle_drawer() -> void:
	is_open = !is_open
	
	var target_x: float = open_position_x if is_open else closed_position_x
	
	drawer_toggle_button.text = ">" if is_open else "<"
	
	if tween and tween.is_running():
		tween.kill()
		
	tween = create_tween().set_trans(transition_type).set_ease(ease_type)
	tween.tween_property(self, "position:x", target_x, slide_duration)

func _on_toggle_button_pressed() -> void:
	toggle_drawer()
