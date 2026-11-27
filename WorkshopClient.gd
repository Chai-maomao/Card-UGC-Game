class_name WorkshopClient
extends WorkshopBackend

const MAX_BYTES := 16 * 1024 * 1024
const DOWNLOAD_TIMEOUT_SECONDS := 10.0
static var token := ""
static var account_name := ""
static var token_origin := ""
var busy := false:
	set(value):
		if busy == value: return
		busy = value
		request_activity_changed.emit()
var origin := ""

func _ready() -> void:
	if FileAccess.file_exists("res://workshop_config.json"):
		var config = JSON.parse_string(FileAccess.get_file_as_string("res://workshop_config.json"))
		if config is Dictionary: origin = str(config.get("url", "")).trim_suffix("/")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--workshop-url="):
			origin = argument.trim_prefix("--workshop-url=").trim_suffix("/")
	if not origin.is_empty() and not origin.begins_with("https://") and not _local_url(origin):
		origin = ""

static func _local_url(url: String) -> bool:
	if not url.begins_with("http://"): return false
	var parts := url.trim_prefix("http://").split(":")
	return parts.size() == 2 and parts[0] in ["127.0.0.1","localhost"] and parts[1].is_valid_int() and int(parts[1]) > 0 and int(parts[1]) <= 65535

func request_api(path: String, method: int = HTTPClient.METHOD_GET, data: Dictionary = {}, timeout_seconds: float = 30.0) -> Dictionary:
	if origin.is_empty(): return {"ok":false,"error":"工坊暂时未开放"}
	if busy: return {"ok":false,"error":"正在处理，请稍候"}
	busy = true
	var request := HTTPRequest.new()
	# Threaded HTTPRequest uses blocking reads. Leaving the Workshop or timing
	# out would wait for that thread to finish before releasing the request.
	request.use_threads = false
	request.timeout = timeout_seconds
	request.body_size_limit = MAX_BYTES + 65536
	add_child(request)
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not token.is_empty() and token_origin == origin: headers.append("Authorization: Bearer " + token)
	var body := "" if method == HTTPClient.METHOD_GET else JSON.stringify(data)
	if body.to_utf8_buffer().size() > MAX_BYTES:
		request.queue_free()
		busy = false
		return {"ok":false,"error":"卡包不能超过 16 MB"}
	var err := request.request(origin + path, headers, method, body)
	if err != OK:
		request.queue_free()
		busy = false
		return {"ok":false,"error":"暂时无法连接工坊，请稍后再试"}
	var reply: Array = await request.request_completed
	request.queue_free()
	busy = false
	if reply[0] == HTTPRequest.RESULT_TIMEOUT:
		return {"ok":false,"error":"请求超时，请重试","timed_out":true}
	if reply[0] != HTTPRequest.RESULT_SUCCESS: return {"ok":false,"error":"连接中断，请重试"}
	var parsed = JSON.parse_string(reply[3].get_string_from_utf8())
	if not parsed is Dictionary: return {"ok":false,"error":"服务暂时不可用，请稍后再试"}
	parsed["ok"] = int(reply[1]) >= 200 and int(reply[1]) < 300
	parsed["status_code"] = reply[1]
	if int(reply[1]) == 401 and token_origin == origin:
		_save_session(false)
		token = ""
		account_name = ""
		token_origin = ""
	return parsed

func sign_in(name_text: String, password: String, register: bool = false, invite: String = "", remember: bool = false) -> Dictionary:
	var result := await request_api("/v1/register" if register else "/v1/login", HTTPClient.METHOD_POST, {"name":name_text,"password":password,"invite":invite})
	if result.get("ok",false):
		token = str(result.get("token",""))
		token_origin = origin
		account_name = str(result.get("user",{}).get("name",""))
		_save_session(remember)
	return result

static func package_for_upload(deck: Dictionary) -> Dictionary:
	var package = JSON.parse_string(PlayerData.serialize_deck_for_share(deck))
	if not package is Dictionary: return {}
	_strip_private_fields(package)
	return package

static func _strip_private_fields(value: Variant) -> void:
	if value is Dictionary:
		for key in ["art_path","damaged_art_path"]:
			if value.has(key): value[key] = ""
		value.erase("_workspace")
		for child in value.values(): _strip_private_fields(child)
	elif value is Array:
		for child in value: _strip_private_fields(child)


func authenticated() -> bool: return not token.is_empty() and token_origin == origin
func display_name() -> String: return account_name if authenticated() else ""
func ready_for_use() -> bool: return not origin.is_empty()
func is_request_active() -> bool: return busy

func browse(query: String, sort: String, offset: int, mine: bool) -> Dictionary:
	return await request_api("/v1/packages?q="+query.uri_encode()+"&offset="+str(offset)+"&sort="+sort+("&mine=1" if mine else ""))

func publish(title: String, description: String, package: Dictionary, cover: String = "") -> Dictionary:
	return await request_api("/v1/packages",HTTPClient.METHOD_POST,{"title":title,"description":description,"package":package,"cover":cover},120.0)

func download(id: String) -> Dictionary:
	var result := await request_api("/v1/packages/"+id+"/download", HTTPClient.METHOD_GET, {}, DOWNLOAD_TIMEOUT_SECONDS)
	if result.get("timed_out", false):
		result["error"] = "下载超时，请重试"
	return result

func withdraw(id: String) -> Dictionary:
	return await request_api("/v1/packages/"+id,HTTPClient.METHOD_DELETE)

func report(id: String, reason: String) -> Dictionary:
	return await request_api("/v1/packages/"+id+"/report",HTTPClient.METHOD_POST,{"reason":reason})

func sign_out() -> Dictionary:
	_save_session(false)
	var result := await request_api("/v1/logout",HTTPClient.METHOD_POST)
	token = ""
	account_name = ""
	token_origin = ""
	return result

static func cover_for_deck(deck: Dictionary) -> String:
	var cards: Array = deck.get("cards",[])
	if cards.is_empty() or not cards[0] is CardData: return ""
	var texture := CardArtwork.texture_for(cards[0])
	if texture == null: return ""
	var image := texture.get_image()
	if image == null or image.is_empty(): return ""
	if image.is_compressed(): image.decompress()
	var ratio := minf(1.0,384.0/maxi(image.get_width(),image.get_height()))
	image.resize(maxi(1,roundi(image.get_width()*ratio)),maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	var bytes := image.save_jpg_to_buffer(0.75)
	if bytes.size() > 65536: bytes = image.save_jpg_to_buffer(0.5)
	if bytes.size() > 65536:
		image.resize(maxi(1,image.get_width()/2),maxi(1,image.get_height()/2),Image.INTERPOLATE_LANCZOS)
		bytes = image.save_jpg_to_buffer(0.65)
	return Marshalls.raw_to_base64(bytes) if bytes.size() <= 65536 else ""


func _save_session(remember: bool) -> void:
	var path := "user://workshop_session.cfg"
	if not remember:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var config := ConfigFile.new()
	config.set_value("session","origin",origin)
	config.set_value("session","token",token)
	config.set_value("session","name",account_name)
	config.save(path)

func restore_session() -> Dictionary:
	if authenticated(): return {"ok":true}
	var config := ConfigFile.new()
	if config.load("user://workshop_session.cfg") != OK: return {"ok":true}
	if str(config.get_value("session","origin","")) != origin: return {"ok":true}
	token = str(config.get_value("session","token",""))
	token_origin = origin
	account_name = str(config.get_value("session","name",""))
	if token.is_empty(): return {"ok":true}
	return await request_api("/v1/me")
