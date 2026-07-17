# AlchemyManager.gd
# The Alchemy production skill (P3): brews recipes (data/recipes/alchemy/)
# into consumables. All mechanics live in CraftingManager; this autoload just
# points the shared engine at Alchemy's recipes, skill, and the Apothecary's
# speed channel.
extends CraftingManager

func _init() -> void:
	recipe_dirs = ["res://data/recipes/alchemy/"]
	skill_key = Ids.SKILL_ALCHEMY
	speed_effect = Ids.EFFECT_ALCHEMY_SPEED_PCT
	finish_sfx = Ids.SFX_BREW
