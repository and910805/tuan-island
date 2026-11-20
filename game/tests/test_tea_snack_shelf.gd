extends SceneTree
## T11 茶屋點心架: a 1x1 two-tier real food store. Each tier is an independent {item: count} store kept in
## `snack_tiers`; the server validates food-only items, counts, tier capacity, reach, target and access.
## Native screenshots: --qa-size=1024 and --qa-dir=<folder>.

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Folio=preload("res://scripts/build_folio.gd")
const Industry=preload("res://scripts/industry.gd")
const Panels=preload("res://scripts/life_ui_panels.gd")
const KIND:="tea_snack_shelf"
const ART:="res://assets/ui-life/tea-snack-shelf.png"
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
const COPY:=Vector2i(44,36)
const OWNER_NAME:="點心架屋主"
const GUEST:="tea-snack-shelf-visitor"
const GUEST_NAME:="路過的阿蓮"
const FOODS:=["ginger_tea","tea_pudding","garden_cookie","soup","mist_tea_brew"]
var app
var world:World
var owner:String
var output:String
var path:String
var sequence:=0
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(label)
	return success

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
	print("TEA_SNACK_SHELF_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func tier(index:int,tile:=SITE)->Dictionary:
	return Industry.snack_tier(obj(tile),index)

func stand_at(token:String,x:float,y:float)->void:
	world.state.players[token].x=x
	world.state.players[token].y=y

func rid(label:String)->String:
	sequence+=1
	return "%s-%d"%[label,sequence]

func put(who:String,tile:Vector2i,tier_index:int,item:String,count:int)->Dictionary:
	return world.act(who,rid("put"),Industry.SNACK_PUT,tile,"%d:%s:%d"%[tier_index,item,count])

func take(who:String,tile:Vector2i,tier_index:int,item:String,count:int)->Dictionary:
	return world.act(who,rid("take"),Industry.SNACK_TAKE,tile,"%d:%s:%d"%[tier_index,item,count])

func raw(who:String,action:String,tile:Vector2i,extra:String)->Dictionary:
	return world.act(who,rid("raw"),action,tile,extra)

## Every unit of `item` anywhere: both players' backpacks plus both tiers of every shelf.
func total(item:String)->int:
	var sum:=0
	for token:String in world.state.players:sum+=int(world.state.players[token].inventory.get(item,0))
	for tile:String in world.state.objects:
		var entry:Dictionary=world.state.objects[tile]
		if entry.get("type")==KIND:
			for index in Industry.SNACK_TIER_NAMES.size():sum+=int(Industry.snack_tier(entry,index).get(item,0))
	return sum

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func hex32()->String:
	return "%016x%016x"%[Time.get_ticks_usec(),randi()]

func focus_camera(tile:Vector2i)->void:
	app.view.camera=(Vector2(tile)+Vector2(0.5,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func publish()->void:
	app.session._send_snapshot(1)

func widget(name:String)->Node:
	return app.modal.find_child(name,true,false) if is_instance_valid(app.modal) else null

func press(name:String)->bool:
	var control:=widget(name) as Button
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func choose(item:String)->void:
	var control:=widget("SnackInventory") as OptionButton
	if not expect(control!=null,"Backpack picker is visible"):return
	for index in control.item_count:
		if control.get_item_metadata(index)==item:
			control.select(index)
			control.item_selected.emit(index)
			return
	expect(false,"Backpack option "+item)

func key_event(code:Key)->InputEventKey:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	return event

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://tea-snack-shelf-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="tea-snack-shelf-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,OWNER_NAME,path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	stand_at(owner,41.5,33.5)
	person.inventory.merge({"bamboo":40,"clay":20,"wood":9,"feed":4,"sugar":3,"strawberry_jam":2,"mist_tea":6,"ginger_tea":200,"tea_pudding":10,"garden_cookie":10,"soup":10,"mist_tea_brew":10},true)
	world.state.time=720.0
	for tile:Vector2i in [SITE,MOVED,COPY]:world.state.removed[World.key(tile)]=true
	world.add_player(GUEST,GUEST_NAME,Vector2(41.5,33.5))
	var guest:Dictionary=world.state.players[GUEST]
	guest.inventory.merge({"ginger_tea":6,"wood":5},true)
	publish()

	# --- Contract: id, recipe, footprint, collision, catalog, art ---------------------------------------
	expect(Industry.TEA_SNACK_SHELF==KIND and Industry.SNACK_PUT=="tea_snack_put" and Industry.SNACK_TAKE=="tea_snack_take","Industry.TEA_SNACK_SHELF is tea_snack_shelf")
	expect(World.BUILD.has(KIND) and World.BUILD[KIND].get("name")=="茶屋點心架","The shelf has the display name 茶屋點心架")
	expect(World.BUILD[KIND].get("bamboo")==8 and World.BUILD[KIND].get("clay")==3 and World.BUILD[KIND].size()==3,"Recipe is exactly 8 bamboo and 3 clay plus the name")
	expect(KIND not in Industry.ORIENTABLE_FOOTPRINTS and KIND not in Industry.FIXED_SQUARE_STATIONS and Industry.square_part({"type":KIND})==-1 and Industry.square_part_field(KIND)=="" ,"It is a single-cell piece, not a multi-part footprint")
	expect(KIND in World.UNDO_SOLID and KIND in preload("res://scripts/house_rooms.gd").SOLID_OBJECTS,"It blocks movement and room checks")
	expect(Folio.TEA_COLLECTION.has(KIND) and Folio.TEA_COLLECTION[Folio.TEA_COLLECTION.size()-2]==KIND,"It sits second to last in the tea catalog (the T12 pavilion closes it)")
	expect(Folio.PLACEMENT_NOTES.has(KIND) and not str(Folio.PLACEMENT_NOTES[KIND]).is_empty(),"The build folio describes the shelf")
	expect(KIND in Panels.FURNITURE,"It is listed under 家具")
	expect(Industry.SNACK_TIER_NAMES==["上層","下層"],"The two tiers are labelled 上層 and 下層")
	var art:Texture2D=load(ART)
	expect(art!=null and art.get_size()==Vector2(32,32),"tea-snack-shelf.png loads at 32x32")
	expect(app.view.SNACK_TIER_SPOTS==[Vector2(16,13),Vector2(16,23)],"Tier icons are centred at (16,13) and (16,23)")
	var thumbnail_host:=Control.new()
	root.add_child(thumbnail_host)
	var panels=Panels.new()
	var frame:Control=panels.build_picture(thumbnail_host,KIND,1)
	expect(frame.get_child_count()==1 and frame.get_child(0).get_script()==preload("res://scripts/pixel_build_thumbnail.gd") and frame.get_child(0).kind==KIND,"The catalog thumbnail is the pixel build thumbnail for the shelf (draws the shelf sprite)")
	thumbnail_host.queue_free()
	for item:String in FOODS:
		expect(World.NAMES.has(item) and Industry.snack_food(item,World.RECIPES),"Food eligibility accepts "+item)
	for item:String in ["wood","mist_tea","feed","sugar","strawberry_jam","bamboo","nonexistent_item"]:
		expect(not Industry.snack_food(item,World.RECIPES),"Food eligibility refuses "+item)

	# --- Build: exact cost, fresh empty tiers; construction undo of a fresh shelf --------------------------
	var bamboo:int=person.inventory.bamboo
	var clay:int=person.inventory.clay
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"A real build action places the shelf for its owner"):
		await finish()
		return
	expect(person.inventory.bamboo==bamboo-8 and person.inventory.clay==clay-3,"Building spends 8 bamboo and 3 clay")
	expect(obj().get("snack_tiers")==[{},{}] and obj().get("items")=={},"A new shelf has two empty tiers and no generic items")
	expect(world.blocked(SITE) and valid(world.state),"The shelf blocks walking and the fresh state passes save validation")
	var undo_id:String=str(world.undo_summary(owner).get("id",""))
	if expect(world.undo_summary(owner).get("available")==true and not undo_id.is_empty(),"Undo is offered for the fresh, empty shelf"):
		var undone:=world.act(owner,rid("undo"),World.UNDO_ACTION,Vector2i.ZERO,undo_id)
		expect(undone.get("ok")==true and obj().is_empty() and person.inventory.bamboo==bamboo and person.inventory.clay==clay,"Undo of an empty shelf returns exactly the materials")
		app._perform_build_action("build",SITE,KIND)
		expect(obj().get("type")==KIND,"The shelf can be rebuilt after undo")
		undo_id=str(world.undo_summary(owner).get("id",""))
	app._select_tool("hoe")
	app.view.set_process(false)
	focus_camera(SITE)
	publish()
	await capture("tea-snack-shelf-empty")

	# --- Independent tiers and food-only counts (server side) -------------------------------------------
	var start_tea:int=total("ginger_tea")
	var start_pudding:int=total("tea_pudding")
	var wood:int=person.inventory.wood
	for item:String in ["wood","mist_tea","feed","sugar","strawberry_jam","bamboo","nonexistent_item"]:
		expect(not put(owner,SITE,0,item,1).ok,"The server refuses non-food "+item)
	expect(person.inventory.wood==wood and total("ginger_tea")==start_tea and Industry.snack_total(obj())==0,"Refused non-food moves nothing")
	for extra:String in ["0:ginger_tea:0","0:ginger_tea:-1","0:ginger_tea:+1","0:ginger_tea:1.5","0:ginger_tea:abc","0:ginger_tea:1000","0:ginger_tea:100","2:ginger_tea:1","-1:ginger_tea:1","x:ginger_tea:1","0:ginger_tea","0::1","0:ginger_tea:1:9",""]:
		expect(not raw(owner,Industry.SNACK_PUT,SITE,extra).ok,"Malformed put request refused: "+extra)
		expect(not raw(owner,Industry.SNACK_TAKE,SITE,extra).ok,"Malformed take request refused: "+extra)
	expect(Industry.snack_total(obj())==0 and total("ginger_tea")==start_tea,"Malformed requests move nothing")
	expect(not put(owner,SITE,0,"tea_pudding",11).ok and person.inventory.tea_pudding==10,"Putting more than the backpack holds is refused")
	expect(put(owner,SITE,0,"ginger_tea",2).ok and tier(0)=={"ginger_tea":2} and tier(1).is_empty() and person.inventory.ginger_tea==198,"Upper tier takes real food from the backpack and leaves the lower tier empty")
	expect(put(owner,SITE,1,"tea_pudding",3).ok and tier(1)=={"tea_pudding":3} and tier(0)=={"ginger_tea":2},"Lower tier is independent of the upper tier")
	expect(put(owner,SITE,1,"ginger_tea",1).ok and tier(0).ginger_tea==2 and tier(1).ginger_tea==1,"The same food can sit in both tiers with separate counts")
	expect(not take(owner,SITE,1,"ginger_tea",2).ok and tier(1).ginger_tea==1 and tier(0).ginger_tea==2,"A tier cannot give more than it holds, even if the other tier has enough")
	expect(not take(owner,SITE,0,"tea_pudding",1).ok and tier(1).tea_pudding==3,"A tier cannot give food stored only in the other tier")
	expect(take(owner,SITE,1,"ginger_tea",1).ok and not tier(1).has("ginger_tea") and tier(0).ginger_tea==2,"Taking a whole stack frees it without touching the other tier")
	expect(total("ginger_tea")==start_tea and total("tea_pudding")==start_pudding,"Food is conserved: nothing duplicated or lost")
	expect(put(owner,SITE,0,"garden_cookie",1).ok and put(owner,SITE,0,"soup",1).ok and tier(0).size()==3,"A tier holds three kinds")
	expect(not put(owner,SITE,0,"mist_tea_brew",1).ok and not tier(0).has("mist_tea_brew") and person.inventory.mist_tea_brew==10,"A fourth kind on one tier is refused")
	expect(put(owner,SITE,1,"mist_tea_brew",1).ok and tier(1).size()==2,"The other tier still has room for it")
	expect(put(owner,SITE,0,"ginger_tea",97).ok and tier(0).ginger_tea==99,"A stack can reach the 99 limit")
	expect(not put(owner,SITE,0,"ginger_tea",1).ok and tier(0).ginger_tea==99,"A stack above 99 is refused")
	expect(Industry.snack_total(obj())==99+1+1+3+1+0 and obj().items.is_empty(),"The generic items stay empty; stock lives only in the two tiers")
	expect(take(owner,SITE,0,"ginger_tea",97).ok and tier(0).ginger_tea==2,"Withdrawing in bulk returns exactly that many")
	expect(valid(world.state),"The stocked state passes save validation")
	publish()
	await capture("tea-snack-shelf-stocked")

	# --- Permissions, reach and target ---------------------------------------------------------------------
	var guest_tea:int=guest.inventory.ginger_tea
	expect(not put(GUEST,SITE,0,"ginger_tea",1).ok and guest.inventory.ginger_tea==guest_tea and tier(0).ginger_tea==2,"A private shelf refuses a guest's deposit")
	expect(not take(GUEST,SITE,0,"ginger_tea",1).ok and tier(0).ginger_tea==2,"A private shelf refuses a guest's withdrawal")
	expect(not raw(GUEST,Industry.CABINET_ACCESS,SITE,"island").ok and not obj().get("cabinet_shared",false),"Only the owner can open the shelf to the island")
	var seen:Dictionary=app.session.public_state("home",GUEST).objects[World.key(SITE)]
	expect(seen.get("locked")==true and seen.snack_tiers==[{},{}] and seen.items.is_empty(),"A guest's snapshot hides every count of a private shelf")
	expect(tier(0).ginger_tea==2 and Industry.snack_total(obj())==2+1+1+3+1,"Redaction never touches the real stock")
	var empty_cell:=Vector2i(SITE.x+1,SITE.y+1)
	expect(obj(empty_cell).is_empty() and not raw(owner,Industry.SNACK_PUT,empty_cell,"0:ginger_tea:1").ok and not raw(owner,Industry.SNACK_TAKE,empty_cell,"0:ginger_tea:1").ok,"A cell without a shelf is not a valid target")
	stand_at(owner,52.5,33.5)
	var far_total:=Industry.snack_total(obj())
	expect(not put(owner,SITE,0,"soup",1).ok and not take(owner,SITE,0,"soup",1).ok and Industry.snack_total(obj())==far_total,"The owner must be within reach to deposit or withdraw")
	stand_at(owner,41.5,33.5)
	expect(raw(owner,Industry.CABINET_ACCESS,SITE,"island").ok and obj().get("cabinet_shared")==true,"The owner opens the shelf to the island")
	expect(not raw(owner,Industry.CABINET_ACCESS,SITE,"maybe").ok,"An invalid access value is refused")
	stand_at(GUEST,60.5,33.5)
	expect(not put(GUEST,SITE,0,"ginger_tea",1).ok and not take(GUEST,SITE,0,"ginger_tea",1).ok,"A shared shelf still needs the guest to be nearby")
	stand_at(GUEST,41.5,33.5)
	expect(put(GUEST,SITE,0,"ginger_tea",2).ok and tier(0).ginger_tea==4 and guest.inventory.ginger_tea==guest_tea-2,"Once shared, a nearby guest deposits real food")
	expect(not put(GUEST,SITE,1,"wood",1).ok and guest.inventory.wood==5,"A guest cannot store non-food either")
	expect(take(GUEST,SITE,0,"ginger_tea",3).ok and tier(0).ginger_tea==1 and guest.inventory.ginger_tea==guest_tea+1,"A nearby guest withdraws from the shared shelf")
	expect(not raw(GUEST,Industry.CABINET_ACCESS,SITE,"owner").ok and obj().get("cabinet_shared")==true,"A guest cannot take the shelf back to private")
	seen=app.session.public_state("home",GUEST).objects[World.key(SITE)]
	expect(not seen.get("locked",false) and seen.snack_tiers[0].get("ginger_tea")==1,"A shared shelf shows its stock to the guest")
	expect(raw(owner,Industry.CABINET_ACCESS,SITE,"owner").ok and not obj().has("cabinet_shared"),"The owner can make it private again")
	seen=app.session.public_state("home",GUEST).objects[World.key(SITE)]
	expect(seen.get("locked")==true and seen.snack_tiers==[{},{}] and str(seen.get("snack_display"))==str([Industry.snack_lead(obj(),0),Industry.snack_lead(obj(),1)]),"Private again: counts are hidden, while only each tier's lead item stays drawable")
	expect(total("ginger_tea")==start_tea,"Guest transfers conserve the island's food")

	# --- Real UI: E opens, tiers list icon / name / quantity, buttons call the server, E and Esc close ----------
	publish()
	app._interact()
	if not expect(widget("SnackTier0")!=null and widget("SnackTier1")!=null,"Interact opens the two-tier panel"):
		await finish()
		return
	expect(app.modal.get_meta("life_modal_layout","")=="tea_snack_shelf","The panel uses its own layout")
	expect((widget("SnackTierTitle0") as Label).text=="上層" and (widget("SnackTierTitle1") as Label).text=="下層","Both tiers are labelled")
	var name0:=widget("SnackName_0_0") as Label
	var count0:=widget("SnackCount_0_0") as Label
	var icon0:=widget("SnackIcon_0_0") as TextureRect
	expect(name0.text==World.NAMES[Industry.snack_ids(tier(0))[0]] and count0.text=="×%d"%int(tier(0)[Industry.snack_ids(tier(0))[0]]),"A row shows the stored item's name and quantity")
	expect(icon0.texture!=null,"A row shows the stored item's icon")
	expect((widget("SnackName_1_0") as Label).text==World.NAMES[Industry.snack_ids(tier(1))[0]],"The lower tier lists its own food")
	expect(widget("SnackAccess") is Button and (widget("SnackAccess") as Button).visible,"The owner sees the access toggle")
	expect((widget("SnackPolicy") as Label).text=="只有主人可以存取。","The panel states the private policy")
	await capture("tea-snack-shelf-panel")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		var scroll:=widget("ModalScroll") as ScrollContainer
		for control_name:String in ["SnackDeposit0","SnackDeposit1","SnackInventory","SnackAmount","SnackAccess"]:
			var control:=widget(control_name) as Control
			expect(scroll.get_global_rect().encloses(control.get_global_rect()),control_name+" is fully visible without scrolling")
	choose("garden_cookie")
	(widget("SnackAmount") as LineEdit).text="4"
	(widget("SnackAmount") as LineEdit).text_changed.emit("4")
	var cookies:int=int(tier(1).get("garden_cookie",0))
	var upper_cookies:int=int(tier(0).get("garden_cookie",0))
	expect(press("SnackDeposit1") and int(tier(1).get("garden_cookie",0))==cookies+4,"The lower deposit button stores four on that tier only")
	expect(int(tier(0).get("garden_cookie",0))==upper_cookies,"The upper tier's own garden_cookie stack is unchanged")
	publish()
	var first:String=Industry.snack_ids(tier(0))[0]
	var first_before:int=int(tier(0)[first])
	expect(press("SnackTake_0_0") and int(tier(0).get(first,0))==first_before-1,"A row's take button withdraws one real unit of the listed item")
	publish()
	(widget("SnackAmount") as LineEdit).text="0"
	(widget("SnackAmount") as LineEdit).text_changed.emit("0")
	expect((widget("SnackDeposit0") as Button).disabled and (widget("SnackDeposit1") as Button).disabled,"Deposit buttons are disabled for an invalid count")
	(widget("SnackAmount") as LineEdit).text="1"
	(widget("SnackAmount") as LineEdit).text_changed.emit("1")
	var picker:=widget("SnackInventory") as OptionButton
	var listed:PackedStringArray=[]
	for index in range(1,picker.item_count):listed.append(str(picker.get_item_metadata(index)))
	expect(not listed.has("wood") and not listed.has("mist_tea") and not listed.has("feed") and not listed.has("strawberry_jam") and listed.has("soup"),"The picker lists only edible backpack items")
	app._unhandled_input(key_event(KEY_E))
	expect(app.modal==null,"Pressing the interact key again closes the panel")
	app._interact()
	expect(widget("SnackTier0")!=null,"Interact reopens the panel")
	app._unhandled_input(key_event(KEY_ESCAPE))
	expect(app.modal==null,"Esc closes the panel")
	stand_at(owner,41.5,33.5)

	# --- Moving keeps both tiers; only the owner may move ------------------------------------------------------
	var tiers_before:=var_to_str(obj().snack_tiers)
	var move:=world.act(GUEST,rid("guest-move"),"move_object",SITE,World.key(MOVED))
	expect(not move.ok and obj().get("type")==KIND and obj(MOVED).is_empty(),"A guest cannot move the owner's shelf")
	expect(world.act(owner,rid("free-move"),"move_object",SITE,World.key(MOVED)).ok and obj(MOVED).get("type")==KIND and obj().is_empty(),"The owner moves a stocked shelf")
	expect(var_to_str(obj(MOVED).snack_tiers)==tiers_before and not obj(MOVED).has("cabinet_shared"),"Both tiers survive the move unchanged")
	expect(not world.blocked(SITE) and world.blocked(MOVED),"The old cell is free and the new one blocks")
	var moved_undo:=world.undo_summary(owner)
	if expect(moved_undo.get("available")==true,"Undo is offered for the move"):
		var back:=world.act(owner,rid("undo-move"),World.UNDO_ACTION,Vector2i.ZERO,str(moved_undo.get("id","")))
		expect(back.get("ok")==true and obj().get("type")==KIND and obj(MOVED).is_empty(),"Undoing the move puts the shelf back")
		expect(var_to_str(obj().snack_tiers)==tiers_before,"Undoing a move neither loses nor duplicates stock")
	else:
		expect(world.act(owner,rid("move-back"),"move_object",MOVED,World.key(SITE)).ok,"Moved back by hand")
	expect(total("ginger_tea")==start_tea and total("tea_pudding")==start_pudding,"Food totals are unchanged after moving and undoing")

	# --- Construction undo and removal never lose or duplicate stock ---------------------------------------------
	if not undo_id.is_empty():
		var stale:=world.act(owner,rid("stale-undo"),World.UNDO_ACTION,Vector2i.ZERO,undo_id)
		expect(not stale.ok and obj().get("type")==KIND and var_to_str(obj().snack_tiers)==tiers_before,"Undo of the original build is closed once the shelf is used")
	var materials:int=person.inventory.bamboo
	var removal:=world.act(owner,rid("stocked-remove"),"remove",SITE)
	expect(not removal.ok and obj().get("type")==KIND and person.inventory.bamboo==materials and var_to_str(obj().snack_tiers)==tiers_before,"A stocked shelf cannot be dismantled, and nothing is refunded")
	expect(not world.act(GUEST,rid("guest-remove"),"remove",SITE).ok and obj().get("type")==KIND,"A guest cannot dismantle the shelf")
	expect(total("ginger_tea")==start_tea and total("tea_pudding")==start_pudding,"A refused removal keeps every food unit")

	# --- Save and reload keep both tiers; validation guards the schema; old saves load ---------------------------
	expect(world.save(),"The world saves with a stocked shelf")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The primary save reloads")
	var reloaded:Dictionary=loaded.state.objects.get(World.key(SITE),{})
	expect(reloaded.get("type")==KIND and Industry.snack_tier(reloaded,0)==tier(0) and Industry.snack_tier(reloaded,1)==tier(1),"Reload keeps both tiers exactly")
	var whole:=true
	for index in Industry.SNACK_TIER_NAMES.size():
		for item in Industry.snack_tier(reloaded,index):whole=whole and typeof(Industry.snack_tier(reloaded,index)[item])==TYPE_INT
	expect(whole,"Reloaded counts are integers")
	var key:=World.key(SITE)
	expect(valid(world.state.duplicate(true)),"Control: the stocked state is valid before any forgery")
	var bad:=world.state.duplicate(true)
	bad.objects[key].snack_tiers[0]["wood"]=1
	expect(not valid(bad),"Validation rejects non-food in a tier")
	bad=world.state.duplicate(true)
	bad.objects[key].snack_tiers[0]["ginger_tea"]=100
	expect(not valid(bad),"Validation rejects more than 99 in a stack")
	bad=world.state.duplicate(true)
	bad.objects[key].snack_tiers[0]["ginger_tea"]=0
	expect(not valid(bad),"Validation rejects an empty stack entry")
	bad=world.state.duplicate(true)
	bad.objects[key].snack_tiers[1]={"ginger_tea":1,"soup":1,"tea_pudding":1,"garden_cookie":1}
	expect(not valid(bad),"Validation rejects four kinds on one tier")
	bad=world.state.duplicate(true)
	bad.objects[key].snack_tiers=[{}]
	expect(not valid(bad),"Validation rejects a missing tier")
	bad=world.state.duplicate(true)
	bad.objects[key].items={"ginger_tea":1}
	expect(not valid(bad),"Validation rejects stock duplicated into the generic items")
	bad=world.state.duplicate(true)
	bad.objects[key].cabinet_shared="true"
	expect(not valid(bad),"Validation rejects a malformed share flag")
	bad=world.state.duplicate(true)
	var lamp_key:=World.key(MOVED)
	bad.objects[lamp_key]={"type":"lamp","owner":owner,"items":{},"snack_tiers":[{},{}]}
	expect(not valid(bad),"Validation rejects shelf data on another furniture type")
	var legacy:=world.state.duplicate(true)
	legacy.objects[key].erase("snack_tiers")
	expect(valid(legacy) and legacy.objects[key].snack_tiers==[{},{}],"An old/hand-edited shelf without tier data loads with two empty tiers")
	var old_world:=world.state.duplicate(true)
	old_world.objects.erase(key)
	expect(valid(old_world),"A save without any shelf (every old save) still validates")

	# --- Blueprint copies carry no stock; the pasted shelf is fresh -----------------------------------------------
	var plan:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"點心架",World.BUILD,World.NAMES)
	if expect(plan.ok and plan.blueprint.pieces.size()==1 and plan.blueprint.pieces[0].kind==KIND,"The blueprint captures the shelf as one piece"):
		var serialised:=var_to_str(plan.blueprint)
		expect(not serialised.contains(Industry.SNACK_FIELD) and not serialised.contains("ginger_tea") and not serialised.contains("cabinet_shared"),"The blueprint holds no stored food and no sharing choice")
		stand_at(owner,44.5,35.5)
		bamboo=person.inventory.bamboo
		clay=person.inventory.clay
		var quote:=world.quote_blueprint(owner,plan.blueprint,COPY,0)
		if expect(quote.get("ok")==true,"Quote for the copy succeeds: "+str(quote.get("message",""))):
			var applied:=world.apply_blueprint(owner,hex32(),plan.blueprint,COPY,0,str(quote.hash))
			expect(applied.get("ok")==true,"Applying the blueprint succeeds: "+str(applied.get("message","")))
			expect(person.inventory.bamboo==bamboo-8 and person.inventory.clay==clay-3,"The blueprint charges exactly one shelf recipe")
			expect(obj(COPY).get("type")==KIND and obj(COPY).get("snack_tiers")==[{},{}] and obj(COPY).get("items")=={},"The copy starts with two empty tiers")
			expect(var_to_str(obj().snack_tiers)==tiers_before and total("ginger_tea")==start_tea,"The original keeps its stock and no food is duplicated")
			expect(valid(world.state),"The state with the copy passes save validation")
			var copy_undo:=world.undo_summary(owner)
			if copy_undo.get("available")==true:
				var undone_copy:=world.act(owner,rid("undo-copy"),World.UNDO_ACTION,Vector2i.ZERO,str(copy_undo.get("id","")))
				expect(undone_copy.get("ok")==true and obj(COPY).is_empty() and obj().get("type")==KIND,"Undo of an unused blueprint copy removes only the fresh shelf")
				expect(var_to_str(obj().snack_tiers)==tiers_before and total("ginger_tea")==start_tea,"Blueprint undo leaves the original stock untouched")
	stand_at(owner,41.5,33.5)

	# --- Empty it, dismantle it, refund materials, keep every unit ---------------------------------------------------
	for index in Industry.SNACK_TIER_NAMES.size():
		for item:String in Industry.snack_ids(tier(index)):
			expect(take(owner,SITE,index,item,int(tier(index)[item])).ok,"Retrieves tier %d %s"%[index,item])
	expect(Industry.snack_total(obj())==0 and total("ginger_tea")==start_tea and total("tea_pudding")==start_pudding,"Emptied shelf: every unit is back in the backpacks")
	materials=person.inventory.bamboo
	var clay_now:int=person.inventory.clay
	expect(world.act(owner,rid("empty-remove"),"remove",SITE).ok and obj().is_empty(),"The owner can dismantle the emptied shelf")
	expect(person.inventory.bamboo==materials+8 and person.inventory.clay==clay_now+3,"Dismantling refunds the full recipe")
	expect(total("ginger_tea")==start_tea and valid(world.state),"No food appeared or vanished through the whole run")
	await finish()
