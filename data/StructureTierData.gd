class_name StructureTier
extends Resource

## One upgrade step of a Structure: what it costs to build and how much it
## adds to the structure's effect. Tiers stack — the structure's total effect
## is the sum of every tier built so far.

## Material recipe for this tier: { item_id: amount }.
@export var cost: Dictionary[String, int] = {}

## Gold component of this tier's cost (P4 / DEP-4 gold sink). 0 = free.
@export var gold: int = 0

## Effect magnitude ADDED when this tier is built (cumulative up the ladder).
@export var magnitude: float = 0.0

## Optional one-line flavour shown on the tier.
@export_multiline var blurb: String = ""
