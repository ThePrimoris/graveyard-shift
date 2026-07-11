class_name Encounter
extends Resource

## A combat encounter: the group of foes the warband faces.
## Boss encounters hold a single is_boss enemy and render as a banner.

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""

@export_category("Foes")
@export var enemies: Array[Enemy] = []

func is_boss_encounter() -> bool:
	return enemies.size() == 1 and enemies[0] != null and enemies[0].is_boss
