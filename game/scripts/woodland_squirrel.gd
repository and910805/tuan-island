extends RefCounted

const NAME:="橡果松鼠"
const POINT:="woodland_squirrel"
const ACTIONS:=["squirrel_observe","squirrel_exchange"]
const SITE:=Vector2i(33,24)
const ACORN:="acorn"
const KIT:="acorn_ornament_kit"
const ORNAMENT:="acorn_ornament"
const COST:=3
const Weather=preload("res://scripts/weather.gd")
const COLORS:={"o":Color("55382f"),"r":Color("b96f47"),"h":Color("d99a60"),
	"w":Color("ffe1b6"),"n":Color("674331"),"l":Color("648759")}
const SQUIRREL:=[
	"...........ooo....",
	"..........ohrro...",
	"..........ohrrro..",
	"...oo...ooohrrro..",
	"..ohro.oohrrrro...",
	"..orrrooohrrro....",
	".orwnoorrrrro.....",
	".orwworrrroo......",
	"..owwrrrrro.......",
	"..owwwrrro........",
	"...oorrro.........",
	"...oooooo.........",
]
const NUT:=["...oooo...","..onnnno..",".onnhnnno.","..orrhro..","..orrhro..","...orro...","....oo...."]
const TRINKET:=["....oo....","...oloo...","..ololoo..",".ollooloo.",".....o....","...oooo...","..onnnno..",".onnhnnno.","..orrhro..","...orro...","....oo...."]
static var textures:Dictionary={}

static func texture(kind:="animal")->Texture2D:
	if not textures.has(kind):
		var rows:=SQUIRREL if kind=="animal" else (NUT if kind==ACORN else TRINKET)
		var art:=Image.create_empty(rows[0].length(),rows.size(),false,Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				var ink:String=rows[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		textures[kind]=ImageTexture.create_from_image(art)
	return textures[kind]

static func present(now:float)->bool:
	var minute:=fposmod(now,Weather.DAY_SECONDS)
	return minute>=480.0 and minute<1080.0

static func observed(player:Dictionary,now:float)->bool:
	return int(player.get("squirrel_day",-1))==int(Weather.day_index(now))

static func act(world,player:Dictionary,action:String)->Dictionary:
	var now:=float(world.state.time)
	if not present(now):return world.fail("松鼠在 08:00–18:00 到林邊活動。")
	var inventory:Dictionary=player.inventory
	if action=="squirrel_observe":
		if observed(player,now):return world.fail("今天已經撿過橡果了。")
		if int(inventory.get(ACORN,0))>=1000000000:return world.fail("背包的橡果已達上限。")
		player.squirrel_day=int(Weather.day_index(now))
		world.give(inventory,ACORN,1)
		return world.ok("松鼠跳上樹枝，留下一顆橡果。")
	if int(inventory.get(ACORN,0))<COST:return world.fail("收集 %d 顆橡果就能交換。"%COST)
	if int(inventory.get(KIT,0))>=1000000000:return world.fail("背包的橡果掛飾已達上限。")
	world.give(inventory,ACORN,-COST)
	world.give(inventory,KIT,1)
	return world.ok("松鼠換給你一件橡果掛飾，可用建造選單擺放。")
