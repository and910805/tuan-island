extends RefCounted

## T021 / chapter 12: "操作紀錄" page of a wooden chest (recent transfers, newest first).
## Pure view: the caller (chest modal) owns requests and permission checks and feeds
## the result through refresh(). Uses only the native Menu theme through app.label /
## app.button; row focus rendering comes from the theme's Button styleboxes.

const World = preload("res://scripts/world.gd")
const ChestHistory = preload("res://scripts/chest_history.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const FlowerArt = preload("res://scripts/flower_art.gd")

const LOADING := "loading"
const DENIED := "denied"
const MAX_ROWS := ChestHistory.MAX_ENTRIES
const VIEWPORT_HEIGHT := 330
const MESSAGES := {
	LOADING: "正在讀取操作紀錄…",
	DENIED: "你目前沒有權限查看這個木箱的操作紀錄。",
}
const EMPTY_TEXT := "這個木箱還沒有存取紀錄。"
const DEPOSIT_COLOR := Color("48694a")
const WITHDRAW_COLOR := Color("925230")

## Returns {root, back, status, count, scroll, list, rows}. Add view.root to the modal
## content. The view starts in the loading state; call refresh() with the result.
static func build(app, on_back: Callable) -> Dictionary:
	var root := VBoxContainer.new()
	root.name = "ChestHistory"
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var back: Button = app.button("返回木箱", on_back)
	back.name = "ChestHistoryBack"
	back.focus_mode = Control.FOCUS_ALL
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header.add_child(back)
	var count: Label = app.label("", 15)
	count.name = "ChestHistoryCount"
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(count)
	var status: Label = app.label("", 16)
	status.name = "ChestHistoryStatus"
	root.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.name = "ChestHistoryRows"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = VIEWPORT_HEIGHT
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var view := {"root": root, "back": back, "status": status, "count": count,
		"scroll": scroll, "list": list, "rows": [], "app": app}
	refresh(view, [], LOADING)
	return view

## status: "" = show rows (or the empty state), LOADING, DENIED, or any other text to
## show as a message instead of rows. Rows are the chest's recent_transfers array in
## stored (oldest first) order; they are sorted and capped here.
static func refresh(view: Dictionary, rows: Array, status: String = "") -> void:
	var list: VBoxContainer = view.list
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var buttons: Array = view.rows
	buttons.clear()
	var message: Label = view.status
	var count: Label = view.count
	var entries := [] if not status.is_empty() else display_rows(rows)
	if not status.is_empty():
		message.text = str(MESSAGES.get(status, status))
		message.add_theme_color_override("font_color", WITHDRAW_COLOR if status == DENIED else Color("5b5a4a"))
		count.text = ""
	elif entries.is_empty():
		message.text = EMPTY_TEXT
		message.add_theme_color_override("font_color", Color("5b5a4a"))
		count.text = "共 0 筆"
	else:
		message.text = ""
		count.text = "最近 %d 筆" % entries.size()
	message.visible = not message.text.is_empty()
	for entry: Dictionary in entries:
		var row := _row(entry, buttons.size() % 2 == 0)
		list.add_child(row)
		buttons.append(row)
	# Rows and the back button are all focusable; the scroll follows focus.
	view.scroll.scroll_vertical = 0

## Valid rows only (bad rows are dropped, never shown half-formed), newest first, at
## most MAX_ROWS. Equal times keep the later-recorded row first.
static func display_rows(rows: Array) -> Array:
	var kept: Array = []
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or not _usable(row):
			continue
		kept.append({"actor": str(row.actor).strip_edges(), "item": str(row.item),
			"amount": int(row.amount), "depositing": row.depositing,
			"time": float(row.time), "order": index})
	kept.sort_custom(func(a, b): return a.time > b.time or (a.time == b.time and a.order > b.order))
	if kept.size() > MAX_ROWS:
		kept.resize(MAX_ROWS)
	return kept

static func _usable(row: Dictionary) -> bool:
	var amount: Variant = row.get("amount")
	var time: Variant = row.get("time")
	return row.get("actor") is String and row.get("item") is String \
		and row.get("depositing") is bool \
		and (amount is int or amount is float) and is_finite(float(amount)) and amount >= 1 \
		and (time is int or time is float) and is_finite(float(time)) and time >= 0

## "第 N 日 HH:MM", same day/clock rule as the HUD (1440 world seconds per day).
static func time_text(time: float) -> String:
	var seconds := int(World.WEATHER.safe_time(time))
	var minutes := seconds % 1440
	return "第 %d 日 %02d:%02d" % [1 + seconds / 1440, minutes / 60, minutes % 60]

static func action_text(depositing: bool) -> String:
	return "存入" if depositing else "取出"

static func item_text(id: String) -> String:
	return str(World.NAMES.get(id, id))

static func summary(entry: Dictionary) -> String:
	var actor: String = entry.actor if not str(entry.actor).is_empty() else "未具名玩家"
	return "%s　%s　%s ×%d\n%s" % [actor, action_text(entry.depositing), item_text(entry.item),
		entry.amount, time_text(entry.time)]

static func _row(entry: Dictionary, shaded: bool) -> Button:
	var row := Button.new()
	row.name = "ChestHistoryRow"
	row.text = summary(entry)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0, 49)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.tooltip_text = summary(entry).replace("\n", "　")
	row.clip_text = true
	row.expand_icon = true
	row.add_theme_constant_override("icon_max_width", 32)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f5e3c6") if shaded else Color("faead1")
	paper.content_margin_left = 12
	paper.content_margin_right = 8
	row.add_theme_stylebox_override("normal", paper)
	var icon: Texture2D = FlowerArt.item_texture(entry.item) if FlowerArt.has_item(entry.item) else ItemArt.icon(entry.item)
	if icon != null:
		row.icon = icon
	var tint: Color = DEPOSIT_COLOR if entry.depositing else WITHDRAW_COLOR
	row.add_theme_color_override("font_color", tint)
	row.add_theme_color_override("font_focus_color", tint)
	row.add_theme_color_override("font_hover_color", tint)
	return row
