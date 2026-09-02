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


static func valid_remote_player_claim(local_player: int, claimed_player: int) -> bool:
	return local_player in [1, 2] and claimed_player == 3 - local_player
