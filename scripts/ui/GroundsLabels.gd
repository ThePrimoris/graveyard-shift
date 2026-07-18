# GroundsLabels.gd
# The name + tier-pip overlay for the Grounds map. Labels used to be drawn by
# each StructureBuilding, which let a taller neighbor's box cover them (Y-sort
# draws siblings back-to-front). This node sits above the whole world on a high
# z_index and draws every visible structure's nameplate last, so names always
# read.
extends Node2D

const GOLD := Color("#c8a24d")
const NAME_COL := Color("#e0d8c6")
const PIP_OFF := Color("#3a3350")
const PLATE := Color(0.05, 0.04, 0.09, 0.55)

func _ready() -> void:
	z_index = 100
	if not GroundsManager.grounds_updated.is_connected(queue_redraw):
		GroundsManager.grounds_updated.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	for structure_id in GroundsManager.sorted_ids():
		if not GroundsManager.is_structure_land_owned(structure_id):
			continue
		var s: Structure = GroundsManager.find_structure(structure_id)
		var tier := GroundsManager.get_level(structure_id)
		var anchor := IsoUtil.cell_to_world(s.grid_cell.x + s.footprint.x, s.grid_cell.y + s.footprint.y)

		var maxed := tier >= s.max_level()
		var nm := s.name
		if nm.begins_with("The "):
			nm = nm.substr(4)
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		# A soft plate behind the text so names stay legible over any geometry.
		draw_rect(Rect2(anchor.x - w * 0.5 - 5, anchor.y + 8, w + 10, 16), PLATE)
		draw_string(font, anchor + Vector2(-w * 0.5, 20), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			GOLD if maxed else NAME_COL)

		var mx := s.max_level()
		var px := anchor.x - (mx * 7) / 2.0 + 3.0
		for i in range(mx):
			draw_circle(Vector2(px + i * 7, anchor.y + 30), 2.6, GOLD if i < tier else PIP_OFF)
