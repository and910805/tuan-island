extends RefCounted

const NAME:="蘑菇刺蝟"
const POINT:="courtyard_hedgehog"
const ACTIONS:=["hedgehog_leave_food","hedgehog_observe"]
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
static var frames:Dictionary={}

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

static func texture(nibbling:bool)->Texture2D:
	if not frames.has(nibbling):
		var art:=Image.create_empty(17,11,false,Image.FORMAT_RGBA8)
		for y in SPRITE.size():
			for x in SPRITE[y].length():
				var ink:String=SPRITE[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if nibbling:art.set_pixel(14,8,COLORS.d)
		frames[nibbling]=ImageTexture.create_from_image(art)
	return frames[nibbling]

static func act(world,player:Dictionary,action:String)->Dictionary:
	var now:=float(world.state.time)
	var day:=int(Weather.day_index(now))
	var status:=phase(player,now)
	if action=="hedgehog_observe":
		if status!="visiting":return world.fail("刺蝟還沒來，或你今天已經看過牠了。")
		player.hedgehog_observed_day=day
		return world.ok("蘑菇刺蝟嗅了嗅蘿蔔，縮起腳打了個小盹。")
	if status!="empty":return world.fail("盤裡已有蘿蔔，先回來看看牠。")
	if int(player.inventory.get("radish",0))<1:return world.fail("先帶一顆普通奶白蘿蔔來。")
	if day>=int(Weather.MAX_DAY_INDEX):return world.fail("這次無法安排明日的造訪。")
	player.inventory.radish=int(player.inventory.radish)-1
	player.hedgehog_visit_day=day+1
	return world.ok("在庭院留了一顆蘿蔔。明早 06:00 至 11:00 回來看看。")
