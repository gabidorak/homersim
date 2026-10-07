class_name PvpBot
extends Node
## PvP scenarios for the headless bot client (M4 integration tests), debug builds only:
##   godot --headless -- --bot rat|supervisor --bot-scenario NAME [--bot-part P] --connect …
## BotClient hands over to run() once the match is PLAYING. Bots of one test are separate
## processes: they coordinate only through replicated state (statuses, cages, the roster) and
## find each other by name (SupervisorBot, VictimBot, RescuerBot, Rat1Bot…). Positions use the
## debug teleport (the server needs --allow-debug).
##
## Scenarios:
##   capture  supervisor + rats "victim" and "rescuer": broom → stun → grab → carry → cage →
##            the rescuer frees the victim → 2nd capture eliminates it → the victim uses the
##            ghost chat → the rescuer is caged too, so every rat is caught. Team chat on the way.
##   swarm    supervisor + rats 1..3: rat 2 bites the carrier so it drops rat 1, then all three
##            bite the supervisor: knockdown, swarm bonus once, knockdown immunity.
##   items    supervisor + rat: steal → locked out of the keycard door → stun drops the keycard →
##            pick it up, open the door → steal again → snap trap, cheese lure → donut, refill →
##            the spare keycard after 30 s.
##   hack     supervisor + rat send requests a hacked client could: wrong role, bad args, out of
##            range, cooldown spam. The server must refuse them all (checked in the server log).
##   plant    (M5, on the plant: --level plant) supervisor + rat: the supervisor sits at the CCTV
##            chair, the rat breaks camera 1, the supervisor stands up and repairs it, then climbs
##            the yard ladder to the vent roof and is teleported out of bounds (it must come back
##            by itself); the rat climbs the vent shaft up to the roof.
##   ai_target (M10, TestArena, with one AI rat that stands still: server --ai-roles rat
##            --ai-goals rat:none) supervisor: stuns, grabs and cages the AI rat. The server moves a
##            bot's body directly (attach_to, force_position without RPCs). Every rat is caught.
##   ai_fill  (M10, a server with bot_fill_to) any role: logs the roster and the bot bodies it sees,
##            then quits mid-match (the server must go back to the lobby, without the bots).

const VICTIM_SPOT := Vector3(0, 0, -1)
const RESCUER_SPOT := Vector3(-3, 0, 3)
const SUPERVISOR_SPOT := Vector3(0, 0, 1)

var bot: Node  ## BotClient
var session: Session
var part := ""


func run(p_bot: Node, scenario: String) -> void:
	bot = p_bot
	session = Session.current
	part = Cli.get_str("bot-part", "")
	Log.info("bot", "scenario %s, part '%s'" % [scenario, part])
	match scenario + ":" + Role.display_name(me().role).to_lower():
		"capture:supervisor":
			await _capture_supervisor()
		"capture:rat":
			if part == "victim":
				await _capture_victim()
			else:
				await _capture_rescuer()
		"swarm:supervisor":
			await _swarm_supervisor()
		"swarm:rat":
			await _swarm_rat(part.to_int())
		"items:supervisor":
			await _items_supervisor()
		"items:rat":
			await _items_rat()
		"hack:supervisor":
			await _hack_supervisor()
		"hack:rat":
			await _hack_rat()
		"plant:supervisor":
			await _plant_supervisor()
		"plant:rat":
			await _plant_rat()
		"ai_target:supervisor":
			await _ai_target_supervisor()
		"ai_fill:supervisor", "ai_fill:rat":
			await _ai_fill()
		_:
			Log.error("bot", "unknown scenario %s for %s" % [scenario, Role.display_name(me().role)])
	Log.info("bot", "scenario done")


# --- Helpers ---------------------------------------------------------------------------------

func me() -> Player:
	return session.get_body(session.local_peer_id)


func body_named(display_name: String) -> Player:
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p.display_name == display_name:
			return p
	return null


func peer_named(display_name: String) -> int:
	for peer: int in session.players:
		if session.players[peer].name == display_name:
			return peer
	return 0


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits until `condition` is true (checked every 0.1 s); false if `timeout` ran out first.
func wait_until(condition: Callable, timeout: float, what: String) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > end:
			Log.warn("bot", "timed out waiting for %s" % what)
			return false
		await get_tree().process_frame
	return true


func teleport(pos: Vector3) -> void:
	session.request_debug_teleport.rpc_id(1, pos)
	await wait_until(func() -> bool: return me() != null and me().global_position.distance_to(pos) < 0.3, 3.0,
		"the teleport to %s" % pos)
	await wait(0.4)  # let the server see us there


## Turn the body (and a first-person head) toward `target`; waits for BodySync to carry it.
func face(target: Vector3) -> void:
	var body := me()
	var to := target - body.global_position
	body.rotation.y = atan2(-to.x, -to.z)
	if body.rig is FirstPersonRig:
		var from := body.rig.global_position
		var d := target - from
		body.rig.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	await wait(0.3)


func has(body: Player, status: StatusComponent.Status) -> bool:
	return body != null and body.status.has(status)


## Press E on `target` the way the interactor does (instant targets: one press).
func press(target: Interactable) -> void:
	me().interactor.bot_hold = target
	await wait(0.3)
	me().interactor.bot_hold = null
	await wait(0.2)


## Hold E on `target` until the server ends the hold; returns why.
func hold(target: Interactable) -> String:
	var interactor := me().interactor
	interactor.bot_hold = target
	var reason: String = await interactor.hold_ended
	interactor.bot_hold = null
	return reason


## The children of World/Dynamic (traps, dropped keycards) that are instances of `type`.
func dynamic_of(type: Variant) -> Array[Node]:
	var out: Array[Node] = []
	for child in session.get_node("World/Dynamic").get_children():
		if is_instance_of(child, type) and not child.is_queued_for_deletion():
			out.append(child)
	return out


func cage(name_: String) -> Cage:
	return session.get_node("World/TestArena/PvP/%s" % name_) as Cage


## Supervisor: stun `victim` with the broom from 1.4 m away, then pick it up.
func stun_and_grab(victim_name: String) -> bool:
	var victim := body_named(victim_name)
	if victim == null:
		Log.warn("bot", "no %s to catch" % victim_name)
		return false
	await teleport(victim.global_position + Vector3(0, 0, 1.4))
	await face(Interactable.origin_of(victim))
	for attempt in 3:
		me().abilities.use(&"broom", Interactable.origin_of(victim) - Interactable.origin_of(me()))
		if await wait_until(func() -> bool: return has(victim, StatusComponent.Status.STUNNED), 1.0, "the stun"):
			break
		await wait(1.3)  # the broom's cooldown
	await press(victim.get_node("GrabHandle") as Interactable)
	return await wait_until(func() -> bool: return me().status.carrying == victim.peer_id, 2.0, "the grab")


## Supervisor carrying a rat: walk (teleport) to `target` and cage it.
func cage_carried(target: Cage) -> void:
	await teleport(target.stand_position(Role.Kind.SUPERVISOR))
	await face(target.global_position)
	await press(target)


# --- capture ---------------------------------------------------------------------------------

func _capture_supervisor() -> void:
	await wait(1.0)  # the rats get into place
	var cage_a := cage("CageA")
	if await stun_and_grab("VictimBot"):
		Log.info("bot", "carrying VictimBot")
		await cage_carried(cage_a)
	var victim := body_named("VictimBot")
	await wait_until(func() -> bool: return has(victim, StatusComponent.Status.CAGED), 2.0, "VictimBot caged")
	await teleport(SUPERVISOR_SPOT)  # out of the rescuer's way
	# The rescuer frees it; the victim runs back to its spot and its invulnerability runs out.
	await wait_until(func() -> bool: return not has(victim, StatusComponent.Status.CAGED), 15.0, "the rescue")
	await wait_until(func() -> bool: return (not has(victim, StatusComponent.Status.INVULNERABLE)
		and victim.global_position.distance_to(VICTIM_SPOT) < 0.5), 6.0, "VictimBot back in place")
	await wait(0.3)
	if await stun_and_grab("VictimBot"):
		await cage_carried(cage_a)  # 2nd capture: eliminated
	await wait_until(func() -> bool: return body_named("VictimBot") == null, 2.0, "VictimBot eliminated")
	await wait(1.0)
	if await stun_and_grab("RescuerBot"):
		await cage_carried(cage("CageB"))  # every rat is caught: supervisors win


func _capture_victim() -> void:
	await teleport(VICTIM_SPOT)
	var me_peer := session.local_peer_id
	await wait_until(func() -> bool: return has(me(), StatusComponent.Status.CAGED), 20.0, "being caged")
	Log.info("bot", "I'm caged")
	await wait_until(func() -> bool: return not has(me(), StatusComponent.Status.CAGED), 15.0, "being freed")
	Log.info("bot", "freed, invulnerable: %s" % has(me(), StatusComponent.Status.INVULNERABLE))
	await wait(0.5)
	await teleport(VICTIM_SPOT)
	await wait_until(func() -> bool: return me() == null, 20.0, "being eliminated")
	await wait_until(func() -> bool: return session.match_manager.is_ghost(me_peer), 2.0, "becoming a ghost")
	Log.info("bot", "eliminated, now a ghost")
	session.chat.send("boo from the other side", ChatService.Channel.GHOST)
	await wait(1.2)
	session.chat.send("can the living hear me", ChatService.Channel.ALL)  # rerouted to ghosts


func _capture_rescuer() -> void:
	await teleport(RESCUER_SPOT)
	var victim_peer := peer_named("VictimBot")
	var cage_a := cage("CageA")
	await wait_until(func() -> bool: return cage_a.has_occupant(victim_peer), 20.0, "VictimBot in the cage")
	session.chat.send("hang on, coming to get you", ChatService.Channel.TEAM)
	# Beside the door rather than in front of it, where the supervisor stood a moment ago.
	await teleport(cage_a.stand_position(Role.Kind.RAT) + cage_a.global_basis.x * 0.6)
	await face(cage_a.global_position)
	var reason := await hold(cage_a)
	Log.info("bot", "free hold ended: %s" % reason)
	await teleport(RESCUER_SPOT)


# --- swarm -----------------------------------------------------------------------------------

func _swarm_supervisor() -> void:
	await teleport(SUPERVISOR_SPOT)
	await wait(1.0)
	if await stun_and_grab("Rat1Bot"):
		Log.info("bot", "carrying Rat1Bot, waiting for a bite")
	await wait_until(func() -> bool: return me().status.carrying == 0, 10.0, "being made to drop the rat")
	Log.info("bot", "hands free again")


func _swarm_rat(index: int) -> void:
	var sup := body_named("SupervisorBot")
	if index == 1:
		await teleport(VICTIM_SPOT)
	await wait_until(func() -> bool: return sup.status.carrying != 0, 20.0, "the supervisor carrying Rat1Bot")
	if index == 2:
		await teleport(sup.global_position + Vector3(0.9, 0, 0))
		await face(sup.global_position)
		me().abilities.use(&"bite", sup.global_position - me().global_position)
	await wait_until(func() -> bool: return sup.status.carrying == 0, 10.0, "the drop")
	await wait(7.0)  # the drop bite falls out of the 6 s knockdown window
	var spots: Array[Vector3] = [Vector3(0, 0, -0.9), Vector3(0.9, 0, 0), Vector3(-0.9, 0, 0)]
	await teleport(sup.global_position + spots[index - 1])
	await face(sup.global_position)
	await wait(0.4 * (index - 1))  # staggered: bites at T, T+0.4, T+0.8
	var end := Time.get_ticks_msec() + 14000
	while Time.get_ticks_msec() < end:
		me().abilities.use(&"bite", sup.global_position - me().global_position)
		await wait(2.6)


# --- items -----------------------------------------------------------------------------------

func _items_supervisor() -> void:
	var rat := body_named("RatBot")
	var door := session.get_node("World/TestArena/PvP/BreakRoomKeycardDoor") as Door
	var reader := door.get_node("ReaderFront") as KeycardReader
	# 1. Stand by the keycard door, facing it (back to the rat): the rat steals the keycard.
	await teleport(reader.stand_position(Role.Kind.SUPERVISOR))
	await face(reader.global_position)
	await wait_until(func() -> bool: return not me().inventory.keycard, 15.0, "the steal")
	Log.info("bot", "keycard stolen")
	# 2. Locked out: the prompt refuses, and so does the server if asked directly.
	await press(reader)
	session.interactions.request_interact_start.rpc_id(1, reader.get_path())
	await wait(0.5)
	Log.info("bot", "door open after pressing without a keycard: %s" % door.open)
	# 3. Turn around, stun the thief: it drops the keycard; pick it up and open the door.
	await face(Interactable.origin_of(rat))
	me().abilities.use(&"broom", Interactable.origin_of(rat) - Interactable.origin_of(me()))
	await wait_until(func() -> bool: return not dynamic_of(Pickup).is_empty(), 3.0, "the dropped keycard")
	var dropped := dynamic_of(Pickup)
	if not dropped.is_empty():
		var keycard := dropped[0] as Pickup
		await teleport(keycard.global_position + Vector3(1.3, 0, -0.6))  # beside the stunned rat on it
		await face(keycard.global_position)
		Log.info("bot", "picking up the keycard at %s from %s" % [keycard.global_position, me().global_position])
		await press(keycard)
	await wait_until(func() -> bool: return me().inventory.keycard, 2.0, "the keycard back")
	Log.info("bot", "keycard back: %s" % me().inventory.keycard)
	await teleport(reader.stand_position(Role.Kind.SUPERVISOR))
	await face(reader.global_position)
	await press(reader)
	await wait_until(func() -> bool: return door.open, 2.0, "the door opening")
	Log.info("bot", "keycard door open: %s" % door.open)
	# 4. The rat steals again (we face the door). The spare-keycard countdown starts.
	await wait_until(func() -> bool: return not me().inventory.keycard, 15.0, "the second steal")
	var lost_at := Time.get_ticks_msec()
	# 5. Traps: a snap trap, then a cheese lure, both 1.5 m ahead (the rat walks onto them).
	await teleport(Vector3(-4, 0, 4))
	await face(Vector3(-4, 0, 2))
	me().abilities.selected_trap = 0
	me().abilities.place_trap(Vector3(-4, 0, 2.5))
	await wait_until(func() -> bool: return me().inventory.snap_charges == 2, 2.0, "the snap trap placed")
	await wait(1.2)
	me().abilities.selected_trap = 1
	me().abilities.place_trap(Vector3(-5, 0, 2.5))
	await wait_until(func() -> bool: return me().inventory.lure_charges == 2, 2.0, "the lure placed")
	Log.info("bot", "traps placed, %d snap trap(s) and %d lure(s) left" % [me().inventory.snap_charges,
		me().inventory.lure_charges])
	await wait_until(func() -> bool: return dynamic_of(Trap).is_empty(), 20.0, "the rat to set off both traps")
	Log.info("bot", "rat revealed: %s" % has(rat, StatusComponent.Status.REVEALED))
	# 6. A donut (carried, then eaten from the hotbar), then the trap box and the cheese box.
	var donuts := session.get_node("World/TestArena/PvP/Donuts") as Pickup
	await teleport(donuts.stand_position(Role.Kind.SUPERVISOR))
	await face(donuts.global_position)
	await press(donuts)
	await wait_until(func() -> bool: return me().inventory.donuts == 1, 2.0, "the donut in the hotbar")
	Log.info("bot", "donut: carried %d, boosted before eating %s, counter available %s" % [me().inventory.donuts,
		has(me(), StatusComponent.Status.BOOSTED), donuts.is_available(me())])
	me().hotbar.select(me().hotbar.slots().find(Hotbar.DONUT))
	me().hotbar.use_selected()
	await wait_until(func() -> bool: return has(me(), StatusComponent.Status.BOOSTED), 2.0, "the donut rush")
	Log.info("bot", "donut: boosted %s, speed x%.2f, %d left" % [has(me(), StatusComponent.Status.BOOSTED),
		me().status.speed_factor, me().inventory.donuts])
	var refill := session.get_node("World/TestArena/PvP/TrapRefill") as Pickup
	await teleport(refill.stand_position(Role.Kind.SUPERVISOR))
	await face(refill.global_position)
	await press(refill)
	await wait_until(func() -> bool: return me().inventory.snap_charges == 3, 2.0, "the refill")
	Log.info("bot", "snap traps refilled: %d, lures untouched: %d" % [me().inventory.snap_charges,
		me().inventory.lure_charges])
	var cheese := session.get_node("World/TestArena/PvP/LureRefill") as Pickup
	await teleport(cheese.stand_position(Role.Kind.SUPERVISOR))
	await face(cheese.global_position)
	await press(cheese)
	await wait_until(func() -> bool: return me().inventory.lure_charges == 3, 2.0, "the cheese refill")
	Log.info("bot", "cheese lures refilled: %d" % me().inventory.lure_charges)
	# 7. The spare keycard: not before 30 s, then yes.
	var spare := session.get_node("World/TestArena/PvP/SpareKeycard") as Pickup
	await teleport(spare.stand_position(Role.Kind.SUPERVISOR))
	await face(spare.global_position)
	await press(spare)
	session.interactions.request_interact_start.rpc_id(1, spare.get_path())
	await wait(0.5)
	Log.info("bot", "spare keycard too early: %s" % me().inventory.keycard)
	var wait_s := 31.0 - (Time.get_ticks_msec() - lost_at) / 1000.0
	await wait(maxf(wait_s, 0.0))
	await press(spare)
	await wait_until(func() -> bool: return me().inventory.keycard, 2.0, "the spare keycard")
	Log.info("bot", "spare keycard taken: %s" % me().inventory.keycard)


func _items_rat() -> void:
	var sup := body_named("SupervisorBot")
	var steal := sup.get_node("StealHandle") as StealHandle
	var door := session.get_node("World/TestArena/PvP/BreakRoomKeycardDoor") as Door
	var reader_spot := (door.get_node("ReaderFront") as Interactable).stand_position(Role.Kind.SUPERVISOR)
	# 1. Sneak up behind the supervisor (waiting at the keycard door) and steal.
	await wait_until(func() -> bool: return sup.global_position.distance_to(reader_spot) < 0.3, 10.0, "the supervisor at the door")
	await wait(0.8)
	await _steal_from(sup, steal)
	# 3. Get stunned (the supervisor turns around): the keycard drops.
	await wait_until(func() -> bool: return has(me(), StatusComponent.Status.STUNNED), 15.0, "the stun")
	Log.info("bot", "stunned, still carrying: '%s'" % me().inventory.stolen_item)
	await wait_until(func() -> bool: return door.open, 15.0, "the supervisor opening the door again")
	await wait(0.5)
	# 4. Steal again.
	await _steal_from(sup, steal)
	# 5. Walk onto the snap trap, then the lure (the supervisor places them at z = 2.5).
	await wait_until(func() -> bool: return dynamic_of(Trap).size() == 2, 15.0, "both traps")
	await teleport(Vector3(-4, 0, 2.5))
	await wait_until(func() -> bool: return has(me(), StatusComponent.Status.STUNNED), 2.0, "the snap")
	Log.info("bot", "snapped: stunned %s" % has(me(), StatusComponent.Status.STUNNED))
	await wait_until(func() -> bool: return not has(me(), StatusComponent.Status.STUNNED), 5.0, "the snap stun ending")
	await teleport(Vector3(-5, 0, 2.5))
	await wait_until(func() -> bool: return has(me(), StatusComponent.Status.REVEALED), 2.0, "the lure")
	Log.info("bot", "lured: revealed %s" % has(me(), StatusComponent.Status.REVEALED))
	await teleport(RESCUER_SPOT)


func _steal_from(sup: Player, steal: StealHandle) -> void:
	var back := sup.global_basis.z
	back.y = 0.0
	await teleport(sup.global_position + back.normalized() * 0.7)
	await face(steal.global_position)
	var reason := await hold(steal)
	Log.info("bot", "steal hold ended: %s, carrying '%s'" % [reason, me().inventory.stolen_item])


# --- hack ------------------------------------------------------------------------------------

func _hack_supervisor() -> void:
	await teleport(SUPERVISOR_SPOT)
	await face(VICTIM_SPOT)
	var abilities := session.abilities
	var items := session.items
	var interactions := session.interactions
	Log.info("bot", "hack: sending bad requests")
	abilities.request_use_ability.rpc_id(1, &"bite", Vector3.FORWARD)  # wrong role
	abilities.request_use_ability.rpc_id(1, &"laser", Vector3.FORWARD)  # no such ability
	abilities.request_use_ability.rpc_id(1, &"snap_trap", Vector3.FORWARD)  # traps aren't "used"
	for i in 3:  # cooldown spam: the 2nd and 3rd must be refused
		abilities.request_use_ability.rpc_id(1, &"broom", Vector3(NAN, 0, INF))
	items.request_place_trap.rpc_id(1, &"broom", SUPERVISOR_SPOT)  # not a trap
	items.request_place_trap.rpc_id(1, &"snap_trap", Vector3(0, 0, 12))  # too far
	items.request_place_trap.rpc_id(1, &"snap_trap", SUPERVISOR_SPOT + Vector3(0, 1.5, -1))  # in the air
	items.request_place_trap.rpc_id(1, &"snap_trap", Vector3(NAN, NAN, NAN))  # garbage
	await wait(1.2)
	for i in 4:  # the 4th has no charge left
		items.request_place_trap.rpc_id(1, &"snap_trap", SUPERVISOR_SPOT + Vector3(-1.5 + i * 0.8, 0, 1.2))
		await wait(1.1)
	var rat := body_named("RatBot")
	interactions.request_interact_start.rpc_id(1, rat.get_node("GrabHandle").get_path())  # not stunned
	interactions.request_interact_start.rpc_id(1, cage("CageA").get_path())  # not carrying, and far
	interactions.request_interact_start.rpc_id(1, NodePath("/root/Session/MatchManager"))  # not an interactable
	session.chat.send("ghost talk from the living", ChatService.Channel.GHOST)
	await wait(1.0)
	Log.info("bot", "hack: done")


func _hack_rat() -> void:
	await teleport(VICTIM_SPOT + Vector3(0, 0, -4))  # out of the traps' way, 6 m from the supervisor
	var abilities := session.abilities
	var items := session.items
	var interactions := session.interactions
	var sup := body_named("SupervisorBot")
	Log.info("bot", "hack: sending bad requests")
	abilities.request_use_ability.rpc_id(1, &"broom", Vector3.FORWARD)  # wrong role
	abilities.request_use_ability.rpc_id(1, &"bite", Vector3.FORWARD)  # out of range: bites the air
	abilities.request_use_ability.rpc_id(1, &"bite", Vector3.FORWARD)  # cooling down
	items.request_place_trap.rpc_id(1, &"snap_trap", me().global_position)  # wrong role
	interactions.request_interact_start.rpc_id(1, sup.get_node("StealHandle").get_path())  # far away
	interactions.request_interact_start.rpc_id(1, cage("CageA").get_path())  # empty and far
	session.chat.send("ghost talk from a rat", ChatService.Channel.GHOST)
	await wait(1.5)
	# Facing the supervisor's front: no steal.
	await teleport(sup.global_position - sup.global_basis.z * 0.7)
	await face(sup.global_position)
	interactions.request_interact_start.rpc_id(1, sup.get_node("StealHandle").get_path())
	await wait(1.0)
	Log.info("bot", "hack: done")


# --- plant (M5) -------------------------------------------------------------------------------

func _console() -> CctvConsole:
	return get_tree().get_first_node_in_group(CctvConsole.CONSOLE_GROUP) as CctvConsole


func _camera(number: int) -> CctvCamera:
	for cam in CctvCamera.all_in(get_tree()):
		if cam.number == number:
			return cam
	return null


## Walk forward (the movement component's test-only auto-move) until `condition` holds.
func _walk_until(condition: Callable, timeout: float, what: String) -> bool:
	me().movement._debug_auto_move = true
	var ok := await wait_until(condition, timeout, what)
	me().movement._debug_auto_move = false
	return ok


func _plant_supervisor() -> void:
	var console := _console()
	await teleport(console.stand_position(Role.Kind.SUPERVISOR))
	await face(console.global_position + Vector3.UP * 0.5)
	await press(console)
	if await wait_until(func() -> bool: return console.user == session.local_peer_id, 3.0, "the seat"):
		Log.info("bot", "sitting at the CCTV")
	var cam := _camera(1)
	if await wait_until(func() -> bool: return cam.broken, 20.0, "camera 1 to break"):
		Log.info("bot", "the CCTV shows camera 1 broken")
	console.request_stand_up.rpc_id(1)
	if await wait_until(func() -> bool: return console.user == 0, 3.0, "standing up"):
		Log.info("bot", "stood up")
	await wait(0.3)
	await teleport(cam.stand_position(Role.Kind.SUPERVISOR))
	await face(cam.global_position)
	Log.info("bot", "camera repair hold ended: %s" % await hold(cam))
	if await wait_until(func() -> bool: return not cam.broken, 2.0, "the repair to arrive"):
		Log.info("bot", "camera 1 works again")
	# Up the yard ladder: walk into it, facing the wall.
	var ladder := get_tree().root.find_child("Ladder", true, false) as Ladder
	var base := ladder.global_position - ladder.up_direction() * 1.0
	base.y = 0.0
	await teleport(base)
	await face(base + ladder.up_direction() * 3.0 + Vector3.UP * 1.6)
	if await _walk_until(func() -> bool: return me().global_position.y > 5.8 and me().is_on_floor(), 10.0, "the top of the ladder"):
		Log.info("bot", "climbed the ladder to the vent roof at %s" % me().global_position)
	await wait(1.0)  # stand on the roof: the last safe spot
	var safe := me().global_position
	session.request_debug_teleport.rpc_id(1, Vector3(0, 2, -48))  # beyond the yard fence
	if await wait_until(func() -> bool: return me().global_position.distance_to(safe) < 1.5, 4.0, "the way back in bounds"):
		Log.info("bot", "back in bounds at %s" % me().global_position)


func _plant_rat() -> void:
	var console := _console()
	if not await wait_until(func() -> bool: return console.user != 0, 15.0, "the supervisor to sit"):
		return
	var cam := _camera(1)
	await teleport(cam.stand_position(Role.Kind.RAT))
	await face(cam.global_position)
	Log.info("bot", "camera break hold ended: %s" % await hold(cam))
	# Into the vent network, at the foot of the shaft, and up: push toward the roof exit (west).
	var shaft := get_tree().root.find_child("ShaftLadder", true, false) as Ladder
	var foot := shaft.global_position
	await teleport(foot)
	var west := shaft.up_direction()
	me().rig.set("_yaw", atan2(-west.x, -west.z))
	if await _walk_until(func() -> bool: return me().global_position.y > 5.8 and me().is_on_floor(), 10.0, "the top of the shaft"):
		Log.info("bot", "climbed the shaft to the vent roof at %s" % me().global_position)


# --- M10: AI bots ----------------------------------------------------------------------------

func _bot_bodies() -> Array[Player]:
	var out: Array[Player] = []
	for node in session.players_root.get_children():
		var p := node as Player
		if p != null and p.is_bot:
			out.append(p)
	return out


func _ai_target_supervisor() -> void:
	await wait(1.0)
	var bots := _bot_bodies()
	if bots.is_empty():
		Log.warn("bot", "no AI rat to catch")
		return
	var rat := bots[0]
	Log.info("bot", "AI rat: %s (peer %d, badge %s)" % [rat.display_name, rat.peer_id, rat.has_node("BotBadge")])
	if await stun_and_grab(rat.display_name):
		Log.info("bot", "carrying the AI rat")
		await cage_carried(cage("CageA"))
	await wait_until(func() -> bool: return has(rat, StatusComponent.Status.CAGED), 2.0, "the AI rat caged")
	Log.info("bot", "AI rat caged: %s, inside the cage: %s" % [has(rat, StatusComponent.Status.CAGED),
		rat.global_position.distance_to(cage("CageA").global_position) < 2.0])


func _ai_fill() -> void:
	var mm := session.match_manager
	var bots: Array = mm.roster.keys().filter(func(p: int) -> bool: return mm.is_bot(p))
	var roles := {Role.Kind.SUPERVISOR: 0, Role.Kind.RAT: 0}
	for peer: int in bots:
		roles[mm.roster[peer]["role"]] = roles.get(mm.roster[peer]["role"], 0) + 1
	Log.info("bot", "match roster: %d entries, %d bots (%d supervisors, %d rats), I am a %s" % [mm.roster.size(),
		bots.size(), roles[Role.Kind.SUPERVISOR], roles[Role.Kind.RAT], Role.display_name(mm.local_role())])
	var start := {}
	for body in _bot_bodies():
		start[body.peer_id] = body.global_position
	await wait(6.0)
	var badges := 0
	var moved := 0
	for body in _bot_bodies():
		if body.has_node("BotBadge"):
			badges += 1
		if start.has(body.peer_id) and body.global_position.distance_to(start[body.peer_id]) > 2.0:
			moved += 1
	Log.info("bot", "bot bodies: %d with a badge, %d moved more than 2 m" % [badges, moved])
	Log.info("bot", "leaving mid-match")
	Net.leave()
	get_tree().quit(0)
	await wait(5.0)  # (never returns: BotClient would report to a server we left)
