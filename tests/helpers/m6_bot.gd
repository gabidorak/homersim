class_name M6Bot
extends PvpBot
## M6 scenarios for the headless bot client (on the plant: --level plant), debug builds only:
##   godot --headless -- --level plant --bot rat|supervisor --bot-scenario hazards|minigame|control …
## Like PvpBot (whose helpers it reuses), bots coordinate only through replicated state. Plant
## states that would take minutes to reach in play (a subsystem at 30%, a hot core) are set with
## the server's test-only request_debug_plant (needs --allow-debug).
##
## Scenarios:
##   hazards   the rat sabotages the pumps (100 → 50: not below 50, so no jets yet); the supervisor
##             breaks them further (30%): the steam jets switch on, and both bots step into a jet and
##             get knocked back and stunned. The supervisor repairs to 65% (≥ 60): jets off. Then the
##             grid (the rat steps into a live puddle: stunned, then slowed), the rods (the rat stands
##             in the radiation: revealed and slowed after 5 s), the turbine (the supervisor runs under
##             falling debris: knocked down) and the ventilation (smoke on).
##   minigame  the rat sabotages the pumps; the supervisor repairs them with the wrench minigame
##             (played by autoplay, through the real overlay): +50. Then, on the valves, a hacked
##             instant "I won" is refused (too fast) and jams the point; a later honest valve game
##             wins. On the grid a lost breaker game gives +10 and jams; walking away closes a game.
##   control   emergency coolant (refused without grid power, then −150 with it, then on cooldown),
##             and SCRAM: the first press lifts the cover, the second fires (timer +30 s, heat halved),
##             the third is refused (cooldown).

const PLANT := "World/Plant/POIs/"
## The rat tells the supervisor it is done with a part by waiting at a known spot (positions are
## the only shared state this needs).
const RAT_DONE_SPOTS := {"puddle": Vector3(-36, 0, -22), "radiation": Vector3(-14, 0, -3)}


func run(p_bot: Node, scenario: String) -> void:
	bot = p_bot
	session = Session.current
	part = Cli.get_str("bot-part", "")
	Log.info("bot", "M6 scenario %s" % scenario)
	match scenario + ":" + Role.display_name(me().role).to_lower():
		"hazards:supervisor":
			await _hazards_supervisor()
		"hazards:rat":
			await _hazards_rat()
		"minigame:supervisor":
			await _minigame_supervisor()
		"minigame:rat":
			await _minigame_rat()
		"control:supervisor":
			await _control_supervisor()
		"control:rat":
			pass  # only there so the match has a rat
		_:
			Log.error("bot", "unknown M6 scenario %s for %s" % [scenario, Role.display_name(me().role)])
	Log.info("bot", "scenario done")


# --- Helpers ---------------------------------------------------------------------------------

func node(path: String) -> Node:
	return session.get_node(PLANT + path)


func plant_index(id: StringName) -> int:
	return session.plant.index_of(id)


func health(id: StringName) -> float:
	return session.plant.health(plant_index(id))


## Server-side test hook: "health" sets a subsystem's health, "core_temp" the core temperature.
func debug_plant(what: String, id: StringName, value: float) -> void:
	session.request_debug_plant.rpc_id(1, what, id, value)
	await wait(0.4)


func repair_point(id: StringName) -> RepairPoint:
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		if n is RepairPoint and (n as RepairPoint).subsystem_id == id:
			return n
	return null


func sabotage_point(id: StringName) -> SabotagePoint:
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		if n is SabotagePoint and (n as SabotagePoint).subsystem_id == id:
			return n
	return null


func rat_sabotage(id: StringName) -> void:
	var point := sabotage_point(id)
	await teleport(point.stand_position(Role.Kind.RAT))
	await face(point.global_position)
	Log.info("bot", "sabotage %s hold ended: %s" % [id, await hold(point)])


## Step into `hazard` at `spot` while it is off (with time to spare before it goes live, so the
## teleport isn't interrupted), then wait until it hits us with `status`. Returns how far we were
## pushed from `spot`.
func get_hit(hazard: Hazard, spot: Vector3, status: StatusComponent.Status, timeout: float, what: String) -> float:
	await wait_until(func() -> bool:
		var t := hazard.elapsed(Net.server_time())
		return not hazard.is_live(Net.server_time()) \
			and HazardRules.time_to_switch(t, hazard.on_s, hazard.off_s, hazard.phase) > 1.2, 8.0, "%s to be off" % what)
	await teleport(spot)
	if not await wait_until(func() -> bool: return has(me(), status), timeout, what):
		return 0.0
	await wait(0.8)  # let a knockback play out
	return me().global_position.distance_to(spot)


## A spot `distance` m down a steam jet's axis, on its floor.
func in_jet(jet: SteamJet, distance: float) -> Vector3:
	var axis := jet.global_basis.z
	axis.y = 0.0
	return jet.global_position + axis.normalized() * distance


func hazards_on(group_id: StringName) -> bool:
	var nodes := get_tree().get_nodes_in_group(Hazard.group_for(group_id))
	return not nodes.is_empty() and nodes.all(func(n: Node) -> bool: return (n as Hazard).active)


func hazards_off(group_id: StringName) -> bool:
	return get_tree().get_nodes_in_group(Hazard.group_for(group_id)).all(func(n: Node) -> bool:
		return not (n as Hazard).active)


# --- hazards ---------------------------------------------------------------------------------

func _hazards_supervisor() -> void:
	await teleport(Vector3(-41, 0, -2))  # the Valve Corridor's east lane, out of everyone's way
	if await wait_until(func() -> bool: return health(&"pumps") <= 50.0, 20.0, "the pumps sabotage"):
		await wait(1.5)
		Log.info("bot", "pumps at %d%%, jets active: %s" % [roundi(health(&"pumps")), not hazards_off(&"pumps")])
	await debug_plant("health", &"pumps", 30.0)
	if await wait_until(func() -> bool: return hazards_on(&"pumps"), 3.0, "the steam jets"):
		Log.info("bot", "the pump jets are on")
	# Into SteamJet3's cone (it blows south, phase 1.5; the rat takes SteamJet).
	var jet := node("PumpHouse/SteamJet3") as SteamJet
	var pushed := await get_hit(jet, in_jet(jet, 1.6), StatusComponent.Status.STUNNED, 9.0, "the steam jet")
	Log.info("bot", "steam jet: stunned and pushed %.1f m" % pushed)
	await wait_until(func() -> bool: return me().status.can_act(), 3.0, "the stun ending")
	# Repair the pumps by hand (hold): 30 → 65, back above 60.
	var point := repair_point(&"pumps")
	await teleport(point.stand_position(Role.Kind.SUPERVISOR))
	await face(point.global_position)
	Log.info("bot", "pumps repair hold ended: %s" % await hold(point))
	if await wait_until(func() -> bool: return hazards_off(&"pumps") and health(&"pumps") >= 60.0, 3.0, "the jets switching off"):
		Log.info("bot", "the pump jets are off at %d%%" % roundi(health(&"pumps")))
	# The other hazards: the rat tries the puddle and the radiation; we take the debris.
	await debug_plant("health", &"grid", 0.0)
	await wait_until(func() -> bool: return part_done("puddle"), 15.0, "the rat's puddle")
	await debug_plant("health", &"rods", 0.0)
	await wait_until(func() -> bool: return part_done("radiation"), 15.0, "the rat's radiation")
	await debug_plant("health", &"turbine", 0.0)
	await _dodge_into_debris()
	await debug_plant("health", &"ventilation", 0.0)
	var smoke := node("ControlRoom/Smoke") as Smoke
	if await wait_until(func() -> bool: return smoke.active, 3.0, "the smoke"):
		Log.info("bot", "smoke in the Control Room: %s" % smoke.active)


func part_done(what: String) -> bool:
	var rat := body_named("RatBot")
	return rat != null and rat.global_position.distance_to(RAT_DONE_SPOTS[what]) < 1.0


## Wait for a debris warning in the Turbine Hall and stand right where it will land.
func _dodge_into_debris() -> void:
	var zone := node("TurbineHall/DebrisZone") as DebrisZone
	await teleport(Vector3(12, 0, -3))
	if not await wait_until(func() -> bool: return zone.active, 3.0, "the debris zone"):
		return
	for attempt in 3:
		if not await wait_until(func() -> bool: return not zone._drops.is_empty(), 12.0, "a debris warning"):
			return
		var spot: Vector3 = zone._drops[0]["pos"]
		session.request_debug_teleport.rpc_id(1, spot)
		if await wait_until(func() -> bool: return has(me(), StatusComponent.Status.KNOCKED_DOWN), 2.0, "the debris"):
			Log.info("bot", "debris: knocked down at %s" % spot)
			return
		await wait_until(func() -> bool: return zone._drops.is_empty(), 2.0, "the last drop to land")


func _hazards_rat() -> void:
	await rat_sabotage(&"pumps")
	await teleport(Vector3(-43, 0, -7.2))  # by the Pump House arch, clear of the jets
	if not await wait_until(func() -> bool: return hazards_on(&"pumps"), 20.0, "the steam jets"):
		return
	var jet := node("PumpHouse/SteamJet") as SteamJet
	var pushed := await get_hit(jet, in_jet(jet, 1.5), StatusComponent.Status.STUNNED, 9.0, "the steam jet")
	Log.info("bot", "steam jet: stunned and pushed %.1f m" % pushed)
	await wait(1.6)  # the stun immunity runs out
	await teleport(Vector3(-43, 0, -7.2))
	# A live puddle: stunned, then slowed.
	if await wait_until(func() -> bool: return hazards_on(&"grid"), 30.0, "the puddles"):
		var puddle := node("Substation/ElectricPuddle") as ElectricPuddle
		await get_hit(puddle, puddle.global_position, StatusComponent.Status.STUNNED, 7.0, "the puddle")
		Log.info("bot", "puddle: stunned %s, speed x%.2f" % [has(me(), StatusComponent.Status.STUNNED), me().status.speed_factor])
		await wait_until(func() -> bool: return not has(me(), StatusComponent.Status.STUNNED), 3.0, "the stun ending")
		Log.info("bot", "puddle: after the stun, slowed %s (x%.2f)" % [has(me(), StatusComponent.Status.SLOWED), me().status.speed_factor])
	await teleport(RAT_DONE_SPOTS["puddle"])
	# The radiation zone: 5 s inside, then slowed and revealed.
	if await wait_until(func() -> bool: return hazards_on(&"rods"), 20.0, "the radiation"):
		await teleport(Vector3(-24, 0, -6.2))
		var t0 := Time.get_ticks_msec()
		if await wait_until(func() -> bool: return has(me(), StatusComponent.Status.REVEALED), 8.0, "the radiation to bite"):
			Log.info("bot", "radiation: revealed after %.1f s, speed x%.2f" % [(Time.get_ticks_msec() - t0) / 1000.0, me().status.speed_factor])
	await teleport(RAT_DONE_SPOTS["radiation"])
	await wait(1.0)
	Log.info("bot", "outside the radiation: still revealed %s" % has(me(), StatusComponent.Status.REVEALED))


# --- minigame --------------------------------------------------------------------------------

func host() -> MinigameHost:
	return session.client_only.get_node("MinigameHost") as MinigameHost


## Press E at `id`'s repair point like a player who wants the minigame; returns once it opened.
func open_minigame(id: StringName) -> bool:
	var point := repair_point(id)
	await teleport(point.stand_position(Role.Kind.SUPERVISOR))
	await face(point.global_position)
	await wait_until(func() -> bool: return point.is_available(me()), 5.0, "the repair point")
	await press(point)
	return await wait_until(func() -> bool: return host().is_open(), 3.0, "the minigame to open")


func _minigame_supervisor() -> void:
	Config.minigame_repairs = true
	var h := host()
	# 1. Pumps: the wrench minigame, played honestly (autoplay) through the overlay.
	await teleport(Vector3(-41, 0, -2))
	await wait_until(func() -> bool: return health(&"pumps") <= 50.0, 20.0, "the pumps sabotage")
	await wait(0.5)
	h.autoplay = true
	if await open_minigame(&"pumps"):
		Log.info("bot", "minigame open: %s" % h.game.get_script().get_global_name())
	await wait_until(func() -> bool: return not h.is_open(), 15.0, "the wrench minigame to finish")
	await wait(0.5)
	Log.info("bot", "pumps after the minigame: %d%%" % roundi(health(&"pumps")))
	# 2. Valves: a hacked client claims an instant win. Refused, and the point jams.
	await debug_plant("health", &"valves", 40.0)
	h.autoplay = false
	var valves := repair_point(&"valves")
	await open_minigame(&"valves")
	session.minigames.request_minigame_result.rpc_id(1, true)
	await wait_until(func() -> bool: return valves.lockout_left() > 0.0, 2.0, "the jam")
	Log.info("bot", "after the hack: valves %d%%, jammed %s, overlay open %s" % [roundi(health(&"valves")),
		valves.lockout_left() > 0.0, h.is_open()])
	session.minigames.request_minigame_result.rpc_id(1, true)  # no game open any more
	await wait(0.5)
	Log.info("bot", "repair prompt while jammed: %s" % valves.prompt_for(me()))
	# 3. The same valves, honestly, once the jam is over.
	await wait_until(func() -> bool: return valves.lockout_left() <= 0.0, 5.0, "the jam to end")
	h.autoplay = true
	await open_minigame(&"valves")
	await wait_until(func() -> bool: return not h.is_open(), 20.0, "the valve minigame to finish")
	await wait(0.5)
	Log.info("bot", "valves after the minigame: %d%%" % roundi(health(&"valves")))
	# 4. Grid: lose the breaker game on purpose (a wrong breaker): +10 and a jam.
	await debug_plant("health", &"grid", 40.0)
	h.autoplay = false
	if await open_minigame(&"grid"):
		var game := h.game as BreakerSequence
		await wait_until(func() -> bool: return game.phase == BreakerSequence.Phase.INPUT, 6.0, "the breakers' input phase")
		game.press_breaker((game.sequence[0] + 1) % BreakerSequence.COUNT)
	await wait_until(func() -> bool: return not h.is_open(), 5.0, "the lost game to close")
	await wait(0.5)
	Log.info("bot", "grid after the lost minigame: %d%%, jammed %s" % [roundi(health(&"grid")),
		repair_point(&"grid").lockout_left() > 0.0])
	# 5. Walking away from an open game closes it (server side).
	await wait_until(func() -> bool: return repair_point(&"grid").lockout_left() <= 0.0, 5.0, "the jam to end")
	if await open_minigame(&"grid"):
		me().position += me().global_basis.x * 1.0
		if await wait_until(func() -> bool: return not h.is_open(), 3.0, "the server closing the game"):
			Log.info("bot", "walked away: the minigame closed")
	# 6. A bite closes an open game: the rat comes over once we play at the grid again.
	await wait(0.5)
	if await open_minigame(&"grid"):
		Log.info("bot", "playing at the grid, waiting for a bite")
		if await wait_until(func() -> bool: return not h.is_open(), 10.0, "the bite closing the game"):
			Log.info("bot", "bitten: the minigame closed")


func _minigame_rat() -> void:
	await rat_sabotage(&"pumps")
	await teleport(Vector3(-14, 0, -3))
	# The supervisor plays at the grid three times (a loss, walking away, then this): bite the 3rd.
	var sup := body_named("SupervisorBot")
	var grid := repair_point(&"grid")
	for game in 3:
		await wait_until(func() -> bool: return grid.minigame_user == sup.peer_id, 50.0, "grid game %d" % (game + 1))
		if game < 2:
			await wait_until(func() -> bool: return grid.minigame_user == 0, 15.0, "grid game %d to end" % (game + 1))
	# From the side: behind it is the grid's electric puddle (live, the grid is below 50).
	await teleport(sup.global_position + sup.global_basis.x * 0.9)
	await face(sup.global_position)
	Log.info("bot", "biting the supervisor: %s" % me().abilities.use(&"bite", sup.global_position - me().global_position))


# --- control ---------------------------------------------------------------------------------

func _control_supervisor() -> void:
	var coolant := node("ControlRoom/ConsoleCoolant") as ConsoleAction
	var scram := node("ControlRoom/ConsoleScram") as ConsoleAction
	var mm := session.match_manager
	# 1. No power: the coolant pumps refuse.
	await debug_plant("health", &"grid", 10.0)
	await debug_plant("core_temp", &"", 650.0)
	await teleport(coolant.stand_position(Role.Kind.SUPERVISOR))
	await face(coolant.global_position)
	Log.info("bot", "coolant prompt without power: %s" % coolant.prompt_for(me()))
	session.interactions.request_interact_start.rpc_id(1, coolant.get_path())  # a direct request too
	await wait(0.5)
	# 2. Power back: −150.
	await debug_plant("health", &"grid", 100.0)
	await press(coolant)
	if await wait_until(func() -> bool: return coolant.cooldown_left() > 0.0, 2.0, "the coolant cooldown"):
		Log.info("bot", "coolant used: core %d, cooldown %d s" % [roundi(session.plant.core_temp), ceili(coolant.cooldown_left())])
	# 3. Cooling down: refused.
	session.interactions.request_interact_start.rpc_id(1, coolant.get_path())
	await wait(0.5)
	# 4. SCRAM: lift the cover, press, then try again.
	var before := mm.time_left
	await teleport(scram.stand_position(Role.Kind.SUPERVISOR))
	await face(scram.global_position)
	await press(scram)
	if await wait_until(func() -> bool: return scram.cover_open(), 2.0, "the cover"):
		Log.info("bot", "SCRAM cover open, prompt: %s" % scram.prompt_for(me()))
	await press(scram)
	if await wait_until(func() -> bool: return session.plant.scram_left > 0.0 and mm.time_added > 0, 2.0, "the SCRAM"):
		Log.info("bot", "SCRAM active %d s, timer %d -> %d (+%d)" % [ceili(session.plant.scram_left), before,
			mm.time_left, mm.time_added])
	session.interactions.request_interact_start.rpc_id(1, scram.get_path())
	await wait(0.5)
	Log.info("bot", "SCRAM cooldown %d s" % ceili(scram.cooldown_left()))
