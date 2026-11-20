extends RefCounted

const NAME:="蘑菇刺蝟"
const POINT:="courtyard_hedgehog"
const ACTIONS:=["hedgehog_leave_food","hedgehog_observe"]
const Industry=preload("res://scripts/industry.gd")
const NAP_RADIUS:=6
const NO_BASKET:=Vector2i(-1,-1)
const Memory=preload("res://scripts/wangan_memory.gd")
const Weather=preload("res://scripts/weather.gd")
const COLORS:={"o":Color("55423c"),"b":Color("94735c"),"w":Color("ecceaa"),
	"d":Color("412d28"),"m":Color("bd7168"),"l":Color("f0aca0")}
const SPRITE:=[
	".........ooo.....",
	"........omlmo....",
	"...oo..ommmmmo...",
	"..obbooowwwwwo...",
	".obbboboowobbo...",
	".obobbbbbbobboo..",
	".obbbbbbbbbobwwo.",
	"..obbbbbbbowdwwo.",
	"..obbbbbbowwwwo..",
	"...obbooowwwoo...",
	"....oo.oooo......",
]
const SLEEP_SPRITE:=[
	"..................",
	"......ooooo.......",
	"....oobbbbboo.....",
	"...obbbobbbbbo....",
	"..obobbbbbobbbo...",
	".obbbbbobbbbbbbo..",
	".obbbbbbbobwwbwoo.",
	"..obbbbbbowwdbwdo.",
	"...oobbbooowwwwo..",
	".....oooooooooo...",
	"..................",
]
static var frames:Dictionary={}
static var sleep_frame:Texture2D

static func site(snapshot:Dictionary)->Vector2i:
	return Memory.COURT_SIGN+Vector2i.LEFT if Memory.courtyard_available(snapshot) else Memory.SITE+Vector2i.DOWN

static func phase(player:Dictionary,now:float)->String:
	var day:=int(Weather.day_index(now))
	var expected:=int(player.get("hedgehog_visit_day",-1))
	if expected<0 or day>expected:return "empty"
	if day<expected:return "waiting"
	var minute:=fposmod(now,Weather.DAY_SECONDS)
	if minute<360.0:return "waiting"
	if minute>=660.0:return "empty"
	return "visited" if int(player.get("hedgehog_observed_day",-1))==day else "visiting"

static func is_food_site(tile:Vector2i)->bool:
	return tile==Memory.COURT_SIGN+Vector2i.LEFT or tile==Memory.SITE+Vector2i.DOWN

static func nap_cell(snapshot:Dictionary,player:Dictionary)->Vector2i:
	if phase(player,float(snapshot.get("time",0)))!="visited":return NO_BASKET
	var dish:=site(snapshot)
	var objects:Dictionary=snapshot.get("objects",{})
	var nearest:=NO_BASKET
	var best:=NAP_RADIUS*NAP_RADIUS+1
	for y in range(-NAP_RADIUS,NAP_RADIUS+1):
		for x in range(-NAP_RADIUS,NAP_RADIUS+1):
			var distance:=x*x+y*y
			if distance==0 or distance>=best:continue
			var tile:=dish+Vector2i(x,y)
			if objects.get("%d,%d"%[tile.x,tile.y],{}).get("type")==Industry.HEDGEHOG_BASKET:
				nearest=tile
				best=distance
	return nearest

static func sleep_texture()->Texture2D:
	if sleep_frame==null:sleep_frame=make_texture(SLEEP_SPRITE)
	return sleep_frame

static func make_texture(pixels:Array,nibbling:=false)->Texture2D:
	var art:=Image.create_empty(pixels[0].length(),pixels.size(),false,Image.FORMAT_RGBA8)
	for y in pixels.size():
		for x in pixels[y].length():
			var ink:String=pixels[y][x]
			if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
	if nibbling:art.set_pixel(14,8,COLORS.d)
	return ImageTexture.create_from_image(art)

static func texture(nibbling:bool)->Texture2D:
	if not frames.has(nibbling):frames[nibbling]=make_texture(SPRITE,nibbling)
	return frames[nibbling]

static func act(world,player:Dictionary,action:String)->Dictionary:
	var now:=float(world.state.time)
	var day:=int(Weather.day_index(now))
	var status:=phase(player,now)
	if action=="hedgehog_observe":
		if status!="visiting":return world.fail("刺蝟還沒來，或你今天已經看過牠了。")
		player.hedgehog_observed_day=day
		if nap_cell(world.state,player)!=NO_BASKET:return world.ok("蘑菇刺蝟吃完蘿蔔，鑽進附近的午睡籃。")
		return world.ok("蘑菇刺蝟嗅了嗅蘿蔔，縮起腳打了個小盹。")
	if status!="empty":return world.fail("盤裡已有蘿蔔，先回來看看牠。")
	if int(player.inventory.get("radish",0))<1:return world.fail("先帶一顆普通奶白蘿蔔來。")
	if day>=int(Weather.MAX_DAY_INDEX):return world.fail("這次無法安排明日的造訪。")
	player.inventory.radish=int(player.inventory.radish)-1
	player.hedgehog_visit_day=day+1
	return world.ok("在庭院留了一顆蘿蔔。明早 06:00 至 11:00 回來看看。")
