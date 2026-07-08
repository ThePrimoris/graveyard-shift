# SmokeTest.gd
# Headless functional test for the fresh-slate build:
#   godot --headless --path . res://tests/SmokeTest.tscn
# Exercises registries, the three nodes, tools, shop, inventory, saves, and UI.
extends Node

const SAVE_BACKUP_PATH: String = "user://graveyard_shift_save.pretest.bak"
const NOTIFICATION_SCENE = preload("res://scenes/ItemNotification.tscn")

var failures: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		failures += 1
		print("FAIL: " + label)

func _ready() -> void:
	# Preserve the player's real save: back it up, restore at the end.
	if FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.copy_absolute(SaveManager.SAVE_PATH, SAVE_BACKUP_PATH)
		DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Registries ---
	check(GameManager.item_db.size() >= 17, "item database holds the core items (%d)" % GameManager.item_db.size())
	for core_id in ["flesh", "rotten_logs", "stone_debris", "bones", "blood"]:
		check(GameManager.find_item_by_id(core_id) != null, "core item exists: %s" % core_id)
	check(GameManager.node_db.size() >= 3, "node registry holds the core nodes (%d)" % GameManager.node_db.size())
	check(GameManager.skills.size() == 3 and not GameManager.skills.has("forging"), "exactly 3 skills remain")
	var missing_icons: Array = []
	for item_id in GameManager.item_db:
		if GameManager.item_db[item_id].icon == null:
			missing_icons.append(item_id)
	check(missing_icons.is_empty(), "every item has an icon" + ("" if missing_icons.is_empty() else " (missing: %s)" % str(missing_icons)))

	# --- The three nodes drop exactly one resource each ---
	var expectations = {
		"fresh_grave": ["graverobbing", "flesh"],
		"dead_trees": ["lumbering", "rotten_logs"],
		"crumbling_walls": ["spelunking", "stone_debris"],
	}
	for node_id in expectations:
		var node = GameManager.find_node_by_id(node_id)
		var skill = expectations[node_id][0]
		var drop = expectations[node_id][1]
		check(node != null and GameManager.get_skill_key(node) == skill, "%s belongs to %s" % [node_id, skill])
		var xp_before = GameManager.skills[skill]["xp"]
		var guaranteed_every_time = true
		for i in range(5):
			if not GameManager.resolve_harvest(node, false).has(drop):
				guaranteed_every_time = false
		check(guaranteed_every_time, "%s always drops %s" % [node_id, drop])
		check(InventoryManager.get_item_count(drop) >= 5, "%s banked in inventory" % drop)
		check(GameManager.skills[skill]["xp"] > xp_before or GameManager.skills[skill]["level"] > 1, "%s grants %s XP" % [node_id, skill])

	# The player-authored Fresh Graves pool: flesh 100%, bones 45%, blood 20%
	var fg = GameManager.find_node_by_id("fresh_grave")
	check(fg.loot_pool.size() == 3, "fresh graves pool holds 3 entries")

	# --- Loot pool: each entry rolls independently against its own chance ---
	var pool_node: HarvestNode = GameManager.find_node_by_id("fresh_grave").duplicate()
	pool_node.id = "test_pool"
	var d1 = LootDrop.new()
	d1.item = GameManager.find_item_by_id("flesh")
	d1.chance = 1.0
	var d2 = LootDrop.new()
	d2.item = GameManager.find_item_by_id("rotten_logs")
	d2.chance = 0.5
	var d3 = LootDrop.new()
	d3.item = GameManager.find_item_by_id("stone_debris")
	d3.chance = 0.0
	var pool: Array[LootDrop] = [d1, d2, d3]
	pool_node.loot_pool = pool
	var always = 0
	var sometimes = 0
	var never = 0
	for i in range(60):
		var g = GameManager.resolve_harvest(pool_node, false)
		if g.has("flesh"): always += 1
		if g.has("rotten_logs"): sometimes += 1
		if g.has("stone_debris"): never += 1
	check(always == 60, "100% entries drop every harvest")
	check(sometimes > 0 and sometimes < 60, "mid-chance entries drop sometimes (%d/60)" % sometimes)
	check(never == 0, "0% entries never drop")

	# Only the first 5 pool entries are honoured
	var six: Array[LootDrop] = []
	for i in range(6):
		var e = LootDrop.new()
		e.item = GameManager.find_item_by_id("flesh")
		e.chance = 1.0
		six.append(e)
	six[5].item = GameManager.find_item_by_id("rotten_logs")
	pool_node.loot_pool = six
	var g6 = GameManager.resolve_harvest(pool_node, false)
	check(g6.get("flesh", 0) >= 5 and not g6.has("rotten_logs"), "loot pool caps at 5 entries")

	# --- XP curve and cap ---
	check(int(GameManager.get_xp_needed(1)) == 83, "RS curve: level 1->2 costs 83 XP")
	GameManager.skills["lumbering"]["level"] = 99
	GameManager.add_xp("lumbering", 99999999.0)
	check(GameManager.skills["lumbering"]["level"] == 100, "levels cap at 100")
	GameManager.skills["lumbering"] = {"level": 1, "xp": 0.0}

	# --- Equipment: all three tools equipped at start ---
	for t in [ToolData.ToolType.SHOVEL, ToolData.ToolType.HATCHET, ToolData.ToolType.PICKAXE]:
		check(GameManager.get_equipped_tool(t) != null, "%s slot filled at start" % ToolData.ToolType.keys()[t].to_lower())
	var grave = GameManager.find_node_by_id("fresh_grave")
	var base_dur = GameManager.get_effective_duration(grave)
	check(base_dur > 0.0 and base_dur <= 3.0, "effective duration applies skill mod (%.2fs)" % base_dur)

	# --- Notifications free themselves and never block input ---
	var notif = NOTIFICATION_SCENE.instantiate()
	add_child(notif)
	notif.setup("Test", 1)
	check(notif.mouse_filter == Control.MOUSE_FILTER_IGNORE, "notification ignores mouse input")
	await get_tree().create_timer(3.5).timeout
	check(not is_instance_valid(notif), "notification frees itself after animating")

	# --- Debug console commands ---
	var xp_before_cmd = GameManager.skills["graverobbing"]["xp"]
	var lvl_before_cmd = GameManager.skills["graverobbing"]["level"]
	var resp = DebugConsole.execute("level graverobbing 500")
	check("level" in resp and (GameManager.skills["graverobbing"]["xp"] > xp_before_cmd or GameManager.skills["graverobbing"]["level"] > lvl_before_cmd), "console 'level' adds XP")
	var flesh_before_cmd = InventoryManager.get_item_count("flesh")
	DebugConsole.execute("spawn flesh 5")
	check(InventoryManager.get_item_count("flesh") == flesh_before_cmd + 5, "console 'spawn' adds items")
	check("Unknown skill" in DebugConsole.execute("level bogus 10"), "console rejects unknown skills")
	check("Unknown item" in DebugConsole.execute("spawn nonsense 1"), "console rejects unknown items")
	check("Commands" in DebugConsole.execute("help"), "console help lists commands")
	DebugConsole.toggle()
	check(DebugConsole.visible, "console opens")
	DebugConsole.toggle()
	check(not DebugConsole.visible and DebugConsole.log_lines.size() > 0, "console closes keeping the log")

	# --- Old-format saves are rejected ---
	var old_save = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	old_save.store_string(JSON.stringify({"version": 1, "gold": 9999}))
	old_save.close()
	GameManager.gold_coins = 42
	SaveManager.load_game()
	check(GameManager.gold_coins == 42, "pre-reboot saves are ignored")

	# --- UI integration: run the real Main scene ---
	var main = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# Sidebar: 3 skills, no forging/necromancy rows, no ritual button
	check(main.find_child("Forging", true, false) == null and main.find_child("Necromancy", true, false) == null, "retired skills gone from the sidebar")
	check(main.find_child("RitualNavButton", true, false) == null, "ritual altar button gone")
	check(main.find_child("SettingsNavButton", true, false) != null, "settings button present")

	# The new plots bar: circle center, plots 1-2 left and 3-4 right
	var plots_bar = main.find_child("PlotsBar", true, false)
	check(plots_bar != null and plots_bar.plot_buttons.size() == 4, "plots bar holds 4 plots")
	if plots_bar and plots_bar.plot_buttons.size() == 4:
		var labels: Array[String] = []
		for btn in plots_bar.plot_buttons:
			labels.append(btn.text)
		check(labels == ["1", "2", "3", "4"], "plots numbered 1-4 left to right (%s)" % str(labels))
		var bar_row = plots_bar.get_node("BarRow")
		check(bar_row.get_child(2) == plots_bar.circle_button, "circle button sits center with two plots per side")

	# Harvest feels per skill survive the reboot
	var gv = main.find_child("GraveyardView", true, false)
	check(gv != null and gv.cards.size() == gv.display_nodes.size() and gv.cards.size() >= 1, "graveyard builds a card per zone node (%d)" % gv.cards.size())
	var grave_ids: Array = []
	for n in gv.display_nodes: grave_ids.append(n.id)
	check(grave_ids.has("fresh_grave"), "Fresh Graves is in the starting zone")
	check(gv.cards[0].bars.size() == 1 and gv.cards[0].bars[0].value == 0.0, "digging bar starts empty and fills")
	var expected_rows = 0
	for entry in gv.display_nodes[0].loot_pool.slice(0, HarvestNode.MAX_LOOT_ENTRIES):
		if entry != null and entry.item != null and entry.chance > 0.0: expected_rows += 1
	check(gv.cards[0].drops_box.get_child_count() == expected_rows, "card lists every pool drop (%d)" % expected_rows)

	check(gv.header_title != null and gv.header_title.text.begins_with("Graverobbing"), "page header shows the skill")
	var fv = main.find_child("ForestView", true, false)
	check(fv.cards.size() >= 1 and fv.cards[0].bars.size() >= 2, "dead trees use chop segment bars")
	var qv = main.find_child("QuarryView", true, false)
	check(qv.cards.size() >= 1 and qv.cards[0].bars[0].value == 1.0, "crumbling walls bar starts full and depletes")
	# Zone selector: one starter zone per skill, left of the node grid
	check(gv.zones.size() == 2 and gv.zones[0].name == "Humboldt Graves", "graverobbing opens in Humboldt Graves")
	check(gv.zones[1].name == "Bedlam Asylum" and gv.zone_buttons.size() == 2, "Bedlam Asylum is the second graverobbing zone")
	check(gv.zone_buttons[1].disabled, "Bedlam Asylum locks until graverobbing level 10")
	check(fv.zones.size() == 1 and fv.zones[0].name == "Shrouded Woods", "lumbering zone is Shrouded Woods")
	check(qv.zones.size() == 1 and qv.zones[0].name == "Mineshaft", "spelunking zone is Mineshaft")
	check(gv.zone_buttons[0].text == "Humboldt Graves" and gv.zone_buttons[0].button_pressed, "zone selector shows the active zone")
	var grid = main.find_child("GraveClickers", true, false)
	check(grid.custom_minimum_size.x == 814, "node grid wraps at three cards per row")

	# Graverobbing dig-layer segment bars, per the node's dig_sections
	check(GameManager.find_node_by_id("fresh_grave").dig_sections == 2, "Fresh Graves digs in 2 sections")
	check(GameManager.find_node_by_id("forgotten_graves").dig_sections == 4, "Forgotten Graves digs in 4 sections")
	check(gv.cards[0].segments.size() == 2 and gv.cards[0].segment_box.visible, "graverobbing card shows a 2-section dig meter")
	check(gv.cards[0].segment_box is VBoxContainer, "dig meter is vertical")
	# A full sweep of the horizontal bar removes one section (top first).
	gv.cards[0].update_progress(0.75, 3.0)  # 25% -> mid first section, none removed yet
	check(gv.cards[0].segments[0].modulate.a > 0.5 and gv.cards[0].bars[0].value > 0.0, "horizontal bar fills within the current section")
	gv.cards[0].update_progress(1.5, 3.0)   # first 1.5s done -> one section gone
	check(gv.cards[0].segments[0].modulate.a < 0.5 and gv.cards[0].segments[1].modulate.a > 0.5, "a full sweep removes the top section")
	gv.cards[0].reset_progress()
	check(gv.cards[0].segments[0].modulate.a > 0.5, "reset restores all sections")
	# Lumbering/Spelunking cards have no dig sections
	check(fv.cards[0].segments.is_empty() and qv.cards[0].segments.is_empty(), "only graverobbing has dig-layer sections")

	# Humboldt Graves: 5 nodes ending in the boss crypt
	check(gv.display_nodes.size() == 5, "Humboldt Graves holds 5 nodes (%d)" % gv.display_nodes.size())
	var crypt = GameManager.find_node_by_id("old_crypt")
	check(crypt != null and crypt.is_boss, "The Old Crypt is a boss node")
	check(crypt.loot_pool.is_empty(), "boss node has no harvest loot")
	# Boss card: level it up so the crypt is accessible, then confirm boss framing
	GameManager.skills["graverobbing"]["level"] = 20
	gv.update_ui()
	var crypt_card = gv.cards[4]
	check(crypt_card.action_button.text == "Confront" and not crypt_card.progress_stack.visible, "unlocked boss card shows Confront, no progress bar")
	check(crypt_card.custom_minimum_size.x >= 520, "boss crypt card spans two node slots (%.0fpx)" % crypt_card.custom_minimum_size.x)
	crypt_card.action_triggered.emit()  # placeholder confront should not crash / not harvest
	check(GameManager.active_action_source != crypt_card, "confronting the boss doesn't start a harvest")
	# The gateway book exists for the eventual necromancy unlock
	var tome = GameManager.find_item_by_id("nincompoops_tome")
	check(tome != null and not tome.is_sellable, "Necromancy for Nincompoops exists as an unsellable key item")
	GameManager.skills["graverobbing"] = {"level": 1, "xp": 0.0}

	# Shop: upgrade rows + backpack slots on the new materials
	var shop = main.find_child("ShopView", true, false)
	check(shop != null and shop.upgrade_rows.size() == 3, "shop shows one upgrade row per tool type")
	GameManager.gold_coins += 200
	InventoryManager.add_item(GameManager.find_item_by_id("rotten_logs"), 20)
	InventoryManager.add_item(GameManager.find_item_by_id("stone_debris"), 10)
	check(shop.try_upgrade(ToolData.ToolType.HATCHET), "hatchet upgrade succeeds with new materials")
	var hatchet = GameManager.get_current_tool_of_type(ToolData.ToolType.HATCHET)
	check(hatchet != null and hatchet.tool_tier == ToolData.ToolTier.GALVANIZED, "upgrade equips the next tier")
	check(not GameManager.owns_tool("rusty_hatchet"), "old tool is melted down")

	var slots_before = InventoryManager.slots.size()
	var cost1 = InventoryManager.get_next_slot_cost()
	GameManager.gold_coins += cost1 * 3
	check(InventoryManager.purchase_slot(), "backpack slot purchase succeeds")
	check(InventoryManager.slots.size() == slots_before + 1, "purchased slot expands the backpack")
	check(InventoryManager.get_next_slot_cost() > cost1, "slot cost scales up")

	# Selling pays gold
	var inv_view = main.find_child("InventoryView", true, false)
	InventoryManager.add_item(GameManager.find_item_by_id("flesh"), 5)
	inv_view._on_item_selected(GameManager.find_item_by_id("flesh"))
	var gold_before = GameManager.gold_coins
	inv_view._on_sell_all_pressed()
	check(GameManager.gold_coins > gold_before, "Sell All pays gold")

	# Save / load round trip + node resume
	GameManager.active_node_data = grave
	var gold_saved = GameManager.gold_coins
	var grob_level = GameManager.skills["graverobbing"]["level"]
	SaveManager.save_game()
	GameManager.gold_coins = 0
	GameManager.active_action_source = null
	GameManager.active_node_data = null
	InventoryManager.purchased_slots = 0
	SaveManager.load_game()
	check(GameManager.gold_coins == gold_saved, "gold restored from save")
	check(GameManager.skills["graverobbing"]["level"] == grob_level, "skills restored from save")
	check(InventoryManager.purchased_slots == 1, "purchased slots restored from save")
	check(GameManager.get_equipped_tool(ToolData.ToolType.HATCHET) == hatchet, "equipped tools restored from save")
	check(GameManager.active_node_data == grave, "active node resumes automatically after load")

	# --- Tutorial: Mortimer walks the three grounds ---
	# No save existed at boot, so the tutorial should have started on its own.
	check(TutorialManager.active, "tutorial starts on a fresh run")
	# Rewind to a clean run-through (earlier tests may have poked at state)
	TutorialManager.begin()
	check(TutorialManager.current_step().get("id", "") == "intro", "tutorial opens with Mortimer's introduction")
	check(TutorialManager.bubble.visible or TutorialManager.visible, "speech bubble is on screen")
	TutorialManager._on_continue_pressed()
	check(TutorialManager.current_step().get("id", "") == "dig", "continue advances to the digging step")
	var target = TutorialManager._resolve_highlight_target()
	check(target != null and target == gv.cards[0], "Fresh Graves card is the highlight target")
	for i in range(TutorialManager.current_step().get("count", 1)):
		GameManager.resolve_harvest(grave, false)
	check(TutorialManager.current_step().get("id", "") == "to_forest", "digging enough flesh advances the tutorial")
	check(TutorialManager._resolve_highlight_target() != null, "sidebar Lumbering button is highlighted")
	get_tree().call_group("view_manager", "switch_view", "forest")
	check(TutorialManager.current_step().get("id", "") == "chop", "opening Lumbering advances the tutorial")
	for i in range(TutorialManager.current_step().get("count", 1)):
		GameManager.resolve_harvest(GameManager.find_node_by_id("dead_trees"), false)
	check(TutorialManager.current_step().get("id", "") == "to_quarry", "felling trees advances the tutorial")
	get_tree().call_group("view_manager", "switch_view", "quarry")
	check(TutorialManager.current_step().get("id", "") == "mine", "opening Spelunking advances the tutorial")
	for i in range(TutorialManager.current_step().get("count", 1)):
		GameManager.resolve_harvest(GameManager.find_node_by_id("crumbling_walls"), false)
	check(TutorialManager.current_step().get("id", "") == "outro", "mining stone advances to the farewell")
	TutorialManager._on_continue_pressed()
	check(TutorialManager.tutorial_complete and not TutorialManager.active, "tutorial completes and dismisses")

	# Completion persists; it does not restart on the next load
	SaveManager.save_game()
	TutorialManager.tutorial_complete = false
	SaveManager.load_game()
	TutorialManager.maybe_start()
	check(TutorialManager.tutorial_complete and not TutorialManager.active, "tutorial completion persists across save/load")

	main.queue_free()

	# --- Hard reset (last: wipes everything) ---
	SaveManager.hard_reset()
	check(GameManager.gold_coins == 0, "hard reset zeroes gold")
	check(GameManager.skills["graverobbing"]["level"] == 1, "hard reset resets skills")
	check(InventoryManager.slots.size() == InventoryManager.BASE_SLOTS, "hard reset restores base inventory size")
	check(GameManager.get_equipped_tool(ToolData.ToolType.SHOVEL) != null, "hard reset re-equips starting tools")
	check(TutorialManager.active and not TutorialManager.tutorial_complete, "hard reset restarts the tutorial")
	TutorialManager.finish(true)

	# Remove the test save, restore the player's original
	DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	if FileAccess.file_exists(SAVE_BACKUP_PATH):
		DirAccess.copy_absolute(SAVE_BACKUP_PATH, SaveManager.SAVE_PATH)
		DirAccess.remove_absolute(SAVE_BACKUP_PATH)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % failures)
	get_tree().quit(failures)
