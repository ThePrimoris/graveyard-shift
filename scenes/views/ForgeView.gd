# ForgeView.gd
# The Boneyard Forge (P5): the Forge recipe grid — relics from ores,
# trinkets from gems. All presentation lives in CraftingView; this just
# points it at the ForgeManager station.
extends CraftingView

func _init() -> void:
	view_title = "Forge — The Boneyard Anvil"
	view_subtitle = "Ores hammered into relics, gems set into trinkets. Equip the results from a minion's page in the Necronomicon."
	verb = "Smith"
	accent = Color("#c08a4a")
	ambience_color = Color(0.063, 0.047, 0.039)
	icon_path = "res://icons/skills/forge.png"
	backdrop = "res://theme/backdrops/bg_forge.png"

func _ready() -> void:
	station = ForgeManager
	super()
