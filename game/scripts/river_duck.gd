extends RefCounted

const SITE:=Vector2i(54,41)
const EGG:="duck_egg"
const QUALITY_EGG:="quality_duck_egg"
const COLORS:={"o":Color("564a4e"),"w":Color("fff0d8"),"s":Color("d8bca5"),
	"b":Color("956c53"),"d":Color("3b3138"),"m":Color("d99a53"),"g":Color("91b39a"),
	"l":Color("7fa861"),"v":Color("48765a")}
const PIXELS:=[
	"............oooo...",
	"...........owwwwo..",
	"..........owwdwwoo.",
	"..........owwwommo.",
	".........oowwwomoo.",
	".ooo....oowwwoo....",
	".owwooooowwwoo.....",
	"..osbwwowwwwo......",
	"...obbwwsswo.......",
	"....oooosoo........",
]
const EGG_PIXELS:=["...oooo...","..oggggo..",".oggwgggo.",".owwgwggo.",
	".owwgwggo.",".owwgwggo.",".owggggo..","..ooooo..."]
static var frames:Dictionary={}
const REEDS:=[".....b.....","..b..l..b..","..l..l..l..","..v.lgl.v..",
	".lv.lv.vgl.","..vglv.vv..","...vlvlv...","...vvvvv..."]

static func pixel_texture(id:String,rows:Array)->Texture2D:
	if not frames.has(id):
		var art:=Image.create_empty(rows[0].length(),rows.size(),false,Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				var ink:String=rows[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		frames[id]=ImageTexture.create_from_image(art)
	return frames[id]

static func texture(egg:=false)->Texture2D:
	return pixel_texture("egg" if egg else "duck",EGG_PIXELS if egg else PIXELS)

static func reed_texture()->Texture2D:
	return pixel_texture("reeds",REEDS)

static func swim_position(now:float,reduced_motion:bool)->Vector2:
	var center:=Vector2(55.82,float(SITE.y)+0.85)
	if reduced_motion:return center
	return center+Vector2(sin(now*0.65)*0.3,sin(now*0.9)*0.75)
