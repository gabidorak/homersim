class_name HazardTuning
extends Resource
## Hazard numbers (GDD §6). Saved as data/hazard_tuning.tres; keep it in sync with the GDD.
## Tune the stun lengths here after playtests: hazards should be funny, not frustrating.

const PATH := "res://data/hazard_tuning.tres"

@export_group("Activation")
@export var on_below_health := 50.0  ## a subsystem's hazards switch on below this…
@export var off_at_health := 60.0  ## …and off again at or above this (hysteresis)

@export_group("Steam jets")
@export var steam_on_s := 3.0
@export var steam_off_s := 3.0
@export var steam_knockback := 6.0  ## m/s, away from the nozzle
@export var steam_lift := 3.0  ## m/s up, so the victim flies a little instead of skidding
@export var steam_stun_s := 1.0

@export_group("Electric puddles")
@export var puddle_live_s := 2.0
@export var puddle_period_s := 5.0  ## live puddle_live_s out of every puddle_period_s
@export var puddle_stun_s := 1.5
@export var puddle_slow := 0.5
@export var puddle_slow_s := 2.0  ## after the stun

@export_group("Radiation")
@export var radiation_exposure_s := 5.0  ## inside this long before it bites; it drains as fast outside
@export var radiation_slow := 0.8
@export var radiation_reveal_after_s := 5.0  ## still revealed this long after leaving

@export_group("Turbine debris")
@export var debris_interval_s := 8.0
@export var debris_warning_s := 1.0
@export var debris_radius := 1.5  ## m around the impact point
@export var debris_knockdown_s := 3.0  ## supervisors
@export var debris_stun_s := 2.0  ## rats

@export_group("Smoke")
@export var smoke_visibility := 6.0  ## m, roughly where you stop seeing anything (cosmetic only)


static func load_default() -> HazardTuning:
	return load(PATH)
