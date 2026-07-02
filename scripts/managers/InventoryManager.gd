# InventoryManager.gd
extends Node

signal inventory_updated

# Total number of inventory slots (This should possibly be configurable in the future)
const TOTAL_SLOTS: int = 24

var slots: Array = []

func _ready() -> void:
	slots.resize(TOTAL_SLOTS)
	slots.fill(null)

func add_tool(tool: ToolData) -> void:
	for i in range(TOTAL_SLOTS):
		if slots[i] == null:
			slots[i] = {"item": tool, "quantity": 1}
			inventory_updated.emit()
			return

func add_item(item: Item, amount: int = 1) -> int:
	var remaining = amount
	
	for i in range(TOTAL_SLOTS):
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
					
	for i in range(TOTAL_SLOTS):
		if slots[i] == null:
			var stack_limit = item.max_stack
			var to_add = min(remaining, stack_limit)
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
	
	for i in range(TOTAL_SLOTS):
		if slots[i] != null and slots[i]["item"].id == item_id:
			if slots[i]["quantity"] > remaining_to_remove:
				slots[i]["quantity"] -= remaining_to_remove
				remaining_to_remove = 0
				break
			else:
				remaining_to_remove -= slots[i]["quantity"]
				slots[i] = null 
				
	inventory_updated.emit()
	return true
