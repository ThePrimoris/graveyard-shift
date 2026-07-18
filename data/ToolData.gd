extends Item
class_name ToolData

enum ToolType { SHOVEL, HATCHET, PICKAXE }
enum ToolTier { RUSTED, GALVANIZED, REINFORCED, TEMPERED }

@export_group("Tool Stats")
@export var speed_multiplier: float = 1.0 
@export var yield_bonus: int = 0
@export var tool_type: ToolType = ToolType.SHOVEL
@export var tool_tier: ToolTier = ToolTier.RUSTED

func effect_line() -> String:
	var bits: Array[String] = []
	var speed := int(round((speed_multiplier - 1.0) * 100))
	if speed > 0: bits.append("+%d%% %s speed" % [speed, ToolType.keys()[tool_type].to_lower()])
	if yield_bonus > 0: bits.append("+%d%% double-haul chance" % yield_bonus)
	return "" if bits.is_empty() else "Equipped: %s." % ", ".join(bits)