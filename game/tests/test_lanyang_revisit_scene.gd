extends SceneTree
## 第 40 章「回訪・旱日分流」／分流閘／分水木牌 native render check at 1024×640 and
## 1280×800. Screenshots go to outputs/蘭陽回訪預覽 (or --capture-dir=), named
## <w>x<h>_<step>.png; icons.png once. Same harness as test_table_warmer_scene.gd.
##
## Art is runtime-painted (lanyang_revisit_art.gd), no new PNGs.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * unlock fixture written directly (canal repaired, my first memory completed, the
##    bridge plaque set); not-ready shots write my record back to round 0;
##    state.lanyang_revisit is ERASED before each size; state.time day 1 / day 3;
##  * the local player is teleported by writing region/x/y;
##  * home: a water network (tank, pipes, gates A open / B low / C closed, three
##    sprinklers) and a neighbour's gate written as objects; bag kits written.
## REALLY EXERCISED: app._interact() opens every page; gate / check / claim / gate_mode /
##  build (the plaque) are real Session.perform calls -> World -> snapshot -> page and
##  world updates; the backpack and the build folio are the real panels.
## SHOTS per size: lanyang_gate_prompt, lanyang_field_prompt, lanyang_xinghe_prompt,
##  page_not_ready, page_rainy, page_dry_start, page_gate_set, page_wrong_split,
##  page_one_checked, page_complete, page_claimed, home_gates (+ crop), gate_page_open,
##  gate_page_closed, gate_page_visitor, plaque_world (+ crop), plaque_card,
##  inventory_plaque, inventory_gate, workshop_plaque, workshop_gate,
##  home_gates_plain (non-preview draw path); icons.png once.
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Industry=preload("res://scripts/industry.gd")
const UI=preload("res://scripts/lanyang_revisit_ui.gd")
const GateUI=preload("res://scripts/diversion_gate_ui.gd")
const Art=preload("res://scripts/lanyang_revisit_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Souvenir=preload("res://scripts/souvenir_art.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const IslandMap=preload("res://scripts/island_map.gd")
const OTHER:="revisit-scene-neighbour-41aa"
const DAY:=1440.0
const GATE_SPOT:=Vector2(32.5,25.5)
const MID_SPOT:=Vector2(32.5,29.5)
const TAIL_SPOT:=Vector2(32.5,32.5)
## One row south of the plaza, the three gates side by side (sprinklers join the
## network, so the row continues through S_B):
##   y=42:  G_A  P_A  TANK  P_B  G_B  S_B  G_C
##   y=43:  S_A                           S_C
## Zones from the tank: S_A full (A open), S_B low (B 餘水), S_C cut (C 關閉).
# Keep the fixture south of the restored courtyard and its hedgehog interaction.
const S_A:=Vector2i(41,43)
const G_A:=Vector2i(41,42)
const P_A:=Vector2i(42,42)
const TANK:=Vector2i(43,42)
const P_B:=Vector2i(44,42)
const G_B:=Vector2i(45,42)
const S_B:=Vector2i(46,42)
const G_C:=Vector2i(47,42)
const S_C:=Vector2i(47,43)
const OTHER_GATE:=Vector2i(46,28)
const GATE_A_SPOT:=Vector2(40.3,41.2)
## South of the row: nothing within interaction reach (no focus label over the gates),
## the player and name tag below the network, the row clear of the tracker and badge.
const VIEW_SPOT:=Vector2(44.5,45.6)
const OTHER_SPOT:=Vector2(46.5,29.4)
const PLAQUE_CELL:=Vector2i(43,34)
## West of the plaque on the same row: the player never covers it.
const PLAQUE_SPOT:=Vector2(41.9,34.7)
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
	print("LANYANG_REVISIT_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("REVISIT_SHOT %s"%file)

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

func set_day(day_index:int)->void:
	w.state.time=float(day_index)*DAY+30.0  # PRESET

func open_local_map()->void:
	await close()
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=KEY_M
		event.physical_keycode=KEY_M
		event.pressed=down
		root.push_input(event)
	await settle()
	check(is_instance_valid(app.map_view) and app.map_view.is_visible_in_tree(),"M opens the local map (%s)"%tag)

func write_unlock(ready:bool)->void:
	var life:Dictionary=w.state.lanyang_life
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:life.cleared[k(cell)]=true
	life.donations=World.LANYANG_LIFE.REPAIR_COST.duplicate()
	life.repaired=true
	var seen:=[]
	if ready:
		for cell:Vector2i in World.HISTORY_MEMORY.OBSERVATIONS:seen.append(k(cell))
	w.state.history_memory={"players":{id:{"seen":seen,"round":3 if ready else 0,"gates":[0,0],"completed":ready}},"plaque":true}

func clear_tile(c:Vector2i)->void:
	if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET

func write_network()->void:
	var o:Dictionary=w.state.objects
	for c:Vector2i in [S_A,G_A,P_A,TANK,P_B,G_B,S_B,G_C,S_C,OTHER_GATE]:clear_tile(c)
	for c:Vector2i in [S_A,S_B,S_C]:o[k(c)]={"type":"sprinkler","owner":id,"items":{},"water":6,"enabled":true,"next_water":0.0,"last_water":-1.0}
	for c:Vector2i in [P_A,P_B]:o[k(c)]={"type":"water_pipe","owner":id,"items":{}}
	o[k(TANK)]={"type":"water_tank","owner":id,"items":{},"water":20}
	o[k(G_A)]={"type":"diversion_gate","owner":id,"items":{},"mode":"open"}
	o[k(G_B)]={"type":"diversion_gate","owner":id,"items":{},"mode":"low"}
	o[k(G_C)]={"type":"diversion_gate","owner":id,"items":{},"mode":"closed"}
	o[k(OTHER_GATE)]={"type":"diversion_gate","owner":OTHER,"items":{},"mode":"closed"}

func erase_home()->void:
	for c:Vector2i in [S_A,G_A,P_A,TANK,P_B,G_B,S_B,G_C,S_C,OTHER_GATE,PLAQUE_CELL]:w.state.objects.erase(k(c))

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

func cell_box(c:Vector2i)->Rect2i:
	return pixel_box(Rect2(app.view.screen(Vector2(c)),Vector2(32,32)))

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

## Share of pixels in `box` painted in the gate's own palette.
func gate_share(image:Image,box:Rect2i)->float:
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	var palette:=[Art.POST,Art.POST_LIGHT,Art.BEAM,Art.BOARD,Art.BOARD_LIGHT,Art.BOARD_DARK,Art.BOARD_CLOSED,Art.WATER,Art.WATER_LIGHT,Art.WATER_SOFT,Art.WET,Art.STONE,Art.STONE_LIGHT,Art.FLAG_CLOSED]
	var hits:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var c:=image.get_pixel(x,y)
			for p:Color in palette:
				if absf(c.r-p.r)+absf(c.g-p.g)+absf(c.b-p.b)<0.09:
					hits+=1
					break
	return float(hits)/float(box.size.x*box.size.y)

func save_crop(image:Image,center:Vector2i,step:String)->void:
	var box:=pixel_box(Rect2(app.view.screen(Vector2(center))+Vector2(-112,-48),Vector2(288,128))).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return
	var crop:=image.get_region(box)
	crop.resize(box.size.x*2,box.size.y*2,Image.INTERPOLATE_NEAREST)
	save_image(crop,step)

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

## The focused prompt `id` is placed with `title`, on screen and clear of HUD panels.
func prompt_ok(id_value:String,title:String,label:String)->void:
	var found:={}
	for entry:Dictionary in placements():
		if str(entry.id)==id_value:found=entry
	check(not found.is_empty() and str(found.get("title",""))==title,"Prompt 「%s」 placed (%s): %s"%[title,label,str(found.get("title","none"))])
	if found.is_empty():return
	var px:=view_to_pixels(found.rect)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Prompt on screen (%s) %s"%[label,str(px)])
	for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Prompt clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(px),str(panel.rect)])

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
	w.state.erase(Revisit.STATE_KEY)  # PRESET
	write_unlock(true)
	set_day(0)
	erase_home()
	for item in [Revisit.PLAQUE_ITEM,Industry.GATE_KIT]:bag()[item]=0  # PRESET
	app.view.reduced_motion=false
	await refresh()

func lanyang_flow()->void:
	# Not ready (own first memory unfinished): the catch-up page from the canal notes.
	write_unlock(false)
	await stand(MID_SPOT,"lanyang")
	await open_here()
	check(layout_name()=="lanyang_garden","Canal notes for a not-ready player (%s)"%tag)
	await press("RevisitOpen")
	check(layout_name()==UI.LAYOUT and label_text("RevisitHoldText")==Revisit.NOT_READY,"Catch-up page (%s)"%tag)
	await shot("page_not_ready")
	page_fits("not ready "+tag)
	await close()
	write_unlock(true)
	set_day(0)
	w.state.history_memory.players[id].completed_day=0  # PRESET: the practice ended today.
	await stand(GATE_SPOT,"lanyang")
	await open_local_map()
	var guide:=IslandMap.canal_revisit(app.session.snapshot)
	check("明天起" in guide.note and guide.markers.all(func(entry):return entry.state=="idle"),"The map shows the next-day invitation (%s)"%tag)
	await shot("map_waiting")
	set_day(1)
	await refresh()
	if not is_instance_valid(app.map_view):return
	guide=IslandMap.canal_revisit(app.map_view.data)
	check(guide.markers[0].state=="next" and guide.markers[0].cell==Revisit.GATE_CELL,
		"The open map highlights the fork after the day changes (%s)"%tag)
	await shot("map_find_gate")
	await close()
	w.state.history_memory.players[id].erase("completed_day")
	# Rainy day at the fork.
	set_day(2)
	await stand(GATE_SPOT,"lanyang")
	await open_here()
	check(label_text("RevisitWeather")==Revisit.RAINY,"Rainy page (%s)"%tag)
	await shot("page_rainy")
	page_fits("rainy "+tag)
	await close()
	set_day(0)
	# Dry day: prompts at the fork, the field and 星禾.
	await stand(GATE_SPOT,"lanyang")
	prompt_ok("memory:33,25","調整岔口分流閘","fork "+tag)
	var fork_before:=await shot("lanyang_gate_prompt")
	var upstream_box:=cell_box(Revisit.GATE_CELL)
	await stand(TAIL_SPOT,"lanyang")
	prompt_ok("memory:33,32","巡看田尾的田","tail "+tag)
	await shot("lanyang_field_prompt")
	await stand(MID_SPOT,"lanyang")
	prompt_ok("gardener","星禾・旱日分流","xinghe "+tag)
	await shot("lanyang_xinghe_prompt")
	await open_here()
	check(layout_name()==UI.LAYOUT,"Revisit page at 星禾 (%s)"%tag)
	await shot("page_dry_start")
	page_fits("dry start "+tag)
	# Gate a to 3 at the fork, then a wrong split reply at the middle field.
	await stand(GATE_SPOT,"lanyang")
	await open_here()
	await press("RevisitGate_a_3")
	check(Revisit.gates(w.state)==[3,0],"Gate a 3 (%s)"%tag)
	await shot("page_gate_set")
	page_fits("gate set "+tag)
	await close()
	var fork_after:=await shot("lanyang_gate_raised")
	check(box_difference(fork_before,fork_after,upstream_box)>0.1,"The actual upstream gate changes visibly when raised (%s)"%tag)
	await stand(MID_SPOT,"lanyang")
	await open_here()
	await press("RevisitCheck")
	check(str(app.modal_feedback.text)==Revisit.WRONG_SHARE%["中段的田",0,4],"Wrong split reply shown (%s): %s"%[tag,str(app.modal_feedback.text)])
	await shot("page_wrong_split")
	page_fits("wrong split "+tag)
	# Gate b to 2, check upstream (within reach of the fork).
	await stand(GATE_SPOT,"lanyang")
	await open_here()
	await press("RevisitGate_b_2")
	await press("RevisitCheck")
	check(Revisit.checked_today(w.state)==["upstream"],"Upstream checked (%s)"%tag)
	await shot("page_one_checked")
	page_fits("one checked "+tag)
	await close()
	var fork_balanced:=await shot("lanyang_gate_balanced")
	var middle_box:=cell_box(Revisit.GATE_CELL+Vector2i.RIGHT)
	check(box_difference(fork_after,fork_balanced,middle_box)>0.1,"The middle gate also changes after its own control is used (%s)"%tag)
	await open_local_map()
	guide=IslandMap.canal_revisit(app.session.snapshot)
	check(guide.markers[0].state=="idle" and guide.markers[1].state=="checked"
		and guide.markers[2].state=="next" and guide.markers[3].state=="next" and "1／3" in guide.note,
		"The map leads to the unvisited middle and tail fields (%s)"%tag)
	await shot("map_canals_in_progress")
	await close()
	await stand(MID_SPOT,"lanyang")
	await open_here()
	await press("RevisitCheck")
	await stand(TAIL_SPOT,"lanyang")
	await open_here()
	await press("RevisitCheck")
	check(Revisit.completed(w.state),"Completed (%s)"%tag)
	await shot("page_complete")
	page_fits("complete "+tag)
	await open_local_map()
	guide=IslandMap.canal_revisit(app.session.snapshot)
	check(guide.markers[2].state=="next" and guide.markers[2].cell==Revisit.SERVICE and "領木牌" in guide.markers[2].label,
		"The completed round points to Xinghe at the wooden bridge (%s)"%tag)
	await shot("map_collect_plaque")
	await close()
	await stand(MID_SPOT,"lanyang")
	await open_here()
	await press("RevisitClaim")
	check(int(bag().get(Revisit.PLAQUE_ITEM,0))==1,"Plaque claimed (%s)"%tag)
	await shot("page_claimed")
	page_fits("claimed "+tag)
	await close()

func home_flow()->void:
	if not w.state.players.has(OTHER):w.add_player(OTHER,"鄰居阿岸")  # PRESET
	write_network()
	await stand(VIEW_SPOT)
	var gates:Image=await shot("home_gates")
	save_crop(gates,TANK,"home_gates_crop")
	for c:Vector2i in [G_A,G_B,G_C]:
		var share:=gate_share(gates,cell_box(c))
		print("NOTE %s gate %s palette share %.0f%%"%[tag,k(c),share*100.0])
		check(share>=0.35,"Gate %s drawn in its own palette (%s): %.0f%%"%[k(c),tag,share*100.0])
		var px:=Rect2(cell_box(c))
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(px),"Gate %s on screen (%s)"%[k(c),tag])
		for panel:Dictionary in hud_panels():check(not px.intersects(panel.rect),"Gate %s clear of HUD %s (%s)"%[k(c),panel.name,tag])
	# Same image, three gates side by side (A joins right+down, B and C left+right).
	check(str(app.view.interaction_focus()).is_empty(),"Nothing focused from the viewing spot (%s): %s"%[tag,str(app.view.interaction_focus())])
	var zones:=Industry.zone_report(w.state,k(G_A))
	var by_key:={}
	for row:Dictionary in zones.consumers:by_key[str(row.key)]=str(row.zone)
	check(by_key=={k(S_A):"full",k(S_B):"low",k(S_C):"cut"},"Scene network zones full / low / cut (%s): %s"%[tag,str(by_key)])
	var ab:=box_difference(gates,gates,cell_box(G_A),cell_box(G_B))
	var ac:=box_difference(gates,gates,cell_box(G_A),cell_box(G_C))
	var bc:=box_difference(gates,gates,cell_box(G_B),cell_box(G_C))
	print("NOTE %s gate boxes differ: open/low %.0f%% open/closed %.0f%% low/closed %.0f%%"%[tag,ab*100,ac*100,bc*100])
	check(ab>=0.15 and ac>=0.15 and bc>=0.15,"Three gate modes look different in the world (%s)"%tag)
	# Static frame to frame, with motion on and reduced motion.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	check(box_difference(gates,root.get_texture().get_image(),cell_box(G_A))<=0.01,"Gate static with motion on (%s)"%tag)
	app.view.reduced_motion=true
	var still:Image=await grab()
	check(box_difference(gates,still,cell_box(G_A))<=0.01 and box_difference(gates,still,cell_box(G_C))<=0.01,"Gate identical with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# Non-preview draw path (no village art): the gates are still drawn.
	var art=app.view.village_art
	app.view.village_art=null
	app.view.queue_redraw()
	var plain:Image=await shot("home_gates_plain")
	app.view.village_art=art
	app.view.queue_redraw()
	for c:Vector2i in [G_A,G_B,G_C]:check(gate_share(plain,cell_box(c))>=0.35,"Gate %s drawn on the plain path too (%s)"%[k(c),tag])
	# Gate page: owner, open -> closed through the server.
	await stand(GATE_A_SPOT)
	await open_here()
	check(layout_name()==GateUI.LAYOUT,"Gate page (%s)"%tag)
	await shot("gate_page_open")
	page_fits("gate open "+tag)
	var before:Image=await grab()
	await press("GateMode_closed")
	check(str(w.state.objects[k(G_A)].mode)=="closed","gate_mode closed (%s)"%tag)
	await shot("gate_page_closed")
	page_fits("gate closed "+tag)
	await close()
	await stand(VIEW_SPOT)
	var closed:Image=await grab()
	var changed:=box_difference(gates,closed,cell_box(G_A))
	print("NOTE %s gate A open -> closed: %.0f%% of its box changed"%[tag,changed*100])
	check(changed>=0.15,"Switching the mode redraws gate A (%s)"%tag)
	# Visitor page.
	await stand(OTHER_SPOT)
	await open_here()
	check(layout_name()==GateUI.LAYOUT and (control("GateMode_open") as Button).disabled,"Visitor page read-only (%s)"%tag)
	await shot("gate_page_visitor")
	page_fits("visitor "+tag)
	await close()
	# Plaque in the world (real build action) and its card.
	await stand(PLAQUE_SPOT)
	app.session.rates[1].clear()
	app.session.perform("build",PLAQUE_CELL,Revisit.PLAQUE_KIND)
	await refresh()
	check(str(w.state.objects.get(k(PLAQUE_CELL),{}).get("type",""))==Revisit.PLAQUE_KIND,"Plaque built (%s)"%tag)
	var plaque_world:Image=await shot("plaque_world")
	save_crop(plaque_world,PLAQUE_CELL,"plaque_world_crop")
	prompt_ok(k(PLAQUE_CELL),Revisit.PLAQUE_NAME,"plaque "+tag)
	await open_here()
	check(layout_name()==GateUI.PLAQUE_LAYOUT,"Plaque card (%s)"%tag)
	await shot("plaque_card")
	page_fits("plaque card "+tag)
	await close()
	# Backpack.
	bag()[Revisit.PLAQUE_ITEM]=1  # PRESET
	bag()[Industry.GATE_KIT]=2  # PRESET
	await refresh()
	app._inventory()
	await settle()
	if app.modal is InventoryPanel:
		for item:String in [Revisit.PLAQUE_ITEM,Industry.GATE_KIT]:
			app.modal.select_item(item)
			var slot=app.modal.slots.get(item)
			if slot!=null:(slot as Control).grab_focus()
			await settle()
			check(str(app.modal.selected_id)==item,"%s selected (%s)"%[item,tag])
			await shot("inventory_plaque" if item==Revisit.PLAQUE_ITEM else "inventory_gate")
	await close()
	# Workshop 生活 entries.
	for kind:String in [Revisit.PLAQUE_KIND,Industry.GATE_KIND]:
		app._build_menu()
		await settle()
		var tab:=control("BuildTab3") as Button
		if tab!=null:tab.pressed.emit()
		await settle()
		var slot:=control("BuildSlot_%s_3"%kind) as Button
		check(slot!=null,"Workshop slot %s (%s)"%[kind,tag])
		if slot!=null:
			var shelf:Node=slot.get_parent()
			while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
			if shelf!=null:(shelf as ScrollContainer).ensure_control_visible(slot)
			slot.pressed.emit()
			await settle()
			slot.grab_focus()
		check(label_text("BuildTitle")==World.BUILD[kind].name,"Recipe card %s (%s): %s"%[kind,tag,label_text("BuildTitle")])
		await shot("workshop_plaque" if kind==Revisit.PLAQUE_KIND else "workshop_gate")
		await close()
	app._select_tool("hoe")

func size_flow()->void:
	await reset()
	await lanyang_flow()
	await home_flow()

## Icon checks and a 4× strip: gate open / low / closed, gate kit, plaque, then plank,
## pipe_kit, the sign furniture (bridge plaque art) and the trio keepsake.
func image_of(tex:Texture2D)->Image:
	if tex==null:return null
	var image:=tex.get_image()
	if image==null:return null
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

func sign_image()->Image:
	var atlas:=load("res://assets/ui-life/furniture.png") as Texture2D
	if atlas==null:return null
	var full:=image_of(atlas)
	var index:=["chest","bench","bed","lamp","door","window","table","chair","stove","private_chest","sign","sofa"].find("sign")
	return full.get_region(Rect2i((index%4)*32,(index/4)*48+16,32,32))

func differ(a:Image,b:Image)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 1.0
	var n:=0
	for x in a.get_width():
		for y in a.get_height():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)+absf(p.a-q.a)>0.3:n+=1
	return float(n)/float(a.get_width()*a.get_height())

func icon_flow()->void:
	var images:={"gate_open":image_of(Art.gate_texture("open")),"gate_low":image_of(Art.gate_texture("low")),"gate_closed":image_of(Art.gate_texture("closed")),
		"gate_kit":image_of(Items.icon(Industry.GATE_KIT)),"plaque":image_of(Items.icon(Revisit.PLAQUE_ITEM)),
		"plank":image_of(Items.icon("plank")),"pipe_kit":image_of(Items.icon("pipe_kit")),"sign":sign_image(),"trio":image_of(Souvenir.piece("trio_keepsake"))}
	for name in images:check(images[name]!=null and (images[name] as Image).get_size()==Vector2i(32,32),"32×32 image: %s"%name)
	var pairs:=[["gate_open","gate_low"],["gate_open","gate_closed"],["gate_low","gate_closed"],
		["gate_kit","plank"],["gate_kit","pipe_kit"],["gate_kit","sign"],["gate_kit","plaque"],
		["plaque","plank"],["plaque","pipe_kit"],["plaque","sign"],["plaque","trio"]]
	for pair:Array in pairs:
		var share:=differ(images[pair[0]],images[pair[1]])
		print("NOTE icon %s vs %s: %.0f%% pixels differ"%[pair[0],pair[1],share*100.0])
		check(share>=0.25,"%s differs from %s (%.0f%%)"%[pair[0],pair[1],share*100.0])
	check(Items.icon(Industry.GATE_KIT)!=Items.icon("pipe_kit") and Items.icon(Revisit.PLAQUE_ITEM)!=Items.icon("plank"),"Placeholders replaced")
	var order:=["gate_open","gate_low","gate_closed","gate_kit","plaque","plank","pipe_kit","sign","trio"]
	var strip:=Image.create(order.size()*136+8,144,false,Image.FORMAT_RGBA8)
	strip.fill(Color("f3e6c8"))
	for i in order.size():
		var img:Image=images[order[i]]
		if img==null:continue
		var big:=img.duplicate() as Image
		big.resize(128,128,Image.INTERPOLATE_NEAREST)
		strip.blend_rect(big,Rect2i(0,0,128,128),Vector2i(8+i*136,8))
	tag=""
	save_image(strip,"icons")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/蘭陽回訪預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("lanyang-revisit-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"分水旅人",path)!=OK:check(false,"Host starts");finish();return
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
	check(shots>=49,"24 screenshots per size plus the icon strip (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
