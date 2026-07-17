# GroundsShot.gd
# One-off visual QA: boots Main, opens the Grounds overlay at a few build
# states, and saves PNGs to user://shots/. Run WITH a display:
#   godot --path . res://tests/GroundsShot.tscn
extends Node

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	var main = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	TutorialManager.finish(true)
	GameManager.gold_coins = 5000
	DirAccess.make_dir_recursive_absolute("user://shots")

	var control = main if main.get_script() != null else main.find_child("Control", true, false)

	# Shot 1: fresh grounds (all build sites).
	control._on_grounds_pressed()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("user://shots/grounds_fresh.png")
	print("shot: grounds_fresh.png")
	control._on_grounds_pressed()  # toggle closed

	# Shot 2: mid/max game — raise every structure a few tiers.
	for sid in GroundsManager.sorted_ids():
		GroundsManager.levels[sid] = mini(3, GroundsManager.structure_db[sid].max_level())
	GroundsManager.grounds_updated.emit()
	control._on_grounds_pressed()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("user://shots/grounds_tier3.png")
	print("shot: grounds_tier3.png")

	print("SCREENSHOTS DONE")
	get_tree().quit(0)
