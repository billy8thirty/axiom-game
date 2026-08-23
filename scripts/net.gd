extends Node

const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 16
const GAME_VERSION := "0.1.0"

const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/mainMenu.tscn"
const BROWSER_SCENE := "res://scenes/serverBrowser.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"

enum Mode {
	NONE,
	SINGLEPLAYER,
	CLIENT,
	LISTEN_SERVER,
	DEDICATED_SERVER,
}

signal players_changed
signal connected
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal player_joined(id: int, display_name: String)
signal player_left(id: int, display_name: String)

var mode := Mode.NONE
var players := {}  # peer_id -> { "name": String }
var player_name := "Player"

var server_name := "axiom server"
var map_name := "world"
var mode_name := "default"
var max_players := DEFAULT_MAX_PLAYERS

var _players_root: Node = null
var _spawn_points: Array[Vector3] = []
var _spawn_index := 0
var _pending_spawn := Vector3.INF


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return mode == Mode.LISTEN_SERVER or mode == Mode.DEDICATED_SERVER


func is_dedicated() -> bool:
	return mode == Mode.DEDICATED_SERVER


func is_online() -> bool:
	return mode == Mode.CLIENT or is_server()


func player_display_name(id: int) -> String:
	var info: Dictionary = players.get(id, {})
	return str(info.get("name", "Spieler %d" % id))


# "127.0.0.1:7777", "example.com", "[::1]:7777" -> { ok, address, port, error }
static func parse_address(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	if text.is_empty():
		return {"ok": false, "address": "", "port": 0,
			"error": "Adresse fehlt - z.B. 127.0.0.1:%d" % DEFAULT_PORT}

	var address := text
	var port := DEFAULT_PORT

	# Doppelpunkt trennt nur ab, wenn dahinter eine Zahl steht - sonst ist es
	# eine nackte IPv6 wie "::1".
	var sep := text.rfind(":")
	if sep > 0 and not text.ends_with("]"):
		var tail := text.substr(sep + 1)
		if tail.is_valid_int():
			address = text.substr(0, sep)
			port = tail.to_int()

	address = address.trim_prefix("[").trim_suffix("]")

	if address.is_empty():
		return {"ok": false, "address": "", "port": 0, "error": "Adresse fehlt"}
	if port < 1 or port > 65535:
		return {"ok": false, "address": address, "port": port,
			"error": "Port %d ist ausserhalb 1-65535." % port}

	return {"ok": true, "address": address, "port": port, "error": ""}


# --- Starten ---

func start_singleplayer() -> void:
	reset()
	mode = Mode.SINGLEPLAYER

	# Ohne Peer ist get_unique_id() 0, dann matcht die Authority aus player.gd
	# nicht und die Figur hat keine Kamera und keine Physik.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	players = {1: {"name": player_name}}
	players_changed.emit()
	get_tree().change_scene_to_file(WORLD_SCENE)


func host(port: int, dedicated: bool, publish: bool, use_upnp: bool = false) -> bool:
	reset()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		var reason := "Server auf Port %d konnte nicht starten (Fehler %d)" % [port, err]
		push_error(reason)
		connection_failed.emit(reason)
		return false

	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED_SERVER if dedicated else Mode.LISTEN_SERVER

	if not dedicated:
		players[1] = {"name": player_name}
	players_changed.emit()

	get_tree().change_scene_to_file(WORLD_SCENE)

	if use_upnp or publish:
		_announce(port, dedicated, publish, use_upnp)
	return true


func _announce(port: int, dedicated: bool, publish: bool, use_upnp: bool) -> void:
	# Erst nach dem UPnP-Ergebnis registrieren, sonst listet der Master die
	# LAN-Adresse.
	if use_upnp:
		PortMapper.open(port)
		var result: Array = await PortMapper.finished
		var ok := bool(result[0])
		var address := str(result[1])
		var reachable := bool(result[2])

		if ok and reachable:
			MasterServer.public_address = address
		elif ok:
			push_warning("[net] Portfreigabe steht, aber %s ist selbst hinter NAT" % address)

	if not publish:
		return

	MasterServer.publish({
		"name": server_name,
		"port": port,
		"map": map_name,
		"mode": mode_name,
		"max_players": max_players,
		"dedicated": dedicated,
		"has_password": false,
		"version": GAME_VERSION,
	})


func join(address: String, port: int) -> bool:
	reset()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		var reason := "Verbindung zu %s:%d fehlgeschlagen (Fehler %d)" % [address, port, err]
		push_error(reason)
		connection_failed.emit(reason)
		return false

	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return true


func leave() -> void:
	if MasterServer.is_published():
		MasterServer.unpublish()
	if PortMapper.is_mapped():
		PortMapper.close()
	reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func reset() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = null

	mode = Mode.NONE
	players.clear()
	_players_root = null
	_spawn_points.clear()
	_spawn_index = 0
	_pending_spawn = Vector3.INF


# --- Welt ---

# Von world.gd im _ready() aufgerufen. Vorher gibt es Players und Spawner nicht.
func world_ready(world: Node) -> void:
	_players_root = world.get_node_or_null(^"Players")
	if _players_root == null:
		push_error("Welt ohne Players-Node - es kann niemand spawnen")
		return

	_spawn_points.assign(world.get_spawn_points())
	if _spawn_points.is_empty():
		_spawn_points.append(Vector3(0, 1, 0))

	match mode:
		Mode.SINGLEPLAYER:
			_spawn_player(1)
		Mode.LISTEN_SERVER:
			_spawn_player(1)
		Mode.CLIENT:
			_request_join.rpc_id(1, player_name, GAME_VERSION)
		Mode.DEDICATED_SERVER:
			pass


func _next_spawn_position() -> Vector3:
	var p := _spawn_points[_spawn_index % _spawn_points.size()]
	_spawn_index += 1
	return p


# Vector3.INF = nicht gespawnt (kein Players-Node oder schon vorhanden).
func _spawn_player(id: int) -> Vector3:
	if _players_root == null or not is_instance_valid(_players_root):
		return Vector3.INF
	if _players_root.has_node(NodePath(str(id))):
		return Vector3.INF

	var spawn := _next_spawn_position()
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	player.name = str(id)
	player.position = spawn
	_players_root.add_child(player)
	return spawn


func _despawn_player(id: int) -> void:
	if _players_root == null or not is_instance_valid(_players_root):
		return
	var player := _players_root.get_node_or_null(NodePath(str(id)))
	if player != null:
		player.queue_free()


# --- RPCs ---

@rpc("any_peer", "reliable")
func _request_join(requested_name: String, version: String) -> void:
	if not multiplayer.is_server():
		return

	var id := multiplayer.get_remote_sender_id()

	if version != GAME_VERSION:
		_join_rejected.rpc_id(id, "Version passt nicht (Server %s, Client %s)" % [GAME_VERSION, version])
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return

	if players.size() >= max_players:
		_join_rejected.rpc_id(id, "Server ist voll")
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return

	players[id] = {"name": _sanitize_name(requested_name)}
	var spawn := _spawn_player(id)

	_sync_server_info.rpc_id(id, {
		"name": server_name,
		"map": map_name,
		"mode": mode_name,
		"max_players": max_players,
	})

	_sync_players.rpc(players)
	if spawn.is_finite():
		_set_spawn.rpc_id(id, spawn)
	players_changed.emit()
	player_joined.emit(id, player_display_name(id))
	print("[net] %s (%d) ist beigetreten - %d/%d" % [player_display_name(id), id, players.size(), max_players])


@rpc("authority", "reliable")
func _sync_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


# Slots, Karte und Name kennt der Client sonst nicht - bei Direktverbindung hat
# er nur Adresse und Port.
@rpc("authority", "reliable")
func _sync_server_info(info: Dictionary) -> void:
	server_name = str(info.get("name", server_name))
	map_name = str(info.get("map", map_name))
	mode_name = str(info.get("mode", mode_name))
	max_players = int(info.get("max_players", max_players))
	players_changed.emit()


# Startposition muss extra geschickt werden: set_multiplayer_authority ist
# rekursiv, der Synchronizer der Figur gehoert also dem Client und der Server
# kann die Position nicht im Spawn-State mitgeben.
#
# Anderer Kanal als die Spawn-Replikation, Reihenfolge nicht garantiert - ist
# die Figur schon da, sofort korrigieren, sonst holt player.gd sie in _ready().
@rpc("authority", "reliable")
func _set_spawn(spawn: Vector3) -> void:
	_pending_spawn = spawn
	if _players_root == null or not is_instance_valid(_players_root):
		return

	var mine := _players_root.get_node_or_null(NodePath(str(multiplayer.get_unique_id())))
	if mine != null and mine.has_method(&"apply_spawn_position"):
		mine.apply_spawn_position(spawn)
		_pending_spawn = Vector3.INF


func take_spawn_position() -> Vector3:
	var spawn := _pending_spawn
	_pending_spawn = Vector3.INF
	return spawn


@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	push_warning("Join abgelehnt: " + reason)
	reset()
	connection_failed.emit(reason)
	get_tree().change_scene_to_file(BROWSER_SCENE)


# --- ENet ---

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[net] Peer %d verbunden" % id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return

	var display := player_display_name(id)
	players.erase(id)
	_despawn_player(id)
	_sync_players.rpc(players)
	players_changed.emit()
	player_left.emit(id, display)
	print("[net] %s (%d) hat verlassen - %d/%d" % [display, id, players.size(), max_players])


func _on_connected_to_server() -> void:
	connected.emit()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_connection_failed() -> void:
	reset()
	connection_failed.emit("Server nicht erreichbar")


func _on_server_disconnected() -> void:
	reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	disconnected.emit("Verbindung zum Server verloren")
	get_tree().change_scene_to_file(BROWSER_SCENE)


func _sanitize_name(raw: String) -> String:
	var clean := raw.strip_edges()
	if clean.is_empty():
		clean = "Spieler"
	return clean.substr(0, 24)
