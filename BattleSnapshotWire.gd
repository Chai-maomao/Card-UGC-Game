extends RefCounted

const COMPRESSED_KEY := "_zstd_snapshot"
const MIN_RAW_BYTES := 1024
# This bounds decompression from a room peer. Large snapshots can still use
# the plain dictionary path and its existing validation rules.
const MAX_PACKED_RAW_BYTES := 4 * 1024 * 1024


static func encode(state: Dictionary) -> Dictionary:
	var raw := var_to_bytes(state)
	if raw.size() < MIN_RAW_BYTES or raw.size() > MAX_PACKED_RAW_BYTES:
		return state
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty() or compressed.size() + 96 >= raw.size():
		return state
	return {COMPRESSED_KEY: compressed, "raw_bytes": raw.size()}


static func decode(payload: Dictionary) -> Dictionary:
	if not payload.has(COMPRESSED_KEY):
		return payload
	var bytes: Variant = payload[COMPRESSED_KEY]
	var size: Variant = payload.get("raw_bytes")
	if not bytes is PackedByteArray or not size is int or size < MIN_RAW_BYTES or size > MAX_PACKED_RAW_BYTES:
		return {}
	if bytes.is_empty() or bytes.size() >= size:
		return {}
	var raw: PackedByteArray = bytes.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return {}
	var state: Variant = bytes_to_var(raw)
	return state if state is Dictionary else {}
