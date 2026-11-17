extends RefCounted

# Display-only pixel art for the two ferry-side feeding stations (livestock.gd
# ANIMALS "cow" 奶糖牛 and "sheep" 雲朵羊). Standalone: no World preload, no
# registration, no gameplay writes. Every sprite is composed in memory from the
# hand-placed pixel rows below (outlined, shaded, 1 char = 1 native pixel) and
# cached per (id, state, frame) as a nearest-friendly ImageTexture.
#
# Canvas 48x32 native px (1.5 x 1 world tiles at TILE 32), feet on row 31.
# Anchor = bottom centre (24, 32): place at the station tile's bottom centre,
# i.e. screen(cell) + Vector2(16, 32) - anchor.
#
# States (state_for maps a livestock.gd record):
#   idle    - head up, standing; idle frame bobs the head 1px.
#   fed     - head lowered into a hay trough in front (trough widens the
#             silhouette low-left); frame 1 chews (head +1px, hay crumb).
#   produce - head up, product beside the rear (milk can / bound wool) with a
#             twinkle that hops between two positions.
# Motion is strictly whole native pixels. reduced_motion => frame 0 and zero
# offset for every elapsed time (a fully static sprite).

const SIZE := Vector2i(48, 32)
const ANCHOR := Vector2i(24, 32)
const IDS := ["cow", "sheep"]
const STATES := ["idle", "fed", "produce"]
const FRAMES := 2
const FRAME_SECONDS := 0.6
const PET_SECONDS:=1.4
const BRUSH=preload("res://assets/livestock/grooming-brush.png")
const PET_PIXELS:=[".oo.oo.","oPPoPPo","oPppPPo",".oPPPo.","..oPo..","...o..."]
const COLLECTOR_PIXELS:=[
	"..oooooooooo..",
	".owwwwwwwwwwo.",
	"orrrrrrrrrrrro",
	"oooooooooooooo",
	"orrrRRmmRRrrro",
	"orrrMRmmMRrrro",
	"oRrrRRmmRRrrRo",
	"oRRrrrrrrrrRRo",
	".oooooooooooo.",
	"..oo......oo..",
]
const SHUFFLE_SECONDS := 0.9
const SHUFFLE := [0, 0, -1, -1, 0, 0, 1, 1]

const PALETTE := {
	"o": Color("3b2a25"), # warm outline shared with the island's sprites
	"w": Color("f4e8d2"), # milk-candy cream
	"s": Color("d8c6a8"), # cream shade
	"c": Color("c98a52"), # caramel patch
	"C": Color("9e6436"), # caramel shade / tail tuft
	"p": Color("e8a8a0"), # muzzle / udder
	"P": Color("c9827c"), # muzzle shade
	"k": Color("2a1f1c"), # eye / hoof
	"h": Color("f0dca0"), # horn
	"b": Color("e0b84a"), # bell
	"f": Color("f6f4ee"), # cloud wool
	"g": Color("d6dbe2"), # wool cool shade
	"G": Color("b4bccb"), # wool deep shade
	"d": Color("4a4250"), # sheep face / legs
	"D": Color("2e2833"), # sheep nose
	"e": Color("6a5f6e"), # sheep ear
	"n": Color("fbfdff"), # white glint (eye, milk)
	"r": Color("a0703f"), # trough wood
	"R": Color("6e4a2a"), # trough wood shade
	"y": Color("e6c860"), # hay / twine
	"Y": Color("b8973a"), # hay shade
	"m": Color("c9d3dc"), # milk can tin
	"M": Color("8d99a6"), # tin shade
	"x": Color("fff6b0"), # twinkle
}

const COW_BODY := [
	"..oooooooooooooooooooooo....",
	".owwwwccccwwwwwwwccwwwwwoo..",
	"owwwcccccCwwwwwwcccwwwwwo.o.",
	"owwcccCCcwwwwwwwcCCcwwwwo.o.",
	"owwwccccwwwwwwwwwcccwwwwo.o.",
	"owwwwccwwwwwwwwwwwwwwwwwo.o.",
	"owwwwwwwwwwwwccccwwwwwwwo.o.",
	"owwwwwwwwwwwcccCcwwwwwwwooCo",
	"oswwwwwwwwwwwcccwwwwwwwsooCo",
	"osswwwwwwwwwwwwwwwwwwwsso.o.",
	"ossssswwwwwwwwwwwwwssssso...",
	".ossssssssssssssPppPsssso...",
	"..ooooooooooooooPppPoooo....",
]

const COW_HEAD := [
	"......oho...",
	"...ooooooooo",
	"..owwwwwwwco",
	".owwkwwwwwoo",
	".owwwwwcwwo.",
	"owwwwwcccwo.",
	"oppppwwcwwo.",
	"opkpppwwwwo.",
	"opppppswwso.",
	".oPPPPoobo..",
	"..oooo.obo..",
]

const COW_LEG := [
	"owo",
	"owo",
	"owo",
	"oso",
	"kkk",
]

const SHEEP_BODY := [
	"...oo..oo..oo..oo..oo.....",
	"..offoofgoofgoofgoofgo....",
	".offffffffffgffffffffffo..",
	"offffffffffffffffgfffffoo.",
	"offfgffffffffffffffffgfofo",
	"offffffgfffffffgfffffffoo.",
	"offffffffffffffffffffffo..",
	"ogfffffffffgfffffffffggo..",
	"oggfffffffffffffffffgggo..",
	"oGgggfffffffffffffgggGGo..",
	".oGGggggggggggggggggGGo...",
	"..oooooooooooooooooooo....",
]

const SHEEP_HEAD := [
	"....ooooo...",
	"...offfgfo..",
	"..offgfffgo.",
	"..odffffffoo",
	".oddndddoeeo",
	"odddddddooeo",
	"odddddddo.o.",
	"oDdddddo....",
	".oDDddo.....",
	"..ooooo.....",
]

const SHEEP_LEG := [
	"odo",
	"odo",
	"odo",
	"oDo",
]

const TROUGH := [
	".yYy.yy.Yyy..",
	"oyyYyyyyYyyyo",
	"orrrrrrrrrrro",
	"oRrrrrrrrrrRo",
	".oRRRRRRRRRo.",
	".o.........o.",
]

const MILK_CAN := [
	"..oooo..",
	"..oMMo..",
	".oommoo.",
	"ommmmmMo",
	"omnnmmMo",
	"omccccMo",
	"omnmmmMo",
	"ommmmmMo",
	"oMmmmMMo",
	".oooooo.",
]

const WOOL_BUNDLE := [
	"..oo.oo..",
	".offoffo.",
	"offfffgfo",
	"offgffffo",
	"oyyyyyyyo",
	"offfffgfo",
	"ofgfffffo",
	".oggfggo.",
	"..ooooo..",
]

const TWINKLE := [
	".x.",
	"xnx",
	".x.",
]

const PARTS := {
	"COW_BODY": COW_BODY, "COW_HEAD": COW_HEAD, "COW_LEG": COW_LEG,
	"SHEEP_BODY": SHEEP_BODY, "SHEEP_HEAD": SHEEP_HEAD, "SHEEP_LEG": SHEEP_LEG,
	"TROUGH": TROUGH, "MILK_CAN": MILK_CAN, "WOOL_BUNDLE": WOOL_BUNDLE, "TWINKLE": TWINKLE,
}

const LAYOUT := {
	"cow": {
		"body": COW_BODY, "body_at": Vector2i(12, 14),
		"leg": COW_LEG, "leg_x": [15, 19, 25, 32], "leg_y": 27,
		"head": COW_HEAD, "head_up": Vector2i(3, 8), "head_down": Vector2i(1, 16),
		"trough_at": Vector2i(0, 26), "crumb": Vector2i(0, 24),
		"prop": MILK_CAN, "prop_at": Vector2i(40, 22),
		"twinkle": [Vector2i(39, 16), Vector2i(44, 18)],
	},
	"sheep": {
		"body": SHEEP_BODY, "body_at": Vector2i(14, 14),
		"leg": SHEEP_LEG, "leg_x": [17, 21, 30, 33], "leg_y": 28,
		"head": SHEEP_HEAD, "head_up": Vector2i(4, 11), "head_down": Vector2i(2, 19),
		"trough_at": Vector2i(0, 26), "crumb": Vector2i(0, 24),
		"prop": WOOL_BUNDLE, "prop_at": Vector2i(39, 23),
		"twinkle": [Vector2i(40, 17), Vector2i(45, 19)],
	},
}

static var cache: Dictionary = {}

static func has_animal(id: String) -> bool:
	return LAYOUT.has(id)

static func has_state(state: String) -> bool:
	return state in STATES

static func sprite_size() -> Vector2i:
	return SIZE

static func sprite_anchor() -> Vector2i:
	return ANCHOR

# Maps a livestock.gd record {"feed","ready","next"} to an art state. A waiting
# product wins (that is what the player needs to see); otherwise stocked feed
# means the animal is eating; an empty trough is idle.
static func state_for(record: Dictionary) -> String:
	if int(record.get("ready", 0)) > 0:
		return "produce"
	if int(record.get("feed", 0)) > 0:
		return "fed"
	return "idle"

static func frame_index(elapsed: float, reduced_motion: bool) -> int:
	if reduced_motion:
		return 0
	return posmod(int(floor(maxf(elapsed, 0.0) / FRAME_SECONDS)), FRAMES)

# Whole-pixel idle shuffle (the animal shifts its weight left/right by 1px).
# Eating and presenting stay planted so the trough/product stay aligned.
static func motion_offset(state: String, elapsed: float, reduced_motion: bool) -> Vector2i:
	if reduced_motion or state != "idle":
		return Vector2i.ZERO
	var step := posmod(int(floor(maxf(elapsed, 0.0) / SHUFFLE_SECONDS)), SHUFFLE.size())
	return Vector2i(int(SHUFFLE[step]), 0)

static func stamp(image: Image, rows: Array, at: Vector2i) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if ch == "." or not PALETTE.has(ch):
				continue
			var p := at + Vector2i(x, y)
			if p.x < 0 or p.y < 0 or p.x >= SIZE.x or p.y >= SIZE.y:
				continue
			image.set_pixelv(p, PALETTE[ch])

# Returns null for unknown animal/state/frame; never falls back to another sprite.
static func build_image(id: String, state: String, frame: int, body_offset:=Vector2i.ZERO,grooming:=false,walk_frame:=-1,animal_only:=false) -> Image:
	if not has_animal(id) or not has_state(state) or frame < 0 or frame >= FRAMES:
		return null
	var spec: Dictionary = LAYOUT[id]
	var image := Image.create_empty(SIZE.x, SIZE.y+maxi(0,body_offset.y), false, Image.FORMAT_RGBA8)
	for index in spec.leg_x.size():
		var step:=Vector2i.ZERO
		if walk_frame>=0:
			var raised:bool=(index+walk_frame)%2==0
			step=Vector2i(1 if raised else -1,-1 if raised else 0)
		stamp(image, spec.leg, Vector2i(int(spec.leg_x[index]), int(spec.leg_y))+body_offset+step)
	stamp(image, spec.body, spec.body_at+body_offset)
	var bob := Vector2i(0, 1 if frame == 1 and state != "produce" else 0)
	var head:Array=spec.head
	if grooming and id=="sheep":
		head=head.duplicate()
		head[4]=".odeedddoeeo"
	if state == "fed":
		stamp(image, head, spec.head_down+bob+body_offset)
		if not animal_only:stamp(image, TROUGH, spec.trough_at)
		if frame == 1 and not animal_only:
			stamp(image, ["Y"], spec.crumb)
	else:
		stamp(image, head, spec.head_up+bob+body_offset)
	if state == "produce" and not animal_only:
		stamp(image, spec.prop, spec.prop_at)
		stamp(image, TWINKLE, spec.twinkle[frame])
	return image

static func texture(id: String, state: String, frame: int = 0) -> Texture2D:
	var key := "%s:%s:%d" % [id, state, frame]
	if cache.has(key):
		return cache[key]
	var image := build_image(id, state, frame)
	if image == null:
		return null
	var tex := ImageTexture.create_from_image(image)
	tex.set_meta("livestock_art", key)
	cache[key] = tex
	return tex

static func texture_at(id: String, state: String, elapsed: float, reduced_motion: bool) -> Texture2D:
	return texture(id, state, frame_index(elapsed, reduced_motion))

# Top-left draw position (whole pixels) for a feet point in canvas space.
static func draw_origin(foot: Vector2, state: String, elapsed: float, reduced_motion: bool) -> Vector2:
	var base := foot.round() - Vector2(ANCHOR)
	return base + Vector2(motion_offset(state, elapsed, reduced_motion))

# Call from the canvas's _draw(). Returns false (draws nothing) for unknown
# IDs/states so the caller can keep its existing sign fallback.
static func draw(canvas: CanvasItem, foot: Vector2, id: String, state: String, reduced_motion: bool, elapsed: float, body_offset:=Vector2i.ZERO,grooming:=false,walk_frame:=-1,animal_only:=false,face_right:=false,zoom:=1.0) -> bool:
	var tex := texture_at(id, state, elapsed, reduced_motion)
	if tex == null:
		return false
	if grooming or animal_only or walk_frame>=0 or (body_offset!=Vector2i.ZERO and not reduced_motion):
		var frame:=frame_index(elapsed,reduced_motion)
		var key:="%s:%s:%d:%s:%s:%d:%s"%[id,state,frame,body_offset,grooming,walk_frame,animal_only]
		if not cache.has(key):
			cache[key]=ImageTexture.create_from_image(build_image(id,state,frame,body_offset,grooming,walk_frame,animal_only))
		tex=cache[key]
	var at:=draw_origin(foot, state, elapsed, reduced_motion)
	if face_right:
		canvas.draw_set_transform(Vector2(2.0*foot.x,0)*zoom,0.0,Vector2(-zoom,zoom))
		canvas.draw_texture(tex,at)
		canvas.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*zoom)
	else:canvas.draw_texture(tex,at)
	return true

## The trough / ready produce stay at the feed station when the sheep moves.
static func draw_station(canvas:CanvasItem,foot:Vector2,id:String,state:String,elapsed:float,quiet:bool)->void:
	if state not in ["fed","produce"]:return
	var frame:=frame_index(elapsed,quiet)
	var key:="station:%s:%s:%d"%[id,state,frame]
	if not cache.has(key):
		var image:=Image.create_empty(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
		var spec:Dictionary=LAYOUT[id]
		if state=="fed":stamp(image,TROUGH,spec.trough_at)
		else:
			stamp(image,spec.prop,spec.prop_at)
			stamp(image,TWINKLE,spec.twinkle[frame])
		cache[key]=ImageTexture.create_from_image(image)
	canvas.draw_texture(cache[key],foot.round()-Vector2(ANCHOR))

static func clear_cache() -> void:
	cache.clear()

static func reaction_offset(id:String,age:float,bond:int,reduced_motion:bool) -> Vector2:
	if reduced_motion or age<0.0 or age>=PET_SECONDS:return Vector2.ZERO
	var pulse:=sin(PI*clampf(age/PET_SECONDS,0.0,1.0))
	match id:
		"cow":return Vector2(0,roundf(pulse*(2 if bond<5 else 3)))
		"sheep":return Vector2(0,-roundf(pulse*(3 if bond<5 else 6)))
	return Vector2.ZERO

static func pet_heart_origin(foot:Vector2,age:float,reduced_motion:bool) -> Vector2:
	return foot.round()+Vector2(9,-38-(0 if reduced_motion else floori(age*8.0)))

static func draw_pet_heart(canvas:CanvasItem,foot:Vector2,age:float,reduced_motion:bool) -> void:
	if age<0.0 or age>=PET_SECONDS:return
	var texture_key:="pet-heart"
	if not cache.has(texture_key):
		var image:=Image.create_empty(7,6,false,Image.FORMAT_RGBA8)
		stamp(image,PET_PIXELS,Vector2i.ZERO)
		cache[texture_key]=ImageTexture.create_from_image(image)
	canvas.draw_texture(cache[texture_key],pet_heart_origin(foot,age,reduced_motion))

static func draw_brushing(canvas:CanvasItem,foot:Vector2,age:float,quiet:bool)->void:
	if age<0.0 or age>=PET_SECONDS:return
	var travel:=0.0 if quiet else roundf(sin(age*TAU*2.5)*4.0)
	canvas.draw_texture_rect(BRUSH,Rect2((foot+Vector2(-6+travel,-32)).round(),Vector2(20,20)),false)

static func collector_texture(count:int,capacity:int)->Texture2D:
	var status:="empty" if count==0 else ("full" if count>=capacity else "stored")
	var texture_key:="collector-"+status
	if not cache.has(texture_key):
		var image:=Image.create_empty(14,14,false,Image.FORMAT_RGBA8)
		stamp(image,COLLECTOR_PIXELS,Vector2i(0,4))
		if status=="stored":
			stamp(image,["ww","ww"],Vector2i(6,9))
		elif status=="full":
			stamp(image,[".y.","yyy",".y."],Vector2i(9,0))
			stamp(image,["yy","yy"],Vector2i(6,9))
		cache[texture_key]=ImageTexture.create_from_image(image)
	return cache[texture_key]
