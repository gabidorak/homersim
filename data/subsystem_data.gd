class_name SubsystemData
extends Resource
## One plant subsystem (GDD §4). Saved as data/subsystems/*.tres and listed, in order, in
## data/plant_tuning.tres: that order is the index used by PlantModel and the synced arrays.

enum HazardKind { NONE, RADIATION, STEAM, DEBRIS, ELECTRIC, SMOKE }

@export var id: StringName = &""
@export var display_name := ""
@export var short_name := ""  ## 3-4 letters for the HUD icon
@export var heat_weight := 1.0  ## heat units/s added when fully broken
@export var critical := false  ## sabotaged with a lever pair (2 rats) instead of normal points
@export var hazard_kind := HazardKind.NONE  ## used from M6
@export var icon: Texture2D  ## optional; the HUD falls back to short_name
