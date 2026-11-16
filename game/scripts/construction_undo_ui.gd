extends RefCounted
## Compact "undo last construction" entry embedded in the EXISTING build menu
## (catalog tab bar in village_art_preview, top row in the legacy list).
##
## Data: session.snapshot.own_construction_undo
##   {id, label, available, reason, seconds_left, region}
## Absent / malformed data means "no history" and the entry stays disabled.
##
## The server is authoritative. Confirm sends exactly one
##   session.perform("undo_build", <own current tile>, record.id)
## for the record that was SHOWN when the confirmation opened. If the snapshot
## later carries a different record (or it becomes unavailable / expires) the
## confirmation re-quotes or disables instead of submitting a different action.
##
## Countdown = snapshot seconds_left minus local time elapsed since that value
## was observed. Text is refreshed from main's existing 0.2 s HUD tick and on
## snapshot change; no nodes are created after attach().

const HouseUI = preload("res://scripts/house_ui.gd")
const LifeShell = preload("res://scripts/life_ui_shell.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const ACTION := "undo_build"
const WINDOW_SECONDS := 30.0
## Session._action drops non-ship extras longer than 32 characters.
const MAX_ID_LEN := 32
const MAX_LABEL_LEN := 40
## After dispatch the same record stays disabled this long (or until the server
## replaces it), so a double click or a stale snapshot cannot resend it.
const SENT_HOLD_MS := 4000

const TEXT_NONE := "目前沒有可復原的施工"
const TEXT_EXPIRED := "已超過 30 秒，無法復原"
const TEXT_UNAVAILABLE := "這筆施工已無法復原"
const TEXT_REGION := "回到施工的地區才能復原"
const TEXT_NO_TILE := "找不到你的位置，暫時無法復原"
const TEXT_SENT := "已送出復原，等待島上結果…"

var app
var modal: Control
var entry: Button
var status: Label
var bar: Control
var bar_text: Label
var confirm_button: Button
var cancel_button: Button
var on_layout: Callable
## Record captured when the confirmation was opened (or last re-quoted).
var shown: Dictionary = {}
var requoted := false
var submitted: Dictionary = {}
var pending_id := ""
# Countdown base: raw summary last observed, its seconds, and local tick.
var base_raw: Variant = null
var base_seconds := 0.0
var base_ms := 0

## Normalized copy of the snapshot summary, or {} for absent/invalid data.
static func normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():return {}
	var id: Variant = raw.get("id")
	if typeof(id) not in [TYPE_STRING, TYPE_STRING_NAME]:return {}
	var text_id := String(id)
	if text_id.is_empty() or text_id.length() > MAX_ID_LEN or text_id.to_utf8_buffer().size() > MAX_ID_LEN:return {}
	var label: Variant = raw.get("label")
	var shown_label := String(label).strip_edges() if typeof(label) in [TYPE_STRING, TYPE_STRING_NAME] else ""
	if shown_label.is_empty():shown_label = "上一次施工"
	if shown_label.length() > MAX_LABEL_LEN:shown_label = shown_label.left(MAX_LABEL_LEN - 1) + "…"
	var reason: Variant = raw.get("reason")
	var seconds: Variant = raw.get("seconds_left")
	var left := 0.0
	if typeof(seconds) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(seconds)):
		left = clampf(float(seconds), 0.0, WINDOW_SECONDS)
	var region: Variant = raw.get("region")
	return {
		"id": text_id,
		"label": shown_label,
		"available": typeof(raw.get("available")) == TYPE_BOOL and bool(raw.get("available")),
		"reason": String(reason) if typeof(reason) in [TYPE_STRING, TYPE_STRING_NAME] else "",
		"seconds_left": left,
		"region": String(region) if typeof(region) in [TYPE_STRING, TYPE_STRING_NAME] else "",
	}

## Called on every snapshot (cheap compare); resets the local countdown base
## only when the summary itself changed.
func observe(snapshot: Dictionary) -> void:
	var raw: Variant = snapshot.get("own_construction_undo")
	if typeof(raw) == typeof(base_raw) and (typeof(raw) == TYPE_NIL or raw == base_raw):return
	base_raw = raw.duplicate(true) if raw is Dictionary else raw
	base_seconds = float(normalize(raw).get("seconds_left", 0.0))
	base_ms = Time.get_ticks_msec()

func remaining() -> float:
	return maxf(0.0, base_seconds - float(Time.get_ticks_msec() - base_ms) / 1000.0)

## {record, enabled, reason, seconds}
func state() -> Dictionary:
	var snapshot: Dictionary = app.session.snapshot
	observe(snapshot)
	var record := normalize(snapshot.get("own_construction_undo"))
	var seconds := int(ceilf(remaining()))
	var result := {"record": record, "enabled": false, "reason": "", "seconds": seconds}
	if record.is_empty():
		result.reason = TEXT_NONE
	elif submitted.has(record.id) and Time.get_ticks_msec() - int(submitted[record.id]) < SENT_HOLD_MS:
		result.reason = TEXT_SENT
	elif not record.available:
		result.reason = record.reason if not String(record.reason).is_empty() else TEXT_UNAVAILABLE
	elif seconds <= 0:
		result.reason = TEXT_EXPIRED
	elif not String(record.region).is_empty() and record.region != str(snapshot.get("region_id", "home")):
		result.reason = TEXT_REGION
	elif not HouseUI.local_cell(snapshot, str(app.session.own_id)).ok:
		result.reason = TEXT_NO_TILE
	else:
		result.enabled = true
	return result

## Builds the compact entry into `toolbar` and a hidden confirmation strip
## into `strip_parent` at `strip_index`. `layout` is called when the strip
## shows/hides so the host can refit.
func attach(host, toolbar: Container, strip_parent: Container, strip_index: int, layout: Callable = Callable()) -> void:
	app = host
	modal = app.modal
	shown = {}
	requoted = false
	on_layout = layout
	status = app.label("", 13)
	status.name = "UndoStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_stretch_ratio = 3.0
	status.custom_minimum_size.x = 0
	status.clip_text = true
	status.add_theme_color_override("font_color", Color("5d634a"))
	toolbar.add_child(status)
	entry = app.button("復原", open_confirmation)
	entry.name = "UndoConstruction"
	entry.icon = LifeShell.icon("remove")
	entry.add_theme_constant_override("icon_max_width", 24)
	entry.custom_minimum_size.x = 112
	entry.size_flags_horizontal = Control.SIZE_SHRINK_END
	toolbar.add_child(entry)
	var strip := PanelContainer.new()
	strip.name = "UndoConfirmBar"
	strip.hide()
	# Existing styles only: pixel paper in the catalog, the app's plain box in legacy.
	strip.add_theme_stylebox_override("panel", PixelTheme.paper_style() if app.village_art_preview else app.box(Color("fff6df"), Color("cabb94"), 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	bar_text = app.label("", 14)
	bar_text.name = "UndoConfirmText"
	bar_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar_text)
	cancel_button = app.button("取消", cancel_confirmation)
	cancel_button.name = "UndoCancel"
	cancel_button.custom_minimum_size.x = 84
	row.add_child(cancel_button)
	confirm_button = app.button("確認復原", confirm)
	confirm_button.name = "UndoConfirm"
	confirm_button.custom_minimum_size.x = 108
	row.add_child(confirm_button)
	strip_parent.add_child(strip)
	strip_parent.move_child(strip, clampi(strip_index, 0, strip_parent.get_child_count() - 1))
	bar = strip
	refresh()

func attached() -> bool:
	if app == null or not is_instance_valid(entry) or not is_instance_valid(modal) or not is_instance_valid(bar) or app.modal != modal:
		detach()
		return false
	return true

func detach() -> void:
	modal = null
	entry = null
	status = null
	bar = null
	bar_text = null
	confirm_button = null
	cancel_button = null
	shown = {}
	requoted = false

func confirming() -> bool:
	return attached() and bar.visible

func open_confirmation() -> void:
	if not attached():return
	var current := state()
	if not current.enabled:
		refresh()
		return
	shown = current.record.duplicate()
	requoted = false
	_show_bar(true)
	refresh()
	cancel_button.call_deferred("grab_focus")

## Cancel / Esc: never sends anything. Returns true when a strip was closed.
func cancel_confirmation() -> bool:
	if not confirming():return false
	shown = {}
	requoted = false
	_show_bar(false)
	refresh()
	if is_instance_valid(entry):entry.call_deferred("grab_focus")
	return true

func confirm() -> void:
	if not confirming() or shown.is_empty():return
	var current := state()
	var record: Dictionary = current.record
	if not _same(record, shown):
		_requote(current)
		return
	if not current.enabled:
		refresh()
		return
	var cell: Dictionary = HouseUI.local_cell(app.session.snapshot, str(app.session.own_id))
	if not cell.ok:
		refresh()
		return
	var id: String = shown.id
	if submitted.size() > 32:submitted.clear()
	submitted[id] = Time.get_ticks_msec()
	pending_id = id
	confirm_button.disabled = true
	shown = {}
	requoted = false
	_show_bar(false)
	refresh()
	app.session.perform(ACTION, cell.cell, id)

func complete(result:Dictionary)->void:
	if pending_id.is_empty():return
	if not result.get("ok",false):submitted.erase(pending_id)
	pending_id=""
	refresh()

func refresh() -> void:
	if not attached():return
	var current := state()
	if bar.visible and not shown.is_empty() and current.enabled and not _same(current.record, shown):
		_requote(current)
		return
	_render(current)

func _render(current: Dictionary) -> void:
	var record: Dictionary = current.record
	entry.disabled = not current.enabled or bar.visible
	entry.text = "復原 %d秒" % current.seconds if current.enabled else "復原"
	var line: String
	if current.enabled:
		line = "上一步：%s · 剩 %d 秒" % [record.label, current.seconds]
	elif record.is_empty():
		line = current.reason
	else:
		line = "%s：%s" % [record.label, current.reason]
	status.text = line
	status.tooltip_text = line
	entry.tooltip_text = line if not current.enabled else "復原「%s」（30 秒內，伺服器確認後反向結算材料）" % record.label
	if not bar.visible:return
	var still:bool = current.enabled and _same(record, shown)
	confirm_button.disabled = not still
	var text: String
	if still:
		text = "復原「%s」？剩 %d 秒。物件還原，材料反向結算；復原拆除會扣回退料。" % [shown.label, current.seconds]
		if requoted:text = "最近的施工已更新，請再確認一次。\n" + text
	else:
		var why: String = current.reason
		if record.is_empty() or not _same(record, shown):why = "紀錄已變更或不存在，這次不會送出"
		text = "無法復原「%s」：%s" % [shown.label, why]
	bar_text.text = text

## A different, still-undoable record replaces the shown one and must be
## confirmed again; an unusable record only disables (shown is kept).
func _requote(current: Dictionary) -> void:
	if current.enabled and not _same(current.record, shown):
		shown = (current.record as Dictionary).duplicate()
		requoted = true
	_render(current)

static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():return false
	return a.id == b.id and a.label == b.label and a.region == b.region

func _show_bar(visible: bool) -> void:
	bar.visible = visible
	if on_layout.is_valid():on_layout.call(visible)
