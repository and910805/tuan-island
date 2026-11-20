extends SceneTree
## 第 40 章「貓空與鶯歌回訪・茶罐大單」＋「茶陶組」native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/茶罐大單預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_jinguashi_revisit_scene.gd.
##
## Art is runtime-painted, no new PNGs: tea ware = tea_revisit_art.teaware_texture() (32×32:
## celadon teapot and two cream cups on a red-brown wooden tray); the exhibit stand's third
## pedestal = tea_revisit_art.mini().
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * chapter one complete (board / picnic / chapter_one flags); my tea_ceramics record =
##    FRESH with intro / potter / potter_story / trials / reused / tea_discussed, and
##    comparison_complete false then true; state.time (day 1, spring); state.tea_revisit
##    erased before each size and stashed/restored once for the 「two exhibits」 stand frame;
##  * jar and tea counts in my bag (0, then tea_returned_jar 2 / tea_worn_jar 1, later 3 more
##    worn jars; tea_light 4 / tea_deep 2) and one tea_ware_kit for the backpack frame;
##  * home objects placed directly for the comparison row: tea_ware (41,34), mine_lantern
##    (43,34), water_share_plaque (45,34), planter (47,34) (state.removed where a base resource
##    sits); real placement by clicks is covered in test_tea_revisit_ui;
##  * state.festival_story_open, the 蘭陽 unlock, a completed lanyang_revisit record, the hoist
##    flag, bobo_workshop.done[me] and a completed jinguashi_revisit record for the
##    three-exhibit stand; player.memory_exhibit erased;
##  * the local player is teleported by writing region/x/y (then the arrival ribbon is
##    dismissed, as 略過 does).
## REALLY EXERCISED: app._interact() at the 鶯歌 potter, the 貓空 packing table, the placed tea
##  ware and the exhibit stand; the tea pages' revisit entry and the revisit page's jar / fill /
##  send / claim buttons and the exhibit pager are pressed (`pressed.emit`) and go through
##  Session.perform → World → snapshot.
## SHOTS per size (27): page_not_ready, potter_entry, page_nothing_handed, page_partly_handed,
##  page_wrong_region, pack_entry, page_jars_short, page_jars_full, page_quota_full,
##  page_ready_to_send, page_completed, maokong_tracker, page_claimed, journal_line,
##  home_objects, home_reduced, home_legacy, home_teaware_focused, teaware_card,
##  inventory_teaware, exhibit_stand_two, exhibit_stand_three, exhibit_page_tea,
##  exhibit_recap_last; plus three crops (objects_strip, icon_strip, stand_strip).
const World=preload("res://scripts/world.gd")
const TR=preload("res://scripts/tea_revisit.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const UI=preload("res://scripts/tea_revisit_ui.gd")
const Art=preload("res://scripts/tea_revisit_art.gd")
const TeaArt=preload("res://scripts/tea_ceramics_art.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const ExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const ExhibitArt=preload("res://scripts/memory_exhibit_art.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const POTTER_SPOT:=Vector2(20.5,21.5)
const PACKER_SPOT:=Vector2(26.5,21.5)
const TEAWARE:=Vector2i(41,34)
const LANTERN:=Vector2i(43,34)
const PLAQUE:=Vector2i(45,34)
const PLANTER:=Vector2i(47,34)
const ROW_VIEW:=Vector2(44.5,37.6)
## South-west of the tea ware so my own sprite does not stand in front of it.
const TEAWARE_NEAR:=Vector2(40.3,35.3)
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
	print("TEA_REVISIT_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("TEA_REVISIT_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

## Two 32×32 textures composited on the same ground colour: share of pixels that differ.
func texture_difference(a:Texture2D,b:Texture2D)->float:
	var ia:=a.get_image();var ib:=b.get_image()
	ia.convert(Image.FORMAT_RGBA8);ib.convert(Image.FORMAT_RGBA8)
	var ground:=Color("6f9a4a")
	var changed:=0
	var total:=0
	for y in mini(ia.get_height(),ib.get_height()):
		for x in mini(ia.get_width(),ib.get_width()):
			var p:=ia.get_pixel(x,y);var q:=ib.get_pixel(x,y)
			if p.a<0.5 and q.a<0.5:continue
			total+=1
			var pc:=ground.lerp(Color(p.r,p.g,p.b),p.a);var qc:=ground.lerp(Color(q.r,q.g,q.b),q.a)
			if absf(pc.r-qc.r)+absf(pc.g-qc.g)+absf(pc.b-qc.b)>0.12:changed+=1
	return float(changed)/maxf(1.0,float(total))

## Share of the tea ware's opaque pixels that appear as painted at its cell.
func teaware_visible(image:Image,label:String)->void:
	var art:Image=Art.teaware_texture().get_image()
	var box:=cell_rect(TEAWARE)
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
	print("NOTE %s: tea ware pixels as painted %.0f%%"%[label,share*100.0])
	check(share>=0.85,"Tea ware drawn as painted, nothing covers it (%s): %.0f%%"%[label,share*100.0])

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
	for cell:Vector2i in [TEAWARE,LANTERN,PLAQUE,PLANTER]:
		var px:=view_to_pixels(cell_rect(cell))
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Object %s on screen (%s)"%[str(cell),label])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Object %s clear of HUD %s (%s)"%[str(cell),panel.name,label])
	if not focused:return
	var list:=placements()
	var mine:Dictionary={}
	for entry:Dictionary in list:
		if str(entry.id)==k(TEAWARE):mine=entry
	check(not mine.is_empty() and str(mine.title)==TR.TEAWARE_NAME,"Tea ware label placed (%s): %s"%[label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var r:Rect2=mine.rect
	var art_box:=Rect2(cell_rect(TEAWARE).position+Vector2(1,8),Vector2(30,22))  # the painted part (teapot knob to tray feet)
	check(not r.intersects(art_box),"Tea ware label not over the tea ware (%s) %s"%[label,str(r)])
	for other:Dictionary in list:
		if other==mine:continue
		check(not r.grow(1.0).intersects(other.rect),"Tea ware label does not overlap 「%s」 (%s)"%[other.title,label])
	for panel:Dictionary in hud_panels():check(not view_to_pixels(r).intersects(panel.rect),"Tea ware label clear of HUD %s (%s)"%[panel.name,label])

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

func reset()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	w.state.festival_story_open=false  # PRESET
	w.state.time=30.0  # PRESET
	var rec:Dictionary=Tea.FRESH.duplicate(true)
	for field in ["intro","potter","potter_story","reused","tea_discussed"]:rec[field]=true  # PRESET
	rec.trials={"jar":true,"fiber":true}  # PRESET
	w.state.tea_ceramics.players[id]=rec  # PRESET
	w.state.erase(TR.STATE_KEY)  # PRESET
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	w.state.erase(JG.STATE_KEY)  # PRESET
	person().erase(Exhibit.RECORD_KEY)  # PRESET
	for cell:Vector2i in [TEAWARE,LANTERN,PLAQUE,PLANTER]:w.state.objects.erase(k(cell))  # PRESET
	for item in ["tea_returned_jar","tea_worn_jar","tea_jar","tea_spent_jar","tea_light","tea_deep",TR.TEAWARE_ITEM]:bag()[item]=0  # PRESET
	app.view.reduced_motion=false

func open_at(spot:Vector2,region:String,entry_shot:String="")->void:
	await stand(spot,region)
	await interact()
	check(layout_name()=="tea_ceramics" and control("TeaRevisitEntry")!=null,"Tea page with the revisit entry at %s (%s): %s"%[region,tag,layout_name()])
	if not entry_shot.is_empty():
		await shot(entry_shot)
		page_fits(entry_shot+" "+tag,"tea_ceramics")
	await press("TeaRevisitEntry")
	check(layout_name()==UI.LAYOUT,"Revisit page opens (%s)"%tag)

func order_map(expected_cell:Vector2i,action:String,step:String)->void:
	app._map_menu()
	await settle()
	if not is_instance_valid(app.map_view):
		check(false,"The local map opens (%s)"%tag)
		return
	var guide:Dictionary=app.map_view.tea_map_guide(app.map_view.data,app.session.own_id)
	check(guide.get("target")==expected_cell and guide.get("title")==action,"The local map points to %s (%s)"%[action,tag])
	await shot(step)
	app._close_modal()
	await settle()

func tea_flow()->void:
	# Not ready.
	await open_at(POTTER_SPOT,"yingge")
	check(label_text("TrHoldText")==TR.NOT_READY,"Not-ready page (%s)"%tag)
	await shot("page_not_ready")
	page_fits("not ready "+tag)
	app._close_modal()
	w.state.tea_ceramics.players[id].comparison_complete=true  # PRESET
	# Nothing handed, at the potter.
	bag().tea_jar=1;bag().tea_spent_jar=1  # PRESET (refusal note)
	await open_at(POTTER_SPOT,"yingge","potter_entry")
	check(label_text("TrJarOther")==TR.NEW_JAR+"\n"+TR.SPENT_JAR,"Refusal note (%s)"%tag)
	await shot("page_nothing_handed")
	page_fits("nothing handed "+tag)
	bag().tea_jar=0;bag().tea_spent_jar=0  # PRESET
	bag().tea_returned_jar=2;bag().tea_worn_jar=1  # PRESET
	await refresh()
	await press("Tr_tea_returned_jar")
	await press("Tr_tea_returned_jar")
	await press("Tr_tea_worn_jar")
	check(TR.jars_total(w.state)==3,"Three jars handed in (%s)"%tag)
	await shot("page_partly_handed")
	page_fits("partly handed "+tag)
	bag().tea_light=4;bag().tea_deep=2;bag().tea_worn_jar=1  # PRESET
	await refresh()
	check(label_text("TrFillReason")==UI.AWAY_FILL%[26,20],"Wrong region reason (%s): %s"%[tag,label_text("TrFillReason")])
	await shot("page_wrong_region")
	page_fits("wrong region "+tag)
	app._close_modal()
	# 貓空: three light jars, then the jars run short.
	await open_at(PACKER_SPOT,"maokong","pack_entry")
	for n in 3:await press("Tr_light")
	check(label_text("TrFillReason")==TR.NEED_JARS%[3,3],"Jars short (%s)"%tag)
	await shot("page_jars_short")
	page_fits("jars short "+tag)
	app._close_modal()
	await stand(PACKER_SPOT,"maokong")
	check(str(app.objective.text)=="茶罐大單・空罐 3／6\n帶回收空罐到鶯歌交給陶師","Tracker in 貓空 (%s): %s"%[tag,str(app.objective.text)])
	await shot("maokong_tracker")
	await order_map(World.TRANSIT.STATIONS.maokong.cell,"交回收空罐","map_return_jars")
	# Back to 鶯歌 for the last three jars.
	bag().tea_worn_jar=3  # PRESET
	await open_at(POTTER_SPOT,"yingge")
	for n in 3:await press("Tr_tea_worn_jar")
	check(TR.jars_total(w.state)==6,"Six jars (%s)"%tag)
	await shot("page_jars_full")
	page_fits("jars full "+tag)
	app._close_modal()
	await open_at(PACKER_SPOT,"maokong")
	await press("Tr_light")
	check(label_text("TrFillReason")==TR.QUOTA_FULL%["淺焙",4,4,"深焙"],"Quota full (%s)"%tag)
	await shot("page_quota_full")
	page_fits("quota full "+tag)
	app._close_modal()
	await order_map(TR.PACKER,"裝罐・深焙","map_fill_order")
	await open_at(PACKER_SPOT,"maokong")
	await press("Tr_deep")
	await press("Tr_deep")
	check(not (control("TrSend") as Button).disabled,"Ready to send (%s)"%tag)
	await shot("page_ready_to_send")
	page_fits("ready to send "+tag)
	app._close_modal()
	await order_map(TR.PACKER,"寄出茶罐大單","map_send_order")
	await open_at(PACKER_SPOT,"maokong")
	await press("TrSend")
	check(TR.completed(w.state),"Completed (%s)"%tag)
	await shot("page_completed")
	page_fits("completed "+tag)
	app._close_modal()
	await order_map(World.TRANSIT.STATIONS.maokong.cell,"領茶陶組","map_claim_teaware")
	await open_at(POTTER_SPOT,"yingge")
	await press("TrClaim")
	check(int(bag().get(TR.TEAWARE_ITEM,0))==1,"Tea ware claimed (%s)"%tag)
	await shot("page_claimed")
	page_fits("claimed "+tag)
	app._close_modal()
	app.TeaUI.open(app,"journal")
	await settle()
	check(label_text("TeaRevisitLine").begins_with("✓ 茶罐大單寄出了"),"Notebook line (%s)"%tag)
	await shot("journal_line")
	page_fits("journal "+tag,"tea_ceramics")
	app._close_modal()

func tea_house_flow()->void:
	# Directly below the table (same cell World.move_player uses as "by_table"): table 1.0 away, the tea
	# house door (19,22) 1.41 away, so the nearest-point rule in main._interact picks the table. The old
	# spot (-0.5,+1.5) was 1.0 from the door and 1.41 from the table, so E walked into the house.
	var stand_at:=Vector2(TR.HOUSE_SITE+Vector2i.DOWN)+Vector2(0.5,0.5)
	await stand(stand_at,"maokong")
	check(not w.act(id,"house-before-"+tag,TR.HOUSE_DISPLAY,TR.HOUSE_SITE).ok,"The unfinished festival keeps the tea house project locked (%s)"%tag)
	w.state.festival_story_open=true  # PRESET: this suite starts after the festival.
	var table_center:=Vector2(TR.HOUSE_SITE)+Vector2(0.5,0.5)
	person().x=table_center.x
	person().y=table_center.y
	w.move_player(id,Vector2.DOWN,0.05)
	check(Vector2(person().x,person().y).distance_to(table_center)>0.75,
		"A player on the newly reserved site can move away (%s)"%tag)
	await stand(stand_at,"maokong")
	await refresh()
	await interact()
	var panel_open:=is_instance_valid(app.modal) and str((app.modal as Node).get_meta("tea_site",""))=="house"
	check(panel_open,"Interacting at the table opens the tea house panel (%s)"%tag)
	if not panel_open:return
	await press("TeaHouseDisplay")
	check(int(bag().get(TR.TEAWARE_ITEM,0))==0 and w.state.get(TR.HOUSE_KEY,{}).get("lender")==id,
		"Loaning moves the earned tea ware to the shared display (%s)"%tag)
	var saved:=World.new()
	check(saved.load_world(path) and saved.state.get(TR.HOUSE_KEY,{}).get("lender")==id,"The tea house loan survives reload (%s)"%tag)
	var guest:="tea-house-visitor-"+tag
	w.add_player(guest,"來訪島民")
	w.state.players[guest].region="maokong"
	w.state.players[guest].x=stand_at.x
	w.state.players[guest].y=stand_at.y
	check(not w.act(guest,"house-take-"+tag,TR.HOUSE_RECLAIM,TR.HOUSE_SITE).ok
		and w.state.get(TR.HOUSE_KEY,{}).get("lender")==id,"Visitors cannot take another player's tea ware (%s)"%tag)
	bag().tea_light=1  # PRESET: one portion of roast tea for the tea house.
	await refresh()
	await press("TeaHouseBrew_light")
	check(int(bag().get("tea_light",0))==0 and w.state[TR.HOUSE_KEY].round.portions==6,"One roast makes six cups (%s)"%tag)
	check(not w.act(id,"house-hot-take-"+tag,TR.HOUSE_RECLAIM,TR.HOUSE_SITE).ok,"Hot tea keeps the tray on the table (%s)"%tag)
	await press("TeaHouseSip")
	check((control("TeaHouseSip") as Button).disabled and w.state[TR.HOUSE_KEY].round.portions==5,"The lender can sip once per pot (%s)"%tag)
	check(w.act(guest,"house-sip-"+tag,World.TEA_SERVICE.HOUSE_SIP,TR.HOUSE_SITE).ok and w.state[TR.HOUSE_KEY].round.portions==4,
		"A second islander shares the same pot (%s)"%tag)
	check(not w.act(guest,"house-sip-again-"+tag,World.TEA_SERVICE.HOUSE_SIP,TR.HOUSE_SITE).ok,"A second sip from the same islander is refused (%s)"%tag)
	await refresh()
	var public_display:Dictionary=app.session.snapshot[TR.HOUSE_KEY]
	check(public_display.round.portions==4 and not public_display.round.has("claimed") and public_display.sipped_own,
		"The client sees cups and its own sip without other islanders' IDs (%s)"%tag)
	check(saved.load_world(path) and saved.state[TR.HOUSE_KEY].round.portions==4,"The shared pot survives reload (%s)"%tag)
	await shot("tea_house_panel")
	app._close_modal()
	await settle()
	var view:Node=app.view
	var had_motion:bool=not app.view.reduced_motion
	var was_processing:=view.is_processing()
	view.set_process(false)
	app.view.reduced_motion=false
	app.view.elapsed=0.0
	await refresh()
	var steam_box:=pixel_box(Rect2(cell_rect(TR.HOUSE_SITE).position+Vector2(17,-24),Vector2(16,23)))
	var hot:=await shot("tea_house_display")
	app.view.elapsed=0.5
	await refresh()
	var drifting:=await grab()
	check(box_difference(hot,drifting,steam_box)>0.01,"Tea steam visibly rises during normal motion (%s)"%tag)
	app.view.reduced_motion=true
	await refresh()
	var still:=await grab()
	app.view.elapsed=0.9
	await refresh()
	check(box_difference(still,await grab(),steam_box)==0.0,"Reduced motion keeps the steam still (%s)"%tag)
	var extra_guests:=PackedStringArray()
	for i in 4:
		var visitor:="tea-house-cup-%s-%d"%[tag,i]
		w.add_player(visitor,"試茶島民",stand_at)
		w.state.players[visitor].region="maokong"  # PRESET: additional guests arrive at the table.
		w.state.players[visitor].x=stand_at.x
		w.state.players[visitor].y=stand_at.y
		extra_guests.append(visitor)
		check(w.act(visitor,"sip-"+tag,World.TEA_SERVICE.HOUSE_SIP,TR.HOUSE_SITE).ok,"An arriving islander can drink the next cup (%s)"%tag)
	await refresh()
	var empty_pot:=await grab()
	check(w.state[TR.HOUSE_KEY].round.portions==0 and box_difference(still,empty_pot,steam_box)>0.01,
		"The finished pot stops steaming (%s)"%tag)
	bag().tea_deep=1  # PRESET: a second pot to verify overnight cooling.
	await refresh()
	await interact()
	await press("TeaHouseBrew_deep")
	for visitor:String in extra_guests:
		w.state.players.erase(visitor)
		w.active_tokens.erase(visitor)
	app._close_modal()
	await refresh()
	var hot_again:=await grab()
	var original_time:float=w.state.time
	w.state.time=original_time+World.WEATHER.DAY_SECONDS  # PRESET: observe the pot on the next world day.
	await refresh()
	check(box_difference(hot_again,await grab(),steam_box)>0.01,"Overnight cooling removes the visible steam (%s)"%tag)
	app.view.reduced_motion=not had_motion
	view.set_process(was_processing)
	await interact()
	check((control("TeaHouseSip") as Button).disabled and not (control("TeaHouseReclaim") as Button).disabled,
		"Yesterday's pot cools and the lender can take back the tray (%s)"%tag)
	await press("TeaHouseReclaim")
	check(int(bag().get(TR.TEAWARE_ITEM,0))==1 and not w.state.has(TR.HOUSE_KEY),"The lender can take the same set back (%s)"%tag)
	w.state.time=original_time
	w.state.players.erase(guest)
	w.active_tokens.erase(guest)
	app._close_modal()

func home_flow()->void:
	for cell:Vector2i in [TEAWARE,LANTERN,PLAQUE,PLANTER]:
		if World.base_resource(cell)!="":w.state.removed[k(cell)]=true  # PRESET
	await stand(ROW_VIEW,World.REGIONS.HOME)
	var bare:Image=await grab()
	w.state.objects[k(TEAWARE)]={"type":TR.TEAWARE_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(LANTERN)]={"type":JG.LANTERN_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(PLAQUE)]={"type":Revisit.PLAQUE_KIND,"owner":id,"items":{}}  # PRESET
	w.state.objects[k(PLANTER)]={"type":"planter","owner":id,"items":{}}  # PRESET
	await stand(ROW_VIEW,World.REGIONS.HOME)
	var row:Image=await shot("home_objects")
	var strip:=pixel_box(Rect2(cell_rect(TEAWARE).position+Vector2(-4,-20),Vector2(32*7+8,56))).intersection(Rect2i(Vector2i.ZERO,row.get_size()))
	save_image(row.get_region(strip),"objects_strip")
	row_ok("objects "+tag,false)
	var drawn:=box_difference(bare,row,pixel_box(cell_rect(TEAWARE)))
	print("NOTE %s: tea ware cell changed %.0f%%"%[tag,drawn*100.0])
	check(drawn>=0.3,"Tea ware drawn at its cell (%.0f%%) %s"%[drawn*100.0,tag])
	teaware_visible(row,"objects "+tag)
	var ware_box:=pixel_box(cell_rect(TEAWARE))
	for other:Array in [[LANTERN,"礦燈"],[PLAQUE,"分水木牌"],[PLANTER,"窗邊花箱"]]:
		var unlike:=region_difference(row,ware_box,pixel_box(cell_rect(other[0])))
		print("NOTE %s: tea ware vs %s %.0f%%"%[tag,other[1],unlike*100.0])
		check(unlike>=0.3,"Tea ware looks different from the %s (%.0f%%) %s"%[other[1],unlike*100.0,tag])
	# Jar-like art (the tea jars and the old placeholder icon) is not placeable: compare the textures.
	var icons:=Image.create_empty(32*5+16,32,false,Image.FORMAT_RGBA8)
	icons.fill(Color("6f9a4a"))
	var x:=0
	for item:Array in [[Art.teaware_texture(),"茶陶組"],[TeaArt.icon("tea_jar"),"陶罐"],[TeaArt.icon("tea_worn_jar"),"磨損陶罐"],[TeaArt.icon("wrapped_jar"),"陶罐包裝"],[preload("res://scripts/jinguashi_revisit_art.gd").lantern_texture(),"礦燈"]]:
		var tex:Texture2D=item[0]
		if tex!=null:
			var img:=tex.get_image();img.convert(Image.FORMAT_RGBA8)
			icons.blend_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),Vector2i(x,0))
			if x>0:
				var unlike:=texture_difference(Art.teaware_texture(),tex)
				print("NOTE %s: tea ware art vs %s %.0f%%"%[tag,item[1],unlike*100.0])
				check(unlike>=0.3,"Tea ware art differs from %s (%.0f%%) %s"%[item[1],unlike*100.0,tag])
		x+=36
	icons.resize(icons.get_width()*4,icons.get_height()*4,Image.INTERPOLATE_NEAREST)
	save_image(icons,"icon_strip")
	# Static frame to frame and with reduced motion.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var later:=root.get_texture().get_image()
	check(box_difference(row,later,ware_box)<=0.01,"Tea ware static frame to frame (%s)"%tag)
	app.view.reduced_motion=true
	var reduced:Image=await shot("home_reduced")
	check(box_difference(row,reduced,ware_box)<=0.01,"Tea ware identical with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# The plain (non-preview) object path draws the same sprite.
	var art=app.view.village_art
	app.view.village_art=null
	app.view.queue_redraw()
	var legacy:Image=await shot("home_legacy")
	app.view.village_art=art
	app.view.queue_redraw()
	teaware_visible(legacy,"legacy "+tag)
	# Focused label and the visitor card.
	await stand(TEAWARE_NEAR,World.REGIONS.HOME)
	check(str(app.view.interaction_focus())==k(TEAWARE),"Tea ware focused (%s): %s"%[tag,str(app.view.interaction_focus())])
	var focused_img:Image=await shot("home_teaware_focused")
	row_ok("focused "+tag,true)
	teaware_visible(focused_img,"focused "+tag)
	await interact()
	check(layout_name()==UI.CARD_LAYOUT and label_text("TeawareSource")==TR.TEAWARE_SOURCE,"Interact opens the tea ware card (%s): %s"%[tag,layout_name()])
	await shot("teaware_card")
	page_fits("tea ware card "+tag,UI.CARD_LAYOUT)
	var card_rect:=(app.modal as Control).get_global_rect()
	check(not card_rect.intersects(view_to_pixels(cell_rect(TEAWARE))),"Card leaves the tea ware in view (%s)"%tag)
	app._close_modal()
	# Backpack.
	app._inventory()
	await settle()
	if app.modal is InventoryPanel:
		app.modal.select_item(TR.TEAWARE_ITEM)
		await settle()
		check(app.modal.detail_name.text=="茶陶組","Backpack shows the tea ware (%s)"%tag)
	await shot("inventory_teaware")
	app._close_modal()

func exhibit_flow()->void:
	w.state.festival_story_open=true  # PRESET
	write_other_exhibits()
	var saved:Dictionary=w.state[TR.STATE_KEY]
	w.state.erase(TR.STATE_KEY)  # PRESET (stashed for the two-exhibit frame, restored below)
	await stand(STAND_VIEW,World.REGIONS.HOME)
	var two:Image=await shot("exhibit_stand_two")
	w.state[TR.STATE_KEY]=saved  # PRESET (restored)
	await stand(STAND_VIEW,World.REGIONS.HOME)
	var three:Image=await shot("exhibit_stand_three")
	var ped:=box_difference(two,three,pixel_box(pedestal_rect(2)))
	print("NOTE %s: tea ware pedestal displayed vs empty %.0f%%"%[tag,ped*100.0])
	check(ped>=0.25,"Third pedestal shows the tea ware vs an empty pedestal (%.0f%%) %s"%[ped*100.0,tag])
	for i in [0,1,3]:check(box_difference(two,three,pixel_box(pedestal_rect(i)))<=0.01,"Pedestal %d unchanged (%s)"%[i,tag])
	var strip:=pixel_box(stand_rect().grow(4.0)).intersection(Rect2i(Vector2i.ZERO,two.get_size()))
	var combined:=Image.create_empty(strip.size.x*2+4,strip.size.y,false,two.get_format())
	combined.fill(Color("392d23"))
	combined.blit_rect(two,strip,Vector2i.ZERO)
	combined.blit_rect(three,strip,Vector2i(strip.size.x+4,0))
	save_image(combined,"stand_strip")
	for other:Array in [[0,"分水木牌"],[1,"礦燈"]]:
		var unlike:=region_difference(three,pixel_box(pedestal_rect(other[0])),pixel_box(pedestal_rect(2)))
		print("NOTE %s: %s pedestal vs tea ware pedestal %.0f%%"%[tag,other[1],unlike*100.0])
		check(unlike>=0.25,"Tea ware distinguishable from the %s on the stand (%.0f%%) %s"%[other[1],unlike*100.0,tag])
	await stand(STAND_NEAR,World.REGIONS.HOME)
	await interact()
	check(layout_name()==ExhibitUI.LAYOUT,"Exhibit page opens (%s)"%tag)
	await press("MemoryCard_tea_pottery")
	check(label_text("MemoryDetailName")=="陶器" and label_text("MemoryHint")==Exhibit.HINT_TEA_CLAIMED,"Tea detail and hint (%s): %s"%[tag,label_text("MemoryHint")])
	await shot("exhibit_page_tea")
	page_fits("exhibit tea "+tag,ExhibitUI.LAYOUT)
	await press("MemoryRecap")
	for i in 3:await press("MemoryNext")
	check(label_text("MemoryPageTitle").begins_with("回顧 4／4") and label_text("MemoryBadge_tea_pottery")==ExhibitUI.BADGE_SEEN,"Last tea page sent the view (%s)"%tag)
	await shot("exhibit_recap_last")
	page_fits("exhibit recap last "+tag,ExhibitUI.LAYOUT)
	app._close_modal()

func size_flow()->void:
	reset()
	await refresh()
	await tea_flow()
	await tea_house_flow()
	await home_flow()
	await exhibit_flow()

func run()->void:
	create_timer(170.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 170 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/茶罐大單預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("tea-revisit-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"茶陶旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=54,"27 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
