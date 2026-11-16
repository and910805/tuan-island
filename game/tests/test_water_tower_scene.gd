extends SceneTree
## 第 40 章家園「水塔」native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/水塔預覽 (or --capture-dir=), named <w>x<h>_<step>.png; icons.png once.
## Same harness as test_lanyang_revisit_scene.gd. Art is runtime-painted
## (water_tower_art.gd), no new PNGs.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * unlock fixture written directly (canal repaired, my first memory completed, the
##    bridge plaque set, state.lanyang_revisit completed);
##  * the local player is teleported by writing region/x/y;
##  * home: one row written as objects (state.removed on tiles with a base resource):
##      y=37:  TANK(40) GATE(41) PUMP(42) SPRINKLER(43) T_EMPTY(44) T_PART(45) T_FULL(46) T_STORE(47) PIPE(48)
##    tower water 0 / 48 / 96 / 96, the last one 只蓄水 (enabled=false); tank water 20;
##    and a neighbour's tower (46,28) (water 30, 只蓄水); state.removed also on the row in
##    front (y=38) so no tree hides a tower; the gate's mode is written directly (low,
##    then back to open) for the tower_page_low shot; bag kits written. No World.step
##    runs (the session's physics step is off), so the written water levels stay put.
## REALLY EXERCISED: app._interact() opens the tower / gate pages; tower_toggle, gate_mode
##  and remove are real Session.perform calls -> World -> snapshot -> page and world
##  updates; the backpack and the build folio are the real panels.
## SHOTS per size: home_towers (+ crop), home_towers_plain (non-preview draw path, + crop),
##  tower_page_full, tower_page_store, tower_page_low, tower_page_visitor,
##  tower_page_removed, gate_page_towers, inventory_tower, workshop_tower; icons.png once.
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Industry=preload("res://scripts/industry.gd")
const TowerUI=preload("res://scripts/water_tower_ui.gd")
const GateUI=preload("res://scripts/diversion_gate_ui.gd")
const Art=preload("res://scripts/water_tower_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const OTHER:="tower-scene-neighbour-93bd"
const ROW:=37
const TANK:=Vector2i(40,ROW)
const GATE:=Vector2i(41,ROW)
const PUMP:=Vector2i(42,ROW)
const SPRINKLER:=Vector2i(43,ROW)
const T_EMPTY:=Vector2i(44,ROW)
const T_PART:=Vector2i(45,ROW)
const T_FULL:=Vector2i(46,ROW)
const T_STORE:=Vector2i(47,ROW)
const PIPE:=Vector2i(48,ROW)
const OTHER_TOWER:=Vector2i(46,28)
## South of the row, more than 3.2 tiles from every object (nothing focused).
const VIEW_SPOT:=Vector2(43.9,40.8)
const PART_SPOT:=Vector2(45.5,38.6)
const EMPTY_SPOT:=Vector2(44.5,38.6)
const GATE_SPOT:=Vector2(41.5,38.4)
const OTHER_SPOT:=Vector2(46.5,29.4)
## Tower-local rectangles (32×48 sprite drawn at the cell's top-left minus 16 px).
const WINDOW:=Rect2(11,13-16,10,7)
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

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("WATER_TOWER_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("TOWER_SHOT %s"%file)

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

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func k(c:Vector2i)->String:
	return World.key(c)

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

func tower(water:int,enabled:bool,owner:String="")->Dictionary:
	return {"type":"water_tower","owner":id if owner.is_empty() else owner,"items":{},"water":water,"enabled":enabled}

func write_row()->void:
	var o:Dictionary=w.state.objects
	for c:Vector2i in [TANK,GATE,PUMP,SPRINKLER,T_EMPTY,T_PART,T_FULL,T_STORE,PIPE,OTHER_TOWER]:clear_tile(c)
	# The row in front stays clear too (a tree at 47,38 would hide the 只蓄水 tower's legs).
	for x in range(40,49):clear_tile(Vector2i(x,ROW+1))
	o[k(TANK)]={"type":"water_tank","owner":id,"items":{},"water":20}
	o[k(GATE)]={"type":"diversion_gate","owner":id,"items":{},"mode":"open"}
	o[k(PUMP)]={"type":"water_pump","owner":id,"items":{},"enabled":false}
	o[k(SPRINKLER)]={"type":"sprinkler","owner":id,"items":{},"water":6,"enabled":true,"next_water":0.0,"last_water":-1.0}
	o[k(T_EMPTY)]=tower(0,true)
	o[k(T_PART)]=tower(48,true)
	o[k(T_FULL)]=tower(96,true)
	o[k(T_STORE)]=tower(96,false)
	o[k(PIPE)]={"type":"water_pipe","owner":id,"items":{}}
	o[k(OTHER_TOWER)]=tower(30,false,OTHER)

func erase_row()->void:
	for c:Vector2i in [TANK,GATE,PUMP,SPRINKLER,T_EMPTY,T_PART,T_FULL,T_STORE,PIPE,OTHER_TOWER]:w.state.objects.erase(k(c))

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

## The 32×48 sprite box of a cell (one tile plus the 16 px above it).
func tall_box(c:Vector2i)->Rect2i:
	return pixel_box(Rect2(app.view.screen(Vector2(c))+Vector2(0,-16),Vector2(32,48)))

func local_box(c:Vector2i,local:Rect2)->Rect2i:
	return pixel_box(Rect2(app.view.screen(Vector2(c))+local.position,local.size))

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

func save_crop(image:Image,center:Vector2i,step:String)->void:
	var box:=pixel_box(Rect2(app.view.screen(Vector2(center))+Vector2(-144,-56),Vector2(320,112))).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return
	var crop:=image.get_region(box)
	crop.resize(box.size.x*2,box.size.y*2,Image.INTERPOLATE_NEAREST)
	save_image(crop,step)

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
	if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Outer page needs no scrolling (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the page: 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"Button whole inside the page: 「%s」 (%s)"%[b.text,label])

# ------------------------------------------------------------------ flows --

func reset()->void:
	await close()
	write_unlock()
	erase_row()
	bag()[Industry.TOWER_KIT]=0  # PRESET
	app.view.reduced_motion=false
	await refresh()

func world_flow()->void:
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居阿岸")  # PRESET
	write_row()
	await stand(VIEW_SPOT)
	check(str(app.view.interaction_focus()).is_empty(),"Nothing focused from the viewing spot (%s): %s"%[tag,str(app.view.interaction_focus())])
	var row:Image=await shot("home_towers")
	save_crop(row,T_EMPTY,"home_towers_crop")
	for c:Vector2i in [T_EMPTY,T_PART,T_FULL,T_STORE,TANK]:
		var px:=Rect2(tall_box(c))
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"%s on screen (%s)"%[k(c),tag])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"%s clear of HUD %s (%s) %s vs %s"%[k(c),panel.name,tag,str(px),str(panel.rect)])
	for c:Vector2i in [T_EMPTY,T_PART,T_FULL,T_STORE]:
		var own:=share(row,tall_box(c),tower_palette())
		print("NOTE %s tower %s palette share %.0f%%"%[tag,k(c),own*100.0])
		check(own>=0.35,"Tower %s drawn in its own palette (%s): %.0f%%"%[k(c),tag,own*100.0])
	# Tower vs the other water-network pieces (32×48 boxes, same image).
	for other:Array in [[TANK,"water_tank"],[GATE,"diversion_gate"],[PUMP,"water_pump"],[SPRINKLER,"sprinkler"]]:
		for c:Vector2i in [T_PART,T_FULL]:
			var d:=box_difference(row,row,tall_box(c),tall_box(other[0]))
			print("NOTE %s tower %s vs %s: %.0f%% of the 32x48 box differs"%[tag,k(c),other[1],d*100.0])
			check(d>=0.35,"Tower %s clearly differs from %s (%s): %.0f%%"%[k(c),other[1],tag,d*100.0])
		var theirs:=share(row,tall_box(other[0]),tower_palette())
		print("NOTE %s %s tower-palette share %.0f%%"%[tag,other[1],theirs*100.0])
	# Water level: the level window, empty / partly / full.
	var water_shares:=[]
	for c:Vector2i in [T_EMPTY,T_PART,T_FULL]:water_shares.append(share(row,local_box(c,WINDOW),[Art.WATER,Art.WATER_LIGHT]))
	print("NOTE %s window water share empty %.0f%% partly %.0f%% full %.0f%%"%[tag,water_shares[0]*100,water_shares[1]*100,water_shares[2]*100])
	check(water_shares[0]<=0.05 and water_shares[1]>=0.3 and water_shares[1]<=0.8 and water_shares[2]>=0.9,"Window water empty < partly < full (%s)"%tag)
	var ep:=box_difference(row,row,local_box(T_EMPTY,WINDOW),local_box(T_PART,WINDOW))
	var pf:=box_difference(row,row,local_box(T_PART,WINDOW),local_box(T_FULL,WINDOW))
	var ef:=box_difference(row,row,local_box(T_EMPTY,WINDOW),local_box(T_FULL,WINDOW))
	print("NOTE %s window differs: empty/partly %.0f%% partly/full %.0f%% empty/full %.0f%%"%[tag,ep*100,pf*100,ef*100])
	check(ep>=0.25 and pf>=0.25 and ef>=0.8,"Three water levels look different (%s)"%tag)
	# 出水 vs 只蓄水 (both full).
	var mode_diff:=box_difference(row,row,tall_box(T_FULL),tall_box(T_STORE))
	var green_on:=share(row,tall_box(T_FULL),[Art.ON]);var green_off:=share(row,tall_box(T_STORE),[Art.ON])
	var red_on:=share(row,tall_box(T_FULL),[Art.OFF]);var red_off:=share(row,tall_box(T_STORE),[Art.OFF])
	print("NOTE %s 出水/只蓄水 box differs %.1f%%; green %.1f%%/%.1f%%, red %.1f%%/%.1f%%"%[tag,mode_diff*100,green_on*100,green_off*100,red_on*100,red_off*100])
	check(mode_diff>=0.04 and green_on-green_off>=0.008 and red_off-red_on>=0.012,"出水 and 只蓄水 look different (%s)"%tag)
	# Static frame to frame, with motion on and with reduced motion.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var later:=root.get_texture().get_image()
	check(box_difference(row,later,tall_box(T_PART))<=0.01 and box_difference(row,later,tall_box(T_STORE))<=0.01,"Tower static with motion on (%s)"%tag)
	app.view.reduced_motion=true
	var still:Image=await grab()
	check(box_difference(row,still,tall_box(T_PART))<=0.01 and box_difference(row,still,tall_box(T_STORE))<=0.01,"Tower identical with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# Non-preview draw path (no village art): the towers are still drawn.
	var art=app.view.village_art
	app.view.village_art=null
	app.view.queue_redraw()
	var plain:Image=await shot("home_towers_plain")
	save_crop(plain,T_EMPTY,"home_towers_plain_crop")
	app.view.village_art=art
	app.view.queue_redraw()
	for c:Vector2i in [T_EMPTY,T_FULL,T_STORE]:check(share(plain,tall_box(c),tower_palette())>=0.35,"Tower %s drawn on the plain path too (%s)"%[k(c),tag])
	check(box_difference(plain,plain,local_box(T_EMPTY,WINDOW),local_box(T_FULL,WINDOW))>=0.8,"Water level visible on the plain path (%s)"%tag)

func page_flow()->void:
	# Owner page at the partly filled tower: open gate -> full zone, one sprinkler.
	await stand(PART_SPOT)
	check(str(app.view.interaction_focus())==k(T_PART),"Partly filled tower focused (%s): %s"%[tag,str(app.view.interaction_focus())])
	await open_here()
	check(layout_name()==TowerUI.LAYOUT and label_text("TowerWater")=="存水 48／96" and label_text("TowerRefill")==TowerUI.REFILL.full,"Tower page, full zone (%s): %s"%[tag,label_text("TowerRefill")])
	await shot("tower_page_full")
	page_fits("full "+tag)
	await press("TowerToggle")
	check(w.state.objects[k(T_PART)].enabled==false and label_text("TowerMode")=="目前：只蓄水","Toggled to 只蓄水 (%s)"%tag)
	await shot("tower_page_store")
	page_fits("store "+tag)
	await press("TowerToggle")
	# The gate is out of reach from here: its mode is written directly for this shot.
	w.state.objects[k(GATE)].mode="low"  # PRESET
	await refresh()
	check(label_text("TowerRefill")==TowerUI.REFILL.low,"Low zone wording (%s): %s"%[tag,label_text("TowerRefill")])
	await shot("tower_page_low")
	page_fits("low "+tag)
	w.state.objects[k(GATE)].mode="open"  # PRESET
	await refresh()
	await close()
	# Gate page lists all four towers.
	await stand(GATE_SPOT)
	await open_here()
	check(layout_name()==GateUI.LAYOUT and label_text("GateTower_3")=="水塔（47,37）・優先補水","Gate page tower rows (%s): %s"%[tag,label_text("GateTower_3")])
	await shot("gate_page_towers")
	page_fits("gate towers "+tag)
	await close()
	# Visitor page.
	await stand(OTHER_SPOT)
	await open_here()
	check(layout_name()==TowerUI.LAYOUT and (control("TowerToggle") as Button).disabled,"Visitor page read-only (%s)"%tag)
	await shot("tower_page_visitor")
	page_fits("visitor "+tag)
	await close()
	# Removed while open.
	await stand(EMPTY_SPOT)
	await open_here()
	check(layout_name()==TowerUI.LAYOUT and label_text("TowerWater")=="存水 0／96","Empty tower page (%s)"%tag)
	await act("remove",T_EMPTY)
	check(not w.state.objects.has(k(T_EMPTY)) and label_text("TowerWater")==TowerUI.GONE,"Removed state (%s)"%tag)
	await shot("tower_page_removed")
	page_fits("removed "+tag)
	await close()

func panels_flow()->void:
	bag()[Industry.TOWER_KIT]=2  # PRESET
	await refresh()
	app._inventory()
	await settle()
	if app.modal is InventoryPanel:
		app.modal.select_item(Industry.TOWER_KIT)
		var slot=app.modal.slots.get(Industry.TOWER_KIT)
		if slot!=null:(slot as Control).grab_focus()
		await settle()
		check(str(app.modal.selected_id)==Industry.TOWER_KIT,"water_tower_kit selected (%s)"%tag)
		await shot("inventory_tower")
	else:check(false,"Backpack opens (%s)"%tag)
	await close()
	app._build_menu()
	await settle()
	var tab:=control("BuildTab3") as Button
	if tab!=null:tab.pressed.emit()
	await settle()
	var slot:=control("BuildSlot_water_tower_3") as Button
	check(slot!=null,"Workshop slot water_tower (%s)"%tag)
	if slot!=null:
		var shelf:Node=slot.get_parent()
		while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
		if shelf!=null:(shelf as ScrollContainer).ensure_control_visible(slot)
		slot.pressed.emit()
		await settle()
		slot.grab_focus()
	check(label_text("BuildTitle")=="水塔","Recipe card 水塔 (%s): %s"%[tag,label_text("BuildTitle")])
	await shot("workshop_tower")
	await close()
	app._select_tool("hoe")

func size_flow()->void:
	await reset()
	await world_flow()
	await page_flow()
	await panels_flow()

# ------------------------------------------------------------------ icons --

func image_of(tex:Texture2D)->Image:
	if tex==null:return null
	var image:=tex.get_image()
	if image==null:return null
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

func differ(a:Image,b:Image)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 1.0
	var n:=0
	for x in a.get_width():
		for y in a.get_height():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)+absf(p.a-q.a)>0.3:n+=1
	return float(n)/float(a.get_width()*a.get_height())

func icon_flow()->void:
	var images:={"tower_kit":image_of(Items.icon(Industry.TOWER_KIT)),"tank_kit":image_of(Items.icon("tank_kit")),"gate_kit":image_of(Items.icon(Industry.GATE_KIT)),
		"pump_kit":image_of(Items.icon("pump_kit")),"sprinkler_kit":image_of(Items.icon("sprinkler_kit")),"pipe_kit":image_of(Items.icon("pipe_kit"))}
	for name in images:check(images[name]!=null and (images[name] as Image).get_size()==Vector2i(32,32),"32×32 image: %s"%name)
	for other:String in ["tank_kit","gate_kit","pump_kit","sprinkler_kit","pipe_kit"]:
		var d:=differ(images.tower_kit,images[other])
		print("NOTE icon tower_kit vs %s: %.0f%% pixels differ"%[other,d*100.0])
		check(d>=0.25,"tower_kit icon differs from %s (%.0f%%)"%[other,d*100.0])
	# Sprite states compared directly (texture pixels).
	var states:={}
	for key:Array in [[0,true],[2,true],[4,true],[4,false],[2,false]]:states["%d_%s"%[key[0],str(key[1])]]=image_of(Art.tower_texture(key[0],key[1]))
	for pair:Array in [["0_true","2_true"],["2_true","4_true"],["0_true","4_true"],["4_true","4_false"],["2_true","2_false"]]:
		var d:=differ(states[pair[0]],states[pair[1]])
		print("NOTE sprite %s vs %s: %.1f%% pixels differ"%[pair[0],pair[1],d*100.0])
		check(d>=0.02,"Sprite %s differs from %s (%.1f%%)"%[pair[0],pair[1],d*100.0])
	# 4× strip: sprite states (32×48), then the kit icon and the comparison icons.
	var order:=["0_true","2_true","4_true","4_false","2_false"]
	var icons:=["tower_kit","tank_kit","gate_kit","pump_kit","sprinkler_kit"]
	var strip:=Image.create((order.size()+icons.size())*136+8,200,false,Image.FORMAT_RGBA8)
	strip.fill(Color("f3e6c8"))
	for i in order.size():
		var big:=(states[order[i]] as Image).duplicate() as Image
		big.resize(128,192,Image.INTERPOLATE_NEAREST)
		strip.blend_rect(big,Rect2i(0,0,128,192),Vector2i(8+i*136,4))
	for j in icons.size():
		var img:Image=images[icons[j]]
		if img==null:continue
		var big:=img.duplicate() as Image
		big.resize(128,128,Image.INTERPOLATE_NEAREST)
		strip.blend_rect(big,Rect2i(0,0,128,128),Vector2i(8+(order.size()+j)*136,68))
	tag=""
	save_image(strip,"icons")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/水塔預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("water-tower-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
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
	icon_flow()
	check(shots>=25,"12 screenshots per size plus the icon strip (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
