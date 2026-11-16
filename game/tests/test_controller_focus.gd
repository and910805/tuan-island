extends SceneTree
## Controller (joypad) focus audit — standalone, read-only.
## See docs/playtest/controller-flow-audit.md for the slices these checks map to.
##
## Two kinds of result:
##   CONTRACT  must hold today; a failure exits 1.
##   GAP       a known controller gap from the audit. Printed as "GAP <id> ..." and
##             NOT a failure by default, so the suite stays green while the slices are
##             unimplemented. Pass `-- --controller-strict` to turn every GAP into a
##             failure (use this once a slice lands to lock it in), and move the probe
##             into CONTRACT when its slice ships.
##
## Writes no files: the session is an in-memory World (same pattern as
## test_input_routing.gd) and bindings are pointed at a path that is never committed.
## Runs in both default and `-- --village-art-preview` modes; the mode is printed.
##
## godot --headless --path game --script res://tests/test_controller_focus.gd [-- --village-art-preview] [--controller-strict]
## Success line: CONTROLLER_FOCUS checks=N failures=0 ... ; treat checks=0 as a failure
## (a compile error exits 0 with no checks).

const World = preload("res://scripts/world.gd")
const InventoryPanel = preload("res://scripts/inventory_panel.gd")
const ShippingPanel = preload("res://scripts/shipping_panel.gd")

var checks := 0
var failures := 0
var gaps := 0
var gaps_closed := 0
var strict := "--controller-strict" in OS.get_cmdline_user_args()
var preview := "--village-art-preview" in OS.get_cmdline_user_args()

func _initialize() -> void:
	# --script hangs forever if a SCRIPT ERROR aborts run(); never let that happen.
	create_timer(90.0).timeout.connect(func():
		print("CONTROLLER_FOCUS timeout checks=%d failures=%d gaps=%d" % [checks, failures, gaps])
		quit(2))
	call_deferred("run")

# --- reporting ---------------------------------------------------------------

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

## condition==true means the controller behaviour is already correct (gap closed).
func gap(id: String, condition: bool, message: String) -> void:
	checks += 1
	if condition:
		gaps_closed += 1
		print("GAP_CLOSED %s %s" % [id, message])
		return
	gaps += 1
	print("GAP %s %s" % [id, message])
	if strict:
		failures += 1
		push_error("FAIL(strict) GAP %s %s" % [id, message])

# --- joypad events -----------------------------------------------------------

func joy_button(button: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	return event

func joy_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event

## Press + release through the root viewport: _input -> GUI (focus nav, ui_accept) -> _unhandled_input.
func tap(button: JoyButton) -> void:
	root.push_input(joy_button(button, true))
	root.push_input(joy_button(button, false))
	await process_frame

func focus_owner() -> Control:
	return root.gui_get_focus_owner()

func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame

func has_joy_button(action: String, button: JoyButton) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return true
	return false

func has_joy_axis(action: String, axis: JoyAxis, sign_value: float) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and signf(event.axis_value) == sign_value:
			return true
	return false

# --- run -----------------------------------------------------------------------

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 800)
	check_input_map()
	await check_inventory_panel()
	await check_shipping_panel()
	await check_main_flow()
	print("CONTROLLER_FOCUS checks=%d failures=%d gaps=%d gaps_closed=%d strict=%s preview=%s" % [
		checks, failures, gaps, gaps_closed, strict, preview])
	quit(1 if failures > 0 or checks == 0 else 0)

## Godot's built-in ui_* actions are the only joypad bindings the game has; the
## project.godot has no [input] section. These must keep their pad events.
func check_input_map() -> void:
	expect(has_joy_button("ui_accept", JOY_BUTTON_A), "ui_accept keeps joypad A (south)")
	expect(has_joy_button("ui_cancel", JOY_BUTTON_B), "ui_cancel keeps joypad B (east)")
	expect(has_joy_button("ui_up", JOY_BUTTON_DPAD_UP), "ui_up keeps d-pad up")
	expect(has_joy_button("ui_down", JOY_BUTTON_DPAD_DOWN), "ui_down keeps d-pad down")
	expect(has_joy_button("ui_left", JOY_BUTTON_DPAD_LEFT), "ui_left keeps d-pad left")
	expect(has_joy_button("ui_right", JOY_BUTTON_DPAD_RIGHT), "ui_right keeps d-pad right")
	# Informational: whether the engine build maps the left stick onto ui_* navigation.
	print("INFO ui_left/ui_right left-stick mapped=%s ui_up/ui_down=%s" % [
		has_joy_axis("ui_left", JOY_AXIS_LEFT_X, -1.0) and has_joy_axis("ui_right", JOY_AXIS_LEFT_X, 1.0),
		has_joy_axis("ui_up", JOY_AXIS_LEFT_Y, -1.0) and has_joy_axis("ui_down", JOY_AXIS_LEFT_Y, 1.0)])
	# Slice C1: gameplay actions are keyboard-only (InputBindings stores physical keycodes).
	gap("C1-actions", InputMap.has_action("interact") or InputMap.has_action("inventory") or InputMap.has_action("move_up"),
		"no InputMap gameplay actions exist; InputBindings.matches() only accepts InputEventKey")

## InventoryPanel is the reference implementation: initial focus + explicit neighbours.
func check_inventory_panel() -> void:
	var snapshot := {"players": {"pad": {"coins": 7, "inventory": {"wood": 3, "stone": 2, "radish_seed": 4, "radish": 1}}}}
	var panel = InventoryPanel.new()
	root.add_child(panel)
	panel.setup(snapshot, "pad", Theme.new())
	panel.layout_for(Vector2(1280, 800))
	var closes := [0]
	panel.close_requested.connect(func(): closes[0] += 1)
	await settle()
	expect(focus_owner() == panel.slots[panel.selected_id], "inventory: opens with the selected slot focused (%s)" % panel.selected_id)

	var visible: Array = []
	for slot in panel.slots.values():
		if slot.visible:
			visible.append(slot)
	expect(visible.size() >= 2, "inventory: 'all' category shows at least two slots")
	if visible.size() >= 2:
		visible[0].grab_focus()
		await process_frame
		expect(panel.selected_id == visible[0].item_id, "inventory: focusing a slot selects it")
		await tap(JOY_BUTTON_DPAD_RIGHT)
		expect(focus_owner() == visible[1], "inventory: d-pad right moves to the next slot")
		expect(panel.selected_id == visible[1].item_id, "inventory: d-pad focus change updates the detail selection")
		await tap(JOY_BUTTON_DPAD_LEFT)
		expect(focus_owner() == visible[0], "inventory: d-pad left returns")
		await tap(JOY_BUTTON_DPAD_LEFT)
		expect(focus_owner() == visible[0], "inventory: d-pad left at column 0 stays put (no wrap into header)")
		await tap(JOY_BUTTON_DPAD_UP)
		expect(focus_owner() == panel.tabs[panel.category], "inventory: d-pad up from the first row reaches the active tab")
		await tap(JOY_BUTTON_DPAD_DOWN)
		expect(focus_owner() == panel.slots[panel.selected_id], "inventory: d-pad down from the tab returns to the selected slot")
		var columns: int = panel.grid.columns
		if visible.size() > columns:
			visible[0].grab_focus()
			await process_frame
			await tap(JOY_BUTTON_DPAD_DOWN)
			expect(focus_owner() == visible[columns], "inventory: d-pad down moves one grid row (%d columns)" % columns)

	# Category switch with A on a tab, then back into the filtered grid.
	var seeds_tab: Button = panel.tabs[2]
	seeds_tab.grab_focus()
	await process_frame
	await tap(JOY_BUTTON_A)
	expect(panel.category == 2, "inventory: A on the seed tab switches category")
	await tap(JOY_BUTTON_DPAD_DOWN)
	var landed := focus_owner()
	expect(landed != null and landed == panel.slots.get(panel.selected_id) and InventoryPanel.category_for(panel.selected_id) == 2,
		"inventory: d-pad down after a category switch lands on a slot of that category")

	# Close: A on the header button works; B relies on main's Escape-only routing.
	var close_button: Button = null
	for node in panel.find_children("*", "Button", true, false):
		if node.text == "關閉":
			close_button = node
	expect(close_button != null, "inventory: close button exists")
	panel.tabs[0].grab_focus()
	await process_frame
	await tap(JOY_BUTTON_DPAD_UP)
	gap("C4-inv-close-reach", focus_owner() == close_button,
		"inventory: d-pad up from the tab row does not reach 關閉 (no explicit neighbour; geometric search)")
	if close_button:
		close_button.grab_focus()
		await process_frame
		await tap(JOY_BUTTON_A)
		expect(closes[0] == 1, "inventory: A on 關閉 emits close_requested")
	panel.slots[panel.selected_id].grab_focus()
	await process_frame
	var before: int = closes[0]
	await tap(JOY_BUTTON_B)
	gap("C2-inv-cancel", closes[0] > before, "inventory panel: B (ui_cancel) does not request close")
	panel.queue_free()
	await process_frame

## ShippingPanel is the trade flow that a controller cannot enter cleanly today.
func check_shipping_panel() -> void:
	var snapshot := {"players": {"pad": {"coins": 0, "inventory": {"radish": 3, "wood": 5}}}}
	var panel = ShippingPanel.new()
	root.add_child(panel)
	panel.setup(snapshot, "pad", Theme.new())
	panel.layout_for(Vector2(1280, 800))
	await settle()
	var owner := focus_owner()
	gap("C4-ship-initial", owner != null and panel.is_ancestor_of(owner),
		"shipping: opens with no focused control (setup never calls grab_focus)")
	expect(not panel.selected_id.is_empty() and panel.slots.has(panel.selected_id), "shipping: a held item is preselected")
	if panel.slots.has(panel.selected_id):
		var start = panel.slots[panel.selected_id]
		start.grab_focus()
		await process_frame
		# Walk down by d-pad (geometric neighbours only) and see whether ＋ is reachable.
		var reached := false
		for step in 6:
			await tap(JOY_BUTTON_DPAD_DOWN)
			if focus_owner() == panel.plus:
				reached = true
				break
		gap("C4-ship-plus-reach", reached, "shipping: d-pad down from the slot grid does not reach ＋ within 6 steps")
		var id: String = panel.selected_id
		panel.plus.grab_focus()
		await process_frame
		await tap(JOY_BUTTON_A)
		expect(int(panel.cart.get(id, 0)) == 1, "shipping: A on ＋ adds one %s to the cart" % id)
		panel.confirm_button.grab_focus()
		await process_frame
		await tap(JOY_BUTTON_A)
		expect(panel.reviewing, "shipping: first A on 核對出貨 enters the review step (no sale yet)")
		var closes := [0]
		panel.close_requested.connect(func(): closes[0] += 1)
		await tap(JOY_BUTTON_B)
		gap("C2-ship-cancel", closes[0] > 0, "shipping panel: B (ui_cancel) does not request close")
	panel.queue_free()
	await process_frame

## Main scene: title -> world -> menus. Session is in-memory; nothing is hosted or saved.
func check_main_flow() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	await settle()
	# Title screen (menu visible, not playing).
	var title_focus := focus_owner()
	gap("C3-title-focus", title_focus is BaseButton and app.menu.is_ancestor_of(title_focus),
		"title: no button is focused on boot, so A does nothing until a mouse click")

	# Enter the world without hosting (same fixture as test_input_routing.gd).
	app.bindings.load_preferences("user://controller-focus-never-written-%d.cfg" % Time.get_ticks_usec())
	var world = World.new()
	world.add_player("tester", "島民")
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	app.session.world = world
	app.session.peers[1] = "tester"
	app.session.set_physics_process(false)
	if app.sound:
		app.sound.volume = 0.0
	app.playing = true
	app.menu.hide()
	app.hud.show()
	await settle()

	# Movement from the pad.
	Input.parse_input_event(joy_axis(JOY_AXIS_LEFT_X, 1.0))
	Input.parse_input_event(joy_button(JOY_BUTTON_DPAD_RIGHT, true))
	Input.flush_buffered_events()
	await process_frame
	gap("C1-move", app.movement_direction() != Vector2.ZERO,
		"world: left stick / d-pad do not move the player (movement_direction reads physical keys only)")
	Input.parse_input_event(joy_axis(JOY_AXIS_LEFT_X, 0.0))
	Input.parse_input_event(joy_button(JOY_BUTTON_DPAD_RIGHT, false))
	Input.flush_buffered_events()
	await process_frame

	# B in the world should open the pause menu like Escape.
	await tap(JOY_BUTTON_B)
	gap("C2-world-pause", app.modal != null, "world: B (ui_cancel) does not open the pause menu (Escape is keycode-only)")
	if app.modal != null:
		app._close_modal()
		await settle()

	# Menus reached by keyboard/mouse; probe initial focus and B-to-close for each.
	for entry in [["inventory", "_inventory"], ["pause", "_pause_menu"], ["settings", "_settings_menu"], ["build", "_build_menu"]]:
		var label: String = entry[0]
		app.call(entry[1])
		await settle(4)
		expect(app.modal != null, "%s: opens a modal" % label)
		if app.modal == null:
			continue
		var owner := focus_owner()
		var focused_inside: bool = owner != null and app.modal.is_ancestor_of(owner)
		if label == "inventory" and app.modal is InventoryPanel:
			expect(focused_inside, "inventory (grid): opens with a focused slot")
		else:
			gap("C3-%s-focus" % label, focused_inside, "%s: opens with no focused control" % label)
		expect(not app._world_keyboard_allowed(), "%s: modal blocks world input" % label)
		var opened = app.modal
		await tap(JOY_BUTTON_B)
		gap("C2-%s-cancel" % label, app.modal == null or app.modal != opened, "%s: B (ui_cancel) does not close the modal" % label)
		app._close_modal()
		await settle()
		expect(focus_owner() == null, "%s: closing releases GUI focus (world input resumes)" % label)

	app.playing = false
	app.life_panels.updates.clear()
	app.queue_free()
	await settle()
