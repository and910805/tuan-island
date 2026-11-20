extends SceneTree

const Ui = preload("res://scripts/chest_history_ui.gd")

## Minimal stand-in for main.gd's label()/button() helpers.
class StubApp:
	extends RefCounted
	func label(text: String, size_value: int = 17) -> Label:
		var l := Label.new()
		l.text = text
		return l
	func button(text: String, callback: Callable) -> Button:
		var b := Button.new()
		b.text = text
		b.pressed.connect(callback)
		return b

var backed := 0
var checks := 0
var failures := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var view := Ui.build(StubApp.new(), func(): backed += 1)
	get_root().add_child(view.root)
	# Loading state first: message, no rows.
	expect(view.status.visible and view.status.text == Ui.MESSAGES[Ui.LOADING], "Loading message is visible")
	expect(view.rows.is_empty(), "Loading does not show rows")
	view.back.pressed.emit()
	expect(backed == 1 and view.back.focus_mode == Control.FOCUS_ALL, "Back button works and accepts focus")

	# Newest first, ties keep the later record first, names/actions/counts explicit.
	var rows := [
		{"actor": "阿露", "item": "wood", "amount": 5, "depositing": true, "time": 100.0},
		{"actor": "米魯", "item": "stone", "amount": 2, "depositing": false, "time": 1500.0},
		{"actor": "小栗", "item": "wood", "amount": 1, "depositing": true, "time": 1500.0},
		{"actor": "壞", "item": "wood", "amount": 0, "depositing": true, "time": 1.0},
		"junk",
	]
	Ui.refresh(view, rows)
	expect(view.rows.size() == 3, "Only valid history rows are shown")
	expect(not view.status.visible, "Status is hidden when records are available")
	if view.rows.size() == 3:
		expect(view.rows[0].text.begins_with("小栗　存入　"), "Later deposit is first when times match")
		expect(view.rows[1].text.begins_with("米魯　取出　"), "Withdrawal records include the name and action")
		expect("×2" in view.rows[1].text and "第 2 日 01:00" in view.rows[0].text, "Quantity and in-game date are shown")
		expect(view.rows[2].text.contains("第 1 日 01:40"), "Oldest record is last")
	expect(Ui.time_text(1440.0) == "第 2 日 00:00", "Midnight rolls over to the next day")
	for row in view.rows:
		expect(row.focus_mode == Control.FOCUS_ALL, "History row accepts focus")

	# Cap at 200, newest kept.
	var many: Array = []
	for i in 250:
		many.append({"actor": "a", "item": "wood", "amount": 1, "depositing": true, "time": float(i)})
	Ui.refresh(view, many)
	expect(view.rows.size() == 200, "History is limited to 200 rows")
	expect(not view.rows.is_empty() and "第 1 日 04:09" in view.rows[0].text, "The newest record stays after truncation")

	# Empty, denied, loading and custom message hide rows.
	Ui.refresh(view, [])
	expect(view.rows.is_empty() and view.status.text == Ui.EMPTY_TEXT, "Empty result displays its message")
	Ui.refresh(view, many, Ui.DENIED)
	expect(view.rows.is_empty() and view.status.text == Ui.MESSAGES[Ui.DENIED], "Denied history hides records")
	Ui.refresh(view, many, "連線逾時")
	expect(view.rows.is_empty() and view.status.text == "連線逾時", "A connection error explains why history is hidden")
	Ui.refresh(view, many, Ui.LOADING)
	expect(view.rows.is_empty(), "Refreshing hides previous records while loading")
	print("CHEST_HISTORY_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
