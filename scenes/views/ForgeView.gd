# ForgeView.gd
# The Boneyard Forge (P5, reworked — see docs/forge_redesign.md): grave-heat
# poured into fantastical stone and heartwood. Relics are the potent,
# unique-borne pieces; trinkets carry small buffs for war or labor. All
# presentation lives in CraftingView; this just points it at the ForgeManager
# station and names the capstone tab (the Golem Work, the Forge's answer to
# Alchemy's Great Work).
extends CraftingView

func _init() -> void:
	view_title = "Forge — The Boneyard Anvil"
	view_subtitle = "Grave-heat poured into stone and heartwood — relics of power, trinkets for war and labor. Equip them from a minion's page in the Necronomicon."
	verb = "Smith"
	accent = Color("#c08a4a")
	ambience_color = Color(0.063, 0.047, 0.039)
	icon_path = "res://icons/skills/forge.png"
	backdrop = "res://theme/backdrops/bg_forge.png"
	fallback_category = "The Golem Work"

func _ready() -> void:
	station = ForgeManager
	super()
