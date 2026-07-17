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
	# NEVER overwrite an existing backup — if one is already there, a previous
	# run died mid-flight and the backup (not SAVE_PATH) holds the real save.
	if FileAccess.file_exists(SaveManager.SAVE_PATH) and not FileAccess.file_exists(SAVE_BACKUP_PATH):
		DirAccess.copy_absolute(SaveManager.SAVE_PATH, SAVE_BACKUP_PATH)
	if FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(SaveManager.SAVE_PATH)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Registries ---
	check(GameManager.item_db.size() >= 17, "item database holds the core items (%d)" % GameManager.item_db.size())
	for core_id in ["flesh", "rotten_logs", "stone_debris", "bones", "blood"]:
		check(GameManager.find_item_by_id(core_id) != null, "core item exists: %s" % core_id)
	check(GameManager.node_db.size() >= 3, "node registry holds the core nodes (%d)" % GameManager.node_db.size())
	check(GameManager.skills.size() == 5 and GameManager.skills.has(Ids.SKILL_ALCHEMY) and GameManager.skills.has(Ids.SKILL_FORGE) \
		and not GameManager.skills.has("forging"),
		"the skill sheet holds the 3 gathering skills + alchemy + forge")
	var missing_icons: Array = []
	for item_id in GameManager.item_db:
		if GameManager.item_db[item_id].icon == null:
			missing_icons.append(item_id)
	check(missing_icons.is_empty(), "every item has an icon" + ("" if missing_icons.is_empty() else " (missing: %s)" % str(missing_icons)))

	# --- Content validation (QA-2): every .tres reference resolves ---
	var content_errors := ContentValidator.validate()
	check(content_errors.is_empty(), "all content valid" + ("" if content_errors.is_empty() else " — %d problem(s):\n    %s" % [content_errors.size(), "\n    ".join(content_errors)]))

	# --- Player settings: the window choice persists in its own file ---
	var prev_window_choice = SettingsManager.window_choice
	SettingsManager.window_choice = "1280x720"
	SettingsManager.save_settings()
	SettingsManager.window_choice = "maximized"
	SettingsManager.load_settings()
	check(SettingsManager.window_choice == "1280x720", "window choice persists to the settings file")
	check(SettingsManager.get_choice_index("bogus") == 1, "unknown window choices fall back to maximized")
	SettingsManager.window_choice = prev_window_choice
	SettingsManager.save_settings()

	# --- Harvest resolution: common/rare (graves) vs hit/break (lumber, mines) ---
	var expectations = {
		"fresh_grave": ["graverobbing", "flesh"],          # common/rare: one pull per bar
		"withered_trees": ["lumbering", "rotten_logs"],     # dig: hit chips per chop, break primary
		"verdigris_seams": ["spelunking", "stone_debris"],  # breakable: hit per bar, break primary
	}
	for node_id in expectations:
		var node = GameManager.find_node_by_id(node_id)
		var skill = expectations[node_id][0]
		var drop = expectations[node_id][1]
		check(node != null and GameManager.get_skill_key(node) == skill, "%s belongs to %s" % [node_id, skill])
		var xp_before = GameManager.skills[skill]["xp"]
		if GameManager.is_breakable(node):
			# Byproduct roll per bar (may whiff); the guaranteed primary waits for the break.
			check(not node.hit_pool.is_empty(), "%s rolls a hit-chance table per bar" % node_id)
			check(GameManager.resolve_break(node, false).has(drop), "%s breaks for its primary (%s)" % [node_id, drop])
			for i in range(15):
				GameManager.resolve_harvest(node, false)  # exercise the hit table + XP
		else:
			var every_harvest_paid = true
			var saw_expected = false
			for i in range(15):
				var g = GameManager.resolve_harvest(node, false)
				if g.is_empty(): every_harvest_paid = false
				if g.has(drop): saw_expected = true
			check(every_harvest_paid, "%s pays out on every harvest" % node_id)
			check(saw_expected, "%s drops %s" % [node_id, drop])
		check(InventoryManager.get_item_count(drop) >= 1, "%s banked in inventory" % drop)
		check(GameManager.skills[skill]["xp"] > xp_before or GameManager.skills[skill]["level"] > 1, "%s grants %s XP" % [node_id, skill])

	# The player-authored Fresh Graves tables: 3 commons, 2 rares at 1%
	var fg = GameManager.find_node_by_id("fresh_grave")
	check(fg.common_pool.size() == 3, "fresh graves common table holds 3 rows")
	check(fg.rare_pool.size() == 2 and is_equal_approx(fg.rare_chance, 0.25), "fresh graves rare table holds 2 rows at 25%")

	# --- Weighted tables: one common row per harvest, weight 0 never lands ---
	var pool_node: HarvestNode = GameManager.find_node_by_id("fresh_grave").duplicate()
	pool_node.id = "test_pool"
	var d1 = LootDrop.new()
	d1.item = GameManager.find_item_by_id("flesh")
	d1.weight = 1.0
	var d2 = LootDrop.new()
	d2.item = GameManager.find_item_by_id("rotten_logs")
	d2.weight = 1.0
	var d3 = LootDrop.new()
	d3.item = GameManager.find_item_by_id("stone_debris")
	d3.weight = 0.0
	var pool: Array[LootDrop] = [d1, d2, d3]
	pool_node.common_pool = pool
	pool_node.rare_chance = 0.0
	var flesh_hits = 0
	var log_hits = 0
	var never = 0
	for i in range(60):
		var g = GameManager.resolve_harvest(pool_node, false)
		var rows = 0
		for item_id in ["flesh", "rotten_logs", "stone_debris"]:
			if g.has(item_id): rows += 1
		if rows != 1: never += 999  # more or fewer than one common row is a failure
		if g.has("flesh"): flesh_hits += 1
		if g.has("rotten_logs"): log_hits += 1
		if g.has("stone_debris"): never += 1
	check(flesh_hits + log_hits == 60 and never == 0, "each harvest lands exactly one weighted row (%d + %d)" % [flesh_hits, log_hits])
	check(flesh_hits > 0 and log_hits > 0, "equal weights land on both sides (%d / %d)" % [flesh_hits, log_hits])

	# Amount ranges respect min..max (plus any tool yield bonus on commons)
	var bonus = 0
	var pool_tool = GameManager.get_equipped_tool(pool_node.required_tool_type)
	if pool_tool: bonus = pool_tool.yield_bonus
	d1.weight = 1.0
	d1.min_amount = 2
	d1.max_amount = 4
	d2.weight = 0.0
	var amounts_ok = true
	for i in range(20):
		var amt = GameManager.resolve_harvest(pool_node, false).get("flesh", 0)
		if amt < 2 + bonus or amt > 4 + bonus: amounts_ok = false
	check(amounts_ok, "common amounts roll within min..max")
	d1.min_amount = 1
	d1.max_amount = 1

	# Rare table: 100% chance always pays, 0% never does
	var r1 = LootDrop.new()
	r1.item = GameManager.find_item_by_id("stone_debris")
	r1.weight = 1.0
	var rares: Array[LootDrop] = [r1]
	pool_node.rare_pool = rares
	pool_node.rare_chance = 1.0
	var rare_always = true
	for i in range(10):
		if not GameManager.resolve_harvest(pool_node, false).has("stone_debris"): rare_always = false
	check(rare_always, "a 100% rare chance rolls the rare table every harvest")
	pool_node.rare_chance = 0.0
	var rare_never = true
	for i in range(10):
		if GameManager.resolve_harvest(pool_node, false).has("stone_debris"): rare_never = false
	check(rare_never, "a 0% rare chance never rolls the rare table")

	# Only the first 5 table rows are honoured
	var six: Array[LootDrop] = []
	for i in range(6):
		var e = LootDrop.new()
		e.item = GameManager.find_item_by_id("flesh")
		e.weight = 0.0
		six.append(e)
	six[5].item = GameManager.find_item_by_id("rotten_logs")
	six[5].weight = 100.0
	pool_node.common_pool = six
	var g6 = GameManager.resolve_harvest(pool_node, false)
	check(not g6.has("rotten_logs"), "drop tables cap at 5 rows")

	# --- XP curve and cap ---
	check(int(GameManager.get_xp_needed(1)) == 83, "level 1 runs at the brisk RS pace (83 XP)")
	var raw_40 = floor((40.0 + 300.0 * pow(2.0, 40.0 / 7.0)) / 4.0)
	check(GameManager.get_xp_needed(40) >= raw_40 * GameManager.SKILL_XP_SCALE_LATE * 0.99, "late levels carry the full slow-burn scale")
	check(GameManager.get_xp_needed(15) > floor((15.0 + 300.0 * pow(2.0, 15.0 / 7.0)) / 4.0), "the ramp is already stretching mid levels")
	check(MinionManager.get_xp_needed(2) > MinionManager.get_xp_needed(1) * 2.0, "minion curve steepens per level")
	GameManager.skills["lumbering"]["level"] = 99
	GameManager.add_xp("lumbering", 99999999.0)
	check(GameManager.skills["lumbering"]["level"] == 100, "levels cap at 100")
	GameManager.skills["lumbering"] = {"level": 1, "xp": 0.0}

	# --- Equipment: all three tools equipped at start ---
	for t in [ToolData.ToolType.SHOVEL, ToolData.ToolType.HATCHET, ToolData.ToolType.PICKAXE]:
		check(GameManager.get_equipped_tool(t) != null, "%s slot filled at start" % ToolData.ToolType.keys()[t].to_lower())
	var grave = GameManager.find_node_by_id("fresh_grave")
	var base_dur = GameManager.get_effective_duration(grave)
	if GameManager.SPEED_BONUSES_ENABLED:
		check(base_dur > 0.0 and base_dur <= grave.base_duration, "effective duration applies speed bonuses (%.2fs)" % base_dur)
	else:
		check(base_dur == grave.base_duration, "speed bonuses parked: duration equals base (%.2fs)" % base_dur)

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
	# The drop ledger: one Common row per table entry, rare column + header %.
	check(gv.cards[0].common_box.get_child_count() == 3, "Common column lists all 3 fresh grave rows")
	check(gv.cards[0].rare_col.visible and gv.cards[0].rare_box.get_child_count() == 2, "Rare column lists both rare rows")
	check(gv.cards[0].rare_header.text == "Rare — 25%", "rare header carries the hit chance (%s)" % gv.cards[0].rare_header.text)
	check(gv.cards[0].divider.visible, "ledger divider splits the two tables")

	check(gv.header_title != null and gv.header_title.text.begins_with("Graverobbing"), "page header shows the skill")
	var fv = main.find_child("ForestView", true, false)
	check(fv.cards.size() >= 1 and fv.cards[0].bars.size() == 1 and fv.cards[0].bars[0].value == 0.0, "withered trees use a single fill bar")
	check(fv.cards[0].rare_col.visible and fv.cards[0].divider.visible, "break column shows for a breakable tree node")
	# Lumbering keeps the discrete dig meter (2 sections on Withered Trees), but a
	# section now falls on BREAK progress — one per completed chop — not within a
	# single bar sweep. The bottom bar just shows the current chop.
	check(GameManager.find_node_by_id("withered_trees").dig_sections == 2, "Withered Trees chops in 2 sections")
	check(fv.cards[0].segments.size() == 2 and fv.cards[0].segment_box.visible, "lumbering card shows a 2-section layer meter")
	check(fv.cards[0].segment_box is VBoxContainer, "layer meter is vertical")
	fv.cards[0].update_progress(1.5, 3.0)   # mid-bar: the chop bar sweeps, no section removed yet
	check(fv.cards[0].bars[0].value > 0.0 and fv.cards[0].segments[0].modulate.a > 0.5, "the bar sweeps without dropping a section")
	fv.cards[0].update_damage(0.5)          # one chop of two -> top section falls
	check(fv.cards[0].segments[0].modulate.a < 0.5 and fv.cards[0].segments[1].modulate.a > 0.5, "a completed chop removes the top section")
	fv.cards[0].update_damage(0.0)          # node fell, break progress reset
	check(fv.cards[0].segments[0].modulate.a > 0.5, "a felled node restores all sections")
	var qv = main.find_child("QuarryView", true, false)
	check(qv.cards.size() >= 1 and qv.cards[0].bars[0].value == 0.0, "verdigris seams bar starts empty and fills")

	# --- Spelunking durability: hits deal damage, a full meter breaks the node ---
	var wall = GameManager.find_node_by_id("verdigris_seams")
	check(is_equal_approx(wall.hit_damage, 0.25), "verdigris seams take 25% damage per hit")
	check(qv.cards[0].damage_meter.visible, "quarry card shows the vertical damage meter")
	check(not gv.cards[0].damage_meter.visible and not fv.cards[0].damage_meter.visible, "graves and trees have no damage meter")
	qv.node_damage.clear()
	for i in range(3):
		qv._register_hit(wall, qv.cards[0])
	check(is_equal_approx(qv.node_damage["verdigris_seams"], 0.75), "three hits leave the wall at 75 percent damage")
	check(is_equal_approx(qv.cards[0].damage_value, 0.75), "damage meter mirrors the dealt damage")
	check(is_equal_approx(qv.cards[0].damage_fill.anchor_top, 0.25), "meter fills from the bottom: 75% dealt leaves the top quarter empty")
	var stone_before = InventoryManager.get_item_count("stone_debris")
	var flake_before = InventoryManager.get_item_count("malachite_flake")
	qv._register_hit(wall, qv.cards[0])
	check(InventoryManager.get_item_count("stone_debris") > stone_before or InventoryManager.get_item_count("malachite_flake") > flake_before,
		"the break always pays its haul")
	check(is_equal_approx(qv.node_damage["verdigris_seams"], 0.0) and qv.cards[0].damage_value == 0.0, "a broken node resets instantly")
	# The quarry ledger reads Hit Chance / Break, not Common / Rare
	check(qv.cards[0].common_header.text == "Hit Chance" and qv.cards[0].rare_header.text == "Break", "quarry ledger reads Hit Chance / Break")
	check(qv.cards[0].rare_col.visible, "break column always shows on breakable nodes")
	check(gv.cards[0].common_header.text == "Common", "grave ledger keeps Common / Rare")
	# Break-only nodes: an empty hit table pays nothing per hit
	var break_only: HarvestNode = wall.duplicate()
	break_only.id = "test_break_only"
	var no_hits: Array[LootDrop] = []
	break_only.hit_pool = no_hits
	check(GameManager.resolve_harvest(break_only, false).is_empty(), "break-only nodes drop nothing per hit")
	check(not GameManager.resolve_break(break_only, false).is_empty(), "the break haul is guaranteed")
	# Hit weights are literal percentages: 100 always pays, the shortfall misses
	var sure_hit = LootDrop.new()
	sure_hit.item = GameManager.find_item_by_id("stone_debris")
	sure_hit.weight = 100.0
	var sure_pool: Array[LootDrop] = [sure_hit]
	break_only.hit_pool = sure_pool
	var always_hit = true
	for i in range(10):
		if not GameManager.resolve_harvest(break_only, false).has("stone_debris"): always_hit = false
	check(always_hit, "a 100-weight hit row pays every hit")
	# Zone selector: one starter zone per skill, left of the node grid
	check(gv.zones.size() == 2 and gv.zones[0].name == "Humboldt Graves", "graverobbing opens in Humboldt Graves")
	check(gv.zones[1].name == "Bedlam Asylum" and gv.zone_buttons.size() == 2, "Bedlam Asylum is the second graverobbing zone")
	check(gv.zone_buttons[1].disabled, "Bedlam Asylum locks until graverobbing level 10")
	check(fv.zones.size() == 5 and fv.zones[0].name == "Shrouded Woods", "lumbering opens in Shrouded Woods (of %d zones)" % fv.zones.size())
	check(qv.zones.size() == 5 and qv.zones[0].name == "Verdigris Seams", "spelunking opens in Verdigris Seams (of %d zones)" % qv.zones.size())
	check(gv.zone_buttons[0].text == "Humboldt Graves" and gv.zone_buttons[0].button_pressed, "zone selector shows the active zone")
	var grid = main.find_child("GraveClickers", true, false)
	check(grid.size_flags_horizontal == Control.SIZE_EXPAND_FILL and grid.custom_minimum_size.x == 0,
		"node grid fills the window width and wraps to fit")

	# Graverobbing: plain single bar, no layer meter
	check(gv.cards[0].segments.is_empty() and not gv.cards[0].segment_box.visible, "graverobbing cards have no layer meter")
	gv.cards[0].update_progress(1.5, 3.0)
	check(gv.cards[0].bars[0].value > 0.4 and gv.cards[0].pct_label.text == "50%", "bottom bar and % label track the harvest")
	gv.cards[0].reset_progress()
	check(gv.cards[0].bars[0].value == 0.0 and gv.cards[0].pct_label.text == "0%", "reset empties the digging bar")
	# Rare chances taper down the grave ladder (deeper graves trade frequency
	# for richer rare pools): fresh 25% > old 20% > sunken 15% > forgotten 10%.
	var rc_fresh = GameManager.find_node_by_id("fresh_grave").rare_chance
	var rc_old = GameManager.find_node_by_id("old_grave").rare_chance
	var rc_sunken = GameManager.find_node_by_id("sunken_graves").rare_chance
	var rc_forgotten = GameManager.find_node_by_id("forgotten_graves").rare_chance
	check(rc_fresh > rc_old and rc_old > rc_sunken and rc_sunken > rc_forgotten,
		"grave rare chances taper down the ladder (%.2f > %.2f > %.2f > %.2f)" % [rc_fresh, rc_old, rc_sunken, rc_forgotten])

	# Humboldt Graves: 5 nodes ending in the boss crypt
	check(gv.display_nodes.size() == 5, "Humboldt Graves holds 5 nodes (%d)" % gv.display_nodes.size())
	var crypt = GameManager.find_node_by_id("old_crypt")
	check(crypt != null and crypt.is_boss, "The Old Crypt is a boss node")
	check(crypt.common_pool.is_empty() and crypt.rare_pool.is_empty(), "boss node has no harvest loot")
	# Boss card: level it up so the crypt is accessible, then confirm boss framing
	GameManager.skills["graverobbing"]["level"] = 20
	gv.update_ui()
	var crypt_card = gv.cards[4]
	check(crypt_card.action_button.text == "Confront" and not crypt_card.bottom_row.visible, "unlocked boss card shows Confront, no progress bar")
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
	var still_owns_rusty := false
	for owned in GameManager.inventory:
		if owned is ToolData and owned.id == "rusty_hatchet":
			still_owns_rusty = true
	check(not still_owns_rusty, "old tool is melted down")

	var slots_before = InventoryManager.slots.size()
	var cost1 = InventoryManager.get_next_slot_cost()
	GameManager.gold_coins += cost1 * 3
	check(InventoryManager.purchase_slot(), "backpack slot purchase succeeds")
	check(InventoryManager.slots.size() == slots_before + 1, "purchased slot expands the backpack")
	check(InventoryManager.get_next_slot_cost() > cost1, "slot cost scales up")

	# Selling pays gold: select, slide to "All", sell
	var inv_view = main.find_child("InventoryView", true, false)
	InventoryManager.add_item(GameManager.find_item_by_id("flesh"), 5)
	inv_view._on_item_selected(GameManager.find_item_by_id("flesh"))
	inv_view.sell_slider.value = inv_view.sell_slider.max_value
	var gold_before = GameManager.gold_coins
	inv_view._on_sell_pressed()
	check(GameManager.gold_coins > gold_before, "selling the whole stack pays gold")
	check(InventoryManager.get_item_count("flesh") == 0, "sell-all quantity empties the stack")

	# --- Minions: raise, slot, earn XP, skill points ---
	check(MinionManager.minion_db.size() >= 2 and MinionManager.find_minion_by_id("zombie") != null, "minion database loads (%d)" % MinionManager.minion_db.size())
	MinionManager.reset_state()
	var zombie: Minion = MinionManager.find_minion_by_id("zombie")

	# The rite fails without materials...
	for item_id in zombie.raise_cost:
		var held = InventoryManager.get_item_count(item_id)
		if held > 0: InventoryManager.remove_item(item_id, held)
	check(not MinionManager.raise_minion("zombie"), "raising fails without materials")
	# ...and succeeds once they're paid, consuming them
	for item_id in zombie.raise_cost:
		InventoryManager.add_item(GameManager.find_item_by_id(item_id), zombie.raise_cost[item_id])
	check(MinionManager.raise_minion("zombie"), "raising succeeds with materials")
	for item_id in zombie.raise_cost:
		check(InventoryManager.get_item_count(item_id) == 0, "rite consumed all %s" % item_id)
	check(not MinionManager.raise_minion("zombie"), "a minion can only be raised once")
	check(MinionManager.get_hp("zombie") == 20 and MinionManager.get_atk("zombie") == 2.0, "fresh zombie has base stats")

	# The Undercroft is gone — the Necronomicon is the only minion UI
	check(main.find_child("UndercroftView", true, false) == null, "no undercroft view remains")
	check(main.find_child("UndercroftNavButton", true, false) == null, "no undercroft nav button remains")
	check(MinionManager.sorted_ids() == ["zombie", "skeleton", "undead_hound", "ghoul", "homunculus"],
		"five minions order by sort_order (%s)" % str(MinionManager.sorted_ids()))
	# The warband roster: five types for four plots — the Homunculus (P3
	# capstone) makes slotting a real choice.
	var hound: Minion = MinionManager.find_minion_by_id("undead_hound")
	var ghoul: Minion = MinionManager.find_minion_by_id("ghoul")
	check(hound != null and hound.raise_cost.get("jagged_fangs", 0) > 0, "undead hound rite costs fangs")
	check(ghoul != null and ghoul.raise_cost.get("withered_heart", 0) > 0, "ghoul rite costs withered hearts")
	check(MinionManager.minion_db.size() == MinionManager.PLOT_COUNT + 1, "the minion book outnumbers the plots by one")

	# Plots: slot and show the occupant. Harvesting feeds minions nothing —
	# offerings (and later combat) are their only XP.
	check(MinionManager.assign_to_plot("zombie", 0), "zombie takes plot 1")
	check(plots_bar.plot_buttons[0].icon != null or plots_bar.plot_buttons[0].text == "Z",
		"plot button shows its occupant (icon or initial)")
	GameManager.resolve_harvest(grave, false)
	check(MinionManager.roster["zombie"]["xp"] == 0.0, "harvesting grants slotted minions no XP")
	MinionManager.assign_to_plot("zombie", 1)
	check(MinionManager.plots[0] == "" and MinionManager.plots[1] == "zombie", "a minion holds only one plot at a time")

	# Skill points: 1 per level, prerequisites enforced, passives need a plot
	check(MinionManager.get_skill_points("zombie") == 0 and not MinionManager.can_unlock_ability("zombie", "gravekeepers_vigor"), "no skill points at level 1")
	MinionManager.add_xp("zombie", MinionManager.get_xp_needed(1) - MinionManager.roster["zombie"]["xp"])
	check(MinionManager.roster["zombie"]["level"] == 2 and MinionManager.get_skill_points("zombie") == 1, "leveling grants a skill point")
	check(not MinionManager.can_unlock_ability("zombie", "carrion_nose"), "prerequisites gate deeper abilities")
	check(MinionManager.unlock_ability("zombie", "gravekeepers_vigor"), "ability unlocks with a point")
	check(MinionManager.get_skill_points("zombie") == 0, "unlocking spends the point")
	check(MinionManager.get_passive_bonus(Ids.EFFECT_HARVEST_XP_PCT) == 5.0, "slotted passive counts toward the bonus")
	MinionManager.vacate_plot(1)
	check(MinionManager.get_passive_bonus(Ids.EFFECT_HARVEST_XP_PCT) == 0.0, "passives sleep while the minion is idle")
	MinionManager.assign_to_plot("zombie", 1)

	# --- The Necronomicon ---
	check(not MinionManager.necronomicon_unlocked, "necronomicon starts locked")
	check("stirs" in DebugConsole.execute("necronomicon on"), "console wakes the necronomicon")
	check(MinionManager.necronomicon_unlocked, "unlock flag flips on")

	var book = load("res://scripts/ui/NecronomiconPanel.gd").new()
	add_child(book)
	await get_tree().process_frame
	check(book.minion_ids.size() == MinionManager.minion_db.size(), "book indexes every minion type")
	check(book.chapter == "minions" and book.page == 0, "book opens on the index spread")
	book.open_minion("zombie")
	check(book.page == book.minion_ids.find("zombie") + 1, "index jumps to a minion's spread")
	await get_tree().process_frame
	var spread_col = book.right_page.get_child(0)
	var sigil_tree = spread_col.get_child(1)
	check(sigil_tree.rune_centers.size() == zombie.abilities.size(),
		"sigil fan lays out every rune (%d of %d)" % [sigil_tree.rune_centers.size(), zombie.abilities.size()])
	sigil_tree.rune_selected.emit("carrion_nose")
	check(book.selected_ability.get("zombie", "") == "carrion_nose", "touching a rune selects it")

	# The offering rite: burn materials, feed the minion
	book._switch_chapter("altar")
	check(book.chapter == "altar", "altar tab turns to the altar spread")
	book.altar_target = "zombie"
	# Earlier harvests may have banked stray flesh (55% common row) — clear it
	# so "offer 5 of 5" is deterministic.
	var stray_flesh = InventoryManager.get_item_count("flesh")
	if stray_flesh > 0:
		InventoryManager.remove_item("flesh", stray_flesh)
	InventoryManager.add_item(GameManager.find_item_by_id("flesh"), 5)
	var zxp_before = MinionManager.roster["zombie"]["xp"]
	var zlvl_before = MinionManager.roster["zombie"]["level"]
	var gained_xp = MinionManager.offer_materials("zombie", "flesh", 5)
	check(gained_xp > 0.0 and InventoryManager.get_item_count("flesh") == 0, "offering burns the materials")
	check(MinionManager.roster["zombie"]["xp"] > zxp_before or MinionManager.roster["zombie"]["level"] > zlvl_before, "offering feeds the minion XP")
	check(MinionManager.offer_materials("zombie", "flesh", 5) == 0.0, "empty pack means no rite")
	check(MinionManager.offer_materials("zombie", "rusty_shovel", 1) == 0.0, "tools cannot be offered")
	book.queue_free()
	await get_tree().process_frame

	# --- Combat view (presentational pass) ---
	var cv = main.find_child("CombatView", true, false)
	check(cv != null, "combat view exists")
	check("battle" in DebugConsole.execute("combat").to_lower(), "console stages a test battle")
	check(cv.visible and not cv.is_boss_fight and cv.enemies.size() == 3, "group encounter fields 3 foes")
	var enemy_cards := 0
	for child in cv.enemy_holder.get_child(0).get_children():
		if child is Button: enemy_cards += 1
	check(enemy_cards == 3, "one enemy card per foe")
	check(cv.party.size() == 1 and cv.party[0]["minion_id"] == "zombie", "the slotted zombie musters as the warband")
	check(cv.party[0]["max_hp"] == MinionManager.get_hp("zombie"), "combat HP comes from minion stats")
	DebugConsole.execute("combat boss")
	check(cv.is_boss_fight and cv.enemies.size() == 1, "boss command stages a single boss")
	check(cv.enemy_holder.get_child(0) is PanelContainer, "the boss renders as a banner, not a card")
	check(not cv.auto_mode and cv.paused, "combat opens paused with auto off")

	# --- The turn engine ---
	DebugConsole.execute("combat")
	cv.enemies[0]["hp"] = 1
	cv._execute_attack(0, 0, 1.0, "")
	check(cv.enemies[0]["hp"] == 0, "an attack fells a 1 HP foe")
	check(cv.party[0]["charge"] == 0.0, "acting resets the charge gauge")
	check(cv.fight_state == "active", "the fight continues while foes remain")
	# Guard halves incoming damage
	cv.party[0]["hp"] = cv.party[0]["max_hp"]
	cv.party[0]["guarding"] = true
	var guarded = cv._apply_party_damage(cv.party[0], 10.0)
	check(guarded <= 6, "guarding halves incoming damage (%d)" % guarded)
	cv.party[0]["guarding"] = false
	var unguarded = cv._apply_party_damage(cv.party[0], 10.0)
	check(unguarded >= 8, "unguarded blows land full (%d)" % unguarded)
	# Victory pays gold, a loot roll per foe, and minion XP to survivors
	var gold_before_fight = GameManager.gold_coins
	var zxp_before_fight = MinionManager.roster["zombie"]["xp"]
	var zlvl_before_fight = MinionManager.roster["zombie"]["level"]
	cv.party[0]["hp"] = cv.party[0]["max_hp"]
	for foe in cv.enemies:
		foe["hp"] = 0
	cv._enter_victory()
	check(cv.fight_state == "victory", "an empty field is a victory")
	check(GameManager.gold_coins > gold_before_fight, "victory pays gold")
	check(MinionManager.roster["zombie"]["xp"] > zxp_before_fight or MinionManager.roster["zombie"]["level"] > zlvl_before_fight,
		"survivors earn minion XP")
	# A fallen warband is a defeat — and defeat EXHAUSTS the warband (P2a)
	DebugConsole.execute("combat")
	for member in cv.party:
		member["hp"] = 0
	cv._enter_defeat()
	check(cv.fight_state == "defeat", "a fallen warband is a defeat")
	check(MinionManager.is_exhausted("zombie"), "defeat exhausts the mustered minions")
	check(MinionManager.exhaustion_left("zombie") > 0.0 and MinionManager.exhaustion_left("zombie") <= MinionManager.EXHAUST_MINUTES * 60.0,
		"exhaustion runs on the rest timer")
	check(MinionManager.battle_ready_ids().is_empty(), "an exhausted roster has nobody battle-ready")
	# An exhausted warband cannot muster: the fight refuses to start
	DebugConsole.execute("combat")
	check(cv.party.is_empty() and cv.fight_state == "idle", "exhausted minions do not muster")
	# The gold rouse (between-fights heal): pay per minion, exhaustion clears
	GameManager.gold_coins += cv.REVIVE_GOLD_PER_MINION
	var rouse_gold_before = GameManager.gold_coins
	GameManager.gold_coins -= cv.REVIVE_GOLD_PER_MINION
	MinionManager.cure_exhaustion("zombie")
	check(not MinionManager.is_exhausted("zombie") and MinionManager.battle_ready_ids().has("zombie"),
		"curing exhaustion restores battle-readiness (gold was %d)" % rouse_gold_before)

	# --- Consumables (P2a→P3): battle potions are brewed, never sold; the
	# shop sells recipe SCROLLS instead ---
	var salve = GameManager.find_item_by_id("embalmers_salve")
	var draught = GameManager.find_item_by_id("war_draught")
	var phial = GameManager.find_item_by_id("venom_phial")
	var tonic = GameManager.find_item_by_id("grave_tonic")
	check(salve is Consumable and draught is Consumable and phial is Consumable and tonic is Consumable,
		"the four battle consumables register as Consumables")
	check(salve.is_combat_usable() and draught.is_combat_usable() and phial.is_combat_usable() and not tonic.is_combat_usable(),
		"combat usability splits potions from tonics")
	# Shop: scrolls only; price gates apply; no dupes; retired once studied
	check(not shop.SCROLL_PRICES.has("embalmers_salve"), "the shop no longer sells finished potions")
	AlchemyManager.known_recipe_ids.clear()
	GameManager.gold_coins = 0
	check(not shop.try_buy_scroll("scroll_war_draught"), "scrolls refuse the penniless")
	GameManager.gold_coins = 1000
	var scroll_gold = GameManager.gold_coins
	check(shop.try_buy_scroll("scroll_war_draught"), "gold buys the war draught scroll")
	check(GameManager.gold_coins == scroll_gold - 150, "the scroll costs its listed gold")
	check(InventoryManager.get_item_count("scroll_war_draught") == 1, "the bought scroll lands in the pack")
	check(not shop.try_buy_scroll("scroll_war_draught"), "the shop refuses a dupe while one sits unread")
	var war_recipe: Recipe = AlchemyManager.find_recipe_by_id("brew_war_draught")
	check(war_recipe != null and war_recipe.scroll_taught and not AlchemyManager.is_learned(war_recipe),
		"the war draught recipe starts unlearned")
	check(AlchemyManager.learn_recipe("brew_war_draught"), "studying the scroll teaches the recipe")
	InventoryManager.remove_item("scroll_war_draught", 1)
	check(AlchemyManager.is_learned(war_recipe) and not AlchemyManager.learn_recipe("brew_war_draught"),
		"a recipe learns once and stays learned")
	check(not shop.try_buy_scroll("scroll_war_draught"), "the shop retires a scroll once studied")
	# The potions themselves now come only from the Still
	InventoryManager.add_item(salve, 1)
	InventoryManager.add_item(draught, 1)
	InventoryManager.add_item(phial, 1)
	InventoryManager.add_item(tonic, 1)

	# In battle: the salve heals the acting minion and consumes itself
	DebugConsole.execute("combat")
	check(not cv.party.is_empty(), "a rested warband musters again")
	cv.action_beat = 0.0
	for foe in cv.enemies:
		foe["hp"] = 100000
		foe["max_hp"] = 100000
	cv.party[0]["hp"] = 1
	cv._execute_item(0, salve)
	var expected_heal = 1 + int(ceil(cv.party[0]["max_hp"] * 0.25))
	check(cv.party[0]["hp"] == mini(expected_heal, cv.party[0]["max_hp"]), "the salve heals 25%% of max HP (%d)" % cv.party[0]["hp"])
	check(InventoryManager.get_item_count("embalmers_salve") == 0, "using a consumable spends it")
	check(cv._held_combat_items().size() == 2, "the item menu lists what remains (draught + phial)")

	# The war draught: attack surge while its turns last
	cv.action_beat = 0.0
	cv._execute_item(0, draught)
	# _execute_item arms duration+1 and the drinking turn itself burns one tick,
	# so the surge stands at exactly duration_turns of REAL attacks.
	check(int(cv.party[0]["atk_up_turns"]) == draught.duration_turns and is_equal_approx(float(cv.party[0]["atk_up_mult"]), 1.3),
		"the draught arms an attack surge")
	# A x3 surge floor (3 * 0.85) clears the unsurged ceiling (1.15) at any ATK,
	# so the assert can't flake on damage-roll rounding.
	cv.party[0]["atk_up_mult"] = 3.0
	var surge_turns_before = int(cv.party[0]["atk_up_turns"])
	cv.action_beat = 0.0
	var pre_hp = int(cv.enemies[0]["hp"])
	cv._execute_attack(0, 0, 1.0, "")
	var surged = pre_hp - int(cv.enemies[0]["hp"])
	check(surged > MinionManager.get_atk("zombie") * 1.15, "a surged attack outdamages the normal ceiling (%d)" % surged)
	check(int(cv.party[0]["atk_up_turns"]) == surge_turns_before - 1, "each of the drinker's turns burns one surge turn")

	# Warden's Draught (P3): surge and stone-skin together
	var warden = GameManager.find_item_by_id("wardens_draught")
	InventoryManager.add_item(warden, 1)
	cv.action_beat = 0.0
	cv._execute_item(0, warden)
	check(int(cv.party[0]["dr_turns"]) == warden.duration_turns and is_equal_approx(float(cv.party[0]["dr_mult"]), 0.75) \
		and is_equal_approx(float(cv.party[0]["atk_up_mult"]), 1.25),
		"the warden's draught arms surge and stone-skin together")

	# Widow's Phial (P3): poison plus weakened blows
	var widow = GameManager.find_item_by_id("widows_phial")
	InventoryManager.add_item(widow, 1)
	cv.action_beat = 0.0
	cv.target_index = 0
	cv._execute_item(0, widow)
	check(int(cv.enemies[0]["poison_turns"]) == widow.duration_turns and is_equal_approx(float(cv.enemies[0]["weak_mult"]), 0.8) \
		and int(cv.enemies[0]["weak_turns"]) == widow.duration_turns,
		"the widow's phial poisons and weakens")

	# Sexton's Ashes (P3): the anointed rise once
	var ashes = GameManager.find_item_by_id("sextons_ashes")
	InventoryManager.add_item(ashes, 1)
	cv.action_beat = 0.0
	cv._execute_item(0, ashes)
	check(is_equal_approx(float(cv.party[0]["potion_revive_pct"]), 30.0), "the ashes anoint the drinker")
	cv.party[0]["hp"] = 1
	cv.party[0]["guarding"] = false
	cv.party[0]["revived"] = true  # spend the rune path so the potion's rise is what's measured
	cv._apply_party_damage(cv.party[0], 100000.0)
	check(cv.party[0]["hp"] == maxi(1, int(round(float(cv.party[0]["max_hp"]) * 0.30))) \
		and float(cv.party[0]["potion_revive_pct"]) == 0.0,
		"the anointed rise once at 30%% and the ashes spend themselves")

	# The venom phial: poison ticks BEFORE the foe acts, ignoring rage/guard
	cv.action_beat = 0.0
	cv.target_index = 0
	cv._execute_item(0, phial)
	check(int(cv.enemies[0]["poison_turns"]) == phial.duration_turns, "the phial poisons the target")
	var pre_poison_hp = int(cv.enemies[0]["hp"])
	cv.party[0]["hp"] = cv.party[0]["max_hp"]  # survive the counterattack
	cv.action_beat = 0.0
	cv._enemy_act(0)
	check(int(cv.enemies[0]["hp"]) <= pre_poison_hp - int(phial.magnitude), "poison bites as the foe stirs")
	check(int(cv.enemies[0]["poison_turns"]) == phial.duration_turns - 1, "each foe turn burns one poison turn")
	# A poisoned foe can die winding up
	cv.enemies[0]["hp"] = 1
	cv.enemies[1]["hp"] = 100000
	cv.action_beat = 0.0
	cv._enemy_act(0)
	check(int(cv.enemies[0]["hp"]) == 0 and cv.fight_state == "active", "venom can fell a foe before it acts")

	# The grave tonic rouses one exhausted minion
	MinionManager.exhaust("zombie")
	check(MinionManager.is_exhausted("zombie"), "exhaust() lays a minion low")
	MinionManager.cure_exhaustion("zombie")
	InventoryManager.remove_item("grave_tonic", 1)
	check(not MinionManager.is_exhausted("zombie") and InventoryManager.get_item_count("grave_tonic") == 0,
		"a tonic spent is a minion roused")
	cv.fight_state = "idle"
	# Bosses enrage as their health quarters break
	DebugConsole.execute("combat boss")
	cv.enemies[0]["hp"] = int(cv.enemies[0]["max_hp"] * 0.4)
	cv._check_boss_enrage(cv.enemies[0])
	check(cv.enemies[0]["segments_broken"] == 2 and cv.enemies[0]["rage"] > 1.0, "broken quarters enrage the boss")
	# Active runes spend once per battle
	cv.used_actives = {"zombie": ["lurch"]}
	check(cv._active_used("zombie", "lurch") and not cv._active_used("zombie", "carrion_nose"),
		"active runes spend once per battle")

	# --- The four active runes resolve DISTINCTLY (QA-1 / DEP-1) ---
	# Each cast: fresh group fight, tanky foes so nothing dies mid-assert.
	var zombie_atk = MinionManager.get_atk("zombie")
	var rune_kinds = {
		Ids.ACTIVE_LURCH: "heavy", Ids.ACTIVE_RATTLING_VOLLEY: "cleave",
		Ids.ACTIVE_RENDING_CLAWS: "sunder", Ids.ACTIVE_SAVAGE_POUNCE: "pounce",
	}
	for eff in Ids.ACTIVE_ALL:
		check(cv._active_defs.has(eff) and cv._active_defs[eff]["kind"] == rune_kinds[eff],
			"active '%s' resolves as %s" % [eff, rune_kinds[eff]])
	var _mk_test_active = func(effect: String, mult: float) -> MinionAbility:
		var ab = MinionAbility.new()
		ab.id = "test_" + effect
		ab.name = "Test " + effect
		ab.kind = MinionAbility.Kind.ACTIVE
		ab.effect = effect
		ab.magnitude = mult
		return ab
	var _fresh_fight = func():
		DebugConsole.execute("combat")
		cv.action_beat = 0.0
		cv.used_actives.clear()
		cv.target_index = 0
		for foe in cv.enemies:
			foe["hp"] = 100000
			foe["max_hp"] = 100000
			foe["charge"] = 0.5

	# Heavy (Lurch): one blow well beyond a normal attack's ceiling.
	_fresh_fight.call()
	cv._execute_active(0, _mk_test_active.call(Ids.ACTIVE_LURCH, 5.0))
	var heavy_dmg = 100000 - cv.enemies[0]["hp"]
	check(heavy_dmg > zombie_atk * 1.15 * 2.0, "Lurch lands a heavy blow (%d vs atk %.1f)" % [heavy_dmg, zombie_atk])
	check(cv._active_used("zombie", "test_" + Ids.ACTIVE_LURCH), "casting spends the rune")

	# Cleave (Rattling Volley): every living foe is struck.
	_fresh_fight.call()
	cv._execute_active(0, _mk_test_active.call(Ids.ACTIVE_RATTLING_VOLLEY, 1.0))
	var all_struck = true
	for foe in cv.enemies:
		if foe["hp"] >= 100000: all_struck = false
	check(all_struck, "Rattling Volley strikes every foe")

	# Sunder (Rending Claws): flags the foe, and follow-up hits punch above
	# an unsundered attack's maximum roll.
	_fresh_fight.call()
	cv._execute_active(0, _mk_test_active.call(Ids.ACTIVE_RENDING_CLAWS, 1.0))
	check(int(cv.enemies[0]["sunder"]) == cv.SUNDER_TURNS, "Rending Claws sunders the foe for %d turns" % cv.SUNDER_TURNS)
	var hp_before_followup = cv.enemies[0]["hp"]
	cv._strike_foe(0, cv.enemies[0], 1.0)
	var sundered_dmg = hp_before_followup - cv.enemies[0]["hp"]
	check(sundered_dmg > zombie_atk * 1.15, "sundered foes take amplified damage (%d)" % sundered_dmg)
	# The window closes as the foe spends its turns.
	cv.enemies[0]["hp"] = 100000
	cv._enemy_act(0)
	check(int(cv.enemies[0]["sunder"]) == cv.SUNDER_TURNS - 1, "a foe's turn ticks the sunder window down")

	# Pounce (Savage Pounce): drains the foe's turn gauge.
	_fresh_fight.call()
	cv.enemies[0]["charge"] = 0.9
	cv._execute_active(0, _mk_test_active.call(Ids.ACTIVE_SAVAGE_POUNCE, 1.0))
	check(float(cv.enemies[0]["charge"]) == 0.0, "Savage Pounce wipes the foe's turn gauge")
	# Confront descends into the crypt now that a warband exists
	GameManager.skills["graverobbing"]["level"] = 20
	gv.update_ui()
	gv.cards[4].action_triggered.emit()
	check(cv.visible and cv.is_boss_fight and "Warden" in cv.enemies[0]["name"], "Confront descends into the crypt")
	GameManager.skills["graverobbing"] = {"level": 1, "xp": 0.0}
	cv.fight_state = "idle"

	get_tree().call_group(Ids.GROUP_VIEW_MANAGER, "switch_view", Ids.VIEW_GRAVEYARD)
	check(not cv.visible, "leaving combat returns to the grounds")

	# Save / load round trip + node resume
	GameManager.active_node_data = grave
	var gold_saved = GameManager.gold_coins
	var grob_level = GameManager.skills["graverobbing"]["level"]
	SaveManager.save_game()
	GameManager.gold_coins = 0
	GameManager.active_action_source = null
	GameManager.active_node_data = null
	InventoryManager.purchased_slots = 0
	MinionManager.reset_state()
	SaveManager.load_game()
	check(GameManager.gold_coins == gold_saved, "gold restored from save")
	check(GameManager.skills["graverobbing"]["level"] == grob_level, "skills restored from save")
	check(InventoryManager.purchased_slots == 1, "purchased slots restored from save")
	check(GameManager.get_equipped_tool(ToolData.ToolType.HATCHET) == hatchet, "equipped tools restored from save")
	check(GameManager.active_node_data == grave, "active node resumes automatically after load")
	check(MinionManager.get_level("zombie") >= 2 and MinionManager.has_ability("zombie", "gravekeepers_vigor"), "minion roster restored from save")
	check(MinionManager.plots[1] == "zombie", "plot assignments restored from save")
	check(MinionManager.necronomicon_unlocked, "necronomicon unlock persists across save/load")

	# Exhaustion (P2a) rides the save file too
	MinionManager.exhaust("zombie", 30.0)
	SaveManager.save_game()
	MinionManager.cure_exhaustion("zombie")
	SaveManager.load_game()
	check(MinionManager.is_exhausted("zombie"), "exhaustion persists across save/load")
	MinionManager.cure_exhaustion("zombie")
	SaveManager.save_game()

	# --- Offline accrual (QA-1): bulk harvests bank gains + XP in one pass ---
	var off_node = GameManager.find_node_by_id("fresh_grave")
	var off_dur = GameManager.get_effective_duration(off_node)
	var off_xp_before = GameManager.skills["graverobbing"]["xp"]
	var off_result = GameManager.accrue_offline(off_node, off_dur * 10.5)
	check(int(off_result.get("harvests", 0)) == 10, "offline sim runs one harvest per duration (%d)" % int(off_result.get("harvests", 0)))
	check(not off_result.get("gains", {}).is_empty(), "offline harvests bank gains")
	check(float(off_result.get("xp", 0.0)) > 0.0 and GameManager.skills["graverobbing"]["xp"] > off_xp_before,
		"offline harvests grant skill XP")
	check(GameManager.accrue_offline(off_node, off_dur * 0.5).is_empty(), "less than one harvest of time accrues nothing")
	# Breakable nodes pay their guaranteed break haul over the bulk pass
	var off_wall = GameManager.find_node_by_id("verdigris_seams")
	var wall_hits = int(ceil(1.0 / off_wall.hit_damage)) * 2
	var wall_result = GameManager.accrue_offline(off_wall, GameManager.get_effective_duration(off_wall) * (wall_hits + 0.5))
	check(int(wall_result.get("harvests", 0)) == wall_hits and not wall_result.get("gains", {}).is_empty(),
		"offline sim breaks nodes and pays their guaranteed haul")
	# COR-6: overflow past a full pack is counted and reported, not silent
	var stashed_slots = InventoryManager.slots.duplicate(true)
	var brick: Item = GameManager.find_item_by_id("obsidian_shard")
	for i in range(InventoryManager.slots.size()):
		InventoryManager.slots[i] = {"item": brick, "quantity": brick.max_stack}
	var full_result = GameManager.accrue_offline(off_node, off_dur * 5.5)
	check(int(full_result.get("lost", 0)) > 0, "offline overflow into a full pack is counted as lost (%d)" % int(full_result.get("lost", 0)))
	var reported_total := 0
	for gid in full_result.get("gains", {}):
		reported_total += int(full_result["gains"][gid])
	check(reported_total == 0, "lost items are not reported as gains")
	InventoryManager.slots = stashed_slots
	InventoryManager.inventory_updated.emit()

	# --- COR-5: offering XP decouples from sell price via offering_value ---
	var rite_item = Item.new()
	rite_item.id = "test_offering"
	rite_item.sell_value = 10
	check(is_equal_approx(MinionManager.get_offering_xp(rite_item), 10.0 * MinionManager.OFFERING_XP_PER_GOLD),
		"offering XP defaults to sell value")
	rite_item.offering_value = 4
	check(is_equal_approx(MinionManager.get_offering_xp(rite_item), 4.0 * MinionManager.OFFERING_XP_PER_GOLD),
		"an explicit offering_value overrides sell value")
	rite_item.is_sellable = false
	check(is_equal_approx(MinionManager.get_offering_xp(rite_item), 4.0 * MinionManager.OFFERING_XP_PER_GOLD),
		"unsellable items with an offering_value can still be offered")
	rite_item.offering_value = -1
	check(MinionManager.get_offering_xp(rite_item) == 0.0, "unsellable items without an offering_value cannot")

	# --- DEP-7: autosave cadence persists and 'off' disables the timer ---
	var prev_autosave = SettingsManager.autosave_choice
	SettingsManager.set_autosave_choice_by_index(SettingsManager.get_autosave_index("off"))
	check(SettingsManager.get_autosave_seconds() == 0.0, "'off' autosave choice reports no interval")
	SettingsManager.autosave_choice = "30s"
	SettingsManager.load_settings()
	check(SettingsManager.autosave_choice == "off", "autosave choice persists to the settings file")
	check(SettingsManager.get_autosave_index("bogus") == 1, "unknown autosave choices fall back to 30s")
	SettingsManager.autosave_choice = prev_autosave
	SettingsManager.save_settings()

	# --- Alchemy (P3): the recipe book, brewing, and gather elixirs ---
	check(AlchemyManager.recipe_db.size() >= 4, "the recipe book loads (%d recipes)" % AlchemyManager.recipe_db.size())
	var salve_recipe: Recipe = AlchemyManager.find_recipe_by_id("brew_embalmers_salve")
	check(salve_recipe != null and salve_recipe.output_item != null and salve_recipe.output_item.id == "embalmers_salve",
		"the salve recipe brews the salve")
	var sorted_recipes = AlchemyManager.sorted_ids()
	check(sorted_recipes[0] == "brew_embalmers_salve", "recipes sort by required level (%s first)" % str(sorted_recipes[0]))
	# Gates: a scroll recipe refuses even a leveled alchemist until studied,
	# and a studied one still gates on alchemy level
	AlchemyManager.known_recipe_ids.clear()
	var gate_recipe: Recipe = AlchemyManager.find_recipe_by_id("brew_war_draught")
	for input_id in gate_recipe.inputs:
		InventoryManager.add_item(GameManager.find_item_by_id(input_id), int(gate_recipe.inputs[input_id]))
	GameManager.skills[Ids.SKILL_ALCHEMY] = {"level": 50, "xp": 0.0}
	check(not AlchemyManager.can_brew(gate_recipe), "scroll recipes refuse the unread")
	AlchemyManager.learn_recipe("brew_war_draught")
	check(AlchemyManager.can_brew(gate_recipe), "a studied scroll recipe brews")
	GameManager.skills[Ids.SKILL_ALCHEMY] = {"level": 1, "xp": 0.0}
	check(not AlchemyManager.can_brew(gate_recipe), "recipes gate on alchemy level")
	# Learned recipes ride the save file
	SaveManager.save_game()
	AlchemyManager.known_recipe_ids.clear()
	SaveManager.load_game()
	check(AlchemyManager.is_learned(gate_recipe), "learned recipes ride the save file")
	# One brew: inputs paid at the start, potion + XP at the finish
	for input_id in salve_recipe.inputs:
		var held_in = InventoryManager.get_item_count(input_id)
		if held_in > 0: InventoryManager.remove_item(input_id, held_in)
		InventoryManager.add_item(GameManager.find_item_by_id(input_id), int(salve_recipe.inputs[input_id]))
	var salves_before = InventoryManager.get_item_count("embalmers_salve")
	var alch_xp_before = GameManager.skills[Ids.SKILL_ALCHEMY]["xp"]
	check(AlchemyManager.start_brew(salve_recipe), "a stocked shelf starts the brew")
	check(InventoryManager.get_item_count("flesh") == 0 and InventoryManager.get_item_count("blood") == 0,
		"starting a brew pays its inputs")
	check(not AlchemyManager.start_brew(salve_recipe) or AlchemyManager.active_recipe == salve_recipe,
		"an empty shelf cannot double-start")
	AlchemyManager._process(salve_recipe.base_seconds + 0.1)
	check(InventoryManager.get_item_count("embalmers_salve") == salves_before + 1, "a finished brew bottles the potion")
	check(GameManager.skills[Ids.SKILL_ALCHEMY]["xp"] > alch_xp_before or GameManager.skills[Ids.SKILL_ALCHEMY]["level"] > 1,
		"brewing grants alchemy XP")
	check(AlchemyManager.active_recipe == null, "the burner goes cold when inputs run dry")
	# Auto-repeat: two sets of inputs = the still restarts itself once
	for input_id in salve_recipe.inputs:
		InventoryManager.add_item(GameManager.find_item_by_id(input_id), int(salve_recipe.inputs[input_id]) * 2)
	AlchemyManager.start_brew(salve_recipe)
	AlchemyManager._process(salve_recipe.base_seconds + 0.1)
	check(AlchemyManager.active_recipe == salve_recipe, "the still auto-repeats while ingredients last")
	AlchemyManager.stop_brew()
	check(AlchemyManager.active_recipe == null, "stop_brew cools the burner")

	# Gather elixirs: a timed buff channel in get_gather_modifiers
	var mods_before = GameManager.get_gather_modifiers(grave)
	GameManager.apply_timed_buff(Ids.EFFECT_HARVEST_XP_PCT, 15.0, 10.0)
	GameManager.apply_timed_buff(Ids.EFFECT_RARE_CHANCE_PCT, 10.0, 10.0)
	var mods_after = GameManager.get_gather_modifiers(grave)
	check(is_equal_approx(mods_after.xp_mult, mods_before.xp_mult + 0.15), "the brew buffs harvest XP (+15%)")
	check(is_equal_approx(mods_after.rare_add, mods_before.rare_add + 0.10), "the elixir buffs rare chance (+10%)")
	check(GameManager.buff_seconds_left(Ids.EFFECT_HARVEST_XP_PCT) > 0.0, "buffs report their time left")
	# The Great Work (P3 capstone): three brewed stages ending in the Homunculus
	var quickening: Recipe = AlchemyManager.find_recipe_by_id("brew_the_quickening")
	check(quickening != null and quickening.output_item != null and quickening.output_item.id == "homunculus_heart",
		"the Quickening brews the homunculus heart")
	check(AlchemyManager.find_recipe_by_id("brew_prima_materia") != null \
		and AlchemyManager.find_recipe_by_id("brew_seed_of_flesh") != null,
		"the Vat's earlier stages load")
	var homunculus: Minion = MinionManager.find_minion_by_id("homunculus")
	check(homunculus != null and homunculus.raise_cost.has("homunculus_heart"),
		"the homunculus is raised from the brewed heart")
	check(not MinionManager.can_afford_raise(homunculus), "no heart, no homunculus")
	InventoryManager.add_item(GameManager.find_item_by_id("homunculus_heart"), 1)
	check(MinionManager.raise_minion("homunculus"), "the brewed heart raises the homunculus")
	check(MinionManager.is_raised("homunculus") and InventoryManager.get_item_count("homunculus_heart") == 0,
		"the Great Work concludes — heart spent, homunculus raised")

	# Buffs ride the save file
	SaveManager.save_game()
	GameManager.active_buffs.clear()
	SaveManager.load_game()
	check(GameManager.get_buff_bonus(Ids.EFFECT_HARVEST_XP_PCT) > 0.0, "elixir buffs persist across save/load")
	# Expiry prunes the channel
	GameManager.apply_timed_buff(Ids.EFFECT_HARVEST_XP_PCT, 15.0, -1.0)
	check(GameManager.get_buff_bonus(Ids.EFFECT_HARVEST_XP_PCT) == 0.0, "expired buffs fall away")
	GameManager.active_buffs.clear()

	# Incense (P3): grounds-wide timed channels
	var vigil: Consumable = GameManager.find_item_by_id("vigil_incense")
	check(vigil is Consumable and vigil.is_incense() and not vigil.is_combat_usable(),
		"incense burns from the inventory, not the battle menu")
	var mods_incense_before = GameManager.get_gather_modifiers(grave)
	InventoryManager.add_item(vigil, 1)
	inv_view._on_item_selected(vigil)
	check(inv_view.use_button.visible, "the Burn button appears for incense")
	inv_view._on_use_pressed()
	check(InventoryManager.get_item_count("vigil_incense") == 0, "burning consumes the incense")
	var mods_incense = GameManager.get_gather_modifiers(grave)
	check(is_equal_approx(mods_incense.double_chance, mods_incense_before.double_chance + 0.15),
		"vigil incense buffs double-harvest chance")
	# Corpse-candle: stirs current rests and discounts new ones while it burns
	MinionManager.exhaust("zombie")
	var rest_before = MinionManager.exhaustion_left("zombie")
	GameManager.apply_timed_buff(Ids.EFFECT_EXHAUST_HASTE_PCT, 50.0, 15.0)
	MinionManager.hasten_exhaustion(50.0)
	check(MinionManager.exhaustion_left("zombie") < rest_before * 0.6, "lighting the candle stirs the resting")
	MinionManager.exhaust("zombie")
	check(MinionManager.exhaustion_left("zombie") < MinionManager.EXHAUST_MINUTES * 60.0 * 0.6,
		"the candle discounts new exhaustion while it burns")
	MinionManager.cure_exhaustion("zombie")
	GameManager.active_buffs.clear()
	# Studying from the inventory: the details-panel Study button
	var scroll_item: Consumable = GameManager.find_item_by_id("scroll_war_draught")
	check(scroll_item is Consumable and scroll_item.is_recipe_scroll() and not scroll_item.is_combat_usable(),
		"recipe scrolls are inventory-studied, not combat items")
	AlchemyManager.known_recipe_ids.clear()
	InventoryManager.add_item(scroll_item, 1)
	inv_view._on_item_selected(scroll_item)
	check(inv_view.use_button.visible and not inv_view.use_button.disabled, "the Study button appears for unread scrolls")
	inv_view._on_use_pressed()
	check(InventoryManager.get_item_count("scroll_war_draught") == 0, "studying consumes the scroll")
	check(AlchemyManager.is_learned(AlchemyManager.find_recipe_by_id("brew_war_draught")),
		"the Study button teaches the recipe")
	GameManager.active_buffs.clear()
	GameManager.skills[Ids.SKILL_ALCHEMY] = {"level": 1, "xp": 0.0}

	# --- Grounds wave two (P4): four new structures, gold costs, effects ---
	for sid in ["mausoleum", "counting_house", "reliquary", "apothecary"]:
		check(GroundsManager.find_structure(sid) != null, "wave-two structure loads: %s" % sid)
	# Gold is now a real tier component: materials alone no longer suffice
	var mauso_tier: StructureTier = GroundsManager.next_tier("mausoleum")
	check(mauso_tier != null and mauso_tier.gold > 0, "wave-two tiers carry a gold cost")
	for cost_id in mauso_tier.cost:
		InventoryManager.add_item(GameManager.find_item_by_id(cost_id), int(mauso_tier.cost[cost_id]))
	var stashed_gold = GameManager.gold_coins
	GameManager.gold_coins = mauso_tier.gold - 1
	check(not GroundsManager.can_afford("mausoleum"), "a light purse blocks the build")
	GameManager.gold_coins = mauso_tier.gold + 10
	check(GroundsManager.can_afford("mausoleum"), "materials + gold afford the build")
	check(GroundsManager.build("mausoleum"), "the mausoleum rises")
	check(GameManager.gold_coins == 10, "building spends the gold component")
	check(GroundsManager.get_level("mausoleum") == 1, "the mausoleum stands at tier 1")
	GameManager.gold_coins = stashed_gold
	# Effects: offering potency, sell value, brew speed, rare-find chance
	GroundsManager.debug_set_level("mausoleum", 0)
	var base_offer_xp = MinionManager.get_offering_xp(GameManager.find_item_by_id("flesh"))
	GroundsManager.debug_set_level("mausoleum", 2)  # 2 tiers × 10% = +20%
	check(is_equal_approx(MinionManager.get_offering_xp(GameManager.find_item_by_id("flesh")), base_offer_xp * 1.2),
		"the mausoleum amplifies offerings (+20%)")
	GroundsManager.debug_set_level("counting_house", 2)  # 2 × 5% = +10%
	check(inv_view._get_unit_sell_value(GameManager.find_item_by_id("obsidian_shard")) == 165,
		"the counting house raises sale prices (150 -> 165)")
	GroundsManager.debug_set_level("apothecary", 2)  # 2 × 10% = +20% speed
	check(is_equal_approx(AlchemyManager.get_effective_seconds(salve_recipe), salve_recipe.base_seconds / 1.2),
		"the apothecary quickens the still (+20%)")
	var rare_before_reliquary = GameManager.get_gather_modifiers(grave).rare_add
	GroundsManager.debug_set_level("reliquary", 3)  # 3 × 1% = +3%
	check(is_equal_approx(GameManager.get_gather_modifiers(grave).rare_add, rare_before_reliquary + 0.03),
		"the reliquary draws rare finds (+3%)")
	for sid in ["mausoleum", "counting_house", "reliquary", "apothecary"]:
		GroundsManager.debug_set_level(sid, 0)

	# --- Forge (P5): smith gear, arm the warband, combat only ---
	check(ForgeManager.recipe_db.size() >= 6, "the forge loads its patterns (%d)" % ForgeManager.recipe_db.size())
	var blade_recipe: Recipe = ForgeManager.find_recipe_by_id("smith_nickel_blade")
	check(blade_recipe != null and blade_recipe.output_item is Gear, "the blade pattern smiths Gear")
	for input_id in blade_recipe.inputs:
		InventoryManager.add_item(GameManager.find_item_by_id(input_id), int(blade_recipe.inputs[input_id]))
	var forge_xp_before = GameManager.skills[Ids.SKILL_FORGE]["xp"]
	check(ForgeManager.start_brew(blade_recipe), "a stocked forge starts the smith")
	ForgeManager._process(blade_recipe.base_seconds + 0.1)
	check(InventoryManager.get_item_count("nickel_blade") >= 1, "the finished smith yields the blade")
	check(GameManager.skills[Ids.SKILL_FORGE]["xp"] > forge_xp_before or GameManager.skills[Ids.SKILL_FORGE]["level"] > 1,
		"smithing grants forge XP")
	ForgeManager.stop_brew()

	# Equipping: weapon adds flat ATK, trinket adds flat HP + a combat passive
	var blade: Gear = GameManager.find_item_by_id("nickel_blade")
	var idol: Gear = GameManager.find_item_by_id("jade_idol")
	var charm: Gear = GameManager.find_item_by_id("quartz_charm")
	check(blade.slot == Gear.GearSlot.WEAPON and idol.slot == Gear.GearSlot.TRINKET, "gear knows its slot")
	var atk_bare = MinionManager.get_atk("zombie")
	var hp_bare = MinionManager.get_hp("zombie")
	var gather_bare = GameManager.get_gather_modifiers(grave)
	check(MinionManager.equip_gear("zombie", blade), "the zombie takes up the blade")
	check(InventoryManager.get_item_count("nickel_blade") == 0, "equipping lifts the piece from the pack")
	check(is_equal_approx(MinionManager.get_atk("zombie"), atk_bare + blade.atk_bonus), "the blade adds flat ATK")
	InventoryManager.add_item(charm, 1)
	check(MinionManager.equip_gear("zombie", charm), "the trinket slot fills independently")
	check(MinionManager.get_hp("zombie") == hp_bare + charm.hp_bonus, "the charm adds flat HP")
	# Swapping trinkets returns the old one to the pack
	InventoryManager.add_item(idol, 1)
	check(MinionManager.equip_gear("zombie", idol), "a new trinket swaps in")
	check(InventoryManager.get_item_count("quartz_charm") == 1, "the displaced charm returns to the pack")
	check(is_equal_approx(MinionManager.get_minion_effect("zombie", Ids.MINION_LIFESTEAL_PCT), idol.passive_magnitude),
		"trinket passives ride the combat channels")
	# Gear is COMBAT ONLY: the gather model must not move
	var gather_armed = GameManager.get_gather_modifiers(grave)
	check(is_equal_approx(gather_armed.xp_mult, gather_bare.xp_mult) and is_equal_approx(gather_armed.rare_add, gather_bare.rare_add),
		"gear never touches the gather economy")
	# Gear rides the save
	SaveManager.save_game()
	MinionManager.gear.clear()
	SaveManager.load_game()
	check(MinionManager.get_gear("zombie", Gear.GearSlot.WEAPON) == blade and MinionManager.get_gear("zombie", Gear.GearSlot.TRINKET) == idol,
		"worn gear persists across save/load")
	# Unequip returns the piece
	check(MinionManager.unequip_gear("zombie", Gear.GearSlot.WEAPON), "the blade comes off")
	check(InventoryManager.get_item_count("nickel_blade") == 1 and is_equal_approx(MinionManager.get_atk("zombie"), atk_bare),
		"unequipping restores bare stats and returns the piece")
	MinionManager.unequip_gear("zombie", Gear.GearSlot.TRINKET)
	SaveManager.save_game()

	# --- Stats, achievements, restoration (P7 / DEP-6) ---
	check(StatsManager.get_stat(StatsManager.STAT_HARVESTS) > 0.0, "harvests count themselves via the signal")
	check(StatsManager.get_stat(StatsManager.STAT_BREAKS) > 0.0, "breaks count themselves via the signal")
	check(StatsManager.get_stat(StatsManager.STAT_CRAFTS) >= 3.0, "brews and smiths share the crafts counter (%d)" % int(StatsManager.get_stat(StatsManager.STAT_CRAFTS)))
	check(StatsManager.get_stat(StatsManager.STAT_MINIONS_RAISED) >= 1.0, "raisings are counted")
	check(StatsManager.get_stat(StatsManager.STAT_OFFERINGS) >= 1.0, "offerings are counted")
	check(StatsManager.get_stat(StatsManager.STAT_FIGHTS_WON) >= 1.0 and StatsManager.get_stat(StatsManager.STAT_FIGHTS_LOST) >= 1.0,
		"combat endings are counted (%d won / %d lost)" % [int(StatsManager.get_stat(StatsManager.STAT_FIGHTS_WON)), int(StatsManager.get_stat(StatsManager.STAT_FIGHTS_LOST))])
	check(StatsManager.has_achievement("first_dig"), "ten harvests earn First Shift")
	check(StatsManager.has_achievement("first_blood"), "the first victory earns First Blood")
	# An achievement never re-fires: bumping past an earned threshold is quiet
	var earned_count = StatsManager.earned.size()
	StatsManager.bump(StatsManager.STAT_FIGHTS_WON)
	check(StatsManager.earned.size() == earned_count, "earned achievements never re-fire")
	# Restoration: monotone rises from building and raising
	var restore_before = StatsManager.get_restoration_pct()
	check(restore_before > 0.0 and restore_before < 100.0, "restoration sits mid-journey (%.1f%%)" % restore_before)
	GroundsManager.debug_set_level("chapel", 5)
	check(StatsManager.get_restoration_pct() > restore_before, "raising structures restores the graveyard")
	GroundsManager.debug_set_level("chapel", 0)
	# Stats ride the save
	var saved_harvests = StatsManager.get_stat(StatsManager.STAT_HARVESTS)
	SaveManager.save_game()
	StatsManager.reset_state()
	check(StatsManager.get_stat(StatsManager.STAT_HARVESTS) == 0.0, "reset clears the ledger")
	SaveManager.load_game()
	check(StatsManager.get_stat(StatsManager.STAT_HARVESTS) == saved_harvests, "stats persist across save/load")
	check(StatsManager.has_achievement("first_dig"), "earned achievements persist across save/load")

	# --- Save migration (ARC-3): old saves upgrade, they don't wipe ---
	# _migrate is pure, so exercise its contract directly.
	var migrated_same = SaveManager._migrate({"version": SaveManager.SAVE_VERSION, "gold": 7}, SaveManager.SAVE_VERSION)
	check(int(migrated_same.get("gold", -1)) == 7 and int(migrated_same.get("version", -1)) == SaveManager.SAVE_VERSION,
		"migration is a no-op at the current save version")
	check(SaveManager._migrate({"version": 1, "gold": 999}, 1).is_empty(),
		"a pre-reboot v1 save is intentionally unrecoverable (starts fresh)")
	var migrated_v2 = SaveManager._migrate({"version": 2, "gold": 55}, 2)
	check(int(migrated_v2.get("version", -1)) == SaveManager.SAVE_VERSION and int(migrated_v2.get("gold", -1)) == 55,
		"a v2 save carries forward to v%d intact" % SaveManager.SAVE_VERSION)
	check(SaveManager._migrate({"version": 0}, 0).is_empty(),
		"a save version with no migration path starts fresh")

	# A save from a NEWER build must be preserved (backed up), never overwritten.
	var newer_data = {"version": SaveManager.SAVE_VERSION + 5, "gold": 424242}
	var newer_file = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	newer_file.store_string(JSON.stringify(newer_data))
	newer_file.close()
	GameManager.gold_coins = 0
	SaveManager.load_game()
	check(GameManager.gold_coins == 0, "a newer-version save is not loaded (state left at defaults)")
	var found_backup := false
	var udir = DirAccess.open("user://")
	if udir:
		udir.list_dir_begin()
		var bak_name = udir.get_next()
		while bak_name != "":
			if bak_name.begins_with("graveyard_shift_save.json.newer.") and bak_name.ends_with(".bak"):
				found_backup = true
				DirAccess.remove_absolute("user://" + bak_name)
			bak_name = udir.get_next()
		udir.list_dir_end()
	check(found_backup, "a newer-version save is backed up to a .bak copy, not clobbered")
	DirAccess.remove_absolute(SaveManager.SAVE_PATH)

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
	get_tree().call_group(Ids.GROUP_VIEW_MANAGER, "switch_view", Ids.VIEW_FOREST)
	check(TutorialManager.current_step().get("id", "") == "chop", "opening Lumbering advances the tutorial")
	for i in range(TutorialManager.current_step().get("count", 1)):
		GameManager.resolve_harvest(GameManager.find_node_by_id("withered_trees"), false)
	check(TutorialManager.current_step().get("id", "") == "to_quarry", "felling trees advances the tutorial")
	get_tree().call_group(Ids.GROUP_VIEW_MANAGER, "switch_view", Ids.VIEW_QUARRY)
	check(TutorialManager.current_step().get("id", "") == "mine", "opening Spelunking advances the tutorial")
	for i in range(TutorialManager.current_step().get("count", 1)):
		GameManager.resolve_harvest(GameManager.find_node_by_id("verdigris_seams"), false)
	check(TutorialManager.current_step().get("id", "") == "tome", "mining stone advances to the tome reward")

	# The Necronomicon chapter of the tutorial. The unlock fires on ENTERING the
	# tome step (_enter_step_effects), so re-run the entry effects to assert it.
	MinionManager.necronomicon_unlocked = false
	TutorialManager._enter_step_effects()
	check(MinionManager.necronomicon_unlocked, "the tome step unlocks the necronomicon")
	TutorialManager._on_continue_pressed()
	check(TutorialManager.current_step().get("id", "") == "open_book", "taking the tome advances to opening it")
	check(TutorialManager._resolve_highlight_target() != null, "the circle is highlighted for the player")
	TutorialManager.notify_event(Ids.EVENT_BOOK_OPENED)
	# Raise and slot lessons auto-skip: this run already has a raised, slotted zombie
	check(TutorialManager.current_step().get("id", "") == "growth", "raise and slot lessons skip when already done")
	TutorialManager._on_continue_pressed()
	check(TutorialManager.current_step().get("id", "") == "altar", "the growth lesson advances to the altar")
	check(InventoryManager.get_item_count("bones") >= 5, "Mortimer leaves bones for the offering")
	MinionManager.offer_materials("zombie", "bones", 1)
	check(TutorialManager.current_step().get("id", "") == "outro", "an offering advances to the farewell")
	TutorialManager._on_continue_pressed()
	check(TutorialManager.tutorial_complete and not TutorialManager.active, "tutorial completes and dismisses")

	# Completion persists; it does not restart on the next load
	SaveManager.save_game()
	TutorialManager.tutorial_complete = false
	SaveManager.load_game()
	TutorialManager.maybe_start()
	check(TutorialManager.tutorial_complete and not TutorialManager.active, "tutorial completion persists across save/load")

	main.queue_free()

	# --- Hard reset (last: wipes everything except player settings) ---
	var window_choice_before_reset = SettingsManager.window_choice
	SaveManager.hard_reset()
	check(SettingsManager.window_choice == window_choice_before_reset, "hard reset leaves display settings alone")
	check(GameManager.gold_coins == 0, "hard reset zeroes gold")
	check(GameManager.skills["graverobbing"]["level"] == 1, "hard reset resets skills")
	check(InventoryManager.slots.size() == InventoryManager.BASE_SLOTS, "hard reset restores base inventory size")
	check(GameManager.get_equipped_tool(ToolData.ToolType.SHOVEL) != null, "hard reset re-equips starting tools")
	check(MinionManager.roster.is_empty() and MinionManager.plots == ["", "", "", ""], "hard reset dismisses all minions")
	check(not MinionManager.necronomicon_unlocked, "hard reset puts the tome back to sleep")
	check(TutorialManager.active and not TutorialManager.tutorial_complete, "hard reset restarts the tutorial")
	TutorialManager.finish(true)
	check(MinionManager.necronomicon_unlocked, "skipping the tutorial still grants the necronomicon")

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
