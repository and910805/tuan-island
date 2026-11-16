extends SceneTree
## T071 家園布置題 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/家園布置題預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness
## as test_fishing_meet_scene.gd.
##
## Art is reused / runtime-painted, no new PNGs: sign = assets/ui-life/furniture.png
## "sign" with a runtime-painted house glyph and a rose flag on the left post; plot =
## warm tint + static dashed border + corner stakes; the 8 props are runtime-painted
## 32×32 pixel images (showcase_ui.piece_texture).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic written directly (picnic false for the before frame);
##  * state.showcase and player.showcase erased before each size;
##  * the local player and the fake participants are teleported by writing x/y; my
##    facing is written on world_view (interpolation snapped); fake participants are
##    World.add_player + a fake session.peers entry, their join / place actions are
##    sent with World.act;
##  * world clock: the cooldown is skipped by setting state.time past `ready`, the
##    time-out by setting it past `ends`, then World.step(1.0) settles;
##  * the paused frame writes a lamp object onto plot cell (29,46) directly.
## REALLY EXERCISED: app._interact() at the sign opens the page and on plot tiles
##  places pieces; 開始一場 / 完成展示 pressed by emitting `pressed`.
## SHOTS per size (18): world_before_picnic, world_unlocked_before, world_unlocked,
##  page_idle, world_round_before, world_round, pieces_strip (crop of the 8 kinds),
##  world_round_reduced, hud_tracker (crop), world_prompt_empty, world_prompt_occupied,
##  page_active, page_active_8, page_result_goal, world_finished, page_result_time,
##  world_paused, page_paused. The two *_before frames are the same scene with
##  world_view.showcase_fade_trees=false (tree crowns opaque, the sign hidden) — the
##  look before the crown-fading fix found while reviewing these screenshots.
const World=preload("res://scripts/world.gd")
const Show=preload("res://scripts/showcase.gd")
const ShowUI=preload("res://scripts/showcase_ui.gd")
const FRIENDS:=["小麥","阿豆","青青","米果","小柚","阿蔥","土豆"]
const SIGN_SPOT:=Vector2(25.5,45.5)
## Viewing spot just below the plot (row 48): with the player-centred camera the whole
## plot, the sign and its label sit clear of the tracker (top-left) and the quick-key
## bar at 1024×640 as well as 1280×800.
const VIEW_SPOT:=Vector2(29.5,48.5)
const PROMPT_SPOT:=Vector2(28.5,47.5)   # faces RIGHT onto (29,47)
const PROMPT_CELL:=Vector2i(29,47)
const BUDDY_SPOT:=Vector2(32.5,45.5)
## Where the 8 kinds go (rows 44-45, columns 28-31).
const LAYOUT:={"flower_pot":Vector2i(28,44),"flower_box":Vector2i(29,44),"fern":Vector2i(30,44),"stool":Vector2i(31,44),
	"bench":Vector2i(28,45),"cushion":Vector2i(29,45),"lantern":Vector2i(30,45),"string_lights":Vector2i(31,45)}
const MINE:=["lantern","string_lights"]
const AWAY:=Vector2(46.5,36.5)
const SPOTS:=[Vector2(27.5,44.5),Vector2(27.5,46.5),Vector2(26.5,47.5),Vector2(25.5,44.5),Vector2(25.5,46.5),Vector2(24.5,45.5)]
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
var friends:Array[String]=[]
var peer_seq:=900

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("SHOWCASE_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("SHOWCASE_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func label_text(control_name:String)->String:
	var l:=control(control_name) as Label
	return l.text if l!=null else ""

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))=="showcase"

func own()->Dictionary:
	return ShowUI.own(app.session.snapshot)

func person()->Dictionary:
	return w.state.players[id]

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()

## PRESET: my facing, walk interpolation snapped to the new position.
func face(dir:Vector2i)->void:
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=dir
	await settle()

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
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

## Fraction of differing pixels between two same-sized boxes of one image.
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

func cell_rect(cell:Vector2i)->Rect2:
	return Rect2(app.view.screen(Vector2(cell)),Vector2(32,32))

## Opaque bounds of the shared "sign" sprite (furniture atlas) + my flag, world px.
func sign_box_world()->Rect2:
	var at:Vector2=app.view.screen(Vector2(Show.SIGN))
	var atlas:=(load("res://assets/ui-life/furniture.png") as Texture2D).get_image()
	if atlas.is_compressed():atlas.decompress()
	var used:=atlas.get_region(Rect2i(64,96,32,48)).get_used_rect()
	var sprite:=Rect2(at+Vector2(0,-16)+Vector2(used.position),Vector2(used.size))
	return sprite.merge(Rect2(at+Vector2(-7,-2),Vector2(10,12)))

func plot_border_pixels(image:Image)->int:
	var r:=ShowUI.plot_rect(app.view).grow(-2.0)
	var count:=0
	for edge:Rect2 in [Rect2(r.position+Vector2(6,-2),Vector2(r.size.x-12,4)),Rect2(Vector2(r.position.x,r.end.y)+Vector2(6,-2),Vector2(r.size.x-12,4)),Rect2(r.position+Vector2(-2,6),Vector2(4,r.size.y-12)),Rect2(Vector2(r.end.x,r.position.y)+Vector2(-2,6),Vector2(4,r.size.y-12))]:
		var box:=pixel_box(edge).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		for x in range(box.position.x,box.end.x):
			for y in range(box.position.y,box.end.y):
				var c:=image.get_pixel(x,y)
				if absf(c.r-ShowUI.PLOT_EDGE.r)+absf(c.g-ShowUI.PLOT_EDGE.g)+absf(c.b-ShowUI.PLOT_EDGE.b)<0.1:count+=1
	return count

## Labels: sign label title, on screen, never over the sign sprite, the pieces or the
## HUD; the plot and the sign clear of every HUD panel.
func world_ok(label:String,piece_cells:Array)->void:
	var list:=placements()
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	var sign_box:=sign_box_world()
	var sign_label:Dictionary={}
	for entry:Dictionary in list:
		if str(entry.id)==ShowUI.POINT:sign_label=entry
	var expected:=ShowUI.sign_title(app.session.snapshot,str(app.view.focused_label)==ShowUI.POINT)
	check(not sign_label.is_empty() and str(sign_label.title)==expected,"Sign label 「%s」 placed (%s): %s"%[expected,label,str(sign_label.get("title","none"))])
	for entry:Dictionary in list:
		var r:Rect2=entry.rect
		check(screen_rect.encloses(view_to_pixels(r)),"Label 「%s」 on screen (%s)"%[entry.title,label])
		check(not r.intersects(sign_box.grow(-0.5)),"Label 「%s」 not over the sign (%s) %s vs %s"%[entry.title,label,str(r),str(sign_box)])
		for cell:Vector2i in piece_cells:
			# Name tags (id "") float between rows; they may touch the bottom shadow band.
			var body:=cell_rect(cell).grow(-1.0)
			if str(entry.id)=="":body.size.y-=8.0
			check(not r.intersects(body),"Label 「%s」 not over the piece at %s (%s) %s"%[entry.title,str(cell),label,str(r)])
		for other:Dictionary in list:
			if other!=entry and str(other.id)!="" and str(entry.id)!="":check(not r.intersects(other.rect),"「%s」 does not overlap 「%s」 (%s)"%[entry.title,other.title,label])
		if str(entry.id)!="":
			for panel:Dictionary in hud_panels():
				check(not view_to_pixels(r).intersects(panel.rect),"Label 「%s」 clear of HUD %s (%s)"%[entry.title,panel.name,label])
	var plot_px:=view_to_pixels(ShowUI.plot_rect(app.view))
	var sign_px:=view_to_pixels(sign_box)
	check(screen_rect.encloses(plot_px) and screen_rect.encloses(sign_px),"Whole plot and sign on screen (%s) %s"%[label,str(plot_px)])
	for panel:Dictionary in hud_panels():
		check(not plot_px.intersects(panel.rect),"Plot clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(plot_px),str(panel.rect)])
		check(not sign_px.intersects(panel.rect),"Sign clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(sign_px),str(panel.rect)])
	# The selected-tool hint above the quick-key bar is a HUD label too.
	var hint:=app.selected_label as Control
	if hint!=null and hint.is_visible_in_tree():check(not plot_px.intersects(hint.get_global_rect()),"Plot clear of the tool hint (%s)"%label)

func prompt_ok(label:String,expect:String,piece_cells:Array)->void:
	var mine:Dictionary={}
	for entry:Dictionary in placements():
		if str(entry.id)==ShowUI.PLOT_POINT:mine=entry
	check(not mine.is_empty() and str(mine.title)==expect,"Plot prompt 「%s」 placed (%s): %s"%[expect,label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var r:Rect2=mine.rect
	check(not r.intersects(cell_rect(PROMPT_CELL).grow(-1.0)),"Prompt does not cover its target cell (%s)"%label)
	check((r.get_center()-cell_rect(PROMPT_CELL).get_center()).length()<=72.0,"Prompt stays near its target (%s) %s"%[label,str(r)])
	world_ok(label,piece_cells)

func friend(index:int,at:Vector2)->String:
	var token:="showcase-scene-friend-%d"%index
	if not w.state.players.has(token):
		w.add_player(token,FRIENDS[index])
		peer_seq+=1
		app.session.peers[peer_seq]=token
		friends.append(token)
	var p:Dictionary=w.state.players[token]
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	return token

func friend_act(token:String,action:String,p:Vector2i,extra:String="")->Dictionary:
	var result:Dictionary=w.act(token,"scene-%d"%Time.get_ticks_usec(),action,p,extra)
	check(bool(result.get("ok",false)),"%s %s (%s): %s"%[token,action,tag,str(result)])
	return result

# ------------------------------------------------------------------ flows --

func size_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.erase("showcase")  # PRESET fresh activity
	for token in w.state.players:(w.state.players[token] as Dictionary).erase("showcase")
	for cell:Vector2i in Show.cells():w.state.objects.erase(Show.cell_key(cell))
	for token in friends:
		w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y
	app.view.showcase_kind=ShowUI.DEFAULT_KIND
	app.view.reduced_motion=false
	w.state.board=true  # PRESET
	w.state.picnic=false  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	await face(Vector2i.DOWN)
	check(not ShowUI.sign_shown(app.session.snapshot) and not ShowUI.plot_shown(app.session.snapshot),"No sign or plot before the picnic (%s)"%tag)
	var has_label:=false
	for entry:Dictionary in placements():
		if str(entry.id) in [ShowUI.POINT,ShowUI.PLOT_POINT]:has_label=true
	check(not has_label,"No 家園布置題 label before the picnic (%s)"%tag)
	var before:Image=await shot("world_before_picnic")
	w.state.picnic=true  # PRESET
	await refresh()
	await stand(VIEW_SPOT)
	await face(Vector2i.DOWN)
	# Before frame of the fix: tree crowns drawn opaque hide the sign (kept for review).
	app.view.showcase_fade_trees=false
	var opaque:Image=await shot("world_unlocked_before")
	app.view.showcase_fade_trees=true
	var unlocked:Image=await shot("world_unlocked")
	var sign_diff:=box_difference(before,unlocked,pixel_box(sign_box_world()))
	var opaque_diff:=box_difference(before,opaque,pixel_box(sign_box_world()))
	print("NOTE %s: sign box changed %.0f%% with faded crowns, %.0f%% with opaque crowns"%[tag,sign_diff*100.0,opaque_diff*100.0])
	check(sign_diff>opaque_diff+0.1,"Faded crowns reveal the sign (%s): %.0f%% vs %.0f%%"%[tag,sign_diff*100.0,opaque_diff*100.0])
	print("NOTE %s: sign box changed %.0f%%, plot border cream pixels %d (before %d)"%[tag,sign_diff*100.0,plot_border_pixels(unlocked),plot_border_pixels(before)])
	check(sign_diff>=0.2,"Sign drawn at its cell (%.0f%% changed) %s"%[sign_diff*100.0,tag])
	check(plot_border_pixels(unlocked)>=60 and plot_border_pixels(before)*5<plot_border_pixels(unlocked),"Dashed plot border drawn after the picnic (%s): %d vs %d"%[tag,plot_border_pixels(unlocked),plot_border_pixels(before)])
	var plot_diff:=box_difference(before,unlocked,pixel_box(ShowUI.plot_rect(app.view).grow(-6.0)))
	check(plot_diff>=0.3,"Plot ground tinted (%.0f%% changed) %s"%[plot_diff*100.0,tag])
	world_ok("unlocked "+tag,[])
	# The outline is static in every motion mode.
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var later:Image=root.get_texture().get_image()
	check(box_difference(unlocked,later,pixel_box(ShowUI.plot_rect(app.view)))<=0.01,"Plot outline static (%s)"%tag)
	# Idle page via the interact path at the sign.
	await stand(SIGN_SPOT)
	check(str(app.view.interaction_focus())==ShowUI.POINT,"Sign focused west of it (%s)"%tag)
	app._interact()
	await settle()
	check(page_open(),"Interact at the sign opens 家園布置題 (%s)"%tag)
	if not page_open():return
	await shot("page_idle")
	page_fits("idle "+tag)
	await press("ShowcaseStart")
	var round_id:=int(own().get("round",0))
	check(bool(own().get("active",false)) and bool(own().get("joined",false)),"Round started (%s)"%tag)
	app._close_modal()
	# A teammate joins and places six kinds; I place the two lights with the interact key.
	var buddy:=friend(0,Vector2(27.5,45.5))
	friend_act(buddy,"showcase_join",Show.SIGN,str(round_id))
	for kind:String in Show.KIND_ORDER:
		if kind in MINE:continue
		var cell:Vector2i=LAYOUT[kind]
		friend(0,Vector2(cell)+Vector2(0.5,0.5))
		friend_act(buddy,"showcase_place",cell,"%d|%s"%[round_id,kind])
	friend(0,BUDDY_SPOT)
	for kind:String in MINE:
		var cell:Vector2i=LAYOUT[kind]
		await stand(Vector2(cell)+Vector2(0.5,1.5))
		await face(Vector2i.UP)
		app.view.showcase_kind=kind
		check(ShowUI.view_target(app.view)==cell,"Target %s for %s (%s)"%[str(cell),kind,tag])
		app.session.rates[1].clear()
		app._interact()
		await refresh()
	for kind:String in Show.KIND_ORDER:
		check(ShowUI.piece_at(app.session.snapshot,LAYOUT[kind])==kind,"%s on the plot (%s)"%[kind,tag])
	app.view.showcase_kind="flower_pot"
	await stand(VIEW_SPOT)
	await face(Vector2i.DOWN)
	app.view.showcase_fade_trees=false
	await shot("world_round_before")
	app.view.showcase_fade_trees=true
	var round_image:Image=await shot("world_round")
	var piece_cells:Array=LAYOUT.values()
	world_ok("round "+tag,piece_cells)
	# Each kind renders (differs from the empty plot) and differs from every other kind.
	var boxes:={}
	for kind:String in Show.KIND_ORDER:
		boxes[kind]=pixel_box(cell_rect(LAYOUT[kind]))
		var drawn:=box_difference(unlocked,round_image,boxes[kind])
		check(drawn>=0.15,"%s renders on its tile (%.0f%% changed) %s"%[kind,drawn*100.0,tag])
	var least:=1.0
	for i in Show.KIND_ORDER.size():
		for j in range(i+1,Show.KIND_ORDER.size()):
			var a:String=Show.KIND_ORDER[i];var b:String=Show.KIND_ORDER[j]
			var d:=region_difference(round_image,boxes[a],boxes[b])
			least=minf(least,d)
			check(d>=0.2,"%s and %s look different (%.0f%%) %s"%[a,b,d*100.0,tag])
	print("NOTE %s: least pairwise piece difference %.0f%%"%[tag,least*100.0])
	# The 8 kinds side by side (crop of the round frame).
	var strip:=Rect2i(pixel_box(cell_rect(LAYOUT.flower_pot))).merge(pixel_box(cell_rect(LAYOUT.string_lights))).grow(6)
	save_image(round_image.get_region(strip.intersection(Rect2i(Vector2i.ZERO,round_image.get_size()))),"pieces_strip")
	for kind:String in Show.KIND_ORDER:
		for panel:Dictionary in hud_panels():
			check(not view_to_pixels(cell_rect(LAYOUT[kind])).intersects(panel.rect),"%s clear of HUD %s (%s)"%[kind,panel.name,tag])
	# Second player visible (body region changed vs the unlocked frame).
	var buddy_box:=pixel_box(Rect2(app.view.screen(BUDDY_SPOT)+Vector2(-10,-40),Vector2(20,40)))
	check(box_difference(unlocked,round_image,buddy_box)>=0.2,"Second player drawn on the plot (%s)"%tag)
	# Reduced motion: still frame-to-frame around the plot.
	app.view.reduced_motion=true
	var still_a:Image=await shot("world_round_reduced")
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var still_b:Image=root.get_texture().get_image()
	check(box_difference(still_a,still_b,pixel_box(ShowUI.plot_rect(app.view)))<=0.01,"Plot and pieces static with reduced motion (%s)"%tag)
	app.view.reduced_motion=false
	# HUD tracker (crop of the round frame).
	check(str(app.objective.text).begins_with("家園布置題 花園茶會\n花草 3/4 座位 3/3✓ 燈飾 2/1✓\n剩 "),"HUD tracker text during the round (%s): %s"%[tag,app.objective.text])
	var tracker:=app.preview_tracker as Control
	if tracker!=null and round_image!=null:
		var rect:=Rect2i(tracker.get_global_rect().grow(4)).intersection(Rect2i(Vector2i.ZERO,round_image.get_size()))
		save_image(round_image.get_region(rect),"hud_tracker")
		for panel:Dictionary in hud_panels():
			if panel.name==tracker.name:continue
			check(not tracker.get_global_rect().intersects(panel.rect),"Tracker clear of HUD %s (%s)"%[panel.name,tag])
		var objective:=app.objective as Label
		check(objective.get_visible_line_count()>=objective.get_line_count() and objective.get_line_count()==3 and tracker.get_global_rect().grow(0.5).encloses(objective.get_global_rect()),"Tracker text whole, three lines (%s): %d"%[tag,objective.get_line_count()])
	# Interact prompts on an empty and on an occupied tile.
	await stand(PROMPT_SPOT)
	await face(Vector2i.RIGHT)
	check(ShowUI.view_target(app.view)==PROMPT_CELL,"Prompt spot targets %s (%s)"%[str(PROMPT_CELL),tag])
	await shot("world_prompt_empty")
	prompt_ok("prompt empty "+tag,"擺上 小花盆",piece_cells)
	app.session.rates[1].clear()
	app._interact()
	await refresh()
	check(ShowUI.piece_at(app.session.snapshot,PROMPT_CELL)=="flower_pot","Interact placed 小花盆 on the prompt cell (%s)"%tag)
	await face(Vector2i.RIGHT)
	await shot("world_prompt_occupied")
	prompt_ok("prompt occupied "+tag,"收起 小花盆",piece_cells)
	# Active page (theme met: 4 flowers, 3 seats, 2 lights).
	await stand(SIGN_SPOT)
	app._interact()
	await settle()
	check(page_open() and label_text("ShowcaseCheck_flower")=="花草 4／4 ✓","Active page with the checklist met (%s): %s"%[tag,label_text("ShowcaseCheck_flower")])
	await shot("page_active")
	page_fits("active "+tag)
	app._close_modal()
	for index in range(1,7):
		var token:=friend(index,SPOTS[index-1])
		friend_act(token,"showcase_join",Show.SIGN,str(round_id))
	await refresh()
	check(int(own().get("joined_count",0))==8,"Eight joined (%s)"%tag)
	app._showcase_menu()
	await settle()
	await shot("page_active_8")
	page_fits("8 participants "+tag)
	check(control("ShowcasePeople")!=null and control("ShowcasePeople").get_child_count()==8,"Eight rows (%s)"%tag)
	# Finish by goal.
	await press("ShowcaseFinish")
	var last:Dictionary=own().get("last",{})
	check(str(last.get("reason",""))=="goal" and int(last.get("tickets",0))==2,"Goal finish with 2 tickets (%s): %s"%[tag,str(last)])
	check(label_text("ShowcaseLast")=="第 %d 輪「花園茶會」· 提早完成展示 · 主題完成"%round_id,"Goal result line (%s): %s"%[tag,label_text("ShowcaseLast")])
	await shot("page_result_goal")
	page_fits("result goal "+tag)
	app._close_modal()
	for token in friends:w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y
	friend(0,BUDDY_SPOT)
	await stand(VIEW_SPOT)
	await face(Vector2i.DOWN)
	var done:Image=await shot("world_finished")
	check(box_difference(unlocked,done,pixel_box(cell_rect(LAYOUT.lantern)))>=0.15,"Finished display stays visible during the cooldown (%s)"%tag)
	world_ok("finished "+tag,piece_cells)
	# Round 2 times out.
	w.state.time=float(w.state.showcase.ready)+0.1  # PRESET: cooldown over
	w.step(1.0,true)
	await stand(SIGN_SPOT)
	app._interact()
	await settle()
	await press("ShowcaseStart")
	app._close_modal()
	w.state.time=float(w.state.showcase.ends)+0.1  # PRESET time
	check(w.step(1.0,true),"World tick ends round 2 (%s)"%tag)
	await refresh()
	app._showcase_menu()
	await settle()
	check(label_text("ShowcaseLast")=="第 %d 輪「海風小攤」· 時間到 · 主題未完成"%(round_id+1),"Time result line (%s): %s"%[tag,label_text("ShowcaseLast")])
	await shot("page_result_time")
	page_fits("result time "+tag)
	app._close_modal()
	# Paused: an occupied plot cell.
	w.state.objects["29,46"]={"type":"lamp","owner":id,"items":{}}  # PRESET occupation
	await stand(VIEW_SPOT)
	await face(Vector2i.DOWN)
	check(not ShowUI.on_field(app.session.snapshot) and ShowUI.sign_shown(app.session.snapshot),"Paused with the sign still shown (%s)"%tag)
	await shot("world_paused")
	await stand(SIGN_SPOT)
	app._interact()
	await settle()
	check(label_text("ShowcaseBlocked").contains("地塊 (29,46)"),"Paused page names the cell (%s): %s"%[tag,label_text("ShowcaseBlocked")])
	await shot("page_paused")
	page_fits("paused "+tag)
	app._close_modal()
	w.state.objects.erase("29,46")
	for token in friends:
		w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/家園布置題預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("showcase-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"布置題旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=36,"18 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
