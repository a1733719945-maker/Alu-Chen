extends Node
## 联机层：通过中继服务器（server/server.js）和房间里的其他玩家收发消息。
##
## 所有玩家都连到同一台中继服务器，服务器负责把包转给对方。
## 房主（id = 1）的电脑负责算魂兽和金魂币；其他人只算自己的移动和射击。
## 单人模式下 mode = OFFLINE，自己就是房主，send() 什么都不做。

signal connected(room_code: String)
signal failed(reason: String)
signal disconnected(reason: String)
signal peer_joined(id: int, peer_name: String)
signal peer_left(id: int)
signal message(from: int, type: String, data: Variant)
signal status(text: String)

enum Mode { NONE, OFFLINE, ONLINE }

const WAKE_TIMEOUT := 100.0     # Render 免费服务器休眠后唤醒大约要 1 分钟
const CONNECT_TIMEOUT := 15.0
const KEEPALIVE := 8.0

var mode: Mode = Mode.NONE
var my_id := 1
var room_code := ""
var peers := {}                 # id -> {"name": String}

var _ws: WebSocketPeer
var _welcomed := false
var _pending := {}              # 正在连接的参数
var _connect_started := 0.0
var _keepalive_timer := 0.0
var _wake_started := 0.0
var _http: HTTPRequest
var _closing_reason := ""


func is_host() -> bool:
	return my_id == 1


func is_online() -> bool:
	return mode == Mode.ONLINE and _welcomed


func peer_name(id: int) -> String:
	if id == my_id:
		return Settings.display_name()
	if peers.has(id):
		return peers[id]["name"]
	return "魂师%d" % id


func start_offline() -> void:
	close()
	mode = Mode.OFFLINE
	my_id = 1
	room_code = ""
	peers.clear()
	connected.emit("")


## 创建房间。room 为空时服务器随机给一个 4 位房间码。
func host(url: String, player_name: String, room := "") -> void:
	_start(url, {"mode": "host", "name": player_name, "room": room})


func join(url: String, code: String, player_name: String) -> void:
	_start(url, {"mode": "join", "name": player_name, "room": code.strip_edges().to_upper()})


func close(reason := "") -> void:
	_pending.clear()
	if _http:
		_http.cancel_request()
	if _ws:
		_closing_reason = reason
		_ws.close()
		_ws = null
	_welcomed = false
	peers.clear()
	room_code = ""
	mode = Mode.NONE
	my_id = 1


## 发消息。target = 0 发给房间里除自己外的所有人，> 0 发给指定玩家。
func send(target: int, type: String, data: Variant = null) -> void:
	if not is_online() or target == my_id:
		return
	var body := var_to_bytes([type, data])
	var pkt := PackedByteArray()
	pkt.resize(4)
	pkt.encode_s32(0, target)
	pkt.append_array(body)
	_ws.send(pkt, WebSocketPeer.WRITE_MODE_BINARY)


## 发给房主。自己就是房主时直接在本地处理，这样房主和客人走同一套代码。
func send_host(type: String, data: Variant = null) -> void:
	if is_host():
		message.emit(my_id, type, data)
	else:
		send(1, type, data)


# ------------------------------------------------------------------ 内部

func _start(url: String, params: Dictionary) -> void:
	close()
	mode = Mode.ONLINE
	params["url"] = url.strip_edges().trim_suffix("/")
	_pending = params
	_wake_started = Time.get_ticks_msec() / 1000.0
	_wake()


func _health_url(url: String) -> String:
	var u := url
	if u.begins_with("wss://"):
		u = "https://" + u.substr(6)
	elif u.begins_with("ws://"):
		u = "http://" + u.substr(5)
	return u + "/health"


func _wake() -> void:
	if _pending.is_empty():
		return
	if not _http:
		_http = HTTPRequest.new()
		_http.timeout = 12.0
		add_child(_http)
		_http.request_completed.connect(_on_wake_done)
	var err := _http.request(_health_url(_pending["url"]))
	if err != OK:
		_fail("服务器地址不对：%s" % _pending["url"])


func _on_wake_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _pending.is_empty():
		return
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_connect_ws()
		return
	var waited := Time.get_ticks_msec() / 1000.0 - _wake_started
	if waited > WAKE_TIMEOUT:
		_fail("连不上服务器（等了 %d 秒）。检查网络，或者在设置里确认服务器地址。" % int(waited))
		return
	status.emit("正在唤醒服务器…免费服务器休眠后第一次连接要等 1 分钟左右（已等 %d 秒）" % int(waited))
	get_tree().create_timer(2.0).timeout.connect(_wake)


func _connect_ws() -> void:
	var p := _pending
	var q := "?mode=%s&v=%s&name=%s" % [p["mode"], Data.PROTOCOL_VERSION.uri_encode(), str(p["name"]).uri_encode()]
	if str(p["room"]) != "":
		q += "&room=" + str(p["room"]).uri_encode()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 21
	_ws.outbound_buffer_size = 1 << 21
	_ws.max_queued_packets = 8192
	var err := _ws.connect_to_url(str(p["url"]) + "/" + q)
	if err != OK:
		_fail("无法连接服务器（错误 %d）" % err)
		return
	_connect_started = Time.get_ticks_msec() / 1000.0
	status.emit("正在进入房间…")


func _fail(reason: String) -> void:
	close()
	failed.emit(reason)


func _process(delta: float) -> void:
	if not _ws:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _ws and _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			if _ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
			else:
				_on_binary(pkt)
		_keepalive_timer += delta
		if _ws and _keepalive_timer > KEEPALIVE:
			_keepalive_timer = 0.0
			_ws.send_text("p")
	elif state == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() / 1000.0 - _connect_started > CONNECT_TIMEOUT:
			_fail("连接超时")
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_in := _welcomed
		var reason := _closing_reason
		if reason == "":
			reason = "和服务器的连接断开了（%d）" % _ws.get_close_code()
		_ws = null
		if was_in:
			close()
			disconnected.emit(reason)
		elif not _pending.is_empty():
			_fail(reason)


func _on_text(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("t", "")):
		"welcome":
			my_id = int(msg["id"])
			room_code = str(msg["room"])
			peers.clear()
			for p in msg.get("peers", []):
				peers[int(p["id"])] = {"name": str(p["name"])}
			_welcomed = true
			_pending.clear()
			connected.emit(room_code)
			for id in peers:
				peer_joined.emit(id, peers[id]["name"])
		"join":
			var id := int(msg["id"])
			peers[id] = {"name": str(msg["name"])}
			peer_joined.emit(id, peers[id]["name"])
		"leave":
			var id := int(msg["id"])
			peers.erase(id)
			peer_left.emit(id)
		"closed":
			_closing_reason = str(msg.get("msg", "房间已解散"))
		"error":
			_closing_reason = str(msg.get("msg", "服务器拒绝连接"))


func _on_binary(pkt: PackedByteArray) -> void:
	if pkt.size() < 5:
		return
	var from := pkt.decode_s32(0)
	var v: Variant = bytes_to_var(pkt.slice(4))
	if typeof(v) != TYPE_ARRAY or v.size() != 2:
		return
	message.emit(from, str(v[0]), v[1])
