extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Design=preload("res://scripts/blueprint_design.gd")
const KIND:="cedar_bed"
const MARK:="home_rest_cell"
const SITE:=Vector2i(40,34)           ## vertical by default: (40,34) and (40,35)
const SECOND:=SITE+Vector2i.DOWN
const OTHER:=Vector2i(43,34)          ## a second cedar bed, for replace-the-mark
const MOVED:=Vector2i(46,34)
const COPY:=Vector2i(40,38)           ## blueprint copy, same orientation
const ROTATED:=COPY                    ## same site after removing the vertical copy
const OLD:=COPY                        ## one-cell legacy bed, removed before blueprint tests
const GUEST:="cedar-bed-guest"
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.3).timeout
	app.view.queue_redraw()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("CEDAR_BED_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE,source:World=null)->Dictionary:
	return (world if source==null else source).state.objects.get(World.key(tile),{})

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

func stand_by(token:String,cell:Vector2i)->void:
	stand_at(token,float(cell.x)+1.5,float(cell.y)+0.5)

func marked(source:World=null)->String:
	return str((world if source==null else source).state.players[owner].get(MARK,""))

func energy(token:String)->int:
	return int(world.state.players[token].get("mine_energy",0))

func widget(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control if is_instance_valid(app.modal) else null

func modal_text()->String:
	var text:=""
	if not is_instance_valid(app.modal):return text
	for node in app.modal.find_children("*","Label",true,false):text+=str(node.text)+"\n"
	for node in app.modal.find_children("*","Button",true,false):text+=str(node.text)+"\n"
	return text

func focus_camera(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(0.5,1.0))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

## Real _interact for the owner, standing beside the given cell.
func open_from(cell:Vector2i)->void:
	app.session.peers[1]=owner
	stand_by(owner,cell)
	app.session._send_snapshot(1)
	app._close_modal()
	app._interact()

func open_as_guest(cell:Vector2i)->void:
	stand_by(GUEST,cell)
	app._close_modal()
	app.session.peers[1]=owner
	var public_owner:String=app.session._public_actor(owner)
	var guest_view:Dictionary=app.session.public_state("home",GUEST)
	expect(guest_view.players.has(public_owner) and not guest_view.players[public_owner].has(MARK),"The visible owner's private preference is withheld from guests")
	app.session.peers[1]=GUEST
	app.session._send_snapshot(1)
	app._interact()

func clock()->String:
	return var_to_str([world.state.time,world.state.get("day",null)])

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://cedar-bed-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="cedar-bed-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,"原木木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	for origin in [SITE,OTHER,MOVED,COPY,ROTATED,OLD]:
		for offset in [Vector2i.ZERO,Vector2i.DOWN,Vector2i.RIGHT,Vector2i.ONE]:world.state.removed[World.key(origin+offset)]=true
	person.inventory.merge({"wood":200,"fiber":120},true)
	person.mine_energy=20
	world.state.time=720.0
	stand_by(owner,SITE)
	world.add_player(GUEST,"路過的訪客",Vector2(SITE.x+1.5,SITE.y+1.5))
	var guest:Dictionary=world.state.players[GUEST]
	guest.mine_energy=33
	app.session._send_snapshot(1)

	# --- Contract: constant, name, recipe --------------------------------------------------------------
	expect(Industry.CEDAR_BED==KIND,"INDUSTRY.CEDAR_BED is cedar_bed")
	if not expect(World.BUILD.has(KIND),"The cedar bed has a recipe"):
		await finish()
		return
	expect(World.BUILD[KIND].get("name")=="原木小床","The display name is 原木小床")
	expect(World.BUILD[KIND].get("wood")==15 and World.BUILD[KIND].get("fiber")==10 and World.BUILD[KIND].size()==3,"Recipe is exactly 15 wood and 10 fiber plus the name")
	expect(World.BUILD.has("bed") and World.BUILD.bed.get("wood")==15 and World.BUILD.bed.get("fiber")==10,"The old bed recipe still exists")

	# --- Insufficient materials change nothing ----------------------------------------------------------
	var bag:Dictionary=person.inventory.duplicate(true)
	person.inventory.wood=14
	expect(not world.act(owner,"poor-wood","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==14 and person.inventory.fiber==bag.fiber,"14 wood is refused and nothing is spent")
	person.inventory.wood=bag.wood
	person.inventory.fiber=9
	expect(not world.act(owner,"poor-fiber","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==bag.wood and person.inventory.fiber==9,"9 fiber is refused and nothing is spent")
	person.inventory.fiber=bag.fiber

	# --- Home-only construction -----------------------------------------------------------------------
	person.region=World.REGIONS.LANYANG
	expect(not world.act(owner,"away-build","build",SITE,KIND).ok and obj().is_empty() and person.inventory.wood==bag.wood and person.inventory.fiber==bag.fiber,"Away from home the cedar bed cannot be built and costs nothing")
	person.region=World.REGIONS.HOME
	app.session._send_snapshot(1)

	# --- Build: recipe, vertical by default, two solid halves, one anchor -----------------------------------
	var player_shape:=person.keys()
	player_shape.sort()
	expect(not person.has(MARK),"Fixture: a fresh player has no home_rest_cell (older-save shape)")
	app._select_tool("hoe")
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the bed for its owner"):
		await finish()
		return
	expect(person.inventory.wood==bag.wood-15 and person.inventory.fiber==bag.fiber-10,"Building spends exactly 15 wood and 10 fiber")
	expect(Industry.is_vertical(obj()),"A normal build is vertical by default")
	expect(obj(SECOND).get("type")==KIND,"The second half is the same bed, directly below")
	expect(world.blocked(SITE) and world.blocked(SECOND),"Both halves are solid")
	expect(not world.blocked(SITE+Vector2i.RIGHT) and not world.blocked(SECOND+Vector2i.RIGHT) and not world.blocked(SECOND+Vector2i.DOWN),"It occupies exactly two cells")
	expect(World.station_anchor(world.state.objects,SITE)==SITE and World.station_anchor(world.state.objects,SECOND)==SITE,"Both halves resolve to one anchor")
	expect(not world.act(owner,"overlap","build",SECOND,KIND).ok and person.inventory.wood==bag.wood-15,"A second bed cannot overlap and costs nothing")
	expect(not person.has(MARK) and marked()=="","Building alone marks nothing")
	expect(World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The world with an unmarked cedar bed passes save validation")
	focus_camera(SITE)
	app.view.set_process(false)
	await capture("cedar-bed-placed")

	# --- Old id "bed": still valid, still one tile ------------------------------------------------------------
	var wood_before_old:int=person.inventory.wood
	stand_by(owner,OLD)
	expect(world.act(owner,"old-bed","build",OLD,"bed").ok and obj(OLD).get("type")=="bed","The old bed id can still be built")
	expect(person.inventory.wood==wood_before_old-15,"The old bed still costs 15 wood")
	expect(obj(OLD+Vector2i.DOWN).is_empty() and obj(OLD+Vector2i.RIGHT).is_empty(),"The old bed stays a single tile")
	expect(World.station_anchor(world.state.objects,OLD)==OLD,"The old bed is its own anchor")
	expect(World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The world with an old bed still passes save validation")
	var old_probe:=world.act(owner,"old-bed-mark","cedar_bed",OLD,"mark")
	expect(not old_probe.ok and marked()=="","The cedar_bed action does not turn an old bed into a rest point")
	expect(not world.act(owner,"old-bed-rest","cedar_bed",OLD,"rest").ok or energy(owner)==20,"The cedar_bed action does not rest on an old bed")
	expect(world.act(owner,"old-bed-remove","remove",OLD).ok and obj(OLD).is_empty(),"The old bed can still be removed")
	stand_by(owner,SITE)

	# --- Rest on an UNMARKED bed, either half; no clock, no cost, no side effects ------------------------------
	var inv_before:=var_to_str(person.inventory)
	var clock_before:=clock()
	var guest_before:=var_to_str(guest)
	var objects_before:=var_to_str(world.state.objects)
	person.mine_energy=20
	expect(world.act(owner,"rest-top","cedar_bed",SITE,"rest").ok and energy(owner)==100,"Rest on the unmarked bed's top half restores 100 energy")
	person.mine_energy=5
	expect(world.act(owner,"rest-bottom","cedar_bed",SECOND,"rest").ok and energy(owner)==100,"Rest on the lower half restores 100 energy")
	expect(marked()=="" and not person.has(MARK),"Resting never marks the bed")
	expect(clock()==clock_before,"Resting does not advance the world clock")
	expect(var_to_str(person.inventory)==inv_before,"Resting costs no materials")
	expect(var_to_str(guest)==guest_before and energy(GUEST)==33,"Resting changes nothing for another player")
	expect(var_to_str(world.state.objects)==objects_before,"Resting changes no object")
	expect(world.act(owner,"rest-full","cedar_bed",SITE,"rest").ok and energy(owner)==100,"Resting at full energy is harmless")
	person.mine_energy=20
	expect(not world.act(owner,"no-extra","cedar_bed",SITE).ok and not world.act(owner,"bad-extra","cedar_bed",SITE,"sleep").ok and not world.act(owner,"empty-extra","cedar_bed",SITE,"").ok and energy(owner)==20 and marked()=="","Missing or unknown extras are rejected and change nothing")

	# --- Mark: either half, stores the anchor key ----------------------------------------------------------------
	expect(world.act(owner,"mark-bottom","cedar_bed",SECOND,"mark").ok and person.get(MARK)==World.key(SITE),"Marking by the lower half stores the ANCHOR key, not the half's")
	expect(clock()==clock_before and var_to_str(person.inventory)==inv_before and energy(owner)==20,"Marking costs nothing, takes no time and does not rest")
	expect(var_to_str(guest)==guest_before,"Marking changes nothing for another player")
	person.erase(MARK)
	expect(world.act(owner,"mark-top","cedar_bed",SITE,"mark").ok and person.get(MARK)==World.key(SITE),"Marking by the top half stores the same anchor key")
	expect(world.act(owner,"mark-again","cedar_bed",SECOND,"mark").ok and person.get(MARK)==World.key(SITE),"Marking the same bed twice is stable")
	expect(World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The world with a marked bed passes save validation")
	person.mine_energy=40
	expect(world.act(owner,"rest-marked","cedar_bed",SECOND,"rest").ok and energy(owner)==100 and person.get(MARK)==World.key(SITE),"Resting on the marked bed restores energy and keeps the mark")
	expect(clock()==clock_before,"Clock is still untouched after mark and rest")

	# --- Only the owner, only nearby, only in home --------------------------------------------------------------
	person.mine_energy=30
	stand_at(owner,SITE.x+9.5,SITE.y+9.5)
	expect(not world.act(owner,"far-rest","cedar_bed",SITE,"rest").ok and energy(owner)==30,"A distant owner cannot rest")
	expect(not world.act(owner,"far-mark","cedar_bed",SITE,"mark").ok and person.get(MARK)==World.key(SITE),"A distant owner cannot mark")
	stand_by(owner,SITE)
	person.region=World.REGIONS.LANYANG
	expect(not world.act(owner,"away-rest","cedar_bed",SITE,"rest").ok and energy(owner)==30,"Away from home the owner cannot rest on it")
	expect(not world.act(owner,"away-mark","cedar_bed",SITE,"mark").ok and person.get(MARK)==World.key(SITE),"Away from home the owner cannot mark it")
	person.region=World.REGIONS.HOME
	person.mine_energy=100
	guest.mine_energy=33
	stand_by(GUEST,SITE)
	var guest_shape:=var_to_str(guest)
	expect(not world.act(GUEST,"guest-rest","cedar_bed",SITE,"rest").ok and energy(GUEST)==33,"A visitor cannot rest on the owner's bed")
	expect(not world.act(GUEST,"guest-rest-low","cedar_bed",SECOND,"rest").ok and energy(GUEST)==33,"A visitor cannot rest by the lower half either")
	expect(not world.act(GUEST,"guest-mark","cedar_bed",SITE,"mark").ok and not guest.has(MARK) and person.get(MARK)==World.key(SITE),"A visitor cannot mark the owner's bed, and the owner's mark is untouched")
	expect(not world.act(GUEST,"guest-mark-low","cedar_bed",SECOND,"mark").ok and not guest.has(MARK),"A visitor cannot mark by the lower half either")
	expect(var_to_str(guest)==guest_shape,"Refused visitor actions leave the visitor record unchanged")
	expect(not world.act(GUEST,"guest-remove","remove",SITE).ok and obj().get("type")==KIND,"A visitor cannot dismantle the owner's bed")
	expect(not world.act(GUEST,"guest-move","move_object",SITE,World.key(MOVED)).ok and obj().get("type")==KIND and person.get(MARK)==World.key(SITE),"A visitor cannot move the owner's bed")

	# --- Real modal: owner sees both controls on EITHER half -----------------------------------------------------
	person.mine_energy=40
	for half in [SITE,SECOND]:
		open_from(half)
		if expect(is_instance_valid(app.modal) and app.modal.visible,"_interact beside half %s opens a modal"%str(half)):
			var mark_button:=widget("CedarBedMark") as Button
			var rest_button:=widget("CedarBedRest") as Button
			expect(mark_button!=null and rest_button!=null,"The owner sees CedarBedMark and CedarBedRest from half %s"%str(half))
	await capture("cedar-bed-owner-modal")
	# Real UI rest.
	var ui_clock:=clock()
	var ui_inv:=var_to_str(person.inventory)
	var ui_rest:=widget("CedarBedRest") as Button
	if ui_rest!=null:
		ui_rest.pressed.emit()
		expect(energy(owner)==100 and clock()==ui_clock and var_to_str(person.inventory)==ui_inv,"The real UI rest restores energy with no clock or cost")
	# Real UI mark on an unmarked bed.
	person.erase(MARK)
	open_from(SECOND)
	var ui_mark:=widget("CedarBedMark") as Button
	if ui_mark!=null:
		ui_mark.pressed.emit()
		expect(person.get(MARK)==World.key(SITE) and clock()==ui_clock,"The real UI mark stores the anchor with no clock change")
	app._close_modal()

	# --- Visitor modal: reason, no controls ----------------------------------------------------------------------
	var shown:=energy(GUEST)
	for half in [SITE,SECOND]:
		open_as_guest(half)
		if expect(is_instance_valid(app.modal) and app.modal.visible,"A visitor beside half %s still gets a modal"%str(half)):
			expect(widget("CedarBedMark")==null and widget("CedarBedRest")==null,"A visitor sees neither CedarBedMark nor CedarBedRest")
			expect(not modal_text().strip_edges().is_empty(),"A visitor is shown a reason")
	await capture("cedar-bed-visitor-modal")
	app._close_modal()
	app.session.peers[1]=owner
	app.session._send_snapshot(1)
	expect(energy(GUEST)==shown and not guest.has(MARK) and person.get(MARK)==World.key(SITE),"Looking at the modal changes nobody's state")

	# --- Another bed replaces the mark -----------------------------------------------------------------------------
	person.erase(MARK)
	stand_by(owner,OTHER)
	expect(world.act(owner,"build-other","build",OTHER,KIND).ok and obj(OTHER).get("type")==KIND,"A second cedar bed can be built")
	expect(not person.has(MARK),"Building a second bed marks nothing")
	stand_by(owner,SITE)
	expect(world.act(owner,"mark-first","cedar_bed",SITE,"mark").ok and person.get(MARK)==World.key(SITE),"The first bed is marked")
	stand_by(owner,OTHER)
	expect(world.act(owner,"mark-other","cedar_bed",OTHER+Vector2i.DOWN,"mark").ok and person.get(MARK)==World.key(OTHER),"Marking another bed REPLACES the mark")
	stand_by(owner,SITE)
	person.mine_energy=10
	expect(world.act(owner,"rest-first-unmarked","cedar_bed",SITE,"rest").ok and energy(owner)==100 and person.get(MARK)==World.key(OTHER),"The first bed is unmarked now but still lets the owner rest, without moving the mark")
	app.session._send_snapshot(1)
	focus_camera(SITE)
	await capture("cedar-bed-two-beds")

	# --- Removing an unmarked bed leaves the mark; removing the marked bed clears it ---------------------------------
	stand_by(owner,SITE)
	var wood_now:int=person.inventory.wood
	var fiber_now:int=person.inventory.fiber
	expect(world.act(owner,"remove-unmarked","remove",SECOND).ok and obj().is_empty() and obj(SECOND).is_empty(),"The unmarked bed is dismantled by its lower half")
	expect(person.inventory.wood==wood_now+15 and person.inventory.fiber==fiber_now+10,"Dismantling refunds the full recipe")
	expect(person.get(MARK)==World.key(OTHER),"Removing a different bed leaves the mark alone")
	expect(not world.blocked(SITE) and not world.blocked(SECOND),"Both cells are walkable again")
	expect(world.act(owner,"rebuild","build",SITE,KIND).ok and obj().get("type")==KIND,"The bed can be rebuilt")
	expect(person.get(MARK)==World.key(OTHER),"Rebuilding does not move the mark")

	# --- Persistence: reload keeps the mark; moving retargets; legacy save has no mark ---------------------------------
	expect(world.save(),"The world saves with a marked bed")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	expect(loaded.state.players[owner].get(MARK)==World.key(OTHER),"Reload keeps home_rest_cell")
	expect(obj(OTHER,loaded).get("type")==KIND and World.station_anchor(loaded.state.objects,OTHER+Vector2i.DOWN)==OTHER,"Reload keeps the vertical bed and its anchor")
	expect(Industry.is_vertical(obj(OTHER,loaded)) and loaded.blocked(OTHER) and loaded.blocked(OTHER+Vector2i.DOWN),"Reload keeps both halves solid")
	expect(str(loaded.state.players[GUEST].get(MARK,""))=="","Reload keeps the visitor unmarked")


	# --- Move retargets a marked bed; moving an unmarked bed does not mark --------------------------------------------
	stand_by(owner,OTHER)
	expect(world.act(owner,"mark-for-move","cedar_bed",OTHER,"mark").ok and person.get(MARK)==World.key(OTHER),"Fixture: the second bed is marked")
	var moved:=world.act(owner,"bed-move","move_object",OTHER+Vector2i.DOWN,World.key(MOVED))
	if expect(moved.ok,"The owner moves the marked bed by its lower half: "+str(moved.get("message",""))):
		expect(obj(OTHER).is_empty() and obj(OTHER+Vector2i.DOWN).is_empty(),"The old cells are cleared")
		expect(obj(MOVED).get("type")==KIND and obj(MOVED+Vector2i.DOWN).get("type")==KIND and Industry.is_vertical(obj(MOVED)),"The bed stands on both new cells and stays vertical")
		expect(world.blocked(MOVED) and world.blocked(MOVED+Vector2i.DOWN) and World.station_anchor(world.state.objects,MOVED+Vector2i.DOWN)==MOVED,"The moved bed is solid and resolves to its new anchor")
		expect(person.get(MARK)==World.key(MOVED),"Moving the marked bed retargets the saved coordinate to the new anchor")
		expect(world.save(),"The world saves after the move")
		var after_move:=World.new()
		expect(after_move.load_world(path) and after_move.state.players[owner].get(MARK)==World.key(MOVED),"The retargeted coordinate survives reload")
		var undo:=world.undo_summary(owner)
		expect(undo.available and world.act(owner,"undo-bed-move",World.UNDO_ACTION,Vector2i.ZERO,undo.id).ok,"The last bed move can be undone")
		expect(person.get(MARK)==World.key(OTHER) and obj(OTHER).get("type")==KIND,"Undoing the move restores the previous marked location")
		expect(world.act(owner,"redo-bed-move","move_object",OTHER+Vector2i.DOWN,World.key(MOVED)).ok,"The marked bed can be moved again")
		expect(not world.act(GUEST,"guest-steal-move","move_object",MOVED,World.key(OTHER)).ok and person.get(MARK)==World.key(MOVED),"A refused visitor move does not disturb the mark")
	stand_by(owner,SITE)
	var unmarked_move:=world.act(owner,"unmarked-move","move_object",SITE,World.key(OTHER))
	if expect(unmarked_move.ok,"The owner moves the UNMARKED bed: "+str(unmarked_move.get("message",""))):
		expect(person.get(MARK)==World.key(MOVED),"Moving an unmarked bed leaves the mark on the other bed")
		expect(world.act(owner,"unmarked-back","move_object",OTHER,World.key(SITE)).ok and obj().get("type")==KIND and person.get(MARK)==World.key(MOVED),"Moving it back also leaves the mark alone")

	# --- Blueprint: one piece, no preference, charged once, orientation honoured ---------------------------------------
	stand_by(owner,MOVED)
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(MOVED,Vector2i(1,2)),"原木小床",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND,"Blueprint captures the marked bed as one piece"):
		expect(cut.blueprint.width==1 and cut.blueprint.height==2,"The vertical bed is a 1x2 blueprint")
		var blueprint_text:=JSON.stringify(cut.blueprint).to_lower()
		expect(not ("rest" in blueprint_text) and not ("mark" in blueprint_text) and not ("home" in blueprint_text) and not (MARK in blueprint_text),"The blueprint stores no rest preference")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		if expect(turned.get("ok")==true and turned.blueprint.pieces.size()==1,"One quarter turn rotates the blueprint"):
			expect(turned.blueprint.width==2 and turned.blueprint.height==1,"The turned bed is a 2x1 blueprint")
		var before_mark:=str(person.get(MARK))
		stand_by(owner,COPY)
		var quote:=world.quote_blueprint(owner,cut.blueprint,COPY,0)
		if expect(quote.get("ok")==true,"Blueprint quote succeeds: "+str(quote.get("message",""))):
			var wood:int=person.inventory.wood
			var fiber:int=person.inventory.fiber
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,COPY,0,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.wood==wood-15 and person.inventory.fiber==fiber-10,"The blueprint charges exactly one recipe")
			expect(obj(COPY).get("type")==KIND and Industry.is_vertical(obj(COPY)) and world.blocked(COPY) and world.blocked(COPY+Vector2i.DOWN),"The copy is a solid vertical bed")
			expect(World.station_anchor(world.state.objects,COPY+Vector2i.DOWN)==COPY,"The copy resolves to its own anchor")
			expect(str(person.get(MARK))==before_mark and person.get(MARK)==World.key(MOVED),"Placing a copy does not move or set the mark")
			expect("rest" not in JSON.stringify(obj(COPY)).to_lower() and "mark" not in JSON.stringify(obj(COPY)).to_lower(),"The copy carries no preference data")
			expect(world.act(owner,"remove-copy","remove",COPY).ok and obj(COPY).is_empty() and person.get(MARK)==World.key(MOVED),"Removing an unmarked copy leaves the mark alone")
		stand_at(owner,ROTATED.x+0.5,ROTATED.y+1.5)
		var turned_quote:=world.quote_blueprint(owner,cut.blueprint,ROTATED,1)
		if expect(turned_quote.get("ok")==true,"Quote for the turned placement succeeds: "+str(turned_quote.get("problems",[]))):
			var applied_turned:=world.apply_blueprint(owner,hex32(),cut.blueprint,ROTATED,1,str(turned_quote.hash))
			expect(applied_turned.get("ok")==true,"Applying the turned blueprint succeeds: "+str(applied_turned.get("message","")))
			expect(obj(ROTATED).get("type")==KIND and not Industry.is_vertical(obj(ROTATED)),"The turned blueprint places a horizontal bed")
			expect(world.blocked(ROTATED) and world.blocked(ROTATED+Vector2i.RIGHT) and World.station_anchor(world.state.objects,ROTATED+Vector2i.RIGHT)==ROTATED,"Its two horizontal cells are solid and share one anchor")
			expect(person.get(MARK)==World.key(MOVED),"The turned copy is not marked either")
			app.session._send_snapshot(1)
			focus_camera(ROTATED)
			await capture("cedar-bed-horizontal")
			# Both halves of a horizontal bed work, and the mark stores its anchor.
			person.mine_energy=15
			expect(world.act(owner,"turned-rest","cedar_bed",ROTATED+Vector2i.RIGHT,"rest").ok and energy(owner)==100,"A horizontal bed rests from its right half")
			expect(world.act(owner,"turned-mark","cedar_bed",ROTATED+Vector2i.RIGHT,"mark").ok and person.get(MARK)==World.key(ROTATED),"Marking a horizontal bed by its right half stores its anchor")
			expect(world.act(owner,"turned-remove","remove",ROTATED+Vector2i.RIGHT).ok and obj(ROTATED).is_empty() and obj(ROTATED+Vector2i.RIGHT).is_empty(),"Removing by either half dismantles the whole bed")
			expect(marked()=="","Removing the marked horizontal bed clears home_rest_cell")

	# --- Removing a marked bed clears the mark (and only the owner's) -------------------------------------------------------
	person.erase(MARK)
	stand_by(owner,MOVED)
	expect(world.act(owner,"mark-final","cedar_bed",MOVED,"mark").ok and person.get(MARK)==World.key(MOVED),"Fixture: the moved bed is marked")
	guest.mine_energy=33
	var guest_final:=var_to_str(guest)
	wood_now=person.inventory.wood
	fiber_now=person.inventory.fiber
	expect(world.act(owner,"final-remove","remove",MOVED+Vector2i.DOWN).ok and obj(MOVED).is_empty() and obj(MOVED+Vector2i.DOWN).is_empty(),"The marked bed is dismantled by its lower half")
	expect(person.inventory.wood==wood_now+15 and person.inventory.fiber==fiber_now+10,"Dismantling refunds the full recipe")
	expect(marked()=="" and (not person.has(MARK) or str(person.get(MARK))==""),"Removing the marked bed clears home_rest_cell")
	expect(var_to_str(guest)==guest_final,"Removing the owner's bed does not touch another player")
	expect(not world.blocked(MOVED) and not world.blocked(MOVED+Vector2i.DOWN),"Both cells are walkable again")
	# A cleared mark must not leave resting broken: the remaining bed still works unmarked.
	stand_by(owner,SITE)
	person.mine_energy=22
	expect(world.act(owner,"rest-after-clear","cedar_bed",SITE,"rest").ok and energy(owner)==100 and marked()=="","The owner can still rest on a remaining bed after the mark was cleared")

	# --- Persistence of the cleared state and no stray data ------------------------------------------------------------------
	expect(world.save(),"The world saves after the mark is cleared")
	var cleared:=World.new()
	expect(cleared.load_world(path) and marked(cleared)=="","Reload keeps the mark cleared")
	var final_shape:=person.keys()
	final_shape.sort()
	var added:=[]
	for field in final_shape:
		if not player_shape.has(field):added.append(str(field))
	expect(added.is_empty() or added==[MARK] or added==["fish_caught"],"Players gain no field other than home_rest_cell: "+str(added))
	expect(not ("cedar" in JSON.stringify(world.state.get("resident_goals",{})).to_lower()),"No cedar bed progress is stored in resident goals")
	expect(not ("cedar" in JSON.stringify(guest).to_lower()),"The visitor record never mentions the cedar bed")
	expect(world.state.objects.get(World.key(SITE),{}).get("items",{}).is_empty(),"The bed object carries no item state")

	# --- Final render (screenshot only; no pixel assertions) ---------------------------------------------------------------------
	app.session.peers[1]=owner
	app.session._send_snapshot(1)
	focus_camera(SITE)
	await capture("cedar-bed-final")
	await finish()
