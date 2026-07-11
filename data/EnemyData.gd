class_name Enemy
extends Resource

## One foe type for the combat screen.

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
## Placeholder art until enemies get real icons.
@export var glyph: String = "☠"
@export_multiline var description: String = ""

@export_category("Combat Stats")
@export var base_hp: int = 10
@export var atk: float = 3.0
## Charge rate multiplier: 1.0 = a standard turn, higher acts more often.
@export var speed: float = 1.0

@export_category("Boss")
@export var is_boss: bool = false
## Name of the telegraphed all-party attack (bosses only, "" = none).
@export var telegraph_name: String = ""
## Extra ATK multiplier gained each time a quarter of its health breaks.
@export_range(0.0, 1.0, 0.05) var enrage_per_segment: float = 0.0

@export_category("Spoils")
## Minion XP each surviving warband member earns when this foe falls.
@export var xp_reward: float = 10.0
@export var gold_min: int = 0
@export var gold_max: int = 0
## Chance table (weights are percentages out of 100; the shortfall drops
## nothing) rolled once when this foe dies.
@export var loot_pool: Array[LootDrop] = []
