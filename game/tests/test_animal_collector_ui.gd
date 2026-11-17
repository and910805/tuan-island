extends SceneTree

const World:=preload("res://scripts/world.gd")
const Industry:=World.INDUSTRY
const Collector:=World.AnimalCollector

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
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://animal-collector-%d.json"%OS.get_process_id()
	if app.session.host(0,"牧場島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	person.workshop_upgraded=true
	world.state.picnic=true
	person.inventory.merge({"hardwood":20,"iron_ingot":18,"woodwork_parts":12,"wood":32,"fiber":6,"feed":12},true)
	var bench:=Vector2i(37,34)
	world.state.objects[World.key(bench)]={"type":"bench","owner":token,"items":{}}
	stand(bench+Vector2i.DOWN)
	expect(world.act(token,"craft-basket","craft",bench,"egg_basket").ok,"Make the portable basket at the workbench")
	var table:=Vector2i(40,34)
	stand(table+Vector2i(1,1))
	expect(world.act(token,"place-table","build",table,Industry.ASSEMBLY_TABLE).ok,"Place the assembly table")
	stand(table+Vector2i(1,1))
	app._interact()
	await process_frame
	var recipe_button:=button("Assemble_animal_collector")
	if recipe_button!=null:
		var scroll_ancestor:=recipe_button.get_parent()
		while scroll_ancestor!=null and not scroll_ancestor is ScrollContainer:
			scroll_ancestor=scroll_ancestor.get_parent()
		var recipe_scroll:=scroll_ancestor as ScrollContainer
		if recipe_scroll!=null:
			recipe_scroll.ensure_control_visible(recipe_button)
			await process_frame
			expect(recipe_scroll.get_global_rect().encloses(recipe_button.get_global_rect()),"Collector recipe can scroll fully into view")
	await capture("collector-assembly.png")
	await press("Assemble_animal_collector")
	await create_timer(0.25).timeout
	expect(app.sound.player.stream==app.sound.sounds.machine_start,"Assembly plays the confirmed machine cue")
	await press("Assemble_animal_collector")
	expect(person.inventory.animal_collector_kit==2 and person.inventory.iron_ingot==0 and person.inventory.woodwork_parts==0 and person.inventory.wood==0,
		"Assembly debits exactly six iron, four parts and twelve wood per collector")
	app._close_modal()
	var site:=Vector2i(47,36)
	var key:=World.key(site)
	stand(site+Vector2i.DOWN)
	expect(world.act(token,"place-collector","build",site,Industry.ANIMAL_COLLECTOR).ok and world.blocked(site),"Place a one-cell collector")
	stand(site+Vector2i.DOWN)
	app._interact()
	await process_frame
	await press("CollectorBind_cow")
	expect(world.state.objects[key].get("collector_animal")=="cow" and person.inventory.egg_basket==0,
		"Binding installs exactly one basket")
	app._close_modal()
	var spare:=Vector2i(48,37)
	stand(spare+Vector2i.DOWN)
	expect(world.act(token,"spare","build",spare,Industry.ANIMAL_COLLECTOR).ok,"Place a second collector")
	expect(not world.act(token,"duplicate-cow","collector_bind",spare,"cow").ok,"One animal cannot be attached to two machines")
	var cow:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
	stand(cow+Vector2i.RIGHT)
	for turn in range(World.LIVESTOCK.BONUS_BOND):
		expect(world.act(token,"pet-cow-%d"%turn,"livestock_pet",cow,"cow").ok,"Build affection through the usual action")
		world.step(World.LIVESTOCK.PET_INTERVAL,true)
	app.session.perform("livestock_feed",cow,"cow")
	await create_timer(0.26).timeout
	expect(app.sound.player.stream==app.sound.sounds.cow,"Feeding through the session plays the cow cue")
	for turn in range(6):
		expect(world.act(token,"feed-cow-%d"%turn,"livestock_feed",cow,"cow").ok,"Feed the cow through the usual feeder")
	for turn in range(7):
		expect(world.step(World.LIVESTOCK.DAY,true),"Advance each normal milk production and collection interval")
	expect(world.state.objects[key].collector_count==Collector.CAPACITY and world.state.livestock.cow.ready==2
		and world.state.objects[key].collector_count_quality==1,"Six products fit, including one quality milk, and two ordinary products stay in the pen")
	expect(world.step(1.0,true) and world.state.objects[key].collector_count==6 and world.state.livestock.cow.ready==2,
		"A full collector does not consume the next product")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and reloaded.state.objects[key].collector_count==6 and reloaded.state.objects[key].collector_count_quality==1,
		"Save and reload preserves the full basket")
	stand(site+Vector2i.DOWN)
	world.add_player("ranch-guest","訪客")
	var guest:Dictionary=world.state.players["ranch-guest"]
	guest.x=person.x
	guest.y=person.y
	expect(not world.act("ranch-guest","guest-take","collector_collect",site).ok
		and world.state.objects[key].collector_count==6,"Nearby guests cannot take stored products")
	expect(not world.act(token,"unbind-full","collector_unbind",site).ok,"Cannot unbind a full basket")
	expect(not world.act(token,"remove-full","remove",site).ok,"Cannot dismantle a loaded collector")
	app._interact()
	await process_frame
	await capture("collector-full.png")
	await press("CollectorTake")
	expect(person.inventory.milk==5 and person.inventory.quality_milk==1 and world.state.objects[key].collector_count==0,"Taking items gives both grades and empties the basket once")
	await create_timer(0.26).timeout
	expect(app.sound.player.stream==app.sound.sounds.basket,"Taking milk through the session plays the basket cue")
	app._close_modal()
	expect(world.step(1.0,true) and world.state.objects[key].collector_count==2 and world.state.livestock.cow.ready==0,
		"Collection resumes as soon as storage is available")
	expect(world.act(token,"take-last","collector_collect",site).ok and person.inventory.milk==7,"The remaining milk was conserved")
	expect(world.act(token,"bind-sheep","collector_bind",site,"sheep").ok,"Reuse the basket for the sheep")
	var sheep:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	stand(sheep+Vector2i.DOWN)
	app.session.perform("livestock_feed",sheep,"sheep")
	await create_timer(0.26).timeout
	expect(app.sound.player.stream==app.sound.sounds.sheep,"Feeding through the session plays the sheep cue")
	expect(world.step(2.0*World.LIVESTOCK.DAY+0.1,true) and world.state.objects[key].collector_count==1
		and world.state.livestock.sheep.ready==0,"The collector takes wool when the sheep is ready")
	stand(site+Vector2i.DOWN)
	expect(world.act(token,"take-wool","collector_collect",site).ok and person.inventory.wool==1,"Retrieve one wool")
	expect(world.act(token,"bind-chicken","collector_bind",site,"chicken").ok,"Reuse the empty basket on a different species")
	world.state.animal.basket_eggs=1
	stand(World.CHICKEN_CELL+Vector2i.LEFT)
	for turn in range(World.LIVESTOCK.BONUS_BOND):
		expect(world.act(token,"pet-chicken-%d"%turn,"pet",World.CHICKEN_CELL).ok,"Build the hen's affection")
		world.step(World.LIVESTOCK.PET_INTERVAL,true)
	app.session.perform("feed",World.CHICKEN_CELL)
	await create_timer(0.26).timeout
	expect(app.sound.player.stream==app.sound.sounds.chicken,"Feeding through the session plays the chicken cue")
	expect(world.step(World.CHICKEN_EGG_SECONDS+0.1,true) and world.state.objects[key].collector_count==1
		and world.state.animal.basket_eggs==1,"New collector takes the new egg while the legacy basket keeps its existing egg")
	for turn in range(1,World.LIVESTOCK.BONUS_INTERVAL):
		expect(world.act(token,"feed-chicken-%d"%turn,"feed",World.CHICKEN_CELL).ok,"Feed the bonded hen")
		world.step(World.CHICKEN_EGG_SECONDS,true)
	stand(site+Vector2i.DOWN)
	await create_timer(0.3).timeout
	await capture("collector-field.png")
	app._interact()
	await capture("collector-quality-egg.png")
	await press("CollectorTake")
	expect(person.inventory.egg==4 and person.inventory.quality_egg==1,"Retrieve the ordinary and quality eggs from the new collector")
	app._close_modal()
	expect(world.act(token,"unbind","collector_unbind",site).ok and person.inventory.egg_basket==1,"Unbinding returns the original basket")
	expect(world.act(token,"refund-kit","remove",site).ok and person.inventory.animal_collector_kit==1,"Dismantle returns exactly one collector kit")
	expect(reloaded.load_world(path) and not reloaded.state.objects.has(key),"Dismantle persists after reload")
	app.session.shutdown()
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ANIMAL_COLLECTOR_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
