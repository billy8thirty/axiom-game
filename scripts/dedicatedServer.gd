extends Node

# Startszene des Headless-Servers. Danach uebernimmt world.tscn und dieser Node
# ist weg - Heartbeat und Shutdown liegen deshalb in MasterServer und Boot.

const DEFAULT_NAME := "axiom dedicated"
const DEFAULT_TICKRATE := 60


func _ready() -> void:
	var port := _int_arg("port", Net.DEFAULT_PORT, 1, 65535)
	var tickrate := _int_arg("tickrate", DEFAULT_TICKRATE, 10, 240)
	var publish := not Boot.args.has("no-publish")
	# opt-in: Serverbetreiber leiten den Port normalerweise selbst um.
	var use_upnp := Boot.args.has("upnp")

	Net.server_name = _str_arg("name", DEFAULT_NAME)
	Net.map_name = _str_arg("map", "world")
	Net.mode_name = _str_arg("mode", "default")
	Net.max_players = _int_arg("max-players", Net.DEFAULT_MAX_PLAYERS, 1, 1024)

	Engine.physics_ticks_per_second = tickrate
	# Ohne Limit dreht die Hauptschleife im Headless frei und frisst einen Kern.
	Engine.max_fps = tickrate

	_print_banner(port, tickrate, publish, use_upnp)

	if not Net.host(port, true, publish, use_upnp):
		push_error("[server] Start fehlgeschlagen - Port %d belegt?" % port)
		get_tree().quit(1)


func _print_banner(port: int, tickrate: int, publish: bool, use_upnp: bool) -> void:
	print("")
	print("  axiom dedicated server  v%s" % Net.GAME_VERSION)
	print("  ----------------------------------------")
	print("  Name        : %s" % Net.server_name)
	print("  Port        : %d (UDP)" % port)
	print("  Karte       : %s" % Net.map_name)
	print("  Modus       : %s" % Net.mode_name)
	print("  Slots       : %d" % Net.max_players)
	print("  Tickrate    : %d Hz" % tickrate)
	if publish:
		print("  Master      : %s" % MasterServer.base_url)
	else:
		print("  Master      : aus (--no-publish)")
	if use_upnp:
		print("  UPnP        : Portfreigabe wird angefragt")
	print("")


func _str_arg(key: String, fallback: String) -> String:
	var value: Variant = Boot.arg(key)
	if value == null or value is bool:
		return fallback
	var text := str(value).strip_edges()
	return fallback if text.is_empty() else text


func _int_arg(key: String, fallback: int, minimum: int, maximum: int) -> int:
	var value: Variant = Boot.arg(key)
	if value == null or value is bool:
		return fallback
	var text := str(value)
	if not text.is_valid_int():
		push_warning("[server] --%s=%s ist keine Zahl, nutze %d" % [key, text, fallback])
		return fallback
	return clampi(text.to_int(), minimum, maximum)
