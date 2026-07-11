class_name Structure
extends Resource

## A buildable graveyard structure: a tiered upgrade track. Each built tier
## adds its magnitude to the structure's effect, which the rest of the game
## reads through GroundsManager (harvest bonuses, storage, etc.).

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## Display order on the Grounds screen (lower = earlier).
@export var sort_order: int = 0

@export_category("Effect")
## What building this raises, matched in code / GroundsManager.get_bonus:
##  "inventory_slots"  - extra backpack slots (capacity)
##  "harvest_xp_pct"   - global bonus % harvest XP
##  "double_drop_pct"  - global % chance to double a haul
##  "rare_chance_pct"  - global flat % added to rare rolls
@export var effect: String = ""
## Display suffix for the effect value: "%" or " slots".
@export var effect_unit: String = "%"
## Short human label for the effect, shown on the card.
@export var effect_label: String = ""

@export_category("Tiers")
@export var tiers: Array[StructureTier] = []

func max_level() -> int:
	return tiers.size()
