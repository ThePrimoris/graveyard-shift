# InventoryManager.gd
extends Node

signal inventory_updated

# Base number of inventory slots; extra slots are purchased with gold.
const BASE_SLOTS: int = 24
const MAX_PURCHASED_SLOTS: int = 24
const SLOT_BASE_COST: int = 250
const SLOT_COST_GROWTH: float = 1.35

var slots: Array = []
var purchased_slots: int = 0

func _ready() -> void:
	slots.resize(BASE_SLOTS)
	slots.fill(null)

## Cost of the NEXT backpack slot: each purchase is 35% pricier than the last.
func get_next_slot_cost() -> int:
	return int(round(SLOT_BASE_COST * pow(SLOT_COST_GROWTH, purchased_slots)))

func can_purchase_slot() -> bool:
	return purchased_slots < MAX_PURCHASED_SLOTS and GameManager.gold_coins >= get_next_slot_cost()

func purchase_slot() -> bool:
	if not can_purchase_slot(): return false
	GameManager.gold_coins -= get_next_slot_cost()
	purchased_slots += 1
	refresh_capacity()
	return true

## Grows the slot array to match purchases + built storage structures;
## never destroys occupied slots.
func refresh_capacity() -> void:
	var target = BASE_SLOTS + purchased_slots + GroundsManager.get_inventory_slot_bonus()
	while slots.size() < target:
		slots.append(null)
	while slots.size() > target and slots[slots.size() - 1] == null:
		slots.pop_back()
	inventory_updated.emit()

func get_total_slots() -> int:
	return slots.size()

## Empties the whole inventory back to base capacity (Settings hard reset).
func reset_state() -> void:
	purchased_slots = 0
	slots.clear()
	slots.resize(BASE_SLOTS)
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
	slots.resize(maxi(BASE_SLOTS + purchased_slots, saved_slots.size()))
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
