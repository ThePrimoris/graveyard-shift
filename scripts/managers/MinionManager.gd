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

## Gear (P5 Forge): minion_id -> { slot_key (String) -> item_id }.
## Five named slots per minion (two relics + three trinkets), COMBAT ONLY —
## bonuses feed get_hp / get_atk / get_minion_effect, never the gather channels.
## Relics are unique-equipped: a minion may bear only one copy of a relic.
var gear: Dictionary = {}

const RELIC_SLOTS: Array[String] = ["relic_0", "relic_1"]
const TRINKET_SLOTS: Array[String] = ["trinket_0", "trinket_1", "trinket_2"]
const GEAR_SLOTS: Array[String] = ["relic_0", "relic_1", "trinket_0", "trinket_1", "trinket_2"]

## Deployment (DEP-8): one gathering minion per skill, working a node's loot
## tables at reduced pace into its own satchel. Exclusive with the plots:
## slotted = fighting, deployed = gathering; never both.
const DEPLOY_SKILLS: Array[String] = [Ids.SKILL_GRAVEROBBING, Ids.SKILL_LUMBERING, Ids.SKILL_SPELUNKING]
const DEPLOY_RATE_BASE: float = 0.5     # fraction of the node's base pace
const DEPLOY_CARRY_BASE: int = 30       # satchel size in total units
const DEPLOY_CARRY_PER_TIER: int = 10   # added per Waystation tier built
const DEPLOY_XP_FACTOR: float = 0.5     # minion XP per harvest = node base_xp * this

## skill_key -> {"minion_id": String, "node_id": String,
##   "carry": {item_id: int}, "progress": float, "damage": float}
var deployments: Dictionary = {}

var _deploy_tick_accum: float = 0.0

func _ready() -> void:
	_build_minion_database()

func reset_state() -> void:
	roster.clear()
	plots = ["", "", "", ""]
	exhausted_until.clear()
	gear.clear()
	deployments.clear()
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
	for slot_key in GEAR_SLOTS:
		var piece = get_gear(minion_id, slot_key)
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

# --- Gear (P5 Forge: 2 relics + 3 trinkets per minion, combat only) ---

## The named slots a gear category can occupy.
func slots_for_category(category: int) -> Array[String]:
	return RELIC_SLOTS if category == Gear.GearSlot.RELIC else TRINKET_SLOTS

## The Gear item a minion wears in the named slot, or null.
func get_gear(minion_id: String, slot_key: String) -> Gear:
	var worn = gear.get(minion_id, {})
	var item = GameManager.find_item_by_id(str(worn.get(slot_key, "")))
	return item if item is Gear else null

## Equips a piece of gear from the pack. With no slot_key, the first empty
## slot of the piece's category is used (or the first slot, swapping out its
## occupant, when all are full). Whatever was worn returns to the pack; fails
## if the pack can't hold the swap-out. Relics are unique-equipped.
func equip_gear(minion_id: String, piece: Gear, slot_key: String = "") -> bool:
	if piece == null or not is_raised(minion_id): return false
	if InventoryManager.get_item_count(piece.id) <= 0: return false
	var slots = slots_for_category(piece.slot)
	if slot_key == "":
		slot_key = slots[0]
		for candidate in slots:
			if get_gear(minion_id, candidate) == null:
				slot_key = candidate
				break
	elif not slots.has(slot_key):
		return false
	if piece.slot == Gear.GearSlot.RELIC:
		for other_key in RELIC_SLOTS:
			if other_key == slot_key: continue
			var worn = get_gear(minion_id, other_key)
			if worn != null and worn.id == piece.id:
				NotificationManager.show_item("Only one %s may be borne" % piece.name, 1)
				return false
	var previous = get_gear(minion_id, slot_key)
	if previous != null and not InventoryManager.has_room_for(previous):
		NotificationManager.show_item("Inventory full — cannot swap gear", 1)
		return false
	InventoryManager.remove_item(piece.id, 1)
	if previous != null:
		InventoryManager.add_item(previous, 1)
	if not gear.has(minion_id):
		gear[minion_id] = {}
	gear[minion_id][slot_key] = piece.id
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Returns the worn piece to the pack and bares the slot.
func unequip_gear(minion_id: String, slot_key: String) -> bool:
	var piece = get_gear(minion_id, slot_key)
	if piece == null: return false
	if not InventoryManager.has_room_for(piece):
		NotificationManager.show_item("Inventory full — cannot unequip", 1)
		return false
	gear[minion_id].erase(slot_key)
	InventoryManager.add_item(piece, 1)
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Sum of one stat across a minion's worn gear.
func _gear_atk(minion_id: String) -> float:
	var total := 0.0
	for slot_key in GEAR_SLOTS:
		var piece = get_gear(minion_id, slot_key)
		if piece: total += piece.atk_bonus
	return total

func _gear_hp(minion_id: String) -> int:
	var total := 0
	for slot_key in GEAR_SLOTS:
		var piece = get_gear(minion_id, slot_key)
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
## Slotted and deployed are exclusive: slotting a deployed minion recalls it
## first (and fails if the recall can't empty its satchel into a full pack).
func assign_to_plot(minion_id: String, plot_index: int) -> bool:
	if plot_index < 0 or plot_index >= PLOT_COUNT: return false
	if not is_raised(minion_id): return false
	var afield = deployed_skill_of(minion_id)
	if afield != "" and not recall(afield):
		return false
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

# --- Deployment (DEP-8: the rite of deployment) ---
# A deployed minion works one harvest node's loot tables at reduced pace,
# banking into its own capped satchel until the player collects. It gains
# minion XP but NEVER player skill XP, and its pace is deliberately
# independent of the player's tools/levels/buffs so offline math stays
# deterministic. Deployment never touches GameManager.register_activity —
# it is the minion's labor, not the player's action.

func deployment_for(skill_key: String) -> Dictionary:
	return deployments.get(skill_key, {})

## The skill a minion is deployed under, or "" when it isn't afield.
func deployed_skill_of(minion_id: String) -> String:
	for skill_key in deployments:
		if str(deployments[skill_key].get("minion_id", "")) == minion_id:
			return skill_key
	return ""

func is_deployed(minion_id: String) -> bool:
	return deployed_skill_of(minion_id) != ""

## Satchel size in total units; the Waystation's built tiers extend it.
func carry_capacity() -> int:
	return DEPLOY_CARRY_BASE + DEPLOY_CARRY_PER_TIER * GroundsManager.get_level("waystation")

## Total units currently in a deployment's satchel.
func carry_count(skill_key: String) -> int:
	var total := 0
	for item_id in deployment_for(skill_key).get("carry", {}):
		total += int(deployments[skill_key]["carry"][item_id])
	return total

## Seconds per harvest for a deployed minion: the node's base pace slowed to
## DEPLOY_RATE_BASE, quickened by Waystation tiers. Never reads
## get_gather_modifiers — a minion's pace must not swing with the player.
func deploy_duration(node: HarvestNode) -> float:
	var rate = DEPLOY_RATE_BASE * (1.0 + GroundsManager.get_bonus(Ids.EFFECT_MINION_GATHER_PCT) / 100.0)
	return node.base_duration / maxf(rate, 0.01)

## Exhausted minions cannot muster for deployment either — the defeat cost
## holds. (No mid-deployment exhaustion exists: deployed minions never fight.)
func can_deploy(minion_id: String, node: HarvestNode) -> bool:
	if node == null or not is_raised(minion_id): return false
	if node.is_boss: return false
	if is_exhausted(minion_id): return false
	return GameManager.is_node_accessible(node)

## Sends a minion afield to a node, vacating any plot it holds (slotted and
## deployed are exclusive). One deployment per gathering skill.
func deploy(minion_id: String, node_id: String) -> bool:
	var node = GameManager.find_node_by_id(node_id)
	if not can_deploy(minion_id, node): return false
	var skill_key = GameManager.get_skill_key(node)
	if not DEPLOY_SKILLS.has(skill_key): return false
	var current = deployment_for(skill_key)
	if not current.is_empty() and str(current.get("minion_id", "")) != minion_id:
		var occupant = find_minion_by_id(str(current.get("minion_id", "")))
		NotificationManager.show_item("Recall %s first — one minion works each ground" \
			% (occupant.name if occupant else "the deployed minion"), 1)
		return false
	var elsewhere = deployed_skill_of(minion_id)
	if elsewhere != "" and elsewhere != skill_key:
		NotificationManager.show_item("Recall it from its post first", 1)
		return false
	var plot = plot_of(minion_id)
	if plot != -1:
		plots[plot] = ""
	# Re-deploying the same minion to another node keeps its satchel; the
	# banked bar and break damage belong to the old node and reset.
	deployments[skill_key] = {
		"minion_id": minion_id, "node_id": node_id,
		"carry": current.get("carry", {}), "progress": 0.0, "damage": 0.0,
	}
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Empties a deployment's satchel into the pack. Overflow past a full pack
## stays in the satchel — nothing is ever silently lost. Returns units moved.
func collect(skill_key: String) -> int:
	var dep = deployment_for(skill_key)
	if dep.is_empty(): return 0
	var carry: Dictionary = dep["carry"]
	var moved := 0
	for item_id in carry.keys():
		var item = GameManager.find_item_by_id(str(item_id))
		if item == null:
			carry.erase(item_id)
			continue
		var amount = int(carry[item_id])
		var overflow = InventoryManager.add_item(item, amount)
		moved += amount - overflow
		if overflow > 0:
			carry[item_id] = overflow
		else:
			carry.erase(item_id)
	if moved > 0:
		var minion = find_minion_by_id(str(dep.get("minion_id", "")))
		NotificationManager.show_item("%s hands over %d gathered materials" \
			% [minion.name if minion else "The minion", moved], 1)
		minions_updated.emit()
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return moved

## Collects, then ends the deployment. Fails (deployment stands) when the
## pack can't hold what the satchel still carries.
func recall(skill_key: String) -> bool:
	var dep = deployment_for(skill_key)
	if dep.is_empty(): return false
	collect(skill_key)
	if not dep["carry"].is_empty():
		NotificationManager.show_item("Inventory full — cannot recall with a laden satchel", 1)
		return false
	deployments.erase(skill_key)
	minions_updated.emit()
	get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")
	return true

## Runs `seconds` of one deployment's labor. Mutates carry/progress/damage.
## Returns {"harvests": int, "gained": int, "filled": bool}.
func _work_deployment(skill_key: String, seconds: float) -> Dictionary:
	var result = {"harvests": 0, "gained": 0, "filled": false}
	var dep = deployment_for(skill_key)
	if dep.is_empty(): return result
	var node = GameManager.find_node_by_id(str(dep.get("node_id", "")))
	var minion_id = str(dep.get("minion_id", ""))
	if node == null: return result
	var dur = deploy_duration(node)
	if dur <= 0.0: return result
	var cap = carry_capacity()
	var carry: Dictionary = dep["carry"]
	dep["progress"] = float(dep["progress"]) + seconds
	while dep["progress"] >= dur:
		if carry_count(skill_key) >= cap:
			result["filled"] = true
			# A stalled minion holds at most one banked bar of progress.
			dep["progress"] = minf(float(dep["progress"]), dur)
			break
		dep["progress"] = float(dep["progress"]) - dur
		var gains: Dictionary = {}
		if GameManager.is_breakable(node):
			var hit = GameManager.roll_chance_table(node.hit_pool)
			if hit:
				gains[hit.item.id] = randi_range(hit.min_amount, maxi(hit.min_amount, hit.max_amount))
			dep["damage"] = float(dep["damage"]) + GameManager.per_hit_damage(node)
			if float(dep["damage"]) >= 0.999:
				var haul = GameManager.roll_drop_table(node.break_pool)
				if haul:
					gains[haul.item.id] = gains.get(haul.item.id, 0) \
						+ randi_range(haul.min_amount, maxi(haul.min_amount, haul.max_amount))
				dep["damage"] = 0.0
		else:
			gains = GameManager.roll_plain_loot(node)
		for item_id in gains:
			var room = cap - carry_count(skill_key)
			if room <= 0: break
			var add = mini(int(gains[item_id]), room)
			carry[item_id] = int(carry.get(item_id, 0)) + add
			result["gained"] += add
		# Minion XP only — deployed labor never grants player skill XP.
		add_xp(minion_id, node.base_xp * DEPLOY_XP_FACTOR)
		result["harvests"] += 1
	if carry_count(skill_key) >= cap:
		result["filled"] = true
	return result

## Offline pass: runs every deployment for the (already capped) seconds.
## Gains land in the satchels — collecting them is the return-visit loop.
func accrue_deployments(seconds: float) -> Dictionary:
	var total = {"gained": 0, "harvests": 0, "any_full": false}
	if seconds <= 0.0: return total
	for skill_key in deployments.keys():
		var r = _work_deployment(skill_key, seconds)
		total["gained"] += int(r["gained"])
		total["harvests"] += int(r["harvests"])
		if bool(r["filled"]): total["any_full"] = true
	if total["gained"] > 0:
		minions_updated.emit()
	return total

## The online tick: deployed minions keep working while the game runs.
func _process(delta: float) -> void:
	if deployments.is_empty(): return
	_deploy_tick_accum += delta
	if _deploy_tick_accum < 1.0: return
	var seconds = _deploy_tick_accum
	_deploy_tick_accum = 0.0
	var banked := false
	for skill_key in deployments.keys():
		var was_full = carry_count(skill_key) >= carry_capacity()
		var r = _work_deployment(skill_key, seconds)
		if int(r["gained"]) > 0:
			banked = true
		if bool(r["filled"]) and not was_full:
			var dep = deployments[skill_key]
			var minion = find_minion_by_id(str(dep.get("minion_id", "")))
			var node = GameManager.find_node_by_id(str(dep.get("node_id", "")))
			NotificationManager.show_item("%s's satchel is full at the %s" \
				% [minion.name if minion else "A minion", node.name if node else "grounds"], 1)
	if banked:
		minions_updated.emit()
		get_tree().call_group(Ids.GROUP_UI_UPDATES, "update_ui")

# --- Save / Load ---

func get_save_data() -> Dictionary:
	return {
		"roster": roster.duplicate(true),
		"plots": plots.duplicate(),
		"necronomicon_unlocked": necronomicon_unlocked,
		"exhausted_until": exhausted_until.duplicate(),
		"gear": gear.duplicate(true),
		"deployments": deployments.duplicate(true),
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
			# Only named slots holding a category-matching piece survive
			# (guards hand-edited or corrupt saves).
			if not GEAR_SLOTS.has(str(slot_key)): continue
			var item = GameManager.find_item_by_id(str(saved_gear[minion_id][slot_key]))
			if item is Gear and slots_for_category(item.slot).has(str(slot_key)):
				if not gear.has(minion_id):
					gear[minion_id] = {}
				gear[minion_id][str(slot_key)] = item.id
	deployments.clear()
	var saved_deployments = data.get("deployments", {})
	for skill_key in saved_deployments:
		if not DEPLOY_SKILLS.has(str(skill_key)): continue
		var d = saved_deployments[skill_key]
		var minion_id = str(d.get("minion_id", ""))
		var node = GameManager.find_node_by_id(str(d.get("node_id", "")))
		if not roster.has(minion_id) or node == null: continue
		if GameManager.get_skill_key(node) != str(skill_key): continue
		var carry: Dictionary = {}
		var saved_carry = d.get("carry", {})
		for item_id in saved_carry:
			if GameManager.find_item_by_id(str(item_id)) != null and int(saved_carry[item_id]) > 0:
				carry[str(item_id)] = int(saved_carry[item_id])
		# Slotted and deployed are exclusive; on a conflicting save, deployment wins.
		var plot = plots.find(minion_id)
		if plot != -1:
			plots[plot] = ""
		deployments[str(skill_key)] = {
			"minion_id": minion_id,
			"node_id": node.id,
			"carry": carry,
			"progress": maxf(float(d.get("progress", 0.0)), 0.0),
			"damage": maxf(float(d.get("damage", 0.0)), 0.0),
		}
	minions_updated.emit()
