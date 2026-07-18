# ParcelData.gd
# One purchasable parcel of the Grounds: a rectangle of grid cells that must be
# bought (gold only — the Counting House's sell bonus finally has a job) before
# the structures standing on it can be raised. The starting parcel has
# cost_gold = 0 and is always unlocked. Loaded from data/parcels/ into
# GroundsManager.parcel_db.
extends Resource
class_name GroundsParcel

@export_group("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
## Position in deed listings and unlock order hints (lower = earlier).
@export var sort_order: int = 0

@export_group("Land")
## Top corner cell of the parcel's rectangle on the iso grid.
@export var origin: Vector2i = Vector2i.ZERO
## Size in cells.
@export var size: Vector2i = Vector2i(3, 3)

@export_group("Deed")
## Gold price to unlock. 0 = free land, unlocked from the start.
@export var cost_gold: int = 0

## True when `cell` lies inside this parcel.
func contains_cell(cell: Vector2i) -> bool:
	return cell.x >= origin.x and cell.x < origin.x + size.x \
		and cell.y >= origin.y and cell.y < origin.y + size.y

## True when a footprint anchored at `cell` spanning `foot` fits fully inside.
func contains_footprint(cell: Vector2i, foot: Vector2i) -> bool:
	return contains_cell(cell) and contains_cell(cell + foot - Vector2i.ONE)
