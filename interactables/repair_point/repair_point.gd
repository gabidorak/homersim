class_name RepairPoint
extends Interactable
## Supervisor repairs (GDD §4.4). Two ways, both accepted by the server:
##   minigame (M6, the default): E opens the subsystem's minigame (MinigameService); a win gives
##            +50 health, a loss +10 and jams this point for 3 s (for everyone).
##   hold     (accessibility, the M3 fallback; `--hold-repairs` until M8's settings toggle): hold E
##            for 6 s, +35 health.
## A subsystem at 0 health needs a 3 s "Reboot" hold first, either way.
## Synced on top of the progress ring: `lockout_until` (server clock) and `minigame_user`
## (who is playing the minigame here: one at a time).

@export var subsystem_id: StringName = &"pumps"

var index := -1

# --- Replicated by the Sync child --------------------------------------------------------
var lockout_until := 0.0  ## server clock: jammed until then
var minigame_user := 0  ## peer playing the minigame here, 0 = nobody

var _last_health := -1.0

@onready var _lamp: Node3D = Art.part(get_node_or_null("Model"), "Lamp")


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	prompt = "Repair"


func _enter_tree() -> void:
	super()
	add_to_group(MatchManager.RESET_GROUP)


func _ready() -> void:
	super()
	index = _plant().index_of(subsystem_id)
	if index == -1:
		Log.error("interact", "%s: unknown subsystem '%s'" % [get_path(), subsystem_id])
	duration_s = _plant().tuning.repair_hold_s


func _synced_properties() -> Array[String]:
	var list := super()
	list.append_array(["lockout_until", "minigame_user"])
	return list


func _rebooting() -> bool:
	return _plant().needs_reboot(index)


func hold_duration() -> float:
	return _plant().tuning.reboot_hold_s if _rebooting() else _plant().tuning.repair_hold_s


func lockout_left() -> float:
	return maxf(lockout_until - Net.server_time(), 0.0)


## Health below max (or offline): there is something to repair.
func needs_repair() -> bool:
	return index != -1 and (_rebooting() or _plant().health(index) < _plant().tuning.max_health)


func is_available(_player: Player) -> bool:
	return needs_repair() and lockout_left() <= 0.0


## The minigame for this subsystem ("wrench_rhythm"…).
func minigame_kind() -> String:
	return _plant().data(index).minigame


## A minigame can start here for `player`: not a reboot, and nobody else is playing it.
func minigame_available(player: Player) -> bool:
	return is_available(player) and not _rebooting() and (minigame_user == 0 or minigame_user == player.peer_id)


## Client: E should open the minigame rather than start a hold (the player's setting).
func prefers_minigame(player: Player) -> bool:
	return Config.minigame_repairs and minigame_available(player)


func prompt_for(player: Player) -> String:
	var plant := _plant()
	var subsystem := plant.data(index).display_name
	if lockout_left() > 0.0:
		return "%s jammed: %d s" % [subsystem, ceili(lockout_left())]
	if _rebooting():
		return "Reboot %s (hold)" % subsystem
	if plant.health(index) >= plant.tuning.max_health:
		return "%s is fine" % subsystem
	if minigame_user != 0 and minigame_user != player.peer_id and Config.minigame_repairs:
		return "%s is fixing %s" % [Session.current.name_of(minigame_user), subsystem]
	return "Repair %s (%d%%)" % [subsystem, roundi(plant.health(index))]


## Server (MatchManager, at every match start).
func reset_for_match() -> void:
	lockout_until = 0.0
	minigame_user = 0


func _complete(player: Player) -> void:
	if _rebooting():
		_plant().reboot(index, [player.peer_id])
	else:
		_plant().apply_repair(index, _plant().tuning.repair_amount, [player.peer_id])
	super(player)


# --- Server: minigame outcomes (MinigameService) -----------------------------------------------

func minigame_won(player: Player) -> void:
	_plant().apply_repair(index, _plant().tuning.minigame_repair_amount, [player.peer_id])


func minigame_lost(player: Player) -> void:
	_plant().apply_repair(index, _plant().tuning.minigame_fail_amount, [player.peer_id])
	_jam()


## A result the server didn't believe (too fast): no repair, and the point jams.
func minigame_rejected(_player: Player) -> void:
	_jam()


func _jam() -> void:
	lockout_until = Net.server_time() + _plant().tuning.minigame_lockout_s
	holders.clear()  # holds stop too: is_available() fails until the lockout ends
	_publish()


# Cosmetic: lamp green when healthy, orange when damaged, blinking red when it needs a reboot,
# flickering yellow while jammed. A chime and sparkles when the subsystem's health jumps up
# (a repair landed), a fizzle and sparks when it drops (a sabotage).
func _process(_delta: float) -> void:
	if index == -1:
		return
	var color := Color(0.2, 0.9, 0.3)
	if lockout_left() > 0.0:
		color = Color(1, 0.9, 0.1) if Time.get_ticks_msec() % 200 < 100 else Color(0.3, 0.25, 0)
	elif _rebooting():
		color = Color(1, 0.1, 0.1) if Time.get_ticks_msec() % 600 < 300 else Color(0.3, 0, 0)
	elif _plant().health(index) < _plant().tuning.max_health:
		color = Color(1, 0.55, 0.1)
	if _lamp != null:
		Art.set_tint(_lamp, color)
		Art.set_glow(_lamp, 1.5)
	var health := _plant().health(index)
	if _last_health >= 0.0 and Session.current.match_manager.state == MatchManager.State.PLAYING:
		var front := global_position + global_basis.z * 0.1
		if health >= _last_health + 5.0:
			Sfx.play_at(self, "repair_done", front)
			Vfx.sparks(self, front, 14, Color(0.6, 1.0, 0.5))
		elif health <= _last_health - 5.0:
			Sfx.play_at(self, "sabotage_done", front - global_basis.z * 0.5)
			Vfx.sparks(self, front - global_basis.z * 0.5, 24)
			Vfx.puff(self, front - global_basis.z * 0.5, Color(0.3, 0.3, 0.3, 0.8), 8, 0.5)
	_last_health = health
