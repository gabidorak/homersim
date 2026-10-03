class_name BotSkill
extends Resource
## One AI difficulty preset (GDD §5.5). data/bot_tuning.tres lists three, easy → normal → hard;
## MatchRules.bot_difficulty picks one. Keep them in sync with the GDD table.

@export var label := "Normal"
@export var reaction_s := 0.4  ## continuous sight before an enemy counts as seen
@export var aim_error_deg := 15.0  ## random error on a broom swing's aim
@export var turn_rate_deg := 400.0  ## how fast the body turns, °/s
@export var view_range := 22.0  ## m
@export var think_hz := 5.0  ## decisions per second
@export_range(0.0, 1.0) var trap_notice := 0.75  ## chance to notice a trap within 6 m, in sight
@export var teamwork := true  ## lever pairs and gang bites
