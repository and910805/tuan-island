extends RefCounted

const Bond=preload("res://scripts/resident_bond.gd")
const NAME:="風鈴鹿"
const POINT:="windbell_deer"
const SITE:=Vector2i(42,26)
const NO_SITE:=Vector2i(-1,-1)
# Clear ground north of the windbell tree on the base map. Keep the original
# four sites first so older islands keep the same encounter when possible.
const SITES:=[SITE,Vector2i(41,26),Vector2i(42,25),Vector2i(43,26),
	Vector2i(42,27),Vector2i(41,27),Vector2i(43,27),Vector2i(41,25),Vector2i(43,25)]
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
	return bool(snapshot.get("festival_story_open",false)) and site(snapshot)!=NO_SITE

static func site(snapshot:Dictionary)->Vector2i:
	var bell_cell:=Bond.bell_cell(snapshot) if snapshot.get("festival_story_open",false) and Bond.present(snapshot,"lingpopo") else NO_SITE
	for cell:Vector2i in SITES:
		if cell==bell_cell:continue
		var key:="%d,%d"%[cell.x,cell.y]
		if snapshot.get("objects",{}).has(key) or snapshot.get("crops",{}).has(key):continue
		if snapshot.get("forest",{}).has(key) or snapshot.get("roofs",{}).has(key):continue
		return cell
	return NO_SITE

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
