# AlchemyView.gd
# The Caretaker's Still (P3): the Alchemy recipe grid. All presentation lives
# in CraftingView; this just points it at the AlchemyManager station.
extends CraftingView

func _init() -> void:
	view_title = "Alchemy — The Caretaker's Still"
	view_subtitle = "Necromantic matter and graveyard herbs, rendered into potions. Brews repeat while ingredients last."
	verb = "Brew"
	accent = Color("#5fae8f")
	ambience_color = Color(0.039, 0.055, 0.051)
	icon_path = "res://icons/skills/alchemy.png"
	backdrop = "res://theme/backdrops/bg_alchemy.png"
	# The vat-work materials (Prima Materia and its successors).
	fallback_category = "The Great Work"

func _ready() -> void:
	station = AlchemyManager
	super()
