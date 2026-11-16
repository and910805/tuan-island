extends SceneTree
## Native UI test for T036 explicit material sourcing
## (docs/material-source-contract.json "ui"/"verification"): the shared
## MaterialSourcePicker (res://scripts/material_source_ui.gd) inside the bench
## workbench, the stove cooking queue and the sawmill (plus a light charcoal
## kiln check: same component, same processing host).
##
## Instantiates the ACTUAL main.tscn with village_art_preview=true, a REAL
## Session host and a REAL isolated World. The island is entered through
## Session._attach_registered(1) -> connected_world -> Main._entered; every
## snapshot reaches Main through Session.changed; every UI action travels
## Session.perform -> World.act (prepare_material_box, craft, queue_cook,
## queue_processing, cancels). Acks are recorded from Session.action_completed.
##
## FIXTURE, NOT HUMAN PLAY (label LABEL). The script programmatically:
##  * builds four isolated sites, each a station with three cardinal neighbours:
##    EAST = shared chest, NORTH = the tester's own private chest, WEST = the
##    neighbour's private chest (written directly into the object layer, same
##    shape as a real build), seeds chest contents directly, lets the neighbour
##    prepare its own private chest through the real World.act, then saves and
##    RE-LOADS the world from disk;
##  * seeds the tester's backpack directly (low stock so the box is required)
##    and, for stale cases, REPLACES / MOVES a chest by writing the object layer
##    directly (each write printed with the FIXTURE label);
##  * once writes a backpack count WITHOUT sending a snapshot, to make the
##    displayed quote stale on purpose (server must requote, no auto retry);
##  * teleports the player next to each station and opens the station UI via
##    the same Main/host entry points _interact uses;
##  * selects MaterialSourceSelect rows by calling OptionButton.select(i) and
##    emitting item_selected(i), presses buttons by emitting `pressed`, pushes
##    synthetic key events through the root viewport;
##  * disables automatic ticks (Session physics + Main _process) and calls
##    Main._refresh_hud() after frames; NO world time is advanced;
##  * paces UI actions under Session's real 12-per-second limit.
## The world lives in one per-run user:// directory removed at the end (copied
## to the QA directory first when something failed). Main's profile token is a
## throwaway value.
##
## UI contract (missing names / API are counted failures, never skipped):
##  MaterialSourcePicker (under app.modal) built by material_source_ui.gd;
##  MaterialSourceSelect (OptionButton, index 0 "只用背包"); option_cells();
##  get_selected_cell(); MaterialSourceBreakdown with MaterialSourceRow_<item>
##  labels "<名> 需N｜背包扣X（持有H）｜箱扣Y（箱內Z）[｜缺S]";
##  MaterialSourceStatus; MaterialSourceRefund (queue stations);
##  MaterialSourceRetry. Host submit buttons: CraftRecipe, CookingEnqueue,
##  ProcessingEnqueue; cancels CookingCancel_<id>, ProcessingCancel_<id>.
##
## Optional native capture: --qa-preview --qa-output=<ABSOLUTE DIR> saves
## material-<state>-<W>x<H>.png at 1024x640 and 1280x800 for bench-source,
## stove-source, mill-source and missing-source (needs a rendering run).

const World=preload("res://scripts/world.gd")
const Supply=preload("res://scripts/material_supply.gd")
const Village=preload("res://scripts/village.gd")
const LABEL:="material-source-ui/fixture-20261114"
const UI_FILE:="res://scripts/material_source_ui.gd"
const EXTENTS:=[Vector2i(1024,640),Vector2i(1280,800)]
const REQUIRED_STATES:=["bench-source","stove-source","mill-source","missing-source"]
const T:="tok-msrc-ui-SECRET-tester"
const B:="tok-msrc-ui-SECRET-neighbour"
const NODE_CAP:=6000
const PICKER:="MaterialSourcePicker"
const SELECT:="MaterialSourceSelect"
const BREAKDOWN:="MaterialSourceBreakdown"
const STATUS:="MaterialSourceStatus"
const REFUND:="MaterialSourceRefund"
const RETRY:="MaterialSourceRetry"
const SCROLL:="MaterialSourceScroll"
const ROW_PREFIX:="MaterialSourceRow_"
const BAG_TEXT:="只用背包"
const PREPARE:="prepare_material_box"
const EAST:=Vector2i(1,0)   # shared chest
const NORTH:=Vector2i(0,-1) # tester's own private chest
const WEST:=Vector2i(-1,0)  # neighbour's private chest: never listed
const FAR:=Vector2i(2,2)    # non-adjacent cell inside the cleared site

var checks:=0
var failures:=0
var app
var w
var dir:=""
var qa:=false
var qa_dir:=""
var saved_shots:={}
var rate_marks:=[]
var acks:=[]
var stations:={}
var foreign_id:=""

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
	if node==null or not is_instance_valid(node):return ""
	for d in [node]+descendants(node,1500):
		if (d is Label or d is Button or d is RichTextLabel) and d.is_visible_in_tree() and not str(d.text).is_empty():parts.append(str(d.text))
	return "\n".join(parts)

func mctl(node_name:String) -> Control:
	if app==null or not is_instance_valid(app.modal):return null
	if str(app.modal.name)==node_name:return app.modal
	return app.modal.find_child(node_name,true,false) as Control

func shown(c:Control) -> bool:
	return c!=null and is_instance_valid(c) and c.is_visible_in_tree()

func usable(node_name:String) -> bool:
	var b:=mctl(node_name) as BaseButton
	return shown(b) and not b.disabled

func unusable(node_name:String) -> bool:
	var b:=mctl(node_name) as BaseButton
	return b==null or not b.is_visible_in_tree() or b.disabled

func picker() -> Control:
	var p:=mctl(PICKER)
	return p if shown(p) else null

func select_node() -> OptionButton:
	var p:=picker()
	if p==null:return null
	return p.find_child(SELECT,true,false) as OptionButton

func pctl(node_name:String) -> Control:
	var p:=picker()
	return null if p==null else p.find_child(node_name,true,false) as Control

func option_cells() -> Array:
	var p:=picker()
	if p==null or not p.has_method("option_cells"):return []
	return Array(p.option_cells())

func selected_cell() -> String:
	var p:=picker()
	if p==null or not p.has_method("get_selected_cell"):return "<missing>"
	return str(p.get_selected_cell())

func in_view(c:Control) -> bool:
	return root.get_visible_rect().grow(0.5).encloses(c.get_global_rect())

func unclipped(c:Control) -> bool:
	var ancestor:=c.get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents:
			if not ancestor.get_global_rect().grow(0.5).encloses(c.get_global_rect()):return false
		ancestor=ancestor.get_parent()
	return true

func hud_visible_children() -> Array:
	var out:=[]
	for c in app.hud.get_children():
		if c is Control and c.visible and c!=app.modal and c!=app.modal_shade and c!=app.toast:out.append(c)
	return out

## Parses MaterialSourceRow_<item>: need / bag share / held / box share / box stock / missing.
func row(item:String) -> Dictionary:
	var r:=pctl(ROW_PREFIX+item)
	if not shown(r):return {}
	var text:=text_of(r)
	var out:={"text":text}
	for pair in [["need","需"],["bag","背包扣"],["held","持有"],["box","箱扣"],["stock","箱內"],["missing","缺"]]:
		var m:=RegEx.create_from_string(str(pair[1])+"(\\d+)").search(text)
		out[pair[0]]=int(m.get_string(1)) if m else (0 if pair[0]=="missing" else -1)
	return out

# ------------------------------------------------------------ world helpers --

func obj(key:String) -> Dictionary:
	var o=w.state.objects.get(key,{})
	return o if o is Dictionary else {}

func box_id(key:String) -> String:
	return str(obj(key).get("box_id",""))

func snap_box_id(key:String) -> String:
	var o=app.session.snapshot.get("objects",{}).get(key,{})
	return str(o.get("box_id","")) if o is Dictionary else ""

func inv() -> Dictionary:
	return (w.state.players[T].inventory as Dictionary).duplicate(true)

func items(key:String) -> Dictionary:
	var it=obj(key).get("items",{})
	return (it as Dictionary).duplicate(true) if it is Dictionary else {}

func positive(d) -> Dictionary:
	var out:={}
	if d is Dictionary:
		for k in d:
			if int(d[k])>0:out[str(k)]=int(d[k])
	return out

func same(a,b) -> bool:
	var x:=positive(a)
	var y:=positive(b)
	if x.size()!=y.size():return false
	for k in x:
		if int(y.get(k,-1))!=int(x[k]):return false
	return true

func lowerhex32(id:String) -> bool:
	return RegEx.create_from_string("^[0-9a-f]{32}$").search(id)!=null

func key_at(st:Dictionary,offset:Vector2i) -> String:
	return World.key((st.cell as Vector2i)+offset)

func recipe_of(st:Dictionary) -> Dictionary:
	match str(st.type):
		"bench":return World.CRAFT[st.recipe]
		"stove":return World.RECIPES[st.recipe]
		_:return w.processing_recipes(str(st.type)).get(st.recipe,{})

func job_records(st:Dictionary) -> Array:
	var q=obj(World.key(st.cell)).get(str(st.get("field","")))
	var out:=[]
	if not q is Dictionary:return out
	if q.get("active") is Dictionary and not (q.active as Dictionary).is_empty():out.append(q.active)
	for field in ["waiting","ready"]:
		if q.get(field) is Array:out.append_array(q[field])
	return out

func job_ids(st:Dictionary) -> Array:
	var out:=[]
	for j in job_records(st):out.append(str(j.get("id","")))
	return out

func near(c:Vector2i) -> Vector2:
	return Vector2(c)+Vector2(0.5,1.6)

func all_box_ids() -> Dictionary:
	var out:={}
	for k in w.state.objects:
		var o=w.state.objects[k]
		if o is Dictionary and o.has("box_id"):out[k]=str(o.box_id)
	return out

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
	expect(false,"fixture found a legal empty station site")
	return Vector2i(-1,-1)

# ------------------------------------------------------------------ fixture --

## Explicit fixture data (not normal-play balances). Expected splits are
## written out literally and cross-checked against MaterialSupply.plan.
func describe() -> void:
	stations={
		"bench":{"type":"bench","owner":T,"recipe":"sprinkler_kit","actions":["craft"],"main":"CraftRecipe",
			"bag":{"wood":5,"stone":4,"copper_joint":0},"box":{"wood":20,"copper_joint":9,"stone":0},
			"private":{"wood":1},"from_bag":{"wood":5,"stone":4},"from_box":{"wood":3,"copper_joint":2}},
		"stove":{"type":"stove","owner":B,"recipe":"feed","actions":["queue_cook","cook"],"main":"CookingEnqueue",
			"cancel":"CookingCancel_","cancel_actions":["cancel_queued_cook","cancel_cook"],"field":"cooking",
			"bag":{"wheat":0,"fiber":1},"box":{"wheat":3,"fiber":8},"private":{"wheat":2,"fiber":4},
			"from_bag":{"fiber":1},"from_box":{"wheat":1,"fiber":1}},
		"mill":{"type":"sawmill","owner":T,"recipe":"plank","actions":["queue_processing","start_processing"],"main":"ProcessingEnqueue",
			"cancel":"ProcessingCancel_","cancel_actions":["cancel_processing_job","cancel_processing"],"field":"processing",
			"bag":{"wood":1},"box":{"wood":30},"private":{},"from_bag":{"wood":1},"from_box":{"wood":3}},
		"kiln":{"type":"charcoal_kiln","owner":T,"recipe":"charcoal","actions":["queue_processing","start_processing"],"main":"ProcessingEnqueue",
			"field":"processing","bag":{"wood":2},"box":{"wood":30},"private":{},"from_bag":{"wood":2},"from_box":{"wood":2}},
	}

func setup_world() -> bool:
	var path:=dir+"/world.json"
	var w0=World.new()
	w0.save_path=path
	w0.add_player(T,"島民")
	w0.add_player(B,"鄰居")
	var avoid:Array=[Vector2i(World.SPAWN),Vector2i(40,29),Vector2i(43,29),Vector2i(45,34),Vector2i(54,25),World.COPPER_CELL]
	for resident in Village.ids_for_region("home"):avoid.append(Village.NPCS[resident].cell)
	for candidate in World.SHIPPING.CANDIDATES:avoid.append(candidate)
	for candidate in World.COMMUNITY.CANDIDATES:avoid.append(candidate)
	for station_name in ["bench","stove","mill","kiln"]:
		var s:=find_site(w0,avoid)
		if s.x<0:return false
		avoid.append(s)
		var st:Dictionary=stations[station_name]
		st.cell=s
		var station:Dictionary={"type":st.type,"owner":st.owner,"items":{}}
		if st.type in ["sawmill","charcoal_kiln"]:station.merge({"input_wood":0,"auto_enabled":false})
		w0.state.objects[World.key(s)]=station
		w0.state.objects[World.key(s+EAST)]={"type":"chest","owner":T,"items":(st.box as Dictionary).duplicate()}
		w0.state.objects[World.key(s+NORTH)]={"type":"private_chest","owner":T,"items":(st.private as Dictionary).duplicate()}
		w0.state.objects[World.key(s+WEST)]={"type":"private_chest","owner":B,"items":{"wood":50,"wheat":50,"fiber":50}}
	print("FIXTURE %s: stations + chests written directly into the object layer; not human play"%LABEL)
	var stove:Dictionary=stations.stove
	var nb:Dictionary=w0.state.players[B]
	nb.x=near(stove.cell).x
	nb.y=near(stove.cell).y
	var r:Dictionary=w0.act(B,"fixture-prepare-foreign",PREPARE,stove.cell,World.key((stove.cell as Vector2i)+WEST))
	expect(r.get("ok")==true,"fixture: neighbour prepares own private chest via World.act: %s"%r.get("message",""))
	var tester:Dictionary=w0.state.players[T]
	tester.x=near(stations.bench.cell).x
	tester.y=near(stations.bench.cell).y
	expect(w0.save(),"fixture world saved")
	w=World.new()
	var loaded:bool=w.load_world(path)
	expect(loaded,"fixture world re-loaded from disk (real SaveSchema v22)")
	if not loaded:return false
	w.add_player(T,"島民")
	var ids:=all_box_ids()
	foreign_id=str(ids.get(key_at(stove,WEST),""))
	expect(ids.size()==1 and lowerhex32(foreign_id),"after reload only the neighbour's explicitly prepared chest has a box_id (no eager ids): %s"%[ids.keys()])
	return true

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

func seed_bag(stock:Dictionary,why:String) -> void:
	print("FIXTURE %s: backpack seeded directly %s (%s)"%[LABEL,stock,why])
	for k in stock:w.state.players[T].inventory[k]=int(stock[k])
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

func _on_ack(sequence:int,action:String,result:Dictionary) -> void:
	acks.append({"sequence":sequence,"action":action,"result":result.duplicate(true)})

func wait_for(actions:Array,since:int,key:String="") -> Dictionary:
	for frame in 60:
		for i in range(since,acks.size()):
			var a:Dictionary=acks[i]
			if str(a.action) in actions and (key.is_empty() or str(a.result.get("source_cell",""))==key):return a
		await process_frame
	return {}

func has_ack(actions:Array,since:int) -> bool:
	for i in range(since,acks.size()):
		if str(acks[i].action) in actions:return true
	return false

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
	var b:=mctl(node_name) as BaseButton
	expect(shown(b),"%s: control '%s' present and visible"%[label,node_name])
	if not shown(b):return false
	await reachable(b,"%s: %s"%[label,node_name])
	b=mctl(node_name) as BaseButton
	if not shown(b):return false
	expect(not b.disabled,"%s: control '%s' enabled"%[label,node_name])
	if b.disabled:return false
	if performs:await pace()
	b.pressed.emit()
	await settle()
	return true

func press_key(code:Key) -> void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code
		e.physical_keycode=code
		e.pressed=pressed
		root.push_input(e)
	await settle()

## Explicit source choice through the real OptionButton signal path.
## target "" = "只用背包", else a box cell key.
func choose(target:String,label:String) -> bool:
	var s:=select_node()
	expect(shown(s),"%s: %s is a visible OptionButton"%[label,SELECT])
	if not shown(s):return false
	var index:=0
	if not target.is_empty():
		index=option_cells().find(target)+1
		expect(index>0,"%s: %s listed as a source option"%[label,target])
		if index<=0:return false
	expect(not s.disabled and not s.is_item_disabled(index),"%s: option %d selectable"%[label,index])
	await reachable(s,label+" select")
	s=select_node()
	if not shown(s):return false
	await pace()
	print("FIXTURE %s: OptionButton.select(%d)+item_selected -> '%s' (%s); not human play"%[LABEL,index,target if not target.is_empty() else BAG_TEXT,label])
	s.select(index)
	s.item_selected.emit(index)
	await settle(6)
	return true

# -------------------------------------------------------- station helpers --

func open_station(st:Dictionary,label:String) -> bool:
	if is_instance_valid(app.modal):
		app._close_modal()
		await settle()
	await pose(near(st.cell))
	var counter0:=int(app.session.counter)
	match str(st.type):
		"bench":app.automation_ui.workbench(app,st.cell)
		"stove":app._cook_menu(st.cell)
		_:app.industry_ui.device(app,st.cell)
	await settle(6)
	if str(st.type) in ["sawmill","charcoal_kiln"]:
		var tab:=mctl("ProcessingManualTab") as BaseButton
		expect(tab!=null,"%s: ProcessingManualTab still exists"%label)
		if shown(tab) and not tab.disabled:
			tab.pressed.emit()
			await settle()
	var p:=picker()
	expect(p!=null,"MISSING API: %s: visible %s inside the station modal"%[label,PICKER])
	if p==null:return false
	var script=p.get_script()
	expect(script!=null and str(script.resource_path)==UI_FILE,"%s: picker is the shared %s component"%[label,UI_FILE])
	for method in ["option_cells","get_selected_cell"]:expect(p.has_method(method),"MISSING API: %s.%s()"%[PICKER,method])
	if str(st.type)=="bench":
		var title:String=World.CRAFT[st.recipe].name
		var hit:Button=null
		for d in descendants(app.modal):
			if d is Button and str(d.text)==title and hit==null:hit=d
		expect(hit!=null,"%s: recipe button '%s' present"%[label,title])
		if hit:
			hit.pressed.emit()
			await settle(4)
	elif str(st.type)=="stove":
		await press("CookingRecipe_"+str(st.recipe),label+" recipe",false)
	expect(str(picker().get("recipe_id"))==str(st.recipe) if picker() else false,"%s: host passed the selected recipe '%s' to the picker"%[label,st.recipe])
	expect(int(app.session.counter)==counter0,"%s: opening and choosing a recipe send no world action"%label)
	return true

## Bag default, eligible options, foreign private hidden, box required.
func check_default(st:Dictionary,label:String) -> void:
	var s:=select_node()
	expect(shown(s),"%s: %s visible"%[label,SELECT])
	if not shown(s):return
	expect(s.item_count>0 and s.get_item_text(0)==BAG_TEXT,"%s: first option is '%s'"%[label,BAG_TEXT])
	expect(s.selected==0 and selected_cell()=="","%s: picker starts at backpack only"%label)
	var cells:=option_cells()
	expect(cells==[key_at(st,NORTH),key_at(st,EAST)],"%s: options are own private (north) then shared (east) in y/x order: %s"%[label,cells])
	expect(not cells.has(key_at(st,WEST)),"%s: neighbour's private chest is not listed"%label)
	expect(s.item_count==cells.size()+1,"%s: OptionButton rows match the candidates"%label)
	var texts:=PackedStringArray()
	for i in s.item_count:texts.append(s.get_item_text(i))
	var joined:="\n".join(texts)
	expect(joined.contains("共用箱") and joined.contains("私人箱"),"%s: option labels name the box kinds"%label)
	expect(snap_box_id(key_at(st,WEST))=="","%s: snapshot never exposes the neighbour's private box_id"%label)
	expect(unusable(st.main),"%s: %s disabled with backpack only (box required)"%[label,st.main])
	if str(st.main)=="CraftRecipe":
		expect(shown(s) and s.get_item_text(s.selected)==BAG_TEXT and not shown(pctl(STATUS)),"%s: visible selector explains backpack-only without a duplicate status row"%label)
	else:
		expect(text_of(pctl(STATUS)).contains("背包"),"%s: queue status explains backpack-only and refund"%label)

## Exact displayed split per row vs. actual stock.
func check_split(st:Dictionary,label:String,box_key:String,from_bag:Dictionary,from_box:Dictionary,missing:Dictionary={}) -> void:
	var need:Dictionary=recipe_of(st).ingredients
	var bag:=inv()
	var box:=items(box_key)
	expect(shown(pctl(BREAKDOWN)),"%s: %s visible"%[label,BREAKDOWN])
	for item in need:
		var r:=row(str(item))
		expect(not r.is_empty(),"%s: row for %s shown"%[label,item])
		if r.is_empty():continue
		expect(int(r.need)==int(need[item]),"%s: %s need %d ('%s')"%[label,item,need[item],r.text])
		expect(int(r.bag)==int(from_bag.get(item,0)),"%s: %s backpack share exactly %d ('%s')"%[label,item,from_bag.get(item,0),r.text])
		expect(int(r.box)==int(from_box.get(item,0)),"%s: %s box share exactly %d ('%s')"%[label,item,from_box.get(item,0),r.text])
		expect(int(r.held)==int(bag.get(item,0)),"%s: %s actual backpack held %d shown separately ('%s')"%[label,item,bag.get(item,0),r.text])
		expect(int(r.stock)==int(box.get(item,0)),"%s: %s box stock %d shown separately ('%s')"%[label,item,box.get(item,0),r.text])
		expect(int(r.missing)==int(missing.get(item,0)),"%s: %s missing %d ('%s')"%[label,item,missing.get(item,0),r.text])

func check_layout(st:Dictionary,label:String) -> void:
	var window:=root.get_visible_rect().grow(0.5)
	expect(is_instance_valid(app.modal) and window.encloses(app.modal.get_global_rect()),"%s: modal contained in the viewport"%label)
	var p:=picker()
	expect(p!=null,"%s: picker visible"%label)
	if p==null:return
	if app.modal.name=="CookingQueueUI":
		for detail_name in ["CookingSelectedName","CookingSelectedInfo"]:
			var detail:=mctl(detail_name)
			expect(shown(detail) and window.encloses(detail.get_global_rect()),"%s: chosen recipe name/yield/time visible without scrolling"%label)
			if shown(detail):
				var ancestor:=detail.get_parent()
				while ancestor!=null:
					if ancestor is ScrollContainer:
						expect(ancestor.get_global_rect().encloses(detail.get_global_rect()),"%s: chosen recipe not clipped by browsing scroll"%label)
					ancestor=ancestor.get_parent()
	expect(app.modal.get_global_rect().grow(0.5).encloses(p.get_global_rect()),"%s: picker contained in the modal"%label)
	var rects:=[]
	for node_name in [SELECT,SCROLL,st.main]:
		var c:=mctl(node_name)
		expect(shown(c),"%s: %s visible"%[label,node_name])
		if not shown(c):continue
		await reachable(c,"%s: %s"%[label,node_name])
		var g:=c.get_global_rect()
		expect(g.size.x>=16 and g.size.y>=16,"%s: %s has a usable size %s"%[label,node_name,g.size])
		for other in rects:
			expect(not g.grow(-1.0).intersects(other[1].grow(-1.0)),"%s: %s does not overlap %s"%[label,node_name,other[0]])
		rects.append([node_name,g])
	var status:=pctl(STATUS)
	if shown(status) and not str((status as Label).text).is_empty():await reachable(status,label+" status")

func shoot(state:String,check:Callable) -> void:
	for extent in EXTENTS:
		root.size=extent
		await settle(4)
		if is_instance_valid(app.modal):
			for i in 30:
				if app.modal.modulate.a>=1.0:break
				await process_frame
		var label:="%s %dx%d"%[state,extent.x,extent.y]
		await check.call(label)
		if qa:
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image()
			var good:bool=image!=null and not image.is_empty() and image.get_size()==extent
			expect(good,"%s: rendered frame captured"%label)
			if good:
				var colors:={}
				for gy in 20:
					for gx in 32:colors[image.get_pixel(int((gx+0.5)*extent.x/32.0),int((gy+0.5)*extent.y/20.0)).to_html()]=true
				expect(colors.size()>=12,"%s: frame is an actual render (%d sampled colours)"%[label,colors.size()])
				var path:=qa_dir.path_join("material-%s-%dx%d.png"%[state,extent.x,extent.y])
				var wrote:=image.save_png(path)==OK
				expect(wrote,"saved "+path)
				var back:=Image.load_from_file(path)
				var readable:bool=back!=null and back.get_size()==extent
				expect(readable,"PNG readable at %s"%path)
				if wrote and readable:
					saved_shots["%s-%dx%d"%[state,extent.x,extent.y]]=path
					print("MATERIAL_SOURCE_UI_SCREENSHOT %s sha256=%s"%[path,FileAccess.get_sha256(path)])
	root.size=EXTENTS[0]
	await settle(4)

## Explicit box choice; when the box has no id, waits for the exact prepare ack.
func select_box(st:Dictionary,key:String,label:String,expect_prepare:bool) -> bool:
	var since:=acks.size()
	var counter0:=int(app.session.counter)
	var id0:=box_id(key)
	var others:=all_box_ids()
	others.erase(key)
	if not await choose(key,label):return false
	if expect_prepare:
		var a:Dictionary=await wait_for([PREPARE],since,key)
		expect(not a.is_empty(),"%s: explicit selection sent %s and its correlated ack arrived"%[label,PREPARE])
		if a.is_empty():return false
		expect(a.result.get("ok")==true,"%s: prepare ok (%s)"%[label,a.result.get("message","")])
		var id:=box_id(key)
		expect(id0=="" and lowerhex32(id),"%s: box_id assigned lazily by the explicit prepare"%label)
		expect(str(a.result.get("source_id",""))==id,"%s: ack source_id equals the stored box_id"%label)
		expect(snap_box_id(key)==id,"%s: snapshot carries the prepared box_id"%label)
		expect(int(app.session.counter)==counter0+1,"%s: exactly one request (the prepare)"%label)
	else:
		expect(not has_ack([PREPARE],since) and int(app.session.counter)==counter0,"%s: already prepared box re-selected without another request"%label)
		expect(box_id(key)==id0,"%s: box_id unchanged"%label)
	var after:=all_box_ids()
	after.erase(key)
	expect(after==others,"%s: no other box gained or lost an id"%label)
	expect(selected_cell()==key,"%s: picker holds the explicit selection"%label)
	return true

## Real UI submit; verifies ack split, exact inventory/chest deltas. Returns new job id.
func submit(st:Dictionary,label:String) -> String:
	var key:=key_at(st,EAST)
	var need:Dictionary=recipe_of(st).ingredients
	var product:=str(st.recipe)
	var bag0:=inv()
	var box0:=items(key)
	var ids0:=job_ids(st)
	var since:=acks.size()
	if not await press(st.main,label+" submit"):return ""
	var a:Dictionary=await wait_for(st.actions,since)
	expect(not a.is_empty(),"%s: correlated completion for the sourced action"%label)
	if a.is_empty():return ""
	var r:Dictionary=a.result
	expect(r.get("ok")==true,"%s: sourced %s accepted (%s)"%[label,a.action,r.get("message","")])
	expect(same(r.get("from_backpack"),st.from_bag) and same(r.get("from_chest"),st.from_box),"%s: server split equals the displayed split %s/%s"%[label,r.get("from_backpack"),r.get("from_chest")])
	expect(str(r.get("source_cell",""))==key and str(r.get("source_id",""))==box_id(key),"%s: result names the chosen box"%label)
	var bag1:=inv()
	var box1:=items(key)
	for item in need:
		expect(int(bag1.get(item,0))==int(bag0.get(item,0))-int(st.from_bag.get(item,0)),"%s: backpack %s %d -> %d"%[label,item,bag0.get(item,0),bag1.get(item,0)])
		expect(int(box1.get(item,0))==int(box0.get(item,0))-int(st.from_box.get(item,0)),"%s: chest %s %d -> %d"%[label,item,box0.get(item,0),box1.get(item,0)])
	var unrelated:=true
	for item in bag0.keys()+bag1.keys():
		if need.has(item) or item==product:continue
		if int(bag0.get(item,0))!=int(bag1.get(item,0)):unrelated=false
	expect(unrelated,"%s: unrelated backpack items untouched"%label)
	for item in box0.keys()+box1.keys():
		if not need.has(item):expect(int(box0.get(item,0))==int(box1.get(item,0)),"%s: unrelated chest item %s untouched"%[label,item])
	if str(st.type)=="bench":
		expect(int(bag1.get(product,0))==int(bag0.get(product,0))+int(World.CRAFT[product].yield),"%s: crafted %s once"%[label,product])
		return ""
	var fresh:=[]
	for id in job_ids(st):
		if not ids0.has(id):fresh.append(id)
	expect(fresh.size()==1,"%s: exactly one job queued"%label)
	if fresh.size()!=1:return ""
	for j in job_records(st):
		if str(j.get("id",""))==fresh[0]:
			expect(same(j.get("ingredients"),need),"%s: job stores the full recipe ingredients %s"%[label,j.get("ingredients")])
	return str(fresh[0])

func cancel(st:Dictionary,id:String,label:String) -> void:
	if id.is_empty():
		expect(false,"%s: no job to cancel"%label)
		return
	var key:=key_at(st,EAST)
	var need:Dictionary=recipe_of(st).ingredients
	var bag0:=inv()
	var box0:=items(key)
	var since:=acks.size()
	if not await press(str(st.cancel)+id,label):return
	var a:Dictionary=await wait_for(st.cancel_actions,since)
	expect(not a.is_empty() and a.result.get("ok")==true,"%s: cancel acknowledged ok"%label)
	expect(not job_ids(st).has(id),"%s: job removed"%label)
	var bag1:=inv()
	for item in need:
		expect(int(bag1.get(item,0))==int(bag0.get(item,0))+int(need[item]),"%s: full %s %d refunded to the backpack"%[label,item,need[item]])
	expect(items(key)==box0,"%s: nothing returned to the chest"%label)

func check_refund_sentence(label:String) -> void:
	var t:=text_of(pctl(REFUND))
	expect(RegEx.create_from_string("退回.*背包").search(t)!=null,"%s: refund-to-backpack sentence shown before confirming ('%s')"%[label,t])

# -------------------------------------------------------------------- run --

func run() -> void:
	print("MATERIAL_SOURCE_UI fixture=%s user_data_dir=%s"%[LABEL,OS.get_user_data_dir()])
	var isolated:=OS.get_environment("MATERIAL_SOURCE_UI_ISOLATED")
	if not isolated.is_empty():
		var user_dir:=OS.get_user_data_dir().replace("\\","/").to_lower()
		var sandbox:=isolated.replace("\\","/").to_lower()
		expect(user_dir.begins_with(sandbox),"user:// lives under the runner's isolated APPDATA (%s)"%OS.get_user_data_dir())
	expect(ResourceLoader.exists(UI_FILE),"MISSING API: %s exists"%UI_FILE)
	dir="user://test-material-source-ui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		await finish()
		return
	var args:=OS.get_cmdline_user_args()
	qa="--qa-preview" in args
	if qa:
		for a in args:
			if a.begins_with("--qa-output="):qa_dir=a.trim_prefix("--qa-output=")
		var absolute:=qa_dir.is_absolute_path() and not qa_dir.begins_with("res://") and not qa_dir.begins_with("user://")
		expect(absolute,"--qa-preview needs an absolute --qa-output=<dir> (got '%s')"%qa_dir)
		if absolute:expect(DirAccess.make_dir_recursive_absolute(qa_dir)==OK,"QA output directory ready")
		qa=absolute
	describe()
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=EXTENTS[0]
	var session=app.session
	session.set_physics_process(false)
	session.profile={"token":"msrc-ui-isolated-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]}
	if not setup_world():
		expect(false,"fixture world could not be prepared")
		await finish()
		return
	session.world=w
	session.action_completed.connect(_on_ack)
	session._attach_registered(1,T)
	await settle(6)
	expect(app.playing and not app.menu.visible and app.hud.visible,"entered through Session.connected_world -> Main._entered")
	await flow_bench()
	await flow_stove()
	await flow_mill()
	await flow_kiln()
	await flow_keys()
	expect(box_id(key_at(stations.stove,WEST))==foreign_id,"neighbour's private box_id never changed by the tester")
	await finish()

# ------------------------------------------------------------------ flows --

func flow_bench() -> void:
	var st:Dictionary=stations.bench
	var plan:=Supply.plan(recipe_of(st).ingredients,st.bag,st.box)
	expect(plan.ok and same(plan.from_backpack,st.from_bag) and same(plan.from_chest,st.from_box),"bench: fixture split matches MaterialSupply.plan")
	await seed_bag(st.bag,"bench: low stock so the chest is required")
	if not await open_station(st,"bench"):return
	check_default(st,"bench")
	expect(box_id(key_at(st,EAST))=="" and box_id(key_at(st,NORTH))=="","bench: viewing assigns no box_id")
	var key:=key_at(st,EAST)
	if not await select_box(st,key,"bench shared",true):return
	check_split(st,"bench shared",key,st.from_bag,st.from_box)
	expect(usable(st.main),"bench: craft enabled once the shared chest covers the shortage")
	expect(text_of(pctl(STATUS)).contains("箱子"),"bench: status states the box share")
	await shoot("bench-source",func(l):await check_layout(st,l))
	await submit(st,"bench craft")
	await bench_replaced(st)

## Box replaced at the same cell: no fallback, no implicit prepare, explicit re-prepare.
func bench_replaced(st:Dictionary) -> void:
	var key:=key_at(st,EAST)
	var old_id:=box_id(key)
	print("FIXTURE %s: shared chest at %s REPLACED directly by a new chest without box_id"%[LABEL,key])
	w.state.objects[key]={"type":"chest","owner":T,"items":(st.box as Dictionary).duplicate()}
	await seed_bag((recipe_of(st).ingredients as Dictionary).duplicate(),"replaced: enough backpack stock must not silently change chosen source")
	expect(selected_cell()==key and unusable(st.main),"replaced: sufficient backpack still requires explicit source reconfirmation")
	await seed_bag(st.bag,"bench replaced: low stock again")
	var bag0:=inv()
	var box0:=items(key)
	var counter0:=int(app.session.counter)
	var since:=acks.size()
	var s:=select_node()
	expect(shown(s) and s.selected!=0 and selected_cell()==key,"replaced: selection stays on the explicit box (no fallback to backpack)")
	expect(unusable(st.main),"replaced: craft blocked until the new box is explicitly prepared")
	var status:=text_of(pctl(STATUS))
	expect(not status.is_empty(),"replaced: status explains the box state")
	expect(shown(pctl(RETRY)) or not status.contains("等待世界同步"),"replaced: offers an explicit re-prepare instead of waiting for a sync that never comes ('%s')"%status)
	if usable(st.main):await press(st.main,"replaced forced submit")
	await settle(4)
	expect(box_id(key)=="","replaced: no implicit prepare of the new box")
	expect(int(app.session.counter)==counter0 and not has_ack(["craft",PREPARE],since),"replaced: no automatic request")
	expect(inv()==bag0 and items(key)==box0,"replaced: backpack and new chest untouched")
	# Explicit recovery: retry button when offered, else backpack then box again.
	if usable(RETRY):
		await pace()
		await press(RETRY,"replaced retry",false)
	else:
		await choose("","replaced back to backpack")
		expect(selected_cell()=="","replaced: explicit backpack choice clears the source")
		await choose(key,"replaced reselect")
	var a:Dictionary=await wait_for([PREPARE],since,key)
	expect(not a.is_empty() and a.result.get("ok")==true,"replaced: explicit re-prepare acknowledged")
	var new_id:=box_id(key)
	expect(lowerhex32(new_id) and new_id!=old_id,"replaced: new box gets its own id, never adopts the old one")
	check_split(st,"replaced split",key,st.from_bag,st.from_box)
	expect(usable(st.main),"replaced: craft available again after explicit prepare")

func flow_stove() -> void:
	var st:Dictionary=stations.stove
	var plan:=Supply.plan(recipe_of(st).ingredients,st.bag,st.box)
	expect(plan.ok and same(plan.from_backpack,st.from_bag) and same(plan.from_chest,st.from_box),"stove: fixture split matches MaterialSupply.plan")
	await seed_bag(st.bag,"stove: low stock")
	if not await open_station(st,"stove"):return
	check_default(st,"stove")
	expect(str(obj(World.key(st.cell)).get("owner",""))==B,"stove: neighbour's stove is still usable as a shared station")
	var key:=key_at(st,EAST)
	if not await select_box(st,key,"stove shared",true):return
	check_split(st,"stove shared",key,st.from_bag,st.from_box)
	check_refund_sentence("stove")
	expect(usable(st.main),"stove: enqueue enabled with the shared chest")
	await shoot("stove-source",func(l):await check_layout(st,l))
	var id:String=await submit(st,"stove enqueue")
	await cancel(st,id,"stove cancel")
	# Own private chest: listed, explicit only, prepared lazily.
	await seed_bag(st.bag,"stove: low stock for the private chest")
	var own:=key_at(st,NORTH)
	expect(box_id(own)=="","stove: own private chest has no id before an explicit choice")
	var shared_id:=box_id(key)
	if await select_box(st,own,"stove own private",true):
		check_split(st,"stove private",own,st.from_bag,st.from_box)
		expect(box_id(key)==shared_id,"stove: shared chest id unchanged by the private prepare")
	await choose("","stove back to backpack")
	expect(selected_cell()=="" and unusable(st.main),"stove: explicit backpack choice clears the source; low stock blocks again")
	expect(not shown(pctl(SCROLL)),"stove: no box split shown for backpack only")
	await select_box(st,own,"stove private again",false)
	var counter0:=int(app.session.counter)
	if await open_station(st,"stove reopen"):
		var s:=select_node()
		expect(shown(s) and s.selected==0 and selected_cell()=="","stove reopen: source resets to backpack (not persisted)")
		expect(int(app.session.counter)==counter0,"stove reopen: no request")
		for node_name in ["CookingClaim","CookingCapacity","CookingRecipe_feed"]:
			expect(mctl(node_name)!=null,"stove: existing control %s retained"%node_name)

func flow_mill() -> void:
	var st:Dictionary=stations.mill
	var key:=key_at(st,EAST)
	await seed_bag(st.bag,"mill: low stock")
	if not await open_station(st,"mill"):return
	check_default(st,"mill")
	if not await select_box(st,key,"mill shared",true):return
	check_split(st,"mill shared",key,st.from_bag,st.from_box)
	check_refund_sentence("mill")
	# Stale displayed quote: backpack changes WITHOUT a snapshot reaching the UI.
	print("FIXTURE %s: backpack wood set to 2 WITHOUT sending a snapshot (stale displayed split)"%LABEL)
	w.state.players[T].inventory["wood"]=2
	var box0:=items(key)
	var counter0:=int(app.session.counter)
	var since:=acks.size()
	if await press(st.main,"mill stale submit"):
		var a:Dictionary=await wait_for(st.actions,since)
		expect(not a.is_empty() and a.result.get("ok")!=true and a.result.get("requote")==true,"stale: server rejects the stale split with requote")
		await settle(6)
		expect(int(app.session.counter)==counter0+1,"stale: frozen request sent once, no automatic retry")
		expect(int(inv().get("wood",0))==2 and items(key)==box0 and job_ids(st).is_empty(),"stale: nothing debited, nothing queued")
		expect(text_of(app.modal).contains("變動"),"stale: readable requote message shown")
		check_split(st,"stale requoted",key,{"wood":2},{"wood":2})
	await seed_bag(st.bag,"mill: restore low stock")
	expect(usable(st.main),"mill: enqueue enabled with the shared chest")
	await shoot("mill-source",func(l):await check_layout(st,l))
	var id:String=await submit(st,"mill enqueue")
	await cancel(st,id,"mill cancel")
	# Insufficient: backpack + chest still short.
	print("FIXTURE %s: chest %s wood set directly to 2 (insufficient)"%[LABEL,key])
	w.state.objects[key].items["wood"]=2
	await seed_bag({"wood":1},"mill: insufficient")
	counter0=int(app.session.counter)
	check_split(st,"mill missing",key,{"wood":1},{"wood":2},{"wood":1})
	expect(unusable(st.main),"missing: enqueue disabled")
	expect(text_of(pctl(STATUS)).contains("缺"),"missing: status names the shortage")
	await shoot("missing-source",func(l):await check_layout(st,l))
	expect(int(app.session.counter)==counter0,"missing: no request sent")
	# Moved: the selected box leaves adjacency (keeps its id).
	var moved_id:=box_id(key)
	var far:=key_at(st,FAR)
	print("FIXTURE %s: chest MOVED directly %s -> %s (keeps box_id)"%[LABEL,key,far])
	w.state.objects[far]=w.state.objects[key]
	w.state.objects.erase(key)
	await seed_bag({"wood":1},"mill moved: box required")
	counter0=int(app.session.counter)
	since=acks.size()
	var s:=select_node()
	var stale_at:=option_cells().find(key)
	expect(not option_cells().has(far),"moved: box at its new non-adjacent cell not offered")
	expect(shown(s) and (stale_at<0 or s.is_item_disabled(stale_at+1)),"moved: old cell no longer selectable")
	expect(shown(s) and s.selected!=0 and selected_cell()==key,"moved: selection not silently switched to backpack")
	expect(shown(s) and s.selected>0 and s.is_item_disabled(s.selected),"moved: stale entry shown disabled")
	expect(unusable(st.main),"moved: enqueue blocked")
	expect(not text_of(pctl(STATUS)).is_empty(),"moved: status explains the box is gone")
	await settle(4)
	expect(int(app.session.counter)==counter0 and not has_ack(st.actions+[PREPARE],since),"moved: no automatic request")
	expect(box_id(far)==moved_id and int(inv().get("wood",0))==1,"moved: box id and backpack untouched")
	await choose("","moved explicit backpack")
	expect(selected_cell()=="","moved: explicit backpack choice clears the source")
	await seed_bag({"wood":8},"mill: backpack alone sufficient")
	expect(usable(st.main),"moved: backpack-only enqueue available after explicit choice")
	# Existing automatic tab retained.
	var auto:=mctl("ProcessingAutoTab") as BaseButton
	expect(shown(auto),"mill: ProcessingAutoTab retained")
	if shown(auto) and not auto.disabled:
		var state0:=var_to_str(w.state.objects)
		auto.pressed.emit()
		await settle()
		for node_name in ["ProcessingFeed","ProcessingToggleAuto","ProcessingCollect"]:expect(shown(mctl(node_name)),"mill auto: %s retained"%node_name)
		expect(usable("ProcessingToggleAuto"),"mill auto: toggle available with an empty queue")
		expect(var_to_str(w.state.objects)==state0,"mill auto: switching tab changes nothing")

func flow_kiln() -> void:
	var st:Dictionary=stations.kiln
	await seed_bag(st.bag,"kiln: low stock")
	if not await open_station(st,"kiln"):return
	check_default(st,"kiln")
	var key:=key_at(st,EAST)
	if await select_box(st,key,"kiln shared",true):
		check_split(st,"kiln shared",key,st.from_bag,st.from_box)
		expect(usable(st.main),"kiln: enqueue enabled with the shared chest")

func flow_keys() -> void:
	var st:Dictionary=stations.bench
	if is_instance_valid(app.modal):
		app._close_modal()
		await settle()
	var before:=hud_visible_children()
	expect(not before.is_empty(),"keys: HUD has visible controls before opening")
	if not await open_station(st,"keys"):return
	await press_key(KEY_TAB)
	expect(picker()!=null,"Tab does not replace the open station UI with the backpack")
	await press_key(KEY_ESCAPE)
	expect(app.modal==null and picker()==null,"Esc closes the station UI")
	for c in before:expect(is_instance_valid(c) and c.visible,"HUD control %s restored after Esc"%c.name)
	await press_key(KEY_TAB)
	expect(app.modal!=null and picker()==null,"Tab still opens the backpack")
	await press_key(KEY_TAB)
	expect(app.modal==null,"Tab closes the backpack")

func finish() -> void:
	if qa:
		for state in REQUIRED_STATES:
			for extent in EXTENTS:
				var k:="%s-%dx%d"%[state,extent.x,extent.y]
				expect(saved_shots.has(k),"required screenshot %s captured"%k)
	if is_instance_valid(app):
		app._close_modal()
		app.queue_free()
	for i in 3:await process_frame
	if failures>0 and qa and FileAccess.file_exists(dir+"/world.json"):
		var copied:=DirAccess.copy_absolute(dir+"/world.json",qa_dir.path_join("failed-world.json"))==OK
		print("MATERIAL_SOURCE_UI retained failing fixture world: %s"%("failed-world.json" if copied else "copy failed"))
	remove_tree(dir)
	if not dir.is_empty():expect(not DirAccess.dir_exists_absolute(dir),"isolated test directory removed")
	print("MATERIAL_SOURCE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func remove_tree(path:String) -> void:
	if not path.begins_with("user://test-material-source-ui-"):return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):remove_tree(path+"/"+sub)
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+f)
	DirAccess.remove_absolute(path)
