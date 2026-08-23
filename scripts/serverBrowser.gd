extends Control

# Direktverbindung geht absichtlich ohne die Liste - so laesst sich ein lokaler
# Server auch ohne laufenden Master testen.

const COL_NAME := 0
const COL_MAP := 1
const COL_MODE := 2
const COL_PLAYERS := 3
const COL_VERSION := 4
const COL_ADDRESS := 5

@onready var player_name_edit: LineEdit = $Margin/Root/TopRow/PlayerName
@onready var master_url_edit: LineEdit = $Margin/Root/TopRow/MasterUrl
@onready var tree: Tree = $Margin/Root/ServerTree
@onready var refresh_button: Button = $Margin/Root/ListRow/Refresh
@onready var join_button: Button = $Margin/Root/ListRow/Join
@onready var direct_address_edit: LineEdit = $Margin/Root/DirectRow/DirectAddress
@onready var direct_button: Button = $Margin/Root/DirectRow/DirectConnect
@onready var host_name_edit: LineEdit = $Margin/Root/HostRow/HostName
@onready var host_port_edit: LineEdit = $Margin/Root/HostRow/HostPort
@onready var host_publish_check: CheckBox = $Margin/Root/HostRow/HostPublish
@onready var host_upnp_check: CheckBox = $Margin/Root/HostRow/HostUpnp
@onready var host_address_edit: LineEdit = $Margin/Root/HostRow/HostAddress
@onready var host_button: Button = $Margin/Root/HostRow/HostButton
@onready var status_label: Label = $Margin/Root/Status
@onready var back_button: Button = $Margin/Root/BackRow/Back

var _loading := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	player_name_edit.text = Net.player_name
	master_url_edit.text = MasterServer.base_url
	host_name_edit.text = "Server von %s" % Net.player_name
	host_port_edit.text = str(Net.DEFAULT_PORT)
	direct_address_edit.text = "127.0.0.1:%d" % Net.DEFAULT_PORT

	_setup_tree()

	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	direct_button.pressed.connect(_on_direct_pressed)
	host_button.pressed.connect(_on_host_pressed)
	back_button.pressed.connect(_on_back_pressed)
	tree.item_activated.connect(_on_join_pressed)

	MasterServer.server_list.connect(_on_server_list)
	MasterServer.server_list_failed.connect(_on_server_list_failed)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_connection_failed)

	_set_status("Bereit.")
	_on_refresh_pressed()


func _setup_tree() -> void:
	tree.columns = 6
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW

	tree.set_column_title(COL_NAME, "Name")
	tree.set_column_title(COL_MAP, "Karte")
	tree.set_column_title(COL_MODE, "Modus")
	tree.set_column_title(COL_PLAYERS, "Spieler")
	tree.set_column_title(COL_VERSION, "Version")
	tree.set_column_title(COL_ADDRESS, "Adresse")

	tree.set_column_expand_ratio(COL_NAME, 3)
	tree.set_column_expand_ratio(COL_MAP, 2)
	tree.set_column_expand_ratio(COL_MODE, 2)
	tree.set_column_expand_ratio(COL_PLAYERS, 1)
	tree.set_column_expand_ratio(COL_VERSION, 1)
	tree.set_column_expand_ratio(COL_ADDRESS, 3)


# --- Liste ---

func _on_refresh_pressed() -> void:
	if _loading:
		return
	_loading = true
	_apply_inputs()
	_set_status("Lade Server von %s ..." % MasterServer.base_url)
	MasterServer.fetch_servers()


func _on_server_list(servers: Array) -> void:
	_loading = false
	tree.clear()
	var root := tree.create_item()

	for entry in servers:
		if entry is not Dictionary:
			continue
		var server: Dictionary = entry
		var address := str(server.get("address", ""))
		var port := int(server.get("port", Net.DEFAULT_PORT))
		if address.is_empty():
			continue

		var item := tree.create_item(root)
		item.set_text(COL_NAME, str(server.get("name", "?")))
		item.set_text(COL_MAP, str(server.get("map", "-")))
		item.set_text(COL_MODE, str(server.get("mode", "-")))
		item.set_text(COL_PLAYERS, "%d/%d" % [
			int(server.get("players", 0)),
			int(server.get("max_players", 0)),
		])
		item.set_text(COL_VERSION, str(server.get("version", "-")))
		item.set_text(COL_ADDRESS, "%s:%d" % [address, port])
		item.set_metadata(COL_NAME, {"address": address, "port": port})

	var count := root.get_child_count()
	if count == 0:
		_set_status("Keine Server gefunden. Direktverbindung geht trotzdem.")
	else:
		_set_status("%d Server gefunden." % count)


func _on_server_list_failed(reason: String) -> void:
	_loading = false
	tree.clear()
	_set_status(reason)


func _on_join_pressed() -> void:
	var item := tree.get_selected()
	if item == null:
		_set_status("Erst einen Server in der Liste auswaehlen.")
		return

	var meta: Variant = item.get_metadata(COL_NAME)
	if meta is not Dictionary:
		_set_status("Eintrag ohne Adresse - bitte aktualisieren.")
		return

	var data: Dictionary = meta
	Net.server_name = item.get_text(COL_NAME)
	_connect_to(str(data["address"]), int(data["port"]))


# --- Direktverbindung ---

func _on_direct_pressed() -> void:
	var parsed := Net.parse_address(direct_address_edit.text)
	if not parsed["ok"]:
		_set_status(str(parsed["error"]))
		return

	var address := str(parsed["address"])
	var port := int(parsed["port"])
	Net.server_name = "%s:%d" % [address, port]
	_connect_to(address, port)


func _connect_to(address: String, port: int) -> void:
	_apply_inputs()
	_set_status("Verbinde zu %s:%d ..." % [address, port])
	if not Net.join(address, port):
		_set_status("Verbindung zu %s:%d fehlgeschlagen." % [address, port])


# --- Hosten ---

func _on_host_pressed() -> void:
	_apply_inputs()

	var port_text := host_port_edit.text.strip_edges()
	if not port_text.is_valid_int():
		_set_status("Port muss eine Zahl sein.")
		return
	var port := port_text.to_int()
	if port < 1 or port > 65535:
		_set_status("Port %d ist ausserhalb 1-65535." % port)
		return

	var wanted_name := host_name_edit.text.strip_edges()
	Net.server_name = wanted_name if not wanted_name.is_empty() else "axiom server"
	Net.map_name = "world"
	Net.mode_name = "default"

	# Ohne UPnP (z.B. Speedport - kann das grundsaetzlich nicht) bleibt
	# MasterServer.public_address sonst leer, und der Master traegt die Adresse
	# ein, von der die Registrierung kam. Laeuft der Master lokal, ist das
	# 127.0.0.1 und niemand von aussen kann beitreten - deshalb hier von Hand
	# ueberschreibbar. Das Feld ist bei jedem Hosten die alleinige Quelle -
	# sonst wuerde eine erfolgreiche Eingabe von vorhin ueberleben, wenn UPnP
	# beim naechsten Versuch fehlschlaegt. Klappt UPnP anschliessend doch,
	# ueberschreibt Net._announce() das hier wieder mit der echten Adresse.
	var wanted_address := host_address_edit.text.strip_edges()
	if wanted_address.is_empty():
		MasterServer.public_address = ""
	else:
		# Ueber parse_address geschickt, damit sowohl "1.2.3.4" als auch
		# "2003:ed:..." (mit oder ohne Klammern) landen, ohne dass hier ein
		# eigener IPv6-Parser noetig ist. Der angehaengte Port wird verworfen.
		var parsed := Net.parse_address(wanted_address + ":1")
		if not parsed["ok"]:
			_set_status("Adresse ungueltig - nur die IP/den Host angeben, ohne Port.")
			return
		MasterServer.public_address = str(parsed["address"])

	# UPnP-Ergebnis kommt erst spaeter, da ist diese Szene weg - Anzeige in world.gd.
	_set_status("Starte Listen-Server auf Port %d ..." % port)
	if not Net.host(port, false, host_publish_check.button_pressed, host_upnp_check.button_pressed):
		_set_status("Server konnte nicht starten - Port %d schon belegt?" % port)


# --- Sonstiges ---

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(Net.MENU_SCENE)


func _on_connection_failed(reason: String) -> void:
	_set_status(reason)


func _apply_inputs() -> void:
	var wanted := player_name_edit.text.strip_edges()
	if not wanted.is_empty():
		Net.player_name = wanted

	var url := master_url_edit.text.strip_edges().rstrip("/")
	if not url.is_empty():
		MasterServer.base_url = url


func _set_status(text: String) -> void:
	status_label.text = text
	print("[browser] " + text)
