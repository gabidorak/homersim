class_name Pickup
extends Interactable
## Supervisor pickups (GDD §5.1), all instant:
##   trap_refill    Storage, the trap box: snap traps back to full
##   lure_refill    Storage, the cheese box: cheese lures back to full
##   spare_keycard  Storage: a new keycard, 30 s after losing yours
##   donut          Break Room: a donut to carry (one at a time), then a 60 s wait (per supervisor);
##                  eaten later from the hotbar (ItemService.request_eat_donut): +20% speed for 20 s
##   keycard        a keycard a stunned rat dropped (spawned in World/Dynamic): consumed on pickup
## Availability uses only replicated state (the supervisor's Inventory), so the prompt on the
## client and the server's check agree.

@export_enum("trap_refill", "lure_refill", "spare_keycard", "donut", "keycard") var item := "trap_refill"

## A refill pickup → the trap it refills (its ability id, Inventory.charges()).
const REFILLS := {"trap_refill": Inventory.SNAP_TRAP, "lure_refill": Inventory.CHEESE_LURE}

## item → [model (assets/generated), model scale, size of the use area, label]
const LOOKS := {
	"trap_refill": ["trap_refill", 1.0, Vector3(0.6, 0.4, 0.4), "SNAP TRAPS"],
	"lure_refill": ["cheese_box", 1.0, Vector3(0.6, 0.4, 0.4), "CHEESE LURES"],
	"spare_keycard": ["keycard", 2.0, Vector3(0.5, 0.9, 0.35), "SPARE KEYCARD"],
	"donut": ["donut_box", 1.0, Vector3(0.5, 0.2, 0.5), "DONUTS"],
	"keycard": ["keycard", 1.6, Vector3(0.25, 0.02, 0.16), ""],
}

var tuning: PvpTuning = PvpTuning.load_default()
var _taken := false  # a consumed keycard, until queue_free() lands


func _init() -> void:
	allowed_roles = [Role.Kind.SUPERVISOR]
	kind = "instant"
	reach = 2.2
	needs_sync = false


func _ready() -> void:
	super()
	_build_look()


func is_available(player: Player) -> bool:
	var inv := player.inventory
	match item:
		"trap_refill", "lure_refill":
			return inv.charges(REFILLS[item]) < inv.max_charges(REFILLS[item])
		"spare_keycard":
			return not inv.keycard and (inv.spare_ready() if Net.is_server else inv.spare_wait_left == 0)
		"donut":
			return inv.can_take_donut() if Net.is_server \
				else inv.donuts < tuning.donut_carry_max and inv.donut_wait_left == 0
		"keycard":
			return not inv.keycard and not _taken
	return false


func prompt_for(player: Player) -> String:
	var inv := player.inventory
	match item:
		"trap_refill":
			return tr("Snap traps are full") if not is_available(player) else tr("Refill snap traps")
		"lure_refill":
			return tr("Cheese lures are full") if not is_available(player) else tr("Refill cheese lures")
		"spare_keycard":
			if inv.keycard:
				return tr("You have your keycard")
			return tr("Spare keycard in %d s") % inv.spare_wait_left if inv.spare_wait_left > 0 else tr("Take the spare keycard")
		"donut":
			if inv.donuts >= tuning.donut_carry_max:
				return tr("You already have a donut")
			return tr("Next donut in %d s") % inv.donut_wait_left if inv.donut_wait_left > 0 else tr("Take a donut")
		"keycard":
			return tr("You have a keycard") if inv.keycard else tr("Pick up the keycard")
	return prompt


func _complete(player: Player) -> void:
	var inv := player.inventory
	match item:
		"trap_refill", "lure_refill":
			inv.set_charges(REFILLS[item], inv.max_charges(REFILLS[item]))
		"spare_keycard", "keycard":
			inv.give_keycard()
		"donut":
			inv.take_donut()
	super(player)
	if item == "keycard":
		_taken = true
		queue_free()  # the Dynamic spawner removes it on clients too


func _build_look() -> void:
	var look: Array = LOOKS[item]
	var size: Vector3 = look[2]
	# Models stand on their base: put it at the bottom of the use area.
	var model := Art.add(self, look[0], Transform3D(Basis.from_scale(Vector3.ONE * look[1]), Vector3(0, -size.y * 0.5, 0)))
	if model != null:
		model.name = "Mesh"
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size.max(Vector3.ONE * 0.3)
	shape.shape = box_shape
	add_child(shape)
	if look[3] != "":
		var label := Label3D.new()
		label.text = tr(look[3])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 36
		label.outline_size = 8
		label.position.y = size.y * 0.5 + 0.35
		add_child(label)


## A dropped keycard bobs and turns so it catches the eye.
func _process(_delta: float) -> void:
	if item != "keycard" or not has_node("Mesh"):
		return
	var mesh := get_node("Mesh") as Node3D
	var t := Time.get_ticks_msec() / 1000.0
	mesh.rotation.y = fmod(t * 1.5, TAU)
	mesh.position.y = 0.08 + sin(t * 3.0) * 0.04