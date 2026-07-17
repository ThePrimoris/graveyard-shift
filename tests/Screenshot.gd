# Screenshot.gd
# Visual QA harness: boots the real Main scene, walks a list of views, and
# saves a PNG of each to user://shots/. Run WITH a display (not --headless):
#   godot --path . res://tests/Screenshot.tscn
# Used to eyeball theme/icon/layout changes without clicking through by hand.
extends Node

const SHOTS := [
	{"view": "graveyard", "file": "01_graveyard.png"},
	{"view": "shop", "file": "02_shop.png"},
	{"view": "inventory", "file": "03_inventory.png"},
	{"view": "alchemy_lab", "file": "04_alchemy.png"},
	{"view": "forge_hall", "file": "05_forge.png"},
	{"view": "combat", "file": "06_combat.png"},
]

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var main = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# Kill the tutorial overlay so shots show the real UI.
	TutorialManager.finish(true)
	# Seed enough state that screens aren't empty.
	GameManager.gold_coins = 1234
	InventoryManager.add_item(GameManager.find_item_by_id("flesh"), 40)
	InventoryManager.add_item(GameManager.find_item_by_id("bones"), 25)
	InventoryManager.add_item(GameManager.find_item_by_id("velvet_moss"), 12)
	InventoryManager.add_item(GameManager.find_item_by_id("obsidian_shard"), 3)
	InventoryManager.add_item(GameManager.find_item_by_id("embalmers_salve"), 2)
	InventoryManager.add_item(GameManager.find_item_by_id("nickel_blade"), 1)
	MinionManager.necronomicon_unlocked = true
	for item_id in MinionManager.find_minion_by_id("zombie").raise_cost:
		InventoryManager.add_item(GameManager.find_item_by_id(item_id),
			MinionManager.find_minion_by_id("zombie").raise_cost[item_id])
	MinionManager.raise_minion("zombie")
	MinionManager.assign_to_plot("zombie", 0)
	DirAccess.make_dir_recursive_absolute("user://shots")

	for shot in SHOTS:
		if shot["view"] == "combat":
			var cv = get_tree().get_first_node_in_group(Ids.GROUP_COMBAT_VIEWS)
			if cv:
				cv.start_test_encounter(false)
		get_tree().call_group(Ids.GROUP_VIEW_MANAGER, "switch_view", shot["view"])
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
		await get_tree().create_timer(0.6).timeout
		var img = get_viewport().get_texture().get_image()
		img.save_png("user://shots/" + shot["file"])
		print("shot: " + shot["file"])

	print("SCREENSHOTS DONE")
	get_tree().quit(0)
