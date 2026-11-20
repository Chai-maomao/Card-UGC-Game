class_name WorkshopBackend
extends Node

# Shared contract for the hosted workshop and a future Steam UGC adapter.
# UI/import code deals with packages; authentication and transport belong here.
func authenticated() -> bool: return false
func display_name() -> String: return ""
func password_login() -> bool: return true
func ready_for_use() -> bool: return false
func browse(_query: String, _sort: String, _offset: int, _mine: bool) -> Dictionary: return _unavailable()
func publish(_title: String, _description: String, _package: Dictionary, _cover: String = "") -> Dictionary: return _unavailable()
func download(_id: String) -> Dictionary: return _unavailable()
func withdraw(_id: String) -> Dictionary: return _unavailable()
func report(_id: String, _reason: String) -> Dictionary: return _unavailable()
func sign_in(_name: String, _password: String, _register: bool = false, _invite: String = "", _remember: bool = false) -> Dictionary: return _unavailable()
func sign_out() -> Dictionary: return _unavailable()
func _unavailable() -> Dictionary: return {"ok":false,"error":"工坊暂时不可用"}

func restore_session() -> Dictionary: return {"ok":true}

func open_account() -> void: pass
