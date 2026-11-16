extends SceneTree
## T071 河岸釣魚會 native render check at 1024×640 and 1280×800. Screenshots go to
## outputs/河岸釣魚會預覽 (or --capture-dir=), named <w>x<h>_<step>.png. Same harness
## as test_harvest_relay_scene.gd.
##
## Art is reused, no new PNGs: notice board = assets/ui-life/furniture.png "sign" with
## the carp icon (assets/ui-inventory/items.png) and a runtime-drawn blue pennant;
## waters marker = runtime-drawn dashed rope + red/white buoys along WATERS.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic written directly (picnic false for the before frame);
##  * state.fish_meet and player.fish_meet erased before each size;
##  * the local player and the fake participants are teleported by writing x/y;
##    fake participants are World.add_player + a fake session.peers entry, and their
##    join / fish_start / fish_catch actions are sent with World.act;
##  * world clock: state.time set to a cast's `ready` (bite) instead of waiting; the
##    time-out sets state.time past `ends` then World.step(1.0) settles; before the
##    second (goal) round state.time is set past the cooldown `ready`.
## REALLY EXERCISED: app._interact() at the sign opens the panel; 開始一場 pressed by
##  emitting `pressed`; my cast and catch go through Session.perform(fish_start /
##  fish_catch) exactly as the fishing tool sends them.
## SHOTS per size (9): world_before_picnic, world_unlocked, panel_idle, world_round,
##  hud_tracker (crop of world_round), panel_mid, panel_active_8, panel_result_time,
##  panel_result_goal.
const World=preload("res://scripts/world.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const FishUI=preload("res://scripts/fishing_meet_ui.gd")
const FRIENDS:=["小麥","阿豆","青青","米果","小柚","阿蔥","土豆"]
const SIGN_SPOT:=Vector2(54.5,39.5)
## Shore (53,38), west of the sign: within sign reach, casts at (55,37). Chosen so the
## camera (player-centred) shows all six WATERS rows above the 1024×640 quick-key bar.
const FISH_SPOT:=Vector2(53.5,38.5)
const CAST:=Vector2i(55,37)
const BUDDY_SPOT:=Vector2(54.5,34.6)  # shore (54,34): casts at (55,34)
const BUDDY_CAST:=Vector2i(55,34)
const AWAY:=Vector2(30.5,33.5)  # off-camera parking for fake players between sizes
const SPOTS:=[Vector2(54.5,35.5),Vector2(53.5,36.5),Vector2(53.5,37.5),Vector2(53.5,38.5),Vector2(53.5,39.5),Vector2(54.5,40.5)]
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
	print("FISHING_MEET_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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
	print("FISHING_MEET_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

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
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))=="fishing_meet"

func own()->Dictionary:
	return FishUI.own(app.session.snapshot)

func person()->Dictionary:
	return w.state.players[id]

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()

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

## Screen box (pixels) of the notice board sprite + pennant (world_view / FishUI.draw_sign).
func sign_box()->Rect2i:
	var at:Vector2=app.view.screen(Vector2(Meet.SIGN))
	return pixel_box(Rect2(at+Vector2(0,-18),Vector2(32,50)))

## Buoys visible: pixels close to the buoy red inside each buoy box (bob ±1 px).
func buoys_seen(image:Image)->int:
	var seen:=0
	for p:Vector2 in FishUI.buoy_points(app.view):
		var box:=pixel_box(Rect2(p-Vector2(5,6),Vector2(10,12))).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		var red:=0
		for x in range(box.position.x,box.end.x):
			for y in range(box.position.y,box.end.y):
				var c:=image.get_pixel(x,y)
				if absf(c.r-FishUI.BUOY.r)+absf(c.g-FishUI.BUOY.g)+absf(c.b-FishUI.BUOY.b)<0.12:red+=1
		if red>=8:seen+=1
	return seen

## Rope dashes: cream pixels along the WATERS rect's long edges.
func rope_pixels(image:Image)->int:
	var r:=FishUI.waters_rect(app.view).grow(-3.0)
	var count:=0
	for edge_x in [r.position.x,r.end.x]:
		var box:=pixel_box(Rect2(Vector2(edge_x-2,r.position.y+8),Vector2(4,r.size.y-16))).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		for x in range(box.position.x,box.end.x):
			for y in range(box.position.y,box.end.y):
				var c:=image.get_pixel(x,y)
				if absf(c.r-FishUI.ROPE.r)+absf(c.g-FishUI.ROPE.g)+absf(c.b-FishUI.ROPE.b)<0.1:count+=1
	return count

## The sign label is placed with the expected title, on screen, over its sign, clear
## of every other label and of every HUD panel (quick-key bar, shortcuts, tracker).
func labels_ok(label:String)->void:
	var expected:=FishUI.sign_title(app.session.snapshot,str(app.view.focused_label)==FishUI.POINT)
	var list:=placements()
	var mine:Dictionary={}
	for entry:Dictionary in list:
		if str(entry.id)==FishUI.POINT:mine=entry
	check(not mine.is_empty() and str(mine.title)==expected,"Sign label 「%s」 placed (%s): %s"%[expected,label,str(mine.get("title","none"))])
	if mine.is_empty():return
	var pixels:=view_to_pixels(mine.rect)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(pixels),"Sign label on screen (%s) %s"%[label,str(pixels)])
	var anchor_x:float=app.view.screen(Vector2(Meet.SIGN)+Vector2(0.5,0)).x
	if str(app.view.focused_label)!=FishUI.POINT:check(absf((mine.rect as Rect2).get_center().x-anchor_x)<=40.0,"Sign label stays over the sign (%s)"%label)
	for entry:Dictionary in list:
		if entry==mine:continue
		check(not (mine.rect as Rect2).intersects(entry.rect),"「%s」 does not overlap 「%s」 (%s)"%[mine.title,entry.title,label])
	for panel:Dictionary in hud_panels():
		check(not pixels.intersects(panel.rect),"Sign label clear of HUD %s (%s) %s vs %s"%[panel.name,label,str(pixels),str(panel.rect)])
		check(not Rect2(sign_box()).intersects(panel.rect),"Sign clear of HUD %s (%s)"%[panel.name,label])
	var waters:=Rect2(pixel_box(FishUI.waters_rect(app.view)))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(waters),"Whole meet waters on screen (%s) %s"%[label,str(waters)])
	for panel:Dictionary in hud_panels():
		check(not waters.intersects(panel.rect),"Meet waters clear of HUD %s (%s)"%[panel.name,label])
	# The board prompt never covers my own bobber.
	if person().has("fishing"):
		var bobber:=Rect2(app.view.screen(Vector2(float(person().fishing.x),float(person().fishing.y))),Vector2(32,32))
		check(not (mine.rect as Rect2).intersects(bobber),"Sign label clear of my bobber (%s) %s vs %s"%[label,str(mine.rect),str(bobber)])
	# Every label stays off the buoys while they are drawn.
	if FishUI.waters_marked(app.session.snapshot):
		for p:Vector2 in FishUI.buoy_points(app.view):
			for entry:Dictionary in list:
				check(not Rect2(p-Vector2(4,4),Vector2(8,8)).intersects(entry.rect),"Label 「%s」 clear of a buoy (%s)"%[entry.title,label])

func friend(index:int,at:Vector2)->String:
	var token:="fishmeet-scene-friend-%d"%index
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

## A teammate records one fish (PRESET clock jump to the bite).
func friend_catch(token:String,cell:Vector2i)->Dictionary:
	friend_act(token,"fish_start",cell,"")
	w.state.time=float((w.state.players[token] as Dictionary).fishing.ready)+0.1
	return friend_act(token,"fish_catch",cell,"")

# ------------------------------------------------------------------ flows --

func size_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	w.state.erase("fish_meet")  # PRESET fresh activity
	for token in w.state.players:
		(w.state.players[token] as Dictionary).erase("fish_meet")
		(w.state.players[token] as Dictionary).erase("fishing")
	for token in friends:
		w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y
	app._select_tool("hoe")
	w.state.board=true  # PRESET
	w.state.picnic=false  # PRESET
	await refresh()
	await stand(FISH_SPOT)
	check(not FishUI.on_field(app.session.snapshot),"No notice board before the picnic (%s)"%tag)
	var has_label:=false
	for entry:Dictionary in placements():
		if str(entry.id)==FishUI.POINT:has_label=true
	check(not has_label and str(app.view.interaction_focus())!=FishUI.POINT,"No sign label or focus before the picnic (%s)"%tag)
	var before:Image=await shot("world_before_picnic")
	w.state.picnic=true  # PRESET
	await refresh()
	await stand(FISH_SPOT)
	check(FishUI.on_field(app.session.snapshot),"Notice board after the picnic (%s)"%tag)
	var after:Image=await shot("world_unlocked")
	var diff:=box_difference(before,after,sign_box())
	print("NOTE %s: sign box %s changed %.0f%% vs before the picnic"%[tag,str(sign_box()),diff*100.0])
	check(diff>=0.2,"Notice board drawn at its cell (%.0f%% changed) %s"%[diff*100.0,tag])
	check(buoys_seen(after)==0 and buoys_seen(before)==0,"No buoys without a round (%s): %d"%[tag,buoys_seen(after)])
	check(str(app.view.focused_label)==FishUI.POINT,"Sign focused from the shore spot (%s)"%tag)
	labels_ok("unlocked "+tag)
	# Panel idle via the interact path at the sign.
	await stand(SIGN_SPOT)
	check(str(app.view.interaction_focus())==FishUI.POINT,"Sign focused from below (%s)"%tag)
	app._interact()
	await settle()
	check(panel_open(),"Interact at the sign opens 河岸釣魚會 (%s)"%tag)
	if not panel_open():return
	await shot("panel_idle")
	panel_fits("idle "+tag)
	await press("FishMeetStart")
	var round_id:=int(own().get("round",0))
	check(bool(own().get("active",false)) and bool(own().get("joined",false)),"Round started (%s)"%tag)
	app._close_modal()
	# I stand on the shore and cast into the marked waters (real Session path).
	await stand(FISH_SPOT)
	app._select_tool("fish")
	app.session.rates[1].clear()
	app.session.perform("fish_start",CAST,"")
	await refresh()
	check(person().has("fishing"),"My cast is out (%s)"%tag)
	var buddy:=friend(0,SPOTS[0])  # joins within reach of the sign, then walks north
	friend_act(buddy,"fish_meet_join",Meet.SIGN,str(round_id))
	friend(0,BUDDY_SPOT)
	friend_act(buddy,"fish_start",BUDDY_CAST,"")
	await refresh()
	var round_image:Image=await shot("world_round")
	var seen:=buoys_seen(round_image)
	print("NOTE %s buoys seen %d / 6, rope pixels %d"%[tag,seen,rope_pixels(round_image)])
	check(seen>=5,"Buoys mark the meet waters during the round (%s): %d"%[tag,seen])
	check(rope_pixels(round_image)>=20,"Dashed rope drawn along the waters (%s): %d"%[tag,rope_pixels(round_image)])
	print("NOTE %s rope-coloured pixels without a round %d"%[tag,rope_pixels(after)])
	check(rope_pixels(after)*10<rope_pixels(round_image),"Rope only during the round (%s): %d vs %d"%[tag,rope_pixels(after),rope_pixels(round_image)])
	labels_ok("round "+tag)
	# The unfocused board label shows the progress (read from the buddy's spot, >3.2 away).
	check(FishUI.sign_title(app.session.snapshot,false)=="河岸釣魚會 0／12","Round label text 河岸釣魚會 0／12 (%s)"%tag)
	# Reduced motion: two frames apart, the buoys do not move.
	app.view.reduced_motion=true
	var still_a:Image=await shot("world_round_reduced")
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var still_b:Image=root.get_texture().get_image()
	var moved:=0.0
	for p:Vector2 in FishUI.buoy_points(app.view):moved=maxf(moved,box_difference(still_a,still_b,pixel_box(Rect2(p-Vector2(5,6),Vector2(10,12)))))
	check(moved<=0.01,"Buoys static with reduced motion (%s): %.2f"%[tag,moved])
	# HUD tracker (crop of the round frame).
	check(str(app.objective.text).begins_with("河岸釣魚會 記錄 0 / 12\n魚種 0 / 4 · 剩 "),"HUD tracker text during the round (%s): %s"%[tag,app.objective.text])
	var tracker:=app.preview_tracker as Control
	if tracker!=null and round_image!=null:
		var rect:=Rect2i(tracker.get_global_rect().grow(4))
		rect=rect.intersection(Rect2i(Vector2i.ZERO,round_image.get_size()))
		save_image(round_image.get_region(rect),"hud_tracker")
		for panel:Dictionary in hud_panels():
			if panel.name==tracker.name:continue
			check(not tracker.get_global_rect().intersects(panel.rect),"Tracker clear of HUD %s (%s)"%[panel.name,tag])
		var objective:=app.objective as Label
		check(objective.get_visible_line_count()>=objective.get_line_count() and tracker.get_global_rect().grow(0.5).encloses(objective.get_global_rect()),"Tracker text whole (%s)"%tag)
	# My catch + two teammate catches: species partly recorded.
	w.state.time=float(person().fishing.ready)+0.1  # PRESET clock
	app.session.rates[1].clear()
	app.session.perform("fish_catch",CAST)
	await refresh()
	check(int(own().get("records",0))==1,"My catch recorded (%s)"%tag)
	w.state.time=float((w.state.players[buddy] as Dictionary).fishing.ready)+0.1
	friend_act(buddy,"fish_catch",BUDDY_CAST,"")
	friend_catch(buddy,BUDDY_CAST)
	await stand(SIGN_SPOT)
	app._fishmeet_menu()
	await settle()
	check(int(own().get("records",0))==3 and int(own().get("species_count",0))<4,"Three records, species partly recorded (%s): %d kinds"%[tag,int(own().get("species_count",0))])
	await shot("panel_mid")
	panel_fits("mid "+tag)
	app._close_modal()
	# Eight participants.
	for index in range(1,7):
		var token:=friend(index,SPOTS[index-1])
		friend_act(token,"fish_meet_join",Meet.SIGN,str(round_id))
	await refresh()
	check(int(own().get("joined_count",0))==8,"Eight joined (%s)"%tag)
	app._fishmeet_menu()
	await settle()
	await shot("panel_active_8")
	panel_fits("8 participants "+tag)
	check(control("FishMeetPeople")!=null and control("FishMeetPeople").get_child_count()==8,"Eight rows (%s)"%tag)
	# Finish by time.
	app._close_modal()
	w.state.time=float(w.state.fish_meet.ends)+0.1  # PRESET time
	check(w.step(1.0,true),"World tick ends the round (%s)"%tag)
	await refresh()
	app._fishmeet_menu()
	await settle()
	check(label_text("FishMeetLast").begins_with("第 %d 輪 · 時間到 · 記錄 3 / 12"%round_id),"Time-out result shown (%s): %s"%[tag,label_text("FishMeetLast")])
	var time_tickets:=int(own().get("tickets",0))
	check(time_tickets==Meet.tickets_for(int(own().last.species),3) and label_text("FishMeetRecord").begins_with("紀念票 %d 張 · 參加 1 場"%time_tickets),"Record shown (%s): %s"%[tag,label_text("FishMeetRecord")])
	await shot("panel_result_time")
	panel_fits("result time "+tag)
	app._close_modal()
	# Second round to the goal: 12 records, all four kinds, 3 tickets each.
	w.state.time=float(w.state.fish_meet.ready)+0.1  # PRESET: cooldown over
	for token in friends:(w.state.players[token] as Dictionary).erase("fishing")
	await stand(SIGN_SPOT)
	app._fishmeet_menu()
	await settle()
	await press("FishMeetStart")
	var goal_round:=int(own().get("round",0))
	check(goal_round==round_id+1 and bool(own().get("active",false)),"Second round started (%s)"%tag)
	app._close_modal()
	friend(0,SPOTS[0])
	friend_act(buddy,"fish_meet_join",Meet.SIGN,str(goal_round))
	friend(0,BUDDY_SPOT)
	for i in range(Meet.GOAL):
		if not bool(w.state.fish_meet.get("active",false)):break
		friend_catch(buddy,BUDDY_CAST)
	await refresh()
	app._fishmeet_menu()
	await settle()
	var last:Dictionary=own().get("last",{})
	check(str(last.get("reason",""))=="goal" and int(last.get("records",0))==12 and int(last.get("tickets",0))==3,"Goal finish with 3 tickets (%s): %s"%[tag,str(last)])
	check(label_text("FishMeetLast")=="第 %d 輪 · 記滿 12 筆 · 記錄 12 / 12 · 魚種 4 / 4"%goal_round and label_text("FishMeetLastTickets")=="2 人參加 · 每人 3 張紀念票","Goal result lines (%s): %s / %s"%[tag,label_text("FishMeetLast"),label_text("FishMeetLastTickets")])
	check(int(own().get("tickets",0))==time_tickets+3,"My tickets add 3 (%s)"%tag)
	await shot("panel_result_goal")
	panel_fits("result goal "+tag)
	app._close_modal()
	app._select_tool("hoe")
	for token in friends:
		w.state.players[token].x=AWAY.x;w.state.players[token].y=AWAY.y
		(w.state.players[token] as Dictionary).erase("fishing")

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/河岸釣魚會預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("fishing-meet-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.sound.standard_fishing=false
	if app.session.host(0,"釣魚會旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=20,"10 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
