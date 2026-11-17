extends SceneTree
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/forestry_ui.gd")
const CELL:=Vector2i(41,34)
var app
var world
var person:Dictionary
var token:=""
var station:Dictionary
var directory:=""
var checks:=0
var failures:=0
var sequence:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func act(action:String,extra:="")->void:
	sequence+=1
	app.session.rates[1]=[]
	app.session._action(1,sequence,action,CELL,extra)
	app.session._send_snapshot(1)
func reset_plots(mode:String)->void:
	station.enabled=true
	station.fuel=0
	station.saplings=0
	station.items={}
	person.x=41.5
	person.y=35.5
	for offset:Vector2i in World.FORESTRY.OFFSETS:
		var p:=CELL+offset
		var k:=World.key(p)
		world.state.removed[k]=true
		for field in ["objects","forest","crops","ground","roofs"]:world.state[field].erase(k)
		if mode in ["mature","growing"]:
			world.state.forest[k]={"owner":token,"mature":mode=="mature","growth":World.TREE_TIME if mode=="mature" else 30.0}
		elif mode=="blocked":world.state.objects[k]={"owner":token,"type":"bench","items":{}}
func capture(name:String,wanted:String)->void:
	app.session._send_snapshot(1)
	await create_timer(0.25).timeout
	var map:=World.new()
	map.state=app.session.snapshot
	var device:Dictionary=map.state.objects[World.key(CELL)]
	var advice:=UI.operation_advice(map,CELL,device)
	expect(advice.short==wanted,"Advice "+name)
	app.forestry_ui.device(app,CELL)
	await create_timer(0.3).timeout
	var text:Label=app.modal.find_child("ForestryAdvice",true,false)
	expect(is_instance_valid(text) and text.text==advice.detail,"Panel shares the same explanation")
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
	expect(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Panel stays inside window")
	expect(app.view.hide_interaction_prompt,"Forestry page hides duplicate world interaction banner")
	var scroll:ScrollContainer=app.modal.find_child("ModalScroll",true,false)
	for index in 4:
		var plot:Label=app.modal.find_child("ForestryPlot_"+str(index),true,false)
		expect(scroll.get_global_rect().encloses(plot.get_global_rect()),"All four plot states are visible without scrolling")
	app._close_modal()
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1280,800) if app.arg_value("qa-size","")=="1280" else Vector2i(1024,640)
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="forestry-advice-qa"
	assert(app.session.host(0,"林務提示測試",directory.path_join("world.json"))==OK)
	await create_timer(0.3).timeout
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.peers[1]
	person=world.state.players[token]
	person.x=41.5
	person.y=35.5
	person.inventory.forester_kit=1
	person.inventory.charcoal=4
	person.inventory.sapling=4
	act("build","forester")
	station=world.state.objects[World.key(CELL)]
	reset_plots("mature")
	await capture("needs_fuel","待補木炭")
	act("load_forester","charcoal")
	expect(station.fuel==4,"Real fuel loading updates station")
	station.cursor=0
	station.next_cycle=float(world.state.time)+12.0
	expect(world.step(12.1,true),"Run authoritative forestry cycle")
	expect(int(station.items.get("wood",0))>=6 and int(station.fuel)<4,"Supplying fuel resumes actual harvest and replant")
	reset_plots("empty")
	await capture("needs_saplings","待補樹苗")
	act("load_forester","sapling")
	station.cursor=0
	station.next_cycle=float(world.state.time)+12.0
	expect(world.step(12.1,true),"Run planting cycle")
	expect(world.state.forest.has(World.key(CELL+Vector2i(0,-2))) and station.saplings<4,"Supplying saplings resumes actual planting")
	reset_plots("growing")
	await capture("growing","等待樹木成長")
	reset_plots("mature")
	station.fuel=4
	station.items={"wood":48,"fiber":16,"resin":8}
	await capture("full","產物滿了，先領取")
	act("collect_forester")
	expect(station.items.is_empty(),"Real collection clears output")
	var map:=World.new()
	map.state=world.state
	expect(UI.operation_advice(map,CELL,station).short=="","Collecting restores an available operation")
	reset_plots("blocked")
	await capture("blocked","作業格被擋住")
	reset_plots("growing")
	for p in world.state.forest.values():p.growth=World.TREE_TIME
	await capture("growth_space","請讓出生長空間")
	reset_plots("blocked")
	var open:=CELL+Vector2i(0,-2)
	world.state.objects.erase(World.key(open))
	station.saplings=4
	person.x=open.x+0.5
	person.y=open.y+0.5
	await capture("occupied","請讓出種植格")
	print("FORESTRY_ADVICE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
