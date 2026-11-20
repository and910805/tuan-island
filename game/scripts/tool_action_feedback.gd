extends RefCounted
## T017 hand-tool action feedback (client presentation only; nothing is saved).
##
## Server source: Session adds short-lived public events to each recipient's
## snapshot under `tool_actions` = {"epoch":String,"events":[{n,actor,tool,x,y[,tx,ty]}]}.
## Events exist only after World.act returned ok for a fresh (non-replayed)
## request, and a recipient only receives events from its own region. `actor` is
## the same public id used as the snapshot player key; no inventory, item counts
## or messages are carried. Gather pickups add the public ground item IDs only.
##
## This observer plays each event once. The first snapshot after a (re)join, a
## region change, a different own id or a new server epoch is only a baseline,
## so events already in flight are never replayed. One animation per actor; a
## newer event replaces the held pose; its predecessor's target effect finishes.

const World=preload("res://scripts/world.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const DURATION:=0.55
const TOOLS:=["hoe","seed","water","harvest","axe","pick","build","remove","plant_tree","move_object"]
const STRIKE_TOOLS:=["hoe","axe","pick"]
const SOIL_IMPACT:={"hoe":[0.50,Color("dfb17c")],"seed":[0.68,Color("ffe6a2")],"water":[0.50,Color("a8deec")]}
const LIFE_ICONS:="res://assets/ui-life/icons.png"
## Same cell order as life_ui_shell.gd ICON_IDS (5 columns of 32 px).
const LIFE_ICON_IDS:=["hoe","water","harvest","axe","pick","build","remove","fish","map","journal","weather","calendar","settings","bell","letter","home","sign","trophy","blueprint","chest"]
## Held-tool icon id in LIFE_ICON_IDS (seed / plant_tree use inventory item icons).
const HELD_ICON:={"hoe":"hoe","water":"water","harvest":"harvest","axe":"axe","pick":"pick","build":"build","remove":"remove","fish":"fish","move_object":"chest"}
## Static pose used with reduced motion (and the rest pose at the end of a swing).
const REST_ANGLE:={"hoe":0.35,"axe":0.35,"pick":0.35,"water":0.8,"seed":0.3,"harvest":-0.3,"build":0.0,"remove":-0.5,"plant_tree":0.6,"move_object":0.0}
const PARTICLE_COLORS:={"hoe":[Color("8a6142"),Color("a77b52")],"axe":[Color("c99a5b"),Color("e2bd84")],
	"pick":[Color("9ea3a0"),Color("c7c9c2")],"water":[Color("8fcbe0"),Color("c4e6f0")],"seed":[Color("e9d18a"),Color("c9a95e")],
	"harvest":[Color("fff1a8"),Color("b3d894")],"build":[Color("efe3c4"),Color("d8c9a3")],"remove":[Color("d9cdb0"),Color("b9a987")],
	"plant_tree":[Color("8fc46e"),Color("6fa653")],"move_object":[Color("e6dcc4"),Color("cfc2a2")]}

static var icon_cache:Dictionary={}

var epoch:=""
var region:=""
var own:=""
var last_n:=0
var initialized:=false
var actions:Dictionary={}
## Interrupted successful actions finish their target effects, never their held pose.
## Bounded and client-local; reset/region changes discard all pending effects.
var tails:Array[Dictionary]=[]
const MAX_TAILS:=32
const FINISH_DURATION:=0.75
var finishes:Dictionary={}
const PICKUP_DURATION:=1.18
var pickups:Dictionary={}

func reset() -> void:
	epoch=""
	region=""
	own=""
	last_n=0
	initialized=false
	actions.clear()
	tails.clear()
	finishes.clear()
	pickups.clear()

## Returns the actors whose animation started from this snapshot (for tests).
func observe(previous:Dictionary,snapshot:Dictionary,own_id:String,elapsed:float) -> Array:
	var started:Array=[]
	var players:Dictionary=snapshot.get("players",{}) if snapshot.get("players") is Dictionary else {}
	for key in finishes.keys():
		if elapsed-float(finishes[key].started)>=FINISH_DURATION:finishes.erase(key)
	for key in pickups.keys():
		if not players.has(pickups[key].actor) or elapsed-float(pickups[key].started)>=PICKUP_DURATION:pickups.erase(key)
	tails=tails.filter(func(record):return players.has(record.actor) and elapsed-float(record.started)<DURATION)
	for actor in actions.keys():
		if not players.has(actor) or elapsed-float(actions[actor].started)>=DURATION:actions.erase(actor)
	var payload=snapshot.get("tool_actions",{})
	var next_epoch:=""
	var events:Array=[]
	var cursor:=0
	if payload is Dictionary:
		next_epoch=str(payload.get("epoch",""))
		if payload.get("cursor") is int:cursor=payload.cursor
		if payload.get("events") is Array:
			for event in payload.events:
				if valid_event(event):events.append(event)
	events.sort_custom(func(a,b):return int(a.n)<int(b.n))
	var next_region:=str(snapshot.get("region_id","home"))
	if not initialized or next_epoch!=epoch or next_region!=region or own_id!=own:
		# Baseline only: whatever is already listed happened before we could see it.
		actions.clear()
		tails.clear()
		finishes.clear()
		pickups.clear()
		epoch=next_epoch
		region=next_region
		own=own_id
		last_n=maxi(cursor,int(events.back().n) if not events.is_empty() else 0)
		initialized=true
		return started
	for event in events:
		var n:=int(event.n)
		if n<=last_n:continue
		last_n=n
		var actor:String=event.actor
		if not players.has(actor):continue
		if event.tool=="gather_pickup":
			pickups[n]={"actor":actor,"cell":Vector2i(int(event.x),int(event.y)),"started":elapsed,"items":event.items,"collected":true}
			if pickups.size()>MAX_TAILS:pickups.erase(pickups.keys()[0])
			continue
		var person:Dictionary=players[actor]
		var cell:=Vector2i(int(event.x),int(event.y))
		var record:={"tool":String(event.tool),"started":elapsed,"cell":cell,"to":cell,
			"origin":Vector2(float(person.get("x",cell.x+0.5)),float(person.get("y",cell.y+0.5))),"item":"","n":n}
		if event.tool=="move_object" and event.has("tx") and event.has("ty"):record.to=Vector2i(int(event.tx),int(event.ty))
		var crop_key:=World.key(cell)
		if event.tool in ["axe","pick"]:
			var was_planted:bool=previous.get("forest",{}).get(crop_key,{}).get("mature",false)
			var lost_planted:bool=was_planted and not snapshot.get("forest",{}).has(crop_key)
			var lost_natural:bool=not previous.get("removed",{}).has(crop_key) and snapshot.get("removed",{}).has(crop_key)
			var resource:="tree" if was_planted else World.base_resource(cell,next_region)
			if (lost_planted or lost_natural) and not snapshot.has("gather_drops"):
				var items:Array=[]
				match resource:
					"tree":items=["wood","hardwood" if was_planted else "resin"]
					"rock":items=["stone"]
					"grass":items=["fiber"]
				if not items.is_empty():
					pickups[crop_key]={"actor":actor,"cell":cell,"started":elapsed,"items":items}
					if pickups.size()>MAX_TAILS:pickups.erase(pickups.keys()[0])
			if (lost_planted or lost_natural) and resource==("tree" if event.tool=="axe" else "rock"):
				finishes[crop_key]={"kind":resource,"started":elapsed,"cell":cell}
				if finishes.size()>MAX_TAILS:finishes.erase(finishes.keys()[0])
		if event.tool=="seed":
			var kind:=str(snapshot.get("crops",{}).get(crop_key,{}).get("kind",""))
			record.item=kind+"_seed" if not kind.is_empty() else ""
		elif event.tool=="harvest":
			record.item=str(previous.get("crops",{}).get(crop_key,{}).get("kind",""))
		elif event.tool=="plant_tree":
			record.item="sapling"
		if actions.has(actor):
			var previous_action:Dictionary=actions[actor].duplicate()
			previous_action.actor=actor
			tails.append(previous_action)
			if tails.size()>MAX_TAILS:tails.pop_front()
		actions[actor]=record
		if actor not in started:started.append(actor)
	last_n=maxi(last_n,cursor)
	return started

static func valid_event(event:Variant) -> bool:
	if not event is Dictionary:return false
	for field in ["n","x","y"]:
		if not (event.get(field) is int or event.get(field) is float):return false
	if not event.get("actor") is String or String(event.actor).length()!=16:return false
	if not event.get("tool") is String:return false
	if event.tool=="gather_pickup":
		if not event.get("items") is Array or event.items.is_empty() or event.items.size()>World.SAVE_SCHEMA.GATHER_ITEMS.size():return false
		for item in event.items:
			if item not in World.SAVE_SCHEMA.GATHER_ITEMS:return false
	elif event.tool not in TOOLS:return false
	if int(event.n)<=0 or absi(int(event.x))>1000 or absi(int(event.y))>1000:return false
	return true

func active(actor:String,elapsed:float) -> Dictionary:
	var record:Dictionary=actions.get(actor,{})
	if record.is_empty() or elapsed-float(record.started)>=DURATION:return {}
	return record

func target_tails(actor:String,elapsed:float) -> Array[Dictionary]:
	return tails.filter(func(record):return record.actor==actor and elapsed-float(record.started)<DURATION)

func resource_finish(cell:Vector2i,elapsed:float,reduced:bool) -> Dictionary:
	if reduced:return {}
	var record:Dictionary=finishes.get(World.key(cell),{})
	if record.is_empty():return {}
	var age:=elapsed-float(record.started)
	if age<0.0 or age>=FINISH_DURATION:return {}
	var progress:=clampf((age-DURATION*0.5)/(FINISH_DURATION-DURATION*0.5),0.0,1.0)
	return {"kind":record.kind,"progress":progress,"alpha":1.0-smoothstep(0.30,1.0,progress)}

static func pickup_pose(age:float,origin:Vector2,collector:Vector2,reduced:bool)->Dictionary:
	if age<0.36 or age>=PICKUP_DURATION:return {}
	if reduced:return {"position":origin,"height":0.0,"alpha":1.0}
	if age<0.64:
		var fall:=(age-0.36)/0.28
		return {"position":origin,"height":lerpf(10.0,0.0,fall)+sin(fall*PI)*13.0,"alpha":1.0}
	var pull:=smoothstep(0.82,PICKUP_DURATION,age)
	return {"position":origin.lerp(collector,pull),"height":9.0*sin(PI*pull),"alpha":1.0-smoothstep(0.74,1.0,pull)}

## Resource sprites react to confirmed contact, including interrupted swings.
## The world cell/collision stays fixed; callers transform only the existing art.
func resource_pose(cell:Vector2i,tool:String,elapsed:float,reduced:bool) -> Dictionary:
	var result:={"angle":0.0,"shift":Vector2.ZERO}
	if reduced or tool not in ["axe","pick"]:return result
	var newest:=-INF
	for record:Dictionary in actions.values()+tails:
		if record.tool!=tool or record.cell!=cell:continue
		var age:=elapsed-float(record.started)
		if age<0.5*DURATION or age>=DURATION:continue
		newest=maxf(newest,float(record.started))
	if newest==-INF:return result
	var phase:=clampf((elapsed-newest-0.5*DURATION)/(0.5*DURATION),0.0,1.0)
	var recoil:=sin(phase*TAU*2.0)*(1.0-phase)
	if tool=="axe":result.angle=recoil*0.055
	else:result.shift=Vector2(roundf(recoil*2.0),0)
	return result

## A watered plant gives a small settling nod; its root, soil and collision stay
## fixed. Only confirmed live water events count, including interrupted pours.
func crop_press(cell:Vector2i,elapsed:float,reduced:bool) -> int:
	if reduced:return 0
	var newest:=-INF
	for record:Dictionary in actions.values()+tails:
		if record.tool=="water" and record.cell==cell:
			newest=maxf(newest,float(record.started))
	if newest==-INF:return 0
	var phase:=(elapsed-newest)/DURATION
	if phase<0.28 or phase>=1.0:return 0
	return roundi(2.0*sin(PI*(phase-0.28)/0.72))

## Both the held PNG and its outgoing particles use the same moving hand.
static func hand_grip(foot:Vector2,pose:Dictionary) -> Vector2:
	var shoulder:=(Vector2(pose.facing)*float(pose.body_lean)).round()
	return (foot+pose.hand+pose.lunge+Vector2(0,pose.lift if pose.tool=="move_object" else 0.0)).round()+Vector2(shoulder.x,absf(shoulder.y))

static func harvest_center(cell_at:Vector2,foot:Vector2,pose:Dictionary,progress:float) -> Vector2:
	var root:=cell_at+Vector2(16,17)
	if pose.reduced:return root
	var lift:=smoothstep(0.12,0.40,progress)
	var travel:=smoothstep(0.34,0.80,progress)
	# Use the mouth of the existing held basket, rotated with the same grip.
	var mouth:=hand_grip(foot,pose)+Vector2(0,-10).rotated(float(pose.angle))
	return (root.lerp(mouth,travel)+Vector2(0,-lift*(1.0-travel)*20.0)).round()

static func facing_toward(origin:Vector2,cell:Vector2i,fallback:Vector2i) -> Vector2i:
	var towards:=Vector2(cell)+Vector2(0.5,0.5)-origin
	if towards.length()<=0.25:return fallback
	if absf(towards.x)>absf(towards.y):return Vector2i(int(signf(towards.x)),0)
	return Vector2i(0,int(signf(towards.y)))

## Pure pose/particle plan for one frame. `hand` and `lunge` are pixels from the
## actor's foot point; particle `pos` is pixels from the target cell's top-left
## (the destination cell for move_object). With reduced motion the tool is shown
## in a fixed pose: no swing, no body lunge, no lift and no particles.
static func plan(tool:String,progress:float,reduced:bool,facing:Vector2i=Vector2i.DOWN) -> Dictionary:
	var t:=clampf(progress,0.0,1.0)
	var side:=-1.0 if facing==Vector2i.LEFT else 1.0
	var hand:=Vector2(side*11.0,-18.0)
	if facing==Vector2i.DOWN:hand=Vector2(10,-16)
	# Keep the rear hand outside the wide hat silhouette; the tool still sorts
	# behind the body, so its exposed edge reads without cutting across the face.
	elif facing==Vector2i.UP:hand=Vector2(-18,-23)
	if tool=="move_object":hand=Vector2(0,-40)
	var result:={"tool":tool,"hand":hand,"angle":float(REST_ANGLE.get(tool,0.0))*side,"lunge":Vector2.ZERO,
		"lift":0.0,"particles":[],"alpha":1.0,"crop_scale":1.0,"reduced":reduced,"body_lean":0.0}
	if reduced or not tool in TOOLS:return result
	var toward:=Vector2(facing)
	var colors:Array=PARTICLE_COLORS.get(tool,[Color.WHITE,Color.WHITE])
	var particles:Array=[]
	var angle:=0.0
	if tool in STRIKE_TOOLS:
		result.body_lean=roundf(3.0*smoothstep(0.36,0.53,t)*(1.0-smoothstep(0.62,1.0,t)))
		if t<0.4:angle=lerpf(0.0,-1.5,ease(t/0.4,0.5))
		elif t<0.55:angle=lerpf(-1.5,0.7,(t-0.4)/0.15)
		else:angle=lerpf(0.7,0.35,(t-0.55)/0.45)
		if t>=0.4 and t<0.75:result.lunge=toward*2.0
		if t>=0.5:
			var k:=(t-0.5)/0.5
			var count:=6 if tool=="hoe" else 4
			for i in count:
				var base:=Vector2(10.0+i*(12.0/(count-1)),22.0)
				var velocity:=Vector2((i-(count-1)*0.5)*10.0,-26.0-i*4.0)
				var tint:Color=colors[i%2]
				tint.a=1.0-smoothstep(0.55,1.0,k)
				particles.append({"pos":(base+velocity*k+Vector2(0,30.0*k*k)).round(),"size":Vector2(2,2) if tool=="pick" else Vector2(3,2),"color":tint})
			if tool=="pick" and k<0.35:particles.append({"pos":Vector2(15,18),"size":Vector2(2,2),"color":Color("fff0a8")})
	elif tool=="water":
		result.body_lean=roundf(3.0*smoothstep(0.0,0.22,t)*(1.0-smoothstep(0.65,1.0,t)))
		angle=0.9*smoothstep(0.0,0.24,t)*(1.0-smoothstep(0.68,1.0,t))
		for i in 5:
			var age:=(t-0.18-i*0.075)/0.32
			if age<0.0 or age>=1.8:continue
			var x:=8.0+i*4.0
			if age<1.0:
				var height:=3.0+age*age*19.0
				particles.append({"pos":Vector2(x,height).round(),"size":Vector2(2,4),"color":colors[i%2]})
			else:
				var splash:=(age-1.0)/0.8
				var tint:Color=colors[i%2]
				tint.a=1.0-splash
				for side_offset in [-1.0,1.0]:
					var position:=Vector2(x+side_offset*(1.0+4.0*splash),23.0-sin(splash*PI)*4.0)
					particles.append({"pos":position.round(),"size":Vector2(2,1),"color":tint})
	elif tool=="seed":
		result.body_lean=roundf(4.0*sin(PI*smoothstep(0.0,0.86,t)))
		angle=0.78*sin(PI*clampf(t/0.58,0.0,1.0))
		for i in 3:
			var fall:=(t-0.2-i*0.055)/0.48
			if fall<0.0 or fall>=1.45:continue
			var across:=minf(fall,1.0)
			var height:=lerpf(5.0,21.0,across*across)-sin(across*PI)*7.0
			var bounce:=(fall-1.0)/0.45
			if bounce>0.0:height-=sin(bounce*PI)*4.0
			var tint:Color=colors[i%2]
			tint.a=1.0-maxf(0.0,bounce)
			var position:=Vector2(16.0+(i-1)*(3.0+across*6.0),height).round()
			particles.append({"pos":position,"size":Vector2(2,3),"color":tint})
	elif tool=="harvest":
		# Reach first, then straighten as the crop comes free. Boots stay planted.
		result.body_lean=roundf(5.0*smoothstep(0.0,0.20,t)*(1.0-smoothstep(0.25,0.64,t)))
		angle=lerpf(0.0,-0.4,clampf(t/0.3,0.0,1.0))
		var pop:=smoothstep(0.12,0.44,t)
		result.crop_scale=1.0+0.22*sin(pop*PI)-0.32*smoothstep(0.62,0.86,t)
		result.alpha=1.0-smoothstep(0.71,0.90,t)
		if t>=0.3:
			for i in 3:
				particles.append({"pos":Vector2(6.0+i*9.0,roundf(10.0-(t-0.3)*14.0+(i%2)*4.0)),"size":Vector2(2,2),"color":colors[i%2]})
	elif tool=="build":
		angle=-0.9*maxf(0.0,sin(t*TAU*2.0))
		for window in [[0.25,0.5],[0.75,1.0]]:
			if t>=window[0] and t<window[1]:
				var k:=(t-float(window[0]))/0.25
				for i in 3:
					particles.append({"pos":Vector2(roundf(16.0+(i-1)*(4.0+k*8.0)),roundf(26.0-k*4.0)),"size":Vector2(3,2),"color":colors[i%2]})
	elif tool=="remove":
		angle=lerpf(0.4,-0.8,ease(t,0.6))
		if t>=0.3:
			var k:=(t-0.3)/0.7
			for i in 4:
				particles.append({"pos":Vector2(roundf(16.0+(i-1.5)*(5.0+k*10.0)),roundf(24.0-k*10.0+(i%2)*3.0)),"size":Vector2(3,2),"color":colors[i%2]})
	elif tool=="plant_tree":
		angle=0.6+0.3*sin(PI*t)
		if t>=0.2 and t<0.6:result.lunge=toward*1.5+Vector2(0,1)
		if t>=0.35:
			for i in 3:
				particles.append({"pos":Vector2(8.0+i*8.0,roundf(18.0-(t-0.35)*20.0-(i%2)*3.0)),"size":Vector2(2,2),"color":colors[i%2]})
	elif tool=="move_object":
		angle=0.15*sin(t*TAU)
		result.lift=-roundf(sin(t*PI)*4.0)
		if t>=0.7:
			var k:=(t-0.7)/0.3
			for i in 3:
				particles.append({"pos":Vector2(roundf(16.0+(i-1)*(6.0+k*8.0)),roundf(28.0-k*3.0)),"size":Vector2(3,2),"color":colors[i%2]})
	result.angle=angle*side
	result.particles=particles
	return result

## Outgoing seeds and water start at the tool, then meet the existing
## cell-local bounce and splash effects. Coordinates stay in world-view pixels.
static func farm_trail(tool:String,progress:float,grip:Vector2,cell_at:Vector2) -> Array[Vector2]:
	var points:Array[Vector2]=[]
	if tool not in ["seed","water"]:return points
	var watering:=tool=="water"
	var count:=5 if watering else 3
	var stagger:=0.075 if watering else 0.055
	var arrival:=0.18 if watering else 0.2
	for i in count:
		var travel:=(progress-arrival-i*stagger+0.16)/0.16
		if travel<0.0 or travel>=1.0:continue
		var landing:=Vector2(8+i*4,3) if watering else Vector2(13+i*3,5)
		var arc:=sin(travel*PI)*(9.0 if watering else 15.0)
		points.append((grip.lerp(cell_at+landing,travel)-Vector2(0,arc)).round())
	return points

## Each kernel lands at the end of its existing staggered flight (0.2 +
## i*0.055 + 0.48). Tiny local soil flecks replace a whole-cell seed flash.
## Presentation only: kernels are decorative, never three inventory items.
static func seed_contacts(progress:float,reduced:bool) -> Array[Dictionary]:
	var contacts:Array[Dictionary]=[]
	if reduced or progress>=1.0:return contacts
	for i in 3:
		var age:=(progress-(0.68+i*0.055))/0.20
		if age<0.0 or age>=1.0:continue
		var tint:=Color("d7b386")
		tint.a=1.0-smoothstep(0.0,1.0,age)
		contacts.append({"center":Vector2(7+i*9,21),"spread":roundf(1.0+age*4.0),
			"lift":roundf(sin(age*PI)*2.0),"color":tint})
	return contacts

## Four short dashes follow the furrows outward from the impact.
static func soil_impact(tool:String,progress:float,reduced:bool) -> Dictionary:
	if reduced or not SOIL_IMPACT.has(tool):return {}
	var cue:Array=SOIL_IMPACT[tool]
	var age:=(progress-float(cue[0]))/(1.0-float(cue[0]))
	if age<0.0 or age>=1.0:return {}
	var tint:Color=cue[1]
	tint.a=0.95*(1.0-smoothstep(0.12,1.0,age))
	return {"spread":roundf(3.0+7.0*age),"color":tint}

## Existing 32px pixel icons only (ui-life tool atlas / inventory item atlas);
## returns null rather than drawing a substitute shape.
static func held_icon(tool:String,item:String="") -> Texture2D:
	var id:=str(HELD_ICON.get(tool,""))
	if tool=="seed":id="item:"+(item if not item.is_empty() else "radish_seed")
	elif tool=="plant_tree":id="item:sapling"
	if id.is_empty():return null
	if icon_cache.has(id):return icon_cache[id]
	var texture:Texture2D=null
	if id.begins_with("item:"):
		texture=Items.icon(id.trim_prefix("item:"))
	else:
		var index:=LIFE_ICON_IDS.find(id)
		if index>=0 and ResourceLoader.exists(LIFE_ICONS):
			var atlas:=AtlasTexture.new()
			atlas.atlas=load(LIFE_ICONS)
			atlas.region=Rect2((index%5)*32,floori(index/5.0)*32,32,32)
			atlas.filter_clip=true
			texture=atlas
	icon_cache[id]=texture
	return texture
