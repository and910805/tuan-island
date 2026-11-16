@static_unload
extends RefCounted
## Beimen 鹽風合作鹽田 world scene (display only), chapter 4.
## Static drawing helpers used by world_view.gd's beimen branch, modelled on
## flower_world_art.gd. Everything is drawn from delivered formal art:
## SaltArt (terrain, pan states, machine working/empty frames, structures,
## 阿曬) and the staged SaltPropsArt (gates, idle machines). Missing art draws
## nothing: there are no geometric stand-ins. Geometry and collision come from
## SaltPan; nothing here changes collision, routing or state.
##
## Motion is real feedback only, on a pixel-stable base (root-reviewed staged
## adapter): the idle machine body is always drawn and only SaltArt's clipped
## animated regions change (waterwheel: its own water pixels advance along the
## flume/outlet, the wheel does NOT rotate; collector: tray rake + salt grains),
## and only while that unit is running and reduced motion is off. Rain stops
## the wheel's flow but not the collector. Ground tiles (sea, channels) and
## pans are static: no whole-tile/whole-frame alternation, no brine_alt, no
## invented glints. 阿曬 does not blink (not root-approved).

const Salt=preload("res://scripts/salt_pan.gd")
const SaltArt=preload("res://scripts/salt_art.gd")
const PropsArt=preload("res://scripts/salt_props_art.gd")
const BrineArt=preload("res://scripts/salt_brine_art.gd")
const SaltBrine=preload("res://scripts/salt_brine.gd")
## Focus/label key of the 儲滷槽 (main.gd routes "salt:" keys to SaltPanUI.open).
const BRINE_TANK_SITE:="salt:brine_tank"

const RADIUS:=3.2
const RESIDENT_SITES:=["salt:worker"]
## Own-unit status ids that never show motion even when the public view says
## the unit is active (SaltPan.STATUS_IDS).
const STILL_STATUSES:=["off","invalid","unset","owner","full","waiting"]
## Work yard around the shed, 阿曬, the cooperative chest and the bus stop.
const YARD:=Rect2i(40,11,12,17)
## Outside LAND but not west of the dike: neighbouring coastal scrub (not walkable).
const SCRUB_TINT:=Color(0.82,0.84,0.76)

# ---------------------------------------------------------------- snapshot reads

static func shared(data:Dictionary)->Dictionary:
	var value=data.get("salt_pan",{})
	return value if value is Dictionary else {}

static func now(data:Dictionary)->float:
	var value=data.get("time",0.0)
	return float(value) if (value is float or value is int) else 0.0

static func raining(data:Dictionary)->bool:
	var weather=shared(data).get("weather",{})
	if weather is Dictionary and weather.has("raining"):return bool(weather.raining)
	return Salt.raining(now(data))

static func pan_data(data:Dictionary,i:int)->Dictionary:
	var pans=shared(data).get("pans",[])
	if pans is Array and i>=0 and i<pans.size() and pans[i] is Dictionary:return pans[i]
	return Salt.fresh_pan()

## Art state of pan i at the snapshot time (SaltPan.pan_view decides
## diluted/covered from the weather at that time).
static func pan_state(data:Dictionary,i:int)->String:
	return view_state(Salt.pan_view(pan_data(data,i),now(data)))

## pan_view -> one of SaltArt.PAN_STATES (never brine_alt).
static func view_state(view:Dictionary)->String:
	match str(view.get("s","empty")):
		"salt":return "covered" if bool(view.get("covered",false)) else "salt"
		"brine":
			if bool(view.get("diluted",false)):return "diluted"
			var ratio:=float(view.get("ratio",0.0))
			if ratio>=2.0/3.0:return "evaporating_2"
			if ratio>=1.0/3.0:return "evaporating_1"
			return "brine"
	return "empty"

static func gate_repaired(data:Dictionary,gate:int)->bool:
	var salt:=shared(data)
	if bool(salt.get("repaired",false)):return true
	var gates=salt.get("gates",[])
	if not gates is Array or gate<0 or gate>=gates.size() or not gates[gate] is Dictionary:return false
	for id in Salt.GATE_NEEDS_EACH:
		if int(gates[gate].get(id,0))<int(Salt.GATE_NEEDS_EACH[id]):return false
	return true

## Public machine view of a lot (0..7 private, APPRENTICE_LOT); {} otherwise.
static func unit(data:Dictionary,lot:int)->Dictionary:
	var salt:=shared(data)
	var value=null
	if lot==Salt.APPRENTICE_LOT:value=salt.get("apprentice",{})
	elif lot>=0 and lot<Salt.LOT_COUNT:
		var lots=salt.get("lots",[])
		if lots is Array and lot<lots.size():value=lots[lot]
	return value if value is Dictionary else {}

## The local player's own unit status id when `lot` is that unit, else "".
static func own_status(data:Dictionary,lot:int)->String:
	var own=shared(data).get("own",{})
	if not own is Dictionary:return ""
	var mine=own.get("unit",{})
	if not mine is Dictionary or str(mine.get("kind",""))=="":return ""
	var index:=int(mine.get("index",-1))
	if str(mine.kind)=="apprentice":index=Salt.APPRENTICE_LOT
	if index!=lot:return ""
	var status=mine.get("status",{})
	return str(status.get("id","")) if status is Dictionary else ""

## Waterwheel flows when installed and public-active (on, or no collector
## yet) and it is not raining (SaltPan refuses wheel fills on rainy days). The
## local player's own unit also honours off/invalid/unset/owner/full/waiting.
static func wheel_running(data:Dictionary,lot:int)->bool:
	var cfg:=unit(data,lot)
	if not bool(cfg.get("wheel",false)) or not bool(cfg.get("active",false)):return false
	if raining(data):return false
	return not own_status(data,lot) in STILL_STATUSES

## Collector rakes when installed with a public-active wheel; it keeps working
## in rain. The own unit honours the same still statuses.
static func collector_running(data:Dictionary,lot:int)->bool:
	var cfg:=unit(data,lot)
	if not bool(cfg.get("rake",false)) or not bool(cfg.get("active",false)):return false
	return not own_status(data,lot) in STILL_STATUSES

## SaltArt machine kind for a scene kind ("wheel"/"rake").
static func art_kind(kind:String)->String:
	return "waterwheel" if kind=="wheel" else "salt_collector"

## The exact texture drawn on a socket: the empty pad when nothing is built,
## otherwise SaltArt.machine_frame (the identical idle texture object unless
## running with motion on; running = stable idle base + clipped animated regions).
static func machine_texture_for(kind:String,installed:bool,running:bool,elapsed:float,reduced_motion:bool,wet:bool=false)->Texture2D:
	var base:=art_kind(kind)
	if not installed:return SaltArt.machine_texture(base+"_empty")
	return SaltArt.machine_frame(base,"running" if running else "idle",elapsed,reduced_motion,wet and base=="waterwheel")

## Frame name for diagnostics/tests: "empty", "idle" or "run:<phase>".
static func machine_frame(installed:bool,running:bool,elapsed:float,reduced_motion:bool)->String:
	if not installed:return "empty"
	if not running or reduced_motion:return "idle"
	return "run:%d"%SaltArt.machine_phase(elapsed)

static func machine_lots()->Array:
	var lots:=[]
	for lot in Salt.LOT_COUNT:lots.append(lot)
	lots.append(Salt.APPRENTICE_LOT)
	return lots

# ---------------------------------------------------------------- sites / focus

static func rect_center(rect:Rect2i)->Vector2:
	return Vector2(rect.position)+Vector2(rect.size)/2.0

static func gate_rect(gate:int)->Rect2i:
	return Rect2i(8,int(Salt.GATE_ROWS[gate])+1,2,1)

## Same keys and points as SaltPanUI.interaction_points("beimen") (tested).
static func sites()->Dictionary:
	var points:Dictionary={}
	points["salt:worker"]=Vector2(Salt.SALT_WORKER)+Vector2(0.5,0.5)
	for gate in range(Salt.GATE_ROWS.size()):points["salt:gate:%d"%gate]=rect_center(gate_rect(gate))
	for pan in range(Salt.PAN_COUNT):points["salt:pan:%d"%pan]=rect_center(Salt.pan_rect(pan))
	for lot in range(Salt.LOT_COUNT):
		points["salt:lot:%d"%lot]=rect_center(Salt.rake_socket(lot))
		points["salt:lot:%d:w"%lot]=rect_center(Salt.wheel_socket(lot))
	points["salt:lot:%d"%Salt.APPRENTICE_LOT]=rect_center(Salt.rake_socket(Salt.APPRENTICE_LOT))
	points["salt:lot:%d:w"%Salt.APPRENTICE_LOT]=rect_center(Salt.wheel_socket(Salt.APPRENTICE_LOT))
	points["salt:lot:%d"%Salt.PUBLIC_LOT]=Vector2(Salt.PUBLIC_SIGN)+Vector2(0.5,0.5)
	points["salt:coop_chest"]=Vector2(Salt.APPRENTICE_CHEST)+Vector2(0.5,0.5)
	points["salt:heritage"]=Vector2(Salt.HERITAGE_SIGN)+Vector2(0.5,0.5)
	return points

static func site_title(id:String)->String:
	var parts:=id.trim_prefix("salt:").split(":")
	match parts[0]:
		"worker":return "阿曬"
		"gate":return "第%d道閘門"%(int(parts[1])+1) if parts.size()>1 else "閘門"
		"pan":return "鹽田"
		"lot":
			var lot:=int(parts[1]) if parts.size()>1 else -1
			if lot==Salt.PUBLIC_LOT:return "保留手作池"
			if parts.size()>2:return "水車"
			return "學徒區收鹽台" if lot==Salt.APPRENTICE_LOT else "收鹽台"
		"coop_chest":return "合作社收鹽箱"
		"heritage":return "瓦盤鹽田觀景區"
	return ""

## Same rule as main.gd _interact for beimen: salt sites first, then transit
## stops, then interactive objects; strict nearest within 3.2 tiles.
static func focus(position:Vector2,transit_points:Dictionary,objects:Dictionary,object_types:Array)->String:
	var points:=sites()
	for gate in transit_points:points["transit:"+str(gate)]=Vector2(transit_points[gate].cell)+Vector2(0.5,0.5)
	for key in objects:
		if objects[key] is Dictionary and objects[key].get("type","") in object_types:
			var parts:=str(key).split(",")
			if parts.size()==2:points[key]=Vector2(int(parts[0]),int(parts[1]))+Vector2(0.5,0.5)
	var closest:=""
	var distance:=RADIUS
	for key in points:
		var candidate:=position.distance_to(points[key])
		if candidate<distance:
			distance=candidate
			closest=key
	return closest

# ---------------------------------------------------------------- footprints

## Ground footprint of every fixed blocking thing the scene draws (sprites and
## channel water). Their union over LAND must equal SaltPan.blocked (tested).
static func footprints()->Array:
	var list:=[]
	for gate in range(Salt.GATE_ROWS.size()):
		var oy:int=Salt.GATE_ROWS[gate]
		list.append({"id":"gate:%d"%gate,"rect":gate_rect(gate),"art":"gate"})
		list.append({"id":"channel:%d:n"%gate,"rect":Rect2i(8,oy,2,1),"art":"channel"})
		list.append({"id":"channel:%d:s"%gate,"rect":Rect2i(8,oy+2,2,1),"art":"channel"})
	for pan in range(Salt.PAN_COUNT):list.append({"id":"pan:%d"%pan,"rect":Salt.pan_rect(pan),"art":"pan"})
	for lot in machine_lots():
		list.append({"id":"wheel:%d"%lot,"rect":Salt.wheel_socket(lot),"art":"machine"})
		list.append({"id":"rake:%d"%lot,"rect":Salt.rake_socket(lot),"art":"machine"})
	list.append({"id":"public_sign","rect":Rect2i(Salt.PUBLIC_SIGN,Vector2i.ONE),"art":"sign"})
	list.append({"id":"heritage_sign","rect":Rect2i(Salt.HERITAGE_SIGN,Vector2i.ONE),"art":"sign"})
	list.append({"id":"worker","rect":Rect2i(Salt.SALT_WORKER,Vector2i.ONE),"art":"resident"})
	list.append({"id":"bus_stop","rect":Salt.BUS_SHELTER,"art":"bus_stop"})
	list.append({"id":"coop_chest","rect":Rect2i(Salt.APPRENTICE_CHEST,Vector2i.ONE),"art":"coop_chest"})
	list.append({"id":"heritage","rect":Salt.HERITAGE_VIEW,"art":"heritage_floor"})
	list.append({"id":"shed","rect":Salt.SHED,"art":"shed"})
	# 第 40 章儲滷槽：procedural art (salt_brine_art.gd), not a SaltArt structure.
	list.append({"id":"brine_tank","rect":Rect2i(Salt.BRINE_TANK,Vector2i.ONE),"art":"brine_tank"})
	return list

# ---------------------------------------------------------------- ground

static func hashed(p:Vector2i)->int:
	return absi(p.x*7127+p.y*19391)

## Terrain name (SaltArt.TERRAIN key) for one cell, stable per coordinate.
static func terrain_for(p:Vector2i)->String:
	var h:=hashed(p)
	var land:=Salt.LAND
	if not Salt.land(p):
		if p.x<land.position.x:
			return "shore" if p.x==land.position.x-1 and p.y>=land.position.y and p.y<land.end.y else "sea"
		return "coast_b" if h%3==0 else "coast"
	if Salt.water(p) or Salt.gate_at(p)>=0:return "channel"
	if p.x<8:return "sand_b" if h%4==0 else "sand"
	if Salt.HERITAGE_VIEW.has_point(p):
		return "heritage_fence" if p.y==Salt.HERITAGE_VIEW.position.y or p.y==Salt.HERITAGE_VIEW.end.y-1 else "heritage_floor"
	if Salt.chest_socket_lot(p)>=0 or p==Salt.APPRENTICE_CHEST:return "plank"
	# Covered ditch between each gate and the first lot's waterwheel.
	if p.x==10 and Salt.GATE_ROWS.has(p.y-1):return "plank"
	if YARD.has_point(p):return "yard_b" if h%5==0 else "yard"
	if p.x<YARD.position.x and p.y<=Salt.HERITAGE_VIEW.position.y-1:return "ridge_b" if h%3==0 else "ridge"
	return "coast_b" if h%3==0 else "coast"

## One static ground cell (sea/channel never flip: their A/B tiles differ in
## almost every pixel). Returns false when the terrain sheet is missing.
static func ground(canvas:CanvasItem,at:Vector2,p:Vector2i,_data:Dictionary,_elapsed:float,_reduced_motion:bool)->bool:
	var tile:=terrain_for(p)
	var texture:=SaltArt.terrain_texture(tile)
	if texture==null:return false
	var tint:=SCRUB_TINT if (not Salt.land(p) and tile.begins_with("coast")) else Color.WHITE
	canvas.draw_texture_rect(texture,Rect2(at,Vector2(32,32)),false,tint)
	return true

# ---------------------------------------------------------------- flat layer

## Pans (3x3 flat sprites, static state art) drawn after the ground pass,
## before tall rows. Returns label entries [anchor, site_id].
static func draw_pans(canvas:CanvasItem,origin:Vector2,data:Dictionary,_elapsed:float,_reduced_motion:bool)->Array:
	var labels:=[]
	for i in range(Salt.PAN_COUNT):
		var rect:=Salt.pan_rect(i)
		var at:=origin+Vector2(rect.position)*32
		var texture:=SaltArt.pan_texture(pan_state(data,i))
		if texture:canvas.draw_texture(texture,at.round())
		labels.append([at+Vector2(48,6),"salt:pan:%d"%i])
	return labels

# ---------------------------------------------------------------- rows

static func feet_of(origin:Vector2,cell:Vector2i)->Vector2:
	return origin+Vector2(cell)*32+Vector2(16,30)

static func draw_machine(canvas:CanvasItem,feet:Vector2,texture:Texture2D)->bool:
	return SaltArt.draw_anchored(canvas,texture,feet,SaltArt.MACHINE_ANCHOR)

## Bottom-centre feet of the 3-tile bus shelter (BUS_SHELTER; TRANSFER = west cell).
static func shelter_feet(origin:Vector2)->Vector2:
	var rect:Rect2i=Salt.BUS_SHELTER
	return origin+Vector2(rect.position.x+rect.size.x*0.5,rect.end.y)*32+Vector2(0,-2)

static func draw_structure(canvas:CanvasItem,feet:Vector2,id:String)->bool:
	return SaltArt.draw_anchored(canvas,SaltArt.structure_texture(id),feet,SaltArt.structure_anchor(id))

## Tall props and 阿曬 whose feet sit on row `y`, in feet order. Returns the
## labels to place as [anchor, site_id] pairs.
static func draw_row(canvas:CanvasItem,origin:Vector2,y:int,data:Dictionary,elapsed:float,reduced_motion:bool)->Array:
	var labels:=[]
	var wet:=raining(data)
	for gate in range(Salt.GATE_ROWS.size()):
		var rect:=gate_rect(gate)
		if rect.position.y!=y:continue
		var feet:=origin+Vector2(rect.position.x+1,y+1)*32
		PropsArt.draw_prop(canvas,"gate_repaired" if gate_repaired(data,gate) else "gate_broken",feet)
		labels.append([feet+Vector2(0,-42),"salt:gate:%d"%gate])
	for lot in machine_lots():
		var cfg:=unit(data,lot)
		var wheel:=Salt.wheel_socket(lot)
		if wheel.position.y==y:
			var feet:=origin+Vector2(wheel.position.x+1,y+1)*32
			draw_machine(canvas,feet,machine_texture_for("wheel",bool(cfg.get("wheel",false)),wheel_running(data,lot),elapsed,reduced_motion,wet))
			labels.append([feet+Vector2(0,-58),"salt:lot:%d:w"%lot])
		var rake:=Salt.rake_socket(lot)
		if rake.position.y==y:
			var feet:=origin+Vector2(rake.position.x+1,y+1)*32
			draw_machine(canvas,feet,machine_texture_for("rake",bool(cfg.get("rake",false)),collector_running(data,lot),elapsed,reduced_motion,wet))
			labels.append([feet+Vector2(0,-56),"salt:lot:%d"%lot])
	if y==Salt.BRINE_TANK.y:
		# 第 40 章儲滷槽 (the one procedural prop here, by design: salt_brine_art.gd).
		# Drawn before the shed row; its 32x48 canvas stays inside column BRINE_TANK.x,
		# right of the shed sprite's edge, so neither covers the other.
		var tank_at:=origin+Vector2(Salt.BRINE_TANK)*32
		BrineArt.draw_tank(canvas,tank_at,SaltBrine.level(data))
		labels.append([tank_at+BrineArt.LABEL_OFFSET,BRINE_TANK_SITE])
	if y==Salt.SHED.end.y-1:
		draw_structure(canvas,origin+Vector2(rect_center(Salt.SHED).x,Salt.SHED.end.y)*32+Vector2(0,-1),"shed")
	if y==Salt.SALT_WORKER.y:
		var feet:=feet_of(origin,Salt.SALT_WORKER)
		SaltArt.draw_anchored(canvas,SaltArt.resident_texture("front"),feet,SaltArt.RESIDENT_FEET)
		labels.append([feet+Vector2(0,-50),"salt:worker"])
	if y==Salt.APPRENTICE_CHEST.y:
		var feet:=origin+Vector2(Salt.APPRENTICE_CHEST.x+0.5,y+1)*32+Vector2(0,-2)
		draw_structure(canvas,feet,"coop_chest")
		labels.append([feet+Vector2(0,-24),"salt:coop_chest"])
	if y==Salt.BUS_SHELTER.end.y-1:
		var feet:=shelter_feet(origin)
		draw_structure(canvas,feet,"bus_stop")
		labels.append([feet+Vector2(0,-66),"transfer"])
	if y==Salt.PUBLIC_SIGN.y:
		var feet:=origin+Vector2(Salt.PUBLIC_SIGN.x+0.5,y+1)*32+Vector2(0,-2)
		draw_structure(canvas,feet,"sign")
		labels.append([feet+Vector2(0,-30),"salt:lot:%d"%Salt.PUBLIC_LOT])
	if y==Salt.HERITAGE_SIGN.y:
		var feet:=origin+Vector2(Salt.HERITAGE_SIGN.x+0.5,y+1)*32+Vector2(0,-2)
		draw_structure(canvas,feet,"sign")
		labels.append([feet+Vector2(0,-30),"salt:heritage"])
	return labels
