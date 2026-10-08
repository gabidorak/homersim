class_name Sfx
extends RefCounted
## The game's sounds by name (M7, ASSETS §6). Synthesized ones come from tools/audio/make_audio.py
## (assets/audio/), recorded CC0 ones from the Kenney packs in assets/third_party/. A sound with
## several files becomes an AudioStreamRandomizer (a different take each time, with pitch and volume
## variation), so repeated footsteps and squeaks don't sound like a machine gun.
##
## Each sound has a Kind: its bus and how far it carries (footsteps are heard close by, alarms
## across a hall). Positional players also pick up the hall reverb from audio areas
## (PhysicsLayers.AUDIO, placed by the level generator in the big halls).

enum Kind { SFX, STEP, VOICE, ALARM, HUM, UI, MUSIC }

## bus, unit_size (m at which the volume is full), max_distance (m), attenuation model
const KINDS := {
	Kind.SFX: [&"SFX", 6.0, 45.0],
	Kind.STEP: [&"SFX", 2.0, 18.0],
	Kind.VOICE: [&"SFX", 5.0, 35.0],
	Kind.ALARM: [&"SFX", 20.0, 90.0],
	Kind.HUM: [&"Ambience", 3.0, 22.0],
	Kind.UI: [&"UI", 1.0, 0.0],
	Kind.MUSIC: [&"Music", 1.0, 0.0],
}
const A := "res://assets/audio/sfx/"
const M := "res://assets/audio/music/"
const IMPACT := "res://assets/third_party/kenney_impact-sounds/"
const UI_K := "res://assets/third_party/kenney_interface-sounds/"
const SCIFI := "res://assets/third_party/kenney_sci-fi-sounds/"
const DIGITAL := "res://assets/third_party/kenney_digital-audio/"
const RPG := "res://assets/third_party/kenney_rpg-audio/"

## name → {kind, files, db (volume), pitch (random pitch scale, 1 = none), loop, also (another
## sound played with it)}
const SOUNDS := {
	# PvP
	"bonk": {"kind": Kind.SFX, "files": [A + "bonk.ogg"], "pitch": 1.05, "also": "punch"},
	"punch": {"kind": Kind.SFX, "files": [IMPACT + "impactPunch_heavy_000.ogg", IMPACT + "impactPunch_heavy_001.ogg",
		IMPACT + "impactPunch_heavy_002.ogg"], "db": -5.0, "pitch": 1.1},
	"whoosh": {"kind": Kind.SFX, "files": [A + "whoosh.ogg"], "db": -3.0, "pitch": 1.15},
	"chomp": {"kind": Kind.SFX, "files": [A + "chomp.ogg"], "pitch": 1.12},
	"snap": {"kind": Kind.SFX, "files": [A + "snap_crack.ogg"], "db": 2.0, "pitch": 1.05, "also": "metal_heavy"},
	"trap_place": {"kind": Kind.SFX, "files": [IMPACT + "impactWood_light_000.ogg", IMPACT + "impactWood_light_001.ogg",
		IMPACT + "impactWood_light_002.ogg"], "pitch": 1.1},
	"cage_slam": {"kind": Kind.SFX, "files": [RPG + "metalLatch.ogg"], "db": 2.0, "also": "metal_heavy"},
	"cage_open": {"kind": Kind.SFX, "files": [RPG + "creak1.ogg"], "pitch": 1.1},
	"powerup": {"kind": Kind.SFX, "files": [DIGITAL + "powerUp2.ogg"], "db": -4.0},
	"spit": {"kind": Kind.SFX, "files": [A + "spit.ogg"], "db": -2.0, "pitch": 1.12},
	"splat": {"kind": Kind.SFX, "files": [A + "splat.ogg"], "db": -2.0, "pitch": 1.15},
	# Voices
	"squeak": {"kind": Kind.VOICE, "files": [A + "squeak_1.ogg", A + "squeak_2.ogg", A + "squeak_3.ogg", A + "squeak_4.ogg"],
		"pitch": 1.12},
	"ow": {"kind": Kind.VOICE, "files": [A + "ow_1.ogg", A + "ow_2.ogg"], "pitch": 1.08},
	"munch": {"kind": Kind.VOICE, "files": [A + "munch.ogg"], "pitch": 1.05},
	"whistle_emote": {"kind": Kind.VOICE, "files": [A + "emote_whistle.ogg"], "pitch": 1.05},
	# Movement
	"step_supervisor": {"kind": Kind.STEP, "files": [IMPACT + "footstep_concrete_000.ogg", IMPACT + "footstep_concrete_001.ogg",
		IMPACT + "footstep_concrete_002.ogg", IMPACT + "footstep_concrete_003.ogg", IMPACT + "footstep_concrete_004.ogg"],
		"db": -6.0, "pitch": 1.08},
	"step_rat": {"kind": Kind.STEP, "files": [A + "rat_step.ogg"], "db": -8.0, "pitch": 1.35},
	"crawl": {"kind": Kind.STEP, "files": [A + "crawl_loop.ogg"], "db": -10.0, "loop": true},
	"land": {"kind": Kind.STEP, "files": [IMPACT + "impactSoft_medium_000.ogg", IMPACT + "impactSoft_medium_001.ogg"],
		"db": -6.0, "pitch": 1.1},
	# Interactions
	"gnaw": {"kind": Kind.SFX, "files": [A + "gnaw_loop.ogg"], "db": -4.0, "loop": true},
	"wrench": {"kind": Kind.SFX, "files": [IMPACT + "impactMetal_light_000.ogg", IMPACT + "impactMetal_light_001.ogg",
		IMPACT + "impactMetal_light_002.ogg"], "db": -6.0, "pitch": 1.1},
	"repair_done": {"kind": Kind.SFX, "files": [A + "repair_done.ogg"]},
	"sabotage_done": {"kind": Kind.SFX, "files": [A + "sabotage_done.ogg"]},
	"spark": {"kind": Kind.SFX, "files": [A + "spark.ogg"], "db": -6.0, "pitch": 1.2},
	"lever": {"kind": Kind.SFX, "files": [A + "lever_pull.ogg"], "pitch": 1.05},
	"button": {"kind": Kind.SFX, "files": [A + "button.ogg"], "pitch": 1.05},
	"door_open": {"kind": Kind.SFX, "files": [SCIFI + "doorOpen_000.ogg", SCIFI + "doorOpen_001.ogg", SCIFI + "doorOpen_002.ogg"],
		"db": -6.0},
	"door_close": {"kind": Kind.SFX, "files": [SCIFI + "doorClose_000.ogg", SCIFI + "doorClose_001.ogg",
		SCIFI + "doorClose_002.ogg"], "db": -6.0},
	"keycard_ok": {"kind": Kind.SFX, "files": [DIGITAL + "twoTone1.ogg"], "db": -4.0},
	"keycard_denied": {"kind": Kind.SFX, "files": [DIGITAL + "lowDown.ogg"], "db": -4.0},
	"glass_break": {"kind": Kind.SFX, "files": [IMPACT + "impactGlass_medium_000.ogg", IMPACT + "impactGlass_medium_001.ogg"]},
	"metal_heavy": {"kind": Kind.SFX, "files": [IMPACT + "impactMetal_heavy_000.ogg", IMPACT + "impactMetal_heavy_001.ogg",
		IMPACT + "impactMetal_heavy_002.ogg"], "db": -3.0, "pitch": 1.08},
	# Hazards and the plant
	"hiss": {"kind": Kind.SFX, "files": [A + "hiss_loop.ogg"], "loop": true},
	"puff": {"kind": Kind.SFX, "files": [A + "puff.ogg"], "pitch": 1.1},
	"zap": {"kind": Kind.SFX, "files": [A + "zap_1.ogg", A + "zap_2.ogg", DIGITAL + "zap1.ogg"], "pitch": 1.1},
	"buzz": {"kind": Kind.HUM, "files": [A + "buzz_loop.ogg"], "loop": true},
	"click": {"kind": Kind.SFX, "files": [A + "geiger_1.ogg", A + "geiger_2.ogg", A + "geiger_3.ogg"], "pitch": 1.3},
	"crash": {"kind": Kind.SFX, "files": [IMPACT + "impactMetal_heavy_000.ogg", IMPACT + "impactMetal_heavy_001.ogg",
		IMPACT + "impactMetal_heavy_002.ogg"], "db": 2.0, "pitch": 1.1, "also": "rumble"},
	"rumble": {"kind": Kind.SFX, "files": [A + "rumble.ogg"]},
	"whistle": {"kind": Kind.SFX, "files": [A + "whistle_fall.ogg"], "pitch": 1.08},
	"klaxon": {"kind": Kind.ALARM, "files": [A + "scram_klaxon.ogg"]},
	"whoosh_cold": {"kind": Kind.SFX, "files": [A + "coolant_whoosh.ogg"]},
	"alarm_warning": {"kind": Kind.ALARM, "files": [A + "warning_loop.ogg"], "db": -8.0, "loop": true},
	"alarm_critical": {"kind": Kind.ALARM, "files": [A + "klaxon_loop.ogg"], "db": -6.0, "loop": true},
	"meltdown": {"kind": Kind.ALARM, "files": [SCIFI + "lowFrequency_explosion_000.ogg"], "db": 4.0},
	"hum_room": {"kind": Kind.HUM, "files": [A + "hum_room_loop.ogg"], "loop": true},
	"hum_reactor": {"kind": Kind.HUM, "files": [A + "hum_reactor_loop.ogg"], "loop": true},
	"hum_turbine": {"kind": Kind.HUM, "files": [A + "hum_turbine_loop.ogg"], "loop": true},
	"hum_pump": {"kind": Kind.HUM, "files": [A + "hum_pump_loop.ogg"], "loop": true},
	"hum_electric": {"kind": Kind.HUM, "files": [A + "hum_electric_loop.ogg"], "loop": true},
	"fan": {"kind": Kind.HUM, "files": [A + "fan_loop.ogg"], "loop": true},
	"crickets": {"kind": Kind.HUM, "files": [A + "crickets_loop.ogg"], "loop": true},
	"drip": {"kind": Kind.HUM, "files": [A + "drip_loop.ogg"], "loop": true},
	# UI
	"ui_click": {"kind": Kind.UI, "files": [UI_K + "click_001.ogg", UI_K + "click_002.ogg", UI_K + "click_003.ogg"]},
	"ui_hover": {"kind": Kind.UI, "files": [UI_K + "select_001.ogg"], "db": -8.0},
	"ui_confirm": {"kind": Kind.UI, "files": [UI_K + "confirmation_001.ogg"]},
	"ui_error": {"kind": Kind.UI, "files": [UI_K + "error_001.ogg"]},
	"ui_open": {"kind": Kind.UI, "files": [UI_K + "open_001.ogg"], "db": -4.0},
	"ui_close": {"kind": Kind.UI, "files": [UI_K + "close_001.ogg"], "db": -4.0},
	"tick": {"kind": Kind.UI, "files": [UI_K + "tick_001.ogg", UI_K + "tick_002.ogg"], "db": -4.0},
	"beep": {"kind": Kind.UI, "files": [A + "beep.ogg"], "db": -4.0},
	"beep_go": {"kind": Kind.UI, "files": [A + "beep_go.ogg"], "db": -2.0},
	"stinger_win": {"kind": Kind.MUSIC, "files": [M + "stinger_win.ogg"]},
	"stinger_lose": {"kind": Kind.MUSIC, "files": [M + "stinger_lose.ogg"]},
	# The intro (client/intro/)
	"intro_squeak": {"kind": Kind.VOICE, "files": [A + "intro_squeak_1.ogg", A + "intro_squeak_2.ogg"], "pitch": 1.06},
	"intro_sparkle": {"kind": Kind.SFX, "files": [A + "intro_sparkle.ogg"]},
	"intro_whoa": {"kind": Kind.VOICE, "files": [A + "intro_whoa.ogg"]},
	"intro_eek": {"kind": Kind.VOICE, "files": [A + "intro_eek.ogg"]},
	"intro_splash": {"kind": Kind.SFX, "files": [A + "intro_splash.ogg"], "db": 2.0},
	"intro_glug": {"kind": Kind.SFX, "files": [A + "intro_glug.ogg"]},
	"intro_clonk": {"kind": Kind.SFX, "files": [A + "intro_clonk.ogg"]},
	"intro_poof_1": {"kind": Kind.SFX, "files": [A + "intro_poof_1.ogg"]},
	"intro_poof_2": {"kind": Kind.SFX, "files": [A + "intro_poof_2.ogg"]},
	"intro_poof_3": {"kind": Kind.SFX, "files": [A + "intro_poof_3.ogg"]},
	"intro_flip": {"kind": Kind.SFX, "files": [A + "intro_flip.ogg"]},
	"clatter": {"kind": Kind.SFX, "files": [IMPACT + "impactPlate_heavy_000.ogg", IMPACT + "impactPlate_heavy_001.ogg"],
		"pitch": 1.1},
}

static var _cache: Dictionary[String, AudioStream] = {}


## Drops the cached streams (Session does it when it leaves, so nothing is held at exit).
static func clear_cache() -> void:
	_cache.clear()


static func has_sound(sound: String) -> bool:
	return SOUNDS.has(sound)


static func get_stream(sound: String) -> AudioStream:
	if DisplayServer.get_name() == "headless":
		return null  # nothing plays there; and no cache left holding streams at exit
	if _cache.has(sound):
		return _cache[sound]
	var def: Dictionary = SOUNDS.get(sound, {})
	if def.is_empty():
		push_warning("Sfx: unknown sound '%s'" % sound)
		_cache[sound] = null
		return null
	var files: Array = def["files"]
	var loop: bool = def.get("loop", false)
	var pitch: float = def.get("pitch", 1.0)
	var stream: AudioStream
	if files.size() == 1 and pitch <= 1.0:
		stream = _load(files[0], loop)
	else:
		var rnd := AudioStreamRandomizer.new()
		for path: String in files:
			rnd.add_stream(-1, _load(path, loop))
		rnd.random_pitch = maxf(pitch, 1.0)
		rnd.random_volume_offset_db = 1.5
		stream = rnd
	_cache[sound] = stream
	return stream


static func _load(path: String, loop: bool) -> AudioStream:
	var stream := load(path) as AudioStream
	if loop:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


static func kind_of(sound: String) -> Kind:
	return SOUNDS.get(sound, {}).get("kind", Kind.SFX)


static func volume_of(sound: String) -> float:
	return SOUNDS.get(sound, {}).get("db", 0.0)


## A 3D player set up for `sound` (bus, distance, volume, reverb areas), not added to the tree.
static func make_player_3d(sound: String, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = get_stream(sound)
	var settings: Array = KINDS[kind_of(sound)]
	player.bus = settings[0]
	player.unit_size = settings[1]
	player.max_distance = settings[2]
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.volume_db = volume_of(sound) + volume_db
	player.area_mask = PhysicsLayers.AUDIO
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	return player


## Plays `sound` at `pos` (3D, positional) under `parent`, freeing the player afterwards.
static func play_at(parent: Node, sound: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var player := make_player_3d(sound, volume_db)
	parent.add_child(player)
	player.global_position = pos
	player.finished.connect(player.queue_free)
	player.play()
	var also: String = SOUNDS.get(sound, {}).get("also", "")
	if also != "":
		play_at(parent, also, pos, volume_db)


## Plays `sound` without position (heard the same everywhere): UI, stingers, plant-wide alarms.
static func play(parent: Node, sound: String, volume_db: float = 0.0) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var player := AudioStreamPlayer.new()
	player.stream = get_stream(sound)
	var kind := kind_of(sound)
	player.bus = KINDS[kind][0] if kind in [Kind.UI, Kind.MUSIC, Kind.HUM] else &"SFX"
	player.volume_db = volume_of(sound) + volume_db
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## A looping 3D player for `sound` under `parent` (not started; call play()).
static func loop_player(parent: Node, sound: String, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var player := make_player_3d(sound, volume_db)
	parent.add_child(player)
	return player
