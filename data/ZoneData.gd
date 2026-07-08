class_name HarvestZone
extends Resource

## A named region within a skill, holding its own set of harvest nodes.
@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""

@export_category("Requirements")
## Skill level needed before this zone can be selected.
@export var required_level: int = 1

@export_category("Nodes")
@export var nodes: Array[HarvestNode] = []
