extends RefCounted

const FIELD:="companion_dog"
const NAME:="小柴犬"
const SITE:=Vector2i(51,33)
const ACTIONS:=["dog_adopt","dog_follow","dog_rest","dog_pet","dog_toy"]
const COLORS:={"o":Color("593d37"),"g":Color("ce8b52"),"w":Color("fff0d0"),
	"d":Color("473238"),"r":Color("675ca2"),"b":Color("baabe1")}
const SPRITE:=[
	"..oo....oo..........",
	".ogwo..owgo.........",
	".oggooooggo.........",
	".oggggggggo.....ooo.",
	".ogdgggdggo....ogwo.",
	".ogwwdwwggo....oggo.",
	"..owwwwwoo....oooo..",
	"...orrrrro..oggo....",
	"...owgggggooggo.....",
	"...owgggggggggo.....",
	"...owwgggwwwggo.....",
	"...owowooowowo.....",
	"...oooo...oooo.....",
]
static var frames:Dictionary={}

static func texture(toy:=false) -> Texture2D:
	if not frames.has(toy):
		var art:=Image.create_empty(20,13,false,Image.FORMAT_RGBA8)
		for y in SPRITE.size():
			for x in SPRITE[y].length():
				var ink:String=SPRITE[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if toy:
			for x in range(3,9):
				art.set_pixel(x,6,COLORS.r)
				art.set_pixel(x,7,COLORS.b if x in [3,8] else COLORS.r)
		frames[toy]=ImageTexture.create_from_image(art)
	return frames[toy]
