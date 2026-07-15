# IsoUtil.gd
# Shared isometric projection helpers for the Grounds view. One source of truth
# for tile size and cell -> world math, used by the ground, the camera framing,
# and (from M2) structure placement + click footprints.
class_name IsoUtil
extends RefCounted

## Full iso tile diamond size in world units (2:1 classic isometric).
const TILE_W: float = 96.0
const TILE_H: float = 48.0
## The plot is a GRID x GRID field of tiles.
const GRID: int = 5

## Grid cell (may be fractional) -> world position of that cell's top corner.
static func cell_to_world(cx: float, cy: float) -> Vector2:
	return Vector2((cx - cy) * TILE_W * 0.5, (cx + cy) * TILE_H * 0.5)

## The four corners of tile (cx, cy) as a closed-ready diamond.
static func tile_diamond(cx: int, cy: int) -> PackedVector2Array:
	return PackedVector2Array([
		cell_to_world(cx, cy),
		cell_to_world(cx + 1, cy),
		cell_to_world(cx + 1, cy + 1),
		cell_to_world(cx, cy + 1),
	])

## Footprint diamond for a building anchored at `cell` spanning `foot` tiles.
static func footprint_polygon(cell: Vector2i, foot: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		cell_to_world(cell.x, cell.y),
		cell_to_world(cell.x + foot.x, cell.y),
		cell_to_world(cell.x + foot.x, cell.y + foot.y),
		cell_to_world(cell.x, cell.y + foot.y),
	])

## World position of the plot's centre (for camera framing / the ritual circle).
static func plot_center() -> Vector2:
	return cell_to_world(GRID * 0.5, GRID * 0.5)
