# GearData.gd
# Minion equipment (P5 Forge, reworked — see docs/forge_redesign.md): two relic
# + three trinket slots per minion. Relics are the powerful, unique-borne pieces;
# trinkets are small buffs. Both carry flat ATK/HP and/or ONE passive channel:
#   - combat (an Ids.MINION_* effect): buffs the wearer itself in battle,
#     read per-minion by MinionManager.get_minion_effect — same channels as runes.
#   - gather (an Ids.EFFECT_* effect): warband-wide while the bearer holds a
#     plot, read by MinionManager.get_worn_gear_bonus. Kept to small magnitudes
#     and one-copy-per-minion so gather bonuses stay spice (Access & Yield).
# Smithed at the Forge; never sold in the shop (the shop sells schematics).
extends Item
class_name Gear

## Category, not a worn position — MinionManager keys worn gear by named slot
## ("relic_0".."trinket_2"). RELIC keeps WEAPON's old int (0) so gear .tres
## files predating the rework load unchanged.
enum GearSlot { RELIC, TRINKET }

@export_group("Gear")
@export var slot: GearSlot = GearSlot.RELIC
## Flat attack added while equipped.
@export var atk_bonus: float = 0.0
## Flat max HP added while equipped.
@export var hp_bonus: int = 0
## Optional passive channel: one of Ids.MINION_* (combat) or Ids.EFFECT_*
## (gather), "" = none.
@export var passive_effect: String = ""
## Magnitude fed into that channel (percentage points, like rune passives).
@export var passive_magnitude: float = 0.0

## Tooltip labels for the gather channels gear may carry; combat channels fall
## through to the generic minion_-prefix trim below.
const GATHER_LABELS: Dictionary = {
	"harvest_xp_pct": "harvest XP",
	"rare_chance_pct": "rare find chance",
	"double_drop_pct": "double haul chance",
	"sell_pct": "sell price",
	"offering_pct": "offering XP",
}

func _init() -> void:
	type = ItemType.MISC
	is_stackable = false
	max_stack = 1

func is_gather_gear() -> bool:
	return GATHER_LABELS.has(passive_effect)

func effect_line() -> String:
	var line := stat_line()
	if line == "ornamental":
		return ""
	var where := "while its bearer holds a plot" if is_gather_gear() else "in battle"
	return "Equipped: %s (%s)." % [line, where]

## One-line stat summary for tooltips and the equip menu.
func stat_line() -> String:
	var bits: Array[String] = []
	if atk_bonus > 0.0: bits.append("+%.1f ATK" % atk_bonus)
	if hp_bonus > 0: bits.append("+%d HP" % hp_bonus)
	if passive_effect != "" and passive_magnitude > 0.0:
		# Flag channels (magnitude is a 0/1 switch) read as prose, not a percent.
		if passive_effect == "minion_taunt":
			bits.append("draws enemy blows")
		elif passive_effect == "minion_revive":
			bits.append("its bearer rises once per battle")
		else:
			var label: String = GATHER_LABELS.get(passive_effect,
				passive_effect.trim_prefix("minion_").replace("_pct", "").replace("_", " "))
			bits.append("+%.0f%% %s" % [passive_magnitude, label])
	return " · ".join(bits) if not bits.is_empty() else "ornamental"
