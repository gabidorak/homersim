extends Node
## Headless scripted client for the integration tests (debug builds only).
##   godot --headless -- --bot rat|supervisor --connect HOST:PORT [--name X]
##                       [--bot-target SUBSYSTEM] [--bot-lever A|B] [--bot-delay S]
## It joins like a normal client (same Session, same InteractorComponent), sets its preference,
## readies up, and once the match is PLAYING:
##   rat:        teleports (debug RPC, needs the server's --allow-debug) next to the target.
##               Normal subsystem: a sabotage point; it starts a hold and lets go after 1 s, holds
##               again and steps 0.8 m aside (the server must cancel both), then holds until the
##               sabotage completes.
##               Critical subsystem: lever --bot-lever (A or B), held until the pair completes.
##   supervisor: waits until the target is damaged, teleports to its repair point and holds
##               until it is back to full health (a reboot first if needed).
## --bot-delay waits S extra seconds after PLAYING starts.
## --bot-scenario NAME [--bot-part P] runs a PvP scenario instead (tests/helpers/pvp_bot.gd, M4). Before each hold it checks that the interactor's own targeting picks the right thing.
## Then it idles. It quits when the server goes away.

var _target := &"pumps"
var _role := Role.Kind.NONE
var _session: Session
var _acted := false


func _ready() -> void:
	_role = Role.from_text(Cli.get_str("bot"))
	_target = StringName(Cli.get_str("bot-target", "pumps"))
	var addr := Net.parse_address(Cli.get_str("connect", "127.0.0.1:7777"))
	_session = (load("res://common/Session.tscn") as PackedScene).instantiate()
	_session.desired_name = Cli.get_str("name", "Bot")
	_session.joined.connect(_on_joined)
	get_tree().root.add_child.call_deferred(_session)
	Net.disconnected.connect(_quit.bind("server gone"))
	Net.connection_failed.connect(func(reason: String) -> void: _quit(reason))
	await get_tree().process_frame
	await get_tree().process_frame
	Net.join(addr["host"], addr["port"])
	Log.info("bot", "%s bot connecting to %s:%d" % [Role.display_name(_role), addr["host"], addr["port"]])


func _quit(reason: String) -> void:
	Log.info("bot", "quitting: %s" % reason)
	get_tree().quit(0)


func _on_joined() -> void:
	_session.match_manager.request_set_pref.rpc_id(1, _role)
	_session.match_manager.request_set_ready.rpc_id(1, true)
	_session.match_manager.state_changed.connect(_on_state_changed)


func _on_state_changed(state: MatchManager.State) -> void:
	if state == MatchManager.State.PLAYING and not _acted:
		_acted = true
		if Cli.has_arg("bot-scenario"):
			var pvp := PvpBot.new()
			pvp.name = "PvpBot"
			add_child(pvp)
			pvp.run(self, Cli.get_str("bot-scenario"))
		elif _role == Role.Kind.RAT:
			_run_rat()
		elif _role == Role.Kind.SUPERVISOR:
			_run_supervisor()


func _body() -> Player:
	return _session.get_body(_session.local_peer_id)


## The first interactable of class `kind` for the target subsystem (or the one named `node_name`).
func _find(kind: String, node_name: String = "") -> Interactable:
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		if node.get_script().get_global_name() == kind and node.get("subsystem_id") == _target \
				and (node_name.is_empty() or node.name == node_name):
			return node
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Teleports next to `target`, turns to face it like a player would, and checks that the
## InteractorComponent's own targeting (look ray / front cone) picks it.
func _go_to(target: Interactable) -> void:
	_session.request_debug_teleport.rpc_id(1, target.stand_position(_role))
	await _wait(1.0)  # let the server see us there (BodySync) before asking for anything
	var body := _body()
	var to := target.global_position - body.rig.global_position
	body.rotation.y = atan2(-to.x, -to.z)
	if body.rig is FirstPersonRig:
		body.rig.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await _wait(0.2)
	if body.interactor.target == target:
		Log.info("bot", "the interactor found %s by itself" % InteractionService.short_path(target.get_path()))
	else:
		Log.warn("bot", "the interactor targets %s instead of %s" % [body.interactor.target,
			InteractionService.short_path(target.get_path())])


## Holds `target` until the server ends the hold; returns the reason.
func _hold(target: Interactable) -> String:
	var interactor := _body().interactor
	interactor.bot_hold = target
	var reason: String = await interactor.hold_ended
	interactor.bot_hold = null
	return reason


func _run_rat() -> void:
	await _wait(0.5 + Cli.get_float("bot-delay", 0.0))
	if _session.plant.data(_session.plant.index_of(_target)).critical:
		var lever := _find("CriticalLever", "Lever%s" % Cli.get_str("bot-lever", "A"))
		await _go_to(lever)
		var lever_reason := await _hold(lever)
		Log.info("bot", "lever hold ended: %s" % lever_reason)
		return
	var point := _find("SabotagePoint")
	await _go_to(point)
	var interactor := _body().interactor
	interactor.bot_hold = point
	await _wait(1.0)
	interactor.bot_hold = null  # let go early: the server must cancel without damage
	Log.info("bot", "released early")
	await _wait(0.5)
	interactor.bot_hold = point  # hold again, then step aside: the server must cancel ("moved")
	await _wait(0.5)
	_body().position += _body().global_basis.x * 0.8
	var moved_reason: String = await interactor.hold_ended
	interactor.bot_hold = null
	Log.info("bot", "stepped aside, hold ended: %s" % moved_reason)
	await _go_to(point)
	var reason := await _hold(point)
	Log.info("bot", "sabotage hold ended: %s" % reason)


func _run_supervisor() -> void:
	var plant := _session.plant
	var index := plant.index_of(_target)
	while plant.health(index) >= plant.tuning.max_health:
		await _wait(0.2)
	await _wait(0.3)  # let a sabotage's full effect arrive
	Log.info("bot", "%s damaged (%d%%), going to repair" % [_target, roundi(plant.health(index))])
	var point := _find("RepairPoint")
	await _go_to(point)
	while point.is_available(_body()):
		var what := "reboot" if plant.needs_reboot(index) else "repair"
		var reason := await _hold(point)
		Log.info("bot", "%s hold ended: %s" % [what, reason])
		if reason != "completed":
			return
		await _wait(0.3)  # the new health arrives with the next PlantSync update
