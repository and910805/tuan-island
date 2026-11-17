extends RefCounted

static func blue_outfit_unlocked(person:Dictionary) -> bool:
	return person.get("blue_outfit_unlocked",false)==true or person.get("blue_outfit",false)==true
## 第三章切片「花開之前，先留下種子」：田尾合作花圃規則核心（W1）。
## Pure static rules, data and validation. No IO, no wall clock, no random.
## Must NOT preload world.gd / regions.gd / transit.gd (they preload this file).
## This is an incremental chapter-3 slice; it does not close T048/T049/T062/T070.

const TeaCeramics=preload("res://scripts/tea_ceramics.gd")
const WEATHER=preload("res://scripts/weather.gd")

const SAVE_VERSION:=25
const REGION:="tianwei"
const HOME:="home"
const FLOWERS:=["bluebell","orange_blossom","chime_herb"]
const SEEDS:={"bluebell":"bluebell_seed","orange_blossom":"orange_blossom_seed","chime_herb":"chime_herb_seed"}
## World.CROPS additions. `time` is a PROVISIONAL current-clock compatibility
## value (potato 4 days=150 s, wheat 3 days=120 s), not a plan value.
const CROPS:={
	"bluebell":{"name":"鈴蘭藍花","time":150.0,"price":28,"seed_price":28,"yield":2},
	"orange_blossom":{"name":"蜜橙花","time":150.0,"price":28,"seed_price":28,"yield":2},
	"chime_herb":{"name":"風鈴香草","time":120.0,"price":48,"seed_price":24,"yield":1},
}
## Source plan values (§09), for display. Dormancy on home plots follows
## World.CROP_SEASONS; the nursery beds here grow all three year-round.
const PLAN:={
	"bluebell":{"plan_seasons":["春"],"plan_days":4,"use":"藍色染料、花束"},
	"orange_blossom":{"plan_seasons":["夏","秋"],"plan_days":4,"use":"橙色染料、蜂蜜"},
	"chime_herb":{"plan_seasons":["全季","溫室"],"plan_days":3,"use":"調味、香氛"},
}
const NAMES:={"bluebell":"鈴蘭藍花","orange_blossom":"蜜橙花","chime_herb":"風鈴香草","bluebell_seed":"鈴蘭藍花種子","orange_blossom_seed":"蜜橙花種子","chime_herb_seed":"風鈴香草種子","blue_dye":"藍色染料","sugar":"糖","garden_cookie":"花園餅乾"}
const FORWARD_IDS:=["bluebell","orange_blossom","chime_herb","bluebell_seed","orange_blossom_seed","chime_herb_seed","blue_dye","sugar","garden_cookie","tianwei"]
## 設計選擇，非原規劃精確配方：plan §14 only gives the direction 麵粉、糖、花材香料.
## Quantities, 60 s and the sell price 36 are user-approved design values.
const COOKIE:={"garden_cookie":{"name":"花園餅乾","ingredients":{"flour":1,"sugar":1,"chime_herb":1},"time":60.0,"yield":4}}
const COOKIE_PRICE:=36 # 設計選擇
## Source plan R31, exact.
const DYE:={"ingredients":{"bluebell":3},"item":"blue_dye","yield":2,"time":30.0}
## 一株的成花換一包，同一株的收成最多補回一包。
const SAVE_SECONDS:=60.0
const STARTER:={"bluebell_seed":2,"orange_blossom_seed":2,"chime_herb_seed":2}
## Tianwei market prices. Seed prices are plan §09; sugar 40 and the daily cap
## are design choices (§35: small shop supply before winter unlock).
const MARKET_PRICES:={"bluebell_seed":28,"orange_blossom_seed":28,"chime_herb_seed":24,"sugar":40}
const SUGAR_DAILY:=2
## 設計選擇：order pays market value 160 plus ~10% co-op premium.
const ORDER:={"bluebell":2,"orange_blossom":2,"chime_herb":1}
const ORDER_PAY:=176
const RESERVE:={"bluebell_seed":1,"orange_blossom_seed":1,"chime_herb_seed":1}
## 設計選擇：sized so one player finishes in two to three batches.
const GARDEN_NEEDS:={"blue_dye":4,"orange_blossom":4,"chime_herb":2}
const MEMENTO:=RESERVE
const PLOT_CAP:=6
const LIMIT:=1000000000

## Tianwei geography (80x60 region).
const LAND:=Rect2i(8,12,34,18)
const NURSERY_BEDS:=Rect2i(18,22,8,3)
const TRANSFER:=Vector2i(12,25)
const ARRIVAL:=Vector2(13.5,25.5)
const SHED:=Rect2i(18,14,8,3)
const FARMER:=Vector2i(20,18)
const SEED_TABLE:=Vector2i(24,18)
const DYE_TABLE:=Vector2i(28,18)
const XINGHE:=Vector2i(34,18)
const MARKET:=Vector2i(31,25)
const GARDEN:=Rect2i(36,23,3,2)
const GARDEN_CELL:=Vector2i(36,24)
const RECEIVER_HOME:=Vector2i(43,29)
const STATION_CELLS:=[FARMER,SEED_TABLE,DYE_TABLE,XINGHE,MARKET]

const FRESH:={"letter":false,"intro":false,"planted":{},"harvested":{},"saving":{},"saved":{},"dyeing":{},"shipped":false,"complete":false,"sugar_day":-1,"sugar_bought":0}
const PHASES:=["locked","letter","travel","intro","plant","harvest","save","ship","garden","report","complete"]
const ACTIONS:=["flower_letter","flower_intro","flower_save","flower_save_take","flower_dye","flower_dye_take","flower_outfit","flower_buy","flower_ship","flower_give","flower_report"]
## action -> [region, cell]. flower_give accepts any cell of the GARDEN rect.
const SITES:={
	"flower_letter":[HOME,RECEIVER_HOME],
	"flower_intro":[REGION,FARMER],
	"flower_save":[REGION,SEED_TABLE],"flower_save_take":[REGION,SEED_TABLE],
	"flower_dye":[REGION,DYE_TABLE],"flower_dye_take":[REGION,DYE_TABLE],
	"flower_outfit":[REGION,DYE_TABLE],
	"flower_buy":[REGION,MARKET],"flower_ship":[REGION,MARKET],
	"flower_give":[REGION,GARDEN_CELL],
	"flower_report":[REGION,XINGHE],
}
const OPTIONS:={"flower_outfit":["blue","original"],"flower_save":["bluebell","orange_blossom","chime_herb"],"flower_buy":["bluebell_seed","orange_blossom_seed","chime_herb_seed","sugar"]}
const REJECT_MESSAGE:="田尾花圃只開放育苗床照顧和花圃工作台。"
const HOME_SEED_MESSAGE:="完成田尾花圃的第三章後，小栗才會進花卉種子。"
const FOREIGN_PLOT_MESSAGE:="這是其他島民的育苗床"
const RESERVE_MESSAGE:="交貨後要留下鈴蘭藍花、蜜橙花、風鈴香草種子各 1 包，才夠下一輪播種。"
const UNSAVED_MESSAGE:="先在留種台替三種花各留一包種子。"
const GARDEN_EVENT:="大家合力讓田尾公共花園開花了"
## Journal replay, one original line per phase (client-side only).
const STORY:={
	"locked":"茶茶和陶師的包裝比較完成後，小栗的攤位會收到一封從田尾寄來的信。",
	"letter":"小栗遞來一封信：「田尾的合作花圃在找人一起育苗。信上寫著：花開之前，先留下種子。」",
	"travel":"從鶯歌經縱貫線鐵路南下，再轉地方接駁，就能抵達虛構的田尾合作花圃。",
	"intro":"阿蕾把六小包種子放進你手裡：「鈴蘭藍花、蜜橙花、風鈴香草各兩包。種下去之前，先想好要留哪一朵回來。」",
	"plant":"育苗床的土已經鬆好。三種花各種下一格，澆過水，就等嫩芽冒出來。",
	"harvest":"花苞一朵朵打開了。只採自己照顧的那幾格，其他島民的育苗床由各自照顧。",
	"save":"阿蕾在留種台示範：「把一株收成的花都留給我，就能換一包種子。藍花和蜜橙花各要兩朵，風鈴香草只要一株。」",
	"ship":"市集的合作訂單要兩朵藍花、兩朵橙花和一株香草；交貨之後，手上每種花都還要留著一包種子。",
	"garden":"公共花園還是一片空土。藍色染料、蜜橙花和風鈴香草，大家可以分次帶來。",
	"report":"花架上開滿了花。星禾在花架旁等著，想聽這一輪種子是怎麼留下來的。",
	"complete":"星禾把三包種子交到你手上：「回家以後，小栗的攤位也會開始進這三種花的種子。」",
}

# ---------------------------------------------------------------- records

static func save_flower_cost(kind:String)->int:
	return int(CROPS[kind].yield)

static func garden_fresh() -> Dictionary:
	return {"given":{"blue_dye":0,"orange_blossom":0,"chime_herb":0},"contributors":{},"complete":false,"completed_at":-1.0}

static func fresh() -> Dictionary:
	return {"players":{},"garden":garden_fresh()}

static func _data(state:Dictionary) -> Dictionary:
	var data=state.get("flower_nursery")
	if data is Dictionary and data.get("players") is Dictionary and data.get("garden") is Dictionary:return data
	return fresh()

static func own_record(state:Dictionary,token:String) -> Dictionary:
	return _data(state).players.get(token,FRESH).duplicate(true)

static func _garden(state:Dictionary) -> Dictionary:
	return _data(state).garden

static func unlocked(state:Dictionary,token:String) -> bool:
	var tea=state.get("tea_ceramics")
	if not tea is Dictionary or not tea.get("players") is Dictionary:return false
	return yes(TeaCeramics.own_record(state,token).get("comparison_complete",false))

static func route_open(state:Dictionary,token:String) -> bool:
	return yes(own_record(state,token).letter)

static func _visited(player:Variant) -> bool:
	if not player is Dictionary:return false
	var book=player.get("travel_book")
	return book is Dictionary and book.get("visited") is Dictionary and yes(book.visited.get(REGION))

static func phase(state:Dictionary,token:String) -> String:
	if not unlocked(state,token):return "locked"
	var record:=own_record(state,token)
	if not record.letter:return "letter"
	if not _visited(state.get("players",{}).get(token)):return "travel"
	if not record.intro:return "intro"
	if not _all(record.planted):return "plant"
	if not _all(record.harvested):return "harvest"
	if not _all(record.saved):return "save"
	if not record.shipped:return "ship"
	if not _garden(state).get("complete",false):return "garden"
	if not record.complete:return "report"
	return "complete"

static func _all(table:Dictionary) -> bool:
	for kind in FLOWERS:
		if not table.has(kind):return false
	return true

static func guidance(state:Dictionary,token:String) -> Dictionary:
	var current:=phase(state,token)
	var g:Dictionary
	match current:
		"locked":g={"title":"尚未開放","detail":"先完成第二章茶陶的包裝比較。","region":"","site":"","cell":Vector2i(-1,-1)}
		"letter":g={"title":"收下介紹信","detail":"回到家鄉渡口，向小栗收下田尾合作花圃的介紹信。","region":HOME,"site":"letter","cell":RECEIVER_HOME}
		"travel":g={"title":"前往田尾","detail":"從鶯歌經縱貫線南下，再轉地方接駁到田尾合作花圃。","region":REGION,"site":"travel","cell":TRANSFER}
		"intro":g={"title":"認識花農","detail":"和花圃的阿蕾打招呼，領取三種花的起始種子。","region":REGION,"site":"farmer","cell":FARMER}
		"plant":g={"title":"播種","detail":"在育苗床鋤地，三種花各種下一格並澆水。","region":REGION,"site":"beds","cell":NURSERY_BEDS.position}
		"harvest":g={"title":"採收","detail":"等花開後，採收自己育苗床上的三種花。","region":REGION,"site":"beds","cell":NURSERY_BEDS.position}
		"save":g={"title":"留種","detail":"在留種台替三種花各留一包種子。藍花與蜜橙花各要兩朵，風鈴香草要一株。每包等 60 秒。","region":REGION,"site":"seed","cell":SEED_TABLE}
		"ship":g={"title":"合作訂單","detail":"到市集交出藍花 2、橙花 2、香草 1；交貨後每種仍須留著 1 包種子。","region":REGION,"site":"market","cell":MARKET}
		"garden":g={"title":"公共花園","detail":"把藍色染料、蜜橙花和風鈴香草捐給公共花園，可分次、可與其他島民合力。","region":REGION,"site":"garden","cell":GARDEN_CELL}
		"report":g={"title":"回報星禾","detail":"公共花園已開花，到花架旁向星禾回報。","region":REGION,"site":"xinghe","cell":XINGHE}
		_:g={"title":"第三章田尾段落完成","detail":"小栗的攤位已開始販售三種花卉種子，可從手帳重看劇情。","region":HOME,"site":"journal","cell":RECEIVER_HOME}
	g.phase=current
	return g

# ---------------------------------------------------------------- geography

static func land(p:Vector2i) -> bool:
	return LAND.has_point(p)

static func protected(p:Vector2i) -> bool:
	return not NURSERY_BEDS.has_point(p)

static func blocked(p:Vector2i) -> bool:
	return SHED.has_point(p) or p in STATION_CELLS or GARDEN.has_point(p)

# ---------------------------------------------------------------- actions

static func apply(state:Dictionary,token:String,action:String,region:String,p:Vector2i,extra:String) -> Dictionary:
	if action not in SITES:return fail("無法執行花圃作業。")
	var site:Array=SITES[action]
	var at_site:bool=GARDEN.has_point(p) if action=="flower_give" else p==site[1]
	if region!=site[0] or not at_site:return fail("請到田尾花圃對應的工作點。")
	if extra not in OPTIONS.get(action,[""]):return fail("請重新選擇花圃作業。")
	if not unlocked(state,token):return fail("先完成第二章茶陶的包裝比較。")
	var data=state.get("flower_nursery")
	if not data is Dictionary or not data.get("players") is Dictionary or not data.get("garden") is Dictionary:return fail("花圃資料尚未就緒。")
	var player=state.get("players",{}).get(token)
	if not player is Dictionary or not player.get("inventory") is Dictionary:return fail("找不到島民資料。")
	var record:=own_record(state,token)
	var garden:Dictionary=data.garden.duplicate(true)
	var result:=perform(record,garden,player,action,extra,float(state.time),token)
	if result.ok:
		data.players[token]=record
		data.garden=garden
		if result.has("event") and state.get("events") is Array:state.events.append(result.event)
	return {"ok":result.ok,"message":result.message}

## The only mutation path. Every check runs before anything changes, so a
## failure leaves record, garden and player untouched. On garden completion the
## result also carries "event" (a state.events line appended by apply).
static func perform(record:Dictionary,garden:Dictionary,player:Dictionary,action:String,extra:String,now:float,token:String) -> Dictionary:
	var inventory:Dictionary=player.inventory
	match action:
		"flower_letter":
			if record.letter:return fail("介紹信已收下，可從手帳重看。")
			record.letter=true
			return ok("小栗遞來田尾合作花圃的介紹信；轉乘時可以選擇前往田尾了。")
		"flower_intro":
			if not record.letter:return fail("先在家鄉渡口向小栗收下田尾的介紹信。")
			if record.intro:return fail("阿蕾已經給過起始種子，可從手帳重看。")
			if not _visited(player):return fail("先經轉乘抵達田尾合作花圃。")
			if not can_grant(inventory,STARTER):return fail("種子已達背包上限，起始種子先由阿蕾保管。")
			grant_all(inventory,STARTER)
			record.intro=true
			return ok("阿蕾給了鈴蘭藍花、蜜橙花、風鈴香草種子各 2 包。")
		"flower_save":
			if not record.intro:return fail("先和花圃的阿蕾打聲招呼。")
			if not record.saving.is_empty():return fail("留種台上已有你的工作，先領取。")
			if not record.harvested.has(extra):return fail("先在田尾育苗床採收過%s，才能在這裡留種。"%NAMES[extra])
			var cost:=save_flower_cost(extra)
			if int(inventory.get(extra,0))<cost:return fail("留種需要 %d 份%s。"%[cost,NAMES[extra]])
			inventory[extra]=int(inventory[extra])-cost
			record.saving={"kind":extra,"ready":now+SAVE_SECONDS}
			return ok("%s已放上留種台，約 60 秒後可領取種子。"%NAMES[extra])
		"flower_save_take":
			if not due(record.saving,now):return fail("留種台上沒有完成的工作。")
			var kind:String=record.saving.kind
			var seed_id:String=SEEDS[kind]
			if not can_grant(inventory,{seed_id:1}):return fail("種子已達背包上限，工作仍保留在留種台。")
			grant_all(inventory,{seed_id:1})
			record.saved[kind]=true
			record.saving={}
			return ok("留下一包%s。"%NAMES[seed_id])
		"flower_dye":
			if not record.intro:return fail("先和花圃的阿蕾打聲招呼。")
			if not record.dyeing.is_empty():return fail("染色桌上已有你的工作，先領取。")
			if int(inventory.get("bluebell",0))<int(DYE.ingredients.bluebell):return fail("需要 3 朵鈴蘭藍花。")
			inventory.bluebell=int(inventory.bluebell)-int(DYE.ingredients.bluebell)
			record.dyeing={"ready":now+float(DYE.time)}
			return ok("藍花已下染缸，約 30 秒後可領取染料。")
		"flower_dye_take":
			if not due(record.dyeing,now):return fail("染色桌上沒有完成的工作。")
			if not can_grant(inventory,{DYE.item:DYE.yield}):return fail("藍色染料已達背包上限，工作仍保留在染色桌。")
			grant_all(inventory,{DYE.item:DYE.yield})
			record.dyeing={}
			return ok("領取藍色染料 ×2。")
		"flower_outfit":
			if not record.intro:return fail("先和花圃的阿蕾打聲招呼。")
			if extra=="original":
				if not player.get("blue_outfit",false):return fail("現在已穿著原色工作服。")
				player.blue_outfit_unlocked=true
				player.erase("blue_outfit")
				return ok("換回原色工作服。")
			if player.get("blue_outfit",false):return fail("現在已穿著藍染工作服。")
			if int(inventory.get("blue_dye",0))<1:return fail("需要一份藍色染料。")
			inventory.blue_dye-=1
			player.blue_outfit=true
			player.blue_outfit_unlocked=true
			return ok("換上了藍染工作服，藍色染料 −1。")
		"flower_buy":
			if not record.intro:return fail("先和花圃的阿蕾打聲招呼。")
			var price:int=MARKET_PRICES[extra]
			if int(player.get("coins",0))<price:return fail("鈴幣不足。")
			var day:=int(WEATHER.day_index(now))
			var bought:=int(record.sugar_bought) if int(record.sugar_day)==day else 0
			if extra=="sugar" and bought>=SUGAR_DAILY:return fail("今日糖已達 2 份（新的遊戲日才重置）。")
			if not can_grant(inventory,{extra:1}):return fail("%s已達背包上限。"%NAMES[extra])
			player.coins=int(player.coins)-price
			grant_all(inventory,{extra:1})
			if extra=="sugar":
				record.sugar_day=day
				record.sugar_bought=bought+1
			return ok("買了 1 份%s，花費 %d 鈴幣。"%[NAMES[extra],price])
		"flower_ship":
			if record.shipped:return fail("合作訂單已出貨。")
			if not _all(record.saved):return fail(UNSAVED_MESSAGE)
			var short:PackedStringArray=[]
			for kind:String in ORDER:
				var held:=int(inventory.get(kind,0))
				if held<int(ORDER[kind]):short.append("%s還差 %d"%[NAMES[kind],int(ORDER[kind])-held])
			if not short.is_empty():return fail("成花不足：%s。"%"、".join(short))
			for seed_id:String in RESERVE:
				if int(inventory.get(seed_id,0))<int(RESERVE[seed_id]):return fail(RESERVE_MESSAGE)
			if int(player.get("coins",0))>LIMIT-ORDER_PAY:return fail("鈴幣已達上限，訂單暫不結算。")
			for kind:String in ORDER:inventory[kind]=int(inventory[kind])-int(ORDER[kind])
			player.coins=int(player.coins)+ORDER_PAY
			record.shipped=true
			return ok("合作訂單已出貨，鈴幣 +%d。"%ORDER_PAY)
		"flower_give":
			if not record.intro:return fail("先和花圃的阿蕾打聲招呼。")
			if garden.complete:return fail("公共花園已完成。")
			var take:Dictionary={}
			var total:=0
			for item:String in GARDEN_NEEDS:
				var amount:=mini(int(GARDEN_NEEDS[item])-int(garden.given[item]),int(inventory.get(item,0)))
				if amount>0:
					take[item]=amount
					total+=amount
			if total<=0:return fail("沒有可捐的染料、橙花或香草（種子不會被拿走）。")
			for item:String in take:
				inventory[item]=int(inventory[item])-int(take[item])
				garden.given[item]=int(garden.given[item])+int(take[item])
			garden.contributors[token]=int(garden.contributors.get(token,0))+total
			var parts:PackedStringArray=[]
			for item:String in take:parts.append("%s ×%d"%[NAMES[item],int(take[item])])
			var result:=ok("捐給公共花園：%s。"%"、".join(parts))
			if garden_met(garden.given):
				garden.complete=true
				garden.completed_at=now
				result.message+="公共花園開花了！"
				result.event=GARDEN_EVENT
			return result
		"flower_report":
			if record.complete:return fail("第三章田尾段落已完成，可從手帳重看。")
			if not record.shipped:return fail("先完成市集的合作訂單。")
			if not garden.complete:return fail("公共花園尚未完成。")
			if not can_grant(inventory,MEMENTO):return fail("種子已達背包上限，紀念種子先由星禾保管。")
			grant_all(inventory,MEMENTO)
			record.complete=true
			return ok("星禾送上三種花的紀念種子各 1 包；小栗的攤位也開始販售花卉種子。")
	return fail("無法執行花圃作業。")

static func garden_met(given:Dictionary) -> bool:
	for item in GARDEN_NEEDS:
		if int(given.get(item,0))<int(GARDEN_NEEDS[item]):return false
	return true

# ---------------------------------------------------------------- world hooks

static func note_plant(state:Dictionary,token:String,kind:String) -> void:
	if kind not in FLOWERS:return
	var data=state.get("flower_nursery")
	if not data is Dictionary or not data.get("players") is Dictionary:return
	var record=data.players.get(token)
	if not record is Dictionary or not record.get("intro",false):return
	record.planted[kind]=true

static func note_harvest(state:Dictionary,token:String,kind:String,count:int) -> void:
	if kind not in FLOWERS or count<=0:return
	var data=state.get("flower_nursery")
	if not data is Dictionary or not data.get("players") is Dictionary:return
	var record=data.players.get(token)
	if not record is Dictionary or not record.get("intro",false) or not record.planted.has(kind):return
	record.harvested[kind]=mini(LIMIT,int(record.harvested.get(kind,0))+mini(count,LIMIT))

static func plot_allowed(crops_layer:Dictionary,token:String) -> bool:
	return _owned(crops_layer,token)<PLOT_CAP

static func _owned(crops_layer:Dictionary,token:String) -> int:
	var count:=0
	for crop in crops_layer.values():
		if crop is Dictionary and crop.get("owner")==token:count+=1
	return count

## Accepts either the crop id or its seed id.
static func home_seed_allowed(state:Dictionary,token:String,kind:String) -> bool:
	if kind not in FLOWERS and kind not in SEEDS.values():return true
	return yes(own_record(state,token).complete)

# ---------------------------------------------------------------- schema

static func valid(state:Dictionary) -> bool:
	var data=state.get("flower_nursery")
	if not data is Dictionary or data.size()!=2 or not data.get("players") is Dictionary or not data.get("garden") is Dictionary:return false
	var players=state.get("players")
	if not players is Dictionary or not _number(state.get("time")):return false
	var now:=float(state.time)
	var today:=int(WEATHER.day_index(now))
	var tea=state.get("tea_ceramics")
	if not tea is Dictionary or not tea.get("players") is Dictionary:return false
	for token in data.players:
		var record=data.players[token]
		if not token is String or not players.has(token) or not record is Dictionary or record.size()!=FRESH.size():return false
		for field in FRESH:
			if not record.has(field):return false
		for field in ["letter","intro","shipped","complete"]:
			if not record[field] is bool:return false
		for field in ["planted","harvested","saving","saved","dyeing"]:
			if not record[field] is Dictionary:return false
		if not record.letter:return false
		var tea_record=tea.players.get(token)
		if not tea_record is Dictionary or not yes(tea_record.get("comparison_complete")):return false
		if record.intro and not _visited(players[token]):return false
		for table in [record.planted,record.saved]:
			for kind in table:
				if kind not in FLOWERS or not yes(table[kind]):return false
		for kind in record.harvested:
			if kind not in FLOWERS or not whole(record.harvested[kind],1) or not record.planted.has(kind):return false
		for kind in record.saved:
			if not record.harvested.has(kind):return false
		if not record.saving.is_empty():
			if record.saving.size()!=2 or record.saving.get("kind") not in FLOWERS or not time_valid(record.saving.get("ready"),now,SAVE_SECONDS):return false
		if not record.dyeing.is_empty():
			if record.dyeing.size()!=1 or not time_valid(record.dyeing.get("ready"),now,float(DYE.time)):return false
		var busy:bool=not (record.planted.is_empty() and record.harvested.is_empty() and record.saved.is_empty() and record.saving.is_empty() and record.dyeing.is_empty())
		if busy and not record.intro:return false
		if record.shipped and not _all(record.saved):return false
		if not _number(record.sugar_day) or floorf(float(record.sugar_day))!=float(record.sugar_day) or float(record.sugar_day)<-1 or float(record.sugar_day)>today:return false
		if not whole(record.sugar_bought,0) or int(record.sugar_bought)>SUGAR_DAILY:return false
		if int(record.sugar_bought)>0 and (not record.intro or int(record.sugar_day)<0):return false
	var garden:Dictionary=data.garden
	if garden.size()!=4 or not garden.get("given") is Dictionary or not garden.get("contributors") is Dictionary or not garden.get("complete") is bool:return false
	if garden.given.size()!=GARDEN_NEEDS.size():return false
	var given_total:=0
	for item in GARDEN_NEEDS:
		if not garden.given.has(item) or not whole(garden.given[item],0) or int(garden.given[item])>int(GARDEN_NEEDS[item]):return false
		given_total+=int(garden.given[item])
	if garden.complete!=garden_met(garden.given):return false
	var contributed:=0
	for token in garden.contributors:
		if not token is String or not players.has(token) or not whole(garden.contributors[token],1):return false
		var record=data.players.get(token)
		if not record is Dictionary or not yes(record.get("intro")):return false
		contributed+=int(garden.contributors[token])
	if contributed!=given_total:return false
	if not _number(garden.get("completed_at")):return false
	if garden.complete:
		if float(garden.completed_at)<0 or float(garden.completed_at)>now:return false
	elif float(garden.completed_at)!=-1.0:return false
	for token in data.players:
		if data.players[token].complete and not (data.players[token].shipped and garden.complete):return false
	for token in players:
		var player=players[token]
		if player is Dictionary and player.get("region")==REGION:
			var record=data.players.get(token)
			if not record is Dictionary or not yes(record.get("letter")):return false
	var regions=state.get("regions")
	if regions is Dictionary and regions.get(REGION) is Dictionary and regions[REGION].get("crops") is Dictionary:
		var owned:Dictionary={}
		for crop in regions[REGION].crops.values():
			if not crop is Dictionary or not crop.get("owner") is String or crop.get("kind") not in ["","bluebell","orange_blossom","chime_herb"]:return false
			owned[crop.owner]=int(owned.get(crop.owner,0))+1
			if owned[crop.owner]>PLOT_CAP:return false
	# Normalize JSON floats once everything is known to be valid.
	for record in data.players.values():
		for kind in record.harvested:record.harvested[kind]=int(record.harvested[kind])
		record.sugar_day=int(record.sugar_day)
		record.sugar_bought=int(record.sugar_bought)
		if not record.saving.is_empty():record.saving.ready=float(record.saving.ready)
		if not record.dyeing.is_empty():record.dyeing.ready=float(record.dyeing.ready)
	for item in GARDEN_NEEDS:garden.given[item]=int(garden.given[item])
	for token in garden.contributors:garden.contributors[token]=int(garden.contributors[token])
	garden.completed_at=float(garden.completed_at)
	return true

## For saves written before version 25: true only when none of the forward ids
## appear anywhere a pre-25 save could carry them (whole-file rejection rule).
static func legacy_clean(s:Dictionary) -> bool:
	if s.has("flower_nursery"):return false
	var regions=s.get("regions",{})
	if regions is Dictionary and regions.has(REGION):return false
	var players=s.get("players",{})
	if players is Dictionary:
		for player in players.values():
			if not player is Dictionary:continue
			if player.get("region")==REGION:return false
			if _has_forward_key(player.get("inventory")):return false
			var book=player.get("travel_book")
			if book is Dictionary and book.get("visited") is Dictionary and book.visited.has(REGION):return false
			var collection=player.get("collection")
			if collection is Dictionary:
				for category in collection.values():
					if _has_forward_key(category):return false
			var last=player.get("last_seed")
			if last is Dictionary and str(last.get("kind","")) in FORWARD_IDS:return false
	var layers:Array=[s]
	if regions is Dictionary:
		for region in regions.values():
			if region is Dictionary:layers.append(region)
	for layer in layers:
		var crops=layer.get("crops",{})
		if crops is Dictionary:
			for crop in crops.values():
				if crop is Dictionary and str(crop.get("kind","")) in FORWARD_IDS:return false
		var objects=layer.get("objects",{})
		if objects is Dictionary:
			for obj in objects.values():
				if obj is Dictionary and not _object_clean(obj):return false
	return true

static func _object_clean(obj:Dictionary) -> bool:
	if _has_forward_key(obj.get("items")):return false
	if not _job_clean(obj.get("job")):return false
	for field in ["cooking","processing"]:
		var queue=obj.get(field)
		if not queue is Dictionary:continue
		var records:Array=[]
		var active=queue.get("active")
		if active is Dictionary and not active.is_empty():records.append(active)
		for bucket in ["waiting","ready"]:
			if queue.get(bucket) is Array:records.append_array(queue[bucket])
		for record in records:
			if not _job_clean(record):return false
	return true

static func _job_clean(job:Variant) -> bool:
	if not job is Dictionary:return true
	return str(job.get("kind","")) not in FORWARD_IDS and not _has_forward_key(job.get("ingredients"))

static func _has_forward_key(table:Variant) -> bool:
	if not table is Dictionary:return false
	for id in FORWARD_IDS:
		if table.has(id):return true
	return false

# ---------------------------------------------------------------- snapshots

static func public(state:Dictionary) -> Dictionary:
	var garden:=_garden(state)
	return {"garden":{"given":garden.get("given",garden_fresh().given).duplicate(true),"complete":garden.get("complete",false),"completed_at":garden.get("completed_at",-1.0),"contributor_count":garden.get("contributors",{}).size()}}

static func own_view(state:Dictionary,token:String) -> Dictionary:
	return {"own_record":own_record(state,token),"own_given":int(_garden(state).get("contributors",{}).get(token,0))}

# ---------------------------------------------------------------- helpers

static func due(job:Dictionary,now:float) -> bool:
	return not job.is_empty() and now>=float(job.ready)

static func can_grant(inventory:Dictionary,items:Dictionary) -> bool:
	for item in items:
		if int(inventory.get(item,0))>LIMIT-int(items[item]):return false
	return true

static func grant_all(inventory:Dictionary,items:Dictionary) -> void:
	for item in items:inventory[item]=int(inventory.get(item,0))+int(items[item])

static func _number(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(value)

static func time_valid(value:Variant,now:float,window:float) -> bool:
	return _number(value) and value>=0 and value<=now+window

static func whole(value:Variant,minimum:int) -> bool:
	return _number(value) and value>=minimum and value<=LIMIT and floorf(value)==value

static func ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

static func fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

## Strict boolean truth (never compares a JSON number with a bool).
static func yes(value:Variant) -> bool:
	return value is bool and value
