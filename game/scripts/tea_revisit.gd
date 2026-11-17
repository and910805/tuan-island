extends RefCounted
## 規劃書第 40 章「貓空與鶯歌回訪・茶罐大單」：串接兩地工坊，回收空罐接大批訂單。
## 自己跟茶茶做完兩種包裝比較（tea_ceramics 的 comparison_complete）的島民，可以一起接一張
## 6 罐茶的大單：先在鶯歌合作陶坊把送貨回來的空罐（回收陶罐／磨損陶罐）交給陶師檢查，
## 再到貓空合作茶園的包裝台照訂單裝淺焙／深焙茶，裝滿 6 罐就在包裝台寄出。寄出後全島永久完成；
## 完成後每位（自己也完成過包裝比較的）島民可在鶯歌陶師那裡領一組「茶陶組」(tea_ware_kit)
## 帶回家擺放。茶陶組只是裝飾，沒有上菜機制（規劃書提到的「上菜」沒有實作）。
##
## 回訪情節與訂單數字為原創（DISCLAIMER），非史料；沒有新增任何貓空、鶯歌的史實敘述。
## 兩個地點都是遊戲裡既有的工作點（鶯歌陶師的工作桌、貓空的包裝台）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；只看 state.time（WEATHER 曆法）。失敗時 state
## 完全不變（先檢查完全部條件，最後才寫入）。不 preload World（避免循環）。
##
## ── 前提（本人）：state.tea_ceramics.players[token].comparison_complete==true（跟茶茶完成兩種
##    包裝比較：陶罐與纖維各交貨一次、領回空罐，再和茶茶談 tea_discuss）。用戶端讀
##    tea_ceramics.own_record.comparison_complete。沒做過的人（含後來加入的島民）→ NOT_READY。
##    沒有世界層級的前提：茶陶這條線本來就是每人各自的紀錄，沒有共同的公共工程。
##
## ── 世界紀錄 state.tea_revisit（可省略；第一次成功動作才寫入，舊存檔不需遷移，不升版）
##   {"jars":{"tea_returned_jar":n,"tea_worn_jar":n},  # 已交給陶師檢查的空罐（只增不減）
##    "filled":{"light":n,"deep":n},                     # 已在包裝台裝好的罐數
##    "day":int,              # 第一次裝茶的世界日（= 這張訂單的日子）；還沒裝時 0
##    "completed":bool,       # 6 罐寄出 → 永久 true
##    "done_day":int,         # 寄出（完成）的世界日；未完成時 0
##    "claimed":{token:true}} # 已領茶陶組的島民（只在伺服器；公開快照不含）
##   不記錄是誰交罐、誰裝茶、誰寄出（沒有 token）。
##   訂單：還沒裝茶時看「今天」的季節；第一次裝茶後鎖定為 day 那天的季節（之後換季也不變）。
##
## ── 訂單（依季節；WEATHER.season_on_day）ORDERS / REASONS；一共 6 罐（TOTAL）
##   spring 淺焙 4／深焙 2、summer 淺焙 5／深焙 1、autumn 淺焙 2／深焙 4、winter 淺焙 1／深焙 5
##   完成一次共用掉：回收空罐 6 只（回收陶罐或磨損陶罐，任意組合）、淺焙茶＋深焙茶共 6 份
##   （各由交罐、裝茶的人從自己背包付）。
##
## ── 地點（都是既有的茶陶工作點）
##   交罐、領茶陶組＝鶯歌 (yingge) 陶師的工作桌 POTTER (20,20)（站在 (20.5,21.5) 一帶）；
##   裝茶、寄出＝貓空 (maokong) 包裝台 PACKER (26,20)（包裝台擋路，站在 (26.5,21.5) 一帶）。
##   REACH=3.2（與一般互動相同）。
##
## ── 動作（World._apply 在 JINGUASHI_REVISIT 之後、一般距離檢查之前轉給 apply()）
##   tea_revisit_jar   鶯歌 p＝POTTER，extra＝"tea_returned_jar" 或 "tea_worn_jar"：交一只空罐
##                     （背包 -1、jars[item]+1）。陶罐（新燒或修好的 tea_jar）與待修陶罐不收。
##   tea_revisit_fill  貓空 p＝PACKER，extra＝"light" 或 "deep"：裝一罐（背包 tea_light/tea_deep -1、
##                     filled[style]+1）。需要：已裝罐數 < 已收空罐數、這種焙法還沒裝滿訂單。
##                     第一次裝茶寫入 day＝今天。
##   tea_revisit_send  貓空 p＝PACKER，extra＝""：6 罐都裝好（必然符合訂單）→ completed=true、
##                     done_day＝今天。
##   tea_revisit_claim 鶯歌 p＝POTTER，extra＝""：completed 之後每人一次，背包 +1 tea_ware_kit。
##   任何人（完成過包裝比較）可以做任何一步，可以兩地分頭進行。
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION_YINGGE / WRONG_REGION_MAOKONG →
##     NOT_READY → BAD_EXTRA（紀錄壞掉）→ WRONG_JAR_CELL / WRONG_FILL_CELL / WRONG_SEND_CELL /
##     WRONG_CLAIM_CELL → TOO_FAR →
##     jar  ：ALREADY_DONE → NEW_JAR / SPENT_JAR / BAD_JAR（extra）→ JARS_FULL → NO_JAR%罐名
##     fill ：ALREADY_DONE → BAD_STYLE → ALL_FILLED → NEED_JARS%[已收,已裝] →
##            QUOTA_FULL%[焙法,訂單數,已裝,另一種焙法] → NO_TEA%茶名
##     send ：BAD_EXTRA（extra 非空）→ ALREADY_DONE → NOT_FILLED%已裝
##     claim：BAD_EXTRA（extra 非空）→ NOT_DONE → CLAIMED → BAG_FULL
##   成功訊息：JAR_OK%[罐名,已收]、FILL_OK%[茶名,已裝,淺焙,深焙]、COMPLETE_OK、CLAIM_OK。
##
## ── 茶陶組（家園裝飾，與礦燈、分水木牌相同的規則）
##   背包物品 TEAWARE_ITEM="tea_ware_kit"，建造種類 TEAWARE_KIND="tea_ware"
##   (World.BUILD 名稱「茶陶組」)：不擋路、拆除退回 kit、可搬移、可放箱子；沒有價目
##   （不能出貨、不能在攤位賣、不能上市集），World.trade_items() 排除（不能交易）。
##   TEAWARE_SOURCE / TEAWARE_PROJECT / TEAWARE_BLURB 給介面顯示來源。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照用 tea_ceramics.own_record 與 tea_revisit.claimed_own）
##   player_ready(snapshot,token="") -> bool       # 本人完成過兩種包裝比較
##   record(snapshot) -> Dictionary                # 唯讀；沒有時 fresh()
##   completed(snapshot) -> bool / today(snapshot) -> int
##   order_season(snapshot) -> String              # 這張訂單的季節（已裝茶時鎖定為 day 那天）
##   order(snapshot) -> {"light":n,"deep":n} / order_for(season) -> {"light":n,"deep":n}
##   reason(snapshot) -> String / reason_for(season) -> String
##   jars(snapshot) -> {"tea_returned_jar":n,"tea_worn_jar":n} / jars_total(snapshot) -> int
##   filled(snapshot) -> {"light":n,"deep":n} / filled_total(snapshot) -> int
##   rows(snapshot,inventory=null) -> Array[{"id","name","tea_item","tea_name","need","filled","have","full"}]
##       （固定 STYLES 順序；have 只在給 inventory 時算，否則 -1）
##   progress(snapshot) -> {"season","jars","jars_total","jars_needed","filled","filled_total",
##       "order","ready_to_send","completed"}
##   jar_cell / fill_cell / send_cell / claim_cell (snapshot) -> Vector2i；JAR_REGION / FILL_REGION
##   jar_block(snapshot,item,inventory,token="") -> String    # 不能交這只罐的原因（不看位置）；可以時 ""
##   fill_block(snapshot,style,inventory,token="") -> String  # 不能裝這種茶的原因（不看位置）
##   send_block(snapshot,token="") -> String
##   claim_block(snapshot,inventory,token="") -> String / can_claim(snapshot,inventory,token="") -> bool
##   claimed_own(snapshot,token="") -> bool
##   public(state) -> Dictionary                   # 快照用：{"jars","filled","day","completed","done_day"}；沒紀錄時 {}
##   apply(state,token,action,p,extra,region) -> {"ok","message"}   # region＝行動者所在的地區 id
##   valid(s) -> bool                              # 存檔檢查（state.tea_revisit）
##   artifacts_valid(s) -> bool                    # 茶陶組物件與 kit 只能出現在完成之後
## Session：snapshot.tea_revisit = public(state)（沒紀錄時沒有這個鍵），
##   並只對收件人加上 tea_revisit.claimed_own（bool）。

const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="tea_revisit"
const JAR_REGION:="yingge"
const FILL_REGION:="maokong"
const POTTER:=Vector2i(20,20)    # = TeaCeramics.POTTER 鶯歌陶師的工作桌
const PACKER:=Vector2i(26,20)    # = TeaCeramics.PACKER 貓空包裝台（擋路）
const HOUSE_SITE:=Vector2i(20,22)
const HOUSE_KEY:="maokong_tea_display"
const HOUSE_DISPLAY:="tea_house_display"
const HOUSE_RECLAIM:="tea_house_reclaim"
const HOUSE_ACTIONS:=[HOUSE_DISPLAY,HOUSE_RECLAIM]
const JAR_ACTION:="tea_revisit_jar"
const FILL_ACTION:="tea_revisit_fill"
const SEND_ACTION:="tea_revisit_send"
const CLAIM_ACTION:="tea_revisit_claim"
const ACTIONS:=[JAR_ACTION,FILL_ACTION,SEND_ACTION,CLAIM_ACTION]
const RECORD_KEYS:=["claimed","completed","day","done_day","filled","jars"]
const REACH:=3.2
const TOTAL:=6
const JAR_ITEMS:=["tea_returned_jar","tea_worn_jar"]
const JAR_NAMES:={"tea_returned_jar":"回收陶罐","tea_worn_jar":"磨損陶罐","tea_jar":"陶罐","tea_spent_jar":"待修陶罐"}
const STYLES:=["light","deep"]
const STYLE_NAMES:={"light":"淺焙","deep":"深焙"}
const TEA_ITEMS:={"light":"tea_light","deep":"tea_deep"}
const TEA_NAMES:={"light":"淺焙茶","deep":"深焙茶"}
const MAX_ITEM:=1000000000
const ORDERS:={
	"spring":{"light":4,"deep":2},
	"summer":{"light":5,"deep":1},
	"autumn":{"light":2,"deep":4},
	"winter":{"light":1,"deep":5},
}
const REASONS:={
	"spring":"茶茶說，春天渡口的茶會大家想喝清香的淺焙；留兩罐深焙，給怕涼、喜歡厚一點的人。",
	"summer":"茶茶說，夏天熱，渡口的人想把淺焙泡成冷茶解渴；只備一罐深焙，給晚上想喝熱茶的人。",
	"autumn":"茶茶說，秋天轉涼，大家開始想喝暖一點的深焙；淺焙留兩罐，配點心剛好。",
	"winter":"茶茶說，冬天圍著暖爐，大家都想喝深焙；淺焙只留一罐，給喜歡清淡的人。",
}
const DISCLAIMER:="回訪情節與訂單數字為原創，非史料。"
const TITLE:="貓空與鶯歌回訪・茶罐大單"

const TEAWARE_KIND:="tea_ware"
const TEAWARE_ITEM:="tea_ware_kit"
const TEAWARE_NAME:="茶陶組"
const TEAWARE_SOURCE:="來源：貓空與鶯歌回訪"
const TEAWARE_PROJECT:="對應紀錄：茶陶合作手帳（貓空茶園與鶯歌陶坊）"
const TEAWARE_BLURB:="一只小茶壺配幾個茶杯，放在木托盤上；紀念大家把送貨回來的空罐交給陶師，裝滿一張茶罐大單。"

const NO_PLAYER:="請重新加入世界再處理茶罐大單。"
const WRONG_REGION_YINGGE:="回收空罐和領茶陶組要到鶯歌合作陶坊的陶師那裡。"
const WRONG_REGION_MAOKONG:="裝茶和寄出大單要到貓空合作茶園的包裝台。"
const NOT_READY:="先和茶茶完成兩種包裝的比較（陶罐與纖維各交貨一次、領回空罐，再和茶茶聊聊），再來幫忙這張大單。"
const WRONG_JAR_CELL:="請到陶師的工作桌交回收空罐。"
const WRONG_FILL_CELL:="請到貓空的包裝台裝茶。"
const WRONG_SEND_CELL:="請到貓空的包裝台寄出大單。"
const WRONG_CLAIM_CELL:="請到陶師的工作桌領茶陶組。"
const TOO_FAR:="再靠近一點。"
const BAD_EXTRA:="請重新操作茶罐大單。"
const ALREADY_DONE:="茶罐大單已經寄出了。"
const BAD_JAR:="請選一只回收陶罐或磨損陶罐。"
const NEW_JAR:="新罐或修好的罐還沒送過貨。請交回收罐或磨損罐。"
const SPENT_JAR:="待修罐已裝不了茶。請交回收罐或磨損罐。"
const JARS_FULL:="大單要的 6 只空罐已經收齊了。"
const NO_JAR:="你的背包裡沒有%s。"
const JAR_OK:="陶師檢查過這只%s，收進大單的空罐箱。（已收 %d／6 只）"
const BAD_STYLE:="請選淺焙或深焙。"
const ALL_FILLED:="6 罐都裝好了，在包裝台寄出這張大單吧。"
const NEED_JARS:="從鶯歌檢查好送來的空罐有 %d 只，已經裝了 %d 罐；再帶回收空罐到鶯歌交給陶師。"
const QUOTA_FULL:="這張單%s只要 %d 罐，已經裝了 %d 罐；剩下的要%s。"
const NO_TEA:="你的背包裡沒有%s。"
const FILL_OK:="裝好一罐%s。（已裝 %d／6 罐：淺焙 %d、深焙 %d）"
const NOT_FILLED:="大單要裝滿 6 罐才能寄出，現在裝了 %d 罐。"
const COMPLETE_OK:="6 罐茶寄出了！茶茶說，陶師準備了茶陶組，大家可以到鶯歌陶坊領一組帶回家。"
const NOT_DONE:="茶罐大單還沒寄出，完成後才能領茶陶組。"
const CLAIMED:="你已經領過茶陶組了。"
const BAG_FULL:="背包裡的茶陶組已經放不下了。"
const CLAIM_OK:="陶師把一組茶陶組交給你。在家園工坊的「生活」頁選它就能擺到家園；拆除會收回背包。"

# ------------------------------------------------------------------ views --

static func fresh() -> Dictionary:
	return {"jars":{"tea_returned_jar":0,"tea_worn_jar":0},"filled":{"light":0,"deep":0},"day":0,"completed":false,"done_day":0,"claimed":{}}

static func player_ready(snapshot:Dictionary,token:String="") -> bool:
	var tea:Variant=snapshot.get("tea_ceramics")
	if not tea is Dictionary:return false
	var rec:Variant
	if not token.is_empty():
		var players:Variant=tea.get("players")
		rec=players.get(token) if players is Dictionary else null
	else:
		rec=tea.get("own_record")
	return rec is Dictionary and rec.get("comparison_complete")==true

static func record(snapshot:Dictionary) -> Dictionary:
	var found:Variant=snapshot.get(STATE_KEY)
	return found if found is Dictionary else fresh()

static func completed(snapshot:Dictionary) -> bool:
	return record(snapshot).get("completed")==true

static func _day_index(snapshot:Dictionary) -> float:
	return WEATHER.day_index(snapshot.get("time",0.0))

static func today(snapshot:Dictionary) -> int:
	return int(_day_index(snapshot))+1

static func _count(raw:Variant,key:String) -> int:
	if not raw is Dictionary:return 0
	var v:Variant=raw.get(key,0)
	if not (v is int or v is float) or not is_finite(float(v)):return 0
	return maxi(0,int(v))

static func jars(snapshot:Dictionary) -> Dictionary:
	var raw:Variant=record(snapshot).get("jars")
	var out:={}
	for item:String in JAR_ITEMS:out[item]=_count(raw,item)
	return out

static func jars_total(snapshot:Dictionary) -> int:
	var total:=0
	for n in jars(snapshot).values():total+=int(n)
	return total

static func filled(snapshot:Dictionary) -> Dictionary:
	var raw:Variant=record(snapshot).get("filled")
	var out:={}
	for style:String in STYLES:out[style]=_count(raw,style)
	return out

static func filled_total(snapshot:Dictionary) -> int:
	var total:=0
	for n in filled(snapshot).values():total+=int(n)
	return total

static func order_season(snapshot:Dictionary) -> String:
	var day:=int(record(snapshot).get("day",0))
	if filled_total(snapshot)>0 and day>=1:return WEATHER.season_on_day(float(day-1))
	return WEATHER.season_on_day(_day_index(snapshot))

static func order_for(season_id:String) -> Dictionary:
	return (ORDERS.get(season_id,ORDERS.spring) as Dictionary).duplicate()

static func reason_for(season_id:String) -> String:
	return str(REASONS.get(season_id,""))

static func order(snapshot:Dictionary) -> Dictionary:
	return order_for(order_season(snapshot))

static func reason(snapshot:Dictionary) -> String:
	return reason_for(order_season(snapshot))

static func jar_cell(_snapshot:Dictionary={}) -> Vector2i:
	return POTTER

static func claim_cell(_snapshot:Dictionary={}) -> Vector2i:
	return POTTER

static func fill_cell(_snapshot:Dictionary={}) -> Vector2i:
	return PACKER

static func send_cell(_snapshot:Dictionary={}) -> Vector2i:
	return PACKER

static func rows(snapshot:Dictionary,inventory:Variant=null) -> Array:
	var need:=order(snapshot)
	var done:=filled(snapshot)
	var out:=[]
	for style:String in STYLES:
		var item:String=TEA_ITEMS[style]
		out.append({"id":style,"name":str(STYLE_NAMES[style]),"tea_item":item,"tea_name":str(TEA_NAMES[style]),
			"need":int(need[style]),"filled":int(done[style]),
			"have":int(inventory.get(item,0)) if inventory is Dictionary else -1,
			"full":int(done[style])>=int(need[style])})
	return out

static func progress(snapshot:Dictionary) -> Dictionary:
	return {"season":order_season(snapshot),"jars":jars(snapshot),"jars_total":jars_total(snapshot),"jars_needed":TOTAL,
		"filled":filled(snapshot),"filled_total":filled_total(snapshot),"order":order(snapshot),
		"ready_to_send":not completed(snapshot) and filled_total(snapshot)>=TOTAL,"completed":completed(snapshot)}

static func _other(style:String) -> String:
	return "deep" if style=="light" else "light"

static func jar_block(snapshot:Dictionary,item:String,inventory:Variant,token:String="") -> String:
	if not player_ready(snapshot,token):return NOT_READY
	return _jar_problem(snapshot,item,inventory)

static func _jar_problem(snapshot:Dictionary,item:String,inventory:Variant) -> String:
	if completed(snapshot):return ALREADY_DONE
	if item=="tea_jar":return NEW_JAR
	if item=="tea_spent_jar":return SPENT_JAR
	if item not in JAR_ITEMS:return BAD_JAR
	if jars_total(snapshot)>=TOTAL:return JARS_FULL
	var have:=int(inventory.get(item,0)) if inventory is Dictionary else 0
	if have<1:return NO_JAR%str(JAR_NAMES[item])
	return ""

static func fill_block(snapshot:Dictionary,style:String,inventory:Variant,token:String="") -> String:
	if not player_ready(snapshot,token):return NOT_READY
	return _fill_problem(snapshot,style,inventory)

static func _fill_problem(snapshot:Dictionary,style:String,inventory:Variant) -> String:
	if completed(snapshot):return ALREADY_DONE
	if style not in STYLES:return BAD_STYLE
	var done:=filled(snapshot)
	var total:=filled_total(snapshot)
	if total>=TOTAL:return ALL_FILLED
	var have_jars:=jars_total(snapshot)
	if total>=have_jars:return NEED_JARS%[have_jars,total]
	var need:=int(order(snapshot)[style])
	if int(done[style])>=need:return QUOTA_FULL%[str(STYLE_NAMES[style]),need,int(done[style]),str(STYLE_NAMES[_other(style)])]
	var item:String=TEA_ITEMS[style]
	var have:=int(inventory.get(item,0)) if inventory is Dictionary else 0
	if have<1:return NO_TEA%str(TEA_NAMES[style])
	return ""

static func send_block(snapshot:Dictionary,token:String="") -> String:
	if not player_ready(snapshot,token):return NOT_READY
	return _send_problem(snapshot)

static func _send_problem(snapshot:Dictionary) -> String:
	if completed(snapshot):return ALREADY_DONE
	var total:=filled_total(snapshot)
	if total<TOTAL:return NOT_FILLED%total
	var need:=order(snapshot)
	var done:=filled(snapshot)
	for style:String in STYLES:
		if int(done[style])!=int(need[style]):return NOT_FILLED%total
	return ""

static func claimed_own(snapshot:Dictionary,token:String="") -> bool:
	var found:Variant=snapshot.get(STATE_KEY)
	if not found is Dictionary:return false
	if not token.is_empty():
		var claimed:Variant=found.get("claimed")
		if claimed is Dictionary:return claimed.has(token)
	return found.get("claimed_own")==true

static func claim_block(snapshot:Dictionary,inventory:Variant,token:String="") -> String:
	if not player_ready(snapshot,token):return NOT_READY
	if not completed(snapshot):return NOT_DONE
	if claimed_own(snapshot,token):return CLAIMED
	if inventory is Dictionary and int(inventory.get(TEAWARE_ITEM,0))>=MAX_ITEM:return BAG_FULL
	return ""

static func can_claim(snapshot:Dictionary,inventory:Variant,token:String="") -> bool:
	return claim_block(snapshot,inventory,token).is_empty()

static func public(state:Dictionary) -> Dictionary:
	var found:Variant=state.get(STATE_KEY)
	if not found is Dictionary:return {}
	return {"jars":jars(state),"filled":filled(state),"day":int(found.get("day",0)),
		"completed":found.get("completed")==true,"done_day":int(found.get("done_day",0))}

# ------------------------------------------------------------------ action --

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _distance(person:Dictionary,cell:Vector2i) -> float:
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))

## World passes region (the actor's current region id). Every check runs before any
## write, so a failure leaves the whole state unchanged.
static func apply(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,region:String) -> Dictionary:
	if action not in ACTIONS:return _fail(BAD_EXTRA)
	var people:Variant=state.get("players",{})
	if not people is Dictionary or not people.get(token) is Dictionary:return _fail(NO_PLAYER)
	var person:Dictionary=people[token]
	var at_yingge:=action in [JAR_ACTION,CLAIM_ACTION]
	if at_yingge and region!=JAR_REGION:return _fail(WRONG_REGION_YINGGE)
	if not at_yingge and region!=FILL_REGION:return _fail(WRONG_REGION_MAOKONG)
	if not player_ready(state,token):return _fail(NOT_READY)
	if state.has(STATE_KEY) and not _shape_ok(state[STATE_KEY]):return _fail(BAD_EXTRA)
	var target:=POTTER if at_yingge else PACKER
	if p!=target:
		match action:
			JAR_ACTION:return _fail(WRONG_JAR_CELL)
			FILL_ACTION:return _fail(WRONG_FILL_CELL)
			SEND_ACTION:return _fail(WRONG_SEND_CELL)
		return _fail(WRONG_CLAIM_CELL)
	if _distance(person,target)>REACH:return _fail(TOO_FAR)
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inv:Dictionary=person.inventory
	match action:
		JAR_ACTION:return _jar(state,extra,inv)
		FILL_ACTION:return _fill(state,extra,inv)
	if not extra.is_empty():return _fail(BAD_EXTRA)
	if action==SEND_ACTION:return _send(state)
	return _claim(state,token,inv)

static func _jar(state:Dictionary,item:String,inv:Dictionary) -> Dictionary:
	var block:=_jar_problem(state,item,inv)
	if not block.is_empty():return _fail(block)
	var own:Dictionary=record(state).duplicate(true)
	var now:=jars(state)
	now[item]=int(now[item])+1
	own.jars=now
	state[STATE_KEY]=own
	inv[item]=int(inv.get(item,0))-1
	return {"ok":true,"message":JAR_OK%[str(JAR_NAMES[item]),jars_total(state)]}

static func _fill(state:Dictionary,style:String,inv:Dictionary) -> Dictionary:
	var block:=_fill_problem(state,style,inv)
	if not block.is_empty():return _fail(block)
	var own:Dictionary=record(state).duplicate(true)
	var done:=filled(state)
	if filled_total(state)==0:own.day=today(state)
	done[style]=int(done[style])+1
	own.filled=done
	state[STATE_KEY]=own
	var item:String=TEA_ITEMS[style]
	inv[item]=int(inv.get(item,0))-1
	return {"ok":true,"message":FILL_OK%[str(TEA_NAMES[style]),filled_total(state),int(done.light),int(done.deep)]}

static func _send(state:Dictionary) -> Dictionary:
	var block:=_send_problem(state)
	if not block.is_empty():return _fail(block)
	var own:Dictionary=record(state).duplicate(true)
	own.completed=true
	own.done_day=today(state)
	state[STATE_KEY]=own
	return {"ok":true,"message":COMPLETE_OK}

static func _claim(state:Dictionary,token:String,inv:Dictionary) -> Dictionary:
	if not completed(state):return _fail(NOT_DONE)
	if claimed_own(state,token):return _fail(CLAIMED)
	if int(inv.get(TEAWARE_ITEM,0))>=MAX_ITEM:return _fail(BAG_FULL)
	var own:Dictionary=state[STATE_KEY]
	own.claimed[token]=true
	inv[TEAWARE_ITEM]=int(inv.get(TEAWARE_ITEM,0))+1
	return {"ok":true,"message":CLAIM_OK}

static func _counts_ok(raw:Variant,keys:Array) -> bool:
	if not raw is Dictionary or raw.size()!=keys.size():return false
	for key:String in keys:
		if not raw.has(key):return false
		var v:Variant=raw[key]
		if not (v is int or v is float) or not is_finite(float(v)):return false
	return true

## Runtime shape check (full consistency is valid()'s job at load time).
static func _shape_ok(own:Variant) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field:String in RECORD_KEYS:
		if not own.has(field):return false
	if not _counts_ok(own.jars,JAR_ITEMS) or not _counts_ok(own.filled,STYLES):return false
	return own.claimed is Dictionary and own.completed is bool

# ------------------------------------------------------------------ schema --

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

## state.tea_revisit (optional). Exact keys; jars exactly the two recycled jar kinds and
## filled exactly light/deep, every count a whole number; jars total <= 6; filled total
## <= jars total; day/done_day 0..today; day==0 <=> nothing filled; once day>0 each style
## <= the order of day's season; completed <=> done_day>0, completed => 6 filled (which then
## matches the order), done_day >= day; at least one known player finished the tea
## comparison (only such players can write the record); claimed only after completion,
## values true, keys known players with comparison_complete. Must run after
## TeaCeramics.valid. Normalises JSON floats to int on success.
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var own:Variant=s[STATE_KEY]
	if not _shape_ok(own):return false
	var now_day:=int(WEATHER.day_index(s.get("time",0.0)))+1
	var jar_total:=0
	for item:String in JAR_ITEMS:
		if not _whole(own.jars[item],0,TOTAL):return false
		jar_total+=int(own.jars[item])
	if jar_total>TOTAL:return false
	var fill_total:=0
	for style:String in STYLES:
		if not _whole(own.filled[style],0,TOTAL):return false
		fill_total+=int(own.filled[style])
	if fill_total>jar_total:return false
	if not _whole(own.day,0,now_day) or not _whole(own.done_day,0,now_day):return false
	if (int(own.day)==0)!=(fill_total==0):return false
	if int(own.day)>0:
		var wanted:=order_for(WEATHER.season_on_day(float(int(own.day)-1)))
		for style:String in STYLES:
			if int(own.filled[style])>int(wanted[style]):return false
	if own.completed!=(int(own.done_day)>0):return false
	# 六罐裝滿但還沒寄出是正常的中間狀態（可存檔）；只有「已完成」必須是六罐。
	if own.completed and fill_total!=TOTAL:return false
	if own.completed and int(own.done_day)<int(own.day):return false
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var anyone:=false
	for token in players:
		if player_ready(s,str(token)):anyone=true
	if not anyone:return false
	for token in own.claimed:
		if not own.completed or not token is String or own.claimed[token]!=true:return false
		if not players.has(token) or not player_ready(s,token):return false
	for item:String in JAR_ITEMS:own.jars[item]=int(own.jars[item])
	for style:String in STYLES:own.filled[style]=int(own.filled[style])
	own.day=int(own.day)
	own.done_day=int(own.done_day)
	return true

## Placed tea ware and tea ware kits exist only after the revisit. Checks home and every
## regional object layer (placed objects and container items) plus every player's inventory.
static func artifacts_valid(s:Dictionary) -> bool:
	if completed(s):return true
	var layers:=[s.get("objects",{})]
	var regions:Variant=s.get("regions",{})
	if regions is Dictionary:
		for region in regions:
			var local:Variant=regions[region]
			if local is Dictionary:layers.append(local.get("objects",{}))
	for layer:Variant in layers:
		if not layer is Dictionary:continue
		for obj:Variant in layer.values():
			if not obj is Dictionary:continue
			if str(obj.get("type",""))==TEAWARE_KIND:return false
			var items:Variant=obj.get("items")
			if items is Dictionary and int(items.get(TEAWARE_ITEM,0))!=0:return false
	var players:Variant=s.get("players",{})
	if players is Dictionary:
		for token in players:
			var person:Variant=players[token]
			if person is Dictionary and person.get("inventory") is Dictionary and int(person.inventory.get(TEAWARE_ITEM,0))!=0:return false
	return true

static func house_open(s:Dictionary) -> bool:
	return completed(s) and (s.get("festival_story_open",false)==true or s.get("festival_story",{}).get("opened",false)==true)

static func house_valid(s:Dictionary) -> bool:
	if not s.has(HOUSE_KEY):return true
	var display:Variant=s[HOUSE_KEY]
	return s.get("festival_story_open",false)==true and completed(s) and display is Dictionary \
		and display.get("lender") is String and s.players.has(display.lender)

static func house_action(s:Dictionary,token:String,action:String,cell:Vector2i,extra:String,region:String) -> Dictionary:
	if region!=FILL_REGION or cell!=HOUSE_SITE or not extra.is_empty():return _fail("請到貓空茶屋的展示桌旁。")
	if not house_open(s):return _fail("風鈴節開幕並完成茶罐大單後，就能布置茶屋。")
	var display:Dictionary=s.get(HOUSE_KEY,{})
	var inventory:Dictionary=s.players[token].inventory
	var held:=int(inventory.get(TEAWARE_ITEM,0))
	if action==HOUSE_DISPLAY:
		if not display.is_empty():return {"ok":false,"message":"桌上已經展出一組茶陶。"}
		if held<1:return {"ok":false,"message":"帶一組茶陶組來，就可以借給茶屋展出。"}
		inventory[TEAWARE_ITEM]=held-1
		s[HOUSE_KEY]={"lender":token}
		return {"ok":true,"message":"茶陶組已擺上茶屋展示桌，來客現在都看得到了。"}
	if display.get("lender","")!=token:return {"ok":false,"message":"出借茶陶組的島民可以收回。"}
	if held>=MAX_ITEM:return {"ok":false,"message":"背包的茶陶組已達上限。"}
	inventory[TEAWARE_ITEM]=held+1
	s.erase(HOUSE_KEY)
	return {"ok":true,"message":"茶陶組已收回背包。"}
