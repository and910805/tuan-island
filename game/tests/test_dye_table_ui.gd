extends SceneTree

const World:=preload("res://scripts/world.gd")
const Flower:=World.FLOWER_NURSERY
const Industry:=World.INDUSTRY

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
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://home-dye-%d.json"%OS.get_process_id()
	if app.session.host(0,"島上染匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var site:=Vector2i(40,34)
	var end:=site+Vector2i.RIGHT
	var chair:=site+Vector2i(2,0)
	var chair_key:=World.key(chair)
	person.inventory.merge({"wood":30,"clay":6,"bluebell":3,"orange_blossom":3},true)
	stand(end+Vector2i.DOWN)
	expect(not world.act(token,"dye-locked","build",site,Industry.DYE_TABLE).ok and person.inventory.clay==6,
		"Dye table needs the Tianwei public garden")
	var tea:=World.TEA_CERAMICS.FRESH.duplicate(true)
	tea.merge({"intro":true,"potter":true,"reused":true,"reuse_count":1,"tea_discussed":true,
		"potter_story":true,"comparison_complete":true,"trials":{"jar":true,"fiber":true}},true)
	world.state.tea_ceramics.players[token]=tea
	var record:=Flower.FRESH.duplicate(true)
	record.letter=true
	record.intro=true
	world.state.flower_nursery.players[token]=record
	person.region=Flower.REGION
	person.travel_book.visited[Flower.REGION]=true
	person.inventory.merge(Flower.GARDEN_NEEDS,true)
	stand(Flower.GARDEN_CELL+Vector2i.LEFT)
	expect(world.act(token,"garden-donate","flower_give",Flower.GARDEN_CELL).ok and world.state.flower_nursery.garden.complete,
		"Completing the garden through a donation unlocks the table")
	person.inventory.orange_blossom=3
	person.region=World.REGIONS.HOME
	stand(end+Vector2i.DOWN)
	app._perform_build_action("build",site,Industry.DYE_TABLE)
	await process_frame
	expect(person.inventory.wood==18 and person.inventory.clay==0,"Dye station uses twelve wood and six clay")
	expect(world.blocked(site) and world.blocked(end) and World.station_anchor(world.state.objects,end)==site,
		"Both tiles block and lead to a single station")
	stand(chair+Vector2i.DOWN)
	expect(world.act(token,"build-chair","build",chair,"chair").ok,"Place the chair near the dye station")
	stand(end+Vector2i.DOWN)
	app._interact()
	await process_frame
	await press("ProcessingRecipe_blue_dye")
	await press("ProcessingEnqueue")
	await press("ProcessingRecipe_orange_dye")
	await press("ProcessingEnqueue")
	expect(person.inventory.bluebell==0 and person.inventory.orange_blossom==0,"Each color consumes its own flowers")
	await capture("dye-queue.png")
	expect(world.step(60.1,true),"Finish both batches")
	app.session._send_snapshot(1)
	await create_timer(0.3).timeout
	await press("ProcessingClaim")
	await press("ProcessingClaim")
	expect(person.inventory.get("blue_dye")==2 and person.inventory.get("orange_dye")==2,"Both colors yield two portions")
	await press("DyeFurnitureMenu")
	await press("DyeFurniture_42_34_blue_dye")
	expect(world.state.objects[chair_key].get("dye")=="blue_dye" and person.inventory.blue_dye==1,
		"Blue tint consumes one portion")
	expect(not world.act(token,"same-color","dye_furniture",site,chair_key+"|blue_dye").ok and person.inventory.blue_dye==1,
		"Reapplying the same color spends nothing")
	await create_timer(0.35).timeout
	expect(button("DyeFurniture_42_34_blue_dye").disabled and button("DyeFurniture_42_34_blue_dye").text.ends_with("1 份"),
		"Panel shows the current dye and inventory after success")
	await capture("furniture-colors.png")
	await press("DyeFurniture_42_34_orange_dye")
	expect(world.state.objects[chair_key].get("dye")=="orange_dye" and person.inventory.orange_dye==1,
		"Orange tint uses the second color recipe")
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects[chair_key].get("dye")=="orange_dye","Dye stays on furniture across reload")
	app._close_modal()
	stand(chair+Vector2i.DOWN)
	await create_timer(2.0).timeout
	await capture("dyed-chair-field.png")
	stand(end+Vector2i.DOWN)
	expect(world.act(token,"reset-dye","dye_furniture",end,chair_key+"|").ok and not world.state.objects[chair_key].has("dye"),
		"Reset the original color from the far side of the table")
	world.add_player("other","訪客")
	var other:Dictionary=world.state.players.other
	other.x=site.x-0.5
	other.y=site.y+0.5
	other.inventory.blue_dye=1
	expect(not world.act("other","foreign-dye","dye_furniture",site,chair_key+"|blue_dye").ok and other.inventory.blue_dye==1,
		"A visitor cannot dye another islander's furniture")
	var design:=World.BLUEPRINT_DESIGN
	var state:={"objects":world.state.objects}
	expect(not design.capture(state,token,Rect2i(site,Vector2i.ONE),"半張桌",World.BUILD,World.NAMES).ok,
		"Blueprint rejects a partial table")
	var wide:=design.capture(state,token,Rect2i(site,Vector2i(2,1)),"染色桌",World.BUILD,World.NAMES)
	expect(wide.ok and wide.blueprint.pieces.size()==1,"Blueprint captures one full dye table")
	if wide.ok:
		var rotated:=design.rotate(wide.blueprint,1,World.BUILD,World.NAMES)
		expect(rotated.ok and rotated.blueprint.width==1 and rotated.blueprint.height==2 and rotated.blueprint.pieces[0].settings.vertical,
			"Rotation produces the correct one-by-two footprint")
		expect(world.act(token,"remove-table","remove",end).ok,"Remove the whole station from its other end")
		var quote:=world.quote_blueprint(token,wide.blueprint,site,1)
		expect(quote.ok and world.apply_blueprint(token,"d".repeat(32),wide.blueprint,site,1,quote.hash).ok,
			"Construct the rotated dye table")
		expect(World.station_anchor(world.state.objects,site+Vector2i.DOWN)==site and world.blocked(site+Vector2i.DOWN),
			"Vertical second tile points to the station")
	app.session.shutdown()
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("DYE_TABLE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
