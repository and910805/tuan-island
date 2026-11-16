extends SceneTree
## 望安開場 logic test (headless): chapter_one.STARTER_PLOT + first_crop_step and
## wangan_opening.is_new_arrival.
##
## PRESET / FIXTURE (not human play):
##  * a real Session hosts an isolated save in %TEMP% (deleted at the end); its own
##    player A is the host. Session physics is switched off so world time and
##    movement only advance when this test calls World.move_player / World.step;
##  * other players (B, C, D) are added with World.add_player (no network peer);
##    their client snapshots are built with Session.public_state + public-id owner,
##    the projection every recipient gets (own-id keyed players, hashed owners);
##  * old-save shapes are written directly into fresh World.state copies
##    (chapter_one.shipped / harvests, picnic, missing chapter_one, region);
##  * the occupied-plot case fills the plot with D's real hoe/build actions after
##    giving D building materials by writing D's inventory.
## REALLY EXERCISED: World.move_player walking from SPAWN to the plot and to the
##  shipping bin; World.act hoe / seed / water / harvest / ship; World.step growing
##  the crop; World.save + World.load_world; Session._send_snapshot round trips.
const World=preload("res://scripts/world.gd")
const Chapter=preload("res://scripts/chapter_one.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const SessionScript=preload("res://scripts/session.gd")
var checks:=0
var failures:=0
var session
var w
var a:=""
var path:=""
var seq:=0

func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func finish()->void:
	if session!=null and is_instance_valid(session):
		session.shutdown()
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WANGAN_OPENING_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func _initialize()->void:
	run.call_deferred()

func act(world,token:String,action:String,cell:Vector2i,extra:String="")->Dictionary:
	seq+=1
	return world.act(token,"wangan-%d"%seq,action,cell,extra)

func step_of(state:Dictionary,owner:String)->Dictionary:
	return Chapter.first_crop_step(state,owner)

func public_id(token:String)->String:
	return token.sha256_text().left(16)

## The host's own client snapshot (real round trip).
func client()->Dictionary:
	session._send_snapshot(1)
	return session.snapshot

## Another player's client projection (Session.public_state; owners and chapter
## keys become public ids, as Session._send_snapshot sends them).
func projection_for(token:String)->Dictionary:
	var out:Dictionary=session.public_state("home")
	check(out.get("players",{}).has(public_id(token)) and not out.get("players",{}).has(token),"Projection keys %s by public id"%token)
	return out

## Server step == client step, and the call leaves both dictionaries untouched.
func same_step(label:String)->Dictionary:
	var server_before:Dictionary=w.state.duplicate(true)
	var server:=step_of(w.state,a)
	check(w.state==server_before and var_to_bytes(w.state)==var_to_bytes(server_before),"first_crop_step does not mutate server state (%s)"%label)
	var snap:=client()
	var snap_before:Dictionary=snap.duplicate(true)
	var mine:=step_of(snap,session.own_id)
	check(snap==snap_before,"first_crop_step does not mutate the client snapshot (%s)"%label)
	check(server==mine,"Server state and client snapshot give the same step (%s): %s vs %s"%[label,str(server),str(mine)])
	return server

func walk(token:String,goal:Vector2,world=null)->bool:
	if world==null:world=w
	# Axis by axis, the way a held movement key moves the player.
	for axis in [0,1]:
		for i in 400:
			var p:Dictionary=world.state.players[token]
			var here:=Vector2(float(p.x),float(p.y))
			var delta:float=goal[axis]-here[axis]
			if absf(delta)<0.06:break
			var direction:=Vector2.ZERO
			direction[axis]=signf(delta)*minf(1.0,absf(delta)/(3.6*0.05))
			world.move_player(token,direction,0.05)
	var p:Dictionary=world.state.players[token]
	return Vector2(float(p.x),float(p.y)).distance_to(goal)<0.1

func grow(token:String)->void:
	for i in 30:
		if step_of(w.state,token).get("id","")!="wait":return
		w.step(5.0,true)

# --------------------------------------------------------------- plot cells --

func reserved_cells(world)->Dictionary:
	var out:={}
	for cell in World.SHIPPING.CANDIDATES:out[cell]="shipping"
	for cell in World.MARKET.CANDIDATES:out[cell]="market"
	for cell in World.HARVEST.CELLS:out[cell]="harvest_relay"
	out[World.FISH_MEET.SIGN]="fish_meet_sign"
	for cell in World.FISH_MEET.SHORE:out[cell]="fish_meet_shore"
	out[World.SHOWCASE.SIGN]="showcase_sign"
	for cell in World.SHOWCASE.cells():out[cell]="showcase"
	for list in [World.RESIDENT_BOND.RANCH_CELLS,World.RESIDENT_BOND.DOCK_CELLS,World.RESIDENT_BOND.POST_CELLS,World.RESIDENT_BOND.BELL_CELLS]:
		for cell in list:out[cell]="walk_up_resident"
	for cell in World.COMMUNITY.CANDIDATES:out[cell]="community_table"
	for id in World.Village.NPCS:
		if World.Village.npc_region(id)=="home":out[World.Village.NPCS[id].cell]="resident_"+id
	for id in World.Village.FESTIVAL_SPOTS:out[World.Village.FESTIVAL_SPOTS[id]]="festival_spot"
	out[World.Festival.TREE_CELL]="festival_tree"
	for cell in World.Festival.VISITORS:out[cell]="festival_visitor"
	for cell in World.Festival.STOPS:out[cell]="festival_bell"
	out[Chapter.STARTER_CELL]="starter_cell"
	out[Vector2i(World.SPAWN.floor())]="spawn"
	out[Vector2i(World.REGIONS.spawn(World.REGIONS.HOME).floor())]="home_spawn"
	out[World.REGIONS.exit_cell(World.REGIONS.HOME)]="exit"
	var home_station:Dictionary=World.TRANSIT.STATIONS.home
	out[home_station.cell]="ferry_point"
	out[Vector2i((home_station.arrival as Vector2).floor())]="ferry_arrival"
	for gate in World.TRANSIT.points("home"):out[World.TRANSIT.points("home")[gate].cell]="transit_"+str(gate)
	for id in World.LIVESTOCK.ANIMALS:out[World.LIVESTOCK.ANIMALS[id].cell]="livestock"
	out[World.COPPER_CELL]="copper"
	for id in Chapter.STEPS:out[Chapter.STEPS[id].cell]="chapter_npc_"+id
	return out

func plot_checks()->void:
	var fresh=World.new()
	check(Chapter.STARTER_PLOT.size()>=4 and Chapter.STARTER_PLOT.size()<=6,"Plot has 4-6 cells: %d"%Chapter.STARTER_PLOT.size())
	var unique:={}
	for cell in Chapter.STARTER_PLOT:unique[cell]=true
	check(unique.size()==Chapter.STARTER_PLOT.size(),"Plot cells are distinct")
	var stall:Vector2i=Chapter.STEPS.grow.cell
	var reserved:=reserved_cells(fresh)
	for cell:Vector2i in Chapter.STARTER_PLOT:
		var tag:=str(cell)
		check(World.land(cell) and not fresh.water(cell),"Plot cell %s is dry land"%tag)
		check(World.base_resource(cell)=="" and fresh.resource(cell)=="","Plot cell %s has no fixed tree/rock/grass tuft"%tag)
		check(not fresh.protected(cell),"Plot cell %s is not a protected/public cell"%tag)
		check(not fresh.blocked(cell) and fresh.can_stand(Vector2(cell)+Vector2(0.5,0.5)),"Plot cell %s is walkable"%tag)
		check(not reserved.has(cell),"Plot cell %s is not reserved (%s)"%[tag,str(reserved.get(cell,""))])
		check(Vector2(cell).distance_to(Vector2(stall))<=5.0,"Plot cell %s is close to Xiaoli's stall %s"%[tag,str(stall)])
		for layer in ["crops","objects","ground","roofs","forest"]:
			check(not fresh.state[layer].has(World.key(cell)),"Plot cell %s starts without %s (not pre-tilled)"%[tag,layer])
		# The stand-north cell is how the plot is worked; trees/props must not sit there.
		check(World.base_resource(cell+Vector2i.DOWN)=="","Cell below %s has no fixed tree whose canopy hides the plot"%tag)
	# Reachable on foot from SPAWN (4-neighbour flood over blocked()).
	var start:=Vector2i(World.SPAWN.floor())
	var seen:={start:true}
	var queue:Array[Vector2i]=[start]
	while not queue.is_empty():
		var at:Vector2i=queue.pop_front()
		for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var next:Vector2i=at+d
			if seen.has(next) or next.x<0 or next.y<0 or next.x>=World.SIZE.x or next.y>=World.SIZE.y:continue
			if fresh.blocked(next):continue
			seen[next]=true
			queue.append(next)
	for cell in Chapter.STARTER_PLOT:check(seen.has(cell),"Plot cell %s reachable on foot from SPAWN"%str(cell))
	check(Chapter.FIRST_CROP_STEPS==["find","till","sow","water","wait","harvest","ship"],"Step ids are exactly find..ship")
	check(Opening.OPENING_LINE=="小栗在渡口旁留了一塊地給你。先種一株蘿蔔，收成後帶到出貨箱。","Opening line is the design book's line verbatim")

# ------------------------------------------------------------ full sequence --

func sequence()->void:
	var start:=same_step("fresh")
	check(start.get("id","")=="find" and Chapter.STARTER_PLOT.has(start.get("cell",Vector2i(-1,-1))),"Fresh player at SPAWN: find, pointing at a plot cell: %s"%str(start))
	check(Opening.is_new_arrival(w.state,a) and Opening.is_new_arrival(client(),session.own_id),"Fresh player at SPAWN is a new arrival (server and client)")
	check(int(w.state.players[a].inventory.get("radish_seed",0))==5,"Starting bag still holds the five existing radish seeds (no extra grant)")
	# Second player B joins and works one plot cell first.
	var b:="wangan-second-player"
	w.add_player(b,"二號")
	session.peers[901]=b  # PRESET: fake online peer so Session.public_state projects B
	check(step_of(w.state,b).get("id","")=="find","B starts at find too")
	check(walk(b,Vector2(45.5,33.5)) and walk(b,Vector2(47.5,28.5)),"B walks to the plot")
	check(step_of(w.state,b).get("id","")=="till","B next to the plot: till")
	check(act(w,b,"hoe",Vector2i(47,27)).ok,"B tills plot cell (47,27)")
	check(step_of(w.state,b).get("id","")=="sow","B's own soil: sow")
	var after_b:=same_step("B tilled a plot cell")
	check(after_b.get("id","")=="find" and after_b.get("cell")!=Vector2i(47,27),"B's soil does not advance my steps nor stay my target: %s"%str(after_b))
	var client_b:=projection_for(b)
	check(step_of(client_b,public_id(b))==step_of(w.state,b),"B: client projection gives B's server step")
	# Walk to the plot with real movement.
	check(walk(a,Vector2(45.5,33.5)) and walk(a,Vector2(45.5,28.5)),"A walks from SPAWN to the plot")
	check(not Opening.is_new_arrival(w.state,a),"Walking away from the landing ends the arrival card condition")
	var till:=same_step("at the plot")
	check(till.get("id","")=="till" and till.get("text","")=="用鋤頭在小栗留的田翻一格土","At the plot: till: %s"%str(till))
	check(act(w,a,"hoe",Vector2i(45,27)).ok,"A tills (45,27)")
	var sow:=same_step("tilled")
	check(sow.get("id","")=="sow" and sow.get("cell")==Vector2i(45,27) and str(sow.text).contains("蘿蔔"),"Tilled: sow radish at (45,27): %s"%str(sow))
	check(act(w,a,"seed",Vector2i(45,27),"radish").ok,"A sows radish")
	var water:=same_step("sown")
	check(water.get("id","")=="water" and water.get("cell")==Vector2i(45,27),"Sown: water: %s"%str(water))
	# Save + reload mid-sequence gives the same step.
	check(w.save(),"World saves mid-sequence")
	var reloaded=World.new()
	check(reloaded.load_world(w.save_path),"Saved world reloads")
	check(step_of(reloaded.state,a)==water,"Reloaded save gives the same step: %s"%str(step_of(reloaded.state,a)))
	check(step_of(reloaded.state,b)==step_of(w.state,b),"Reloaded save gives B the same step")
	check(act(w,a,"water",Vector2i(45,27)).ok,"A waters")
	var wait:=same_step("watered")
	check(wait.get("id","")=="wait","Watered: wait: %s"%str(wait))
	# B's progress stays independent.
	check(step_of(w.state,b).get("id","")=="sow","B is still at sow while A waits")
	grow(a)
	var harvest:=same_step("grown")
	check(harvest.get("id","")=="harvest" and harvest.get("cell")==Vector2i(45,27),"Grown: harvest: %s"%str(harvest))
	check(step_of(w.state,b).get("id","")=="sow","A's mature crop does not move B")
	check(act(w,a,"harvest",Vector2i(45,27)).ok,"A harvests")
	var ship:=same_step("harvested")
	check(ship.get("id","")=="ship" and ship.get("text","")=="把蘿蔔帶到出貨箱" and ship.get("cell")==World.SHIPPING.cell_for(w.state),"Harvested: ship to the shipping bin: %s"%str(ship))
	check(step_of(w.state,b).get("id","")=="sow","A's harvest record does not move B to ship")
	check(walk(a,Vector2(45.5,32.5)) and walk(a,Vector2(42.5,32.5)),"A walks to the shipping bin")
	var payload:=JSON.stringify([[["radish",1]],int(World.CROPS.radish.price)])
	check(act(w,a,"ship",World.SHIPPING.cell_for(w.state),payload).ok,"A ships the radish")
	check(same_step("shipped").is_empty(),"After the first shipment the first-crop steps are over")
	check(step_of(w.state,b).is_empty(),"The world's first shipment also ends B's opening guidance (shared chapter)")
	check(not Opening.marker_shown(w.state,a) and not Opening.marker_shown(client(),session.own_id),"Plot marker gone after the shipment")

# --------------------------------------------------------- planted elsewhere --

func elsewhere()->void:
	var world=World.new()
	var c:="wangan-elsewhere"
	world.add_player(c,"三號")
	check(walk(c,Vector2(36.5,34.5),world),"C walks west of SPAWN")
	check(step_of(world.state,c).get("id","")=="find","C away from the plot: find")
	check(act(world,c,"hoe",Vector2i(36,35)).ok,"C tills outside the plot")
	check(not Chapter.STARTER_PLOT.has(Vector2i(36,35)),"(36,35) is outside the plot")
	check(step_of(world.state,c).get("id","")=="sow" and step_of(world.state,c).get("cell")==Vector2i(36,35),"Soil outside the plot advances to sow")
	check(act(world,c,"seed",Vector2i(36,35),"radish").ok and step_of(world.state,c).get("id","")=="water","Sown outside: water")
	check(act(world,c,"water",Vector2i(36,35)).ok and step_of(world.state,c).get("id","")=="wait","Watered outside: wait")
	check(Opening.marker_shown(world.state,c),"Marker still shown (free plot) while C grows elsewhere")

# -------------------------------------------------------------- occupied plot --

func occupied()->void:
	var world=World.new()
	var d:="wangan-occupier"
	var me:="wangan-late"
	world.add_player(d,"佔地")
	world.add_player(me,"晚到")
	var person:Dictionary=world.state.players[d]
	person.inventory.wood=200
	person.inventory.stone=200
	person.x=46.5;person.y=28.5
	var cells:=Chapter.STARTER_PLOT
	for i in cells.size():
		var cell:Vector2i=cells[i]
		var result:Dictionary
		if i%2==0:result=act(world,d,"hoe",cell)
		else:result=act(world,d,"build",cell,"floor")
		check(result.ok,"D occupies %s: %s"%[str(cell),str(result)])
		if i==2:
			var partly:=step_of(world.state,me)
			check(partly.get("id","")=="find" and Chapter.starter_plot_free(world.state).has(partly.get("cell")),"Partly occupied: target is a still-free plot cell: %s"%str(partly))
	check(Chapter.starter_plot_free(world.state).is_empty(),"All plot cells occupied")
	var fallback:=step_of(world.state,me)
	check(fallback.get("id","")=="till" and fallback.get("cell")==Chapter.NO_PLOT_CELL and str(fallback.get("text","")).contains("附近任一塊空草地"),"Occupied plot: any-free-grass wording, no unusable target: %s"%str(fallback))
	check(not Opening.marker_shown(world.state,me),"Occupied plot: no marker for me")
	check(Opening.marker_shown(world.state,d),"The occupier with own soil there still sees the marker")
	check(step_of(world.state,d).get("id","")=="sow","D's own soil in the plot: sow")
	# Planting elsewhere still advances my steps.
	var p:Dictionary=world.state.players[me]
	p.x=36.5;p.y=34.5
	check(act(world,me,"hoe",Vector2i(36,35)).ok and step_of(world.state,me).get("id","")=="sow","Fallback grass works: sow")

# ----------------------------------------------------------- old save shapes --

func old_saves()->void:
	var world=World.new()
	var t:="wangan-old"
	world.add_player(t,"老島民")
	var base:Dictionary=world.state.duplicate(true)
	var shipped:Dictionary=base.duplicate(true)
	shipped.chapter_one.shipped=true
	shipped.board=true
	shipped.picnic=true
	check(step_of(shipped,t).is_empty(),"Already shipped + picnic done: nothing")
	check(not Opening.is_new_arrival(shipped,t),"Already shipped world: no arrival card")
	var ready_to_ship:Dictionary=base.duplicate(true)
	ready_to_ship.chapter_one.harvests[t]={"radish":2}
	ready_to_ship.players[t].inventory.radish=1
	ready_to_ship.players[t].harvests=2
	var ship:=step_of(ready_to_ship,t)
	check(ship.get("id","")=="ship" and ship.get("cell")==World.SHIPPING.CELL,"Old save with a harvest record and radish: ship: %s"%str(ship))
	check(not Opening.is_new_arrival(ready_to_ship,t),"Returning player with harvests: no arrival card")
	ready_to_ship.objects[World.key(World.SHIPPING.CELL)]={"type":"chest","owner":t,"items":{}}
	check(step_of(ready_to_ship,t).get("cell")==World.SHIPPING.CANDIDATES[1],"Ship points at the bin's fallback cell when the first is occupied")
	var lettuce:Dictionary=base.duplicate(true)
	lettuce.chapter_one.harvests[t]={"lettuce":1}
	lettuce.players[t].inventory.lettuce=1
	check(step_of(lettuce,t).get("text","")=="把收成帶到出貨箱","Other crop harvested: generic ship wording")
	var sold:Dictionary=base.duplicate(true)
	sold.chapter_one.harvests[t]={"radish":1}
	sold.players[t].inventory.erase("radish")
	check(step_of(sold,t).get("id","") in ["find","till"],"Harvest record but sold everything: back to planting: %s"%str(step_of(sold,t)))
	var legacy:Dictionary=base.duplicate(true)
	legacy.erase("chapter_one")
	check(step_of(legacy,t).is_empty(),"State without chapter_one: nothing")
	var away:Dictionary=base.duplicate(true)
	away.players[t].region="lanyang"
	check(step_of(away,t).is_empty() and not Opening.is_new_arrival(away,t),"Player in another region: nothing")
	var region_snapshot:Dictionary=base.duplicate(true)
	region_snapshot.region_id="lanyang"
	check(step_of(region_snapshot,t).is_empty(),"Non-home snapshot: nothing")
	check(step_of(base,"nobody").is_empty() and not Opening.is_new_arrival(base,"nobody"),"Unknown owner: nothing")
	var no_seeds:Dictionary=base.duplicate(true)
	no_seeds.crops["46,27"]={"kind":"","growth":0.0,"wet":false,"owner":t}
	for item in no_seeds.players[t].inventory.keys():
		if str(item).ends_with("_seed"):no_seeds.players[t].inventory.erase(item)
	check(step_of(no_seeds,t).get("id","")=="sow" and str(step_of(no_seeds,t).text).contains("買種子"),"Soil but no seeds: sow via buying seeds")
	check(base==world.state,"Old-save probes never touched the world state")

func run()->void:
	var watchdog:=create_timer(110.0)
	watchdog.timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	path=OS.get_environment("TEMP").path_join("wangan-opening-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	session=SessionScript.new()
	root.add_child(session)
	if session.host(0,"望安旅人",path)!=OK:
		check(false,"Session hosts")
		finish()
		return
	session.set_physics_process(false)
	w=session.world
	a=session.profile.token
	check(w.state.players.has(a) and session.own_id==public_id(a),"Host player joined with a public id")
	plot_checks()
	sequence()
	elsewhere()
	occupied()
	old_saves()
	finish()
