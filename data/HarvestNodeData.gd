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
@export var required_tool_tier: ToolData.ToolTier = ToolData.ToolTier.RUSTED

@export_category("Balancing")
@export var base_duration: float = 3.0
@export var base_xp: float = 10.0

@export_category("Loot Table (Drop Chances 0.0 - 1.0)")
@export var primary_drop: Resource  # ItemData / PackedScene Resource
@export var primary_chance: float = 1.0

@export var secondary_drop: Resource
@export var secondary_chance: float = 0.30 # 30% chance

@export var tertiary_drop: Resource
@export var tertiary_chance: float = 0.05 # 5% chance