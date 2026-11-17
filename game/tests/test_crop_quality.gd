extends SceneTree

const World=preload("res://scripts/world.gd")
const TOKEN:="quality-grower"
const GRADE:="quality_radish"
const FIELD:=Vector2i(40,35)
const PLOTS:=[FIELD,Vector2i(41,35),Vector2i(42,35),Vector2i(40,36),Vector2i(41,36)]
var world:World
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func expect(condition:bool,message:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func person() -> Dictionary:
	return world.state.players[TOKEN]

func run() -> void:
	world=World.new()
	world.add_player(TOKEN,"望安農夫")
	person().x=41.5
	person().y=35.5
	for index in PLOTS.size():
		var cell:Vector2i=PLOTS[index]
		var tilled:=world.act(TOKEN,"hoe-%d"%index,"hoe",cell)
		var planted:=world.act(TOKEN,"seed-%d"%index,"seed",cell,"radish")
		expect(tilled.ok and planted.ok,"A normal plot is planted at "+str(cell))
		expect(world.act(TOKEN,"water-%d"%index,"water",cell).ok,"A new growing plot is watered")
		expect(int(person().get("crop_care",0))==index+1,"Each dry growing plot earns one care credit")
		if index==0:
			world.act(TOKEN,"water-again","water",cell)
			expect(int(person().get("crop_care",0))==1,"Repeated watering earns no care")
	var path:="user://crop-quality-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	expect(world.save() and world.load_world(path) and int(person().crop_care)==5,"The full care streak survives reloading")
	expect(world.step(World.CROPS.radish.time,true),"Watered crops finish growing")
	person().inventory[GRADE]=1000000000
	expect(not world.act(TOKEN,"caps","harvest",FIELD).ok and int(person().crop_care)==5
		and world.state.crops[World.key(FIELD)].kind=="radish","A full quality stack preserves crop and guarantee")
	person().inventory.erase(GRADE)
	expect(world.act(TOKEN,"harvest","harvest",FIELD).ok and int(person().inventory.get(GRADE,0))==1
		and int(person().inventory.radish)==1 and int(person().crop_care)==0,"A harvest gives normal yield plus one quality item and consumes the guarantee")
	expect(world.save() and world.load_world(path) and int(person().inventory[GRADE])==1,"The quality crop survives reloading")
	var preview:=OS.get_cmdline_user_args()
	if DisplayServer.get_name()!="headless":
		await verify_presentation(preview)
	person().x=42.5
	person().y=32.0
	var coins:=int(person().coins)
	var sell_at:=World.SHIPPING.cell_for(world.state)
	var result:=world.act(TOKEN,"ship-quality","ship",sell_at,JSON.stringify([[[GRADE,1]],30]))
	expect(result.ok and int(person().coins)==coins+30 and int(person().inventory[GRADE])==0,"A quality-only shipment pays 125 percent and removes one item")
	expect(world.state.chapter_one.shipped,"A quality shipment counts for the first chapter")
	person().x=41.5
	person().y=35.5
	person().crop_care=5
	person().inventory.harvester=1
	person().inventory.charcoal=1
	expect(world.act(TOKEN,"batch","harvest_area",PLOTS[1]).ok and int(person().inventory[GRADE])==1
		and int(person().crop_care)==0 and int(person().inventory.charcoal)==0,"Batch harvest settles exactly one guarantee and consumes one fuel")
	var field_key:=World.key(FIELD)
	var rotation:=["lettuce","wheat"]
	var care_before_harvest:=0
	for index in rotation.size():
		var kind:String=rotation[index]
		expect(world.act(TOKEN,"rotate-seed-"+kind,"seed",FIELD,kind).ok,"Same plot accepts a different crop")
		expect(world.act(TOKEN,"rotate-water-"+kind,"water",FIELD).ok,"Rotated crop is watered")
		world.step(World.CROPS[kind].time,true)
		if index==1:
			person().inventory.quality_wheat=1000000000
			person().inventory.charcoal=1
			var before:Dictionary=world.state.duplicate(true)
			expect(not world.act(TOKEN,"rotation-full","harvest_area",FIELD).ok and world.state==before,
				"Capacity check for a rotation bonus is atomic for the harvesting machine")
			person().inventory.erase("quality_wheat")
			if DisplayServer.get_name()!="headless":
				await verify_soil_panel(preview)
		care_before_harvest=int(person().crop_care)
		expect(world.act(TOKEN,"rotate-harvest-"+kind,"harvest",FIELD).ok,"Rotated crop is harvested")
		expect(world.save() and world.load_world(path),"Rotated plot and soil are saved")
		expect(world.state.crops[field_key].last_harvest_kind==kind
			and int(world.state.crops[field_key].fertility)==1-index,"Soil stores one rotation or resets after earning quality")
	expect(int(person().inventory.get("quality_lettuce",0))==0 and int(person().inventory.get("quality_wheat",0))==1
		and int(person().crop_care)==care_before_harvest,"Rotation earns quality after two changes and keeps the separate care streak")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("CROP_QUALITY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_presentation(args:PackedStringArray) -> void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.state.duplicate(true)
	app.view.update_snapshot(app.session.snapshot,TOKEN)
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._inventory()
	await create_timer(0.35).timeout
	app.modal.slots[GRADE].grab_focus()
	await process_frame
	expect(app.modal.selected_id==GRADE and app.modal.detail_name.text=="優良奶白蘿蔔","The inventory identifies the quality stack")
	expect(app.modal.slots[GRADE].grade.visible,"The quality stack displays its star")
	expect(not app.modal.slots["quality_wheat"].visible,"Only held quality crops occupy slots")
	for arg:String in args:
		if not arg.begins_with("--crop-quality-preview="):continue
		await RenderingServer.frame_post_draw
		var path:=arg.trim_prefix("--crop-quality-preview=")
		expect(root.get_texture().get_image().save_png(path)==OK,"The native quality screen was captured")
	app.queue_free()
	await process_frame

func verify_soil_panel(args:PackedStringArray) -> void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	var snapshot:Dictionary=world.state.duplicate(true)
	snapshot.players[TOKEN].x=FIELD.x+0.5
	snapshot.players[TOKEN].y=FIELD.y+0.5
	app.session.snapshot=snapshot
	app.view.update_snapshot(snapshot,TOKEN)
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._interact()
	await create_timer(0.35).timeout
	var labels:Array=app.modal.find_children("*","Label",true,false) if is_instance_valid(app.modal) else []
	expect(labels.any(func(node):return node.text.begins_with("土壤肥力 1／2")),"Plot interaction displays saved fertility")
	expect(labels.any(func(node):return node.text=="這批作物可多收一件優良品。"),"Plot interaction displays the quality forecast")
	for arg:String in args:
		if not arg.begins_with("--soil-preview="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--soil-preview="))==OK,"Native soil screen was captured")
	app.queue_free()
	await process_frame
