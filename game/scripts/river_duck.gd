extends RefCounted

const SITE:=Vector2i(54,41)
const EGG:="duck_egg"
const QUALITY_EGG:="quality_duck_egg"
const FEED_ARRIVE:=0.48
const FEED_RETURN:=1.8
const FEED_DURATION:=2.48
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
const PECK_PIXELS:=[
	"...................",
	"...................",
	"...................",
	"...........oooo....",
	".........oowwwwoo..",
	".ooo....owwwwwdwo..",
	".owwooooowwwwwommo.",
	"..osbwwowwwwswoomo.",
	"...obbwwsswoo..oo..",
	"....oooosoo........",
]
const DISH_PIXELS:=[".ooomoooo..","oommmwmmoo.","obbbmmmbboo",".oobbbbooo.","...oooo...."]
static var frames:Dictionary={}
const REEDS:=[".....b.....","..b..l..b..","..l..l..l..","..v.lgl.v..",
	".lv.lv.vgl.","..vglv.vv..","...vlvlv...","...vvvvv..."]

static func pixel_texture(id:String,rows:Array,flip:=false)->Texture2D:
	if not frames.has(id):
		var art:=Image.create_empty(rows[0].length(),rows.size(),false,Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				var ink:String=rows[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if flip:art.flip_x()
		frames[id]=ImageTexture.create_from_image(art)
	return frames[id]

static func texture(egg:=false)->Texture2D:
	return pixel_texture("egg" if egg else "duck",EGG_PIXELS if egg else PIXELS)

static func reed_texture()->Texture2D:
	return pixel_texture("reeds",REEDS)

static func feeding_texture(pecking:bool,flip:=false)->Texture2D:
	if pecking:return pixel_texture("peck",PECK_PIXELS)
	return pixel_texture("duck_left",PIXELS,true) if flip else texture()

static func dish_texture()->Texture2D:
	return pixel_texture("dish",DISH_PIXELS)

static func swim_position(now:float,reduced_motion:bool)->Vector2:
	var center:=Vector2(55.82,float(SITE.y)+0.85)
	if reduced_motion:return center
	return center+Vector2(sin(now*0.65)*0.3,sin(now*0.9)*0.75)

static func feed_pose(origin:Vector2,station:Vector2,water:Vector2,age:float,penned:bool,quiet:bool)->Dictionary:
	if age<0.0 or age>=FEED_DURATION:return {}
	if quiet:return {"position":station,"peck":true,"flip":false}
	if not penned and age<FEED_ARRIVE:
		var t:=smoothstep(0.0,1.0,age/FEED_ARRIVE)
		return {"position":origin.lerp(station,t),"peck":false,"flip":true}
	if not penned and age>=FEED_RETURN:
		var t:=smoothstep(0.0,1.0,(age-FEED_RETURN)/(FEED_DURATION-FEED_RETURN))
		return {"position":station.lerp(water,t),"peck":false,"flip":false}
	var peck:=fposmod(maxf(0.0,age-FEED_ARRIVE),0.39)<0.23
	return {"position":station,"peck":peck,"flip":false}
