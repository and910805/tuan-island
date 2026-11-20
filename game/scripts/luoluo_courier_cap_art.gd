extends RefCounted
## 洛洛的信差帽。手帳用正面，遊戲角色則依朝向顯示帽舌、信封或後扣。
## Callers must keep Control texture_filter = TEXTURE_FILTER_NEAREST (this file does not set it).

const WIDTH:=27
const HEIGHT:=15
## Same anchor family as the wool hat: x centred on foot, bottom edge at foot.y-29.
const OFFSET_X:=-13   # -(WIDTH/2) as an integer so .round() never shifts a half pixel
const OFFSET_Y:=-44

const PALETTE:={
	"O":Color("2f3f52"), # ink-blue outline
	"B":Color("5f86a3"), # muted ocean blue crown
	"b":Color("476b87"), # crown shade / band
	"L":Color("7fa3bb"), # crown highlight
	"C":Color("efe0bd"), # warm cream seam
	"c":Color("d2bf94"), # cream seam shade
	"V":Color("8a5a3a"), # leather visor
	"W":Color("a87649"), # visor highlight
	"v":Color("6a4129"), # visor shade
	"E":Color("f4ead2"), # envelope paper
	"e":Color("b59a6c"), # envelope flap line
}

const FRONT:=[
	"........OOOOOOOOOOO........",
	".....OBLLBBBBCBBBBBBBO.....",
	"...OBBLLLBBBBCBBBBBBBbbO...",
	"..OBBLLLBBBBBCBBBBBBBBbbO..",
	".OBBLLLBBBBBBCBBBBBBBBBbbO.",
	".OBLLBBBBBEeEEEeEBBBBBBBbO.",
	".OBLBBBBBBEEeEeEEBBBBBBbbO.",
	".OBBBBBBBBEEEeEEEBBBBBBbbO.",
	".OBBBBBBBBEEEEEEEBBBBBbbbO.",
	".OcCCCCCCCCCCCCCCCCCCCCCcO.",
	"ObbbbbbbbbbbbbbbbbbbbbbbbbO",
	"OOOOOOOOOOOOOOOOOOOOOOOOOOO",
	".....OVWWWVVVVVVVVVvvO.....",
	".......OVVVVVVVVVvvO.......",
	".........OOOOOOOOO.........",
]
const LEFT:=[
	"........OOOOOOOOOOO........",
	"......OBBLLBBBBBBBBbO......",
	"....OBBLLLBBBBBBBBBBbO.....",
	"...OBBLLBBBBBBBBBBBBbbO....",
	"..OBBLLBBBBBBBBBBBBBBbbO...",
	"..OBLBBEeEBBBBBBBBBBBBbO...",
	"..OBBBBEEEbBBBBBBBBBBBbO...",
	"..OBBBBEEEBBBBBBBBBBBbbO...",
	"..OBBBBBBBBBBBBBBBBBBbbO...",
	"..OcCCCCCCCCCCCccccccccO...",
	".ObbbbbbbbbbbbbbbbbbbbbbO..",
	"OVWWWVVOOOOOOOOOOOOOOOO....",
	"OVWWVVVO...................",
	"OVVVvO.....................",
	".OOOO......................",
]
const BACK:=[
	"........OOOOOOOOOOO........",
	".....OBBLLBBBBBBBBBbBO.....",
	"...OBBLLBBBBBBBBBBBBbbBO...",
	"..OBBLLBBBBBBBBBBBBBBBbbO..",
	".OBBLLBBBBBBBLBBBBBBBBBbbO.",
	".OBLLBBBBBBBBLBBBBBBBBBbbO.",
	".OBLBBBBBBBBBbBBBBBBBBBbbO.",
	".OBBBBBBBBBBBbBBBBBBBBBbbO.",
	".OBBBBBBBBBBBbBBBBBBBBbbbO.",
	".ObbbbbbbbbbbbbbbbbbbbbbbO.",
	"ObbbbbbbbbbbbbbbbbbbbbbbbbO",
	"OOOOOOOOOVVVVVVVVVOOOOOOOOO",
	"........OVWWWcVVvvO........",
	".........OVVVvVVvO.........",
	"..........OOOOOOO..........",
]
static var cache:Dictionary[Vector2i,Texture2D]={}

static func texture(facing:=Vector2i.DOWN) -> Texture2D:
	var rows:=FRONT
	match facing:
		Vector2i.LEFT,Vector2i.RIGHT:rows=LEFT
		Vector2i.UP:rows=BACK
		_:facing=Vector2i.DOWN
	if cache.has(facing):return cache[facing]
	var art:=Image.create_empty(WIDTH,HEIGHT,false,Image.FORMAT_RGBA8)
	for y in HEIGHT:
		var row:String=rows[y]
		for x in WIDTH:
			var key:=row[x]
			if key!=".":art.set_pixel(x,y,PALETTE[key])
	if facing==Vector2i.RIGHT:art.flip_x()
	cache[facing]=ImageTexture.create_from_image(art)
	return cache[facing]

## foot = the character's foot point (same anchor person_sprite uses).
static func draw(canvas:CanvasItem,foot:Vector2,facing:=Vector2i.DOWN) -> void:
	canvas.draw_texture(texture(facing),(foot+Vector2(OFFSET_X,OFFSET_Y)).round())
