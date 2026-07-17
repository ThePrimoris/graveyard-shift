# MinionManager.gd
# The minion system's home: the raisable roster, per-minion levels and XP,
# skill-tree unlocks, and the four graveyard plots.
#
# The loop: pay a minion's raising rite once, then grow it with offerings at
# the Ritual Altar (and, one day, combat). Levels raise HP/ATK and grant
# 1 skill point each. Passive abilities only function while the minion sits
# in a plot; slotted minions are the warband combat will draw on.
extends Node

signal minions_updated

const MINION_DIRS: Array[String] = ["res://data/minions/"]

const PLOT_COUNT: int = 4
const MAX_LEVEL: int = 50
## Offering rite: minion XP granted per gold of an offered item's sell value.
const OFFERING_XP_PER_GOLD: float = 1.5
## Defeat cost (DEP-2): how long a broken minion must rest before fighting again.
const EXHAUST_MINUTES: float = 5.0

## Gates the Necronomicon — the circle's book UI and the only way to manage
## minions. Granted by the tutorial (finished or skipped); console: `necronomicon on`.
var necronomicon_unlocked: bool = false

## minion_id -> Minion resource, auto-loaded from MINION_DIRS.
var minion_db: Dictionary = {}

## Raised minions: minion_id -> { "level": int, "xp": float, "abilities": Array[String] }
var roster: Dictionary = {}

## Plot occupants by index; "" = empty. One plot per minion.
var plots: Array = ["", "", "", ""]

## Exhaustion (DEP-2's defeat cost): minion_id -> unix timestamp when it can
## fight again. Exhausted minions still work their plot passives — they are
## tired, not gone — but they cannot muster for combat until rested or cured.
var exhausted_until: Dictionary = {}

## Gear (P5 Forge): minion_id -> { slot (int, Gear.GearSlot) -> item_id }.
## Two slots per minion (weapon + trinket), COMBAT ONLY — bonuses feed
## get_hp / get_atk / get_minion_effect, never the gather channels.
var gear: Dictionary = {}

func _ready() -> void:
	_build_minion_database()

func reset_state() -> void:
	roster.clear()
	plots = ["", "", "", ""]
	exhausted_until.clear()
	gear.clear()
	necronomicon_unlocked = false
	minions_updated.emit()

# --- Database ---

func _build_minion_database() -> void:
	minion_db.clear()
	for dir_path in MINION_DIRS:
		var dir = DirAccess.open(dir_path)
		if not dir:
			push_warning("MinionManager: Could not open resource directory: " + dir_path)
			continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# Exported builds list text resources as "<name>.tres.remap".
			var res_file = file_name.trim_suffix(".remap")
			if not dir.current_is_dir() and res_file.ends_with(".tres"):
				var res = load(dir_path + res_file)
				if res is Minion and res.id != "":
					minion_db[res.id] = res
			file_name = dir.get_next()
		dir.list_dir_end()

func find_minion_by_id(minion_id: String) -> Minion:
	return minion_db.get(minion_id, null)

## Minion ids in display order: sort_order first, then name.
## Every roster/book/picker listing should use this, not alphabetical ids.
func sorted_ids(only_raised: bool = false) -> Array:
	var ids: Array = []
	for minion_id in minion_db:
		if only_raised and not roster.has(minion_id): continue
		ids.append(minion_id)
	ids.sort_custom(func(a, b):
		var ma: Minion = minion_db[a]
		var mb: Minion = minion_db[b]
		if ma.sort_order != mb.sort_order:
			return ma.sort_order < mb.sort_order
		return ma.name < mb.name)
	return ids

# --- Raising ---

func is_raised(minion_id: String) -> bool:
	return roster.has(minion_id)

func can_afford_raise(minion: Minion) -> bool:
	for item_id in minion.raise_cost:
		if minion.raise_cost[item_id] > 0 and InventoryManager.get_item_count(item_id) < minion.raise_cost[item_id]:
			return false
	return true

## Pays the raising rite and adds the minion to the roster.
func raise_minion(minion_id: String) -> bool:
	var minion = find_minion_by_id(minion_id)
	if minion == null or is_raised(minion_id) or not can_afford_raise(minion):
		return false
	for item_id in minion.raise_cost:
		if minion.raise_cost[item_id] > 0:
			InventoryManager.remove_item(item_id, minion.raise_cost[item_id])
	roster[minion_id] = {"level": 1, "xp": 0.0, "abilities": []}
	StatsManager.bump(StatsManager.STAT_MINIONS_RAISED)
	NotificationManager.show_item("%s rises from the earth!" % minion.name, 1)
	minions_updated.emit()
	TutorialManager.notify_event(Ids.EVENT_MINION_RAISED)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

# --- Levels & XP ---

## XP to advance FROM `level`. Minions grow only on altar offerings (and,
## later, combat), so this curve is tuned as a deliberate slow burn.
func get_xp_needed(level: int) -> float:
	return floor(60.0 * pow(level, 1.6))

func add_xp(minion_id: String, amount: float) -> void:
	if not roster.has(minion_id) or amount <= 0.0: return
	var state = roster[minion_id]
	if state["level"] >= MAX_LEVEL: return
	state["xp"] += amount
	var needed = get_xp_needed(state["level"])
	var leveled := false
	while state["xp"] >= needed and state["level"] < MAX_LEVEL:
		state["xp"] -= needed
		state["level"] += 1
		leveled = true
		needed = get_xp_needed(state["level"])
	if state["level"] >= MAX_LEVEL:
		state["xp"] = 0.0
	if leveled:
		var minion = find_minion_by_id(minion_id)
		if minion:
			NotificationManager.show_item("%s reached level %d" % [minion.name, state["level"]], 1)
		minions_updated.emit()

func get_level(minion_id: String) -> int:
	return roster[minion_id]["level"] if roster.has(minion_id) else 0

func get_hp(minion_id: String) -> int:
	var minion = find_minion_by_id(minion_id)
	if minion == null: return 0
	var level = maxi(get_level(minion_id), 1)
	# Gear HP is flat, added before the % passives so runes amplify gear too.
	var base = minion.base_hp + (level - 1) * minion.hp_per_level + _gear_hp(minion_id)
	return int(round(base * (1.0 + get_minion_effect(minion_id, Ids.MINION_HP_PCT) / 100.0)))

func get_atk(minion_id: String) -> float:
	var minion = find_minion_by_id(minion_id)
	if minion == null: return 0.0
	var level = maxi(get_level(minion_id), 1)
	var base = minion.base_atk + (level - 1) * minion.atk_per_level + _gear_atk(minion_id)
	return base * (1.0 + get_minion_effect(minion_id, Ids.MINION_ATK_PCT) / 100.0)

## Sum of one passive effect across a SINGLE minion's own unlocked abilities
## AND its worn gear (P5 trinket channels). Combat effects buff the minion
## itself, so they read per-minion — unlike get_passive_bonus, which
## aggregates the whole slotted warband for gather.
func get_minion_effect(minion_id: String, effect: String) -> float:
	if not roster.has(minion_id): return 0.0
	var minion = find_minion_by_id(minion_id)
	if minion == null: return 0.0
	var total := 0.0
	for ability_id in roster[minion_id]["abilities"]:
		var ability = minion.find_ability(ability_id)
		if ability and ability.kind == MinionAbility.Kind.PASSIVE and ability.effect == effect:
			total += ability.magnitude
	for slot in [Gear.GearSlot.WEAPON, Gear.GearSlot.TRINKET]:
		var piece = get_gear(minion_id, slot)
		if piece and piece.passive_effect == effect:
			total += piece.passive_magnitude
	return total

# --- Skill tree ---
# 1 point per level past the first; the tree UI arrives next pass, but the
# manager already enforces costs and prerequisites.

func get_skill_points(minion_id: String) -> int:
	if not roster.has(minion_id): return 0
	var minion = find_minion_by_id(minion_id)
	var spent := 0
	for ability_id in roster[minion_id]["abilities"]:
		var ability = minion.find_ability(ability_id) if minion else null
		if ability: spent += ability.cost
	return (roster[minion_id]["level"] - 1) - spent

func has_ability(minion_id: String, ability_id: String) -> bool:
	return roster.has(minion_id) and roster[minion_id]["abilities"].has(ability_id)

func can_unlock_ability(minion_id: String, ability_id: String) -> bool:
	var minion = find_minion_by_id(minion_id)
	if minion == null or not roster.has(minion_id): return false
	var ability = minion.find_ability(ability_id)
	if ability == null or has_ability(minion_id, ability_id): return false
	if get_skill_points(minion_id) < ability.cost: return false
	for prereq in ability.prerequisites:
		if not has_ability(minion_id, prereq): return false
	return true

func unlock_ability(minion_id: String, ability_id: String) -> bool:
	if not can_unlock_ability(minion_id, ability_id): return false
	roster[minion_id]["abilities"].append(ability_id)
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Sum of one passive effect across every slotted minion's unlocked abilities.
## e.g. get_passive_bonus("harvest_xp_pct") -> 9.0 for +9% harvest XP.
func get_passive_bonus(effect: String) -> float:
	var total := 0.0
	var seen: Array = []
	for minion_id in plots:
		if minion_id == "" or seen.has(minion_id): continue
		seen.append(minion_id)
		var minion = find_minion_by_id(minion_id)
		if minion == null or not roster.has(minion_id): continue
		for ability_id in roster[minion_id]["abilities"]:
			var ability = minion.find_ability(ability_id)
			if ability and ability.kind == MinionAbility.Kind.PASSIVE and ability.effect == effect:
				total += ability.magnitude
	return total

# --- Gear (P5 Forge: weapon + trinket per minion, combat only) ---

## The Gear item a minion wears in `slot`, or null.
func get_gear(minion_id: String, slot: int) -> Gear:
	var worn = gear.get(minion_id, {})
	var item = GameManager.find_item_by_id(str(worn.get(slot, "")))
	return item if item is Gear else null

## Equips a piece of gear from the pack into its slot; whatever was worn
## there returns to the pack. Fails if the pack can't hold the swap-out.
func equip_gear(minion_id: String, piece: Gear) -> bool:
	if piece == null or not is_raised(minion_id): return false
	if InventoryManager.get_item_count(piece.id) <= 0: return false
	var previous = get_gear(minion_id, piece.slot)
	if previous != null and not InventoryManager.has_room_for(previous):
		NotificationManager.show_item("Inventory full — cannot swap gear", 1)
		return false
	InventoryManager.remove_item(piece.id, 1)
	if previous != null:
		InventoryManager.add_item(previous, 1)
	if not gear.has(minion_id):
		gear[minion_id] = {}
	gear[minion_id][piece.slot] = piece.id
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Returns the worn piece to the pack and bares the slot.
func unequip_gear(minion_id: String, slot: int) -> bool:
	var piece = get_gear(minion_id, slot)
	if piece == null: return false
	if not InventoryManager.has_room_for(piece):
		NotificationManager.show_item("Inventory full — cannot unequip", 1)
		return false
	gear[minion_id].erase(slot)
	InventoryManager.add_item(piece, 1)
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Sum of one stat across a minion's worn gear.
func _gear_atk(minion_id: String) -> float:
	var total := 0.0
	for slot in [Gear.GearSlot.WEAPON, Gear.GearSlot.TRINKET]:
		var piece = get_gear(minion_id, slot)
		if piece: total += piece.atk_bonus
	return total

func _gear_hp(minion_id: String) -> int:
	var total := 0
	for slot in [Gear.GearSlot.WEAPON, Gear.GearSlot.TRINKET]:
		var piece = get_gear(minion_id, slot)
		if piece: total += piece.hp_bonus
	return total

# --- Exhaustion (DEP-2: defeat has a cost) ---

func is_exhausted(minion_id: String) -> bool:
	return exhaustion_left(minion_id) > 0.0

## Seconds of rest remaining, or 0 when battle-ready.
func exhaustion_left(minion_id: String) -> float:
	var until = float(exhausted_until.get(minion_id, 0.0))
	return maxf(0.0, until - Time.get_unix_time_from_system())

func exhaust(minion_id: String, minutes: float = EXHAUST_MINUTES) -> void:
	if not is_raised(minion_id): return
	# Corpse-Candle (incense): while it burns, the fallen rest quicker.
	var haste = GameManager.get_buff_bonus(Ids.EFFECT_EXHAUST_HASTE_PCT)
	if haste > 0.0:
		minutes *= maxf(0.1, 1.0 - haste / 100.0)
	exhausted_until[minion_id] = Time.get_unix_time_from_system() + minutes * 60.0
	minions_updated.emit()

func cure_exhaustion(minion_id: String) -> void:
	if exhausted_until.erase(minion_id):
		minions_updated.emit()

## Shortens every current rest by pct% (lighting a Corpse-Candle also stirs
## minions already resting, not just those who fall while it burns).
func hasten_exhaustion(pct: float) -> void:
	if pct <= 0.0: return
	var now = Time.get_unix_time_from_system()
	var changed := false
	for minion_id in exhausted_until.keys():
		var left = float(exhausted_until[minion_id]) - now
		if left <= 0.0: continue
		exhausted_until[minion_id] = now + left * maxf(0.0, 1.0 - pct / 100.0)
		changed = true
	if changed:
		minions_updated.emit()

## Raised minion ids fit to muster (not exhausted), in display order.
func battle_ready_ids() -> Array:
	var ids: Array = []
	for minion_id in sorted_ids(true):
		if not is_exhausted(minion_id):
			ids.append(minion_id)
	return ids

# --- The Offering Rite (Ritual Altar) ---

## XP one unit of this item yields when offered at the altar. An explicit
## offering_value on the item wins; otherwise sellable items derive it from
## their sell_value (unsellable items with no offering_value can't be offered).
func get_offering_xp(item: Item) -> float:
	if item == null: return 0.0
	# Mausoleum (P4): built tiers amplify every offering.
	var potency := 1.0 + GroundsManager.get_bonus(Ids.EFFECT_OFFERING_PCT) / 100.0
	if item.offering_value >= 0:
		return float(item.offering_value) * OFFERING_XP_PER_GOLD * potency
	if not item.is_sellable: return 0.0
	return maxf(item.sell_value, 1.0) * OFFERING_XP_PER_GOLD * potency

## Burns `amount` of an item from the inventory and feeds the XP to a raised
## minion. Returns the XP granted (0 = the rite failed).
func offer_materials(minion_id: String, item_id: String, amount: int) -> float:
	if not is_raised(minion_id) or amount <= 0: return 0.0
	var item = GameManager.find_item_by_id(item_id)
	if item == null or item is ToolData: return 0.0
	var xp_each = get_offering_xp(item)
	if xp_each <= 0.0: return 0.0
	var held = InventoryManager.get_item_count(item_id)
	var burn = mini(amount, held)
	if burn <= 0: return 0.0
	InventoryManager.remove_item(item_id, burn)
	var total = xp_each * burn
	StatsManager.bump(StatsManager.STAT_OFFERINGS)
	add_xp(minion_id, total)
	minions_updated.emit()
	TutorialManager.notify_event(Ids.EVENT_OFFERING_MADE)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return total

# --- Plots ---

func plot_of(minion_id: String) -> int:
	return plots.find(minion_id)

## Slots a raised minion into a plot, vacating any plot it already holds.
func assign_to_plot(minion_id: String, plot_index: int) -> bool:
	if plot_index < 0 or plot_index >= PLOT_COUNT: return false
	if not is_raised(minion_id): return false
	var previous = plot_of(minion_id)
	if previous != -1:
		plots[previous] = ""
	plots[plot_index] = minion_id
	minions_updated.emit()
	TutorialManager.notify_event(Ids.EVENT_MINION_SLOTTED)
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

func vacate_plot(plot_index: int) -> void:
	if plot_index < 0 or plot_index >= PLOT_COUNT: return
	if plots[plot_index] == "": return
	plots[plot_index] = ""
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

# --- Save / Load ---

func get_save_data() -> Dictionary:
	# Gear slot keys become strings for JSON round-tripping.
	var gear_out: Dictionary = {}
	for minion_id in gear:
		gear_out[minion_id] = {}
		for slot in gear[minion_id]:
			gear_out[minion_id][str(slot)] = gear[minion_id][slot]
	return {
		"roster": roster.duplicate(true),
		"plots": plots.duplicate(),
		"necronomicon_unlocked": necronomicon_unlocked,
		"exhausted_until": exhausted_until.duplicate(),
		"gear": gear_out,
	}

func restore_from_save(data: Dictionary) -> void:
	roster.clear()
	var saved_roster = data.get("roster", {})
	for minion_id in saved_roster:
		if not minion_db.has(minion_id): continue
		var s = saved_roster[minion_id]
		var abilities: Array = []
		for a in s.get("abilities", []):
			abilities.append(str(a))
		roster[minion_id] = {
			"level": clampi(int(s.get("level", 1)), 1, MAX_LEVEL),
			"xp": maxf(float(s.get("xp", 0.0)), 0.0),
			"abilities": abilities,
		}
	plots = ["", "", "", ""]
	var saved_plots = data.get("plots", [])
	for i in range(mini(saved_plots.size(), PLOT_COUNT)):
		var occupant = str(saved_plots[i])
		if occupant != "" and roster.has(occupant) and plots.find(occupant) == -1:
			plots[i] = occupant
	necronomicon_unlocked = bool(data.get("necronomicon_unlocked", false))
	exhausted_until.clear()
	var saved_exhaustion = data.get("exhausted_until", {})
	for minion_id in saved_exhaustion:
		if roster.has(minion_id):
			exhausted_until[minion_id] = float(saved_exhaustion[minion_id])
	gear.clear()
	var saved_gear = data.get("gear", {})
	for minion_id in saved_gear:
		if not roster.has(minion_id): continue
		for slot_key in saved_gear[minion_id]:
			var item = GameManager.find_item_by_id(str(saved_gear[minion_id][slot_key]))
			if item is Gear:
				if not gear.has(minion_id):
					gear[minion_id] = {}
				gear[minion_id][int(slot_key)] = item.id
	minions_updated.emit()
