@static_unload
extends RefCounted
## P06「礦車搬運」合作礦車挑戰（獨立區域 cart_gallery）的程式繪製。沒有新美術檔：
##  地面用礦坑地磚（MineArt.draw_tile，原尺寸 32×32 圖集區塊）、軌道沿用 OreRouteArt 的軌道遮罩、
##  裝載台／卸礦台／台車直接呼叫 OreRouteArt，標示牌與出口階梯用 MineArt.draw_prop。
##  不預載 World；所有繪製都是整數像素（無縮放角色）。
##
## 軌道（四向相鄰格）：由 STOPS 之間的正交折線組成——
##   起點→岔口 一直線；岔口→北／南停靠點經過 (岔口.x, 停靠點.y) 的轉角；北／南→匯流點經過 (匯流.x, 停靠點.y)；匯流→碼頭一直線。
## 每格依四個鄰格是否也在軌道上決定形狀（直線、轉角、端點、T 字），所以相鄰格的鐵軌一定接得上。
##
## 快照格式：snapshot.party_cart（或快照本身就是 party_cart 字典）與 snapshot.time（世界秒數）。

const PartyCart=preload("res://scripts/party_cart.gd")
const OreRouteArt=preload("res://scripts/ore_route_art.gd")
const MineArt=preload("res://scripts/mine_art.gd")

const SURFACE:="jinguashi"
const CELL:=32
const START:=0
const JUNCTION:=1
const NORTH:=2
const SOUTH:=3
const MERGE:=4
const DOCK:=5
const DIRS:=[Vector2i(0,-1),Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0)]

const SIGN_PROP:=3
const EXIT_PROP:=1
const PORTAL_PROP:=0
const LAMP_SITES:=[Vector2i(15,16),Vector2i(23,16),Vector2i(29,16),Vector2i(13,24),Vector2i(23,24),Vector2i(29,24)]

const STONE_OUTLINE:=Color("45403a")
const STONE:=Color("85807a")
const STONE_LIGHT:=Color("b3aca0")
const SHADOW:=Color(0,0,0,0.25)
const LEVER_PLATE:=Color("4a3320")
const LEVER_ARM:=Color("c4925a")
const LEVER_KNOB:=Color("d0694a")
const LAMP_IDLE:=Color("f3b858")
const LAMP_RUN:=Color("7bd88f")
const LAMP_DONE:=Color("8cc4e8")
const PIP_OFF:=Color("2e241c")
const PIP_ON:=Color("f6e27a")

static var track_set:Dictionary={}
static var waypoint_cache:Dictionary={}

# ----------------------------------------------------------------- snapshot --

## The shared cart dictionary from either the whole snapshot or the cart dictionary itself.
static func cart_state(snapshot:Variant) -> Dictionary:
	if not (snapshot is Dictionary):return {}
	var data:Dictionary=snapshot
	var nested:Variant=data.get("party_cart")
	if nested is Dictionary:return nested
	return data if data.has("phase") else {}

const LOCKED_LABEL:="礦車坑道・待維修"
const LOCKED_NOTICE:="到礦樣桌找波波，完成「動不了的礦車」就能進坑道。"

static func portal_locked(snapshot:Variant) -> bool:
	return not (snapshot is Dictionary and snapshot.get("party_cart_unlocked",false)==true)

static func snapshot_time(snapshot:Variant,view:Object=null) -> float:
	if snapshot is Dictionary and (snapshot as Dictionary).has("time"):
		var t:=float((snapshot as Dictionary).get("time",0.0))
		if not is_nan(t) and not is_inf(t):return t
	if view!=null and "elapsed" in view:return float(view.elapsed)
	return 0.0

static func _stop_index(value:Variant,fallback:int) -> int:
	var i:int=int(value) if (value is int or value is float) else fallback
	return clampi(i,0,PartyCart.STOPS.size()-1)

static func _stop_cell(i:int) -> Vector2i:
	return PartyCart.STOPS[clampi(i,0,PartyCart.STOPS.size()-1)]

static func _center(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

static func _moving(state:Dictionary) -> bool:
	var to:Variant=state.get("to",-1)
	if not (to is int or to is float):return false
	var target:=int(to)
	return target>=0 and target<PartyCart.STOPS.size() and target!=_stop_index(state.get("stop",0),0)

# --------------------------------------------------------------------- path --

## Orthogonal corner list for one segment (stop indices), cells inclusive of both ends.
static func waypoints(from:int,to:int) -> Array[Vector2i]:
	var key:=from*10+to
	if waypoint_cache.has(key):return waypoint_cache[key]
	var forward:=from<=to
	var a:=mini(from,to)
	var b:=maxi(from,to)
	var s:Array=PartyCart.STOPS
	var list:Array[Vector2i]=[]
	if a==START and b==JUNCTION:list=[s[START],s[JUNCTION]]
	elif a==JUNCTION and (b==NORTH or b==SOUTH):list=[s[JUNCTION],Vector2i(s[JUNCTION].x,s[b].y),s[b]]
	elif (a==NORTH or a==SOUTH) and b==MERGE:list=[s[a],Vector2i(s[MERGE].x,s[a].y),s[MERGE]]
	elif a==MERGE and b==DOCK:list=[s[MERGE],s[DOCK]]
	else:list=[s[a],Vector2i(s[b].x,s[a].y),s[b]] # fallback L-shape, never diagonal
	if not forward:list.reverse()
	waypoint_cache[key]=list
	return list

static func _segments() -> Array:
	return [[START,JUNCTION],[JUNCTION,NORTH],[JUNCTION,SOUTH],[NORTH,MERGE],[SOUTH,MERGE],[MERGE,DOCK]]

## Every cell of the shared rail network (Dictionary used as a set).
static func track_cells() -> Dictionary:
	if not track_set.is_empty():return track_set
	var cells:Dictionary={}
	for pair:Array in _segments():
		var list:=waypoints(int(pair[0]),int(pair[1]))
		for i in range(list.size()-1):
			var p:=list[i]
			var q:=list[i+1]
			var step:=Vector2i(signi(q.x-p.x),signi(q.y-p.y))
			cells[p]=true
			while p!=q:
				p+=step
				cells[p]=true
	track_set=cells
	return cells

static func on_track(cell:Vector2i) -> bool:
	return track_cells().has(cell)

## Rail shapes (OreRouteArt names) for one cell from its four-neighbour links; corners/ends first, straights last.
static func track_shapes(cell:Vector2i) -> Array[String]:
	var shapes:Array[String]=[]
	if not on_track(cell):return shapes
	var n:=on_track(cell+Vector2i(0,-1))
	var s:=on_track(cell+Vector2i(0,1))
	var e:=on_track(cell+Vector2i(1,0))
	var w:=on_track(cell+Vector2i(-1,0))
	var count:=int(n)+int(s)+int(e)+int(w)
	match count:
		0:return shapes
		1:
			shapes.append("end_"+("n" if n else "s" if s else "e" if e else "w"))
		2:
			if n and s:shapes.append("v")
			elif e and w:shapes.append("h")
			else:shapes.append(("n" if n else "s")+("e" if e else "w"))
		3:
			if n and s:
				shapes.append("n"+("e" if e else "w"))
				shapes.append("v")
			else:
				# Through line is horizontal; the stub goes north or south.
				shapes.append(("n" if n else "s")+"e")
				shapes.append("h")
		_:
			shapes.append("h")
			shapes.append("v")
	return shapes

## Tile-centre position of the cart. Reduced motion snaps to the destination stop while moving.
static func cart_position(snapshot:Variant,reduced:=false,time:=-1.0) -> Vector2:
	var state:=cart_state(snapshot)
	var from:=_stop_index(state.get("stop",0),0)
	if not _moving(state):return _center(_stop_cell(from))
	var to:=_stop_index(state.get("to",-1),from)
	if reduced:return _center(_stop_cell(to))
	var now:=time if time>=0.0 else snapshot_time(snapshot)
	var departed:=float(state.get("departed",0.0))
	var arrives:=float(state.get("arrives",departed))
	var span:=arrives-departed
	var t:=1.0
	if span>0.0 and not is_nan(span) and not is_nan(now):t=clampf((now-departed)/span,0.0,1.0)
	var list:=waypoints(from,to)
	var total:=0.0
	for i in range(list.size()-1):total+=Vector2(list[i+1]-list[i]).length()
	var remaining:=t*total
	for i in range(list.size()-1):
		var length:=Vector2(list[i+1]-list[i]).length()
		if remaining<=length and length>0.0:
			return _center(list[i])+Vector2(list[i+1]-list[i])*(remaining/length)
		remaining-=length
	return _center(list[list.size()-1])

# ----------------------------------------------------------------- drawing --

static func _box(canvas:CanvasItem,at:Vector2,x:float,y:float,w:float,h:float,c:Color) -> void:
	canvas.draw_rect(Rect2(at+Vector2(x,y),Vector2(w,h)),c)

static func _in_gallery(view:Object) -> bool:
	return view.region_id()==PartyCart.REGION

static func _outside_distance(cell:Vector2i) -> int:
	var area:Rect2i=PartyCart.BOUNDS
	return maxi(maxi(area.position.x-cell.x,cell.x-area.end.x+1),maxi(area.position.y-cell.y,cell.y-area.end.y+1))

## One ground tile plus rails. `at` = camera-shifted top-left of the cell. Only draws in cart_gallery.
static func draw_floor(view:CanvasItem,at:Vector2,cell:Vector2i) -> void:
	if not _in_gallery(view):return
	var base:=at.round()
	var outside:=_outside_distance(cell)
	if outside>0:
		MineArt.draw_tile(view,base,MineArt.ROUGH_EARTH,MineArt.FLOOR_TINT[0].darkened(minf(0.58+outside*0.085,0.92)))
		return
	var edge:=0
	for d:Vector2i in DIRS:
		if _outside_distance(cell+d)>0:edge+=1
	var pair:Array=MineArt.SIDE_FLOOR[0]
	var material:int=pair[1 if posmod(cell.x*13+cell.y*7,7)>4 else 0]
	var light:=0.0
	for lamp:Vector2i in LAMP_SITES:
		var offset:=Vector2(lamp-cell)
		light=maxf(light,maxf(0.0,1.0-offset.length()/2.6))
	var tint:Color=MineArt.FLOOR_TINT[0].darkened(0.19+edge*0.09)
	MineArt.draw_tile(view,base,material,tint.lerp(Color("f6c089"),light*0.35))
	for shape in track_shapes(cell):
		for rect:Array in OreRouteArt._track_rects(shape):
			view.draw_rect(Rect2(base+Vector2(float(rect[0]),float(rect[1])),Vector2(float(rect[2]),float(rect[3]))),OreRouteArt.TRACK_COLORS[int(rect[4])])

static func _stone(canvas:CanvasItem,b:Vector2,x:float,y:float,w:float,h:float) -> void:
	_box(canvas,b,x,y,w,h,STONE_OUTLINE)
	_box(canvas,b,x+1,y+1,w-2,h-2,STONE)
	_box(canvas,b,x+1,y+1,maxf(w-4,1),1,STONE_LIGHT)
	_box(canvas,b,x+1,y+1,1,maxf(h-4,1),STONE_LIGHT)

static func _draw_rock(canvas:CanvasItem,b:Vector2,blocked:bool) -> void:
	if blocked:
		_box(canvas,b,2,24,28,4,SHADOW)
		_stone(canvas,b,3,15,12,10)
		_stone(canvas,b,15,12,14,13)
		_stone(canvas,b,9,6,12,11)
	else:
		_stone(canvas,b,5,24,5,4)
		_stone(canvas,b,22,25,4,3)
		_stone(canvas,b,14,27,3,2)

static func _draw_lever(canvas:CanvasItem,b:Vector2,branch:String) -> void:
	_box(canvas,b,2,5,11,6,LEVER_PLATE)
	_box(canvas,b,3,6,9,1,LEVER_ARM)
	if branch=="south":
		_box(canvas,b,8,10,3,8,LEVER_ARM)
		_box(canvas,b,7,17,5,3,LEVER_KNOB)
	else:
		_box(canvas,b,5,-6,3,12,LEVER_ARM)
		_box(canvas,b,4,-8,5,3,LEVER_KNOB)

static func _draw_lantern_post(view:CanvasItem,at:Vector2) -> void:
	var iron:=Color("4a3c2c")
	var wood:=Color("765032")
	var tarnish:=Color("ac7449")
	_box(view,at,10,28,15,3,SHADOW)
	_box(view,at,14,1,4,28,iron)
	_box(view,at,15,2,2,26,wood)
	_box(view,at,11,1,13,3,wood)
	_box(view,at,11,1,13,1,tarnish)
	_box(view,at,20,4,1,3,iron)
	_box(view,at,17,7,8,9,iron)
	_box(view,at,18,8,6,7,Color("cb8548"))
	_box(view,at,19,8,3,6,Color("ffcf80"))
	_box(view,at,20,9,2,3,Color("fff0a7"))
	_box(view,at,17,14,8,2,iron)

static func _draw_sign_status(canvas:CanvasItem,b:Vector2,state:Dictionary) -> void:
	var lamp:=LAMP_IDLE
	match str(state.get("phase","idle")):
		"run":lamp=LAMP_RUN
		"results":lamp=LAMP_DONE
	_box(canvas,b,14,-12,5,5,STONE_OUTLINE)
	_box(canvas,b,15,-11,3,3,lamp)
	var delivered:=int(state.get("delivered",0))
	for i in 3:
		_box(canvas,b,7+i*7,28,5,3,STONE_OUTLINE)
		_box(canvas,b,8+i*7,29,3,1,PIP_ON if i<delivered else PIP_OFF)

static func _label(view:Object,at:Vector2,title:String,id:String) -> void:
	if view.focused_label==id:view.world_label(at+Vector2(16,-18),title,id)

## Signs, lever, rocks, docks (gallery) or the jinguashi portal. `at` = camera-shifted top-left of `cell`.
static func draw_site(view:CanvasItem,at:Vector2,cell:Vector2i,snapshot:Variant=null) -> void:
	var state:=cart_state(snapshot)
	var base:=at.round()
	if view.region_id()==SURFACE:
		if cell==PartyCart.SURFACE_PORTAL:
			MineArt.draw_prop(view,base,PORTAL_PROP)
			MineArt.draw_freight(view,base+Vector2(14,12),"cart",-1.0,view.reduced_motion,16)
			_label(view,base,LOCKED_LABEL if portal_locked(snapshot) else "礦車搬運入口","party_cart_portal")
		return
	if not _in_gallery(view):return
	if cell in LAMP_SITES:_draw_lantern_post(view,base)
	var stops:Array=PartyCart.STOPS
	if cell==PartyCart.SIGN:
		MineArt.draw_prop(view,base,SIGN_PROP)
		_draw_sign_status(view,base,state)
		_label(view,base,"礦車搬運","party_cart:sign")
	elif cell==PartyCart.EXIT:
		MineArt.draw_prop(view,base,EXIT_PROP)
		_label(view,base,"回金瓜石","party_cart_exit")
	elif cell==stops[START]:
		OreRouteArt.draw_platform(view,base,"load")
	elif cell==stops[DOCK]:
		OreRouteArt.draw_platform(view,base,"unload")
	elif cell==stops[JUNCTION]:
		_draw_lever(view,base,str(state.get("branch","north")))
		_label(view,base,"道岔","party_cart:junction")
	for side:String in PartyCart.ROCKS:
		if cell==PartyCart.ROCKS[side]:
			var rocks:Dictionary=state.get("rocks",{}) if state.get("rocks") is Dictionary else {}
			var blocked:bool=bool(rocks.get(side,true))
			_draw_rock(view,base,blocked)
			if blocked:_label(view,base,"北線落石" if side=="north" else "南線落石","party_cart:"+side)

## The shared cart on the rails (side-view OreRouteArt cart; loaded once it has left the start).
static func draw_cart(view:CanvasItem,snapshot:Variant) -> void:
	if not _in_gallery(view):return
	var state:=cart_state(snapshot)
	var reduced:bool=view.reduced_motion or view.photograph_mode
	var now:=snapshot_time(snapshot,view)+clampf(float(view.elapsed)-float(view.party_cart_clock_at),0.0,0.2)
	var pos:=cart_position(snapshot,reduced,now)
	var at:Vector2=view.screen(pos-Vector2(0.5,0.5)).round()
	var stop:=_stop_index(state.get("stop",0),0)
	var to:=_stop_index(state.get("to",-1),stop) if _moving(state) else stop
	var loaded:=maxi(stop,to)>START
	OreRouteArt.draw_cart(view,at,loaded,now,reduced)
	if view.focused_label=="party_cart:cart":
		var joined:bool=snapshot.get(PartyCart.VIEW_KEY,{}).get("joined",false)
		var message:="卸貨" if stop==DOCK else "推礦車"
		view.world_label(at+Vector2(16,-18),message if joined else "共用礦車","party_cart:cart")

# ------------------------------------------------------------------ points --

## World tile-centre points. `region` defaults to snapshot.region / snapshot.region_id (empty → no points).
static func points(snapshot:Variant,region:="") -> Dictionary:
	var out:Dictionary={}
	var name:=region
	if name.is_empty() and snapshot is Dictionary:
		name=str((snapshot as Dictionary).get("region",(snapshot as Dictionary).get("region_id","")))
	if name==SURFACE:
		out["party_cart_portal"]=_center(PartyCart.SURFACE_PORTAL)
		return out
	if name!=PartyCart.REGION:return out
	var state:=cart_state(snapshot)
	out["party_cart_exit"]=_center(PartyCart.EXIT)
	out["party_cart:sign"]=_center(PartyCart.SIGN)
	if str(state.get("phase","idle"))!="run":return out
	var stop:=_stop_index(state.get("stop",0),0)
	if not _moving(state):
		# The junction point already offers both switch and push, so it replaces the cart point there.
		if stop==JUNCTION:out["party_cart:junction"]=_center(_stop_cell(JUNCTION))
		else:out["party_cart:cart"]=_center(_stop_cell(stop))
	var rocks:Dictionary=state.get("rocks",{}) if state.get("rocks") is Dictionary else {}
	for side:String in PartyCart.ROCKS:
		if bool(rocks.get(side,false)):out["party_cart:"+side]=_center(PartyCart.ROCKS[side])
	return out
