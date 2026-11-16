extends RefCounted

const Catalog:=preload("res://scripts/mine_expansion_catalog.gd")
const ACTIONS:=["survey_observe","survey_claim"]
## B6–B15 survey points reuse the side cave named by the catalog layout_template.
const POINTS:={1:Vector2i(16,12),2:Vector2i(44,21),3:Vector2i(24,32),4:Vector2i(34,12),5:Vector2i(46,24),
	6:Vector2i(16,12),7:Vector2i(44,21),8:Vector2i(34,12),9:Vector2i(24,32),10:Vector2i(46,24),
	11:Vector2i(24,32),12:Vector2i(16,12),13:Vector2i(44,21),14:Vector2i(34,12),15:Vector2i(46,24)}
## The original reward still needs exactly the five shallow pages.
const REWARD_PAGES:=["1","2","3","4","5"]
const FRESH:={"seen":{},"claimed":false}
const REWARD_LIMIT:=1000000000
const ENTRIES:=[
	{"title":"疊起的岩層","text":"側壁有一深一淺的石紋，細線沿著岩面延伸，遇上裂縫才分開。","hint":"沿第一層北側支洞走到底。","icon":"stone"},
	{"title":"銅色斑點","text":"這塊碎面上有幾點銅色，轉個角度才看得清楚。把顏色和所在位置一起記下。","hint":"穿過第二層東側窄口。","icon":"copper_ore"},
	{"title":"水留下的痕跡","text":"南側洞壁底部顏色較深。把這道痕跡畫進筆記，再對照主洞水池的位置。","hint":"走第三層南側支洞，繞開主洞水池。","icon":"pump_kit"},
	{"title":"搬運與落腳","text":"從這裡回望主洞，木板工作帶和軌道方向一目了然。記下搬料時可以在哪裡讓路。","hint":"從第四層往北進入側洞。","icon":"plank"},
	{"title":"礦樣的亮面","text":"灰暗石面夾著一小道暖色亮痕。記下礦樣外觀，回整理桌與其他四頁筆記一起核對。","hint":"深入第五層東側支洞。","icon":"gold_ore"},
]

## Page for any depth 1..15 (deep pages come from the T067 catalog).
static func entry(depth:int) -> Dictionary:
	if depth>=1 and depth<=ENTRIES.size():return ENTRIES[depth-1]
	return Catalog.entry(depth).get("survey",{})

static func reward_ready(record:Dictionary) -> bool:
	var seen:Dictionary=record.get("seen",{})
	for page in REWARD_PAGES:
		if not seen.has(page):return false
	return true

static func fresh() -> Dictionary:
	return {"players":{}}

static func own_record(state:Dictionary,actor:String) -> Dictionary:
	return state.mine_survey.players.get(actor,FRESH).duplicate(true)

static func valid(state:Dictionary) -> bool:
	var survey=state.get("mine_survey")
	if not survey is Dictionary or survey.size()!=1 or not survey.get("players") is Dictionary:return false
	for actor in survey.players:
		var record=survey.players[actor]
		if not state.players.has(actor) or not record is Dictionary or record.size()!=2:return false
		if not record.get("claimed") is bool or not record.get("seen") is Dictionary:return false
		for key in record.seen:
			if not key is String or not key.is_valid_int() or str(int(key))!=key or not POINTS.has(int(key)):return false
			if not record.seen[key] is bool or not record.seen[key]:return false
		if record.claimed and not reward_ready(record):return false
	return true

static func observe(state:Dictionary,actor:String,depth:int) -> Dictionary:
	var record:=own_record(state,actor)
	var key:=str(depth)
	var page:=entry(depth)
	if record.seen.has(key):
		return {"ok":true,"unchanged":true,"message":page.text}
	record.seen[key]=true
	state.mine_survey.players[actor]=record
	return {"ok":true,"message":"已記下「%s」。"%page.title}

static func claim(state:Dictionary,actor:String) -> Dictionary:
	var record:=own_record(state,actor)
	if record.claimed:return {"ok":false,"message":"這份踏查獎勵已領取。"}
	if not reward_ready(record):return {"ok":false,"message":"先完成五層側洞的觀察。"}
	var inventory:Dictionary=state.players[actor].inventory
	var held:=int(inventory.get("gold_sample",0))
	if held>=REWARD_LIMIT:return {"ok":false,"message":"金工收藏樣本已達背包上限，獎勵仍可領取。"}
	inventory.gold_sample=held+1
	record.claimed=true
	state.mine_survey.players[actor]=record
	return {"ok":true,"message":"已領取踏查獎勵：金工收藏樣本 ×1。"}
