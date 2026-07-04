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

@export_group("Storage")
@export var max_stack: int = 250
@export var is_stackable: bool = true

@export_group("Gameplay")
@export var required_level: int = 1
@export var item_effect: Resource = null

enum ItemType { MATERIAL, TOOL, QUEST, MISC }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }