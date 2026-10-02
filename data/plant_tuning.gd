class_name PlantTuning
extends Resource
## Plant simulation numbers (GDD §4). Saved as data/plant_tuning.tres; keep it in sync with the GDD.

@export var subsystems: Array[SubsystemData] = []  ## index order = PlantModel / synced array order

@export_group("Core temperature")
@export var nominal_temp := 300.0  ## cooling only works above this
@export var min_temp := 300.0
@export var max_temp := 1000.0
@export var cooling_rate := 1.5  ## units/s
@export var warning_temp := 500.0  ## alarm WARNING from here
@export var critical_temp := 700.0  ## alarm CRITICAL from here

@export_group("Meltdown")
@export var meltdown_start_temp := 700.0  ## the meter fills above this
@export var meltdown_fill_rate := 1.0  ## %/s per 100 units above meltdown_start_temp
@export var meltdown_recover_temp := 400.0  ## the meter drains below this
@export var meltdown_decay_rate := 0.25  ## %/s

@export_group("Sabotage")
@export var max_health := 100.0
@export var sabotage_damage := 50.0
@export var critical_sabotage_damage := 100.0
@export var sabotage_cooldown_s := 20.0  ## per subsystem, after a successful sabotage
@export var sabotage_hold_s := 4.0
@export var critical_hold_s := 6.0  ## both levers held at the same time

@export_group("Repair")
@export var repair_amount := 35.0  ## hold repair
@export var repair_hold_s := 6.0
@export var reboot_hold_s := 3.0  ## needed first when health hit 0
@export var minigame_repair_amount := 50.0  ## a won repair minigame (M6)
@export var minigame_fail_amount := 10.0  ## a lost one still helps a little…
@export var minigame_lockout_s := 3.0  ## …but locks that repair point for everyone this long
@export var minigame_min_s := 3.0  ## the server refuses results that arrive faster (hacked clients)
@export var minigame_max_s := 30.0  ## a minigame left open longer is cancelled

@export_group("Control room")
@export var scram_heat_factor := 0.5  ## heat_in multiplier while SCRAM is active
@export var scram_duration_s := 30.0
@export var scram_cooldown_s := 120.0
@export var scram_time_penalty_s := 30  ## added to the match timer: the shift gets longer
@export var coolant_amount := 150.0  ## emergency coolant: core_temp drops this much
@export var coolant_cooldown_s := 90.0
@export var coolant_min_grid_health := 25.0  ## the pumps need power
