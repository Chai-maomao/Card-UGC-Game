class_name BetaRelayPeer
extends MultiplayerPeerExtension

# HTTPS carries opaque Godot packets. RPC validation, P1 authority, revisions,
# ACKs, card transfer and resume negotiation stay in the existing game layer.
const MAX_PACKET_BYTES := 192 * 1024
const POLL_INTERVAL_MS := 600
const MATCH_POLL_INTERVAL_MS := 120
const REQUEST_TIMEOUT_MS := 10000
const RESPONSE_LIMIT := 768 * 1024
var failure_reason := ""
var instance_id := ""
var _http := HTTPClient.new()
var _origin := ""
var _host := ""
var _port := 0
var _path := ""
var _request_path := ""
var _request_body := ""
var _response_code := 0
var _response_length := -1
var _response_body := PackedByteArray()
var _token := ""
var _id := 1
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _target := 0
var _refuse := false
var _incoming: Array[Dictionary] = []
var _outgoing: Array[Dictionary] = []
var _batch: Array[Dictionary] = []
var _cursor := 0
var _sequence := 0
var _generation := -1
var _busy := false
var _announced := false
var _next_poll := 0
var _request_started := 0
var _retry_after := 0
var _match_active := false
var _last_success := 0

func set_match_active() -> void:
	_match_active = true
	_next_poll = mini(_next_poll, Time.get_ticks_msec())

func setup(_owner_node: Node, url: String, code: String, token: String, player: int, transport_instance: String) -> void:
	var authority_end := url.find("/", url.find("://") + 3)
	_origin = url if authority_end < 0 else url.left(authority_end)
	# HTTPClient strips the scheme but does not parse an authority port.
	# Keep the endpoint's explicit port out of DNS (including bracketed IPv6).
	_host = _origin.substr(_origin.find("://") + 3)
	_port = 443 if _origin.begins_with("https://") else 80
	if _host.begins_with("["):
		var closing := _host.find("]")
		if closing > 0:
			if _host.substr(closing + 1).begins_with(":"): _port = int(_host.substr(closing + 2))
			_host = _host.substr(1, closing - 1)
	elif _host.count(":") == 1:
		_port = int(_host.get_slice(":", 1))
		_host = _host.get_slice(":", 0)
	_path = ("" if authority_end < 0 else url.substr(authority_end)) + "/api/rooms/" + code
	_token = token
	_id = player
	instance_id = transport_instance
	_status = MultiplayerPeer.CONNECTION_CONNECTED if _id == 1 else MultiplayerPeer.CONNECTION_CONNECTING
	_last_success = Time.get_ticks_msec()

func queued_packets() -> int:
	return _outgoing.size() + _batch.size()

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	if _busy:
		_poll_http()
		if _busy or _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return
	if Time.get_ticks_msec() < maxi(_next_poll, _retry_after):
		return
	if Time.get_ticks_msec() - _last_success > 30000:
		_fail("unavailable")
		return
	if _generation < 0:
		_request("attach", {"instance": instance_id})
		return
	if _batch.is_empty():
		var bytes := 0
		while not _outgoing.is_empty() and _batch.size() < 16:
			var packet: Dictionary = _outgoing[0]
			var packet_size := str(packet["data"]).length() + 150
			if bytes + packet_size > 480 * 1024:
				break
			bytes += packet_size
			_batch.append(_outgoing.pop_front())
	_request("exchange", {"generation": _generation, "after": _cursor, "packets": _batch})

func _request(action: String, data: Dictionary) -> void:
	_busy = true
	_request_started = Time.get_ticks_msec()
	_request_path = _path + "/" + action
	_request_body = JSON.stringify(data)
	_response_code = 0
	_response_length = -1
	_response_body = PackedByteArray()
	if _http.get_status() != HTTPClient.STATUS_CONNECTED:
		var tls := TLSOptions.client() if _origin.begins_with("https://") else null
		if _http.connect_to_host(_host, _port, tls) != OK:
			_http_error()
			return
	_poll_http()

func _poll_http() -> void:
	if Time.get_ticks_msec() - _request_started >= REQUEST_TIMEOUT_MS or _http.poll() != OK:
		_http_error()
		return
	var status := _http.get_status()
	if status == HTTPClient.STATUS_CONNECTED and not _request_path.is_empty():
		var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _token])
		if _http.request(HTTPClient.METHOD_POST, _request_path, headers, _request_body) != OK:
			_http_error()
			return
		_request_path = ""
		_request_body = ""
		return
	if _http.has_response() and _response_code == 0:
		_response_code = _http.get_response_code()
		_response_length = _http.get_response_body_length()
		_http.get_response_headers()
	if status == HTTPClient.STATUS_BODY:
		while _http.get_status() == HTTPClient.STATUS_BODY:
			var chunk := _http.read_response_body_chunk()
			if chunk.is_empty():
				break
			_response_body.append_array(chunk)
			if _response_body.size() > RESPONSE_LIMIT:
				_http_error()
				return
		status = _http.get_status()
	if _response_code != 0 and (status == HTTPClient.STATUS_CONNECTED or (
		status == HTTPClient.STATUS_DISCONNECTED and (_response_length < 0 or _response_body.size() == _response_length)
	)):
		_on_response(HTTPRequest.RESULT_SUCCESS, _response_code, _response_body)
	elif status not in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_BODY]:
		_http_error()

func _http_error() -> void:
	_http.close()
	_on_response(HTTPRequest.RESULT_CONNECTION_ERROR, 0, PackedByteArray())

func _on_response(result: int, response_code: int, body: PackedByteArray) -> void:
	_busy = false
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var now := Time.get_ticks_msec()
	_next_poll = now + POLL_INTERVAL_MS
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 500 or response_code == 429:
		_retry_after = now + 1800
		return
	_retry_after = 0
	var value: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not value is Dictionary:
		_fail("private_site" if response_code in [200, 301, 302, 401, 403] else "unavailable")
		return
	var data: Dictionary = value
	if response_code < 200 or response_code >= 300:
		if str(data.get("error", "")) == "generation_changed" and not _announced:
			# First join changes the generation before either RPC peer is visible.
			_generation = -1
			_batch.clear()
			_outgoing.clear()
			return
		_fail(str(data.get("error", "unavailable")))
		return
	_last_success = Time.get_ticks_msec()
	if _match_active:
		# Count the request itself toward the poll interval.
		_next_poll = _request_started + MATCH_POLL_INTERVAL_MS
	if _generation < 0:
		_generation = int(data.get("generation", -1))
		_cursor = int(data.get("cursor", 0))
		return
	_batch.clear()
	if bool(data.get("present", false)) and not _announced:
		_announced = true
		_status = MultiplayerPeer.CONNECTION_CONNECTED
		peer_connected.emit(3 - _id)
	for entry in data.get("packets", []):
		if not entry is Dictionary or int(entry.get("id", 0)) <= _cursor:
			continue
		_cursor = int(entry["id"])
		_incoming.append({"channel": int(entry["channel"]), "mode": int(entry["mode"]), "bytes": Marshalls.base64_to_raw(str(entry["data"]))})
	if not _outgoing.is_empty():
		for packet in _outgoing:
			_schedule_outgoing(int(packet["mode"]))

func _schedule_outgoing(mode: int) -> void:
	var delay := 0 if _match_active and mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE else 80
	_next_poll = mini(_next_poll, Time.get_ticks_msec() + delay)

func _fail(reason: String) -> void:
	failure_reason = reason
	# NetworkManager owns disconnect/reconnect signals and replacing this peer.
	var remote := 3 - _id
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	peer_disconnected.emit(remote)

func _close() -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_token = ""
	_http.close()
	_request_body = ""
	_response_body.clear()
	_incoming.clear()
	_outgoing.clear()
	_batch.clear()

func _disconnect_peer(_peer: int, _force: bool) -> void:
	_close()

func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front()["bytes"]

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > MAX_PACKET_BYTES:
		return ERR_OUT_OF_MEMORY
	if _target == _id or _target == -(3 - _id):
		return OK
	if _mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
		# Target arrows/heartbeats may update every frame; only the latest per
		# channel/mode is useful over a polling transport.
		for i in range(_outgoing.size() - 1, -1, -1):
			if _outgoing[i]["mode"] == _mode and _outgoing[i]["channel"] == _channel:
				_outgoing.remove_at(i)
				break
	if queued_packets() >= 512:
		return ERR_BUSY
	_sequence += 1
	_outgoing.append({"sequence": _sequence, "channel": _channel, "mode": _mode, "data": Marshalls.raw_to_base64(buffer)})
	_schedule_outgoing(_mode)
	return OK

func _get_available_packet_count() -> int:
	return _incoming.size()
func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status
func _get_max_packet_size() -> int:
	return MAX_PACKET_BYTES
func _get_packet_channel() -> int:
	return int(_incoming[0]["channel"]) if not _incoming.is_empty() else 0
func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return int(_incoming[0]["mode"]) as MultiplayerPeer.TransferMode if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE
func _get_packet_peer() -> int:
	return 3 - _id
func _get_transfer_channel() -> int:
	return _channel
func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode
func _get_unique_id() -> int:
	return _id
func _is_server() -> bool:
	return _id == 1
func _is_server_relay_supported() -> bool:
	return false
func _is_refusing_new_connections() -> bool:
	return _refuse
func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable
func _set_target_peer(target_peer: int) -> void:
	_target = target_peer
func _set_transfer_channel(channel: int) -> void:
	_channel = channel
func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode
