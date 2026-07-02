# MinionCard.gd
extends PanelContainer

# Signal to tell UndercroftView which card button was pressed
signal buy_triggered

@onready var title_label: Label = %TitleLabel
@onready var desc_label: Label = %DescLabel
@onready var cost_label: Label = %CostLabel
@onready var action_button: Button = %ActionButton

func _ready() -> void:
	action_button.pressed.connect(_on_button_pressed)

# Configures the static text fields on startup
func setup_card(title_text: String, desc_text: String) -> void:
	title_label.text = title_text
	desc_label.text = desc_text

# Dynamically updates the costs, count, visibility, and disabled state
func update_card_state(unlocked: bool, current_count: int, action_verb: String, cost_text: String, can_afford: bool) -> void:
	visible = unlocked
	
	if action_button:
		action_button.text = "%s (%d)" % [action_verb, current_count]
		action_button.disabled = not can_afford
		
	if cost_label:
		cost_label.text = cost_text

func _on_button_pressed() -> void:
	buy_triggered.emit()
