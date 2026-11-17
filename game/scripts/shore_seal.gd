extends RefCounted

const NAME:="胖海豹"
const POINT:="shore_seal"
const SITE:=Vector2i(52,57)
const ACTION:="seal_observe"
const Coast=preload("res://scripts/wangan_coast.gd")
const COLORS:={"o":Color("535461"),"s":Color("7d8990"),"c":Color("a5b5b5"),
	"w":Color("d7e0d6"),"d":Color("383744"),"p":Color("d89c91")}
const PIXELS:=[
	"................oooo......",
	"..............ooccccoo....",
	".............occcccwwo....",
	"............occccdcwdwo...",
	"...........occcwwwdddwo...",
	"....oo...oocccccwwpwpwo...",
	"...ossooooccccccccwwwo....",
	"..ossoccccccccccccccco....",
	".ossoocccscccsccccccwo....",
	".oosoccscccscscccccwwo....",
	"...oosccccccccccccwwwo....",
	"....oossssscccwwoooowo....",
	"......oooooooooo..ooo.....",
]
static var frames:Dictionary={}

static func present(now:float)->bool:
	return not Coast.high_tide(now)

static func texture(blink:=false)->Texture2D:
	if not frames.has(blink):
		var art:=Image.create_empty(26,PIXELS.size(),false,Image.FORMAT_RGBA8)
		for y in PIXELS.size():
			for x in PIXELS[y].length():
				var ink:String=PIXELS[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if blink:
			art.set_pixel(17,3,COLORS.c)
			art.set_pixel(20,3,COLORS.w)
		frames[blink]=ImageTexture.create_from_image(art)
	return frames[blink]
