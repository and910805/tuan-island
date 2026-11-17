extends RefCounted

const NAME:="風鈴鹿"
const POINT:="windbell_deer"
const SITE:=Vector2i(42,26)
const ACTION:="observe_windbell_deer"
const COLORS:={"o":Color("5e463f"),"b":Color("a46f58"),"a":Color("d39c71"),
	"w":Color("f5dcc4"),"d":Color("483640"),"p":Color("c87b70"),"g":Color("d6ac62")}
const PIXELS:=[
	"....o.......o...............",
	"...o.o.....o.o..............",
	".oo.o.......o.oo............",
	"...oo.......oo..............",
	".....o.....o................",
	"..oo..ooooo..oo.............",
	"..obooaaaaaoobo.............",
	"...oobaaaaaboo..............",
	"....oadabadbao..............",
	"....oawaaaawao..............",
	"....oawwawwbao..............",
	".....owddwbao...............",
	"......owwwao................",
	".......obpo...........oo....",
	".......opgoodoooooooobwwo...",
	".......obgowaaaaaaaboo......",
	".......obboaaawawabbbo......",
	".......obaoaaaawaaabbaoo....",
	".......obaoaaaaaaaabbao.....",
	".......obbaoobbbbaabao......",
	"........ooooooooooooo.......",
	".........ob.o.....ob.o......",
	".........oa.o.....oa.o......",
	".........oo.o.....oo.o......",
	"........oooo.....oooo.......",
]
static var frames:Dictionary={}

static func present(snapshot:Dictionary)->bool:
	return bool(snapshot.get("festival_story_open",false))

static func site(snapshot:Dictionary)->Vector2i:
	for cell:Vector2i in [SITE,Vector2i(41,26),Vector2i(42,25),Vector2i(43,26)]:
		var key:="%d,%d"%[cell.x,cell.y]
		if not snapshot.get("objects",{}).has(key) and not snapshot.get("crops",{}).has(key) and not snapshot.get("forest",{}).has(key):
			return cell
	return SITE

static func texture(blink:=false)->Texture2D:
	if not frames.has(blink):
		var art:=Image.create_empty(28,PIXELS.size(),false,Image.FORMAT_RGBA8)
		for y in PIXELS.size():
			for x in PIXELS[y].length():
				var ink:String=PIXELS[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if blink:
			for eye in [6,10]:art.set_pixel(eye,8,COLORS.a)
		frames[blink]=ImageTexture.create_from_image(art)
	return frames[blink]
