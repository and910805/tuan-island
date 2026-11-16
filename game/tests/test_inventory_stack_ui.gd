extends SceneTree

## T014 chest stack controls (village art preview UI, real World through Session).
##
## Run with the user arg `-- --village-art-preview` like the other life UI tests;
## the suite also sets app.village_art_preview=true before the scene enters the tree.
## Session.perform runs locally: app.session.world is the World and peers[1] is the
## tester, so every press goes Session.perform -> _action -> World.act.
##
## Disclosed fixture presets (direct state writes, marked # PRESET): the chest at
## CELL with its items, the tester's backpack counts and x/y.

const World = preload("res://scripts/world.gd")
const CELL := Vector2i(38, 33)
const TOKEN := "tester"
const BUTTONS := ["ChestDeposit1", "ChestDepositHalf", "ChestDepositAll", "ChestWithdraw1", "ChestWithdrawHalf", "ChestWithdrawAll"]
const DEPOSITS := ["ChestDeposit1", "ChestDepositHalf", "ChestDepositAll"]
const WITHDRAWS := ["ChestWithdraw1", "ChestWithdrawHalf", "ChestWithdrawAll"]
const SIZES := [Vector2i(1024, 640), Vector2i(1280, 720), Vector2i(1920, 1080)]

var app
var world
var checks := 0
var failures := 0
var finished := false

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func finish() -> void:
	if finished:
		return
	finished = true
	print("INVENTORY_STACK_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 or checks == 0 else 0)

# ------------------------------------------------------------------ helpers --

func person() -> Dictionary:
	return world.state.players[TOKEN]

func held(item: String) -> int:
	return int(person().inventory.get(item, 0))

func box() -> Dictionary:
	var found = world.state.objects.get(World.key(CELL), {})
	return found if found is Dictionary else {}

func stored(item: String) -> int:
	var contents = box().get("items", {})
	return int(contents.get(item, 0)) if contents is Dictionary else 0

func set_counts(in_bag: int, in_box: int) -> void:
	person().inventory.wood = in_bag  # PRESET
	world.state.objects[World.key(CELL)] = {"type": "chest", "owner": TOKEN, "items": {"wood": in_box}}  # PRESET

func modal_open() -> bool:
	return app.modal != null and is_instance_valid(app.modal)

func chest_button(node_name: String) -> Button:
	if not modal_open():
		return null
	return (app.modal as Node).find_child(node_name, true, false) as Button

func button_named(title: String, node: Node) -> Button:
	if node is Button and (node.text == title or node.tooltip_text == title):
		return node
	for child in node.get_children():
		var match_button := button_named(title, child)
		if match_button != null:
			return match_button
	return null

func focused_name() -> String:
	var owner := root.gui_get_focus_owner()
	return str(owner.name) if owner != null else "none"

func frames() -> void:
	for i in range(4):
		await process_frame
	app._layout_preview()
	await process_frame
	await process_frame

## Publish the World through the real host snapshot path, then refresh the
## open life panel in place.
func sync() -> void:
	app.session._send_snapshot(1)
	if modal_open():
		app.life_panels.refresh(app)
	await frames()

func open_chest() -> void:
	app.session._send_snapshot(1)
	app.life_panels.chest(app, CELL)
	var entry: Button = button_named(str(World.NAMES.wood), app.modal) if modal_open() else null
	expect(entry != null, "chest catalog lists wood")
	if entry != null:
		entry.pressed.emit()
	await frames()

func close_chest() -> void:
	if modal_open():
		app._close_modal()
	await frames()

func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		root.push_input(e)
	await frames()

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await process_frame
	await frames()

func not_clipped(item: Control) -> bool:
	var parent := item.get_parent()
	while parent != null:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().grow(1).encloses(item.get_global_rect()):
			return false
		parent = parent.get_parent()
	return true

func tooltips_are(expected: Dictionary, label: String) -> void:
	for node_name in expected:
		var b := chest_button(str(node_name))
		var got: String = b.tooltip_text if b != null else "<missing>"
		expect(got == str(expected[node_name]), "%s: %s tooltip '%s' == '%s'" % [label, node_name, got, expected[node_name]])

func disabled_are(names: Array, disabled: bool, label: String) -> void:
	for node_name in names:
		var b := chest_button(str(node_name))
		expect(b != null and b.disabled == disabled, "%s: %s disabled=%s" % [label, node_name, str(disabled)])

func ready_to_act() -> void:
	app.session.rates[1] = []

# -------------------------------------------------------------------- cases --

func check_layout() -> void:
	set_counts(6, 4)
	for size in SIZES:
		root.content_scale_size = size
		root.size = size
		await frames()
		await open_chest()
		var tag := str(size)
		expect(modal_open(), "chest opens at " + tag)
		if not modal_open():
			continue
		var modal: Control = app.modal
		var modal_rect := modal.get_global_rect()
		expect(root.get_visible_rect().encloses(modal_rect), "chest modal fits the viewport at %s: %s in %s" % [tag, str(modal_rect), str(root.get_visible_rect())])
		for node_name in BUTTONS:
			var b := chest_button(node_name)
			expect(b != null, "%s exists at %s" % [node_name, tag])
			if b == null:
				continue
			var r := b.get_global_rect()
			expect(b.is_visible_in_tree(), "%s visible at %s" % [node_name, tag])
			expect(modal_rect.encloses(r), "%s inside the modal at %s: %s in %s" % [node_name, tag, str(r), str(modal_rect)])
			expect(not_clipped(b), "%s not clipped by a scroll area at %s" % [node_name, tag])
			expect(r.size.x >= 1.0 and r.size.y >= 1.0, "%s has a real hit area at %s" % [node_name, tag])
			expect(b.size.x + 0.5 >= b.get_combined_minimum_size().x, "%s label not cut at %s" % [node_name, tag])
			expect(b.focus_mode == Control.FOCUS_ALL, "%s accepts keyboard focus at %s" % [node_name, tag])
			expect(not b.disabled, "%s enabled with 6 held / 4 stored at %s" % [node_name, tag])
		tooltips_are({"ChestDeposit1": "存入 1 件", "ChestDepositHalf": "存入半數 3 件", "ChestDepositAll": "全部存入 6 件",
			"ChestWithdraw1": "取出 1 件", "ChestWithdrawHalf": "取出半數 2 件", "ChestWithdrawAll": "全部取出 4 件"}, "6/4 at " + tag)
		await close_chest()
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await frames()

func check_refresh_in_place() -> void:
	set_counts(6, 4)
	await open_chest()
	var half := chest_button("ChestDepositHalf")
	var take_all := chest_button("ChestWithdrawAll")
	person().inventory.wood = 0  # PRESET
	await sync()
	expect(chest_button("ChestDepositHalf") == half and chest_button("ChestWithdrawAll") == take_all, "refresh keeps the same button instances")
	disabled_are(DEPOSITS, true, "empty backpack")
	disabled_are(WITHDRAWS, false, "empty backpack")
	tooltips_are({"ChestDeposit1": "存入 1 件", "ChestWithdraw1": "取出 1 件", "ChestWithdrawHalf": "取出半數 2 件", "ChestWithdrawAll": "全部取出 4 件"}, "empty backpack")
	person().inventory.wood = 5  # PRESET
	box().items.wood = 0  # PRESET
	await sync()
	disabled_are(DEPOSITS, false, "empty box stack")
	disabled_are(WITHDRAWS, true, "empty box stack")
	tooltips_are({"ChestDepositHalf": "存入半數 3 件", "ChestDepositAll": "全部存入 5 件"}, "odd backpack 5")
	person().inventory.wood = 1  # PRESET
	box().items.wood = 3  # PRESET
	await sync()
	tooltips_are({"ChestDepositHalf": "存入半數 1 件", "ChestDepositAll": "全部存入 1 件",
		"ChestWithdrawHalf": "取出半數 2 件", "ChestWithdrawAll": "全部取出 3 件"}, "single backpack / odd box")
	disabled_are(BUTTONS, false, "1 held / 3 stored")
	world.state.objects.erase(World.key(CELL))  # PRESET box removed by someone else
	await sync()
	disabled_are(BUTTONS, true, "box gone")
	set_counts(6, 4)
	await sync()
	disabled_are(BUTTONS, false, "box restored")
	tooltips_are({"ChestDepositHalf": "存入半數 3 件", "ChestWithdrawAll": "全部取出 4 件"}, "box restored")
	await close_chest()

func check_press_half() -> void:
	set_counts(6, 4)
	await open_chest()
	var b := chest_button("ChestDepositHalf")
	expect(b != null and not b.disabled, "ChestDepositHalf ready to press")
	var counter: int = app.session.counter
	ready_to_act()
	if b != null:
		b.pressed.emit()
	await frames()
	expect(int(app.session.counter) == counter + 1, "deposit half sends exactly one Session action")
	expect(held("wood") == 3 and stored("wood") == 7, "deposit half moved 3 (backpack %d, box %d)" % [held("wood"), stored("wood")])
	expect(held("wood") + stored("wood") == 10, "deposit half conserves wood")
	expect(not modal_open(), "deposit half closes the chest panel")
	var shown: String = app.toast.text if app.toast != null else ""
	expect(shown.contains("已存入%s ×3" % str(World.NAMES.wood)), "toast reports the stack move: " + shown)
	await close_chest()

func check_keyboard() -> void:
	set_counts(6, 4)
	await open_chest()
	var one := chest_button("ChestDeposit1")
	expect(one != null, "ChestDeposit1 present for keyboard test")
	if one == null:
		return
	one.grab_focus()
	await frames()
	expect(focused_name() == "ChestDeposit1", "ChestDeposit1 takes keyboard focus: " + focused_name())
	await key(KEY_RIGHT)
	expect(focused_name() == "ChestDepositHalf", "KEY_RIGHT moves 1 -> 半數: " + focused_name())
	await key(KEY_RIGHT)
	expect(focused_name() == "ChestDepositAll", "KEY_RIGHT moves 半數 -> 全部: " + focused_name())
	await key(KEY_DOWN)
	expect(focused_name().begins_with("ChestWithdraw"), "KEY_DOWN reaches the withdraw row: " + focused_name())
	var half := chest_button("ChestWithdrawHalf")
	if half != null:
		half.grab_focus()
	await frames()
	expect(focused_name() == "ChestWithdrawHalf", "ChestWithdrawHalf focused before Enter: " + focused_name())
	var counter: int = app.session.counter
	ready_to_act()
	await key(KEY_ENTER)
	expect(int(app.session.counter) == counter + 1, "KEY_ENTER on the focused button sends one action")
	expect(held("wood") == 8 and stored("wood") == 2, "KEY_ENTER withdraw half moved 2 (backpack %d, box %d)" % [held("wood"), stored("wood")])
	expect(not modal_open(), "KEY_ENTER press closes the chest panel")
	await close_chest()

func check_mouse() -> void:
	set_counts(6, 2)
	await open_chest()
	var all := chest_button("ChestDepositAll")
	expect(all != null and not all.disabled and all.is_visible_in_tree(), "ChestDepositAll clickable")
	if all == null:
		return
	var counter: int = app.session.counter
	ready_to_act()
	await click(all.get_global_rect().get_center())
	expect(int(app.session.counter) == counter + 1, "mouse click sends one action")
	expect(held("wood") == 0 and stored("wood") == 8, "mouse deposit all moved 6 (backpack %d, box %d)" % [held("wood"), stored("wood")])
	expect(not modal_open(), "mouse click closes the chest panel")
	await close_chest()
	# A click on a disabled button does nothing and keeps the panel open.
	await open_chest()
	var blocked := chest_button("ChestDepositAll")
	expect(blocked != null and blocked.disabled, "ChestDepositAll disabled with an empty backpack")
	if blocked == null:
		return
	counter = app.session.counter
	ready_to_act()
	await click(blocked.get_global_rect().get_center())
	expect(int(app.session.counter) == counter, "disabled click sends nothing")
	expect(held("wood") == 0 and stored("wood") == 8, "disabled click moves nothing")
	expect(modal_open(), "disabled click keeps the chest panel open")
	await close_chest()

func run() -> void:
	create_timer(180.0).timeout.connect(func():
		if not finished:
			expect(false, "watchdog: suite did not finish within 180 s")
			finish()
	)
	app = load("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	world = World.new()
	world.add_player(TOKEN, "島民")
	person().x = 39.5  # PRESET within the 3.2 reach of CELL
	person().y = 33.5  # PRESET
	set_counts(6, 4)
	app.session.snapshot = world.state
	app.session.own_id = TOKEN
	app.session.world = world
	app.session.peers[1] = TOKEN
	app.session.sequences[1] = 0
	app.session.rates[1] = []
	if app.menu != null:
		app.menu.hide()
	if app.hud != null:
		app.hud.show()
	app.view.update_snapshot(world.state, TOKEN)
	expect(app.village_art_preview, "village art preview UI active")
	await check_layout()
	await check_refresh_in_place()
	await check_press_half()
	await check_keyboard()
	await check_mouse()
	app.life_panels.updates.clear()
	app.queue_free()
	await process_frame
	finish()
