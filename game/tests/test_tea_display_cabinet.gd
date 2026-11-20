extends SceneTree

# T06 茶葉展示櫃. Native headless by default; pixel checks run only on a real renderer.
# Optional: --qa-dir=<folder> saves screenshots, --qa-size=1024 uses a 1024x640 window.

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.TEA_DISPLAY_CABINET
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(40,36)
const VERT:=Vector2i(44,34)
const COST:={"bamboo":12,"glass":4}
const WIDE_ART:="res://assets/ui-life/tea-display-cabinet-wide.png"
const LONG_ART:="res://assets/ui-life/tea-display-cabinet-long.png"
const GUEST:="tea-cabinet-guest"
var app
var world:World
var owner:String
var person:Dictionary
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

func act(action:String,at:Vector2i,extra:="",actor:="")->Dictionary:
	request+=1
	return world.act(owner if actor.is_empty() else actor,"tea-cabinet-%d"%request,action,at,extra)

func stock(at:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(at),{}).get("items",{})

func bag(item:String)->int:
	return int(person.inventory.get(item,0))

func cabinets()->int:
	var total:=0
	for obj:Dictionary in world.state.objects.values():
		if obj.get("type")==KIND and Industry.square_part(obj)==0:total+=1
	return total

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func texture_ok(art_path:String,size:Vector2)->void:
	var texture:=load(art_path) as Texture2D
	if not expect(texture!=null and texture.get_size()==size,"%s imports as a %dx%d texture"%[art_path.get_file(),int(size.x),int(size.y)]):return
	var image:=texture.get_image()
	var last:=Vector2i(int(size.x)-1,int(size.y)-1)
	var clear_corners:=0
	for corner:Vector2i in [Vector2i.ZERO,Vector2i(last.x,0),Vector2i(0,last.y),last]:
		if image.get_pixelv(corner).a<0.01:clear_corners+=1
	expect(clear_corners>=2 and image.get_pixelv(last/2).a>0.95,art_path.get_file()+" has a cut-out silhouette and opaque cabinet")

func pixel(cell:Vector2i,offset:Vector2)->Vector2i:
	var local:Vector2=app.view.screen(Vector2(cell)+offset)
	return Vector2i((local*app.view.view_zoom()).round())

func frame(capture_name:="")->Image:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty() and not capture_name.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(capture_name+".png"))==OK,"Screenshot "+capture_name)
	return image

## Mean absolute colour difference over the three counter-top spaces of a horizontal cabinet.
func spots_difference(a:Image,b:Image,cell:Vector2i)->float:
	var total:=0.0
	var samples:=0
	for spot:Vector2 in app.view.TEA_CABINET_WIDE_SPOTS:
		var centre:=pixel(cell,(Vector2(app.view.TEA_CABINET_WIDE_AT)+spot)/32.0)
		for dy in range(-3,4):
			for dx in range(-3,4):
				var at:=centre+Vector2i(dx,dy)
				if at.x<0 or at.y<0 or at.x>=a.get_width() or at.y>=a.get_height():continue
				var one:=a.get_pixelv(at)
				var two:=b.get_pixelv(at)
				total+=absf(one.r-two.r)+absf(one.g-two.g)+absf(one.b-two.b)
				samples+=1
	return total/float(maxi(samples,1))

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.22).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("TEA_DISPLAY_CABINET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://tea-display-cabinet-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="tea-cabinet-owner"
	if app.session.host(0,"茶葉展示櫃測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	person=world.state.players[owner]
	person.x=42.5
	person.y=35.5
	person.inventory={"bamboo":24,"glass":8,"mist_tea":4,"quality_mist_tea":2,"tea_leaf":2,"tea_light":1,"tea_deep":1,"tea_jar":2,"tea_returned_jar":1,"tea_worn_jar":1,"wood":3}
	world.state.time=720.0
	for cell:Vector2i in [SITE,SITE+Vector2i.RIGHT,MOVED,MOVED+Vector2i.RIGHT,VERT,VERT+Vector2i.DOWN]:world.state.removed[World.key(cell)]=true
	app.session._send_snapshot(1)

	# --- data, catalogue and art contract ---------------------------------------------
	var recipe:Dictionary=World.BUILD.get(KIND,{})
	var cost:=recipe.duplicate()
	cost.erase("name")
	expect(KIND=="tea_display_cabinet" and recipe.get("name")=="茶葉展示櫃" and cost==COST,"Industry.TEA_DISPLAY_CABINET costs bamboo 12 and glass 4")
	expect(KIND in Industry.TWO_CELL_STATIONS and KIND in Industry.ORIENTABLE_FOOTPRINTS and Industry.station_cells(KIND,false)==[Vector2i.ZERO,Vector2i.RIGHT] and Industry.station_cells(KIND,true)==[Vector2i.ZERO,Vector2i.DOWN],"It is a 2x1 piece that can also stand vertically")
	expect(Industry.square_part_field(KIND)=="tea_cabinet_part" and Industry.vertical_field(KIND)=="tea_cabinet_vertical","Footprint fields are cabinet specific")
	expect(Industry.TEA_CABINET_SLOTS==3,"There are three display spaces")
	for jar:String in ["tea_jar","tea_returned_jar","tea_worn_jar","tea_spent_jar","mist_tea_brew","tea_pudding"]:
		expect(jar not in Industry.TEA_CABINET_TEAS,jar+" is not displayable")
	for tea:String in Industry.TEA_CABINET_TEAS:
		expect(World.NAMES.has(tea) and World.ITEM_CATALOG.is_known(tea),tea+" is a known inventory item")
	expect(Industry.tea_cabinet_slots({"mist_tea":2,"quality_mist_tea":1})==["mist_tea","mist_tea","quality_mist_tea"],"Quantities expand into one space per unit in a stable order")
	expect(Industry.valid_tea_cabinet_items({"mist_tea":3}) and not Industry.valid_tea_cabinet_items({"mist_tea":2,"tea_leaf":2}) and not Industry.valid_tea_cabinet_items({"tea_jar":1}) and not Industry.valid_tea_cabinet_items({"mist_tea":0}) and not Industry.valid_tea_cabinet_items({"mist_tea":1.5}),"Item validation enforces tea kind, whole counts and the three-unit cap")
	texture_ok(WIDE_ART,Vector2(62,43))
	texture_ok(LONG_ART,Vector2(30,69))
	var folio:=preload("res://scripts/build_folio.gd")
	expect(folio.TEA_COLLECTION.has(KIND) and folio.PLACEMENT_NOTES.has(KIND),"The tea category lists the cabinet with a placement note")
	expect(preload("res://scripts/life_ui_panels.gd").FURNITURE.has(KIND),"The furniture list includes the cabinet")
	expect(KIND in World.UNDO_SOLID,"The cabinet is solid for undo and placement checks")

	# --- native build menu -------------------------------------------------------------
	app._build_menu()
	var tea_name:String=preload("res://scripts/build_style_catalog.gd").style("tea_house").name
	var picked:=false
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text==tea_name:
			entry.pressed.emit()
			var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"),true,false) as Button
			if slot!=null:
				slot.pressed.emit()
				picked=true
			break
	expect(picked,"The tea page shows a build slot for the cabinet")
	if picked:
		var place:=app.modal.find_child("BuildPlace",true,false) as Button
		if expect(place!=null and not place.disabled,"The build button is enabled with the stated recipe"):place.pressed.emit()
		expect(app.building==KIND and app.view.build_placement_offsets(KIND)==[Vector2i.ZERO,Vector2i.RIGHT],"Selecting it previews two cells")
	if is_instance_valid(app.modal):app._close_modal()

	# --- build -------------------------------------------------------------------------
	var built:=act("build",SITE,KIND)
	if not expect(built.ok and stock(SITE).is_empty(),"Owner builds the cabinet empty: "+str(built.get("message",""))):
		await finish()
		return
	expect(bag("bamboo")==12 and bag("glass")==4,"One placement consumes exactly the recipe")
	var anchor:Dictionary=world.state.objects[World.key(SITE)]
	var second:Dictionary=world.state.objects.get(World.key(SITE+Vector2i.RIGHT),{})
	expect(anchor.owner==owner and anchor.get("tea_cabinet_part")==0 and second.get("tea_cabinet_part")==1 and World.station_anchor(world.state.objects,SITE+Vector2i.RIGHT)==SITE,"Two linked cells share one anchor")
	expect(not world.can_stand(Vector2(SITE)+Vector2(0.5,0.5)) and not world.can_stand(Vector2(SITE+Vector2i.RIGHT)+Vector2(0.5,0.5)),"Both cells block walking")

	# --- native UI ---------------------------------------------------------------------
	app.session._send_snapshot(1)
	app._interact()
	var picker:=app.modal.find_child("TeaCabinetPicker",true,false) as OptionButton if is_instance_valid(app.modal) else null
	var put:=app.modal.find_child("TeaCabinetPut",true,false) as Button if is_instance_valid(app.modal) else null
	if expect(picker!=null and put!=null,"Interaction opens the owner's cabinet with a tea picker"):
		for number in 3:expect(app.modal.find_child("TeaCabinetTake_%d"%number,true,false)!=null,"Space %d has a take button"%(number+1))
		var count:=app.modal.find_child("TeaCabinetCount",true,false) as Label
		expect(count!=null and count.text.contains("0／3"),"The empty cabinet reads 0／3")
		var chosen:=false
		for index in picker.item_count:
			if picker.get_item_metadata(index)=="mist_tea":
				picker.select(index)
				chosen=true
				break
		expect(chosen and picker.get_item_text(picker.selected).contains("×4"),"The picker shows the item and how many are in the bag")
		put.pressed.emit()
		await process_frame
		expect(stock(SITE)=={"mist_tea":1} and bag("mist_tea")==3,"The UI moves one real unit out of the bag")
		var title:=app.modal.find_child("TeaCabinetTitle_0",true,false) as Label if is_instance_valid(app.modal) else null
		count=app.modal.find_child("TeaCabinetCount",true,false) as Label if is_instance_valid(app.modal) else null
		expect(title!=null and title.text==World.NAMES.mist_tea and count!=null and count.text.contains("1／3") and count.text.contains("×1"),"Space 1 shows the tea and the count reads 1／3")
	if is_instance_valid(app.modal):app._close_modal()

	# --- put rules ---------------------------------------------------------------------
	for bad:String in ["tea_jar","tea_returned_jar","tea_worn_jar","wood","mist_tea_brew","","nonsense"]:
		expect(not act(Industry.TEA_CABINET_PUT,SITE,bad).ok,"Rejects non-display item '%s'"%bad)
	expect(stock(SITE)=={"mist_tea":1} and bag("tea_jar")==2 and bag("wood")==3,"Rejected puts change nothing")
	expect(act(Industry.TEA_CABINET_PUT,SITE+Vector2i.RIGHT,"mist_tea").ok,"The same tea can fill a second space, through the far cell")
	expect(act(Industry.TEA_CABINET_PUT,SITE,"quality_mist_tea").ok,"A different tea takes the third space")
	var shown:={"mist_tea":2,"quality_mist_tea":1}
	expect(stock(SITE)==shown and bag("mist_tea")==2 and bag("quality_mist_tea")==1,"Three units moved out of the bag and into the cabinet")
	expect(Industry.tea_cabinet_slots(stock(SITE))==["mist_tea","mist_tea","quality_mist_tea"],"The three spaces read mist tea, mist tea, quality mist tea")
	expect(not act(Industry.TEA_CABINET_PUT,SITE,"tea_leaf").ok and not stock(SITE).has("tea_leaf") and bag("tea_leaf")==2,"A fourth unit stays in the bag")
	expect(not act(Industry.TEA_CABINET_PUT,MOVED,"tea_leaf").ok,"Cannot put onto empty ground")
	expect(not act(Industry.TEA_CABINET_TAKE,SITE,"tea_leaf").ok,"Cannot take a tea that is not displayed")
	var stale:=world.undo_summary(owner)
	expect(not stale.get("available",false),"Using a display closes the build's undo record")
	expect(not act(World.UNDO_ACTION,Vector2i.ZERO,str(stale.get("id",""))).ok and stock(SITE)==shown and bag("bamboo")==12,"A stale undo cannot delete stocked tea")
	var before_total:=bag("mist_tea")+bag("quality_mist_tea")+Industry.tea_cabinet_total(stock(SITE))
	expect(before_total==6,"Tea is conserved between bag and cabinet")

	# --- owner only, visitors can view -------------------------------------------------
	world.add_player(GUEST,"訪客",Vector2(41.5,35.5))
	var guest:Dictionary=world.state.players[GUEST]
	guest.inventory={"mist_tea":2}
	expect(not act(Industry.TEA_CABINET_TAKE,SITE,"mist_tea",GUEST).ok and not act(Industry.TEA_CABINET_PUT,SITE,"mist_tea",GUEST).ok and stock(SITE)==shown and int(guest.inventory.mist_tea)==2,"A nearby visitor can neither take nor add tea")
	expect(not act("remove",SITE,"",GUEST).ok and not act("move_object",SITE,World.key(MOVED),GUEST).ok and stock(SITE)==shown and world.state.objects.has(World.key(SITE)),"A visitor cannot dismantle or move it")
	person.x=48.5
	expect(not act(Industry.TEA_CABINET_PUT,SITE,"quality_mist_tea").ok and not act(Industry.TEA_CABINET_TAKE,SITE,"mist_tea").ok,"The owner must stand close to the cabinet")
	person.x=42.5
	app.session._send_snapshot(1)
	var seen:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(SITE),{})
	expect(seen.get("type")==KIND and seen.get("items",{})==shown and not seen.has("locked"),"The multiplayer snapshot shows the displayed tea to everyone")
	var seen_far:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(SITE+Vector2i.RIGHT),{})
	expect(seen_far.get("tea_cabinet_part")==1 and seen_far.get("items",{}).is_empty(),"The snapshot keeps the far cell empty")

	# --- stock protection --------------------------------------------------------------
	expect(not act("remove",SITE).ok and not act("remove",SITE+Vector2i.RIGHT).ok and stock(SITE)==shown and bag("bamboo")==12,"Demolition from either cell is refused while tea is displayed")
	for day in 3:expect(world.step(World.WEATHER.DAY_SECONDS,true),"Advance a normal day")
	expect(stock(SITE)==shown,"Displayed tea does not spoil or get consumed")

	# --- save and secure schema --------------------------------------------------------
	expect(world.save(),"The world saves with a stocked cabinet")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[World.key(SITE)].items==shown and loaded.state.objects[World.key(SITE+Vector2i.RIGHT)].tea_cabinet_part==1,"Stock and footprint survive a real reload")
	var base:=world.state.duplicate(true)
	expect(valid(base),"The live state validates")
	var tampered:=base.duplicate(true)
	tampered.objects[World.key(SITE+Vector2i.RIGHT)].items={"mist_tea":1}
	expect(not valid(tampered),"The far cell cannot secretly store tea")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].items={"tea_jar":1}
	expect(not valid(tampered),"A jar cannot be saved on the cabinet")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].items={"mist_tea":2,"tea_leaf":2}
	expect(not valid(tampered),"More than three units cannot be saved")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].items={"mist_tea":1.5}
	expect(not valid(tampered),"A fractional quantity is rejected")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].items={"mist_tea":-1}
	expect(not valid(tampered),"A negative quantity is rejected")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].tea_cabinet_vertical="yes"
	expect(not valid(tampered),"A non-boolean orientation is rejected")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].erase("tea_cabinet_part")
	expect(not valid(tampered),"A cabinet without its footprint marker is rejected")
	tampered=base.duplicate(true)
	tampered.objects[World.key(SITE)].type="chest"
	expect(not valid(tampered),"Another object cannot borrow the cabinet's linked fields")

	# --- rendering ---------------------------------------------------------------------
	app._select_tool("hoe")
	var graphical:=DisplayServer.get_name()!="headless"
	if graphical:
		app.session._send_snapshot(1)
		app._interact()
		var full_count:=app.modal.find_child("TeaCabinetCount",true,false) as Label if is_instance_valid(app.modal) else null
		expect(full_count!=null and full_count.text.contains("3／3"),"The owner sees all three occupied places")
		if full_count!=null:
			await frame("tea-cabinet-owner-menu")
			var hint:=app.modal.find_child("TeaCabinetHint",true,false) as Label
			var scroll:Node=hint.get_parent() if hint!=null else null
			while scroll!=null and not scroll is ScrollContainer:scroll=scroll.get_parent()
			expect(scroll is ScrollContainer and (scroll as ScrollContainer).get_global_rect().encloses(hint.get_global_rect()),"The help line is fully visible without scrolling")
		if is_instance_valid(app.modal):app._close_modal()
		var stocked:=await frame("tea-cabinet-stocked")
		var taken:=[]
		for tea:String in ["mist_tea","mist_tea","quality_mist_tea"]:taken.append(act(Industry.TEA_CABINET_TAKE,SITE,tea).ok)
		expect(not taken.has(false) and stock(SITE).is_empty(),"The owner retrieves all three units")
		app.session._send_snapshot(1)
		var bare:=await frame("tea-cabinet-empty")
		expect(spots_difference(stocked,bare,SITE)>0.01,"The counter top visibly changes when the tea leaves")
		for tea:String in ["mist_tea","mist_tea","quality_mist_tea"]:act(Industry.TEA_CABINET_PUT,SITE,tea)
		app.session._send_snapshot(1)
	else:
		for tea:String in ["mist_tea","mist_tea","quality_mist_tea"]:expect(act(Industry.TEA_CABINET_TAKE,SITE,tea).ok,"Retrieve "+tea)
		expect(stock(SITE).is_empty() and bag("mist_tea")==4 and bag("quality_mist_tea")==2,"All tea returns to the bag exactly")
		for tea:String in ["mist_tea","mist_tea","quality_mist_tea"]:act(Industry.TEA_CABINET_PUT,SITE,tea)

	# --- move with stock ---------------------------------------------------------------
	var bag_before:Dictionary=person.inventory.duplicate()
	var moved:=act("move_object",SITE+Vector2i.RIGHT,World.key(MOVED))
	expect(moved.ok and stock(MOVED)==shown and not world.state.objects.has(World.key(SITE)) and not world.state.objects.has(World.key(SITE+Vector2i.RIGHT)),"Moving from the far cell carries all three units: "+str(moved.get("message","")))
	expect(person.inventory==bag_before and cabinets()==1,"Moving costs nothing and leaves exactly one cabinet")
	expect(world.state.objects[World.key(MOVED+Vector2i.RIGHT)].get("tea_cabinet_part")==1 and World.station_anchor(world.state.objects,MOVED+Vector2i.RIGHT)==MOVED,"The moved footprint is intact")

	# --- blueprint is shape-only and empty ---------------------------------------------
	var copy:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(MOVED,Vector2i(2,1)),"茶葉展示櫃",World.BUILD,World.NAMES)
	expect(copy.ok and copy.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"Blueprint captures one cabinet and none of its tea")
	if copy.ok:
		var quote:=world.quote_blueprint(owner,copy.blueprint,VERT,1)
		if expect(quote.ok,"Quote a rotated cabinet: "+str(quote.get("message",""))):
			var result:=world.apply_blueprint(owner,"e".repeat(32),copy.blueprint,VERT,1,quote.hash)
			var upright:Dictionary=world.state.objects.get(World.key(VERT),{})
			expect(result.ok and Industry.is_vertical(upright) and upright.get("items",{}).is_empty(),"The rotated blueprint builds an empty vertical cabinet")
			expect(World.station_anchor(world.state.objects,VERT+Vector2i.DOWN)==VERT and stock(MOVED)==shown and cabinets()==2,"The original keeps its tea and nothing is duplicated")
			expect(act(Industry.TEA_CABINET_PUT,VERT+Vector2i.DOWN,"tea_deep").ok and stock(VERT)=={"tea_deep":1} and bag("tea_deep")==0,"A vertical cabinet accepts tea from its second cell")
			expect(valid(world.state.duplicate(true)),"A vertical stocked cabinet validates")
			app.session._send_snapshot(1)
			if graphical:await frame("tea-cabinet-vertical")
			expect(act(Industry.TEA_CABINET_TAKE,VERT,"tea_deep").ok and bag("tea_deep")==1,"The vertical cabinet gives its tea back")
			expect(act("remove",VERT+Vector2i.DOWN).ok and not world.state.objects.has(World.key(VERT)) and not world.state.objects.has(World.key(VERT+Vector2i.DOWN)),"The empty vertical cabinet can be removed")

	# --- full bag keeps the tea safe, then clean removal --------------------------------
	person.inventory.mist_tea=1000000000
	expect(not act(Industry.TEA_CABINET_TAKE,MOVED,"mist_tea").ok and stock(MOVED)==shown,"A full bag keeps the tea on the display")
	person.inventory.mist_tea=2
	for tea:String in ["mist_tea","mist_tea","quality_mist_tea"]:expect(act(Industry.TEA_CABINET_TAKE,MOVED+Vector2i.RIGHT,tea).ok,"Retrieve "+tea+" from the second cell")
	expect(stock(MOVED).is_empty() and bag("mist_tea")==4 and bag("quality_mist_tea")==2,"Every unit returns exactly once")
	expect(not act(Industry.TEA_CABINET_TAKE,MOVED,"mist_tea").ok,"Tea cannot leave the cabinet twice")
	var bamboo_before:=bag("bamboo")
	var glass_before:=bag("glass")
	expect(act("remove",MOVED+Vector2i.RIGHT).ok and bag("bamboo")==bamboo_before+12 and bag("glass")==glass_before+4,"Dismantling the empty cabinet refunds the full recipe")
	expect(cabinets()==0 and not world.state.objects.has(World.key(MOVED)),"No cabinet remains")
	var final_save:=World.new()
	expect(world.save() and final_save.load_world(path) and final_save.state.objects.get(World.key(MOVED))==null,"The cleaned-up world reloads")
	await finish()
