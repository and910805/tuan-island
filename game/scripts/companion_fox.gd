extends RefCounted

const FIELD:="companion_fox"
const NAME:="葉耳狐"
const REGION:="bamboo_grove"
const SITE:=Vector2i(20,25)
const TRACKS:={Vector2i(16,23):2,Vector2i(22,28):4}
const ACTIONS:=["fox_adopt","fox_follow","fox_rest","fox_pet","fox_track","fox_hint"]
const COLORS:={"o":Color("51413b"),"t":Color("bf7650"),"w":Color("ffebcb"),
	"l":Color("75a465"),"s":Color("456d4d"),"d":Color("453431")}
const SPRITE:=[
	".soo....oos..........",
	".slto..otls..........",
	"..oltootlo...........",
	"..ottwtto............",
	".otdtwtdto..........o",
	".otwwwwwwto......ooow",
	"..owwdwwoo.....ootwwo",
	"...oowooo.....otttwo.",
	"....otttto...otttwo..",
	"....ottttto.otttoo...",
	"....owtwtwoootoo.....",
	"....oo.oo..ooo.......",
]
static var portrait:Texture2D

static func points(player:Dictionary)->Dictionary:
	var result:={"companion_fox":Vector2(SITE)+Vector2(0.5,0.5)}
	var progress:=int(player.get("fox_tracks",0))
	if progress>0:
		for cell:Vector2i in TRACKS:
			if (progress&int(TRACKS[cell]))==0:
				result["fox_track:%d,%d"%[cell.x,cell.y]]=Vector2(cell)+Vector2(0.5,0.5)
	return result

static func texture()->Texture2D:
	if portrait==null:
		var art:=Image.create_empty(21,12,false,Image.FORMAT_RGBA8)
		for y in SPRITE.size():
			for x in SPRITE[y].length():
				var ink:String=SPRITE[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		portrait=ImageTexture.create_from_image(art)
	return portrait

static func home_clues(world,snapshot:Dictionary) -> Dictionary:
	var clues:Dictionary={}
	var now:=float(snapshot.get("time",0))
	if float(snapshot.get("seaweed_ready",0))<=now:clues[world.SEAWEED_CELL]="海苔"
	if float(snapshot.get("wangan_shell_ready",0))<=now and not world.WANGAN_COAST.high_tide(now):
		clues[world.WANGAN_COAST.SHELL_CELL]="潮紋貝殼"
	return clues

static func visible_clues(world,snapshot:Dictionary,player:Dictionary) -> Dictionary:
	if snapshot.get("region_id","home")!="home" or not player.get(FIELD,{}).get("following",false):return {}
	if float(player.get("fox_hint_until",0))<=float(snapshot.get("time",0)):return {}
	return home_clues(world,snapshot)
