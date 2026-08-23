extends Node

# UPnP-Portfreigabe. UPNP.discover() blockiert ~2s, laeuft deshalb im Thread.

# reachable = false: Freigabe steht, Adresse ist aber selbst hinter NAT
# (DS-Lite / Carrier-NAT) - von aussen kommt trotzdem niemand rein.
signal finished(ok: bool, address: String, reachable: bool, error: String)

const DISCOVER_TIMEOUT_MS := 2000
const DISCOVER_TTL := 2
# 0 = dauerhaft. Befristete Leases lehnen manche Router ab.
const LEASE_SECONDS := 0
const MAPPING_DESC := "axiom game server"

var external_address := ""
var is_reachable := false

var _thread: Thread = null
var _mapped_port := 0


func is_mapped() -> bool:
	return _mapped_port > 0


func open(port: int) -> void:
	if _thread != null:
		push_warning("[upnp] Anfrage laeuft schon")
		return
	if is_mapped():
		close()

	_thread = Thread.new()
	var err := _thread.start(_worker.bind(port))
	if err != OK:
		_thread = null
		finished.emit(false, "", false, "Thread konnte nicht starten (Fehler %d)" % err)


# Blockiert kurz - Aufruf beim Beenden ist ok.
func close() -> void:
	if not is_mapped():
		return

	var port := _mapped_port
	_mapped_port = 0
	external_address = ""
	is_reachable = false

	var upnp := UPNP.new()
	if upnp.discover(DISCOVER_TIMEOUT_MS, DISCOVER_TTL, "InternetGatewayDevice") != UPNP.UPNP_RESULT_SUCCESS:
		return
	upnp.delete_port_mapping(port, "UDP")
	print("[upnp] Freigabe fuer Port %d entfernt" % port)


func _exit_tree() -> void:
	_join_thread()
	close()


func _worker(port: int) -> void:
	var upnp := UPNP.new()

	var err := upnp.discover(DISCOVER_TIMEOUT_MS, DISCOVER_TTL, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		_finish.call_deferred(0, "", _result_text(err))
		return

	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		_finish.call_deferred(0, "", "Kein UPnP-faehiges Gateway gefunden")
		return

	var address := upnp.query_external_address()

	var map_err := upnp.add_port_mapping(port, port, MAPPING_DESC, "UDP", LEASE_SECONDS)
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		_finish.call_deferred(0, address, _result_text(map_err))
		return

	_finish.call_deferred(port, address, "")


# wieder im Hauptthread
func _finish(port: int, address: String, error: String) -> void:
	_join_thread()

	external_address = address

	if not error.is_empty():
		is_reachable = false
		push_warning("[upnp] " + error)
		finished.emit(false, address, false, error)
		return

	_mapped_port = port
	is_reachable = is_public_address(address)

	if is_reachable:
		print("[upnp] Port %d offen, erreichbar unter %s" % [port, address])
	else:
		print("[upnp] Port %d freigegeben, aber %s ist selbst hinter NAT - "
			% [port, address] + "von aussen kommt so niemand rein (DS-Lite?)")

	finished.emit(true, address, is_reachable, "")


func _join_thread() -> void:
	if _thread == null:
		return
	_thread.wait_to_finish()
	_thread = null


# Falsch bei privaten Netzen und bei Carrier-NAT (100.64.0.0/10) - letzteres
# ist DS-Lite, da geht nur IPv6 nach aussen.
static func is_public_address(address: String) -> bool:
	var text := address.strip_edges()
	if text.is_empty():
		return false

	if text.contains(":"):
		var lower := text.to_lower()
		if lower.begins_with("fe80") or lower.begins_with("fc") or lower.begins_with("fd"):
			return false
		return lower != "::1"

	var parts := text.split(".")
	if parts.size() != 4:
		return false
	var a := parts[0].to_int()
	var b := parts[1].to_int()

	if a == 10 or a == 127 or a == 0:
		return false
	if a == 192 and b == 168:
		return false
	if a == 172 and b >= 16 and b <= 31:
		return false
	if a == 169 and b == 254:
		return false
	if a == 100 and b >= 64 and b <= 127:
		return false

	return true


func _result_text(code: int) -> String:
	match code:
		UPNP.UPNP_RESULT_NO_DEVICES:
			return "Kein UPnP-Geraet im Netz gefunden"
		UPNP.UPNP_RESULT_NO_GATEWAY:
			return "Kein Gateway gefunden"
		UPNP.UPNP_RESULT_NOT_AUTHORIZED:
			return "Router lehnt ab - UPnP ist dort abgeschaltet"
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING:
			return "Port ist schon von einer anderen Freigabe belegt"
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MECHANISM:
			return "Port kollidiert mit einer anderen Freigabe am Router"
		UPNP.UPNP_RESULT_ONLY_PERMANENT_LEASE_SUPPORTED:
			return "Router unterstuetzt nur dauerhafte Freigaben"
		UPNP.UPNP_RESULT_INVALID_GATEWAY:
			return "Gateway antwortet nicht wie erwartet"
		UPNP.UPNP_RESULT_HTTP_ERROR:
			return "HTTP-Fehler beim Router"
		UPNP.UPNP_RESULT_SOCKET_ERROR:
			return "Socket-Fehler bei der UPnP-Anfrage"
		_:
			return "UPnP-Fehler %d" % code
