extends SceneTree
## Native UI test for the blueprint client (docs/blueprint-client-contract.md,
## 「藍圖冊與施工資訊」「素材預覽」「Main 接線」「驗收」).
##
## Instantiates the ACTUAL main.tscn in village-art preview mode (same convention
## as test_build_folio.gd) with a REAL Session host and a REAL, isolated World.
## The island is entered through Session._attach_registered(1) ->
## connected_world -> Main._entered, and every snapshot reaches Main through the
## real Session.changed signal.
##
## FIXTURE, NOT HUMAN PLAY. The script programmatically:
##  * seeds materials, A's floors / bench / automatic roof, and a neighbour's
##    floors (collision) directly into the World and teleports the player;
##  * injects a fake blueprint_clock so Session rate limits never stall;
##  * presses UI buttons by emitting `pressed`, types into LineEdits by setting
##    `text`, and pushes synthetic mouse / key events through the root viewport;
##  * disables Main's OS-cursor polling and calls its blueprint frame method
##    with each synthetic pointer position (the OS pointer is not warped);
##  * writes one explicitly SIMULATED unknown pending record (unknown state).
## Library / pending / world files live in one per-run user:// directory that is
## removed at the end. Main's controller is re-pointed (dispose + setup) to that
## directory right after _entered; the profile token used for Main's default
## library-path hash is replaced by a unique throwaway value first, so no real
## blueprint library is ever written.
##
## Optional native capture: --qa-preview --qa-output=<ABSOLUTE DIR> saves PNGs at
## 1024x640 and 1280x800 for every state (requires a rendering, non-headless run).
## Missing API / controls and every skipped step are counted failures.

const World=preload("res://scripts/world.gd")
const Library=preload("res://scripts/blueprint_library.gd")
const REGIONS=preload("res://scripts/regions.gd")
const THUMB_PATH:="res://scripts/blueprint_thumbnail.gd"
const EXTENTS:=[Vector2i(1024,640),Vector2i(1280,800)]
const LAYOUT:="blueprint_folio"
const FOLIO_MAX:=Vector2(900,560)
const T:="tok-ui-tester-SECRET-blueprint"
const B:="tok-ui-neighbour-SECRET-bp"
const PARK:=World.SPAWN
const NODE_CAP:=6000
## Control lookup: node name first, then visible Button text containing a keyword.
const FIND:={
	"book":[["BlueprintBook"],["藍圖冊"]],
	"capture":[["BlueprintCapture"],["框選"]],
	"primary":[["BlueprintPrimary"],["存入藍圖冊","放到地圖上"]],
	"name":[["BlueprintCaptureName"],[]],
	"rename":[["BlueprintRenameToggle"],["重新命名"]],
	"rename_edit":[["BlueprintNameEdit"],[]],
	"rename_save":[["BlueprintRenameSave"],["儲存名稱"]],
	"delete":[["BlueprintDelete"],["刪除"]],
	"delete_yes":[["BlueprintDeleteYes"],["確定刪除"]],
	"rotate":[["BlueprintRotate"],["旋轉"]],
	"reposition":[["BlueprintReposition"],["換位置"]],
	"quote":[["BlueprintQuote"],["估價","報價"]],
	"confirm":[["BlueprintConfirm"],["確認施工"]],
	"retry":[["BlueprintRetry"],["重新查詢","重試"]],
	"cancel":[["BlueprintCancel"],["取消"]],
}

class Ticks extends RefCounted:
	var ms:int=7000000
	func now() -> int:return ms

var checks:=0
var failures:=0
var app
var w
var ctrl
var dir:=""
var lib:=""
var scope:=""
var bclock:Ticks
var qa:=false
var qa_dir:=""
var src:=Vector2i(-1,-1)
var clash:=Vector2i(-1,-1)
var site1:=Vector2i(-1,-1)
var site2:=Vector2i(-1,-1)
var own:=""
var default_library:=""

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
	for d in [node]+descendants(node,800):
		if (d is Label or d is Button or d is RichTextLabel) and d.is_visible_in_tree() and not str(d.text).is_empty():parts.append(str(d.text))
	return "\n".join(parts)

func has_number(text:String,value:int) -> bool:
	var regex:=RegEx.new()
	regex.compile("(?<!\\d)%d(?!\\d)"%value)
	return regex.search(text)!=null

func strip() -> Control:
	var node=app.get("blueprint_strip")
	return node as Control if node is Control else null

func layout() -> String:
	return str(app.modal.get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

## Visible control by FIND key inside `scope_node` (modal / strip / hud).
func find(key:String,scope_node:Node) -> Control:
	if scope_node==null:return null
	var spec:Array=FIND[key]
	for node_name in spec[0]:
		var hit:=scope_node.find_child(node_name,true,false) as Control
		if hit!=null and hit.is_visible_in_tree():return hit
	for d in descendants(scope_node):
		if d is Button and d.is_visible_in_tree():
			for word in spec[1]:
				if str(d.text).contains(word):return d
	return null

## Presses a real UI button through its signal (programmatic, not manual play).
func press(key:String,scope_node:Node,label:String) -> bool:
	var b:=find(key,scope_node) as Button
	expect(b!=null,"%s: control '%s' present and visible"%[label,key])
	if b==null:return false
	expect(not b.disabled,"%s: control '%s' enabled"%[label,key])
	if b.disabled:return false
	b.pressed.emit()
	await settle()
	return true

func thumbs_in(node:Node) -> Array:
	var out:=[]
	for d in descendants(node):
		var sc:Script=d.get_script()
		while sc!=null:
			if sc.resource_path==THUMB_PATH:
				out.append(d)
				break
			sc=sc.get_base_script()
	return out

# ---------------------------------------------------------------- fixture --

func settle(frames:int=4) -> void:
	for i in frames:await process_frame
	if is_instance_valid(app) and app.playing:
		# Main's frame loop is disabled only for deterministic pointer input;
		# explicitly keep its normal HUD refresh for representative screenshots.
		app._refresh_hud()
		app._blueprint_sync()

func wait(seconds:float) -> void:
	await create_timer(seconds).timeout
	await settle(2)

func tick() -> void:
	bclock.ms+=2000

func pending_path() -> String:
	return lib+".pending-"+scope.sha256_text().left(16)+".json"

func clear_cell(c:Vector2i) -> bool:
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":return false
	var k:=World.key(c)
	for f in ["objects","ground","roofs","crops","forest"]:
		if w.state[f].has(k):return false
	return true

func site_ok(o:Vector2i,size:Vector2i) -> bool:
	for y in range(o.y,o.y+size.y):
		if not clear_cell(Vector2i(o.x-1,y)):return false
		for x in range(o.x,o.x+size.x):
			if not clear_cell(Vector2i(x,y)):return false
	return true

func zone(o:Vector2i,size:Vector2i) -> Rect2i:
	return Rect2i(o-Vector2i(4,4),size+Vector2i(8,8))

func find_site(size:Vector2i,avoid:Array) -> Vector2i:
	for oy in range(4,REGIONS.SIZE.y-size.y-4):
		for ox in range(5,REGIONS.SIZE.x-size.x-4):
			var o:=Vector2i(ox,oy)
			var z:=zone(o,size)
			if z.has_point(Vector2i(PARK)):continue
			var hit:=false
			for r in avoid:
				if z.intersects(r):
					hit=true
					break
			if not hit and site_ok(o,size):return o
	expect(false,"found a naturally clear %s home site"%size)
	return Vector2i(-1,-1)

## Fixture teleport + real snapshot delivery to Main.
func pose(at:Vector2) -> void:
	var person:Dictionary=w.state.players[T]
	person.x=at.x
	person.y=at.y
	app.session._send_snapshot(1)
	await wait(0.3)

func set_bag(values:Dictionary) -> void:
	for k in values:w.state.players[T].inventory[k]=values[k]
	app.session._send_snapshot(1)
	await settle()

func cell_screen(c:Vector2i) -> Vector2:
	var view=app.view
	return ((Vector2(c)+Vector2(0.5,0.5))*32.0-view.camera)*view.view_zoom()

func aim(c:Vector2i,buttons:int=0) -> Vector2:
	var p:=cell_screen(c)
	expect(app.view.to_cell(p)==c,"screen mapping round-trips cell %s"%c)
	var e:=InputEventMouseMotion.new()
	e.position=p
	e.global_position=p
	e.button_mask=buttons
	root.push_input(e)
	# Synthetic viewport events do not move the OS cursor read by Main._process.
	# Drive that same blueprint frame method explicitly with this fixture point.
	app._blueprint_process(p)
	return p

func click_at(p:Vector2,release_at:Variant=null) -> void:
	var down:=InputEventMouseButton.new()
	down.button_index=MOUSE_BUTTON_LEFT
	down.pressed=true
	down.button_mask=MOUSE_BUTTON_MASK_LEFT
	down.position=p
	down.global_position=p
	root.push_input(down)
	await settle(2)
	var q:Vector2=p if release_at==null else release_at
	var up:=InputEventMouseButton.new()
	up.button_index=MOUSE_BUTTON_LEFT
	up.pressed=false
	up.position=q
	up.global_position=q
	root.push_input(up)
	await settle()

func key(code:Key) -> void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code
		e.physical_keycode=code
		e.pressed=pressed
		root.push_input(e)
	await settle()

func built_at(o:Vector2i) -> bool:
	for y in 2:
		for x in 2:
			var g=w.state.ground.get(World.key(o+Vector2i(x,y)))
			if not (g is Dictionary and g.get("type")=="floor" and g.get("owner")==T):return false
	var bench=w.state.objects.get(World.key(o+Vector2i(1,0)))
	return bench is Dictionary and bench.get("type")=="bench" and bench.get("owner")==T

func setup_world() -> void:
	w=World.new()
	w.save_path=dir+"/world.json"
	w.add_player(T,"島民")
	w.add_player(B,"鄰居")
	# Explicit fixture stock, not normal-play balances.
	w.state.players[T].inventory={"wood":400,"stone":160,"fiber":200}
	src=find_site(Vector2i(2,2),[])
	clash=find_site(Vector2i(3,3),[zone(src,Vector2i(2,2))])
	site1=find_site(Vector2i(3,3),[zone(src,Vector2i(2,2)),zone(clash,Vector2i(3,3))])
	site2=find_site(Vector2i(3,3),[zone(src,Vector2i(2,2)),zone(clash,Vector2i(3,3)),zone(site1,Vector2i(3,3))])
	if src.x>=0:
		for y in 2:
			for x in 2:w.state.ground[World.key(src+Vector2i(x,y))]={"type":"floor","owner":T,"items":{}}
		w.state.objects[World.key(src+Vector2i(1,0))]={"type":"bench","owner":T,"items":{}}
		w.state.roofs[World.key(src+Vector2i(0,1))]={"type":"roof","owner":T,"auto":true,"items":{}}
	if clash.x>=0:
		for y in 3:
			for x in 3:w.state.ground[World.key(clash+Vector2i(x,y))]={"type":"floor","owner":B,"items":{}}
	w.state.players[T].x=float(src.x)-0.5
	w.state.players[T].y=float(src.y)+0.5
	expect(w.save(),"isolated fixture world saved")

# ------------------------------------------------------------- screenshots --

## Verifies `check` at both extents and (with --qa-preview) saves real PNGs.
## `reaim` re-points the mouse after each resize (camera depends on size).
func shoot(state:String,check:Callable,reaim:Callable=Callable()) -> void:
	for extent in EXTENTS:
		root.size=extent
		await settle(4)
		if reaim.is_valid():
			reaim.call()
			await settle(3)
		if is_instance_valid(app.modal):
			for i in 30:
				if app.modal.modulate.a>=1.0:break
				await process_frame
		check.call("%s %dx%d"%[state,extent.x,extent.y])
		if not qa:continue
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		var good:bool=image!=null and not image.is_empty() and image.get_size()==extent
		expect(good,"%s: rendered frame captured at %s"%[state,extent])
		if not good:continue
		var colors:={}
		for gy in 20:
			for gx in 32:colors[image.get_pixel(int((gx+0.5)*extent.x/32.0),int((gy+0.5)*extent.y/20.0)).to_html()]=true
		expect(colors.size()>=12,"%s: frame is an actual render (%d sampled colours)"%[state,colors.size()])
		var path:=qa_dir.path_join("blueprint-%s-%dx%d.png"%[state,extent.x,extent.y])
		expect(image.save_png(path)==OK,"saved "+path)
		var back:=Image.load_from_file(path)
		expect(back!=null and back.get_size()==extent,"PNG readable at %s"%path)
	root.size=EXTENTS[0]
	await settle(4)
	if reaim.is_valid():
		reaim.call()
		await settle(3)

func in_view(c:Control) -> bool:
	return root.get_visible_rect().grow(0.5).encloses(c.get_global_rect())

func unclipped(c:Control) -> bool:
	var ancestor := c.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			if not ancestor.get_global_rect().grow(0.5).encloses(c.get_global_rect()):return false
		ancestor = ancestor.get_parent()
	return true

func check_controls(label:String,container:Control,keys:Array,enabled:Dictionary={}) -> void:
	expect(container!=null and container.is_visible_in_tree() and in_view(container),"%s: container visible inside the window"%label)
	if container==null:return
	var rects:=[]
	for k in keys:
		var c:=find(k,container)
		var shown:=c!=null and c.is_visible_in_tree()
		expect(shown,"%s: %s visible"%[label,k])
		if not shown:continue
		var r:=c.get_global_rect()
		expect(r.size.x>=16 and r.size.y>=16,"%s: %s has a usable size %s"%[label,k,r.size])
		expect(in_view(c) and container.get_global_rect().grow(0.5).encloses(r),"%s: %s inside its panel and the window"%[label,k])
		expect(unclipped(c),"%s: %s is not hidden behind a scroll clip"%[label,k])
		if enabled.has(k) and c is BaseButton:
			expect((c as BaseButton).disabled==not bool(enabled[k]),"%s: %s %s"%[label,k,"enabled" if enabled[k] else "disabled"])
		for other in rects:
			expect(not r.grow(-1.0).intersects(other[1].grow(-1.0)),"%s: %s does not overlap %s"%[label,k,other[0]])
		rects.append([k,r])

func check_folio(label:String,keys:Array,enabled:Dictionary={}) -> void:
	expect(is_instance_valid(app.modal) and layout()==LAYOUT,"%s: blueprint folio open (layout=%s)"%[label,layout()])
	if not is_instance_valid(app.modal):return
	var r:Rect2=app.modal.get_global_rect()
	expect(r.size.x<=FOLIO_MAX.x+0.5 and r.size.y<=FOLIO_MAX.y+0.5,"%s: folio at most 900x560 (%s)"%[label,r.size])
	check_controls(label,app.modal,keys,enabled)
	var s:=strip()
	expect(s==null or not s.is_visible_in_tree(),"%s: strip hidden under the folio"%label)

func check_strip(label:String,keys:Array,enabled:Dictionary={}) -> void:
	var s:=strip()
	if s!=null and app.toast.visible:
		expect(not s.get_global_rect().intersects(app.toast.get_global_rect()),"%s: feedback does not overlap blueprint strip"%label)
	expect(not is_instance_valid(app.modal),"%s: no modal over the strip"%label)
	check_controls(label,s,keys,enabled)
	if s==null:return
	var r:=s.get_global_rect()
	expect(app._world_pointer_allowed(r.get_center())==false,"%s: strip is inside the pointer gate"%label)
	for k in keys:
		var c:=find(k,s)
		if c!=null:expect(app._world_pointer_allowed(c.get_global_rect().get_center())==false,"%s: %s blocks ground clicks"%[label,k])
	# The player is drawn at window centre + (0,40); that ground stays clickable.
	var free_spot:=root.get_visible_rect().size*0.5+Vector2(0,40)
	expect(not r.has_point(free_spot) and app._world_pointer_allowed(free_spot),"%s: strip leaves the ground around the player clickable"%label)
	expect(app.hud.is_visible_in_tree(),"%s: HUD still shown"%label)

# -------------------------------------------------------------------- run --

func run() -> void:
	dir="user://test-blueprint-client-ui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var made:=DirAccess.make_dir_recursive_absolute(dir)==OK
	expect(made,"isolated test directory created")
	if not made:
		finish()
		return
	lib=dir+"/library.json"
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
	# Deterministic pointer fixture; Control input and World/View still run.
	app.set_process(false)
	expect(app._blueprint_address_scope("wss://Example.test/IslandA",1)!=app._blueprint_address_scope("wss://example.test/islanda",1),"case-sensitive WebSocket routes have separate pending scopes")
	expect(app._blueprint_address_scope("WSS://Example.test/IslandA",1)==app._blueprint_address_scope("wss://example.test/IslandA",2),"host/scheme case and ignored WS port do not split a world scope")
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=EXTENTS[0]
	bclock=Ticks.new()
	var session=app.session
	session.set_physics_process(false)
	session.set("blueprint_clock",Callable(bclock,"now"))
	# Only feeds Main's default library-path hash; real profile token never used.
	session.profile={"token":"ui-isolated-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]}
	default_library="user://blueprints-%s.json"%str(session.profile.token).sha256_text().left(16)
	setup_world()
	session.world=w
	session._attach_registered(1,T)
	await settle(6)
	own=T.sha256_text().left(16)
	expect(app.playing and not app.menu.visible and app.hud.visible,"entered through Session.connected_world -> Main._entered")
	expect(session.own_id==own,"Main session holds the public own_id")
	ctrl=app.get("blueprints")
	var wired:bool=ctrl is Node and ctrl.has_method("setup") and app.get("blueprint_overlay") is Node2D and strip()!=null
	expect(wired,"Main created blueprints / blueprint_overlay / blueprint_strip")
	if not wired or src.x<0 or clash.x<0 or site1.x<0 or site2.x<0:
		expect(false,"UI flow cannot continue (wiring or fixture sites missing)")
		await finish()
		return
	var tool_list:Array=app.TOOL_ACTIONS
	expect(not tool_list.has("blueprints") and not tool_list.has("blueprint"),"blueprints not added to TOOL_ACTIONS")
	scope=str(app.call("_blueprint_scope")) if app.has_method("_blueprint_scope") else ""
	expect(scope.begins_with("host:") and not scope.contains("tok-") and not scope.contains("SECRET"),"Main derives a host scope without secrets: "+scope)
	if scope.is_empty():scope="host:ui-test"
	ctrl.call("dispose")
	ctrl.call("setup",session,lib,scope)
	await settle()
	expect((ctrl.entries as Array).is_empty() and str(ctrl.library_error)=="" and ctrl.mode=="idle","controller re-pointed to the isolated library")
	await flow_book_and_capture()
	await flow_gallery()
	await flow_place_and_build()
	await flow_keys()
	await flow_rename_delete()
	await flow_unknown()
	await flow_release_on_ui()
	await flow_corrupt_pending_notice()
	await finish()

# ------------------------------------------------------------------ flows --

func flow_book_and_capture() -> void:
	await pose(Vector2(src.x-0.5,src.y+0.5))
	# BuildFolio -> 藍圖冊 entry.
	app._build_menu()
	await settle()
	expect(layout()=="build_folio","build menu opens the build folio")
	var opened:=await press("book",app.modal,"build folio")
	if not opened or layout()!=LAYOUT:
		expect(false,"BuildFolio entry opens the blueprint folio")
		app._blueprint_menu()
		await settle()
	await shoot("book-empty",func(l):check_folio(l,["capture","primary"],{"capture":true}))
	# Esc closes the folio (modal close is not swallowed by blueprint handling).
	await key(KEY_ESCAPE)
	expect(app.modal==null and ctrl.mode=="idle","Esc closes the folio")
	app._blueprint_menu()
	await settle()
	var began:=await press("capture",app.modal,"book")
	if not began:
		ctrl.call("begin_capture")
		await settle()
	expect(app.modal==null and ctrl.mode=="capture","capture closes the folio and enters capture mode")
	var stage_check:=func(l):
		check_strip(l,["cancel"])
		expect(text_of(strip()).contains("框"),"%s: capture hint shown"%l)
	await shoot("capture-stage",stage_check,func():aim(src))
	# Drag on the ground from src to src+(1,1).
	var start:=aim(src)
	var down:=InputEventMouseButton.new()
	down.button_index=MOUSE_BUTTON_LEFT
	down.pressed=true
	down.button_mask=MOUSE_BUTTON_MASK_LEFT
	down.position=start
	down.global_position=start
	root.push_input(down)
	await settle(2)
	expect(app.get("capture_drag")==true,"press on the ground starts a capture drag")
	aim(src+Vector2i(1,1),MOUSE_BUTTON_MASK_LEFT)
	await settle(3)
	var overlay=app.blueprint_overlay
	expect(overlay.capture_visible==true and overlay.capture_rect==Rect2i(src,Vector2i(2,2)),"overlay shows the dragged capture rectangle")
	var drag_check:=func(l):
		check_strip(l,["cancel"])
		expect(overlay.visible and overlay.capture_visible and overlay.capture_rect==Rect2i(src,Vector2i(2,2)),"%s: capture rectangle drawn"%l)
	var drag_aim:=func():aim(src+Vector2i(1,1),MOUSE_BUTTON_MASK_LEFT)
	await shoot("capture-drag",drag_check,drag_aim)
	var counter0:=int(app.session.counter)
	var end:=cell_screen(src+Vector2i(1,1))
	var up:=InputEventMouseButton.new()
	up.button_index=MOUSE_BUTTON_LEFT
	up.pressed=false
	up.position=end
	up.global_position=end
	root.push_input(up)
	await settle()
	expect(int(app.session.counter)==counter0,"capture release never performs build_area")
	var cap=ctrl.captured
	expect(cap is Dictionary and int(cap.get("width",0))==2 and int(cap.get("height",0))==2 and (cap.get("pieces",[]) as Array).size()==5,"release captured the 2x2 layout")
	expect(int(ctrl.auto_roofs_omitted)==1,"automatic roof omitted")
	expect(layout()==LAYOUT,"successful capture opens the folio for naming")
	var edit:=find("name",app.modal) as LineEdit
	expect(edit!=null,"naming field present")
	if edit!=null:
		edit.text="UI測試小屋"
		edit.text_changed.emit(edit.text)
	await settle()
	expect(has_number(text_of(app.modal),1) and text_of(app.modal).contains("屋頂"),"folio mentions the omitted automatic roof")
	await shoot("name-save",func(l):check_folio(l,["name","primary"],{"primary":true}))
	expect(not FileAccess.file_exists(lib),"nothing saved before pressing save")
	var saved:=await press("primary",app.modal,"name/save")
	if not saved:ctrl.call("save_capture","UI測試小屋")
	var disk:=Library.load_library(lib,World.BUILD,World.NAMES)
	expect(disk.get("ok")==true and (disk.entries as Array).size()==1 and str(disk.entries[0].design.name)=="UI測試小屋","save button wrote the named entry to disk")
	expect((ctrl.entries as Array).size()==1,"controller lists the saved entry")

func flow_gallery() -> void:
	if not is_instance_valid(app.modal):
		app._blueprint_menu()
		await settle()
	var pocket:Button=null
	var stage:Control=null
	if is_instance_valid(app.modal):pocket=app.modal.find_child("BlueprintPocket0",true,false) as Button
	expect(pocket!=null and pocket.is_visible_in_tree() and not pocket.disabled,"gallery pocket for the saved entry")
	if pocket!=null:
		expect(not thumbs_in(pocket).is_empty(),"gallery pocket draws a blueprint thumbnail")
		pocket.pressed.emit()
		await settle()
	if is_instance_valid(app.modal):stage=app.modal.find_child("BlueprintStage",true,false) as Control
	expect(stage!=null and stage.is_visible_in_tree() and not thumbs_in(stage).is_empty(),"large preview uses a blueprint thumbnail")
	var t:=text_of(app.modal)
	expect(t.contains("UI測試小屋") and t.contains("2") and has_number(t,5),"detail shows name, size and piece count")
	var gallery_check:=func(l):
		check_folio(l,["primary","rename","delete","capture"],{"primary":true})
		var costs:Control=app.modal.find_child("BlueprintBaseCost",true,false)
		expect(costs!=null and costs.get_child_count()==2,"gallery shows both recipe materials")
		if costs!=null:
			for chip in costs.get_children():
				expect(chip.is_visible_in_tree() and unclipped(chip) and in_view(chip),"material icon/count remains visible without scrolling")
		if pocket!=null:
			expect(pocket.is_visible_in_tree() and in_view(pocket),"%s: pocket visible in the window"%l)
			for th in thumbs_in(pocket):
				if th is CanvasItem:
					var at:Vector2=(th as CanvasItem).get_global_transform().origin
					expect(pocket.get_global_rect().grow(0.5).has_point(at),"%s: thumbnail anchored inside its pocket"%l)
	await shoot("gallery",gallery_check)
	var chose:=await press("primary",app.modal,"gallery choose")
	if not chose:ctrl.call("choose",str(ctrl.entries[0].id))
	expect(app.modal==null and ctrl.mode=="placing" and ctrl.locked==false and int(ctrl.turns)==0,"choose closes the folio and enters placing")

func flow_place_and_build() -> void:
	# Collision: the neighbour's 3x3 floors.
	await pose(Vector2(clash.x-0.5,clash.y+1.5))
	var target:=clash+Vector2i(1,1)
	aim(target)
	await settle(3)
	expect(ctrl.origin==target,"unlocked origin follows the mouse cell")
	var preview_check:=func(l):
		check_strip(l,["rotate","cancel"])
		expect(app.blueprint_overlay.visible and ctrl.locked==false,"%s: unlocked ground preview overlay visible"%l)
	await shoot("world-preview",preview_check,func():aim(target))
	ctrl.call("move_origin",target)
	var counter0:=int(app.session.counter)
	var state0:=var_to_str(w.state)
	tick()
	await click_at(cell_screen(target))
	await settle()
	expect(int(app.session.counter)==counter0 and var_to_str(w.state)==state0,"ground click in placing never runs an ordinary tool action")
	expect(ctrl.locked==true and ctrl.origin==target,"ground click pins the origin")
	var q:Dictionary=ctrl.quote
	expect(q.get("ok")==false and (q.get("problems",[]) as Array).size()>0,"collision quote lists problem cells: "+str(q.get("message")))
	var collision_check:=func(l):
		check_strip(l,["rotate","reposition","confirm","cancel"],{"confirm":false})
		expect(text_of(strip()).contains("不能施工"),"%s: problem summary shown"%l)
	await shoot("collision",collision_check)
	# Materials short at site1.
	var moved:=await press("reposition",strip(),"collision")
	if not moved:ctrl.call("reposition")
	expect(ctrl.locked==false,"reposition unlocks")
	await set_bag({"wood":0,"stone":0})
	await pose(Vector2(site1.x-0.5,site1.y+1.5))
	var spot:=site1+Vector2i(1,1)
	aim(spot)
	await settle(3)
	tick()
	await click_at(cell_screen(spot))
	await settle()
	q=ctrl.quote
	expect(ctrl.origin==spot and q.get("ok")==false and str(q.get("message","")).contains("材料不足"),"short materials quote: "+str(q.get("message")))
	await shoot("materials-short",func(l):check_strip(l,["rotate","reposition","confirm","cancel"],{"confirm":false}))
	# Restore materials, ask for a fresh quote through the strip.
	await set_bag({"wood":400,"stone":160})
	tick()
	var quoted:=await press("quote",strip(),"requote")
	if not quoted:ctrl.call("request_quote")
	await settle()
	q=ctrl.quote
	var direct:Dictionary=w.quote_blueprint(T,ctrl.draft,spot,0)
	expect(q.get("ok")==true and q.get("hash")==direct.get("hash"),"strip quote equals the authoritative World quote")
	var cost:Dictionary=direct.get("cost",{})
	var ok_check:=func(l):
		check_strip(l,["rotate","reposition","quote","confirm","cancel"],{"confirm":true})
		var txt:=text_of(strip())
		for item in cost:expect(has_number(txt,int(cost[item])),"%s: %s ×%d shown"%[l,item,int(cost[item])])
		var icons:=0
		for d in descendants(strip()):
			if d is TextureRect and d.is_visible_in_tree() and d.texture!=null:icons+=1
		expect(icons>=cost.size(),"%s: material icons drawn (%d)"%[l,icons])
		var reversibility:="可在建造選單使用「復原」" if bool(direct.get("undoable",false)) else "不能用「復原」撤回"
		var warning:=strip().find_child("BlueprintStripWarning",true,false) as Label
		expect(txt.contains("立即施工並扣除材料") and txt.contains(reversibility),"%s: build timing and undoability match the quote"%l)
		expect(warning!=null and warning.is_visible_in_tree() and unclipped(warning) and in_view(warning),
			"%s: construction warning is visible without scrolling"%l)
	await shoot("quote-ok",ok_check)
	# R rotates while placing (not the move_object tool), clearing the quote.
	var tool0:=str(app.selected)
	await key(KEY_R)
	expect(int(ctrl.turns)==1 and (ctrl.quote as Dictionary).get("ok")!=true and str(app.selected)==tool0,"R rotates in placing, clears the quote, keeps the tool")
	var confirm_btn:=find("confirm",strip()) as Button
	expect(confirm_btn==null or confirm_btn.disabled,"confirm disabled after rotation")
	for i in 3:await key(KEY_R)
	expect(int(ctrl.turns)==0,"R x4 returns to 0")
	tick()
	var requoted:=await press("quote",strip(),"requote after rotate")
	if not requoted:ctrl.call("request_quote")
	await settle()
	expect(ctrl.quote.get("hash")==direct.get("hash"),"quote restored after a full rotation")
	# Real build.
	var inv0:Dictionary=w.state.players[T].inventory.duplicate()
	tick()
	var confirmed:=await press("confirm",strip(),"confirm")
	if not confirmed:ctrl.call("confirm")
	await settle(6)
	expect(built_at(spot),"confirm built the blueprint in the real World")
	expect(int(w.state.players[T].inventory.get("wood",0))==int(inv0.get("wood",0))-int(cost.get("wood",0)),"wood charged exactly once")
	expect(ctrl.mode=="idle" and (ctrl.pending as Dictionary).is_empty() and not FileAccess.file_exists(pending_path()),"success cleans the pending record")
	var snap_ground:Dictionary=app.session.snapshot.get("ground",{})
	var cell=snap_ground.get(World.key(spot))
	expect(cell is Dictionary and cell.get("owner")==own,"Main snapshot shows the new floors")
	var built_check:=func(l):
		expect(strip()==null or not strip().is_visible_in_tree(),"%s: strip hidden after success"%l)
		expect(app.hud.is_visible_in_tree() and app.modal==null,"%s: HUD back, no modal"%l)
	await shoot("built",built_check)

func flow_keys() -> void:
	await pose(Vector2(site2.x-0.5,site2.y+1.5))
	# Placing + Esc -> idle.
	expect(ctrl.call("choose",str(ctrl.entries[0].id))==true,"fixture: choose for key checks")
	await settle()
	await key(KEY_ESCAPE)
	expect(ctrl.mode=="idle" and app.modal==null,"Esc cancels placing")
	# Folio open while placing: Esc closes the folio first, R does not rotate.
	ctrl.call("choose",str(ctrl.entries[0].id))
	await settle()
	app._blueprint_menu()
	await settle()
	await key(KEY_R)
	expect(int(ctrl.turns)==0,"R ignored while a modal is open")
	await key(KEY_ESCAPE)
	expect(app.modal==null and ctrl.mode=="placing","Esc closes the modal without cancelling placing")
	# Tool switch (key 1 = hoe) cancels an unsubmitted placement.
	await key(KEY_1)
	expect(ctrl.mode=="idle" and str(app.selected)=="hoe","tool key cancels placing and selects the tool")
	# Idle regressions: R = move_object tool, Tab = inventory.
	await key(KEY_R)
	expect(str(app.selected)=="move_object","R still selects move_object outside placing")
	await key(KEY_1)
	await key(KEY_TAB)
	expect(app.modal!=null,"Tab opens the inventory")
	await key(KEY_TAB)
	expect(app.modal==null,"Tab closes the inventory")

func flow_rename_delete() -> void:
	# Fixture: a second entry via the controller API (labelled, not UI).
	ctrl.call("begin_capture")
	var r=ctrl.call("capture_area",Rect2i(src,Vector2i(2,1)),"第二份")
	expect(r is Dictionary and r.get("ok")==true,"fixture: second capture")
	ctrl.call("save_capture","第二份")
	await settle()
	expect((ctrl.entries as Array).size()==2,"fixture: two entries")
	app._blueprint_menu()
	await settle()
	var first_id:=str(ctrl.entries[0].id)
	var second_id:=str(ctrl.entries[1].id)
	# Rename the first entry through the folio.
	var p0:=app.modal.find_child("BlueprintPocket0",true,false) as Button
	if p0!=null:
		p0.pressed.emit()
		await settle()
	var renaming:=await press("rename",app.modal,"rename")
	if renaming:
		var edit:=find("rename_edit",app.modal) as LineEdit
		expect(edit!=null,"rename field visible")
		if edit!=null:
			edit.text="改名小屋"
			edit.text_changed.emit(edit.text)
		await press("rename_save",app.modal,"rename save")
	var disk:=Library.load_library(lib,World.BUILD,World.NAMES)
	var renamed:=false
	for e in disk.get("entries",[]):renamed=renamed or (str(e.id)==first_id and str(e.design.name)=="改名小屋")
	expect(renamed,"rename through the folio kept the ID and wrote the name")
	# Two-step delete of the second entry.
	var p1:=app.modal.find_child("BlueprintPocket1",true,false) as Button
	expect(p1!=null,"second pocket present")
	if p1!=null:
		p1.pressed.emit()
		await settle()
	var arming:=await press("delete",app.modal,"delete")
	if arming:
		expect((ctrl.entries as Array).size()==2 and (Library.load_library(lib,World.BUILD,World.NAMES).entries as Array).size()==2,"first delete press only asks for confirmation")
		await shoot("delete-confirm",func(l):check_folio(l,["delete_yes"],{"delete_yes":true}))
		await press("delete_yes",app.modal,"delete confirm")
	disk=Library.load_library(lib,World.BUILD,World.NAMES)
	var ids:=[]
	for e in disk.get("entries",[]):ids.append(str(e.id))
	expect(ids==[first_id] and not second_id in ids,"second confirmation deleted exactly that entry on disk")
	await key(KEY_ESCAPE)
	expect(app.modal==null,"folio closed")

func flow_unknown() -> void:
	await pose(Vector2(site2.x-0.5,site2.y+1.5))
	var design:Dictionary=(ctrl.entries[0] as Dictionary).design
	var direct:Dictionary=w.quote_blueprint(T,design,site2,0)
	expect(direct.get("ok")==true,"fixture: unknown site quotes ok: "+str(direct.get("message")))
	# SIMULATED unknown: a pending record as if the reply was lost.
	var nonce:=Crypto.new().generate_random_bytes(16).hex_encode()
	var record:={"version":1,"scope":scope,"actor":own,"nonce":nonce,"design":design,"origin":{"x":site2.x,"y":site2.y},
		"turns":0,"hash":str(direct.get("hash","")),"region":"home","epoch":int(w.state.players[T].get("travel_epoch",0))}
	var f:=FileAccess.open(pending_path(),FileAccess.WRITE)
	expect(f!=null,"fixture: simulated pending record written")
	if f==null:return
	f.store_string(JSON.stringify(record))
	f.close()
	ctrl.call("dispose")
	ctrl.call("setup",app.session,lib,scope)
	app._blueprint_sync()
	await settle()
	expect(ctrl.mode=="unknown" and str((ctrl.pending as Dictionary).get("nonce",""))==nonce,"simulated record restores the unknown state")
	# Ground tools refuse to build while unknown.
	var counter0:=int(app.session.counter)
	var state0:=var_to_str(w.state)
	await key(KEY_7)
	await wait(0.2)
	await click_at(cell_screen(site2+Vector2i(2,2)))
	expect(int(app.session.counter)==counter0 and var_to_str(w.state)==state0,"no ground build while a blueprint is unknown")
	await key(KEY_ESCAPE)
	expect(ctrl.mode=="unknown" and FileAccess.file_exists(pending_path()),"Esc never discards an unknown record")
	if app.modal!=null:
		await key(KEY_ESCAPE)
	var unknown_check:=func(l):
		check_strip(l,["retry"],{"retry":true})
		var txt:=text_of(strip())
		expect(not txt.contains("沒有施工") and not txt.contains("沒有扣除") and not txt.contains("未扣"),"%s: never claims nothing was built"%l)
		expect(txt.contains("待確認") or txt.contains("無法確定") or txt.contains("未確認"),"%s: says the result is unconfirmed"%l)
		var confirm_btn:=find("confirm",strip()) as Button
		expect(confirm_btn==null or confirm_btn.disabled,"%s: no new confirm while unknown"%l)
	await shoot("unknown",unknown_check)
	tick()
	var retried:=await press("retry",strip(),"unknown")
	if not retried:ctrl.call("retry_pending")
	await settle(6)
	expect(built_at(site2),"retry of the simulated record built it in the real World")
	expect(w.state.players[T].receipts.has("blueprint:"+nonce),"receipt stored under the same nonce")
	expect(ctrl.mode=="idle" and not FileAccess.file_exists(pending_path()),"retry success cleans up")

func flow_release_on_ui() -> void:
	await pose(Vector2(src.x-0.5,src.y+0.5))
	app._blueprint_menu()
	await settle()
	var again:=await press("capture",app.modal,"capture again")
	if not again:
		ctrl.call("begin_capture")
		await settle()
	var count0:=(ctrl.entries as Array).size()
	var s:=strip()
	expect(s!=null and s.is_visible_in_tree(),"strip shown in capture mode")
	if s==null:return
	await click_at(aim(src),s.get_global_rect().get_center())
	expect(app.modal==null and (ctrl.entries as Array).size()==count0,"release over the strip cancels the capture without saving")
	var cap=ctrl.captured
	expect(not (cap is Dictionary and not cap.is_empty()),"release over UI captured nothing")
	await key(KEY_ESCAPE)
	if ctrl.mode=="capture":await key(KEY_ESCAPE)
	expect(ctrl.mode=="idle","Esc leaves capture mode")

func flow_corrupt_pending_notice() -> void:
	var path:=pending_path()
	expect(not FileAccess.file_exists(path),"corruption fixture has no prior pending operation")
	if FileAccess.file_exists(path):return
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string("{isolated corrupt pending")
	file.close()
	var original:=FileAccess.get_file_as_bytes(path)
	ctrl.setup(app.session,lib,scope)
	await settle()
	expect(not ctrl.pending_error.is_empty() and strip().visible,"corrupt record is immediately visible on the island")
	expect(text_of(strip()).contains("保留"),"strip tells player to preserve corrupt record")
	app._blueprint_menu()
	await settle()
	var banner:Control=app.modal.find_child("BlueprintPendingNote",true,false)
	expect(banner!=null and banner.is_visible_in_tree() and text_of(banner).contains("保留"),"folio explains blocked pending record")
	expect((find("capture",app.modal) as BaseButton).disabled and (find("primary",app.modal) as BaseButton).disabled,"capture and placement disabled while pending is unreadable")
	ctrl.changed.emit()
	expect(not strip().visible,"controller signal cannot flash strip above modal")
	expect(FileAccess.get_file_as_bytes(path)==original,"showing error never changes corrupt record")
	app._close_modal()
	expect(DirAccess.remove_absolute(path)==OK,"external recovery removes only isolated fixture")
	ctrl.setup(app.session,lib,scope)
	await settle()
	expect(ctrl.pending_error.is_empty() and not strip().visible,"same-process reconnect recovers after external file repair")

func finish() -> void:
	if is_instance_valid(app):
		app._close_modal()
		app.queue_free()
	await settle(3)
	expect(not FileAccess.file_exists(default_library),"Main's default library path was never written")
	remove_tree(dir)
	expect(not DirAccess.dir_exists_absolute(dir),"isolated test directory removed")
	print("BLUEPRINT_CLIENT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func remove_tree(path:String) -> void:
	if not path.begins_with("user://test-blueprint-client-ui-"):return
	for sub in DirAccess.get_directories_at(path):remove_tree(path+"/"+sub)
	for f in DirAccess.get_files_at(path):DirAccess.remove_absolute(path+"/"+f)
	DirAccess.remove_absolute(path)
