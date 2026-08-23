extends Node

# HTTP-Client für axiom-masterserver. Der Master wirft Eintraege ohne
# Heartbeat per TTL raus, ein verpasstes unregister ist also nicht schlimm.

const DEFAULT_URL := "http://127.0.0.1:8080"
const REQUEST_TIMEOUT := 5.0

signal published(id: String)
signal publish_failed(reason: String)
signal server_list(servers: Array)
signal server_list_failed(reason: String)

var base_url := DEFAULT_URL
# Leer = der Master nimmt die IP der Verbindung.
var public_address := ""

var _server_id := ""
var _token := ""
var _heartbeat: Timer


func _ready() -> void:
	if OS.has_environment("AXIOM_MASTER_URL"):
		base_url = OS.get_environment("AXIOM_MASTER_URL")

	_heartbeat = Timer.new()
	_heartbeat.one_shot = false
	_heartbeat.timeout.connect(_send_heartbeat)
	add_child(_heartbeat)


func is_published() -> bool:
	return not _server_id.is_empty()


# --- Server-Liste ---

# filters landen als Query-Parameter, z.B. { "dedicated": "true" }.
func fetch_servers(filters: Dictionary = {}) -> void:
	var path := "/v1/servers"
	var query := PackedStringArray()
	for key: String in filters:
		var value := str(filters[key])
		if not value.is_empty():
			query.append("%s=%s" % [key.uri_encode(), value.uri_encode()])
	if query.size() > 0:
		path += "?" + "&".join(query)

	var res := await _request(HTTPClient.METHOD_GET, path)
	if not res["ok"]:
		server_list_failed.emit(res["error"])
		return

	var data: Dictionary = res["data"] if res["data"] is Dictionary else {}
	var servers: Array = data.get("servers") if data.get("servers") is Array else []
	server_list.emit(servers)


# --- Eigenen Server registrieren ---

func publish(info: Dictionary) -> void:
	if is_published():
		await unpublish()

	var body := info.duplicate()
	if not public_address.is_empty():
		body["address"] = public_address

	var res := await _request(HTTPClient.METHOD_POST, "/v1/servers", body)
	if not res["ok"]:
		push_warning("[master] Registrierung fehlgeschlagen: " + res["error"])
		publish_failed.emit(res["error"])
		return

	var data: Dictionary = res["data"]
	_server_id = str(data.get("id", ""))
	_token = str(data.get("token", ""))

	var interval := int(data.get("heartbeat_seconds", 20))
	_heartbeat.start(maxi(interval, 5))

	print("[master] Registriert als %s bei %s" % [_server_id, base_url])
	published.emit(_server_id)


func unpublish() -> void:
	if not is_published():
		return

	var id := _server_id
	_heartbeat.stop()
	_server_id = ""
	var token := _token
	_token = ""

	var res := await _request(HTTPClient.METHOD_DELETE, "/v1/servers/" + id, null, token)
	if res["ok"]:
		print("[master] Abgemeldet (%s)" % id)
	else:
		# Nicht kritisch, die TTL raeumt eh auf.
		push_warning("[master] Abmelden fehlgeschlagen: " + res["error"])


func _send_heartbeat() -> void:
	if not is_published():
		return

	var res := await _request(HTTPClient.METHOD_PUT, "/v1/servers/%s/heartbeat" % _server_id, {
		"players": Net.players.size(),
		"map": Net.map_name,
		"mode": Net.mode_name,
	}, _token)

	if not res["ok"]:
		push_warning("[master] Heartbeat fehlgeschlagen: " + res["error"])
		# 404/401: Eintrag ist weg. Lieber aufhoeren als endlos ins Leere senden.
		if res["code"] == 404 or res["code"] == 401:
			_heartbeat.stop()
			_server_id = ""
			_token = ""


# --- HTTP ---

# -> { ok, code, data, error }
func _request(method: int, path: String, body: Variant = null, token: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)

	var headers := PackedStringArray(["Accept: application/json"])
	if body != null:
		headers.append("Content-Type: application/json")
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)

	var payload := JSON.stringify(body) if body != null else ""
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null, "error": "Request fehlgeschlagen (%d)" % err}

	var result: Array = await http.request_completed
	http.queue_free()

	var status := int(result[0])
	var code := int(result[1])
	var text := (result[3] as PackedByteArray).get_string_from_utf8()

	if status != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": code, "data": null,
			"error": "Master Server nicht erreichbar (%s)" % base_url}
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else {}

	if code < 200 or code >= 300:
		var message := "HTTP %d" % code
		if data is Dictionary and data.has("error"):
			message = str(data["error"])
		return {"ok": false, "code": code, "data": data, "error": message}

	return {"ok": true, "code": code, "data": data if data != null else {}, "error": ""}
