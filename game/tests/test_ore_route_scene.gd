extends SceneTree
## 第 40 章金瓜石初訪「沿運礦路線送一批礦料」native render check at 1024×640 and 1280×800
## (run WITHOUT --headless). Screenshots go to outputs/運礦路線預覽 (or --capture-dir=), named
## <w>x<h>_<step>.png. Same harness as test_gold_panning_scene.gd (real main.tscn host).
##
## Art is runtime-painted, no new PNGs (ore_route_art.gd): draw_track on every Route.TRACK cell,
## draw_platform "load" on STOPS[0] / "unload" on STOPS[-1], draw_cart on cart_cell(stage)
## (loaded ore heap with a two-frame glint unless reduced motion); the page's cart picture is
## ore_route_art.cart_texture(stage>0) (64×64). Colours are looked up by name in the art script's
## constants (groups RAIL*, TIE*, WOOD*, ORE*, COPPER*, GOLD*), so a renamed constant fails a check
## instead of the whole suite.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.time = 30.0 (day 1, sunny) and state.ore_route erased before each size (and again
##    before the final save);
##  * the local player is teleported by writing region="jinguashi" / x / y: PARK (40.5,30.5) far
##    off-screen (no focus), NEAR0 (32.5,20.5) next to the load platform (in reach, not on the
##    cart), the centre of each stop (on the cart cell, to push / unload), RUN_SPOT (35.5,20.5)
##    (camera follows the player while the view runs; cart on screen, out of focus range),
##    ON_TRACK (21.5,23.5) on a plain track cell, and the load platform centre (on the cart);
##  * the camera is aimed directly (view processing paused so the frame is still) at EAST
##    (26.5,21.5) or WEST (17.5,21.5); view.zoom=2, view.reduced_motion and view.elapsed (the glint
##    clock) are written directly for the deterministic frames.
## REALLY PLAYED / EXERCISED:
##  * main._interact() at the empty cart opens the 運礦路線 page (stage 0 entry);
##  * load through the page's OrAction button (pressed.emit -> Session.perform -> World.act ->
##    Route.apply -> snapshot -> OreRouteUI.refresh), first delivery's six pushes and the unload
##    through main._interact() at each stop (stage >= 1 entry performs directly, page stays shut);
##  * the second delivery entirely through the page button (player moved to each stop while the
##    page is open, so the away / near states refresh in place) up to the daily limit;
##  * view processing re-enabled for ~2 s (real elapsed clock) with reduced motion and with motion.
## REALLY RENDERED: the real WorldView of the host app (HUD included) in a native window.
## SHOTS per size (18): world_idle, world_idle_west, world_focus, world_loaded,
##  world_loaded_reduced, world_stage_2..world_stage_7, world_back, world_on_track, world_on_cart,
##  page_idle, page_loaded, page_away, page_daily_done.
## ASSERTS: every TRACK cell fully in view is clear of HUD (both aims, idle); sampled track cells
##  differ from the bare ground cell REF (24,22) (same terrain tile as (24,23)) and carry RAIL / TIE
##  colours in excess of REF (REF's terrain speckles match ~128 px of RAIL colours by area, so the
##  check is differential: area excess, and a geometry probe at every pixel the art paints as rail / tie
##  compared with the same offsets of REF, plus rail-vs-ballast luminance contrast); the empty cart cell carries WOOD colours; focused label text ==
##  Route.cart_label (near) and gone far away; loaded cart differs from the empty cart, ore-heap
##  colours appear; reduced motion: cart box identical for any elapsed (written and played); motion:
##  the glint changes the cart box (written and played); each stage: cart drawn at cart_cell(stage),
##  previous stop and load platform back to the no-cart pixels, every visible TRACK cell keeps rail
##  pixels; at the unload platform; after unload the empty cart is back (load box identical to the
##  idle frame); page states idle / loaded-near / loaded-away (WARN-red reason) / daily-done with
##  texts from the contract, panel fits, nothing cut, OrCart texture switches, gold / copper only
##  when loaded; the player drawn over a track cell and over the cart.
## NOT COVERED: other players' carts (private, not in snapshots), PURSE_FULL, day rollover,
##  network clients, keyboard-only focus traversal (see test_ore_route_ui).
## Same-machine evidence only (one native run on the coordinator's machine).
const World=preload("res://scripts/world.gd")
const Route=preload("res://scripts/ore_route.gd")
const Art=preload("res://scripts/ore_route_art.gd")
const UI=preload("res://scripts/ore_route_ui.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const ART_PATH:="res://scripts/ore_route_art.gd"
const REGION:="jinguashi"
## Bare ground above the track cell (24,23); same terrain tile and tint as (24,23).
const REF:=Vector2i(24,22)
const REF_TRACK:=Vector2i(24,23)
## Track cells sampled for rail / tie colours (straight h, straight v, corner, west straight v).
const SAMPLES:=[Vector2i(24,23),Vector2i(26,22),Vector2i(31,21),Vector2i(16,22)]
const PARK:=Vector2(40.5,30.5)
const NEAR0:=Vector2(32.5,20.5)
const RUN_SPOT:=Vector2(35.5,20.5)
const ON_TRACK:=Vector2(21.5,23.5)
const EAST:=Vector2(26.5,21.5)
const WEST:=Vector2(17.5,21.5)
## Written glint clock for the deterministic frames.
const E0:=0.1
## World px trimmed from each side of a cell before comparing / counting (neighbouring art spills
## at most 2 px sideways).
const INSET:=3.0
const TOL:=0.1
const RAIL_MIN:=8
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var panel_shots:=0
var aim:=EAST
var colours:={}
var idle_east:Image
var idle_west:Image
var loaded_east:Image
var no_cart_east:Image

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("ORE_ROUTE_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func person()->Dictionary:
	return w.state.players[id]

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

## Snapshot -> HUD -> view, then the camera is aimed at `aim` (tiles) and held there.
func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	var zoom:float=float(app.view.view_zoom())
	app.view.camera=(aim*32.0-app.view.get_viewport_rect().size/zoom*0.5).round()
	app.view.queue_redraw()
	hide_toast()
	await settle()

func stand(at:Vector2,look:Vector2)->void:
	aim=look
	var p:Dictionary=person()
	p.region=REGION  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	v.starts[me]=at
	v.goals[me]=at
	v.display_positions[me]=at
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:app.hud.remove_child(ribbon);ribbon.queue_free()
	await refresh()

func look_at(look:Vector2)->void:
	aim=look
	app.view.elapsed=E0  # PRESET (glint clock)
	app.view.reduced_motion=false
	await refresh()

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("ORE_ROUTE_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	if image!=null:image.convert(Image.FORMAT_RGBA8)
	return image

func shot(step:String)->Image:
	var image:Image=await grab()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return Image.create_empty(root.size.x,root.size.y,false,Image.FORMAT_RGBA8)
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	save_image(image,step)
	return image

# ------------------------------------------------------------- geometry --

func view_rect(world_px:Rect2)->Rect2:
	return Rect2(world_px.position-app.view.camera,world_px.size)

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## The whole 32×32 cell on screen.
func cell_box(cell:Vector2i)->Rect2i:
	return pixel_box(view_rect(Rect2(Vector2(cell)*32.0,Vector2(32,32))))

## The cell's interior (INSET trimmed on every side): only this cell's own art.
func inner_box(cell:Vector2i)->Rect2i:
	return pixel_box(view_rect(Rect2(Vector2(cell)*32.0+Vector2(INSET,INSET),Vector2(32.0-2.0*INSET,32.0-2.0*INSET))))

## Art.CART_BOUNDS placed on `cell`.
func cart_box(cell:Vector2i)->Rect2i:
	return pixel_box(view_rect(Rect2(Vector2(cell)*32.0+Art.CART_BOUNDS.position,Art.CART_BOUNDS.size)))

## Torso / legs of a standing actor whose feet are at `foot` (tiles); lies inside the foot cell.
func body_box(foot:Vector2)->Rect2i:
	return pixel_box(view_rect(Rect2(foot*32.0+Vector2(-8,-15),Vector2(16,14))))

func screen_rect()->Rect2i:
	return Rect2i(Vector2i.ZERO,root.size)

func fully_on_screen(box:Rect2i)->bool:
	return box.size.x>0 and box.size.y>0 and screen_rect().encloses(box)

func hud_panels()->Array:
	var result:=[]
	if not is_instance_valid(app.hud) or not (app.hud as CanvasItem).is_visible_in_tree():return result
	var area:=Vector2(root.size).x*Vector2(root.size).y
	for child in (app.hud as Node).get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree() or c.size.x<=0 or c.size.y<=0:continue
		if c.size.x*c.size.y>area*0.5:continue
		result.append({"name":str(c.name),"rect":c.get_global_rect()})
	return result

func box_on_screen(box:Rect2i,what:String)->void:
	var r:=Rect2(Vector2(box.position),Vector2(box.size))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(r),"%s on screen (%s) %s"%[what,tag,str(box)])
	for panel:Dictionary in hud_panels():check(not r.intersects(panel.rect),"%s clear of HUD %s (%s) %s vs %s"%[what,panel.name,tag,str(box),str(panel.rect)])

func box_difference(a:Image,b:Image,box:Rect2i)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 0.0
	box=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	var changed:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(box.size.x*box.size.y)

## Exact pixel compare inside `box`: number of differing pixels (-1 when not comparable).
func exact_changed(a:Image,b:Image,box:Rect2i)->int:
	if a==null or b==null or a.get_size()!=b.get_size():return -1
	var r:=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if r.size.x<=0 or r.size.y<=0:return -1
	var n:=0
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			if a.get_pixel(x,y)!=b.get_pixel(x,y):n+=1
	return n

## Same-size regions `ra` of `a` and `rb` of `b`: share of pixels that differ.
func cross_difference(a:Image,ra:Rect2i,b:Image,rb:Rect2i)->float:
	var size:=Vector2i(mini(ra.size.x,rb.size.x),mini(ra.size.y,rb.size.y))
	if a==null or b==null or size.x<=0 or size.y<=0:return 0.0
	if not Rect2i(Vector2i.ZERO,a.get_size()).encloses(Rect2i(ra.position,size)):return 0.0
	if not Rect2i(Vector2i.ZERO,b.get_size()).encloses(Rect2i(rb.position,size)):return 0.0
	var changed:=0
	for x in size.x:
		for y in size.y:
			var p:=a.get_pixel(ra.position.x+x,ra.position.y+y);var q:=b.get_pixel(rb.position.x+x,rb.position.y+y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(size.x*size.y)

## Pixels inside `box` within `tol` (sum of channel differences) of any colour in `targets`.
func count_colours(image:Image,box:Rect2i,targets:Array,tol:float)->int:
	if image==null or targets.is_empty():return 0
	var r:=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var n:=0
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			var c:=image.get_pixel(x,y)
			if c.a<0.5:continue
			for t:Color in targets:
				if absf(c.r-t.r)+absf(c.g-t.g)+absf(c.b-t.b)<tol:n+=1;break
	return n

## Geometry-derived differential probe. The art script itself says which local pixel (x,y) of a track
## cell is painted with which colour (Art.track_pixel). For every such pixel whose colour is one of
## `targets` (and lies inside the INSET interior) the rendered screen pixel of `cell` is compared with
## that exact colour, and so is the pixel at the SAME local offset of the bare reference cell `ref`.
## Result: points (expected positions), hits (track matches), ref_hits (ground happens to match),
## luma (mean brightness of the rendered track pixels at those positions) and ref_luma.
## Bare terrain contains dark / grey speckles that are "rail coloured" by area counting (128 px in
## REF), so absolute near-zero reference counts are wrong; what must hold is the excess at the
## expected positions, which terrain cannot reproduce in a regular rail / tie layout.
func probe(image:Image,cell:Vector2i,ref:Vector2i,targets:Array)->Dictionary:
	var shape:=Art.track_shape(cell)
	var zoom:float=float(app.view.view_zoom())
	var origin:=cell_box(cell).position
	var ref_origin:=cell_box(ref).position
	var lo:=int(INSET)
	var hi:=int(Art.CELL)-int(INSET)
	var points:=0
	var hits:=0
	var ref_hits:=0
	var luma:=0.0
	var ref_luma:=0.0
	for y in range(lo,hi):
		for x in range(lo,hi):
			var want:Color=Art.track_pixel(shape,x,y)
			var wanted:=false
			for t:Color in targets:
				if want==t:wanted=true;break
			if not wanted:continue
			var dx:=int((float(x)+0.5)*zoom)
			var dy:=int((float(y)+0.5)*zoom)
			var px:Vector2i=origin+Vector2i(dx,dy)
			var rx:Vector2i=ref_origin+Vector2i(dx,dy)
			if not Rect2i(Vector2i.ZERO,image.get_size()).has_point(px) or not Rect2i(Vector2i.ZERO,image.get_size()).has_point(rx):continue
			points+=1
			var c:=image.get_pixel(px.x,px.y)
			var r:=image.get_pixel(rx.x,rx.y)
			if absf(c.r-want.r)+absf(c.g-want.g)+absf(c.b-want.b)<TOL:hits+=1
			if absf(r.r-want.r)+absf(r.g-want.g)+absf(r.b-want.b)<TOL:ref_hits+=1
			luma+=c.get_luminance();ref_luma+=r.get_luminance()
	var n:=float(maxi(points,1))
	return {"points":points,"hits":hits,"ref_hits":ref_hits,"frac":float(hits)/n,"ref_frac":float(ref_hits)/n,"luma":luma/n,"ref_luma":ref_luma/n}

## Distinct colours on a 20×14 grid inside `box` (clipped to the image).
func region_variety(image:Image,box:Rect2i)->int:
	if image==null:return 0
	var r:=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if r.size.x<=0 or r.size.y<=0:return 0
	var seen:={}
	for gx in range(20):
		for gy in range(14):
			var c:Color=image.get_pixel(r.position.x+int((gx+0.5)*r.size.x/20.0),r.position.y+int((gy+0.5)*r.size.y/14.0))
			seen[c.to_html(false)]=true
	return seen.size()

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func label_entry(label_id:String)->Dictionary:
	for entry:Dictionary in placements():
		if str(entry.id)==label_id:return entry
	return {}

func focus()->String:
	return str(app.view.interaction_focus())

# ------------------------------------------------------------- colours --

## Colour constants of the art script whose name is `prefix` or starts with `prefix`_.
func art_group(prefix:String)->Array:
	var result:=[]
	var script:Script=load(ART_PATH) as Script
	if script==null:return result
	var map:Dictionary=script.get_script_constant_map()
	for key in map:
		var key_name:=str(key)
		var value:Variant=map[key]
		if value is Color and (key_name==prefix or key_name.begins_with(prefix+"_")):result.append(value)
	return result

func group(prefix:String)->Array:
	return colours.get(prefix,[])

func ore_heap()->Array:
	var result:=[]
	result.append_array(group("ORE"))
	result.append_array(group("COPPER"))
	result.append_array(group("GOLD"))
	return result

func precious()->Array:
	var result:=[]
	result.append_array(group("COPPER"))
	result.append_array(group("GOLD"))
	return result

# ------------------------------------------------------------- pure checks --

func pure_checks()->void:
	for prefix:String in ["RAIL","TIE","WOOD","ORE","COPPER","GOLD"]:
		colours[prefix]=art_group(prefix)
		check(not group(prefix).is_empty(),"ore_route_art exposes %s colour constants (%d)"%[prefix,group(prefix).size()])
	check(Art.POINT=="ore_cart" and UI.POINT==Art.POINT and Route.ACTION==Art.POINT,"Point id ore_cart shared by art / UI / rules")
	check(UI.LAYOUT=="ore_route" and UI.PAGE_TITLE==Route.TITLE,"UI.LAYOUT ore_route, PAGE_TITLE = Route.TITLE")
	check(Art.TRACK_BOUNDS==Rect2(0,0,32,32),"Art.TRACK_BOUNDS is Rect2(0,0,32,32): %s"%str(Art.TRACK_BOUNDS))
	check(Art.PLATFORM_BOUNDS==Rect2(-4,-20,40,52),"Art.PLATFORM_BOUNDS is Rect2(-4,-20,40,52): %s"%str(Art.PLATFORM_BOUNDS))
	check(Art.CART_BOUNDS==Rect2(-2,-10,36,42),"Art.CART_BOUNDS is Rect2(-2,-10,36,42): %s"%str(Art.CART_BOUNDS))
	check(Art.CART_SIZE==64,"Art.CART_SIZE is 64")
	check(Route.TRACK.size()==23 and Route.STOPS.size()==7,"23 track cells, 7 stops")
	for i in range(1,Route.TRACK.size()):
		var a:Vector2i=Route.TRACK[i-1];var b:Vector2i=Route.TRACK[i]
		check(absi(a.x-b.x)+absi(a.y-b.y)==1,"Track cells %s -> %s adjacent"%[str(a),str(b)])
	var last:=-1
	for stop:Vector2i in Route.STOPS:
		var at:=Route.TRACK.find(stop)
		check(at>last,"Stop %s on the track, in order"%str(stop))
		last=at
	check(REF not in Route.TRACK and World.land(REF,REGION) and REF not in World.JINGUASHI.NODES,"Reference %s is bare land off the track"%str(REF))
	check(Vector2i(ON_TRACK.floor()) in Route.TRACK and Vector2i(ON_TRACK.floor()) not in Route.STOPS,"ON_TRACK stands on a plain track cell")
	check(NEAR0.distance_to(Vector2(Route.STOPS[0])+Vector2(0.5,0.5))<=Route.REACH and Vector2i(NEAR0.floor())!=Route.STOPS[0],"NEAR0 in reach of the load platform, not on it")
	check(RUN_SPOT.distance_to(Vector2(Route.STOPS[0])+Vector2(0.5,0.5))>3.2,"RUN_SPOT outside the focus radius")
	var shapes:={Vector2i(24,23):"h",Vector2i(26,22):"v",Vector2i(16,22):"v",Vector2i(31,21):"nw",Vector2i(26,21):"se",
		Vector2i(26,23):"nw",Vector2i(16,23):"ne",Vector2i(16,21):"sw",Vector2i(31,20):"end_s",Vector2i(14,21):"end_e",REF:""}
	for cell:Vector2i in shapes:
		check(Art.track_shape(cell)==str(shapes[cell]),"track_shape%s is 「%s」: 「%s」"%[str(cell),shapes[cell],Art.track_shape(cell)])
	var images:=[]
	for loaded:bool in [false,true]:
		var tex:=Art.cart_texture(loaded)
		check(tex!=null and tex.get_size()==Vector2(64,64),"cart_texture(%s) is 64×64"%str(loaded))
		check(tex==Art.cart_texture(loaded),"cart_texture(%s) is cached"%str(loaded))
		var img:Image=tex.get_image() if tex!=null else null
		if img==null:images.append(null);continue
		img.convert(Image.FORMAT_RGBA8)
		images.append(img)
		var box:=Rect2i(0,0,img.get_width(),img.get_height())
		var copper:=count_colours(img,box,group("COPPER"),0.06)
		var gold:=count_colours(img,box,group("GOLD"),0.06)
		var wood:=count_colours(img,box,group("WOOD"),0.06)
		print("NOTE cart_texture(%s): wood %d, copper %d, gold %d px"%[str(loaded),wood,copper,gold])
		check(wood>=20,"Wood pixels in cart_texture(%s) (%d)"%[str(loaded),wood])
		if loaded:check(copper>=1 and gold>=1,"Copper and gold pixels in the loaded cart texture (%d / %d)"%[copper,gold])
		else:check(copper==0 and gold==0,"No copper / gold pixels in the empty cart texture (%d / %d)"%[copper,gold])
	if images.size()==2 and images[0]!=null and images[1]!=null:
		check((images[0] as Image).get_data()!=(images[1] as Image).get_data(),"Empty and loaded cart textures differ")

# ------------------------------------------------------------------ world --

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.time=30.0  # PRESET (day 1, sunny)
	w.state.erase(Route.STATE_KEY)  # PRESET
	app.view.zoom=2.0
	app.view.reduced_motion=false
	app.view.elapsed=E0  # PRESET
	app.view.set_process(false)

func record()->Dictionary:
	return Route.view(w.state,id)

func expect_record(stage:int,count:int,total:int,label:String)->void:
	var where:="%s %s"%[label,tag]
	check(record()=={"stage":stage,"count":count,"total":total},"Server record stage %d count %d total %d (%s): %s"%[stage,count,total,where,str(record())])
	var s:Dictionary=app.session.snapshot
	check(Route.stage(s)==stage and Route.count_today(s)==count and Route.total(s)==total,"Snapshot own_ore_route matches (%s): %s"%[where,str(s.get(Route.OWN_KEY,"none"))])

func coins()->int:
	return int(person().get("coins",0))

func snap_coins()->int:
	var players:Dictionary=app.session.snapshot.get("players",{})
	var me:Dictionary=players.get(app.session.own_id,{})
	return int(me.get("coins",0))

## Track cells fully on screen in the current frame.
func visible_track()->Array:
	var result:=[]
	for cell:Vector2i in Route.TRACK:
		if fully_on_screen(cell_box(cell)):result.append(cell)
	return result

## Every visible track cell (except the one under the cart) has rail-coloured pixels.
func track_continuous(image:Image,cart:Vector2i,label:String)->void:
	var seen:=visible_track()
	check(seen.size()>=8,"At least 8 track cells in view (%s %s): %d"%[label,tag,seen.size()])
	var weakest:=1000000
	for cell:Vector2i in seen:
		if cell==cart:continue
		var rail:=count_colours(image,inner_box(cell),group("RAIL"),TOL)
		weakest=mini(weakest,rail)
		check(rail>=RAIL_MIN,"Rail pixels in track cell %s (%d) %s %s"%[str(cell),rail,label,tag])
	print("NOTE %s %s: %d track cells in view, weakest rail count %d"%[label,tag,seen.size(),weakest])

## Idle frame checks: HUD clearance of the track in view, track vs bare ground, cart wood.
func idle_checks(image:Image,required:Array,label:String)->void:
	var seen:=visible_track()
	for cell:Vector2i in required:check(cell in seen,"Track cell %s fully in view (%s %s)"%[str(cell),label,tag])
	var panels:=hud_panels()
	for cell:Vector2i in seen:
		var r:=cell_box(cell)
		for panel:Dictionary in panels:
			check(not Rect2(Vector2(r.position),Vector2(r.size)).intersects(panel.rect),"Track cell %s clear of HUD %s (%s %s) %s vs %s"%[str(cell),panel.name,label,tag,str(r),str(panel.rect)])
	track_continuous(image,Route.STOPS[0],label)
	# Track vs the bare reference cell (only compared against: no HUD check, interior only).
	var ref:=inner_box(REF)
	if fully_on_screen(ref):
		var ref_rail:=count_colours(image,ref,group("RAIL"),TOL)
		var ref_tie:=count_colours(image,ref,group("TIE"),TOL)
		for cell:Vector2i in SAMPLES:
			var box:=inner_box(cell)
			if not fully_on_screen(box):continue
			var unlike:=cross_difference(image,box,image,ref)
			var rail:=count_colours(image,box,group("RAIL"),TOL)
			var tie:=count_colours(image,box,group("TIE"),TOL)
			print("NOTE %s %s: track %s vs ground %s %.1f%%, rail %d tie %d (ref rail %d tie %d)"%[label,tag,str(cell),str(REF),unlike*100.0,rail,tie,ref_rail,ref_tie])
			check(unlike>=0.1,"Track cell %s differs from the bare ground %s (%.1f%%) %s %s"%[str(cell),str(REF),unlike*100.0,label,tag])
			check(rail>=16,"RAIL colours in track cell %s (%d) %s %s"%[str(cell),rail,label,tag])
			check(tie>=16,"TIE colours in track cell %s (%d) %s %s"%[str(cell),tie,label,tag])
			# The bare terrain tile itself holds dark / grey speckles (ref rail 128 px, tie 0), so the
			# absolute reference count is not near zero; the track must EXCEED it.
			check(rail-ref_rail>=16,"Track has more rail colour than the bare ground (%d vs %d, excess %d) %s %s %s"%[rail,ref_rail,rail-ref_rail,str(cell),label,tag])
			check(tie-ref_tie>=16,"Track has more tie colour than the bare ground (%d vs %d, excess %d) %s %s %s"%[tie,ref_tie,tie-ref_tie,str(cell),label,tag])
			# Differential at the expected geometry: rendered pixels at every position where the art
			# paints rail / tie must have that colour, the same offsets of the bare tile must not.
			var rails:=probe(image,cell,REF,[Art.RAIL,Art.RAIL_LIGHT])
			var ties:=probe(image,cell,REF,[Art.TIE])
			var rail_dark:=probe(image,cell,REF,[Art.RAIL])
			var bed:=probe(image,cell,REF,[Art.BALLAST])
			var contrast:float=float(bed.luma)-float(rail_dark.luma)
			var ref_contrast:float=float(bed.ref_luma)-float(rail_dark.ref_luma)
			print("NOTE %s %s: %s geometry rail %d/%d (ref %d) tie %d/%d (ref %d) rail-vs-ballast contrast %.2f (ref %.2f)"%[label,tag,str(cell),rails.hits,rails.points,rails.ref_hits,ties.hits,ties.points,ties.ref_hits,contrast,ref_contrast])
			check(int(rails.points)>=40 and int(ties.points)>=40,"Expected rail / tie positions found for %s (%d / %d) %s %s"%[str(cell),rails.points,ties.points,label,tag])
			check(float(rails.frac)>=0.9,"Rail pixels at the expected rail positions of %s (%.0f%% of %d) %s %s"%[str(cell),float(rails.frac)*100.0,rails.points,label,tag])
			check(float(ties.frac)>=0.9,"Tie pixels at the expected tie positions of %s (%.0f%% of %d) %s %s"%[str(cell),float(ties.frac)*100.0,ties.points,label,tag])
			check(float(rails.frac)-float(rails.ref_frac)>=0.5,"Rail positions of %s match far more than the same offsets of bare ground (%.0f%% vs %.0f%%) %s %s"%[str(cell),float(rails.frac)*100.0,float(rails.ref_frac)*100.0,label,tag])
			check(float(ties.frac)-float(ties.ref_frac)>=0.5,"Tie positions of %s match far more than the same offsets of bare ground (%.0f%% vs %.0f%%) %s %s"%[str(cell),float(ties.frac)*100.0,float(ties.ref_frac)*100.0,label,tag])
			check(contrast>=0.2 and contrast-ref_contrast>=0.1,"Rails are darker than the ballast between them, beyond the ground (%.2f vs ground %.2f) %s %s %s"%[contrast,ref_contrast,str(cell),label,tag])
		var same:=cross_difference(image,inner_box(REF_TRACK),image,ref)
		check(same>=0.1,"Track painted over the same terrain tile: %s vs %s differ (%.1f%%) %s"%[str(REF_TRACK),str(REF),same*100.0,tag])
	else:
		check(label!="world_idle","Reference cell %s fully on screen (%s %s) %s"%[str(REF),label,tag,str(ref)])

func world_idle()->void:
	reset()
	await stand(PARK,EAST)
	await look_at(EAST)
	check(focus()!=Art.POINT,"Parked far away: cart not focused (%s): %s"%[tag,focus()])
	check(label_entry(Art.POINT).is_empty(),"No cart label when parked (%s)"%tag)
	expect_record(0,0,0,"idle")
	idle_east=await shot("world_idle")
	var east_required:=[]
	for cell:Vector2i in Route.TRACK:
		if cell.x>=19:east_required.append(cell)
	idle_checks(idle_east,east_required,"world_idle")
	var cart:=cart_box(Route.STOPS[0])
	box_on_screen(cart,"Empty cart box")
	var loading_frame:=Art.PLATFORM_BOUNDS
	loading_frame.position+=Vector2(Route.STOPS[0])*Art.CELL
	box_on_screen(pixel_box(view_rect(loading_frame)),"Loading frame")
	var wood:=count_colours(idle_east,inner_box(Route.STOPS[0]),group("WOOD"),TOL)
	print("NOTE %s: empty cart cell wood %d px"%[tag,wood])
	check(wood>=40,"WOOD colours in the empty cart cell (%d) %s"%[wood,tag])
	# The west half (unload platform) from the same parked spot.
	await look_at(WEST)
	idle_west=await shot("world_idle_west")
	var west_required:=[]
	for cell:Vector2i in Route.TRACK:
		if cell.x<=24:west_required.append(cell)
	idle_checks(idle_west,west_required,"world_idle_west")
	box_on_screen(inner_box(Route.STOPS[-1]),"Unload platform cell")
	# Near the load platform: focused, label text from the rules.
	await stand(NEAR0,EAST)
	app.view.elapsed=E0  # PRESET
	await refresh()
	check(focus()==Art.POINT,"Next to the cart at %s: ore_cart focused (%s): %s"%[str(NEAR0),tag,focus()])
	check(str(app.view.focused_label)==Art.POINT,"view.focused_label is ore_cart (%s): %s"%[tag,str(app.view.focused_label)])
	await shot("world_focus")
	var mine:=label_entry(Art.POINT)
	var want:=Route.cart_label(app.session.snapshot)
	check(want==Route.LABEL_IDLE,"cart_label at stage 0 is LABEL_IDLE (%s): %s"%[tag,want])
	check(not mine.is_empty() and str(mine.get("title",""))==want,"Focused label 「%s」 (%s): %s"%[want,tag,str(mine.get("title","none"))])
	if not mine.is_empty():
		var px:=view_to_pixels(mine.rect)
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Cart label on screen (%s) %s"%[tag,str(px)])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Cart label clear of HUD %s (%s)"%[panel.name,tag])
	# Far away again: no focus, no label.
	await stand(PARK,EAST)
	check(focus()!=Art.POINT and str(app.view.focused_label)!=Art.POINT,"Far away: ore_cart not focused (%s): %s"%[tag,focus()])
	check(label_entry(Art.POINT).is_empty(),"No cart label far away (%s)"%tag)

## After the page loaded the cart: the loaded cart vs the empty one, reduced motion, glint.
func loaded_motion()->void:
	await stand(PARK,EAST)
	await look_at(EAST)
	loaded_east=await shot("world_loaded")
	var box:=cart_box(Route.STOPS[0])
	var changed:=exact_changed(idle_east,loaded_east,box)
	var heap_idle:=count_colours(idle_east,box,ore_heap(),TOL)
	var heap:=count_colours(loaded_east,box,ore_heap(),TOL)
	var rich:=count_colours(loaded_east,box,precious(),TOL)
	print("NOTE %s: loaded vs empty cart %d px changed; heap colours %d (empty %d), copper/gold %d"%[tag,changed,heap,heap_idle,rich])
	check(changed>=40,"Loaded cart differs from the empty cart (%d px) %s"%[changed,tag])
	check(heap-heap_idle>=16,"Ore-heap colours appear on the loaded cart (%d vs %d) %s"%[heap,heap_idle,tag])
	check(rich>=1,"Copper / gold specks on the loaded cart (%d) %s"%[rich,tag])
	# Reduced motion, written clock: identical for any elapsed.
	app.view.reduced_motion=true  # PRESET
	app.view.elapsed=E0  # PRESET
	app.view.queue_redraw()
	var reduced:Image=await shot("world_loaded_reduced")
	for t:float in [0.6,1.35,2.85]:
		app.view.elapsed=t  # PRESET
		app.view.queue_redraw()
		var later:Image=await grab()
		var n:=exact_changed(reduced,later,box)
		check(n==0,"Reduced motion: cart box identical at elapsed %.2f vs %.2f (%d px) %s"%[E0,t,n,tag])
	# Motion on, written clock: the glint changes within its period.
	app.view.reduced_motion=false
	app.view.elapsed=E0  # PRESET
	app.view.queue_redraw()
	var base:Image=await grab()
	var most:=0
	var whole:=0.0
	for t:float in [0.35,0.6,0.85,1.1,1.6,2.1]:
		app.view.elapsed=t  # PRESET
		app.view.queue_redraw()
		var frame:Image=await grab()
		var n:=exact_changed(base,frame,box)
		if n>most:most=n;whole=box_difference(base,frame,box)
		if most>=4:break
	print("NOTE %s: glint max %d px changed in the cart box"%[tag,most])
	check(most>=4,"Motion on: glint changes the cart box (%d px) %s"%[most,tag])
	check(whole<0.5,"Glint is a small part of the cart box (%.1f%%) %s"%[whole*100.0,tag])
	# Played clock: the camera follows the player at RUN_SPOT; the cart stays on screen.
	await stand(RUN_SPOT,EAST)
	app.view.reduced_motion=true
	app.view.set_process(true)
	await create_timer(0.3).timeout
	var first:Image=await grab()
	var cam:Vector2=app.view.camera
	var played:=cart_box(Route.STOPS[0])
	check(fully_on_screen(played),"Cart box on screen while the view runs (%s) %s"%[tag,str(played)])
	await create_timer(1.8).timeout
	var second:Image=await grab()
	check(Vector2(app.view.camera)==cam,"Camera steady while the view runs (%s)"%tag)
	var still:=exact_changed(first,second,played)
	check(still==0,"Reduced motion (running view, ~2 s apart): cart box identical (%d px) %s"%[still,tag])
	app.view.reduced_motion=false
	await create_timer(0.1).timeout
	var start:Image=await grab()
	var moved:=0
	for i in range(5):
		await create_timer(0.15).timeout
		var next:Image=await grab()
		moved=maxi(moved,exact_changed(start,next,played))
	print("NOTE %s: running view, motion on: max %d px changed in the cart box"%[tag,moved])
	check(moved>0,"Motion on (running view, ~2 s): glint changes the cart box (%d px) %s"%[moved,tag])
	app.view.set_process(false)
	app.view.reduced_motion=false
	app.view.elapsed=E0  # PRESET

func interact(label:String,verify_roll:=false)->void:
	app.action_clock=0
	app.session.rates[1].clear()
	if verify_roll:
		app.sound.master_volume=1.0
		app.sound.volume=0.45
	app._interact()
	if verify_roll:
		var voice:AudioStreamPlayer=app.sound.cart_roll
		var duration:float=app.view.ore_cart_travel_seconds(int(record().stage))
		check(voice.playing and is_equal_approx(voice.stream.get_length()/voice.pitch_scale,duration),
			"Accepted push starts the wheel sound for the duration of the slide (%s)"%tag)
		app.sound.master_volume=0.0
		app.sound.refresh_gains()
		check(not voice.playing,"Master mute stops the rolling sound immediately (%s)"%tag)
		app.sound.master_volume=1.0
		app.sound.refresh_gains()
		app.session._send_snapshot(1)
		check(not voice.playing,"Duplicate snapshot does not restart the sound (%s)"%tag)
	await settle()
	await refresh()
	print("NOTE %s %s: interact -> stage %d"%[label,tag,int(record().stage)])

func aim_for(stage:int)->Vector2:
	return EAST if Route.cart_cell(stage).x>=23 else WEST

## First delivery: six pushes and the unload through main._interact at each stop.
func route_map_shot(step:String,stage:int,delivered:int)->void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=KEY_M
		event.physical_keycode=KEY_M
		event.pressed=down
		root.push_input(event)
	await settle()
	check(is_instance_valid(app.map_view),"M opens the mountain local map (%s)"%tag)
	if not is_instance_valid(app.map_view):return
	var map_state:Dictionary=app.map_view.mine_route(app.map_view.data)
	check(map_state.cell==Route.cart_cell(stage) and map_state.loaded==(stage>0) and map_state.delivered==delivered,
		"The map reflects the cart and delivery count from the current snapshot (%s, %s)"%[step,tag])
	await shot(step)
	if delivered>0:
		await press("JinguashiMapHistory")
		var railway_date:=control("MineHistoryHaulingDate1933") as Label
		check(railway_date!=null and railway_date.is_visible_in_tree(),"Unloading a cart unlocks the mining transport entry (%s)"%tag)
		await shot("map_history_unlocked")
		await press("JinguashiHistoryBack")
		check(is_instance_valid(app.map_view),"The history entry returns to the local map (%s)"%tag)
	app._close_modal()
	await settle()

func route_flow()->void:
	for stage in range(1,Route.LAST):
		var stop:Vector2i=Route.cart_cell(stage)
		var approach:=Vector2(stop)+Vector2(0.5,0.5)
		if stage==2:
			# From the northwest, the mineral is closer than the cart or mine entrance.
			var too_far:=Vector2(26.75,20.25)
			await stand(too_far,aim_for(stage))
			check(focus()=="mine:28,20","The copper remains selectable outside cart reach (%s)"%tag)
			approach=Vector2(27.55,20.4)
		await stand(approach,aim_for(stage))
		check(focus()==Art.POINT,"On the cart at %s: ore_cart focused (%s): %s"%[str(stop),tag,focus()])
		await interact("push %d"%stage,stage==1)
		check(not UI.is_open(app),"Interact on a loaded cart does not open the page (stage %d, %s)"%[stage,tag])
		expect_record(stage+1,0,0,"after push %d"%stage)
		var now:=stage+1
		var cell:=Route.cart_cell(now)
		if stage==1:
			var started:float=app.view.ore_cart_push_started
			app.view.elapsed=started+1.5/app.view.ORE_CART_TILES_PER_SECOND
			check(app.view.ore_cart_position(now).is_equal_approx(Vector2(30.5,21)),"Cart follows the first rail corner (%s)"%tag)
			var player_position:=Vector2(float(person().x),float(person().y))
			var push_pose:Dictionary=app.view.ore_cart_push_pose(now,player_position)
			check(push_pose.get("facing")==Vector2i.DOWN and push_pose.get("lean",0)>0,"Player leans into the first rail direction (%s)"%tag)
			check(app.view.ore_cart_push_pose(now,player_position+Vector2(1,0)).get("facing")==Vector2i.LEFT,
				"Player beside the cart turns toward it (%s)"%tag)
			# Keep the adjacent copper tag out of the cart capture.
			app.set_process(false)
			app.view.hide_interaction_prompt=true
			app.view.queue_redraw()
			var pushing_frame:Image=await shot("world_cart_rounding_corner")
			app.view.hide_interaction_prompt=false
			app.set_process(true)
			app.view.reduced_motion=true
			check(app.view.ore_cart_position(now)==Vector2(cell),"Reduced motion skips cart travel (%s)"%tag)
			check(app.view.ore_cart_push_pose(now,player_position).is_empty(),"Reduced motion skips the push pose (%s)"%tag)
			app.view.reduced_motion=false
			app.view.elapsed=started+1.0
			check(app.view.ore_cart_position(now)==Vector2(cell),"Cart settles at the authoritative stop (%s)"%tag)
			check(app.view.ore_cart_push_pose(now,player_position).is_empty() and Vector2(float(person().x),float(person().y))==player_position,
				"Pose ends without moving the player (%s)"%tag)
			app.view.queue_redraw()
			var resting_frame:Image=await grab()
			var scale:float=app.view.view_zoom()
			var foot:Vector2=app.view.screen(player_position)*scale
			var head:=Rect2i(Vector2i(foot+Vector2(-11,-43)*scale),Vector2i(Vector2(22,23)*scale))
			check(exact_changed(pushing_frame,resting_frame,head)>0,"Native render shows the sprite leaning (%s)"%tag)
		# Keep the remaining reference frames at the same fixed glint clock.
		app.view.ore_cart_push_started=-INF
		app.view.elapsed=E0
		await stand(PARK,aim_for(now))
		await look_at(aim_for(now))
		var frame:Image=await shot("world_stage_%d"%now)
		var idle:Image=idle_east if aim_for(now)==EAST else idle_west
		var label:="stage %d"%now
		box_on_screen(cart_box(cell),"Cart box at %s (%s)"%[str(cell),label])
		var drawn:=box_difference(idle,frame,inner_box(cell))
		var heap:=count_colours(frame,cart_box(cell),ore_heap(),TOL)
		var heap_idle:=count_colours(idle,cart_box(cell),ore_heap(),TOL)
		print("NOTE %s %s: cart cell %s vs idle %.1f%%, heap %d (idle %d)"%[label,tag,str(cell),drawn*100.0,heap,heap_idle])
		check(drawn>=0.15,"Cart drawn at cart_cell(%d)=%s (%.1f%% changed) %s"%[now,str(cell),drawn*100.0,tag])
		check(heap-heap_idle>=16,"Loaded ore heap at %s (%d vs %d) %s %s"%[str(cell),heap,heap_idle,label,tag])
		# The stop it left is back to the no-cart pixels.
		var left:=Route.cart_cell(stage)
		if left!=Route.STOPS[0] and fully_on_screen(inner_box(left)):
			var n:=exact_changed(idle,frame,inner_box(left))
			check(n==0,"Previous stop %s has no cart any more (%d px) %s %s"%[str(left),n,label,tag])
		if aim_for(now)==EAST:
			var load_box:=inner_box(Route.STOPS[0])
			if now==2:
				no_cart_east=frame
				var gone:=box_difference(loaded_east,frame,load_box)
				check(gone>=0.15,"Cart left the load platform (%.1f%% changed) %s"%[gone*100.0,tag])
			else:
				var n:=exact_changed(no_cart_east,frame,load_box)
				check(n==0,"Load platform equals the no-cart reference (%d px) %s %s"%[n,label,tag])
		else:
			var unload:=inner_box(Route.STOPS[-1])
			if now<Route.LAST:
				var n:=exact_changed(idle_west,frame,unload)
				check(n==0,"Unload platform without cart equals the idle frame (%d px) %s %s"%[n,label,tag])
		track_continuous(frame,cell,label)
		if now==4:await route_map_shot("map_cart_transit",now,0)
	check(Route.cart_cell(Route.LAST)==Route.STOPS[-1],"cart_cell(LAST) is the unload platform")
	# Unload at the last stop.
	var purse:=coins()
	var end:Vector2i=Route.STOPS[-1]
	await stand(Vector2(end)+Vector2(0.5,0.5),WEST)
	await interact("unload")
	expect_record(0,1,1,"after unload")
	check(coins()==purse+Route.PAY and snap_coins()==coins(),"Unload pays %d coins (%s): %d -> %d / snapshot %d"%[Route.PAY,tag,purse,coins(),snap_coins()])
	# Back (empty) at the load platform: identical to the idle frame there.
	await stand(PARK,EAST)
	await look_at(EAST)
	var back:Image=await shot("world_back")
	var n:=exact_changed(idle_east,back,cart_box(Route.STOPS[0]))
	check(n==0,"Empty cart back at the load platform, identical to the idle frame (%d px) %s"%[n,tag])
	track_continuous(back,Route.STOPS[0],"world_back")
	await route_map_shot("map_cart_returned",0,1)
	await look_at(WEST)
	var west:Image=await grab()
	var m:=exact_changed(idle_west,west,inner_box(Route.STOPS[-1]))
	check(m==0,"Unload platform empty again (%d px) %s"%[m,tag])

## The player stands on a track cell and on the cart: drawn over both.
func actor_flow()->void:
	var cell:=Vector2i(ON_TRACK.floor())
	await stand(ON_TRACK,EAST)
	await look_at(EAST)
	var on_track:Image=await shot("world_on_track")
	var body:=body_box(ON_TRACK)
	check(cell_box(cell).encloses(body),"Body probe inside the track cell %s (%s)"%[str(cell),tag])
	var seen:=box_difference(idle_east,on_track,body)
	var rails_before:=count_colours(idle_east,inner_box(cell),group("RAIL"),TOL)
	var rails_after:=count_colours(on_track,inner_box(cell),group("RAIL"),TOL)
	print("NOTE %s: on track %s body %.1f%% changed, rails %d -> %d"%[tag,str(cell),seen*100.0,rails_before,rails_after])
	check(seen>=0.3,"Player visible over the track cell %s (%.1f%%) %s"%[str(cell),seen*100.0,tag])
	check(rails_before>=RAIL_MIN and rails_after<rails_before,"Player covers part of the rails (%d -> %d) %s"%[rails_before,rails_after,tag])
	var stop:Vector2=Vector2(Route.STOPS[0])+Vector2(0.5,0.5)
	await stand(stop,EAST)
	await look_at(EAST)
	var on_cart:Image=await shot("world_on_cart")
	var probe:=body_box(stop)
	var over:=box_difference(idle_east,on_cart,probe)
	var wood_before:=count_colours(idle_east,inner_box(Route.STOPS[0]),group("WOOD"),TOL)
	var wood_after:=count_colours(on_cart,inner_box(Route.STOPS[0]),group("WOOD"),TOL)
	print("NOTE %s: on cart body %.1f%% changed, wood %d -> %d"%[tag,over*100.0,wood_before,wood_after])
	check(over>=0.3,"Player visible over the cart (%.1f%%) %s"%[over*100.0,tag])
	check(wood_after<wood_before,"Player covers part of the cart (wood %d -> %d) %s"%[wood_before,wood_after,tag])

# ------------------------------------------------------------------ page --

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func shown(control_name:String)->bool:
	var c:=control(control_name)
	return c!=null and c.is_visible_in_tree()

func node_text(control_name:String)->String:
	var c:=control(control_name)
	if c==null:return ""
	if c is Label:return (c as Label).text
	if c is Button:return (c as Button).text
	var inner:Array[Node]=c.find_children("*","Label",true,false)
	if inner.size()>0:return (inner[0] as Label).text
	return ""

func layout_name()->String:
	return str((app.modal as Node).get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

func page_texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func not_cut(l:Label)->bool:
	if l==null:return false
	if l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func button_not_cut(b:Button)->bool:
	if b==null:return false
	if b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x

func page_fit(label:String)->void:
	check(layout_name()=="ore_route","Page ore_route open (%s): %s"%[label,layout_name()])
	if not is_instance_valid(app.modal):return
	var modal:Control=app.modal
	var page_rect:Rect2=modal.get_global_rect()
	check(root.get_visible_rect().encloses(page_rect),"Page fits the viewport (%s) %s"%[label,str(page_rect)])
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Page needs no outer scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect or c is ColorRect):continue
		check(page_rect.grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,str(c.get_global_rect())])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s)"%[c.name,label])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not page_texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)

func modal_box()->Rect2i:
	if not is_instance_valid(app.modal):return Rect2i()
	var r:Rect2=(app.modal as Control).get_global_rect()
	return Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.floor()))

func picture_box()->Rect2i:
	var pic:=control("OrCart")
	if pic==null:return Rect2i()
	var r:=pic.get_global_rect()
	return Rect2i(Vector2i(r.position.ceil()),Vector2i(r.size.floor())).intersection(Rect2i(Vector2i.ZERO,root.size))

## Contract texts, written out independently of the UI helpers.
func caption_for(stage:int)->String:
	if stage==0:return "裝一車礦料"
	if stage==Route.LAST:return "卸下礦料"
	return "往前推一段（還剩 %d 段）"%(Route.LAST-stage)

func chip_for(stage:int,index:int)->String:
	var here:=clampi(stage,1,7)-1
	var title:="裝礦台" if index==0 else ("卸礦台" if index==6 else str(index))
	if index<here:return "✓ "+title
	if index==here:return "▶ "+title
	return "○ "+title

func away_for(stage:int)->String:
	if stage<=1:return "請沿軌道到裝礦台找台車。"
	if stage==Route.LAST:return "請沿軌道到卸礦台找台車。"
	return "請沿軌道到%d 號停靠點找台車。"%(stage-1)

func top_of(control_name:String)->float:
	var c:=control(control_name)
	return c.get_global_rect().position.y if c!=null else -1.0

## Page texts / state at `stage` with `count` carts today and `total` overall.
## `reason` "" = action enabled with the step caption; otherwise disabled with that reason.
func page_state(label:String,stage:int,count:int,total:int,reason:String)->void:
	var where:="%s %s"%[label,tag]
	check(UI.is_open(app) and layout_name()=="ore_route","Page open (%s): %s"%[where,layout_name()])
	if not is_instance_valid(app.modal):return
	var modal:Node=app.modal
	check(str(modal.name)=="OreRoutePanel","Page node OreRoutePanel (%s): %s"%[where,str(modal.name)])
	check(modal.has_meta("or_body") and modal.get_meta("suppress_world_prompts",false)==true,"Page has or_body and suppress_world_prompts (%s)"%where)
	expect_record(stage,count,total,label)
	var s:Dictionary=app.session.snapshot
	var want_count:="今天 %d／%d 車・累計 %d 車"%[count,Route.DAILY,total]
	check(UI.count_text(s)==want_count,"count_text 「%s」 (%s): %s"%[want_count,where,UI.count_text(s)])
	check(shown("OrCount") and node_text("OrCount")==want_count,"OrCount 「%s」 (%s): %s"%[want_count,where,node_text("OrCount")])
	check(shown("OrStage") and node_text("OrStage")==Route.stage_text(stage),"OrStage 「%s」 (%s): %s"%[Route.stage_text(stage),where,node_text("OrStage")])
	for index in range(7):
		var chip:="OrStop_%d"%index
		check(UI.chip_text(stage,index)==chip_for(stage,index),"chip_text(%d,%d) 「%s」: %s"%[stage,index,chip_for(stage,index),UI.chip_text(stage,index)])
		check(shown(chip) and node_text(chip)==chip_for(stage,index),"%s 「%s」 (%s): %s"%[chip,chip_for(stage,index),where,node_text(chip)])
	var pic:=control("OrCart") as TextureRect
	check(pic!=null and pic.is_visible_in_tree() and pic.texture!=null,"OrCart TextureRect shown (%s)"%where)
	if pic!=null and pic.texture!=null:
		var same:bool=pic.texture==Art.cart_texture(stage>0)
		if not same:
			var a:Image=pic.texture.get_image()
			var b:Image=Art.cart_texture(stage>0).get_image()
			if a!=null and b!=null:
				a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
				same=a.get_size()==b.get_size() and a.get_data()==b.get_data()
		check(same,"OrCart shows cart_texture(%s) (%s)"%[str(stage>0),where])
		check(pic.size.x>=127.0 and pic.size.y>=127.0,"OrCart shown at 128×128 (%s): %s"%[where,str(pic.size)])
	var action:=control("OrAction") as Button
	check(action!=null and action.is_visible_in_tree(),"OrAction button shown (%s)"%where)
	if action!=null:
		check(UI.action_caption(stage)==caption_for(stage),"action_caption(%d) 「%s」: %s"%[stage,caption_for(stage),UI.action_caption(stage)])
		check(action.text==caption_for(stage),"OrAction caption 「%s」 (%s): %s"%[caption_for(stage),where,action.text])
		check(action.focus_mode==Control.FOCUS_ALL,"OrAction focusable (%s)"%where)
		if reason.is_empty():
			check(not action.disabled,"OrAction enabled (%s)"%where)
		else:
			check(action.disabled,"OrAction disabled (%s)"%where)
			check(action.tooltip_text==reason,"OrAction tooltip is the reason (%s): %s"%[where,action.tooltip_text])
	if reason.is_empty():
		check(not shown("OrReason"),"No reason shown (%s): %s"%[where,node_text("OrReason")])
	else:
		check(shown("OrReason") and node_text("OrReason")==reason,"OrReason 「%s」 (%s): %s"%[reason,where,node_text("OrReason")])
		var why:=control("OrReason")
		if why!=null:
			var tint:Color=why.get_theme_color("font_color")
			check(tint==UI.WARN and tint.r>tint.g+0.15 and tint.r>tint.b+0.15,"OrReason in WARN red (%s): %s"%[where,tint.to_html(false)])
	var purse:="鈴幣：%d"%snap_coins()
	check(shown("OrPurse") and node_text("OrPurse")==purse,"OrPurse 「%s」 (%s): %s"%[purse,where,node_text("OrPurse")])
	var pay:="運礦工資：每車 %d 鈴幣"%Route.PAY
	check(shown("OrPay") and node_text("OrPay")==pay,"OrPay 「%s」 (%s): %s"%[pay,where,node_text("OrPay")])
	check(shown("OrBlurb") and node_text("OrBlurb")==Route.BLURB,"OrBlurb is Route.BLURB (%s)"%where)
	check(shown("OrHow") and node_text("OrHow")==Route.HOW,"OrHow is Route.HOW (%s)"%where)
	check(shown("OrDisclaimer") and node_text("OrDisclaimer")==Route.DISCLAIMER,"OrDisclaimer is Route.DISCLAIMER (%s)"%where)
	var order:=["OrHeader","OrCartCard","OrBlurb","OrHow","OrDisclaimer"]
	for i in range(1,order.size()):
		check(top_of(order[i-1])<top_of(order[i]),"%s above %s (%s)"%[order[i-1],order[i],where])
	var inner:=["OrStage","OrStops","OrAction","OrPurse","OrPay"]
	for i in range(1,inner.size()):
		check(top_of(inner[i-1])<top_of(inner[i]),"%s above %s (%s)"%[inner[i-1],inner[i],where])

## Native shot of the open page + fit checks + the cart picture on screen.
func page_shot(step:String,loaded:bool)->Image:
	check(UI.is_open(app),"Page open before the shot %s_%s"%[tag,step])
	if not is_instance_valid(app.modal):return null
	var image:Image=await shot(step)
	panel_shots+=1
	page_fit(step+" "+tag)
	var live:=region_variety(image,modal_box())
	check(live>=6,"Page region of %s_%s is not a flat colour (%d colours)"%[tag,step,live])
	var box:=picture_box()
	check(box.size.x>=64 and box.size.y>=64,"OrCart at least 64 px on screen (%s_%s) %s"%[tag,step,str(box)])
	var variety:=region_variety(image,box)
	check(variety>=4,"OrCart pixels on screen are not uniform (%s_%s): %d colours"%[tag,step,variety])
	var rich:=count_colours(image,box,precious(),TOL)
	print("NOTE %s_%s: OrCart %s, %d colours, %d copper/gold px"%[tag,step,str(box),variety,rich])
	if loaded:check(rich>=1,"Copper / gold pixels in OrCart when loaded (%s_%s): %d"%[tag,step,rich])
	else:check(rich==0,"No copper / gold pixels in OrCart when empty (%s_%s): %d"%[tag,step,rich])
	return image

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	app.action_clock=0
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func open_page(label:String)->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	await stand(NEAR0,EAST)
	await interact(label)
	check(UI.is_open(app) and layout_name()=="ore_route","Interact at the empty cart opens the page (%s %s): %s"%[label,tag,layout_name()])

## Page at stage 0 (first visit): idle -> load through the button -> walk away.
func page_first()->void:
	await open_page("first")
	await press("OrHistory")
	check(is_instance_valid(app.modal) and app.modal.get_meta("history_mode","")=="jinguashi","The cart opens the same historical page (%s)"%tag)
	await press("JinguashiHistoryBack")
	page_state("idle",0,0,0,"")
	var idle:Image=await page_shot("page_idle",false)
	var idle_box:=picture_box()
	await press("OrAction")
	page_state("loaded near",1,0,0,"")
	var loaded:Image=await page_shot("page_loaded",true)
	var unlike:=cross_difference(idle,idle_box,loaded,picture_box())
	check(unlike>=0.03,"OrCart picture changes when loaded (%.1f%%) %s"%[unlike*100.0,tag])
	await stand(PARK,EAST)
	check(UI.is_open(app),"Page stays open when I walk away (%s)"%tag)
	if UI.is_open(app):
		check(UI.away_text(1)==away_for(1),"away_text(1) 「%s」: %s"%[away_for(1),UI.away_text(1)])
		page_state("loaded away",1,0,0,away_for(1))
		await page_shot("page_away",true)
	app._close_modal()
	await settle()

## Second delivery entirely through the page button, up to the daily limit.
func page_daily()->void:
	var purse:=coins()
	await open_page("second")
	page_state("idle again",0,1,1,"")
	await press("OrAction")
	page_state("second loaded",1,1,1,"")
	for stage in range(1,Route.LAST):
		var ok:bool=await press("OrAction")
		if not ok:return
		var now:=stage+1
		page_state("pushed to %d, away"%now,now,1,1,away_for(now))
		var stop:Vector2i=Route.cart_cell(now)
		await stand(Vector2(stop)+Vector2(0.5,0.5),aim_for(now))
		check(UI.is_open(app),"Page stays open while I follow the cart (stage %d, %s)"%[now,tag])
		page_state("at stop %d"%now,now,1,1,"")
	await press("OrAction")
	check(coins()==purse+Route.PAY,"Second unload pays %d (%s): %d -> %d"%[Route.PAY,tag,purse,coins()])
	check(Route.step_block(app.session.snapshot,"load",person())==Route.DAILY_DONE,"Client rules agree: load blocked by DAILY_DONE (%s)"%tag)
	page_state("daily done",0,Route.DAILY,Route.DAILY,Route.DAILY_DONE)
	await page_shot("page_daily_done",false)
	app._close_modal()
	await settle()
	# The world label says so too.
	await stand(NEAR0,EAST)
	var mine:=label_entry(Art.POINT)
	check(Route.cart_label(app.session.snapshot)==Route.LABEL_FULL,"cart_label is LABEL_FULL after two carts (%s)"%tag)
	check(not mine.is_empty() and str(mine.get("title",""))==Route.LABEL_FULL,"Focused label 「%s」 (%s): %s"%[Route.LABEL_FULL,tag,str(mine.get("title","none"))])

func size_flow()->void:
	await world_idle()
	await page_first()
	await loaded_motion()
	await route_flow()
	await actor_flow()
	await page_daily()

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/運礦路線預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	pure_checks()
	path=OS.get_environment("TEMP").path_join("ore-route-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"運礦旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	WanganUI.dismiss(app)
	app.view.set_process(false)
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(panel_shots==8,"4 page screenshots per size (%d)"%panel_shots)
	check(shots==44,"22 screenshots per size (%d)"%shots)
	w.state.erase(Route.STATE_KEY)  # PRESET cleanup before the final save
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
