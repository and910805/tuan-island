extends SceneTree
## Beimen salt-pan world scene integration (render test: run WITHOUT --headless).
## Seeded in-process Session snapshots drawn by the real WorldView, like
## test_flower_scene.gd, plus pixel checks against the delivered art, real
## movement through World.move_player, collision parity, main.gd routing and
## captures under work/salt/scene-check/.
const World=preload("res://scripts/world.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const View=preload("res://scripts/world_view.gd")
const SaltWorldArt=preload("res://scripts/salt_world_art.gd")
const SaltArt=preload("res://scripts/salt_art.gd")
const PropsArt=preload("res://scripts/salt_props_art.gd")
const SaltUI=preload("res://scripts/salt_pan_ui.gd")
const Weather=preload("res://scripts/weather.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const ACTOR:="salt-scene-PRIVATE-TOKEN"
const BASE:=Vector2i(1280,800)
class FixtureSession extends "res://scripts/session.gd":
	func _ready()->void:
		name="Session"
		session_nonce="salt-scene-audit"
var checks:=0
var failures:=0
var session
var view
var out_dir:=""
var walk_cells:={}

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:run.call_deferred()

func world()->World:
	return session.world

func send()->void:
	session._send_snapshot(1)
	view.update_snapshot(session.snapshot,session.own_id)

func place(at:Vector2)->void:
	var person:Dictionary=world().state.players[ACTOR]
	person.region=Salt.REGION
	person.x=at.x
	person.y=at.y
	send()
	view.display_positions[session.own_id]=at

func aim(center:Vector2)->void:
	view.camera=(center*32.0-Vector2(BASE)*0.5/view.view_zoom()).round()

func render()->void:
	view.queue_redraw()
	await process_frame
	await process_frame

func capture()->Image:
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

func label_titles(id:String)->Array:
	var titles:=[]
	for entry in view.world_labels:if entry.id==id:titles.append(entry.title)
	return titles

func day_with(kind:String)->float:
	for d in 60:
		if Weather.outdoor_id(float(d))==kind:return float(d)
	return -1.0

## Mean colour error between the captured screen block and a texture drawn at
## world point `top_left` (texture pixels with alpha>=200 only).
func error_to(image:Image,top_left:Vector2,texture:Texture2D)->float:
	if texture==null:return INF
	var tex:=texture.get_image()
	tex.convert(Image.FORMAT_RGBA8)
	var z:float=view.view_zoom()
	var origin:Vector2=(top_left-view.camera)*z
	var total:=0.0
	var n:=0
	for y in tex.get_height():
		for x in tex.get_width():
			var c:=tex.get_pixel(x,y)
			if c.a8<200:continue
			var at:=Vector2i((origin+Vector2(x+0.5,y+0.5)*z).floor())
			if at.x<0 or at.y<0 or at.x>=image.get_width() or at.y>=image.get_height():continue
			var s:=image.get_pixel(at.x,at.y)
			total+=absf(s.r-c.r)+absf(s.g-c.g)+absf(s.b-c.b)
			n+=1
	return total/n if n>200 else INF

func set_time(day:float)->void:
	world().state.time=day*Weather.DAY_SECONDS+Weather.DAY_SECONDS*0.5

func pans_mixed()->Array:
	var expected:=[]
	var now:float=world().state.time
	var pans:Array=world().state.salt_pan.pans
	for i in Salt.PAN_COUNT:
		match i%5:
			0:pans[i]={"s":"empty","p":0.0,"t":0.0,"f":""}
			1:pans[i]={"s":"brine","p":Salt.NEED*0.1,"t":now,"f":"hand"}
			2:pans[i]={"s":"brine","p":Salt.NEED*0.5,"t":now,"f":"hand"}
			3:pans[i]={"s":"brine","p":Salt.NEED*0.85,"t":now,"f":"hand"}
			4:pans[i]={"s":"salt","p":Salt.NEED,"t":now,"f":"hand"}
	return pans

func machines_mixed()->void:
	var lots:Array=world().state.salt_pan.lots
	lots[1].owner="other-a";lots[1].wheel=true;lots[1].rake=true;lots[1].on=true
	lots[2].owner="other-b";lots[2].wheel=true;lots[2].rake=false;lots[2].on=false
	lots[4].owner="other-c";lots[4].wheel=true;lots[4].rake=true;lots[4].on=false

func differing(a:Image,b:Image)->int:
	var n:=0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x,y)!=b.get_pixel(x,y):n+=1
	return n

func differing_outside(a:Image,b:Image,skip:Array)->int:
	var n:=0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x,y)==b.get_pixel(x,y):continue
			var masked:=false
			for r in skip:
				if (r as Rect2i).has_point(Vector2i(x,y)):masked=true
			if not masked:n+=1
	return n

func differing_in(a:Image,b:Image,region:Rect2i)->int:
	var n:=0
	var r:=region.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	for y in range(r.position.y,r.end.y):
		for x in range(r.position.x,r.end.x):
			if a.get_pixel(x,y)!=b.get_pixel(x,y):n+=1
	return n

## Screen rectangle of a native machine ROI for a sprite whose world top-left is `tl`.
func roi_screen(tl:Vector2,roi:Rect2i)->Rect2i:
	var z:float=view.view_zoom()
	return Rect2i(Vector2i(((tl+Vector2(roi.position))-view.camera)*z),Vector2i(Vector2(roi.size)*z))

## Screen ROIs of every machine the scene says is running.
func running_rois(data:Dictionary)->Array:
	var rects:=[]
	for lot in SaltWorldArt.machine_lots():
		if SaltWorldArt.wheel_running(data,lot):
			for roi in SaltArt.animated_rois("waterwheel"):rects.append(roi_screen(feet_top_left(Salt.wheel_socket(lot),SaltArt.MACHINE_ANCHOR),roi))
		if SaltWorldArt.collector_running(data,lot):
			for roi in SaltArt.animated_rois("salt_collector"):rects.append(roi_screen(feet_top_left(Salt.rake_socket(lot),SaltArt.MACHINE_ANCHOR),roi))
	return rects

## Inside the ROIs: a screen pixel changed (still -> moving) exactly where the
## running texture differs from the idle texture. Returns wrong pixel count.
func mask_mismatch(still:Image,moving:Image,tl:Vector2,idle:Texture2D,running:Texture2D,rois:Array)->int:
	if idle==null or running==null:return 1<<20
	var a:=idle.get_image()
	a.convert(Image.FORMAT_RGBA8)
	var b:=running.get_image()
	b.convert(Image.FORMAT_RGBA8)
	var z:float=view.view_zoom()
	var wrong:=0
	for roi in rois:
		var r:Rect2i=roi
		for y in range(r.position.y,r.end.y):
			for x in range(r.position.x,r.end.x):
				var at:=Vector2i(((tl+Vector2(x+0.5,y+0.5))-view.camera)*z)
				if at.x<0 or at.y<0 or at.x>=still.get_width() or at.y>=still.get_height():continue
				var ca:=a.get_pixel(x,y)
				var cb:=b.get_pixel(x,y)
				var want:=ca!=cb and not (ca.a8==0 and cb.a8==0)
				var got:=still.get_pixel(at.x,at.y)!=moving.get_pixel(at.x,at.y)
				if want!=got:wrong+=1
	return wrong

func feet_top_left(rect:Rect2i,anchor:Vector2i)->Vector2:
	return Vector2(rect.position.x+1,rect.position.y+1)*32-Vector2(anchor)

# ------------------------------------------------------------------ walking

func walkable()->Dictionary:
	var cells:={}
	world().switch_region(Salt.REGION)
	for y in range(Salt.LAND.position.y-1,Salt.LAND.end.y+1):
		for x in range(Salt.LAND.position.x-1,Salt.LAND.end.x+1):
			if not world().blocked(Vector2i(x,y)):cells[Vector2i(x,y)]=true
	world().switch_region(World.REGIONS.HOME)
	return cells

func bfs(from:Vector2i,goal:Callable)->Array:
	var prev:={from:from}
	var queue:=[from]
	while not queue.is_empty():
		var cell:Vector2i=queue.pop_front()
		if goal.call(cell):
			var path:=[cell]
			while path[0]!=from:path.push_front(prev[path[0]])
			return path
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:Vector2i=cell+step
			if walk_cells.has(next) and not prev.has(next):
				prev[next]=cell
				queue.append(next)
	return []

func focus_at(cell:Vector2i)->String:
	return SaltWorldArt.focus(Vector2(cell)+Vector2(0.5,0.5),World.TRANSIT.points(Salt.REGION),{},View.INTERACTIVE_OBJECTS)

## A walkable cell where `site` is the strict nearest interaction (BFS-nearest from `from`).
func cell_for(site:String,from:Vector2i=Vector2i(Salt.ARRIVAL))->Vector2i:
	var path:=bfs(from,func(c:Vector2i)->bool:return focus_at(c)==site)
	return path[-1] if not path.is_empty() else Vector2i(-1,-1)

func walk_to(site:String)->bool:
	var person:Dictionary=world().state.players[ACTOR]
	var start:=Vector2i(floori(person.x),floori(person.y))
	var path:=bfs(start,func(c:Vector2i)->bool:return focus_at(c)==site)
	if path.is_empty():return false
	for cell:Vector2i in path:
		var target:=Vector2(cell)+Vector2(0.5,0.5)
		var guard:=0
		while Vector2(person.x,person.y).distance_to(target)>0.06:
			var before:=Vector2(person.x,person.y)
			var dir:=target-before
			world().move_player(ACTOR,dir.normalized()*minf(1.0,dir.length()/0.072),0.02)
			guard+=1
			if guard>200 or (Vector2(person.x,person.y)==before):return false
	return true

# ------------------------------------------------------------------ run

func run()->void:
	root.size=BASE
	out_dir=ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()+"/work/salt/scene-check"
	DirAccess.make_dir_recursive_absolute(out_dir)
	session=FixtureSession.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	session.world.add_player(ACTOR,"鹽田旅人")
	session.peers={1:ACTOR}
	var record:Dictionary=Salt.RECORD.duplicate(true)
	record.letter=true;record.intro=true
	world().state.salt_pan.players[ACTOR]=record
	view=View.new()
	view.village_art_preview=true
	root.add_child(view)
	view.set_process(false)
	view.reduced_motion=true
	var sunny:=day_with("sunny")
	var rainy:=day_with("rainy")
	expect(sunny>=0.0 and rainy>=0.0,"calendar has sunny and rainy days")
	set_time(sunny)

	# Snapshot shape consumed by the scene.
	place(Salt.ARRIVAL)
	var salt:Dictionary=session.snapshot.get("salt_pan",{})
	expect(salt.get("pans",[]).size()==20 and salt.get("lots",[]).size()==8 and salt.has("apprentice") and salt.has("weather") and salt.has("own"),"snapshot carries salt_pan public view + own")
	expect(view.region_id()==Salt.REGION,"view is in beimen")
	expect(SaltWorldArt.shared({"salt_pan":"bad"}).is_empty() and SaltWorldArt.pan_state({},3)=="empty" and not SaltWorldArt.gate_repaired({},0),"defensive reads tolerate missing/bad snapshot fields")

	# Focus points are the same as SaltPanUI.interaction_points (main.gd routing).
	var ui_points:Dictionary=SaltUI.interaction_points(Salt.REGION)
	var art_points:=SaltWorldArt.sites()
	expect(ui_points.size()==art_points.size() and ui_points.size()==45,"45 salt interaction sites (%d/%d)"%[ui_points.size(),art_points.size()])
	var same:=true
	for key in ui_points:
		if not art_points.has(key) or Vector2(art_points[key]).distance_to(ui_points[key])>0.001:same=false
	expect(same,"view focus points equal SaltPanUI.interaction_points")
	expect(SaltUI.interaction_points("home").is_empty(),"no salt sites outside beimen")

	# Collision: every drawn footprint equals SaltPan.blocked, and World agrees.
	var covered:={}
	for item in SaltWorldArt.footprints():
		var rect:Rect2i=item.rect
		expect(rect.has_area(),"footprint %s has area"%item.id)
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				expect(not covered.has(Vector2i(x,y)),"footprints do not overlap at %s (%s)"%[Vector2i(x,y),item.id])
				covered[Vector2i(x,y)]=item.id
	var parity:=true
	var world_parity:=true
	world().switch_region(Salt.REGION)
	for y in range(0,60):
		for x in range(0,80):
			var p:=Vector2i(x,y)
			if Salt.LAND.has_point(p) and Salt.blocked(p)!=covered.has(p):
				parity=false
				push_error("collision mismatch at %s blocked=%s drawn=%s"%[p,Salt.blocked(p),covered.get(p,"")])
			if world().blocked(p)!=(not Salt.LAND.has_point(p) or covered.has(p)):world_parity=false
	world().switch_region(World.REGIONS.HOME)
	expect(parity,"drawn footprints == SaltPan.blocked over LAND")
	expect(world_parity,"World.blocked in beimen == outside LAND or a drawn footprint (no objects)")
	for item in SaltWorldArt.footprints():
		var art:String=item.art
		var ok:=false
		match art:
			"gate":ok=PropsArt.prop_texture("gate_broken")!=null and PropsArt.prop_texture("gate_repaired")!=null
			"channel","heritage_floor":ok=SaltArt.terrain_texture(art)!=null
			"pan":ok=SaltArt.pan_texture("empty")!=null
			"machine":ok=SaltArt.machine_texture("waterwheel_empty")!=null and PropsArt.prop_texture("waterwheel")!=null
			"resident":ok=SaltArt.resident_texture()!=null
			"brine_tank":ok=preload("res://scripts/salt_brine_art.gd").texture_for(0)!=null # 第 40 章儲滷槽：程式繪製
			_:ok=SaltArt.structure_texture(art)!=null
		expect(ok,"footprint %s has delivered art (%s)"%[item.id,art])
	# Bus shelter: 3 solid cells (TRANSFER = west cell), arrival free, drawn over all three.
	world().switch_region(Salt.REGION)
	for x in range(Salt.BUS_SHELTER.position.x,Salt.BUS_SHELTER.end.x):
		expect(world().blocked(Vector2i(x,Salt.BUS_SHELTER.position.y)) and covered.get(Vector2i(x,Salt.BUS_SHELTER.position.y),"")=="bus_stop","shelter cell (%d,%d) is solid and drawn by the shelter"%[x,Salt.BUS_SHELTER.position.y])
	expect(not world().blocked(Vector2i(Salt.ARRIVAL)) and not covered.has(Vector2i(Salt.ARRIVAL)),"arrival cell west of the shelter stays free")
	world().switch_region(World.REGIONS.HOME)
	# Ground contact of each sprite stays on its footprint (no overhang allowance).
	for id in ["shed","sign","coop_chest","bus_stop"]:
		var image:=SaltArt.structure_texture(id).get_image()
		var widest:=0
		for x0 in image.get_width():
			for y0 in range(image.get_height()-3,image.get_height()):
				if image.get_pixel(x0,y0).a8>8:widest=maxi(widest,x0)
		var leftmost:=image.get_width()
		for x0 in image.get_width():
			for y0 in range(image.get_height()-3,image.get_height()):
				if image.get_pixel(x0,y0).a8>8:leftmost=mini(leftmost,x0)
		var contact:=widest-leftmost+1
		var foot:int={"shed":Salt.SHED.size.x*32,"sign":32,"coop_chest":32,"bus_stop":Salt.BUS_SHELTER.size.x*32}[id]
		print("SALT_SCENE_CONTACT %s %dpx footprint %dpx"%[id,contact,foot])
		expect(contact<=foot,"%s ground contact %dpx fits footprint %dpx"%[id,contact,foot])

	# Terrain: sea west, dike, channels, heritage floor, yard.
	expect(SaltWorldArt.terrain_for(Vector2i(2,20))=="sea" and SaltWorldArt.terrain_for(Vector2i(5,20))=="shore","sea and shoreline west of the dike")
	expect(SaltWorldArt.terrain_for(Vector2i(6,20)).begins_with("sand") and SaltWorldArt.terrain_for(Vector2i(8,13))=="channel" and SaltWorldArt.terrain_for(Vector2i(8,14))=="channel","dike sand and feed channels")
	expect(SaltWorldArt.terrain_for(Vector2i(20,36))=="heritage_floor" and SaltWorldArt.terrain_for(Vector2i(20,34))=="heritage_fence","heritage view floor and rope fence")
	expect(SaltWorldArt.terrain_for(Vector2i(44,19)).begins_with("yard") and SaltWorldArt.terrain_for(Vector2i(14,16))=="plank","work yard and chest-socket planks")

	# Every site is focusable from some walkable cell, with its Chinese label.
	walk_cells=walkable()
	expect(walk_cells.has(Vector2i(Salt.ARRIVAL)),"arrival cell is walkable")
	var site_cells:={}
	for key in ui_points:
		var cell:=cell_for(key)
		site_cells[key]=cell
		expect(cell!=Vector2i(-1,-1),"%s is reachable and focusable on foot"%key)
	await render()
	var focus_checked:=0
	for key in ["salt:worker","salt:gate:0","salt:gate:1","salt:gate:2","salt:pan:0","salt:pan:17","salt:pan:19","salt:lot:0","salt:lot:3:w","salt:lot:8","salt:lot:9","salt:lot:9:w","salt:coop_chest","salt:heritage"]:
		var cell:Vector2i=site_cells.get(key,Vector2i(-1,-1))
		if cell.x<0:continue
		place(Vector2(cell)+Vector2(0.5,0.5))
		aim(Vector2(cell))
		expect(view.interaction_focus()==key,"view focus %s at %s got %s"%[key,cell,view.interaction_focus()])
		await render()
		expect(label_titles(key)==[SaltWorldArt.site_title(key)],"%s label %s"%[key,label_titles(key)])
		focus_checked+=1
	expect(focus_checked==14,"focus checked at 14 representative sites")
	expect(SaltWorldArt.site_title("salt:lot:8")=="保留手作池" and SaltWorldArt.site_title("salt:worker")=="阿曬" and SaltWorldArt.site_title("salt:gate:2")=="第3道閘門","site titles")
	place(Salt.ARRIVAL)
	aim(Salt.ARRIVAL)
	expect(view.interaction_focus()=="transit:bus","arrival focuses the bus stop")
	await render()
	expect(label_titles("transit:bus")==["鹽田站牌"],"bus stop label from transit %s"%[label_titles("transit:bus")])
	place(Vector2(Salt.SALT_WORKER)+Vector2(0.5,2.5))
	await render()
	expect(label_titles("salt:worker")==["阿曬"],"阿曬 always labelled")
	expect(label_titles("salt:gate:0").is_empty() and label_titles("salt:heritage").is_empty(),"unfocused sites unlabelled")
	# No other chapter's focus leaks into beimen.
	var leaked:=false
	for cell:Vector2i in walk_cells:
		var focus:=focus_at(cell)
		if not (focus=="" or focus.begins_with("salt:") or focus.begins_with("transit:")):leaked=true
	expect(not leaked,"beimen focus only salt:/transit: across the walkable land")
	# A chest on a private chest socket uses the ordinary chest focus.
	world().switch_region(Salt.REGION)
	world().state.objects["14,16"]={"type":"chest","owner":ACTOR,"items":{}}
	world().switch_region(World.REGIONS.HOME)
	place(Vector2(14.5,17.5))
	expect(view.interaction_focus()=="14,16","chest on a socket focuses as a chest (%s)"%view.interaction_focus())
	await render()
	world().switch_region(Salt.REGION)
	world().state.objects.erase("14,16")
	world().switch_region(World.REGIONS.HOME)

	# Walking east from the arrival cell stops at the shelter's west wall.
	place(Salt.ARRIVAL)
	var traveller:Dictionary=world().state.players[ACTOR]
	for i in 120:world().move_player(ACTOR,Vector2.RIGHT,0.02)
	expect(float(traveller.x)<float(Salt.BUS_SHELTER.position.x) and absf(float(traveller.y)-Salt.ARRIVAL.y)<0.01,"walking east from arrival is stopped by the shelter (x=%.2f)"%float(traveller.x))
	# Walk: arrival -> 阿曬 -> gate -> public pool -> apprentice station.
	place(Salt.ARRIVAL)
	for site in ["salt:worker","salt:gate:0","salt:lot:8","salt:lot:9"]:
		var walked:=walk_to(site)
		var person:Dictionary=world().state.players[ACTOR]
		send()
		view.display_positions[session.own_id]=Vector2(person.x,person.y)
		expect(walked and view.interaction_focus()==site,"walked to %s (at %.2f,%.2f focus %s)"%[site,person.x,person.y,view.interaction_focus()])

	# ---------------------------------------------- gates: broken vs repaired (pixels)
	view.zoom=2.0
	place(Vector2(10.5,21.5))
	aim(Vector2(10,20))
	var shot:=await capture()
	for gate in 3:
		var tl:=feet_top_left(SaltWorldArt.gate_rect(gate),PropsArt.FOOT_ANCHOR)
		if gate==1:
			expect(error_to(shot,tl,PropsArt.prop_texture("gate_broken"))<error_to(shot,tl,PropsArt.prop_texture("gate_repaired")),"unrepaired gate 1 renders the broken gate")
	var unrepaired_shot:=shot
	unrepaired_shot.save_png(out_dir+"/beimen-unrepaired-1280x800.png")
	for g in 3:
		world().state.salt_pan.gates[g]={"plank":6,"resin":1,"stone":4}
	world().state.salt_pan.repaired_at=1.0
	send()
	expect(SaltWorldArt.gate_repaired(view.data,1) and bool(view.data.salt_pan.repaired),"repaired state visible to the view")
	shot=await capture()
	var tl1:=feet_top_left(SaltWorldArt.gate_rect(1),PropsArt.FOOT_ANCHOR)
	expect(error_to(shot,tl1,PropsArt.prop_texture("gate_repaired"))<error_to(shot,tl1,PropsArt.prop_texture("gate_broken")),"repaired gate 1 renders the repaired gate")

	# ---------------------------------------------- all pan states (dry), machines
	var pans:=pans_mixed()
	machines_mixed()
	send()
	var dry_expect:=["empty","brine","evaporating_1","evaporating_2","salt"]
	var states_ok:=true
	for i in Salt.PAN_COUNT:
		if SaltWorldArt.pan_state(view.data,i)!=dry_expect[i%5]:states_ok=false
	expect(states_ok,"dry day: pans show empty/brine/evaporating_1/evaporating_2/salt")
	# Zoom 1 frames lots 1..3 and their pans (x 8..48, y 5..30) at once.
	view.zoom=1.0
	place(Vector2(21.5,17.5))
	aim(Vector2(28,18))
	view.reduced_motion=true
	view.elapsed=0.5
	shot=await capture()
	for i in [2,3,4,5,6,7]:
		var tl:=Vector2(Salt.pan_rect(i).position)*32
		var mine:String=dry_expect[i%5]
		var other:="salt" if mine!="salt" else "empty"
		expect(error_to(shot,tl,SaltArt.pan_texture(mine))<error_to(shot,tl,SaltArt.pan_texture(other)),"pan %d renders %s"%[i,mine])
	# Machines: lot1 running (wheel+collector), lot2 wheel only (pumping), lot4
	# switched off, lot3/5 bare pads. Stable-base running frames: the idle body
	# is always drawn, only SaltArt.animated_rois change, only while running.
	var w1:=feet_top_left(Salt.wheel_socket(1),SaltArt.MACHINE_ANCHOR)
	var r1:=feet_top_left(Salt.rake_socket(1),SaltArt.MACHINE_ANCHOR)
	var r2:=feet_top_left(Salt.rake_socket(2),SaltArt.MACHINE_ANCHOR)
	var idle_wheel:=PropsArt.prop_texture("waterwheel")
	var idle_rake:=PropsArt.prop_texture("salt_collector")
	expect(SaltWorldArt.wheel_running(view.data,1) and SaltWorldArt.collector_running(view.data,1) and SaltWorldArt.wheel_running(view.data,2),"public active lots run (lot1 wheel+collector, lot2 wheel only)")
	expect(not SaltWorldArt.wheel_running(view.data,4) and not SaltWorldArt.collector_running(view.data,4) and not SaltWorldArt.wheel_running(view.data,3),"switched-off lot4 and unbuilt lot3 stay still")
	expect(error_to(shot,r2,SaltArt.machine_texture("salt_collector_empty"))<error_to(shot,r2,idle_rake),"lot without a collector shows the empty pad")
	expect(error_to(shot,w1,idle_wheel)<0.25 and error_to(shot,r1,idle_rake)<0.25,"lot1 machines drawn from the props idle frames (err %.3f/%.3f)"%[error_to(shot,w1,idle_wheel),error_to(shot,r1,idle_rake)])
	# Keep the player off-camera so only scene art is compared across times.
	place(Salt.ARRIVAL)
	view.zoom=2.0
	aim(Vector2(23,17))
	var times:=[0.0,0.15,0.30]
	view.reduced_motion=true
	var still:=[]
	for t in times:
		view.elapsed=t
		still.append(await capture())
	expect(differing(still[0],still[1])==0 and differing(still[1],still[2])==0,"reduced motion: the whole screen is identical at t=0/0.15/0.30")
	view.reduced_motion=false
	var moving:=[]
	for t in times:
		view.elapsed=t
		moving.append(await capture())
	var rects:=running_rois(view.data)
	expect(rects.size()>=6,"running machines on screen expose their animated regions (%d rects)"%rects.size())
	for k in times.size():
		expect(differing_outside(still[0],moving[k],rects)==0,"t=%s: every pixel outside the running machines' ROIs equals the still frame (sea, channels, pans, bodies)"%times[k])
	for k in range(1,times.size()):
		expect(differing_outside(moving[k-1],moving[k],rects)==0,"t=%s->%s: no change outside the ROIs"%[times[k-1],times[k]])
	for unit in [["wheel",1],["rake",1],["wheel",2]]:
		var tl:=feet_top_left(Salt.wheel_socket(unit[1]) if unit[0]=="wheel" else Salt.rake_socket(unit[1]),SaltArt.MACHINE_ANCHOR)
		var kind:=SaltWorldArt.art_kind(unit[0])
		for k in times.size():
			var phase:=SaltArt.machine_phase(times[k])
			var wrong:=mask_mismatch(still[0],moving[k],tl,SaltArt.prop_texture(kind),SaltArt.running_frame(kind,phase),SaltArt.animated_rois(kind))
			expect(wrong==0,"%s %d at t=%s: screen changes exactly where running phase %d differs from idle (%d wrong px)"%[unit[0],unit[1],times[k],phase,wrong])
		var changed:=0
		for k in range(1,times.size()):
			for roi in SaltArt.animated_rois(kind):changed+=differing_in(moving[k-1],moving[k],roi_screen(tl,roi))
		expect(changed>0,"%s %d: animated region visibly moves over t0->t1->t2 (%d px)"%[unit[0],unit[1],changed])
	# Non-running statuses equal idle: switching lot1 off makes it identical to
	# reduced motion (lot2, a wheel-only unit, keeps pumping and is masked).
	var lots:Array=world().state.salt_pan.lots
	lots[1].on=false
	send()
	expect(not SaltWorldArt.wheel_running(view.data,1) and not SaltWorldArt.collector_running(view.data,1),"switched-off lot1 is not running")
	var lot2_rects:=[]
	var w2:=feet_top_left(Salt.wheel_socket(2),SaltArt.MACHINE_ANCHOR)
	for roi in SaltArt.animated_rois("waterwheel"):lot2_rects.append(roi_screen(w2,roi))
	for t in times:
		view.elapsed=t
		var off_shot:=await capture()
		var off_diff:=differing_outside(still[0],off_shot,lot2_rects)
		expect(off_diff==0,"switched-off lot1 at t=%s draws exactly the idle frames (%d px differ)"%[t,off_diff])
	lots[1].on=true
	send()
	# Salt rain flag (SaltPan public weather.raining): wheel flow stops, collector keeps raking.
	view.data.salt_pan.weather.raining=true
	var wet:=[]
	for t in times:
		view.elapsed=t
		wet.append(await capture())
	var w1_rois:=[]
	for roi in SaltArt.animated_rois("waterwheel"):w1_rois.append(roi_screen(w1,roi))
	var wheel_wet_change:=0
	var rake_wet_change:=0
	for k in range(1,times.size()):
		for roi in w1_rois:wheel_wet_change+=differing_in(wet[k-1],wet[k],roi)
		for roi in SaltArt.animated_rois("salt_collector"):rake_wet_change+=differing_in(wet[k-1],wet[k],roi_screen(r1,roi))
	expect(wheel_wet_change==0,"rain: waterwheel flow region is still (%d px)"%wheel_wet_change)
	expect(rake_wet_change>0,"rain: collector keeps raking (%d px)"%rake_wet_change)
	for roi in w1_rois:expect(differing_in(still[0],wet[1],roi)==0,"rain: waterwheel shows exactly its idle frame")
	send()
	# 3-time crop strip of the running lot1 machines (zoom 2 screen pixels).
	var crop_rect:=Rect2i(Vector2i(((Vector2(Salt.wheel_socket(1).position)*32+Vector2(-32,-48))-view.camera)*view.view_zoom()),Vector2i(Vector2(8,5)*32*view.view_zoom()))
	crop_rect=crop_rect.intersection(Rect2i(Vector2i.ZERO,moving[0].get_size()))
	if crop_rect.has_area():
		var strip:=Image.create_empty(crop_rect.size.x*3+16,crop_rect.size.y,false,Image.FORMAT_RGBA8)
		strip.fill(Color(0.1,0.1,0.1,1))
		for k in times.size():strip.blit_rect(moving[k],crop_rect,Vector2i(k*(crop_rect.size.x+8),0))
		strip.save_png(out_dir+"/beimen-machines-t0t1t2.png")
		var rain_strip:=Image.create_empty(crop_rect.size.x*3+16,crop_rect.size.y,false,Image.FORMAT_RGBA8)
		rain_strip.fill(Color(0.1,0.1,0.1,1))
		for k in times.size():rain_strip.blit_rect(wet[k],crop_rect,Vector2i(k*(crop_rect.size.x+8),0))
		rain_strip.save_png(out_dir+"/beimen-machines-rainflag-t0t1t2.png")
	expect(crop_rect.has_area(),"machine crop strip saved")
	view.elapsed=0.5
	place(Vector2(31.5,24.5))
	aim(Vector2(32,23))
	view.reduced_motion=false
	shot=await capture()
	var w4:=feet_top_left(Salt.wheel_socket(4),SaltArt.MACHINE_ANCHOR)
	expect(error_to(shot,w4,idle_wheel)<0.25,"switched-off unit stays idle even with motion on")
	var w5:=feet_top_left(Salt.wheel_socket(5),SaltArt.MACHINE_ANCHOR)
	expect(error_to(shot,w5,SaltArt.machine_texture("waterwheel_empty"))<error_to(shot,w5,idle_wheel),"unbuilt wheel socket shows the empty foundation")

	# ---------------------------------------------- 阿曬, shed, heritage
	view.reduced_motion=true
	place(Vector2(44.5,19.5))
	aim(Vector2(44,17))
	shot=await capture()
	var ashai_tl:=Vector2(Salt.SALT_WORKER)*32+Vector2(16,30)-Vector2(SaltArt.RESIDENT_FEET)
	expect(error_to(shot,ashai_tl,SaltArt.resident_texture())<0.25,"阿曬 drawn from salt-resident.png (err %.3f)"%error_to(shot,ashai_tl,SaltArt.resident_texture()))
	var shed_tl:=Vector2(SaltWorldArt.rect_center(Salt.SHED).x,Salt.SHED.end.y)*32+Vector2(0,-1)-Vector2(SaltArt.structure_anchor("shed"))
	expect(error_to(shot,shed_tl.round(),SaltArt.structure_texture("shed"))<0.25,"cooperative shed drawn")
	shot.save_png(out_dir+"/beimen-1280x800.png")
	place(Vector2(24.5,32.5))
	aim(Vector2(24,35))
	shot=await capture()
	var floor_tl:=Vector2(20,36)*32
	expect(error_to(shot,floor_tl,SaltArt.terrain_texture("heritage_floor"))<0.2,"heritage tile-pan floor drawn")
	var sign_tl:=Vector2(Salt.HERITAGE_SIGN.x+0.5,Salt.HERITAGE_SIGN.y+1)*32+Vector2(0,-2)-Vector2(SaltArt.structure_anchor("sign"))
	var sign_error:=error_to(shot,sign_tl,SaltArt.structure_texture("sign"))
	expect(sign_error<0.25,"heritage sign drawn (err %.3f)"%sign_error)
	shot.save_png(out_dir+"/beimen-heritage-sign.png")
	expect(view.interaction_focus()=="salt:heritage","standing at the heritage sign focuses it")

	# ---------------------------------------------- rain: diluted / covered
	set_time(rainy)
	pans_mixed()
	send()
	expect(WeatherArt.rains(view.weather_info()),"rain overlay active in beimen")
	var rain_expect:=["empty","diluted","diluted","diluted","covered"]
	states_ok=true
	for i in Salt.PAN_COUNT:
		if SaltWorldArt.pan_state(view.data,i)!=rain_expect[i%5]:states_ok=false
	expect(states_ok,"rainy day: brine pans diluted, salt covered")
	expect(not SaltWorldArt.wheel_running(view.data,1) and SaltWorldArt.collector_running(view.data,1),"rain: wheel paused, collector keeps working")
	view.zoom=1.0
	place(Vector2(21.5,17.5))
	aim(Vector2(28,18))
	shot=await capture()
	for i in [2,4,6]:
		var tl:=Vector2(Salt.pan_rect(i).position)*32
		var want:String=rain_expect[i%5]
		var dry:String=dry_expect[i%5]
		expect(error_to(shot,tl,SaltArt.pan_texture(want))<error_to(shot,tl,SaltArt.pan_texture(dry)),"rain: pan %d renders %s, not %s"%[i,want,dry])
	view.zoom=2.0

	# ---------------------------------------------- captures
	view.reduced_motion=false
	view.elapsed=0.5
	view.zoom=1.0
	place(Vector2(26.5,24.5))
	aim(Vector2(27,25))
	shot=await capture()
	shot.save_png(out_dir+"/beimen-rain-1280x800.png")
	set_time(sunny)
	pans_mixed()
	send()
	root.size=Vector2i(1024,640)
	await process_frame
	shot=await capture()
	expect(shot.get_size()==Vector2i(1024,640),"1024x640 capture size")
	shot.save_png(out_dir+"/beimen-1024x640.png")
	view.zoom=2.0
	place(Vector2(Salt.ARRIVAL))
	aim(Vector2(45,22))
	shot=await capture()
	shot.save_png(out_dir+"/beimen-arrival-1024x640.png")
	root.size=BASE
	await process_frame
	# Shelter pixels at the unscaled base size (1024x640 is stretch-scaled).
	shot=await capture()
	var shelter_tl:=SaltWorldArt.shelter_feet(Vector2.ZERO)-Vector2(SaltArt.structure_anchor("bus_stop"))
	var shelter_err:=error_to(shot,shelter_tl,SaltArt.structure_texture("bus_stop"))
	expect(shelter_err<0.25,"96x64 bus shelter drawn bottom-centred on BUS_SHELTER (err %.3f)"%shelter_err)

	await main_routing(site_cells)
	view.queue_free()
	session.queue_free()
	await process_frame
	print("SALT_PAN_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

# ------------------------------------------------------------------ main.gd routing

func main_routing(site_cells:Dictionary)->void:
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	expect(app.has_method("_interact") and app.session!=null,"main.gd compiles and has a session")
	if not app.has_method("_interact") or app.session==null:
		app.queue_free()
		return
	app.session.set_physics_process(false)
	var game:=World.new()
	game.add_player(ACTOR,"鹽田旅人")
	var record:Dictionary=Salt.RECORD.duplicate(true)
	record.letter=true;record.intro=true
	game.state.salt_pan.players[ACTOR]=record
	app.session.world=game
	app.session.peers={1:ACTOR}
	app.hud.show()
	app.menu.hide()
	var person:Dictionary=game.state.players[ACTOR]
	person.region=Salt.REGION
	var routes:={"salt:worker":"worker","salt:gate:0":"gate:0","salt:pan:0":"pan:0","salt:lot:0":"lot:0","salt:lot:0:w":"lot:0:w","salt:lot:8":"lot:8","salt:lot:9":"lot:9","salt:coop_chest":"coop_chest","salt:heritage":"heritage"}
	for key in routes:
		var cell:Vector2i=site_cells.get(key,Vector2i(-1,-1))
		person.x=cell.x+0.5
		person.y=cell.y+0.5
		app.session._send_snapshot(1)
		app._close_modal()
		app._interact()
		var opened:=""
		if is_instance_valid(app.modal) and app.modal.has_meta("salt_site"):opened=str(app.modal.get_meta("salt_site"))
		expect(opened==routes[key],"E at %s opens SaltPanUI %s (got '%s')"%[key,routes[key],opened])
		await process_frame
	# The panel owns E while open, including at a salt interaction point.
	app.playing=true
	app._process(0.016)
	app.view.queue_redraw()
	await process_frame
	await process_frame
	expect(app.view.interaction_focus().begins_with("salt:") and app.view.focused_label=="","salt prompt hidden while the salt panel is open")
	game.switch_region(Salt.REGION)
	game.state.objects["14,16"]={"type":"chest","owner":ACTOR,"items":{}}
	game.switch_region(World.REGIONS.HOME)
	person.x=14.5;person.y=17.5
	app.session._send_snapshot(1)
	app.view.display_positions[app.session.own_id]=Vector2(14.5,17.5)
	app.view.queue_redraw()
	await process_frame
	await process_frame
	expect(app.view.interaction_focus()=="14,16" and app.view.focused_label=="","chest prompt hidden while the salt panel is open")
	app._close_modal()
	app._process(0.016)
	expect(not app.view.hide_interaction_prompt,"closing the salt panel restores world prompts")
	app.view.queue_redraw()
	await process_frame
	await process_frame
	expect(app.view.focused_label=="14,16","chest prompt back after closing")
	# Chest on a chest socket -> ordinary chest UI; bus stop -> existing transit menu.
	app._interact()
	expect(is_instance_valid(app.modal) and not app.modal.has_meta("salt_site"),"E at a socket chest opens the chest UI, not a salt panel")
	app._close_modal()
	var bus:=cell_for("transit:bus")
	person.x=bus.x+0.5;person.y=bus.y+0.5
	app.session._send_snapshot(1)
	app._interact()
	expect(is_instance_valid(app.modal) and not app.modal.has_meta("salt_site"),"E at the bus stop opens the travel menu")
	app._close_modal()
	app.playing=false
	app.queue_free()
	await process_frame
