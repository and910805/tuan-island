extends RefCounted
## 規劃書第 40 章「風鈴節廣場・地方記憶展」：第一次成功舉辦風鈴節（state.festival_story_open）
## 之後，風鈴渡口廣場北緣設一座展台，展示各地回訪取得的紀念物。展覽隨進度更新：
## 回訪故事完成時，對應展品自動擺上展台；遲到或缺席的人可在展台補看回顧。
## 目前蘭陽回訪（lanyang_revisit.gd）完成時點亮「分水木牌」，金瓜石回訪（jinguashi_revisit.gd）
## 完成時點亮「礦燈」，貓空與鶯歌回訪（tea_revisit.gd）完成時點亮「陶器」（茶陶組），臺南北門回訪
## （salt_revisit.gd）完成時點亮「鹽籃」。四格都有對應的回訪故事。
##
## 回顧文字只重述紀錄裡真的存得下來的資料。蘭陽：state.lanyang_revisit（完成日、季節、當天天氣、
## 三塊田的需求、兩道閘的檔位、三塊田巡看的先後）。金瓜石：state.jinguashi_revisit（訂單日與
## 季節、三個貨箱各分到的礦料與數量、送出的先後、完成日與當天天氣）。貓空與鶯歌：state.tea_revisit
## （訂單日與季節、回收陶罐／磨損陶罐各收了幾只、淺焙／深焙各裝了幾罐、寄出日與當天貓空的天氣）。
## 臺南北門：state.salt_revisit（訂單日與季節、晴天／多雲各入倉幾批、料理用／醃漬用各裝幾籃、
## 其中雨天裝了幾籃、送出日與當天北門的天氣）。
## 沒有記錄誰做了哪一步，展台也不寫。回訪情節與數字為原創，非史料（沿用各回訪模組的 DISCLAIMER）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；失敗時 state 完全不變（先檢查完全部條件，
## 最後才寫入）。不 preload World（避免循環）。
##
## ── 解鎖 unlocked(snapshot)：state.festival_story_open==true（用戶端快照另認
##    festival_story.opened 或公開區塊 memory_exhibit）。未解鎖時動作一律 LOCKED、不寫入。
##
## ── 展台位置（家園座標，只在風鈴渡口；與 T071 紀念品交換攤相同的作法）
##   CANDIDATES=[(39,26),(41,23),(37,22)]：(39,26) 在廣場北緣、紀念品交換攤與鐘之間；
##   後兩格是再往北的草地。依序取第一個 objects/ground/roofs/crops/forest 都沒有東西的格子；
##   三格都被佔用時 NO_CELL，展台「暫停」（動作回 NO_POINT，blocked_cells() 列出要清的格子）。
##   舊存檔若已在這些格子蓋了東西不會失效。解鎖後使用中的那一格保留（World.protected）並擋路
##   （World.blocked）。三格都是陸地、沒有固定樹／石／草；不碰（含 8 鄰格）出生點、公告板、
##   種子攤、共餐桌／出貨箱／市集候選、紀念品交換攤三格、居民與節慶站位、風鈴樹、鐘、
##   豐收接力、河岸釣魚會、家園布置題、第一塊田、渡口出入口與轉乘點（test_memory_exhibit 驗）。
##   站在 (39,27) 一帶即在 REACH 內。
##
## ── 展品 EXHIBIT_ORDER（固定四格、固定順序）EXHIBITS[id]={"name","region","story"}
##   lanyang      分水木牌（宜蘭・蘭陽水圳回訪「旱日分流」）— LanyangRevisit.completed(state) 時展出
##   jinguashi    礦燈（金瓜石回訪「礦料調度」）— JinguashiRevisit.completed(state) 時展出
##   tea_pottery  陶器（貓空與鶯歌回訪「茶罐大單」，紀念品茶陶組）— TeaRevisit.completed(state) 時展出
##   beimen       鹽籃（臺南北門回訪「鹽籃批次」，紀念品鹽籃）— SaltRevisit.completed(state) 時展出
##   available(snapshot,id) 是唯一決定「故事是否已補齊」的地方。
##   on_display(snapshot,id) = unlocked(snapshot) and available(snapshot,id)。
##
## ── 個人紀錄 player.memory_exhibit（可省略；第一次成功 exhibit_view 才寫入，舊存檔不需遷移）
##   {"seen":[exhibit_id..]}   # 看過的展品，不重複，依看過的先後
##   不記錄看的時間；世界紀錄裡沒有「誰看過」。
##
## ── 動作（World._apply 在 LANYANG_REVISIT 之後、一般距離檢查之前轉給 apply()）
##   exhibit_view  p＝目前的展台格（stand_cell），extra＝展品 id（extra_for(id)）
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → LOCKED → WRONG_REGION →
##     BAD_EXTRA（紀錄壞掉）→ NO_POINT（暫停）→ WRONG_POINT → TOO_FAR → UNKNOWN_EXHIBIT →
##     NOT_ON_DISPLAY → ALREADY_SEEN → 寫入 seen，回 VIEW_OK%展品名。
##   ALREADY_SEEN 是不改任何東西的回覆（ok=false）；介面重看回顧不必送動作。
##   重送：World.act 以 request id 存回條，同一請求重送拿到同一個回覆、不再寫入；
##   新請求再看同一件 → ALREADY_SEEN。
##
## ── 快照
##   公開（Session.public_state，所有收件人一樣）：snapshot.memory_exhibit = public(state)
##     = {"cell":Vector2i（暫停時 NO_CELL）,"paused":bool,"on_display":[id..],"blocked_cells":[Vector2i..]}
##     未解鎖時沒有這個鍵。不含任何玩家資料。
##   只給本人：snapshot.own_memory_exhibit = own(state,token)
##     = {"seen":[id..],"first_share_done":bool,"plaque_claimed":bool,
##        "sorting_done":bool,"lantern_claimed":bool,"comparison_done":bool,"teaware_claimed":bool,
##        "raking_done":bool,"basket_claimed":bool}（不含 token）
##     sorting_done＝本人跟波波整理過一次礦樣（金瓜石回訪的本人前提）；lantern_claimed＝已領礦燈。
##     comparison_done＝本人跟茶茶完成兩種包裝比較（貓空與鶯歌回訪的本人前提）；teaware_claimed＝已領茶陶組。
##     raking_done＝本人在北門親手收過鹽（臺南北門回訪的本人前提）；basket_claimed＝已領鹽籃。
##   其他玩家的 players[*] 不含 memory_exhibit。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照讀 own_memory_exhibit）
##   unlocked(snapshot) -> bool
##   cell_free(snapshot,cell) -> bool / cell_for(snapshot) -> Vector2i（看圖層，不看解鎖）
##   stand_cell(snapshot) -> Vector2i            # 未解鎖或暫停時 NO_CELL；用戶端優先讀公開區塊
##   paused(snapshot) -> bool                    # 已解鎖但三格都被佔用
##   blocked_cells(snapshot) -> Array[Vector2i]  # 暫停時要清的格子（任一格清空即恢復）；沒暫停時 []
##   reserved(snapshot,p) / blocks(snapshot,p) -> bool   # World.protected / World.blocked 用
##   available(snapshot,id) -> bool / on_display(snapshot,id) -> bool / on_display_ids(snapshot) -> Array
##   seen_ids(snapshot,token="") -> Array[String]
##   exhibits(snapshot,token="") -> Array[{"id","name","region","story","on_display","seen","unread",
##       "lines":Array[String],"source","project","blurb","disclaimer","extra"}]（固定 EXHIBIT_ORDER）
##       空展台 lines=[EMPTY_LINE]、source/project/blurb/disclaimer=""。
##   exhibit(snapshot,id,token="") -> Dictionary（同上一列；未知 id 時 {}）
##   unread_count(snapshot,token="") -> int      # 已展出但本人還沒看過
##   recap(snapshot) -> Dictionary               # 蘭陽完成日的資料；未完成時 {}
##       {"day","season","season_label","weather","weather_label","demand":[3],"gates":[2],
##        "order":[field_id..],"order_names":[..],"reason"}
##   jinguashi_recap(snapshot) -> Dictionary     # 金瓜石的資料；未完成時 {}
##       {"day"(完成日),"weather","weather_label","order_day","season","season_label","reason",
##        "crates":[{"id","name","how","ore","ore_name","amount"}..（DESTS 順序）],
##        "sent":[dest..],"sent_names":[..]}
##   tea_recap(snapshot) -> Dictionary           # 貓空與鶯歌的資料；未完成時 {}
##       {"day"(寄出日),"weather","weather_label"（當天貓空的天氣）,"order_day","season","season_label",
##        "reason","order":{"light","deep"},"returned","worn","light","deep"}
##   salt_recap(snapshot) -> Dictionary          # 臺南北門的資料；未完成時 {}
##       {"day"(送出日),"weather","weather_label"（當天北門的天氣）,"order_day","season","season_label",
##        "reason","order":{"kitchen","pickle"},"sunny","cloudy"（各天氣入倉批數）,"kitchen","pickle",
##        "rain_packs"（雨天裝的籃數）}
##   recap_for(snapshot,id) -> Dictionary        # lanyang→recap、jinguashi→jinguashi_recap、
##                                               # tea_pottery→tea_recap、beimen→salt_recap；其他 {}
##   recap_pages(id,snapshot) -> Array[{"title","lines":Array[String]}]  # 已展出時 4 頁；否則 []
##   personal(snapshot,token="") -> {"seen","unread","first_share_done","plaque_claimed","hint",
##       "sorting_done","lantern_claimed","lantern_hint","comparison_done","teaware_claimed","teaware_hint",
##       "raking_done","basket_claimed","basket_hint"}
##   personal_hint(snapshot,token="") -> String  # 蘭陽的 HINT_* 之一（= personal_hint_for(…,"lanyang",…)）
##   personal_hint_for(snapshot,id,token="") -> String  # 各展品的「你的進度」：
##       lanyang → HINT_*；jinguashi → HINT_JG_*（LOCKED / NOT_DONE_NOT_READY / NOT_DONE /
##       NOT_READY / UNCLAIMED / CLAIMED）；tea_pottery → HINT_TEA_*（NOT_DONE_NOT_READY / NOT_DONE /
##       NOT_READY / UNCLAIMED / CLAIMED；茶陶沒有世界層級的前提，所以沒有 LOCKED）；
##       beimen → HINT_SALT_*（LOCKED / NOT_DONE_NOT_READY / NOT_DONE / NOT_READY / UNCLAIMED / CLAIMED）；
##       未知 id ""
##   view_block(snapshot,id,token="") -> String  # 不能送 exhibit_view 的原因（不看位置）；可以時 ""
##   extra_for(id) -> String
##   public(state) / own(state,token) / apply(state,token,action,p,extra,at_home) / valid(s)

const REVISIT=preload("res://scripts/lanyang_revisit.gd")
const JG=preload("res://scripts/jinguashi_revisit.gd")
const TEA=preload("res://scripts/tea_revisit.gd")
const SALT=preload("res://scripts/salt_revisit.gd")
const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="memory_exhibit"      # 公開快照區塊（伺服器 state 頂層永遠沒有這個鍵）
const OWN_KEY:="own_memory_exhibit"    # 只給本人的快照區塊
const RECORD_KEY:="memory_exhibit"     # player.memory_exhibit
const RECORD_KEYS:=["seen"]
const VIEW_ACTION:="exhibit_view"
const ACTIONS:=[VIEW_ACTION]
const HOME:="home"
const NO_CELL:=Vector2i(-1,-1)
const CANDIDATES:=[Vector2i(39,26),Vector2i(41,23),Vector2i(37,22)]
const REACH:=3.2
const TITLE:="地方記憶展"

const EXHIBIT_ORDER:=["lanyang","jinguashi","tea_pottery","beimen"]
const EXHIBITS:={
	"lanyang":{"name":"分水木牌","region":"宜蘭・蘭陽水圳","story":"蘭陽回訪「旱日分流」"},
	"jinguashi":{"name":"礦燈","region":"金瓜石","story":"金瓜石回訪"},
	"tea_pottery":{"name":"陶器","region":"貓空與鶯歌","story":"貓空與鶯歌回訪"},
	"beimen":{"name":"鹽籃","region":"臺南北門","story":"臺南北門回訪"},
}
const EMPTY_LINE:="這段回訪故事還沒補齊，展台先空著。"

const NO_PLAYER:="請重新加入世界再看展。"
const LOCKED:="風鈴節開幕之後，廣場才會設地方記憶展。"
const WRONG_REGION:="地方記憶展在風鈴渡口廣場，請回到渡口再看。"
const NO_POINT:="記憶展的展台位置都被占住了，清出 %s 其中一格就能擺回來。"
const WRONG_POINT:="請走到地方記憶展的展台前。"
const TOO_FAR:="再靠近展台一點。"
const UNKNOWN_EXHIBIT:="找不到這件展品，請重新打開記憶展。"
const NOT_ON_DISPLAY:="這件展品還沒擺上展台，等回訪故事補齊再來看。"
const ALREADY_SEEN:="你已經看過這件展品了，隨時可以再翻閱回顧。"
const BAD_EXTRA:="請重新操作記憶展。"
const VIEW_OK:="看完了「%s」的回顧，展台記下你看過了。"

const HINT_REVISIT_LOCKED:="蘭陽的旱日分流還沒開始：要先修好蘭陽水圳、在橋邊設好配水紀念牌。"
const HINT_NOT_DONE_NOT_READY:="蘭陽的旱日分流還沒完成。你也還沒走完自己的第一次分水；先到蘭陽找星禾補做，再一起去岔口調閘。"
const HINT_NOT_DONE:="蘭陽的旱日分流還沒完成；放晴的日子到岔口調閘、巡看三塊田，展台就會擺上分水木牌。"
const HINT_NOT_READY:="你還沒走完自己的第一次分水；到蘭陽找星禾補做後，可以領一塊分水木牌。"
const HINT_UNCLAIMED:="你的木牌還在星禾那裡等你領。"
const HINT_CLAIMED:="你已經領到自己的分水木牌；在家園工坊的「生活」頁可以擺出來。"
const HINT_JG_LOCKED:="金瓜石的礦料調度還沒開始：要先修好合作礦場的升降台。"
const HINT_JG_NOT_DONE_NOT_READY:="金瓜石的礦料調度還沒完成。你也還沒跟波波整理過礦樣；先到波波的整理桌完成一次，再一起分揀寄運。"
const HINT_JG_NOT_DONE:="金瓜石的礦料調度還沒完成；到波波的整理桌分揀三個貨箱，再分頭送出，展台就會擺上礦燈。"
const HINT_JG_NOT_READY:="你還沒跟波波整理過礦樣；到金瓜石完成一次礦樣整理後，可以領一盞礦燈。"
const HINT_JG_UNCLAIMED:="你的礦燈還在波波那裡等你領。"
const HINT_JG_CLAIMED:="你已經領到自己的礦燈；在家園工坊的「生活」頁可以擺出來。"
const HINT_TEA_NOT_DONE_NOT_READY:="貓空與鶯歌的茶罐大單還沒寄出。你也還沒跟茶茶完成兩種包裝的比較；先到貓空找茶茶補做，再一起交空罐、裝茶。"
const HINT_TEA_NOT_DONE:="貓空與鶯歌的茶罐大單還沒寄出；把送貨回來的空罐交給鶯歌的陶師，再到貓空的包裝台裝滿 6 罐寄出，展台就會擺上陶器。"
const HINT_TEA_NOT_READY:="你還沒跟茶茶完成兩種包裝的比較；到貓空找茶茶補做後，可以領一組茶陶組。"
const HINT_TEA_UNCLAIMED:="你的茶陶組還在鶯歌陶師那裡等你領。"
const HINT_TEA_CLAIMED:="你已經領到自己的茶陶組；在家園工坊的「生活」頁可以擺出來。"
const HINT_SALT_LOCKED:="臺南北門的鹽籃批次還沒開始：要先修好北門合作鹽田的三道閘門。"
const HINT_SALT_NOT_DONE_NOT_READY:="北門的鹽籃批次還沒送出。你也還沒在北門親手收過鹽；先到保留手作池引海水、收一次鹽，再一起入倉、裝籃。"
const HINT_SALT_NOT_DONE:="北門的鹽籃批次還沒送出；不下雨的日子把海鹽交給阿曬入倉，在合作社收鹽箱旁裝滿 6 籃，再到海邊公車站送出，展台就會擺上鹽籃。"
const HINT_SALT_NOT_READY:="你還沒在北門親手收過鹽；到保留手作池收一次鹽後，可以領一只鹽籃。"
const HINT_SALT_UNCLAIMED:="你的鹽籃還在阿曬那裡等你領。"
const HINT_SALT_CLAIMED:="你已經領到自己的鹽籃；在家園工坊的「生活」頁可以擺出來。"

# ------------------------------------------------------------------ views --

static func unlocked(snapshot:Dictionary) -> bool:
	if snapshot.get("festival_story_open")==true:return true
	var view:Variant=snapshot.get("festival_story")
	if view is Dictionary and view.get("opened")==true:return true
	return snapshot.get(STATE_KEY) is Dictionary

static func cell_free(snapshot:Dictionary,cell:Vector2i) -> bool:
	var tile:="%d,%d"%[cell.x,cell.y]
	for field in ["objects","ground","roofs","crops","forest"]:
		var layer:Variant=snapshot.get(field,{})
		if layer is Dictionary and layer.has(tile):return false
	return true

## 第一個空著的候選格（看傳入的圖層，不看是否解鎖）；全被佔用時 NO_CELL。
static func cell_for(snapshot:Dictionary) -> Vector2i:
	for cell:Vector2i in CANDIDATES:
		if cell_free(snapshot,cell):return cell
	return NO_CELL

static func _block(snapshot:Dictionary) -> Dictionary:
	var found:Variant=snapshot.get(STATE_KEY)
	return found if found is Dictionary else {}

static func stand_cell(snapshot:Dictionary) -> Vector2i:
	if not unlocked(snapshot):return NO_CELL
	var block:=_block(snapshot)
	if block.get("cell") is Vector2i:return block.cell
	return cell_for(snapshot)

static func paused(snapshot:Dictionary) -> bool:
	return unlocked(snapshot) and stand_cell(snapshot)==NO_CELL

static func blocked_cells(snapshot:Dictionary) -> Array:
	return CANDIDATES.duplicate() if paused(snapshot) else []

## 伺服器端（圖層在 state 上）：解鎖後使用中的那一格。
static func reserved(snapshot:Dictionary,p:Vector2i) -> bool:
	return p in CANDIDATES and unlocked(snapshot) and p==cell_for(snapshot)

static func blocks(snapshot:Dictionary,p:Vector2i) -> bool:
	return reserved(snapshot,p)

## 故事是否已補齊（不看風鈴節）。之後的回訪批次在這裡點亮其他展品。
static func available(snapshot:Dictionary,id:String) -> bool:
	match id:
		"lanyang":return REVISIT.completed(snapshot)
		"jinguashi":return JG.completed(snapshot)
		"tea_pottery":return TEA.completed(snapshot)
		"beimen":return SALT.completed(snapshot)
	return false

static func on_display(snapshot:Dictionary,id:String) -> bool:
	return EXHIBITS.has(id) and unlocked(snapshot) and available(snapshot,id)

static func on_display_ids(snapshot:Dictionary) -> Array:
	var out:=[]
	for id:String in EXHIBIT_ORDER:
		if on_display(snapshot,id):out.append(id)
	return out

static func extra_for(id:String) -> String:
	return id

static func _person(snapshot:Dictionary,token:String) -> Dictionary:
	if token.is_empty():return {}
	var people:Variant=snapshot.get("players")
	if people is Dictionary and people.get(token) is Dictionary:return people[token]
	return {}

static func _clean_ids(raw:Variant) -> Array:
	var out:=[]
	if raw is Array:
		for id in raw:
			if (id is String or id is StringName) and EXHIBITS.has(str(id)) and str(id) not in out:out.append(str(id))
	return out

static func seen_ids(snapshot:Dictionary,token:String="") -> Array:
	var person:=_person(snapshot,token)
	if not person.is_empty():
		var own:Variant=person.get(RECORD_KEY)
		return _clean_ids(own.get("seen")) if own is Dictionary else []
	var mine:Variant=snapshot.get(OWN_KEY)
	return _clean_ids(mine.get("seen")) if mine is Dictionary else []

static func _first_share_done(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("first_share_done"):return mine.get("first_share_done")==true
	return REVISIT.player_ready(snapshot,token)

static func _plaque_claimed(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("plaque_claimed"):return mine.get("plaque_claimed")==true
	return REVISIT.claimed_own(snapshot,token)

static func _sorting_done(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("sorting_done"):return mine.get("sorting_done")==true
	return JG.player_ready(snapshot,token)

static func _lantern_claimed(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("lantern_claimed"):return mine.get("lantern_claimed")==true
	return JG.claimed_own(snapshot,token)

static func _comparison_done(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("comparison_done"):return mine.get("comparison_done")==true
	return TEA.player_ready(snapshot,token)

static func _teaware_claimed(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("teaware_claimed"):return mine.get("teaware_claimed")==true
	return TEA.claimed_own(snapshot,token)

static func _raking_done(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("raking_done"):return mine.get("raking_done")==true
	return SALT.player_ready(snapshot,token)

static func _basket_claimed(snapshot:Dictionary,token:String) -> bool:
	if token.is_empty():
		var mine:Variant=snapshot.get(OWN_KEY)
		if mine is Dictionary and mine.has("basket_claimed"):return mine.get("basket_claimed")==true
	return SALT.claimed_own(snapshot,token)

static func _season_text(season:String) -> String:
	return str(WEATHER.SEASON_LABELS.get(season,""))+"季"

## 蘭陽完成日的資料，全部從 state.lanyang_revisit（公開欄位）推得：完成後閘門不能再調，
## 所以 day／gates 就是完成那天的設定；checked 的先後就是巡看的先後。
static func recap(snapshot:Dictionary) -> Dictionary:
	if not REVISIT.completed(snapshot):return {}
	var rec:=REVISIT.record(snapshot)
	var day:=maxi(1,int(rec.get("day",1)))
	var day_index:=float(day-1)
	var season:=WEATHER.season_on_day(day_index)
	var weather:=WEATHER.outdoor_id(day_index)
	var order:=[]
	var names:=[]
	var raw:Variant=rec.get("checked")
	if raw is Array:
		for id in raw:
			if str(id) in REVISIT.FIELDS and str(id) not in order:
				order.append(str(id))
				names.append(str(REVISIT.FIELD_NAMES[str(id)]))
	return {"day":day,"season":season,"season_label":_season_text(season),"weather":weather,
		"weather_label":str(WEATHER.LABELS.get(weather,"")),"demand":REVISIT.demand_for(season),
		"gates":REVISIT.gates(snapshot),"order":order,"order_names":names,"reason":REVISIT.reason_for(season)}

static func _lanyang_lines(snapshot:Dictionary) -> Array:
	var r:=recap(snapshot)
	var need:Array=r.demand
	var gates:Array=r.gates
	return [REVISIT.PLAQUE_BLURB,REVISIT.PLAQUE_SOURCE,REVISIT.PLAQUE_PROJECT,
		"完成那天：第 %d 日・%s・%s"%[int(r.day),str(r.season_label),str(r.weather_label)],
		"三塊田需要：上游 %d／中段 %d／田尾 %d 份"%[int(need[0]),int(need[1]),int(need[2])],
		"岔口的閘：上游閘 %d 檔、中段閘 %d 檔"%[int(gates[0]),int(gates[1])],
		REVISIT.DISCLAIMER]

## 金瓜石的資料，全部從 state.jinguashi_revisit（公開欄位）推得：第一箱送出後分揀就鎖住，
## 所以 crates 就是那批訂單的分揀；sent 的先後就是送出的先後；day＝第一箱送出（訂單）的日子，
## done_day＝第三箱送出（完成）的日子。
static func jinguashi_recap(snapshot:Dictionary) -> Dictionary:
	if not JG.completed(snapshot):return {}
	var rec:=JG.record(snapshot)
	var order_day:=maxi(1,int(rec.get("day",1)))
	var day:=maxi(order_day,int(rec.get("done_day",order_day)))
	var season:=WEATHER.season_on_day(float(order_day-1))
	var weather:=WEATHER.outdoor_id(float(day-1))
	var now:=JG.crates(snapshot)
	var rows:=[]
	for dest:String in JG.DESTS:
		var ore:=str(now[dest])
		rows.append({"id":dest,"name":str(JG.DEST_NAMES[dest]),"how":str(JG.DEST_HOW[dest]),"ore":ore,
			"ore_name":str(JG.ORE_NAMES.get(ore,"")),"amount":JG.amount_for(ore)})
	var order:=JG.sent(snapshot)
	var names:=[]
	for dest:String in order:names.append(str(JG.DEST_NAMES[dest]))
	return {"day":day,"weather":weather,"weather_label":str(WEATHER.LABELS.get(weather,"")),"order_day":order_day,
		"season":season,"season_label":_season_text(season),"reason":JG.reason_for(season),
		"crates":rows,"sent":order,"sent_names":names}

## 貓空與鶯歌的資料，全部從 state.tea_revisit（公開欄位）推得：day＝第一次裝茶（訂單）的日子，
## 之後訂單鎖在那天的季節；done_day＝寄出（完成）的日子；天氣是那天貓空（戶外）的天氣。
static func tea_recap(snapshot:Dictionary) -> Dictionary:
	if not TEA.completed(snapshot):return {}
	var rec:=TEA.record(snapshot)
	var order_day:=maxi(1,int(rec.get("day",1)))
	var day:=maxi(order_day,int(rec.get("done_day",order_day)))
	var season:=WEATHER.season_on_day(float(order_day-1))
	var weather:="indoor" if WEATHER.is_indoor(TEA.FILL_REGION) else WEATHER.outdoor_id(float(day-1))
	var jars:=TEA.jars(snapshot)
	var done:=TEA.filled(snapshot)
	return {"day":day,"weather":weather,"weather_label":str(WEATHER.LABELS.get(weather,"")),"order_day":order_day,
		"season":season,"season_label":_season_text(season),"reason":TEA.reason_for(season),
		"order":TEA.order_for(season),"returned":int(jars.tea_returned_jar),"worn":int(jars.tea_worn_jar),
		"light":int(done.light),"deep":int(done.deep)}

## 臺南北門的資料，全部從 state.salt_revisit（公開欄位）推得：day＝第一次裝籃（訂單）的日子，
## 之後訂單鎖在那天的季節；done_day＝送出（完成）的日子；天氣是那天北門（戶外）的天氣。
## 入倉只記得那批是晴天或多雲入倉，不記得哪一天。
static func salt_recap(snapshot:Dictionary) -> Dictionary:
	if not SALT.completed(snapshot):return {}
	var rec:=SALT.record(snapshot)
	var order_day:=maxi(1,int(rec.get("day",1)))
	var day:=maxi(order_day,int(rec.get("done_day",order_day)))
	var season:=WEATHER.season_on_day(float(order_day-1))
	var weather:="indoor" if WEATHER.is_indoor(SALT.REGION) else WEATHER.outdoor_id(float(day-1))
	var lots:=SALT.stocked(snapshot)
	var done:=SALT.packed(snapshot)
	return {"day":day,"weather":weather,"weather_label":str(WEATHER.LABELS.get(weather,"")),"order_day":order_day,
		"season":season,"season_label":_season_text(season),"reason":SALT.reason_for(season),
		"order":SALT.order_for(season),"sunny":int(lots.sunny),"cloudy":int(lots.cloudy),
		"kitchen":int(done.kitchen),"pickle":int(done.pickle),"rain_packs":SALT.rain_packs(snapshot)}

static func recap_for(snapshot:Dictionary,id:String) -> Dictionary:
	match id:
		"lanyang":return recap(snapshot)
		"jinguashi":return jinguashi_recap(snapshot)
		"tea_pottery":return tea_recap(snapshot)
		"beimen":return salt_recap(snapshot)
	return {}

static func _crate_text(r:Dictionary,sep:String) -> String:
	var parts:=PackedStringArray()
	for c:Dictionary in r.crates:parts.append("%s %s %d"%[str(c.name),str(c.ore_name),int(c.amount)])
	return sep.join(parts)

static func _jinguashi_lines(snapshot:Dictionary) -> Array:
	var r:=jinguashi_recap(snapshot)
	return [JG.LANTERN_BLURB,JG.LANTERN_SOURCE,JG.LANTERN_PROJECT,
		"完成那天：第 %d 日・%s"%[int(r.day),str(r.weather_label)],
		"%s的訂單：%s"%[str(r.season_label),_crate_text(r,"／")],
		"送出的先後：%s"%"、".join(PackedStringArray(r.sent_names)),
		JG.DISCLAIMER]

static func _tea_lines(snapshot:Dictionary) -> Array:
	var r:=tea_recap(snapshot)
	return [TEA.TEAWARE_BLURB,TEA.TEAWARE_SOURCE,TEA.TEAWARE_PROJECT,
		"完成那天：第 %d 日・貓空%s"%[int(r.day),str(r.weather_label)],
		"%s的訂單：淺焙 %d 罐／深焙 %d 罐"%[str(r.season_label),int(r.light),int(r.deep)],
		"回收的空罐：回收陶罐 %d 只、磨損陶罐 %d 只"%[int(r.returned),int(r.worn)],
		TEA.DISCLAIMER]

static func _salt_lines(snapshot:Dictionary) -> Array:
	var r:=salt_recap(snapshot)
	return [SALT.BASKET_BLURB,SALT.BASKET_SOURCE,SALT.BASKET_PROJECT,
		"完成那天：第 %d 日・北門%s"%[int(r.day),str(r.weather_label)],
		"%s的訂單：料理用 %d 籃／醃漬用 %d 籃"%[str(r.season_label),int(r.kitchen),int(r.pickle)],
		"入倉的散鹽：晴天 %d 批、多雲 %d 批；雨天裝籃 %d 籃"%[int(r.sunny),int(r.cloudy),int(r.rain_packs)],
		SALT.DISCLAIMER]

static func exhibit(snapshot:Dictionary,id:String,token:String="") -> Dictionary:
	if not EXHIBITS.has(id):return {}
	var info:Dictionary=EXHIBITS[id]
	var shown:=on_display(snapshot,id)
	var seen:=id in seen_ids(snapshot,token)
	var row:={"id":id,"name":str(info.name),"region":str(info.region),"story":str(info.story),
		"on_display":shown,"seen":seen,"unread":shown and not seen,"lines":[EMPTY_LINE],
		"source":"","project":"","blurb":"","disclaimer":"","extra":extra_for(id)}
	if shown and id=="lanyang":
		row.lines=_lanyang_lines(snapshot)
		row.source=REVISIT.PLAQUE_SOURCE
		row.project=REVISIT.PLAQUE_PROJECT
		row.blurb=REVISIT.PLAQUE_BLURB
		row.disclaimer=REVISIT.DISCLAIMER
	elif shown and id=="jinguashi":
		row.lines=_jinguashi_lines(snapshot)
		row.source=JG.LANTERN_SOURCE
		row.project=JG.LANTERN_PROJECT
		row.blurb=JG.LANTERN_BLURB
		row.disclaimer=JG.DISCLAIMER
	elif shown and id=="tea_pottery":
		row.lines=_tea_lines(snapshot)
		row.source=TEA.TEAWARE_SOURCE
		row.project=TEA.TEAWARE_PROJECT
		row.blurb=TEA.TEAWARE_BLURB
		row.disclaimer=TEA.DISCLAIMER
	elif shown and id=="beimen":
		row.lines=_salt_lines(snapshot)
		row.source=SALT.BASKET_SOURCE
		row.project=SALT.BASKET_PROJECT
		row.blurb=SALT.BASKET_BLURB
		row.disclaimer=SALT.DISCLAIMER
	return row

static func exhibits(snapshot:Dictionary,token:String="") -> Array:
	var out:=[]
	for id:String in EXHIBIT_ORDER:out.append(exhibit(snapshot,id,token))
	return out

static func unread_count(snapshot:Dictionary,token:String="") -> int:
	var seen:=seen_ids(snapshot,token)
	var count:=0
	for id:String in on_display_ids(snapshot):
		if id not in seen:count+=1
	return count

## 給缺席者的回顧（4 頁）。只在展品已展出時有內容。
static func recap_pages(id:String,snapshot:Dictionary) -> Array:
	if id=="jinguashi" and on_display(snapshot,id):return _jinguashi_pages(snapshot)
	if id=="tea_pottery" and on_display(snapshot,id):return _tea_pages(snapshot)
	if id=="beimen" and on_display(snapshot,id):return _salt_pages(snapshot)
	if id!="lanyang" or not on_display(snapshot,id):return []
	var r:=recap(snapshot)
	var need:Array=r.demand
	var gates:Array=r.gates
	var order:Array=r.order_names
	var walked:="大家依序巡看了%s，三塊田同一天都確認過，旱日分流就完成了。"%"、".join(PackedStringArray(order)) if order.size()==3 else "三塊田同一天都確認過，旱日分流就完成了。"
	return [
		{"title":"回訪的緣由","lines":["蘭陽水圳修好、橋邊的配水紀念牌設好之後，星禾在放晴的日子邀大家回來，用岔口的分流閘把水分給三塊田。",
			"那天是%s，星禾說：%s"%[str(r.season_label),str(r.reason)]]},
		{"title":"當天的需要","lines":["第 %d 日・%s・%s，田裡不下雨，要靠水圳分水。"%[int(r.day),str(r.season_label),str(r.weather_label)],
			"三塊田需要：上游 %d 份、中段 %d 份、田尾 %d 份（一共 12 份）。"%[int(need[0]),int(need[1]),int(need[2])]]},
		{"title":"怎麼調閘","lines":["岔口的上游閘調到 %d 檔、中段閘調到 %d 檔，三塊田剛好分到 %d／%d／%d 份。"%[int(gates[0]),int(gates[1]),int(need[0]),int(need[1]),int(need[2])],
			walked,"展台沒有記錄是誰調閘、誰巡看。"]},
		{"title":"帶回家的紀念","lines":[REVISIT.PLAQUE_BLURB,
			"完成後，每位走完自己第一次分水的島民都能到星禾那裡領一塊分水木牌；家園工坊也能做分流閘。",
			REVISIT.DISCLAIMER]},
	]

static func _jinguashi_pages(snapshot:Dictionary) -> Array:
	var r:=jinguashi_recap(snapshot)
	var sorted:=PackedStringArray()
	for c:Dictionary in r.crates:sorted.append("%s的貨箱分到%s"%[str(c.name),str(c.ore_name)])
	var names:Array=r.sent_names
	var walked:="送出的先後是%s；"%"、".join(PackedStringArray(names)) if names.size()==3 else ""
	return [
		{"title":"回訪的緣由","lines":["合作礦場的升降台修好之後，波波邀大家回金瓜石，把升降台送上來的礦料分揀到三個貨箱，再送到對應的地方。",
			"那張訂單是%s開的，波波說：%s"%[str(r.season_label),str(r.reason)]]},
		{"title":"訂單上的需要","lines":["第 %d 日送出第一箱，照的是%s的訂單。"%[int(r.order_day),str(r.season_label)],
			"三個貨箱要：%s。"%_crate_text(r,"、")]},
		{"title":"怎麼分揀與寄運","lines":["在波波的整理桌分揀：%s。"%"，".join(sorted),
			"%s第 %d 日・%s三箱都送出，礦料調度就完成了。"%[walked,int(r.day),str(r.weather_label)],
			"展台沒有記錄是誰分揀、誰寄運。"]},
		{"title":"帶回家的紀念","lines":[JG.LANTERN_BLURB,
			"完成後，每位跟波波整理過礦樣的島民都能到波波的整理桌領一盞礦燈，擺在家園。",
			JG.DISCLAIMER]},
	]

static func _tea_pages(snapshot:Dictionary) -> Array:
	var r:=tea_recap(snapshot)
	var need:Dictionary=r.order
	return [
		{"title":"回訪的緣由","lines":["跟茶茶比較過陶罐和纖維兩種包裝之後，茶茶接到一張 6 罐茶的大單，想用送貨回來的空罐來裝，邀大家串起貓空茶園和鶯歌陶坊。",
			"那張訂單是%s開的，%s"%[str(r.season_label),str(r.reason)]]},
		{"title":"訂單上的需要","lines":["第 %d 日裝下第一罐，照的是%s的訂單。"%[int(r.order_day),str(r.season_label)],
			"一共 6 罐：淺焙 %d 罐、深焙 %d 罐。"%[int(need.light),int(need.deep)]]},
		{"title":"怎麼回收與裝罐","lines":["在鶯歌，陶師收下 6 只送貨回來的空罐：回收陶罐 %d 只、磨損陶罐 %d 只。"%[int(r.returned),int(r.worn)],
			"在貓空的包裝台裝了淺焙 %d 罐、深焙 %d 罐，第 %d 日・貓空%s寄出，茶罐大單就完成了。"%[int(r.light),int(r.deep),int(r.day),str(r.weather_label)],
			"展台沒有記錄是誰交罐、誰裝茶、誰寄出。"]},
		{"title":"帶回家的紀念","lines":[TEA.TEAWARE_BLURB,
			"完成後，每位跟茶茶完成過包裝比較的島民都能到鶯歌陶師那裡領一組茶陶組，擺在家園。",
			TEA.DISCLAIMER]},
	]

static func _salt_pages(snapshot:Dictionary) -> Array:
	var r:=salt_recap(snapshot)
	var need:Dictionary=r.order
	var rain_line:="其中 %d 籃是在下雨天、倉棚不收散鹽的日子裝的。"%int(r.rain_packs) if int(r.rain_packs)>0 else "這批沒有在下雨天裝籃。"
	return [
		{"title":"回訪的緣由","lines":["北門合作鹽田的三道閘門修好、大家也親手收過鹽之後，阿曬接到一張 6 籃鹽的訂單，邀大家用合作社的倉棚、收鹽箱和海邊公車站安排一批鹽籃。",
			"那張訂單是%s開的，%s"%[str(r.season_label),str(r.reason)]]},
		{"title":"訂單上的需要","lines":["第 %d 日裝下第一籃，照的是%s的訂單。"%[int(r.order_day),str(r.season_label)],
			"一共 6 籃：料理用 %d 籃、醃漬用 %d 籃。"%[int(need.kitchen),int(need.pickle)]]},
		{"title":"怎麼入倉與裝籃","lines":["一批散鹽是 3 份海鹽，交給阿曬入倉：晴天入倉 %d 批、多雲入倉 %d 批；下雨天倉棚不收散鹽。"%[int(r.sunny),int(r.cloudy)],
			"在合作社收鹽箱旁裝了料理用 %d 籃、醃漬用 %d 籃；%s"%[int(r.kitchen),int(r.pickle),rain_line],
			"第 %d 日・北門%s，在海邊公車站送出，鹽籃批次就完成了。"%[int(r.day),str(r.weather_label)],
			"展台沒有記錄是誰入倉、誰裝籃、誰送出。"]},
		{"title":"帶回家的紀念","lines":[SALT.BASKET_BLURB,
			"完成後，每位在北門親手收過鹽的島民都能到阿曬那裡領一只鹽籃，擺在家園。",
			SALT.DISCLAIMER]},
	]

static func personal_hint(snapshot:Dictionary,token:String="") -> String:
	var ready:=_first_share_done(snapshot,token)
	if not REVISIT.completed(snapshot):
		if not REVISIT.unlocked(snapshot):return HINT_REVISIT_LOCKED
		return HINT_NOT_DONE if ready else HINT_NOT_DONE_NOT_READY
	if not ready:return HINT_NOT_READY
	return HINT_CLAIMED if _plaque_claimed(snapshot,token) else HINT_UNCLAIMED

## 各展品的「你的進度」提示；lanyang 與 personal_hint() 相同，沒有回訪故事的展品回 ""。
static func personal_hint_for(snapshot:Dictionary,id:String,token:String="") -> String:
	match id:
		"lanyang":return personal_hint(snapshot,token)
		"jinguashi":
			var ready:=_sorting_done(snapshot,token)
			if not JG.completed(snapshot):
				if not JG.unlocked(snapshot):return HINT_JG_LOCKED
				return HINT_JG_NOT_DONE if ready else HINT_JG_NOT_DONE_NOT_READY
			if not ready:return HINT_JG_NOT_READY
			return HINT_JG_CLAIMED if _lantern_claimed(snapshot,token) else HINT_JG_UNCLAIMED
		"tea_pottery":
			var ready:=_comparison_done(snapshot,token)
			if not TEA.completed(snapshot):
				return HINT_TEA_NOT_DONE if ready else HINT_TEA_NOT_DONE_NOT_READY
			if not ready:return HINT_TEA_NOT_READY
			return HINT_TEA_CLAIMED if _teaware_claimed(snapshot,token) else HINT_TEA_UNCLAIMED
		"beimen":
			var ready:=_raking_done(snapshot,token)
			if not SALT.completed(snapshot):
				if not SALT.unlocked(snapshot):return HINT_SALT_LOCKED
				return HINT_SALT_NOT_DONE if ready else HINT_SALT_NOT_DONE_NOT_READY
			if not ready:return HINT_SALT_NOT_READY
			return HINT_SALT_CLAIMED if _basket_claimed(snapshot,token) else HINT_SALT_UNCLAIMED
	return ""

static func personal(snapshot:Dictionary,token:String="") -> Dictionary:
	return {"seen":seen_ids(snapshot,token),"unread":unread_count(snapshot,token),
		"first_share_done":_first_share_done(snapshot,token),"plaque_claimed":_plaque_claimed(snapshot,token),
		"hint":personal_hint(snapshot,token),
		"sorting_done":_sorting_done(snapshot,token),"lantern_claimed":_lantern_claimed(snapshot,token),
		"lantern_hint":personal_hint_for(snapshot,"jinguashi",token),
		"comparison_done":_comparison_done(snapshot,token),"teaware_claimed":_teaware_claimed(snapshot,token),
		"teaware_hint":personal_hint_for(snapshot,"tea_pottery",token),
		"raking_done":_raking_done(snapshot,token),"basket_claimed":_basket_claimed(snapshot,token),
		"basket_hint":personal_hint_for(snapshot,"beimen",token)}

static func _cells_text() -> String:
	var parts:=PackedStringArray()
	for cell:Vector2i in CANDIDATES:parts.append("(%d,%d)"%[cell.x,cell.y])
	return "、".join(parts)

## 不能送 exhibit_view 的原因（不看位置與距離）；可以時 ""。
static func view_block(snapshot:Dictionary,id:String,token:String="") -> String:
	if not unlocked(snapshot):return LOCKED
	if paused(snapshot):return NO_POINT%_cells_text()
	if not EXHIBITS.has(id):return UNKNOWN_EXHIBIT
	if not on_display(snapshot,id):return NOT_ON_DISPLAY
	if id in seen_ids(snapshot,token):return ALREADY_SEEN
	return ""

## 公開快照區塊（伺服器 state，家園圖層在頂層時呼叫）；未解鎖時 {}。
static func public(state:Dictionary) -> Dictionary:
	if not unlocked(state):return {}
	var cell:=cell_for(state)
	return {"cell":cell,"paused":cell==NO_CELL,"on_display":on_display_ids(state),
		"blocked_cells":CANDIDATES.duplicate() if cell==NO_CELL else []}

## 只給本人的區塊（不含 token）。
static func own(state:Dictionary,token:String) -> Dictionary:
	return {"seen":seen_ids(state,token),"first_share_done":REVISIT.player_ready(state,token),
		"plaque_claimed":REVISIT.claimed_own(state,token),
		"sorting_done":JG.player_ready(state,token),"lantern_claimed":JG.claimed_own(state,token),
		"comparison_done":TEA.player_ready(state,token),"teaware_claimed":TEA.claimed_own(state,token),
		"raking_done":SALT.player_ready(state,token),"basket_claimed":SALT.claimed_own(state,token)}

# ------------------------------------------------------------------ action --

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## World passes at_home (actor's region is home, so the home layers are on state).
## Every check runs before the single write.
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,at_home:bool) -> Dictionary:
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.get(token) is Dictionary:return _fail(NO_PLAYER)
	var person:Dictionary=people[token]
	if state.get("festival_story_open")!=true:return _fail(LOCKED)
	if not at_home:return _fail(WRONG_REGION)
	if person.has(RECORD_KEY) and not _shape_ok(person[RECORD_KEY]):return _fail(BAD_EXTRA)
	var point:=cell_for(state)
	if point==NO_CELL:return _fail(NO_POINT%_cells_text())
	if p!=point:return _fail(WRONG_POINT)
	if _distance(person,point)>REACH:return _fail(TOO_FAR)
	if not EXHIBITS.has(extra):return _fail(UNKNOWN_EXHIBIT)
	if not available(state,extra):return _fail(NOT_ON_DISPLAY)
	var seen:=_clean_ids(person[RECORD_KEY].seen) if person.has(RECORD_KEY) else []
	if extra in seen:return _fail(ALREADY_SEEN)
	seen.append(extra)
	person[RECORD_KEY]={"seen":seen}
	return {"ok":true,"message":VIEW_OK%str(EXHIBITS[extra].name)}

static func _shape_ok(own_record:Variant) -> bool:
	if not own_record is Dictionary or own_record.size()!=RECORD_KEYS.size():return false
	return own_record.has("seen") and own_record.seen is Array

# ------------------------------------------------------------------ schema --

## player.memory_exhibit（可省略）。存在時：恰好 {"seen":[...]}；seen 1..4 個不重複的已知
## 展品 id（字串）；風鈴節必須已開幕；每件看過的展品必須已補齊（available）。
## 頂層不能有 STATE_KEY（那是用戶端快照的公開區塊）。必須在 LanyangRevisit.valid 與
## JinguashiRevisit.valid 之後呼叫。
static func valid(s:Dictionary) -> bool:
	if s.has(STATE_KEY):return false
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	for token in players:
		var person:Variant=players[token]
		if not person is Dictionary or not person.has(RECORD_KEY):continue
		var own_record:Variant=person[RECORD_KEY]
		if not _shape_ok(own_record):return false
		if s.get("festival_story_open")!=true:return false
		var seen:Array=own_record.seen
		if seen.is_empty() or seen.size()>EXHIBIT_ORDER.size():return false
		var found:={}
		for id in seen:
			if not id is String or not EXHIBITS.has(id) or found.has(id):return false
			if not available(s,id):return false
			found[id]=true
	return true
