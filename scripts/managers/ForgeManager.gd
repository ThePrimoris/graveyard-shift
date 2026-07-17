# ForgeManager.gd
# The Forge production skill (P5): smiths recipes (data/recipes/forge/) into
# minion gear — weapons from ores, trinkets from gems. All mechanics live in
# CraftingManager; read the shared brew_* vocabulary as "smith" here.
extends CraftingManager

func _init() -> void:
	recipe_dirs = ["res://data/recipes/forge/"]
	skill_key = Ids.SKILL_FORGE
	speed_effect = ""  # no forge-speed structure yet; a Bellows could hook in here
	finish_sfx = Ids.SFX_SMITH
