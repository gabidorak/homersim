class_name Sfx
extends RefCounted
## Placeholder sounds generated in code (until M7's audio pass), cached per name.

const RATE := 22050

static var _cache: Dictionary[String, AudioStreamWAV] = {}


static func get_stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		match sound:
			"bonk":  # a hollow knock that drops in pitch
				_cache[sound] = _make(0.22, func(t: float) -> float: return sin(TAU * (320.0 - 900.0 * t) * t) * 0.8)
			"whoosh":  # the broom cutting air: filtered noise
				_cache[sound] = _make(0.18, func(t: float) -> float: return randf_range(-1.0, 1.0) * 0.25 * sin(PI * t / 0.18))
			"chomp":
				_cache[sound] = _make(0.12, func(t: float) -> float: return signf(sin(TAU * 520.0 * t)) * 0.3)
			"snap":  # a loud crack
				_cache[sound] = _make(0.3, func(t: float) -> float: return randf_range(-1.0, 1.0) * exp(-t * 25.0))
			_:
				_cache[sound] = _make(0.1, func(t: float) -> float: return sin(TAU * 440.0 * t) * 0.3)
	return _cache[sound]


## Plays `sound` at `pos` (3D, positional) under `parent`, freeing the player afterwards.
static func play_at(parent: Node, sound: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	player.unit_size = 6.0
	parent.add_child(player)
	player.global_position = pos
	player.finished.connect(player.queue_free)
	player.play()


## Plays `sound` without position (heard the same everywhere).
static func play(parent: Node, sound: String, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = get_stream(sound)
	player.volume_db = volume_db
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


static func _make(seconds: float, wave: Callable) -> AudioStreamWAV:
	var samples := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / RATE
		var fade := minf(1.0, (samples - i) / 300.0)  # no click at the end
		data.encode_s16(i * 2, int(clampf(wave.call(t) * fade, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
