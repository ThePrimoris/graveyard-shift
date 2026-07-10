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

## Dig-layer meter (used by Lumbering): how many stacked sections the card's
## vertical meter shows (0 = no meter). The bottom bar fills once per section
## and the meter loses its top section at each 1/n mark of the harvest.
@export var dig_sections: int = 0

@export_category("Encounter")
## Boss nodes are cleared through combat rather than harvested.
## Combat isn't implemented yet, so these show a placeholder for now.
@export var is_boss: bool = false

@export_category("Loot")
## Weighted table — every harvest drops exactly one row from it.
## Row share = weight / total weight of the table.
@export var common_pool: Array[LootDrop] = []

## Chance per harvest to ALSO roll once on the rare table (0 = never).
@export_range(0.0, 1.0, 0.001) var rare_chance: float = 0.0

## Weighted table for the rare roll, same rules as common_pool.
@export var rare_pool: Array[LootDrop] = []

## Rows beyond this many (per table) are ignored at harvest time.
const MAX_LOOT_ENTRIES: int = 5
