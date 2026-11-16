extends SceneTree
## Native UI test for the T036 cooking queue UI (docs/cooking-queue-integration.json
## "ui" boundary): cookbook with all recipes, visible ten-slot queue, ready shelf.
##
## Instantiates the ACTUAL main.tscn in village-art preview mode with a REAL
## Session host and a REAL, isolated World (same convention as
## test_blueprint_client_ui.gd). The island is entered through
## Session._attach_registered(1) -> connected_world -> Main._entered and every
## snapshot reaches Main through the real Session.changed signal. All UI actions
## travel Session.perform -> World.act.
##
## FIXTURE, NOT HUMAN PLAY (label LABEL). The script programmatically:
##  * seeds ingredients and three plain stoves directly into the World, creates
##    two legacy single jobs through the real pre-queue World.act("cook") path,
##    saves, and RE-LOADS the world from disk (legacy jobs are loaded state);
##  * teleports the player next to each stove;
##  * has a second (offline) neighbour enqueue through World.act directly;
##  * stops automatic ticks (Session physics + Main _process disabled) and
##    ADVANCES WORLD TIME PROGRAMMATICALLY with World.step (each advance is
##    printed with the FIXTURE label);
##  * presses UI buttons by emitting `pressed`, pushes synthetic key events
##    through the root viewport, and calls Main._refresh_hud() after frames
##    because Main's own polling loop is disabled for determinism;
##  * paces UI actions under Session's real 12-per-second limit.
## The world file lives in one per-run user:// directory that is removed at the
## end (its world.json is first copied to the QA directory if anything failed).
## The profile token used by Main is replaced by a throwaway value.
##
## UI contract under test (node names may be re-aligned by root; see constants):
##  CookingQueueUI (Control, descendant of app.modal or app.modal itself),
##  CookingRecipe_<recipe id>, CookingEnqueue, CookingClaim, CookingCancel_<job id>,
##  CookingCapacity, CookingStatus, CookingProgress. Opened by app._cook_menu(cell).
##
## Optional native capture: --qa-preview --qa-output=<ABSOLUTE DIR> saves PNGs at
## 1024x640 and 1280x800 for every state (needs a rendering, non-headless run).
## Missing API / controls and every skipped step are counted failures.

const World=preload("res://scripts/world.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const Village=preload("res://scripts/village.gd")
const LABEL:="cooking-queue-ui/fixture-20261114"
const EXTENTS:=[Vector2i(1024,640),Vector2i(1280,800)]
const REQUIRED_STATES:=["empty","error","active","ready","full","legacy"]
const T:="tok-cook-ui-SECRET-tester"
const B:="tok-cook-ui-SECRET-neighbour"
const NODE_CAP:=6000
const TOL:=0.001
# --- UI node names (single place to re-align after the runtime worker returns).
const ROOT_NAME:="CookingQueueUI"
const ENQUEUE:="CookingEnqueue"
const CLAIM:="CookingClaim"
const CAPACITY:="CookingCapacity"
const STATUS:="CookingStatus"
const PROGRESS:="CookingProgress"
const RECIPE_PREFIX:="CookingRecipe_"
const CANCEL_PREFIX:="CookingCancel_"
# Explicit fixture stock, not normal-play balances.
const STOCK:={"minnow":40,"sea_salt":40,"radish":40,"wheat":40,"fiber":40,"lettuce":40,"tomato":40,"potato":40,"carp":40,"carrot":40,"pumpkin":40,"flour":40,"sugar":40,"chime_herb":40,"egg":40,"strawberry":40,"cucumber":40,"sugar_beet":40,"snow_trout":40,"cabbage":40,"star_mushroom":40,"sweet_potato":40,"rice":40,"eggplant":40,"mist_tea":40,"watermelon":40,"sweet_corn":40,"milk":40}

var checks:=0
var failures:=0
var app
var w
var dir:=""
var qa:=false
var qa_dir:=""
var saved_shots:={}
var S:=Vector2i(-1,-1)
var L:=Vector2i(-1,-1)
var L2:=Vector2i(-1,-1)
var legacy_jobs:={}
var rate_marks:=[]
var serial:=0
var soup_id:=""
var bread_id:=""
var salad_id:=""
var feed_id:=""

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

## The cooking UI root: app.modal itself or a named descendant of it.
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

## {job id: BaseButton} for every CookingCancel_<id> currently in the UI.
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

func png_texture(t:Texture2D) -> bool:
	if t==null:return false
	if t is AtlasTexture:return png_texture((t as AtlasTexture).atlas)
	if t is ImageTexture:
		var source:=str(t.get_meta("source_png",""))
		return source.get_extension()=="png" and ResourceLoader.exists(source) and not t.get_image().is_invisible()
	return t.resource_path.get_extension().to_lower()=="png"

func same_icon(a:Texture2D,b:Texture2D) -> bool:
	if a==null or b==null:return false
	if a==b:return true
	if a is AtlasTexture and b is AtlasTexture:
		return (a as AtlasTexture).atlas==(b as AtlasTexture).atlas and (a as AtlasTexture).region==(b as AtlasTexture).region
	return false

func inside_recipe(node:Node) -> bool:
	var stop:=ui()
	var n:=node
	while n!=null and n!=stop:
		if str(n.name).begins_with(RECIPE_PREFIX):return true
		n=n.get_parent()
	return false

## Visible textures (TextureRect / Button.icon) inside `node`.
func icons_in(node:Node,skip_recipes:bool=false) -> Array:
	var out:=[]
	if node==null:return out
	for d in [node]+descendants(node):
		if skip_recipes and inside_recipe(d):continue
		if d is TextureRect and d.is_visible_in_tree() and d.texture!=null:out.append(d.texture)
		elif d is Button and d.is_visible_in_tree() and d.icon!=null:out.append(d.icon)
	return out

func shows_icon(icons:Array,want:Texture2D) -> bool:
	for t in icons:
		if same_icon(t,want):return true
	return false

func hud_visible_children() -> Array:
	var out:=[]
	for c in app.hud.get_children():
		# The toast follows its own notice timer, so it is not part of the HUD check.
		if c is Control and c.visible and c!=app.modal and c!=app.modal_shade and c!=app.toast:out.append(c)
	return out

# ------------------------------------------------------------ world helpers --

func stove_obj(c:Vector2i) -> Dictionary:
	var o=w.state.objects.get(World.key(c),{})
	return o if o is Dictionary else {}

func queue_of(c:Vector2i) -> Dictionary:
	var q=stove_obj(c).get("cooking")
	return q if q is Dictionary else {}

func ids_of(list) -> Array:
	var out:=[]
	if list is Array:
		for entry in list:out.append(str(entry.get("id","")))
	return out

func total(q:Dictionary) -> int:
	if q.is_empty():return 0
	return (0 if (q.active as Dictionary).is_empty() else 1)+(q.waiting as Array).size()+(q.ready as Array).size()

func all_jobs(q:Dictionary) -> Array:
	var out:=[]
	if q.is_empty():return out
	if not (q.active as Dictionary).is_empty():out.append(q.active)
	out.append_array(q.waiting)
	out.append_array(q.ready)
	return out

func bag() -> Dictionary:
	var out:={}
	var src:Dictionary=w.state.players[T].inventory
	for item in src:
		if int(src[item])!=0:out[str(item)]=int(src[item])
	return out

func shifted(base:Dictionary,delta:Dictionary,sign:int) -> Dictionary:
	var out:Dictionary=base.duplicate()
	for item in delta:
		out[item]=int(out.get(item,0))+sign*int(delta[item])
		if int(out[item])==0:out.erase(item)
	return out

func cooked() -> int:
	return int(w.state.players[T].get("cooked",0))

func near(c:Vector2i) -> Vector2:
	return Vector2(c)+Vector2(1.5,0.8)

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

## Legal empty 3x1 home site with a two-cell margin, >= 7 cells from `avoid`.
func find_site(w0,avoid:Array) -> Vector2i:
	for oy in range(3,57):
		for ox in range(3,77):
			var far:=true
			for a in avoid:
				if Vector2(ox,oy).distance_to(Vector2(a))<7.0:
					far=false
					break
			if not far:continue
			if site_clear(w0,Vector2i(ox-2,oy-2),Vector2i(7,5)):
				for y in range(oy-2,oy+3):
					for x in range(ox-2,ox+5):
						var c:=Vector2i(x,y)
						if w0.resource(c)!="":w0.state.removed[World.key(c)]=true
				return Vector2i(ox,oy)
	expect(false,"fixture found a legal empty stove site")
	return Vector2i(-1,-1)

func setup_world() -> bool:
	var path:=dir+"/world.json"
	var w0=World.new()
	w0.save_path=path
	w0.add_player(T,"島民")
	w0.add_player(B,"鄰居")
	for t in [T,B]:
		for item in STOCK:w0.state.players[t].inventory[item]=STOCK[item]
	var avoid:Array=[Vector2i(World.SPAWN),Vector2i(40,29),Vector2i(43,29),Vector2i(45,34),Vector2i(54,25),World.COPPER_CELL]
	for resident in Village.ids_for_region("home"):avoid.append(Village.NPCS[resident].cell)
	for candidate in World.SHIPPING.CANDIDATES:avoid.append(candidate)
	for candidate in World.COMMUNITY.CANDIDATES:avoid.append(candidate)
	S=find_site(w0,avoid)
	avoid.append(S)
	L=find_site(w0,avoid)
	avoid.append(L)
	L2=find_site(w0,avoid)
	if S.x<0 or L.x<0 or L2.x<0:return false
	for c in [S,L,L2]:w0.state.objects[World.key(c)]={"type":"stove","owner":T,"items":{}}
	# Legacy single jobs through the real pre-queue path on plain stoves.
	for c in [L,L2]:
		var person:Dictionary=w0.state.players[T]
		person.x=near(c).x
		person.y=near(c).y
		var r:Dictionary=w0.act(T,"fixture-legacy-"+World.key(c),"cook",c,"bread")
		expect(r.get("ok")==true,"fixture: legacy cook on plain stove %s: %s"%[c,r.get("message","")])
		var job=w0.state.objects[World.key(c)].get("job")
		expect(job is Dictionary and not w0.state.objects[World.key(c)].has("cooking"),"fixture: plain stove keeps the legacy single job")
		if job is Dictionary:legacy_jobs[World.key(c)]=job.duplicate(true)
	var tester:Dictionary=w0.state.players[T]
	tester.x=near(S).x
	tester.y=near(S).y
	expect(w0.save(),"fixture world saved")
	# Real load from disk: legacy jobs come back as loaded save state.
	w=World.new()
	var loaded:bool=w.load_world(path)
	expect(loaded,"fixture world re-loaded from disk")
	if not loaded:return false
	w.add_player(T,"島民")
	w.add_player(B,"鄰居")
	for c in [L,L2]:
		var o:=stove_obj(c)
		expect(o.has("job") and not o.has("cooking"),"legacy job loaded from save on %s"%c)
	expect(not stove_obj(S).has("job") and not stove_obj(S).has("cooking"),"queue stove starts plain and empty")
	return true

# ---------------------------------------------------------------- fixture --

func settle(frames:int=4) -> void:
	for i in frames:await process_frame
	if is_instance_valid(app) and app.playing:
		# Main's _process is disabled for determinism; keep its HUD/panel refresh.
		app._refresh_hud()

func sync() -> void:
	app.session._send_snapshot(1)
	await settle()

## Fixture teleport + real snapshot delivery to Main.
func pose(at:Vector2) -> void:
	var person:Dictionary=w.state.players[T]
	person.x=at.x
	person.y=at.y
	await sync()

func set_bag(values:Dictionary) -> void:
	for k in values:w.state.players[T].inventory[k]=values[k]
	await sync()

func advance(seconds:float,why:String) -> void:
	print("FIXTURE %s: world time advanced programmatically by %.3fs (%s); automatic ticks disabled"%[LABEL,seconds,why])
	expect(w.step(seconds,true),"fixture time advance committed (%s)"%why)
	await sync()

## Keeps UI actions under Session's real 12-actions-per-second limit.
func pace() -> void:
	var now:=Time.get_ticks_msec()
	while not rate_marks.is_empty() and now-int(rate_marks[0])>1100:rate_marks.pop_front()
	if rate_marks.size()>=8:
		var wait_ms:=1150-(now-int(rate_marks[0]))
		if wait_ms>0:await create_timer(wait_ms/1000.0).timeout
		now=Time.get_ticks_msec()
		while not rate_marks.is_empty() and now-int(rate_marks[0])>1100:rate_marks.pop_front()
	rate_marks.append(Time.get_ticks_msec())

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

func select(id:String,label:String) -> bool:
	var node_name:=RECIPE_PREFIX+id
	var b:=ctl(node_name) as BaseButton
	expect(shown(b),"%s: recipe button %s present"%[label,node_name])
	if not shown(b):return false
	await reachable(b,"%s: recipe %s"%[label,id])
	b=ctl(node_name) as BaseButton
	if b==null:return false
	expect(not b.disabled,"%s: recipe %s selectable"%[label,id])
	var counter0:=int(app.session.counter)
	if b.toggle_mode:b.button_pressed=true
	b.pressed.emit()
	await settle()
	expect(int(app.session.counter)==counter0,"%s: selecting %s performs no world action"%[label,id])
	var again:=ctl(node_name) as BaseButton
	if again!=null and again.toggle_mode:expect(again.button_pressed,"%s: recipe %s shown as selected"%[label,id])
	return true

## Scrolls every ScrollContainer ancestor to `c`, then requires it fully visible.
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
	expect(ok,"%s: reachable inside the window without clipping (%d scroll ancestors)"%[label,scrolls.size()])
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
	app._cook_menu(c)
	await settle(6)
	var ok:=ui()!=null
	expect(ok,"%s: app._cook_menu(%s) opens a visible %s under app.modal"%[label,c,ROOT_NAME])
	return ok

func neighbour(action:String,c:Vector2i,extra:String) -> Dictionary:
	var person:Dictionary=w.state.players[B]
	person.x=float(c.x)-0.5
	person.y=float(c.y)+0.5
	serial+=1
	var r:Dictionary=w.act(B,"fixture-neighbour-%d"%serial,action,c,extra)
	await sync()
	return r

func progress_ratio() -> float:
	var p:=ctl(PROGRESS)
	if not shown(p) or not p is Range:return -1.0
	var r:=p as Range
	if r.max_value<=r.min_value:return -1.0
	return (r.value-r.min_value)/(r.max_value-r.min_value)

func capacity_text() -> String:
	return text_of(ctl(CAPACITY))

# ------------------------------------------------------------- screenshots --

## Runs `check` at both extents and (with --qa-preview) saves real PNGs.
func shoot(state:String,check:Callable) -> void:
	for extent in EXTENTS:
		root.size=extent
		await settle(4)
		# Neutral screenshot framing. Reachability below still scrolls every item.
		if is_instance_valid(app.modal):
			for node in descendants(app.modal):
				if node is ScrollContainer:node.scroll_vertical=0
			await settle(2)
		if is_instance_valid(app.modal):
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
				var path:=qa_dir.path_join("cooking-%s-%dx%d.png"%[state,extent.x,extent.y])
				var wrote:=image.save_png(path)==OK
				expect(wrote,"saved "+path)
				var back:=Image.load_from_file(path)
				var readable:bool=back!=null and back.get_size()==extent
				expect(readable,"PNG readable at %s"%path)
				if wrote and readable:
					saved_shots["%s-%dx%d"%[state,extent.x,extent.y]]=path
					print("COOKING_UI_SCREENSHOT %s"%path)
		await check.call(label)
	root.size=EXTENTS[0]
	await settle(4)

## Bounded-layout rules shared by every state.
func check_layout(label:String,claim_expected:bool) -> void:
	var r:=ui()
	expect(r!=null,"%s: %s visible"%[label,ROOT_NAME])
	if r==null:return
	var window:=root.get_visible_rect().grow(0.5)
	expect(window.encloses(r.get_global_rect()),"%s: %s inside the window %s"%[label,ROOT_NAME,r.get_global_rect()])
	if is_instance_valid(app.modal):expect(window.encloses(app.modal.get_global_rect()),"%s: modal inside the window"%label)
	var must:=[ENQUEUE,CAPACITY]
	if claim_expected:must.append(CLAIM)
	var rects:=[]
	for node_name in [ENQUEUE,CLAIM,CAPACITY,STATUS]:
		var c:=ctl(node_name)
		if node_name in must:expect(shown(c),"%s: %s visible"%[label,node_name])
		if not shown(c):continue
		var g:=c.get_global_rect()
		if c is BaseButton:expect(g.size.x>=16 and g.size.y>=16,"%s: %s has a usable size %s"%[label,node_name,g.size])
		expect(r.get_global_rect().grow(0.5).encloses(g),"%s: %s inside %s"%[label,node_name,ROOT_NAME])
		expect(in_view(c),"%s: %s inside the window"%[label,node_name])
		expect(unclipped(c),"%s: %s not clipped by a scroll region"%[label,node_name])
		if node_name!=STATUS:
			for other in rects:
				expect(not g.grow(-1.0).intersects(other[1].grow(-1.0)),"%s: %s does not overlap %s"%[label,node_name,other[0]])
			rects.append([node_name,g])
	for id in World.RECIPES:
		var b:=ctl(RECIPE_PREFIX+id)
		expect(b!=null,"%s: recipe %s listed"%[label,id])
		if b!=null:await reachable(b,"%s: recipe %s"%[label,id])
	var cancels:=cancel_buttons()
	for id in cancels:
		if is_instance_valid(cancels[id]) and (cancels[id] as Control).is_visible_in_tree():await reachable(cancels[id],"%s: cancel %s"%[label,id])

# -------------------------------------------------------------------- run --

func run() -> void:
	print("COOKING_UI fixture=%s user_data_dir=%s"%[LABEL,OS.get_user_data_dir()])
	var isolated:=OS.get_environment("COOKING_UI_ISOLATED")
	if not isolated.is_empty():
		var user_dir:=OS.get_user_data_dir().replace("\\","/").to_lower()
		var sandbox:=isolated.replace("\\","/").to_lower()
		expect(user_dir.begins_with(sandbox),"user:// lives under the runner's isolated APPDATA (%s)"%OS.get_user_data_dir())
	dir="user://test-cooking-queue-ui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
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
	# Deterministic fixture: Main's OS polling loop off; Control input still runs.
	app.set_process(false)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=EXTENTS[0]
	var session=app.session
	# Automatic world ticks / broadcasts off; time only moves through advance().
	session.set_physics_process(false)
	# Only feeds profile-derived paths; the real profile token is never used.
	session.profile={"token":"cook-ui-isolated-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]}
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
		await flow_empty_error()
		await flow_legacy()
		await flow_enqueue_cancel()
		await flow_ready_claim()
		await flow_full()
		await flow_reply_matching()
		await flow_keys_hud()
		await flow_classic_route()
	await finish()

# ------------------------------------------------------------------ flows --

func flow_open() -> bool:
	await pose(near(S))
	var before:=hud_visible_children()
	expect(not before.is_empty(),"HUD shows world controls before opening")
	# Real interact path (E) near the stove -> Main._cook_menu(cell).
	app._interact()
	await settle(6)
	expect(ui()!=null,"interact next to the stove opens %s"%ROOT_NAME)
	if ui()==null:
		app._close_modal()
		app._cook_menu(S)
		await settle(6)
	var opened:=ui()!=null
	expect(opened,"MISSING API: app._cook_menu(cell) -> CookingUI.open(app,cell) produced no visible '%s' under app.modal"%ROOT_NAME)
	if not opened:return false
	for c in before:expect(not c.visible,"HUD control %s hidden under the cooking UI"%c.name)
	return true

func flow_empty_error() -> void:
	var ids:Array=World.RECIPES.keys()
	var expected_recipes:=World.RECIPES.keys()
	expect(ids.size()==expected_recipes.size() and expected_recipes.all(func(id):return ids.has(id)),"all recipes in the catalog (got %d)"%ids.size())
	var counter0:=int(app.session.counter)
	var state0:=var_to_str(w.state)
	for id in ids:
		var b:=ctl(RECIPE_PREFIX+id)
		expect(b is BaseButton,"recipe %s is a button"%id)
		if b==null:continue
		var icons:=icons_in(b)
		var png:=false
		for t in icons:png=png or png_texture(t)
		expect(png,"recipe %s shows a PNG icon"%id)
		expect(shows_icon(icons,ItemArt.icon(id)),"recipe %s shows its own item icon"%id)
	for id in ids:
		if not await select(id,"empty"):continue
		var recipe:Dictionary=World.RECIPES[id]
		var detail:=text_of(ui())
		var outside:=icons_in(ui(),true)
		for item in recipe.ingredients:
			expect(has_number(detail,int(recipe.ingredients[item])),"%s: ingredient %s count %d shown"%[id,item,int(recipe.ingredients[item])])
			expect(shows_icon(outside,ItemArt.icon(item)),"%s: ingredient %s icon shown"%[id,item])
		var enq:=ctl(ENQUEUE) as BaseButton
		expect(shown(enq) and not enq.disabled,"%s: enqueue enabled with enough materials"%id)
	expect(int(app.session.counter)==counter0 and var_to_str(w.state)==state0,"browsing recipes never changes the world")
	expect(cancel_buttons().is_empty(),"empty: no job cancel controls")
	var claim:=ctl(CLAIM) as BaseButton
	expect(claim==null or not claim.is_visible_in_tree() or claim.disabled,"empty: nothing to claim")
	expect(has_number(capacity_text(),0) and has_number(capacity_text(),Queue.CAPACITY),"empty: capacity shows 0 of %d ('%s')"%[Queue.CAPACITY,capacity_text()])
	await select("soup","empty")
	await shoot("empty",func(l):await check_layout(l,false))
	# Missing materials.
	var objects0:=var_to_str(w.state.objects)
	var zero:={}
	for item in STOCK:zero[item]=0
	await set_bag(zero)
	for id in ids:
		if not await select(id,"error"):continue
		var enq:=ctl(ENQUEUE) as BaseButton
		expect(enq==null or not enq.is_visible_in_tree() or enq.disabled,"%s: enqueue unavailable without materials"%id)
	await select("soup","error")
	var error_check:=func(l):
		await check_layout(l,false)
		var status:=ctl(STATUS)
		expect(shown(status) and not text_of(status).strip_edges().is_empty(),"%s: %s explains the missing materials"%[l,STATUS])
		var enq:=ctl(ENQUEUE) as BaseButton
		expect(enq==null or enq.disabled or not enq.is_visible_in_tree(),"%s: enqueue disabled"%l)
	await shoot("error",error_check)
	expect(var_to_str(w.state.objects)==objects0 and int(app.session.counter)==counter0,"missing materials: no request sent, stoves untouched")
	await set_bag(STOCK)
	await select("soup","restock")
	var enq2:=ctl(ENQUEUE) as BaseButton
	expect(shown(enq2) and not enq2.disabled,"enqueue re-enabled after restocking")

func flow_legacy() -> void:
	if not await open_at(L,"legacy"):return
	var snap_obj:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(L),{})
	expect(snap_obj.has("job") and not snap_obj.has("cooking"),"legacy: Session shows the loaded single job")
	var usable:=usable_cancels()
	expect(usable.size()==1,"legacy: exactly one usable cancel control for the own legacy job (%d)"%usable.size())
	expect(stove_obj(L).has("job") and not stove_obj(L).has("cooking"),"legacy: viewing does not convert the stove")
	var legacy_check:=func(l):
		await check_layout(l,false)
		expect(shown(ctl(PROGRESS)),"%s: legacy job progress shown"%l)
		expect(usable_cancels().size()==1,"%s: legacy cancel still offered"%l)
	await shoot("legacy",legacy_check)
	# First enqueue imports the legacy job without charging it again.
	var job:Dictionary=legacy_jobs.get(World.key(L),{})
	var inv0:=bag()
	await select("soup","legacy import")
	if not await press(ENQUEUE,"legacy import"):return
	var q:=queue_of(L)
	expect(not stove_obj(L).has("job") and total(q)==2,"legacy import: queue holds imported job + soup (total %d)"%total(q))
	var imported:Dictionary={}
	for entry in all_jobs(q):
		if str(entry.kind)==str(job.get("kind","")) and imported.is_empty():imported=entry
	var deadline:=float(imported.get("finish",imported.get("completed",-1.0)))
	expect(not imported.is_empty() and absf(deadline-float(job.get("ready",-2.0)))<=TOL,"legacy import keeps the original deadline")
	expect(not imported.is_empty() and imported.get("ingredients")==job.get("ingredients") and str(imported.get("owner"))==T,"legacy import keeps owner and ingredients")
	var soup_jobs:=all_jobs(q).filter(func(e):return str(e.kind)=="soup")
	expect(soup_jobs.size()==1,"legacy import: new soup queued")
	expect(bag()==shifted(inv0,World.RECIPES.soup.ingredients,-1),"legacy import charged only the new soup")
	await settle()
	expect(shown(ctl(PROGRESS)),"imported queue shows progress")
	# Legacy cancel on the second loaded stove.
	if not await open_at(L2,"legacy cancel"):return
	var job2:Dictionary=legacy_jobs.get(World.key(L2),{})
	var cancels:=usable_cancels()
	expect(cancels.size()==1,"legacy cancel: one usable cancel control")
	if cancels.size()!=1:return
	var inv1:=bag()
	var cooked0:=cooked()
	if not await press(str((cancels.values()[0] as Node).name),"legacy cancel"):return
	var o:=stove_obj(L2)
	expect(not o.has("job") and total(queue_of(L2))==0,"legacy cancel removed the single job")
	expect(bag()==shifted(inv1,job2.get("ingredients",{}),1),"legacy cancel refunded the original ingredients exactly")
	expect(cooked()==cooked0,"legacy cancel never counts as cooked")

func flow_enqueue_cancel() -> void:
	if not await open_at(S,"enqueue"):return
	var inv0:=bag()
	await select("soup","enqueue soup")
	if not await press(ENQUEUE,"enqueue soup"):return
	var q:=queue_of(S)
	expect(total(q)==1 and str(q.active.get("kind",""))=="soup" and str(q.active.get("owner",""))==T,"first enqueue starts soup")
	soup_id=str(q.active.get("id",""))
	expect(bag()==shifted(inv0,World.RECIPES.soup.ingredients,-1),"enqueue charged soup ingredients once")
	await select("bread","enqueue bread")
	await press(ENQUEUE,"enqueue bread")
	q=queue_of(S)
	expect(total(q)==2 and str((q.waiting as Array).back().kind)=="bread","bread waits behind soup")
	if total(q)==2:bread_id=str((q.waiting as Array).back().id)
	# Current recipe selection survives snapshot / HUD refreshes and a time tick.
	await select("salad","selection")
	for i in 3:await sync()
	app.session.changed.emit(app.session.snapshot,app.session.own_id)
	await settle()
	await advance(0.5,"refresh churn while salad selected")
	await press(ENQUEUE,"enqueue after refresh")
	q=queue_of(S)
	var last:Dictionary=(q.waiting as Array).back() if not (q.waiting as Array).is_empty() else {}
	expect(str(last.get("kind",""))=="salad","selected recipe (salad) kept across refresh and enqueued")
	salad_id=str(last.get("id",""))
	# Another contributor's job: visible, not cancellable here.
	var r:Dictionary=await neighbour("queue_cook",S,"feed")
	expect(r.get("ok")==true,"fixture: neighbour enqueues feed: %s"%r.get("message",""))
	feed_id=str(r.get("id",""))
	await settle()
	var all:=cancel_buttons()
	for id in [soup_id,bread_id,salad_id]:
		expect(all.has(id) and (all[id] as BaseButton).is_visible_in_tree() and not (all[id] as BaseButton).disabled,"own job %s cancellable by exact id"%id.left(8))
	expect(not usable_cancels().has(feed_id),"neighbour's job offers no usable cancel")
	expect(has_number(capacity_text(),4) and has_number(capacity_text(),Queue.CAPACITY),"capacity shows 4 of %d ('%s')"%[Queue.CAPACITY,capacity_text()])
	var p0:=progress_ratio()
	expect(p0>=0.0 and p0<1.0,"active progress is a Range below complete (%.3f)"%p0)
	await advance(3.0,"progress movement")
	var p1:=progress_ratio()
	expect(p1>p0,"progress advances with world time (%.3f -> %.3f)"%[p0,p1])
	var active_check:=func(l):
		await check_layout(l,false)
		expect(shown(ctl(PROGRESS)),"%s: progress shown"%l)
		expect(usable_cancels().size()==3 and not usable_cancels().has(feed_id),"%s: three own cancels, none for the neighbour"%l)
	await shoot("active",active_check)
	# Cancel exactly the middle (waiting) job.
	var inv1:=bag()
	if not await press(CANCEL_PREFIX+bread_id,"cancel bread"):return
	q=queue_of(S)
	expect(str(q.active.get("id",""))==soup_id and ids_of(q.waiting)==[salad_id,feed_id],"cancel removed exactly the bread job")
	expect(bag()==shifted(inv1,World.RECIPES.bread.ingredients,1),"cancel refunded bread ingredients exactly")
	expect(not cancel_buttons().has(bread_id),"cancelled job leaves the UI")

func flow_ready_claim() -> void:
	var q:=queue_of(S)
	if total(q)!=3 or (q.waiting as Array).is_empty():
		expect(false,"ready flow precondition: soup active, salad + feed waiting")
		return
	var salad:Dictionary=q.waiting[0]
	var dt:=float(q.active.finish)+float(salad.duration)-float(w.state.time)+0.25
	await advance(dt,"complete soup and salad")
	q=queue_of(S)
	expect(ids_of(q.ready)==[soup_id,salad_id] and str(q.active.get("id",""))==feed_id,"soup and salad ready in order; neighbour feed active")
	var ready_check:=func(l):
		await check_layout(l,true)
		var c:=ctl(CLAIM) as BaseButton
		expect(shown(c) and not c.disabled,"%s: claim available"%l)
		expect(not usable_cancels().has(soup_id) and not usable_cancels().has(salad_id),"%s: ready food is not cancellable"%l)
	await shoot("ready",ready_check)
	var inv0:=bag()
	var cooked0:=cooked()
	var soup_yield:=int(q.ready[0]["yield"])
	if not await press(CLAIM,"claim"):return
	q=queue_of(S)
	expect(ids_of(q.ready)==[salad_id],"one claim took exactly the oldest ready job")
	expect(bag()==shifted(inv0,{"soup":soup_yield},1),"claim added soup x%d only"%soup_yield)
	expect(cooked()==cooked0+1,"claim counted once as cooked")
	var c2:=ctl(CLAIM) as BaseButton
	expect(shown(c2) and not c2.disabled,"claim still offered for the remaining ready salad")

func flow_full() -> void:
	var ids:Array=World.RECIPES.keys()
	var q:=queue_of(S)
	var need:=Queue.CAPACITY-total(q)
	expect(need==8,"full flow precondition: 2 jobs before filling (got %d)"%total(q))
	for i in maxi(0,need):
		await select(str(ids[i%ids.size()]),"fill %d"%i)
		if not await press(ENQUEUE,"fill %d"%i):break
	q=queue_of(S)
	expect(total(q)==Queue.CAPACITY and ids_of(q.ready).has(salad_id),"queue full at %d including ready salad"%Queue.CAPACITY)
	var own_waiting:=[]
	for entry in q.waiting:
		if str(entry.owner)==T:own_waiting.append(str(entry.id))
	var full_check:=func(l):
		await check_layout(l,true)
		var enq:=ctl(ENQUEUE) as BaseButton
		expect(enq==null or enq.disabled or not enq.is_visible_in_tree(),"%s: enqueue disabled when full"%l)
		expect(has_number(capacity_text(),Queue.CAPACITY),"%s: capacity shows %d ('%s')"%[l,Queue.CAPACITY,capacity_text()])
		var usable:=usable_cancels()
		for id in own_waiting:expect(usable.has(id),"%s: own waiting job %s reachable and cancellable"%[l,id.left(8)])
		expect(not usable.has(feed_id) and not usable.has(salad_id),"%s: neighbour/ready jobs not cancellable"%l)
		for id in usable:await reachable(usable[id],"%s: queue entry %s"%[l,id.left(8)])
	await shoot("full",full_check)
	# A forced extra request through Session is refused by World atomically.
	await pace()
	var inv0:=bag()
	var objects0:=var_to_str(w.state.objects)
	app.session.perform("queue_cook",S,"soup")
	await settle()
	expect(bag()==inv0 and var_to_str(w.state.objects)==objects0,"eleventh request refused without charge")

func flow_reply_matching() -> void:
	# Inject one pending UI intent only; no synthetic server success or grant.
	var controller=app.modal.get_meta("cooking_queue",null)
	expect(controller!=null,"cooking controller available for reply correlation")
	if controller==null:return
	controller.pending={"sequence":9000,"action":"queue_cook","extra":"soup","host":false,"at":Time.get_ticks_msec()}
	app.session.notice.emit("世界節慶開始了",true)
	expect(not controller.pending.is_empty(),"unrelated notice cannot release pending cooking")
	app.session.action_completed.emit(8999,"queue_cook",{"ok":true,"message":"stale"})
	expect(not controller.pending.is_empty(),"stale sequence cannot release pending cooking")
	app.session.action_completed.emit(9000,"claim_cook",{"ok":true,"message":"wrong action"})
	expect(not controller.pending.is_empty(),"different action cannot release pending cooking")
	app.session.action_completed.emit(9000,"queue_cook",{"ok":false,"message":"測試拒絕，沒有扣料"})
	expect(controller.pending.is_empty(),"matching response releases pending cooking")
	expect(text_of(ctl(STATUS)).contains("測試拒絕"),"matched error remains readable")
	await settle()

func flow_keys_hud() -> void:
	app._close_modal()
	await settle()
	var before:=hud_visible_children()
	if not await open_at(S,"keys"):return
	for c in before:expect(not c.visible,"keys: HUD control %s hidden while cooking"%c.name)
	await press_key(KEY_TAB)
	expect(ui()!=null,"Tab does not replace the open cooking UI with the backpack")
	await press_key(KEY_ESCAPE)
	expect(app.modal==null and ui()==null,"Esc closes the cooking UI")
	for c in before:expect(is_instance_valid(c) and c.visible,"HUD control %s restored after Esc"%c.name)
	await press_key(KEY_TAB)
	expect(app.modal!=null and ui()==null,"Tab still opens the backpack")
	await press_key(KEY_TAB)
	expect(app.modal==null,"Tab closes the backpack")

func flow_classic_route() -> void:
	app._close_modal()
	app.queue_free()
	for i in 3:await process_frame
	# Construct the classic HUD normally; flipping the flag on a preview HUD
	# leaves its classic objective/status controls uninitialised.
	app=load("res://main.tscn").instantiate()
	app.village_art_preview=false
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.profile={"token":"cook-classic-isolated-%d"%OS.get_process_id()}
	app.session.world=w
	app.session._attach_registered(1,T)
	await settle(6)
	var before:=hud_visible_children()
	app._cook_menu(S)
	await settle(6)
	expect(ui()!=null,"classic HUD opens the same cooking workbench")
	for c in before:expect(not c.visible,"classic HUD hidden while cooking")
	await shoot("classic",func(l):await check_layout(l,true))
	app._close_modal()
	for c in before:expect(c.visible,"classic HUD restored after cooking")
	await settle()

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
		print("COOKING_UI retained failing fixture world: %s"%("failed-world.json" if copied else "copy failed"))
	remove_tree(dir)
	if not dir.is_empty():expect(not DirAccess.dir_exists_absolute(dir),"isolated test directory removed")
	print("COOKING_QUEUE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func remove_tree(path:String) -> void:
	if not path.begins_with("user://test-cooking-queue-ui-"):return
	if not DirAccess.dir_exists_absolute(path):return
	for sub in DirAccess.get_directories_at(path):remove_tree(path+"/"+sub)
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+f)
	DirAccess.remove_absolute(path)
