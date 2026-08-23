extends Node3D

@onready var hud: CanvasLayer = $HUD
@onready var info_label: Label = $HUD/Info
@onready var pause_menu: Control = $HUD/PauseMenu
@onready var resume_button: Button = $HUD/PauseMenu/Panel/Buttons/Resume
@onready var leave_button: Button = $HUD/PauseMenu/Panel/Buttons/Leave

var _paused := false
var _upnp_line := ""


func _ready() -> void:
	pause_menu.hide()

	resume_button.pressed.connect(_set_paused.bind(false))
	leave_button.pressed.connect(_on_leave_pressed)

	Net.players_changed.connect(_update_info)
	PortMapper.finished.connect(_on_upnp_finished)

	if Net.is_dedicated():
		hud.hide()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Zuletzt - ab hier darf gespawnt werden.
	Net.world_ready(self)
	_update_info()


# Global, weil SpawnPoints selbst verschoben sein kann.
func get_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker in $SpawnPoints.get_children():
		if marker is Node3D:
			points.append((marker as Node3D).global_position)
	return points


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_dedicated():
		return
	if event.is_action_pressed(&"ui_cancel"):
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()


func _set_paused(value: bool) -> void:
	_paused = value
	pause_menu.visible = value
	# Kein get_tree().paused - sonst frieren im Multiplayer die anderen Spieler
	# auf unserem Bildschirm ein.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED


func _on_leave_pressed() -> void:
	Net.leave()


# Kommt erst nach dem Szenenwechsel rein, deshalb hier und nicht im Browser.
func _on_upnp_finished(ok: bool, address: String, reachable: bool, error: String) -> void:
	if not ok:
		_upnp_line = "Portfreigabe fehlgeschlagen: %s" % error
	elif reachable:
		_upnp_line = "Von aussen erreichbar: %s" % address
	else:
		_upnp_line = "Nicht von aussen erreichbar (%s hinter NAT)" % address

	print("[world] " + _upnp_line)
	_update_info()


func _update_info() -> void:
	if not is_instance_valid(info_label):
		return

	var lines := PackedStringArray([
		_mode_text(),
		"%d/%d Spieler" % [Net.players.size(), Net.max_players],
		"Peer %s" % _peer_text(),
	])
	if not _upnp_line.is_empty():
		lines.append(_upnp_line)

	info_label.text = "\n".join(lines)


func _mode_text() -> String:
	match Net.mode:
		Net.Mode.SINGLEPLAYER:
			return "Singleplayer"
		Net.Mode.CLIENT:
			return "Client - " + Net.server_name
		Net.Mode.LISTEN_SERVER:
			return "Listen-Server - " + Net.server_name
		Net.Mode.DEDICATED_SERVER:
			return "Dedicated Server - " + Net.server_name
		_:
			return "Offline"


func _peer_text() -> String:
	if not Net.is_online():
		return "lokal"
	var peer := Net.multiplayer.multiplayer_peer
	if peer == null:
		return "-"
	return str(Net.multiplayer.get_unique_id())
