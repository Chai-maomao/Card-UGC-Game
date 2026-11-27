class_name NetworkProtocolGuard
extends RefCounted


static func valid_room_code(code: String) -> bool:
	if code.length() < 1 or code.length() > 16:
		return false
	for character in code:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "z") or (character >= "A" and character <= "Z")):
			return false
	return true


static func valid_address(address: String) -> bool:
	return not address.strip_edges().is_empty()


static func parse_host_address(value: String, default_port: int) -> Dictionary:
	var address := value.strip_edges()
	var port := default_port
	var separator := address.rfind("]:") + 1 if address.begins_with("[") and "]:" in address else -1
	if separator < 0 and address.count(":") == 1:
		separator = address.find(":")
	if separator > 0:
		var suffix := address.substr(separator + 1)
		port = int(suffix) if suffix.is_valid_int() else 0
		address = address.left(separator).trim_prefix("[").trim_suffix("]")
	elif address.begins_with("[") and address.ends_with("]"):
		address = address.trim_prefix("[").trim_suffix("]")
	return {"address": address, "port": port}


static func valid_remote_player_claim(local_player: int, claimed_player: int) -> bool:
	return local_player in [1, 2] and claimed_player == 3 - local_player
