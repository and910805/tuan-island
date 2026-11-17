extends RefCounted

const FIELD:="companion_cat"
const NAME:="圍巾貓"
const SITE:=Vector2i(46,38)
const Memory=preload("res://scripts/wangan_memory.gd")
const ACTIONS:=["cat_adopt","cat_follow","cat_rest","cat_pet","cat_yarn"]
const COLORS:={"o":Color("513c36"),"g":Color("d6a679"),"w":Color("ffead2"),
	"d":Color("573a42"),"r":Color("a9504e"),"p":Color("e89073")}
const SPRITE:=[
	"..o....o.........",
	".ogo..ogo........",
	".ogoooogo........",
	".ogggwggo........",
	".ogdgwgdo.....oo.",
	".ogwwdwwgo...ogo.",
	"..owwwwwo....ogo.",
	"...orrro.....ogo.",
	"...orgggo...ogo..",
	"...ogwgggo.oogo..",
	"...ogwgggooogo...",
	"...owogwggggo....",
	"...ooooooo...o...",
]
static var frames:Dictionary={}
static var ball:Texture2D

static func site(snapshot:Dictionary)->Vector2i:
	return SITE if Memory.courtyard_available(snapshot) else Memory.SITE+Vector2i.LEFT

static func texture(greeting:=false) -> Texture2D:
	if not frames.has(greeting):
		var art:=Image.create_empty(17,13,false,Image.FORMAT_RGBA8)
		for y in SPRITE.size():
			for x in SPRITE[y].length():
				var ink:String=SPRITE[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if greeting:art.set_pixel(5,6,COLORS.p)
		frames[greeting]=ImageTexture.create_from_image(art)
	return frames[greeting]

static func yarn_texture()->Texture2D:
	if ball==null:
		var art:=Image.create_empty(7,6,false,Image.FORMAT_RGBA8)
		var rows:=["..ooo..",".orrpo.","orrprro","orprrro",".orrpo.","..ooo.."]
		for y in rows.size():
			for x in rows[y].length():
				if COLORS.has(rows[y][x]):art.set_pixel(x,y,COLORS[rows[y][x]])
		ball=ImageTexture.create_from_image(art)
	return ball
