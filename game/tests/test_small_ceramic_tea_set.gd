extends SceneTree

# T07 小陶茶具. Native headless by default; pixel checks run only on a real renderer.
# Optional: --qa-dir=<folder> saves screenshots, --qa-size=1024 uses a 1024x640 window.

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Session=preload("res://scripts/session.gd")
const SET:=Industry.TEA_SET
const ART:="res://assets/ui-inventory/small-ceramic-tea-set.png"
const BENCH:=Vector2i(40,40)
const TABLE:=Vector2i(40,34)
const ROUND:=Vector2i(46,34)
const TEA:=Vector2i(51,34)
const GUEST:="tea-set-guest"
const POUR:="tea_pour"
const SERVE:="tea_serve"
var app
var world:World
var owner:String
var person:Dictionary
var guest:Dictionary
var output:String
var path:String
var checks:=0
var failures:=0
var request:=0
var guest_sequence:=0
var emotes:Array[String]=[]

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
	return world.act(owner if actor.is_empty() else actor,"tea-set-%d"%request,action,at,extra)

func bag(item:String)->int:
	return int(person.inventory.get(item,0))

func obj(at:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(at),{})

func items(at:Vector2i)->Dictionary:
	return obj(at).get("items",{})

func valid(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

## Everything a pouring emote must leave alone: coins, every bag, every table.
func books()->Dictionary:
	var bags:={}
	for token:String in world.state.players:
		bags[token]={"coins":int(world.state.players[token].get("coins",0)),"inventory":world.state.players[token].inventory.duplicate(true)}
	return {"bags":bags,"objects":world.state.objects.duplicate(true)}

func stand(at:Vector2)->void:
	person.x=at.x
	person.y=at.y
	app.session._send_snapshot(1)

func widget(widget_name:String)->Control:
	return app.modal.find_child(widget_name,true,false) as Control if is_instance_valid(app.modal) else null

func press(widget_name:String)->bool:
	var button:=widget(widget_name) as Button
	if not expect(button!=null and not button.disabled and button.visible,"Available button "+widget_name):return false
	button.pressed.emit()
	return true

## The owner (peer 1) sends an emote through the real session path and the cooldown is reset first.
func owner_emote(id:String)->Array[String]:
	emotes.clear()
	app.session.emote_sent_at.erase(1)
	app.session.rates[1].clear()
	app.session.perform("emote",Vector2i.ZERO,id)
	return emotes.duplicate()

## A visitor (fake peer 2, no network transport) sends the same request through _action.
func guest_emote(id:String)->Array[String]:
	emotes.clear()
	app.session.emote_sent_at.erase(2)
	app.session.rates[2].clear()
	guest_sequence+=1
	app.session._action(2,guest_sequence,"emote",Vector2i.ZERO,id)
	return emotes.duplicate()

func texture_ok()->void:
	var texture:=load(ART) as Texture2D
	if not expect(texture!=null and texture.get_size()==Vector2(32,24),"The tea set icon imports as 32×24"):return
	var image:=texture.get_image()
	var last:=Vector2i(image.get_width()-1,image.get_height()-1)
	var clear:=0
	for corner:Vector2i in [Vector2i.ZERO,Vector2i(last.x,0),Vector2i(0,last.y),last]:
		if image.get_pixelv(corner).a<0.01:clear+=1
	expect(clear>=3,"The icon has a transparent background")

func frame(capture_name:="")->Image:
	app.view.queue_redraw()
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty() and not capture_name.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(capture_name+".png"))==OK,"Screenshot "+capture_name)
	return image

func focus(cell:Vector2i,span:=Vector2(1,0.5))->void:
	app.view.set_process(false)
	app.view.camera=(Vector2(cell)+span)*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())

func region_difference(a:Image,b:Image,cell:Vector2i,offset:Vector2,half:int)->float:
	var local:Vector2=app.view.screen(Vector2(cell)+offset)
	var centre:=Vector2i((local*app.view.view_zoom()).round())
	var total:=0.0
	var samples:=0
	for dy in range(-half,half+1):
		for dx in range(-half,half+1):
			var at:=centre+Vector2i(dx,dy)
			if at.x<0 or at.y<0 or at.x>=a.get_width() or at.y>=a.get_height():continue
			var one:=a.get_pixelv(at)
			var two:=b.get_pixelv(at)
			total+=absf(one.r-two.r)+absf(one.g-two.g)+absf(one.b-two.b)
			samples+=1
	return total/float(maxi(samples,1))

func finish()->void:
	app.session.peers.erase(2)
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.22).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SMALL_CERAMIC_TEA_SET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://small-ceramic-tea-set-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="tea-set-owner"
	if app.session.host(0,"小陶茶具測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	app.session.emote_received.connect(func(_actor:String,_region:String,caption:String):emotes.append(caption))
	world=app.session.world
	owner=app.session.peers[1]
	person=world.state.players[owner]
	person.coins=500
	person.inventory={"wood":80,"stone":5,"bamboo":12,"clay":19,"mist_tea":4,Industry.TABLE_VASE:1,"mist_tea_brew":5,"tea_pudding":1}
	world.state.time=720.0
	var cells:Array[Vector2i]=[BENCH,BENCH+Vector2i.RIGHT,TABLE,ROUND,ROUND+Vector2i.RIGHT,TEA,TEA+Vector2i.RIGHT]
	for cell:Vector2i in cells:world.state.removed[World.key(cell)]=true
	world.add_player(GUEST,"訪客",Vector2(30.5,30.5))
	guest=world.state.players[GUEST]
	guest.inventory={"clay":6,"mist_tea":1}
	guest.coins=77
	app.session.peers[2]=GUEST
	app.session.sequences[2]=0
	app.session.rates[2]=[]
	app.session._send_snapshot(1)

	# --- data, catalogue, icon, guide ---------------------------------------------------
	var recipe:Dictionary=World.CRAFT.get(SET,{})
	expect(SET=="small_ceramic_tea_set" and recipe.get("name")=="小陶茶具" and recipe.get("ingredients")=={"clay":6,"mist_tea":1} and int(recipe.get("yield",0))==1,"Recipe is 6 clay + 1 mist tea for one set")
	expect(World.NAMES.get(SET)=="小陶茶具" and World.ITEM_CATALOG.is_known(SET),"The set is a known, named inventory item")
	expect(not World.BUILD.has(SET) and SET not in Industry.TWO_CELL_STATIONS and SET not in Industry.ORIENTABLE_FOOTPRINTS and not World.RECIPES.has(SET),"It is a tabletop item: no floor footprint, build entry or meal recipe")
	expect(not Industry.shareable_meal(SET,World.RECIPES) and not Industry.four_seat_meal(Industry.BAMBOO_TEA_TABLE,SET,World.RECIPES),"It can never count as a meal")
	expect(SET in Industry.WOOD_TABLE_DISPLAY and SET in Industry.ROUNDED_DECOR and Industry.rounded_table_item(SET,World.RECIPES),"It rides the existing wood-table and rounded-table display lists")
	expect(preload("res://scripts/inventory_panel.gd").category_for(SET)==4,"It sits in the 其他 inventory category with the other table decor")
	expect(not preload("res://scripts/inventory_panel.gd").use_for(SET).is_empty() and preload("res://scripts/automation_ui.gd").GUIDE.get(SET,{}).get("kind")=="table_display","Inventory help and workbench guidance explain it")
	expect(not preload("res://scripts/economy_audit.gd").sale_table().has(SET),"It has no sale price anywhere")
	expect(preload("res://scripts/inventory_item_art.gd").icon(SET)==load(ART),"The inventory icon is the supplied art")
	texture_ok()
	expect(Industry.TEA_SET_EMOTES.size()==2 and Industry.TEA_SET_EMOTES.has(POUR) and Industry.TEA_SET_EMOTES.has(SERVE) and Industry.TEA_SET_EMOTES[POUR]!=Industry.TEA_SET_EMOTES[SERVE],"Two distinguishable pouring emotes exist")
	for id:String in Industry.TEA_SET_EMOTES:
		expect(not Session.EMOTES.has(id) and Industry.TEA_SET_EMOTE_BUTTONS.has(id),id+" is kept out of the generic emote list and has a button label")

	# --- crafting ----------------------------------------------------------------------
	stand(Vector2(40.5,38.5))
	expect(act("build",BENCH,"bench").ok,"Build a workbench")
	var coins_before:=int(person.coins)
	var crafted:=act("craft",BENCH,SET)
	expect(crafted.ok and bag(SET)==1 and bag("clay")==13 and bag("mist_tea")==3,"Crafting spends exactly 6 clay and 1 mist tea and yields one set: "+str(crafted.get("message","")))
	expect(int(person.coins)==coins_before,"Crafting touches no coins")
	person.inventory.clay=5
	expect(not act("craft",BENCH,SET).ok and bag(SET)==1 and bag("clay")==5 and bag("mist_tea")==3,"Too little clay is refused without spending anything")
	person.inventory.clay=13
	person.inventory.mist_tea=0
	expect(not act("craft",BENCH,SET).ok and bag(SET)==1 and bag("clay")==13,"No mist tea is refused without spending anything")
	person.inventory.mist_tea=3
	expect(not act("build",TABLE,SET).ok and not world.state.objects.has(World.key(TABLE)),"The set cannot be placed on the floor as furniture")
	for count in 2:expect(act("craft",BENCH,SET).ok,"Craft set %d"%(count+2))
	expect(bag(SET)==3 and bag("clay")==1 and bag("mist_tea")==1,"Three sets cost exactly 18 clay and 3 mist tea")
	var worth:=int(person.coins)

	# --- build the three existing tables ------------------------------------------------
	stand(Vector2(40.5,35.5))
	expect(act("build",TABLE,"table").ok,"Build a regular wood table")
	stand(Vector2(46.5,35.5))
	var rounded:=act("build",ROUND,Industry.ROUNDED_TABLE)
	expect(rounded.ok,"Build a rounded table: "+str(rounded.get("message","")))
	stand(Vector2(51.5,35.5))
	expect(act("build",TEA,Industry.BAMBOO_TEA_TABLE).ok,"Build a bamboo tea table")
	if not expect(obj(TABLE).get("type")=="table" and obj(ROUND).get("type")==Industry.ROUNDED_TABLE and obj(TEA).get("type")==Industry.BAMBOO_TEA_TABLE,"All three tables stand"):
		await finish()
		return

	# --- the guard: no fixture, no pouring ---------------------------------------------
	var untouched:=books()
	stand(Vector2(40.5,35.5))
	expect(owner_emote(POUR).is_empty() and owner_emote(SERVE).is_empty(),"Beside an empty table the pouring emotes are refused")
	expect(owner_emote("hello")==["你好！"],"The generic emote still works with no fixture")
	stand(Vector2(33.5,28.5))
	expect(owner_emote(POUR).is_empty() and not world.tea_set_nearby(owner),"Far from any table the hotkey cannot invoke a pouring emote")
	expect(owner_emote("nonsense").is_empty(),"Unknown emote ids are still ignored")
	expect(books()==untouched,"Refused and generic emotes change no bag, coin or table")

	# --- regular table -----------------------------------------------------------------
	stand(Vector2(40.5,35.5))
	var put:=act(Industry.SHELL_PUT,TABLE,SET)
	expect(put.ok and items(TABLE)=={SET:1} and bag(SET)==2,"The owner puts one set on the wood table: "+str(put.get("message","")))
	expect(not act(Industry.SHELL_PUT,TABLE,Industry.TABLE_VASE).ok and items(TABLE)=={SET:1},"A wood table still shows only one item")
	expect(Industry.has_tea_set(obj(TABLE)) and world.tea_set_nearby(owner),"The host sees a placed set beside the owner")
	var before:=books()
	expect(owner_emote(POUR)==[Industry.TEA_SET_EMOTES[POUR]],"The owner can pour beside the placed set")
	expect(owner_emote(SERVE)==[Industry.TEA_SET_EMOTES[SERVE]],"The owner can serve beside the placed set")
	expect(books()==before and int(person.coins)==worth,"Emotes never set inventory or coins")
	app.session.emote_sent_at.erase(1)
	owner_emote(POUR)
	emotes.clear()
	app.session.perform("emote",Vector2i.ZERO,SERVE)
	expect(emotes.is_empty(),"The existing cooldown also covers pouring emotes")
	# visitors: nearby may pour without taking the set; far away may not
	guest.x=41.5
	guest.y=36.5
	var guest_before:Dictionary=guest.inventory.duplicate()
	expect(guest_emote(POUR)==[Industry.TEA_SET_EMOTES[POUR]] and guest_emote(SERVE)==[Industry.TEA_SET_EMOTES[SERVE]],"A nearby visitor can pour and serve without holding a set")
	expect(guest.inventory==guest_before and int(guest.coins)==77 and items(TABLE)=={SET:1},"The visitor gained and lost nothing")
	expect(not act(Industry.SHELL_TAKE,TABLE,SET,GUEST).ok and not act(Industry.SHELL_PUT,TABLE,SET,GUEST).ok and items(TABLE)=={SET:1},"Only the owner controls the display")
	expect(not act("remove",TABLE,"",GUEST).ok and not act("remove",TABLE).ok and obj(TABLE).get("type")=="table","Nobody can dismantle the table while the set is on it")
	guest.x=30.5
	guest.y=30.5
	expect(guest_emote(POUR).is_empty(),"A visitor who walks away can no longer pour")

	# --- native UI on the regular table ------------------------------------------------
	stand(Vector2(40.5,35.5))
	app._select_tool("hoe")
	app._interact()
	var row:=widget("TeaSetEmotes")
	if expect(row!=null and row.visible and widget("TeaSetEmote_tea_pour")!=null and widget("TeaSetEmote_tea_serve")!=null,"The table page lists the two pouring emotes beside a set"):
		emotes.clear()
		app.session.emote_sent_at.erase(1)
		press("TeaSetEmote_tea_serve")
		expect(emotes==[Industry.TEA_SET_EMOTES[SERVE]],"The 奉茶 button sends the serving emote")
		expect(app.view.active_emote(Session._public_actor(owner)).get("fx")=="pour","The emote carries the cosmetic pour effect")
	if is_instance_valid(app.modal):app._close_modal()
	var taken:=act(Industry.SHELL_TAKE,TABLE,SET)
	expect(taken.ok and items(TABLE).is_empty() and bag(SET)==3,"The owner takes the set back")
	app.session._send_snapshot(1)
	app._interact()
	expect(widget("TeaSetEmotes")!=null and not widget("TeaSetEmotes").visible,"Without a set the emote buttons are hidden")
	if is_instance_valid(app.modal):app._close_modal()
	expect(act(Industry.SHELL_PUT,TABLE,SET).ok and owner_emote(POUR).size()==1,"The set goes back and the emote works again")

	# --- rounded table -----------------------------------------------------------------
	stand(Vector2(46.5,35.5))
	expect(act(Industry.SHELL_PUT,ROUND,SET).ok and act(Industry.SHELL_PUT,ROUND+Vector2i.RIGHT,Industry.TABLE_VASE).ok,"The rounded table holds a set and a vase together")
	expect(items(ROUND)=={SET:1,Industry.TABLE_VASE:1} and bag(SET)==1,"Both items left the bag exactly once")
	expect(not act(Industry.SHELL_PUT,ROUND,SET).ok and items(ROUND)=={SET:1,Industry.TABLE_VASE:1} and bag(SET)==1,"A full table refuses another set without spending it")
	expect(not act(Industry.ROUNDED_EAT,ROUND,SET).ok and items(ROUND).has(SET),"The set cannot be eaten from the rounded table")
	expect(owner_emote(SERVE).size()==1,"The owner pours beside the rounded table from either half")
	guest.x=47.5
	guest.y=36.5
	expect(guest_emote(POUR).size()==1 and not act(Industry.SHELL_TAKE,ROUND,SET,GUEST).ok and items(ROUND).has(SET),"A visitor pours at the rounded table but cannot take the set")
	guest.x=30.5
	guest.y=30.5
	app.session._send_snapshot(1)
	app._interact()
	row=widget("TeaSetEmotes")
	expect(row!=null and row.visible and widget("TeaSetEmote_tea_pour")!=null,"The rounded table page lists the pouring emotes")
	if is_instance_valid(app.modal):app._close_modal()
	expect(not act("remove",ROUND).ok and obj(ROUND).get("type")==Industry.ROUNDED_TABLE,"The rounded table cannot be removed while loaded")

	# --- bamboo tea table: own flag, meal stock untouched --------------------------------
	stand(Vector2(51.5,35.5))
	for dish:String in ["mist_tea_brew","mist_tea_brew","mist_tea_brew","mist_tea_brew"]:expect(act(Industry.MUSHROOM_SERVE,TEA,dish).ok,"Serve "+dish)
	expect(items(TEA)=={"mist_tea_brew":4} and not act(Industry.MUSHROOM_SERVE,TEA,"tea_pudding").ok,"Four meals fill the tea table")
	var set_put:=act(Industry.MUSHROOM_SERVE,TEA,SET)
	expect(set_put.ok and obj(TEA).get(Industry.TEA_SET_FIELD)==true and bag(SET)==0,"A set still fits on a full tea table: "+str(set_put.get("message","")))
	expect(items(TEA)=={"mist_tea_brew":4} and not items(TEA).has(SET),"The set never enters meal stock")
	expect(not act(Industry.MUSHROOM_SERVE,TEA,SET).ok and bag(SET)==0,"A second set is refused")
	expect(not act(Industry.MUSHROOM_EAT,TEA,SET).ok and obj(TEA).get(Industry.TEA_SET_FIELD)==true,"The set cannot be eaten")
	expect(not act(Industry.MUSHROOM_SERVE,ROUND,SET).ok and not act(Industry.MUSHROOM_SERVE,TABLE,SET).ok,"The serve action cannot put a set on a table that does not use that path")
	expect(act(Industry.MUSHROOM_SIT,TEA,"0").ok,"Sit at the tea table")
	var energy:=int(person.mine_energy)
	expect(act(Industry.MUSHROOM_EAT,TEA,"mist_tea_brew").ok and items(TEA)=={"mist_tea_brew":3} and obj(TEA).get(Industry.TEA_SET_FIELD)==true and int(person.mine_energy)>=energy,"Eating a meal leaves the set in place")
	expect(owner_emote(POUR).size()==1,"A seated guest of the tea table can pour")
	expect(act(Industry.MUSHROOM_SIT,TEA,"leave").ok,"Stand up again")
	guest.x=52.5
	guest.y=36.5
	expect(guest_emote(SERVE).size()==1,"A visitor pours at the tea table without owning anything")
	expect(not act(Industry.MUSHROOM_TAKE,TEA,SET,GUEST).ok and not act(Industry.MUSHROOM_SERVE,TEA,SET,GUEST).ok and obj(TEA).get(Industry.TEA_SET_FIELD)==true,"Only the owner can take the set away")
	guest.x=30.5
	guest.y=30.5
	app.session._send_snapshot(1)
	app._interact()
	var toggle:=widget("BambooTeaTableSetToggle") as Button
	expect(toggle!=null and toggle.text.contains("取回") and widget("TeaSetEmotes")!=null and widget("TeaSetEmotes").visible,"The tea table page offers the owner a take-back button and the two emotes")
	if DisplayServer.get_name()!="headless" and toggle!=null:
		await frame("tea-set-menu")
		var emote_row:=widget("TeaSetEmotes") as Control
		var scroll:Node=emote_row.get_parent() if emote_row!=null else null
		while scroll!=null and not scroll is ScrollContainer:scroll=scroll.get_parent()
		expect(scroll is ScrollContainer and (scroll as ScrollContainer).get_global_rect().encloses(emote_row.get_global_rect()),"Both emotes are visible without scrolling when the tea table holds refreshments")
	if is_instance_valid(app.modal):app._close_modal()
	expect(not act("remove",TEA).ok and obj(TEA).get("type")==Industry.BAMBOO_TEA_TABLE,"The tea table cannot be removed while it holds the set")

	# --- save, reload and secure schema --------------------------------------------------
	expect(world.save(),"The world saves with all three displays")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup,"The world reloads")
	expect(loaded.state.objects[World.key(TABLE)].items=={SET:1} and loaded.state.objects[World.key(ROUND)].items=={SET:1,Industry.TABLE_VASE:1} and loaded.state.objects[World.key(TEA)].get(Industry.TEA_SET_FIELD)==true,"All three sets survive a real reload")
	expect(Industry.has_tea_set(loaded.state.objects[World.key(TEA)]) and loaded.state.objects[World.key(TEA)].items=={"mist_tea_brew":3},"The tea table reloads its set and meals separately")
	var base:=world.state.duplicate(true)
	expect(valid(base),"The live state validates")
	var tampered:=base.duplicate(true)
	tampered.objects[World.key(TEA)][Industry.TEA_SET_FIELD]=false
	expect(not valid(tampered),"A false flag is not a legal save")
	tampered=base.duplicate(true)
	tampered.objects[World.key(TEA)][Industry.TEA_SET_FIELD]="yes"
	expect(not valid(tampered),"A non-boolean flag is rejected")
	tampered=base.duplicate(true)
	tampered.objects[World.key(ROUND)][Industry.TEA_SET_FIELD]=true
	expect(not valid(tampered),"Another table cannot borrow the tea table's flag")
	tampered=base.duplicate(true)
	tampered.objects[World.key(TEA+Vector2i.RIGHT)][Industry.TEA_SET_FIELD]=true
	expect(not valid(tampered),"The far half of the tea table cannot carry the flag")
	tampered=base.duplicate(true)
	tampered.objects[World.key(TEA)].items[SET]=1
	expect(not valid(tampered),"The set cannot be smuggled into tea table meal stock")
	tampered=base.duplicate(true)
	tampered.objects[World.key(TABLE)].items[Industry.TABLE_VASE]=1
	expect(not valid(tampered),"A wood table still cannot save two displays")
	tampered=base.duplicate(true)
	tampered.objects[World.key(ROUND)].items[SET]=2
	expect(not valid(tampered),"The rounded table cannot save more than its two places")

	# --- rendering ---------------------------------------------------------------------
	var graphical:=DisplayServer.get_name()!="headless"
	if graphical:
		stand(Vector2(40.5,35.5))
		focus(TABLE)
		var with_set:=await frame("tea-set-wood-table")
		act(Industry.SHELL_TAKE,TABLE,SET)
		app.session._send_snapshot(1)
		var bare:=await frame("tea-set-wood-table-empty")
		expect(region_difference(with_set,bare,TABLE,Vector2(0.5,0.4),10)>0.01,"The set is visibly drawn on the wood table")
		act(Industry.SHELL_PUT,TABLE,SET)
		stand(Vector2(46.5,35.5))
		focus(ROUND)
		await frame("tea-set-rounded-table")
		stand(Vector2(51.5,35.5))
		focus(TEA,Vector2(1,0.5))
		var tea_with:=await frame("tea-set-tea-table")
		act(Industry.MUSHROOM_TAKE,TEA,SET)
		app.session._send_snapshot(1)
		var tea_bare:=await frame("tea-set-tea-table-empty")
		expect(region_difference(tea_with,tea_bare,TEA,Vector2(1.2,0.8),10)>0.01,"The set is visibly drawn on the tea table")
		act(Industry.MUSHROOM_SERVE,TEA,SET)
		focus(TEA,Vector2(1,0.5))
		app.toast_time=0
		expect(owner_emote(POUR)==[Industry.TEA_SET_EMOTES[POUR]],"The real request starts the photographed pouring effect")
		app.session._send_snapshot(1)
		await frame("tea-set-pour-effect")
	else:
		app._show_emote(Session._public_actor(owner),app.view.region_id(),Industry.TEA_SET_EMOTES[POUR])
		expect(app.view.active_emote(Session._public_actor(owner)).get("fx")=="pour","Headless: the pour effect is attached to the emote")
		app._show_emote(Session._public_actor(owner),app.view.region_id(),Session.EMOTES.hello)
		expect(not app.view.active_emote(Session._public_actor(owner)).has("fx"),"Headless: a generic emote carries no pour effect")

	# --- move with the set, then clean removal -----------------------------------------
	stand(Vector2(40.5,35.5))
	var moved_to:=Vector2i(40,36)
	world.state.removed[World.key(moved_to)]=true
	var table_state:Dictionary=books().bags
	expect(act("remove",TABLE).ok==false,"The loaded wood table still refuses demolition")
	expect(act("move_object",TABLE,World.key(moved_to)).ok and items(moved_to)=={SET:1} and not world.state.objects.has(World.key(TABLE)),"Moving the wood table carries the set")
	expect(books().bags==table_state,"Moving costs and refunds nothing")
	var home_total:=bag(SET)
	expect(act(Industry.SHELL_TAKE,moved_to,SET).ok and bag(SET)==home_total+1,"The set can be taken from the moved table")
	expect(act("remove",moved_to).ok and bag("wood")>=0,"The empty wood table then comes down")
	stand(Vector2(46.5,35.5))
	for item:String in [SET,Industry.TABLE_VASE]:expect(act(Industry.SHELL_TAKE,ROUND,item).ok,"Take "+item+" from the rounded table")
	expect(act("remove",ROUND).ok,"The empty rounded table comes down")
	stand(Vector2(51.5,35.5))
	for dish:String in ["mist_tea_brew","mist_tea_brew","mist_tea_brew"]:expect(act(Industry.MUSHROOM_TAKE,TEA,dish).ok,"Take back "+dish)
	if obj(TEA).get(Industry.TEA_SET_FIELD,false):expect(act(Industry.MUSHROOM_TAKE,TEA,SET).ok,"Take the set from the tea table")
	expect(not obj(TEA).has(Industry.TEA_SET_FIELD) and act("remove",TEA).ok,"The tea table comes down once emptied")
	expect(bag(SET)==3 and bag("clay")==1 and bag("mist_tea")==1 and bag(Industry.TABLE_VASE)==1,"All three sets and the vase are back in the bag; materials were only spent on crafting")
	expect(int(person.coins)==worth,"Coins never moved through any step")
	expect(valid(world.state.duplicate(true)),"The final state validates")
	await finish()
