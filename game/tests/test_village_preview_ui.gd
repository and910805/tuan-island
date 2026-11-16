extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func run() -> void:
	create_timer(5.0).timeout.connect(func(): quit(1))
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.sound.volume = 0.0
	var world = preload("res://scripts/world.gd").new()
	world.add_player("preview-test", "島民")
	main.session.snapshot = world.state
	main.session.own_id = "preview-test"
	main._entered()
	main._refresh_hud()
	await process_frame
	await process_frame
	expect(main.village_art_preview, "command-line flag enables preview")
	expect(main.view.get("village_art_preview") == true, "preview flag forwarded to village renderer")
	expect(main.tool_buttons.size() == 8, "all eight toolbar tools available")
	expect(main.status_label.text.contains("第 1 日"), "date visible")
	expect(main.inventory_label == null, "resource summary stays inside backpack")
	expect(main._world_pointer_allowed(Vector2(180, 365)), "old left HUD area available to tools")
	expect(main._world_pointer_allowed(Vector2(640, 58)), "open space above village can be targeted")
	expect(not main._world_pointer_allowed(Vector2(-1, 10)), "outside viewport cannot be targeted")
	for control in main.preview_controls:
		if control.is_visible_in_tree():
			expect(not main._world_pointer_allowed(control.get_global_rect().get_center()), "visible HUD control blocks targeting")
			expect(root.get_visible_rect().encloses(control.get_global_rect()), "visible HUD control fits the viewport: %s" % control.get_global_rect())
	var toggle: Button
	for control in main.preview_controls:
		for button in control.find_children("*", "Button", true, false):
			if button.text.begins_with("島上的小心願"):
				toggle = button
	var tracker_point: Vector2 = main.objective.get_global_rect().end - Vector2(8, 4)
	expect(main.objective.visible and main.objective.text.contains("渡口修繕") and main.objective.text.contains("木 0/30"), "tracker shows real current goals")
	expect(toggle != null, "quest tracker toggle present")
	if toggle != null:
		toggle.pressed.emit()
		await process_frame
		await process_frame
		expect(not main.objective.visible and main._world_pointer_allowed(tracker_point), "collapsed tracker releases the objective footprint")
		toggle.pressed.emit()
		await process_frame
		expect(main.objective.visible and not main._world_pointer_allowed(tracker_point), "expanded tracker blocks its own footprint")
	main._inventory()
	expect(main.modal != null and not main._world_pointer_allowed(Vector2(640, 400)), "modal suppresses targeting")
	main._close_modal()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = main.tool_buttons[0].get_global_rect().get_center()
	main.area_drag = true
	main._input(release)
	expect(not main.area_drag and main.toast.text.contains("沒有扣除材料"), "drag release on toolbar cancels construction")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.physical_keycode = KEY_F
	key.pressed = true
	main._unhandled_input(key)
	expect(main.selected == "fish", "fish shortcut retained")
	main.playing = false
	main.queue_free()
	await process_frame
	print("VILLAGE_PREVIEW_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
