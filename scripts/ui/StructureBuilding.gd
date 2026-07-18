# StructureBuilding.gd
# One placed structure on the Grounds map. Reads its Structure + current level
# from GroundsManager and draws per-tier isometric art that grows as the
# structure is raised — ported from the approved concept mockup. Clickable via
# an Area2D footprint; emits `selected` for the view to inspect it.
#
# Art is dispatched by id (_draw_chapel / _ossuary / _grove / _lantern); any
# unknown id falls back to a plain box so future structures still render.
extends Node2D

signal selected(structure_id: String)

# Iso box + palette (mirrors the mockup / Lanternlight theme).
const TOP := Color("#3a2f57")
const FACE_L := Color("#2c2342")
const FACE_R := Color("#1d1630")
const ROOF_D := Color("#241c3c")
const ROOF_L := Color("#31274d")
const WARM := Color("#f0be62")
const WARM2 := Color("#e8b45a")
const FLAME := Color("#f6c968")
const DOOR := Color("#150f22")
const STONE := Color("#d8cdba")
const CAP := Color("#453a63")
const COLUMN := Color("#241c38")
const BARK := Color("#4a3d26")
const RUNE := Color("#7bc06a")
const POST := Color("#4a4560")
const SPIRE := Color("#5a4f70")
const SITE := Color("#5a4f70")
const COPPER := Color("#b06e3c")
const COPPER_LIT := Color("#d18a4e")
const GLASS := Color(0.78, 0.84, 0.95, 0.30)
const RELIC := Color("#9a7de0")
const SMOKE := Color(0.75, 0.72, 0.85, 0.18)
const COIN := Color("#e3bb63")
const GOLD := Color("#c8a24d")
const NAME_COL := Color("#e0d8c6")
const PIP_OFF := Color("#3a3350")
const SHADOW := Color(0.04, 0.03, 0.07, 0.4)

var structure_id: String = ""
var cell: Vector2i
var foot: Vector2i
var is_selected: bool = false
var _last_tier: int = -1

func setup(s: Structure) -> void:
	structure_id = s.id
	cell = s.grid_cell
	foot = s.footprint
	# Anchor at the footprint's front corner so it doubles as the Y-sort point.
	position = IsoUtil.cell_to_world(cell.x + foot.x, cell.y + foot.y)
	_build_area()
	if not GroundsManager.grounds_updated.is_connected(_on_changed):
		GroundsManager.grounds_updated.connect(_on_changed)
	_last_tier = GroundsManager.get_level(structure_id)
	queue_redraw()

## Footprint corners in local space (front corner C sits at the origin).
func _corners() -> Dictionary:
	return {
		"A": IsoUtil.cell_to_world(cell.x, cell.y) - position,
		"B": IsoUtil.cell_to_world(cell.x + foot.x, cell.y) - position,
		"C": Vector2.ZERO,
		"D": IsoUtil.cell_to_world(cell.x, cell.y + foot.y) - position,
	}

func _center() -> Vector2:
	var c := _corners()
	return (c.A + c.C) * 0.5

func _build_area() -> void:
	var area := Area2D.new()
	area.input_pickable = true
	var cp := CollisionPolygon2D.new()
	var c := _corners()
	cp.polygon = PackedVector2Array([c.A, c.B, c.C, c.D])
	area.add_child(cp)
	area.input_event.connect(_on_area_input)
	add_child(area)

func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(structure_id)

func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()

func _on_changed() -> void:
	var t := GroundsManager.get_level(structure_id)
	if _last_tier != -1 and t != _last_tier:
		_pop()
	_last_tier = t
	queue_redraw()

## A brief "just built" brighten when this structure's own tier changes.
func _pop() -> void:
	modulate = Color(1.5, 1.45, 1.2)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.35)

# --- Draw dispatch ---

func _draw() -> void:
	var s: Structure = GroundsManager.find_structure(structure_id)
	if s == null:
		return
	var tier := GroundsManager.get_level(structure_id)
	match structure_id:
		"chapel": _draw_chapel(tier)
		"ossuary": _draw_ossuary(tier)
		"wardens_grove": _draw_grove(tier)
		"grave_lantern": _draw_lantern(tier)
		"mausoleum": _draw_mausoleum(tier)
		"counting_house": _draw_counting_house(tier)
		"reliquary": _draw_reliquary(tier)
		"apothecary": _draw_apothecary(tier)
		_: _draw_generic(tier)

	if is_selected:
		var c := _corners()
		draw_polyline(_closed(PackedVector2Array([c.A, c.B, c.C, c.D])), GOLD, 3.0, true)
	# Nameplates moved to the GroundsLabels overlay so neighbors can't cover them.

# --- Shared iso helpers ---

func _box(h: float) -> Dictionary:
	var c := _corners()
	var up := Vector2(0, -h)
	var At: Vector2 = c.A + up
	var Bt: Vector2 = c.B + up
	var Ct: Vector2 = c.C + up
	var Dt: Vector2 = c.D + up
	draw_colored_polygon(PackedVector2Array([c.D, c.C, Ct, Dt]), FACE_L)
	draw_colored_polygon(PackedVector2Array([c.B, c.C, Ct, Bt]), FACE_R)
	draw_colored_polygon(PackedVector2Array([At, Bt, Ct, Dt]), TOP)
	return {
		"A": c.A, "B": c.B, "C": c.C, "D": c.D, "At": At, "Bt": Bt, "Ct": Ct, "Dt": Dt,
		"ctr": (At + Ct) * 0.5, "rf": (c.B + Ct) * 0.5, "lf": (c.D + Ct) * 0.5,
	}

func _L(a: Vector2, b: Vector2, u: float) -> Vector2:
	return a + (b - a) * u

func _ell_pts(center: Vector2, rx: float, ry: float, seg: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg):
		var ang := TAU * float(i) / float(seg)
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	return pts

func _fill_ell(center: Vector2, rx: float, ry: float, color: Color) -> void:
	draw_colored_polygon(_ell_pts(center, rx, ry), color)

func _draw_site() -> void:
	var c := _corners()
	var pts := [c.A, c.B, c.C, c.D]
	for i in range(4):
		draw_dashed_line(pts[i], pts[(i + 1) % 4], SITE, 1.5, 6.0)

func _alpha(color: Color, a: float) -> Color:
	return Color(color.r, color.g, color.b, a)

# --- Per-structure art ---

func _draw_chapel(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	var h := 28.0 + t * 11.0
	var b := _box(h)
	var ap: Vector2 = b.ctr + Vector2(0, -(14.0 + t * 5.0))
	draw_colored_polygon(PackedVector2Array([b.Bt, b.Ct, ap]), ROOF_D)
	draw_colored_polygon(PackedVector2Array([b.Ct, b.Dt, ap]), ROOF_L)
	draw_line(ap, ap + Vector2(0, -(8.0 + t * 5.0)), SPIRE, 2.5)
	var cross_y := ap.y - (4.0 + t * 4.0)
	draw_line(Vector2(ap.x - 5, cross_y), Vector2(ap.x + 5, cross_y), SPIRE, 2.5)
	if t >= 5:
		draw_colored_polygon(PackedVector2Array([
			Vector2(ap.x, ap.y - 33), Vector2(ap.x + 14, ap.y - 28), Vector2(ap.x, ap.y - 23)]), GOLD)
	var n: int = mini(t, 4)
	for i in range(n):
		var w := _L(b.B, b.C, float(i + 1) / float(n + 1))
		draw_rect(Rect2(w.x - 4, w.y - h * 0.62, 9, 13 + t), _alpha(WARM, 0.9))
	if t >= 2:
		var lw := _L(b.D, b.C, 0.5)
		draw_rect(Rect2(lw.x - 4, lw.y - h * 0.6, 8, 12 + t), _alpha(WARM2, 0.75))
	if t >= 3:
		for u in [0.22, 0.78]:
			var sp := _L(b.D, b.C, u)
			draw_colored_polygon(PackedVector2Array([
				Vector2(sp.x - 10, sp.y), Vector2(sp.x, sp.y - h * 0.5), sp]), FACE_L)
	var dr := _L(b.D, b.C, 0.5)
	draw_rect(Rect2(dr.x - 6, dr.y - 20, 12, 20), DOOR)

func _draw_ossuary(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	var h := 24.0 + t * 6.0
	var b := _box(h)
	var lift := Vector2(0, -(3.0 + t * 2.0))
	draw_colored_polygon(PackedVector2Array([b.At + lift, b.Bt + lift, b.Ct + lift, b.Dt + lift]),
		GOLD if t >= 5 else CAP)
	var n := 2 + t
	for i in range(n):
		var col := _L(b.B, b.C, (i + 0.5) / float(n))
		draw_rect(Rect2(col.x - 2.5, col.y - h * 0.92, 5, h * 0.9), COLUMN)
	var sk := 6.0 + t
	draw_circle(b.ctr + Vector2(0, -4), sk, STONE)
	draw_circle(b.ctr + Vector2(-sk * 0.4, -5), sk * 0.22, DOOR)
	draw_circle(b.ctr + Vector2(sk * 0.4, -5), sk * 0.22, DOOR)
	if t >= 3:
		var bp := _L(b.D, b.C, 0.7)
		draw_circle(bp, 5, STONE)
		draw_circle(bp + Vector2(-7, 2), 4, Color("#b8afa0"))
		draw_circle(bp + Vector2(6, 2), 4, Color("#c4bbab"))
	var dr := _L(b.D, b.C, 0.5)
	draw_rect(Rect2(dr.x - 6, dr.y - 17, 12, 17), DOOR)

func _draw_grove(t: int) -> void:
	var ctr := _center()
	_fill_ell(ctr + Vector2(0, 4), 20.0 + t * 7.0, 9.0 + t * 2.0, SHADOW)
	if t >= 4:
		_fill_ell(ctr + Vector2(0, 2), 24.0 + t * 6.0, 10.0 + t * 2.0, Color(0.30, 0.60, 0.28, 0.10))
	var spread := [Vector2(-28, 8), Vector2(0, -4), Vector2(26, 10), Vector2(-6, -2),
		Vector2(14, -6), Vector2(-16, 12), Vector2(8, 14)]
	var n: int = mini(t + 1, 7)
	var hgt := 22.0 + t * 6.0
	for i in range(n):
		var o: Vector2 = ctr + spread[i]
		draw_line(o, o + Vector2(0, -hgt), BARK, 4.0)
		draw_line(o + Vector2(0, -hgt * 0.6), o + Vector2(-13, -hgt * 0.6 - 11), BARK, 4.0)
		draw_line(o + Vector2(0, -hgt * 0.78), o + Vector2(15, -hgt * 0.78 - 9), BARK, 4.0)
		draw_line(o + Vector2(0, -hgt * 0.92), o + Vector2(-9, -hgt * 0.92 - 11), BARK, 4.0)
	if t >= 4:
		draw_circle(ctr + Vector2(0, 4), 2.5, RUNE)
		draw_circle(ctr + Vector2(14, 0), 2.0, RUNE)

func _draw_lantern(t: int) -> void:
	var ctr := _center()
	if t <= 0:
		_draw_site()
		draw_line(ctr, ctr + Vector2(0, -24), FACE_L, 6.0)
		draw_rect(Rect2(ctr.x - 6, ctr.y - 36, 12, 14), FACE_L)
		return
	var glow := t * 30.0
	_fill_ell(ctr, glow * 1.9, glow * 0.95, _alpha(WARM, 0.07))
	_fill_ell(ctr, glow * 1.1, glow * 0.55, _alpha(WARM, 0.08))
	_fill_ell(ctr + Vector2(0, -6), 16, 8, SHADOW)
	draw_rect(Rect2(ctr.x - 9, ctr.y - 22, 18, 16), FACE_L)
	var post_h := 30.0 + t * 15.0
	var ly := ctr.y - 18.0 - post_h
	draw_line(Vector2(ctr.x, ctr.y - 18), Vector2(ctr.x, ly), POST, 6.0)
	if t >= 3:
		draw_line(Vector2(ctr.x - 16, ly + 18), Vector2(ctr.x - 16, ly + 30), SPIRE, 2.0)
		draw_rect(Rect2(ctr.x - 21, ly + 30, 10, 12), FACE_L)
		draw_rect(Rect2(ctr.x - 19, ly + 32, 6, 8), WARM)
	var lamp := 8.0 + t * 2.4
	draw_rect(Rect2(ctr.x - lamp, ly - lamp * 1.7, lamp * 2, lamp * 2.1), FACE_L)
	draw_rect(Rect2(ctr.x - lamp * 0.6, ly - lamp * 1.3, lamp * 1.2, lamp * 1.5), FLAME)
	draw_colored_polygon(PackedVector2Array([
		Vector2(ctr.x, ly - lamp * 1.7),
		Vector2(ctr.x - lamp, ly - lamp * 1.7 - 8),
		Vector2(ctr.x + lamp, ly - lamp * 1.7 - 8)]), GOLD if t >= 5 else FACE_L)

## The Mausoleum: a stone tomb that gains columns, a pediment, and flanking
## urns as the honored dead move in.
func _draw_mausoleum(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	var h := 20.0 + t * 7.0
	var b := _box(h)
	# Colonnade across the right face, one more column per tier.
	var n: int = 1 + mini(t, 4)
	for i in range(n):
		var col := _L(b.B, b.C, (i + 0.5) / float(n))
		draw_rect(Rect2(col.x - 2.5, col.y - h * 0.9, 5, h * 0.88), COLUMN)
	# The pediment: a shallow stone gable riding the roofline.
	var peak: Vector2 = b.ctr + Vector2(0, -(8.0 + t * 3.0))
	draw_colored_polygon(PackedVector2Array([b.Bt, b.Ct, peak]), ROOF_D)
	draw_colored_polygon(PackedVector2Array([b.Ct, b.Dt, peak]), ROOF_L)
	if t >= 2:
		draw_line(b.Bt, peak, CAP, 1.5)
		draw_line(b.Dt, peak, CAP, 1.5)
	# The sealed door — stone, not wood; the dead of means knock from inside.
	var dr := _L(b.D, b.C, 0.5)
	draw_rect(Rect2(dr.x - 7, dr.y - 22, 14, 22), DOOR)
	draw_arc(dr + Vector2(0, -22), 7.0, PI, TAU, 16, CAP, 2.0)
	if t >= 3:
		for u in [0.15, 0.85]:
			var urn := _L(b.D, b.C, u)
			draw_circle(urn + Vector2(0, -6), 4.0, STONE)
			draw_rect(Rect2(urn.x - 2, urn.y - 3, 4, 3), STONE)
	if t >= 4:
		draw_rect(Rect2(peak.x - 2, peak.y - 10, 4, 10), CAP)
	if t >= 5:
		draw_circle(peak + Vector2(0, -14), 4.0, GOLD)

## The Counting House: a timbered ledger-den. The coin sign grows with the
## takings and the chimney smokes while the books are cooked.
func _draw_counting_house(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	var h := 24.0 + t * 8.0
	var b := _box(h)
	# Timber framing on both faces.
	for u in [0.25, 0.75]:
		var fl := _L(b.D, b.C, u)
		draw_line(fl, fl + Vector2(0, -h * 0.9), BARK, 2.0)
		var fr := _L(b.B, b.C, u)
		draw_line(fr, fr + Vector2(0, -h * 0.9), BARK, 2.0)
	draw_line(_L(b.D, b.C, 0.0) + Vector2(0, -h * 0.55), _L(b.D, b.C, 1.0) + Vector2(0, -h * 0.55), BARK, 2.0)
	# A lit ledger window per tier (cap 3) — someone is always counting.
	var n: int = mini(t, 3)
	for i in range(n):
		var w := _L(b.B, b.C, float(i + 1) / float(n + 1))
		draw_rect(Rect2(w.x - 4, w.y - h * 0.6, 8, 9), _alpha(WARM, 0.85))
	# The hanging coin sign, larger as the house's cut grows.
	var sp := _L(b.D, b.C, 0.22)
	var r := 4.0 + t * 1.2
	draw_line(sp + Vector2(0, -h * 0.78), sp + Vector2(0, -h * 0.78 + 8), POST, 2.0)
	draw_circle(sp + Vector2(0, -h * 0.78 + 8 + r), r, COIN)
	draw_arc(sp + Vector2(0, -h * 0.78 + 8 + r), r * 0.55, 0, TAU, 16, _alpha(DOOR, 0.6), 1.5)
	if t >= 2:
		var ch: Vector2 = b.At + Vector2(6, 4)
		draw_rect(Rect2(ch.x - 3, ch.y - 12, 6, 12), COLUMN)
		draw_circle(ch + Vector2(2, -16), 3.0, SMOKE)
		draw_circle(ch + Vector2(5, -22), 4.0, SMOKE)
	if t >= 4:
		var st := _L(b.D, b.C, 0.7)
		for i in range(3):
			draw_rect(Rect2(st.x - 3 + i, st.y - 2 - i * 2, 6, 2), COIN)
	var dr := _L(b.D, b.C, 0.5)
	draw_rect(Rect2(dr.x - 5, dr.y - 16, 10, 16), DOOR)
	if t >= 5:
		draw_circle(b.ctr + Vector2(0, -6), 5.0, GOLD)

## The Reliquary: a stepped shrine whose glass case holds a relic that burns
## brighter — and hungrier — with every tier.
func _draw_reliquary(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	var c := _center()
	var glow := 10.0 + t * 7.0
	_fill_ell(c + Vector2(0, -8), glow * 1.6, glow * 0.8, _alpha(RELIC, 0.06))
	_fill_ell(c + Vector2(0, -8), glow, glow * 0.5, _alpha(RELIC, 0.08))
	# Stepped plinth: one stone step per two tiers.
	var steps: int = 1 + int(t / 2.0)
	for i in range(steps):
		var w := 22.0 - i * 5.0
		var y := -i * 5.0
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-w, y), c + Vector2(0, y + w * 0.5), c + Vector2(w, y), c + Vector2(0, y - w * 0.5)]),
			FACE_L if i % 2 == 0 else CAP)
	var top := c + Vector2(0, -steps * 5.0 - 4.0)
	# The glass case and the relic inside.
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(-9, 0), top + Vector2(-9, -18), top + Vector2(0, -22),
		top + Vector2(9, -18), top + Vector2(9, 0)]), GLASS)
	var relic_r := 3.0 + t * 0.8
	draw_circle(top + Vector2(0, -10), relic_r, RELIC)
	draw_circle(top + Vector2(-1, -11), relic_r * 0.45, Color(0.95, 0.9, 1.0, 0.9))
	if t >= 3:
		for off in [Vector2(-16, 2), Vector2(16, 2)]:
			draw_line(top + off, top + off + Vector2(0, -6), POST, 1.5)
			draw_circle(top + off + Vector2(0, -8), 1.6, FLAME)
	if t >= 5:
		draw_arc(top + Vector2(0, -10), relic_r + 5.0, 0, TAU, 24, _alpha(GOLD, 0.7), 1.5)

## The Apothecary: copper stills multiply and vent stranger smoke as the
## Caretaker's brewing operation industrializes.
func _draw_apothecary(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	var h := 18.0 + t * 5.0
	var b := _box(h)
	# Slanted lean-to roof rising toward the back.
	draw_colored_polygon(PackedVector2Array([b.At, b.Bt, b.Bt + Vector2(0, -8), b.At + Vector2(0, -12)]), ROOF_L)
	# Copper stills along the left face — one more kettle per two tiers.
	var kettles: int = 1 + int(mini(t, 4) / 2.0) + (1 if t >= 5 else 0)
	for i in range(kettles):
		var kp := _L(b.D, b.C, (i + 0.6) / float(kettles + 0.4))
		var kr := 5.0 + t * 0.8
		draw_circle(kp + Vector2(0, -kr - 2), kr, COPPER)
		draw_circle(kp + Vector2(-kr * 0.3, -kr - 3), kr * 0.35, COPPER_LIT)
		# The swan-neck pipe.
		draw_arc(kp + Vector2(kr * 0.4, -kr * 2.0), kr * 0.9, PI, PI + 1.8, 10, COPPER_LIT, 2.0)
		if t >= 3:
			draw_circle(kp + Vector2(kr, -kr * 2.6), 2.5, SMOKE)
			draw_circle(kp + Vector2(kr + 3, -kr * 2.6 - 5), 3.2, SMOKE)
	# Shelved bottles glinting on the right face.
	var n: int = mini(t + 1, 5)
	for i in range(n):
		var bp := _L(b.B, b.C, float(i + 1) / float(n + 1))
		draw_rect(Rect2(bp.x - 1.5, bp.y - h * 0.55, 3, 6), _alpha(RUNE, 0.9) if i % 2 == 0 else _alpha(RELIC, 0.9))
	var dr := _L(b.B, b.C, 0.5)
	draw_rect(Rect2(dr.x - 5, dr.y - 15, 10, 15), DOOR)
	if t >= 5:
		var gp := _L(b.D, b.C, 0.85)
		draw_circle(gp + Vector2(0, -h * 0.9), 4.0, GOLD)

func _draw_generic(t: int) -> void:
	if t <= 0:
		_draw_site()
		return
	_box(26.0 + t * 10.0)

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var p := pts.duplicate()
	p.append(pts[0])
	return p
