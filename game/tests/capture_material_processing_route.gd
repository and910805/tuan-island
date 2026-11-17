extends "res://tests/capture_workbench_material_hints.gd"
const ProcessingUI=preload("res://scripts/processing_queue_ui.gd")
var world
var person:Dictionary
func press(id:String)->void:
	var button:Button=app.modal.find_child(id,true,false)
	expect(is_instance_valid(button) and not button.disabled,"Action available: "+id)
	if not is_instance_valid(button) or button.disabled:return
	button.pressed.emit()
	await create_timer(0.3).timeout
func capture(name:String)->void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
	expect(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Linked panel stays inside viewport")
	var scroll:ScrollContainer=app.modal.find_child("ModalScroll",true,false)
	for id in ["CraftRecipe","MaterialRecipe"]:
		var control:Control=app.modal.find_child(id,true,false)
		if is_instance_valid(control) and control.is_visible_in_tree():expect(scroll.get_global_rect().encloses(control.get_global_rect()),"Recipe actions remain visible: "+id)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="processing-route-qa"
	assert(app.session.host(0,"工坊銜接測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	world=app.session.world
	person=world.state.players[app.session.peers[1]]
	person.x=41.5
	person.y=34.5
	person.inventory.merge({"wood":100,"stone":50,"copper_ore":4},true)
	for cell in [BENCH,Vector2i(40,35),Vector2i(42,35)]:world.state.removed[World.key(cell)]=true
	app.session.perform("build",BENCH,"bench")
	await create_timer(0.3).timeout
	expect(world.state.objects.get(World.key(BENCH),{}).get("type")=="bench","Build the actual workbench")
	for spec in [["plank","sawmill_kit","sawmill",Vector2i(40,35)],["charcoal","kiln_kit","charcoal_kiln",Vector2i(42,35)]]:
		app.automation_ui.workbench(app,BENCH,"pump_kit")
		await press("MaterialHint_"+str(spec[0]))
		expect(UI.material_route(app.session.snapshot,app.session.own_id,spec[0]).get("recipe")==spec[1],"Missing machine links to its real kit recipe")
		await capture("missing_"+str(spec[0]))
		await press("MaterialRecipe")
		expect(app.modal.find_child("WorkbenchController",true,false).picker.recipe_id==spec[1],"Machine kit is selected")
		await press("CraftRecipe")
		expect(int(person.inventory.get(spec[1],0))==1,"Craft original kit")
		app._close_modal()
		app.session.rates[1]=[]
		app.session.perform("build",spec[3],spec[2])
		await create_timer(0.3).timeout
		expect(world.state.objects.get(World.key(spec[3]),{}).get("type")==spec[2],"Place actual machine using crafted kit")
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		app.automation_ui.workbench(app,BENCH,"pump_kit")
		for spec in [["plank","sawmill",Vector2i(40,35)],["charcoal","charcoal_kiln",Vector2i(42,35)]]:
			var item:String=spec[0]
			await press("MaterialHint_"+item)
			var route:=UI.material_route(app.session.snapshot,app.session.own_id,item)
			expect(route.action=="device" and route.cell==spec[2],"Nearby owned station is chosen")
			var before:Dictionary=person.inventory.duplicate(true)
			await press("MaterialRecipe")
			expect(str(app.modal.get_meta("life_modal_layout",""))==ProcessingUI.LAYOUT,"Open real processing UI")
			expect(person.inventory==before,"Opening processing never consumes ingredients")
			await capture("%d_%s_processing"%[extent.x,item])
			await press("ProcessingEnqueue")
			expect(world.step(float(World.INDUSTRY.PROCESS[item].time)+0.2,true),"Advance real processing queue")
			app.session._send_snapshot(1)
			await create_timer(0.3).timeout
			await press("ProcessingClaim")
			expect(int(person.inventory.get(item,0))==2,"Claim real output")
			await press("ProcessingReturnRecipe")
			expect(app.modal.find_child("WorkbenchController",true,false).picker.recipe_id=="pump_kit","Return to original equipment recipe")
		await press("MaterialHint_copper_joint")
		await press("MaterialRecipe")
		await press("CraftRecipe")
		await press("CraftRecipe")
		await press("RecipeBack")
		await capture("%d_pump_ready"%extent.x)
		var old:int=person.inventory.get("pump_kit",0)
		await press("CraftRecipe")
		expect(int(person.inventory.get("pump_kit",0))==old+1,"Complete pump from processed materials and crafted joints")
		app._close_modal()
		# Raw-material restock for the second resolution, not an earned reward.
		person.inventory.copper_ore=4
		app.session._send_snapshot(1)
	# Snapshot-only edge fixtures: friend machines never grant remote access.
	var snapshot:Dictionary=app.session.snapshot.duplicate(true)
	var own:String=app.session.own_id
	snapshot.objects={"40,35":{"type":"sawmill","owner":"friend"},"55,35":{"type":"sawmill","owner":own}}
	var far:=UI.material_route(snapshot,own,"plank")
	expect(far.action=="far" and far.cell==Vector2i(55,35) and float(far.distance)>3.2,"Friend's nearby machine is ignored; far machine is not opened")
	snapshot.objects.erase("55,35")
	expect(UI.material_route(snapshot,own,"plank").action=="recipe","Only a friend's machine still offers own kit recipe")
	print("MATERIAL_PROCESSING_ROUTE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
