extends SceneTree

const World=preload("res://scripts/world.gd")
var app
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(condition:bool,message:String)->void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func visible(control:Control)->bool:
	if not control.is_visible_in_tree() or not root.get_visible_rect().encloses(control.get_global_rect()):return false
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func settle()->void:
	for frame in range(5):await process_frame
	app._layout_preview()
	await process_frame

func node(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control

func press(id:String)->void:
	var button:=node(id) as Button
	check(button!=null and not button.disabled and visible(button),"Visible enabled action: "+id)
	if button==null or button.disabled:return
	await create_timer(0.13).timeout
	button.pressed.emit()
	await settle()

func run()->void:
	var path:=OS.get_environment("TEMP").path_join("auto-freight-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"運礦旅人",path)!=OK:
		quit(1)
		return
	var world=app.session.world
	var actor:String=app.session.profile.token
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		var person:Dictionary=world.state.players[actor]
		person.region="mine_4";person.x=33.5;person.y=20.5
		world.state.mine_depths.unlocked=5
		world.state.mine_depths.pumped=24
		world.state.mine_freight=World.MINE_FREIGHT.fresh()
		world.state.mine_auto_freight=World.MINE_AUTO_FREIGHT.fresh()
		var source:Dictionary={"type":"private_chest","owner":actor,"items":{"copper_ore":20}}
		var target:Dictionary={"type":"private_chest","owner":actor,"items":{}}
		world.state.regions.mine_4.objects["26,24"]=source
		world.state.objects["45,35"]=target
		for cell in ["44,35","46,35","47,35"]:
			world.state.objects[cell]={"type":"private_chest","owner":actor,"items":{}}
		app.session._send_snapshot(1)
		app._auto_freight_menu()
		await settle()
		if (node("AutoTargetLabel") as Label).text!="45,35":await press("AutoTargetNext")
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Auto freight modal fits viewport")
		for id in ["AutoSourcePrev","AutoSourceNext","AutoTargetPrev","AutoTargetNext","AutoReserve","AutoBatch","AutoSave","AutoToggle","AutoClear","AutoFreightHint","AutoManual"]:
			var control:=node(id)
			check(control!=null and visible(control),"Visible "+id)
		(node("AutoReserve") as SpinBox).value=4
		(node("AutoBatch") as SpinBox).value=8
		await press("AutoSave")
		var routes:Dictionary=world.state.mine_auto_freight.routes
		var route:Dictionary=routes.get(actor,{})
		check(route.get("reserve")==4 and route.get("batch")==8 and route.get("item")=="copper_ore","UI saves exact item/reserve/batch")
		(node("AutoBatch") as SpinBox).value=7
		check((node("AutoToggle") as Button).disabled,"Unsaved batch cannot start")
		(node("AutoBatch") as SpinBox).value=8
		await press("AutoToggle")
		check(route.get("enabled",false),"UI activates saved route")
		check((node("AutoSave") as Button).disabled,"Active route cannot edit settings")
		World.MINE_AUTO_FREIGHT.step(world.state)
		app.session._send_snapshot(1)
		await settle()
		var job:Dictionary=world.state.mine_freight.jobs.get(actor,{})
		check(job.get("status")=="transit" and int(job.get("items",{}).get("copper_ore",0))==8 and int(source.items.copper_ore)==12,"Batch uses shared freight and leaves source reserve")
		await press("AutoToggle")
		check(not route.get("enabled",true) and job.get("status")=="transit","Pause preserves current load")
		await press("AutoManual")
		check(app.modal.find_child("FreightAuto",true,false)!=null,"Manual freight remains accessible")
		await press("FreightAuto")
		check((node("AutoFreightStock") as Label).text.contains("8 件"),"Returning to schedule reads same in-flight load")
		world.state.mine_freight.jobs[actor]=World.MINE_FREIGHT.draft()
		source.items.copper_ore=5
		await press("AutoToggle")
		check(app.session.snapshot.mine_auto_freight.status.id=="manual_draft","Manual empty draft blocks scheduled jobs")
		await press("AutoManual")
		var dispatch:=node("FreightDispatch")
		check(dispatch!=null and visible(dispatch) and (dispatch as Button).disabled,"Four home boxes: empty draft keeps disabled dispatch fully visible")
		await press("FreightCancel")
		check(not world.state.mine_freight.jobs.has(actor),"Cancel action clears empty manual draft")
		await press("FreightAuto")
		check(app.session.snapshot.mine_auto_freight.status.id=="waiting","Schedule resumes waiting for a full load")
		app._close_modal()
	app.session.shutdown()
	app.queue_free()
	await process_frame
	print("AUTO_FREIGHT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
