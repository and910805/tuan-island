extends SceneTree
## T071 豐收接力 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/豐收接力預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness
## as test_market_stall_scene.gd.
##
## Art is reused, no new PNGs: sign = assets/ui-life/furniture.png "sign"; crate =
## assets/mine/freight.png frame 2; baskets = assets/bobo/tray.png recoloured per
## basket at runtime; vegetables = assets/ui-inventory/items.png icons (cabbage /
## cucumber / eggplant are runtime recolours).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.picnic written directly (false for the before-picnic contrast frame);
##  * state.harvest_relay and player.harvest_relay erased before each size;
##  * the local player and the fake participants are teleported by writing x/y;
##    fake participants are World.add_player + a fake session.peers entry, and their
##    join/pick actions are sent with World.act;
##  * world time set past `ends`, then World.step(1.0) settles the round.
## REALLY EXERCISED: app._interact() at the sign opens the panel; 開始一場 is pressed
##  by emitting `pressed`; app._interact() at the crate picks (real Session.perform).
## SHOTS per size (7): world_before_picnic, world_unlocked, panel_idle, world_round,
##  hud_tracker (crop of the world_round frame), panel_active_8, panel_result.
const World=preload("res://scripts/world.gd")
const Relay=preload("res://scripts/harvest_relay.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const SIDES:=[Vector2(0.5,1.4),Vector2(1.4,0.5),Vector2(-0.4,0.5),Vector2(0.5,-0.4)]
## Where the player stands for world frames: west of the sign, between crate and
## baskets, so neither carried vegetable covers a prop (partner stands 1 tile east).
const SPOTS:=[Vector2(29.6,32.4),Vector2(29.6,31.9),Vector2(31.0,32.3),Vector2(32.0,32.3)]
const FRIENDS:=["小麥","阿豆","青青","米果","小柚","阿蔥","土豆"]
const AWAY:=Vector2(46.5,36.5)
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
	print("HARVEST_RELAY_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("HARVEST_RELAY_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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

func panel_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))=="harvest_relay"

func own()->Dictionary:
	return HarvestUI.own(app.session.snapshot)

func stand(at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=at.x;person.y=at.y
	await refresh()

func standable(tile:Vector2i)->bool:
	return World.land(tile) and not w.blocked(tile)

func press(control_name:String)->bool:
	var b:=control(control_name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[control_name,tag])
	if b==null or b.disabled:return false
	b.grab_focus()
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	return true

func panel_fits(label:String)->void:
	check(panel_open(),"Panel open (%s)"%label)
	if not panel_open():return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Panel fits the viewport (%s)"%label)
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:check(outer.get_v_scroll_bar().max_value<=outer.get_v_scroll_bar().page+1.0,"Outer panel needs no scrolling (%s)"%label)
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside the panel: 「%s」 (%s)"%[l.text,label])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()) and b.size.x+0.5>=b.get_combined_minimum_size().x,"Button whole inside the panel: 「%s」 (%s)"%[b.text,label])

# ------------------------------------------------------------- world view --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

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

func mean_colour(image:Image,box:Rect2i)->Color:
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var sum:=Vector3.ZERO
	var count:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var c:=image.get_pixel(x,y)
			sum+=Vector3(c.r,c.g,c.b);count+=1
	if count==0:return Color.BLACK
	sum/=float(count)
	return Color(sum.x,sum.y,sum.z)

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

## Screen box (pixels) of each prop, matching world_view.draw_harvest_prop.
func prop_box(site:String)->Rect2i:
	var at:Vector2=app.view.screen(Vector2(HarvestUI.site_cell(site)))
	var rect:=Rect2(at+Vector2(0,-16),Vector2(32,48))
	if site=="crate":rect=Rect2(at+Vector2(0,-10),Vector2(32,42))
	elif site in Relay.BASKET_ORDER:rect=Rect2(at+Vector2(-4,-1),Vector2(40,35))
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## Inside of the painted name plaque of a basket (world_view.draw_harvest_prop).
func tray_box(site:String)->Rect2i:
	var at:Vector2=app.view.screen(Vector2(HarvestUI.site_cell(site)))
	var r:=view_to_pixels(Rect2(at+Vector2(4,21),Vector2(24,11)))
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## Every harvest label is placed with the expected title, on screen, clear of other
## labels and of every HUD panel (hotbar, quest card...), and each prop is on screen
## clear of the HUD.
func labels_ok(label:String)->void:
	var list:=placements()
	var found:={}
	for entry:Dictionary in list:
		if str(entry.id).begins_with("harvest:"):found[str(entry.id)]=entry
	var focused:=str(app.view.focused_label)
	var basket_focused:=focused.begins_with("harvest:") and focused.trim_prefix("harvest:") in Relay.BASKET_ORDER
	for site:String in HarvestUI.SITES:
		var key:="harvest:"+site
		var expected:=HarvestUI.site_title(app.session.snapshot,app.session.own_id,site,focused==key)
		if basket_focused and site in Relay.BASKET_ORDER and focused!=key:
			# The other baskets keep only their painted plaques (no sideways-pushed label).
			check(not found.has(key),"%s label hidden while %s is focused (%s)"%[site,focused,label])
			continue
		check(found.has(key) and str(found[key].title)==expected,"World label 「%s」 placed (%s): %s"%[expected,label,str(found.get(key,{}).get("title","none"))])
		if not found.has(key):continue
		# The label stays over its own prop (not pushed sideways onto something else).
		var anchor_x:float=app.view.screen(Vector2(HarvestUI.site_cell(site))+Vector2(0.5,0)).x
		if focused!=key:check(absf((mine_center(found[key]))-anchor_x)<=40.0,"%s label stays over its prop (%s): centre %.0f vs %.0f"%[site,label,mine_center(found[key]),anchor_x])
		var mine:Dictionary=found[key]
		var pixels:=view_to_pixels(mine.rect)
		check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(pixels),"%s label on screen (%s) %s"%[site,label,str(pixels)])
		for entry:Dictionary in list:
			if entry==mine:continue
			check(not (mine.rect as Rect2).intersects(entry.rect),"「%s」 does not overlap 「%s」 (%s)"%[mine.title,entry.title,label])
		for panel:Dictionary in hud_panels():
			check(not pixels.intersects(panel.rect),"%s label clear of HUD %s (%s) %s vs %s"%[site,panel.name,label,str(pixels),str(panel.rect)])
		var box:=prop_box(site)
		check(Rect2i(Vector2i.ZERO,root.size).encloses(box),"Whole %s prop on screen (%s) %s"%[site,label,str(box)])
		for panel:Dictionary in hud_panels():
			check(not Rect2(box).intersects(panel.rect),"%s prop clear of HUD %s (%s)"%[site,panel.name,label])

func mine_center(entry:Dictionary)->float:
	return (entry.rect as Rect2).get_center().x

func carry_box(foot_world:Vector2)->Rect2i:
	var r:=view_to_pixels(app.view.harvest_carry_rect(app.view.screen(foot_world).round()))
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## The model vegetable above a head: cream backing plus enough non-cream icon pixels.
func carry_drawn(image:Image,foot_world:Vector2,who:String)->void:
	var box:=carry_box(foot_world)
	check(Rect2i(Vector2i.ZERO,root.size).encloses(box),"%s carry icon on screen (%s) %s"%[who,tag,str(box)])
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var cream:=0;var icon:=0
	var paper:=Color("fff3d2")
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var c:=image.get_pixel(x,y)
			var d:=absf(c.r-paper.r)+absf(c.g-paper.g)+absf(c.b-paper.b)
			if d<0.06:cream+=1
			elif c.s>0.3:icon+=1
	var total:=maxi(1,box.size.x*box.size.y)
	print("NOTE %s carry box %s cream %.0f%% icon %.0f%%"%[who,str(box),100.0*cream/total,100.0*icon/total])
	check(cream>=total*0.08 and icon>=total*0.12,"%s carries a visible vegetable above the head (%s): cream %d icon %d of %d"%[who,tag,cream,icon,total])
	for panel:Dictionary in hud_panels():
		check(not Rect2(box).intersects(panel.rect),"%s carry icon clear of HUD %s (%s)"%[who,panel.name,tag])
	for entry:Dictionary in placements():
		check(not Rect2(box).intersects(view_to_pixels(entry.rect)),"%s carry icon not covered by label 「%s」 (%s)"%[who,entry.title,tag])

func world_spot()->Vector2:
	for at:Vector2 in SPOTS:
		if standable(Vector2i(at.floor())):return at
	return SPOTS[0]

func stand_at(site:String)->bool:
	var cell:=HarvestUI.site_cell(site)
	for off:Vector2 in SIDES:
		var at:Vector2=Vector2(cell)+off
		if not standable(Vector2i(at.floor())):continue
		await stand(at)
		if str(app.view.interaction_focus())=="harvest:"+site:return true
	check(false,"Some side of %s focuses it (%s)"%[site,tag])
	return false

func friend(index:int,at:Vector2)->String:
	var token:="harvest-scene-friend-%d"%index
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
	w.state.erase("harvest_relay")  # PRESET fresh activity
	for token in w.state.players:(w.state.players[token] as Dictionary).erase("harvest_relay")
	for token in friends:
		w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y
	# Before the picnic: no props.
	w.state.picnic=false  # PRESET
	await refresh()
	var spot:=world_spot()
	await stand(spot)
	check(not HarvestUI.on_field(app.session.snapshot),"No activity field before the picnic (%s)"%tag)
	var has_label:=false
	for entry:Dictionary in placements():
		if str(entry.id).begins_with("harvest:"):has_label=true
	check(not has_label and not str(app.view.interaction_focus()).begins_with("harvest:"),"No harvest label or focus before the picnic (%s)"%tag)
	var before:Image=await shot("world_before_picnic")
	# After the picnic, same spot and camera.
	w.state.picnic=true  # PRESET
	await refresh()
	await stand(spot)
	check(HarvestUI.on_field(app.session.snapshot),"Activity field after the picnic (%s)"%tag)
	var after:Image=await shot("world_unlocked")
	for site:String in HarvestUI.SITES:
		var box:=prop_box(site)
		var diff:=box_difference(before,after,box)
		print("NOTE %s: %s box %s changed %.0f%% vs before the picnic"%[tag,site,str(box),diff*100.0])
		check(diff>=0.2,"%s prop drawn at its cell (%.0f%% changed) %s"%[site,diff*100.0,tag])
	var tints:={}
	for basket:String in Relay.BASKET_ORDER:tints[basket]=mean_colour(after,tray_box(basket))
	print("NOTE %s basket felt colours %s"%[tag,str(tints)])
	for pair in [["root","leaf"],["leaf","fruit"],["root","fruit"]]:
		var a:Color=tints[pair[0]];var b:Color=tints[pair[1]]
		check(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>=0.12,"Baskets %s and %s visibly differ in colour (%s)"%[pair[0],pair[1],tag])
	labels_ok("unlocked "+tag)
	# Panel idle via the interact key path at the sign.
	if not await stand_at("sign"):return
	app._interact()
	await settle()
	check(panel_open(),"Interact at the sign opens 豐收接力 (%s)"%tag)
	if not panel_open():return
	await shot("panel_idle")
	panel_fits("idle "+tag)
	await press("HarvestStart")
	var round_id:=int(own().get("round",0))
	check(bool(own().get("active",false)) and bool(own().get("joined",false)),"Round started (%s)"%tag)
	app._close_modal()
	# I pick at the crate (real interact); a partner joins and picks too.
	if not await stand_at("crate"):return
	app._interact()
	await settle()
	var mine:=str(own().get("carry",""))
	check(mine==Relay.kind_at(round_id,0),"I carry %s (%s): %s"%[Relay.kind_at(round_id,0),tag,mine])
	var buddy:=friend(0,Vector2(Relay.CRATE)+Vector2(1.4,0.9))
	friend_act(buddy,"harvest_join",Relay.SIGN,str(round_id))
	friend_act(buddy,"harvest_pick",Relay.CRATE,"")
	# Both stand at the world spot, side by side.
	await stand(spot)
	var buddy_at:=spot+Vector2(1.0,0.0)
	w.state.players[buddy].x=buddy_at.x;w.state.players[buddy].y=buddy_at.y
	await refresh()
	var buddy_id:=buddy.sha256_text().left(16)
	check(HarvestUI.carried(app.session.snapshot,buddy_id)==Relay.kind_at(round_id,1),"Partner carries %s in the public snapshot (%s)"%[Relay.kind_at(round_id,1),tag])
	# The snapshot moves the test partner from the crate. The actual renderer
	# may still be catching up to that position, especially at high refresh.
	var settle_deadline:=Time.get_ticks_msec()+2000
	while Vector2(app.view.display_positions.get(buddy_id,Vector2.INF)).distance_to(buddy_at)>0.02 and Time.get_ticks_msec()<settle_deadline:
		await process_frame
	var rendered_buddy:=Vector2(app.view.display_positions.get(buddy_id,Vector2.INF))
	check(rendered_buddy.distance_to(buddy_at)<=0.02,"Partner settles beside the player (%s)"%tag)
	var round_image:Image=await shot("world_round")
	carry_drawn(round_image,spot,"player")
	carry_drawn(round_image,buddy_at,"partner")
	labels_ok("round "+tag)
	# HUD tracker (crop of the same frame).
	check(str(app.objective.text).begins_with("豐收接力 0 / 24 · 剩 "),"HUD tracker text during the round (%s): %s"%[tag,app.objective.text])
	check(str(app.objective.text).contains("手上：%s → %s"%[Relay.kind_name(mine),HarvestUI.basket_label(Relay.basket_of(mine))]),"HUD tracker shows my hands (%s)"%tag)
	var tracker:=app.preview_tracker as Control
	if tracker!=null and round_image!=null:
		var rect:=Rect2i(tracker.get_global_rect().grow(4))
		rect=rect.intersection(Rect2i(Vector2i.ZERO,round_image.get_size()))
		save_image(round_image.get_region(rect),"hud_tracker")
		for panel:Dictionary in hud_panels():
			if panel.name==tracker.name:continue
			check(not tracker.get_global_rect().intersects(panel.rect),"Tracker clear of HUD %s (%s)"%[panel.name,tag])
		var pass_hud:=app.hud.find_child("TrackerHarvestPass",true,false) as Control
		check(pass_hud!=null and pass_hud.is_visible_in_tree() and tracker.get_global_rect().grow(0.5).encloses(pass_hud.get_global_rect()),"傳給身旁的夥伴 inside the tracker (%s)"%tag)
		var objective:=app.objective as Label
		check(objective.get_visible_line_count()>=objective.get_line_count() and tracker.get_global_rect().grow(0.5).encloses(objective.get_global_rect()),"Tracker text whole (%s)"%tag)
	# Eight participants.
	for index in range(1,7):
		var token:=friend(index,Vector2(Relay.SIGN)+Vector2(0.5,0.5)+Vector2(cos(index*0.9),sin(index*0.9))*1.5)
		friend_act(token,"harvest_join",Relay.SIGN,str(round_id))
	await refresh()
	check(int(own().get("joined_count",0))==8,"Eight joined (%s)"%tag)
	app._harvest_menu()
	await settle()
	await shot("panel_active_8")
	panel_fits("8 participants "+tag)
	check(control("HarvestPeople")!=null and control("HarvestPeople").get_child_count()==8,"Eight rows (%s)"%tag)
	# Finish by time; the result is shown.
	app._close_modal()
	w.state.time=float(w.state.harvest_relay.ends)+0.1  # PRESET time
	check(w.step(1.0,true),"World tick ends the round (%s)"%tag)
	await refresh()
	app._harvest_menu()
	await settle()
	check(label_text("HarvestLast").begins_with("第 %d 輪 · 時間到"%round_id),"Result shown (%s): %s"%[tag,label_text("HarvestLast")])
	check(label_text("HarvestRecord").begins_with("紀念票 1 張 · 參加 1 場"),"Record shown (%s): %s"%[tag,label_text("HarvestRecord")])
	await shot("panel_result")
	panel_fits("result "+tag)
	app._close_modal()
	for token in friends:
		w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/豐收接力預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("harvest-relay-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"豐收旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=14,"7 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
