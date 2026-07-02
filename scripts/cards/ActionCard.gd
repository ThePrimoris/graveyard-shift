# ActionCard.gd
extends PanelContainer

signal action_triggered

@onready var title_label: Label = %TitleLabel
@onready var desc_label: Label = %DescLabel       
@onready var progress_bar: ProgressBar = %ActionProgress
@onready var action_button: Button = %ActionButton

var action_verb: String = "Start"

func _ready() -> void:
	action_button.pressed.connect(_on_button_pressed)

func setup_card(title_text: String, desc_text: String, verb: String, max_duration: float) -> void:
	title_label.text = title_text
	desc_label.text = desc_text       
	action_verb = verb
	action_button.text = action_verb
	progress_bar.max_value = max_duration
	progress_bar.value = 0.0

func update_progress(current_value: float) -> void:
	if progress_bar:
		progress_bar.value = current_value

func set_button_text(is_active: bool) -> void:
	if action_button:
		action_button.text = "Stop" if is_active else "Start " + action_verb

func set_card_visibility(is_unlocked: bool) -> void:
	visible = is_unlocked

func _on_button_pressed() -> void:
	action_triggered.emit()
