# Ids.gd
# Central registry of the string ids that wire the game together. These used to
# live as raw literals scattered across managers, views, and content — where a
# single typo did nothing and failed silently. Referencing a constant instead
# turns a typo into a parse-time error rather than a quiet runtime no-op, and the
# *_ALL lists give content validation (see ContentValidator) a single source of
# truth for "what ids are known".
#
# Kept as flat top-level constants (not nested classes) so they are valid
# constant expressions everywhere they're used — including const dictionaries
# (GameManager.AFFIXES), const arrays (TutorialManager.STEPS) and match patterns.
#
# Values here are byte-identical to the strings they replace. Anything stored in
# a `.tres` (affix ids, effect ids) MUST match a constant below.
#
# Talks to: GameManager, MinionManager, GroundsManager, TutorialManager,
# HarvestView, NecronomiconPanel, NavigationPanel, Control, ContentValidator,
# SmokeTest.
class_name Ids
extends RefCounted

# --- Gather-bonus / structure passive effects -------------------------
# Read by GameManager.get_gather_modifiers, GroundsManager.get_bonus,
# MinionManager.get_passive_bonus. Every one of these is actually handled in code.
const EFFECT_HARVEST_XP_PCT := "harvest_xp_pct"
const EFFECT_RARE_CHANCE_PCT := "rare_chance_pct"
const EFFECT_DOUBLE_DROP_PCT := "double_drop_pct"
const EFFECT_GROUNDS_YIELD_PCT := "grounds_yield_pct"
const EFFECT_INVENTORY_SLOTS := "inventory_slots"
const EFFECT_OFFLINE_HOURS := "offline_hours"
# Wave-two structure channels (P4 / DEP-9):
const EFFECT_OFFERING_PCT := "offering_pct"            ## Mausoleum: +% altar offering XP
const EFFECT_SELL_PCT := "sell_pct"                    ## Counting House: +% item sell value
const EFFECT_ALCHEMY_SPEED_PCT := "alchemy_speed_pct"  ## Apothecary: +% brew speed
const EFFECT_EXHAUST_HASTE_PCT := "exhaust_haste_pct"  ## Incense: exhausted minions rest this % quicker
const EFFECT_OFFLINE_GAIN_PCT := "offline_gain_pct"    ## Incense: offline seconds it covers pay +%
# Deployment (DEP-8):
const EFFECT_MINION_GATHER_PCT := "minion_gather_pct"  ## Waystation: +% deployed minion gather pace
const EFFECT_ALL: Array[String] = [
	EFFECT_HARVEST_XP_PCT, EFFECT_RARE_CHANCE_PCT, EFFECT_DOUBLE_DROP_PCT,
	EFFECT_GROUNDS_YIELD_PCT, EFFECT_INVENTORY_SLOTS, EFFECT_OFFLINE_HOURS,
	EFFECT_OFFERING_PCT, EFFECT_SELL_PCT, EFFECT_ALCHEMY_SPEED_PCT,
	EFFECT_EXHAUST_HASTE_PCT, EFFECT_OFFLINE_GAIN_PCT, EFFECT_MINION_GATHER_PCT,
]

# --- Minion active-rune effects (combat) ------------------------------
# Free-form per-minion, but each must be declared here so typos surface. Their
# distinct combat resolution is DEP-1 (still parked).
const ACTIVE_LURCH := "active_lurch"
const ACTIVE_RATTLING_VOLLEY := "active_rattling_volley"
const ACTIVE_RENDING_CLAWS := "active_rending_claws"
const ACTIVE_SAVAGE_POUNCE := "active_savage_pounce"
const ACTIVE_ALL: Array[String] = [
	ACTIVE_LURCH, ACTIVE_RATTLING_VOLLEY, ACTIVE_RENDING_CLAWS, ACTIVE_SAVAGE_POUNCE,
]

# --- Node affix ids ---------------------------------------------------
# See GameManager.AFFIXES for their metadata. AFFIX_ALL must match its keys.
const AFFIX_STICKY_SAP := "sticky_sap"
const AFFIX_BLIND_CANOPIES := "blind_canopies"
const AFFIX_UNSTABLE_SEAMS := "unstable_seams"
const AFFIX_THORN_VEIL := "thorn_veil"
const AFFIX_TOXIC_ROOTS := "toxic_roots"
const AFFIX_SONIC_RESONANCE := "sonic_resonance"
const AFFIX_SUBTERRANEAN_CHILL := "subterranean_chill"
const AFFIX_VOLCANIC_GAS := "volcanic_gas"
const AFFIX_ALL: Array[String] = [
	AFFIX_STICKY_SAP, AFFIX_BLIND_CANOPIES, AFFIX_UNSTABLE_SEAMS, AFFIX_THORN_VEIL,
	AFFIX_TOXIC_ROOTS, AFFIX_SONIC_RESONANCE, AFFIX_SUBTERRANEAN_CHILL, AFFIX_VOLCANIC_GAS,
]

# --- Skill keys -------------------------------------------------------
# The SkillType enum names lowercased. Used as `skills` dict keys and everywhere
# a skill is referenced by string.
const SKILL_GRAVEROBBING := "graverobbing"
const SKILL_LUMBERING := "lumbering"
const SKILL_SPELUNKING := "spelunking"
## Alchemy (P3) and Forge (P5) are PRODUCTION skills: they live in
## GameManager.skills and use the shared XP curve, but have recipes
## (CraftingManager subclasses) instead of nodes.
const SKILL_ALCHEMY := "alchemy"
const SKILL_FORGE := "forge"
const SKILL_ALL: Array[String] = [SKILL_GRAVEROBBING, SKILL_LUMBERING, SKILL_SPELUNKING, SKILL_ALCHEMY, SKILL_FORGE]

# --- Scene-tree group names (the "groups + tick" broadcast pattern) ----
const GROUP_UI_UPDATES := "ui_updates"
const GROUP_VIEW_MANAGER := "view_manager"
const GROUP_HARVEST_VIEWS := "harvest_views"
const GROUP_COMBAT_VIEWS := "combat_views"
const GROUP_NECRONOMICON := "necronomicon"

# --- Switchable view names (passed to Control/TutorialManager.switch_view) ---
const VIEW_GRAVEYARD := "graveyard"
const VIEW_FOREST := "forest"
const VIEW_QUARRY := "quarry"
const VIEW_INVENTORY := "inventory"
const VIEW_SHOP := "shop"
const VIEW_COMBAT := "combat"
const VIEW_ALCHEMY := "alchemy_lab"
const VIEW_FORGE := "forge_hall"
const VIEW_GROUNDS := "grounds"

# --- Named tutorial beats (fired via TutorialManager.notify_event) ----
const EVENT_BOOK_OPENED := "book_opened"
const EVENT_MINION_RAISED := "minion_raised"
const EVENT_MINION_SLOTTED := "minion_slotted"
const EVENT_OFFERING_MADE := "offering_made"

# --- Minion combat passive effects -----------------------------------
# Applied PER-MINION to its own warband member in CombatView (a minion's tree
# buffs itself in battle), unlike the gather EFFECT_* which sum across the whole
# slotted warband. Kept modest — minions are the sole source of combat power, so
# there's headroom here without touching the gather economy.
const MINION_HP_PCT := "minion_hp_pct"          ## +% max HP
const MINION_ATK_PCT := "minion_atk_pct"        ## +% attack
const MINION_SPEED_PCT := "minion_speed_pct"    ## +% ATB charge rate
const MINION_REGEN_PCT := "minion_regen_pct"    ## heal this % of max HP each of its turns
const MINION_LIFESTEAL_PCT := "minion_lifesteal_pct"  ## heal this % of damage dealt
const MINION_CRIT_PCT := "minion_crit_pct"      ## chance to land a crit (x1.5)
const MINION_FRENZY_PCT := "minion_frenzy_pct"  ## +% attack for each foe it kills this fight
const MINION_THORNS_PCT := "minion_thorns_pct"  ## reflect this % of damage taken
const MINION_TAUNT := "minion_taunt"            ## enemies prefer to target this minion
const MINION_REVIVE := "minion_revive"          ## revive once per fight at 25% HP
const COMBAT_EFFECT_ALL: Array[String] = [
	MINION_HP_PCT, MINION_ATK_PCT, MINION_SPEED_PCT, MINION_REGEN_PCT,
	MINION_LIFESTEAL_PCT, MINION_CRIT_PCT, MINION_FRENZY_PCT, MINION_THORNS_PCT,
	MINION_TAUNT, MINION_REVIVE,
]

# --- Consumable use effects (DEP-2 / P2a) -----------------------------
# Set on Consumable.use_effect; resolved by CombatView's Item command (combat
# effects) or the exhaustion system (cures). ContentValidator enforces these.
const CONSUME_HEAL_PCT := "consume_heal_pct"              ## heal the acting minion this % of max HP
const CONSUME_ATK_PCT := "consume_atk_pct"                ## +% ATK for duration_turns of its turns
const CONSUME_POISON := "consume_poison"                  ## poison the target foe: magnitude dmg for duration_turns
const CONSUME_CURE_EXHAUSTION := "consume_cure_exhaustion"  ## rouse an exhausted minion
const CONSUME_ATK_DEF_PCT := "consume_atk_def_pct"        ## +% ATK and -% damage taken for duration_turns
const CONSUME_POISON_WEAKEN := "consume_poison_weaken"    ## poison + sap the foe's blows by secondary_magnitude%
const CONSUME_REVIVE_ONCE := "consume_revive_once"        ## the drinker rises once at magnitude% HP this battle
## Gather elixirs (P3): drunk from the inventory, they lay a timed buff on
## GameManager.active_buffs that get_gather_modifiers reads until it expires.
const CONSUME_GATHER_XP_BUFF := "consume_gather_xp_buff"      ## +magnitude% harvest XP for buff_minutes
const CONSUME_GATHER_RARE_BUFF := "consume_gather_rare_buff"  ## +magnitude% rare chance for buff_minutes
const CONSUME_LEARN_RECIPE := "consume_learn_recipe"          ## studies a scroll: teaches taught_recipe_id
const CONSUME_INCENSE_EXHAUST := "consume_incense_exhaust"    ## grounds: minions rest magnitude% quicker for buff_minutes
const CONSUME_INCENSE_DOUBLE := "consume_incense_double"      ## grounds: +magnitude% double-harvest chance for buff_minutes
const CONSUME_INCENSE_OFFLINE := "consume_incense_offline"    ## grounds: offline gains +magnitude% while it burns
const CONSUME_ALL: Array[String] = [
	CONSUME_HEAL_PCT, CONSUME_ATK_PCT, CONSUME_POISON, CONSUME_CURE_EXHAUSTION,
	CONSUME_ATK_DEF_PCT, CONSUME_POISON_WEAKEN, CONSUME_REVIVE_ONCE,
	CONSUME_GATHER_XP_BUFF, CONSUME_GATHER_RARE_BUFF, CONSUME_LEARN_RECIPE,
	CONSUME_INCENSE_EXHAUST, CONSUME_INCENSE_DOUBLE, CONSUME_INCENSE_OFFLINE,
]

# --- Sound effect ids (AudioManager.play_sfx). Each matches audio/sfx/<id>.wav. ---
const SFX_UI_CLICK := "ui_click"
const SFX_HARVEST_TICK := "harvest_tick"
const SFX_ITEM_PICKUP := "item_pickup"
const SFX_LEVEL_UP := "level_up"
const SFX_BUILD := "build"
const SFX_COMBAT_HIT := "combat_hit"
const SFX_BREW := "brew"                    ## a brew finishes at the Still
const SFX_SMITH := "smith"                  ## a smith finishes at the Forge
const SFX_POTION := "potion"                ## any consumable is drunk/used
const SFX_VICTORY_STING := "victory_sting"  ## combat won
const SFX_DEFEAT_STING := "defeat_sting"    ## combat lost
const SFX_ALL: Array[String] = [
	SFX_UI_CLICK, SFX_HARVEST_TICK, SFX_ITEM_PICKUP,
	SFX_LEVEL_UP, SFX_BUILD, SFX_COMBAT_HIT,
	SFX_BREW, SFX_SMITH, SFX_POTION, SFX_VICTORY_STING, SFX_DEFEAT_STING,
]
