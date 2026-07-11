class_name Minion
extends Resource

## A raisable minion type: combat statline, growth per level, the material
## recipe of its raising rite, and its skill tree.

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Position in rosters and the Necronomicon's pages (lower = earlier).
@export var sort_order: int = 0

@export_category("Base Combat Stats")
@export var base_hp: int = 10
@export var base_atk: float = 1.0

@export_category("Stat Growth Per Level")
@export var hp_per_level: int = 5
@export var atk_per_level: float = 0.5

@export_category("Combat")
## Charge rate multiplier in battle: 1.0 = standard, higher acts more often.
@export var speed: float = 1.0

@export_category("Raising Rite")
## One-time material cost to raise this minion: { item_id: amount }.
@export var raise_cost: Dictionary[String, int] = {}

@export_category("Skill Tree")
## The minion's abilities in display order. Points come from levels.
@export var abilities: Array[MinionAbility] = []

func find_ability(ability_id: String) -> MinionAbility:
	for a in abilities:
		if a != null and a.id == ability_id:
			return a
	return null
