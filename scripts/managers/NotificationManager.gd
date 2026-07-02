extends Node

var notification_scene = preload("res://scenes/ItemNotification.tscn")

func show_item(item_name: String, amount: int):
	var instance = notification_scene.instantiate()
	get_tree().root.add_child(instance)
	instance.setup(item_name, amount)
