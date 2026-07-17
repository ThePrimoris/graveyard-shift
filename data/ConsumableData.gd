# ConsumableData.gd
# A usable item (DEP-2 / P2a): potions and tonics with a one-shot effect.
# Combat consumables are used from the battle Item menu and spend the acting
# minion's turn; grave tonics cure exhaustion from the defeat panel.
# `use_effect` must be one of Ids.CONSUME_* — ContentValidator enforces it.
extends Item
class_name Consumable

@export_group("Consumable Effect")
## One of Ids.CONSUME_*: what using this item does.
@export var use_effect: String = ""
## Effect strength. heal: % of max HP. atk: +% attack. poison: damage per tick.
@export var magnitude: float = 0.0
## For timed effects (atk buff, poison): how many of the bearer's turns it lasts.
@export var duration_turns: int = 0
## For gather elixirs and incense: how many real-time minutes the buff lasts.
@export var buff_minutes: float = 10.0
## For recipe scrolls (CONSUME_LEARN_RECIPE): the recipe id this scroll teaches.
@export var taught_recipe_id: String = ""
## Second dial for two-part effects (poison_weaken: the % the foe's blows sap).
@export var secondary_magnitude: float = 0.0

func _init() -> void:
	type = ItemType.CONSUMABLE

## True for effects used from the in-battle Item menu (vs out-of-combat cures).
func is_combat_usable() -> bool:
	return use_effect in [Ids.CONSUME_HEAL_PCT, Ids.CONSUME_ATK_PCT, Ids.CONSUME_POISON,
		Ids.CONSUME_ATK_DEF_PCT, Ids.CONSUME_POISON_WEAKEN, Ids.CONSUME_REVIVE_ONCE]

## True for gather elixirs drunk from the inventory screen.
func is_gather_elixir() -> bool:
	return use_effect in [Ids.CONSUME_GATHER_XP_BUFF, Ids.CONSUME_GATHER_RARE_BUFF]

## True for recipe scrolls studied from the inventory screen.
func is_recipe_scroll() -> bool:
	return use_effect == Ids.CONSUME_LEARN_RECIPE

## True for incense burned from the inventory screen (grounds-wide timed buffs).
func is_incense() -> bool:
	return use_effect in [Ids.CONSUME_INCENSE_EXHAUST, Ids.CONSUME_INCENSE_DOUBLE, Ids.CONSUME_INCENSE_OFFLINE]

## The GameManager timed-buff channel an incense burns on ("" if not incense).
func incense_channel() -> String:
	if use_effect == Ids.CONSUME_INCENSE_EXHAUST: return Ids.EFFECT_EXHAUST_HASTE_PCT
	if use_effect == Ids.CONSUME_INCENSE_DOUBLE: return Ids.EFFECT_DOUBLE_DROP_PCT
	if use_effect == Ids.CONSUME_INCENSE_OFFLINE: return Ids.EFFECT_OFFLINE_GAIN_PCT
	return ""
