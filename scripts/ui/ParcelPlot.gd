# ParcelPlot.gd
# One parcel of land on the Grounds map. Locked parcels are marked by a carved
# waystone at their heart and low boundary stones at their corners — no
# floating text; the deed's name and price live in the inspect panel once the
# land is clicked. Once bought the plot goes quiet: the world draws its tiles
# and the stones come down.
extends Node2D

signal selected(parcel_id: String)

const STONE := Color("#3b3450")
const STONE_LIT := Color("#565073")
const STONE_DARK := Color("#2a2440")
const RUNE := Color(0.663, 0.61, 0.867, 0.85)
const GLIMMER := Color(0.83, 0.64, 0.27)
const SHADOW := Color(0.04, 0.03, 0.06, 0.5)
const GOLD := Color("#c8a24d")

var parcel_id: String = ""
var is_selected: bool = false

func setup(p: GroundsParcel) -> void:
	parcel_id = p.id
	# Anchor at the parcel's front corner; the signpost draws at its center.
	position = IsoUtil.cell_to_world(p.origin.x + p.size.x, p.origin.y + p.size.y)
	var area := Area2D.new()
	area.input_pickable = true
	var cp := CollisionPolygon2D.new()
	var poly := IsoUtil.footprint_polygon(p.origin, p.size)
	var local := PackedVector2Array()
	for pt in poly:
		local.append(pt - position)
	cp.polygon = local
	area.add_child(cp)
	area.input_event.connect(_on_area_input)
	add_child(area)
	if not GroundsManager.grounds_updated.is_connected(_on_changed):
		GroundsManager.grounds_updated.connect(_on_changed)
	queue_redraw()

func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Only locked land answers the door; owned parcels let clicks fall through
	# to the structures standing on them.
	if GroundsManager.is_parcel_unlocked(parcel_id):
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(parcel_id)

func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()

func _on_changed() -> void:
	queue_redraw()

func _center_local() -> Vector2:
	var p: GroundsParcel = GroundsManager.find_parcel(parcel_id)
	return IsoUtil.cell_to_world(p.origin.x + p.size.x * 0.5, p.origin.y + p.size.y * 0.5) - position

func _draw() -> void:
	var p: GroundsParcel = GroundsManager.find_parcel(parcel_id)
	if p == null or GroundsManager.is_parcel_unlocked(parcel_id):
		return

	var c := _center_local()
	if is_selected:
		var poly := IsoUtil.footprint_polygon(p.origin, p.size)
		var local := PackedVector2Array()
		for pt in poly:
			local.append(pt - position)
		local.append(local[0])
		draw_polyline(local, GOLD, 3.0, true)

	# Low boundary stones at the parcel's corners.
	for corner in [Vector2i(0, 0), Vector2i(p.size.x, 0), Vector2i(0, p.size.y), Vector2i(p.size.x, p.size.y)]:
		var pos := IsoUtil.cell_to_world(p.origin.x + corner.x, p.origin.y + corner.y) - position
		_boundary_stone(pos)

	# The waystone: a carved marker at the land's heart. Its rune glimmers so
	# it reads as a point of interest without a word of floating text.
	draw_colored_polygon(_ellipse(c + Vector2(0, 4), 14, 6), SHADOW)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-9, 2), c + Vector2(-7, -30), c + Vector2(0, -36),
		c + Vector2(7, -30), c + Vector2(9, 2)]), STONE)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, 2), c + Vector2(0, -34), c + Vector2(7, -30), c + Vector2(9, 2)]), STONE_DARK)
	draw_line(c + Vector2(-9, 2), c + Vector2(-7, -30), STONE_LIT, 1.5)
	# The carved rune, and a faint gold glimmer above when affordable curiosity
	# should be piqued (always, softly — the panel does the talking).
	draw_arc(c + Vector2(-3, -18), 5.0, 0.6, TAU - 0.6, 20, RUNE, 1.6)
	draw_line(c + Vector2(-3, -24), c + Vector2(-3, -12), RUNE, 1.6)
	draw_circle(c + Vector2(0, -44), 7.0, Color(GLIMMER.r, GLIMMER.g, GLIMMER.b, 0.14))
	draw_circle(c + Vector2(0, -44), 1.8, Color(GLIMMER.r, GLIMMER.g, GLIMMER.b, 0.8))

func _boundary_stone(pos: Vector2) -> void:
	draw_colored_polygon(_ellipse(pos + Vector2(0, 2), 7, 3), SHADOW)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-5, 1), pos + Vector2(-4, -9), pos + Vector2(0, -11),
		pos + Vector2(4, -9), pos + Vector2(5, 1)]), STONE)
	draw_line(pos + Vector2(-4, -9), pos + Vector2(0, -11), STONE_LIT, 1.2)

func _ellipse(center: Vector2, rx: float, ry: float, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
