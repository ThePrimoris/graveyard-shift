# GearData.gd
# Minion equipment (P5 Forge): one weapon + one trinket slot per minion,
# COMBAT ONLY by design — gear never touches the gather economy, keeping the
# Access & Yield model clean. Weapons carry flat ATK; trinkets carry flat HP
# and/or one combat passive channel (an Ids.MINION_* effect, same ones the
# skill-tree runes use). Smithed at the Forge; not sold in the shop.
extends Item
class_name Gear

enum GearSlot { WEAPON, TRINKET }

@export_group("Gear")
@export var slot: GearSlot = GearSlot.WEAPON
## Flat attack added while equipped (weapons).
@export var atk_bonus: float = 0.0
## Flat max HP added while equipped (trinkets, mostly).
@export var hp_bonus: int = 0
## Optional combat passive channel (one of Ids.MINION_*, "" = none).
@export var passive_effect: String = ""
## Magnitude fed into that channel (percentage points, like rune passives).
@export var passive_magnitude: float = 0.0

func _init() -> void:
	type = ItemType.MISC
	is_stackable = false
	max_stack = 1

## One-line stat summary for tooltips and the equip menu.
func stat_line() -> String:
	var bits: Array[String] = []
	if atk_bonus > 0.0: bits.append("+%.1f ATK" % atk_bonus)
	if hp_bonus > 0: bits.append("+%d HP" % hp_bonus)
	if passive_effect != "" and passive_magnitude > 0.0:
		bits.append("+%.0f%% %s" % [passive_magnitude, passive_effect.trim_prefix("minion_").replace("_pct", "").replace("_", " ")])
	return " · ".join(bits) if not bits.is_empty() else "ornamental"
