extends SceneTree
## 第 40 章北門合作鹽田「儲滷槽」native render check at 1024×640 and 1280×800 (run WITHOUT --headless).
## Screenshots go to outputs/儲滷槽預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_salt_revisit_scene.gd / test_tea_service_scene.gd (real main.tscn host).
##
## Art is runtime-painted, no new PNGs: salt_brine_art.gd (32×48 oval stone-and-plank vat with a
## copper outlet, a level gauge and five level states empty / low / mid / high / full), drawn by
## salt_world_art.draw_row on SaltBrine.TANK (48,14), right of the co-op shed.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * the three Beimen gates repaired (gates + repaired_at) and my salt_pan record
##    (letter / intro / raked 1) so a state.salt_brine record is schema-valid;
##  * THE TANK LEVEL: state.salt_brine={"level":n} is written directly for every level state
##    (0, 6, 15, 25, 30) — the store/pour actions are covered by test_salt_brine*/journey;
##  * state.time (a sunny, dry Beimen day);
##  * the local player is teleported by writing region/x/y; the camera is aimed directly
##    (view processing paused so the frame is still); view.zoom / reduced_motion set directly.
##  PAGE PHASE (page_phase, after both sizes' world shots so those frames are unchanged):
##  * app.bindings reset to defaults from an isolated %TEMP% file; app.playing=true if it was false;
##  * salt_pan.lots / apprentice / pans reset to fresh; lot 0 claimed by me (owner; wheel=false,
##    then wheel=true) — the earned claim / wheel install is covered by the salt journey tests;
##  * pans 0 / 1 (my west / east pans) written as empty / brine {p, t=now, f="wheel"} / salt:
##    no_wheel both empty; ready west p=300 (6 成) + east empty; rain west p=150 + east empty;
##    full west p=470 (9 成) + east salt;
##  * state.salt_brine={"level":n}: no_wheel 0, ready 12, rain 8, full 30, revisit 12;
##  * state.time: the sunny dry day above, and a rainy Beimen day (Salt.raining) for page_rain;
##  * session rate bucket 1 cleared before each interact key.
##  REALLY EXERCISED there: KEY_E through root.push_input -> main._unhandled_input -> _interact
##  next to the tank (TANK_STAND) opens the 儲滷槽 page; KEY_E at 阿曬 (SR.WORKER_STAND) opens her page
##  and its SaltRevisitEntry (pressed.emit) opens the 鹽籃批次 page.
## REALLY RENDERED: the real WorldView of the host app (HUD included) in a native window.
## SHOTS per size: empty, low, mid, high, full, full_motion, far_empty, far_full, wide
##  (zoom 1: shed + tank + nearby pans), focus_label, plus the crop tank_strip (five states, ×4);
##  then the pages: page_no_wheel, page_ready, page_rain, page_full, revisit_brine_line (16 per size).
## PAGE ASSERTS: modal kind salt_brine / salt_revisit; the page lies inside the viewport with no outer
##  scroll; every visible label / button / icon inside the page and the scroll area, no label cut or
##  ellipsized; level text「槽裡 n／30 桶」(or SaltBrineLine with n); per-state buttons / reasons;
##  page_full is the tallest; the written PNG reloads at the viewport size and the page region is
##  not a flat colour.
## ASSERTS: footprints contain the tank exactly at (48,14) and still equal SaltPan.blocked over
##  LAND; the tank canvas stays right of the shed sprite; the level states differ pairwise inside
##  the tank's rect (zoom 2 and zoom 1); pixels around it (shed, yard, other props) are identical
##  between level states; the tank is drawn as painted (not hidden by the shed / HUD); its art
##  differs strongly from the co-op chest sprite and from a pan tile; motion on vs reduced motion
##  is identical; the focused label reads「儲滷槽・n／30 桶」 and stays off the tank.
const World=preload("res://scripts/world.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Brine=preload("res://scripts/salt_brine.gd")
const Art=preload("res://scripts/salt_brine_art.gd")
const SaltArt=preload("res://scripts/salt_art.gd")
const SaltWorldArt=preload("res://scripts/salt_world_art.gd")
const Weather=preload("res://scripts/weather.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const BrineUI=preload("res://scripts/salt_brine_ui.gd")
const RevisitUI=preload("res://scripts/salt_revisit_ui.gd")
const SR=preload("res://scripts/salt_revisit.gd")
## Camera aim for the 阿曬 page shot (the batch page is opened from her page).
const WORKER_AIM:=Vector2(45.0,17.5)
## Level written for each visual state.
const LEVELS:={"empty":0,"low":6,"mid":15,"high":25,"full":30}
## Out of focus range (5 tiles from the tank, far from every other site), east of the yard.
const VIEW_SPOT:=Vector2(51.5,18.5)
## South of the tank: the tank is the strict-nearest site (2.8 tiles; 阿曬 is 4.0).
const FOCUS_SPOT:=Vector2(48.5,17.3)
## Close shots centre on the tank; the wide shot on the shed/yard.
const TANK_AIM:=Vector2(48.5,14.2)
const WIDE_AIM:=Vector2(45.0,17.0)
## Minimum share of the tank rect that changes between two level states.
const MIN_STATE_CHANGE:=0.02
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
var day_time:=-1.0
var rain_time:=-1.0
var page_shots:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SALT_BRINE_SCENE_TESTS checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
func refresh(aim:Vector2)->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	var zoom:float=float(app.view.view_zoom())
	app.view.camera=(aim*32.0-app.view.get_viewport_rect().size/zoom*0.5).round()
	app.view.queue_redraw()
	hide_toast()
	await settle()

func stand(at:Vector2,aim:Vector2)->void:
	var p:Dictionary=person()
	p.region=Salt.REGION  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	await refresh(aim)
	var v=app.view
	var me:String=app.session.own_id
	v.starts[me]=at
	v.goals[me]=at
	v.display_positions[me]=at
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:app.hud.remove_child(ribbon);ribbon.queue_free()
	await refresh(aim)

func set_level(level:int)->void:
	w.state[Brine.STATE_KEY]={"level":level}  # PRESET
	check(Brine.valid(w.state),"Fixture salt_brine level %d is schema-valid"%level)

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("SALT_BRINE_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

## World-pixel rect -> view rect (before zoom).
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

func tank_box()->Rect2i:
	return pixel_box(view_rect(Art.canvas_rect()))

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

## Pixels (exact compare) inside `area` but outside every rect of `skip` that differ.
func changed_outside(a:Image,b:Image,area:Rect2i,skip:Array)->int:
	var r:=area.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	var n:=0
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			if a.get_pixel(x,y)==b.get_pixel(x,y):continue
			var masked:=false
			for s:Rect2i in skip:
				if s.has_point(Vector2i(x,y)):masked=true;break
			if not masked:n+=1
	return n

## Share of the tank's opaque texture pixels that appear on screen as painted.
func tank_as_painted(image:Image,state:String,label:String)->void:
	var art:Image=Art.texture_for_state(state).get_image()
	art.convert(Image.FORMAT_RGBA8)
	var top:Vector2=Art.canvas_rect().position
	var matched:=0
	var total:=0
	for y in range(0,Art.SIZE.y,2):
		for x in range(0,Art.SIZE.x,2):
			var c:=art.get_pixel(x,y)
			if c.a<0.99:continue
			total+=1
			var at:=view_to_pixels(view_rect(Rect2(top+Vector2(x+0.5,y+0.5),Vector2.ZERO))).position
			var px:=Vector2i(at.floor())
			if px.x<0 or px.y<0 or px.x>=image.get_width() or px.y>=image.get_height():continue
			var q:=image.get_pixel(px.x,px.y)
			if absf(c.r-q.r)+absf(c.g-q.g)+absf(c.b-q.b)<0.15:matched+=1
	var share:=float(matched)/maxf(1.0,float(total))
	print("NOTE %s: tank pixels as painted %.0f%%"%[label,share*100.0])
	check(share>=0.85,"Tank drawn as painted, nothing covers it (%s): %.0f%%"%[label,share*100.0])

func tank_on_screen(label:String)->void:
	var px:=view_to_pixels(view_rect(Art.art_rect()))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Tank on screen (%s) %s"%[label,str(px)])
	for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Tank clear of HUD %s (%s)"%[panel.name,label])

## Two images composited on the same ground colour: share of pixels that differ.
func image_difference(ia:Image,ib:Image)->float:
	ia.convert(Image.FORMAT_RGBA8);ib.convert(Image.FORMAT_RGBA8)
	if ib.get_size()!=ia.get_size():ib.resize(ia.get_width(),ia.get_height(),Image.INTERPOLATE_NEAREST)
	var ground:=Color("c9b48a")
	var changed:=0
	var total:=0
	for y in ia.get_height():
		for x in ia.get_width():
			var p:=ia.get_pixel(x,y);var q:=ib.get_pixel(x,y)
			if p.a<0.5 and q.a<0.5:continue
			total+=1
			var pc:=ground.lerp(Color(p.r,p.g,p.b),p.a);var qc:=ground.lerp(Color(q.r,q.g,q.b),q.a)
			if absf(pc.r-qc.r)+absf(pc.g-qc.g)+absf(pc.b-qc.b)>0.12:changed+=1
	return float(changed)/maxf(1.0,float(total))

func texture_image(tex:Texture2D)->Image:
	if tex==null:return null
	var img:=tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

# ------------------------------------------------------------- pure checks --

func pure_checks()->void:
	check(Art.state_of(0)=="empty" and Art.state_of(1)=="low" and Art.state_of(10)=="low" and Art.state_of(11)=="mid" and Art.state_of(20)=="mid" and Art.state_of(21)=="high" and Art.state_of(29)=="high" and Art.state_of(30)=="full" and Art.state_of(-3)=="empty" and Art.state_of(99)=="full","Level -> state thresholds 0 / 1–10 / 11–20 / 21–29 / 30")
	check(Art.label(15)=="儲滷槽・15／30 桶" and Art.label(0)=="儲滷槽・0／30 桶","Tank label text")
	check(Brine.TANK==Salt.BRINE_TANK and Salt.site_at(Brine.TANK)=="brine_tank" and Salt.blocked(Brine.TANK),"Tank cell (48,14) is the blocked brine_tank site")
	# Footprints: the tank exactly at (48,14), no overlap, union == SaltPan.blocked over LAND.
	var tank_items:=0
	var covered:={}
	var overlap:=false
	for item:Dictionary in SaltWorldArt.footprints():
		var rect:Rect2i=item.rect
		if str(item.id)=="brine_tank":
			tank_items+=1
			check(rect==Rect2i(Vector2i(48,14),Vector2i.ONE),"Tank footprint is exactly (48,14) 1×1: %s"%str(rect))
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				if covered.has(Vector2i(x,y)):overlap=true
				covered[Vector2i(x,y)]=str(item.id)
	check(tank_items==1,"Tank listed once in SaltWorldArt.footprints() (%d)"%tank_items)
	check(not overlap,"Footprints do not overlap")
	check(str(covered.get(Vector2i(48,14),""))=="brine_tank","(48,14) is drawn by the tank")
	var parity:=true
	for y in range(Salt.LAND.position.y,Salt.LAND.end.y):
		for x in range(Salt.LAND.position.x,Salt.LAND.end.x):
			var p:=Vector2i(x,y)
			if Salt.blocked(p)!=covered.has(p):
				parity=false
				print("NOTE collision mismatch at %s blocked=%s drawn=%s"%[p,Salt.blocked(p),covered.get(p,"")])
	check(parity,"Drawn footprints == SaltPan.blocked over LAND")
	# The tank canvas stays in its own column, right of the shed sprite (drawn bottom-centred on SHED).
	var shed_size:=SaltArt.structure_size("shed")
	var shed_right:=SaltWorldArt.rect_center(Salt.SHED).x*32+shed_size.x*0.5
	var canvas:=Art.canvas_rect()
	check(canvas.position.x>=shed_right and canvas.position.x==Brine.TANK.x*32 and canvas.end.x==(Brine.TANK.x+1)*32,"Tank canvas x %.0f..%.0f is right of the shed sprite (ends at %.0f)"%[canvas.position.x,canvas.end.x,shed_right])
	check(canvas.size==Vector2(32,48) and canvas.end.y==(Brine.TANK.y+1)*32,"Tank canvas is 32×48 standing on its cell")
	# Art: states pairwise distinct; strongly unlike the co-op chest and a pan tile.
	var states:Array=Art.STATES
	for i in states.size():
		var tex:=Art.texture_for_state(str(states[i]))
		check(tex!=null and tex.get_size()==Vector2(32,48),"Tank texture %s is 32×48"%states[i])
		check(Art.texture_for_state(str(states[i]))==tex,"Tank texture %s is cached (static)"%states[i])
		for j in range(i+1,states.size()):
			var unlike:=image_difference(texture_image(tex),texture_image(Art.texture_for_state(str(states[j]))))
			print("NOTE tank art %s vs %s %.1f%%"%[states[i],states[j],unlike*100.0])
			check(unlike>=0.04,"Tank art %s differs from %s (%.1f%%)"%[states[i],states[j],unlike*100.0])
	for state in ["empty","mid","full"]:
		var tile:=texture_image(Art.texture_for_state(state)).get_region(Rect2i(0,16,32,32))
		var chest:=texture_image(SaltArt.structure_texture("coop_chest"))
		check(chest!=null,"Co-op chest art exists")
		if chest!=null:
			var unlike:=image_difference(tile,chest)
			print("NOTE tank %s vs co-op chest %.0f%%"%[state,unlike*100.0])
			check(unlike>=0.3,"Tank (%s) differs strongly from the co-op chest (%.0f%%)"%[state,unlike*100.0])
		for pan_state in ["empty","brine","salt"]:
			var pan:=texture_image(SaltArt.pan_texture(pan_state))
			check(pan!=null,"Pan art %s exists"%pan_state)
			if pan==null:continue
			var cell:=pan.get_region(Rect2i(pan.get_width()/2-16,pan.get_height()/2-16,32,32))
			var unlike:=image_difference(tile,cell)
			print("NOTE tank %s vs pan tile %s %.0f%%"%[state,pan_state,unlike*100.0])
			check(unlike>=0.3,"Tank (%s) differs strongly from a %s pan tile (%.0f%%)"%[state,pan_state,unlike*100.0])

# ------------------------------------------------------------------ flows --

func level_flow()->void:
	app.view.zoom=2.0
	app.view.reduced_motion=true
	var images:={}
	for state:String in Art.STATES:
		set_level(int(LEVELS[state]))
		await stand(VIEW_SPOT,TANK_AIM)
		check(Brine.level(app.view.data)==int(LEVELS[state]),"View snapshot carries level %d (%s)"%[int(LEVELS[state]),tag])
		check(str(app.view.interaction_focus())=="","Nothing focused at the viewing spot (%s): %s"%[tag,str(app.view.interaction_focus())])
		var image:Image=await shot(state)
		images[state]=image
		tank_on_screen(state+" "+tag)
		tank_as_painted(image,state,state+" "+tag)
	var box:=tank_box()
	var near:=pixel_box(view_rect(Rect2(Vector2(42,11)*32,Vector2(11,9)*32)))
	var skip:=[box.grow(1)]
	for panel:Dictionary in hud_panels():
		var r:Rect2=panel.rect
		skip.append(Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.ceil())+Vector2i.ONE))
	var states:Array=Art.STATES
	for i in states.size():
		for j in range(i+1,states.size()):
			var a:Image=images[states[i]];var b:Image=images[states[j]]
			var inside:=box_difference(a,b,box)
			print("NOTE %s: tank rect %s vs %s %.1f%%"%[tag,states[i],states[j],inside*100.0])
			check(inside>=MIN_STATE_CHANGE,"Level states %s / %s differ inside the tank rect (%.1f%%) %s"%[states[i],states[j],inside*100.0,tag])
			var outside:=changed_outside(a,b,near,skip)
			check(outside==0,"Nothing outside the tank rect changes between %s and %s (%d px) %s"%[states[i],states[j],outside,tag])
	# Close-up strip of the five states (×4).
	var strip:=Image.create_empty((box.size.x+4)*states.size(),box.size.y,false,Image.FORMAT_RGBA8)
	strip.fill(Color("392d23"))
	var clip:=box.intersection(Rect2i(Vector2i.ZERO,root.size))
	for i in states.size():
		strip.blit_rect(images[states[i]],clip,Vector2i(i*(box.size.x+4),0))
	strip.resize(strip.get_width()*4,strip.get_height()*4,Image.INTERPOLATE_NEAREST)
	save_image(strip,"tank_strip")
	# Motion on vs reduced motion: identical (the tank has no animation).
	app.view.reduced_motion=false
	app.view.set_process(true)
	await create_timer(0.4).timeout
	app.view.set_process(false)
	await refresh(TANK_AIM)
	var moving:Image=await shot("full_motion")
	var motion_change:=box_difference(images.full,moving,box)
	check(motion_change==0.0,"Tank identical with motion on vs reduced motion (%.2f%%) %s"%[motion_change*100.0,tag])
	await create_timer(0.3).timeout
	var later:Image=await grab()
	check(box_difference(moving,later,box)==0.0,"Tank static frame to frame with motion on (%s)"%tag)
	app.view.reduced_motion=true

func wide_flow()->void:
	# Zoom 1 (遠景): shed + tank + the apprentice / lot 2 pans.
	app.view.zoom=1.0
	set_level(int(LEVELS["empty"]))
	await stand(VIEW_SPOT,WIDE_AIM)
	var empty:Image=await shot("far_empty")
	set_level(int(LEVELS["full"]))
	await refresh(WIDE_AIM)
	var full:Image=await shot("far_full")
	var box:=tank_box()
	var change:=box_difference(empty,full,box)
	print("NOTE %s: zoom 1 tank rect empty vs full %.1f%%"%[tag,change*100.0])
	check(change>=MIN_STATE_CHANGE,"Zoom 1: empty and full differ inside the tank rect (%.1f%%) %s"%[change*100.0,tag])
	var near:=pixel_box(view_rect(Rect2(Vector2(32,11)*32,Vector2(21,13)*32)))
	var skip:=[box.grow(1)]
	for panel:Dictionary in hud_panels():
		var r:Rect2=panel.rect
		skip.append(Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.ceil())+Vector2i.ONE))
	check(changed_outside(empty,full,near,skip)==0,"Zoom 1: shed, pans and yard unchanged between empty and full (%s)"%tag)
	set_level(int(LEVELS["mid"]))
	await refresh(WIDE_AIM)
	var wide:Image=await shot("wide")
	tank_on_screen("wide "+tag)
	tank_as_painted(wide,"mid","wide "+tag)
	var shed_px:=view_to_pixels(view_rect(Rect2(Vector2(Salt.SHED.position)*32,Vector2(Salt.SHED.size)*32)))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(shed_px),"Shed in the wide shot (%s)"%tag)
	var pans_px:=view_to_pixels(view_rect(Rect2(Vector2(Salt.pan_rect(18).position)*32,Vector2(Salt.pan_rect(19).end-Salt.pan_rect(18).position)*32)))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(pans_px),"Apprentice pans in the wide shot (%s)"%tag)
	app.view.zoom=2.0

func focus_flow()->void:
	app.view.zoom=2.0
	set_level(int(LEVELS["mid"]))
	await stand(FOCUS_SPOT,Vector2(48.5,15.6))
	check(str(app.view.interaction_focus())==SaltWorldArt.BRINE_TANK_SITE,"Tank focused at %s (%s): %s"%[str(FOCUS_SPOT),tag,str(app.view.interaction_focus())])
	var image:Image=await shot("focus_label")
	tank_on_screen("focus "+tag)
	tank_as_painted(image,"mid","focus "+tag)
	var mine:Dictionary={}
	for entry:Dictionary in placements():
		if str(entry.id)==SaltWorldArt.BRINE_TANK_SITE:mine=entry
	var want:=Art.label(int(LEVELS["mid"]))
	check(not mine.is_empty() and str(mine.title)==want and bool(mine.get("active",false)),"Focused label 「%s」 (%s): %s"%[want,tag,str(mine.get("title","none"))])
	if mine.is_empty():return
	var r:Rect2=mine.rect
	var art:=view_rect(Art.art_rect())
	check(not r.intersects(art.grow(-1.0)),"Label not over the tank (%s) %s vs %s"%[tag,str(r),str(art)])
	var px:=view_to_pixels(r)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Label on screen (%s)"%tag)
	for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Label clear of HUD %s (%s)"%[panel.name,tag])

func size_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await level_flow()
	await wide_flow()
	await focus_flow()

# ------------------------------------------------------------------ pages --

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func button(control_name:String)->Button:
	return control(control_name) as Button

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func shown(control_name:String)->bool:
	var c:=control(control_name)
	return c!=null and c.is_visible_in_tree()

func layout_name()->String:
	return str((app.modal as Node).get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

func salt_site()->String:
	return str((app.modal as Node).get_meta("salt_site","")) if is_instance_valid(app.modal) else ""

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

## Visible label and button texts of the open page.
func page_texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

## As test_salt_brine_ui.not_cut: no trimming, every line visible, unwrapped lines fit their width.
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

## Fit checks of test_salt_revisit_scene.page_fits plus the stricter per-control checks of
## test_salt_brine_ui.layout_ok: inside the viewport, no outer scrolling, every visible label /
## button / icon inside the page and the visible scroll area, nothing cut, no ellipsis.
func page_fit(label:String,expected:String)->void:
	check(layout_name()==expected,"Page %s open (%s): %s"%[expected,label,layout_name()])
	if not is_instance_valid(app.modal):return
	var modal:Control=app.modal
	var page_rect:Rect2=modal.get_global_rect()
	check(root.get_visible_rect().encloses(page_rect),"Page fits the viewport (%s) %s"%[label,str(page_rect)])
	var outer:=control("ModalScroll") as ScrollContainer
	check(outer!=null,"Outer scroll container found (%s)"%label)
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect or c is ColorRect):continue
		check(page_rect.grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,str(c.get_global_rect())])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,str(c.get_global_rect())])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not page_texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)

## Distinct colours on a 20×14 grid inside `box` (clipped to the image).
func region_variety(image:Image,box:Rect2i)->int:
	var r:=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if r.size.x<=0 or r.size.y<=0:return 0
	var seen:={}
	for gx in range(20):
		for gy in range(14):
			var c:Color=image.get_pixel(r.position.x+int((gx+0.5)*r.size.x/20.0),r.position.y+int((gy+0.5)*r.size.y/14.0))
			seen[c.to_html(false)]=true
	return seen.size()

func modal_box()->Rect2i:
	if not is_instance_valid(app.modal):return Rect2i()
	var r:Rect2=(app.modal as Control).get_global_rect()
	return Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.floor()))

## Native shot of the open page + fit checks + the written PNG reloads with a non-flat page region.
func page_shot(step:String,expected:String)->void:
	check(layout_name()==expected,"Page %s open before the shot %s_%s: %s"%[expected,tag,step,layout_name()])
	if not is_instance_valid(app.modal):return
	var image:Image=await shot(step)
	page_shots+=1
	page_fit(step+" "+tag,expected)
	var box:=modal_box()
	var live:=region_variety(image,box)
	check(live>=6,"Page region of %s_%s is not a flat colour (%d colours)"%[tag,step,live])
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(FileAccess.file_exists(file),"Page PNG written %s"%file)
	if not FileAccess.file_exists(file):return
	var saved:=Image.load_from_file(file)
	check(saved!=null and not saved.is_empty() and saved.get_size()==root.size,"Page PNG reloads at the viewport size (%s_%s)"%[tag,step])
	if saved==null or saved.is_empty():return
	saved.convert(Image.FORMAT_RGBA8)
	var stored:=region_variety(saved,box)
	print("NOTE %s_%s: page %s, %d colours in the saved page region"%[tag,step,str(box),stored])
	check(stored>=6,"Saved PNG page region of %s_%s is not a flat colour (%d colours)"%[tag,step,stored])

## The interact key (default binding E) through the real input path.
func press_interact(aim:Vector2)->void:
	app.session.rates[1].clear()
	for pressed:bool in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=KEY_E;e.physical_keycode=KEY_E;e.pressed=pressed
		root.push_input(e)
	await settle()
	await refresh(aim)

func reset_pans()->void:
	var data:Dictionary=w.state.salt_pan
	for i in data.lots.size():data.lots[i]=Salt.fresh_lot()  # PRESET
	data.apprentice=Salt.fresh_apprentice()  # PRESET
	for i in data.pans.size():data.pans[i]=Salt.fresh_pan()  # PRESET

## Lot 0 is mine (pans 0 = west, 1 = east).
func own_lot(wheel:bool)->void:
	var cfg:Dictionary=Salt.fresh_lot()
	cfg.owner=id;cfg.wheel=wheel
	w.state.salt_pan.lots[0]=cfg  # PRESET

func set_pan(i:int,state:String,p:float=0.0)->void:
	var pan:Dictionary=w.state.salt_pan.pans[i]
	pan.s=state  # PRESET
	match state:
		"brine":pan.p=p;pan.t=float(w.state.time);pan.f="wheel"  # PRESET
		"salt":pan.p=Salt.NEED;pan.t=float(w.state.time);pan.f="wheel"  # PRESET
		_:pan.p=0.0;pan.t=0.0;pan.f=""  # PRESET

## Close any page, stand at TANK_STAND and press the interact key.
func open_tank(label:String)->void:
	await close_page()
	await stand(Brine.TANK_STAND,TANK_AIM)
	await press_interact(TANK_AIM)
	check(layout_name()==BrineUI.LAYOUT,"E next to the tank opens the 儲滷槽 page (%s %s): %s"%[label,tag,layout_name()])

func level_line_is(n:int,label:String)->void:
	var want:String="槽裡 %d／30 桶"%n
	check(label_text("SbLevel")==want and shown("SbLevel"),"Level text 「%s」 (%s %s): %s"%[want,label,tag,label_text("SbLevel")])

func button_is(control_name:String,enabled:bool,caption_or_reason:String,label:String)->void:
	var b:=button(control_name)
	check(b!=null and b.is_visible_in_tree() and b.disabled==not enabled,"%s %s (%s %s)"%[control_name,"enabled" if enabled else "disabled",label,tag])
	if b==null:return
	if enabled:check(b.text==caption_or_reason,"%s caption 「%s」 (%s %s): %s"%[control_name,caption_or_reason,label,tag,b.text])
	else:check(b.tooltip_text==caption_or_reason,"%s reason 「%s」 (%s %s): %s"%[control_name,caption_or_reason,label,tag,b.tooltip_text])

func reason_line_is(side:String,expected:String,label:String)->void:
	var got:=label_text("SbReason_"+side)
	check(got==expected and (expected.is_empty() or shown("SbReason_"+side)),"%s reason 「%s」 (%s %s): 「%s」"%[side,expected.replace("\n"," / "),label,tag,got.replace("\n"," / ")])

func page_flow()->Dictionary:
	var heights:={}
	w.state.time=day_time  # PRESET (the sunny dry day)
	reset_pans()
	# 1. A lot without a wheel: one red reason card.
	own_lot(false)
	set_level(0)
	await open_tank("no wheel")
	check(shown("SbBlock") and label_text("SbBlockText")==Brine.NO_WHEEL,"Single NO_WHEEL card (%s): %s"%[tag,label_text("SbBlockText")])
	check(not shown("SbCards"),"No pan cards without a wheel (%s)"%tag)
	level_line_is(0,"no wheel")
	await page_shot("page_no_wheel",BrineUI.LAYOUT)
	heights["no_wheel"]=float(modal_box().size.y)
	# 2. Wheel lot, west pan about 6 成, east empty, tank 12: store and pour both possible west.
	own_lot(true)
	set_level(12)
	set_pan(0,"brine",300.0)
	set_pan(1,"empty")
	await open_tank("ready")
	check(shown("SbCards") and not shown("SbBlock"),"Pan cards shown (ready %s)"%tag)
	level_line_is(12,"ready")
	check(label_text("SbState_a")=="滷水約 6 成","West pan 6 成 (%s): %s"%[tag,label_text("SbState_a")])
	check(label_text("SbState_b")==BrineUI.STATE_EMPTY,"East pan empty (%s): %s"%[tag,label_text("SbState_b")])
	button_is("Sb_store_a",true,"收滷 6 桶","ready")
	button_is("Sb_pour_a",true,"放滷 3 桶","ready")
	button_is("Sb_store_b",false,Brine.PAN_EMPTY,"ready")
	reason_line_is("a","","ready")
	reason_line_is("b",Brine.PAN_EMPTY,"ready")
	check(not shown("SbRain"),"No rain line on the dry day (%s)"%tag)
	await page_shot("page_ready",BrineUI.LAYOUT)
	heights["ready"]=float(modal_box().size.y)
	# 3. A rainy Beimen day, west storable, tank 8: pour refused with the rain reason.
	w.state.time=rain_time  # PRESET (a rainy Beimen day)
	set_level(8)
	set_pan(0,"brine",150.0)
	set_pan(1,"empty")
	await open_tank("rain")
	check(Brine.rainy_now(app.session.snapshot),"Snapshot is a rainy Beimen day (%s)"%tag)
	check(shown("SbRain") and label_text("SbRain")==BrineUI.RAIN_LINE,"Rain line (%s): %s"%[tag,label_text("SbRain")])
	level_line_is(8,"rain")
	button_is("Sb_store_a",true,"收滷 3 桶","rain")
	button_is("Sb_pour_a",false,Brine.RAIN_POUR,"rain")
	reason_line_is("a","放滷："+Brine.RAIN_POUR,"rain")
	await page_shot("page_rain",BrineUI.LAYOUT)
	heights["rain"]=float(modal_box().size.y)
	# 4. Tank full, west brine almost crystallised, east salt: two reason lines (tallest).
	w.state.time=day_time  # PRESET
	set_level(30)
	set_pan(0,"brine",470.0)
	set_pan(1,"salt")
	await open_tank("full")
	level_line_is(30,"full")
	check(label_text("SbState_a")=="滷水約 9 成" and label_text("SbState_b")==BrineUI.STATE_SALT,"Pan states 9 成 / salt (%s): %s / %s"%[tag,label_text("SbState_a"),label_text("SbState_b")])
	button_is("Sb_store_a",false,Brine.TANK_FULL,"full")
	button_is("Sb_pour_a",false,Brine.PAN_RICH,"full")
	button_is("Sb_store_b",false,Brine.PAN_SALT,"full")
	reason_line_is("a","收滷："+Brine.TANK_FULL+"\n放滷："+Brine.PAN_RICH,"full")
	reason_line_is("b",Brine.PAN_SALT,"full")
	await page_shot("page_full",BrineUI.LAYOUT)
	heights["full"]=float(modal_box().size.y)
	# 5. 阿曬's page -> 鹽籃批次 with SaltBrineLine at level 12.
	await close_page()
	set_level(12)
	await stand(SR.WORKER_STAND,WORKER_AIM)
	await press_interact(WORKER_AIM)
	check(layout_name()=="salt_pan" and salt_site()=="worker","E opens 阿曬's page (%s): %s %s"%[tag,layout_name(),salt_site()])
	var entry:=button("SaltRevisitEntry")
	check(entry!=null and not entry.disabled and entry.is_visible_in_tree(),"鹽籃批次 entry on 阿曬's page (%s)"%tag)
	if entry!=null and not entry.disabled:
		entry.grab_focus()
		entry.pressed.emit()
		await settle()
		await refresh(WORKER_AIM)
	check(layout_name()==RevisitUI.LAYOUT,"Entry opens the batch page (%s): %s"%[tag,layout_name()])
	if layout_name()==RevisitUI.LAYOUT:
		var want:String=RevisitUI.BRINE_LINE%12
		check(shown("SaltBrineLine") and label_text("SaltBrineLine")==want,"SaltBrineLine with level 12 (%s): %s"%[tag,label_text("SaltBrineLine")])
		check(label_text("SaltBrineLine").begins_with("儲滷槽 12／30 桶"),"SaltBrineLine reads 12／30 (%s)"%tag)
		await page_shot("revisit_brine_line",RevisitUI.LAYOUT)
	await close_page()
	return heights

func page_phase()->void:
	# Default key bindings from an isolated file (a player's own rebinding must not leak in).
	app.bindings.load_preferences(path+".bindings")
	if not app.playing:
		print("NOTE app.playing was false after host; set true for key input")
		app.playing=true
	app.view.zoom=2.0
	app.view.reduced_motion=true
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		var heights:Dictionary=await page_flow()
		var full_h:float=float(heights.get("full",0.0))
		for state:String in ["no_wheel","ready","rain"]:
			var h:float=float(heights.get(state,0.0))
			check(full_h>=h,"page_full is the tallest 儲滷槽 page (%s): full %.0f vs %s %.0f"%[tag,full_h,state,h])
	reset_pans()
	w.state.time=day_time  # PRESET

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/儲滷槽預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	pure_checks()
	for d in range(1,60):
		var t:=float(d)*Weather.DAY_SECONDS+30.0
		if Weather.outdoor_id(float(d))=="sunny" and not Weather.rains(float(d),Salt.REGION) and not Salt.raining(t):
			day_time=t
			break
	check(day_time>0.0,"Calendar has a sunny, dry Beimen day")
	for d in range(1,60):
		var t:=float(d)*Weather.DAY_SECONDS+30.0
		if Salt.raining(t):
			rain_time=t
			break
	check(rain_time>0.0,"Calendar has a rainy Beimen day")
	path=OS.get_environment("TEMP").path_join("salt-brine-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"儲滷槽旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	WanganUI.dismiss(app)
	app.view.set_process(false)
	for g in Salt.GATE_ROWS.size():w.state.salt_pan.gates[g]={"plank":6,"resin":1,"stone":4}  # PRESET
	w.state.salt_pan.repaired_at=1.0  # PRESET
	var rec:Dictionary=Salt.RECORD.duplicate(true)
	rec.letter=true;rec.intro=true;rec.raked=1
	w.state.salt_pan.players[id]=rec  # PRESET
	person().travel_book.visited[Salt.REGION]=true  # PRESET
	w.state.time=maxf(day_time,30.0)  # PRESET
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=22,"11 screenshots per size (%d)"%shots)
	await page_phase()
	print("NOTE pages done at %.1f s"%[(Time.get_ticks_msec()-started)/1000.0])
	check(page_shots==10,"5 page screenshots per size (%d)"%page_shots)
	check(shots>=32,"16 screenshots per size (%d)"%shots)
	w.state.erase(Brine.STATE_KEY)  # PRESET cleanup before the final save
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
