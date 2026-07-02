# ShopView.gd
extends PanelContainer

# Shop Upgrade Button Handle
@onready var upgrade_shovel_button: Button = %UpgradeShovelButton

func _ready() -> void:
	add_to_group("ui_updates")
	
	# Keep the connection, but the function below won't do anything yet
	upgrade_shovel_button.pressed.connect(_on_upgrade_shovel_pressed)
	
	update_ui()

func _on_upgrade_shovel_pressed() -> void:
	# Gutted: This is empty for now so the game doesn't crash.
	# Once you are ready to implement the new "Buy Tool" logic, 
	# we will fill this with an InventoryManager.add_item() call.
	print("Shop upgrade logic is currently disabled.")

# This function is triggered automatically via our "ui_updates" group broadcast
func update_ui() -> void:
	if upgrade_shovel_button != null:
		# Gutted: The button is disabled and text is set to placeholder status
		upgrade_shovel_button.text = "Shop Upgrades Temporarily Disabled"
		upgrade_shovel_button.disabled = true