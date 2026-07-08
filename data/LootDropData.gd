class_name LootDrop
extends Resource

## One entry in a node's loot pool.
@export var item: Item
## Chance per harvest that this entry drops (1.0 = every time).
## Each entry rolls independently of the others.
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
