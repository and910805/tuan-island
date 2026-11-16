extends SceneTree
## Native UI regression test for the loom (織布機) inside ProcessingQueueUI:
## cotton / wool cloth recipes, manual queue + cancel + claim, compact layout at
## 1024x640 vs 1280x800, and owner-only restrictions.
##
## Instantiates the ACTUAL main.tscn with village_art_preview=true, a REAL
## Session host and a REAL isolated World. The island is entered through
## Session._attach_registered(1) -> Main._entered; every snapshot reaches the
## controller through Session.changed and every UI action travels
## Session.perform -> World.act.
##
## FIXTURE, NOT HUMAN PLAY (label LABEL). The script programmatically:
##  * seeds build materials, cotton and wool directly into backpacks;
##  * builds both looms through the real World.act("build") path (owner LOOM for
##    the tester, FOREIGN for a neighbour who queues one cotton job through
##    World.act), then saves and RE-LOADS the world from disk;
##  * teleports the player next to each loom;
##  * stops automatic ticks (Session physics + Main _process disabled) and
##    ADVANCES WORLD TIME with World.step (each advance printed as FIXTURE);
##  * presses UI buttons by emitting `pressed` and calls Main._refresh_hud()
##    after frames because Main's polling loop is disabled;
##  * paces UI actions under Session's real per-second limit.
## The world lives in one per-run user:// directory removed at the end. The
## profile token is a throwaway value.
##
## Run: godot --headless --path game --script res://tests/test_loom_ui.gd -- --village-art-preview

const World=preload("res://scripts/world.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const Village=preload("res://scripts/village.gd")
const LABEL:="loom-ui/fixture-20261114"
const EXTENTS:=[Vector2i(1024,640),Vector2i(1280,800)]
const T:="tok-loom-ui-SECRET-tester"
const B:="tok-loom-ui-SECRET-neighbour"
const NODE_CAP:=6000
const ROOT_NAME:="ProcessingQueueUI"
const ENQUEUE:="ProcessingEnqueue"
const CLAIM:="ProcessingClaim"
const CAPACITY:="ProcessingCapacity"
const STATUS:="ProcessingStatus"
const CANCEL_PREFIX:="ProcessingCancel_"
const RECIPE_PREFIX:="ProcessingRecipe_"
const COTTON:="cotton_cloth"
const WOOL:="wool_cloth"
const AUTO_ONLY:=["ProcessingManualTab","ProcessingAutoTab","ProcessingFeed","ProcessingUnload","ProcessingToggleAuto","ProcessingCollect"]
const BUILD_KIT:={"plank":8,"fiber":4,"copper_joint":1}

var checks:=0
var failures:=0
var app
var w
var dir:=""
var LOOM:=Vector2i(-1,-1)
var FOREIGN:=Vector2i(-1,-1)
var rate_marks:=[]

func _initialize() -> void:call_deferred("run")

func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

# ------------------------------------------------------------- tree helpers --

func descendants(node:Node,cap:int=NODE_CAP) -> Array[Node]:
	var result:Array[Node]=[]
	if node==null:return result
	var queue:Array[Node]=[node]
	var head:=0
	while head<queue.size() and result.size()<cap:
		var current:Node=queue[head]
		head+=1
		for child in current.get_children():
			result.append(child)
			queue.append(child)
			if result.size()>=cap:break
	return result

func text_of(node:Node) -> String:
	var parts:=PackedStringArray()
	if node==null:return ""
	for d in [node]+descendants(node,1500):
		if (d is Label or d is Button or d is RichTextLabel) and d.is_visible_in_tree() and not str(d.text).is_empty():parts.append(str(d.text))
	return "\n".join(parts)

func has_number(text:String,value:int) -> bool:
	var regex:=RegEx.new()
	regex.compile("(?<!\\d)%d(?!\\d)"%value)
	return regex.search(text)!=null

func ui() -> Control:
	if app==null or not is_instance_valid(app.modal):return null
	var modal:Control=app.modal
	if str(modal.name)==ROOT_NAME:return modal if modal.is_visible_in_tree() else null
	var hit:=modal.find_child(ROOT_NAME,true,false) as Control
	return hit if hit!=null and hit.is_visible_in_tree() else null

func ctl(node_name:String) -> Control:
	var r:=ui()
	if r==null:return null
	return r.find_child(node_name,true,false) as Control

func shown(c:Control) -> bool:
	return c!=null and is_instance_valid(c) and c.is_visible_in_tree()

func usable(node_name:String) -> bool:
	var b:=ctl(node_name) as BaseButton
	return shown(b) and not b.disabled

func unusable(node_name:String) -> bool:
	var b:=ctl(node_name) as BaseButton
	return b==null or not b.is_visible_in_tree() or b.disabled

func usable_cancels() -> Dictionary:
	var out:={}
	for d in descendants(ui()):
		if d is BaseButton and str(d.name).begins_with(CANCEL_PREFIX) and d.is_visible_in_tree() and not d.disabled:
			out[str(d.name).trim_prefix(CANCEL_PREFIX)]=d
	return out

func in_view(c:Control) -> bool:
	return root.get_visible_rect().grow(0.5).encloses(c.get_global_rect())

func unclipped(c:Control) -> bool:
	var ancestor:=c.get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents:
			if not ancestor.get_global_rect().grow(0.5).encloses(c.get_global_rect()):return false
		ancestor=ancestor.get_parent()
	return true

func name_of(item:String) -> String:
	return str(World.NAMES.get(item,item))

# ------------------------------------------------------------ world helpers --

func dev(c:Vector2i) -> Dictionary:
	var o=w.state.objects.get(World.key(c),{})
	return o if o is Dictionary else {}

func q(c:Vector2i) -> Dictionary:
	var p=dev(c).get("processing")
	return p if p is Dictionary else {}

func ids_of(list) -> Array:
	var out:=[]
	if list is Array:
		for entry in list:out.append(str(entry.get("id","")))
	return out

func all_ids(p:Dictionary) -> Array:
	if p.is_empty():return []
	var out:=[]
	if not (p.get("active",{}) as Dictionary).is_empty():out.append(str(p.active.id))
	return out+ids_of(p.get("waiting",[]))+ids_of(p.get("ready",[]))

func kinds_of(p:Dictionary) -> Array:
	if p.is_empty():return []
	var out:=[]
	if not (p.get("active",{}) as Dictionary).is_empty():out.append(str(p.active.kind))
	for lane in ["waiting","ready"]:
		for entry in p.get(lane,[]):out.append(str(entry.get("kind","")))
	return out

func held(item:String,token:String=T) -> int:
	return int(w.state.players[token].inventory.get(item,0))

func progress() -> String:
	var person:Dictionary=w.state.players[T]
	return var_to_str([person.get("cooked",0),person.get("collection",{}),person.get("harvests",0)])

func near(c:Vector2i) -> Vector2:
	return Vector2(c)+Vector2(0.5,1.6)

func site_clear(w0,a:Vector2i,size:Vector2i) -> bool:
	for y in range(a.y,a.y+size.y):
		for x in range(a.x,a.x+size.x):
			var c:=Vector2i(x,y)
			var k:=World.key(c)
			if not w0.is_land(c) or w0.water(c) or w0.protected(c):return false
			for field in ["objects","ground","roofs","crops","forest"]:
				if w0.state[field].has(k):return false
			var had:bool=w0.state.removed.has(k)
			w0.state.removed[k]=true
			var blocked:bool=w0.blocked(c)
			if not had:w0.state.removed.erase(k)
			if blocked:return false
	return true

func find_site(w0,avoid:Array) -> Vector2i:
	for oy in range(3,57):
		for ox in range(3,77):
			var far:=true
			for a in avoid:
				if Vector2(ox,oy).distance_to(Vector2(a))<7.0:
					far=false
					break
			if not far:continue
			if site_clear(w0,Vector2i(ox-2,oy-2),Vector2i(5,5)):
				for y in range(oy-2,oy+3):
					for x in range(ox-2,ox+3):
						var c:=Vector2i(x,y)
						if w0.resource(c)!="":w0.state.removed[World.key(c)]=true
				return Vector2i(ox,oy)
	expect(false,"fixture found a legal empty loom site")
	return Vector2i(-1,-1)

func fixture_act(w0,token:String,action:String,c:Vector2i,extra:String) -> Dictionary:
	var person:Dictionary=w0.state.players[token]
	person.x=near(c).x
	person.y=near(c).y
	return w0.act(token,"fixture-%s-%s-%s"%[action,World.key(c),extra],action,c,extra)

func setup_world() -> bool:
	var path:=dir+"/world.json"
	var w0=World.new()
	w0.save_path=path
	w0.add_player(T,"島民")
	w0.add_player(B,"鄰居")
	w0.state.players[T].inventory.merge(BUILD_KIT.duplicate(),true)
	w0.state.players[T].inventory.merge({"cotton":6,"wool":4},true)
	w0.state.players[B].inventory.merge(BUILD_KIT.duplicate(),true)
	w0.state.players[B].inventory.merge({"cotton":3},true)
	var avoid:Array=[Vector2i(World.SPAWN),Vector2i(40,29),Vector2i(43,29),Vector2i(45,34),Vector2i(54,25),World.COPPER_CELL]
	for resident in Village.ids_for_region("home"):avoid.append(Village.NPCS[resident].cell)
	for candidate in World.SHIPPING.CANDIDATES:avoid.append(candidate)
	for candidate in World.COMMUNITY.CANDIDATES:avoid.append(candidate)
	LOOM=find_site(w0,avoid)
	if LOOM.x<0:return false
	avoid.append(LOOM)
	FOREIGN=find_site(w0,avoid)
	if FOREIGN.x<0:return false
	var r:Dictionary=fixture_act(w0,T,"build",LOOM,"loom")
	expect(r.get("ok")==true,"fixture: tester builds a loom through World.act: %s"%r.get("message",""))
	r=fixture_act(w0,B,"build",FOREIGN,"loom")
	expect(r.get("ok")==true,"fixture: neighbour builds a loom through World.act: %s"%r.get("message",""))
	for entry in [[LOOM,T],[FOREIGN,B]]:
		var obj=w0.state.objects.get(World.key(entry[0]),{})
		expect(obj is Dictionary and obj.get("type")=="loom" and obj.get("owner")==entry[1],"fixture: loom at %s owned by its builder"%entry[0])
		expect(obj is Dictionary and not obj.has("job") and not bool(obj.get("auto_enabled",false)),"fixture: built loom has no legacy job / automatic mode")
	for item in BUILD_KIT:expect(int(w0.state.players[T].inventory.get(item,0))==0,"fixture: building spent the tester's %s"%item)
	r=fixture_act(w0,B,"queue_processing",FOREIGN,COTTON)
	expect(r.get("ok")==true,"fixture: neighbour queues cotton cloth on own loom: %s"%r.get("message",""))
	var tester:Dictionary=w0.state.players[T]
	tester.x=near(LOOM).x
	tester.y=near(LOOM).y
	expect(w0.save(),"fixture world saved")
	w=World.new()
	var loaded:bool=w.load_world(path)
	expect(loaded,"fixture world re-loaded from disk (real SaveSchema)")
	if not loaded:return false
	w.add_player(T,"島民")
	expect(dev(LOOM).get("type")=="loom" and all_ids(q(LOOM)).is_empty(),"own loom loaded empty")
	expect(kinds_of(q(FOREIGN))==[COTTON],"neighbour's cotton job loaded from save")
	return true

# ---------------------------------------------------------------- fixture --

func settle(frames:int=4) -> void:
	for i in frames:await process_frame
	if is_instance_valid(app) and app.playing:app._refresh_hud()

func sync() -> void:
	app.session._send_snapshot(1)
	await settle()

func pose(at:Vector2) -> void:
	var person:Dictionary=w.state.players[T]
	person.x=at.x
	person.y=at.y
	await sync()

func set_item(item:String,value:int) -> void:
	print("FIXTURE %s: backpack %s set programmatically to %d"%[LABEL,item,value])
	w.state.players[T].inventory[item]=value
	await sync()

func advance(seconds:float,why:String) -> void:
	print("FIXTURE %s: world time advanced programmatically by %.3fs (%s); automatic ticks disabled"%[LABEL,seconds,why])
	expect(w.step(seconds,true),"fixture time advance committed (%s)"%why)
	await sync()

func pace() -> void:
	var now:=Time.get_ticks_msec()
	while not rate_marks.is_empty() and now-int(rate_marks[0])>1100:rate_marks.pop_front()
	if rate_marks.size()>=8:
		var wait_ms:=1150-(now-int(rate_marks[0]))
		if wait_ms>0:await create_timer(wait_ms/1000.0).timeout
		now=Time.get_ticks_msec()
		while not rate_marks.is_empty() and now-int(rate_marks[0])>1100:rate_marks.pop_front()
	rate_marks.append(Time.get_ticks_msec())

func reachable(c:Control,label:String) -> bool:
	if c==null or not is_instance_valid(c):
		expect(false,"%s: control exists to be reached"%label)
		return false
	var scrolls:=[]
	var p:=c.get_parent()
	while p!=null and p!=app.hud:
		if p is ScrollContainer:scrolls.append(p)
		p=p.get_parent()
	for s in scrolls:(s as ScrollContainer).ensure_control_visible(c)
	if not scrolls.is_empty():
		for i in 2:await process_frame
		for s in scrolls:
			if is_instance_valid(s) and is_instance_valid(c):(s as ScrollContainer).ensure_control_visible(c)
		await process_frame
	var ok:bool=is_instance_valid(c) and c.is_visible_in_tree() and in_view(c) and unclipped(c)
	expect(ok,"%s: reachable inside the window without clipping"%label)
	return ok

## Presses a real UI button through its signal (programmatic, not manual play).
func press(node_name:String,label:String,performs:bool=true) -> bool:
	var b:=ctl(node_name) as BaseButton
	expect(shown(b),"%s: control '%s' present and visible"%[label,node_name])
	if not shown(b):return false
	await reachable(b,"%s: %s"%[label,node_name])
	b=ctl(node_name) as BaseButton
	if not shown(b):return false
	expect(not b.disabled,"%s: control '%s' enabled"%[label,node_name])
	if b.disabled:return false
	if performs:await pace()
	b.pressed.emit()
	await settle()
	return true

## Recipe choice is local: it must never send a world action.
func choose(recipe:String,label:String) -> bool:
	var counter0:=int(app.session.counter)
	var state0:=var_to_str(w.state)
	var ok:bool=await press(RECIPE_PREFIX+recipe,label,false)
	expect(int(app.session.counter)==counter0 and var_to_str(w.state)==state0,"%s: choosing a recipe performs no world action"%label)
	var b:=ctl(RECIPE_PREFIX+recipe) as BaseButton
	expect(b!=null and b.button_pressed,"%s: %s button shows as selected"%[label,recipe])
	expect(text_of(ctl("ProcessingRecipeCard")).contains(name_of(recipe)),"%s: recipe card names %s"%[label,name_of(recipe)])
	return ok

func open_at(c:Vector2i,label:String) -> bool:
	if is_instance_valid(app.modal):
		app._close_modal()
		await settle()
	await pose(near(c))
	app.industry_ui.device(app,c)
	await settle(6)
	var ok:=ui()!=null
	expect(ok,"%s: app.industry_ui.device(%s) opens a visible %s"%[label,c,ROOT_NAME])
	return ok

func capacity_text() -> String:
	return text_of(ctl(CAPACITY))

# ------------------------------------------------------------------ layout --

## Bounded layout at the current window size: modal fits, compact sizing tracks
## the window height, controls are visible / unclipped / non-overlapping.
func check_layout(label:String,extent:Vector2i) -> void:
	var r:=ui()
	expect(r!=null,"%s: %s visible"%[label,ROOT_NAME])
	if r==null:return
	var window:=root.get_visible_rect().grow(0.5)
	expect(window.encloses(r.get_global_rect()),"%s: %s inside the window"%[label,ROOT_NAME])
	var want:=Vector2(minf(980.0,extent.x-32.0),minf(620.0,extent.y-32.0)).floor()
	expect(r.size.is_equal_approx(want),"%s: panel sized %s (got %s)"%[label,want,r.size])
	var compact:=extent.y<720
	var icon:=ctl("ProcessingStationIcon")
	var hero:=ctl("ProcessingSelectedIcon")
	var slot:=ctl("ProcessingSlot_0")
	var big:=Vector2(48,48) if compact else Vector2(64,64)
	var cell:=Vector2(36,36) if compact else Vector2(40,40)
	expect(icon!=null and icon.custom_minimum_size==big,"%s: station icon %s in %s mode"%[label,big,"compact" if compact else "roomy"])
	expect(hero!=null and hero.custom_minimum_size==big,"%s: selected recipe icon %s"%[label,big])
	expect(slot!=null and slot.custom_minimum_size==cell,"%s: queue slot %s"%[label,cell])
	for node_name in AUTO_ONLY:
		expect(not shown(ctl(node_name)),"%s: loom shows no automatic-buffer control %s"%[label,node_name])
	var rects:=[]
	for node_name in [ENQUEUE,CLAIM,CAPACITY,"ProcessingSlots",RECIPE_PREFIX+COTTON,RECIPE_PREFIX+WOOL,"ProcessingStationIcon",STATUS]:
		var c:=ctl(node_name)
		expect(shown(c),"%s: %s visible"%[label,node_name])
		if not shown(c):continue
		await reachable(c,"%s: %s"%[label,node_name])
		var g:=c.get_global_rect()
		if c is BaseButton:expect(g.size.x>=16 and g.size.y>=16,"%s: %s has a usable size %s"%[label,node_name,g.size])
		if node_name==STATUS:continue
		for other in rects:
			expect(not g.grow(-1.0).intersects(other[1].grow(-1.0)),"%s: %s does not overlap %s"%[label,node_name,other[0]])
		rects.append([node_name,g])
	for i in Queue.CAPACITY:
		var s:=ctl("ProcessingSlot_%d"%i)
		expect(shown(s) and in_view(s) and unclipped(s),"%s: queue slot %d fully shown"%[label,i])
	var cancels:=usable_cancels()
	for id in cancels:await reachable(cancels[id],"%s: cancel %s"%[label,id.left(8)])

func at_each_extent(state:String,check:Callable) -> void:
	for extent in EXTENTS:
		root.size=extent
		await settle(4)
		if is_instance_valid(app.modal):
			for node in descendants(app.modal):
				if node is ScrollContainer:node.scroll_vertical=0
			await settle(2)
		var label:="%s %dx%d"%[state,extent.x,extent.y]
		await check_layout(label,extent)
		await check.call(label)
	root.size=EXTENTS[0]
	await settle(4)

# -------------------------------------------------------------------- run --

func run() -> void:
	print("LOOM_UI fixture=%s"%LABEL)
	dir="user://test-loom-ui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		await finish()
		return
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=EXTENTS[0]
	var session=app.session
	session.set_physics_process(false)
	session.profile={"token":"loom-ui-isolated-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]}
	if not setup_world():
		expect(false,"fixture world could not be prepared")
		await finish()
		return
	session.world=w
	session._attach_registered(1,T)
	await settle(6)
	expect(app.playing and app.hud.visible,"entered through Session.connected_world -> Main._entered")
	expect(session.own_id==T.sha256_text().left(16),"Main session holds the public own_id")
	if await flow_open():
		await flow_recipes()
		await flow_missing()
		await flow_queue_cancel()
		await flow_ready_claim()
		await flow_nonowner()
		await flow_full_layout()
		await flow_reload()
	await finish()

# ------------------------------------------------------------------ flows --

func flow_open() -> bool:
	await pose(near(LOOM))
	app._interact()
	await settle(6)
	expect(ui()!=null,"interact next to the loom opens %s"%ROOT_NAME)
	if ui()==null:
		if not await open_at(LOOM,"open fallback"):return false
	for node_name in [ENQUEUE,CLAIM,CAPACITY,STATUS,"ProcessingMaterials",RECIPE_PREFIX+COTTON,RECIPE_PREFIX+WOOL]:
		expect(ctl(node_name)!=null,"MISSING CONTROL: %s"%node_name)
	var recipe_buttons:=descendants(ctl("ProcessingRecipes")).filter(func(n):return n is BaseButton and str(n.name).begins_with(RECIPE_PREFIX))
	expect(recipe_buttons.size()==2,"loom offers exactly two recipes (got %d)"%recipe_buttons.size())
	expect(World.processing_recipes("loom").keys().size()==2 and World.processing_recipes("loom").has(COTTON) and World.processing_recipes("loom").has(WOOL),"loom catalogue is cotton + wool cloth")
	var header:=text_of(ctl("ProcessingHeader"))
	expect(header.contains(str(World.BUILD.loom.name)),"header names the loom ('%s')"%header)
	expect(not header.contains("只有擁有者可以操作"),"own loom has no owner-only note")
	expect(has_number(capacity_text(),0) and has_number(capacity_text(),Queue.CAPACITY),"empty loom shows 0 of %d ('%s')"%[Queue.CAPACITY,capacity_text()])
	expect(usable(ENQUEUE),"enqueue enabled with enough cotton")
	expect(unusable(CLAIM),"nothing to claim on an empty loom")
	expect(usable_cancels().is_empty(),"no cancel controls on an empty loom")
	return true

func flow_recipes() -> void:
	var recipes:=World.processing_recipes("loom")
	for spec in [[COTTON,"cotton",3,6],[WOOL,"wool",2,4]]:
		var recipe:String=spec[0]
		var material:String=spec[1]
		var need:int=spec[2]
		var have:int=spec[3]
		expect(recipes[recipe].ingredients=={material:need} and int(recipes[recipe].yield)==1 and is_equal_approx(float(recipes[recipe].time),60.0),"%s: %d %s -> 1, 60 s"%[recipe,need,material])
		if not await choose(recipe,"choose "+recipe):continue
		var row:=ctl("ProcessingMaterial_"+material)
		expect(shown(row),"%s: material row for %s shown"%[recipe,material])
		var other:="wool" if material=="cotton" else "cotton"
		expect(not shown(ctl("ProcessingMaterial_"+other)),"%s: no stale %s row"%[recipe,other])
		var row_text:=text_of(row)
		expect(has_number(row_text,have) and has_number(row_text,need),"%s: row shows backpack %d / need %d ('%s')"%[recipe,have,need,row_text])
		expect(has_number(text_of(ctl("ProcessingRecipeCard")),60),"%s: card shows the 60 s batch"%recipe)
		expect(usable(ENQUEUE) and text_of(ctl(ENQUEUE)).contains(name_of(recipe)),"%s: enqueue names the selected cloth ('%s')"%[recipe,text_of(ctl(ENQUEUE))])
	await choose(COTTON,"back to cotton")

func flow_missing() -> void:
	var counter0:=int(app.session.counter)
	var objects0:=var_to_str(w.state.objects)
	await set_item("cotton",2)
	expect(unusable(ENQUEUE),"missing: enqueue disabled with 2 of 3 cotton")
	expect(text_of(ctl(ENQUEUE)).contains("不足"),"missing: enqueue explains the shortage ('%s')"%text_of(ctl(ENQUEUE)))
	await choose(WOOL,"missing: wool still possible")
	expect(usable(ENQUEUE),"missing: wool recipe stays available while cotton is short")
	await choose(COTTON,"missing: back to cotton")
	expect(unusable(ENQUEUE),"missing: cotton still blocked")
	expect(int(app.session.counter)==counter0 and var_to_str(w.state.objects)==objects0,"missing: no request sent, loom untouched")
	await set_item("cotton",6)
	expect(usable(ENQUEUE),"enqueue re-enabled after restocking cotton")

func flow_queue_cancel() -> void:
	var prog0:=progress()
	if not await press(ENQUEUE,"enqueue cotton"):return
	expect(held("cotton")==3,"UI cotton enqueue charged exactly 3 cotton")
	expect(kinds_of(q(LOOM))==[COTTON] and str(q(LOOM).active.get("owner",""))==T,"cotton job active, owned by the tester")
	expect(not text_of(ctl(STATUS)).strip_edges().is_empty(),"status line reports the enqueue")
	if not await choose(WOOL,"choose wool for queue"):return
	if not await press(ENQUEUE,"enqueue wool"):return
	expect(held("wool")==2,"UI wool enqueue charged exactly 2 wool")
	var p:=q(LOOM)
	var ids:=all_ids(p)
	expect(kinds_of(p)==[COTTON,WOOL] and ids_of(p.waiting).size()==1,"FIFO: cotton active, wool waiting")
	expect(has_number(capacity_text(),2),"capacity shows 2 ('%s')"%capacity_text())
	var cancels:=usable_cancels()
	for id in ids:expect(cancels.has(id),"own job %s cancellable by exact id"%id.left(8))
	var active_title:=text_of(ctl("ProcessingActive"))
	expect(active_title.contains(name_of(COTTON)),"active card shows cotton cloth ('%s')"%active_title)
	if ids.size()!=2:return
	if not await press(CANCEL_PREFIX+ids[1],"cancel waiting wool"):return
	expect(all_ids(q(LOOM))==[ids[0]],"UI cancel removed exactly the wool job")
	expect(held("wool")==4,"UI cancel refunded the stored 2 wool")
	expect(not usable_cancels().has(ids[1]),"cancelled job leaves the UI")
	if not await press(ENQUEUE,"re-enqueue wool"):return
	expect(kinds_of(q(LOOM))==[COTTON,WOOL] and held("wool")==2,"wool re-queued behind cotton")
	expect(progress()==prog0,"queueing never touches cooked / collection / harvest progress")

func flow_ready_claim() -> void:
	var p:=q(LOOM)
	if (p.get("active",{}) as Dictionary).is_empty():
		expect(false,"ready precondition: an active cotton job")
		return
	var first_id:=str(p.active.id)
	var dt:=float(p.active.finish)-float(w.state.time)+0.25
	# The controller must react to Session.changed alone (no Main refresh here).
	print("FIXTURE %s: world time advanced programmatically by %.3fs (cotton done; Session.changed only)"%[LABEL,dt])
	expect(w.step(dt,true),"fixture time advance committed (cotton)")
	app.session._send_snapshot(1)
	for i in 4:await process_frame
	expect(usable(CLAIM),"claim enabled from Session.changed without Main refresh")
	await settle()
	expect(ids_of(q(LOOM).ready)==[first_id] and kinds_of(q(LOOM))==[WOOL,COTTON],"cotton ready while wool now active")
	expect(text_of(ctl(CLAIM)).contains(name_of(COTTON)),"claim names the oldest ready cloth ('%s')"%text_of(ctl(CLAIM)))
	expect(not usable_cancels().has(first_id),"ready cotton job is not cancellable")
	await advance(61.0,"wool done")
	expect(ready_n(q(LOOM))==2,"both cloth jobs ready")
	expect(has_number(text_of(ctl("ProcessingShelf")),1),"shelf shows ×1 yields")
	var prog0:=progress()
	if not await press(CLAIM,"claim cotton"):return
	expect(held(COTTON)==1 and held(WOOL)==0,"first claim gives exactly one cotton cloth (FIFO)")
	expect(text_of(ctl(CLAIM)).contains(name_of(WOOL)),"claim now names wool cloth")
	if not await press(CLAIM,"claim wool"):return
	expect(held(WOOL)==1 and held(COTTON)==1,"second claim gives exactly one wool cloth")
	expect(all_ids(q(LOOM)).is_empty(),"loom queue emptied by claims")
	expect(unusable(CLAIM),"claim disabled when nothing is ready")
	expect(has_number(capacity_text(),0),"capacity back to 0 ('%s')"%capacity_text())
	expect(progress()==prog0,"claims never touch cooked / collection / harvest progress")
	await pace()
	app.session.perform("claim_processing",LOOM,"")
	await settle()
	expect(held(COTTON)==1 and held(WOOL)==1,"forced extra claim yields nothing more")

func ready_n(p:Dictionary) -> int:
	return 0 if p.is_empty() else (p.get("ready",[]) as Array).size()

func flow_nonowner() -> void:
	if not await open_at(FOREIGN,"nonowner"):return
	var header:=text_of(ctl("ProcessingHeader"))
	expect(header.contains("只有擁有者可以操作"),"nonowner: header states owner-only ('%s')"%header)
	expect(unusable(ENQUEUE) and text_of(ctl(ENQUEUE)).contains("擁有者"),"nonowner: enqueue disabled and explains why")
	expect(unusable(CLAIM) and text_of(ctl(CLAIM)).contains("擁有者"),"nonowner: claim disabled and explains why")
	expect(usable_cancels().is_empty(),"nonowner: no usable cancel for the neighbour's job")
	expect(has_number(capacity_text(),1),"nonowner: neighbour's queue still visible ('%s')"%capacity_text())
	expect(ready_n(q(FOREIGN))==1,"nonowner: neighbour's cotton finished during earlier time advances")
	await choose(WOOL,"nonowner: browsing recipes still allowed")
	expect(unusable(ENQUEUE),"nonowner: enqueue stays disabled after choosing wool")
	await at_each_extent("nonowner",func(_l):pass)
	# Forced requests that bypass the disabled buttons are refused by World.
	var state0:=var_to_str(w.state.objects)
	var bag0:=var_to_str(w.state.players[T].inventory)
	for spec in [["queue_processing",WOOL],["claim_processing",""],["cancel_processing_job",str(ids_of(q(FOREIGN).ready).front() if ready_n(q(FOREIGN))>0 else "")]]:
		await pace()
		app.session.perform(spec[0],FOREIGN,spec[1])
		await settle()
		expect(var_to_str(w.state.objects)==state0 and var_to_str(w.state.players[T].inventory)==bag0,"nonowner: forced %s refused, nothing changed"%spec[0])
	expect(ready_n(q(FOREIGN))==1 and held(COTTON,B)==0,"nonowner: neighbour's cloth stays on their loom")

func flow_full_layout() -> void:
	if not await open_at(LOOM,"full"):return
	await set_item("wool",2*Queue.CAPACITY)
	if not await choose(WOOL,"full: choose wool"):return
	for i in Queue.CAPACITY:
		if not await press(ENQUEUE,"fill %d"%i):break
	var p:=q(LOOM)
	expect(all_ids(p).size()==Queue.CAPACITY and held("wool")==0,"queue full at %d, %d wool spent"%[Queue.CAPACITY,2*Queue.CAPACITY])
	expect(unusable(ENQUEUE) and text_of(ctl(ENQUEUE)).contains("已滿"),"full: enqueue disabled and says the queue is full")
	var own:=ids_of(p.waiting)
	var full_check:=func(l):
		expect(has_number(capacity_text(),Queue.CAPACITY),"%s: capacity shows %d ('%s')"%[l,Queue.CAPACITY,capacity_text()])
		var cancels:=usable_cancels()
		for id in own:expect(cancels.has(id),"%s: waiting job %s cancellable"%[l,id.left(8)])
	await at_each_extent("full",full_check)
	await set_item("wool",2)
	var objects0:=var_to_str(w.state.objects)
	await pace()
	app.session.perform("queue_processing",LOOM,WOOL)
	await settle()
	expect(held("wool")==2 and var_to_str(w.state.objects)==objects0,"forced eleventh request refused without charge")

func flow_reload() -> void:
	var expected:=all_ids(q(LOOM))
	var again=World.new()
	var loaded:bool=again.load_world(w.save_path)
	expect(loaded,"reload: saved loom queue passes SaveSchema")
	if not loaded:return
	var obj:Dictionary=again.state.objects.get(World.key(LOOM),{})
	var p=obj.get("processing")
	expect(obj.get("type")=="loom" and not obj.has("job") and not bool(obj.get("auto_enabled",false)),"reload: loom stays a manual-only station")
	expect(p is Dictionary and all_ids(p)==expected,"reload: UI-made queue order survives the save")

func finish() -> void:
	if is_instance_valid(app):
		app._close_modal()
		app.queue_free()
	for i in 3:await process_frame
	remove_tree(dir)
	if not dir.is_empty():expect(not DirAccess.dir_exists_absolute(dir),"isolated test directory removed")
	print("LOOM_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func remove_tree(path:String) -> void:
	if not path.begins_with("user://test-loom-ui-"):return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):remove_tree(path+"/"+sub)
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+f)
	DirAccess.remove_absolute(path)
