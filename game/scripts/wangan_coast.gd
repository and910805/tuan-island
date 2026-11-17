extends RefCounted

# Add a walkable southern spit to the prototype island. The original land mask
# remains in use everywhere, including the approach from the village.
const SHORE_ROWS:={
	54:Vector2i(52,54),
	55:Vector2i(46,54),
	56:Vector2i(45,53),
	57:Vector2i(47,52),
	58:Vector2i(49,50),
}
const LANDING_X:=[49,50]
const VISITOR_AREA:=Rect2(45,51,10,8)
const FERRY_LANDING:=Vector2(52.5,30.5)
const FERRY_ACCESS:=Rect2i(44,30,11,1)
const FISHING_WATER:=Rect2i(47,59,6,1)
const FISHING_SPOT:="wangan_south_shore"
const SHELL_CELL:=Vector2i(47,56)
const SHELL_POINT:="wangan_shell"
const SHELL_ITEM:="seashell"
const SHELL_RESPAWN:=90.0
const STAR_ROWS:={56:Vector2i(33,37),57:Vector2i(31,38),58:Vector2i(30,38),59:Vector2i(32,37)}
const STAR_REPAIR:=Vector2i(34,52)
const STAR_REPAIR_POINT:="wangan_repair_star_walk"
const STAR_COST:={"plank":8,"fiber":4}
const STAR_SAND:=Vector2i(36,58)
const STAR_SAND_POINT:="wangan_gather_star_sand"
const STAR_SAND_RESPAWN:=90.0
const STAR_POOL:=Rect2i(31,58,2,1)
const STAR_POOL_SPOT:="wangan_star_tidepool"
const DOCK_ORDERS:=Vector2i(51,32)
const DOCK_ORDERS_POINT:="wangan_dock_orders"
const STAR_POOL_ART=preload("res://assets/ui-life/wangan-star-pool.png")
const TIDE_SECONDS:=240.0
const WEIR_AT:=Vector2(44.15,57.1)
const WEIR_SIZE:=Vector2(144,84)
const WEIR_ART=preload("res://assets/ui-life/wangan-live-weir.png")

static func shore_cell(cell:Vector2i)->bool:
	var span:Vector2i=SHORE_ROWS.get(cell.y,Vector2i(1,0))
	return cell.x>=span.x and cell.x<=span.y

static func star_shore(cell:Vector2i)->bool:
	var span:Vector2i=STAR_ROWS.get(cell.y,Vector2i(1,0))
	return cell.x>=span.x and cell.x<=span.y

static func star_boardwalk(cell:Vector2i)->bool:
	return cell.x in [34,35] and cell.y in range(54,58)

static func boardwalk(cell:Vector2i)->bool:
	return cell.x in LANDING_X and cell.y in range(51,57)

static func ferry_walk(cell:Vector2i)->bool:
	return cell.y==30 and cell.x in range(51,55)

static func tide_height(time:float)->float:
	return (1.0+cos(TAU*fposmod(time,TIDE_SECONDS)/TIDE_SECONDS))*0.5

static func high_tide(time:float)->bool:
	var elapsed:=fposmod(time,TIDE_SECONDS)
	return elapsed<TIDE_SECONDS*0.25 or elapsed>=TIDE_SECONDS*0.75

static func next_tide_text(time:float)->String:
	var elapsed:=fposmod(time,TIDE_SECONDS)
	var high:=high_tide(time)
	var boundary:=TIDE_SECONDS*(0.25 if high else 0.75)
	var remaining:=ceili(fposmod(boundary-elapsed,TIDE_SECONDS))
	return "%s %d:%02d 後"%["退潮" if high else "漲潮",floori(remaining/60.0),remaining%60]

static func draw_weir(canvas:CanvasItem,at:Vector2,time:float,elapsed:float,reduced_motion:bool)->void:
	var tide:=tide_height(time)
	var target:=Rect2(at,WEIR_SIZE)
	canvas.draw_texture_rect_region(WEIR_ART,target,Rect2(Vector2.ZERO,WEIR_SIZE),Color(1,1,1,1.0-tide))
	canvas.draw_texture_rect_region(WEIR_ART,target,Rect2(Vector2(0,WEIR_SIZE.y),WEIR_SIZE),Color(1,1,1,tide))
	for i in 3:
		var drift:=0.0 if reduced_motion else sin(elapsed*1.35+i*1.9)*3.0
		var point:=at+Vector2(107+i*5+tide*14+drift,55-(i%2)*6-tide*12).round()
		var tint:=Color("e9d29a").lerp(Color("9dc6b5"),tide)
		canvas.draw_colored_polygon(PackedVector2Array([
			point+Vector2(-4,0),point+Vector2(-2,-2),point+Vector2(1,-1),
			point+Vector2(4,-2),point+Vector2(3,0),point+Vector2(4,2),
			point+Vector2(1,1),point+Vector2(-2,2),
		]),tint)

static func draw_star_pool(canvas:CanvasItem,at:Vector2,time:float,elapsed:float,reduced_motion:bool)->void:
	var bounds:=Rect2(at+Vector2(-8,-6),Vector2(80,44))
	var row:=44 if high_tide(time) else 0
	canvas.draw_texture_rect_region(STAR_POOL_ART,bounds,Rect2(0,row,80,44))
	if reduced_motion:return
	for index in 3:
		var drift:=fposmod(elapsed*6.0+index*9.0,22.0)
		var point:=bounds.position+Vector2(25+drift,18+index*4).round()
		var shimmer:=Color(0.82,0.96,0.89,0.23+0.16*sin(elapsed*2.1+index))
		canvas.draw_line(point,point+Vector2(6,0),shimmer)
