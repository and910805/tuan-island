extends SceneTree
## 第 40 章風鈴節廣場「地方記憶展」native render check at 1024×640 and 1280×800. Screenshots go
## to outputs/地方記憶展預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness as
## test_souvenir_exchange_scene.gd.
##
## Art is runtime-painted, no new PNGs: stand = memory_exhibit_art.stand(on_display) (56×56,
## grey-blue tiled roof, red name board, cream wall, four stone pedestals; the 分水木牌
## miniature on the first pedestal when on display, dashed outlines on empty ones); the red
## unread dot is drawn by memory_exhibit_ui.draw_stand; card icons = memory_exhibit_art.icon().
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / picnic / chapter_one.shipped+watered and state.festival_story_open written
##    directly (festival false for the first frame);
##  * the 蘭陽 unlock (lanyang_life repaired, history_memory with my completed first 分水,
##    plaque) and the completed 蘭陽回訪 record (gates 3/2, day 1, three fields checked) are
##    written directly; player.memory_exhibit erased before each size; a diversion_gate_kit is
##    written into my bag for the tracker frame;
##  * the local player is teleported by writing x/y; the paused frames write three lamp
##    objects onto the stand candidates.
## REALLY EXERCISED: app._interact() at the stand opens the page; the recap pager is turned by
##  emitting `pressed` on 翻閱回顧 / 下一頁; the last page sends exhibit_view through the real
##  Session.perform → World → snapshot.
## SHOTS per size (15): world_locked, world_stand_empty, world_stand_plaque,
##  world_stand_focused, world_stand_seen, world_reduced, world_paused, tracker_slot,
##  page_empty, page_unread, page_recap_1, page_recap_last, page_latecomer, page_paused,
##  stand_strip (crop: empty / plaque+unread / seen).
const World=preload("res://scripts/world.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const UI=preload("res://scripts/memory_exhibit_ui.gd")
const Art=preload("res://scripts/memory_exhibit_art.gd")
const SouvUI=preload("res://scripts/souvenir_exchange_ui.gd")
const STAND:=Vector2i(39,26)
const NEAR:=Vector2(39.5,27.5)
## Viewing spot south-west of the stand: stand, its label, the 紀念品交換攤 and 鈴婆婆 in view.
const VIEW_SPOT:=Vector2(38.5,28.6)
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

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("MEMORY_EXHIBIT_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step])
	check(image.save_png(file)==OK,"native screenshot saved %s_%s"%[tag,step])
	shots+=1
	print("MEMORY_EXHIBIT_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

func shot(step:String)->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	save_image(image,step)
	return image

func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))==UI.LAYOUT

func person()->Dictionary:
	return w.state.players[id]

func k(c:Vector2i)->String:
	return World.key(c)

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	await settle()

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	app.action_clock=0
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func page_fits(label:String)->void:
	check(page_open(),"Page open (%s)"%label)
	if not page_open():return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Page fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Outer page needs no scrolling (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the page: 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"Button whole inside the page: 「%s」 (%s)"%[b.text,label])

# ------------------------------------------------------------- world view --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

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

func region_difference(image:Image,a:Rect2i,b:Rect2i)->float:
	var size:=Vector2i(mini(a.size.x,b.size.x),mini(a.size.y,b.size.y))
	if size.x<=0 or size.y<=0:return 0.0
	var changed:=0
	for x in size.x:
		for y in size.y:
			var p:=image.get_pixel(a.position.x+x,a.position.y+y);var q:=image.get_pixel(b.position.x+x,b.position.y+y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(size.x*size.y)

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

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

func stand_rect()->Rect2:
	return UI.stand_rect(app.view,STAND)

## Pedestal-1 area (the 分水木牌 spot) inside the stand, world px.
func pedestal_rect(index:int)->Rect2:
	var cx:int=Art.PEDESTALS[index]
	return Rect2(stand_rect().position+Vector2(cx-5,25),Vector2(11,13))

## The stand's contents (wall, name board, pedestals) without the eaves, posts and plinth.
func stand_inner()->Rect2:
	return UI.stand_inner_rect(app.view,STAND)

func marker_rect()->Rect2:
	return Rect2(stand_rect().position+Vector2(40,11),Vector2(10,10))

## Labels: the stand label has the right title just above the stand, never over the stand,
## never overlapping another label (鈴婆婆, 公告板, 紀念品交換攤, name tags); stand and label
## clear of every HUD panel.
func world_ok(label:String,expect_stand:=true)->void:
	var list:=placements()
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	var mine:Dictionary={}
	var ids:=PackedStringArray()
	for entry:Dictionary in list:
		ids.append("%s「%s」"%[str(entry.id),str(entry.title)])
		if str(entry.id)==UI.POINT:mine=entry
	print("NOTE %s labels: %s"%[label,", ".join(ids)])
	if not expect_stand:
		check(mine.is_empty(),"No stand label (%s)"%label)
		return
	var expected:=UI.stand_title(app.session.snapshot,str(app.view.focused_label)==UI.POINT)
	check(not mine.is_empty() and str(mine.title)==expected,"Stand label 「%s」 placed (%s): %s"%[expected,label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var r:Rect2=mine.rect
	var box:=stand_rect()
	check(screen_rect.encloses(view_to_pixels(r)),"Stand label on screen (%s)"%label)
	check(not r.intersects(box.grow(-2.0)),"Stand label not over the stand (%s) %s vs %s"%[label,str(r),str(box)])
	check(absf(r.get_center().x-box.get_center().x)<=48.0 and r.end.y<=box.position.y+4.0 and r.end.y>=box.position.y-30.0,"Stand label stays just above the stand (%s) %s vs %s"%[label,str(r),str(box)])
	for other:Dictionary in list:
		if other==mine:continue
		check(not r.grow(1.0).intersects(other.rect),"Stand label does not overlap 「%s」 (%s) %s vs %s"%[other.title,label,str(r),str(other.rect)])
		# My own name tag may sit over the stand while I stand right in front of it.
		if str(other.id)=="" and label.begins_with("focused"):continue
		check(not (other.rect as Rect2).intersects(stand_inner()),"Label 「%s」 not over the stand's wall / pedestals (%s) %s vs %s"%[other.title,label,str(other.rect),str(stand_inner())])
	if SouvUI.booth_shown(app.session.snapshot):
		var booth:=SouvUI.booth_rect(app.view,SouvUI.booth_cell(app.session.snapshot))
		var overlap:=r.intersection(booth)
		print("NOTE %s: stand label over the booth %.1f%% of its area"%[label,100.0*overlap.get_area()/maxf(1.0,r.get_area())])
		check(overlap.get_area()<=0.02*r.get_area(),"Stand label stays off the 紀念品交換攤 (%s) %s vs %s"%[label,str(r),str(booth)])
	var px:=view_to_pixels(box)
	check(screen_rect.encloses(px),"Whole stand on screen (%s) %s"%[label,str(px)])
	for panel:Dictionary in hud_panels():
		check(not px.intersects(panel.rect),"Stand clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(px),str(panel.rect)])
		check(not view_to_pixels(r).intersects(panel.rect),"Stand label clear of HUD %s (%s)"%[panel.name,label])

## No tree crown, character or other sprite covers the stand: its painted colours stay.
func stand_uncovered(image:Image,label:String)->void:
	var art:Image=Art.stand(Exhibit.on_display_ids(app.session.snapshot)).get_image()
	var box:=stand_rect()
	var matched:=0
	var total:=0
	for y in range(0,56,2):
		for x in range(0,56,2):
			var c:=art.get_pixel(x,y)
			if c.a<0.99:continue
			total+=1
			var at:=pixel_box(Rect2(box.position+Vector2(x,y),Vector2.ONE)).position
			if at.x<0 or at.y<0 or at.x>=image.get_width() or at.y>=image.get_height():continue
			var q:=image.get_pixel(at.x,at.y)
			if absf(c.r-q.r)+absf(c.g-q.g)+absf(c.b-q.b)<0.15:matched+=1
	var share:=float(matched)/maxf(1.0,float(total))
	print("NOTE %s: stand pixels as painted %.0f%%"%[label,share*100.0])
	check(share>=0.8,"Stand is not covered by canopies or other sprites (%s): %.0f%%"%[label,share*100.0])

func static_ok(image:Image,label:String)->void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var d:=box_difference(image,root.get_texture().get_image(),pixel_box(stand_rect()))
	check(d<=0.01,"Stand static frame to frame (%s): %.1f%%"%[label,d*100.0])

# ------------------------------------------------------------------ flows --

func write_unlock(ready:bool)->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var seen:=[]
	if ready:
		for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3 if ready else 0,"gates":[0,0],"completed":ready}},"plaque":true}  # PRESET

func write_completed()->void:
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}  # PRESET

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	w.state.festival_story_open=false  # PRESET
	w.state.time=30.0  # PRESET
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	(person().inventory as Dictionary).erase("diversion_gate_kit")  # PRESET
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects.erase(k(cell))
	write_unlock(true)
	app.view.reduced_motion=false

func open_at_stand()->void:
	await stand(NEAR)
	check(str(app.view.interaction_focus())==UI.POINT,"Stand focused (%s)"%tag)
	app._interact()
	await settle()
	check(page_open(),"Interact at the stand opens 地方記憶展 (%s)"%tag)

func size_flow()->void:
	reset()
	await refresh()
	await stand(VIEW_SPOT)
	check(not UI.stand_shown(app.session.snapshot),"No stand before the festival (%s)"%tag)
	var locked:Image=await shot("world_locked")
	world_ok("locked "+tag,false)
	# Festival open, nothing on display.
	w.state.festival_story_open=true  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	check(UI.stand_cell(app.session.snapshot)==STAND,"Stand at (39,26) (%s)"%tag)
	var empty_img:Image=await shot("world_stand_empty")
	var drawn:=box_difference(locked,empty_img,pixel_box(stand_rect().grow(-2.0)))
	print("NOTE %s: stand box changed %.0f%%"%[tag,drawn*100.0])
	check(drawn>=0.35,"Stand drawn at its cell (%.0f%% changed) %s"%[drawn*100.0,tag])
	stand_uncovered(empty_img,"empty "+tag)
	world_ok("empty "+tag)
	# The stand looks different from the 紀念品交換攤 two tiles west.
	var booth_box:=pixel_box(SouvUI.booth_rect(app.view,SouvUI.booth_cell(app.session.snapshot)))
	var stand_box:=pixel_box(stand_rect())
	var unlike:=region_difference(empty_img,stand_box,booth_box)
	print("NOTE %s: stand vs souvenir booth difference %.0f%%"%[tag,unlike*100.0])
	check(SouvUI.booth_shown(app.session.snapshot) and unlike>=0.4,"Stand looks different from the 紀念品交換攤 (%.0f%%) %s"%[unlike*100.0,tag])
	await static_ok(empty_img,"empty "+tag)
	# Page with nothing on display.
	await open_at_stand()
	await shot("page_empty")
	page_fits("page empty "+tag)
	app._close_modal()
	# 分水木牌 on display, unread.
	write_completed()
	await refresh()
	await stand(VIEW_SPOT)
	var plaque_img:Image=await shot("world_stand_plaque")
	stand_uncovered(plaque_img,"plaque "+tag)
	world_ok("plaque "+tag)
	var ped:=box_difference(empty_img,plaque_img,pixel_box(pedestal_rect(0)))
	print("NOTE %s: plaque pedestal displayed vs empty %.0f%%"%[tag,ped*100.0])
	check(ped>=0.25,"Plaque pedestal differs between displayed and empty (%.0f%%) %s"%[ped*100.0,tag])
	for i in range(1,4):check(box_difference(empty_img,plaque_img,pixel_box(pedestal_rect(i)))<=0.01,"Pedestal %d stays empty (%s)"%[i,tag])
	var marker_new:=box_difference(empty_img,plaque_img,pixel_box(marker_rect()))
	check(marker_new>=0.25,"Unread marker drawn (%.0f%%) %s"%[marker_new*100.0,tag])
	await static_ok(plaque_img,"plaque "+tag)
	# Tracker slot (tea guidance outranks it in _refresh_hud; see test_memory_exhibit_ui).
	person().inventory["diversion_gate_kit"]=1  # PRESET
	await refresh()
	app.LifeShell.refresh_hud(app,app.session.snapshot,app.session.snapshot.players[app.session.own_id])
	check(str(app.objective.text)==UI.TRACKER%1,"Tracker slot shows the exhibit line (%s)"%tag)
	await shot("tracker_slot")
	await refresh()
	# Focused prompt.
	await stand(NEAR)
	await shot("world_stand_focused")
	world_ok("focused "+tag)
	# Page unread, recap, send.
	await open_at_stand()
	await shot("page_unread")
	page_fits("page unread "+tag)
	await press("MemoryRecap")
	await shot("page_recap_1")
	page_fits("page recap 1 "+tag)
	for i in 3:await press("MemoryNext")
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and label_text("MemoryBadge_lanyang")==UI.BADGE_SEEN,"Last recap page sent the view (%s)"%tag)
	await shot("page_recap_last")
	page_fits("page recap last "+tag)
	app._close_modal()
	await stand(VIEW_SPOT)
	var seen_img:Image=await shot("world_stand_seen")
	world_ok("seen "+tag)
	var marker_gone:=box_difference(plaque_img,seen_img,pixel_box(marker_rect()))
	check(marker_gone>=0.25 and box_difference(empty_img,seen_img,pixel_box(marker_rect()))<=0.02,"Unread marker gone after seeing (%.0f%%) %s"%[marker_gone*100.0,tag])
	check(box_difference(plaque_img,seen_img,pixel_box(pedestal_rect(0)))<=0.01,"Plaque still on its pedestal (%s)"%tag)
	# Reduced motion: still the same picture.
	app.view.reduced_motion=true
	var reduced:Image=await shot("world_reduced")
	check(box_difference(seen_img,reduced,pixel_box(stand_rect()))<=0.01,"Stand identical with reduced motion (%s)"%tag)
	await static_ok(reduced,"reduced "+tag)
	app.view.reduced_motion=false
	var strip:=pixel_box(stand_rect().grow(4.0)).intersection(Rect2i(Vector2i.ZERO,empty_img.get_size()))
	var combined:=Image.create_empty(strip.size.x*3+8,strip.size.y,false,empty_img.get_format())
	combined.fill(Color("392d23"))
	combined.blit_rect(empty_img,strip,Vector2i.ZERO)
	combined.blit_rect(plaque_img,strip,Vector2i(strip.size.x+4,0))
	combined.blit_rect(seen_img,strip,Vector2i(strip.size.x*2+8,0))
	save_image(combined,"stand_strip")
	# Latecomer page.
	write_unlock(false)
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	await refresh()
	await open_at_stand()
	check(label_text("MemoryHint")==Exhibit.HINT_NOT_READY,"Latecomer hint (%s)"%tag)
	await shot("page_latecomer")
	page_fits("page latecomer "+tag)
	app._close_modal()
	# Paused.
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects[k(cell)]={"type":"lamp","owner":id,"items":{}}  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	await shot("world_paused")
	world_ok("paused "+tag,false)
	app._festival_menu()
	await settle()
	var entry:=control("MemoryExhibitEntry") as Button
	check(entry!=null,"Festival page lists 地方記憶展 (%s)"%tag)
	if entry!=null:
		entry.pressed.emit()
		await settle()
	check(page_open() and label_text("MemoryState").contains("(39,26)"),"Paused page lists the cells (%s)"%tag)
	await shot("page_paused")
	page_fits("page paused "+tag)
	app._close_modal()
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects.erase(k(cell))
	await refresh()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/地方記憶展預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("memory-exhibit-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"看展旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=30,"15 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
