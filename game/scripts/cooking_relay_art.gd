extends RefCounted
## Picnic cooking relay: a sign plus three temporary activity tables (prep / assembly / serve) on the
## home village. Program-drawn pixel art in the wood palette of the other village props, with item
## icons from inventory_item_art. Pure view: reads snapshot.cooking_relay (phase, mode, tray, dish,
## plates, plated) and never changes rules or collisions.

const ItemArt=preload("res://scripts/inventory_item_art.gd")
const Relay=preload("res://scripts/cooking_relay.gd")
const SIGN_POINT:="cooking_relay_sign"
const PREFIX:="cooking_relay:"
const TABLE_PHASES:=["lobby","run","results"]
const MAX_TRAY:=6

const WOOD_DARK:=Color("6a3a1c")
const WOOD:=Color("a8642c")
const WOOD_LIGHT:=Color("d99a4a")
const BOARD:=Color("e2bf86")
const BOARD_EDGE:=Color("b58a4c")
const CLOTH_A:=Color("c4562a")
const CLOTH_B:=Color("f4e4b8")
const METAL:=Color("9aa3a6")
const METAL_DARK:=Color("5d676b")
const PLATE:=Color("f6efe0")
const PLATE_SHADE:=Color("cfc3aa")
const SHADOW:=Color(0.18,0.12,0.08,0.28)
const STEAM:=Color(1.0,0.96,0.85,0.6)
const CONFETTI:=[Color("e0523d"),Color("f2b53a"),Color("5fae6a"),Color("4f9ad0"),Color("d779b6")]
const STATE_LAMP:={"lobby":Color("8fc4e8"),"run":Color("f2b53a"),"results":Color("7fd081")}

static func station_cells() -> Dictionary:
	return Relay.STATIONS

static func sign_cell() -> Vector2i:
	return Relay.SIGN

static func relay(snapshot:Dictionary) -> Dictionary:
	var value=snapshot.get("cooking_relay",{})
	return value if value is Dictionary else {}

static func phase(snapshot:Dictionary) -> String:
	return str(relay(snapshot).get("phase","idle"))

## Picnic on the home village only.
static func available(snapshot:Dictionary) -> bool:
	return str(snapshot.get("region_id","home"))=="home" and bool(snapshot.get("picnic",false))

static func tables_shown(snapshot:Dictionary) -> bool:
	return available(snapshot) and phase(snapshot) in TABLE_PHASES

## Focus points, tile-centre coordinates, sorted by y (then x, then key) so the nearest/tie order is stable.
static func points(snapshot:Dictionary) -> Dictionary:
	if not available(snapshot):return {}
	var list:Array=[[SIGN_POINT,Vector2(sign_cell())+Vector2(0.5,0.5)]]
	if tables_shown(snapshot):
		var cells:Dictionary=station_cells()
		for id in cells:list.append([PREFIX+str(id),Vector2(cells[id])+Vector2(0.5,0.5)])
	list.sort_custom(func(a:Array,b:Array):
		var pa:Vector2=a[1]
		var pb:Vector2=b[1]
		if not is_equal_approx(pa.y,pb.y):return pa.y<pb.y
		if not is_equal_approx(pa.x,pb.x):return pa.x<pb.x
		return str(a[0])<str(b[0]))
	var result:Dictionary={}
	for entry:Array in list:result[entry[0]]=entry[1]
	return result

## Map of cell -> "sign" / station id, for the world's per-cell draw pass.
static func cell_map(snapshot:Dictionary) -> Dictionary:
	var map:Dictionary={}
	if not available(snapshot):return map
	map[sign_cell()]="sign"
	if tables_shown(snapshot):
		var cells:Dictionary=station_cells()
		for id in cells:map[cells[id]]=str(id)
	return map

static func label(id:String) -> String:
	return {"sign":"料理接力","prep":"備料桌","assembly":"組裝桌","serve":"出餐檯"}.get(id,"")

## Draw one piece at the screen origin `at` of its cell.
static func draw(canvas:CanvasItem,at:Vector2,id:String,snapshot:Dictionary,elapsed:float,reduced_motion:bool,celebration_age:float=INF) -> void:
	var state:Dictionary=relay(snapshot)
	var origin:=at.floor()
	match id:
		"sign":_draw_sign(canvas,origin,state)
		"prep":_draw_prep(canvas,origin,state)
		"assembly":_draw_assembly(canvas,origin,state,elapsed,reduced_motion)
		"serve":_draw_serve(canvas,origin,state,reduced_motion,celebration_age)

static func _rect(canvas:CanvasItem,origin:Vector2,x:float,y:float,w:float,h:float,color:Color) -> void:
	canvas.draw_rect(Rect2(origin+Vector2(x,y),Vector2(w,h)),color)

static func _icon(canvas:CanvasItem,item:String,rect:Rect2) -> void:
	var tex:Texture2D=ItemArt.icon(item) if item!="" else null
	if tex!=null:
		canvas.draw_texture_rect(tex,rect,false)
	else:
		canvas.draw_rect(rect.grow(-2.0),Color("c9a35c"))

static func _tray(state:Dictionary) -> Array:
	var tray=state.get("tray",[])
	return tray if tray is Array else []

static func _count(value) -> int:
	if value is Array or value is Dictionary:return value.size()
	return maxi(0,int(value))

static func _draw_sign(canvas:CanvasItem,o:Vector2,state:Dictionary) -> void:
	var current:=str(state.get("phase","idle"))
	_rect(canvas,o,8,29,16,3,SHADOW)
	_rect(canvas,o,14,12,4,19,WOOD_DARK)
	_rect(canvas,o,15,12,2,19,WOOD)
	# Board with a pot silhouette; the lamp colour follows the phase.
	_rect(canvas,o,3,-2,26,16,WOOD_DARK)
	_rect(canvas,o,4,-1,24,14,WOOD)
	_rect(canvas,o,4,-1,24,2,WOOD_LIGHT)
	_rect(canvas,o,8,5,12,6,METAL_DARK)
	_rect(canvas,o,9,4,10,2,METAL)
	_rect(canvas,o,6,6,2,2,METAL_DARK)
	_rect(canvas,o,20,6,2,2,METAL_DARK)
	var lamp:Color=STATE_LAMP.get(current,Color("b9a98a"))
	_rect(canvas,o,23,1,4,4,WOOD_DARK)
	_rect(canvas,o,24,2,2,2,lamp)
	for i in 3:_rect(canvas,o,10+i*3,0,1,2,Color(1.0,0.96,0.85,0.5))

static func _draw_prep(canvas:CanvasItem,o:Vector2,state:Dictionary) -> void:
	# Wide low bench with a cutting board; items from the tray lie on it.
	_rect(canvas,o,-8,28,48,4,SHADOW)
	_rect(canvas,o,-6,10,44,16,WOOD_DARK)
	_rect(canvas,o,-5,9,42,15,WOOD)
	_rect(canvas,o,-5,9,42,2,WOOD_LIGHT)
	for x in [-4.0,33.0]:_rect(canvas,o,x,24,3,7,WOOD_DARK)
	_rect(canvas,o,-3,12,38,10,BOARD)
	_rect(canvas,o,-3,12,38,1,BOARD_EDGE)
	_rect(canvas,o,-3,21,38,1,BOARD_EDGE)
	# knife
	_rect(canvas,o,28,16,6,2,METAL)
	_rect(canvas,o,34,16,3,2,WOOD_DARK)
	var tray:=_tray(state)
	for i in mini(tray.size(),MAX_TRAY):
		_icon(canvas,str(tray[i]),Rect2(o+Vector2(-2+i*6,3 if i%2==0 else 5),Vector2(10,10)))
	if tray.size()>MAX_TRAY:
		_rect(canvas,o,34,3,4,4,CLOTH_A)
	if tray.is_empty():_rect(canvas,o,6,16,14,2,Color(0.5,0.34,0.18,0.35))

static func _draw_assembly(canvas:CanvasItem,o:Vector2,state:Dictionary,elapsed:float,reduced_motion:bool) -> void:
	# Round pedestal table with a pot and a plate for the current dish.
	_rect(canvas,o,3,29,26,3,SHADOW)
	_rect(canvas,o,13,19,6,11,WOOD_DARK)
	_rect(canvas,o,9,28,14,3,WOOD_DARK)
	_rect(canvas,o,5,11,22,3,WOOD_DARK)
	_rect(canvas,o,3,13,26,6,WOOD_DARK)
	_rect(canvas,o,4,12,24,6,WOOD)
	_rect(canvas,o,7,10,18,2,WOOD_LIGHT)
	_rect(canvas,o,5,18,22,1,WOOD_DARK)
	# plate
	_rect(canvas,o,6,7,13,5,PLATE_SHADE)
	_rect(canvas,o,7,6,11,5,PLATE)
	var dish:=str(state.get("dish",""))
	if dish!="":_icon(canvas,dish,Rect2(o+Vector2(8,-3),Vector2(10,10)))
	# small pot
	_rect(canvas,o,21,5,7,6,METAL_DARK)
	_rect(canvas,o,22,4,5,2,METAL)
	_rect(canvas,o,20,6,1,2,METAL_DARK)
	_rect(canvas,o,28,6,1,2,METAL_DARK)
	if reduced_motion or str(state.get("phase",""))!="run" or dish=="":return
	for i in 3:
		var t:=fposmod(elapsed*0.7+float(i)*0.33,1.0)
		var x:=22.0+float(i)*2.0+sin((elapsed+i)*3.0)*1.0
		canvas.draw_rect(Rect2(o+Vector2(x,2.0-t*10.0),Vector2(2,2)),Color(STEAM.r,STEAM.g,STEAM.b,STEAM.a*(1.0-t)))

static func _draw_serve(canvas:CanvasItem,o:Vector2,state:Dictionary,reduced_motion:bool,celebration_age:float) -> void:
	# Counter with a striped awning and a service bell; stacked plates show the count.
	_rect(canvas,o,-2,29,36,3,SHADOW)
	_rect(canvas,o,0,-6,32,3,WOOD_DARK)
	for i in 8:_rect(canvas,o,i*4,-3,4,6,CLOTH_A if i%2==0 else CLOTH_B)
	_rect(canvas,o,0,3,32,1,WOOD_DARK)
	_rect(canvas,o,1,4,2,20,WOOD_DARK)
	_rect(canvas,o,29,4,2,20,WOOD_DARK)
	_rect(canvas,o,0,14,32,14,WOOD_DARK)
	_rect(canvas,o,1,13,30,13,WOOD)
	_rect(canvas,o,1,13,30,2,WOOD_LIGHT)
	for i in 3:_rect(canvas,o,4+i*9,18,6,6,WOOD_DARK)
	# bell
	_rect(canvas,o,24,9,5,4,Color("e4b456"))
	_rect(canvas,o,25,8,3,1,Color("efc867"))
	_rect(canvas,o,26,7,1,1,WOOD_DARK)
	# plates: ready stack (plates) and finished marks (plated)
	var ready:=mini(_count(state.get("plates",0)),4)
	for i in ready:
		_rect(canvas,o,4,11-i*2,12,2,PLATE if i%2==0 else PLATE_SHADE)
	var plated:=mini(_count(state.get("plated",0)),5)
	for i in plated:
		_rect(canvas,o,18+(i%3)*3,17 if i<3 else 20,2,2,Color("7fd081"))
	if reduced_motion or celebration_age<0.0 or celebration_age>1.1:return
	# One brief cheer per new plate, with no effect on the score.
	var progress:=celebration_age/1.1
	for i in 10:
		var drift:=float((i*37)%23)-11.0
		var x:=16.0+drift*1.5+sin(celebration_age*4.0+i)*2.0
		var y:=-14.0+progress*26.0+float((i*13)%7)
		var c:Color=CONFETTI[i%CONFETTI.size()]
		c.a=1.0-progress*0.6
		canvas.draw_rect(Rect2(o+Vector2(x,y),Vector2(2,2)),c)
