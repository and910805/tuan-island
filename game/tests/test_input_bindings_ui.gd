extends SceneTree

const Bindings=preload("res://scripts/input_bindings.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
var app

func _initialize() -> void:
	call_deferred("run")

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func key(code:int) -> InputEventKey:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	return event

func run() -> void:
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.sound.volume=0
	var world:=World.new()
	world.add_player("bindings-ui","島民")
	app.session.world=world
	app.session.peers[1]="bindings-ui"
	app.session.snapshot=world.state
	app.session.own_id="bindings-ui"
	app._entered()
	var config:="user://input-bindings-ui-%d.cfg"%Time.get_ticks_usec()
	app.bindings.path=config
	app.bindings.keys=Bindings.DEFAULTS.duplicate()
	app._bindings_changed()
	for size in [Vector2i(1024,640),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=size
		app._bindings_menu()
		await process_frame
		await process_frame
		var panel=app.bindings_panel
		var viewport:=root.get_visible_rect()
		expect(viewport.encloses(app.modal.get_global_rect()),"Modal fits at %s"%size)
		expect(panel.values.size()==Bindings.DEFAULTS.size(),"All binding actions have rows")
		for category in Bindings.GROUPS:
			panel.category_buttons[category].pressed.emit()
			await process_frame
			for id in Bindings.GROUPS[category]:
				expect(panel.values[id].is_visible_in_tree(),"Category exposes "+id)
		panel.category_buttons["工具"].pressed.emit()
		panel.begin_capture("area_modifier")
		var ctrl_chord := key(KEY_CTRL)
		ctrl_chord.ctrl_pressed = true
		ctrl_chord.shift_pressed = true
		expect(panel.capture_event(ctrl_chord) and app.bindings.keys.area_modifier == KEY_SHIFT and panel.capturing == "area_modifier", "Shift+Ctrl is rejected during modifier capture")
		var alt_chord := key(KEY_ALT)
		alt_chord.alt_pressed = true
		alt_chord.meta_pressed = true
		expect(panel.capture_event(alt_chord) and app.bindings.keys.area_modifier == KEY_SHIFT and panel.capturing == "area_modifier", "Meta+Alt is rejected during modifier capture")
		ctrl_chord.shift_pressed = false
		expect(panel.capture_event(ctrl_chord) and app.bindings.keys.area_modifier == KEY_CTRL and panel.capturing.is_empty(), "A bare Ctrl press still binds the area modifier")
		panel.finish(app.bindings.restore_defaults())
		panel.begin_capture("hoe")
		expect(panel.capture_event(key(KEY_F12)),"F12 capture consumed")
		var hoe:Button
		for node in app.hud.find_children("*","Button",true,false):
			if node.get_meta("binding_action","")=="hoe":hoe=node;break
		expect(hoe!=null and hoe.tooltip_text.contains("F12"),"HUD exposes complete F12 name")
		panel.begin_capture("hoe")
		expect(panel.capture_event(key(KEY_BACKSLASH)),"Backslash capture consumed")
		expect(hoe.get_node("KeyBadge").get_global_rect().end.x<=hoe.get_global_rect().end.x,"Key badge fits inside tool")
		expect(hoe.tooltip_text.contains(app.binding_label("hoe")),"Tooltip uses full key label")
		panel.finish(app.bindings.clear("hoe"))
		expect(hoe.get_node("KeyBadge").text=="—","Cleared HUD key shows dash")
		panel.finish(app.bindings.restore_defaults())
		panel.begin_capture("hoe")
		expect(panel.capture_event(key(KEY_E)) and panel.confirm_row.visible,"Conflict opens confirmation without transfer")
		await process_frame
		await process_frame
		expect(root.gui_get_focus_owner()==panel.transfer_button,"Conflict focuses transfer for keyboard input")
		expect(not panel.capture_event(key(KEY_ENTER)) and not panel.capture_event(key(KEY_TAB)),"Confirmation forwards Enter and Tab to GUI")
		var scroll:Control=app.modal.find_child("ModalScroll",true,false)
		expect(scroll.get_global_rect().encloses(panel.notice.get_global_rect()) and scroll.get_global_rect().encloses(panel.confirm_row.get_global_rect()),"Notice and confirmation are visible")
		panel.transfer_button.pressed.emit()
		expect(app.bindings.keys.hoe==KEY_E and app.bindings.keys.interact==KEY_NONE,"Explicit transfer applies once")
		panel.finish(app.bindings.restore_defaults())
		app._close_modal()
		await process_frame
	app.playing=false
	app.session.world=null
	app.queue_free()
	await process_frame
	if FileAccess.file_exists(config):DirAccess.remove_absolute(config)
	if FileAccess.file_exists(config+".bak"):DirAccess.remove_absolute(config+".bak")
	print("INPUT_BINDINGS_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
