extends SceneTree
## 第 40 章「臺南北門回訪・鹽籃批次」＋「鹽籃」native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/鹽籃批次預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_tea_revisit_scene.gd.
##
## Art is runtime-painted, no new PNGs: 鹽籃 = salt_revisit_art.basket_texture() (32×32: a wide
## woven bamboo basket with a hoop handle and red cord knots, heaped with white sea salt); the
## exhibit stand's fourth pedestal = salt_revisit_art.mini().
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * the chapter 1/2/3 story fixture of test_salt_revisit (picnic / board / chapter_one, a
##    finished tea comparison, a complete flower record + garden, travel_book tianwei + beimen);
##    my salt_pan record (letter / intro; then raked 1 + auto_raked / order / complete);
##    the three Beimen gates (unrepaired, then repaired); state.time (day 1, a rainy Beimen day,
##    the dry day after); state.salt_revisit erased before each size;
##  * sea_salt and fiber counts in my bag and one salt_basket_kit for the backpack frame;
##  * home objects placed directly for the comparison row: salt_basket (41,34), tea_ware (43,34),
##    mine_lantern (45,34), water_share_plaque (47,34), veg_basket_rack (48,36) (state.removed
##    where a base resource sits); real placement by clicks is covered in test_salt_revisit_ui;
##  * state.festival_story_open, the 蘭陽 unlock + completed lanyang_revisit, the hoist flag,
##    bobo_workshop.done[me], completed jinguashi_revisit and tea_revisit records; state.salt_revisit
##    is stashed/restored once for the 「three exhibits」 stand frame; player.memory_exhibit erased;
##  * the local player is teleported by writing region/x/y (then the arrival ribbon is dismissed).
## REALLY EXERCISED: app._interact() at 阿曬, the co-op chest, the 鹽田站牌 bus stop, the placed
##  basket and the exhibit stand; the Beimen pages' entry and the batch page's stock / pack / send /
##  claim buttons and the exhibit pager are pressed (`pressed.emit`) and go through
##  Session.perform → World → snapshot.
## SHOTS per size (29 frames + 3 crops = 32): worker_locked_entry, stop_locked_entry, page_locked, page_not_ready,
##  worker_entry, page_nothing_stocked, page_partly_stocked, page_wrong_spot, chest_entry,
##  page_short_fiber, page_quota_full, page_rainy_day, beimen_tracker, page_stock_full,
##  page_ready_to_send, stop_entry, page_completed, page_claimed, journal_line, home_objects,
##  home_reduced, home_legacy, home_basket_focused, basket_card, inventory_basket,
##  exhibit_stand_three, exhibit_stand_four, exhibit_page_salt, exhibit_recap_last; plus three
##  crops (objects_strip, icon_strip, stand_strip).
const World=preload("res://scripts/world.gd")
const SR=preload("res://scripts/salt_revisit.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const UI=preload("res://scripts/salt_revisit_ui.gd")
const Art=preload("res://scripts/salt_revisit_art.gd")
const TeaWareArt=preload("res://scripts/tea_revisit_art.gd")
const LanternArt=preload("res://scripts/jinguashi_revisit_art.gd")
const PlaqueArt=preload("res://scripts/lanyang_revisit_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const ExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const ExhibitArt=preload("res://scripts/memory_exhibit_art.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Weather=preload("res://scripts/weather.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const BASKET:=Vector2i(41,34)
const TEAWARE:=Vector2i(43,34)
const LANTERN:=Vector2i(45,34)
const PLAQUE:=Vector2i(47,34)
const RACK:=Vector2i(48,36)
const ROW_VIEW:=Vector2(44.5,37.6)
## South-west of the basket so my own sprite does not stand in front of it.
const BASKET_NEAR:=Vector2(40.3,35.3)
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
var rain_time:=0.0
var dry_time:=0.0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SALT_REVISIT_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("SALT_REVISIT_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

func salt_record()->Dictionary:
	return w.state.salt_pan.players[id]

func k(c:Vector2i)->String:
	return World.key(c)

func stand(at:Vector2,region:String)->void:
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

## Two textures composited on the same ground colour: share of pixels that differ.
func texture_difference(a:Texture2D,b:Texture2D)->float:
	var ia:=a.get_image();var ib:=b.get_image()
	ia.convert(Image.FORMAT_RGBA8);ib.convert(Image.FORMAT_RGBA8)
	if ib.get_size()!=ia.get_size():ib.resize(ia.get_width(),ia.get_height(),Image.INTERPOLATE_NEAREST)
	var ground:=Color("6f9a4a")
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

## Share of the basket's opaque pixels that appear as painted at its cell.
func basket_visible(image:Image,label:String)->void:
	var art:Image=Art.basket_texture().get_image()
	var box:=cell_rect(BASKET)
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
	print("NOTE %s: basket pixels as painted %.0f%%"%[label,share*100.0])
	check(share>=0.85,"Basket drawn as painted, nothing covers it (%s): %.0f%%"%[label,share*100.0])

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

func row_ok(label:String,focused:bool)->void:
	# The veg basket rack is only compared in the row frame (the focused frame centres further west).
	for cell:Vector2i in ([BASKET,TEAWARE,LANTERN,PLAQUE] if focused else [BASKET,TEAWARE,LANTERN,PLAQUE,RACK]):
		var px:=view_to_pixels(cell_rect(cell))
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Object %s on screen (%s)"%[str(cell),label])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Object %s clear of HUD %s (%s)"%[str(cell),panel.name,label])
	if not focused:return
	var list:=placements()
	var mine:Dictionary={}
	for entry:Dictionary in list:
		if str(entry.id)==k(BASKET):mine=entry
	check(not mine.is_empty() and str(mine.title)==SR.BASKET_NAME,"Basket label placed (%s): %s"%[label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var r:Rect2=mine.rect
	var art_box:=Rect2(cell_rect(BASKET).position+Vector2(2,2),Vector2(28,28))  # the painted part (handle top to the foot)
	check(not r.intersects(art_box),"Basket label not over the basket (%s) %s"%[label,str(r)])
	for other:Dictionary in list:
		if other==mine:continue
		check(not r.grow(1.0).intersects(other.rect),"Basket label does not overlap 「%s」 (%s)"%[other.title,label])
	for panel:Dictionary in hud_panels():check(not view_to_pixels(r).intersects(panel.rect),"Basket label clear of HUD %s (%s)"%[panel.name,label])

func stand_rect()->Rect2:
	return ExhibitUI.stand_rect(app.view,STAND)

func pedestal_rect(index:int)->Rect2:
	var cx:int=ExhibitArt.PEDESTALS[index]
	return Rect2(stand_rect().position+Vector2(cx-5,25),Vector2(11,13))

# ------------------------------------------------------------------ flows --

func write_other_exhibits()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true  # PRESET
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()  # PRESET
	life.repaired=true  # PRESET
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}  # PRESET
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}  # PRESET
	w.state.mine_depths={"unlocked":6,"ready":{},"pumped":24,"hoist":true}  # PRESET
	w.state.bobo_workshop.done[id]=true  # PRESET
	w.state[JG.STATE_KEY]={"crates":{"bobo":"gold_ore","ferry":"copper_ore","depot":"stone"},"day":1,"sent":["bobo","ferry","depot"],"completed":true,"done_day":1,"claimed":{}}  # PRESET
	w.state[TR.STATE_KEY]={"jars":{"tea_returned_jar":2,"tea_worn_jar":4},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":1,"claimed":{}}  # PRESET

func set_gates(repaired:bool)->void:
	for g in Salt.GATE_ROWS.size():
		w.state.salt_pan.gates[g]={"plank":6,"resin":1,"stone":4} if repaired else {"plank":0,"resin":0,"stone":0}  # PRESET
	w.state.salt_pan.repaired_at=1.0 if repaired else -1.0  # PRESET

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.picnic=true  # PRESET
	w.state.board=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	var tea:Dictionary=Tea.FRESH.duplicate(true)
	tea.intro=true;tea.potter=true;tea.reused=true;tea.reuse_count=1
	tea.trials={"jar":true,"fiber":true};tea.tea_discussed=true;tea.comparison_complete=true
	w.state.tea_ceramics.players[id]=tea  # PRESET
	var a:Dictionary=Flower.FRESH.duplicate(true)
	a.letter=true;a.intro=true;a.shipped=true;a.complete=true
	for kind in Flower.FLOWERS:
		a.planted[kind]=true;a.harvested[kind]=2;a.saved[kind]=true
	w.state.flower_nursery.players[id]=a  # PRESET
	person().travel_book.visited[Flower.REGION]=true  # PRESET
	person().travel_book.visited[Salt.REGION]=true  # PRESET
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},"contributors":{id:10},"complete":true,"completed_at":0.0}  # PRESET
	var rec:Dictionary=Salt.RECORD.duplicate(true)
	rec.letter=true;rec.intro=true
	w.state.salt_pan.players[id]=rec  # PRESET
	set_gates(false)
	w.state.festival_story_open=false  # PRESET
	w.state.time=30.0  # PRESET
	for key in [SR.STATE_KEY,Revisit.STATE_KEY,JG.STATE_KEY,TR.STATE_KEY]:w.state.erase(key)  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	for cell:Vector2i in [BASKET,TEAWARE,LANTERN,PLAQUE,RACK]:w.state.objects.erase(k(cell))  # PRESET
	for item in ["sea_salt","fiber",SR.BASKET_ITEM]:bag()[item]=0  # PRESET
	app.view.reduced_motion=false

func open_entry(entry_shot:String="",expected:String="salt_pan")->void:
	check(control("SaltRevisitEntry")!=null,"Entry offered on %s (%s)"%[expected,tag])
	if not entry_shot.is_empty():
		await shot(entry_shot)
		page_fits(entry_shot+" "+tag,expected)
	await press("SaltRevisitEntry")
	check(layout_name()==UI.LAYOUT,"Batch page opens (%s)"%tag)

func open_at(spot:Vector2,entry_shot:String="")->void:
	await stand(spot,SR.REGION)
	await interact()
	await open_entry(entry_shot,"travel_map" if spot==SR.STOP_STAND else "salt_pan")

func batch_map(expected:Vector2i,label:String)->void:
	app._map_menu()
	await settle()
	if not is_instance_valid(app.map_view):
		check(false,"The Beimen local map opens (%s)"%tag)
		return
	var marks:Dictionary=app.map_view.salt_landmarks(app.map_view.data,app.session.own_id)
	check(marks.target==expected and marks.note.begins_with("鹽籃批次"),"The batch map shows %s (%s)"%[label,tag])
	await shot(label)
	app._close_modal()
	await settle()

func salt_flow()->void:
	# Locked: entries on 阿曬's page and the bus stop, then the page.
	await stand(SR.STOP_STAND,SR.REGION)
	await interact()
	check(layout_name()=="travel_map" and control("SaltRevisitEntry")!=null and (control("SaltRevisitEntry") as Button).text==UI.ENTRY_LOCKED,"Locked caption on the bus stop page (%s)"%tag)
	await shot("stop_locked_entry")
	page_fits("stop locked "+tag,"travel_map")
	app._close_modal()
	await open_at(SR.WORKER_STAND,"worker_locked_entry")
	check(label_text("SrLockedText")==SR.LOCKED,"Locked page (%s)"%tag)
	await shot("page_locked")
	page_fits("locked "+tag)
	app._close_modal()
	# Not ready.
	set_gates(true)
	await open_at(SR.WORKER_STAND)
	check(label_text("SrHoldText")==SR.NOT_READY,"Not-ready page (%s)"%tag)
	await shot("page_not_ready")
	page_fits("not ready "+tag)
	app._close_modal()
	var rec:=salt_record()
	rec.raked=1;rec.wheel_raked=1;rec.auto_raked=1;rec.order=true;rec.complete=true  # PRESET
	# Nothing stocked, at 阿曬.
	await open_at(SR.WORKER_STAND,"worker_entry")
	await shot("page_nothing_stocked")
	page_fits("nothing stocked "+tag)
	bag().sea_salt=13  # PRESET
	await refresh()
	for n in 4:await press("Sr_stock")
	check(SR.stocked_total(w.state)==4 and label_text("SrStockReason")==SR.NO_SALT%[3,1],"Four lots, short of salt (%s)"%tag)
	await shot("page_partly_stocked")
	page_fits("partly stocked "+tag)
	bag().fiber=2  # PRESET
	await refresh()
	check(label_text("SrPackReason")==UI.AWAY_PACK%[47,23],"Wrong spot reason (%s): %s"%[tag,label_text("SrPackReason")])
	await shot("page_wrong_spot")
	page_fits("wrong spot "+tag)
	app._close_modal()
	# The co-op chest.
	await open_at(SR.CHEST_STAND,"chest_entry")
	await press("Sr_kitchen")
	check(label_text("SrPackReason")==SR.NO_FIBER%[2,0],"Short of fiber (%s)"%tag)
	await shot("page_short_fiber")
	page_fits("short of fiber "+tag)
	bag().fiber=4  # PRESET
	await refresh()
	await press("Sr_kitchen")
	await press("Sr_kitchen")
	check(label_text("SrPackReason").contains(SR.QUOTA_FULL%["料理用",3,3,"醃漬用"]),"Quota full (%s)"%tag)
	await shot("page_quota_full")
	page_fits("quota full "+tag)
	app._close_modal()
	# A rainy Beimen day: no stocking, packing goes on.
	w.state.time=rain_time  # PRESET
	bag().sea_salt=6;bag().fiber=2  # PRESET
	await stand(SR.CHEST_STAND,SR.REGION)
	await batch_map(SR.CHEST,"map_pack_rain")
	await open_at(SR.CHEST_STAND)
	check(SR.rainy_today(w.state) and label_text("SrStockReason")==SR.RAIN_STOCK and not (control("Sr_pickle") as Button).disabled,"Rainy day: stock refused, pack enabled (%s)"%tag)
	await shot("page_rainy_day")
	page_fits("rainy day "+tag)
	check(label_text("SaltBrineLine").contains("雨停再放滷"),"Batch shows rain-dependent brine guidance (%s)"%tag)
	await press("SrBrine")
	check(layout_name()==app.SaltBrineUI.LAYOUT,"Batch opens the actual brine controls (%s)"%tag)
	await press("SbBackToBatch")
	check(layout_name()==UI.LAYOUT and label_text("SrStockReason")==SR.RAIN_STOCK,"Back restores the rainy batch page (%s)"%tag)
	await press("Sr_pickle")
	check(SR.rain_packs(w.state)==1,"Rain pack (%s)"%tag)
	app._close_modal()
	# Dry day after: two more lots; the tracker card follows the batch.
	w.state.time=dry_time  # PRESET
	bag().fiber=4  # PRESET
	await stand(SR.WORKER_STAND,SR.REGION)
	check(str(app.objective.text)=="鹽籃批次・入倉 4／6 批\n帶海鹽找阿曬入倉","Tracker in 北門 (%s): %s"%[tag,str(app.objective.text)])
	await shot("beimen_tracker")
	await batch_map(SR.WORKER,"map_stock")
	await open_at(SR.WORKER_STAND)
	await press("Sr_stock")
	await press("Sr_stock")
	check(label_text("SrStockReason")==SR.STOCK_FULL,"Stock full (%s)"%tag)
	await shot("page_stock_full")
	page_fits("stock full "+tag)
	app._close_modal()
	await open_at(SR.CHEST_STAND)
	await press("Sr_pickle")
	await press("Sr_pickle")
	check(not (control("SrSend") as Button).disabled,"Ready to send (%s)"%tag)
	await shot("page_ready_to_send")
	page_fits("ready to send "+tag)
	app._close_modal()
	await batch_map(SR.STOP,"map_send")
	await open_at(SR.STOP_STAND,"stop_entry")
	await press("SrSend")
	check(SR.completed(w.state),"Completed (%s)"%tag)
	await shot("page_completed")
	page_fits("completed "+tag)
	app._close_modal()
	await batch_map(SR.WORKER,"map_claim")
	await open_at(SR.WORKER_STAND)
	await press("SrClaim")
	check(int(bag().get(SR.BASKET_ITEM,0))==1,"Basket claimed (%s)"%tag)
	await shot("page_claimed")
	page_fits("claimed "+tag)
	app._close_modal()
	app.SaltUI.open(app,"journal")
	await settle()
	check(label_text("SaltRevisitLine").begins_with("✓ 鹽籃批次送出了"),"Journal line (%s)"%tag)
	await shot("journal_line")
	page_fits("journal "+tag,"salt_pan")
	app._close_modal()

func home_flow()->void:
	for cell:Vector2i in [BASKET,TEAWARE,LANTERN,PLAQUE,RACK]:
		if World.base_resource(cell)!="":w.state.removed[k(cell)]=true  # PRESET
	await stand(ROW_VIEW,World.REGIONS.HOME)
	var bare:Image=await grab()
	w.state.objects[k(BASKET)]={"type":SR.BASKET_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(TEAWARE)]={"type":TR.TEAWARE_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(LANTERN)]={"type":JG.LANTERN_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(PLAQUE)]={"type":Revisit.PLAQUE_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(RACK)]={"type":"veg_basket_rack","owner":id,"items":{}}  # PRESET
	await stand(ROW_VIEW,World.REGIONS.HOME)
	var row:Image=await shot("home_objects")
	var strip:=pixel_box(Rect2(cell_rect(BASKET).position+Vector2(-4,-20),Vector2(32*9+8,56+64))).intersection(Rect2i(Vector2i.ZERO,row.get_size()))
	save_image(row.get_region(strip),"objects_strip")
	row_ok("objects "+tag,false)
	var drawn:=box_difference(bare,row,pixel_box(cell_rect(BASKET)))
	print("NOTE %s: basket cell changed %.0f%%"%[tag,drawn*100.0])
	check(drawn>=0.3,"Basket drawn at its cell (%.0f%%) %s"%[drawn*100.0,tag])
	basket_visible(row,"objects "+tag)
	var basket_box:=pixel_box(cell_rect(BASKET))
	for other:Array in [[TEAWARE,"茶陶組"],[LANTERN,"礦燈"],[PLAQUE,"分水木牌"],[RACK,"菜籃小架"]]:
		var unlike:=region_difference(row,basket_box,pixel_box(cell_rect(other[0])))
		print("NOTE %s: basket vs %s %.0f%%"%[tag,other[1],unlike*100.0])
		check(unlike>=0.3,"Basket looks different from the %s (%.0f%%) %s"%[other[1],unlike*100.0,tag])
	# Textures: the basket against the other mementos, the sea_salt icon and the basket/crate kits.
	var icons:=Image.create_empty(36*7,32,false,Image.FORMAT_RGBA8)
	icons.fill(Color("6f9a4a"))
	var x:=0
	for item:Array in [[Art.basket_texture(),"鹽籃"],[TeaWareArt.teaware_texture(),"茶陶組"],[LanternArt.lantern_texture(),"礦燈"],[PlaqueArt.plaque_texture(),"分水木牌"],[Items.icon("sea_salt"),"海鹽"],[Items.icon("veg_basket_rack_kit"),"菜籃小架"],[Items.icon("relay_crate_stack_kit"),"接力菜箱堆"]]:
		var tex:Texture2D=item[0]
		check(tex!=null,"Comparison art exists: %s (%s)"%[item[1],tag])
		if tex!=null:
			var img:=tex.get_image();img.convert(Image.FORMAT_RGBA8)
			if img.get_size()!=Vector2i(32,32):img.resize(32,32,Image.INTERPOLATE_NEAREST)
			icons.blend_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),Vector2i(x,0))
			if x>0:
				var unlike:=texture_difference(Art.basket_texture(),tex)
				print("NOTE %s: basket art vs %s %.0f%%"%[tag,item[1],unlike*100.0])
				check(unlike>=0.3,"Basket art differs from %s (%.0f%%) %s"%[item[1],unlike*100.0,tag])
		x+=36
	check(Items.icon(SR.BASKET_ITEM)==Art.basket_texture() and Items.icon(SR.BASKET_ITEM)!=Items.icon("sea_salt"),"Inventory icon is the basket, not the sea salt placeholder (%s)"%tag)
	icons.resize(icons.get_width()*4,icons.get_height()*4,Image.INTERPOLATE_NEAREST)
	save_image(icons,"icon_strip")
	# Static frame to frame and with reduced motion.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var later:=root.get_texture().get_image()
	check(box_difference(row,later,basket_box)<=0.01,"Basket static frame to frame (%s)"%tag)
	app.view.reduced_motion=true
	var reduced:Image=await shot("home_reduced")
	check(box_difference(row,reduced,basket_box)<=0.01,"Basket identical with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# The plain (non-preview) object path draws the same sprite.
	var art=app.view.village_art
	app.view.village_art=null
	app.view.queue_redraw()
	var legacy:Image=await shot("home_legacy")
	app.view.village_art=art
	app.view.queue_redraw()
	basket_visible(legacy,"legacy "+tag)
	# Focused label and the visitor card.
	await stand(BASKET_NEAR,World.REGIONS.HOME)
	check(str(app.view.interaction_focus())==k(BASKET),"Basket focused (%s): %s"%[tag,str(app.view.interaction_focus())])
	var focused_img:Image=await shot("home_basket_focused")
	row_ok("focused "+tag,true)
	basket_visible(focused_img,"focused "+tag)
	await interact()
	check(layout_name()==UI.CARD_LAYOUT and label_text("BasketSource")==SR.BASKET_SOURCE,"Interact opens the basket card (%s): %s"%[tag,layout_name()])
	await shot("basket_card")
	page_fits("basket card "+tag,UI.CARD_LAYOUT)
	var card_rect:=(app.modal as Control).get_global_rect()
	check(not card_rect.intersects(view_to_pixels(cell_rect(BASKET))),"Card leaves the basket in view (%s)"%tag)
	app._close_modal()
	# Backpack.
	app._inventory()
	await settle()
	if app.modal is InventoryPanel:
		app.modal.select_item(SR.BASKET_ITEM)
		await settle()
		check(app.modal.detail_name.text=="鹽籃","Backpack shows the basket (%s)"%tag)
	await shot("inventory_basket")
	app._close_modal()

func exhibit_flow()->void:
	w.state.festival_story_open=true  # PRESET
	write_other_exhibits()
	var saved:Dictionary=w.state[SR.STATE_KEY]
	w.state.erase(SR.STATE_KEY)  # PRESET (stashed for the three-exhibit frame, restored below)
	await stand(STAND_VIEW,World.REGIONS.HOME)
	var three:Image=await shot("exhibit_stand_three")
	w.state[SR.STATE_KEY]=saved  # PRESET (restored)
	await stand(STAND_VIEW,World.REGIONS.HOME)
	var four:Image=await shot("exhibit_stand_four")
	var ped:=box_difference(three,four,pixel_box(pedestal_rect(3)))
	print("NOTE %s: basket pedestal displayed vs empty %.0f%%"%[tag,ped*100.0])
	check(ped>=0.25,"Fourth pedestal shows the basket vs an empty pedestal (%.0f%%) %s"%[ped*100.0,tag])
	for i in [0,1,2]:check(box_difference(three,four,pixel_box(pedestal_rect(i)))<=0.01,"Pedestal %d unchanged (%s)"%[i,tag])
	var strip:=pixel_box(stand_rect().grow(4.0)).intersection(Rect2i(Vector2i.ZERO,three.get_size()))
	var combined:=Image.create_empty(strip.size.x*2+4,strip.size.y,false,three.get_format())
	combined.fill(Color("392d23"))
	combined.blit_rect(three,strip,Vector2i.ZERO)
	combined.blit_rect(four,strip,Vector2i(strip.size.x+4,0))
	combined.resize(combined.get_width()*3,combined.get_height()*3,Image.INTERPOLATE_NEAREST)
	save_image(combined,"stand_strip")
	for other:Array in [[0,"分水木牌"],[1,"礦燈"],[2,"茶陶組"]]:
		var unlike:=region_difference(four,pixel_box(pedestal_rect(other[0])),pixel_box(pedestal_rect(3)))
		print("NOTE %s: %s pedestal vs basket pedestal %.0f%%"%[tag,other[1],unlike*100.0])
		check(unlike>=0.25,"Basket distinguishable from the %s on the stand (%.0f%%) %s"%[other[1],unlike*100.0,tag])
	await stand(STAND_NEAR,World.REGIONS.HOME)
	await interact()
	check(layout_name()==ExhibitUI.LAYOUT,"Exhibit page opens (%s)"%tag)
	await press("MemoryCard_beimen")
	check(label_text("MemoryDetailName")=="鹽籃" and label_text("MemoryHint")==Exhibit.HINT_SALT_CLAIMED,"Salt detail and hint (%s): %s"%[tag,label_text("MemoryHint")])
	await shot("exhibit_page_salt")
	page_fits("exhibit salt "+tag,ExhibitUI.LAYOUT)
	await press("MemoryRecap")
	for i in 3:await press("MemoryNext")
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and label_text("MemoryBadge_beimen")==ExhibitUI.BADGE_SEEN,"Last salt page sent the view (%s)"%tag)
	await shot("exhibit_recap_last")
	page_fits("exhibit recap last "+tag,ExhibitUI.LAYOUT)
	app._close_modal()

func size_flow()->void:
	reset()
	await refresh()
	await salt_flow()
	await home_flow()
	await exhibit_flow()

func run()->void:
	create_timer(220.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 220 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/鹽籃批次預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	for d in range(1,30):
		if Weather.rains(float(d),SR.REGION) and not Weather.rains(float(d+1),SR.REGION):
			rain_time=d*1440.0+30.0
			dry_time=(d+1)*1440.0+30.0
			break
	check(rain_time>0.0,"Calendar has a rainy Beimen day")
	path=OS.get_environment("TEMP").path_join("salt-revisit-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"鹽籃旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=64,"32 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
