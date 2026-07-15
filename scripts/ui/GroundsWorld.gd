# GroundsWorld.gd
# The isometric world drawn inside the Grounds SubViewport: the dark backdrop,
# the tiled plot, the central ritual circle, and (M4) the graveyard dressing —
# a back fence, candles, and headstones/dead trees framing the grounds. The
# StructureBuilding nodes are added on top as Y-sorted children by the view.
extends Node2D

const BG := Color("#12101d")
const TILE_A := Color("#1a1430")
const TILE_B := Color("#1e1836")
const EDGE := Color("#282240")
const CIRCLE := Color(0.541, 0.435, 0.745, 0.9)
const CIRCLE_DIM := Color(0.427, 0.353, 0.627, 0.9)
const FENCE := Color("#4a4560")
const FENCE_TIP := Color("#5a5273")
const HS := Color("#3b3450")
const HS_EDGE := Color("#565073")
const HS_SHADOW := Color(0.04, 0.03, 0.06, 0.5)
const CANDLE := Color("#f0be62")
const TREE := Color("#3d3320")

## Headstones scattered in the dark beyond the plot: (x, y, kind, tilt°).
const SURROUND := [
	Vector4(-300, 60, 0, -6), Vector4(300, 54, 1, 5), Vector4(-332, 140, 2, -4),
	Vector4(326, 150, 0, 6), Vector4(-252, 206, 1, -3), Vector4(252, 206, 2, 4),
	Vector4(-140, 256, 0, 7), Vector4(150, 258, 1, -5), Vector4(0, -34, 0, 3),
]

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-540, -240, 1080, 760), BG)

	# Surrounding graveyard (behind the plot).
	_dead_tree(Vector2(-322, 108))
	_dead_tree(Vector2(330, 96))
	for h in SURROUND:
		_headstone(Vector2(h.x, h.y), int(h.z), h.w)

	# Iso ground tiles.
	for gy in range(IsoUtil.GRID):
		for gx in range(IsoUtil.GRID):
			var poly := IsoUtil.tile_diamond(gx, gy)
			draw_colored_polygon(poly, TILE_B if (gx + gy) % 2 == 0 else TILE_A)
			var outline := poly.duplicate()
			outline.append(poly[0])
			draw_polyline(outline, EDGE, 1.0, true)

	# Iron fence along the two far edges.
	_fence_edge(Vector2(0, 0), Vector2(IsoUtil.GRID, 0))
	_fence_edge(Vector2(0, 0), Vector2(0, IsoUtil.GRID))

	# Central ritual circle + candles.
	var c := IsoUtil.plot_center()
	draw_polyline(_iso_ellipse(c, 150.0, 75.0), CIRCLE, 2.0, true)
	draw_polyline(_iso_ellipse(c, 104.0, 52.0), CIRCLE_DIM, 1.5, true)
	draw_circle(c, 6.0, CIRCLE)
	for off in [Vector2(-70, -4), Vector2(70, -2), Vector2(-40, 20), Vector2(40, 20)]:
		draw_circle(c + off, 7.0, Color(CANDLE.r, CANDLE.g, CANDLE.b, 0.18))
		draw_circle(c + off, 2.4, CANDLE)

# --- Props ---

func _fence_edge(cell_a: Vector2, cell_b: Vector2) -> void:
	var steps := 10
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

func _iso_ellipse(center: Vector2, rx: float, ry: float, segments: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
