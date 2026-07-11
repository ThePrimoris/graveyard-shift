class_name MinionAbility
extends Resource

## One node in a minion's skill tree. Passives take effect while the minion
## is slotted in a graveyard plot; actives are stored for combat, later.
enum Kind { PASSIVE, ACTIVE }

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_category("Tree")
@export var kind: Kind = Kind.PASSIVE
## Which arc of the sigil fan this rune sits on (1 = nearest the root).
## The Necronomicon lays runes out automatically from this.
@export var tier: int = 1
## Skill points to unlock (minions earn 1 point per level).
@export var cost: int = 1
## Ability ids that must be unlocked first.
@export var prerequisites: Array[String] = []

@export_category("Effect")
## What the ability does, matched in code. Current passive hooks:
##  "harvest_xp_pct"   - bonus % skill XP from harvests
##  "rare_chance_pct"  - flat % added to nodes' rare table chance
##  "double_drop_pct"  - % chance to double a harvest's haul
##  "grounds_yield_pct" - boosts the grounds' offline output while slotted
## Actives use free-form ids until combat lands.
@export var effect: String = ""
@export var magnitude: float = 0.0
