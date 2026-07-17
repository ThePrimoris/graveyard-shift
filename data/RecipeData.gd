# RecipeData.gd
# One production-skill recipe (P3 Alchemy; Forge will reuse this): a set of
# item inputs brewed over a timer into an output item, granting skill XP.
# Loaded from data/recipes/<skill>/ into AlchemyManager.recipe_db.
extends Resource
class_name Recipe

@export_group("Basic Information")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""

@export_group("Craft")
## item_id -> amount consumed when the brew STARTS.
@export var inputs: Dictionary = {}
@export var output_item: Item = null
@export var output_amount: int = 1

@export_group("Progression")
## Alchemy level required before this recipe appears unlocked.
@export var required_level: int = 1
## When true, reaching required_level is not enough: the recipe must also be
## learned from a scroll item (shop-bought or encounter loot) whose
## taught_recipe_id names this recipe. Persisted in CraftingManager.
@export var scroll_taught: bool = false
## Seconds one brew takes (the harvest-progress pattern).
@export var base_seconds: float = 4.0
## Alchemy XP granted when the brew completes.
@export var base_xp: float = 8.0
