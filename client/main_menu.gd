class_name MainMenu
extends Control
## Connect screen. Creates the Session, connects, and frees itself once the server accepts us.
## If anything goes wrong later, the Session reopens this scene with `notice` set to the reason.

const SESSION_SCENE: PackedScene = preload("res://common/Session.tscn")

## Shown once when the menu opens (for example why we got disconnected).
static var notice := ""
static var _auto_connect_used := false

@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	connect_button.pressed.connect(_on_connect_pressed)
	name_edit.text_submitted.connect(_on_text_submitted)
	address_edit.text_submitted.connect(_on_text_submitted)
	status_label.text = notice
	notice = ""
	if Cli.has_arg("name"):
		name_edit.text = Cli.get_str("name")
	# `--connect host:port` connects straight away, but only once: not again after a disconnect.
	if Cli.has_arg("connect") and not _auto_connect_used:
		_auto_connect_used = true
		address_edit.text = Cli.get_str("connect")
		_on_connect_pressed.call_deferred()
	else:
		name_edit.grab_focus()


func _on_text_submitted(_text: String) -> void:
	if not connect_button.disabled:
		_on_connect_pressed()


func _on_connect_pressed() -> void:
	var addr := Net.parse_address(address_edit.text)
	if addr.is_empty():
		status_label.text = "Invalid address, expected host:port"
		return

	# The Session must exist before we connect: the server starts replicating (spawning
	# the other players) as soon as the connection is up.
	var session: Session = SESSION_SCENE.instantiate()
	session.desired_name = name_edit.text
	session.joined.connect(queue_free)
	get_tree().root.add_child(session)

	var err := Net.join(addr["host"], addr["port"])
	if err != OK:
		get_tree().root.remove_child(session)
		session.queue_free()
		status_label.text = "Could not start the connection: %s" % error_string(err)
		return
	connect_button.disabled = true
	status_label.text = "Connecting to %s:%d…" % [addr["host"], addr["port"]]
	Log.info("menu", status_label.text)
