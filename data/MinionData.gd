class_name Minion
extends Resource

@export_category("Identity")
@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""

@export_category("Base Combat Stats")
@export var base_hp: int = 10
@export var base_atk: float = 1.0

@export_category("Stat Growth Curves")
@export var hp_per_level: int = 5
@export var atk_per_level: float = 0.5

@export_category("Leveling Cost Requirements")
## Simply check the boxes or fill out the dictionary using static keys.
## To make this completely error-proof, we type-hint it so you just type numbers.
@export var requirements: Dictionary[String, int] = {
	"flesh": 0, # Still Flesh
	"blood": 0, # Coagulated Blood
	"marrow": 0, # Raw Marrow
	"bones": 0, # Brittle Bones
	"beast_urn": 0, # Beast Reliquary
	"grave_dust": 0, # Grave Dust
	"rotten_meat": 0, # Putrid Meat
	"beast_claws": 0, # Serrated Claws
	"bile": 0, # Fetid Bile
	"chains": 0, # Shackle Links
	"skulls": 0, # Fractured Skulls
	"ectoplasm": 0, # Ectoplasm
	"wax": 0, # Vigil Wax
	"beads": 0, # Gilded Rosary Beads
	"ashes": 0, # Censer Ashes
}