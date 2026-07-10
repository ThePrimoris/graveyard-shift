class_name LootDrop
extends Resource

## One row in a node's drop table (common or rare).
@export var item: Item

## Relative weight within its table. A row's drop share is
## weight / (sum of the table's weights) — weights that add to 100 read
## directly as percentages, but any positive numbers work.
@export_range(0.0, 100.0, 0.01, "or_greater") var weight: float = 1.0

## Amount rolled on a hit, inclusive range.
@export_range(1, 99) var min_amount: int = 1
@export_range(1, 99) var max_amount: int = 1
