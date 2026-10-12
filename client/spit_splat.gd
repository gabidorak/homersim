class_name SpitSplat
extends Control
## A cartoon gob of rat spit on the screen (CombatFeedback, when a caged rat's spit hits us): an
## ink-outlined blob with a few droplets, drips that run down, then a fade. Frees itself.

const INK := Color("1b1b1f")
const OUTLINE := 5.0  ## px
const LIFE_S := 2.2
const FADE_S := 0.7
const DRIP_SPEED := 70.0  ## px/s

var _blobs: Array[Vector3] = []  # x, y, radius (px, from the centre)
var _drips: Array[Vector3] = []  # x, y, width (px, from the centre)
var _age := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := RandomNumberGenerator.new()
	r.randomize()
	var big := r.randf_range(70.0, 95.0)
	_blobs.append(Vector3(0, 0, big))
	for i in 7:
		var a := r.randf() * TAU
		var d := big * r.randf_range(0.7, 1.5)
		_blobs.append(Vector3(cos(a) * d, sin(a) * d, r.randf_range(12.0, 34.0)))
	for i in 3:
		_drips.append(Vector3(r.randf_range(-big * 0.55, big * 0.55), big * 0.5, r.randf_range(14.0, 22.0)))
	# Somewhere off the crosshair, so it's funny rather than blinding.
	position = Vector2(r.randf_range(-0.25, 0.25), r.randf_range(-0.2, 0.15)) * get_viewport_rect().size


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE_S:
		queue_free()
		return
	modulate.a = clampf((LIFE_S - _age) / FADE_S, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var run := _age * DRIP_SPEED
	for pass_ink in [true, false]:
		var grow: float = OUTLINE if pass_ink else 0.0
		var color: Color = INK if pass_ink else Vfx.SPIT
		for b in _blobs:
			draw_circle(centre + Vector2(b.x, b.y), b.z + grow, color)
		for d in _drips:
			var top := centre + Vector2(d.x, d.y)
			var length := run * (d.z / 18.0)
			draw_rect(Rect2(top.x - d.z * 0.5 - grow, top.y, d.z + grow * 2.0, length), color)
			draw_circle(top + Vector2(0, length), d.z * 0.5 + grow, color)
	# A shine, like the other cartoon highlights.
	draw_circle(centre + Vector2(-_blobs[0].z * 0.35, -_blobs[0].z * 0.4), _blobs[0].z * 0.18, Color(1, 1, 1, 0.55))
