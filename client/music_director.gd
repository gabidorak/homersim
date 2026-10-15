class_name MusicDirector
extends Node
## Client music (M7). In a match, three synced stems play together in one AudioStreamSynchronized
## (tools/audio/music.py: calm, warning, critical, all 32 s at 120 BPM) and fade in and out with the
## plant alarm (GDD §4.2): calm alone when all is well, + warning at WARNING, + critical at CRITICAL.
## The lobby has its own lounge loop; the countdown beeps; the end of a match plays a win or lose
## stinger for our team when the post-match screen comes up (after the end-of-match cinematic, which
## has its own score); a meltdown's boom comes at once.

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
var _shown_ms := 0  # when the post-match screen last came up (Events.post_match_shown)
var _outro := false  # the end-of-match cinematic is coming: the match theme leaves with the fade to black


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	Events.post_match_shown.connect(func() -> void: _shown_ms = Time.get_ticks_msec())
	Events.outro_started.connect(func() -> void: _outro = true)
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
		if state != MatchManager.State.POST_MATCH:
			_outro = false
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
	# Match stems (out with the fade to black when a cinematic comes: its score starts on silence).
	var rate := 1.0 / OutroScreen.LEAD_IN if _outro else FADE_PER_S
	for i in _weights.size():
		var want := 1.0 if in_match and i <= alarm else 0.0
		_weights[i] = move_toward(_weights[i], want, rate * delta)
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
	var started_ms := Time.get_ticks_msec()
	var meltdown := str(mm.result.get("reason", "")).begins_with("Meltdown")
	if meltdown:
		Sfx.play(self, "meltdown")  # KA-BOOM, then the stinger
		Vfx.shake(1.0)
	# The stinger goes with the post-match screen: right away, or once the cinematic is over (given
	# up if the next match starts first), and never on top of the boom.
	while _shown_ms < started_ms:
		await get_tree().process_frame
		if not is_inside_tree() or mm.state not in [MatchManager.State.POST_MATCH, MatchManager.State.LOBBY]:
			return
	var wait := 1.2 - (Time.get_ticks_msec() - started_ms) / 1000.0 if meltdown else 0.0
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	Sfx.play(self, "stinger_lose" if lost else "stinger_win")


## Weight 0..1 → volume, with a perceptual (square root) curve.
static func _db(weight: float, gain_db: float) -> float:
	return SILENT_DB if weight <= 0.0 else lerpf(SILENT_DB, gain_db, sqrt(weight))
