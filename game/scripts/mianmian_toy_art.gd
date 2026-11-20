extends RefCounted
## T066 N06-3: pixel art for the toy sewn with Mianmian (布球 / 布偶), 14x14, crooked stitching.
## Shared by the reward page and the local in-world pet play so both show the same toy.
## Reads only the viewer's own resident_goals.mianmian stage 3 choice.

const SIZE:=14
const OUTLINE:=Color("6b3f2c")
const CLOTH:=Color("d98e6b")
const LIGHT:=Color("ecb48f")
const STITCH:=Color("fff1d2")
const DARK:=Color("3c2d22")
static var cache:Dictionary={}

static func choice(snapshot:Dictionary) -> String:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return ""
	var mianmian:Variant=goals.get("mianmian")
	if not mianmian is Dictionary:return ""
	var event:Variant=mianmian.get("3",mianmian.get(3))
	if not event is Dictionary or event.get("state")!="done":return ""
	var kind:=str(event.get("choice",""))
	return kind if kind in ["ball","doll"] else ""

static func label(kind:String) -> String:
	return "布球" if kind=="ball" else "布偶"

static func texture(kind:String) -> Texture2D:
	if not cache.has(kind):
		var art:=Image.create_empty(SIZE,SIZE,false,Image.FORMAT_RGBA8)
		if kind=="ball":_ball(art)
		else:_doll(art)
		cache[kind]=ImageTexture.create_from_image(art)
	return cache[kind]

static func _disc(art:Image,center:Vector2,radius:float,fill:Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var d:=Vector2(x,y).distance_to(center)
			if d<=radius:art.set_pixel(x,y,OUTLINE if d>radius-1.0 else fill)

static func _ball(art:Image) -> void:
	_disc(art,Vector2(6.5,6.5),6.3,CLOTH)
	for p:Vector2i in [Vector2i(3,3),Vector2i(4,3),Vector2i(3,4),Vector2i(4,4),Vector2i(5,3)]:art.set_pixelv(p,LIGHT)
	# A deliberately crooked seam: one stitch drifts a pixel off the line.
	for p:Vector2i in [Vector2i(3,9),Vector2i(5,8),Vector2i(7,8),Vector2i(8,6),Vector2i(10,6)]:art.set_pixelv(p,STITCH)

static func _doll(art:Image) -> void:
	_disc(art,Vector2(6.5,4.5),3.6,CLOTH)
	for ear:Vector2i in [Vector2i(3,0),Vector2i(4,0),Vector2i(9,0),Vector2i(10,0),Vector2i(3,1),Vector2i(10,1)]:art.set_pixelv(ear,OUTLINE)
	for y in range(8,14):
		for x in range(3,11):
			var edge:=y==13 or x==3 or x==10
			art.set_pixel(x,y,OUTLINE if edge else CLOTH)
	for p:Vector2i in [Vector2i(5,4),Vector2i(8,4)]:art.set_pixelv(p,DARK)
	for p:Vector2i in [Vector2i(6,6),Vector2i(7,6)]:art.set_pixelv(p,STITCH)
	for p:Vector2i in [Vector2i(5,10),Vector2i(6,11),Vector2i(8,10),Vector2i(8,12)]:art.set_pixelv(p,STITCH)
