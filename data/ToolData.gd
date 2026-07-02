extends Item
class_name ToolData

enum ToolType { SHOVEL, HATCHET, PICKAXE }
enum ToolTier { RUSTED, REINFORCED, BLOODFORGED, PHANTASMAL }

@export_group("Tool Stats")
@export var speed_multiplier: float = 1.0 
@export var yield_bonus: int = 0
@export var tool_type: ToolType = ToolType.SHOVEL
@export var tool_tier: ToolTier = ToolTier.RUSTED