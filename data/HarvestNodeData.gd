extends Resource
class_name HarvestNode

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""

@export_category("Requirements")
@export var required_skill: GameManager.SkillType = GameManager.SkillType.GRAVEROBBING
@export var required_level: int = 1
@export var required_tool_type: ToolData.ToolType = ToolData.ToolType.SHOVEL

@export_category("Balancing")
@export var base_duration: float = 3.0
@export var base_xp: float = 5.0

## Graverobbing dig-layer bar: how many sections it shows (0 = no section bar).
## The sections deplete evenly across the harvest cycle, left to right.
@export var dig_sections: int = 0

@export_category("Encounter")
## Boss nodes are cleared through combat rather than harvested.
## Combat isn't implemented yet, so these show a placeholder for now.
@export var is_boss: bool = false

@export_category("Loot Pool")
## Up to 5 entries. Every harvest rolls each entry independently against its
## own chance — e.g. dirt 100%, gravel 75%, spectacular gem 5%.
@export var loot_pool: Array[LootDrop] = []

## Entries beyond this many are ignored at harvest time.
const MAX_LOOT_ENTRIES: int = 5
