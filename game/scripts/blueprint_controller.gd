extends Node
## Player-side blueprint controller (docs/blueprint-client-contract.md).
##
## Owns the personal library CRUD (via blueprint_library.gd), the staged capture
## (never auto-saved), the placement draft / authoritative quote correlation and
## the durable pending-submission record (via blueprint_pending.gd).
## Main owns this node as `blueprints`; UI/preview read the public fields only.
##
## Safety rules implemented here:
## - The local Design.base_cost is never treated as a price: confirm() only
##   accepts the current authoritative ok quote (request ID + generation +
##   region/epoch correlated) for the locked origin and rotation.
## - The pending record is written atomically BEFORE submit; a write failure
##   means nothing is sent. Its nonce/intent is fixed and retries reuse it.
## - A pending record is only cleared on a decidable authoritative outcome
##   (success receipt, explicit requote, World rejection carrying a quote,
##   server stale_context). The file is deleted first; if deletion fails the
##   record stays and blocks new construction. rate_limited / paused /
##   not_sent / timeout / disconnect keep it as "unknown".
## - Nothing is ever resubmitted automatically; retry is a player action.
## - Results are classified by flags only, never by parsing Chinese messages.

const World = preload("res://scripts/world.gd")
const Design = preload("res://scripts/blueprint_design.gd")
const Library = preload("res://scripts/blueprint_library.gd")
const Pending = preload("res://scripts/blueprint_pending.gd")
const Protocol = preload("res://scripts/blueprint_protocol.gd")

signal changed
signal feedback(message: String, ok: bool)
signal applied(result: Dictionary)

const QUOTE_TIMEOUT_MS := 8000
const SUBMIT_TIMEOUT_MS := 15000
const MAX_ENTRIES := Library.MAX_ENTRIES

## idle / capture / placing / submitting / unknown
var mode: String = "idle"
## Normalized library entries [{id, design}] (deep copies; replaced only after a successful save).
var entries: Array = []
## Staged capture awaiting save_capture(); never written automatically.
var captured: Dictionary = {}
var auto_roofs_omitted: int = 0
## Normalized UNROTATED design being placed.
var draft: Dictionary = {}
## Top-left of the rotated bounding box, in world cells.
var origin: Vector2i = Vector2i.ZERO
var turns: int = 0
var locked: bool = false
## Latest sanitized authoritative quote for the current draft/origin/turns/context, or {}.
var quote: Dictionary = {}
var quote_waiting: bool = false
## Player-facing Chinese status line.
var status: String = ""
## Non-empty when the personal library failed to load; all library writes are refused.
var library_error: String = ""
## Durable pending record (see blueprint_pending.gd) or {}.
var pending: Dictionary = {}
## Non-empty when a pending record is corrupt / cannot be cleared; blocks new construction.
var pending_error: String = ""

## Extra (not in contract): optional deterministic clock for tests (returns msec).
var clock: Callable

var _session = null
var _library_path: String = ""
var _scope: String = ""
var _configured: bool = false
var _generation: int = 0
var _quote_request: int = 0
var _quote_generation: int = -1
var _quote_context: Dictionary = {}
var _quote_sent_ms: int = 0
var _quote_for_generation: int = -2
var _submit_ms: int = 0
var _context: Dictionary = {}

# ------------------------------------------------------------------ lifecycle

## Loads the personal library, binds Session signals once and loads any pending
## record for `scope`. Never submits anything. A different scope keeps the
## older scope's pending file on disk untouched.
func setup(session: Node, library_path: String, scope: String) -> void:
	if _session != null and _session != session:
		_unbind()
	_session = session
	_bind()
	var reload := not _configured or library_path != _library_path or scope != _scope
	_library_path = library_path
	_scope = scope
	_configured = true
	if reload:
		# Older scope's pending file stays on disk; only memory is reset.
		_reset_transient()
		mode = "idle"
		status = ""
		captured = {}
		auto_roofs_omitted = 0
		pending = {}
		pending_error = ""
		_load_library()
	else:
		_drop_unsent_modes()
	_context = _own_context()
	_load_pending()
	changed.emit()

## Unbinds Session signals and drops in-flight trackers. Never deletes the
## pending record; an in-flight submission becomes "unknown".
func dispose() -> void:
	_unbind()
	_session = null
	quote_waiting = false
	_quote_request = 0
	if mode == "submitting":
		mode = "unknown"
	elif mode == "capture" or mode == "placing":
		_reset_transient()

func _exit_tree() -> void:
	dispose()

func _bind() -> void:
	if _session == null or not is_instance_valid(_session):
		return
	var pairs := [["changed", _on_session_changed], ["disconnected_world", _on_disconnected],
		["blueprint_quoted", _on_quoted], ["blueprint_applied", _on_applied]]
	for pair in pairs:
		if _session.has_signal(pair[0]) and not _session.is_connected(pair[0], pair[1]):
			_session.connect(pair[0], pair[1])

func _unbind() -> void:
	if _session == null or not is_instance_valid(_session):
		return
	var pairs := [["changed", _on_session_changed], ["disconnected_world", _on_disconnected],
		["blueprint_quoted", _on_quoted], ["blueprint_applied", _on_applied]]
	for pair in pairs:
		if _session.has_signal(pair[0]) and _session.is_connected(pair[0], pair[1]):
			_session.disconnect(pair[0], pair[1])

func _process(_delta: float) -> void:
	var now := _now()
	if quote_waiting and now - _quote_sent_ms >= QUOTE_TIMEOUT_MS:
		# The request ID stays current so a late but still-correlated reply is accepted.
		quote_waiting = false
		status = "報價逾時，沒有收到世界回覆。可再按「報價」重試。"
		feedback.emit(status, false)
		changed.emit()
	if mode == "submitting" and now - _submit_ms >= SUBMIT_TIMEOUT_MS:
		mode = "unknown"
		status = "施工結果逾時未確認。記錄已保留，可按「重試確認」以同一施工編號查詢，不會重複扣料。"
		feedback.emit(status, false)
		changed.emit()

# ------------------------------------------------------------------ helpers (extra, read-only)

## Extra: true when a new construction must be refused (submitting/unknown, a
## pending record, or a pending record that could not be read/cleared).
func busy() -> bool:
	return mode == "submitting" or mode == "unknown" or not pending.is_empty() or not pending_error.is_empty()

## Extra: absolute pending file path for the current library/scope ("" if invalid).
func pending_path() -> String:
	return Pending.path_for(_library_path, _scope)

# ------------------------------------------------------------------ library

func capture_span() -> int:
	if not is_instance_valid(_session):return 8
	var snapshot:Dictionary=_session.get("snapshot")
	var person:Dictionary=snapshot.get("players",{}).get(_own_id(),{})
	return Design.SIZE_MAX if World.crafting_level(person)>=3 else 8

func begin_capture() -> bool:
	if busy():
		_refuse(_busy_reason())
		return false
	_reset_transient()
	mode = "capture"
	var span:=capture_span()
	status = "拖曳框選自己的建物（最大 %d×%d 格），放開後命名保存。Esc 取消。" % [span,span]
	changed.emit()
	return true

## Staged only: success fills `captured`/`auto_roofs_omitted` and returns to idle.
func capture_area(area: Rect2i, name: String) -> Dictionary:
	if busy():
		return _result(false, _busy_reason())
	if mode != "capture":
		return _result(false, "請先按「框選新藍圖」再拖曳範圍。")
	if not _session_ready():
		return _result(false, "尚未連上世界，無法框選。")
	var own := _own_id()
	var snap = _session.get("snapshot")
	if own.is_empty() or not snap is Dictionary:
		return _result(false, "尚未取得世界資料，無法框選。")
	var span:=capture_span()
	if area.size.x>span or area.size.y>span:
		var reason:="目前最多框選 %d×%d 格。手作三級可保存 16×16 格藍圖。" % [span,span]
		status=reason
		feedback.emit(status,false)
		changed.emit()
		return _result(false,reason)
	var got: Dictionary = Design.capture(snap, own, area, name, World.BUILD, World.NAMES)
	if got.get("ok") != true:
		status = "框選失敗：" + str(got.get("reason", ""))
		feedback.emit(status, false)
		changed.emit()
		return _result(false, str(got.get("reason", "")))
	captured = (got.blueprint as Dictionary).duplicate(true)
	auto_roofs_omitted = int(got.get("auto_roofs_omitted", 0))
	mode = "idle"
	var pieces: int = (captured.pieces as Array).size()
	status = "已框選 %d×%d 格、%d 件建物" % [int(captured.width), int(captured.height), pieces]
	if auto_roofs_omitted > 0:
		status += "（略過 %d 格自動屋頂，套用時依房間重新計價）" % auto_roofs_omitted
	status += "。請命名並保存，尚未寫入藍圖冊。"
	changed.emit()
	var out := _result(true, "")
	out.pieces = pieces
	out.auto_roofs_omitted = auto_roofs_omitted
	return out

func save_capture(name: String) -> Dictionary:
	if captured.is_empty():
		return _library_fail("沒有待保存的框選，請先框選範圍。")
	var guard := _library_guard()
	if not guard.is_empty():
		return _library_fail(guard)
	if entries.size() >= MAX_ENTRIES:
		return _library_fail("藍圖冊最多 %d 份，請先刪除不需要的藍圖。" % MAX_ENTRIES)
	var design := captured.duplicate(true)
	design.name = name
	var checked: Dictionary = Design.validate(design, World.BUILD, World.NAMES)
	if checked.get("ok") != true:
		return _library_fail("未保存：" + str(checked.get("reason", "")))
	var id := _new_id()
	var next: Array = entries.duplicate(true)
	next.append({"id": id, "design": checked.blueprint})
	var saved := _write_library(next)
	if not saved.ok:
		return saved
	captured = {}
	auto_roofs_omitted = 0
	status = "已保存藍圖「%s」。" % str(checked.blueprint.name)
	feedback.emit(status, true)
	changed.emit()
	saved.id = id
	return saved

func rename_entry(id: String, name: String) -> Dictionary:
	var guard := _library_guard()
	if not guard.is_empty():
		return _library_fail(guard)
	var index := _entry_index(id)
	if index < 0:
		return _library_fail("找不到這份藍圖。")
	var design: Dictionary = (entries[index].design as Dictionary).duplicate(true)
	design.name = name
	var checked: Dictionary = Design.validate(design, World.BUILD, World.NAMES)
	if checked.get("ok") != true:
		return _library_fail("未重新命名：" + str(checked.get("reason", "")))
	var next: Array = entries.duplicate(true)
	next[index] = {"id": id, "design": checked.blueprint}
	var saved := _write_library(next)
	if not saved.ok:
		return saved
	status = "已重新命名為「%s」。" % str(checked.blueprint.name)
	feedback.emit(status, true)
	changed.emit()
	saved.id = id
	return saved

## The UI must have obtained an explicit second confirmation before calling.
func delete_entry(id: String) -> Dictionary:
	var guard := _library_guard()
	if not guard.is_empty():
		return _library_fail(guard)
	var index := _entry_index(id)
	if index < 0:
		return _library_fail("找不到這份藍圖。")
	var label := str(entries[index].design.name)
	var next: Array = entries.duplicate(true)
	next.remove_at(index)
	var saved := _write_library(next)
	if not saved.ok:
		return saved
	status = "已刪除藍圖「%s」。" % label
	feedback.emit(status, true)
	changed.emit()
	saved.id = id
	return saved

# ------------------------------------------------------------------ placement

func choose(id: String) -> bool:
	if busy():
		_refuse(_busy_reason())
		return false
	var index := _entry_index(id)
	if index < 0:
		_refuse("找不到這份藍圖。")
		return false
	var checked: Dictionary = Design.validate(entries[index].design, World.BUILD, World.NAMES)
	if checked.get("ok") != true:
		_refuse("這份藍圖無法使用：" + str(checked.get("reason", "")))
		return false
	var cell = _player_cell()
	if cell == null:
		_refuse("尚未取得目前位置，無法放置藍圖。")
		return false
	_reset_transient()
	draft = (checked.blueprint as Dictionary).duplicate(true)
	turns = 0
	origin = _clamp_cell(cell + Vector2i(1, 0))
	locked = false
	mode = "placing"
	_context = _own_context()
	status = "放置「%s」：移動選擇位置，點地面鎖定落點並報價；R旋轉，Esc取消。" % str(draft.name)
	changed.emit()
	return true

func move_origin(cell: Vector2i) -> bool:
	if mode != "placing" or locked:
		return false
	var target := _clamp_cell(cell)
	if target == origin:
		return false
	origin = target
	_invalidate_quote()
	changed.emit()
	return true

func pin_origin(cell: Vector2i) -> bool:
	if mode != "placing" or locked:
		return false
	origin = _clamp_cell(cell)
	locked = true
	_invalidate_quote()
	status = "落點已鎖定，正在報價。"
	request_quote()
	changed.emit()
	return true

func reposition() -> bool:
	if mode != "placing" or not locked:
		return false
	locked = false
	_invalidate_quote()
	status = "請重新選擇落點，點地面鎖定並報價。"
	changed.emit()
	return true

## Clockwise quarter turn. Require an explicit new quote after changing intent.
func rotate() -> bool:
	if mode != "placing":
		return false
	turns = (turns + 1) % 4
	_invalidate_quote()
	status = "已旋轉 %d°，請重新報價。" % (turns * 90)
	changed.emit()
	return true

## Returns the request ID, or 0 when nothing was sent.
func request_quote() -> int:
	if mode != "placing" or draft.is_empty():
		return 0
	if quote_waiting and _quote_request != 0 and _quote_generation == _generation:
		return _quote_request
	if not _session_ready() or not _session.has_method("quote_blueprint"):
		status = "尚未連上世界，無法報價。"
		changed.emit()
		return 0
	var ctx := _own_context()
	if ctx.is_empty():
		status = "尚未取得目前位置，無法報價。"
		changed.emit()
		return 0
	quote = {}
	_quote_for_generation = -2
	_quote_generation = _generation
	_quote_context = ctx
	_quote_sent_ms = _now()
	quote_waiting = true
	var id = _session.quote_blueprint(draft.duplicate(true), origin, turns)
	_quote_request = int(id) if typeof(id) == TYPE_INT else 0
	if _quote_request == 0:
		quote_waiting = false
		status = "報價沒有送出，請再試一次。"
	else:
		status = "正在向世界報價…"
	changed.emit()
	return _quote_request

func confirm() -> bool:
	if busy():
		_refuse(_busy_reason())
		return false
	if mode != "placing" or not locked:
		_refuse("請先鎖定落點並取得報價。")
		return false
	if quote_waiting:
		_refuse("報價尚未回覆，請稍候。")
		return false
	if quote.get("ok") != true or not Protocol.valid_hash(quote.get("hash")) or _quote_for_generation != _generation:
		_refuse("目前沒有可施工的有效報價，請重新報價。")
		return false
	if not _session_ready() or not _session.has_method("submit_blueprint"):
		_refuse("尚未連上世界，沒有送出施工。")
		return false
	var ctx := _own_context()
	if ctx.is_empty() or ctx != _quote_context:
		_invalidate_quote()
		_refuse("位置或區域已變動，請重新報價。")
		changed.emit()
		return false
	var actor := _own_id()
	if not Pending.lower_hex(actor, Pending.ACTOR_LENGTH):
		_refuse("無法確認島民身分，沒有送出施工。")
		return false
	var path := pending_path()
	if path.is_empty():
		_refuse("無法識別目前世界，沒有送出施工。")
		return false
	var made: Dictionary = Pending.make(_scope, actor, _new_id(), draft, origin, turns, str(quote.hash),
		str(ctx.region), int(ctx.epoch), World.BUILD, World.NAMES)
	if made.get("ok") != true:
		_refuse("無法建立待確認施工記錄，沒有送出施工：" + str(made.get("reason", "")))
		return false
	var problem: String = Pending.save_pending(path, made.record, World.BUILD, World.NAMES)
	if not problem.is_empty():
		_refuse(problem)
		return false
	pending = (made.record as Dictionary).duplicate(true)
	pending_error = ""
	mode = "submitting"
	_submit_ms = _now()
	status = "已送出施工，等待世界確認…期間不能開始另一筆施工。"
	changed.emit()
	_send_pending()
	return true

## Player-initiated resend of the SAME nonce/intent/context/hash.
func retry_pending() -> bool:
	if pending.is_empty():
		_refuse("沒有待確認的施工。" if pending_error.is_empty() else pending_error)
		return false
	if mode != "unknown":
		_refuse("施工結果仍在等待中，請稍候。")
		return false
	if str(pending.get("scope")) != _scope:
		_refuse("這筆記錄屬於其他世界，不會送到目前的世界。")
		return false
	if not _session_ready() or not _session.has_method("submit_blueprint"):
		_refuse("尚未連上世界，請連上同一世界後再重試。")
		return false
	var own := _own_id()
	if own.is_empty():
		_refuse("尚未取得島民身分，請稍候再重試。")
		return false
	if own != str(pending.get("actor")):
		_refuse("這筆記錄屬於其他島民身分，不會送出。")
		return false
	mode = "submitting"
	_submit_ms = _now()
	status = "正在以同一施工編號查詢結果…不會重複扣料。"
	changed.emit()
	_send_pending()
	return true

## Cancels capture/placing only. A submitted construction cannot be withdrawn.
func cancel() -> bool:
	if mode == "submitting" or mode == "unknown":
		_refuse("已送出的施工無法取消，只能等待或重試確認結果；記錄會保留。")
		return false
	if mode != "capture" and mode != "placing":
		return false
	_reset_transient()
	status = "已取消藍圖操作。"
	changed.emit()
	return true

# ------------------------------------------------------------------ session signals

func _on_session_changed(_snapshot: Dictionary, _own: String) -> void:
	var ctx := _own_context()
	if ctx.is_empty():
		return
	var dirty := false
	if not _context.is_empty() and ctx != _context and (mode == "capture" or mode == "placing"):
		_reset_transient()
		status = "已換區域或旅程，未送出的藍圖預覽與報價已取消。"
		dirty = true
	_context = ctx
	if not pending.is_empty() and mode != "submitting" and mode != "unknown":
		mode = "unknown"
		dirty = true
	if dirty:
		changed.emit()

func _on_disconnected() -> void:
	quote_waiting = false
	_quote_request = 0
	_context = {}
	if mode == "submitting":
		mode = "unknown"
		status = "連線中斷，施工結果未確認。記錄已保留，重新連上同一世界後可按「重試確認」。"
		feedback.emit(status, false)
	elif mode == "capture" or mode == "placing":
		_reset_transient()
		status = "連線中斷，已取消未送出的藍圖操作。"
	changed.emit()

func _on_quoted(request_id: int, result: Dictionary) -> void:
	if _quote_request == 0 or request_id != _quote_request:
		return
	if mode != "placing" or _quote_generation != _generation:
		return
	_quote_request = 0
	quote_waiting = false
	if _own_context() != _quote_context:
		quote = {}
		status = "位置或區域已變動，舊報價已作廢，請重新報價。"
		changed.emit()
		return
	quote = Protocol.sanitize(result, World.NAMES)
	quote.erase("quote")
	_quote_for_generation = _generation
	if quote.ok == true and Protocol.valid_hash(quote.get("hash")):
		status = "報價完成：確認後才會施工並扣除材料。"
		if quote.get("undoable") != true:
			status += "此次施工無法用撤銷復原。"
	else:
		quote.ok = false
		var why := str(quote.get("message", ""))
		if quote.get("rate_limited") == true:
			status = "報價太頻繁，請稍候再按「報價」。"
		elif quote.get("not_sent") == true:
			status = ("報價沒有送出：" + why if not why.is_empty() else "報價沒有送出。") + "可再按「報價」重試。"
		elif quote.get("stale_context") == true:
			status = "位置或區域已變動，請重新報價。"
		else:
			status = "目前無法施工：" + (why if not why.is_empty() else "請查看問題格。")
	changed.emit()

func _on_applied(nonce: String, result: Dictionary) -> void:
	if pending.is_empty() or nonce != str(pending.get("nonce")):
		return
	var r := Protocol.sanitize(result, World.NAMES)
	var why := str(r.get("message", ""))
	if r.ok == true:
		if not _clear_pending_file():
			status = "世界已完成施工，但無法清除本機待確認記錄；記錄已保留並暫停新施工。按「重試確認」只會查詢同一筆收據，不會再扣料。"
			feedback.emit(status, false)
			changed.emit()
			return
		pending = {}
		pending_error = ""
		_reset_transient()
		mode = "idle"
		status = "施工完成" + ("：" + why if not why.is_empty() else "。")
		changed.emit()
		feedback.emit(status, true)
		applied.emit(r)
		return
	var requote: bool = r.get("requote") == true
	var rejected: bool = r.get("quote") is Dictionary
	var stale: bool = r.get("stale_context") == true and r.get("not_sent") != true
	if requote or rejected or stale:
		# Decidable: the server found no receipt for this nonce and did not build.
		if not _clear_pending_file():
			status = "這筆施工未執行，但無法清除本機待確認記錄；記錄已保留並暫停新施工。"
			feedback.emit(status, false)
			changed.emit()
			return
		var record := pending
		pending = {}
		pending_error = ""
		_reset_transient()
		draft = (record.design as Dictionary).duplicate(true)
		turns = int(record.turns)
		origin = Vector2i(int(record.origin.x), int(record.origin.y))
		mode = "placing"
		var ctx := _own_context()
		_context = ctx
		var same_context: bool = not ctx.is_empty() and str(ctx.region) == str(record.region) and int(ctx.epoch) == int(record.epoch)
		if (requote or rejected) and same_context and r.quote is Dictionary:
			locked = true
			quote = (r.quote as Dictionary).duplicate(true)
			quote.requote = requote
			if quote.get("ok") != true or not Protocol.valid_hash(quote.get("hash")):
				quote.ok = false
			_quote_for_generation = _generation
			_quote_context = ctx
			if requote:
				status = "現場或價格已變動，這次沒有施工。請檢查新報價，再按「確認」才會施工。"
			else:
				status = "這次沒有施工：" + (why if not why.is_empty() else "請查看問題格。")
		else:
			locked = false
			status = "位置或區域已變動，這次沒有施工；請重新選擇落點並報價。"
		feedback.emit(status, false)
		changed.emit()
		return
	# Undecidable (rate_limited, paused, not_sent, save failure, other): keep.
	mode = "unknown"
	if r.get("rate_limited") == true:
		status = "世界暫時忙碌，施工結果尚未確認。記錄已保留，請稍候按「重試確認」。"
	else:
		status = "施工結果尚未確認" + ("（" + why + "）" if not why.is_empty() else "") + "。記錄已保留，可按「重試確認」以同一施工編號查詢，不會重複扣料。"
	feedback.emit(status, false)
	changed.emit()

# ------------------------------------------------------------------ internals

func _send_pending() -> void:
	var o: Dictionary = pending.origin
	_session.submit_blueprint(str(pending.nonce), (pending.design as Dictionary).duplicate(true),
		Vector2i(int(o.x), int(o.y)), int(pending.turns), str(pending.hash), str(pending.region), int(pending.epoch))

## Deletes the pending file; on failure keeps `pending`, sets pending_error and mode unknown.
func _clear_pending_file() -> bool:
	# A second client or external recovery may have replaced this path while
	# the reply was in flight. Never erase a corrupt or different intent.
	var stored := Pending.load_pending(pending_path(), _scope, World.BUILD, World.NAMES)
	if stored.get("ok") != true or (stored.get("missing") != true and stored.get("record") != pending):
		pending_error = "待確認施工記錄已變動或無法讀取，已保留原檔；請先確認記錄。"
		mode = "unknown"
		return false
	var problem: String = Pending.remove_pending(pending_path())
	if problem.is_empty():
		return true
	pending_error = problem
	mode = "unknown"
	return false

func _load_pending() -> void:
	var path := pending_path()
	if path.is_empty():
		pending = {}
		pending_error = "無法識別目前世界，藍圖施工已停用。"
		status = pending_error
		return
	var loaded: Dictionary = Pending.load_pending(path, _scope, World.BUILD, World.NAMES)
	if loaded.get("ok") != true:
		pending = {}
		pending_error = str(loaded.get("reason", "")) + "請保留此檔案；在處理前不會開始新的藍圖施工。"
		_drop_unsent_modes()
		status = pending_error
		return
	if loaded.get("missing") == true:
		# Keep an in-memory record of this same scope rather than forget it.
		if not pending.is_empty():
			mode = "unknown" if mode != "submitting" else mode
		else:
			pending_error = ""
			status = ""
		return
	pending = (loaded.record as Dictionary).duplicate(true)
	pending_error = ""
	if mode != "submitting":
		_drop_unsent_modes()
		mode = "unknown"
	status = "上次送出的藍圖施工結果尚未確認。連上同一世界後請按「重試確認」；系統不會自動重送。"

func _load_library() -> void:
	var loaded: Dictionary = Library.load_library(_library_path, World.BUILD, World.NAMES)
	if loaded.get("ok") == true:
		entries = (loaded.entries as Array).duplicate(true)
		library_error = ""
	else:
		entries = []
		library_error = str(loaded.get("reason", "藍圖冊無法讀取。"))
		status = library_error

func _write_library(next: Array) -> Dictionary:
	var saved: Dictionary = Library.save_library(_library_path, next, World.BUILD, World.NAMES)
	if saved.get("ok") != true:
		return _library_fail(str(saved.get("reason", "藍圖冊未保存。")))
	entries = (saved.entries as Array).duplicate(true)
	return _result(true, "")

func _library_guard() -> String:
	if not _configured:
		return "藍圖冊尚未載入。"
	if not library_error.is_empty():
		return "藍圖冊讀取失敗，為保護原檔已暫停寫入：" + library_error
	var bad: String = Library.path_problem(_library_path)
	return bad

func _library_fail(reason: String) -> Dictionary:
	status = reason
	feedback.emit(reason, false)
	changed.emit()
	return _result(false, reason)

func _entry_index(id: String) -> int:
	if not Library.valid_id(id):
		return -1
	for i in entries.size():
		if str(entries[i].id) == id:
			return i
	return -1

func _new_id() -> String:
	var crypto := Crypto.new()
	for _attempt in 8:
		var id := crypto.generate_random_bytes(16).hex_encode()
		if _entry_index(id) < 0:
			return id
	return crypto.generate_random_bytes(16).hex_encode()

func _invalidate_quote() -> void:
	_generation += 1
	quote = {}
	quote_waiting = false
	_quote_request = 0
	_quote_for_generation = -2

## Clears capture/placing state (not captured, entries or pending) and returns to idle.
func _reset_transient() -> void:
	_invalidate_quote()
	draft = {}
	turns = 0
	locked = false
	origin = Vector2i.ZERO
	if mode == "capture" or mode == "placing":
		mode = "idle"

func _drop_unsent_modes() -> void:
	if mode == "capture" or mode == "placing":
		_reset_transient()

func _busy_reason() -> String:
	if not pending_error.is_empty():
		return pending_error
	if mode == "submitting":
		return "施工結果等待中，不能開始另一筆施工。"
	return "有一筆施工結果尚未確認，請先按「重試確認」。"

func _refuse(reason: String) -> void:
	status = reason
	feedback.emit(reason, false)
	changed.emit()

func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}

func _session_ready() -> bool:
	return _session != null and is_instance_valid(_session)

func _own_id() -> String:
	if not _session_ready():
		return ""
	var value = _session.get("own_id")
	return String(value) if typeof(value) == TYPE_STRING else ""

## {region, epoch} of the own player from the current snapshot, or {}.
func _own_context() -> Dictionary:
	var me = _own_player()
	if not me is Dictionary:
		return {}
	var snap: Dictionary = _session.get("snapshot")
	var epoch = me.get("travel_epoch", 0)
	if typeof(epoch) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	return {"region": str(snap.get("region_id", "home")), "epoch": int(epoch)}

func _own_player():
	if not _session_ready():
		return null
	var snap = _session.get("snapshot")
	var own := _own_id()
	if not snap is Dictionary or own.is_empty():
		return null
	var people = snap.get("players")
	if not people is Dictionary:
		return null
	var me = people.get(own)
	return me if me is Dictionary else null

func _player_cell():
	var me = _own_player()
	if me == null:
		return null
	var x = me.get("x")
	var y = me.get("y")
	if typeof(x) not in [TYPE_INT, TYPE_FLOAT] or typeof(y) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	if not is_finite(float(x)) or not is_finite(float(y)):
		return null
	return Vector2i(floori(float(x)), floori(float(y)))

func _clamp_cell(cell: Vector2i) -> Vector2i:
	var limit: int = Protocol.COORD_LIMIT
	return Vector2i(clampi(cell.x, -limit, limit), clampi(cell.y, -limit, limit))

func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return Time.get_ticks_msec()
