extends RefCounted
## T071「紀念票兌換裝飾」：在風鈴渡口廣場北邊的紀念品交換攤，用三種合作活動
## （豐收接力、河岸釣魚會、家園布置題）得到的紀念票換家園裝飾。
##
## 規劃書第 19 章：活動不出售不可替代的成長資源，願意參與的人得到裝飾與紀念。
## 本模組只做兌換：紀念票仍由各活動結算時寫入 player.harvest_relay.tickets／
## player.fish_meet.tickets／player.showcase.tickets（「累計獲得」，本模組從不改動，
## 那些欄位的載入檢查把票數綁在回合數上）。花掉的票另外記在 player.souvenir.spent，
## 可用餘額＝累計獲得－已花掉，三種活動各自計算、不能互換。
##
## 獎勵是真的家具：每件兌換品是一個背包物品 "<kind>_kit"（World.NAMES 有名字），
## 經既有的建造動作 build（extra=<kind>，World.BUILD[<kind>]={"name",<kind>_kit:1}）
## 放到家園，拆除（remove）時照既有規則把 1 個 kit 退回背包；可以搬移（move_object）。
## 七種都不擋路（與木燈、木椅、手刻歡迎牌相同）。不能出貨（不在 SHIPPING.prices）、
## 不能在小栗攤位賣、不能上市集攤位（MARKET.sellable 只收有價目的物品）、不能和其他
## 玩家交易（World.trade_items() 排除），所以不是換鈴幣的漏洞；可以放進箱子。
## 拆除或搬移不退票，兌換不可撤銷。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；同樣的 state 與動作永遠得到同樣結果；
## 失敗時 state 完全不變（先檢查完全部條件，最後才寫入）。
##
## ── 交換攤位置（家園座標，渡口野餐後解鎖，只在風鈴渡口）─────────────────────
## CANDIDATES=[(37,25),(35,26),(39,24)]：廣場石板地北緣再往北的草地。依序取第一個
## objects/ground/roofs/crops/forest 都沒有東西的格子（與市集攤位、出貨箱相同），全被
## 佔用時為 NO_CELL，交換攤「暫停」（兌換回 NO_POINT）。舊存檔若已在這些格子蓋了東西
## 不會失效。解鎖後使用中的那一格保留（World.protected：不能建造、耕作、種樹）並擋路
## （World.blocked）。三格都是陸地、不是河、沒有 base_resource 固定樹／石／草；不碰
## （含 8 鄰格）出生點、出貨箱／市集攤位／共餐桌候選、公告板、種子攤、居民與節慶站位、
## 豐收接力五格、河岸釣魚會、家園布置題、第一塊田 (45..47,26..27)、渡口出入口與轉乘點；
## 也遠離常用建地（41..43,34..37、34..37,33..37、46..51,22..29）。站在廣場 (37,27)
## 一帶即在 REACH 內。
##
## ── 個人紀錄 player.souvenir（可省略；第一次兌換成功才寫入，舊存檔不需遷移）
##   {"spent":{"harvest_relay":int,"fish_meet":int,"showcase":int},   # 三鍵都在
##    "redeemed":{entry_id:int>=1}}                                   # 只列換過的
##   spent[活動] 恆等於 Σ redeemed[e]×ENTRIES[e].cost[活動]，且 <= 該活動累計獲得的票。
##
## ── 目錄 ENTRIES（ENTRY_ORDER 順序；id 同時是 World.BUILD 的種類）──
##   veg_basket_rack   菜籃小架     豐收接力 3
##   relay_crate_stack 接力菜箱堆   豐收接力 6
##   carp_banner       鯽魚布旗     河岸釣魚會 3
##   float_garland     浮球串飾     河岸釣魚會 6
##   lantern_post      紙燈籠柱     家園布置題 3
##   flower_arch       花草拱架     家園布置題 6
##   trio_keepsake     三活動紀念牌 豐收接力 3＋河岸釣魚會 3＋家園布置題 3
## 背包物品 id 一律是 "<id>_kit"。同一件可以重複兌換（每件最多 MAX_REDEEMED 次）。
##
## ── 公開 API（伺服器與介面共用）──
##   const ACTIONS=["souvenir_redeem"], HOME, NO_CELL, CANDIDATES, REACH=3.2,
##         ACTIVITIES=["harvest_relay","fish_meet","showcase"], ACTIVITY_NAMES,
##         ENTRIES{id->{"name","blurb","cost":{activity->int}}}, ENTRY_ORDER,
##         KIT_SUFFIX="_kit", MAX_ITEM, MAX_REDEEMED, MAX_SPENT,
##         訊息常數（LOCKED, WRONG_REGION, NO_POINT, WRONG_POINT, TOO_FAR, UNKNOWN_ENTRY,
##         STALE, NOT_ENOUGH(%s), BAG_FULL(%s), LIMIT, BAD_EXTRA, NO_PLAYER）
##   static func unlocked(snapshot) -> bool                 # state.picnic==true
##   static func cell_free(snapshot,cell) -> bool
##   static func cell_for(snapshot) -> Vector2i             # 第一個空的候選格，全被佔用時 NO_CELL
##   static func active_cell(snapshot) -> Vector2i          # 未解鎖時 NO_CELL
##   static func available(snapshot) -> bool                # 已解鎖且有可用的攤位格
##   static func reserved(snapshot,p) -> bool               # 解鎖後使用中的攤位格（保留並擋路）
##   static func blocks(snapshot,p) -> bool                 # = reserved
##   static func item_of(entry) -> String                   # "<entry>_kit"；未知時 ""
##   static func entry_of_item(item) -> String              # 反查；不是兌換品時 ""
##   static func is_item(item) -> bool / is_kind(kind) -> bool
##   static func items() -> Array                           # 七個背包物品 id（ENTRY_ORDER 順序）
##   static func cost_text(entry) -> String                 # 「豐收接力 3 張」「豐收接力 3、河岸釣魚會 3、家園布置題 3 張」
##   static func fresh_record() -> Dictionary
##   static func record(person) -> Dictionary               # 唯讀，沒有時 fresh_record()
##   static func earned(person) -> Dictionary               # {activity:int}，讀三個活動紀錄的 tickets
##   static func balances(person) -> Dictionary             # earned − spent
##   static func extra_for(entry,person) -> String          # 動作 extra "<entry>|<已兌換次數>"
##   static func view(state,token) -> Dictionary            # 本人用（data.own_souvenir）
##   static func apply(state,token,action,p,extra,at_home:bool) -> Dictionary  # {"ok","message"}
##   static func valid(s:Dictionary) -> bool                # 存檔檢查（player.souvenir）
## World 另有 World.souvenir_cell(snapshot)、World.souvenir_view(token) 包裝。
##
## 動作 souvenir_redeem：p＝目前的攤位格（view.point），距離 <= REACH；
##   extra＝"<entry_id>|<本人已兌換該件的次數>"（= view.entries[i].extra），次數不符回
##   STALE，防止重送或連點換到兩次。檢查順序：LOCKED → WRONG_REGION → NO_PLAYER →
##   BAD_EXTRA（未知動作／紀錄壞掉）→ NO_POINT → WRONG_POINT → TOO_FAR → BAD_EXTRA（格式）
##   → UNKNOWN_ENTRY → STALE → LIMIT → NOT_ENOUGH → BAG_FULL。成功時背包該 kit +1、
##   spent 依價目增加、redeemed[entry]+1。不動鈴幣、其他物品與三個活動紀錄。
##
## view(state,token) 的鍵（data.own_souvenir；不含任何 token）：
##   unlocked(bool), available(bool), point(Vector2i；NO_CELL=(-1,-1) 表示暫停),
##   candidates(Array[Vector2i]), reach(float),
##   activities[{"id","name","earned","spent","balance"}]（固定 ACTIVITIES 順序）,
##   earned{activity:int}, spent{activity:int}, balance{activity:int},
##   entries[{"id","name","blurb","item","cost"{activity:int},"cost_text",
##            "affordable"(bool：餘額夠), "short"{activity:還差幾張}（夠時為 {}）,
##            "redeemed"(本人已兌換次數), "held"(背包內 kit 數), "placed"(本人已擺出的件數，
##            含其他地區), "extra"(直接當動作 extra 用)}]（固定 ENTRY_ORDER 順序）,
##   redeemed_total(int), can_redeem(bool：已解鎖且攤位可用)
## 公開快照不另加欄位：攤位位置可由 cell_for(家園快照) 算出；他人的票與兌換紀錄
## 只在伺服器與本人的 own_souvenir。

const HARVEST=preload("res://scripts/harvest_relay.gd")
const FISH_MEET=preload("res://scripts/fishing_meet.gd")
const SHOWCASE=preload("res://scripts/showcase.gd")

const ACTIONS:=["souvenir_redeem"]
const HOME:="home"
const NO_CELL:=Vector2i(-1,-1)
const CANDIDATES:=[Vector2i(37,25),Vector2i(35,26),Vector2i(39,24)]
const REACH:=3.2
const ACTIVITIES:=["harvest_relay","fish_meet","showcase"]
const ACTIVITY_NAMES:={"harvest_relay":"豐收接力","fish_meet":"河岸釣魚會","showcase":"家園布置題"}
const ENTRIES:={
	"veg_basket_rack":{"name":"菜籃小架","blurb":"豐收接力的紀念：三只小竹籃疊在木架上，裝著漆成蔬菜樣子的木塊。","cost":{"harvest_relay":3}},
	"relay_crate_stack":{"name":"接力菜箱堆","blurb":"兩只疊起來的菜箱，側面畫著接力用的箭頭，適合擺在田邊。","cost":{"harvest_relay":6}},
	"carp_banner":{"name":"鯽魚布旗","blurb":"河岸釣魚會的紀念：一面畫著圓肚鯽魚的小布旗，有風時會輕輕擺動。","cost":{"fish_meet":3}},
	"float_garland":{"name":"浮球串飾","blurb":"幾顆彩色浮球用麻繩串起來，掛在木架上當裝飾。","cost":{"fish_meet":6}},
	"lantern_post":{"name":"紙燈籠柱","blurb":"家園布置題的紀念：木柱上掛一盞暖色紙燈籠。","cost":{"showcase":3}},
	"flower_arch":{"name":"花草拱架","blurb":"細竹搭的小拱架，纏著花草，可以放在門口或小徑旁。","cost":{"showcase":6}},
	"trio_keepsake":{"name":"三活動紀念牌","blurb":"畫著菜籃、鯽魚和紙燈籠的木牌，紀念三種合作活動都參加過。","cost":{"harvest_relay":3,"fish_meet":3,"showcase":3}},
}
const ENTRY_ORDER:=["veg_basket_rack","relay_crate_stack","carp_banner","float_garland","lantern_post","flower_arch","trio_keepsake"]
const KIT_SUFFIX:="_kit"
const MAX_ITEM:=1000000000
const MAX_REDEEMED:=9999
const MAX_SPENT:=999999
const RECORD_KEYS:=["redeemed","spent"]

const LOCKED:="完成渡口野餐後，廣場北邊的紀念品交換攤才會開放。"
const WRONG_REGION:="紀念品交換攤在風鈴渡口廣場北邊，請回到渡口再兌換。"
const NO_POINT:="紀念品交換攤的位置被占住了，先把廣場北邊的空地整理出來。"
const WRONG_POINT:="請走到紀念品交換攤前再兌換。"
const TOO_FAR:="再靠近紀念品交換攤一點。"
const UNKNOWN_ENTRY:="找不到這件紀念品，請重新打開交換攤。"
const STALE:="兌換紀錄已更新，請重新打開交換攤。"
const NOT_ENOUGH:="紀念票不夠，還差%s。"
const BAG_FULL:="背包裡的%s已經放不下了，先整理背包再來兌換。"
const LIMIT:="這件紀念品的兌換次數已達上限。"
const BAD_EXTRA:="請重新操作紀念品交換攤。"
const NO_PLAYER:="請重新加入世界再兌換紀念品。"

static func unlocked(snapshot:Dictionary) -> bool:
	return snapshot.get("picnic",false)==true

static func cell_free(snapshot:Dictionary,cell:Vector2i) -> bool:
	var tile:="%d,%d"%[cell.x,cell.y]
	for field in ["objects","ground","roofs","crops","forest"]:
		var layer:Variant=snapshot.get(field,{})
		if layer is Dictionary and layer.has(tile):return false
	return true

## 第一個空著的候選格（不看是否解鎖）；全被佔用時 NO_CELL。
static func cell_for(snapshot:Dictionary) -> Vector2i:
	for cell:Vector2i in CANDIDATES:
		if cell_free(snapshot,cell):return cell
	return NO_CELL

static func active_cell(snapshot:Dictionary) -> Vector2i:
	return cell_for(snapshot) if unlocked(snapshot) else NO_CELL

static func available(snapshot:Dictionary) -> bool:
	return active_cell(snapshot)!=NO_CELL

static func reserved(snapshot:Dictionary,p:Vector2i) -> bool:
	return p in CANDIDATES and p==active_cell(snapshot)

static func blocks(snapshot:Dictionary,p:Vector2i) -> bool:
	return reserved(snapshot,p)

static func item_of(entry:String) -> String:
	return entry+KIT_SUFFIX if ENTRIES.has(entry) else ""

static func entry_of_item(item:String) -> String:
	if not item.ends_with(KIT_SUFFIX):return ""
	var entry:=item.trim_suffix(KIT_SUFFIX)
	return entry if ENTRIES.has(entry) else ""

static func is_item(item:String) -> bool:
	return not entry_of_item(item).is_empty()

static func is_kind(kind:String) -> bool:
	return ENTRIES.has(kind)

static func items() -> Array:
	var out:=[]
	for entry:String in ENTRY_ORDER:out.append(item_of(entry))
	return out

static func cost_text(entry:String) -> String:
	if not ENTRIES.has(entry):return ""
	var parts:=PackedStringArray()
	var cost:Dictionary=ENTRIES[entry].cost
	for activity:String in ACTIVITIES:
		if cost.has(activity):parts.append("%s %d"%[ACTIVITY_NAMES[activity],int(cost[activity])])
	return "、".join(parts)+" 張"

static func fresh_record() -> Dictionary:
	var spent:={}
	for activity:String in ACTIVITIES:spent[activity]=0
	return {"spent":spent,"redeemed":{}}

static func record(person:Dictionary) -> Dictionary:
	var found:Variant=person.get("souvenir")
	return found if found is Dictionary else fresh_record()

## 三個活動紀錄的累計紀念票（唯讀）。
static func earned(person:Dictionary) -> Dictionary:
	return {"harvest_relay":int(HARVEST.record(person).get("tickets",0)),
		"fish_meet":int(FISH_MEET.record(person).get("tickets",0)),
		"showcase":int(SHOWCASE.record(person).get("tickets",0))}

static func balances(person:Dictionary) -> Dictionary:
	var got:=earned(person)
	var spent:Variant=record(person).get("spent",{})
	var out:={}
	for activity:String in ACTIVITIES:
		out[activity]=int(got[activity])-(int(spent.get(activity,0)) if spent is Dictionary else 0)
	return out

static func _redeemed(person:Dictionary,entry:String) -> int:
	var redeemed:Variant=record(person).get("redeemed",{})
	return int(redeemed.get(entry,0)) if redeemed is Dictionary else 0

static func extra_for(entry:String,person:Dictionary) -> String:
	return "%s|%d"%[entry,_redeemed(person,entry)]

static func _shortfall(entry:String,balance:Dictionary) -> Dictionary:
	var out:={}
	var cost:Dictionary=ENTRIES[entry].cost
	for activity:String in ACTIVITIES:
		if cost.has(activity) and int(balance[activity])<int(cost[activity]):out[activity]=int(cost[activity])-int(balance[activity])
	return out

static func _shortfall_text(short:Dictionary) -> String:
	var parts:=PackedStringArray()
	for activity:String in ACTIVITIES:
		if short.has(activity):parts.append("%s的紀念票 %d 張"%[ACTIVITY_NAMES[activity],int(short[activity])])
	return "、".join(parts)

static func _object_layers(state:Dictionary) -> Array:
	var layers:=[state.get("objects",{})]
	var regions:Variant=state.get("regions",{})
	if regions is Dictionary:
		for region in regions:
			var local:Variant=regions[region]
			if local is Dictionary:layers.append(local.get("objects",{}))
	return layers

## 一次掃過所有地區，統計本人擺出的各兌換品件數。
static func _placed_counts(state:Dictionary,token:String) -> Dictionary:
	var counts:={}
	for layer:Variant in _object_layers(state):
		if not layer is Dictionary:continue
		for obj:Variant in layer.values():
			if not obj is Dictionary:continue
			var kind:=str(obj.get("type",""))
			if ENTRIES.has(kind) and str(obj.get("owner",""))==token:counts[kind]=int(counts.get(kind,0))+1
	return counts

## 供專服在同一輪廣播共用，玩家代碼只留在主機。
static func placed_by_owner(state:Dictionary) -> Dictionary:
	var counts:={}
	for layer:Variant in _object_layers(state):
		if not layer is Dictionary:continue
		for obj:Variant in layer.values():
			if not obj is Dictionary:continue
			var kind:=str(obj.get("type",""))
			if not ENTRIES.has(kind):continue
			var owner:=str(obj.get("owner",""))
			var own:Dictionary=counts.get_or_add(owner,{})
			own[kind]=int(own.get(kind,0))+1
	return counts

## 只給本人看的摘要（Session 以 data.own_souvenir 送給本人）。不含任何 token。
static func view(state:Dictionary,token:String,placements:Variant=null) -> Dictionary:
	var found:Variant=state.get("players",{}).get(token,{})
	var person:Dictionary=found if found is Dictionary else {}
	var got:=earned(person)
	var own:=record(person)
	var spent:={}
	var balance:={}
	var activities:=[]
	var spent_record:Variant=own.get("spent")
	for activity:String in ACTIVITIES:
		var earned_count:=int(got[activity])
		var spent_count:=int(spent_record.get(activity,0)) if spent_record is Dictionary else 0
		var remaining:=earned_count-spent_count
		spent[activity]=spent_count
		balance[activity]=remaining
		activities.append({"id":activity,"name":str(ACTIVITY_NAMES[activity]),"earned":earned_count,"spent":spent_count,"balance":remaining})
	var inv:Variant=person.get("inventory",{})
	var redeemed:Variant=own.get("redeemed")
	var entries:=[]
	var placed:Dictionary=placements.get(token,{}) if placements is Dictionary else _placed_counts(state,token)
	var total:=0
	for entry:String in ENTRY_ORDER:
		var short:=_shortfall(entry,balance)
		var count:=int(redeemed.get(entry,0)) if redeemed is Dictionary else 0
		var item:=item_of(entry)
		total+=count
		entries.append({"id":entry,"name":str(ENTRIES[entry].name),"blurb":str(ENTRIES[entry].blurb),"item":item,
			"cost":(ENTRIES[entry].cost as Dictionary).duplicate(),"cost_text":cost_text(entry),
			"affordable":short.is_empty(),"short":short,"redeemed":count,
			"held":int(inv.get(item,0)) if inv is Dictionary else 0,
			"placed":int(placed.get(entry,0)),"extra":"%s|%d"%[entry,count]})
	var point:=active_cell(state)
	return {"unlocked":unlocked(state),"available":point!=NO_CELL,"point":point,"candidates":CANDIDATES.duplicate(),"reach":REACH,
		"activities":activities,"earned":got,"spent":spent,"balance":balance,"entries":entries,"redeemed_total":total,
		"can_redeem":point!=NO_CELL}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## 兌換動作。World 只負責把 actor 是否在家園（at_home）傳進來；
## 失敗時 state 完全不變（所有檢查都在寫入之前）。
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,at_home:bool) -> Dictionary:
	if not unlocked(state):return _fail(LOCKED)
	if not at_home:return _fail(WRONG_REGION)
	var person:Variant=state.get("players",{}).get(token)
	if not person is Dictionary:return _fail(NO_PLAYER)
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	if person.has("souvenir") and not _shape_ok(person.souvenir):return _fail(BAD_EXTRA)
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var point:=active_cell(state)
	if point==NO_CELL:return _fail(NO_POINT)
	if p!=point:return _fail(WRONG_POINT)
	if _distance(person,point)>REACH:return _fail(TOO_FAR)
	var parts:=extra.split("|")
	if parts.size()!=2 or not parts[1].is_valid_int():return _fail(BAD_EXTRA)
	var entry:=parts[0]
	if not ENTRIES.has(entry):return _fail(UNKNOWN_ENTRY)
	var count:=_redeemed(person,entry)
	if parts[1]!=str(count):return _fail(STALE)
	if count>=MAX_REDEEMED:return _fail(LIMIT)
	var balance:=balances(person)
	var short:=_shortfall(entry,balance)
	if not short.is_empty():return _fail(NOT_ENOUGH%_shortfall_text(short))
	var item:=item_of(entry)
	var inv:Dictionary=person.inventory
	if int(inv.get(item,0))>=MAX_ITEM:return _fail(BAG_FULL%str(ENTRIES[entry].name))
	var own:Dictionary=record(person).duplicate(true)
	var cost:Dictionary=ENTRIES[entry].cost
	for activity:String in ACTIVITIES:
		if int(own.spent[activity])+int(cost.get(activity,0))>MAX_SPENT:return _fail(LIMIT)
	# All checks passed: write.
	for activity:String in ACTIVITIES:own.spent[activity]=int(own.spent[activity])+int(cost.get(activity,0))
	own.redeemed[entry]=count+1
	person.souvenir=own
	inv[item]=int(inv.get(item,0))+1
	return {"ok":true,"message":"用%s換到「%s」，已放進背包。在家園工坊的「生活」頁選它就能擺到家園；拆除會收回背包，不會退票。"%[_spent_text(cost),str(ENTRIES[entry].name)]}

static func _spent_text(cost:Dictionary) -> String:
	var parts:=PackedStringArray()
	for activity:String in ACTIVITIES:
		if cost.has(activity):parts.append("%s的紀念票 %d 張"%[ACTIVITY_NAMES[activity],int(cost[activity])])
	return "、".join(parts)

## 執行期的形狀檢查（不檢查與獲得票數的關係，那由 valid() 在載入時做）。
static func _shape_ok(own:Variant) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	if not own.get("spent") is Dictionary or not own.get("redeemed") is Dictionary:return false
	for activity:String in ACTIVITIES:
		if not own.spent.has(activity):return false
	return true

# ------------------------------------------------------------------ schema --

## 存檔檢查：player.souvenir 可省略；存在時必須已野餐、恰好兩鍵、spent 恰好三個活動鍵、
## redeemed 只有已知兌換品且次數 1..MAX_REDEEMED、spent 恰等於 redeemed×價目、每種活動
## spent <= 該活動累計獲得的紀念票。通過時把 JSON 讀回的浮點整數正規化為 int。
## 必須在 HarvestRelay／FishingMeet／Showcase.valid 之後呼叫（它們先驗好票數）。
static func valid(s:Dictionary) -> bool:
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary or not person.has("souvenir"):continue
		if s.get("picnic")!=true:return false
		if not _valid_record(person.souvenir,person):return false
	return true

static func _valid_record(own:Variant,person:Dictionary) -> bool:
	if not _shape_ok(own):return false
	var spent:Dictionary=own.spent
	var redeemed:Dictionary=own.redeemed
	if spent.size()!=ACTIVITIES.size() or redeemed.is_empty() or redeemed.size()>ENTRIES.size():return false
	var expected:={}
	for activity:String in ACTIVITIES:expected[activity]=0
	for entry in redeemed:
		if not entry is String or not ENTRIES.has(entry):return false
		if not _whole(redeemed[entry],1,MAX_REDEEMED):return false
		var cost:Dictionary=ENTRIES[entry].cost
		for activity:String in ACTIVITIES:expected[activity]=int(expected[activity])+int(redeemed[entry])*int(cost.get(activity,0))
	var got:=earned(person)
	for activity:String in ACTIVITIES:
		if not _whole(spent[activity],0,MAX_SPENT):return false
		if int(spent[activity])!=int(expected[activity]):return false
		if int(spent[activity])>int(got[activity]):return false
	for activity:String in ACTIVITIES:spent[activity]=int(spent[activity])
	for entry in redeemed.keys():redeemed[entry]=int(redeemed[entry])
	return true

static func _number(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _whole(value:Variant,minimum:int,maximum:int) -> bool:
	return _number(value,float(minimum),float(maximum)) and floorf(float(value))==float(value)

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
