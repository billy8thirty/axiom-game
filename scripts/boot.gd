extends Node

# Client oder dedizierter Server? Beides ist dasselbe Projekt, der Server ist
# nur ein Headless-Build.
#
#   godot --headless -- --server --port=7777 --name="EU #1"

const DEDICATED_SCENE := "res://scenes/dedicatedServer.tscn"

# "--port=7777" -> { "port": "7777" }, "--server" -> { "server": true }
var args := {}


func _ready() -> void:
	args = _parse_args()

	if args.has("master"):
		MasterServer.base_url = str(args["master"])
	if args.has("public-address"):
		MasterServer.public_address = str(args["public-address"])
	if args.has("player-name"):
		Net.player_name = str(args["player-name"])

	if is_server_mode():
		# Shutdown selbst abwickeln, um uns beim Master abzumelden statt auf die
		# TTL zu warten.
		get_tree().auto_accept_quit = false
		get_tree().change_scene_to_file.call_deferred(DEDICATED_SCENE)
	elif args.has("connect"):
		_auto_connect(str(args["connect"]))


# --connect=127.0.0.1:7777 ueberspringt Splash und Menue. Fuer den lokalen
# Zwei-Client-Test.
func _auto_connect(target: String) -> void:
	var parsed := Net.parse_address(target)
	if not parsed["ok"]:
		push_error("[boot] --connect=%s: %s" % [target, parsed["error"]])
		return

	var address := str(parsed["address"])
	var port := int(parsed["port"])
	Net.server_name = "%s:%d" % [address, port]
	print("[boot] --connect: verbinde zu %s:%d als '%s'" % [address, port, Net.player_name])

	# Deferred, damit die Autoloads durch sind, bevor ENet aufgebaut wird.
	Net.join.call_deferred(address, port)


func is_server_mode() -> bool:
	return args.has("server") or OS.has_feature("dedicated_server")


func arg(key: String, fallback: Variant = null) -> Variant:
	return args.get(key, fallback)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_server_mode():
		_shutdown()


func _shutdown() -> void:
	print("[boot] Shutdown ...")
	await MasterServer.unpublish()
	if PortMapper.is_mapped():
		PortMapper.close()
	Net.reset()
	get_tree().quit()


# Beide Quellen: alles nach "--" und die rohe Kommandozeile, damit ein
# exportierter Server auch ohne Trenner funktioniert.
func _parse_args() -> Dictionary:
	var out := {}
	var raw := PackedStringArray()
	raw.append_array(OS.get_cmdline_args())
	raw.append_array(OS.get_cmdline_user_args())

	for entry in raw:
		if not entry.begins_with("--"):
			continue
		var body := entry.substr(2)
		if body.is_empty():
			continue
		var key := body
		var value: Variant = true
		var eq := body.find("=")
		if eq >= 0:
			key = body.substr(0, eq)
			value = body.substr(eq + 1).lstrip("\"").rstrip("\"")
		out[key] = value

	return out
