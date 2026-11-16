extends SceneTree
## 第 40 章「金瓜石回訪・礦料調度」＋「礦燈」native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/金瓜石回訪預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_memory_exhibit_scene.gd.
##
## Art is runtime-painted, no new PNGs: lantern = jinguashi_revisit_art.lantern_texture()
## (32×32: wire bail, brass cap, iron guard over warm glass, brass foot, ore lumps); the
## exhibit stand's second pedestal = jinguashi_revisit_art.mini().
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.mine_depths (hoist false → true), state.bobo_workshop.done[me], state.time (day 1,
##    spring), state.jinguashi_revisit erased before each size and stashed/restored once for
##    the 「only 分水木牌」 stand frame;
##  * ore counts in my bag (0, then gold 2 / copper 4 / stone 6) and one mine_lantern_kit for
##    the backpack frame;
##  * home objects placed directly for the comparison row: mine_lantern (41,34), lantern_post
##    (43,34), water_share_plaque (45,34), lamp (47,34) (state.removed on those tiles where a
##    base resource sits); real placement by clicks is covered in test_jinguashi_revisit_ui;
##  * state.festival_story_open, the 蘭陽 unlock and a completed lanyang_revisit record
##    (gates 3/2, day 1) for the two-exhibit stand; player.memory_exhibit erased;
##  * the local player is teleported by writing region/x/y.
## REALLY EXERCISED: app._interact() at Bobo's table, the shuttle, the entry sign, the placed
##  lantern and the exhibit stand; the revisit page's sort / ship / claim buttons and the
##  exhibit pager are pressed (`pressed.emit`) and go through Session.perform → World →
##  snapshot.
## SHOTS per size (23): page_locked, page_not_ready, jg_world_tracker, bobo_sort_entry,
##  page_nothing_sorted, page_wrong, page_short, page_partly_sent, shuttle_entry,
##  page_at_shuttle, mine_entry, page_completed, page_claimed, home_objects, home_reduced,
##  home_legacy, home_lantern_focused, lantern_card, inventory_lantern, exhibit_stand_lanyang,
##  exhibit_stand_two, exhibit_page_lantern, exhibit_recap_last; plus two crops
##  (objects_strip, stand_strip).
const World=preload("res://scripts/world.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const UI=preload("res://scripts/jinguashi_revisit_ui.gd")
const Art=preload("res://scripts/jinguashi_revisit_art.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const ExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const ExhibitArt=preload("res://scripts/memory_exhibit_art.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const TABLE_SPOT:=Vector2(23.5,21.5)
const HOIST_SPOT:=Vector2(27.5,19.5)
const SHUTTLE_SPOT:=Vector2(12.5,20.5)
const LANTERN:=Vector2i(41,34)
const POST:=Vector2i(43,34)
const PLAQUE:=Vector2i(45,34)
const LAMP:=Vector2i(47,34)
const ROW_VIEW:=Vector2(44.5,37.6)
## South-west of the lantern so my own sprite does not stand in front of it (before/).
const LANTERN_NEAR:=Vector2(40.3,35.3)
const STAND:=Vector2i(39,26)
const STAND_NEAR:=Vector2(39.5,27.5)
const STAND_VIEW:=Vector2(38.5,28.6)
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
	print("JINGUASHI_REVISIT_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("JINGUASHI_REVISIT_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

func layout_name()->String:
	return str((app.modal as Node).get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func k(c:Vector2i)->String:
	return World.key(c)

func stand(at:Vector2,region:String="jinguashi")->void:
	var p:Dictionary=person()
	p.region=region  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	# Teleporting between regions raises the travel arrival ribbon (it would fade after 1.8 s
	# and covered the object row in the first run; before/): dismiss it like 略過 does.
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:app.hud.remove_child(ribbon);ribbon.queue_free()
	await settle()

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

func interact()->void:
	app.session.rates[1].clear()
	app._interact()
	await settle()
	await refresh()

func page_fits(label:String,expected:String=UI.LAYOUT)->void:
	check(layout_name()==expected,"Page %s open (%s): %s"%[expected,label,layout_name()])
	if not is_instance_valid(app.modal):return
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

func cell_rect(cell:Vector2i)->Rect2:
	return Rect2(app.view.screen(Vector2(cell)),Vector2(32,32))

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

## Share of the lantern's opaque pixels that appear as painted at its cell.
func lantern_visible(image:Image,label:String)->void:
	var art:Image=Art.lantern_texture().get_image()
	var box:=cell_rect(LANTERN)
	var matched:=0
	var total:=0
	for y in range(0,32,2):
		for x in range(0,32,2):
			var c:=art.get_pixel(x,y)
			if c.a<0.99:continue
			total+=1
			var at:=pixel_box(Rect2(box.position+Vector2(x,y),Vector2.ONE)).position
			if at.x<0 or at.y<0 or at.x>=image.get_width() or at.y>=image.get_height():continue
			var q:=image.get_pixel(at.x,at.y)
			if absf(c.r-q.r)+absf(c.g-q.g)+absf(c.b-q.b)<0.15:matched+=1
	var share:=float(matched)/maxf(1.0,float(total))
	print("NOTE %s: lantern pixels as painted %.0f%%"%[label,share*100.0])
	check(share>=0.85,"Lantern drawn as painted, nothing covers it (%s): %.0f%%"%[label,share*100.0])

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

## The four objects and the lantern label stay clear of HUD panels; the lantern label does not
## overlap other labels or sit over the lantern.
func row_ok(label:String,focused:bool)->void:
	for cell:Vector2i in [LANTERN,POST,PLAQUE,LAMP]:
		var px:=view_to_pixels(cell_rect(cell))
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Object %s on screen (%s)"%[str(cell),label])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Object %s clear of HUD %s (%s)"%[str(cell),panel.name,label])
	if not focused:return
	var list:=placements()
	var mine:Dictionary={}
	for entry:Dictionary in list:
		if str(entry.id)==k(LANTERN):mine=entry
	check(not mine.is_empty() and str(mine.title)==JG.LANTERN_NAME,"Lantern label placed (%s): %s"%[label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var r:Rect2=mine.rect
	check(not r.intersects(cell_rect(LANTERN).grow(-4.0)),"Lantern label not over the lantern (%s) %s"%[label,str(r)])
	for other:Dictionary in list:
		if other==mine:continue
		check(not r.grow(1.0).intersects(other.rect),"Lantern label does not overlap 「%s」 (%s)"%[other.title,label])
	for panel:Dictionary in hud_panels():check(not view_to_pixels(r).intersects(panel.rect),"Lantern label clear of HUD %s (%s)"%[panel.name,label])

func stand_rect()->Rect2:
	return ExhibitUI.stand_rect(app.view,STAND)

func pedestal_rect(index:int)->Rect2:
	var cx:int=ExhibitArt.PEDESTALS[index]
	return Rect2(stand_rect().position+Vector2(cx-5,25),Vector2(11,13))

# ------------------------------------------------------------------ flows --

func write_lanyang()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}  # PRESET
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}  # PRESET

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	w.state.festival_story_open=false  # PRESET
	w.state.time=30.0  # PRESET
	w.state.erase(JG.STATE_KEY)  # PRESET
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	w.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":false}  # PRESET
	(w.state.bobo_workshop.done as Dictionary).erase(id)  # PRESET
	w.state.bobo_workshop.jobs={}  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	for cell:Vector2i in [LANTERN,POST,PLAQUE,LAMP]:w.state.objects.erase(k(cell))  # PRESET
	for item in ["gold_ore","copper_ore","stone",JG.LANTERN_ITEM]:bag()[item]=0  # PRESET
	app.view.reduced_motion=false

func open_from_table()->void:
	await stand(TABLE_SPOT)
	await interact()
	check(layout_name()=="bobo_sort","Interact at the table opens Bobo's page (%s): %s"%[tag,layout_name()])
	await press("JgRevisitEntry")

func jinguashi_flow()->void:
	# Locked.
	await open_from_table()
	check(label_text("JgHoldText")==JG.LOCKED,"Locked page (%s)"%tag)
	await shot("page_locked")
	page_fits("locked "+tag)
	app._close_modal()
	# Not ready.
	w.state.mine_depths.hoist=true  # PRESET
	await open_from_table()
	check(label_text("JgHoldText")==JG.NOT_READY,"Not-ready page (%s)"%tag)
	await shot("page_not_ready")
	page_fits("not ready "+tag)
	app._close_modal()
	# Ready: the tracker, the table page and the empty order.
	w.state.bobo_workshop.done[id]=true  # PRESET
	await stand(TABLE_SPOT)
	check(str(app.objective.text).begins_with("礦料調度・春季訂單"),"Tracker shows the order (%s): %s"%[tag,str(app.objective.text)])
	await shot("jg_world_tracker")
	await interact()
	await shot("bobo_sort_entry")
	page_fits("bobo sort "+tag,"bobo_sort")
	await press("JgRevisitEntry")
	await shot("page_nothing_sorted")
	page_fits("nothing sorted "+tag)
	# Wrong assignment (sorted through the server).
	await press("JgSort_bobo_gold_ore")
	await press("JgSort_ferry_stone")
	check(label_text("JgShipReason_ferry")==JG.WRONG_ORE%["渡口家園工坊","石材","銅礦"],"Wrong-assignment reason (%s)"%tag)
	await shot("page_wrong")
	page_fits("wrong "+tag)
	await press("JgSort_ferry_copper_ore")
	await press("JgSort_depot_stone")
	check(label_text("JgShipReason_bobo")==JG.SHORT%["含金礦料",2,0],"Short-of-ore reason (%s)"%tag)
	await shot("page_short")
	page_fits("short "+tag)
	bag().gold_ore=2;bag().copper_ore=4;bag().stone=6  # PRESET
	await refresh()
	await press("JgShip_bobo")
	check(JG.sent(w.state)==["bobo"],"Table crate sent (%s)"%tag)
	await shot("page_partly_sent")
	page_fits("partly sent "+tag)
	app._close_modal()
	# Shuttle.
	await stand(SHUTTLE_SPOT)
	await interact()
	check(layout_name()=="travel_map" and control("JgRevisitEntry")!=null,"Ticket page with the entry (%s)"%tag)
	await shot("shuttle_entry")
	await press("JgRevisitEntry")
	await shot("page_at_shuttle")
	page_fits("at shuttle "+tag)
	await press("JgShip_ferry")
	app._close_modal()
	# Entry sign / hoist.
	await stand(HOIST_SPOT)
	await interact()
	check(layout_name()=="mine_station" and control("JgRevisitEntry")!=null,"Entry card with the entry (%s)"%tag)
	await shot("mine_entry")
	page_fits("mine entry "+tag,"mine_station")
	await press("JgRevisitEntry")
	await press("JgShip_depot")
	check(JG.completed(w.state),"Completed (%s)"%tag)
	await shot("page_completed")
	page_fits("completed "+tag)
	app._close_modal()
	# Claim at the table.
	await open_from_table()
	await press("JgClaim")
	check(int(bag().get(JG.LANTERN_ITEM,0))==1,"Lantern claimed (%s)"%tag)
	await shot("page_claimed")
	page_fits("claimed "+tag)
	app._close_modal()

func home_flow()->Array:
	for cell:Vector2i in [LANTERN,POST,PLAQUE,LAMP]:
		if World.base_resource(cell)!="":w.state.removed[k(cell)]=true  # PRESET
	await stand(ROW_VIEW,World.REGIONS.HOME)
	var bare:Image=await grab()
	w.state.objects[k(LANTERN)]={"type":JG.LANTERN_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(POST)]={"type":"lantern_post","owner":id,"items":{}}  # PRESET
	w.state.objects[k(PLAQUE)]={"type":Revisit.PLAQUE_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(LAMP)]={"type":"lamp","owner":id,"items":{}}  # PRESET
	await stand(ROW_VIEW,World.REGIONS.HOME)
	var row:Image=await shot("home_objects")
	var strip:=pixel_box(Rect2(cell_rect(LANTERN).position+Vector2(-4,-20),Vector2(32*7+8,56))).intersection(Rect2i(Vector2i.ZERO,row.get_size()))
	save_image(row.get_region(strip),"objects_strip")
	row_ok("objects "+tag,false)
	var drawn:=box_difference(bare,row,pixel_box(cell_rect(LANTERN)))
	print("NOTE %s: lantern cell changed %.0f%%"%[tag,drawn*100.0])
	check(drawn>=0.3,"Lantern drawn at its cell (%.0f%%) %s"%[drawn*100.0,tag])
	lantern_visible(row,"objects "+tag)
	var lantern_box:=pixel_box(cell_rect(LANTERN))
	for other:Array in [[POST,"紙燈籠柱"],[PLAQUE,"分水木牌"],[LAMP,"燈"]]:
		var unlike:=region_difference(row,lantern_box,pixel_box(cell_rect(other[0])))
		print("NOTE %s: lantern vs %s %.0f%%"%[tag,other[1],unlike*100.0])
		check(unlike>=0.3,"Lantern looks different from the %s (%.0f%%) %s"%[other[1],unlike*100.0,tag])
	# Static frame to frame and with reduced motion.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var later:=root.get_texture().get_image()
	check(box_difference(row,later,lantern_box)<=0.01,"Lantern static frame to frame (%s)"%tag)
	app.view.reduced_motion=true
	var reduced:Image=await shot("home_reduced")
	check(box_difference(row,reduced,lantern_box)<=0.01,"Lantern identical with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# The plain (non-preview) object path draws the same sprite.
	var art=app.view.village_art
	app.view.village_art=null
	app.view.queue_redraw()
	var legacy:Image=await shot("home_legacy")
	app.view.village_art=art
	app.view.queue_redraw()
	lantern_visible(legacy,"legacy "+tag)  # the ground differs without the village layer; the sprite is the same
	# Focused label and the visitor card.
	await stand(LANTERN_NEAR,World.REGIONS.HOME)
	check(str(app.view.interaction_focus())==k(LANTERN),"Lantern focused (%s): %s"%[tag,str(app.view.interaction_focus())])
	var focused_img:Image=await shot("home_lantern_focused")
	row_ok("focused "+tag,true)
	lantern_visible(focused_img,"focused "+tag)
	await interact()
	check(layout_name()==UI.CARD_LAYOUT and label_text("LanternSource")==JG.LANTERN_SOURCE,"Interact opens the lantern card (%s): %s"%[tag,layout_name()])
	await shot("lantern_card")
	page_fits("lantern card "+tag,UI.CARD_LAYOUT)
	var card_rect:=(app.modal as Control).get_global_rect()
	check(not card_rect.intersects(view_to_pixels(cell_rect(LANTERN))),"Card leaves the lantern in view (%s)"%tag)
	app._close_modal()
	# Backpack.
	app._inventory()
	await settle()
	if app.modal is InventoryPanel:
		app.modal.select_item(JG.LANTERN_ITEM)
		await settle()
		check(app.modal.detail_name.text=="礦燈","Backpack shows the lantern (%s)"%tag)
	await shot("inventory_lantern")
	app._close_modal()
	return [bare,row]

func exhibit_flow()->Image:
	w.state.festival_story_open=true  # PRESET
	write_lanyang()
	var saved:Dictionary=w.state[JG.STATE_KEY]
	w.state.erase(JG.STATE_KEY)  # PRESET (stashed for the lanyang-only frame, restored below)
	await stand(STAND_VIEW,World.REGIONS.HOME)
	var one:Image=await shot("exhibit_stand_lanyang")
	w.state[JG.STATE_KEY]=saved  # PRESET (restored)
	await stand(STAND_VIEW,World.REGIONS.HOME)
	var two:Image=await shot("exhibit_stand_two")
	var ped:=box_difference(one,two,pixel_box(pedestal_rect(1)))
	print("NOTE %s: lantern pedestal displayed vs empty %.0f%%"%[tag,ped*100.0])
	check(ped>=0.25,"Second pedestal shows the lantern vs an empty pedestal (%.0f%%) %s"%[ped*100.0,tag])
	check(box_difference(one,two,pixel_box(pedestal_rect(0)))<=0.01,"First pedestal (分水木牌) unchanged (%s)"%tag)
	for i in [2,3]:check(box_difference(one,two,pixel_box(pedestal_rect(i)))<=0.01,"Pedestal %d stays empty (%s)"%[i,tag])
	var strip:=pixel_box(stand_rect().grow(4.0)).intersection(Rect2i(Vector2i.ZERO,one.get_size()))
	var combined:=Image.create_empty(strip.size.x*2+4,strip.size.y,false,one.get_format())
	combined.fill(Color("392d23"))
	combined.blit_rect(one,strip,Vector2i.ZERO)
	combined.blit_rect(two,strip,Vector2i(strip.size.x+4,0))
	save_image(combined,"stand_strip")
	var plaque_vs_lantern:=region_difference(two,pixel_box(pedestal_rect(0)),pixel_box(pedestal_rect(1)))
	print("NOTE %s: plaque pedestal vs lantern pedestal %.0f%%"%[tag,plaque_vs_lantern*100.0])
	check(plaque_vs_lantern>=0.25,"The two exhibits are distinguishable on the stand (%.0f%%) %s"%[plaque_vs_lantern*100.0,tag])
	await stand(STAND_NEAR,World.REGIONS.HOME)
	await interact()
	check(layout_name()==ExhibitUI.LAYOUT,"Exhibit page opens (%s)"%tag)
	await press("MemoryCard_jinguashi")
	check(label_text("MemoryDetailName")=="礦燈" and label_text("MemoryHint")==Exhibit.HINT_JG_CLAIMED,"Lantern detail and hint (%s): %s"%[tag,label_text("MemoryHint")])
	await shot("exhibit_page_lantern")
	page_fits("exhibit lantern "+tag,ExhibitUI.LAYOUT)
	await press("MemoryRecap")
	for i in 3:await press("MemoryNext")
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and label_text("MemoryBadge_jinguashi")==ExhibitUI.BADGE_SEEN,"Last lantern page sent the view (%s)"%tag)
	await shot("exhibit_recap_last")
	page_fits("exhibit recap last "+tag,ExhibitUI.LAYOUT)
	app._close_modal()
	return two

func size_flow()->void:
	reset()
	await refresh()
	await jinguashi_flow()
	await home_flow()
	await exhibit_flow()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/金瓜石回訪預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("jinguashi-revisit-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"礦燈旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=50,"25 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
