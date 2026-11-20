extends RefCounted
## Warm lantern night: three shared paper-lantern statues (grove / lane / harbor) drawn from the
## existing assets/ui-life/paper-tea-lamp.png plus original pixel overlays. Display only: this
## script reads the public snapshot `warm_lantern_night` and the rules script's STATIONS dict
## (cell,title,hint) and never changes gameplay. Lit lamps tint the paper, cast a coloured
## ground pool (drawn by WorldView under sprites) and flicker by at most one pixel / a few
## percent of glow; reduced motion and photo mode are fully still.

const Night=preload("res://scripts/warm_lantern_night.gd")
const POINT_PREFIX:="warm_lantern:"
const LAMP:=preload("res://assets/ui-life/paper-tea-lamp.png")
## Same placement as the paper tea lamp: 26x34 sprite centred in its 32px cell.
const LAMP_AT:=Vector2(3,-4)
const LAMP_SIZE:=Vector2(26,34)
const LABEL_ANCHOR:=Vector2(34,4)
const POOL_SIZE:=Vector2(96,56)
const UNLIT_PAPER:=Color(0.86,0.84,0.80)
const SHADOW:=Color(0.10,0.08,0.16,0.30)
const FLAME_CORE:=Color(1.0,0.96,0.74)
const GLYPHS:={
	"home":["..#..",".###.","#####",".#.#."],
	"harvest":["#.#.#",".###.","..#..","..#.."],
	"friends":[".#.#.","#####","#####",".###."]}
## light = ground pool / halo, paper = shade tint, shadow = glyph and floor patch.
const PALETTES:={
	"home":{"light":Color(1.0,0.70,0.36),"paper":Color(1.0,0.80,0.58),"shadow":Color(0.54,0.27,0.14)},
	"harvest":{"light":Color(0.98,0.86,0.34),"paper":Color(1.0,0.93,0.55),"shadow":Color(0.48,0.38,0.10)},
	"friends":{"light":Color(1.0,0.60,0.64),"paper":Color(1.0,0.78,0.80),"shadow":Color(0.55,0.20,0.30)}}
const DEFAULT_PALETTE:={"light":Color(1.0,0.74,0.40),"paper":Color(1.0,0.86,0.66),"shadow":Color(0.50,0.30,0.16)}

static var pools:Dictionary={}

static func stations() -> Dictionary:
	return Night.STATIONS

static func phase(snapshot:Dictionary) -> String:
	var state=snapshot.get(Night.KEY,{})
	return str(state.get("phase","idle")) if state is Dictionary else "idle"

static func shown(snapshot:Dictionary) -> bool:
	return phase(snapshot) in ["lighting","celebrated"]

## station id -> wish, only for stations that have a wish.
static func lamps(snapshot:Dictionary) -> Dictionary:
	var state=snapshot.get(Night.KEY,{})
	var raw=state.get("lamps",{}) if state is Dictionary else {}
	var result:Dictionary={}
	if raw is Dictionary:
		for id in raw:
			if str(raw[id])!="":result[str(id)]=str(raw[id])
	return result

## cell -> station id for every station visible this frame.
static func cells(snapshot:Dictionary) -> Dictionary:
	var result:Dictionary={}
	if not shown(snapshot):return result
	var all:=stations()
	for id in all:result[all[id].cell]=id
	return result

## Interaction points (world coordinates, cell centre) keyed "warm_lantern:<station>".
static func points(snapshot:Dictionary) -> Dictionary:
	var result:Dictionary={}
	if not shown(snapshot):return result
	var all:=stations()
	for id in all:result[POINT_PREFIX+str(id)]=Vector2(all[id].cell)+Vector2(0.5,0.5)
	return result

static func palette(wish:String) -> Dictionary:
	return PALETTES.get(wish,DEFAULT_PALETTE)

static func lamp_rect(at:Vector2) -> Rect2:
	return Rect2(at.round()+LAMP_AT-Vector2(0,2),LAMP_SIZE+Vector2(0,2))

## Quiet steps in [0.93,1.0]; exactly 1.0 when still. `lamp_seed` desynchronises the three lamps.
static func flicker(elapsed:float,still:bool,lamp_seed:int) -> float:
	if still or not is_finite(elapsed):return 1.0
	var wave:=sin(elapsed*5.3+lamp_seed*1.9)+0.6*sin(elapsed*11.7+lamp_seed*0.7)
	return 1.0 if wave>0.5 else (0.965 if wave>-0.6 else 0.93)

static func pool(wish:String) -> GradientTexture2D:
	if pools.has(wish):return pools[wish]
	var light:Color=palette(wish).light
	var ramp:=Gradient.new()
	ramp.offsets=PackedFloat32Array([0.0,0.42,1.0])
	ramp.colors=PackedColorArray([Color(light,0.55),Color(light,0.24),Color(light,0.0)])
	var texture:=GradientTexture2D.new()
	texture.gradient=ramp
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(0.5,0.5)
	texture.fill_to=Vector2(1.0,0.5)
	pools[wish]=texture
	return texture

## Ground glow for one lit lamp, drawn by WorldView under sprites via draw_night_lamp.
## Returns {cell,size,tint,pool} per lit, visible station (strength is applied by the caller).
static func glows(snapshot:Dictionary,visible:Rect2i,elapsed:float,still:bool) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not shown(snapshot):return result
	var all:=stations()
	var lit:=lamps(snapshot)
	var bigger:=phase(snapshot)=="celebrated"
	var index:=0
	for id in all:
		index+=1
		if not lit.has(id) or not visible.has_point(all[id].cell):continue
		var size:=POOL_SIZE+(Vector2(12,6) if bigger else Vector2.ZERO)
		result.append({"cell":all[id].cell,"size":size,"tint":Color(1,1,1,flicker(elapsed,still,index)),"pool":pool(str(lit[id]))})
	return result

static func prompt(id:String) -> String:
	var entry:Dictionary=stations().get(id,{})
	return str(entry.get("title",""))

## Draws one statue (feet on the cell, same scale as village objects). `wish` is "" when unlit.
static func draw_station(canvas:CanvasItem,at:Vector2,wish:String,elapsed:float,still:bool,lamp_seed:int) -> void:
	var origin:=at.round()
	var lit:=wish!=""
	var colors:=palette(wish)
	# Floor: soft dark shadow, plus a coloured light patch when lit.
	canvas.draw_rect(Rect2(origin+Vector2(7,27),Vector2(18,4)),SHADOW)
	canvas.draw_rect(Rect2(origin+Vector2(9,26),Vector2(14,1)),SHADOW)
	if lit:
		var patch:Color=colors.light
		patch.a=0.30
		canvas.draw_rect(Rect2(origin+Vector2(9,28),Vector2(14,2)),patch)
		canvas.draw_rect(Rect2(origin+Vector2(11,27),Vector2(10,1)),patch)
	var top:=origin+LAMP_AT
	canvas.draw_texture(LAMP,top,colors.paper if lit else UNLIT_PAPER)
	if not lit:return
	var level:=flicker(elapsed,still,lamp_seed)
	# Warm shade interior: layered pixel glow over the paper, then the flame.
	var halo:Color=colors.light
	halo.a=0.26*level
	canvas.draw_rect(Rect2(top+Vector2(8,9),Vector2(10,14)),halo)
	halo.a=0.20*level
	canvas.draw_rect(Rect2(top+Vector2(10,12),Vector2(6,9)),halo)
	var tall:=1 if level>=1.0 else 0
	canvas.draw_rect(Rect2(top+Vector2(12,18-tall),Vector2(2,3+tall)),FLAME_CORE)
	canvas.draw_rect(Rect2(top+Vector2(12,17-tall),Vector2(2,1)),Color(colors.light,0.85))
	# Wish glyph on the paper face (shape distinguishes wishes without relying on colour).
	var glyph:Array=GLYPHS.get(wish,GLYPHS.home)
	var ink:Color=colors.shadow
	ink.a=0.85
	for row in glyph.size():
		var line:String=glyph[row]
		for column in line.length():
			if line[column]=="#":canvas.draw_rect(Rect2(top+Vector2(10+column,10+row),Vector2(1,1)),ink)
