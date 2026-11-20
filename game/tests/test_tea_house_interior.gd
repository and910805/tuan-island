extends SceneTree
## 貓空茶屋室內 (Maokong tea house interior): native + headless regression.
##
## Run headless for the logic checks, or natively (no --headless) for the screenshot and music checks:
##   godot --path game --script res://tests/test_tea_house_interior.gd -- [--wide] [--capture-dir=DIR]
## --wide renders 1280x800 instead of 1024x640. --capture-dir= saves the PNGs (native only); without it a
## native run still renders every frame and checks it is not blank, it just does not keep the files.
## Output: TEA_HOUSE_INTERIOR_TESTS checks=N failures=M (exit code 1 on any failure or zero checks).
##
## Contract under test (World.TEA_HOUSE_INTERIOR): REGION="maokong", ROOM=Rect2i(56,17,15,11),
## DOOR=(19,22) outdoors, EXIT=(63,27) indoors, PORTAL, SIT, SEAT_KEY, FURNITURE, SEAT_FEET, inside(person).
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * an isolated host save under user:// (deleted at the end);
##  * the fixture copied from test_tea_revisit_scene.gd: chapter one flags, a comparison-complete tea record,
##    and a completed 茶罐大單 (jars 3+3, light 4 / deep 2 in spring) with state.festival_story_open=true, so
##    TeaRevisit.house_open() is true. The fixture is saved and reloaded once to prove the save accepts it;
##  * players are teleported by writing region/x/y (the same preset the other scene tests use).
## REALLY EXERCISED:
##  * app._interact() at the outer door, beside the chairs and at the inner exit (the playable path), with a
##    server-side World.act fallback only so later checks still run after a reported failure;
##  * World.act for the wrong-direction, far-away and extra-argument refusals, chair occupancy, and exit;
##  * World.move_player for furniture collision, aisle walking, standing up from a chair and walking away;
##  * World.save + JSON read + World.load_world + World.add_player (the rejoin path) for the seat/position/access
##    persistence checks.
const World=preload("res://scripts/world.gd")
const House=World.TEA_HOUSE_INTERIOR
const TR=World.TEA_REVISIT
const Tea=preload("res://scripts/tea_ceramics.gd")
const Music=preload("res://scripts/scene_music.gd")
const TILE:=32.0
const OVERVIEW_ZOOM:=1.4
## Long enough for the travel-arrival ribbon and any modal to fade before a frame is grabbed.
const FADE_WAIT:=0.5
const TEA_TRACK:="maokong_tea_house"
const GUEST:="tea-house-guest"
const DIRECTIONS:=[Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]

var app
var w
var me:String=""
var path:String=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var native:=false
var finished:=false
var shots:=0
var request:=0
var overview_room_pixels:=Rect2()
## Quest note area outdoors in Maokong, read once before entering; the compact state is compared with it.
var outdoor_quest_area:=0.0
var outdoor_quest_width:=0.0
var outdoor_quest_visibility:=Vector2i.ZERO

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("TEA_HOUSE_INTERIOR_TESTS checks=%d failures=%d"%[checks,failures])
	print("TEA_HOUSE_INTERIOR_SHOTS native=%s shots=%d"%[str(native),shots])
	quit(1 if failures>0 or checks==0 else 0)

# ------------------------------------------------------------------ helpers --

func person(token:String="")->Dictionary:
	return w.state.players[me if token.is_empty() else token]

func here(token:String="")->Vector2:
	var p:Dictionary=person(token)
	return Vector2(p.x,p.y)

func cell_of(token:String="")->Vector2i:
	var v:=here(token)
	return Vector2i(floori(v.x),floori(v.y))

func centre(c:Vector2i)->Vector2:
	return Vector2(c)+Vector2(0.5,0.5)

func seat_of(token:String="")->String:
	return str(person(token).get(House.SEAT_KEY,""))

func seat_name(chair:Vector2i)->String:
	return "%s:%d,%d"%[House.SIT,chair.x,chair.y]

func inside(token:String="")->bool:
	return House.inside(person(token))

## Unique request id per call so World.act never replays a cached receipt.
func act(token:String,label:String,action:String,cell:Vector2i,extra:String="")->bool:
	request+=1
	return bool(w.act(token,"thi-%d-%s"%[request,label.left(40)],action,cell,extra).ok)

func solid(c:Vector2i)->bool:
	w.switch_region(House.REGION)
	var result:bool=w.blocked(c)
	w.switch_region(World.REGIONS.HOME)
	return result

func standable(v:Vector2)->bool:
	w.switch_region(House.REGION)
	var result:bool=w.can_stand(v)
	w.switch_region(World.REGIONS.HOME)
	return result

func put(token:String,v:Vector2,region:String=House.REGION)->void:
	var p:Dictionary=person(token)
	p.region=region  # PRESET
	p.x=v.x;p.y=v.y  # PRESET

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func close_modal()->void:
	if is_instance_valid(app.modal):app._close_modal()

## Hides whatever is still fading: the toast and the travel-arrival ribbon.
func clear_overlays()->void:
	hide_toast()
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:(ribbon as CanvasItem).hide()

func refresh()->void:
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

## Teleports the local player and snaps the view to it, as test_tea_revisit_scene does.
func place_me(v:Vector2)->void:
	put(me,v)
	await refresh()
	var view=app.view
	var own:String=app.session.own_id
	if view.goals.has(own):
		view.starts[own]=view.goals[own]
		view.display_positions[own]=view.goals[own]
	view.stride_stop.erase(own)
	view.facings[own]=Vector2i.DOWN
	clear_overlays()
	await settle()

## The playable path: the interact key.
func interact()->void:
	app.session.rates[1].clear()
	if "action_clock" in app:app.action_clock=0
	app._interact()
	await settle()
	await refresh()

func save_world()->bool:
	w.switch_region(World.REGIONS.HOME)  # World.save refuses while a regional projection is active.
	return w.save()

func saved_players()->Dictionary:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("players") is Dictionary:return parsed.players
	return {}

# --------------------------------------------------------------- movement ----

## Breadth-first walkable cells inside the room: cell -> previous cell (the start maps to itself).
func reachable(start:Vector2i)->Dictionary:
	var came:Dictionary={start:start}
	var queue:Array=[start]
	var index:=0
	while index<queue.size():
		var c:Vector2i=queue[index]
		index+=1
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if came.has(n) or not House.ROOM.has_point(n) or not standable(centre(n)):continue
			came[n]=c
			queue.append(n)
	return came

## Walks the local player along the BFS route with real World.move_player steps.
func walk_route(came:Dictionary,goal:Vector2i)->bool:
	if not came.has(goal):return false
	var route:Array=[]
	var cursor:Vector2i=goal
	while came[cursor]!=cursor:
		route.push_front(cursor)
		cursor=came[cursor]
	for stop:Vector2i in route:
		var target:=centre(stop)
		for step in range(80):
			var delta:=target-here()
			if delta.length()<0.12:break
			w.move_player(me,delta.normalized(),0.03)
	return cell_of()==goal

func stand_up(token:String,world=null)->bool:
	var target=w if world==null else world
	for d:Vector2 in DIRECTIONS:
		target.move_player(token,d,0.1)
		if str(target.state.players[token].get(House.SEAT_KEY,"")).is_empty():break
	return str(target.state.players[token].get(House.SEAT_KEY,"")).is_empty()

## After standing up the player must be on a standable spot and able to walk off it.
func can_walk_away(token:String,world=null)->bool:
	var target=w if world==null else world
	var p:Dictionary=target.state.players[token]
	var origin:=Vector2(p.x,p.y)
	for d:Vector2 in DIRECTIONS:
		p.x=origin.x;p.y=origin.y
		for i in range(4):target.move_player(token,d,0.1)
		if Vector2(p.x,p.y).distance_to(origin)>0.2:
			p.x=origin.x;p.y=origin.y
			return true
	p.x=origin.x;p.y=origin.y
	return false

# ------------------------------------------------------------------ screen ---

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func overview_chair_box(chair:Vector2i)->Rect2i:
	var scale:=overview_room_pixels.size/Vector2(House.ROOM.size)
	var entry:=overview_room_pixels.position+Vector2(chair-House.ROOM.position)*scale
	var bounds:=Rect2(entry-Vector2(4,18),scale+Vector2(8,20))
	return Rect2i(Vector2i(bounds.position.round()),Vector2i(bounds.size.round()))

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

## Native frame grab. Waits for modal / arrival fades first. Returns null in headless.
func shot(step:String)->Image:
	if not native:return null
	close_modal()
	await create_timer(FADE_WAIT).timeout
	clear_overlays()
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"Non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	shots+=1
	if not output.is_empty():
		var file:=output.path_join("%s_%s.png"%[tag,step])
		check(image.save_png(file)==OK,"Screenshot saved %s_%s"%[tag,step])
		print("TEA_HOUSE_INTERIOR_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

## Whole-room overview: zoom about 1.4, camera centred on the room, then verified to fit the viewport.
func overview(step:String)->Image:
	var view=app.view
	var previous_zoom:float=view.zoom
	view.zoom=OVERVIEW_ZOOM
	view.set_process(false)  # hold the camera still while the frame is taken
	var middle:=Vector2(House.ROOM.position)+Vector2(House.ROOM.size)/2.0
	view.update_camera(middle,true)
	view.queue_redraw()
	clear_overlays()
	await settle()
	var room_px:=view_to_pixels(Rect2(app.view.screen(Vector2(House.ROOM.position)),Vector2(House.ROOM.size)*TILE))
	overview_room_pixels=room_px
	if inside():
		hud_state("Overview "+step,true)
		furniture_clear_check("Overview "+step)
	var visible:=Rect2(Vector2.ZERO,Vector2(root.size))
	check(visible.encloses(room_px),"The whole room fits the %s view at zoom %.1f: %s"%[tag,OVERVIEW_ZOOM,str(room_px)])
	var offset:=room_px.get_center()-visible.get_center()
	check(absf(offset.x)<=60.0 and absf(offset.y)<=80.0,"The room is centred in the view (%s): offset %s"%[tag,str(offset)])
	for panel:Dictionary in hud_panels():
		if room_px.intersects(panel.rect):print("NOTE %s: HUD panel %s overlaps the overview room"%[tag,panel.name])
	var image:Image=await shot(step)
	if image!=null and not image.is_empty():
		var box:=Rect2i(Vector2i(room_px.position.round()),Vector2i(room_px.size.round())).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		check(colour_variety(image.get_region(box))>=8,"The room itself is painted, not blank (%s_%s)"%[tag,step])
	view.zoom=previous_zoom
	view.set_process(true)
	return image

## ---- HUD contract (compact Maokong HUD) ----
## Inside the tea house: the build/farm tool strip and its hint are hidden, the quest note stays reachable in a
## compact form. Outdoors (Maokong, before entering and after leaving): the strip, hint and full note are back.
## Only node visibility, geometry and sizes are asserted; no label copy is read.

func quest_note()->Control:
	var named:=app.hud.get_node_or_null("QuestNote") as Control
	return named if named!=null else (app.preview_tracker as Control)

func quest_buttons(node:Node)->Array:
	var found:=[]
	for child in node.get_children():
		if child is BaseButton:found.append(child)
		found.append_array(quest_buttons(child))
	return found

func quest_area(note:Control)->float:
	return note.get_global_rect().size.x*note.get_global_rect().size.y

## Furniture tiles (as drawn at the current camera) that the quest note covers.
func furniture_under_note(note:Control)->Array:
	var covered:=[]
	var screen:=Rect2(Vector2.ZERO,Vector2(root.size))
	var note_rect:=note.get_global_rect()
	for cell:Vector2i in House.FURNITURE:
		var px:=view_to_pixels(Rect2(app.view.screen(Vector2(cell)),Vector2(TILE,TILE)))
		if not screen.intersects(px):continue  # not on screen at all, so nothing can hide it
		if note_rect.intersects(px):covered.append("%s@%s"%[str(House.FURNITURE[cell]),str(cell)])
	return covered

func furniture_clear_check(label:String)->void:
	var note:=quest_note()
	if note==null or not note.is_visible_in_tree():return  # nothing drawn, nothing covers the room
	var covered:=furniture_under_note(note)
	check(covered.is_empty(),"%s (%s): the quest note %s covers no room furniture: %s"%[label,tag,str(note.get_global_rect()),str(covered)])

func hud_state(label:String,indoors:bool)->void:
	var toolbar:=app.preview_toolbar as Control
	var hint:=app.selected_label as Control
	var note:=quest_note()
	var screen:=Rect2(Vector2.ZERO,Vector2(root.size)).grow(1.0)
	check(is_instance_valid(toolbar) and is_instance_valid(hint),"%s (%s): the toolbar and the tool hint exist"%[label,tag])
	check(note!=null and is_instance_valid(note),"%s (%s): the quest note exists"%[label,tag])
	if not is_instance_valid(toolbar) or not is_instance_valid(hint) or note==null or not is_instance_valid(note):return
	# The quest note is reachable in both states.
	check(note.is_visible_in_tree(),"%s (%s): the quest note is visible in the tree"%[label,tag])
	check(note.size.x>0 and note.size.y>0 and screen.encloses(note.get_global_rect()),"%s (%s): the quest note sits fully inside the viewport: %s"%[label,tag,str(note.get_global_rect())])
	var usable:=false
	for button:BaseButton in quest_buttons(note):
		if button.is_visible_in_tree() and not button.disabled and button.size.x>0 and button.size.y>0 and button.mouse_filter!=Control.MOUSE_FILTER_IGNORE:usable=true
	check(usable,"%s (%s): the quest note keeps a clickable control"%[label,tag])
	if indoors:
		check(not toolbar.is_visible_in_tree(),"%s (%s): the tool strip is hidden inside the tea house"%[label,tag])
		check(not hint.is_visible_in_tree(),"%s (%s): the tool hint is hidden inside the tea house"%[label,tag])
		var shown:=0
		for button in app.tool_buttons:
			if (button as Control).is_visible_in_tree():shown+=1
		check(shown==0,"%s (%s): no build/farm tool button is visible inside (%d)"%[label,tag,shown])
		if outdoor_quest_area>0.0:
			check(quest_area(note)<outdoor_quest_area-1.0,"%s (%s): the quest note is compact inside (%.0f px² vs %.0f outdoors)"%[label,tag,quest_area(note),outdoor_quest_area])
	else:
		check(toolbar.is_visible_in_tree() and toolbar.size.x>0 and toolbar.size.y>0,"%s (%s): the tool strip is visible outdoors"%[label,tag])
		check(hint.is_visible_in_tree(),"%s (%s): the tool hint is visible outdoors"%[label,tag])
		check(screen.encloses(toolbar.get_global_rect()),"%s (%s): the tool strip sits inside the viewport outdoors: %s"%[label,tag,str(toolbar.get_global_rect())])
		var any_tool:=false
		for button in app.tool_buttons:any_tool=any_tool or (button as Control).is_visible_in_tree()
		check(any_tool,"%s (%s): at least one tool button is visible outdoors"%[label,tag])
		var next:=note.find_child("TrackerNext",true,false) as Button
		var visibility:=Vector2i(int(app.objective.visible),int(next!=null and next.visible))
		if outdoor_quest_area<=0.0:
			outdoor_quest_area=quest_area(note)  # first outdoor reading is the normal-state baseline
			outdoor_quest_width=note.size.x
			outdoor_quest_visibility=visibility
		else:
			# The container can drop surplus height when it reflows; its width and controls must return.
			check(is_equal_approx(note.size.x,outdoor_quest_width),"%s (%s): the quest note restores its outdoor width"%[label,tag])
			check(visibility==outdoor_quest_visibility,"%s (%s): the outdoor objective and guide visibility are restored"%[label,tag])

## Opens a real modal, checks it took over, closes it and re-checks the HUD state from scratch.
func modal_roundtrip(label:String,indoors:bool)->void:
	app.session.rates[1].clear()
	app._journal()
	await settle()
	check(is_instance_valid(app.modal),"%s (%s): a modal opened for the round trip"%[label,tag])
	close_modal()
	await refresh()
	check(not is_instance_valid(app.modal),"%s (%s): the modal is closed again"%[label,tag])
	clear_overlays()
	check(inside()==indoors,"%s (%s): the modal does not change where the player is"%[label,tag])
	hud_state(label+" after modal",indoors)
	if indoors:furniture_clear_check(label+" after modal")

func music_check(label:String)->void:
	if not native:return
	var file:="res://assets/music/%s.ogg"%TEA_TRACK
	check(Music.TEA_HOUSE_TRACK==TEA_TRACK,"The scene music names the track %s"%TEA_TRACK)
	if not ResourceLoader.exists(file) or app.sound==null:
		print("NOTE %s: %s is not packaged here; music check skipped"%[label,TEA_TRACK])
		return
	# The room is far from the outdoor table, so an outdoor zone would switch away after the dwell time.
	var waited:=0.0
	while waited<Music.ZONE_DWELL_SECONDS+1.8:
		await create_timer(0.25).timeout
		waited+=0.25
	check(app.sound.music.scene_id==TEA_TRACK and app.sound.music.current.playing,"%s: the %s track plays (scene %s)"%[label,TEA_TRACK,str(app.sound.music.scene_id)])

# ------------------------------------------------------------------- flows ---

func contract_flow()->void:
	check(House.REGION=="maokong" and House.ROOM==Rect2i(56,17,15,11),"The interior lives in the Maokong region at (56,17,15,11)")
	check(House.DOOR==Vector2i(19,22) and House.EXIT==Vector2i(63,27),"The outer door is (19,22) and the inner exit (63,27)")
	check(House.PORTAL=="maokong_tea_house_portal" and House.SIT=="maokong_tea_house_sit","Portal and sit action names match the contract")
	check(not str(House.SEAT_KEY).is_empty() and House.SEAT_KEY!=House.PORTAL and House.SEAT_KEY!=House.SIT,"The seat key is a distinct field name")
	check(House.ROOM.has_point(House.EXIT) and not House.ROOM.has_point(House.DOOR),"The exit is inside the room and the door outside it")
	check(Vector2(House.DOOR).distance_to(Vector2(TR.HOUSE_SITE))<=1.5,"The outer door is beside the existing tea display table")
	check(House.FURNITURE.size()>=12,"At least 12 furniture cells (%d)"%House.FURNITURE.size())
	var kinds:={}
	for kind in House.FURNITURE.values():kinds[str(kind)]=true
	check(kinds.size()>=4,"At least four kinds of furniture (%s)"%str(kinds.keys()))
	check(House.SEAT_FEET.size()>=4,"At least four chairs (%d)"%House.SEAT_FEET.size())
	var feet:={}
	for chair:Vector2i in House.SEAT_FEET:
		feet[House.SEAT_FEET[chair]]=true
		check(House.FURNITURE.has(chair) and House.ROOM.has_point(House.SEAT_FEET[chair]),"Chair %s is furniture with a foot tile inside the room"%str(chair))
	check(feet.size()==House.SEAT_FEET.size(),"Every chair has its own foot tile")
	var probe:={"region":House.REGION,"x":centre(House.DOOR).x,"y":centre(House.DOOR).y}
	check(not House.inside(probe),"inside() is false at the outer door")
	probe.x=centre(House.EXIT+Vector2i.UP).x;probe.y=centre(House.EXIT+Vector2i.UP).y
	check(House.inside(probe),"inside() is true by the inner exit")

func seed_fixture()->void:
	# Copied from test_tea_revisit_scene.reset(): the known-valid revisit fixture.
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	w.state.time=30.0  # PRESET (day 1, spring)
	var rec:Dictionary=Tea.FRESH.duplicate(true)
	for field in ["intro","potter","potter_story","reused","tea_discussed"]:rec[field]=true  # PRESET
	rec.trials={"jar":true,"fiber":true}  # PRESET
	rec.comparison_complete=true  # PRESET
	w.state.tea_ceramics.players[me]=rec  # PRESET
	w.state[TR.STATE_KEY]={"jars":{"tea_returned_jar":3,"tea_worn_jar":3},"filled":{"light":4,"deep":2},"day":1,"completed":true,"done_day":1,"claimed":{}}  # PRESET
	w.state.festival_story_open=true  # PRESET
	check(TR.house_open(w.state),"The fixture opens the tea house (completed revisit and festival)")
	check(save_world(),"The fixture saves")
	var reloaded:=World.new()
	check(reloaded.load_world(path) and TR.house_open(reloaded.state),"The fixture reloads and keeps the tea house open")

## The gate is the existing TeaRevisit.house_open: it needs the festival AND the finished order.
func gate_flow()->void:
	await place_me(centre(House.DOOR))
	check(not inside() and cell_of()==House.DOOR,"The test begins outdoors on the door tile")
	w.state.festival_story_open=false  # PRESET
	check(not TR.house_open(w.state),"Without the festival the tea house is closed")
	check(not act(me,"closed-festival",House.PORTAL,House.DOOR) and not inside(),"The server refuses the door before the festival opens")
	await interact()
	close_modal()
	check(not inside() and cell_of()==House.DOOR,"Interacting at the door does nothing before the festival opens")
	w.state.festival_story_open=true  # PRESET
	var record:Dictionary=w.state[TR.STATE_KEY]
	w.state.erase(TR.STATE_KEY)  # PRESET (restored below)
	check(not TR.house_open(w.state),"Without the finished tea order the tea house is closed")
	check(not act(me,"closed-order",House.PORTAL,House.DOOR) and not inside(),"The server refuses the door before the tea order is done")
	await interact()
	close_modal()
	check(not inside() and cell_of()==House.DOOR,"Interacting at the door does nothing before the tea order is done")
	w.state[TR.STATE_KEY]=record  # PRESET (restored)
	check(TR.house_open(w.state),"Both conditions open the tea house again")
	await refresh()

func outdoor_flow()->void:
	await place_me(centre(House.DOOR))
	check(not act(me,"out-exit",House.PORTAL,House.EXIT) and not inside(),"Outdoors the interior exit cannot be addressed (wrong direction)")
	var first:Vector2i=House.SEAT_FEET.keys()[0]
	check(not act(me,"out-sit",House.SIT,first) and seat_of(me)=="" and not inside(),"Outdoors a chair cannot be used")
	check(not act(me,"out-extra",House.PORTAL,House.DOOR,"extra") and not inside(),"The portal takes no extra argument")
	check(not act(me,"out-sit-extra",House.SIT,first,"extra") and seat_of(me)=="","Sitting takes no extra argument")
	put(me,centre(House.DOOR+Vector2i(0,12)))
	check(not act(me,"out-far",House.PORTAL,House.DOOR) and not inside(),"A far-away player cannot use the door")
	await place_me(centre(House.DOOR))
	check(str(app.view.interaction_focus())==House.PORTAL,"The door prompt focuses the portal action: %s"%str(app.view.interaction_focus()))
	hud_state("Outdoors at the door",false)
	await modal_roundtrip("Outdoors at the door",false)
	await place_me(centre(House.DOOR))
	await shot("door_outdoors")

func entry_flow()->void:
	await interact()
	var entered:=inside()
	check(entered,"Interacting at the outer door walks the player into the tea house")
	if not entered:
		check(act(me,"enter-fallback",House.PORTAL,House.DOOR),"Server fallback entry")
		await refresh()
	check(person().region==House.REGION and House.ROOM.has_point(cell_of()),"The player is inside the room in the shared Maokong region")
	check(standable(here()),"The arrival spot is standable")
	check(here().distance_to(centre(House.EXIT))<=4.0,"The player arrives beside the inner exit")
	check(not act(me,"in-door",House.PORTAL,House.DOOR) and inside(),"Inside, the outer door is out of reach (wrong direction)")
	check(not act(me,"in-display",TR.HOUSE_DISPLAY,TR.HOUSE_SITE) and not act(me,"in-reclaim",TR.HOUSE_RECLAIM,TR.HOUSE_SITE),"Distance keeps the outdoor display table out of reach from inside")
	await refresh()
	hud_state("Just inside the tea house",true)
	furniture_clear_check("Just inside the tea house")
	var note:=quest_note()
	if note!=null:
		var heading:=note.find_child("TrackerHeading",true,false) as Button
		var guide:=note.find_child("TrackerNext",true,false) as Button
		check(heading!=null and guide!=null,"The compact tracker retains the heading and guide")
		if heading!=null and guide!=null:
			check(not app.objective.visible and not guide.visible,"The tracker starts collapsed indoors")
			heading.pressed.emit()
			check(app.objective.visible and guide.visible,"Clicking the heading immediately reveals the objective and guide")
			heading.pressed.emit()
			check(not app.objective.visible and not guide.visible,"Clicking the heading again clears the view")
	await modal_roundtrip("Inside the tea house",true)
	await music_check("Inside the tea house")
	if native:check(app.sound.ambience_kind.is_empty() and not app.sound.ambience.playing,"The tea house has no outdoor wind bed")

func furniture_flow()->void:
	var start:Vector2i=House.EXIT+Vector2i.UP
	check(not solid(House.EXIT) and standable(centre(start)),"The exit tile and the tile before it are walkable")
	check(solid(House.ROOM.position) and solid(Vector2i(House.ROOM.end.x-1,House.ROOM.position.y)),"The room walls block movement")
	check(not solid(House.DOOR) and standable(centre(House.DOOR)),"The outdoor door tile is still walkable terrain")
	check(solid(TR.HOUSE_SITE) and solid(TR.PACKER),"The existing outdoor table and packing bench still block")
	var came:=reachable(start)
	check(came.size()>=30,"A generous aisle network is walkable (%d cells)"%came.size())
	var solid_cells:Array=[]
	var solid_kinds:={}
	for cell:Vector2i in House.FURNITURE:
		var kind:=str(House.FURNITURE[cell])
		check(House.ROOM.has_point(cell) and cell!=House.EXIT and cell!=start,"Furniture %s at %s stays off the door path"%[kind,str(cell)])
		if solid(cell):
			solid_cells.append(cell)
			solid_kinds[kind]=int(solid_kinds.get(kind,0))+1
	check(solid_cells.size()>=8,"Tables, shelves and counters block movement (%d solid cells)"%solid_cells.size())
	var wide:=false
	for kind in solid_kinds:wide=wide or int(solid_kinds[kind])>=2
	check(wide,"At least one piece of furniture blocks more than one tile (%s)"%str(solid_kinds))
	for chair:Vector2i in House.SEAT_FEET:
		var feet:Vector2i=House.SEAT_FEET[chair]
		check(not solid(feet) and came.has(feet),"The foot tile %s of chair %s is on the aisle network"%[str(feet),str(chair)])
	# Walking into solid furniture from an aisle never enters it.
	var probes:=0
	for cell:Vector2i in solid_cells:
		var near:=Vector2i(-999,-999)
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			if came.has(cell+d):near=cell+d;break
		if near.x==-999:continue
		probes+=1
		put(me,centre(near))
		for i in range(12):w.move_player(me,Vector2(cell-near),0.1)
		check(cell_of()!=cell and not solid(cell_of()),"Walking into %s at %s is stopped (ended at %s)"%[str(House.FURNITURE[cell]),str(cell),str(cell_of())])
	check(probes>=6,"Collision was probed against several furniture cells (%d)"%probes)
	# Real aisle walking from the door to every chair.
	for chair:Vector2i in House.SEAT_FEET:
		put(me,centre(start))
		check(walk_route(came,House.SEAT_FEET[chair]),"The aisle leads from the exit to chair %s (ended at %s)"%[str(chair),str(cell_of())])
	put(me,centre(start))
	# Far from the exit the portal cannot be used.
	var far:=start
	for cell:Vector2i in came:
		if abs(cell.x-start.x)+abs(cell.y-start.y)>abs(far.x-start.x)+abs(far.y-start.y):far=cell
	put(me,centre(far))
	check(not act(me,"far-exit",House.PORTAL,House.EXIT) and inside(),"The exit cannot be used from across the room")
	await place_me(centre(start))

func sit_down(chair:Vector2i,real:bool)->void:
	var feet:Vector2i=House.SEAT_FEET[chair]
	await place_me(centre(feet))
	if real:
		await interact()
		var seated:=seat_of()==seat_name(chair)
		check(seated,"Pressing interact beside chair %s seats the player: %s"%[str(chair),seat_of()])
		if seated:return
		person().erase(House.SEAT_KEY)  # PRESET: undo whatever else was picked, then use the server path
		put(me,centre(feet))
	check(act(me,"sit-"+str(chair),House.SIT,chair),"The server seats the player at chair %s"%str(chair))

func seats_flow(empty_view:Image)->void:
	var chairs:Array=House.SEAT_FEET.keys()
	chairs.sort_custom(func(a:Vector2i,b:Vector2i):return a.x<b.x or (a.x==b.x and a.y<b.y))
	# A visitor walks in through the door independently.
	w.add_player(GUEST,"茶屋訪客")
	put(GUEST,centre(House.DOOR+Vector2i.DOWN))
	var owner_before:=here()
	check(not inside(GUEST),"The visitor starts outdoors")
	check(act(GUEST,"guest-enter",House.PORTAL,House.DOOR) and inside(GUEST),"The visitor enters through the door on their own")
	check(inside() and here()==owner_before,"The visitor entering does not move the owner")
	# Every chair works for the owner (the first two through the real interact key), is refused to a
	# visitor while taken, and is released by moving.
	for index in range(chairs.size()):
		var chair:Vector2i=chairs[index]
		var feet:Vector2i=House.SEAT_FEET[chair]
		await sit_down(chair,index<2)
		check(seat_of()==seat_name(chair),"The owner holds seat %s (%s)"%[str(chair),seat_of()])
		check(cell_of()==feet,"The owner stands on the foot tile %s of chair %s (at %s)"%[str(feet),str(chair),str(cell_of())])
		put(GUEST,centre(feet))
		var guest_spot:=here(GUEST)
		check(not act(GUEST,"taken-"+str(chair),House.SIT,chair) and seat_of(GUEST)=="" and here(GUEST)==guest_spot,"A visitor cannot take the occupied chair %s and does not move"%str(chair))
		check(seat_of()==seat_name(chair),"The refusal leaves the owner seated")
		check(stand_up(me),"Moving stands the owner up from chair %s"%str(chair))
		check(seat_of()=="" and standable(here()),"The owner is standable after leaving chair %s: %s"%[str(chair),str(here())])
		check(can_walk_away(me),"The owner can walk away from chair %s (not stuck)"%str(chair))
		check(act(GUEST,"freed-"+str(chair),House.SIT,chair) and seat_of(GUEST)==seat_name(chair),"The freed chair %s is usable by the visitor"%str(chair))
		check(stand_up(GUEST) and can_walk_away(GUEST),"The visitor stands up and walks away from chair %s"%str(chair))
	# Two different chairs held at once.
	var one:Vector2i=chairs[0]
	var two:Vector2i=chairs[1]
	await sit_down(one,true)
	put(GUEST,centre(House.SEAT_FEET[two]))
	check(act(GUEST,"guest-two",House.SIT,two) and seat_of(GUEST)==seat_name(two),"The visitor sits in a second chair at the same time")
	check(seat_of()==seat_name(one) and seat_of()!=seat_of(GUEST),"Both hold distinct seats")
	app.session.peers[2]=GUEST
	await refresh()
	var seated:Image=await overview("interior_seated")
	if seated!=null and empty_view!=null:
		for pair:Array in [[one,"owner"],[two,"visitor"]]:
			var chair:Vector2i=pair[0]
			var box:=overview_chair_box(chair)
			var changed:=box_difference(empty_view,seated,box)
			print("NOTE %s: %s seated frame differs %.0f%% at chair %s"%[tag,pair[1],changed*100.0,str(chair)])
			check(changed>=0.02,"The seated %s is drawn at chair %s (%.0f%% changed)"%[pair[1],str(chair),changed*100.0])

## Seats stay out of the save; positions, access and standing come back after a rejoin.
func persistence_flow()->void:
	var chairs:Array=House.SEAT_FEET.keys()
	chairs.sort_custom(func(a:Vector2i,b:Vector2i):return a.x<b.x or (a.x==b.x and a.y<b.y))
	var one:Vector2i=chairs[0]
	var two:Vector2i=chairs[1]
	check(seat_of()==seat_name(one) and seat_of(GUEST)==seat_name(two),"Both islanders are seated before the save")
	var live_me:=here()
	var live_guest:=here(GUEST)
	check(save_world(),"Save while both are seated")
	var rows:=saved_players()
	for token:String in [me,GUEST]:
		var row:Dictionary=rows.get(token,{})
		check(not row.is_empty() and not row.has(House.SEAT_KEY),"The save omits the seat marker for %s"%token)
		check(row.get("region")==House.REGION and House.inside(row),"The save keeps %s inside the tea house"%token)
	check(seat_of()==seat_name(one) and seat_of(GUEST)==seat_name(two),"Saving does not stand anyone up in the live room")
	var again:=World.new()
	check(again.load_world(path),"The saved island reloads")
	check(TR.house_open(again.state),"The tea house is still open after the reload")
	again.add_player(me,str(person().name))  # the rejoin path
	again.add_player(GUEST,"茶屋訪客")
	for token:String in [me,GUEST]:
		var back:Dictionary=again.state.players[token]
		check(not back.has(House.SEAT_KEY),"Rejoining leaves %s standing, not seated"%token)
		check(again.player_region(token)==House.REGION and House.inside(back),"Rejoining returns %s to the tea house interior"%token)
		again.switch_region(House.REGION)
		var ok:bool=again.can_stand(Vector2(back.x,back.y))
		again.switch_region(World.REGIONS.HOME)
		check(ok,"The rejoined %s is not stuck inside a chair or table at %s"%[token,str(Vector2(back.x,back.y))])
		check(can_walk_away(token,again),"The rejoined %s can walk away"%token)
	check(Vector2(again.state.players[me].x,again.state.players[me].y).distance_to(live_me)<=1.5 and Vector2(again.state.players[GUEST].x,again.state.players[GUEST].y).distance_to(live_guest)<=1.5,"Rejoined players stay by the chairs they used")
	# Access persists through the rejoin: leave and come back in the reloaded world.
	var back_me:Dictionary=again.state.players[me]
	back_me.x=centre(House.EXIT+Vector2i.UP).x
	back_me.y=centre(House.EXIT+Vector2i.UP).y
	check(again.act(me,"again-exit",House.PORTAL,House.EXIT).ok and not House.inside(back_me),"After the rejoin the exit still leads outdoors")
	check(again.act(me,"again-enter",House.PORTAL,House.DOOR).ok and House.inside(back_me),"After the rejoin the door still opens")

func exit_flow()->void:
	var start:Vector2i=House.EXIT+Vector2i.UP
	# The visitor keeps their chair while the owner leaves through the real exit.
	var guest_seat:=seat_of(GUEST)
	check(stand_up(me),"The owner stands up from the chair left over from the persistence checks")
	await place_me(centre(House.EXIT))
	check(inside(),"The owner is inside before leaving")
	check(str(app.view.interaction_focus())==House.PORTAL,"On the exit tile the prompt focuses the portal: %s"%str(app.view.interaction_focus()))
	await place_me(centre(start))
	hud_state("Seated then standing by the exit",true)
	furniture_clear_check("Standing by the exit")
	await modal_roundtrip("Before leaving",true)
	await place_me(centre(start))
	await interact()
	var left:=not inside()
	check(left,"Interacting at the inner exit returns the owner outdoors")
	if not left:
		check(act(me,"exit-fallback",House.PORTAL,House.EXIT),"Server fallback exit")
		await refresh()
	check(person().region==House.REGION and here().distance_to(centre(House.DOOR))<4.0 and standable(here()),"The owner is back beside the outer door on walkable ground (%s)"%str(here()))
	if native:check(app.sound.ambience_kind=="wind" and app.sound.ambience.playing,"The outdoor wind bed resumes on the mountain path")
	check(not act(me,"back-exit",House.PORTAL,House.EXIT),"Outdoors again, the interior exit cannot be addressed")
	check(inside(GUEST) and not guest_seat.is_empty() and seat_of(GUEST)==guest_seat,"The visitor inside keeps their chair while the owner leaves")
	hud_state("Straight after leaving",false)
	await modal_roundtrip("After leaving",false)
	await place_me(centre(House.DOOR))
	hud_state("Back at the door",false)
	await shot("back_outdoors")
	# Re-enter through the playable door, sit, and leave while holding the chair: the seat is released.
	await interact()
	check(inside(),"The owner can come back in")
	hud_state("Re-entered",true)
	furniture_clear_check("Re-entered")
	var chairs:Array=House.SEAT_FEET.keys()
	chairs.sort_custom(func(a:Vector2i,b:Vector2i):return a.x<b.x or (a.x==b.x and a.y<b.y))
	var held:Vector2i=chairs[2]
	await sit_down(held,false)
	check(seat_of()==seat_name(held),"The owner holds a third chair")
	hud_state("Seated",true)
	put(me,centre(start))
	check(act(me,"held-exit",House.PORTAL,House.EXIT) and seat_of()=="" and not inside(),"Leaving through the door releases a held seat")
	await refresh()
	hud_state("After leaving while seated",false)
	# Access persists with the owner outdoors too.
	check(save_world(),"Save with the owner outdoors")
	var rows:=saved_players()
	check(not House.inside(rows.get(me,{})) and not rows.get(me,{}).has(House.SEAT_KEY),"The save shows the owner outdoors without a seat")
	var again:=World.new()
	check(again.load_world(path) and TR.house_open(again.state),"The outdoor save reloads with the tea house still open")
	again.add_player(me,str(person().name))
	check(again.act(me,"outdoor-reenter",House.PORTAL,House.DOOR).ok and House.inside(again.state.players[me]),"An islander who left before the save can still walk back in")

# --------------------------------------------------------------------- run ---

func run()->void:
	create_timer(150.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 150 s")
		finish())
	var wide:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
		elif arg=="--wide":wide=true
	native=DisplayServer.get_name()!="headless"
	if native and not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1280,800) if wide else Vector2i(1024,640)
	tag="%dx%d"%[root.size.x,root.size.y]
	await contract_flow()
	path="user://tea-house-interior-%d.json"%OS.get_process_id()
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"茶屋旅人",path)!=OK:
		check(false,"The host session starts")
		finish()
		return
	w=app.session.world
	me=app.session.profile.token
	await settle()
	seed_fixture()
	await gate_flow()
	await outdoor_flow()
	await entry_flow()
	var empty_view:Image=await overview("interior_empty")
	await furniture_flow()
	await seats_flow(empty_view)
	await persistence_flow()
	await exit_flow()
	if native:check(shots>=4,"Native run produced its screenshots (%d)"%shots)
	app.session.peers.erase(2)
	w.state.players.erase(GUEST)
	w.active_tokens.erase(GUEST)
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	await process_frame
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	finish()
