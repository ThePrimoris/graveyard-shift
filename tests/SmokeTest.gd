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

	# --- Every harvest lands exactly one common-table row ---
	var expectations = {
		"fresh_grave": ["graverobbing", "flesh"],
		"withered_trees": ["lumbering", "rotten_logs"],
		"verdigris_seams": ["spelunking", "stone_debris"],
	}
	for node_id in expectations:
		var node = GameManager.find_node_by_id(node_id)
		var skill = expectations[node_id][0]
		var drop = expectations[node_id][1]
		check(node != null and GameManager.get_skill_key(node) == skill, "%s belongs to %s" % [node_id, skill])
		var xp_before = GameManager.skills[skill]["xp"]
		var every_harvest_paid = true
		var saw_expected = false
		for i in range(15):
			var g = GameManager.resolve_harvest(node, false)
			if g.is_empty(): every_harvest_paid = false
			if g.has(drop): saw_expected = true
		if node.hit_damage > 0.0:
			check(not node.hit_pool.is_empty(), "%s rolls a hit chance table" % node_id)
		else:
			check(every_harvest_paid, "%s pays out on every harvest" % node_id)
		check(saw_expected, "%s drops %s" % [node_id, drop])
		check(InventoryManager.get_item_count(drop) >= 1, "%s banked in inventory" % drop)
		check(GameManager.skills[skill]["xp"] > xp_before or GameManager.skills[skill]["level"] > 1, "%s grants %s XP" % [node_id, skill])

	# The player-authored Fresh Graves tables: 3 commons, 2 rares at 1%
	var fg = GameManager.find_node_by_id("fresh_grave")
	check(fg.common_pool.size() == 3, "fresh graves common table holds 3 rows")
	check(fg.rare_pool.size() == 2 and is_equal_approx(fg.rare_chance, 0.01), "fresh graves rare table holds 2 rows at 1%")

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
	check(gv.cards[0].rare_header.text == "Rare — 1%", "rare header carries the hit chance (%s)" % gv.cards[0].rare_header.text)
	check(gv.cards[0].divider.visible, "ledger divider splits the two tables")

	check(gv.header_title != null and gv.header_title.text.begins_with("Graverobbing"), "page header shows the skill")
	var fv = main.find_child("ForestView", true, false)
	check(fv.cards.size() >= 1 and fv.cards[0].bars.size() == 1 and fv.cards[0].bars[0].value == 0.0, "withered trees use a single fill bar")
	check(fv.cards[0].rare_col.visible and fv.cards[0].divider.visible, "rare column shows for a node with a rare table")
	# Lumbering keeps the dig-layer meter: 2 sections on Withered Trees
	check(GameManager.find_node_by_id("withered_trees").dig_sections == 2, "Withered Trees chops in 2 sections")
	check(fv.cards[0].segments.size() == 2 and fv.cards[0].segment_box.visible, "lumbering card shows a 2-section layer meter")
	check(fv.cards[0].segment_box is VBoxContainer, "layer meter is vertical")
	# A full sweep of the bottom bar removes one section (top first).
	fv.cards[0].update_progress(0.75, 3.0)  # 25% -> bar mid-sweep, no section removed yet
	check(fv.cards[0].segments[0].modulate.a > 0.5 and fv.cards[0].bars[0].value > 0.0, "bottom bar sweeps within the current section")
	fv.cards[0].update_progress(1.5, 3.0)   # halfway -> top section gone
	check(fv.cards[0].segments[0].modulate.a < 0.5 and fv.cards[0].segments[1].modulate.a > 0.5, "a full sweep removes the top section")
	fv.cards[0].reset_progress()
	check(fv.cards[0].segments[0].modulate.a > 0.5, "reset restores all sections")
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
	check(fv.zones.size() == 1 and fv.zones[0].name == "Shrouded Woods", "lumbering zone is Shrouded Woods")
	check(qv.zones.size() == 1 and qv.zones[0].name == "Mineshaft", "spelunking zone is Mineshaft")
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
	# Escalating rare chances across the grave nodes
	check(is_equal_approx(GameManager.find_node_by_id("forgotten_graves").rare_chance, 0.05), "deeper graves carry richer rare chances")

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
	check(not GameManager.owns_tool("rusty_hatchet"), "old tool is melted down")

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
	check(MinionManager.sorted_ids() == ["zombie", "skeleton", "undead_hound", "ghoul"], "four minions order by sort_order (%s)" % str(MinionManager.sorted_ids()))
	# The warband roster: one minion per plot once all four are raised
	var hound: Minion = MinionManager.find_minion_by_id("undead_hound")
	var ghoul: Minion = MinionManager.find_minion_by_id("ghoul")
	check(hound != null and hound.raise_cost.get("jagged_fangs", 0) > 0, "undead hound rite costs fangs")
	check(ghoul != null and ghoul.raise_cost.get("withered_heart", 0) > 0, "ghoul rite costs withered hearts")
	check(MinionManager.minion_db.size() == MinionManager.PLOT_COUNT, "one minion type per graveyard plot")

	# Plots: slot and show the occupant. Harvesting feeds minions nothing —
	# offerings (and later combat) are their only XP.
	check(MinionManager.assign_to_plot("zombie", 0), "zombie takes plot 1")
	check(plots_bar.plot_buttons[0].text == "Z", "plot button shows its occupant")
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
	check(MinionManager.get_passive_bonus("harvest_xp_pct") == 5.0, "slotted passive counts toward the bonus")
	MinionManager.vacate_plot(1)
	check(MinionManager.get_passive_bonus("harvest_xp_pct") == 0.0, "passives sleep while the minion is idle")
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
	check(sigil_tree.rune_centers.size() == 3, "sigil fan lays out every rune (%d)" % sigil_tree.rune_centers.size())
	sigil_tree.rune_selected.emit("carrion_nose")
	check(book.selected_ability.get("zombie", "") == "carrion_nose", "touching a rune selects it")

	# The offering rite: burn materials, feed the minion
	book._switch_chapter("altar")
	check(book.chapter == "altar", "altar tab turns to the altar spread")
	book.altar_target = "zombie"
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
	# A fallen warband is a defeat
	DebugConsole.execute("combat")
	for member in cv.party:
		member["hp"] = 0
	cv._enter_defeat()
	check(cv.fight_state == "defeat", "a fallen warband is a defeat")
	# Bosses enrage as their health quarters break
	DebugConsole.execute("combat boss")
	cv.enemies[0]["hp"] = int(cv.enemies[0]["max_hp"] * 0.4)
	cv._check_boss_enrage(cv.enemies[0])
	check(cv.enemies[0]["segments_broken"] == 2 and cv.enemies[0]["rage"] > 1.0, "broken quarters enrage the boss")
	# Active runes spend once per battle
	cv.used_actives = {"zombie": ["lurch"]}
	check(cv._active_used("zombie", "lurch") and not cv._active_used("zombie", "carrion_nose"),
		"active runes spend once per battle")
	# Confront descends into the crypt now that a warband exists
	GameManager.skills["graverobbing"]["level"] = 20
	gv.update_ui()
	gv.cards[4].action_triggered.emit()
	check(cv.visible and cv.is_boss_fight and "Warden" in cv.enemies[0]["name"], "Confront descends into the crypt")
	GameManager.skills["graverobbing"] = {"level": 1, "xp": 0.0}
	cv.fight_state = "idle"

	get_tree().call_group("view_manager", "switch_view", "graveyard")
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
		GameManager.resolve_harvest(GameManager.find_node_by_id("withered_trees"), false)
	check(TutorialManager.current_step().get("id", "") == "to_quarry", "felling trees advances the tutorial")
	get_tree().call_group("view_manager", "switch_view", "quarry")
	check(TutorialManager.current_step().get("id", "") == "mine", "opening Spelunking advances the tutorial")
	for i in range(TutorialManager.current_step().get("count", 1)):
		GameManager.resolve_harvest(GameManager.find_node_by_id("verdigris_seams"), false)
	check(TutorialManager.current_step().get("id", "") == "tome", "mining stone advances to the tome reward")

	# The Necronomicon chapter of the tutorial
	MinionManager.necronomicon_unlocked = false
	TutorialManager._on_continue_pressed()
	check(TutorialManager.current_step().get("id", "") == "open_book", "taking the tome advances to opening it")
	check(MinionManager.necronomicon_unlocked, "the tome step unlocks the necronomicon")
	check(TutorialManager._resolve_highlight_target() != null, "the circle is highlighted for the player")
	TutorialManager.notify_event("book_opened")
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
