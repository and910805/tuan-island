extends SceneTree

const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_ui.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func button_at(node:Node,title:String)->Button:
	if node is Button and node.text.begins_with(title):return node
	for child in node.get_children():
		var result:=button_at(child,title)
		if result!=null:return result
	return null

func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.menu.hide()
	app.hud.show()
	var world:=World.new()
	world.add_player("tester","島民")
	var person:Dictionary=world.state.players.tester
	person.x=38.5
	person.y=30.5
	app.session.snapshot=world.state
	app.view.update_snapshot(world.state,"tester")
	app.session.own_id="tester"
	app.session.world=world
	app.session.peers[1]="tester"
	app.session.sequences[1]=0
	app.session.rates[1]=[]
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		await process_frame
		Chapter.open(app)
		app._layout_preview()
		await process_frame
		await process_frame
		expect(Rect2(Vector2.ZERO,Vector2(size)).encloses(app.modal.get_global_rect()),"Chapter fits "+str(size))
		expect(button_at(app.modal,"查看小島地圖").is_visible_in_tree(),"Map route visible")
		expect(app.modal.get_meta("chapter_step").id=="grow","Fresh world starts at grow")
	var first:Control=app.modal.get_meta("chapter_content").get_child(0)
	Chapter.refresh(app)
	expect(app.modal.get_meta("chapter_content").get_child(0)==first,"Unchanged refresh keeps controls")
	world.state.chapter_one.shipped=true
	world.state.board=true
	Chapter.refresh(app)
	expect(app.modal.get_meta("chapter_step").id=="water","Updated snapshot changes chapter")
	for size in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=size
		app._layout_preview()
		await process_frame
		await process_frame
		var scroll:ScrollContainer=app.modal.get_meta("chapter_content").get_parent()
		for name in ["ChapterWaterFlow","ChapterDetails"]:
			var element:Control=app.modal.find_child(name,true,false)
			expect(element!=null and scroll.get_global_rect().encloses(element.get_global_rect()),"Water section fully visible at "+str(size)+": "+name)
	await capture(app,"chapter-water")
	Tasks.resident(app,"aru")
	expect(button_at(app.modal,"交付這段委託")!=null,"Original resident quest remains")
	var letter:=button_at(app.modal,"看渡口來信")
	expect(letter!=null,"Current resident offers chapter letter")
	if letter!=null:letter.pressed.emit()
	var claim:=button_at(app.modal,"交材料換入門設備")
	expect(claim!=null and claim.is_visible_in_tree(),"Nearby resident can offer equipment trade")
	await capture(app,"resident-water")
	person.inventory.wood=0
	var before:Dictionary=person.inventory.duplicate(true)
	if claim!=null:claim.pressed.emit()
	expect(app.session.sequences[1]>0 and app.toast.text.contains("需要木材 12"),"Claim reaches Session and reports insufficient materials")
	expect(person.inventory==before and world.state.chapter_one.starter_claims.is_empty(),"Missing materials change neither inventory nor claim")
	Tasks.resident(app,"milu")
	expect(button_at(app.modal,"看渡口來信")==null,"Unrelated resident has no chapter prompt")
	app.queue_free()
	await process_frame
	print("CHAPTER_UI_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(app,name:String)->void:
	var target:String=app.arg_value("qa-capture","")
	if target.is_empty():return
	var size:String=app.arg_value("qa-size","1024x640")
	var extent:=size.split("x")
	root.size=Vector2i(int(extent[0]),int(extent[1]))
	app._layout_preview()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(target.path_join(name+"-"+size+".png"))==OK,"Saved rendered fixture")

