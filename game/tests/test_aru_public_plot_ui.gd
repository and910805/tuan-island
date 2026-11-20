extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.24).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func node(id:String) -> Node:
	return app.find_child(id,true,false)

## Bounded wait on real frames; never loops forever.
func wait_until(done:Callable,max_frames:=180) -> bool:
	for i in max_frames:
		if done.call():return true
		await process_frame
	return done.call()

func press_any(id:String) -> void:
	await wait_until(func():return node(id)!=null,60)
	var target:=node(id) as Button
	expect(target!=null,"Found "+id)
	if target==null:return
	await wait_until(func():return not target.disabled,120)
	expect(not target.disabled,"Enabled action: "+id)
	if not target.disabled:target.pressed.emit()
	await process_frame
	await process_frame

func open_preview() -> void:
	if node("AruParkPhotoPreview")==null:await press("AruParkPhoto")
	await wait_until(func():
		var rect:=node("AruParkPhotoPreview") as TextureRect
		return rect!=null and rect.texture!=null,120)
	await process_frame
	await process_frame

func preview_image() -> Image:
	var rect:=node("AruParkPhotoPreview") as TextureRect
	return rect.texture.get_image() if rect!=null and rect.texture!=null else null

func check_preview(label:String,windowed:bool) -> void:
	var rect:=node("AruParkPhotoPreview") as TextureRect
	expect(rect!=null,"Preview TextureRect exists at "+label)
	expect(node("AruParkPhotoConfirm") is Button and node("AruParkPhotoCancel") is Button,"Confirm and cancel exist at "+label)
	if rect==null:return
	var view:=Rect2(Vector2.ZERO,Vector2(root.size))
	for id in ["AruParkPhotoPreview","AruParkPhotoConfirm","AruParkPhotoCancel"]:
		var control:=node(id) as Control
		if control!=null:expect(view.encloses(control.get_global_rect()),"%s fits %s"%[id,label])
	if not windowed:return
	await RenderingServer.frame_post_draw
	var image:=preview_image()
	expect(image!=null and not image.is_empty(),"Preview shows a real image at "+label)
	if image==null or image.is_empty():return
	var colors:={}
	for sx in 16:
		for sy in 16:
			colors[image.get_pixel(sx*image.get_width()/16,sy*image.get_height()/16).to_html(false)]=true
	expect(colors.size()>=6,"Preview is the rendered scene, not a blank fill (%d colors)"%colors.size())
	var live:=root.get_texture().get_image()
	expect(not (live.get_size()==image.get_size() and live.get_data()==image.get_data()),"Preview is not a HUD screenshot")

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://aru-public-bench-test-%d.json"%OS.get_process_id()
	app.session.profile.token="aru-public-bench-test-%d"%OS.get_process_id()
	if app.session.host(0,"渡口島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var tile:=Goals.ARU_PARK_VIEW
	stand(tile)
	expect(not world.act(token,"locked",Goals.ARU_PARK_PLACE,Goals.ARU_PARK_SLOTS.lamp,"lamp").ok,"Friendship gates the shared plot")
	person.bonds={"aru":{"points":24,"talk_day":-1,"gift_day":-1}}
	person.stories.aru=2
	person.inventory.wood=100
	person.inventory.fiber=100
	person.inventory.stone=100
	stand(tile)
	expect(not world.act(token,"early-photo",Goals.ARU_PARK_PHOTO,tile).ok,"Cannot photograph unfinished plot")
	expect(not world.act(token,"ordinary-build", "build",Goals.ARU_PARK_SLOTS.lamp,"lamp").ok,"Ordinary building respects the reserved plot")
	app._interact()
	await process_frame
	expect(button("AruParkPhoto")==null,"Photo option waits for furniture")
	await press("AruParkPlace_long_bench")
	expect(Goals.aru_park_has(app.session.snapshot.objects,"long_bench"),"Public bench is placed from the marker")
	var friend:="aru-second-decorator"
	world.add_player(friend,"訪客")
	var guest:Dictionary=world.state.players[friend]
	guest.bonds={"aru":{"points":24,"talk_day":-1,"gift_day":-1}}
	guest.x=person.x
	guest.y=person.y
	expect(world.act(friend,"shared-lamp",Goals.ARU_PARK_PLACE,Goals.ARU_PARK_SLOTS.lamp,"lamp").ok,"Another islander can place the lamp")
	expect(not world.act(friend,"move-donation","move_object",Goals.ARU_PARK_SLOTS.lamp,"37,34").ok,"A donated lamp cannot be moved")
	expect(not world.act(token,"remove-donation","remove",Goals.ARU_PARK_SLOTS.long_bench).ok,"The donor cannot remove a public bench")
	var bench:Vector2i=Goals.ARU_PARK_SLOTS.long_bench
	Tasks.aru_inscription(app,bench,app.session.snapshot.objects[World.key(bench)])
	await press("AruParkBenchSit")
	expect(person.get(Goals.MASTER_BENCH_SEAT,{}).get("cell","")==World.key(bench),"The public bench offers a working Sit action")
	app._interact()
	await process_frame
	expect(not person.has(Goals.MASTER_BENCH_SEAT),"The normal interact key stands up")
	stand(tile)
	app._interact()
	await process_frame
	await capture("01-public-plot.png")
	var photo:=Tasks.aru_photo_path(app)
	var windowed:=DisplayServer.get_name()!="headless"
	var started:=Time.get_ticks_msec()
	# First photograph: preview, then cancel. Nothing may be written or flagged.
	await open_preview()
	await check_preview("1024x640",windowed)
	expect(not FileAccess.file_exists(photo),"Preview alone writes no file")
	expect(not person.has(Goals.ARU_PHOTO_KEY),"Preview alone gives no quest progress")
	await capture("02-preview-1024x640.png")
	await press_any("AruParkPhotoCancel")
	expect(node("AruParkPhotoPreview")==null,"Cancel closes the preview")
	expect(not FileAccess.file_exists(photo),"Cancel before the first photograph writes no file")
	expect(not person.has(Goals.ARU_PHOTO_KEY),"Cancel before the first photograph sets no flag")
	# First photograph: confirm.
	stand(tile)
	app._interact()
	await process_frame
	await open_preview()
	var shown:=preview_image()
	await press_any("AruParkPhotoConfirm")
	await wait_until(func():return FileAccess.file_exists(photo) and person.get(Goals.ARU_PHOTO_KEY,false)==true)
	expect(FileAccess.file_exists(photo),"A real PNG is saved on the player device after confirm")
	expect(person.get(Goals.ARU_PHOTO_KEY,false) and not guest.has(Goals.ARU_PHOTO_KEY),"Only the photographer earns progress")
	var saved:=PackedByteArray()
	if FileAccess.file_exists(photo):
		var disk:=Image.load_from_file(photo)
		expect(disk!=null and not disk.is_empty(),"Saved file is a decodable image")
		if windowed and disk!=null and shown!=null and not shown.is_empty():
			disk.convert(shown.get_format())
			expect(disk.get_size()==shown.get_size() and disk.get_data()==shown.get_data(),"Saved album is the image that was previewed")
		saved=FileAccess.get_file_as_bytes(photo)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--capture-dir="):
				var out:=arg.trim_prefix("--capture-dir=").path_join("02-island-photo.png")
				expect(disk.save_png(out)==OK,"Keep the player photo as test evidence")
	# Reshoot then cancel: the saved PNG must be untouched.
	stand(tile)
	app._interact()
	await process_frame
	await open_preview()
	await press_any("AruParkPhotoCancel")
	expect(FileAccess.get_file_as_bytes(photo)==saved,"Cancelled reshoot preserves the saved PNG")
	expect(person.get(Goals.ARU_PHOTO_KEY,false)==true,"Cancelled reshoot keeps quest progress")
	# Server refusal while the preview is open: move far away on the server only.
	var home:=Vector2(person.x,person.y)
	person.x=2.5
	person.y=2.5
	var refused:bool=not world.act(token,"refusal-probe",Goals.ARU_PARK_PHOTO,Goals.ARU_PARK_VIEW).ok
	person.x=home.x
	person.y=home.y
	if refused:
		stand(tile)
		app._interact()
		await process_frame
		await open_preview()
		person.x=2.5
		person.y=2.5
		await press_any("AruParkPhotoConfirm")
		await wait_until(func():return false,30)
		expect(FileAccess.get_file_as_bytes(photo)==saved,"Server refusal keeps the previous album")
		person.x=home.x
		person.y=home.y
		if node("AruParkPhotoCancel")!=null:await press_any("AruParkPhotoCancel")
	else:
		print("ARU_PUBLIC_PLOT_UI note: server accepts photo from afar; refusal case skipped")
	stand(tile)
	if "--wide" in OS.get_cmdline_user_args():
		root.size=Vector2i(1280,800)
		await process_frame
		await process_frame
		app._interact()
		await process_frame
		await open_preview()
		await check_preview("1280x800",windowed)
		await capture("02-preview-1280x800.png")
		await press_any("AruParkPhotoCancel")
		expect(FileAccess.get_file_as_bytes(photo)==saved,"Wide cancel preserves the saved PNG")
		root.size=Vector2i(1024,640)
		await process_frame
		stand(tile)
	expect(Time.get_ticks_msec()-started<60000,"Photo preview scenario finishes in bounded time")
	expect(DirAccess.rename_absolute(photo,photo+".previous")==OK,"Simulate an interrupted album replacement")
	stand(tile)
	app._interact()
	await process_frame
	expect(app.modal.find_child("AruAlbumPhoto",true,false)!=null,"The album displays the actual saved image")
	expect(FileAccess.get_file_as_bytes(photo)==saved,"Reopening restores the previous photo after an interrupted replacement")
	await capture("03-album.png")
	stand(World.bond_place(app.session.snapshot,"aru")[1])
	Tasks.bond_goal(app,"aru",4)
	await process_frame
	await press("BondGoalDo")
	var bird:="keepsake_aru_bird"
	expect(int(person.inventory.get(Goals.keepsake_item(bird),0))==1,"Reporting awards one carved bird")
	Tasks.bond_goal(app,"aru",4)
	await press("AruParkAlbum")
	expect(node("AruAlbumPhoto") is TextureRect,"The completed story reopens the public album")
	app._close_modal()
	stand(Vector2i(38,33))
	expect(world.act(token,"display-bird","build",Vector2i(38,33),bird).ok,"Build one bird from the earned decoration kit")
	stand(Vector2i(38,33))
	await capture("04-wood-bird.png")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the game after decorating")
	expect(Goals.aru_park_has(loaded.state.objects,"long_bench") and Goals.aru_park_has(loaded.state.objects,"lamp"),"Both donations survive reload")
	expect(loaded.state.objects.get(World.key(Vector2i(38,33)),{}).get("type")==bird,"Placed bird survives reload")
	for file:String in [path,path+".bak",path+".tmp",photo]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ARU_PUBLIC_PLOT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
