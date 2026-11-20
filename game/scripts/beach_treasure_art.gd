extends RefCounted
## Beach treasure hunt art: the 尋寶 sign (always shown on the home picnic beach), six handcrafted
## sand patches (search phase only), the shared pennant marker and the found-token icon.
## Pure drawing + point helpers; world_view.gd owns the y-sorting and label placement.
##
## beach_treasure.gd is read lazily (SIGN Vector2i, SPOTS {id:{cell,title}}) so this file parses
## even before that script lands; without it only the sign at SIGN_FALLBACK is drawn.
##
## Patch art is identical in weight and position for all six ids and never reads where the
## treasure is, so nothing here reveals it.

const SOURCE:="res://scripts/beach_treasure.gd"
const SIGN_FALLBACK:=Vector2i(50,55)
const SIGN_POINT:="beach_treasure_sign"
const POINT_PREFIX:="beach_treasure:"
const ORDER:=["a","b","c","d","e","f"]
const SIGN_TITLE:="海灘尋寶"
## Passive sign name appears this close (tiles); the shell prompt sits 3 tiles west of the sign.
const SIGN_NAME_RADIUS:=5.5

const WOOD:=Color("8a6240")
const WOOD_LIGHT:=Color("b98a58")
const SEA_GLASS:=Color("8fc9c0")
const CREAM:=Color("fff4d6")
const CORAL:=Color("e8795f")
const CORAL_DARK:=Color("b9573f")
const GOLD:=Color("e8b84a")
const GOLD_DARK:=Color("9a6f22")
const SAND_BASE:=Color(0.85,0.77,0.56,0.5)
const SAND_DARK:=Color(0.72,0.62,0.42,0.75)
const SAND_LIGHT:=Color(0.95,0.9,0.74,0.85)
const SHADOW:=Color(0.25,0.22,0.12,0.25)

static var _cache:Dictionary={}

static func _constants() -> Dictionary:
	if _cache.is_empty():
		var out:={"SIGN":SIGN_FALLBACK,"SPOTS":{}}
		if ResourceLoader.exists(SOURCE):
			var script:=load(SOURCE) as Script
			if script!=null:
				var map:=script.get_script_constant_map()
				if map.get("SIGN") is Vector2i:out.SIGN=map.SIGN
				if map.get("SPOTS") is Dictionary:out.SPOTS=map.SPOTS
		_cache=out
	return _cache

static func sign_cell() -> Vector2i:
	return _constants().SIGN

static func spots() -> Dictionary:
	return _constants().SPOTS

static func spot_cell(id:String) -> Vector2i:
	return spots().get(id,{}).get("cell",Vector2i(-1,-1))

static func spot_title(id:String) -> String:
	return str(spots().get(id,{}).get("title",""))

## Picnic day on the home field only.
static func available(snapshot:Dictionary) -> bool:
	return str(snapshot.get("region_id","home"))=="home" and bool(snapshot.get("picnic",false))

static func state(snapshot:Dictionary) -> Dictionary:
	var value=snapshot.get("beach_treasure",{})
	return value if value is Dictionary else {}

static func phase(snapshot:Dictionary) -> String:
	return str(state(snapshot).get("phase","idle"))

static func _flag(snapshot:Dictionary,field:String,id:String) -> bool:
	var table=state(snapshot).get(field,{})
	return table is Dictionary and bool(table.get(id,false))

static func found(snapshot:Dictionary,id:String) -> bool:
	return _flag(snapshot,"found",id)

static func marked(snapshot:Dictionary,id:String) -> bool:
	return _flag(snapshot,"marks",id)

static func found_count(snapshot:Dictionary) -> int:
	var count:=0
	for id:String in ORDER:
		if found(snapshot,id):count+=1
	return count

## Focus points (cell centre) in fixed order for main.gd / interaction_focus: the sign always,
## then each still-unfound spot while the hunt is searching.
static func points(snapshot:Dictionary) -> Dictionary:
	var out:={}
	if not available(snapshot):return out
	out[SIGN_POINT]=Vector2(sign_cell())+Vector2(0.5,0.5)
	if phase(snapshot)=="search":
		for id:String in ORDER:
			var cell:=spot_cell(id)
			if cell.x>=0 and not found(snapshot,id):out[POINT_PREFIX+id]=Vector2(cell)+Vector2(0.5,0.5)
	return out

## Rects the focused prompt must step around (screen space, `origin`=screen(Vector2.ZERO)).
static func art_rect(origin:Vector2,key:String) -> Rect2:
	if key==SIGN_POINT:
		return Rect2(origin+Vector2(sign_cell())*32.0+Vector2(3,-10),Vector2(27,40))
	if key.begins_with(POINT_PREFIX):
		return Rect2(origin+Vector2(spot_cell(key.trim_prefix(POINT_PREFIX)))*32.0,Vector2(32,32))
	return Rect2()

## Draws everything whose cell is in row `y` and returns label entries
## [{anchor,title,id,side,passive}]. `reduced` = reduced_motion or photograph mode.
static func draw_row(canvas:CanvasItem,origin:Vector2,y:int,from_x:int,to_x:int,snapshot:Dictionary,elapsed:float,reduced:bool,player:Vector2=Vector2.INF) -> Array:
	var labels:Array=[]
	if not available(snapshot):return labels
	var mode:=phase(snapshot)
	var board:=sign_cell()
	if board.y==y and board.x>=from_x and board.x<to_x:
		var at:=origin+Vector2(board)*32.0
		draw_sign(canvas,at,found_count(snapshot) if mode!="idle" else -1,elapsed,reduced)
		var near:=player.is_finite() and player.distance_to(Vector2(board)+Vector2(0.5,0.5))<=SIGN_NAME_RADIUS
		# East of the post, away from the shell prompt to the west; never over the board.
		labels.append({"anchor":at+Vector2(35,8),"title":SIGN_TITLE,"id":SIGN_POINT,"side":true,"passive":near})
	if mode=="idle":return labels
	for id:String in ORDER:
		var cell:=spot_cell(id)
		if cell.y!=y or cell.x<from_x or cell.x>=to_x:continue
		var is_found:=found(snapshot,id)
		if mode=="search" or is_found:
			var at:=origin+Vector2(cell)*32.0
			var checked:=is_found or _flag(snapshot,"searched",id)
			draw_patch(canvas,at,id,checked)
			if marked(snapshot,id) and not checked:draw_pennant(canvas,at+Vector2(24,25),11,elapsed,reduced,cell.x+cell.y)
			if is_found:draw_token(canvas,at+Vector2(24,9))
			if mode=="search" and not is_found:
				labels.append({"anchor":at+Vector2(16,-3),"title":spot_title(id),"id":POINT_PREFIX+id,"side":false,"passive":false})
	return labels

## --- Sign ---------------------------------------------------------------------------------------

## `found_total` < 0 hides the pips (idle). `at` is the cell's top-left; art rises above the cell.
static func draw_sign(canvas:CanvasItem,at:Vector2,found_total:int,elapsed:float=0.0,reduced:bool=false) -> void:
	canvas.draw_rect(Rect2(at+Vector2(7,27),Vector2(19,3)),SHADOW)
	# Tall mast carrying the pennant, thick post below.
	canvas.draw_rect(Rect2(at+Vector2(15,-8),Vector2(2,16)),WOOD_LIGHT)
	canvas.draw_rect(Rect2(at+Vector2(14,16),Vector2(4,12)),WOOD)
	canvas.draw_rect(Rect2(at+Vector2(14,16),Vector2(1,12)),WOOD_LIGHT)
	# Sea-glass board with a coral X and a dashed trail, unlike the plain village sign.
	canvas.draw_rect(Rect2(at+Vector2(4,7),Vector2(24,14)),WOOD)
	canvas.draw_rect(Rect2(at+Vector2(5,8),Vector2(22,12)),SEA_GLASS)
	canvas.draw_rect(Rect2(at+Vector2(5,8),Vector2(22,2)),SEA_GLASS.lightened(0.3))
	for i in range(4):canvas.draw_rect(Rect2(at+Vector2(7+i*3,16),Vector2(2,1)),CREAM)
	for step in range(3):
		canvas.draw_rect(Rect2(at+Vector2(20+step,12+step),Vector2(1,1)),CORAL_DARK)
		canvas.draw_rect(Rect2(at+Vector2(22-step,12+step),Vector2(1,1)),CORAL_DARK)
	draw_pennant(canvas,at+Vector2(15,8),16,elapsed,reduced,0,true)
	if found_total>=0:
		for i in range(ORDER.size()):
			var x:=at+Vector2(7+i*3.5,22.0)
			canvas.draw_rect(Rect2(x.round(),Vector2(2,2)),GOLD if i<found_total else SAND_DARK)

## --- Shared pennant marker --------------------------------------------------------------------

## Pole of `height` px standing at `foot` with a triangular coral flag. Sway is 1px and
## disabled with reduced motion / photo mode.
static func draw_pennant(canvas:CanvasItem,foot:Vector2,height:int,elapsed:float,reduced:bool,seed_value:int=0,pole_drawn:bool=false) -> void:
	var sway:=0.0 if reduced else roundf(sin(elapsed*2.4+float(seed_value)))
	var top:=foot+Vector2(0,-height)
	if not pole_drawn:
		canvas.draw_rect(Rect2(foot+Vector2(0,-height),Vector2(2,height+1)),WOOD)
		canvas.draw_rect(Rect2(foot+Vector2(0,-height),Vector2(1,height+1)),WOOD_LIGHT)
	var span:=float(maxi(8,height-3))
	var flag:=PackedVector2Array([top+Vector2(2,0),top+Vector2(2+span,span*0.32+sway),top+Vector2(2,span*0.6)])
	canvas.draw_colored_polygon(flag,CORAL)
	canvas.draw_colored_polygon(PackedVector2Array([top+Vector2(2,0),top+Vector2(2+span*0.55,span*0.18+sway*0.5),top+Vector2(2,span*0.22)]),CORAL.lightened(0.25))
	canvas.draw_rect(Rect2(top+Vector2(-1,-2),Vector2(4,2)),CORAL_DARK)

## --- Found token ------------------------------------------------------------------------------

## 12px gold token with a little shell star; `center` is its middle.
static func draw_token(canvas:CanvasItem,center:Vector2) -> void:
	canvas.draw_circle(center+Vector2(0,1),6.0,Color(0.3,0.22,0.08,0.3))
	canvas.draw_circle(center,6.0,GOLD_DARK)
	canvas.draw_circle(center,5.0,GOLD)
	canvas.draw_circle(center+Vector2(-1,-1),2.4,GOLD.lightened(0.3))
	for arm:Vector2 in [Vector2(0,-3),Vector2(0,3),Vector2(-3,0),Vector2(3,0)]:
		canvas.draw_rect(Rect2((center+arm).round()-Vector2(0.5,0.5),Vector2(1,1)),CREAM)
	canvas.draw_rect(Rect2(center.round()-Vector2(0.5,0.5),Vector2(1,1)),GOLD_DARK)

## --- Six sand patches ------------------------------------------------------------------------

static func _oval(center:Vector2,rx:float,ry:float) -> PackedVector2Array:
	var out:=PackedVector2Array()
	for i in range(12):
		var angle:=TAU*float(i)/12.0
		out.append(center+Vector2(cos(angle)*rx,sin(angle)*ry))
	return out

## Faint oval of disturbed sand plus one hand-placed motif per id. Same footprint and contrast
## for all six; `done` fades the motif once its token is shown.
static func draw_patch(canvas:CanvasItem,at:Vector2,id:String,done:bool=false) -> void:
	var fade:=0.55 if done else 1.0
	var dark:=Color(SAND_DARK,SAND_DARK.a*fade)
	var light:=Color(SAND_LIGHT,SAND_LIGHT.a*fade)
	canvas.draw_colored_polygon(_oval(at+Vector2(16,19),12.0,7.0),Color(SAND_BASE,SAND_BASE.a*fade))
	match id:
		"a":# wave ripples
			for row in range(3):
				for i in range(5):
					var p:=at+Vector2(7+i*4.5,14+row*4+(i%2))
					canvas.draw_rect(Rect2(p.round(),Vector2(4,1)),dark)
					canvas.draw_rect(Rect2(p.round()+Vector2(1,1),Vector2(3,1)),light)
		"b":# pebble cluster
			for pebble:Vector2 in [Vector2(9,17),Vector2(14,14),Vector2(19,19),Vector2(13,22),Vector2(22,15),Vector2(17,24)]:
				canvas.draw_rect(Rect2((at+pebble).round(),Vector2(3,2)),dark)
				canvas.draw_rect(Rect2((at+pebble).round(),Vector2(1,1)),light)
		"c":# scooped crescent
			canvas.draw_arc(at+Vector2(16,17),7.0,0.15*PI,0.85*PI,8,dark,2.0)
			canvas.draw_arc(at+Vector2(16,19),7.0,0.2*PI,0.8*PI,8,light,1.0)
		"d":# low dune ridge
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(6,24),at+Vector2(10,18),at+Vector2(16,15),at+Vector2(22,18),at+Vector2(27,24)]),light)
			canvas.draw_rect(Rect2(at+Vector2(8,23),Vector2(17,1)),dark)
			canvas.draw_rect(Rect2(at+Vector2(12,18),Vector2(8,1)),dark)
		"e":# driftwood chip
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(8,22),at+Vector2(22,16),at+Vector2(24,18),at+Vector2(10,24)]),Color(0.65,0.54,0.37,0.85*fade))
			canvas.draw_line(at+Vector2(9,22),at+Vector2(22,17),light,1.0)
			canvas.draw_rect(Rect2(at+Vector2(24,22),Vector2(2,1)),dark)
			canvas.draw_rect(Rect2(at+Vector2(6,17),Vector2(1,1)),dark)
		"f":# grain ring
			for i in range(8):
				var angle:=TAU*float(i)/8.0
				var p:=at+Vector2(16,19)+Vector2(cos(angle)*7.0,sin(angle)*4.0)
				canvas.draw_rect(Rect2(p.round(),Vector2(2,1)),dark)
			canvas.draw_rect(Rect2(at+Vector2(15,18),Vector2(2,2)),light)
