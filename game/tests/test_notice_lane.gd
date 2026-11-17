extends SceneTree
var app
var checks:=0
var failures:=0
var directory:=""
func _initialize()->void:
	if DisplayServer.get_name()=="headless":
		print("NOTICE_LANE_TESTS requires native rendering")
		quit(1)
		return
	run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func settle()->void:
	app._layout_preview()
	app._update_activity_caption(0.0)
	await process_frame
	await process_frame
func shot(name:String)->void:
	if directory.is_empty():return
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	directory=app.arg_value("qa-dir","")
	if not directory.is_empty():DirAccess.make_dir_recursive_absolute(directory)
	var save_dir:=directory if not directory.is_empty() else OS.get_cache_dir().path_join("tuan-notice-lane-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(save_dir)
	app.session.profile.token="notice-lane-qa"
	expect(app.session.host(0,"提示測試",save_dir.path_join("world.json"))==OK,"Start isolated native world")
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	app.set_process(false)
	for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=extent
		await settle()
		app._notice("已排入加工：木板（共 2 份）",true)
		await settle()
		expect(app.toast.visible and not app.activity_caption.visible,"Action result uses one lane")
		app._caption("鋸木台完工，可以領取成品。",1)
		await settle()
		expect(app.activity_caption.visible and not app.toast.visible and app.toast_time==0.0,"Completion replaces old queue toast")
		expect(app.activity_caption.size.x<400.0,"Short completion fits content")
		await shot("complete-%dx%d"%[extent.x,extent.y])
		app._notice("已領取：木板 ×2",true)
		await settle()
		expect(app.toast.visible and not app.activity_caption.visible,"Claim replaces completion")
		var small:Vector2=app.toast.size
		app._notice("缺少木材。請先到林地採集木材，或確認材料箱裡的木材是否足夠；加工材料沒有扣除。\n靠近自己的鋸木台後再試一次。",false)
		await settle()
		expect(app.toast.visible and app.toast.size.y>small.y,"Long failure wraps into readable lines")
		app._caption("炭窯完工，可以領取成品。",1)
		await settle()
		expect(app.toast.visible and not app.activity_caption.visible and app.toast.text.begins_with("缺少木材"),"Background completion does not hide failure")
		await shot("error-%dx%d"%[extent.x,extent.y])
		for control in [app.toast,app.activity_caption]:
			expect(control.position.x>=0 and control.position.y>=0 and control.get_rect().end.x<=extent.x and control.get_rect().end.y<=extent.y,"Notice stays inside viewport")
		app._notice("已領取：木板 ×2",true)
		await settle()
		expect(app.toast.size==small,"Short result shrinks after wrapped failure")
		app._caption("魚咬鉤了！點浮標或按 Space 收竿。",2)
		app._caption("鋸木台完工，可以領取成品。",1)
		await settle()
		expect(app.activity_caption.text.begins_with("魚咬鉤"),"Completion cannot replace higher-priority fishing prompt")
		app._update_activity_caption(4.0)
		expect(not app.activity_caption.visible and not app.toast.visible,"Expired captions do not revive stale notices")
		app.sound.activity_captions=false
		app._notice("已領取：木板 ×2",true)
		app._caption("不顯示",1)
		await settle()
		expect(app.toast.visible and not app.activity_caption.visible,"Caption setting does not disable action results")
		app.sound.activity_captions=true
		app._settings_menu()
		await settle()
		expect(not app.toast.visible and not app.activity_caption.visible,"Modal hides transient world messages")
		app._close_modal()
		await settle()
		expect(app.toast.visible and not app.activity_caption.visible,"Closing modal restores only current result")
	root.size=Vector2i(1024,640)
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	app._notice("加工材料不足。請確認背包或材料箱，再靠近設備重新嘗試。\n這次沒有扣除材料。",false)
	await settle()
	expect(app.toast.get_rect().end.x<=1024 and app.toast.get_rect().end.y<=640,"Largest current text scale stays inside small window")
	await shot("large-text-1024x640")
	var world=app.session.world
	var token:String=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	var cell:=Vector2i(41,36)
	var key:=preload("res://scripts/world.gd").key(cell)
	person.x=41.5
	person.y=37.5
	person.inventory.wood=0
	world.state.objects[key]={"type":"sawmill","owner":token,"items":{}}
	app.session._send_snapshot(1)
	var before:Dictionary=person.inventory.duplicate(true)
	app.session.perform("queue_processing",cell,"plank")
	await settle()
	expect(not app.toast_success and app.toast.visible and not app.activity_caption.visible,"Real insufficient-material result is visible")
	expect(before==person.inventory,"Failed queue does not change inventory")
	person.inventory.wood=4
	app.session.rates[1]=[]
	app.session.perform("queue_processing",cell,"plank")
	await settle()
	expect(app.toast_success and app.toast.visible and not app.activity_caption.visible,"Real successful queue replaces failure")
	var finish:float=world.state.objects[key].processing.active.finish
	expect(world.step(finish-float(world.state.time)+0.1,true),"Complete actual queued batch")
	app.session._send_snapshot(1)
	await settle()
	expect(app.activity_caption.visible and not app.toast.visible,"Actual batch completion replaces queue notice")
	app.session.rates[1]=[]
	app.session.perform("claim_processing",cell,"")
	await settle()
	expect(app.toast.visible and not app.activity_caption.visible and int(person.inventory.get("plank",0))>=2,"Actual claim displays result and preserves yield")
	app.session.shutdown()
	app.queue_free()
	await process_frame
	print("NOTICE_LANE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
