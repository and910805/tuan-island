extends RefCounted

const NAME:="棉球兔"
const FIELD:="companion_rabbit"
const ACTIONS:=["rabbit_adopt","rabbit_follow","rabbit_rest","rabbit_pet"]
const MAX_BOND:=10
const PET_INTERVAL:=30.0
const COLORS:={"o":Color("694c4c"),"w":Color("fff1db"),"s":Color("dec6b2"),
	"p":Color("df9f98"),"d":Color("49343c")}
const SPRITE:=[
	"...oo...oo.....",
	"..owpo.owpo....",
	"..owpo.owpo....",
	"..owpo.owpo....",
	"...owooowoo....",
	"...owwwwwwo....",
	"..owdwwwdwo....",
	"..owwwwpwwwo...",
	"..oswwwwwwwo...",
	"...oswwssswoo..",
	"...owssssswoso.",
	"....oowoowooo..",
]

static var frames:Dictionary={}

static func texture(elapsed:float,reduced:bool,sleeping:=false) -> Texture2D:
	var frame:="awake"
	if sleeping:frame="sleep"
	elif not reduced and fposmod(elapsed,2.4)>2.05:frame="sniff"
	if not frames.has(frame):
		var art:=Image.create_empty(15,12,false,Image.FORMAT_RGBA8)
		for y in SPRITE.size():
			for x in SPRITE[y].length():
				var ink:String=SPRITE[y][x]
				if COLORS.has(ink):art.set_pixel(x,y,COLORS[ink])
		if frame=="sniff":
			art.set_pixel(7,7,COLORS.w)
			art.set_pixel(7,6,COLORS.p)
		elif frame=="sleep":
			for eye in [4,8]:
				art.set_pixel(eye,6,COLORS.w)
				art.set_pixel(eye,7,COLORS.d)
				art.set_pixel(eye+1,7,COLORS.o)
		frames[frame]=ImageTexture.create_from_image(art)
	return frames[frame]

static func act(world,player:Dictionary,action:String,at_site:bool,field:String,name:String) -> Dictionary:
	var pet:Dictionary=player.get(field,{})
	if action=="adopt":
		if not at_site:return world.fail("請在渡口野餐後，走到%s的小窩。"%name)
		if not pet.is_empty():return world.fail("%s已經是你的夥伴了。"%name)
		player[field]={"following":true,"bond":0,"last_pet":-PET_INTERVAL}
		stop_other_pets(player,field)
		return world.ok("%s跟著你踏出了第一步。"%name)
	if pet.is_empty():return world.fail("請先領養%s。"%name)
	if action in ["pet","yarn","toy"]:
		if not pet.following and not at_site:return world.fail("%s正在自己的小窩休息。"%name)
		var now:=float(world.state.time)
		if now-float(pet.last_pet)<PET_INTERVAL:return world.fail("%s正在舒服地休息。"%name)
		pet.last_pet=now
		pet.bond=mini(MAX_BOND,int(pet.bond)+1)
		if field==FIELD:return world.ok("棉球兔用鼻尖碰了碰你的手。")
		if field=="companion_fox":return world.ok("葉耳狐把耳朵壓低，親暱地蹭了蹭你。")
		pet.last_play=action
		if field=="companion_dog":return world.ok("小柴犬開心地叼起布玩具。" if action=="toy" else "小柴犬放下玩具，搖了搖尾巴。")
		return world.ok("圍巾貓追著毛線球跑了兩步。" if action=="yarn" else "圍巾貓抬起尾巴，輕輕喵了一聲。")
	var following:=action=="follow"
	if pet.following==following:return world.fail("%s已經在你身旁。"%name if following else "%s已經回小窩休息。"%name)
	pet.following=following
	if following:stop_other_pets(player,field)
	return world.ok("%s跟了上來。"%name if following else "%s回小窩休息了。"%name)

const PET_FIELDS:=[FIELD,"companion_cat","companion_dog","companion_fox"]

static func stop_other_pets(player:Dictionary,active:String) -> void:
	for field:String in PET_FIELDS:
		if field!=active and player.has(field):player[field].following=false
