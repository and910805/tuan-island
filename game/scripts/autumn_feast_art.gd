extends RefCounted
## Autumn harvest feast: a small wooden platter with up to three produce icons (roots / greens /
## gold) beside the shared table plus a tiny centrepiece on the table top. Program-drawn trim,
## existing item PNGs only. Drawn only while the shared round is 'collect' or 'served'.

const ItemArt=preload("res://scripts/inventory_item_art.gd")
const SLOTS:=["roots","greens","gold"]
const WOOD_DARK:=Color("6a3a1c")
const WOOD:=Color("a8642c")
const WOOD_LIGHT:=Color("d99a4a")
const CLOTH:=Color("c4562a")
const CLOTH_LIGHT:=Color("f0a03c")
const LEAF_RED:=Color("c0452a")
const LEAF_GOLD:=Color("e6a93a")
const STEAM:=Color(1.0,0.96,0.85,0.55)
const EMPTY:=Color(0.42,0.24,0.12,0.55)
## Platter rectangle relative to the table cell origin (right of the table, clear of the label).
const PLATTER:=Rect2(30,14,34,17)
const ICON:=10.0

static func active(feast) -> bool:
	return feast is Dictionary and str(feast.get("phase","idle")) in ["collect","served"]

static func draw(canvas:CanvasItem,at:Vector2,feast,elapsed:float,reduced_motion:bool) -> void:
	if not active(feast):return
	var served:=str(feast.get("phase",""))=="served"
	var origin:=at.floor()
	var entries:Dictionary=feast.get("entries",{})
	var r:=PLATTER
	var base:=origin+r.position
	# Platter: dark rim, wood body, light top edge and a warm cloth runner.
	canvas.draw_rect(Rect2(base+Vector2(0,2),Vector2(r.size.x,r.size.y-2)),WOOD_DARK)
	canvas.draw_rect(Rect2(base+Vector2(1,3),Vector2(r.size.x-2,r.size.y-5)),WOOD)
	canvas.draw_rect(Rect2(base+Vector2(1,2),Vector2(r.size.x-2,1)),WOOD_LIGHT)
	canvas.draw_rect(Rect2(base+Vector2(2,r.size.y-5),Vector2(r.size.x-4,2)),CLOTH)
	canvas.draw_rect(Rect2(base+Vector2(2,r.size.y-5),Vector2(r.size.x-4,1)),CLOTH_LIGHT)
	for i in 3:
		var at_slot:=base+Vector2(3+i*11,0)
		var id:String=entries.get(SLOTS[i],"")
		var tex:Texture2D=ItemArt.icon(id) if id!="" else null
		if tex!=null:
			canvas.draw_texture_rect(tex,Rect2(at_slot,Vector2(ICON,ICON)),false)
		else:
			# Awaiting contribution: a dim plate ring instead of produce.
			canvas.draw_rect(Rect2(at_slot+Vector2(1,3),Vector2(8,6)),EMPTY)
			canvas.draw_rect(Rect2(at_slot+Vector2(2,4),Vector2(6,4)),WOOD_DARK)
	# Pixel trim: a small leaf garland at both platter ends.
	for end_x in [0.0,r.size.x-3.0]:
		canvas.draw_rect(Rect2(base+Vector2(end_x,1),Vector2(3,2)),LEAF_RED)
		canvas.draw_rect(Rect2(base+Vector2(end_x+1,0),Vector2(2,1)),LEAF_GOLD)
	# Shared centrepiece on the table's top-right corner: a tiny gourd with a leaf.
	var c:=origin+Vector2(25,0)
	canvas.draw_rect(Rect2(c+Vector2(0,2),Vector2(5,4)),Color("d9792a") if served else Color("b8702e"))
	canvas.draw_rect(Rect2(c+Vector2(1,1),Vector2(3,1)),Color("f0a03c"))
	canvas.draw_rect(Rect2(c+Vector2(2,0),Vector2(1,1)),Color("5f7a3a"))
	canvas.draw_rect(Rect2(c+Vector2(3,0),Vector2(2,1)),LEAF_GOLD)
	if reduced_motion or not served:return
	# Optional motion: steam over the platter and a drifting leaf.
	for i in 2:
		var phase:=fposmod(elapsed*0.6+float(i)*0.5,1.0)
		var sx:=base.x+9.0+float(i)*12.0+roundf(sin((elapsed+i)*2.0))
		canvas.draw_rect(Rect2(Vector2(sx,base.y-2.0-roundf(phase*6.0)),Vector2(1,2)),Color(STEAM.r,STEAM.g,STEAM.b,STEAM.a*(1.0-phase)))
	var drift:=fposmod(elapsed*0.35,1.0)
	var leaf:=Vector2(base.x+4.0+roundf(drift*26.0),base.y-8.0+roundf(drift*7.0))
	canvas.draw_rect(Rect2(leaf,Vector2(2,1)),LEAF_RED)
