extends SceneTree
## T12 不完美的茶亭: an open, walkable 3x3 shelter unlocked by the player's OWN persisted chacha stage-3
## goal (N04-3 信任・一場沒有流程的茶會). Covers locked/unlocked, 30 bamboo + 10 wood + 8 cotton cloth, the exact
## 3x3 footprint (centre and edges), walkability, essential routes / reserved cells, save and reload,
## blueprint quote/apply, move / removal / undo, the E memento and the normal story unlock.
## Native screenshots: --qa-size=1024 and --qa-dir=<folder>.

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Folio=preload("res://scripts/build_folio.gd")
const Industry=preload("res://scripts/industry.gd")
const Rules=preload("res://scripts/imperfect_tea_pavilion.gd")
const Art=preload("res://scripts/imperfect_tea_pavilion_art.gd")
const Panels=preload("res://scripts/life_ui_panels.gd")
const LifeTasks=preload("res://scripts/life_ui_tasks.gd")
const StyleCatalog=preload("res://scripts/build_style_catalog.gd")
const Goals=World.RESIDENT_GOALS
const Bond=World.RESIDENT_BOND
const KIND:="imperfect_tea_pavilion"
const PART_FIELD:="imperfect_pavilion_part"
const MAIN_ART:="res://assets/ui-life/imperfect-tea-pavilion.png"
const BASE_ART:="res://assets/ui-life/imperfect-tea-pavilion-base.png"
const SITE:=Vector2i(31,35)         ## footprint (31..33, 35..37): clear west-side grass
const MOVED:=Vector2i(27,35)        ## footprint (27..29, 35..37)
const BLUEPRINT_SITE:=Vector2i(27,41)
const PATH_SITE:=Vector2i(38,34)    ## covers the village's southern footpath
const PROTECTED_SITE:=Vector2i(41,27)
const TRANSIT_SITE:=Vector2i(46,29) ## covers the island exit cell (47,30)
const RESERVED_SITE:=Vector2i(32,23) ## covers the squirrel's interaction cell (33,24)
const OWNER_NAME:="茶亭主人"
const GUEST:="imperfect-tea-pavilion-guest"
const GUEST_NAME:="沒到信任的訪客"
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0
var sequence:=0

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
	for suffix:String in ["",".bak",".writer-lock",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("IMPERFECT_TEA_PAVILION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func act(action:String,tile:Vector2i,extra:="",actor:="")->Dictionary:
	sequence+=1
	return world.act(owner if actor.is_empty() else actor,"pavilion-%d"%sequence,action,tile,extra)

func obj(tile:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand(token:String,position:Vector2)->void:
	world.state.players[token].x=position.x
	world.state.players[token].y=position.y

func stand_beside(token:String,anchor:Vector2i)->void:
	stand(token,Vector2(anchor)+Vector2(1.5,1.5))

func travel(station:String,destination:String)->bool:
	var origin:=world.player_region(owner)
	var cell:Vector2i=World.TRANSIT.points(origin)[station].cell
	stand(owner,Vector2(cell)+Vector2(0.5,0.5))
	var trip:=act("transit",cell,destination)
	return expect(trip.ok and world.player_region(owner)==destination,"Travel %s to %s: %s"%[origin,destination,trip.message])

func visit_tea_garden()->bool:
	# The picnic is a starting milestone; verify the remaining chapter gates at the station.
	world.state.picnic=true
	if not travel("ferry","toucheng") or not travel("rail","ruifang"):return false
	var rail:Vector2i=World.TRANSIT.points("ruifang").rail.cell
	stand(owner,Vector2(rail)+Vector2(0.5,0.5))
	expect(not act("transit",rail,"maokong").ok and world.player_region(owner)=="ruifang","The picnic alone does not open the tea route")
	if not travel("rail","home"):return false
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	expect(World.CHAPTER_ONE.phase(world.state)=="complete","The fixture now starts at the first chapter milestone")
	var receiver:=World.TEA_CERAMICS.RECEIVER
	stand(owner,Vector2(receiver)+Vector2(0.5,0.5))
	var letter:=act("tea_intro",receiver)
	if not expect(letter.ok,"Read the tea cooperative letter: "+str(letter.message)):return false
	return travel("ferry","toucheng") and travel("rail","ruifang") and travel("rail","maokong")

func earn_chacha_trust(cell:Vector2i)->void:
	var person:Dictionary=world.state.players[owner]
	expect(Bond.points(person,"chacha")==0,"No friendship record is seeded")
	expect(int(person.inventory.get("tea_leaf",0))==0,"No tea leaves are supplied")
	for index in range(2):
		var bush:Vector2i=World.TEA_CERAMICS.TEA_NODES[index]
		stand(owner,Vector2(bush)+Vector2(0.5,0.5))
		var picked:=act("tea_pick",bush)
		expect(picked.ok,"Harvest fresh tea leaves for the gifts: "+str(picked.message))
	expect(int(person.inventory.get("tea_leaf",0))==4,"Two bushes supply four fresh leaves")
	stand(owner,Vector2(cell)+Vector2(0.5,1.5))
	person.inventory["radish"]=1
	for day in range(4):
		if day>0:expect(world.step(World.WEATHER.DAY_SECONDS,true),"Advance to the next gift day")
		expect(act("resident_talk",cell,"chacha").ok,"Talk to Chacha on day %d"%(day+1))
		expect(Bond.stage(person,"chacha")<3,"The story requires more friendship after this conversation")
		var item:="tea_leaf" if day<3 else "radish"
		expect(act("resident_gift",cell,"chacha:"+item).ok,"Give Chacha "+item)
	expect(Bond.points(person,"chacha")==Bond.THRESHOLDS[2],"Four visits reach exactly fourteen points")
	expect(int(person.inventory.get("tea_leaf",0))==1 and int(person.inventory.get("radish",0))==0,"Each gift is taken once")

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

func whole_footprint(anchor:Vector2i)->bool:
	var cells:Array=Industry.station_cells(KIND)
	for part in cells.size():
		var tile:Vector2i=anchor+Vector2i(cells[part])
		var piece:Dictionary=obj(tile)
		if piece.get("type")!=KIND or piece.get("owner")!=owner or int(piece.get(PART_FIELD,-1))!=part or world.blocked(tile):return false
	return true

func footprint_empty(anchor:Vector2i)->bool:
	for offset:Vector2i in Industry.station_cells(KIND):
		if world.state.objects.has(World.key(anchor+offset)):return false
	return true

func focus_camera(anchor:Vector2i)->void:
	app.view.camera=(Vector2(anchor)+Vector2(1.5,1.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func publish()->void:
	app.session._send_snapshot(1)

func frame_player(position:Vector2)->void:
	stand(owner,position)
	publish()
	app.view.display_positions[app.session.own_id]=position

func folio_slot()->Button:
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if candidate.text==str(StyleCatalog.style("tea_house").name):
			candidate.pressed.emit()
			return app.modal.find_child("BuildSlot_"+KIND+"_"+str(candidate.name).trim_prefix("BuildTab"),true,false) as Button
	return null

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://imperfect-tea-pavilion-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="imperfect-tea-pavilion-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"bamboo":150,"wood":50,"cotton_cloth":40,"stone":4},true)
	world.state.time=720.0
	for anchor:Vector2i in [SITE,MOVED,BLUEPRINT_SITE,RESERVED_SITE]:
		for y in range(anchor.y-2,anchor.y+6):
			for x in range(anchor.x-2,anchor.x+6):world.state.removed[World.key(Vector2i(x,y))]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(30.5,34.5))
	var guest:Dictionary=world.state.players[GUEST]
	guest.inventory.merge({"bamboo":150,"wood":50,"cotton_cloth":40},true)
	stand_beside(owner,SITE)
	publish()

	# --- Contract: id, recipe, exact 3x3 footprint, collision, catalog, art -----------------------------
	expect(Industry.IMPERFECT_TEA_PAVILION==KIND and Industry.PAVILION_INSPECT=="pavilion_inspect","Industry.IMPERFECT_TEA_PAVILION is imperfect_tea_pavilion")
	expect(Industry.PAVILION_INSPECT.length()<=24,"The inspect action id fits the session action-name limit")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].get("name")=="不完美的茶亭","The pavilion has the display name 不完美的茶亭")
	expect(World.BUILD[KIND].get("bamboo")==30 and World.BUILD[KIND].get("wood")==10 and World.BUILD[KIND].get("cotton_cloth")==8 and World.BUILD[KIND].size()==4,"Recipe is exactly 30 bamboo, 10 wood and 8 cotton cloth plus the name")
	var cells:Array=Industry.station_cells(KIND)
	var every_cell:=true
	for row in 3:
		for column in 3:every_cell=every_cell and cells[row*3+column]==Vector2i(column,row)
	expect(cells.size()==9 and every_cell and Industry.station_cells(KIND,true)==cells,"Footprint is exactly 3x3, row-major, whatever the rotation flag")
	expect(KIND in Industry.ORIENTABLE_FOOTPRINTS and Industry.square_part_field(KIND)==PART_FIELD and Industry.vertical_field(KIND)=="imperfect_pavilion_vertical","It reuses the shared multi-tile footprint lifecycle")
	expect(not KIND in World.UNDO_SOLID,"The shelter never blocks walking")
	expect(Folio.TEA_COLLECTION.has(KIND) and Folio.TEA_COLLECTION.back()==KIND,"It closes the tea catalog")
	expect(Folio.PLACEMENT_NOTES.has(KIND) and not str(Folio.PLACEMENT_NOTES[KIND]).is_empty() and KIND in Panels.FURNITURE,"The folio describes it and lists it under 家具")
	var main_art:Texture2D=load(MAIN_ART)
	var base_art:Texture2D=load(BASE_ART)
	expect(main_art!=null and main_art.get_size()==Vector2(96,96),"imperfect-tea-pavilion.png loads at 96x96")
	expect(base_art!=null and base_art.get_size()==Vector2(96,96),"imperfect-tea-pavilion-base.png loads at 96x96")
	expect(app.view.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"The world view draws with nearest filtering")
	expect(KIND in app.view.PASS_DRAWN_OBJECTS,"The shelter is drawn in its own ground and canopy passes")
	var preview:Array=app.view.build_placement_offsets(KIND)
	expect(preview.size()==9 and preview==cells,"The placement ghost previews the nine cells")

	# --- Locked: no chacha stage 3 yet --------------------------------------------------------------------
	expect(not Rules.unlocked(person) and not Rules.unlocked(guest) and not Rules.unlocked({}) and not Rules.unlocked(null),"Nobody starts with the pattern")
	var bag:=var_to_str(person.inventory)
	var locked:=act("build",SITE,KIND)
	expect(not locked.ok and locked.get("message")==Rules.LOCK_MESSAGE,"Normal building is refused with the story reason")
	expect(var_to_str(person.inventory)==bag and footprint_empty(SITE),"A refused build charges and places nothing")
	var raw:Dictionary={"version":Design.VERSION,"name":"不完美的茶亭","width":3,"height":3,"pieces":[{"kind":KIND,"x":0,"y":0}]}
	var locked_quote:=world.quote_blueprint(owner,raw,SITE,0)
	expect(not locked_quote.ok and locked_quote.problems.size()==1 and locked_quote.problems[0].reason==Rules.LOCK_MESSAGE,"The blueprint quote carries the same gate: "+str(locked_quote.get("message","")))
	var locked_apply:=world.apply_blueprint(owner,hex32(),raw,SITE,0,str(locked_quote.hash))
	expect(not locked_apply.ok and footprint_empty(SITE) and var_to_str(person.inventory)==bag,"Blueprint apply refuses without charging or placing")
	app._build_menu()
	var slot:=folio_slot()
	if expect(slot!=null and slot.is_visible_in_tree(),"The tea shelf lists the pavilion"):
		slot.pressed.emit()
		var place_locked:=app.modal.find_child("BuildPlace",true,false) as Button
		var status_locked:=app.modal.find_child("BuildStatus",true,false) as Label
		var note_locked:=app.modal.find_child("BuildDescription",true,false) as Label
		expect(place_locked!=null and place_locked.disabled and place_locked.text==Rules.LOCK_SHORT,"The builder disables placement and names the story")
		expect(status_locked!=null and status_locked.text=="圖樣未解鎖" and note_locked!=null and note_locked.text==Rules.LOCK_DETAIL,"The builder explains why the pattern is locked")
		await capture("pavilion-folio-locked")
	app._close_modal()
	LifeTasks.bond_goal(app,"chacha",3)
	var promise:=app.modal.find_child("BondGoalPavilionUnlock",true,false) as Label
	expect(promise!=null and promise.text.contains("不完美的茶亭"),"The story page says what the goal unlocks")
	await capture("pavilion-story-locked")
	app._close_modal()

	# --- Normal story unlock: chacha stage 3 alone, at the tea farm ---------------------------------------
	if not visit_tea_garden():
		await finish()
		return
	person=world.state.players[owner]
	var tea_place:Array=World.bond_place(world.state,"chacha")
	var tea_cell:Vector2i=tea_place[1]
	stand(owner,Vector2(tea_cell)+Vector2(0.5,1.5))
	earn_chacha_trust(tea_cell)
	var held:=var_to_str(person.inventory)
	var finished:=act(Goals.ACTION,tea_cell,"chacha:3::012")
	if not expect(finished.ok,"The real chacha stage-3 goal completes: "+str(finished.get("message",""))):
		await finish()
		return
	expect(str(finished.message).ends_with(Goals.PAVILION_UNLOCK_NOTE),"Completing it says where the pattern went")
	expect(Goals.done(person,"chacha")=={3:""} and var_to_str(person.inventory)==held,"Only stage 3 is recorded and nothing is paid or given")
	expect(Rules.unlocked(person) and not Rules.unlocked(guest),"The unlock is this player's own")
	if not travel("transfer","ruifang") or not travel("rail","toucheng") or not travel("street","home"):
		await finish()
		return
	person=world.state.players[owner]
	stand_beside(owner,SITE)
	publish()
	var folio_person:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(Folio.unlocked(app,folio_person,KIND),"The builder now treats the pattern as unlocked")
	app._build_menu()
	slot=folio_slot()
	if expect(slot!=null,"The tea shelf still lists the pavilion"):
		slot.pressed.emit()
		var place_open:=app.modal.find_child("BuildPlace",true,false) as Button
		var status_open:=app.modal.find_child("BuildStatus",true,false) as Label
		var note_open:=app.modal.find_child("BuildDescription",true,false) as Label
		expect(place_open!=null and not place_open.disabled and status_open.text.begins_with("材料齊全"),"The builder offers placement with enough materials")
		expect(note_open.text.contains("3×3"),"The builder describes the open shelter")
		await capture("pavilion-folio-unlocked")
		place_open.pressed.emit()
		expect(app.building==KIND,"Choosing the recipe selects the pavilion for placement")
	LifeTasks.bond_goal(app,"chacha",3)
	var pattern_button:=app.modal.find_child("ChachaPavilionPattern",true,false) as Button
	expect(pattern_button!=null and app.modal.find_child("BondGoalPavilionUnlock",true,false)==null,"The finished story page links the pattern instead of the promise")
	await capture("pavilion-story-done")
	app._close_modal()
	app._select_tool("hoe")

	# --- Essential routes, transitions and reserved interaction cells --------------------------------------
	stand_beside(owner,PATH_SITE)
	bag=var_to_str(person.inventory)
	var refusal:=act("build",PATH_SITE,KIND)
	expect(not refusal.ok and refusal.message==Rules.ESSENTIAL_MESSAGE and footprint_empty(PATH_SITE),"A footprint over the village footpath is refused")
	expect(World.essential_cell_reason(world.state,"home",Vector2i(40,36))==Rules.ESSENTIAL_MESSAGE,"The footpath is an essential cell")
	stand_beside(owner,PROTECTED_SITE)
	refusal=act("build",PROTECTED_SITE,KIND)
	expect(not refusal.ok and refusal.message==Rules.ESSENTIAL_MESSAGE and footprint_empty(PROTECTED_SITE),"A footprint over the protected plaza is refused")
	stand_beside(owner,TRANSIT_SITE)
	refusal=act("build",TRANSIT_SITE,KIND)
	expect(not refusal.ok and refusal.message==Rules.ESSENTIAL_MESSAGE and footprint_empty(TRANSIT_SITE),"A footprint over the island exit and ferry access is refused")
	expect(not World.essential_cell_reason(world.state,"home",World.REGIONS.exit_cell("home")).is_empty(),"The exit is an essential transition cell")
	var squirrel:Vector2i=World.Squirrel.SITE
	expect(not world.protected(squirrel) and not World.essential_cell_reason(world.state,"home",squirrel).is_empty(),"The squirrel's interaction cell is reserved by the new rule alone")
	stand_beside(owner,RESERVED_SITE)
	refusal=act("build",RESERVED_SITE,KIND)
	expect(not refusal.ok and refusal.message==Rules.ESSENTIAL_MESSAGE and footprint_empty(RESERVED_SITE),"A footprint over a reserved interaction cell is refused")
	var post:Vector2i=World.bond_place(world.state,"luoluo")[1]
	var weir:Vector2i=World.WANGAN_MEMORY.WEIR_SITE
	expect(not World.essential_cell_reason(world.state,"home",post).is_empty() and not World.essential_cell_reason(world.state,"home",weir).is_empty(),"Walk-up resident spots and memory sites are reserved")
	expect(World.essential_cell_reason(world.state,"home",SITE).is_empty() and World.essential_cell_reason(world.state,"home",SITE+Vector2i(2,2)).is_empty(),"The chosen building site is not essential")
	expect(var_to_str(person.inventory)==bag,"Refused sites charge nothing")
	# Any one occupied cell (an edge, then the centre) refuses the whole 3x3 before charging.
	stand_beside(owner,SITE)
	for blocker:Vector2i in [SITE+Vector2i(2,2),SITE+Vector2i(1,1),SITE+Vector2i(1,0)]:
		world.state.objects[World.key(blocker)]={"type":"chair","owner":owner,"items":{}}
		var crowded:=act("build",SITE,KIND)
		expect(not crowded.ok and var_to_str(person.inventory)==bag and not obj(SITE).has(PART_FIELD),"An occupied cell at %s refuses the whole footprint"%str(blocker))
		world.state.objects.erase(World.key(blocker))

	# A save from before this update: stage 3 already recorded, no pavilion anywhere.
	var legacy:=world.state.duplicate(true)

	# --- Build: exact cost, all nine parts, standing inside does not block ----------------------------------
	stand(owner,Vector2(SITE)+Vector2(1.5,1.5))
	var bamboo:int=person.inventory.bamboo
	var wood:int=person.inventory.wood
	var cloth:int=person.inventory.cotton_cloth
	app._perform_build_action("build",SITE,KIND)
	if not expect(whole_footprint(SITE),"The real build action places all nine parts for the owner, even with the owner standing inside"):
		await finish()
		return
	expect(person.inventory.bamboo==bamboo-30 and person.inventory.wood==wood-10 and person.inventory.cotton_cloth==cloth-8,"Building spends exactly 30 bamboo, 10 wood and 8 cotton cloth")
	var anchors_agree:=true
	for offset:Vector2i in cells:anchors_agree=anchors_agree and World.station_anchor(world.state.objects,SITE+offset)==SITE
	expect(anchors_agree and Industry.square_part(obj(SITE+Vector2i(1,1)))==4,"Every cell, centre included, resolves to one anchor")
	expect(valid(world.state),"The fresh state passes save validation")
	expect(not world.state.objects.has(World.key(SITE+Vector2i(-1,0))) and not world.state.objects.has(World.key(SITE+Vector2i(3,0))) and not world.state.objects.has(World.key(SITE+Vector2i(0,3))),"Nothing is placed outside the 3x3")

	# --- Walkability: through the interior and across open sides -----------------------------------------------
	var all_stand:=true
	for offset:Vector2i in cells:all_stand=all_stand and world.can_stand(Vector2(SITE+offset)+Vector2(0.5,0.5))
	expect(all_stand,"Every cell, posts included, is standable")
	stand(owner,Vector2(30.5,36.5))
	for step in 60:
		if person.x>=34.4:break
		world.move_player(owner,Vector2.RIGHT,0.10)
	expect(person.x>=34.4 and absf(person.y-36.5)<0.01,"A player walks west to east straight through the shelter")
	stand(owner,Vector2(32.5,34.5))
	for step in 60:
		if person.y>=38.4:break
		world.move_player(owner,Vector2.DOWN,0.10)
	expect(person.y>=38.4 and absf(person.x-32.5)<0.01,"A player walks north to south across the open sides")
	stand(owner,Vector2(32.5,36.5))
	expect(world.can_stand(Vector2(person.x,person.y)),"The avatar can stand in the middle of the shelter")

	# --- Rendering rules: canopy fades under/behind, flat in quiet mode ---------------------------------------
	var inside:=Vector2(32.5,36.5)
	expect(Art.opacity(SITE,inside,false)<=0.40 and Art.opacity(SITE,inside,true)==Art.FADED,"The canopy fades when the avatar is under it, in either motion setting")
	expect(Art.opacity(SITE,Vector2(32.5,39.0),false)<1.0,"Walking just in front the canopy would cover the head, so it fades")
	expect(Art.opacity(SITE,Vector2(32.5,33.0),false)==1.0 and Art.opacity(SITE,Vector2(40.0,36.5),false)==1.0 and Art.opacity(SITE,Vector2(INF,INF),false)==1.0,"Far away or unknown positions stay opaque")
	expect(Art.opacity(SITE,Vector2(32.5,34.9),true)==1.0 and Art.opacity(SITE,Vector2(32.5,35.6),true)==Art.FADED,"Quiet mode is a flat step, never a partial fade")
	expect(Art.opacity(SITE,Vector2(32.5,34.9),false)<1.0,"The canopy starts to fade as the avatar passes just behind the back beam")
	expect(Art.opacity(SITE,Vector2(32.5,34.9),false)>Art.opacity(SITE,Vector2(32.5,36.5),false),"The fade deepens as the avatar moves under the roof")
	app._select_tool("hoe")
	app.view.set_process(false)
	focus_camera(SITE)
	frame_player(Vector2(29.5,36.5))
	await capture("pavilion-built")
	frame_player(Vector2(32.5,36.5))
	await capture("pavilion-under-canopy")
	frame_player(Vector2(32.5,34.9))
	await capture("pavilion-behind-canopy")

	# --- E memento: any cell, read-only, no reward --------------------------------------------------------------
	stand(owner,Vector2(32.5,36.5))
	publish()
	var clock:=float(world.state.time)
	var energy:=int(person.mine_energy)
	var position_before:=Vector2(person.x,person.y)
	bag=var_to_str(person.inventory)
	var object_count:int=world.state.objects.size()
	var saved_state:=var_to_str(world.state.objects)
	for tile:Vector2i in [SITE,SITE+Vector2i(1,1),SITE+Vector2i(2,2),SITE+Vector2i(0,2)]:
		var memory:=act(Industry.PAVILION_INSPECT,tile)
		expect(memory.ok and str(memory.message).contains("茶涼了，可是大家還在說話。") and str(memory.message).contains("沒照流程走的茶會筆記"),"Inspecting %s shows the trust-stage quote and the memento"%str(tile))
	expect(var_to_str(person.inventory)==bag and float(world.state.time)==clock and int(person.mine_energy)==energy,"Inspecting gives no materials and passes no time")
	expect(Vector2(person.x,person.y)==position_before and world.state.objects.size()==object_count and var_to_str(world.state.objects)==saved_state,"Inspecting moves nobody and changes nothing")
	stand(GUEST,Vector2(34.5,36.5))
	var neutral:=act(Industry.PAVILION_INSPECT,SITE+Vector2i(2,1),"",GUEST)
	expect(neutral.ok and neutral.message==Rules.NEUTRAL_MEMENTO and not str(neutral.message).contains("茶涼了"),"A visitor who has not earned the story gets a neutral line")
	expect(not act(Industry.PAVILION_INSPECT,SITE+Vector2i(5,5)).ok and not act(Industry.PAVILION_INSPECT,SITE,"x").ok,"Inspecting needs a pavilion cell and no extra")
	stand(owner,Vector2(40.5,40.5))
	expect(not act(Industry.PAVILION_INSPECT,SITE).ok,"Inspecting from far away is refused")
	stand(owner,Vector2(32.5,37.5))
	# Client interaction: the shelter is only a fallback and never hides another target.
	publish()
	expect(app.view.interaction_focus()==World.key(SITE+Vector2i(1,2)),"With nothing else near, E focuses the nearest pavilion cell")
	world.state.objects[World.key(SITE+Vector2i(3,2))]={"type":"chest","owner":owner,"items":{}}
	publish()
	expect(app.view.interaction_focus()==World.key(SITE+Vector2i(3,2)),"A chest beside the shelter still wins the E target")
	world.state.objects.erase(World.key(SITE+Vector2i(3,2)))
	publish()
	var before_interact:=var_to_str(world.state.objects)
	app._interact()
	expect(var_to_str(world.state.objects)==before_interact and whole_footprint(SITE),"Pressing E in the shelter leaves the world untouched")
	var topic:=app.modal.find_child("ChachaGatheringTopic",true,false) as Label if is_instance_valid(app.modal) else null
	expect(topic!=null and topic.text.contains("今年的茶"),"Inspecting the finished pavilion replays the viewer's first topic")
	var back:=app.modal.find_child("ChachaGatheringBack",true,false) as Button if is_instance_valid(app.modal) else null
	expect(back!=null and back.text=="回到島上","Pavilion replay can return to the island")
	await capture("pavilion-tea-replay")
	app._close_modal()

	# --- Construction undo of the fresh build --------------------------------------------------------------------
	var summary:=world.undo_summary(owner)
	var undo_id:String=str(summary.get("id",""))
	if expect(summary.get("available")==true and not undo_id.is_empty(),"Undo is offered for the shelter"):
		var undone:=world.act(owner,"undo-pavilion",World.UNDO_ACTION,Vector2i.ZERO,undo_id)
		expect(undone.get("ok")==true and footprint_empty(SITE),"Undo clears all nine parts")
		expect(person.inventory.bamboo==bamboo and person.inventory.wood==wood and person.inventory.cotton_cloth==cloth,"Undo returns exactly the materials")
		stand_beside(owner,SITE)
		expect(act("build",SITE,KIND).ok and whole_footprint(SITE),"The shelter can be rebuilt after undo")

	# --- Save and reload, forged footprints, earlier completed saves --------------------------------------------
	expect(world.save(),"The world saves with the shelter")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	var reloaded:=true
	for part in cells.size():
		var restored:Dictionary=loaded.state.objects.get(World.key(SITE+Vector2i(cells[part])),{})
		reloaded=reloaded and restored.get("type")==KIND and int(restored.get(PART_FIELD,-1))==part
	expect(reloaded and Rules.unlocked(loaded.state.players[owner]),"Reload keeps every part and the player's own unlock")
	var forged:=world.state.duplicate(true)
	forged.objects.erase(World.key(SITE+Vector2i(1,1)))
	expect(not valid(forged),"A save missing the centre part is rejected")
	forged=world.state.duplicate(true)
	forged.objects.erase(World.key(SITE+Vector2i(2,1)))
	expect(not valid(forged),"A save missing an edge part is rejected")
	forged=world.state.duplicate(true)
	forged.objects[World.key(SITE+Vector2i(2,2))][PART_FIELD]=9
	expect(not valid(forged),"A part index outside 0..8 is rejected")
	forged=world.state.duplicate(true)
	forged.objects[World.key(SITE+Vector2i(1,2))].owner=GUEST
	expect(not valid(forged),"A part owned by someone else is rejected")
	forged=world.state.duplicate(true)
	forged.objects[World.key(SITE)]["imperfect_pavilion_vertical"]=true
	expect(not valid(forged),"A rotated flag on the square shelter is rejected")
	forged=world.state.duplicate(true)
	forged.objects[World.key(SITE)]["items"]={"wood":1}
	expect(not valid(forged),"Stored items on the shelter are rejected")
	# A save from before this update only holds the stage-3 record; no migration and no new field.
	expect(Goals.done(legacy.players[owner],"chacha")=={3:""} and not legacy.objects.has(World.key(SITE)) and valid(legacy),"A save that completed stage 3 before this update is valid")
	var veteran:=World.new()
	veteran.add_player("veteran","老手")
	var elder:Dictionary=veteran.state.players.veteran
	elder["bonds"]={"chacha":{"points":14,"talk_day":-1,"gift_day":-1}}
	elder["bond_goals"]={"chacha":{"3":""}}
	elder.inventory.merge({"bamboo":30,"wood":10,"cotton_cloth":8},true)
	for offset:Vector2i in cells:veteran.state.removed[World.key(SITE+offset)]=true
	elder.x=SITE.x+1.5
	elder.y=SITE.y+1.5
	expect(Rules.unlocked(elder) and veteran.act("veteran","veteran-build","build",SITE,KIND).ok,"Such a save builds it with no migration")
	expect(valid(veteran.state) and veteran.state.objects.get(World.key(SITE+Vector2i(2,2)),{}).get(PART_FIELD)==8,"...and the result validates with all nine parts")

	# --- Move: from an edge and from the centre, shelter-aware destination checks ------------------------------------
	stand(owner,Vector2(30.5,36.5))
	var blocked_move:=act("move_object",SITE+Vector2i(2,0),World.key(PATH_SITE))
	expect(not blocked_move.ok and whole_footprint(SITE),"Moving onto the footpath is refused and the shelter stays")
	var guest_move:=act("move_object",SITE,World.key(MOVED),GUEST)
	expect(not guest_move.ok and whole_footprint(SITE),"A visitor cannot move the owner's shelter")
	var nudge:=act("move_object",SITE+Vector2i(1,1),World.key(SITE+Vector2i(1,0)))
	expect(nudge.ok and whole_footprint(SITE+Vector2i(1,0)) and not world.state.objects.has(World.key(SITE)),"Moving by the centre part can overlap its own old cells")
	expect(act("move_object",SITE+Vector2i(2,0),World.key(SITE)).ok and whole_footprint(SITE),"...and back again by an edge part")
	stand(owner,Vector2(29.5,36.5))
	var moved:=act("move_object",SITE+Vector2i(0,2),World.key(MOVED))
	expect(moved.ok and whole_footprint(MOVED) and footprint_empty(SITE),"Moving by a corner relocates the whole shelter and frees the old cells")
	expect(valid(world.state),"The moved state passes save validation")
	expect(act("move_object",MOVED+Vector2i(1,1),World.key(SITE)).ok and whole_footprint(SITE),"The shelter can be moved back by its centre")

	# --- Blueprint: capture, quote, apply, gate for a visitor -------------------------------------------------------
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(3,3)),"不完美的茶亭",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND and not cut.blueprint.pieces[0].has("settings"),"The blueprint captures the nine cells as one piece without settings"):
		expect(not Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,3)),"局部茶亭",World.BUILD,World.NAMES).ok,"A clipped blueprint is rejected")
		expect(not Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE+Vector2i(1,1),Vector2i(2,2)),"只有中心",World.BUILD,World.NAMES).ok,"A blueprint holding only part of the footprint is rejected")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		expect(turned.get("ok")==true and turned.blueprint.width==3 and turned.blueprint.height==3 and turned.blueprint.pieces[0].x==0 and turned.blueprint.pieces[0].y==0 and not turned.blueprint.pieces[0].has("settings"),"A quarter turn keeps the square shelter at the same corner")
		var vertical:=Design.validate({"version":Design.VERSION,"name":"歪的","width":3,"height":3,"pieces":[{"kind":KIND,"x":0,"y":0,"settings":{"vertical":true}}]},World.BUILD,World.NAMES)
		expect(vertical.get("ok")!=true,"A forged rotation setting is rejected")
		stand_beside(owner,BLUEPRINT_SITE)
		bamboo=person.inventory.bamboo
		wood=person.inventory.wood
		cloth=person.inventory.cotton_cloth
		var quote:=world.quote_blueprint(owner,cut.blueprint,BLUEPRINT_SITE,0)
		if expect(quote.get("ok")==true,"Quote for a legal site succeeds: "+str(quote.get("message",""))):
			expect(quote.cost=={"bamboo":30,"cotton_cloth":8,"wood":10} and quote.pieces==1,"The quote lists exactly one shelter's materials")
			expect(person.inventory.bamboo==bamboo and footprint_empty(BLUEPRINT_SITE),"Quoting changes nothing")
			var stale:=world.apply_blueprint(owner,hex32(),cut.blueprint,BLUEPRINT_SITE,0,"0".repeat(64))
			expect(not stale.ok and stale.get("requote")==true and footprint_empty(BLUEPRINT_SITE),"A stale quote hash is refused and asks for a new quote")
			var applied:=world.apply_blueprint(owner,hex32(),cut.blueprint,BLUEPRINT_SITE,0,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the blueprint succeeds: "+str(applied.get("message","")))
			expect(whole_footprint(BLUEPRINT_SITE) and valid(world.state),"The blueprint builds the complete 3x3 and the state validates")
			expect(person.inventory.bamboo==bamboo-30 and person.inventory.wood==wood-10 and person.inventory.cotton_cloth==cloth-8,"The blueprint charges exactly one recipe")
			var bp_undo:=str(world.undo_summary(owner).get("id",""))
			if expect(not bp_undo.is_empty(),"The blueprint build can be undone"):
				expect(world.act(owner,"undo-blueprint",World.UNDO_ACTION,Vector2i.ZERO,bp_undo).ok and footprint_empty(BLUEPRINT_SITE),"Undoing the blueprint clears the footprint")
				expect(person.inventory.bamboo==bamboo and person.inventory.wood==wood and person.inventory.cotton_cloth==cloth,"...and refunds it")
		stand_beside(owner,PATH_SITE)
		var route_quote:=world.quote_blueprint(owner,cut.blueprint,PATH_SITE,0)
		expect(not route_quote.ok and route_quote.problems.size()==1 and route_quote.problems[0].reason==Rules.ESSENTIAL_MESSAGE,"The blueprint quote rejects a footprint over the footpath: "+str(route_quote.get("message","")))
		stand_beside(owner,TRANSIT_SITE)
		var transit_quote:=world.quote_blueprint(owner,cut.blueprint,TRANSIT_SITE,0)
		expect(not transit_quote.ok,"The blueprint quote rejects a footprint over the island exit")
		stand_beside(GUEST,BLUEPRINT_SITE)
		var guest_quote:=world.quote_blueprint(GUEST,cut.blueprint,BLUEPRINT_SITE,0)
		expect(not guest_quote.ok and guest_quote.problems.size()==1 and guest_quote.problems[0].reason==Rules.LOCK_MESSAGE,"A visitor without the story cannot quote it either")
		var guest_apply:=world.apply_blueprint(GUEST,hex32(),cut.blueprint,BLUEPRINT_SITE,0,str(guest_quote.hash))
		expect(not guest_apply.ok and footprint_empty(BLUEPRINT_SITE),"...nor apply it")
	var guest_build:=act("build",BLUEPRINT_SITE,KIND,GUEST)
	expect(not guest_build.ok and guest_build.message==Rules.LOCK_MESSAGE and footprint_empty(BLUEPRINT_SITE),"A visitor cannot build it, though the owner earned it")

	# --- Dismantle: visitor refused, owner from the centre, undo restores -------------------------------------------
	stand(GUEST,Vector2(34.5,36.5))
	var guest_remove:=act("remove",SITE+Vector2i(1,1),"",GUEST)
	expect(not guest_remove.ok and whole_footprint(SITE),"A visitor cannot dismantle the owner's shelter")
	stand(owner,Vector2(30.5,36.5))
	bamboo=person.inventory.bamboo
	wood=person.inventory.wood
	cloth=person.inventory.cotton_cloth
	var removed:=act("remove",SITE+Vector2i(1,1))
	expect(removed.ok and footprint_empty(SITE),"Removing by the centre part dismantles the whole shelter")
	expect(person.inventory.bamboo==bamboo+30 and person.inventory.wood==wood+10 and person.inventory.cotton_cloth==cloth+8,"Dismantling refunds the full recipe once")
	var remove_undo:=str(world.undo_summary(owner).get("id",""))
	if expect(not remove_undo.is_empty(),"The removal can be undone"):
		var restored_all:=world.act(owner,"undo-removal",World.UNDO_ACTION,Vector2i.ZERO,remove_undo)
		expect(restored_all.get("ok")==true and whole_footprint(SITE) and valid(world.state),"Undoing the removal restores all nine parts")
		expect(person.inventory.bamboo==bamboo and person.inventory.wood==wood and person.inventory.cotton_cloth==cloth,"...and re-spends the recipe")
	expect(act("remove",SITE+Vector2i(2,2)).ok and footprint_empty(SITE),"Removing by a corner also dismantles the whole shelter")
	expect(world.can_stand(Vector2(SITE)+Vector2(1.5,1.5)),"The cells are open ground again")
	await finish()
