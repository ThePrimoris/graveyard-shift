# GroundsWorld.gd
# The isometric world drawn inside the Grounds SubViewport: wilderness backdrop,
# the parceled plot (unlocked parcels tiled, locked parcels dark and hatched),
# the ritual circle at the heart of the Old Yard, and the graveyard dressing —
# fence, candles, headstones and dead trees in the wild dark beyond the land.
# StructureBuilding and ParcelPlot nodes are added on top as Y-sorted children
# by the view.
extends Node2D

const BG := Color("#12101d")
const WILD := Color("#161226")
const WILD_DOT := Color("#221c38")
const TILE_A := Color("#1a1430")
const TILE_B := Color("#1e1836")
const EDGE := Color("#282240")
const LOCK_TILE := Color("#151021")
const LOCK_HATCH := Color("#241d3a")
const CIRCLE := Color(0.541, 0.435, 0.745, 0.9)
const CIRCLE_DIM := Color(0.427, 0.353, 0.627, 0.9)
const FENCE := Color("#4a4560")
const FENCE_TIP := Color("#5a5273")
const HS := Color("#3b3450")
const HS_EDGE := Color("#565073")
const HS_SHADOW := Color(0.04, 0.03, 0.06, 0.5)
const CANDLE := Color("#f0be62")
const TREE := Color("#3d3320")

## The ritual circle sits at the heart of the Old Yard (cell coordinates).
const CIRCLE_CELL := Vector2(6.0, 6.5)

const PATH := Color("#241d3c")
const PATH_EDGE := Color("#2c2447")

## Worn dirt paths (cell-coordinate waypoints), drawn only once their parcel
## is owned. The Old Yard's spokes radiate from the ritual circle; each bought
## parcel extends the network to its own doorsteps.
const PATHS := {
	"old_yard": [
		[Vector2(6.0, 5.9), Vector2(5.2, 5.1)],            # circle -> chapel door
		[Vector2(6.4, 6.0), Vector2(8.0, 5.1)],            # circle -> ossuary door
		[Vector2(6.0, 5.9), Vector2(6.0, 4.4)],            # north walk
		[Vector2(6.9, 6.9), Vector2(8.4, 6.9)],            # east walk
		[Vector2(6.0, 7.4), Vector2(6.0, 8.4)],            # south walk
	],
	"north_rise": [
		[Vector2(6.0, 4.4), Vector2(6.0, 2.2)],
		[Vector2(6.0, 2.2), Vector2(4.9, 1.9)],            # -> grove
		[Vector2(6.0, 2.2), Vector2(7.3, 1.9)],            # -> lantern
	],
	"east_field": [
		[Vector2(8.4, 6.9), Vector2(9.8, 6.4)],
		[Vector2(9.8, 6.4), Vector2(10.3, 4.9)],           # -> mausoleum
		[Vector2(9.8, 6.4), Vector2(10.4, 7.4)],           # -> counting house
	],
	"the_hollow": [
		[Vector2(6.0, 8.4), Vector2(6.0, 9.8)],
		[Vector2(6.0, 9.8), Vector2(4.9, 10.4)],           # -> reliquary
		[Vector2(6.0, 9.8), Vector2(7.4, 9.9)],            # -> apothecary
	],
}

## In-plot dressing per parcel: (cell_x, cell_y, kind, tilt°). Kinds 0-2 are
## headstone shapes, 3 a small dead tree, 4 a lamp post with a warm flame.
const PARCEL_PROPS := {
	"old_yard": [
		Vector4(3.5, 8.5, 0, -5), Vector4(4.3, 8.2, 1, 4), Vector4(3.4, 6.4, 2, -3),
		Vector4(8.5, 8.4, 0, 6), Vector4(8.3, 7.0, 1, -4), Vector4(6.0, 4.4, 4, 0),
	],
	"north_rise": [
		Vector4(6.2, 0.5, 0, 4), Vector4(5.6, 0.4, 2, -6), Vector4(6.0, 2.2, 4, 0),
	],
	"east_field": [
		Vector4(9.4, 8.4, 1, 5), Vector4(11.5, 6.3, 0, -4), Vector4(11.4, 3.4, 3, 0),
		Vector4(9.8, 6.4, 4, 0),
	],
	"the_hollow": [
		Vector4(3.5, 9.5, 2, -5), Vector4(5.5, 11.4, 0, 4), Vector4(8.5, 11.3, 1, -3),
		Vector4(3.4, 11.3, 3, 0), Vector4(6.0, 9.8, 4, 0),
	],
}

## Headstones scattered in the wild dark beyond the land: (x, y, kind, tilt°).
const SURROUND := [
	Vector4(-620, 240, 0, -6), Vector4(640, 250, 1, 5), Vector4(-560, 380, 2, -4),
	Vector4(600, 400, 0, 6), Vector4(-480, 120, 1, -3), Vector4(500, 130, 2, 4),
	Vector4(-380, 560, 0, 7), Vector4(400, 570, 1, -5), Vector4(0, -60, 0, 3),
	Vector4(-180, -40, 2, -5), Vector4(190, -44, 1, 4), Vector4(0, 660, 2, 5),
]

func _ready() -> void:
	if not GroundsManager.grounds_updated.is_connected(queue_redraw):
		GroundsManager.grounds_updated.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-760, -160, 1520, 1000), BG)

	# The wild dark beyond the parcels (behind everything).
	_dead_tree(Vector2(-600, 330))
	_dead_tree(Vector2(620, 310))
	_dead_tree(Vector2(-300, -10))
	_dead_tree(Vector2(330, 640))
	for h in SURROUND:
		_headstone(Vector2(h.x, h.y), int(h.z), h.w)

	# Wilderness cells: rough untiled ground inside the grid but outside every
	# parcel — the land the graveyard hasn't tamed.
	for gy in range(IsoUtil.GRID):
		for gx in range(IsoUtil.GRID):
			var cell := Vector2i(gx, gy)
			if _parcel_at(cell) != null: continue
			var center := IsoUtil.cell_to_world(gx + 0.5, gy + 0.5)
			draw_colored_polygon(IsoUtil.tile_diamond(gx, gy), WILD)
			if (gx * 7 + gy * 13) % 5 == 0:
				draw_circle(center + Vector2(((gx * 31 + gy * 17) % 20) - 10, -3), 2.0, WILD_DOT)

	# Parcel cells: proper tiles when unlocked, dark hatched earth when not.
	for parcel_id in GroundsManager.parcel_db:
		var p: GroundsParcel = GroundsManager.parcel_db[parcel_id]
		var owned := GroundsManager.is_parcel_unlocked(parcel_id)
		for gy in range(p.origin.y, p.origin.y + p.size.y):
			for gx in range(p.origin.x, p.origin.x + p.size.x):
				var poly := IsoUtil.tile_diamond(gx, gy)
				if owned:
					draw_colored_polygon(poly, TILE_B if (gx + gy) % 2 == 0 else TILE_A)
					var outline := poly.duplicate()
					outline.append(poly[0])
					draw_polyline(outline, EDGE, 1.0, true)
				else:
					draw_colored_polygon(poly, LOCK_TILE)
					# Sparse diagonal hatch: unclaimed, untended earth.
					draw_line(
						IsoUtil.cell_to_world(gx + 0.15, gy + 0.85),
						IsoUtil.cell_to_world(gx + 0.85, gy + 0.15),
						LOCK_HATCH, 1.0)
		# A boundary line around every parcel so the land reads as land.
		var border := IsoUtil.footprint_polygon(p.origin, p.size)
		var closed := border.duplicate()
		closed.append(border[0])
		draw_polyline(closed, EDGE if owned else LOCK_HATCH, 1.5, true)

	# Worn paths: the Old Yard's spokes, extended into each parcel as bought.
	for parcel_id in PATHS:
		if not GroundsManager.is_parcel_unlocked(parcel_id):
			continue
		for segment in PATHS[parcel_id]:
			var pts := PackedVector2Array()
			for wp in segment:
				pts.append(IsoUtil.cell_to_world(wp.x, wp.y))
			draw_polyline(pts, PATH_EDGE, 15.0, true)
			draw_polyline(pts, PATH, 11.0, true)

	# In-plot dressing on owned land: headstones, a stray tree, lamp posts at
	# the path crossings.
	for parcel_id in PARCEL_PROPS:
		if not GroundsManager.is_parcel_unlocked(parcel_id):
			continue
		for prop in PARCEL_PROPS[parcel_id]:
			var pos := IsoUtil.cell_to_world(prop.x, prop.y)
			match int(prop.z):
				3: _small_tree(pos)
				4: _lamp_post(pos)
				_: _headstone(pos, int(prop.z), prop.w)

	# Iron fence along the two far edges of the whole grounds.
	_fence_edge(Vector2(0, 0), Vector2(IsoUtil.GRID, 0))
	_fence_edge(Vector2(0, 0), Vector2(0, IsoUtil.GRID))

	# The ritual circle in the Old Yard's heart.
	var c := IsoUtil.cell_to_world(CIRCLE_CELL.x, CIRCLE_CELL.y)
	draw_polyline(_iso_ellipse(c, 132.0, 66.0), CIRCLE, 2.0, true)
	draw_polyline(_iso_ellipse(c, 92.0, 46.0), CIRCLE_DIM, 1.5, true)
	draw_circle(c, 6.0, CIRCLE)
	for off in [Vector2(-64, -4), Vector2(64, -2), Vector2(-38, 18), Vector2(38, 18)]:
		draw_circle(c + off, 7.0, Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.18))
		draw_circle(c + off, 2.4, CANDLE)

func _parcel_at(cell: Vector2i) -> GroundsParcel:
	for parcel_id in GroundsManager.parcel_db:
		if GroundsManager.parcel_db[parcel_id].contains_cell(cell):
			return GroundsManager.parcel_db[parcel_id]
	return null

# --- Props ---

func _fence_edge(cell_a: Vector2, cell_b: Vector2) -> void:
	var steps := 24
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := IsoUtil.cell_to_world(lerpf(cell_a.x, cell_b.x, t), lerpf(cell_a.y, cell_b.y, t))
		draw_line(p, p + Vector2(0, -16), FENCE, 2.0)
		draw_circle(p + Vector2(0, -18), 2.0, FENCE_TIP)

func _headstone(pos: Vector2, kind: int, tilt: float) -> void:
	draw_set_transform(pos, deg_to_rad(tilt), Vector2.ONE)
	draw_colored_polygon(_iso_ellipse(Vector2(0, 3), 8, 4), HS_SHADOW)
	if kind == 1:
		draw_rect(Rect2(-2, -20, 4, 20), HS)
		draw_rect(Rect2(-8, -15, 16, 4), HS)
	elif kind == 2:
		draw_colored_polygon(PackedVector2Array([
			Vector2(-7, 0), Vector2(-7, -11), Vector2(2, -8), Vector2(7, -13), Vector2(7, 0)]), HS)
	else:
		draw_rect(Rect2(-6, -13, 12, 13), HS)
		draw_circle(Vector2(0, -13), 6, HS)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _dead_tree(pos: Vector2) -> void:
	draw_line(pos, pos + Vector2(0, -70), TREE, 6.0)
	for b in [Vector2(-20, -60), Vector2(18, -72), Vector2(-14, -82), Vector2(16, -74)]:
		draw_line(pos + Vector2(0, b.y + 10), pos + b, TREE, 4.0)

## A stunted in-plot tree, half the wilderness kind's size.
func _small_tree(pos: Vector2) -> void:
	draw_line(pos, pos + Vector2(0, -36), TREE, 4.0)
	for b in [Vector2(-11, -30), Vector2(10, -38), Vector2(-7, -42)]:
		draw_line(pos + Vector2(0, b.y + 6), pos + b, TREE, 2.5)

## A lamp post marking a path crossing, with a small warm flame.
func _lamp_post(pos: Vector2) -> void:
	draw_colored_polygon(_iso_ellipse(pos + Vector2(0, 2), 7, 3), HS_SHADOW)
	draw_line(pos, pos + Vector2(0, -34), FENCE, 2.5)
	draw_rect(Rect2(pos.x - 4, pos.y - 44, 8, 10), FENCE)
	draw_circle(pos + Vector2(0, -39), 6.0, Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.16))
	draw_rect(Rect2(pos.x - 2, pos.y - 42, 4, 6), CANDLE)

func _iso_ellipse(center: Vector2, rx: float, ry: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
