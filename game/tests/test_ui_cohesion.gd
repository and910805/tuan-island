extends SceneTree

const World = preload("res://scripts/world.gd")
var app
var world: World
var checks := 0
var failures := 0
const PLAYER := "cohesion"

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, context: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + context)

func frames() -> void:
	await process_frame
	await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	var previous: Control = app.modal
	app._input(event)
	if app.modal == previous:
		app._unhandled_input(event)

func find_button(text: String) -> Button:
	if not is_instance_valid(app.modal):
		return null
	for control in app.modal.find_children("*", "Button", true, false):
		if control.is_visible_in_tree() and (control.text.begins_with(text) or control.tooltip_text.begins_with(text)):
			return control
	return null

func has_text(text: String) -> bool:
	if not is_instance_valid(app.modal):
		return false
	for label in app.modal.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text.contains(text):
			return true
	return false

func check_modal(name: String, viewport: Rect2, close_after:bool=true) -> void:
	var panel: Control = app.modal
	expect(is_instance_valid(panel), name + " opened")
	if not is_instance_valid(panel):
		return
	var rect := panel.get_global_rect()
	expect(viewport.encloses(rect), "%s fits %s: %s" % [name, viewport, rect])
	expect(not app._world_pointer_allowed(viewport.get_center()), name + " blocks world targeting")
	for scroll in panel.find_children("*", "ScrollContainer", true, false):
		if scroll.is_visible_in_tree():
			expect(rect.encloses(scroll.get_global_rect()), name + " scroll is within its panel")
	if name in ["_journal", "_resident_menu"]:
		var materials := 0
		for item in get_nodes_in_group("quest_material_text"):
			if panel.is_ancestor_of(item) and item.is_visible_in_tree():
				materials += 1
				var width:float=item.get_theme_font("font").get_string_size(item.text,
					HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x
				expect(item.get_line_count()==1 and item.size.x>=width,
					name + " material text fits on one line: " + item.text)
		expect(materials>0, name + " shows current quest materials")
	if name=="_orders_menu":
		var scrolls:=panel.find_children("*","ScrollContainer",true,false)
		var actions:=0
		for button in panel.find_children("*","Button",true,false):
			if button.text=="交件":
				actions+=1
				expect(not scrolls.is_empty() and scrolls[0].get_global_rect().encloses(button.get_global_rect()),
					"order delivery visible without scrolling")
		expect(actions==3,"three daily orders show delivery actions")
	if name=="_resident_menu":
		var deliver:=find_button("交付這段委託")
		var scrolls:=panel.find_children("*","ScrollContainer",true,false)
		expect(deliver!=null and not scrolls.is_empty() and scrolls[0].get_global_rect().encloses(deliver.get_global_rect()),
			"resident delivery is visible without scrolling")
	if close_after:
		key(KEY_ESCAPE)
		await frames()
		expect(app.modal == null and app._world_pointer_allowed(viewport.get_center()), name + " closes and restores targeting")

func check_pause() -> void:
	for entry in [
		["島嶼地圖", "周邊地圖"], ["島民手帳", "島民手冊"], ["生活收藏", "小島生活圖鑑"],
		["風鈴接力", "風鈴接力"], ["作物種子", "選擇種子"], ["舒適設定", "讓自己舒服一點"],
		["共同工程", "渡口的共同工程"], ["操作指南", "第一天的口袋指南"],
	]:
		key(KEY_ESCAPE)
		await frames()
		var button := find_button(entry[0])
		expect(button != null and not button.disabled, "pause offers " + entry[0])
		if button != null:
			button.pressed.emit()
			await frames()
			expect(has_text(entry[1]), "pause opens " + entry[1])
		key(KEY_ESCAPE)
		await frames()
	key(KEY_ESCAPE)
	await frames()
	var fish := find_button("拿起釣竿")
	expect(fish != null, "pause offers fishing")
	if fish != null:
		fish.pressed.emit()
		expect(app.modal == null and app.selected == "fish", "pause equips fishing and returns to the world")
	key(KEY_ESCAPE)
	await frames()
	expect(find_button("迷路了？回到渡口") != null, "pause offers rescue")
	expect(find_button("儲存今天 · 離開小島") != null, "pause offers save and exit")
	key(KEY_ESCAPE)
	await frames()

func check_journal() -> void:
	world.state.players[PLAYER].stories = {"aru": 2, "milu": 1}
	app._journal()
	await frames()
	var memory := find_button("回憶 1")
	expect(memory != null, "completed Aru memory has an entry")
	if memory != null:
		memory.pressed.emit()
		await frames()
		expect(has_text(World.Village.QUESTS.aru[0].line), "Aru completed story can be reread")
	var milu := find_button("米露")
	expect(milu != null, "journal offers Milu bookmark")
	if milu != null:
		milu.pressed.emit()
		await frames()
		expect(has_text(World.Village.QUESTS.milu[1].title), "changing resident shows current Milu delivery")
		var milu_memory := find_button("回憶 1")
		if milu_memory != null:
			milu_memory.pressed.emit()
			await frames()
		expect(has_text(World.Village.QUESTS.milu[0].line), "Milu completed story remains readable")
	key(KEY_ESCAPE)
	await frames()
	app._resident_menu("milu")
	await frames()
	expect(find_button("交付這段委託") != null, "resident still offers delivery")
	key(KEY_ESCAPE)
	await frames()

func run() -> void:
	create_timer(12.0).timeout.connect(func(): quit(1))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	expect(app.village_art_preview, "finished illustrated UI is enabled by default in the game")
	app.set_process(false)
	app.sound.volume = 0.0
	world = World.new()
	world.add_player(PLAYER, "測試島民")
	app.session.snapshot = world.state
	app.session.world = world
	app.session.set_physics_process(false)
	app.session.own_id = PLAYER
	app.session.peers[1] = app.session.own_id
	app._entered()
	app._refresh_hud()
	for size in [Vector2i(1024,640), Vector2i(1280,720), Vector2i(1280,800), Vector2i(1920,1080)]:
		root.content_scale_size = size
		root.size = size
		await frames()
		var viewport := root.get_visible_rect()
		expect(Vector2i(viewport.size) == size, "logical viewport matches " + str(size))
		for entry in [
			["_pause_menu", []], ["_build_menu", []], ["_seed_menu", []], ["_shop", []],
			["_board", []], ["_resident_menu", ["aru"]], ["_journal", []], ["_collection_menu", []],
			["_festival_menu", []], ["_animal_menu", []], ["_orders_menu", []], ["_settings_menu", []],
			["_map_menu", []], ["_help", []], ["_quarry_menu", []],
		]:
			app.callv(entry[0], entry[1])
			await frames()
			await check_modal(entry[0], viewport)
		for control in [app.preview_toolbar, app.preview_top, app.selected_label, app.preview_tracker]:
			if is_instance_valid(control) and control.is_visible_in_tree():
				expect(viewport.encloses(control.get_global_rect()), "HUD control stays in %s: %s" % [size, control.name])
	for reduced in [false, true]:
		app.sound.reduced_motion = reduced
		app.preview_tracker.visible = true
		key(KEY_TAB)
		await frames()
		expect(app.modal != null and not app.preview_tracker.visible, "inventory hides tracker, motion reduced=" + str(reduced))
		if app.modal != null:await check_modal("_inventory", root.get_visible_rect(),false)
		key(KEY_TAB if reduced else KEY_ESCAPE)
		await frames()
		expect(app.modal == null and app.preview_tracker.visible, "close restores tracker, motion reduced=" + str(reduced))
		key(KEY_3)
		expect(app.selected == "water", "tool input works after close")
	await check_pause()
	await check_journal()
	app.playing = false
	app.queue_free()
	await process_frame
	print("UI_COHESION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

