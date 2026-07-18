# InventoryManager.gd
extends Node

signal inventory_updated

# The backpack is TABS of slots: one tab to start, whole tabs bought from the
# shop, and the Ossuary widens EVERY tab it owns by its built slot bonus.
const TAB_BASE_SLOTS: int = 40
const BASE_TABS: int = 1
const MAX_PURCHASED_TABS: int = 3
## Gold price of each successive shop tab.
const TAB_COSTS: Array[int] = [2000, 12000, 50000]
## Slot-grid columns; the view reads this so rows stay full at every width.
const GRID_COLUMNS: int = 10

var slots: Array = []
var purchased_tabs: int = 0
## Player-given tab names (index = tab). Missing/empty entries fall back to
## "Tab N". Persisted by SaveManager.
var tab_names: Array = []

func _ready() -> void:
	slots.resize(TAB_BASE_SLOTS)
	slots.fill(null)

func tab_count() -> int:
	return BASE_TABS + purchased_tabs

## Slots per tab: the base width plus the Ossuary's built bonus.
func page_size() -> int:
	return TAB_BASE_SLOTS + GroundsManager.get_inventory_slot_bonus()

## The player's label for a tab, or "Tab N" when unnamed.
func tab_name(page: int) -> String:
	if page < tab_names.size() and String(tab_names[page]).strip_edges() != "":
		return String(tab_names[page])
	return "Tab %d" % (page + 1)

func set_tab_name(page: int, new_name: String) -> void:
	while tab_names.size() <= page:
		tab_names.append("")
	tab_names[page] = new_name.strip_edges().left(16)
	inventory_updated.emit()

func get_next_tab_cost() -> int:
	if purchased_tabs >= MAX_PURCHASED_TABS: return 0
	return TAB_COSTS[purchased_tabs]

func can_purchase_tab() -> bool:
	return purchased_tabs < MAX_PURCHASED_TABS and GameManager.gold_coins >= get_next_tab_cost()

func purchase_tab() -> bool:
	if not can_purchase_tab(): return false
	GameManager.gold_coins -= get_next_tab_cost()
	purchased_tabs += 1
	refresh_capacity()
	return true

## Grows the slot array to match tabs x tab width; never destroys occupied
## slots (an over-capacity tail from an old save empties out naturally).
func refresh_capacity() -> void:
	var target = tab_count() * page_size()
	while slots.size() < target:
		slots.append(null)
	while slots.size() > target and slots[slots.size() - 1] == null:
		slots.pop_back()
	inventory_updated.emit()

## Empties the whole inventory back to base capacity (Settings hard reset).
func reset_state() -> void:
	purchased_tabs = 0
	tab_names.clear()
	slots.clear()
	slots.resize(TAB_BASE_SLOTS)
	slots.fill(null)
	inventory_updated.emit()

## True when `item` could be added without losing it.
func has_room_for(item: Item) -> bool:
	for slot in slots:
		if slot == null:
			return true
		if item.is_stackable and slot["item"].id == item.id and slot["quantity"] < slot["item"].max_stack:
			return true
	return false

func add_item(item: Item, amount: int = 1) -> int:
	StatsManager.mark_item_discovered(item.id)
	var remaining = amount

	for i in range(slots.size()):
		if slots[i] != null and slots[i]["item"].id == item.id:
			var current_stack = slots[i]["quantity"]
			var space_left = slots[i]["item"].max_stack - current_stack

			if space_left > 0:
				var to_add = min(remaining, space_left)
				slots[i]["quantity"] += to_add
				remaining -= to_add
				if remaining <= 0:
					inventory_updated.emit()
					return 0

	for i in range(slots.size()):
		if slots[i] == null:
			var to_add = min(remaining, item.max_stack)
			slots[i] = {"item": item, "quantity": to_add}
			remaining -= to_add
			if remaining <= 0:
				inventory_updated.emit()
				return 0

	inventory_updated.emit()
	return remaining

func swap_slots(from_index: int, to_index: int) -> void:
	var temp = slots[to_index]
	slots[to_index] = slots[from_index]
	slots[from_index] = temp
	inventory_updated.emit()

## Drops one slot onto another: same-item stacks merge (up to max_stack),
## anything else swaps. The backpack's drag-and-drop lands here.
func merge_or_swap(from_index: int, to_index: int) -> void:
	if from_index == to_index: return
	if from_index < 0 or from_index >= slots.size(): return
	if to_index < 0 or to_index >= slots.size(): return
	var a = slots[from_index]
	var b = slots[to_index]
	if a != null and b != null and a["item"].id == b["item"].id and a["item"].is_stackable:
		var space: int = a["item"].max_stack - int(b["quantity"])
		if space > 0:
			var moved: int = mini(space, int(a["quantity"]))
			b["quantity"] = int(b["quantity"]) + moved
			a["quantity"] = int(a["quantity"]) - moved
			if int(a["quantity"]) <= 0:
				slots[from_index] = null
			inventory_updated.emit()
			return
	swap_slots(from_index, to_index)

## Splits `amount` off a stack into the first empty slot (same tab first,
## then anywhere). False when the split can't happen (no room, bad amount).
func split_stack(index: int, amount: int) -> bool:
	if index < 0 or index >= slots.size(): return false
	var slot = slots[index]
	if slot == null or amount <= 0 or int(slot["quantity"]) <= amount:
		return false
	var empty := _first_empty_slot(index)
	if empty == -1:
		return false
	slot["quantity"] = int(slot["quantity"]) - amount
	slots[empty] = {"item": slot["item"], "quantity": amount}
	inventory_updated.emit()
	return true

## First empty slot, preferring the tab `near_index` sits on.
func _first_empty_slot(near_index: int) -> int:
	var page_start := (near_index / page_size()) * page_size()
	for i in range(page_start, slots.size()):
		if slots[i] == null: return i
	for i in range(page_start):
		if slots[i] == null: return i
	return -1

## Drops a dragged slot onto a tab button: merge into that tab's stacks
## first, then take its first empty slot. True if anything moved.
func move_to_page(from_index: int, page: int) -> bool:
	var start := page * page_size()
	var end := mini(start + page_size(), slots.size())
	if from_index < 0 or from_index >= slots.size() or slots[from_index] == null:
		return false
	if from_index >= start and from_index < end:
		return false
	var moving = slots[from_index]
	var moved_any := false
	if moving["item"].is_stackable:
		for i in range(start, end):
			var s = slots[i]
			if s != null and s["item"].id == moving["item"].id:
				var space: int = s["item"].max_stack - int(s["quantity"])
				if space > 0:
					var moved: int = mini(space, int(moving["quantity"]))
					s["quantity"] = int(s["quantity"]) + moved
					moving["quantity"] = int(moving["quantity"]) - moved
					moved_any = true
					if int(moving["quantity"]) <= 0:
						slots[from_index] = null
						inventory_updated.emit()
						return true
	for i in range(start, end):
		if slots[i] == null:
			slots[i] = moving
			slots[from_index] = null
			inventory_updated.emit()
			return true
	if moved_any:
		inventory_updated.emit()
	return moved_any

## Sorts and consolidates the slot range [start, end): partial stacks of the
## same item merge, then everything packs from `start` ordered by `key` —
## "name", "count" (largest stacks first) or "value" (priciest first).
func sort_range(start: int, end: int, key: String) -> void:
	start = maxi(start, 0)
	end = mini(end, slots.size())
	var entries: Array = []
	for i in range(start, end):
		if slots[i] != null:
			entries.append(slots[i])
			slots[i] = null
	var merged: Array = []
	for e in entries:
		if e["item"].is_stackable:
			for m in merged:
				if m["item"].id == e["item"].id and int(m["quantity"]) < m["item"].max_stack:
					var space: int = m["item"].max_stack - int(m["quantity"])
					var moved: int = mini(space, int(e["quantity"]))
					m["quantity"] = int(m["quantity"]) + moved
					e["quantity"] = int(e["quantity"]) - moved
					if int(e["quantity"]) <= 0:
						break
		if int(e["quantity"]) > 0:
			merged.append(e)
	match key:
		"count":
			merged.sort_custom(func(a, b):
				if int(a["quantity"]) != int(b["quantity"]):
					return int(a["quantity"]) > int(b["quantity"])
				return a["item"].name < b["item"].name)
		"value":
			merged.sort_custom(func(a, b):
				if a["item"].sell_value != b["item"].sell_value:
					return a["item"].sell_value > b["item"].sell_value
				return a["item"].name < b["item"].name)
		_:
			merged.sort_custom(func(a, b):
				if a["item"].name != b["item"].name:
					return a["item"].name < b["item"].name
				return int(a["quantity"]) > int(b["quantity"]))
	for i in range(merged.size()):
		slots[start + i] = merged[i]
	inventory_updated.emit()

func get_item_count(item_id: String) -> int:
	var total = 0
	for slot in slots:
		if slot != null and slot["item"].id == item_id:
			total += slot["quantity"]
	return total

func remove_item(item_id: String, amount_to_remove: int) -> bool:
	if get_item_count(item_id) < amount_to_remove:
		return false

	var remaining_to_remove = amount_to_remove

	for i in range(slots.size()):
		if slots[i] != null and slots[i]["item"].id == item_id:
			if slots[i]["quantity"] > remaining_to_remove:
				slots[i]["quantity"] -= remaining_to_remove
				remaining_to_remove = 0
				break
			else:
				remaining_to_remove -= slots[i]["quantity"]
				slots[i] = null
				if remaining_to_remove <= 0:
					break

	inventory_updated.emit()
	return true

## Wipes and rebuilds the whole inventory from saved data.
func restore_from_save(saved_slots: Array) -> void:
	slots.clear()
	slots.resize(maxi(tab_count() * TAB_BASE_SLOTS, saved_slots.size()))
	slots.fill(null)

	for i in range(saved_slots.size()):
		var entry = saved_slots[i]
		if entry == null: continue
		var item = GameManager.find_item_by_id(entry.get("id", ""))
		if item:
			slots[i] = {"item": item, "quantity": int(entry.get("quantity", 1))}

	inventory_updated.emit()

## Serializes slots for saving.
func get_save_data() -> Array:
	var result: Array = []
	for slot in slots:
		if slot == null:
			result.append(null)
		else:
			result.append({"id": slot["item"].id, "quantity": slot["quantity"]})
	return result
