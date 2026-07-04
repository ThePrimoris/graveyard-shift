extends Node

var notification_scene = preload("res://scenes/ItemNotification.tscn")

func show_item(item_name: String, amount: int, item_resource: Resource = null) -> void:
	var instance = notification_scene.instantiate()
	
	# Find our automatic vertical layout container in the active scene tree
	var container = get_tree().current_scene.find_child("NotificationContainer", true, false)
	
	if container:
		container.add_child(instance)
	else:
		# Fail-safe fallback to screen root if the container isn't found
		get_tree().root.add_child(instance)
	
	# Pass data down to display the text and icon asset cleanly
	if instance.has_method("setup_with_resource") and item_resource != null:
		instance.setup_with_resource(item_name, amount, item_resource)
	else:
		instance.setup(item_name, amount)