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

## Generated from the effect fields, never hand-written, so the stated rules
## can't drift from what using the item actually does. The leading word names
## where the item is used (Battle / Drink / Burn / Study).
func effect_line() -> String:
	match use_effect:
		Ids.CONSUME_HEAL_PCT:
			if magnitude >= 100.0:
				return "Battle: restores a minion to full health."
			return "Battle: restores %.0f%% of a minion's max health." % magnitude
		Ids.CONSUME_ATK_PCT:
			return "Battle: +%.0f%% ATK for the drinker's next %d turns." % [magnitude, duration_turns]
		Ids.CONSUME_ATK_DEF_PCT:
			return "Battle: +%.0f%% ATK and %.0f%% less damage taken for the drinker's next %d turns." % [magnitude, magnitude, duration_turns]
		Ids.CONSUME_POISON:
			return "Battle: poisons a foe for %.0f damage on each of its next %d turns. Poison ignores rage and armor." % [magnitude, duration_turns]
		Ids.CONSUME_POISON_WEAKEN:
			return "Battle: poisons a foe for %.0f damage on each of its next %d turns, and its blows land %.0f%% softer." % [magnitude, duration_turns, secondary_magnitude]
		Ids.CONSUME_REVIVE_ONCE:
			return "Battle: the next time the dusted minion falls this fight, it rises again at %.0f%% health." % magnitude
		Ids.CONSUME_CURE_EXHAUSTION:
			return "Rouses one exhausted minion back to battle-readiness."
		Ids.CONSUME_GATHER_XP_BUFF:
			return "Drink: +%.0f%% harvest XP for %s." % [magnitude, _fmt_buff_time()]
		Ids.CONSUME_GATHER_RARE_BUFF:
			return "Drink: +%.0f%% rare-find chance for %s." % [magnitude, _fmt_buff_time()]
		Ids.CONSUME_LEARN_RECIPE:
			return "Study: permanently learns this recipe at its crafting station."
		Ids.CONSUME_INCENSE_EXHAUST:
			return "Burn: exhausted minions rest %.0f%% quicker for %s. Lighting it also stirs those already resting." % [magnitude, _fmt_buff_time()]
		Ids.CONSUME_INCENSE_DOUBLE:
			return "Burn: +%.0f%% double-harvest chance for %s." % [magnitude, _fmt_buff_time()]
		Ids.CONSUME_INCENSE_OFFLINE:
			return "Burn: offline gains pay +%.0f%% more for %s." % [magnitude, _fmt_buff_time()]
	return ""

## buff_minutes rendered for humans: whole hours read as hours.
func _fmt_buff_time() -> String:
	var minutes := int(round(buff_minutes))
	if minutes >= 60 and minutes % 60 == 0:
		var hours := minutes / 60
		return "1 hour" if hours == 1 else "%d hours" % hours
	return "%d minutes" % minutes
