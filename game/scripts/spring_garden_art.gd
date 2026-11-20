extends RefCounted
## Spring Garden Day: three 32px flower station signs on the home field (bluebell, orange
## blossom, chime herb). Pure drawing + point helpers; world_view.gd owns the y-sorting.

const Scene=preload("res://scripts/spring_garden_day.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")

const POINT_PREFIX:="spring_garden:"
## SPOTS id -> short focus suffix, in the same fixed order as Scene.SPOTS.
const POINT_KEYS:={"bluebell":"spring_garden:bluebell","orange":"spring_garden:orange","herb":"spring_garden:herb"}
const ACCENTS:={"bluebell":Color("7f93e0"),"orange":Color("f0a04a"),"herb":Color("7dbb8a")}
const WOOD:=Color("8a6240")
const WOOD_LIGHT:=Color("b98a58")
const BOARD:=Color("f6ecd2")
const DONE_GREEN:=Color("4d9a5c")

static func active(snapshot:Dictionary) -> bool:
	var garden=snapshot.get("own_spring_garden",{})
	return garden is Dictionary and bool(garden.get("active",false))

static func collected(snapshot:Dictionary,id:String) -> bool:
	var garden=snapshot.get("own_spring_garden",{})
	if not (garden is Dictionary):return false
	return Scene.has_stamp(int(garden.get("mask",0)),id)

static func cell_of(id:String) -> Vector2i:
	return Scene.SPOTS[id].cell

## Station ids in fixed SPOTS order (empty unless active).
static func ids(snapshot:Dictionary) -> Array[String]:
	var out:Array[String]=[]
	if not active(snapshot):return out
	for id:String in Scene.ORDER:
		out.append(id)
	return out

## Focus points for stations whose stamp is still missing (cell centre).
static func points(snapshot:Dictionary) -> Dictionary:
	var out:={}
	for id:String in ids(snapshot):
		if not collected(snapshot,id):out[POINT_KEYS[id]]=Vector2(cell_of(id))+Vector2(0.5,0.5)
	return out

static func title(id:String) -> String:
	var spot:Dictionary=Scene.SPOTS.get(id,{})
	return str(spot.get("title",""))

## Draws one station sign inside the tile whose top-left is `at`.
static func draw_sign(canvas:CanvasItem,at:Vector2,id:String,done:bool,elapsed:float=0.0,reduced:bool=false) -> void:
	var accent:Color=ACCENTS.get(id,Color("e8b0c8"))
	var dim:=0.55 if done else 1.0
	var sway:=0.0 if done or reduced else roundf(sin(elapsed*2.0+float(cell_of(id).x)))
	# Soft ground shadow and post.
	canvas.draw_rect(Rect2(at+Vector2(7,27),Vector2(18,3)),Color(0.2,0.28,0.2,0.28))
	canvas.draw_rect(Rect2(at+Vector2(14,16),Vector2(4,12)),WOOD.darkened(0.0 if not done else 0.1))
	canvas.draw_rect(Rect2(at+Vector2(14,16),Vector2(1,12)),WOOD_LIGHT)
	# Board.
	canvas.draw_rect(Rect2(at+Vector2(4,3),Vector2(24,15)),WOOD)
	canvas.draw_rect(Rect2(at+Vector2(5,4),Vector2(22,13)),BOARD.darkened(0.12 if done else 0.0))
	canvas.draw_rect(Rect2(at+Vector2(5,4),Vector2(22,2)),accent.lerp(Color.WHITE,0.35 if done else 0.0))
	# Flower on the board: existing item pixel art, tinted down once collected.
	var spot:Dictionary=Scene.SPOTS.get(id,{})
	var icon:=ItemArt.icon(str(spot.get("item",""))) as Texture2D
	if icon!=null:
		canvas.draw_texture_rect(icon,Rect2(at+Vector2(8,4+sway),Vector2(16,16)),false,Color(1,1,1,dim))
	else:
		_fallback_flower(canvas,at+Vector2(16,10),accent,dim)
	if done:
		# Check accent on the board corner.
		var c:=at+Vector2(19,10)
		canvas.draw_circle(c+Vector2(6,5),6.0,Color("fff8dd"))
		canvas.draw_circle(c+Vector2(6,5),5.0,DONE_GREEN)
		canvas.draw_rect(Rect2(c+Vector2(2,5),Vector2(2,2)),Color.WHITE)
		canvas.draw_rect(Rect2(c+Vector2(4,7),Vector2(2,2)),Color.WHITE)
		canvas.draw_rect(Rect2(c+Vector2(6,5),Vector2(2,2)),Color.WHITE)
		canvas.draw_rect(Rect2(c+Vector2(8,3),Vector2(2,2)),Color.WHITE)

static func _fallback_flower(canvas:CanvasItem,center:Vector2,accent:Color,dim:float) -> void:
	var tint:=Color(accent.r,accent.g,accent.b,dim)
	canvas.draw_rect(Rect2(center+Vector2(-1,0),Vector2(2,7)),Color(0.43,0.62,0.4,dim))
	canvas.draw_rect(Rect2(center+Vector2(-4,-3),Vector2(8,4)),tint)
	canvas.draw_rect(Rect2(center+Vector2(-2,-5),Vector2(4,8)),tint)
	canvas.draw_rect(Rect2(center+Vector2(-1,-2),Vector2(2,2)),Color(0.85,0.65,0.4,dim))
