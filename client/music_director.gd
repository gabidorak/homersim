class_name MusicDirector
extends Node
## Client music (M7). In a match, three synced stems play together in one AudioStreamSynchronized
## (tools/audio/music.py: calm, warning, critical, all 32 s at 120 BPM) and fade in and out with the
## plant alarm (GDD §4.2): calm alone when all is well, + warning at WARNING, + critical at CRITICAL.
## The lobby has its own lounge loop; the countdown beeps; the end of a match plays a win or lose
## stinger for our team.

const STEMS: Array[String] = ["res://assets/audio/music/match_calm.ogg",
	"res://assets/audio/music/match_warning.ogg", "res://assets/audio/music/match_critical.ogg"]
const LOBBY := "res://assets/audio/music/lobby.ogg"
const SILENT_DB := -60.0
const FADE_PER_S := 0.6  ## weight per second: a layer fades in or out in under 2 s
const STEM_DB := [2.0, 0.0, 0.0]  ## extra gain per stem at full weight
const LOBBY_DB := -6.0

var _match_stream: AudioStreamSynchronized
var _match_player: AudioStreamPlayer
var _lobby_player: AudioStreamPlayer
var _weights: Array[float] = [0.0, 0.0, 0.0]
var _lobby_weight := 0.0
var _last_state := -1
var _stinger_pending := false
var _last_countdown := -1


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_match_stream = AudioStreamSynchronized.new()
	_match_stream.stream_count = STEMS.size()
	for i in STEMS.size():
		var stem := load(STEMS[i]) as AudioStreamOggVorbis
		stem.loop = true
		_match_stream.set_sync_stream(i, stem)
		_match_stream.set_sync_stream_volume(i, SILENT_DB)
	_match_player = AudioStreamPlayer.new()
	_match_player.stream = _match_stream
	_match_player.bus = &"Music"
	add_child(_match_player)
	var lobby := load(LOBBY) as AudioStreamOggVorbis
	lobby.loop = true
	_lobby_player = AudioStreamPlayer.new()
	_lobby_player.stream = lobby
	_lobby_player.bus = &"Music"
	_lobby_player.volume_db = SILENT_DB
	add_child(_lobby_player)


func _process(delta: float) -> void:
	var session := Session.current
	if session == null:
		return
	var mm := session.match_manager
	var state := mm.state
	if state != _last_state:
		_stinger_pending = state == MatchManager.State.POST_MATCH and _last_state == MatchManager.State.PLAYING
		if state == MatchManager.State.PLAYING and _last_state == MatchManager.State.COUNTDOWN:
			Sfx.play(self, "beep_go")
		_last_state = state
	# Countdown beeps, one per second.
	var seconds := ceili(mm.countdown_left) if state == MatchManager.State.COUNTDOWN else -1
	if seconds != _last_countdown:
		if seconds > 0 and seconds <= 5:
			Sfx.play(self, "beep")
		_last_countdown = seconds
	if _stinger_pending and not mm.result.is_empty():  # the result and the state can arrive in either order
		_stinger_pending = false
		_play_stinger()
	var in_match := state == MatchManager.State.PLAYING
	var alarm: PlantModel.Alarm = session.plant.alarm if in_match else PlantModel.Alarm.NORMAL
	# Match stems.
	for i in _weights.size():
		var want := 1.0 if in_match and i <= alarm else 0.0
		_weights[i] = move_toward(_weights[i], want, FADE_PER_S * delta)
		_match_stream.set_sync_stream_volume(i, _db(_weights[i], STEM_DB[i]))
	var any: bool = _weights.max() > 0.0
	if any and not _match_player.playing:
		_match_player.play()
	elif not any and _match_player.playing:
		_match_player.stop()  # restarts from the top at the next match
	# Lobby loop: before the match (lobby, role assignment, countdown).
	var lobby_on := state in [MatchManager.State.LOBBY, MatchManager.State.ROLE_ASSIGN, MatchManager.State.COUNTDOWN]
	_lobby_weight = move_toward(_lobby_weight, 1.0 if lobby_on else 0.0, FADE_PER_S * delta)
	_lobby_player.volume_db = _db(_lobby_weight, LOBBY_DB)
	if _lobby_weight > 0.0 and not _lobby_player.playing:
		_lobby_player.play()
	elif _lobby_weight <= 0.0 and _lobby_player.playing:
		_lobby_player.stop()


func _play_stinger() -> void:
	var mm := Session.current.match_manager
	var winner: MatchRulesModel.Team = mm.result.get("winner", MatchRulesModel.Team.NONE)
	var mine := mm.local_role()
	var lost := (winner == MatchRulesModel.Team.SUPERVISORS and mine == Role.Kind.RAT) \
		or (winner == MatchRulesModel.Team.RATS and mine == Role.Kind.SUPERVISOR)
	if str(mm.result.get("reason", "")).begins_with("Meltdown"):
		Sfx.play(self, "meltdown")  # KA-BOOM, then the stinger
		Vfx.shake(1.0)
		await get_tree().create_timer(1.2).timeout
	Sfx.play(self, "stinger_lose" if lost else "stinger_win")


## Weight 0..1 → volume, with a perceptual (square root) curve.
static func _db(weight: float, gain_db: float) -> float:
	return SILENT_DB if weight <= 0.0 else lerpf(SILENT_DB, gain_db, sqrt(weight))
