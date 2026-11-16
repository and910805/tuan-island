extends RefCounted
## T017 hand-tool action feedback (client presentation only; nothing is saved).
##
## Server source: Session adds short-lived public events to each recipient's
## snapshot under `tool_actions` = {"epoch":String,"events":[{n,actor,tool,x,y[,tx,ty]}]}.
## Events exist only after World.act returned ok for a fresh (non-replayed)
## request, and a recipient only receives events from its own region. `actor` is
## the same public id used as the snapshot player key; no inventory, item counts
## or messages are carried.
##
## This observer plays each event once. The first snapshot after a (re)join, a
## region change, a different own id or a new server epoch is only a baseline,
## so events already in flight are never replayed. One animation per actor; a
## newer event replaces the older one.

const World=preload("res://scripts/world.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const DURATION:=0.55
const TOOLS:=["hoe","seed","water","harvest","axe","pick","build","remove","plant_tree","move_object"]
const STRIKE_TOOLS:=["hoe","axe","pick"]
const LIFE_ICONS:="res://assets/ui-life/icons.png"
## Same cell order as life_ui_shell.gd ICON_IDS (5 columns of 32 px).
const LIFE_ICON_IDS:=["hoe","water","harvest","axe","pick","build","remove","fish","map","journal","weather","calendar","settings","bell","letter","home","sign","trophy","blueprint","chest"]
## Held-tool icon id in LIFE_ICON_IDS (seed / plant_tree use inventory item icons).
const HELD_ICON:={"hoe":"hoe","water":"water","harvest":"harvest","axe":"axe","pick":"pick","build":"build","remove":"remove","move_object":"chest"}
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

func reset() -> void:
	epoch=""
	region=""
	own=""
	last_n=0
	initialized=false
	actions.clear()

## Returns the actors whose animation started from this snapshot (for tests).
func observe(previous:Dictionary,snapshot:Dictionary,own_id:String,elapsed:float) -> Array:
	var started:Array=[]
	var players:Dictionary=snapshot.get("players",{}) if snapshot.get("players") is Dictionary else {}
	for actor in actions.keys():
		if not players.has(actor) or elapsed-float(actions[actor].started)>=DURATION:actions.erase(actor)
	var payload=snapshot.get("tool_actions",{})
	var next_epoch:=""
	var events:Array=[]
	if payload is Dictionary:
		next_epoch=str(payload.get("epoch",""))
		if payload.get("events") is Array:
			for event in payload.events:
				if valid_event(event):events.append(event)
	events.sort_custom(func(a,b):return int(a.n)<int(b.n))
	var next_region:=str(snapshot.get("region_id","home"))
	if not initialized or next_epoch!=epoch or next_region!=region or own_id!=own:
		# Baseline only: whatever is already listed happened before we could see it.
		actions.clear()
		epoch=next_epoch
		region=next_region
		own=own_id
		last_n=int(events.back().n) if not events.is_empty() else 0
		initialized=true
		return started
	for event in events:
		var n:=int(event.n)
		if n<=last_n:continue
		last_n=n
		var actor:String=event.actor
		if not players.has(actor):continue
		var person:Dictionary=players[actor]
		var cell:=Vector2i(int(event.x),int(event.y))
		var record:={"tool":String(event.tool),"started":elapsed,"cell":cell,"to":cell,
			"origin":Vector2(float(person.get("x",cell.x+0.5)),float(person.get("y",cell.y+0.5))),"item":"","n":n}
		if event.tool=="move_object" and event.has("tx") and event.has("ty"):record.to=Vector2i(int(event.tx),int(event.ty))
		var crop_key:=World.key(cell)
		if event.tool=="seed":
			var kind:=str(snapshot.get("crops",{}).get(crop_key,{}).get("kind",""))
			record.item=kind+"_seed" if not kind.is_empty() else ""
		elif event.tool=="harvest":
			record.item=str(previous.get("crops",{}).get(crop_key,{}).get("kind",""))
		elif event.tool=="plant_tree":
			record.item="sapling"
		actions[actor]=record
		if actor not in started:started.append(actor)
	return started

static func valid_event(event:Variant) -> bool:
	if not event is Dictionary:return false
	for field in ["n","x","y"]:
		if not (event.get(field) is int or event.get(field) is float):return false
	if not event.get("actor") is String or String(event.actor).length()!=16:return false
	if not event.get("tool") is String or not String(event.tool) in TOOLS:return false
	if int(event.n)<=0 or absi(int(event.x))>1000 or absi(int(event.y))>1000:return false
	return true

func active(actor:String,elapsed:float) -> Dictionary:
	var record:Dictionary=actions.get(actor,{})
	if record.is_empty() or elapsed-float(record.started)>=DURATION:return {}
	return record

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
	elif facing==Vector2i.UP:hand=Vector2(-9,-22)
	if tool=="move_object":hand=Vector2(0,-40)
	var result:={"tool":tool,"hand":hand,"angle":float(REST_ANGLE.get(tool,0.0))*side,"lunge":Vector2.ZERO,
		"lift":0.0,"particles":[],"alpha":1.0,"reduced":reduced}
	if reduced or not tool in TOOLS:return result
	var toward:=Vector2(facing)
	var colors:Array=PARTICLE_COLORS.get(tool,[Color.WHITE,Color.WHITE])
	var particles:Array=[]
	var angle:=0.0
	if tool in STRIKE_TOOLS:
		if t<0.4:angle=lerpf(0.0,-1.5,ease(t/0.4,0.5))
		elif t<0.55:angle=lerpf(-1.5,0.7,(t-0.4)/0.15)
		else:angle=lerpf(0.7,0.35,(t-0.55)/0.45)
		if t>=0.4 and t<0.75:result.lunge=toward*2.0
		if t>=0.5:
			var k:=(t-0.5)/0.5
			for i in 4:
				var base:=Vector2(10.0+i*4.0,22.0)
				var velocity:=Vector2((i-1.5)*10.0,-26.0-i*4.0)
				particles.append({"pos":(base+velocity*k+Vector2(0,40.0*k*k)).round(),"size":Vector2(3,2) if tool=="axe" else Vector2(2,2),"color":colors[i%2]})
			if tool=="pick" and k<0.35:particles.append({"pos":Vector2(15,18),"size":Vector2(2,2),"color":Color("fff0a8")})
	elif tool=="water":
		angle=lerpf(0.0,0.9,clampf(t/0.3,0.0,1.0))
		if t>=0.25:
			for i in 5:
				var d:=fposmod((t-0.25)*2.2+i*0.2,1.0)
				particles.append({"pos":Vector2(8.0+i*4.0,roundf(2.0+d*22.0)),"size":Vector2(2,3),"color":colors[i%2]})
	elif tool=="seed":
		angle=0.5*sin(PI*clampf(t/0.4,0.0,1.0))
		if t>=0.2:
			var k:=clampf((t-0.2)/0.5,0.0,1.0)
			for i in 3:
				particles.append({"pos":Vector2(10.0+i*6.0,roundf(2.0+k*20.0-sin(k*PI)*6.0)),"size":Vector2(2,2),"color":colors[i%2]})
	elif tool=="harvest":
		angle=lerpf(0.0,-0.4,clampf(t/0.3,0.0,1.0))
		result.lift=-roundf(t*14.0)
		result.alpha=1.0-t*0.6
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
