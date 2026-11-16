extends SceneTree
## Native UI test for T036 manual sawmill / charcoal-kiln processing queues
## (docs/processing-queue-contract.json "ui"): compact manual queue tab and
## automatic buffer tab inside the existing industry device modal.
##
## Instantiates the ACTUAL main.tscn with village_art_preview=true, a REAL
## Session host and a REAL isolated World. The island is entered through
## Session._attach_registered(1) -> connected_world -> Main._entered; every
## snapshot reaches Main through the real Session.changed signal and every UI
## action travels Session.perform -> World.act.
##
## FIXTURE, NOT HUMAN PLAY (label LABEL). The script programmatically:
##  * seeds wood directly into both players' backpacks;
##  * writes four stations directly into the World object layer (same shape as
##    a real build): MILL (own sawmill), AUTO (own sawmill for the automatic
##    tab), KILN (own charcoal kiln holding a legacy single job created through
##    the real World.act("start_processing") path) and FOREIGN (a neighbour's
##    kiln with a job the neighbour queued through World.act), then saves and
##    RE-LOADS the world from disk;
##  * teleports the player next to each station;
##  * stops automatic ticks (Session physics + Main _process disabled) and
##    ADVANCES WORLD TIME with World.step (each advance printed as FIXTURE);
##  * presses UI buttons by emitting `pressed`, pushes synthetic physical key
##    events through the root viewport, and calls Main._refresh_hud() after
##    frames because Main's polling loop is disabled (one check deliberately
##    skips that call to prove the controller listens to Session.changed);
##  * paces UI actions under Session's real 12-per-second limit.
## The world lives in one per-run user:// directory removed at the end (copied
## to the QA directory first when something failed). The profile token used by
## Main is a throwaway value.
##
## UI contract (missing names are counted failures, never skipped):
##  ProcessingQueueUI (app.modal or a descendant), opened via
##  app.industry_ui.device(app, cell) for sawmill / charcoal_kiln;
##  ProcessingManualTab, ProcessingAutoTab, ProcessingEnqueue, ProcessingClaim,
##  ProcessingCapacity, ProcessingCancel_<job id> (legacy job: any suffix),
##  ProcessingStatus, ProcessingFeed, ProcessingUnload, ProcessingToggleAuto,
##  ProcessingCollect.
##
## Optional native capture: --qa-preview --qa-output=<ABSOLUTE DIR> saves PNGs
## at 1024x640 and 1280x800 for every state (needs a rendering run).

const World=preload("res://scripts/world.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const Village=preload("res://scripts/village.gd")
const LABEL:="processing-queue-ui/fixture-20261114"
const EXTENTS:=[Vector2i(1024,640),Vector2i(1280,800)]
const REQUIRED_STATES:=["manual-empty","missing","active","ready","full","auto","legacy","nonowner"]
const T:="tok-proc-ui-SECRET-tester"
const B:="tok-proc-ui-SECRET-neighbour"
const NODE_CAP:=6000
const TOL:=0.001
const ROOT_NAME:="ProcessingQueueUI"
const ENQUEUE:="ProcessingEnqueue"
const CLAIM:="ProcessingClaim"
const CAPACITY:="ProcessingCapacity"
const STATUS:="ProcessingStatus"
const CANCEL_PREFIX:="ProcessingCancel_"
const MANUAL_TAB:="ProcessingManualTab"
const AUTO_TAB:="ProcessingAutoTab"
const FEED:="ProcessingFeed"
const UNLOAD:="ProcessingUnload"
const TOGGLE:="ProcessingToggleAuto"
const COLLECT:="ProcessingCollect"
const STOCK_WOOD:=120

var checks:=0
var failures:=0
var app
var w
var dir:=""
var qa:=false
var qa_dir:=""
var saved_shots:={}
var MILL:=Vector2i(-1,-1)
var AUTO:=Vector2i(-1,-1)
var KILN:=Vector2i(-1,-1)
var FOREIGN:=Vector2i(-1,-1)
var legacy_job:={}
var rate_marks:=[]
var ids:=[]

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

func cancel_buttons() -> Dictionary:
	var out:={}
	for d in descendants(ui()):
		if d is BaseButton and str(d.name).begins_with(CANCEL_PREFIX):out[str(d.name).trim_prefix(CANCEL_PREFIX)]=d
	return out

func usable_cancels() -> Dictionary:
	var out:={}
	var all:=cancel_buttons()
	for id in all:
		var b:BaseButton=all[id]
		if b.is_visible_in_tree() and not b.disabled:out[id]=b
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

func hud_visible_children() -> Array:
	var out:=[]
	for c in app.hud.get_children():
		if c is Control and c.visible and c!=app.modal and c!=app.modal_shade and c!=app.toast:out.append(c)
	return out

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
	if not (p.active as Dictionary).is_empty():out.append(str(p.active.id))
	return out+ids_of(p.waiting)+ids_of(p.ready)

func held(item:String) -> int:
	return int(w.state.players[T].inventory.get(item,0))

func progress() -> String:
	var person:Dictionary=w.state.players[T]
	return var_to_str([person.get("cooked",0),person.get("collection",{})])

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
	expect(false,"fixture found a legal empty station site")
	return Vector2i(-1,-1)

func fixture_act(w0,token:String,action:String,c:Vector2i,extra:String) -> Dictionary:
	var person:Dictionary=w0.state.players[token]
	person.x=near(c).x
	person.y=near(c).y
	return w0.act(token,"fixture-%s-%s"%[action,World.key(c)],action,c,extra)

func setup_world() -> bool:
	var path:=dir+"/world.json"
	var w0=World.new()
	w0.save_path=path
	w0.add_player(T,"島民")
	w0.add_player(B,"鄰居")
	for t in [T,B]:w0.state.players[t].inventory["wood"]=STOCK_WOOD
	var avoid:Array=[Vector2i(World.SPAWN),Vector2i(40,29),Vector2i(43,29),Vector2i(45,34),Vector2i(54,25),World.COPPER_CELL]
	for resident in Village.ids_for_region("home"):avoid.append(Village.NPCS[resident].cell)
	for candidate in World.SHIPPING.CANDIDATES:avoid.append(candidate)
	for candidate in World.COMMUNITY.CANDIDATES:avoid.append(candidate)
	var sites:=[]
	for i in 4:
		var s:=find_site(w0,avoid)
		if s.x<0:return false
		sites.append(s)
		avoid.append(s)
	MILL=sites[0];AUTO=sites[1];KILN=sites[2];FOREIGN=sites[3]
	var shape:={"items":{},"input_wood":0,"auto_enabled":false}
	for entry in [[MILL,"sawmill",T],[AUTO,"sawmill",T],[KILN,"charcoal_kiln",T],[FOREIGN,"charcoal_kiln",B]]:
		var obj:Dictionary=shape.duplicate(true)
		obj.type=entry[1]
		obj.owner=entry[2]
		w0.state.objects[World.key(entry[0])]=obj
	var r:Dictionary=fixture_act(w0,T,"start_processing",KILN,"charcoal")
	expect(r.get("ok")==true,"fixture: legacy start_processing on untouched kiln: %s"%r.get("message",""))
	var job=w0.state.objects[World.key(KILN)].get("job")
	expect(job is Dictionary and not w0.state.objects[World.key(KILN)].has("processing"),"fixture: untouched kiln keeps the legacy single job")
	if job is Dictionary:legacy_job=job.duplicate(true)
	r=fixture_act(w0,B,"queue_processing",FOREIGN,"charcoal")
	expect(r.get("ok")==true,"fixture: neighbour queues on own kiln through World.act: %s"%r.get("message",""))
	var tester:Dictionary=w0.state.players[T]
	tester.x=near(MILL).x
	tester.y=near(MILL).y
	expect(w0.save(),"fixture world saved")
	w=World.new()
	var loaded:bool=w.load_world(path)
	expect(loaded,"fixture world re-loaded from disk (real SaveSchema)")
	if not loaded:return false
	w.add_player(T,"島民")
	expect(dev(KILN).has("job") and not dev(KILN).has("processing"),"legacy job loaded from save")
	expect(all_ids(q(FOREIGN)).size()==1,"neighbour queue loaded from save")
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

func set_wood(value:int) -> void:
	w.state.players[T].inventory["wood"]=value
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

## Switches tab; must not send any world action. A visible but disabled tab
## button is accepted as "already the current tab".
func tab(node_name:String,label:String) -> bool:
	var counter0:=int(app.session.counter)
	var state0:=var_to_str(w.state)
	var b:=ctl(node_name) as BaseButton
	expect(shown(b),"%s: tab '%s' present and visible"%[label,node_name])
	if not shown(b):return false
	if b.disabled:return true
	var ok:bool=await press(node_name,label,false)
	expect(int(app.session.counter)==counter0 and var_to_str(w.state)==state0,"%s: switching tab performs no world action"%label)
	return ok

func press_key(code:Key) -> void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code
		e.physical_keycode=code
		e.pressed=pressed
		root.push_input(e)
	await settle()

func open_at(c:Vector2i,label:String) -> bool:
	if is_instance_valid(app.modal):
		app._close_modal()
		await settle()
	await pose(near(c))
	app.industry_ui.device(app,c)
	await settle(6)
	var ok:=ui()!=null
	expect(ok,"%s: app.industry_ui.device(%s) opens a visible %s"%[label,c,ROOT_NAME])
	if ok:await tab(MANUAL_TAB,label+" manual tab")
	return ok

func capacity_text() -> String:
	return text_of(ctl(CAPACITY))

# ------------------------------------------------------------- screenshots --

func shoot(state:String,check:Callable) -> void:
	for extent in EXTENTS:
		root.size=extent
		await settle(4)
		# Neutral framing: every scroll region at the top before capture.
		if is_instance_valid(app.modal):
			for node in descendants(app.modal):
				if node is ScrollContainer:node.scroll_vertical=0
			await settle(2)
			for i in 30:
				if app.modal.modulate.a>=1.0:break
				await process_frame
		var label:="%s %dx%d"%[state,extent.x,extent.y]
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
				var path:=qa_dir.path_join("processing-%s-%dx%d.png"%[state,extent.x,extent.y])
				var wrote:=image.save_png(path)==OK
				expect(wrote,"saved "+path)
				var back:=Image.load_from_file(path)
				var readable:bool=back!=null and back.get_size()==extent
				expect(readable,"PNG readable at %s"%path)
				if wrote and readable:
					saved_shots["%s-%dx%d"%[state,extent.x,extent.y]]=path
					print("PROCESSING_UI_SCREENSHOT %s"%path)
		await check.call(label)
	root.size=EXTENTS[0]
	await settle(4)

## Bounded layout: `names` visible, sized, inside the window, unclipped, no overlap.
func check_layout(label:String,names:Array) -> void:
	var r:=ui()
	expect(r!=null,"%s: %s visible"%[label,ROOT_NAME])
	if r==null:return
	var window:=root.get_visible_rect().grow(0.5)
	expect(window.encloses(r.get_global_rect()),"%s: %s inside the window"%[label,ROOT_NAME])
	if is_instance_valid(app.modal):expect(window.encloses(app.modal.get_global_rect()),"%s: modal inside the window"%label)
	var rects:=[]
	for node_name in [MANUAL_TAB,AUTO_TAB]+names:
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
	var cancels:=usable_cancels()
	for id in cancels:await reachable(cancels[id],"%s: cancel %s"%[label,id.left(8)])

func manual_names() -> Array:
	return [ENQUEUE,CAPACITY,STATUS]

func auto_names() -> Array:
	return [FEED,UNLOAD,TOGGLE,COLLECT]

# -------------------------------------------------------------------- run --

func run() -> void:
	print("PROCESSING_UI fixture=%s user_data_dir=%s"%[LABEL,OS.get_user_data_dir()])
	var isolated:=OS.get_environment("PROCESSING_UI_ISOLATED")
	if not isolated.is_empty():
		var user_dir:=OS.get_user_data_dir().replace("\\","/").to_lower()
		var sandbox:=isolated.replace("\\","/").to_lower()
		expect(user_dir.begins_with(sandbox),"user:// lives under the runner's isolated APPDATA (%s)"%OS.get_user_data_dir())
	dir="user://test-processing-queue-ui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
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
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=EXTENTS[0]
	var session=app.session
	session.set_physics_process(false)
	session.profile={"token":"proc-ui-isolated-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]}
	if not setup_world():
		expect(false,"fixture world could not be prepared")
		await finish()
		return
	session.world=w
	session._attach_registered(1,T)
	await settle(6)
	expect(app.playing and not app.menu.visible and app.hud.visible,"entered through Session.connected_world -> Main._entered")
	expect(session.own_id==T.sha256_text().left(16),"Main session holds the public own_id")
	if await flow_open():
		await flow_manual_empty_and_missing()
		# Legacy before any time advance, so the loaded legacy job is still running.
		await flow_legacy()
		await flow_enqueue_cancel()
		await flow_ready_claim()
		await flow_full()
		await flow_auto()
		await flow_nonowner()
		await flow_keys()
	await finish()

# ------------------------------------------------------------------ flows --

func flow_open() -> bool:
	await pose(near(MILL))
	app._interact()
	await settle(6)
	expect(ui()!=null,"interact next to the sawmill opens %s"%ROOT_NAME)
	if ui()==null:
		app._close_modal()
		app.industry_ui.device(app,MILL)
		await settle(6)
	var opened:=ui()!=null
	expect(opened,"MISSING API: app.industry_ui.device(app,cell) -> ProcessingQueueUI.open(app,cell) produced no visible '%s'"%ROOT_NAME)
	if not opened:return false
	for node_name in [MANUAL_TAB,AUTO_TAB,ENQUEUE,CLAIM,CAPACITY,STATUS]:
		expect(ctl(node_name)!=null,"MISSING CONTROL: %s"%node_name)
	await tab(AUTO_TAB,"open auto tab")
	for node_name in auto_names():expect(ctl(node_name)!=null,"MISSING CONTROL: %s"%node_name)
	await tab(MANUAL_TAB,"open manual tab")
	return true

func flow_manual_empty_and_missing() -> void:
	expect(usable(ENQUEUE),"empty: enqueue enabled with enough wood")
	expect(unusable(CLAIM),"empty: nothing to claim")
	expect(cancel_buttons().is_empty(),"empty: no cancel controls")
	expect(has_number(capacity_text(),0) and has_number(capacity_text(),Queue.CAPACITY),"empty: capacity shows 0 of %d ('%s')"%[Queue.CAPACITY,capacity_text()])
	await shoot("manual-empty",func(l):await check_layout(l,manual_names()))
	var counter0:=int(app.session.counter)
	var objects0:=var_to_str(w.state.objects)
	await set_wood(3)
	expect(unusable(ENQUEUE),"missing: enqueue disabled with 3 wood")
	var missing_check:=func(l):
		await check_layout(l,manual_names())
		expect(not text_of(ctl(STATUS)).strip_edges().is_empty(),"%s: %s explains the missing wood"%[l,STATUS])
		expect(unusable(ENQUEUE),"%s: enqueue disabled"%l)
	await shoot("missing",missing_check)
	expect(int(app.session.counter)==counter0 and var_to_str(w.state.objects)==objects0,"missing: no request sent, stations untouched")
	await set_wood(STOCK_WOOD)
	expect(usable(ENQUEUE),"enqueue re-enabled after restocking")

func flow_enqueue_cancel() -> void:
	if not await open_at(MILL,"enqueue"):return
	var wood0:=held("wood")
	for i in 3:
		if not await press(ENQUEUE,"enqueue %d"%i):return
	var p:=q(MILL)
	ids=all_ids(p)
	expect(ids.size()==3 and str(p.active.get("owner",""))==T,"three jobs queued through the UI")
	expect(held("wood")==wood0-12,"each UI enqueue charged 4 wood once")
	if ids.size()!=3:return
	var all:=usable_cancels()
	for id in ids:expect(all.has(id),"own job %s cancellable by exact id"%id.left(8))
	expect(has_number(capacity_text(),3),"capacity shows 3 ('%s')"%capacity_text())
	var active_check:=func(l):
		await check_layout(l,manual_names())
		expect(usable_cancels().size()==3,"%s: three own cancels"%l)
	await shoot("active",active_check)
	var wood1:=held("wood")
	if not await press(CANCEL_PREFIX+ids[1],"cancel middle"):return
	expect(all_ids(q(MILL))==[ids[0],ids[2]],"UI cancel removed exactly the middle job")
	expect(held("wood")==wood1+4,"UI cancel refunded 4 wood")
	expect(not cancel_buttons().has(ids[1]),"cancelled job leaves the UI")
	ids=[ids[0],ids[2]]

func flow_ready_claim() -> void:
	var p:=q(MILL)
	if ids.size()!=2 or p.is_empty() or (p.active as Dictionary).is_empty():
		expect(false,"ready precondition: one active, one waiting")
		return
	var dt:=float(p.active.finish)-float(w.state.time)+0.25
	# Controller must react to Session.changed alone (no Main._refresh_hud here).
	print("FIXTURE %s: world time advanced programmatically by %.3fs (complete first job; Session.changed only)"%[LABEL,dt])
	expect(w.step(dt,true),"fixture time advance committed (first job)")
	app.session._send_snapshot(1)
	for i in 4:await process_frame
	expect(usable(CLAIM),"claim enabled from Session.changed without Main refresh")
	await settle()
	expect(ids_of(q(MILL).ready)==[ids[0]],"first job ready")
	var ready_check:=func(l):
		await check_layout(l,manual_names()+[CLAIM])
		expect(usable(CLAIM),"%s: claim available"%l)
		expect(not usable_cancels().has(ids[0]),"%s: ready job not cancellable"%l)
	await shoot("ready",ready_check)
	var plank0:=held("plank")
	var prog0:=progress()
	if not await press(CLAIM,"claim"):return
	expect(held("plank")==plank0+2 and ready_n(q(MILL))==0,"claim added exactly 2 planks once")
	expect(progress()==prog0,"claim never touches cooked counter / collections")
	expect(unusable(CLAIM),"claim disabled when nothing is ready")

func ready_n(p:Dictionary) -> int:
	return 0 if p.is_empty() else (p.ready as Array).size()

func flow_full() -> void:
	var need:=Queue.CAPACITY-all_ids(q(MILL)).size()
	expect(need==9,"full precondition: one job before filling (need %d)"%need)
	for i in maxi(0,need):
		if not await press(ENQUEUE,"fill %d"%i):break
	var p:=q(MILL)
	expect(all_ids(p).size()==Queue.CAPACITY,"queue full at %d"%Queue.CAPACITY)
	var own:=ids_of(p.waiting)
	var full_check:=func(l):
		await check_layout(l,manual_names())
		expect(unusable(ENQUEUE),"%s: enqueue disabled when full"%l)
		expect(has_number(capacity_text(),Queue.CAPACITY),"%s: capacity shows %d ('%s')"%[l,Queue.CAPACITY,capacity_text()])
		var cancels:=usable_cancels()
		for id in own:expect(cancels.has(id),"%s: waiting job %s cancellable"%[l,id.left(8)])
	await shoot("full",full_check)
	await pace()
	var wood0:=held("wood")
	var objects0:=var_to_str(w.state.objects)
	app.session.perform("queue_processing",MILL,"plank")
	await settle()
	expect(held("wood")==wood0 and var_to_str(w.state.objects)==objects0,"forced eleventh request refused without charge")
	# Automatic mode cannot be enabled while the queue holds work.
	if await tab(AUTO_TAB,"full auto tab"):
		expect(shown(ctl(TOGGLE)) and unusable(TOGGLE),"auto toggle disabled while the manual queue is busy")
		await tab(MANUAL_TAB,"full manual tab")

func flow_auto() -> void:
	if not await open_at(AUTO,"auto"):return
	if not await tab(AUTO_TAB,"auto tab"):return
	var wood0:=held("wood")
	if not await press(FEED,"feed"):return
	expect(int(dev(AUTO).get("input_wood",0))==4 and held("wood")==wood0-4,"feed moved 4 wood into the input buffer")
	if not await press(TOGGLE,"enable auto"):return
	expect(dev(AUTO).get("auto_enabled",false)==true,"automatic mode enabled through the UI")
	await tab(MANUAL_TAB,"auto manual tab")
	expect(unusable(ENQUEUE),"manual enqueue unavailable while automatic mode is on")
	await tab(AUTO_TAB,"auto tab again")
	for i in 8:await advance(2.0,"automatic batch tick %d"%i)
	var d:=dev(AUTO)
	expect(int(d.items.get("plank",0))==2 and not d.has("job"),"automatic batch finished into the output buffer")
	expect(all_ids(q(AUTO)).is_empty(),"automatic work never appears in the manual queue")
	var auto_check:=func(l):
		await check_layout(l,auto_names())
		expect(usable(COLLECT) and usable(TOGGLE),"%s: collect and toggle available to the owner"%l)
	await shoot("auto",auto_check)
	var plank0:=held("plank")
	if await press(COLLECT,"collect"):
		expect(held("plank")==plank0+2 and int(dev(AUTO).items.get("plank",0))==0,"collect moved 2 planks to the backpack")
	if await press(TOGGLE,"disable auto"):
		expect(dev(AUTO).get("auto_enabled",true)==false,"automatic mode disabled again")
	var wood1:=held("wood")
	var fed:bool=await press(FEED,"feed again")
	var unloaded:=false
	if fed:unloaded=await press(UNLOAD,"unload")
	if unloaded:
		expect(int(dev(AUTO).get("input_wood",-1))==0 and held("wood")==wood1,"unload returned the buffered wood")
	await tab(MANUAL_TAB,"auto back to manual")
	expect(usable(ENQUEUE),"manual enqueue available again after automatic mode is off")

func flow_legacy() -> void:
	if not await open_at(KILN,"legacy"):return
	expect(float(legacy_job.get("ready",0.0))>float(w.state.time),"legacy: loaded job still running (no time advanced yet)")
	expect(dev(KILN).has("job") and not dev(KILN).has("processing"),"legacy: viewing does not convert the kiln")
	var cancels:=usable_cancels()
	expect(cancels.size()==1,"legacy: exactly one usable cancel for the legacy job (%d)"%cancels.size())
	var legacy_check:=func(l):
		await check_layout(l,manual_names())
		expect(usable_cancels().size()==1,"%s: legacy cancel offered"%l)
	await shoot("legacy",legacy_check)
	cancels=usable_cancels()
	if cancels.size()!=1:return
	var wood0:=held("wood")
	if not await press(str((cancels.values()[0] as Node).name),"legacy cancel"):return
	expect(not dev(KILN).has("job"),"legacy cancel removed the single job")
	expect(held("wood")==wood0+int(legacy_job.get("ingredients",{}).get("wood",-999)),"legacy cancel refunded the stored ingredients")

func flow_nonowner() -> void:
	if not await open_at(FOREIGN,"nonowner"):return
	var state0:=var_to_str(w.state)
	expect(unusable(ENQUEUE),"nonowner: enqueue disabled")
	expect(unusable(CLAIM),"nonowner: claim disabled")
	expect(usable_cancels().is_empty(),"nonowner: no usable cancel for the neighbour's job")
	expect(has_number(capacity_text(),1),"nonowner: neighbour's queue still visible ('%s')"%capacity_text())
	await shoot("nonowner",func(l):await check_layout(l,manual_names()))
	if await tab(AUTO_TAB,"nonowner auto tab"):
		for node_name in auto_names():
			expect(shown(ctl(node_name)) and unusable(node_name),"nonowner: %s visible but disabled"%node_name)
	expect(var_to_str(w.state)==state0,"nonowner: viewing changes nothing")

func flow_keys() -> void:
	app._close_modal()
	await settle()
	var before:=hud_visible_children()
	if not await open_at(MILL,"keys"):return
	await press_key(KEY_TAB)
	expect(ui()!=null,"Tab does not replace the open processing UI with the backpack")
	await press_key(KEY_ESCAPE)
	expect(app.modal==null and ui()==null,"Esc closes the processing UI")
	for c in before:expect(is_instance_valid(c) and c.visible,"HUD control %s restored after Esc"%c.name)
	await press_key(KEY_TAB)
	expect(app.modal!=null and ui()==null,"Tab still opens the backpack")
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
		print("PROCESSING_UI retained failing fixture world: %s"%("failed-world.json" if copied else "copy failed"))
	remove_tree(dir)
	if not dir.is_empty():expect(not DirAccess.dir_exists_absolute(dir),"isolated test directory removed")
	print("PROCESSING_QUEUE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func remove_tree(path:String) -> void:
	if not path.begins_with("user://test-processing-queue-ui-"):return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):remove_tree(path+"/"+sub)
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+f)
	DirAccess.remove_absolute(path)
