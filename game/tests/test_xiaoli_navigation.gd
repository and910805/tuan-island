extends SceneTree

const World = preload("res://scripts/world.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text.begins_with(title):
		return node
	for child in node.get_children():
		var found := find_button(child, title)
		if found != null:
			return found
	return null

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	# Exercise navigation with a real isolated session. Opening modals stops
	# movement through Session, so a detached snapshot produces networking errors.
	var path:=OS.get_environment("TEMP").path_join("xiaoli-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var hosted:int=app.session.host(0,"島民",path)
	expect(hosted==OK,"isolated navigation session starts")
	if hosted!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.hud.show()
	app.sound.volume=0.0
	app.playing=true
	for resolution in [Vector2i(1024, 640), Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = resolution
		app._shop()
		await process_frame
		await process_frame
		var chat := find_button(app.modal, "和小栗聊聊")
		expect(chat != null and chat.is_visible_in_tree(), "shop has Xiao-Li dialogue at %s" % resolution)
		expect(find_button(app.modal, "買種子與材料") != null and find_button(app.modal, "出售") != null, "shop keeps both trading tabs")
		expect(root.get_visible_rect().encloses(app.modal.get_rect()), "shop stays in viewport")
		expect(app.modal.size.y <= 500, "shop remains a short catalog")
		if chat == null:
			continue
		chat.pressed.emit()
		var journal := find_button(app.modal, "打開島民手冊")
		expect(journal != null and find_button(app.modal, "交付這段委託") != null, "shop opens Xiao-Li's active quest")
		if journal == null:
			continue
		journal.pressed.emit()
		await process_frame
		await process_frame
		var bookmark := find_button(app.modal, "小栗")
		expect(bookmark != null and bookmark.icon != null, "journal lists Xiao-Li with the existing portrait")
		expect(bookmark != null and bookmark.button_pressed, "conversation opens the same resident in the journal")
		if bookmark != null:
			bookmark.pressed.emit()
			expect(find_button(app.modal, "目前委託") != null, "third bookmark opens the current chapter")
		app._close_modal()
		app._notice("小栗："+World.Village.QUESTS.xiaoli[3].line+"（鈴幣 +100，J 可重看）",true)
		await process_frame
		await process_frame
		expect(not app.toast.get_global_rect().intersects(app.selected_label.get_global_rect()),"long story reward does not overlap tool hint")
	app.playing=false
	app.life_panels.updates.clear()
	app.queue_free()
	await process_frame
	print("XIAOLI_NAVIGATION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
