extends SceneTree

const World = preload("res://scripts/world.gd")
var app
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func key(code: int, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	return event

# Native Windows event shape observed by root: keycode=KEY_5 (53), physical_keycode=4194313.
const NATIVE_PHYSICAL := 4194313

func native(code: int, physical: int, is_pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = physical
	event.pressed = is_pressed
	return event

func feed(events: Array) -> void:
	for event in events:
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.playing = true
	app.hud.show()
	app.menu.hide()
	var world = World.new()
	world.add_player("tester", "島民")
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	app.session.world = world
	app.session.peers[1] = "tester"
	app.session.set_physics_process(false)
	var path := "user://input-routing-%d.cfg" % Time.get_ticks_usec()
	app.bindings.load_preferences(path)
	expect(app.bindings.rebind("inventory", KEY_Q).ok and app.bindings.rebind("map", KEY_H).ok, "test binds new inventory and map keys")
	app._unhandled_input(key(KEY_TAB))
	expect(app.modal == null, "old inventory key does not open")
	app._unhandled_input(key(KEY_Q))
	expect(app.modal != null, "new inventory key opens")
	var inventory = app.modal
	app._input(key(KEY_TAB))
	expect(app.modal == inventory, "old key can navigate GUI without closing re-bound inventory")
	app._unhandled_input(key(KEY_8))
	expect(app.selected != "remove", "inventory blocks tool shortcuts")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(640, 400)
	app.view.show_target = true
	app._select_tool("build")
	app._unhandled_input(click)
	expect(not app.area_drag and app.action_clock == 0, "modal blocks terrain clicks before tool dispatch")
	app._input(key(KEY_Q))
	expect(app.modal == null, "new inventory key closes before GUI routing")
	app._unhandled_input(key(KEY_Q))
	app._input(key(KEY_ESCAPE))
	expect(app.modal == null, "Escape still closes the re-bound inventory")
	app._unhandled_input(key(KEY_M))
	expect(app.modal == null, "old map key does not open")
	app._unhandled_input(key(KEY_H))
	expect(is_instance_valid(app.map_view), "new map key opens")
	app._unhandled_input(key(KEY_H))
	expect(app.modal == null, "new map key closes")
	app._unhandled_input(key(KEY_H, true))
	expect(app.modal == null, "system shortcut chord does not open map")
	app._bindings_menu()
	var panel = app.bindings_panel
	panel.begin_capture("interact")
	app._input(key(KEY_8))
	expect(app.selected == "build" and panel.pending_key == KEY_8, "capture consumes tool key and presents conflict")
	app._input(key(KEY_ESCAPE))
	expect(app.modal != null and panel.capturing.is_empty(), "first Escape cancels capture only")
	app._input(key(KEY_ESCAPE))
	expect(app.modal == null, "second Escape closes settings")
	var field := LineEdit.new()
	app.hud.add_child(field)
	field.grab_focus()
	app._unhandled_input(key(KEY_8))
	expect(not app._world_keyboard_allowed() and app.selected == "build", "text focus blocks tool shortcuts")
	field.release_focus()
	field.queue_free()
	expect(app.bindings.rebind("move_up", KEY_UP).ok and app.bindings.rebind("area_modifier", KEY_CTRL).ok,
		"movement arrow and area modifier can be rebound")
	var old_up := key(KEY_W)
	Input.parse_input_event(old_up)
	Input.flush_buffered_events()
	expect(app.movement_direction() == Vector2.ZERO, "old W does not move after rebinding")
	var old_release := key(KEY_W)
	old_release.pressed = false
	Input.parse_input_event(old_release)
	var arrow := key(KEY_UP)
	Input.parse_input_event(arrow)
	Input.flush_buffered_events()
	await process_frame
	expect(app.movement_direction() == Vector2.UP, "rebound direction is read from physical input")
	app._inventory()
	expect(app.movement_direction() == Vector2.ZERO, "modal blocks held movement")
	app._close_modal()
	var release := key(KEY_UP)
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	# Held movement uses the same identity as discrete input: logical keycode, physical only as fallback.
	expect(app.bindings.rebind("move_up", KEY_W).ok, "default W restored for native held movement")
	await feed([native(KEY_W, NATIVE_PHYSICAL)])
	expect(app.movement_direction() == Vector2.UP, "native W with an unrelated physical code moves up while held")
	await feed([native(KEY_Y, KEY_S)])
	expect(app.movement_direction() == Vector2.UP, "a key labelled Y at the physical S position does not also move down")
	await feed([native(KEY_W, NATIVE_PHYSICAL, false), native(KEY_Y, KEY_S, false)])
	expect(app.movement_direction() == Vector2.ZERO, "native release stops movement")
	for step in [[KEY_A, Vector2.LEFT], [KEY_S, Vector2.DOWN], [KEY_D, Vector2.RIGHT]]:
		await feed([native(step[0], NATIVE_PHYSICAL)])
		expect(app.movement_direction() == step[1], "native %s moves while held" % OS.get_keycode_string(step[0]))
		await feed([native(step[0], NATIVE_PHYSICAL, false)])
		expect(app.movement_direction() == Vector2.ZERO, "native %s release stops" % OS.get_keycode_string(step[0]))
	await feed([native(KEY_NONE, KEY_D)])
	expect(app.movement_direction() == Vector2.RIGHT, "event without a logical keycode falls back to its physical key")
	await feed([native(KEY_NONE, KEY_D, false)])
	expect(app.movement_direction() == Vector2.ZERO, "physical-only release stops movement")
	var move_conflict: Dictionary = app.bindings.rebind("move_left", KEY_J)
	expect(not move_conflict.ok and move_conflict.get("conflict", "") == "journal", "movement rebinding keeps conflict detection")
	expect(app.bindings.rebind("move_left", KEY_K).ok and app.binding_label("move_left") == "K", "movement rebinding shows its label")
	await feed([native(KEY_A, KEY_K)])
	expect(app.movement_direction() == Vector2.ZERO, "old label A no longer moves, even at the physical K position")
	await feed([native(KEY_A, KEY_K, false), native(KEY_K, KEY_A)])
	expect(app.movement_direction() == Vector2.LEFT, "rebound label K moves left wherever it sits physically")
	await feed([native(KEY_K, KEY_A, false)])
	expect(app.movement_direction() == Vector2.ZERO, "rebound key release stops movement")
	var reloaded = load("res://scripts/input_bindings.gd").new()
	expect(reloaded.load_preferences(path) and reloaded.keys == app.bindings.keys, "rebound movement survives reload")
	expect(app.bindings.rebind("move_left", KEY_A).ok, "default A restored")
	var stick:=InputEventJoypadMotion.new()
	stick.device=7
	stick.axis=JOY_AXIS_LEFT_X
	stick.axis_value=0.1
	app._input(stick)
	expect(app.movement_direction()==Vector2.ZERO,"Stick drift is ignored")
	stick.axis_value=0.75
	app._input(stick)
	expect(app.movement_direction().x>0.6 and app.movement_direction().x<0.75,"Stick moves with scaled analog magnitude")
	app._inventory()
	expect(app.movement_direction()==Vector2.ZERO,"Inventory blocks stick movement")
	var back:=InputEventJoypadButton.new()
	back.button_index=JOY_BUTTON_B
	back.pressed=true
	app._input(back)
	expect(app.modal==null,"Controller back closes inventory")
	app._controller_connection_changed(7,false)
	expect(app.movement_direction()==Vector2.ZERO,"Disconnect clears latched direction")
	var direction:=InputEventJoypadButton.new()
	direction.button_index=JOY_BUTTON_DPAD_RIGHT
	direction.pressed=true
	var target_before:Vector2i=app._controller_target()
	app._input(direction)
	expect(app.controller_aim and app._controller_target()==target_before+Vector2i.RIGHT,"D-pad moves the active tool target")
	direction.button_index=JOY_BUTTON_Y
	app._input(direction)
	expect(app.modal!=null,"Y opens construction catalog without mouse")
	await process_frame
	var focused:Control=app.get_viewport().gui_get_focus_owner()
	expect(focused is BaseButton and app.modal.is_ancestor_of(focused),"Controller-opened construction catalog assigns focus")
	app._input(back)
	expect(app.modal==null,"B returns from construction catalog")
	click.ctrl_pressed = true
	app._unhandled_input(click)
	expect(app.area_drag, "rebound held Ctrl starts an area drag")
	app._input(key(KEY_ESCAPE))
	expect(not app.area_drag and app.modal == null, "Escape cancels drag before opening a menu")
	expect(app.bindings.rebind("interact", KEY_Q, true).ok and app.bindings.rebind("harvest_area", KEY_E).ok,
		"interaction and harvesting can swap their physical keys")
	expect(app._display_notice("再按 {harvest_area}") == "再按 E", "expanded harvest key is never remapped as interaction")
	expect(app._display_notice("走到金色風鈴身邊，再按 E 接住") == "走到金色風鈴身邊，再按 Q 接住",
		"legacy server interaction text uses the rebound physical key")
	app.session.sequences[1]=0
	app.session.rates[1]=[]
	world.state.players.tester.inventory.wood=20
	world.state.players.tester.x=39.5
	world.state.players.tester.y=34.5
	app.controller_offset=Vector2i.ZERO
	app.action_clock=0
	var pad:=InputEventJoypadButton.new()
	pad.pressed=true
	pad.button_index=JOY_BUTTON_Y
	app._input(pad)
	await process_frame
	app._input(pad)
	var place:Control=app.get_viewport().gui_get_focus_owner()
	expect(place!=null and place.name=="BuildPlace","Second Y focuses the recipe confirmation")
	pad=InputEventJoypadButton.new()
	pad.button_index=JOY_BUTTON_A
	pad.pressed=true
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	await process_frame
	pad=InputEventJoypadButton.new()
	pad.button_index=JOY_BUTTON_A
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	await process_frame
	expect(app.modal==null and app.selected=="build","Controller A selects the floor recipe")
	pad.button_index=JOY_BUTTON_DPAD_RIGHT
	pad.pressed=true
	app._input(pad)
	pad.button_index=JOY_BUTTON_X
	app._input(pad)
	expect(world.state.ground.get("40,34",{}).get("type")=="floor","Controller X places a floor through the local session")
	pad.button_index=JOY_BUTTON_DPAD_DOWN
	app._input(pad)
	pad.button_index=JOY_BUTTON_RIGHT_STICK
	app._input(pad)
	expect(app.area_drag and app.area_start==Vector2i(40,35),"Right stick press marks the first construction tile")
	pad.button_index=JOY_BUTTON_DPAD_RIGHT
	app._input(pad)
	app.action_clock=0
	pad.button_index=JOY_BUTTON_X
	app._input(pad)
	expect(not app.area_drag and world.state.ground.has("40,35") and world.state.ground.has("41,35"),"Controller confirms two-tile construction")
	# T017: default hand-tool keys 5/6 and LB/RB cycling follow the toolbar order (synthetic events, not native play).
	app._unhandled_input(key(KEY_5))
	expect(app.selected=="axe","Key 5 selects the axe")
	app._unhandled_input(key(KEY_6))
	expect(app.selected=="pick","Key 6 selects the pick")
	app._unhandled_input(native(KEY_5, NATIVE_PHYSICAL))
	expect(app.selected=="axe","Native Windows 5 (physical 4194313) selects the axe")
	app._unhandled_input(native(KEY_6, NATIVE_PHYSICAL, false))
	expect(app.selected=="axe","Native key release does not switch tools")
	app.view.zoom=2.0
	var zoom_before:float=app.view.zoom
	app._unhandled_input(native(KEY_Z, KEY_8))
	expect(app.selected=="axe" and app.view.zoom!=zoom_before,"Labelled Z at the physical 8 position zooms without selecting remove")
	app._unhandled_input(native(KEY_Z, KEY_8))
	expect(app.view.zoom==zoom_before,"Second Z restores the zoom")
	app._select_tool("hoe")
	pad.button_index=JOY_BUTTON_RIGHT_SHOULDER
	app._input(pad)
	expect(app.selected=="seed","RB selects the next toolbar tool")
	app._select_tool("hoe")
	pad.button_index=JOY_BUTTON_LEFT_SHOULDER
	app._input(pad)
	expect(app.selected=="move_object","LB wraps from hoe to the last cycled tool")
	expect(not app.controller_tool_cycle().has("till_area") and not app.controller_tool_cycle().has("harvest_area"),"Unowned machines are skipped by LB/RB")
	world.state.players.tester.inventory["tiller"]=1
	world.state.players.tester.inventory["harvester"]=1
	app.session.own_id="tester"
	app.session.snapshot=world.state
	app._select_tool("fish")
	pad.button_index=JOY_BUTTON_RIGHT_SHOULDER
	app._input(pad)
	expect(app.selected=="till_area","RB reaches an owned tiller after the fishing rod")
	app._input(pad)
	expect(app.selected=="harvest_area","RB skips the unowned seeder and reaches the owned harvester")
	app._input(pad)
	expect(app.selected=="move_object","RB continues past the machines")
	pad.button_index=JOY_BUTTON_LEFT_SHOULDER
	app._input(pad)
	expect(app.selected=="harvest_area","LB steps back onto the owned harvester")
	world.state.players.tester.inventory.erase("tiller")
	world.state.players.tester.inventory.erase("harvester")
	app.session.own_id="tester"
	app.session.snapshot=world.state
	app._select_tool("build")
	pad.button_index=JOY_BUTTON_START
	app._input(pad)
	await process_frame
	await process_frame
	for direction_index in [JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]:
		pad.button_index=direction_index
		app._input(pad)
	var comfort_focus:Control=root.gui_get_focus_owner()
	expect(comfort_focus!=null and comfort_focus.name=="PauseComfort","D-pad reaches comfort settings in the pause menu")
	pad.button_index=JOY_BUTTON_A
	app._input(pad)
	await process_frame
	var motion:CheckBox
	for box:CheckBox in app.modal.find_children("*","CheckBox",true,false):
		if box.text.contains("減少"):
			motion=box
			break
	expect(motion!=null,"Settings exposes reduced motion")
	if motion!=null:
		pad.button_index=JOY_BUTTON_DPAD_DOWN
		for step in range(8):
			if root.gui_get_focus_owner()==motion:break
			app._input(pad)
		expect(root.gui_get_focus_owner()==motion,"D-pad reaches reduced motion")
		var initial:=motion.button_pressed
		pad.button_index=JOY_BUTTON_A
		app._input(pad)
		expect(motion.button_pressed!=initial,"Controller A toggles the focused comfort option")
		var settings_path:String=app.arg_value("settings","")
		if not settings_path.is_empty():
			var save_button:=app.modal.find_child("SaveComfort",true,false) as Button
			expect(save_button!=null,"Comfort settings expose a focusable save button")
			if save_button!=null:
				pad.button_index=JOY_BUTTON_DPAD_DOWN
				for step in range(12):
					if root.gui_get_focus_owner()==save_button:break
					app._input(pad)
				expect(root.gui_get_focus_owner()==save_button,"D-pad reaches save")
				pad.button_index=JOY_BUTTON_A
				app._input(pad)
				var saved:=ConfigFile.new()
				expect(saved.load(settings_path)==OK and saved.get_value("comfort","reduced_motion",initial)==not initial,"Controller A saves the changed comfort preference")
				expect(app.view.reduced_motion==not initial,"Saved motion setting is applied immediately")
	app._input(back)
	expect(app.modal==null,"Controller B closes comfort settings")
	app.playing = false
	DirAccess.remove_absolute(path)
	app.queue_free()
	await process_frame
	print("INPUT_ROUTING_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
