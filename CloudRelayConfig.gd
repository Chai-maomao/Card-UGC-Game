class_name CloudRelayConfig
extends RefCounted

const SETTINGS_PATH := "res://res/network/cloudflare.json"
const RETIRED_ENET_ADDRESS := "121.199.57.218"

static func server_url() -> String:
	var override := OS.get_environment("CARDEX_CLOUDFLARE_TEST_URL")
	if OS.is_debug_build() and (override.begins_with("http://127.0.0.1:") or override.begins_with("http://localhost:")):
		return override.trim_suffix("/")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not data is Dictionary or int(data.get("schema", 0)) != 1:
		return ""
	var url := str(data.get("url", "")).trim_suffix("/")
	return url if valid_origin(url) else ""

static func valid_origin(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var host := url.trim_prefix("https://")
	if host.is_empty() or host.find(".") < 1:
		return false
	for character in host:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789.-":
			return false
	return true

static func accepts_saved_url(url: String) -> bool:
	var current := server_url()
	return not current.is_empty() and url == current

static func error_text(error: String) -> String:
	if error in ["not_configured", "unavailable", "capacity_reached", "protocol_mismatch", "private_site"]:
		return Locale.t("cloud.error_" + error)
	return BetaRelayConfig.error_text(error)
