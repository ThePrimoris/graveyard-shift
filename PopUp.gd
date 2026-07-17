extends Control

@onready var icon_node = %Icon
@onready var name_label = %ItemName
@onready var amount_label = %ItemAmount
@onready var anim = $AnimationPlayer

func _ready() -> void:
	# Notifications must never eat clicks meant for the UI underneath them
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Self-destruct once the pop_up animation finishes so they never pile up
	anim.animation_finished.connect(func(_anim_name): queue_free())

func setup(item_name: String, amount: int):
	name_label.text = item_name
	amount_label.text = "+" + str(amount)
	# Text-only toasts (no item icon) hide the icon well entirely — an empty
	# square next to the message reads as a rendering bug.
	if icon_node:
		icon_node.visible = false
	# Announcements read odd as "+1"; only real item stacks show an amount.
	amount_label.visible = amount > 1
	anim.play("pop_up")

## This handles the dynamic icon assignment from your Item Resource file
func setup_with_resource(item_name: String, amount: int, item_resource: Resource) -> void:
	# 1. Run your standard text and animation setup first
	setup(item_name, amount)

	# 2. Check if the resource has an icon property and assign its texture
	if item_resource and "icon" in item_resource and item_resource.icon:
		if icon_node:
			icon_node.texture = item_resource.icon
			icon_node.visible = true
		amount_label.visible = true
