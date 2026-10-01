class_name PvpTuning
extends Resource
## Player-vs-player numbers that aren't an ability (GDD §5): carrying, cages, stealing, pickups,
## doors, CCTV, traps. Saved as data/pvp_tuning.tres; keep it in sync with the GDD.

const PATH := "res://data/pvp_tuning.tres"

@export_group("Capture")
@export var carry_max_s := 8.0  ## a carried rat escapes on its own after this
@export var drop_invulnerable_s := 1.5  ## a dropped rat (escape, bite on the carrier)
@export var free_hold_s := 4.0  ## rat hold at a cage
@export var freed_invulnerable_s := 3.0
@export var captures_to_eliminate := 2  ## the Nth capture eliminates instead of caging

@export_group("Stealing")
@export var steal_hold_s := 1.0
@export var stolen_item_speed := 0.9  ## speed factor of a rat carrying a stolen item
@export var spare_keycard_delay_s := 30.0  ## after a loss, before Storage hands out a spare

@export_group("Pickups and doors")
@export var donut_speed := 1.2
@export var donut_duration_s := 20.0
@export var donut_cooldown_s := 60.0  ## per supervisor
@export var keycard_door_open_s := 3.0

@export_group("CCTV")
@export var cctv_break_hold_s := 2.0  ## rat hold to break a camera
@export var cctv_repair_hold_s := 3.0  ## supervisor hold to repair it

@export_group("Traps")
@export var trap_charges := 3
@export var trap_min_spacing := 0.6  ## m between two traps


static func load_default() -> PvpTuning:
	return load(PATH)
