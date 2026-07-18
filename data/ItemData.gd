extends Resource
class_name Item

@export_group("Basic Information")
@export var id: String = ""
@export var name: String = ""
@export var type: ItemType = ItemType.MATERIAL
@export var icon: Texture2D
@export_multiline var description: String = ""

@export_group("Economy")
@export var sell_value: int = 1
@export var is_sellable: bool = true
@export var rarity: Rarity = Rarity.COMMON
## Worth of ONE unit when offered at the Ritual Altar, in "gold" the offering
## rite converts to minion XP. -1 (the default) derives it from sell_value, so
## economy re-pricing (Counting House, Alchemy) never silently shifts minion
## leveling unless a .tres opts in with an explicit value.
@export var offering_value: int = -1

@export_group("Storage")
@export var max_stack: int = 250
@export var is_stackable: bool = true

@export_group("Gameplay")
@export var required_level: int = 1
@export var item_effect: Resource = null

# CONSUMABLE is appended last so existing .tres int values keep their meaning.
enum ItemType { MATERIAL, TOOL, QUEST, MISC, CONSUMABLE }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## The mechanical rules line shown separately from the flavor `description`.
## Subclasses derive it from their effect fields so the UI always states what
## an item actually does; "" means the item has no effect to state.
func effect_line() -> String:
	return ""