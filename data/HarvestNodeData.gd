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

@export_category("Affix")
## Optional node affix id, looked up in GameManager.AFFIXES. Loop-safe affixes
## (sticky_sap, blind_canopies, unstable_seams) change harvesting; the combat
## hazard affixes are flavour for now, inert until minions can be deployed here.
@export var affix: String = ""

@export_category("Encounter")
## Boss nodes are cleared through combat rather than harvested.
@export var is_boss: bool = false
## The Encounter resource id Confront launches (see data/encounters/).
@export var encounter_id: String = ""

@export_category("Loot")
## Weighted table — every harvest drops exactly one row from it.
## Row share = weight / total weight of the table.
## Breakable nodes (hit_damage > 0) ignore this and use the tables below.
@export var common_pool: Array[LootDrop] = []

## Chance per harvest to ALSO roll once on the rare table (0 = never).
@export_range(0.0, 1.0, 0.001) var rare_chance: float = 0.0

## Weighted table for the rare roll, same rules as common_pool.
@export var rare_pool: Array[LootDrop] = []

@export_category("Durability (Spelunking)")
## Damage one completed harvest bar deals to the node (0 = no health bar).
## Health is always 100% under the hood, so 0.25 = four hits to break.
## The card shows a vertical damage meter that fills per hit; at full, the
## node breaks, pays its Break table, and resets.
@export_range(0.0, 1.0, 0.01) var hit_damage: float = 0.0

## Hit Chance table: weights are literal percentages out of 100. Each hit
## rolls once — a row's weight is its chance to drop, and any shortfall
## from 100 is the chance the hit shakes nothing loose.
@export var hit_pool: Array[LootDrop] = []

## Break table: rolled once, GUARANTEED, when the node breaks. Weights are
## relative shares like common_pool — something always drops.
@export var break_pool: Array[LootDrop] = []

## Rows beyond this many (per table) are ignored at harvest time.
const MAX_LOOT_ENTRIES: int = 5
