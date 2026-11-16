extends SceneTree
## 第 40 章「定量分區配水」native render check of the water tower page's two settings rows
## (桶水保留 / 每日配水) at 1024×640 and 1280×800. Screenshots go to
## outputs/水塔定量配水預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_water_tower_scene.gd (window size, host save, settle/grab/shot,
## page_fits, pixel helpers, ending). No new art: the tower sprite must look the same
## with or without settings.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * unlock fixture written directly (canal repaired, my first memory completed, the
##    bridge plaque set, state.lanyang_revisit completed);
##  * the local player is teleported by writing region/x/y;
##  * home: one row written as objects (state.removed on tiles with a base resource, and on
##    the row in front, y=38):
##      y=37:  TANK(40) PIPE(41) S2(42) TOWER(43) S1(44) [X(45) X(46) X(47) X(48)]
##    tank water 0 (no pump, so nothing refills anything); TOWER water 48, 出水, no settings;
##    S1 小型灑水器 water 9 enabled; S2 小型灑水器 water 0 disabled. The X cells (alternating
##    中型／小型灑水器, full) are written only before page_worst_case: 6 consumers is the longest
##    list the reference fixture's row (x 40..48) holds.
##  * a neighbour's tower (46,28) written with reserve 24, quota 8, quota_day today,
##    quota_used 2, 只蓄水 (schema-valid) right before page_visitor;
##  * if the world clock is within 240 min of midnight at the start of a size, state.time is
##    written forward to 08:00 of the next day so the ticks below stay on one world day.
## REALLY EXERCISED: app._interact() opens the tower page; every settings change is a press of
##  the real 「＋」 button (TowerReserveMore / TowerQuotaMore) -> TowerUI._step ->
##  Session.perform("tower_set") -> World -> snapshot -> page; 只蓄水 is the real TowerToggle
##  button; S2 is enabled with a real Session.perform("toggle_sprinkler"); the quota is used up
##  by World.step(Industry.INTERVAL,true) called directly by this test (the same call
##  Session._physics_process makes; the session's own physics step is off), so quota_day /
##  quota_used come from the real plan_detail -> step_region path. The visitor's refused
##  tower_set is a real Session.perform; the world state is compared before/after.
##  world_after: the settings are then erased directly (PRESET) for one unsaved comparison
##  frame and written back.
## SHOTS per size: page_default, page_reserve_24, page_quota_8_partial, page_quota_done,
##  page_store_only, page_worst_case, page_visitor, world_after.
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Industry=preload("res://scripts/industry.gd")
const TowerUI=preload("res://scripts/water_tower_ui.gd")
const Art=preload("res://scripts/water_tower_art.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const OTHER:="tower-quota-neighbour-5c1e"
const ROW:=37
const TANK:=Vector2i(40,ROW)
const PIPE:=Vector2i(41,ROW)
const S2:=Vector2i(42,ROW)
const TOWER:=Vector2i(43,ROW)
const S1:=Vector2i(44,ROW)
const EXTRAS:=[Vector2i(45,ROW),Vector2i(46,ROW),Vector2i(47,ROW),Vector2i(48,ROW)]
const OTHER_TOWER:=Vector2i(46,28)
## South of the row, more than 3.2 tiles from every object (nothing focused).
const VIEW_SPOT:=Vector2(43.9,40.8)
const TOWER_SPOT:=Vector2(43.5,38.6)
const OTHER_SPOT:=Vector2(46.5,29.4)
const SHOT_STEPS:=["page_default","page_reserve_24","page_quota_8_partial","page_quota_done","page_store_only","page_worst_case","page_visitor","world_after"]
const ROW_PARTS:=["TowerReserveRow","TowerReserve","TowerReserveLess","TowerReserveMore","TowerQuotaRow","TowerQuota","TowerQuotaLess","TowerQuotaMore","TowerSupplyTitle"]
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var images:={}
var rects:={}

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("WATER_TOWER_QUOTA_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	var file:=output.path_join("%s_%s.png"%[tag,step] if not tag.is_empty() else "%s.png"%step)
	check(image.save_png(file)==OK,"native screenshot saved %s"%file.get_file())
	shots+=1
	print("TOWER_QUOTA_SHOT %s"%file)
	check(FileAccess.file_exists(file),"Screenshot file exists %s"%file.get_file())
	var back:=Image.load_from_file(file)
	check(back!=null and not back.is_empty() and back.get_size()==image.get_size() and back.get_size()==root.size,"Screenshot file has the viewport size %s"%file.get_file())

func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func shot(step:String)->Image:
	var image:=await grab()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	save_image(image,step)
	return image

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func layout_name()->String:
	return str((app.modal as Node).get_meta("life_modal_layout","")) if is_instance_valid(app.modal) else ""

func feedback()->String:
	return str(app.modal_feedback.text) if is_instance_valid(app.modal_feedback) else ""

func person()->Dictionary:
	return w.state.players[id]

func k(c:Vector2i)->String:
	return World.key(c)

func tower_obj()->Dictionary:
	return w.state.objects.get(k(TOWER),{})

func today()->int:
	return Industry.tower_day(float(w.state.time))

func stand(at:Vector2,region:String=World.REGIONS.HOME)->void:
	var p:Dictionary=person()
	p.region=region
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

func act(action:String,cell:Vector2i,extra:String="")->void:
	app.session.rates[1].clear()
	app.action_clock=0
	app.session.perform(action,cell,extra)
	await refresh()

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	app.action_clock=0
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func open_here()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	app._interact()
	await settle()
	await refresh()

func close()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func write_unlock()->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3,"gates":[0,0],"completed":true}},"plaque":true}
	w.state[Revisit.STATE_KEY]={"gates":[3,2],"day":0,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}}

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

func sprinkler(kind:String,water:int,enabled:bool)->Dictionary:
	return {"type":kind,"owner":id,"items":{},"water":water,"enabled":enabled,"next_water":0.0,"last_water":-1.0}

func all_cells()->Array:
	var cells:=[TANK,PIPE,S2,TOWER,S1,OTHER_TOWER]
	cells.append_array(EXTRAS)
	return cells

func write_row()->void:
	var o:Dictionary=w.state.objects
	for c:Vector2i in all_cells():clear_tile(c)
	for x in range(40,49):clear_tile(Vector2i(x,ROW+1))
	o[k(TANK)]={"type":"water_tank","owner":id,"items":{},"water":0}
	o[k(PIPE)]={"type":"water_pipe","owner":id,"items":{}}
	o[k(S2)]=sprinkler("sprinkler",0,false)
	o[k(TOWER)]={"type":"water_tower","owner":id,"items":{},"water":48,"enabled":true}
	o[k(S1)]=sprinkler("sprinkler",9,true)

func write_extras()->void:
	for i in EXTRAS.size():
		var kind:String="medium_sprinkler" if i%2==0 else "sprinkler"
		w.state.objects[k(EXTRAS[i])]=sprinkler(kind,int(Industry.SPRINKLER_CAPACITIES[kind]),true)  # PRESET

func erase_row()->void:
	for c:Vector2i in all_cells():w.state.objects.erase(k(c))

func keep_clear_of_midnight()->void:
	var t:=float(w.state.time)
	if fmod(t,Industry.TOWER_DAY)>Industry.TOWER_DAY-240.0:
		w.state.time=(floorf(t/Industry.TOWER_DAY)+1.0)*Industry.TOWER_DAY+480.0  # PRESET
		print("NOTE %s world clock moved off midnight: %.1f -> %.1f"%[tag,t,float(w.state.time)])

# ------------------------------------------------------------- pixel helpers --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## The 32×48 sprite box of a cell (one tile plus the 16 px above it).
func tall_box(c:Vector2i)->Rect2i:
	return pixel_box(Rect2(app.view.screen(Vector2(c))+Vector2(0,-16),Vector2(32,48)))

## A GUI global rect in screenshot pixels.
func gui_box(r:Rect2)->Rect2i:
	var xf:Transform2D=root.get_final_transform()
	var a:Vector2=xf*r.position
	var b:Vector2=xf*r.end
	return Rect2i(Vector2i(a.round()),Vector2i((b-a).round()))

func box_difference(a:Image,b:Image,box_a:Rect2i,box_b:Rect2i=Rect2i())->float:
	if box_b.size==Vector2i.ZERO:box_b=box_a
	if a==null or b==null:return 0.0
	box_a=box_a.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	box_b=box_b.intersection(Rect2i(Vector2i.ZERO,b.get_size()))
	var size:=Vector2i(mini(box_a.size.x,box_b.size.x),mini(box_a.size.y,box_b.size.y))
	if size.x<=0 or size.y<=0:return 0.0
	var changed:=0
	for x in size.x:
		for y in size.y:
			var p:=a.get_pixel(box_a.position.x+x,box_a.position.y+y);var q:=b.get_pixel(box_b.position.x+x,box_b.position.y+y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(size.x*size.y)

## Share of pixels in `box` within 0.09 of any colour in `palette`.
func share(image:Image,box:Rect2i,palette:Array)->float:
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	var hits:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var c:=image.get_pixel(x,y)
			for p:Color in palette:
				if absf(c.r-p.r)+absf(c.g-p.g)+absf(c.b-p.b)<0.09:
					hits+=1
					break
	return float(hits)/float(box.size.x*box.size.y)

func tower_palette()->Array:
	return [Art.STONE,Art.STONE_LIGHT,Art.STONE_DARK,Art.ROOF,Art.ROOF_LIGHT,Art.ROOF_DARK,Art.STAVE,Art.STAVE_LIGHT,Art.STAVE_DARK,Art.DECK,Art.DECK_LIGHT,Art.COPPER,Art.COPPER_DARK,Art.GLASS,Art.WATER]

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

func page_fits(label:String)->void:
	check(is_instance_valid(app.modal),"Page open (%s)"%label)
	if not is_instance_valid(app.modal):return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Page fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		print("NOTE %s outer scroll max %.1f page %.1f, modal %s"%[label,outer.get_v_scroll_bar().max_value,outer.get_v_scroll_bar().page,str(modal.get_global_rect())])
		check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Outer page needs no scrolling (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the page: 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"Button whole inside the page: 「%s」 (%s)"%[b.text,label])

# ------------------------------------------------------------ settings rows --

## Texts, enabled states and geometry of the two settings rows.
func settings_check(step:String,reserve:int,quota:int,used:int,enabled:bool,owner:bool)->void:
	var label:="%s %s"%[step,tag]
	check(label_text("TowerReserve")==TowerUI.reserve_text(reserve),"Reserve text (%s): %s"%[label,label_text("TowerReserve")])
	check(label_text("TowerQuota")==TowerUI.quota_text(quota,used),"Quota text (%s): %s"%[label,label_text("TowerQuota")])
	check(label_text("TowerSupplyTitle")==str(TowerUI.SUPPLY_TITLE[enabled]),"Supply title (%s): %s"%[label,label_text("TowerSupplyTitle")])
	if not is_instance_valid(app.modal):return
	var modal_rect:=(app.modal as Control).get_global_rect()
	for row:Array in [["TowerReserve","TowerRefillCard",Industry.TOWER_RESERVES,reserve,TowerUI.RESERVE_HELP,"TowerTanks"],
			["TowerQuota","TowerSupplyCard",Industry.TOWER_QUOTAS,quota,TowerUI.QUOTA_HELP,"TowerSupplyTitle"]]:
		var row_id:String=row[0]
		var options:Array=row[2]
		var index:int=options.find(int(row[3]))
		var card:=control(str(row[1]))
		var line:=control(row_id+"Row")
		var lbl:=control(row_id) as Label
		var less:=control(row_id+"Less") as Button
		var more:=control(row_id+"More") as Button
		var above:=control(str(row[5]))
		check(card!=null and line!=null and lbl!=null and less!=null and more!=null and above!=null,"%s row nodes exist (%s)"%[row_id,label])
		if card==null or line==null or lbl==null or less==null or more==null or above==null:continue
		check(line.is_visible_in_tree() and lbl.is_visible_in_tree() and less.is_visible_in_tree() and more.is_visible_in_tree(),"%s row shown (%s)"%[row_id,label])
		check(less.text=="－" and more.text=="＋","%s buttons read －／＋ (%s)"%[row_id,label])
		check(less.disabled==(not owner or index<=0),"%s － %s (%s)"%[row_id,"disabled" if (not owner or index<=0) else "enabled",label])
		check(more.disabled==(not owner or index>=options.size()-1),"%s ＋ %s (%s)"%[row_id,"disabled" if (not owner or index>=options.size()-1) else "enabled",label])
		check(less.tooltip_text==(str(row[4]) if owner else TowerUI.NOT_OWNER) and more.tooltip_text==less.tooltip_text,"%s button tooltips (%s)"%[row_id,label])
		check(lbl.tooltip_text==str(row[4]),"%s label tooltip (%s)"%[row_id,label])
		var lr:=lbl.get_global_rect()
		var cr:=card.get_global_rect()
		var a:=less.get_global_rect()
		var b:=more.get_global_rect()
		for pair:Array in [[a,"－"],[b,"＋"]]:
			var r:Rect2=pair[0]
			check(modal_rect.grow(0.5).encloses(r),"%s %s inside the modal (%s) %s"%[row_id,pair[1],label,str(r)])
			check(cr.grow(0.5).encloses(r),"%s %s inside its card (%s) %s vs %s"%[row_id,pair[1],label,str(r),str(cr)])
			check(not r.intersects(lr),"%s %s clear of the label (%s)"%[row_id,pair[1],label])
			check(r.size.x>=39.5 and r.size.y>=29.5,"%s %s keeps its 40×30 size (%s) %s"%[row_id,pair[1],label,str(r.size)])
		check(not a.intersects(b) and a.position.x<b.position.x,"%s － left of ＋, not overlapping (%s)"%[row_id,label])
		check(cr.grow(0.5).encloses(lr) and modal_rect.grow(0.5).encloses(lr),"%s label inside its card (%s)"%[row_id,label])
		check(lbl.get_line_count()==1 and lbl.get_visible_line_count()>=lbl.get_line_count(),"%s label on one unclipped line (%s): %d lines"%[row_id,label,lbl.get_line_count()])
		check(line.get_global_rect().position.y>=above.get_global_rect().end.y-0.5,"%s row below %s (%s)"%[row_id,str(row[5]),label])
		# The other row's buttons never overlap this row's.
	var rl:=control("TowerReserveLess");var rm:=control("TowerReserveMore");var ql:=control("TowerQuotaLess");var qm:=control("TowerQuotaMore")
	if rl!=null and rm!=null and ql!=null and qm!=null:
		for x:Control in [rl,rm]:
			for y:Control in [ql,qm]:check(not x.get_global_rect().intersects(y.get_global_rect()),"%s clear of %s (%s)"%[x.name,y.name,label])

func record(step:String)->void:
	var r:={}
	for part:String in ROW_PARTS:
		var c:=control(part)
		if c!=null:r[part]=c.get_global_rect()
	rects[step]=r

func row_difference(a:String,b:String,part:String)->float:
	var ra:Dictionary=rects.get(a,{})
	var rb:Dictionary=rects.get(b,{})
	if not ra.has(part) or not rb.has(part) or not images.has(a) or not images.has(b):return -1.0
	var box_a:=gui_box(ra[part])
	var box_b:=gui_box(rb[part])
	var d:=box_difference(images[a],images[b],box_a,box_b)
	print("NOTE %s %s: %s vs %s differs %.1f%%"%[tag,part,a,b,d*100.0])
	return d

func page_state(step:String,reserve:int,quota:int,used:int,enabled:bool,owner:bool)->void:
	check(layout_name()==TowerUI.LAYOUT,"Tower page open for %s (%s)"%[step,tag])
	var image:Image=await shot(step)
	images[step]=image
	page_fits("%s %s"%[step,tag])
	settings_check(step,reserve,quota,used,enabled,owner)
	record(step)

# ------------------------------------------------------------------ flows --

func tick_until_used(expected:int)->int:
	var n:=0
	while n<3:
		n+=1
		check(w.step(Industry.INTERVAL,true),"World.step tick %d succeeds (%s)"%[n,tag])
		if int(tower_obj().get("quota_used",0))>=expected:break
	await refresh()
	return n

func reset()->void:
	await close()
	write_unlock()
	erase_row()
	keep_clear_of_midnight()
	app.view.reduced_motion=false
	await refresh()

func owner_flow()->void:
	write_row()
	await refresh()
	await stand(TOWER_SPOT)
	check(str(app.view.interaction_focus())==k(TOWER),"Tower focused (%s): %s"%[tag,str(app.view.interaction_focus())])
	await open_here()
	var t:=tower_obj()
	check(not t.has("reserve") and not t.has("quota") and not t.has("quota_day") and not t.has("quota_used"),"Fresh tower has no settings fields (%s)"%tag)
	check(label_text("TowerReserve")=="桶水保留：不保留" and label_text("TowerQuota")=="每日配水：不限","Fresh rows read 不保留／不限 (%s)"%tag)
	check(label_text("TowerRefill")==TowerUI.REFILL.full and label_text("TowerTanks")=="接通 1 個儲水桶","Refill card (%s): %s / %s"%[tag,label_text("TowerRefill"),label_text("TowerTanks")])
	await page_state("page_default",0,0,0,true,true)
	# 2. 桶水保留 24 by pressing the real ＋ twice.
	await press("TowerReserveMore")
	check(int(tower_obj().get("reserve",0))==12 and label_text("TowerReserve")==TowerUI.reserve_text(12),"First ＋ -> 12 (%s): %s"%[tag,label_text("TowerReserve")])
	check(feedback().contains("儲水桶留 12 份"),"Server reply shown (%s): %s"%[tag,feedback()])
	await press("TowerReserveMore")
	check(int(tower_obj().get("reserve",0))==24 and label_text("TowerReserve")=="桶水保留：儲水桶留 24 份","Second ＋ -> 24 (%s)"%tag)
	check(feedback().contains("儲水桶留 24 份"),"Server reply 24 shown (%s): %s"%[tag,feedback()])
	check(not tower_obj().has("quota"),"Reserve presses leave the quota alone (%s)"%tag)
	await page_state("page_reserve_24",24,0,0,true,true)
	var reserve_changed:=row_difference("page_default","page_reserve_24","TowerReserve")
	check(reserve_changed>=0.01,"Reserve row pixels changed 不保留 -> 24 (%s): %.1f%%"%[tag,reserve_changed*100.0])
	var quota_same:=row_difference("page_default","page_reserve_24","TowerQuota")
	check(quota_same>=0.0 and quota_same<=0.02,"Quota row pixels unchanged by the reserve presses (%s): %.1f%%"%[tag,quota_same*100.0])
	var plus_same:=row_difference("page_default","page_reserve_24","TowerQuotaMore")
	check(plus_same>=0.0 and plus_same<=0.05,"Enabled, unfocused quota ＋ looks the same in both shots (%s): %.1f%%"%[tag,plus_same*100.0])
	# 3. 每日配水 8 (two real ＋ presses), then real World.step ticks send 3 to S1.
	var day:=today()
	await press("TowerQuotaMore")
	t=tower_obj()
	check(int(t.get("quota",0))==4 and int(t.get("quota_day",-1))==day and int(t.get("quota_used",-1))==0,"First quota ＋ -> 4, today, 0 used (%s): %s"%[tag,str(t)])
	await press("TowerQuotaMore")
	t=tower_obj()
	check(int(t.get("quota",0))==8 and int(t.get("quota_used",-1))==0 and label_text("TowerQuota")==TowerUI.quota_text(8,0),"Second quota ＋ -> 8 (%s): %s"%[tag,label_text("TowerQuota")])
	check(feedback().contains("每日配水 8 份"),"Server reply 每日配水 8 份 (%s): %s"%[tag,feedback()])
	var ticks:int=await tick_until_used(3)
	print("NOTE %s partial quota after %d tick(s)"%[tag,ticks])
	t=tower_obj()
	check(today()==day,"Ticks stayed on world day %d (%s)"%[day,tag])
	check(int(t.get("quota_used",-1))==3 and int(t.get("quota_day",-1))==day,"World.step recorded 3 sent today (%s): %s"%[tag,str(t)])
	check(int(t.get("water",0))==45 and int(w.state.objects[k(S1)].water)==12,"Tower 48 -> 45, S1 9 -> 12 (%s)"%tag)
	check(int(w.state.objects[k(S2)].water)==0,"Disabled S2 got nothing (%s)"%tag)
	check(label_text("TowerWater")=="存水 45／96","Page water follows the tick (%s): %s"%[tag,label_text("TowerWater")])
	await page_state("page_quota_8_partial",24,8,3,true,true)
	check(label_text("TowerQuota")=="每日配水：8 份・今天已送 3","Partial quota wording (%s)"%tag)
	# 4. Enable S2 (real toggle_sprinkler); the next tick sends the remaining 5.
	await act("toggle_sprinkler",S2)
	if w.state.objects[k(S2)].enabled!=true:
		check(false,"toggle_sprinkler enabled S2 (%s)"%tag)
		w.state.objects[k(S2)].enabled=true  # PRESET fallback, only if the real action was refused
		await refresh()
	else:check(true,"toggle_sprinkler enabled S2 (%s)"%tag)
	ticks=await tick_until_used(8)
	print("NOTE %s quota used up after %d tick(s)"%[tag,ticks])
	t=tower_obj()
	check(int(t.get("quota_used",-1))==8 and int(t.get("water",0))==40 and int(w.state.objects[k(S2)].water)==5,"Remaining 5 sent, quota 8/8 (%s): %s"%[tag,str(t)])
	check(w.step(Industry.INTERVAL,true),"Extra World.step tick succeeds (%s)"%tag)
	t=tower_obj()
	check(int(t.get("quota_used",-1))==8 and int(t.get("water",0))==40 and int(w.state.objects[k(S2)].water)==5,"Used-up quota sends nothing more (%s): %s"%[tag,str(t)])
	await refresh()
	await page_state("page_quota_done",24,8,8,true,true)
	check(label_text("TowerQuota").ends_with("（今天送完了）"),"Done wording (%s): %s"%[tag,label_text("TowerQuota")])
	var quota_changed:=row_difference("page_quota_8_partial","page_quota_done","TowerQuota")
	check(quota_changed>=0.01,"Quota row pixels changed partial -> done (%s): %.1f%%"%[tag,quota_changed*100.0])
	var reserve_same:=row_difference("page_quota_8_partial","page_quota_done","TowerReserve")
	check(reserve_same>=0.0 and reserve_same<=0.02,"Reserve label unchanged partial -> done (%s): %.1f%%"%[tag,reserve_same*100.0])
	# 5. 只蓄水 with the real toggle.
	await press("TowerToggle")
	t=tower_obj()
	check(t.get("enabled",true)==false and label_text("TowerMode")=="目前：只蓄水","Toggled to 只蓄水 (%s)"%tag)
	check(int(t.get("quota",0))==8 and int(t.get("quota_used",-1))==8 and int(t.get("reserve",0))==24,"Toggle keeps the settings (%s)"%tag)
	await page_state("page_store_only",24,8,8,false,true)
	check(label_text("TowerSupplyTitle")=="改為出水後會送到","Store-only supply title (%s)"%tag)
	var title_changed:=row_difference("page_quota_done","page_store_only","TowerSupplyTitle")
	check(title_changed>=0.01,"Supply title pixels changed (%s): %.1f%%"%[tag,title_changed*100.0])
	# 6. Worst case: 只蓄水 + reserve 48 + quota 24 + 6 consumers.
	write_extras()
	await refresh()
	for i in 2:await press("TowerReserveMore")
	check(int(tower_obj().get("reserve",0))==48,"Reserve stepped to 48 (%s)"%tag)
	for i in 2:await press("TowerQuotaMore")
	t=tower_obj()
	check(int(t.get("quota",0))==24 and int(t.get("quota_used",-1))==8 and int(t.get("quota_day",-1))==day,"Quota stepped to 24, today's 8 kept (%s): %s"%[tag,str(t)])
	var consumers:=0
	while control("TowerConsumer_%d"%consumers)!=null:consumers+=1
	check(consumers==2+EXTRAS.size(),"Worst case lists %d consumers (%s): %d"%[2+EXTRAS.size(),tag,consumers])
	check(control("TowerConsumerEmpty")==null,"No empty-list line (%s)"%tag)
	await page_state("page_worst_case",48,24,8,false,true)
	check(label_text("TowerReserve")=="桶水保留：儲水桶留 48 份" and label_text("TowerQuota")=="每日配水：24 份・今天已送 8","Worst-case wording (%s)"%tag)
	for part:String in ["TowerReserveMore","TowerQuotaMore"]:
		var d:=row_difference("page_default","page_worst_case",part)
		check(d>=0.02,"%s enabled (at 0) vs disabled (at the top) look different (%s): %.1f%%"%[part,tag,d*100.0])
	var reserve_48:=row_difference("page_reserve_24","page_worst_case","TowerReserve")
	check(reserve_48>=0.005,"Reserve row pixels changed 24 -> 48 (%s): %.1f%%"%[tag,reserve_48*100.0])
	await close()

func visitor_flow()->void:
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居阿岸")  # PRESET
	clear_tile(OTHER_TOWER)
	w.state.objects[k(OTHER_TOWER)]={"type":"water_tower","owner":OTHER,"items":{},"water":30,"enabled":false,"reserve":24,"quota":8,"quota_day":today(),"quota_used":2}  # PRESET
	await refresh()
	await stand(OTHER_SPOT)
	check(str(app.view.interaction_focus())==k(OTHER_TOWER),"Neighbour's tower focused (%s): %s"%[tag,str(app.view.interaction_focus())])
	await open_here()
	check((control("TowerToggle") as Button)!=null and (control("TowerToggle") as Button).disabled,"Visitor toggle disabled (%s)"%tag)
	await page_state("page_visitor",24,8,2,false,false)
	for part:String in ["TowerReserveLess","TowerReserveMore","TowerQuotaLess","TowerQuotaMore"]:
		var b:=control(part) as Button
		check(b!=null and b.disabled and b.is_visible_in_tree(),"Visitor %s shown but disabled (%s)"%[part,tag])
	var d:=row_difference("page_default","page_visitor","TowerReserveMore")
	check(d>=0.02,"Owner ＋ (enabled) vs visitor ＋ (disabled) look different (%s): %.1f%%"%[tag,d*100.0])
	# A visitor's tower_set is refused and changes nothing.
	var before:=JSON.stringify(w.state.objects[k(OTHER_TOWER)],"",true)
	var objects_before:=JSON.stringify(w.state.objects,"",true)
	await act(Industry.TOWER_SET_ACTION,OTHER_TOWER,"reserve:12")
	check(JSON.stringify(w.state.objects[k(OTHER_TOWER)],"",true)==before,"Visitor tower_set leaves the tower unchanged (%s)"%tag)
	check(JSON.stringify(w.state.objects,"",true)==objects_before,"Visitor tower_set leaves every object unchanged (%s)"%tag)
	check(label_text("TowerReserve")==TowerUI.reserve_text(24) and label_text("TowerQuota")==TowerUI.quota_text(8,2),"Visitor rows unchanged after the refusal (%s)"%tag)
	await close()

func world_flow()->void:
	await stand(VIEW_SPOT)
	check(not is_instance_valid(app.modal),"Page closed (%s)"%tag)
	check(str(app.view.interaction_focus()).is_empty(),"Nothing focused from the viewing spot (%s): %s"%[tag,str(app.view.interaction_focus())])
	var t:=tower_obj()
	check(int(t.get("reserve",0))==48 and int(t.get("quota",0))==24 and t.get("enabled",true)==false,"Settings kept after closing (%s)"%tag)
	var after:Image=await shot("world_after")
	images["world_after"]=after
	if after==null or after.is_empty():return
	var box:=Rect2(tall_box(TOWER))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(box),"Tower on screen (%s)"%tag)
	for panel:Dictionary in hud_panels():check(not box.intersects(panel.rect),"Tower clear of HUD %s (%s)"%[panel.name,tag])
	var own:=share(after,tall_box(TOWER),tower_palette())
	print("NOTE %s tower palette share %.0f%%"%[tag,own*100.0])
	check(own>=0.35,"Tower still drawn in its own palette (%s): %.0f%%"%[tag,own*100.0])
	for c:Vector2i in [S1,S2]:check(box_difference(after,after,tall_box(TOWER),tall_box(c))>=0.35,"Tower differs from the sprinkler at %s (%s)"%[k(c),tag])
	# Same tower without the settings fields (unsaved comparison frame): identical art.
	var saved:=t.duplicate(true)
	for field in ["reserve","quota","quota_day","quota_used"]:t.erase(field)  # PRESET
	await refresh()
	var plain:Image=await grab()
	var d:=box_difference(after,plain,tall_box(TOWER))
	print("NOTE %s tower box with vs without settings differs %.2f%%"%[tag,d*100.0])
	check(d<=0.01,"Settings do not change the tower art (%s): %.2f%%"%[tag,d*100.0])
	w.state.objects[k(TOWER)]=saved  # PRESET (restore)
	await refresh()

func size_flow()->void:
	images={}
	rects={}
	await reset()
	await owner_flow()
	await visitor_flow()
	await world_flow()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/水塔定量配水預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("water-tower-quota-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"水塔旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	WanganUI.dismiss(app)
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
		if failures>60:break
	check(shots==SHOT_STEPS.size()*2,"%d screenshots per size (%d)"%[SHOT_STEPS.size(),shots])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
