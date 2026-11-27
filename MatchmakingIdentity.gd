extends RefCounted

const PROFILE_PATH := "user://matchmaking_identity.pem"


static func load_or_create() -> CryptoKey:
	var key := CryptoKey.new()
	if FileAccess.file_exists(PROFILE_PATH):
		return key if key.load(PROFILE_PATH) == OK else null
	key = Crypto.new().generate_rsa(2048)
	return key if key != null and key.save(PROFILE_PATH) == OK else null


static func _digest(nonce: String, action: String, mode: String) -> PackedByteArray:
	return ("Cardex matchmaking v1\n%s\n%s\n%s" % [nonce, action, mode]).sha256_buffer()


static func prove(key: CryptoKey, nonce: String, action: String, mode: String) -> Dictionary:
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, _digest(nonce, action, mode), key)
	return {"public_key": key.save_to_string(true), "signature": Marshalls.raw_to_base64(signature)}


static func verify(proof: Dictionary, nonce: String, action: String, mode: String) -> String:
	var public_key := str(proof.get("public_key", ""))
	var signature := str(proof.get("signature", ""))
	if public_key.is_empty() or public_key.length() > 512 or signature.length() != 344:
		return ""
	var key := CryptoKey.new()
	if key.load_from_string(public_key, true) != OK:
		return ""
	if not Crypto.new().verify(HashingContext.HASH_SHA256, _digest(nonce, action, mode), Marshalls.base64_to_raw(signature), key):
		return ""
	return key.save_to_string(true).sha256_text()
