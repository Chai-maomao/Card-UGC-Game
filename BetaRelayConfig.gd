class_name BetaRelayConfig
extends RefCounted

const DEFAULT_URL := "https://cardex-online-beta.ycn3258823137.chatgpt.site"
const PROTOCOL := 1

static func server_url() -> String:
	# Debug-only loopback override is used by two-process integration tests.
	var override := OS.get_environment("CARDEX_BETA_TEST_URL")
	if OS.is_debug_build() and (override.begins_with("http://127.0.0.1:") or override.begins_with("http://localhost:")):
		return override.trim_suffix("/")
	return DEFAULT_URL

static func valid_code(code: String) -> bool:
	if code.length() != 8:
		return false
	for character in code:
		if character not in "0123456789ABCDEF":
			return false
	return true

static func error_text(error: String) -> String:
	var key := error if error in ["room_full", "room_expired", "capacity_reached", "unauthorized", "protocol_mismatch", "private_site"] else "unavailable"
	return Locale.t("beta.error_" + key)
