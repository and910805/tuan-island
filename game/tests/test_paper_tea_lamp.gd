extends SceneTree

# T05 紙罩茶燈. Native headless by default; pixel checks run only on a real renderer.
# Optional: --qa-dir=<folder> saves screenshots, --qa-size=1024 uses a 1024x640 window.

const World=preload("res://scripts/world.gd")
const StyleCatalog=preload("res://scripts/build_style_catalog.gd")
const LAMP:=World.INDUSTRY.PAPER_TEA_LAMP
const FLOOR_LAMP:="lamp"
const SITE:=Vector2i(42,34)
const MOVED:=Vector2i(43,35)
const FLOOR_SITE:=Vector2i(45,35)
const COST:={"bamboo":4,"cotton_cloth":2,"copper_ingot":1}
const FLOOR_COST:={"wood":5,"stone":2}
const ART_PATH:="res://assets/ui-life/paper-tea-lamp.png"
var app
var world:World
var owner:String
var guest:="paper-tea-lamp-guest"
var output:String
var path:String
var checks:=0
var failures:=0
var request:=0

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(label)
	return success

func press(name:String)->bool:
	var control:=app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func frame(capture_name:="")->Image:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty() and not capture_name.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(capture_name+".png"))==OK,"Screenshot "+capture_name)
	return image

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.22).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("PAPER_TEA_LAMP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func act(token:String,action:String,at:Vector2i,extra:="")->Dictionary:
	request+=1
	return world.act(token,"paper-tea-%d"%request,action,at,extra)

func bag()->Dictionary:
	return world.state.players[owner].inventory

func inventory_is(amounts:Dictionary)->bool:
	for item:String in amounts:
		if int(bag().get(item,0))!=int(amounts[item]):return false
	return true

func type_at(at:Vector2i)->String:
	return str(world.state.objects.get(World.key(at),{}).get("type",""))

func lamp_off(at:Vector2i)->bool:
	return bool(world.state.objects.get(World.key(at),{}).get("lamp_off",false))

## Screen pixel for a point given in cell units.
func pixel(cell:Vector2i,offset:Vector2)->Vector2i:
	var local:Vector2=app.view.screen(Vector2(cell)+offset)
	return Vector2i((local*app.view.view_zoom()).round())

func glow_point(cell:Vector2i)->Vector2i:
	return pixel(cell,Vector2(1.0,0.65))

## Centre of the 26x34 sprite drawn at PAPER_TEA_LAMP_AT inside the 32px cell.
func body_point(cell:Vector2i)->Vector2i:
	var at:Vector2=Vector2(app.view.PAPER_TEA_LAMP_AT)
	return pixel(cell,(at+Vector2(13,17))/32.0)

func warm_gain(lit:Color,dark:Color)->float:
	return lit.r-dark.r

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://paper-tea-lamp-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="paper-tea-lamp-owner"
	if app.session.host(0,"茶燈木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=33.5
	person.inventory={"bamboo":12,"cotton_cloth":6,"copper_ingot":3,"wood":5,"stone":2}
	world.state.time=720.0
	for cell:Vector2i in [SITE,MOVED,FLOOR_SITE]:world.state.removed[World.key(cell)]=true
	app.session._send_snapshot(1)

	# --- recipe, data and art contract (headless-safe) -------------------------------
	var recipe:Dictionary=World.BUILD.get(LAMP,{})
	expect(LAMP=="paper_tea_lamp" and recipe.get("name")=="紙罩茶燈","Industry.PAPER_TEA_LAMP is paper_tea_lamp named 紙罩茶燈")
	var cost:=recipe.duplicate()
	cost.erase("name")
	expect(cost==COST,"Recipe is exactly bamboo 4, cotton_cloth 2, copper_ingot 1")
	expect(LAMP not in World.INDUSTRY.TWO_CELL_STATIONS and LAMP not in World.INDUSTRY.FIXED_SQUARE_STATIONS,"The lamp needs no multi-cell footprint")
	var texture:=load(ART_PATH) as Texture2D
	if expect(texture!=null and texture.get_size()==Vector2(26,34),"paper-tea-lamp.png imports as a 26x34 texture"):
		var art:=texture.get_image()
		expect(art.get_pixel(0,0).a==0.0 and art.get_pixel(25,0).a==0.0,"Sprite corners are transparent")
		var lowest:=-1
		for y in 34:
			for x in 26:
				if art.get_pixel(x,y).a>0.5:lowest=y
		expect(lowest>=28,"The lamp body reaches the bottom of its sprite so it sits on the tile")
	var at:Vector2=Vector2(app.view.PAPER_TEA_LAMP_AT)
	expect(at.x>=0.0 and at.x+26.0<=32.0 and at.y+34.0<=32.0 and at.y+34.0>=28.0,"Sprite offset keeps the 26x34 art inside its 32px tile, resting near the bottom edge")

	# --- catalogue: tea collection, furniture list, preview --------------------------
	expect(World.BUILD.has(LAMP),"Lamp is a buildable")
	expect(preload("res://scripts/build_folio.gd").TEA_COLLECTION.has(LAMP),"Tea collection lists the lamp")
	expect(preload("res://scripts/life_ui_panels.gd").FURNITURE.has(LAMP),"Furniture list includes the lamp")
	expect(preload("res://scripts/build_folio.gd").PLACEMENT_NOTES.has(LAMP),"The catalogue has a placement note")
	app._build_menu()
	var tea_name:String=StyleCatalog.style("tea_house").name
	var picked:=false
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text==tea_name:
			entry.pressed.emit()
			picked=press("BuildSlot_"+LAMP+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	expect(picked,"The tea collection page shows a slot for the lamp")
	if picked:
		press("BuildPlace")
		expect(app.building==LAMP and app.view.build_placement_offsets(LAMP)==[Vector2i.ZERO],"Selecting it previews one cell")

	# --- owner builds through the normal action ---------------------------------------
	var built:=act(owner,"build",SITE,LAMP)
	if not expect(built.ok and type_at(SITE)==LAMP,"Owner places the lamp: "+str(built.get("message",""))):
		await finish()
		return
	expect(inventory_is({"bamboo":8,"cotton_cloth":4,"copper_ingot":2}),"One placement consumes exactly the recipe")
	expect(world.state.objects[World.key(SITE)].owner==owner and not lamp_off(SITE),"The lamp is owned by the builder and starts on")
	expect(not world.blocked(SITE),"The lamp is passable")
	person.x=SITE.x+0.5
	person.y=SITE.y+0.5
	expect(world.can_stand(Vector2(person.x,person.y)),"The owner can stand on the lamp's cell")
	person.x=41.5
	person.y=33.5

	# --- owner-only control ------------------------------------------------------------
	world.add_player(guest,"訪客",Vector2(42.5,33.5))
	var visitor_toggle:=act(guest,"floor_lamp_toggle",SITE)
	expect(not visitor_toggle.ok and not lamp_off(SITE),"A visitor cannot switch the owner's lamp")
	expect(world.can_stand(Vector2(SITE)+Vector2(0.5,0.5)),"A visitor can walk through the lamp cell")
	expect(not act(guest,"remove",SITE).ok and type_at(SITE)==LAMP,"A visitor cannot dismantle it")
	expect(not act(guest,"move_object",SITE,"%d,%d"%[MOVED.x,MOVED.y]).ok and type_at(SITE)==LAMP and type_at(MOVED)=="","A visitor cannot move it")
	expect(not act(owner,"floor_lamp_toggle",SITE,"extra").ok,"Toggle rejects stray extra data")
	person.x=SITE.x+6.0
	expect(not act(owner,"floor_lamp_toggle",SITE).ok and not lamp_off(SITE),"The owner must be close to the lamp")
	person.x=41.5
	var off:=act(owner,"floor_lamp_toggle",SITE)
	expect(off.ok and lamp_off(SITE) and str(off.message).contains("紙罩茶燈"),"Owner switches it off through the shared floor-lamp action")
	expect(world.state.objects[World.key(SITE)].get("lamp_off")==true,"Off is stored as the existing lamp_off flag")

	# --- save and reload keep the switch state ------------------------------------------
	var saved:=World.new()
	expect(saved.load_world(path) and saved.state.objects.get(World.key(SITE),{}).get("type")==LAMP and saved.state.objects[World.key(SITE)].get("lamp_off",false),"Save and reload keep the lamp and its off state")
	var plan:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"茶燈",World.BUILD,World.NAMES)
	expect(plan.ok and plan.blueprint.pieces==[{"kind":LAMP,"x":0,"y":0}],"Blueprint captures a single lamp")
	expect(act(owner,"floor_lamp_toggle",SITE).ok and not lamp_off(SITE),"Owner switches it back on")

	# --- original floor lamp is untouched -----------------------------------------------
	person.x=44.5
	person.y=34.5
	var original:=act(owner,"build",FLOOR_SITE,FLOOR_LAMP)
	expect(original.ok and type_at(FLOOR_SITE)==FLOOR_LAMP,"The original warm-wood floor lamp still places: "+str(original.get("message","")))
	expect(inventory_is({"wood":0,"stone":0}),"Floor lamp keeps its own recipe")
	person.x=FLOOR_SITE.x+0.5
	person.y=FLOOR_SITE.y-0.5
	var floor_off:=act(owner,"floor_lamp_toggle",FLOOR_SITE)
	expect(floor_off.ok and lamp_off(FLOOR_SITE) and str(floor_off.message)=="關上暖木落地燈。" and not lamp_off(SITE),"The floor lamp toggles by itself with its original wording")
	expect(not act(guest,"floor_lamp_toggle",FLOOR_SITE).ok,"A visitor still cannot switch the floor lamp")
	expect(act(owner,"floor_lamp_toggle",FLOOR_SITE).ok and not lamp_off(FLOOR_SITE),"The floor lamp switches back on")
	person.x=41.5
	person.y=33.5

	# --- rendered checks ---------------------------------------------------------------
	app._select_tool("hoe")
	var graphical:=DisplayServer.get_name()!="headless"
	var day:Image
	var lit:Color
	var dark:Color
	if graphical:
		day=await frame("paper-tea-lamp-day")
		var day_bare:Color=day.get_pixelv(glow_point(SITE))
		world.state.time=1260.0
		app.session._send_snapshot(1)
		var night:=await frame("paper-tea-lamp-night")
		var glow:=glow_point(SITE)
		var body:=body_point(SITE)
		lit=night.get_pixelv(glow)
		var body_lit:Color=night.get_pixelv(body)
		expect(not day_bare.is_equal_approx(lit),"Night changes the ground around the lamp")
		var steady:=true
		var steady_body:=true
		for index in 3:
			var next:=await frame("paper-tea-lamp-steady-%d"%index)
			var again:=next.get_pixelv(glow)
			steady=steady and absf(again.r-lit.r)<0.004 and absf(again.g-lit.g)<0.004 and absf(again.b-lit.b)<0.004
			steady_body=steady_body and absf(next.get_pixelv(body).r-body_lit.r)<0.004 and absf(next.get_pixelv(body).g-body_lit.g)<0.004
		expect(steady,"The warm glow is pixel-stable across frames (no sway or pulse)")
		expect(steady_body,"The lamp sprite is pixel-stable across frames")
		# Off: halo disappears and the sprite dims through the existing tint.
		person.x=SITE.x+0.5
		person.y=SITE.y-0.5
		expect(act(owner,"floor_lamp_toggle",SITE).ok and lamp_off(SITE),"Owner turns the lamp off at night")
		person.x=41.5
		person.y=33.5
		app.session._send_snapshot(1)
		var dim:=await frame("paper-tea-lamp-off")
		expect(lit.r-dim.get_pixelv(glow).r>0.04,"Switching off removes the warm halo at night")
		expect(body_lit.get_luminance()-dim.get_pixelv(body).get_luminance()>0.01,"Switching off dims the sprite through the shared tint")
		person.x=SITE.x+0.5
		person.y=SITE.y-0.5
		expect(act(owner,"floor_lamp_toggle",SITE).ok and not lamp_off(SITE),"Owner turns the lamp back on")
		person.x=41.5
		person.y=33.5
		app.session._send_snapshot(1)
		var back:=await frame("paper-tea-lamp-on-again")
		var back_glow:Color=back.get_pixelv(glow)
		expect(absf(back_glow.r-lit.r)<0.004 and absf(back_glow.g-lit.g)<0.004,"Turning it back on restores the identical glow")

	# --- move, undo -------------------------------------------------------------------
	person.x=42.5
	person.y=33.5
	var moved:=act(owner,"move_object",SITE,"%d,%d"%[MOVED.x,MOVED.y])
	expect(moved.ok and type_at(MOVED)==LAMP and type_at(SITE)=="" and inventory_is({"bamboo":8,"cotton_cloth":4,"copper_ingot":2}),"Owner moves the lamp without extra cost: "+str(moved.get("message","")))
	expect(world.state.objects.get(World.key(MOVED),{}).get("owner")==owner,"Moving keeps ownership")
	var undo_move:=world.undo_summary(owner)
	expect(undo_move.get("available",false) and undo_move.get("id","")!="","Undo is offered after a move")
	expect(act(owner,World.UNDO_ACTION,Vector2i.ZERO,str(undo_move.get("id",""))).ok and type_at(SITE)==LAMP and type_at(MOVED)=="","Undo puts the lamp back")
	if graphical:
		var returned:=await frame("paper-tea-lamp-undone-move")
		expect(absf(returned.get_pixelv(glow_point(SITE)).r-lit.r)<0.004,"The undone lamp renders the same glow at its original cell")

	# --- remove, undo, refund ----------------------------------------------------------
	var removed:=act(owner,"remove",SITE)
	expect(removed.ok and type_at(SITE)=="" and inventory_is({"bamboo":12,"cotton_cloth":6,"copper_ingot":3}),"Owner dismantles it and receives exactly one full refund")
	app.session._send_snapshot(1)
	if graphical:
		var bare:=await frame("paper-tea-lamp-removed")
		expect(lit.r-bare.get_pixelv(glow_point(SITE)).r>0.04,"With the lamp removed the warm halo is gone")
		world.state.time=720.0
		app.session._send_snapshot(1)
		var noon:=await frame()
		expect(absf(noon.get_pixelv(glow_point(SITE)).r-day.get_pixelv(glow_point(SITE)).r)<0.02,"Daylight shows no pool on that spot")
		world.state.time=1260.0
		app.session._send_snapshot(1)
	var undo_remove:=world.undo_summary(owner)
	expect(act(owner,World.UNDO_ACTION,Vector2i.ZERO,str(undo_remove.get("id",""))).ok and type_at(SITE)==LAMP and inventory_is({"bamboo":8,"cotton_cloth":4,"copper_ingot":2}),"Undoing the removal restores the lamp and re-charges the refund")
	var final_save:=World.new()
	expect(final_save.load_world(path) and final_save.state.objects.get(World.key(SITE),{}).get("type")==LAMP,"The restored lamp is also in the saved file")
	await finish()
