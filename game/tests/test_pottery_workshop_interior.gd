extends SceneTree
## 鶯歌合作陶坊室內 (Yingge cooperative pottery workshop interior): native-play smoke + headless regression.
##
##   godot --path game --script res://tests/test_pottery_workshop_interior.gd -- [--wide] [--capture-dir=DIR]
## Windows native play: run WITHOUT --headless so the scene renders and real frames are grabbed; --wide renders
## 1280x800 instead of 1024x640; --capture-dir= keeps the PNGs (native only). Headless falls back to the logic
## checks and skips every screenshot check. Output: POTTERY_WORKSHOP_INTERIOR_TESTS checks=N failures=M
## (exit code 1 on any failure or zero checks).
##
## Contract under test (World.POTTERY_WORKSHOP_INTERIOR): REGION="yingge", ROOM=Rect2i(52,16,16,12),
## DOOR=(20,22) outdoors, EXIT=(59,27) indoors, PORTAL, REACH=1.6, STATIONS={(56,19):clay,(59,19):potter,(63,19):kiln},
## inside(person), blocked(cell), points(person,points_out), station_cell(site), FURNITURE, optional PART_CELLS.
##
## WRITTEN DIRECTLY INTO STATE (PRESET / FIXTURE, not human play):
##  * an isolated host save under user:// (deleted at the end);
##  * chapter one flags like test_tea_ceramics.gd (shipped, watered, board, picnic) and, if the player holds fewer
##    than 4 stone, a stone top-up for the 2-stone clay exchange. No tea record, clay, or kiln job is pre-filled:
##    the introduction letter, potter clay, exchange, firing and collecting are all played;
##  * players are teleported by writing region/x/y only to start a leg (the other scene tests do the same);
##  * time advances through World.step (the same call the existing tea tests use) to finish the kiln.
## REALLY EXERCISED:
##  * app._interact() at the door, every station and the exit, then the real modal buttons (TeaPotter, TeaClay,
##    TeaFire, TeaFireTake). World.act with the indoor station cell is only a fallback so later checks still run;
##  * World.move_player along a BFS route built from World.can_stand, collision probing, distance rejection at the
##    standard 3.2, wrong-region/wrong-cell refusals, shared outdoor cooldown and kiln, portal exit and reentry,
##    World.save + load_world for the same kiln queue.
const World=preload("res://scripts/world.gd")
const Work=World.POTTERY_WORKSHOP_INTERIOR
const Tea=World.TEA_CERAMICS
const Music=preload("res://scripts/scene_music.gd")
const TILE:=32.0
const OVERVIEW_ZOOM:=1.4
const FADE_WAIT:=0.5
const REACH_STANDARD:=3.2
const STATION_SITES:=["clay","potter","kiln"]
const DIRS:=[Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]

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
var stand_cells:={}
var came:={}

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("POTTERY_WORKSHOP_INTERIOR_TESTS checks=%d failures=%d"%[checks,failures])
	print("POTTERY_WORKSHOP_INTERIOR_SHOTS native=%s shots=%d"%[str(native),shots])
	quit(1 if failures>0 or checks==0 else 0)

# ------------------------------------------------------------------ helpers --

func person()->Dictionary:return w.state.players[me]

func here()->Vector2:
	var p:=person()
	return Vector2(p.x,p.y)

func cell_of()->Vector2i:
	var v:=here()
	return Vector2i(floori(v.x),floori(v.y))

func centre(c:Vector2i)->Vector2:return Vector2(c)+Vector2(0.5,0.5)

func inside()->bool:return Work.inside(person())

func record()->Dictionary:return Tea.own_record(w.state,me)

func bag()->Dictionary:return person().inventory

func station(site:String)->Vector2i:return Work.station_cell(site)

func act(action:String,cell:Vector2i,extra:String="",label:String="")->bool:
	request+=1
	return bool(w.act(me,"pwi-%d-%s"%[request,label.left(30)],action,cell,extra).ok)

func solid(c:Vector2i)->bool:
	w.switch_region(Work.REGION)
	var result:bool=w.blocked(c)
	w.switch_region(World.REGIONS.HOME)
	return result

func standable(v:Vector2)->bool:
	w.switch_region(Work.REGION)
	var result:bool=w.can_stand(v)
	w.switch_region(World.REGIONS.HOME)
	return result

func put(v:Vector2,region:String=Work.REGION)->void:
	var p:=person()
	p.region=region  # PRESET
	p.x=v.x;p.y=v.y  # PRESET

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func close_modal()->void:
	if is_instance_valid(app.modal):app._close_modal()

func clear_overlays()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:(ribbon as CanvasItem).hide()

func refresh()->void:
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	clear_overlays()
	await settle()

func place_me(v:Vector2,region:String=Work.REGION)->void:
	put(v,region)
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

func interact()->void:
	app.session.rates[1].clear()
	if "action_clock" in app:app.action_clock=0
	app._interact()
	await settle()
	await refresh()

func save_world()->bool:
	w.switch_region(World.REGIONS.HOME)
	return w.save()

func advance(seconds:float)->void:
	check(w.step(seconds,true),"The world advances %.0f seconds"%seconds)
	await refresh()

func focus()->String:return str(app.view.interaction_focus())

# --------------------------------------------------------------- movement ----

func reachable(start:Vector2i)->Dictionary:
	var result:Dictionary={start:start}
	var queue:Array=[start]
	var index:=0
	while index<queue.size():
		var c:Vector2i=queue[index]
		index+=1
		for d:Vector2i in DIRS:
			var n:=c+d
			if result.has(n) or not Work.ROOM.has_point(n) or not standable(centre(n)):continue
			result[n]=c
			queue.append(n)
	return result

func walk_route(goal:Vector2i)->bool:
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

## Closest reachable floor cell beside a station (the cell the player stands on to use it).
func stand_for(site:String)->Vector2i:
	var target:=centre(station(site))
	var best:=Vector2i(-999,-999)
	var best_d:=INF
	for c:Vector2i in came:
		var d:=centre(c).distance_to(target)
		if d<best_d and c!=station(site):
			best=c;best_d=d
	return best

func walk_to_station(site:String)->void:
	var goal:=stand_for(site)
	check(goal.x!=-999 and centre(goal).distance_to(centre(station(site)))<=2.3,"%s has a reachable standing cell within 2.3 of its centre (%s)"%[site,str(goal)])
	check(walk_route(goal),"Real movement walks to the %s station (ended at %s)"%[site,str(cell_of())])
	await refresh()

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
		var file:=output.path_join("pottery_workshop_%s_%s.png"%[tag,step])
		check(image.save_png(file)==OK,"Screenshot saved %s_%s"%[tag,step])
		print("POTTERY_WORKSHOP_INTERIOR_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

func overview(step:String)->Image:
	var view=app.view
	var previous_zoom:float=view.zoom
	view.zoom=OVERVIEW_ZOOM
	view.set_process(false)
	var middle:=Vector2(Work.ROOM.position)+Vector2(Work.ROOM.size)/2.0
	view.update_camera(middle,true)
	view.queue_redraw()
	clear_overlays()
	await settle()
	var room_px:=view_to_pixels(Rect2(app.view.screen(Vector2(Work.ROOM.position)),Vector2(Work.ROOM.size)*TILE))
	var visible:=Rect2(Vector2.ZERO,Vector2(root.size))
	check(visible.encloses(room_px),"The whole workshop fits the %s view at zoom %.1f: %s"%[tag,OVERVIEW_ZOOM,str(room_px)])
	var image:Image=await shot(step)
	if image!=null and not image.is_empty():
		var box:=Rect2i(Vector2i(room_px.position.round()),Vector2i(room_px.size.round())).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		check(colour_variety(image.get_region(box))>=8,"The workshop room is painted, not blank (%s_%s)"%[tag,step])
		# Every station must be drawn as workshop art (not bare floor): its tile area holds several colours.
		for site in STATION_SITES:
			var cell:=station(site)
			var px:=view_to_pixels(Rect2(app.view.screen(Vector2(cell))-Vector2(0,TILE),Vector2(TILE,TILE*2.0)))
			var spot:=Rect2i(Vector2i(px.position.round()),Vector2i(px.size.round())).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
			if spot.size.x>2 and spot.size.y>2:
				check(colour_variety(image.get_region(spot))>=3,"The %s station area shows workshop art (%s_%s)"%[site,tag,step])
	view.zoom=previous_zoom
	view.set_process(true)
	return image

# ----------------------------------------------------------------- station ---

## Presses E at the station, then a real modal button. Falls back to World.act (indoor cell) when the UI
## path does not complete, so the remaining checks still run after a reported failure.
func use_station(site:String,button:String,action:String,extra:String="")->bool:
	await walk_to_station(site)
	check(focus()=="tea:"+site,"Standing at %s focuses tea:%s (%s)"%[site,site,focus()])
	await interact()
	var opened:=is_instance_valid(app.modal) and str(app.modal.get_meta("tea_site",""))==site
	check(opened,"E opens the %s tea modal indoors"%site)
	var done:=false
	if opened:
		await settle()
		var control:=app.modal.find_child(button,true,false) as Button
		if control!=null and not control.disabled and control.is_visible_in_tree():
			await create_timer(0.12).timeout
			app.session.rates[1].clear()
			control.pressed.emit()
			done=true
			await refresh()
	check(done,"The %s button is enabled indoors (%s)"%[button,site])
	close_modal()
	if not done:
		check(act(action,station(site),extra,button),"Fallback World.act %s at the indoor %s cell"%[action,site])
		await refresh()
	return done

func far_cell(site:String)->Vector2i:
	var target:=centre(station(site))
	var best:=Vector2i(-999,-999)
	for c:Vector2i in came:
		var d:=centre(c).distance_to(target)
		if d>REACH_STANDARD+0.3 and d<8.0:
			best=c
			break
	return best

# ------------------------------------------------------------------- flows ---

func contract_flow()->void:
	check(Work.REGION=="yingge" and Work.ROOM==Rect2i(52,16,16,12),"The workshop lives in yingge at (52,16,16,12)")
	check(Work.DOOR==Vector2i(20,22) and Work.EXIT==Vector2i(59,27),"The door is (20,22) and the inner exit (59,27)")
	check(Work.PORTAL=="yingge_pottery_portal" and is_equal_approx(float(Work.REACH),1.6),"Portal name fits the session protocol and reach matches the doorway")
	check(Work.ROOM.has_point(Work.EXIT) and not Work.ROOM.has_point(Work.DOOR),"The exit is inside the room and the door outside it")
	check(Work.STATIONS=={Vector2i(56,19):"clay",Vector2i(59,19):"potter",Vector2i(63,19):"kiln"},"STATIONS match the contract")
	for cell:Vector2i in Work.STATIONS:
		check(Work.ROOM.has_point(cell) and Work.station_cell(Work.STATIONS[cell])==cell,"Station %s resolves to its cell %s"%[Work.STATIONS[cell],str(cell)])
	check(Work.station_cell("nope")==Vector2i(-1,-1) and Work.station_cell("")==Vector2i(-1,-1),"station_cell returns (-1,-1) for an unknown site")
	var outside:={"region":Work.REGION,"x":centre(Work.DOOR).x,"y":centre(Work.DOOR).y}
	var within:={"region":Work.REGION,"x":centre(Work.EXIT+Vector2i.UP).x,"y":centre(Work.EXIT+Vector2i.UP).y}
	check(not Work.inside(outside) and Work.inside(within),"inside() is false at the door and true by the exit")
	check(not Work.inside({"region":"home","x":within.x,"y":within.y}),"inside() requires the yingge region")
	var out_points:={}
	Work.points(outside,out_points)
	check(out_points.has(Work.PORTAL) and out_points[Work.PORTAL]==centre(Work.DOOR),"Outdoors points() offers the portal at the door")
	check(out_points.size()==1,"Outdoors points() offers nothing but the portal (%s)"%str(out_points.keys()))
	var in_points:={}
	Work.points(within,in_points)
	check(in_points.get(Work.PORTAL)==centre(Work.EXIT),"Indoors points() offers the portal at the exit")
	for cell:Vector2i in Work.STATIONS:
		check(in_points.get("tea:"+Work.STATIONS[cell])==centre(cell),"Indoors points() offers tea:%s at its centre"%Work.STATIONS[cell])
	check(Work.FURNITURE.size()>=8,"The workshop has at least 8 furniture anchors (%d)"%Work.FURNITURE.size())
	var view_source:=FileAccess.get_file_as_string("res://scripts/world_view.gd")
	var kinds:={}
	for cell:Vector2i in Work.FURNITURE:
		var kind:=str(Work.FURNITURE[cell])
		kinds[kind]=true
		check(Work.ROOM.has_point(cell) and cell!=Work.EXIT,"Furniture %s at %s is in the room and off the exit"%[kind,str(cell)])
		check(not kind.is_empty() and (view_source.contains("\"%s\""%kind) or World.BUILD.has(kind) or view_source.contains(kind)),"Furniture kind %s is known to the world view"%kind)
	check(kinds.size()>=3,"At least three kinds of furniture (%s)"%str(kinds.keys()))
	for cell:Vector2i in Work.PART_CELLS:
		check(Work.ROOM.has_point(cell) and Work.blocked(cell),"Multi-cell furniture part %s is in the room and blocks"%str(cell))
	for cell:Vector2i in Work.FURNITURE:
		check(Work.blocked(cell),"Furniture %s blocks movement"%str(cell))
	check(Work.blocked(Work.ROOM.position) and Work.blocked(Vector2i(Work.ROOM.end.x-1,Work.ROOM.end.y-1)),"The room walls block")
	check(not Work.blocked(Work.EXIT) and not Work.blocked(Work.DOOR),"The exit and the outdoor door are never blocked")

func setup_stones()->void:
	if int(bag().get("stone",0))<4:bag().stone=4  # FIXTURE: payment for the 2-stone clay exchange

func visit_gate_flow()->void:
	## Region reachable == shop reachable: no chapter progress is needed to walk in.
	await place_me(centre(Work.DOOR))
	check(not inside() and cell_of()==Work.DOOR,"The test begins outdoors on the door tile")
	check(focus()==Work.PORTAL,"The door prompt focuses the portal (%s)"%focus())
	check(not act(Work.PORTAL,Work.EXIT,"","wrong-way") and not inside(),"Outdoors the interior exit cannot be addressed")
	check(not act(Work.PORTAL,Work.DOOR,"extra","extra") and not inside(),"The portal takes no extra argument")
	put(centre(Work.DOOR+Vector2i(0,10)))
	check(not act(Work.PORTAL,Work.DOOR,"","far") and not inside(),"A far-away player cannot use the door")
	await place_me(centre(Work.DOOR))
	check(not Tea.apply(w.state,me,"tea_potter",Work.REGION,Work.DOOR,"").ok,"Tea actions at the door cell are refused")
	await shot("door_outdoors")
	await interact()
	var entered:=inside()
	check(entered,"E at the door walks into the workshop before any chapter progress")
	if not entered:
		check(act(Work.PORTAL,Work.DOOR,"","enter-fallback"),"Server fallback entry")
		await refresh()
	check(person().region==Work.REGION and Work.ROOM.has_point(cell_of()) and standable(here()),"The arrival spot is inside the room and standable")
	check(here().distance_to(centre(Work.EXIT))<=4.0,"The player arrives beside the inner exit")
	if native:
		check(app.sound.music.scene_id==Music.POTTERY_WORKSHOP_TRACK and app.sound.music.current.playing,"The interior workshop recording plays on entry")
		check(app.sound.ambience_kind.is_empty() and not app.sound.ambience.playing,"The pottery room has no outdoor wind bed")
	came=reachable(Work.EXIT+Vector2i.UP)
	# Chapter gates are unchanged: the stations refuse until the chapter, then until the letter.
	var before:=record()
	for site:String in STATION_SITES:check(station(site)!=Vector2i(-1,-1),"Station %s exists"%site)
	check(not act("tea_potter",station("potter"),"","pre-chapter"),"The potter refuses before chapter one is complete")
	check(not act("tea_clay",station("clay"),"","pre-chapter-clay"),"The clay exchange refuses before chapter one is complete")
	check(not act("tea_fire",station("kiln"),"","pre-chapter-kiln"),"The kiln refuses before chapter one is complete")
	check(record()==before and int(bag().get("clay",0))==0,"Refused station actions change nothing")
	w.state.chapter_one.shipped=true  # PRESET
	w.state.chapter_one.watered=true  # PRESET
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	await walk_to_station("potter")
	check(not act("tea_potter",station("potter"),"","pre-intro") and not record().potter,"The potter still needs the introduction letter")
	await refresh()
	# Leave and read the letter at the ferry (a real action), then come back.
	await place_me(centre(Work.EXIT+Vector2i.UP))
	await interact()
	check(not inside(),"E on the exit leaves the workshop")
	put(centre(Tea.RECEIVER+Vector2i(1,0)),"home")
	check(act("tea_intro",Tea.RECEIVER,"","intro") and record().intro,"The introduction letter is read at the ferry")
	await place_me(centre(Work.DOOR))

func enter_flow()->void:
	await interact()
	check(inside(),"E at the door enters the workshop again")
	if not inside():
		check(act(Work.PORTAL,Work.DOOR,"","reenter-fallback"),"Server fallback entry")
		await refresh()
	came=reachable(Work.EXIT+Vector2i.UP)
	check(came.size()>=30,"A generous aisle network is walkable (%d cells)"%came.size())
	await overview("interior")
	await collision_flow()
	await place_me(centre(Work.EXIT+Vector2i.UP))

func collision_flow()->void:
	var start:Vector2i=Work.EXIT+Vector2i.UP
	check(not solid(Work.EXIT) and standable(centre(start)),"The exit tile and the one before it are walkable")
	check(solid(Work.ROOM.position),"Walls block movement (world)")
	for site:String in STATION_SITES:
		check(came.has(stand_for(site)),"The %s station is on the aisle network"%site)
	var probes:=0
	for cell:Vector2i in Work.FURNITURE:
		if not solid(cell):continue
		var near:=Vector2i(-999,-999)
		for d:Vector2i in DIRS:
			if came.has(cell+d):near=cell+d;break
		if near.x==-999:continue
		probes+=1
		put(centre(near))
		for i in range(12):w.move_player(me,Vector2(cell-near),0.1)
		check(cell_of()!=cell and not solid(cell_of()),"Walking into %s at %s is stopped (ended at %s)"%[str(Work.FURNITURE[cell]),str(cell),str(cell_of())])
	check(probes>=5,"Collision was probed against several furniture cells (%d)"%probes)
	for cell:Vector2i in Work.PART_CELLS:
		check(solid(cell),"World blocks the furniture part %s"%str(cell))
	put(centre(start))

func round_one()->void:
	var clay_before:=int(bag().get("clay",0))
	check(clay_before==0 and record().kiln.is_empty() and not record().potter,"Round one starts with no clay, no potter progress and an empty kiln")
	await use_station("potter","TeaPotter","tea_potter")
	check(record().potter and int(bag().get("clay",0))==2,"The potter hands over two clay indoors (clay %d)"%int(bag().get("clay",0)))
	check(not act("tea_potter",station("potter"),"","twice") and int(bag().get("clay",0))==2,"Free clay cannot be claimed twice indoors")
	var stone:=int(bag().get("stone",0))
	await use_station("clay","TeaClay","tea_clay")
	check(int(bag().get("clay",0))==3 and int(bag().get("stone",0))==stone-2,"The clay exchange gives one clay for two stone indoors")
	check(not act("tea_clay",station("clay"),"","cooldown") and int(bag().get("clay",0))==3,"The clay cooldown is enforced indoors")
	check(w.state.tea_ceramics.players[me].clay_ready>float(w.state.time),"The cooldown lives in the shared tea record")
	check(record().kiln.is_empty(),"No kiln job exists before the player starts one")
	await use_station("kiln","TeaFire","tea_fire")
	var job:Dictionary=record().kiln
	check(not job.is_empty() and job.get("repair")==false and int(bag().get("clay",0))==1,"The kiln job started indoors costs two clay (%s)"%str(job))
	check(not act("tea_fire_take",station("kiln"),"","early") and not act("tea_fire",station("kiln"),"","busy"),"The kiln is reserved until the jar is ready")
	check(int(bag().get("tea_jar",0))==0,"No jar exists yet")
	# Save and reload: the same queue comes back.
	check(save_world(),"The island saves with the kiln queue running")
	var reopened:=World.new()
	check(reopened.load_world(path) and not reopened.recovered_from_backup,"The save reloads from the primary file")
	var back:=Tea.own_record(reopened.state,me)
	check(back.kiln==job and back.clay_ready==record().clay_ready and back.potter and back.intro,"The reload keeps the same kiln job, clay cooldown and tea record")
	check(Work.inside(reopened.state.players[me]) and reopened.state.players[me].region==Work.REGION,"The save keeps the player inside the workshop")
	reopened.add_player(me,str(person().name))
	check(reopened.player_region(me)==Work.REGION and Work.inside(reopened.state.players[me]),"Rejoining returns the player to the workshop")
	check(not reopened.act(me,"pwi-reload-early","tea_fire_take",station("kiln")).ok,"The reloaded kiln is still not ready")
	check(reopened.step(Tea.KILN_SECONDS,true) and reopened.act(me,"pwi-reload-take","tea_fire_take",station("kiln")).ok and int(reopened.state.players[me].inventory.get("tea_jar",0))==1,"The reloaded queue finishes into exactly one jar")

func outdoor_leg()->void:
	var job:Dictionary=record().kiln
	# Leave through the real exit.
	await place_me(centre(Work.EXIT+Vector2i.UP))
	check(focus()==Work.PORTAL,"Beside the exit the prompt focuses the portal (%s)"%focus())
	await interact()
	var left:=not inside()
	check(left,"E at the inner exit returns the player outdoors")
	if not left:
		check(act(Work.PORTAL,Work.EXIT,"","exit-fallback"),"Server fallback exit")
		await refresh()
	check(person().region==Work.REGION and here().distance_to(centre(Work.DOOR))<4.0 and standable(here()),"The player is beside the door on walkable ground (%s)"%str(here()))
	if native:
		check(app.sound.music.scene_id==Work.REGION and app.sound.music.current.playing,"Leaving restores the outdoor Yingge recording")
		check(app.sound.ambience_kind=="wind" and app.sound.ambience.playing,"Leaving restores outdoor wind")
	check(not act(Work.PORTAL,Work.EXIT,"","back-exit"),"Outdoors the exit cannot be addressed again")
	check(record().kiln==job,"The kiln queue is untouched by leaving")
	# The outdoor stations use the very same record.
	put(centre(Tea.CLAY)+Vector2(1.0,0.0))
	check(not act("tea_clay",Tea.CLAY,"","outdoor-cooldown"),"The outdoor exchange shares the indoor cooldown")
	put(centre(Tea.KILN)+Vector2(1.0,0.0))
	check(not act("tea_fire_take",Tea.KILN,"","outdoor-early") and record().kiln==job,"The outdoor kiln shows the same unfinished job")
	check(not act("tea_fire",Tea.KILN,"","outdoor-busy"),"The outdoor kiln is busy with the same job")
	await advance(Tea.KILN_SECONDS)
	# Standard distance: outdoors from the door arrival the kiln is out of reach.
	put(centre(Work.DOOR))
	check(centre(Work.DOOR).distance_to(centre(Tea.KILN))>REACH_STANDARD,"The door is farther than %.1f from the outdoor kiln"%REACH_STANDARD)
	check(not act("tea_fire_take",Tea.KILN,"","outdoor-far") and int(bag().get("tea_jar",0))==0,"A far-away player cannot take the finished jar")
	var steps:=0
	while here().distance_to(centre(Tea.KILN))>2.6 and steps<120:
		w.move_player(me,(centre(Tea.KILN)-here()).normalized(),0.05)
		steps+=1
	check(here().distance_to(centre(Tea.KILN))<=REACH_STANDARD,"Real movement brings the player within reach of the outdoor kiln (%.2f)"%here().distance_to(centre(Tea.KILN)))
	await refresh()
	check(act("tea_fire_take",Tea.KILN,"","outdoor-take") and int(bag().get("tea_jar",0))==1 and record().kiln.is_empty(),"The jar fired indoors is collected outdoors from the same kiln")
	await place_me(centre(Work.DOOR))
	await shot("back_outdoors")

func round_two()->void:
	# Reentry through the real door.
	await place_me(centre(Work.DOOR))
	await interact()
	check(inside(),"E at the door re-enters the workshop")
	if not inside():
		check(act(Work.PORTAL,Work.DOOR,"","reenter"),"Server fallback reentry")
		await refresh()
	came=reachable(Work.EXIT+Vector2i.UP)
	check(float(record().clay_ready)<=float(w.state.time),"The shared clay cooldown has elapsed")
	var stone:=int(bag().get("stone",0))
	await use_station("clay","TeaClay","tea_clay")
	check(int(bag().get("clay",0))==2 and int(bag().get("stone",0))==stone-2,"The indoor exchange works again after outdoor time (clay %d)"%int(bag().get("clay",0)))
	await use_station("kiln","TeaFire","tea_fire")
	check(not record().kiln.is_empty() and int(bag().get("clay",0))==0,"A second job starts indoors")
	var job:Dictionary=record().kiln
	await shot("kiln_busy")
	await advance(Tea.KILN_SECONDS)
	# Distance rejection indoors: the job is ready, only reach can refuse.
	var far:=far_cell("kiln")
	check(far.x!=-999,"A reachable spot farther than %.1f from the kiln exists"%REACH_STANDARD)
	if far.x!=-999:
		put(centre(far))
		check(centre(far).distance_to(centre(station("kiln")))>REACH_STANDARD,"The far spot is out of the standard reach")
		check(not act("tea_fire_take",station("kiln"),"","indoor-far") and record().kiln==job and int(bag().get("tea_jar",0))==1,"The kiln refuses a collector standing out of reach")
		check(not act("tea_clay",station("clay"),"","indoor-far-clay") or centre(far).distance_to(centre(station("clay")))<=REACH_STANDARD,"The exchange also keeps its distance rule")
	# Wrong cell: an outdoor site cannot be used from inside the room, and the interior portal cannot be reused.
	await walk_to_station("kiln")
	check(not act("tea_fire_take",Tea.KILN,"","wrong-cell") and record().kiln==job,"The outdoor kiln cell is refused while inside")
	check(not act("tea_fire_take",Vector2i(station("kiln").x+1,station("kiln").y+1),"","other-cell") and record().kiln==job,"An arbitrary neighbouring cell is not a station")
	# The indoor take finishes the job (no outdoor visit needed).
	await use_station("kiln","TeaFireTake","tea_fire_take")
	check(record().kiln.is_empty() and int(bag().get("tea_jar",0))==2,"The indoor take delivers the second jar (jars %d)"%int(bag().get("tea_jar",0)))
	check(not act("tea_fire_take",station("kiln"),"","take-twice") and int(bag().get("tea_jar",0))==2,"A jar cannot be taken twice")
	await overview("interior_done")

func finish_flow()->void:
	var snapshot:Dictionary=JSON.parse_string(JSON.stringify(record()))
	check(save_world(),"Final save inside the workshop")
	var again:=World.new()
	check(again.load_world(path) and Tea.own_record(again.state,me)==snapshot,"The final reload keeps the same tea record values")
	again.add_player(me,str(person().name))
	check(Work.inside(again.state.players[me]),"Rejoin keeps the player in the workshop")
	var spot:=Vector2(again.state.players[me].x,again.state.players[me].y)
	again.state.players[me].x=centre(Work.EXIT+Vector2i.UP).x
	again.state.players[me].y=centre(Work.EXIT+Vector2i.UP).y
	check(again.act(me,"pwi-again-exit",Work.PORTAL,Work.EXIT).ok and not Work.inside(again.state.players[me]),"After the reload the exit still leads outdoors")
	check(again.act(me,"pwi-again-enter",Work.PORTAL,Work.DOOR).ok and Work.inside(again.state.players[me]),"After the reload the door still opens")
	check(spot.distance_to(centre(Work.EXIT))<30.0,"The saved position was inside the room area")
	# Leave for real.
	await place_me(centre(Work.EXIT+Vector2i.UP))
	await interact()
	check(not inside(),"The player finishes the visit outdoors")
	if inside():
		check(act(Work.PORTAL,Work.EXIT,"","final-exit"),"Server fallback final exit")

# --------------------------------------------------------------------- run ---

func run()->void:
	create_timer(180.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 180 s")
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
	path="user://pottery-workshop-interior-%d.json"%OS.get_process_id()
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"陶坊旅人",path)!=OK:
		check(false,"The host session starts")
		finish()
		return
	w=app.session.world
	me=app.session.profile.token
	await settle()
	setup_stones()
	await visit_gate_flow()
	await enter_flow()
	await round_one()
	await outdoor_leg()
	await round_two()
	await finish_flow()
	if native:check(shots>=4,"Native run produced its screenshots (%d)"%shots)
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	await process_frame
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	finish()
