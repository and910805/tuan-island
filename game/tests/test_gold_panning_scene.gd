extends SceneTree
## 第 40 章金瓜石初訪「河邊淘砂金」native render check at 1024×640 and 1280×800 (run WITHOUT --headless).
## Screenshots go to outputs/淘砂金預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_salt_brine_scene.gd / test_jinguashi_revisit_scene.gd (real main.tscn host).
##
## Art is runtime-painted, no new PNGs: gold_panning_art.draw_site (plank platform + panning pan
## on the water cell SITE (5,26), two-frame ripple unless reduced motion), drawn by world_view's
## Jinguashi row loop; the panel's pan = gold_panning_art.pan_texture(stage) (64×64, stage 0..5).
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.time = 30.0 (day 1, sunny); state.gold_panning erased and my bag's gold_ore set to 0
##    before each size (and gold_panning erased again before the final save);
##  * the local player is teleported by writing region="jinguashi" / x / y (bank spots
##    (7.5,26.5) in reach, (9.5,26.5) out of reach, the shuttle stop (12.5,20.5) far away);
##  * the camera is aimed directly (view processing paused so the frame is still);
##    view.zoom=2, view.reduced_motion and view.elapsed (the ripple clock) are written directly
##    for the deterministic frames.
## REALLY PLAYED / EXERCISED:
##  * view processing re-enabled for ~2 s (real elapsed clock) with motion on and with reduced
##    motion, to show the ripple animates / stays still on its own;
##  * main._interact() on the bank opens the 淘砂 panel; every pan step (scoop, sift, swirl ×3,
##    pick) is the panel's GpAction button (pressed.emit) -> Session.perform -> World ->
##    GoldPanning.apply -> snapshot -> GoldPanUI.refresh; three full pans reach the daily limit;
##  * the player moved away while the panel is open -> panel refresh shows away_text().
## REALLY RENDERED: the real WorldView of the host app (HUD included) in a native window.
## SHOTS per size (9): world_site, world_focus, world_reduced, panel_empty, panel_gravel,
##  panel_swirl, panel_gold, panel_daily_done, panel_away.
## ASSERTS: the SITE cell's BOUNDS rect is on screen and clear of HUD; inside it the platform /
##  pan differs from a reference water cell (5,29) and wood-brown / rim-dark pixels are present
##  (absent at the reference); the 淘砂處 label is the focused label in reach and gone far away;
##  reduced motion: BOUNDS identical for any elapsed (written and played); motion: the ripple
##  changes BOUNDS (written and played); the panel at each stage lies inside the viewport, no
##  label / button cut; GpCount / GpAction / GpStep_* texts equal the GoldPanUI helpers;
##  GpPan shows pan_texture(stage), non-uniform on screen, gold-coloured only at stage 5;
##  first pan -> +1 gold_ore in the server bag and in my snapshot; daily done / away reasons.
## Same-machine evidence only (one native run on the coordinator's machine).
const World=preload("res://scripts/world.gd")
const Gold=preload("res://scripts/gold_panning.gd")
const Art=preload("res://scripts/gold_panning_art.gd")
const UI=preload("res://scripts/gold_panning_ui.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const REGION:="jinguashi"
## Water cell further along the same shore (same relative BOUNDS rect, no site there).
const REF:=Vector2i(5,29)
## On the bank, 2.0 tiles from the SITE centre (in reach, sprite right of BOUNDS).
const NEAR_SPOT:=Vector2(7.5,26.5)
## On the bank, 4.0 tiles from the SITE centre (out of reach, SITE still on screen).
const VIEW_SPOT:=Vector2(9.5,26.5)
## The shuttle stop: far from the site.
const FAR_SPOT:=Vector2(12.5,20.5)
const AIM:=Vector2(7.0,27.0)
const FAR_AIM:=Vector2(12.5,21.0)
const WOOD_COLOURS:=["8a6238","b88a55"]
const RIM_COLOURS:=["4a4038"]
const GOLD_COLOURS:=["e9c44a","f6e27a"]
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
var aim:=AIM

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("GOLD_PANNING_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

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

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("GOLD_PANNING_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

## Art.BOUNDS placed on `cell` (relative to the cell's top-left world pixel).
func bounds_world(cell:Vector2i)->Rect2:
	return Rect2(Vector2(cell)*32.0+Art.BOUNDS.position,Art.BOUNDS.size)

func bounds_box(cell:Vector2i)->Rect2i:
	return pixel_box(view_rect(bounds_world(cell)))

func site_box()->Rect2i:
	return bounds_box(Gold.SITE)

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
	for panel:Dictionary in hud_panels():check(not r.intersects(panel.rect),"%s clear of HUD %s (%s)"%[what,panel.name,tag])

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

## Same-size regions `a` and `b` of one image: share of pixels that differ.
func region_difference(image:Image,a:Rect2i,b:Rect2i)->float:
	var size:=Vector2i(mini(a.size.x,b.size.x),mini(a.size.y,b.size.y))
	if image==null or size.x<=0 or size.y<=0:return 0.0
	var whole:=Rect2i(Vector2i.ZERO,image.get_size())
	if not whole.encloses(Rect2i(a.position,size)) or not whole.encloses(Rect2i(b.position,size)):return 0.0
	var changed:=0
	for x in size.x:
		for y in size.y:
			var p:=image.get_pixel(a.position.x+x,a.position.y+y);var q:=image.get_pixel(b.position.x+x,b.position.y+y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(size.x*size.y)

## Pixels inside `box` within `tol` (sum of channel differences) of any of `hexes`.
func count_colours(image:Image,box:Rect2i,hexes:Array,tol:float)->int:
	if image==null:return 0
	var r:=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var targets:=[]
	for hex in hexes:targets.append(Color(str(hex)))
	var n:=0
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			var c:=image.get_pixel(x,y)
			for t:Color in targets:
				if absf(c.r-t.r)+absf(c.g-t.g)+absf(c.b-t.b)<tol:n+=1;break
	return n

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

# ------------------------------------------------------------- pure checks --

func pure_checks()->void:
	check(Art.POINT=="gold_pan" and UI.POINT==Art.POINT and Gold.ACTION==Art.POINT,"Point id gold_pan shared by art / UI / rules")
	check(Art.BOUNDS==Rect2(0,-8,40,40),"Art.BOUNDS is Rect2(0,-8,40,40): %s"%str(Art.BOUNDS))
	check(Gold.SITE==Vector2i(5,26) and World.GOLD_PANNING.SITE==Gold.SITE,"SITE is (5,26)")
	check(not World.land(Gold.SITE,REGION) and World.land(Gold.SITE+Vector2i(1,0),REGION),"SITE is water, (6,26) is bank")
	check(not World.land(REF,REGION) and World.land(REF+Vector2i(1,0),REGION),"Reference cell %s is water next to the bank like SITE"%str(REF))
	check(NEAR_SPOT.distance_to(Vector2(Gold.SITE)+Vector2(0.5,0.5))<=Gold.REACH,"NEAR_SPOT within REACH")
	check(VIEW_SPOT.distance_to(Vector2(Gold.SITE)+Vector2(0.5,0.5))>Gold.REACH,"VIEW_SPOT out of REACH")
	var images:=[]
	for stage in range(6):
		var tex:=Art.pan_texture(stage)
		check(tex!=null and tex.get_size()==Vector2(64,64),"pan_texture(%d) is 64×64"%stage)
		var img:=Art.pan_image(stage)
		check(img!=null and img.get_size()==Vector2i(64,64),"pan_image(%d) is 64×64"%stage)
		if img==null:images.append(null);continue
		img.convert(Image.FORMAT_RGBA8)
		images.append(img)
		var gold:=count_colours(img,Rect2i(0,0,64,64),GOLD_COLOURS,0.06)
		print("NOTE pan_image(%d): %d gold pixels"%[stage,gold])
		if stage==5:check(gold>=1,"Gold pixels in pan stage 5 (%d)"%gold)
		else:check(gold==0,"No gold pixels in pan stage %d (%d)"%[stage,gold])
	for i in range(6):
		for j in range(i+1,6):
			var a:Image=images[i];var b:Image=images[j]
			check(a!=null and b!=null and a.get_data()!=b.get_data(),"Pan stages %d / %d differ"%[i,j])

# ------------------------------------------------------------------ world --

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.time=30.0  # PRESET (day 1, sunny)
	w.state.erase(Gold.STATE_KEY)  # PRESET
	bag()[Gold.ITEM]=0  # PRESET
	app.view.zoom=2.0
	app.view.reduced_motion=false
	app.view.set_process(false)

## The site is painted: BOUNDS differs from the reference water cell, wood / rim colours present.
func site_drawn(image:Image,label:String)->void:
	var box:=site_box()
	var ref:=bounds_box(REF)
	box_on_screen(box,"Site BOUNDS "+label)
	# The reference is only compared against; at 1024×640 the (invisible) ToolHint control rect reaches it.
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(Rect2(Vector2(ref.position),Vector2(ref.size))),"Reference cell %s on screen (%s) %s"%[label,tag,str(ref)])
	var unlike:=region_difference(image,box,ref)
	print("NOTE %s %s: site BOUNDS vs reference water %.1f%%"%[label,tag,unlike*100.0])
	check(unlike>=0.2,"Site BOUNDS differs from the reference water cell (%.1f%%) %s %s"%[unlike*100.0,label,tag])
	var wood:=count_colours(image,box,WOOD_COLOURS,0.2)
	var rim:=count_colours(image,box,RIM_COLOURS,0.15)
	# BOUNDS reaches 8px onto the bank, whose soil is itself brown: count the reference's wood
	# colours over its water part only (the left 32 of BOUNDS' 40 px).
	var ref_water:=Rect2i(ref.position,Vector2i(int(ref.size.x*32.0/40.0),ref.size.y))
	var ref_wood:=count_colours(image,ref_water,WOOD_COLOURS,0.2)
	print("NOTE %s %s: wood %d px, rim %d px, reference wood %d px"%[label,tag,wood,rim,ref_wood])
	check(wood>=40,"Wood-brown pixels in the site BOUNDS (%d) %s %s"%[wood,label,tag])
	check(rim>=12,"Dark pan-rim pixels in the site BOUNDS (%d) %s %s"%[rim,label,tag])
	check(ref_wood*4<wood,"Reference water cell has (almost) no wood (%d vs %d) %s %s"%[ref_wood,wood,label,tag])

func world_flow()->void:
	reset()
	# world_site: out of reach, motion on, ripple clock written to frame 0.
	await stand(VIEW_SPOT,AIM)
	app.view.elapsed=0.1  # PRESET (ripple frame 0)
	await refresh()
	check(focus()!=Art.POINT,"Out of reach at %s: not focused (%s): %s"%[str(VIEW_SPOT),tag,focus()])
	check(label_entry(Art.POINT).is_empty(),"No 淘砂處 label out of reach (%s)"%tag)
	var site:Image=await shot("world_site")
	site_drawn(site,"world_site")
	# world_focus: in reach on the bank.
	await stand(NEAR_SPOT,AIM)
	check(focus()==Art.POINT,"In reach at %s: gold_pan focused (%s): %s"%[str(NEAR_SPOT),tag,focus()])
	check(str(app.view.focused_label)==Art.POINT,"view.focused_label is gold_pan (%s): %s"%[tag,str(app.view.focused_label)])
	var focused:Image=await shot("world_focus")
	site_drawn(focused,"world_focus")
	var mine:=label_entry(Art.POINT)
	check(not mine.is_empty() and str(mine.get("title",""))==Gold.SITE_NAME and Gold.SITE_NAME=="淘砂處","Focused label 「淘砂處」 (%s): %s"%[tag,str(mine.get("title","none"))])
	if not mine.is_empty():
		var r:Rect2=mine.rect
		var px:=view_to_pixels(r)
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"淘砂處 label on screen (%s) %s"%[tag,str(px)])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"淘砂處 label clear of HUD %s (%s)"%[panel.name,tag])
	# Far away: the shuttle stop.
	await stand(FAR_SPOT,FAR_AIM)
	check(focus()!=Art.POINT and str(app.view.focused_label)!=Art.POINT,"Far at the shuttle: gold_pan not focused (%s): %s"%[tag,focus()])
	check(label_entry(Art.POINT).is_empty(),"No 淘砂處 label far away (%s)"%tag)
	await motion_flow()

func motion_flow()->void:
	await stand(VIEW_SPOT,AIM)
	var box:=site_box()
	# Reduced motion, written clock: identical inside BOUNDS for any elapsed.
	app.view.reduced_motion=true  # PRESET
	app.view.elapsed=0.1  # PRESET
	await refresh()
	var reduced:Image=await shot("world_reduced")
	site_drawn(reduced,"world_reduced")
	for t:float in [0.6,3.6,5.85]:
		app.view.elapsed=t  # PRESET
		app.view.queue_redraw()
		var later:Image=await grab()
		var n:=exact_changed(reduced,later,box)
		check(n==0,"Reduced motion: BOUNDS identical at elapsed 0.1 vs %.2f (%d px) %s"%[t,n,tag])
	# Motion on, written clock: ripple frame 0 vs frame 1 differ inside BOUNDS.
	app.view.reduced_motion=false
	app.view.elapsed=0.1  # PRESET
	app.view.queue_redraw()
	var frame0:Image=await grab()
	app.view.elapsed=0.6  # PRESET
	app.view.queue_redraw()
	var frame1:Image=await grab()
	var ripple:=exact_changed(frame0,frame1,box)
	print("NOTE %s: ripple frame 0 vs 1: %d px in BOUNDS"%[tag,ripple])
	check(ripple>=16,"Motion on: ripple frames differ inside BOUNDS (%d px) %s"%[ripple,tag])
	check(box_difference(frame0,frame1,box)<0.5,"Ripple change is a small part of BOUNDS (%s)"%tag)
	# Played clock, reduced motion: two captures ~2 s apart identical inside BOUNDS.
	app.view.reduced_motion=true
	app.view.set_process(true)
	await create_timer(0.3).timeout
	var first:Image=await grab()
	var cam:Vector2=app.view.camera
	var played_box:=site_box()
	await create_timer(1.8).timeout
	var second:Image=await grab()
	check(Vector2(app.view.camera)==cam,"Camera steady while the view runs (%s)"%tag)
	var still:=exact_changed(first,second,played_box)
	check(still==0,"Reduced motion (running view, ~2 s apart): BOUNDS identical (%d px) %s"%[still,tag])
	# Played clock, motion on: at least one of several captures across ~2 s differs.
	app.view.reduced_motion=false
	await create_timer(0.1).timeout
	var base:Image=await grab()
	var most:=0
	for i in range(5):
		await create_timer(0.15).timeout
		var next:Image=await grab()
		most=maxi(most,exact_changed(base,next,played_box))
	print("NOTE %s: running view, motion on: max %d px changed in BOUNDS"%[tag,most])
	check(most>0,"Motion on (running view, ~2 s): ripple changes BOUNDS (%d px) %s"%[most,tag])
	app.view.set_process(false)
	app.view.reduced_motion=false
	await refresh()

# ------------------------------------------------------------------ panel --

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func shown(control_name:String)->bool:
	var c:=control(control_name)
	return c!=null and c.is_visible_in_tree()

## Text of a Label / Button, or of the first Label inside a container.
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

## As test_salt_brine_scene.not_cut: no trimming, every line visible, unwrapped lines fit.
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

## test_salt_brine_scene.page_fit (outer ModalScroll optional, as in test_jinguashi_revisit_scene).
func page_fit(label:String)->void:
	check(layout_name()=="gold_panning","Panel gold_panning open (%s): %s"%[label,layout_name()])
	if not is_instance_valid(app.modal):return
	var modal:Control=app.modal
	var page_rect:Rect2=modal.get_global_rect()
	check(root.get_visible_rect().encloses(page_rect),"Panel fits the viewport (%s) %s"%[label,str(page_rect)])
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Panel needs no outer scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect or c is ColorRect):continue
		check(page_rect.grow(0.5).encloses(c.get_global_rect()),"%s inside the panel (%s) %s"%[c.name,label,str(c.get_global_rect())])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s)"%[c.name,label])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not page_texts().contains("…"),"No ellipsis anywhere in the panel (%s)"%label)

func modal_box()->Rect2i:
	if not is_instance_valid(app.modal):return Rect2i()
	var r:Rect2=(app.modal as Control).get_global_rect()
	return Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.floor()))

func pan_box()->Rect2i:
	var pan:=control("GpPan")
	if pan==null:return Rect2i()
	var r:=pan.get_global_rect()
	return Rect2i(Vector2i(r.position.ceil()),Vector2i(r.size.floor())).intersection(Rect2i(Vector2i.ZERO,root.size))

## The caption the contract gives for the next step at `stage`.
func caption_for(stage:int)->String:
	match str(Gold.STEPS[stage]):
		"scoop":return "舀一盤河砂"
		"sift":return "揀掉石礫"
		"swirl":return "搖盤（還要 %d 次）"%Gold.swirls_left(stage)
		"pick":return "揀起金砂"
	return ""

func snap_ore()->int:
	var s:Dictionary=app.session.snapshot
	var players:Dictionary=s.get("players",{})
	var me:Dictionary=players.get(app.session.own_id,{})
	var inv:Dictionary=me.get("inventory",{})
	return int(inv.get(Gold.ITEM,0))

## Panel texts / state at `stage` with `count` pans today and `total` overall.
## `reason` "" = action enabled with the step caption; otherwise disabled with that reason.
func panel_state(label:String,stage:int,count:int,total:int,reason:String)->void:
	var where:="%s %s"%[label,tag]
	check(UI.is_open(app) and layout_name()=="gold_panning","Panel open (%s): %s"%[where,layout_name()])
	if not is_instance_valid(app.modal):return
	check(str((app.modal as Node).name)=="GoldPanningPanel" or control("GoldPanningPanel")!=null,"Panel node GoldPanningPanel (%s): %s"%[where,str((app.modal as Node).name)])
	check((app.modal as Node).has_meta("gp_body"),"Panel has meta gp_body (%s)"%where)
	var s:Dictionary=app.session.snapshot
	check(Gold.view(w.state,id)=={"stage":stage,"count":count,"total":total},"Server record stage %d count %d total %d (%s): %s"%[stage,count,total,where,str(Gold.view(w.state,id))])
	check(Gold.stage(s)==stage and Gold.count_today(s)==count and Gold.total(s)==total,"Snapshot own_gold_panning matches (%s): %s"%[where,str(s.get(Gold.OWN_KEY,"none"))])
	var want_count:="今天 %d／%d 盤・累計 %d 盤"%[count,Gold.DAILY,total]
	check(UI.count_text(s)==want_count,"count_text helper 「%s」 (%s): %s"%[want_count,where,UI.count_text(s)])
	check(shown("GpCount") and node_text("GpCount")==UI.count_text(s),"GpCount 「%s」 (%s): %s"%[want_count,where,node_text("GpCount")])
	check(shown("GpStage") and node_text("GpStage").contains(Gold.stage_text(stage)),"GpStage shows 「%s」 (%s): %s"%[Gold.stage_text(stage),where,node_text("GpStage")])
	for step:String in Gold.STEP_IDS:
		var chip:="GpStep_"+step
		check(shown(chip) and node_text(chip)==UI.chip_text(stage,step),"%s 「%s」 (%s): %s"%[chip,UI.chip_text(stage,step),where,node_text(chip)])
	var pan:=control("GpPan") as TextureRect
	check(pan!=null and pan.is_visible_in_tree() and pan.texture!=null,"GpPan TextureRect shown (%s)"%where)
	if pan!=null and pan.texture!=null:
		var same:bool=pan.texture==Art.pan_texture(stage)
		if not same:
			var a:Image=pan.texture.get_image()
			var b:Image=Art.pan_image(stage)
			if a!=null and b!=null:
				a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
				same=a.get_size()==b.get_size() and a.get_data()==b.get_data()
		check(same,"GpPan shows pan_texture(%d) (%s)"%[stage,where])
	var action:=control("GpAction") as Button
	check(action!=null and action.is_visible_in_tree(),"GpAction button shown (%s)"%where)
	if action!=null:
		if reason.is_empty():
			check(not action.disabled,"GpAction enabled (%s)"%where)
			check(UI.action_caption(stage)==caption_for(stage),"action_caption(%d) 「%s」: %s"%[stage,caption_for(stage),UI.action_caption(stage)])
			check(action.text==UI.action_caption(stage),"GpAction caption 「%s」 (%s): %s"%[UI.action_caption(stage),where,action.text])
		else:
			check(action.disabled,"GpAction disabled (%s)"%where)
	if reason.is_empty():
		check(node_text("GpReason").is_empty() or not shown("GpReason"),"No reason shown (%s): %s"%[where,node_text("GpReason")])
	else:
		check(shown("GpReason") and node_text("GpReason")==reason,"GpReason 「%s」 (%s): %s"%[reason,where,node_text("GpReason")])
	check(shown("GpBag") and node_text("GpBag")==UI.BAG_TEXT%snap_ore(),"GpBag 「%s」 (%s): %s"%[UI.BAG_TEXT%snap_ore(),where,node_text("GpBag")])
	check(shown("GpBlurb") and node_text("GpBlurb").contains(Gold.BLURB),"GpBlurb carries the blurb (%s)"%where)
	check(shown("GpDisclaimer") and node_text("GpDisclaimer").contains(Gold.DISCLAIMER),"GpDisclaimer carries the disclaimer (%s)"%where)

## Native shot of the open panel + fit checks + the pan region on screen.
func panel_shot(step:String,stage:int)->void:
	check(UI.is_open(app),"Panel open before the shot %s_%s"%[tag,step])
	if not is_instance_valid(app.modal):return
	var image:Image=await shot(step)
	panel_shots+=1
	page_fit(step+" "+tag)
	var live:=region_variety(image,modal_box())
	check(live>=6,"Panel region of %s_%s is not a flat colour (%d colours)"%[tag,step,live])
	var box:=pan_box()
	check(box.size.x>=32 and box.size.y>=32,"GpPan at least 32 px on screen (%s_%s) %s"%[tag,step,str(box)])
	var variety:=region_variety(image,box)
	check(variety>=4,"GpPan pixels on screen are not uniform (%s_%s): %d colours"%[tag,step,variety])
	var gold:=count_colours(image,box,GOLD_COLOURS,0.2)
	print("NOTE %s_%s: GpPan %s, %d colours, %d gold px"%[tag,step,str(box),variety,gold])
	if stage==5:check(gold>=1,"Gold-coloured pixels in GpPan at stage 5 (%s_%s): %d"%[tag,step,gold])
	else:check(gold==0,"No gold-coloured pixels in GpPan at stage %d (%s_%s): %d"%[stage,tag,step,gold])

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

func open_panel(label:String)->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	await stand(NEAR_SPOT,AIM)
	app.session.rates[1].clear()
	app._interact()
	await settle()
	await refresh()
	check(UI.is_open(app) and layout_name()=="gold_panning","Interact on the bank opens the 淘砂 panel (%s %s): %s"%[label,tag,layout_name()])

## One whole pan through the panel button; returns after the pick.
func full_pan(count_before:int,total_before:int)->void:
	for stage in range(6):
		var ok:bool=await press("GpAction")
		if not ok:return
		if stage<5:panel_state("pan %d step %d"%[total_before+1,stage+1],stage+1,count_before,total_before,"")
	panel_state("pan %d done"%[total_before+1],0,count_before+1,total_before+1,"" if count_before+1<Gold.DAILY else Gold.DAILY_DONE)

func panel_flow()->void:
	reset()
	await open_panel("first")
	panel_state("empty",0,0,0,"")
	await panel_shot("panel_empty",0)
	# Scoop -> gravel.
	await press("GpAction")
	panel_state("gravel",1,0,0,"")
	await panel_shot("panel_gravel",1)
	# Sift, one swirl -> mid swirl (stage 3).
	await press("GpAction")
	panel_state("sifted",2,0,0,"")
	await press("GpAction")
	panel_state("swirl",3,0,0,"")
	await panel_shot("panel_swirl",3)
	# Two more swirls -> gold visible (stage 5).
	await press("GpAction")
	panel_state("swirl 2",4,0,0,"")
	await press("GpAction")
	panel_state("gold",5,0,0,"")
	await panel_shot("panel_gold",5)
	# Pick: +1 gold_ore.
	await press("GpAction")
	panel_state("first pan done",0,1,1,"")
	check(int(bag().get(Gold.ITEM,0))==1,"Server bag +1 gold_ore after the first pan (%s): %d"%[tag,int(bag().get(Gold.ITEM,0))])
	check(snap_ore()==1,"Snapshot inventory +1 gold_ore after the first pan (%s): %d"%[tag,snap_ore()])
	# Away while the panel is open.
	await stand(FAR_SPOT,FAR_AIM)
	check(UI.is_open(app),"Panel stays open when I walk away (%s)"%tag)
	if UI.is_open(app):
		panel_state("away",0,1,1,UI.away_text())
		await panel_shot("panel_away",0)
	# Back in reach; two more full pans reach the daily limit.
	await stand(NEAR_SPOT,AIM)
	if not UI.is_open(app):await open_panel("back")
	panel_state("back in reach",0,1,1,"")
	await full_pan(1,1)
	await full_pan(2,2)
	panel_state("daily done",0,Gold.DAILY,Gold.DAILY,Gold.DAILY_DONE)
	check(Gold.step_block(app.session.snapshot,"scoop",bag())==Gold.DAILY_DONE,"Client rules agree: scoop blocked by DAILY_DONE (%s)"%tag)
	check(int(bag().get(Gold.ITEM,0))==Gold.DAILY and snap_ore()==Gold.DAILY,"Three pans -> 3 gold_ore (%s): %d / %d"%[tag,int(bag().get(Gold.ITEM,0)),snap_ore()])
	await panel_shot("panel_daily_done",0)
	app._close_modal()
	await settle()

func size_flow()->void:
	await world_flow()
	await panel_flow()

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/淘砂金預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	pure_checks()
	path=OS.get_environment("TEMP").path_join("gold-panning-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"淘砂旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	WanganUI.dismiss(app)
	app.view.set_process(false)
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(panel_shots==12,"6 panel screenshots per size (%d)"%panel_shots)
	check(shots==18,"9 screenshots per size (%d)"%shots)
	w.state.erase(Gold.STATE_KEY)  # PRESET cleanup before the final save
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
