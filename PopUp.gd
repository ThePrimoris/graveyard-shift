# PopUp.gd
# One toast notification: an optional item icon, the message, and a "+N"
# amount for real item stacks. Lives in the top-center NotificationContainer
# stack; fades in place (no travel, so nothing ever slides off screen), holds,
# fades out, and frees itself.
extends PanelContainer

const FADE_IN := 0.18
const HOLD := 2.2
const FADE_OUT := 0.5

@onready var icon_node: TextureRect = %Icon
@onready var name_label: Label = %ItemName
@onready var amount_label: Label = %ItemAmount

func _ready() -> void:
	# Notifications must never eat clicks meant for the UI underneath them
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(item_name: String, amount: int) -> void:
	name_label.text = item_name
	amount_label.text = "+" + str(amount)
	# Text-only toasts (system messages) show no icon and no empty well.
	icon_node.visible = false
	# Announcements read odd as "+1"; only real item stacks show an amount.
	amount_label.visible = amount > 1
	_animate()

## This handles the dynamic icon assignment from your Item Resource file
func setup_with_resource(item_name: String, amount: int, item_resource: Resource) -> void:
	setup(item_name, amount)
	if item_resource and "icon" in item_resource and item_resource.icon:
		icon_node.texture = item_resource.icon
		icon_node.visible = true
		amount_label.visible = true

func _animate() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD)
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(queue_free)
