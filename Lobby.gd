extends "res://BetaLobby.gd"

func _relay_url() -> String:
	return CloudRelayConfig.server_url()

func _relay_error(error: String) -> String:
	return CloudRelayConfig.error_text(error)

func _connect_relay_room(address: String, code: String, token: String, player: int) -> bool:
	NetworkManager.connect_cloud_room(address, code, token, player)
	return NetworkManager.has_saved_cloud_session()

func _apply_texts() -> void:
	super._apply_texts()
	title_label.text = Locale.t("cloud.title")
	host_btn.text = Locale.t("cloud.create")
	join_btn.text = Locale.t("cloud.join")
	status_label.text = "" if not _relay_url().is_empty() else _relay_error("not_configured")
