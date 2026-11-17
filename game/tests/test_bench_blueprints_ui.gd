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
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://bench-blueprints-%d.json"%OS.get_process_id()
	app.session.profile.token="bench-blueprints-%d"%OS.get_process_id()
	if app.session.host(0,"藍圖島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	person.bonds={"aru":{"points":14,"talk_day":-1,"gift_day":-1}}
	person[Goals.RECORD_KEY]={"aru":{"2":"","3":""}}
	person.inventory.wood=100
	person.inventory.hardwood=24
	var source:=Vector2i(38,34)
	stand(source+Vector2i.DOWN)
	expect(world.act(token,"place-original","build",source,Goals.MASTER_BENCH).ok,"Build an original horizontal bench")
	expect(world.act(token,"inscribe",Goals.INSCRIBE_ACTION,source,"老地方").ok,"Add a personal inscription to the source")
	stand(source+Vector2i.DOWN)
	var ctrl=app.blueprints
	var design=World.BLUEPRINT_DESIGN
	expect(ctrl.begin_capture(),"Open the real blueprint capture flow")
	for tile:Vector2i in [source,source+Vector2i.RIGHT]:
		expect(not ctrl.capture_area(Rect2i(tile,Vector2i.ONE),"半張長椅").ok,"Capturing either half alone fails")
	expect(ctrl.capture_area(Rect2i(source,Vector2i(2,1)),"師父的長椅").ok,"Capture the full bench")
	var original:Dictionary=ctrl.captured.duplicate(true)
	expect(original.pieces==[{"kind":Goals.MASTER_BENCH,"x":0,"y":0}],"The whole bench is stored as one piece")
	for turns in range(4):
		var rotated:Dictionary=design.rotate(original,turns,World.BUILD,World.NAMES)
		expect(rotated.ok and (rotated.blueprint.width==1)==(turns%2==1) and (rotated.blueprint.height==2)==(turns%2==1),"Footprint rotates correctly at %d degrees"%(turns*90))
	var mixed:Dictionary=original.duplicate(true)
	mixed.width=4
	mixed.height=3
	mixed.pieces=[{"kind":Goals.MASTER_BENCH,"x":1,"y":0},{"kind":"lamp","x":3,"y":2}]
	var reverse:Dictionary=design.rotate(mixed,2,World.BUILD,World.NAMES)
	expect(reverse.ok and reverse.blueprint.pieces==[{"kind":"lamp","x":0,"y":0},{"kind":Goals.MASTER_BENCH,"x":1,"y":2}],"Rotating 180 degrees chooses the left anchor relative to other furniture")
	var vertical:Dictionary=design.rotate(mixed,3,World.BUILD,World.NAMES)
	expect(vertical.ok and vertical.blueprint.pieces==[{"kind":"lamp","x":2,"y":0},{"kind":Goals.MASTER_BENCH,"x":0,"y":1,"settings":{"vertical":true}}],"Rotating 270 degrees chooses the north anchor relative to other furniture")
	var overlap:Dictionary=original.duplicate(true)
	overlap.pieces.append({"kind":"lamp","x":1,"y":0})
	expect(not design.validate(overlap,World.BUILD,World.NAMES).ok,"A blueprint cannot place another object under the second half")
	var saved:Dictionary=ctrl.save_capture("師父的長椅")
	expect(saved.ok and ctrl.choose(saved.get("id","")),"Save and choose it from the player's blueprint book")
	var site:=Vector2i(41,34)
	stand(site+Vector2i.RIGHT)
	expect(ctrl.rotate() and ctrl.move_origin(site),"Rotate and move the blueprint preview")
	await process_frame
	await capture("01-rotated-preview.png")
	var end:=site+Vector2i.DOWN
	world.state.objects[World.key(end)]={"type":"lamp","owner":token,"items":{}}
	expect(not world.quote_blueprint(token,original,site,1).ok,"Existing objects on the rotated second tile block construction")
	world.state.objects.erase(World.key(end))
	stand(site+Vector2i.RIGHT)
	expect(ctrl.pin_origin(site),"Request a quote from the real placement menu")
	await process_frame
	await process_frame
	expect(ctrl.quote.get("ok",false) and int(ctrl.quote.get("cost",{}).get("hardwood",0))==4,"A two-tile bench is charged once")
	var hardwood:=int(person.inventory.hardwood)
	expect(ctrl.confirm(),"Confirm the quoted construction")
	await process_frame
	await process_frame
	var items:Dictionary=world.state.objects
	expect(items.get(World.key(site),{}).get("bench_vertical",false) and items.get(World.key(end),{}).get("bench_end",false),"Construction writes the vertical pair")
	expect(int(person.inventory.hardwood)==hardwood-4 and world.blocked(site) and world.blocked(end),"Both tiles block movement with one debit")
	expect(not items.get(World.key(site),{}).has("inscription"),"The new bench starts without the source's private wording")
	expect(items.get(World.key(source),{}).get("inscription")=="老地方","Capturing did not alter the original")
	await capture("02-vertical-bench.png")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and checkpoint.state.objects.get(World.key(site),{}).get("bench_vertical"),"The vertical bench and live undo record survive a reload")
	var quote:=world.undo_summary(token)
	var reverted:Dictionary=world.act(token,"undo-blueprint",World.UNDO_ACTION,Vector2i.ZERO,quote.id) if quote.available else quote
	expect(reverted.get("ok",false),"Undo the blueprint using normal construction history: %s"%str(reverted))
	expect(not items.has(World.key(site)) and not items.has(World.key(end)) and int(person.inventory.hardwood)==hardwood,"Undo clears both tiles and returns one set of materials")
	var second_quote:=world.quote_blueprint(token,original,site,1)
	expect(second_quote.ok and world.apply_blueprint(token,"c".repeat(32),original,site,1,second_quote.hash).ok,"Rebuild the rotated bench after undo")
	var seat:=world.act(token,"sit-southern-half",Goals.MASTER_BENCH_SIT,end)
	expect(seat.ok and int(person.get(Goals.MASTER_BENCH_SEAT,{}).get("side",-1))==1,"The south tile selects its own seat")
	world.move_player(token,Vector2.RIGHT,0.1)
	expect(not world.undo_summary(token).available,"Construction history protects a bench already used")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(loaded.state.objects.get(World.key(source),{}).get("inscription")=="老地方","The original bench survives the blueprint and undo")
	var library:String=app._blueprint_library_path()
	for name:String in [path,library]:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(name+suffix):DirAccess.remove_absolute(name+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("BENCH_BLUEPRINT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
