extends RefCounted
## 規劃書第 40 章「臺南北門回訪・鹽籃批次」：用合作社的倉棚（阿曬）、收鹽箱與海邊公車站安排
## 一批 6 籃的鹽；雨天倉棚不收散鹽，大家改在棚下裝籃（雨天轉做包裝），裝好的鹽分料理用與
## 醃漬用兩種，最後在海邊公車站出貨。完成後全島永久完成；每位在北門親手收過鹽的島民可在阿曬
## 那裡領一只「鹽籃」(salt_basket_kit) 帶回家擺放（保留鹽籃供展示）。鹽籃只是裝飾。
##
## 回訪情節與訂單數字為原創（DISCLAIMER），非史料；沒有新增任何北門、井仔腳的史實敘述。
## 三個地點都是遊戲裡既有的北門點位（阿曬 SALT_WORKER、合作社收鹽箱 APPRENTICE_CHEST、
## 海邊公車站 TRANSFER）。規劃書提到的儲滷槽沒有做成獨立的裝置：一「批」就是入倉的 3 份海鹽；
## 海鹽本身來自手收或水車＋收鹽台（salt_pan.gd，行為不變）。
##
## 純規則：不讀檔、不看現實時鐘、不用亂數；只看 state.time（WEATHER 曆法；北門是戶外，用
## WEATHER.rains(day,"beimen")）。失敗時 state 完全不變（先檢查完全部條件，最後才寫入）。
## 不 preload World / salt_pan.gd（避免循環；直接讀 state.salt_pan）。
##
## ── 前提
##   世界：北門合作鹽田三道閘門都修好（伺服器 state.salt_pan.repaired_at>=0；用戶端快照
##         salt_pan.repaired==true）。之前每個動作都回 LOCKED。
##   本人：在北門親手收過鹽（伺服器 state.salt_pan.players[token].raked>=1；用戶端快照
##         salt_pan.own.record.raked>=1）。沒收過的人（含後來加入的島民）→ NOT_READY。
##
## ── 世界紀錄 state.salt_revisit（可省略；第一次成功動作才寫入，舊存檔不需遷移，不升版）
##   {"stocked":{"sunny":n,"cloudy":n},   # 入倉的批數，依入倉那天北門的天氣（雨天不能入倉）
##    "packed":{"kitchen":n,"pickle":n},   # 已裝好的籃數（料理用／醃漬用）
##    "rain_packs":int,        # 其中在下雨天裝的籃數
##    "day":int,               # 第一次裝籃的世界日（= 這批訂單的日子）；還沒裝時 0
##    "completed":bool,        # 6 籃送出 → 永久 true
##    "done_day":int,          # 送出（完成）的世界日；未完成時 0
##    "claimed":{token:true}}  # 已領鹽籃的島民（只在伺服器；公開快照不含）
##   不記錄是誰入倉、誰裝籃、誰送出（沒有 token）。
##   訂單：還沒裝籃時看「今天」的季節；第一次裝籃後鎖定為 day 那天的季節（之後換季也不變）。
##
## ── 訂單（依季節；WEATHER.season_on_day）ORDERS / REASONS（阿曬各一句原創理由）；一共 6 籃
##   spring 料理用 3／醃漬用 3、summer 2／4、autumn 4／2、winter 5／1
##   一批（LOT_SALT=3 份海鹽）裝一籃；一籃另用纖維 FIBER_PER_BASKET=2 份。完成一次共用掉
##   海鹽 18 份、纖維 12 份（各由入倉、裝籃的人從自己背包付）。
##
## ── 地點（REGION="beimen"；REACH=3.2，與一般互動相同；都是 World.protected 的既有點位）
##   入倉、領鹽籃＝阿曬 WORKER (44,17)（擋路；站在 (44.5,18.5) 一帶）
##   裝籃＝合作社收鹽箱 CHEST (47,23)（擋路；站在 (47.5,24.5) 一帶）
##   出貨＝海邊公車站 STOP (48,25)（擋路；站在抵達點 (47.5,25.5) 一帶）
##   注意：收鹽箱與公車站彼此很近，抵達點 (47.5,25.5) 和 (47.5,24.5) 都同時搆得到兩者；
##   阿曬離抵達點較遠（要走到工寮前）。test_salt_revisit 以 flood-fill 驗證三個站位都能從抵達點走到。
##
## ── 動作（World._apply 在 TEA_REVISIT 之後、一般距離檢查之前轉給 apply()）
##   salt_revisit_stock  p＝WORKER，extra＝""：背包海鹽 -3、stocked[今天天氣]+1（最多 6 批）。
##                       北門今天下雨 → RAIN_STOCK（已入倉的鹽照樣可以裝籃）。
##   salt_revisit_pack   p＝CHEST，extra＝"kitchen" 或 "pickle"：背包纖維 -2、packed[kind]+1；
##                       任何天氣都可以；已裝籃數 < 已入倉批數；這種用途還沒裝滿訂單。
##                       第一次裝籃寫入 day＝今天；下雨天裝的另記 rain_packs+1。
##   salt_revisit_send   p＝STOP，extra＝""：6 籃都裝好（必然符合訂單）→ completed、done_day＝今天。
##   salt_revisit_claim  p＝WORKER，extra＝""：completed 之後每人一次，背包 +1 salt_basket_kit。
##   任何（親手收過鹽的）人都可以做任何一步，可以分頭進行。
##   檢查順序：BAD_EXTRA（不是本模組的動作）→ NO_PLAYER → WRONG_REGION → LOCKED → NOT_READY →
##     BAD_EXTRA（紀錄壞掉）→ WRONG_STOCK_CELL / WRONG_PACK_CELL / WRONG_SEND_CELL / WRONG_CLAIM_CELL →
##     TOO_FAR →
##     stock：BAD_EXTRA（extra 非空）→ ALREADY_DONE → STOCK_FULL → RAIN_STOCK → NO_SALT%[3,持有]
##     pack ：ALREADY_DONE → BAD_KIND → ALL_PACKED → NEED_STOCK%[已入倉,已裝] →
##            QUOTA_FULL%[用途,訂單數,已裝,另一種用途] → NO_FIBER%[2,持有]
##     send ：BAD_EXTRA（extra 非空）→ ALREADY_DONE → NOT_PACKED%已裝
##     claim：BAD_EXTRA（extra 非空）→ NOT_DONE → CLAIMED → BAG_FULL
##   成功訊息：STOCK_OK%[3,天氣,已入倉]、PACK_OK%[用途,已裝,料理用,醃漬用]（雨天再接 PACK_RAIN_NOTE）、
##     COMPLETE_OK、CLAIM_OK。
##
## ── 鹽籃（家園裝飾，與茶陶組、礦燈、分水木牌相同的規則）
##   背包物品 BASKET_ITEM="salt_basket_kit"，建造種類 BASKET_KIND="salt_basket"
##   (World.BUILD 名稱「鹽籃」)：不擋路、拆除退回 kit、可搬移、可放箱子；沒有價目
##   （不能出貨、不能在攤位賣、不能上市集），World.trade_items() 排除（不能交易）。
##   BASKET_NAME / BASKET_SOURCE / BASKET_PROJECT / BASKET_BLURB 給介面顯示來源。
##
## ── 介面用的純函式（snapshot 可以是伺服器 state 或用戶端快照；token 只在伺服器 state 有用，
##    用戶端快照用 salt_pan.repaired、salt_pan.own.record.raked 與 salt_revisit.claimed_own）
##   unlocked(snapshot) -> bool                    # 三道閘門都修好
##   player_ready(snapshot,token="") -> bool       # 本人在北門親手收過鹽
##   record(snapshot) -> Dictionary                # 唯讀；沒有時 fresh()
##   completed(snapshot) -> bool / today(snapshot) -> int
##   weather_today(snapshot) -> String（"sunny"/"cloudy"/"rainy"）/ rainy_today(snapshot) -> bool
##   order_season(snapshot) -> String              # 這批訂單的季節（已裝籃時鎖定為 day 那天）
##   order(snapshot) -> {"kitchen":n,"pickle":n} / order_for(season) / reason(snapshot) / reason_for(season)
##   stocked(snapshot) -> {"sunny":n,"cloudy":n} / stocked_total(snapshot) -> int
##   packed(snapshot) -> {"kitchen":n,"pickle":n} / packed_total(snapshot) -> int / rain_packs(snapshot) -> int
##   rows(snapshot,inventory=null) -> Array[{"id","name","need","packed","full","fiber"}]
##       （固定 KINDS 順序；fiber＝背包纖維數，只在給 inventory 時算，否則 -1）
##   progress(snapshot) -> {"season","stocked","stocked_total","lots_needed","packed","packed_total",
##       "rain_packs","order","rainy_today","ready_to_send","completed"}
##   stock_cell / pack_cell / send_cell / claim_cell (snapshot) -> Vector2i；REGION
##   WORKER_STAND / CHEST_STAND / STOP_STAND（測試過的站位）
##   stock_block(snapshot,inventory,token="") -> String       # 不能入倉的原因（不看位置）；可以時 ""
##   pack_block(snapshot,kind,inventory,token="") -> String   # 不能裝這種籃的原因（不看位置）
##   send_block(snapshot,token="") -> String
##   claim_block(snapshot,inventory,token="") -> String / can_claim(snapshot,inventory,token="") -> bool
##   （各 *_block 的第一個原因：LOCKED → NOT_READY；位置的原因由 apply 回 WRONG_*_CELL，文字指出要站在哪）
##   claimed_own(snapshot,token="") -> bool
##   public(state) -> Dictionary   # 快照用：{"stocked","packed","rain_packs","day","completed","done_day"}；沒紀錄時 {}
##   apply(state,token,action,p,extra,region) -> {"ok","message"}   # region＝行動者所在的地區 id
##   valid(s) -> bool                              # 存檔檢查（state.salt_revisit）
##   artifacts_valid(s) -> bool                    # 鹽籃物件與 kit 只能出現在完成之後
## Session：snapshot.salt_revisit = public(state)（沒紀錄時沒有這個鍵），
##   並只對收件人加上 salt_revisit.claimed_own（bool）。

const WEATHER=preload("res://scripts/weather.gd")

const STATE_KEY:="salt_revisit"
const REGION:="beimen"
const WORKER:=Vector2i(44,17)    # = SaltPan.SALT_WORKER 阿曬（合作社工寮前）
const CHEST:=Vector2i(47,23)     # = SaltPan.APPRENTICE_CHEST 合作社收鹽箱
const STOP:=Vector2i(48,25)      # = SaltPan.TRANSFER 海邊公車站
const WORKER_STAND:=Vector2(44.5,18.5)
const CHEST_STAND:=Vector2(47.5,24.5)
const STOP_STAND:=Vector2(47.5,25.5)   # = SaltPan.ARRIVAL
const STOCK_ACTION:="salt_revisit_stock"
const PACK_ACTION:="salt_revisit_pack"
const SEND_ACTION:="salt_revisit_send"
const CLAIM_ACTION:="salt_revisit_claim"
const ACTIONS:=[STOCK_ACTION,PACK_ACTION,SEND_ACTION,CLAIM_ACTION]
const RECORD_KEYS:=["claimed","completed","day","done_day","packed","rain_packs","stocked"]
const REACH:=3.2
const TOTAL:=6
const LOT_SALT:=3
const FIBER_PER_BASKET:=2
const SALT_ITEM:="sea_salt"
const FIBER_ITEM:="fiber"
const STOCK_WEATHERS:=["sunny","cloudy"]
const KINDS:=["kitchen","pickle"]
const KIND_NAMES:={"kitchen":"料理用","pickle":"醃漬用"}
const MAX_ITEM:=1000000000
const ORDERS:={
	"spring":{"kitchen":3,"pickle":3},
	"summer":{"kitchen":2,"pickle":4},
	"autumn":{"kitchen":4,"pickle":2},
	"winter":{"kitchen":5,"pickle":1},
}
const REASONS:={
	"spring":"阿曬說，春天各家的灶上和醃菜甕都要用鹽，料理用和醃漬用各裝三籃剛剛好。",
	"summer":"阿曬說，夏天菜和魚放不久，大家想多醃一點，醃漬用的要四籃；料理用的兩籃就夠。",
	"autumn":"阿曬說，秋天收成多、灶上忙，料理用的鹽要四籃；醃漬用的留兩籃。",
	"winter":"阿曬說，冬天大家圍著爐子煮熱湯，料理用的要五籃；醃漬用的只留一籃。",
}
const DISCLAIMER:="回訪情節與訂單數字為原創，非史料。"
const TITLE:="臺南北門回訪・鹽籃批次"

const BASKET_KIND:="salt_basket"
const BASKET_ITEM:="salt_basket_kit"
const BASKET_NAME:="鹽籃"
const BASKET_SOURCE:="來源：臺南北門回訪"
const BASKET_PROJECT:="對應工程：北門合作鹽田閘門修復"
const BASKET_BLURB:="一只編得密密的小竹籃，裝著一把白白的海鹽；紀念大家在北門把鹽入倉、裝籃，送出一批鹽籃。"

const NO_PLAYER:="請重新加入世界再處理鹽籃批次。"
const WRONG_REGION:="鹽籃批次在北門合作鹽田：入倉和領鹽籃找阿曬，裝籃在合作社收鹽箱旁，出貨在海邊公車站。"
const LOCKED:="北門合作鹽田的三道閘門修好之後，阿曬才會安排鹽籃批次。"
const NOT_READY:="先在北門的保留手作池親手收一次鹽（引海水、等鹽結成、再收起來），再來幫忙鹽籃批次。"
const WRONG_STOCK_CELL:="請到合作社工寮前找阿曬入倉。"
const WRONG_PACK_CELL:="請到合作社收鹽箱旁裝籃。"
const WRONG_SEND_CELL:="請到海邊公車站送出鹽籃。"
const WRONG_CLAIM_CELL:="請到合作社工寮前找阿曬領鹽籃。"
const TOO_FAR:="再靠近一點。"
const BAD_EXTRA:="請重新操作鹽籃批次。"
const ALREADY_DONE:="鹽籃批次已經送出了。"
const STOCK_FULL:="這批要的 6 批散鹽已經都入倉了。"
const RAIN_STOCK:="下雨天倉棚不收散鹽，怕受潮；已經入倉的鹽可以先裝籃。"
const NO_SALT:="入倉一批要海鹽 %d 份，你的背包裡有 %d 份。"
const STOCK_OK:="阿曬把 %d 份海鹽收進倉棚，記成%s入倉的一批。（已入倉 %d／6 批）"
const BAD_KIND:="請選料理用或醃漬用。"
const ALL_PACKED:="6 籃都裝好了，到海邊公車站送出吧。"
const NEED_STOCK:="倉棚裡入倉的散鹽有 %d 批，已經裝了 %d 籃；先帶海鹽找阿曬入倉。"
const QUOTA_FULL:="這批%s只要 %d 籃，已經裝了 %d 籃；剩下的要%s。"
const NO_FIBER:="裝一籃要纖維 %d 份（編籃、綁口），你的背包裡有 %d 份。"
const PACK_OK:="裝好一籃%s的鹽。（已裝 %d／6 籃：料理用 %d、醃漬用 %d）"
const PACK_RAIN_NOTE:="今天下雨，在倉棚下裝籃正好。"
const NOT_PACKED:="鹽籃要裝滿 6 籃才能送出，現在裝了 %d 籃。"
const COMPLETE_OK:="6 籃鹽送上沿海公車了！阿曬說，合作社留了幾只鹽籃，大家可以到工寮前領一只帶回家。"
const NOT_DONE:="鹽籃批次還沒送出，完成後才能領鹽籃。"
const CLAIMED:="你已經領過鹽籃了。"
const BAG_FULL:="背包裡的鹽籃已經放不下了。"
const CLAIM_OK:="阿曬把一只鹽籃交給你。在家園工坊的「生活」頁選它就能擺到家園；拆除會收回背包。"

# ------------------------------------------------------------------ views --

static func fresh() -> Dictionary:
	return {"stocked":{"sunny":0,"cloudy":0},"packed":{"kitchen":0,"pickle":0},"rain_packs":0,"day":0,"completed":false,"done_day":0,"claimed":{}}

static func _number(v:Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func unlocked(snapshot:Dictionary) -> bool:
	var salt:Variant=snapshot.get("salt_pan")
	if not salt is Dictionary:return false
	if salt.has("repaired_at"):
		var at:Variant=salt.repaired_at
		return _number(at) and float(at)>=0.0
	return salt.get("repaired")==true

static func player_ready(snapshot:Dictionary,token:String="") -> bool:
	var salt:Variant=snapshot.get("salt_pan")
	if not salt is Dictionary:return false
	var rec:Variant
	if not token.is_empty():
		var players:Variant=salt.get("players")
		rec=players.get(token) if players is Dictionary else null
	else:
		var own:Variant=salt.get("own")
		rec=own.get("record") if own is Dictionary else null
	if not rec is Dictionary:return false
	var raked:Variant=rec.get("raked")
	return _number(raked) and float(raked)>=1.0

static func record(snapshot:Dictionary) -> Dictionary:
	var found:Variant=snapshot.get(STATE_KEY)
	return found if found is Dictionary else fresh()

static func completed(snapshot:Dictionary) -> bool:
	return record(snapshot).get("completed")==true

static func _day_index(snapshot:Dictionary) -> float:
	return WEATHER.day_index(snapshot.get("time",0.0))

static func today(snapshot:Dictionary) -> int:
	return int(_day_index(snapshot))+1

## Beimen's (outdoor) weather id today.
static func weather_today(snapshot:Dictionary) -> String:
	return str(WEATHER.at(WEATHER.safe_time(snapshot.get("time",0.0)),REGION).id)

static func rainy_today(snapshot:Dictionary) -> bool:
	return WEATHER.rains(_day_index(snapshot),REGION)

static func _count(raw:Variant,key:String) -> int:
	if not raw is Dictionary:return 0
	var v:Variant=raw.get(key,0)
	if not _number(v):return 0
	return maxi(0,int(v))

static func stocked(snapshot:Dictionary) -> Dictionary:
	var raw:Variant=record(snapshot).get("stocked")
	var out:={}
	for w:String in STOCK_WEATHERS:out[w]=_count(raw,w)
	return out

static func stocked_total(snapshot:Dictionary) -> int:
	var total:=0
	for n in stocked(snapshot).values():total+=int(n)
	return total

static func packed(snapshot:Dictionary) -> Dictionary:
	var raw:Variant=record(snapshot).get("packed")
	var out:={}
	for kind:String in KINDS:out[kind]=_count(raw,kind)
	return out

static func packed_total(snapshot:Dictionary) -> int:
	var total:=0
	for n in packed(snapshot).values():total+=int(n)
	return total

static func rain_packs(snapshot:Dictionary) -> int:
	var v:Variant=record(snapshot).get("rain_packs",0)
	return maxi(0,int(v)) if _number(v) else 0

static func order_season(snapshot:Dictionary) -> String:
	var day:Variant=record(snapshot).get("day",0)
	var d:=int(day) if _number(day) else 0
	if packed_total(snapshot)>0 and d>=1:return WEATHER.season_on_day(float(d-1))
	return WEATHER.season_on_day(_day_index(snapshot))

static func order_for(season_id:String) -> Dictionary:
	return (ORDERS.get(season_id,ORDERS.spring) as Dictionary).duplicate()

static func reason_for(season_id:String) -> String:
	return str(REASONS.get(season_id,""))

static func order(snapshot:Dictionary) -> Dictionary:
	return order_for(order_season(snapshot))

static func reason(snapshot:Dictionary) -> String:
	return reason_for(order_season(snapshot))

static func stock_cell(_snapshot:Dictionary={}) -> Vector2i:
	return WORKER

static func claim_cell(_snapshot:Dictionary={}) -> Vector2i:
	return WORKER

static func pack_cell(_snapshot:Dictionary={}) -> Vector2i:
	return CHEST

static func send_cell(_snapshot:Dictionary={}) -> Vector2i:
	return STOP

static func rows(snapshot:Dictionary,inventory:Variant=null) -> Array:
	var need:=order(snapshot)
	var done:=packed(snapshot)
	var out:=[]
	for kind:String in KINDS:
		out.append({"id":kind,"name":str(KIND_NAMES[kind]),"need":int(need[kind]),"packed":int(done[kind]),
			"full":int(done[kind])>=int(need[kind]),
			"fiber":int(inventory.get(FIBER_ITEM,0)) if inventory is Dictionary else -1})
	return out

static func progress(snapshot:Dictionary) -> Dictionary:
	return {"season":order_season(snapshot),"stocked":stocked(snapshot),"stocked_total":stocked_total(snapshot),"lots_needed":TOTAL,
		"packed":packed(snapshot),"packed_total":packed_total(snapshot),"rain_packs":rain_packs(snapshot),"order":order(snapshot),
		"rainy_today":rainy_today(snapshot),
		"ready_to_send":not completed(snapshot) and packed_total(snapshot)>=TOTAL,"completed":completed(snapshot)}

static func _other(kind:String) -> String:
	return "pickle" if kind=="kitchen" else "kitchen"

static func _common_block(snapshot:Dictionary,token:String) -> String:
	if not unlocked(snapshot):return LOCKED
	if not player_ready(snapshot,token):return NOT_READY
	return ""

static func stock_block(snapshot:Dictionary,inventory:Variant,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	return _stock_problem(snapshot,inventory)

static func _stock_problem(snapshot:Dictionary,inventory:Variant) -> String:
	if completed(snapshot):return ALREADY_DONE
	if stocked_total(snapshot)>=TOTAL:return STOCK_FULL
	if rainy_today(snapshot):return RAIN_STOCK
	var have:=int(inventory.get(SALT_ITEM,0)) if inventory is Dictionary else 0
	if have<LOT_SALT:return NO_SALT%[LOT_SALT,maxi(0,have)]
	return ""

static func pack_block(snapshot:Dictionary,kind:String,inventory:Variant,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	return _pack_problem(snapshot,kind,inventory)

static func _pack_problem(snapshot:Dictionary,kind:String,inventory:Variant) -> String:
	if completed(snapshot):return ALREADY_DONE
	if kind not in KINDS:return BAD_KIND
	var done:=packed(snapshot)
	var total:=packed_total(snapshot)
	if total>=TOTAL:return ALL_PACKED
	var lots:=stocked_total(snapshot)
	if total>=lots:return NEED_STOCK%[lots,total]
	var need:=int(order(snapshot)[kind])
	if int(done[kind])>=need:return QUOTA_FULL%[str(KIND_NAMES[kind]),need,int(done[kind]),str(KIND_NAMES[_other(kind)])]
	var have:=int(inventory.get(FIBER_ITEM,0)) if inventory is Dictionary else 0
	if have<FIBER_PER_BASKET:return NO_FIBER%[FIBER_PER_BASKET,maxi(0,have)]
	return ""

static func send_block(snapshot:Dictionary,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	return _send_problem(snapshot)

static func _send_problem(snapshot:Dictionary) -> String:
	if completed(snapshot):return ALREADY_DONE
	var total:=packed_total(snapshot)
	if total<TOTAL:return NOT_PACKED%total
	var need:=order(snapshot)
	var done:=packed(snapshot)
	for kind:String in KINDS:
		if int(done[kind])!=int(need[kind]):return NOT_PACKED%total
	return ""

static func claimed_own(snapshot:Dictionary,token:String="") -> bool:
	var found:Variant=snapshot.get(STATE_KEY)
	if not found is Dictionary:return false
	if not token.is_empty():
		var claimed:Variant=found.get("claimed")
		if claimed is Dictionary:return claimed.has(token)
	return found.get("claimed_own")==true

static func claim_block(snapshot:Dictionary,inventory:Variant,token:String="") -> String:
	var common:=_common_block(snapshot,token)
	if not common.is_empty():return common
	if not completed(snapshot):return NOT_DONE
	if claimed_own(snapshot,token):return CLAIMED
	if inventory is Dictionary and int(inventory.get(BASKET_ITEM,0))>=MAX_ITEM:return BAG_FULL
	return ""

static func can_claim(snapshot:Dictionary,inventory:Variant,token:String="") -> bool:
	return claim_block(snapshot,inventory,token).is_empty()

static func public(state:Dictionary) -> Dictionary:
	var found:Variant=state.get(STATE_KEY)
	if not found is Dictionary:return {}
	var day:Variant=found.get("day",0)
	var done_day:Variant=found.get("done_day",0)
	return {"stocked":stocked(state),"packed":packed(state),"rain_packs":rain_packs(state),
		"day":int(day) if _number(day) else 0,"completed":found.get("completed")==true,
		"done_day":int(done_day) if _number(done_day) else 0}

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
	if region!=REGION:return _fail(WRONG_REGION)
	if not unlocked(state):return _fail(LOCKED)
	if not player_ready(state,token):return _fail(NOT_READY)
	if state.has(STATE_KEY) and not _shape_ok(state[STATE_KEY]):return _fail(BAD_EXTRA)
	var target:Vector2i
	match action:
		STOCK_ACTION,CLAIM_ACTION:target=WORKER
		PACK_ACTION:target=CHEST
		_:target=STOP
	if p!=target:
		match action:
			STOCK_ACTION:return _fail(WRONG_STOCK_CELL)
			PACK_ACTION:return _fail(WRONG_PACK_CELL)
			SEND_ACTION:return _fail(WRONG_SEND_CELL)
		return _fail(WRONG_CLAIM_CELL)
	if _distance(person,target)>REACH:return _fail(TOO_FAR)
	if not person.get("inventory") is Dictionary:return _fail(NO_PLAYER)
	var inv:Dictionary=person.inventory
	if action==PACK_ACTION:return _pack(state,extra,inv)
	if not extra.is_empty():return _fail(BAD_EXTRA)
	match action:
		STOCK_ACTION:return _stock(state,inv)
		SEND_ACTION:return _send(state)
	return _claim(state,token,inv)

static func _stock(state:Dictionary,inv:Dictionary) -> Dictionary:
	var block:=_stock_problem(state,inv)
	if not block.is_empty():return _fail(block)
	var weather:=weather_today(state)
	if weather not in STOCK_WEATHERS:return _fail(RAIN_STOCK)
	var own:Dictionary=record(state).duplicate(true)
	var now:=stocked(state)
	now[weather]=int(now[weather])+1
	own.stocked=now
	state[STATE_KEY]=own
	inv[SALT_ITEM]=int(inv.get(SALT_ITEM,0))-LOT_SALT
	return {"ok":true,"message":STOCK_OK%[LOT_SALT,str(WEATHER.LABELS[weather]),stocked_total(state)]}

static func _pack(state:Dictionary,kind:String,inv:Dictionary) -> Dictionary:
	var block:=_pack_problem(state,kind,inv)
	if not block.is_empty():return _fail(block)
	var own:Dictionary=record(state).duplicate(true)
	var done:=packed(state)
	if packed_total(state)==0:own.day=today(state)
	done[kind]=int(done[kind])+1
	own.packed=done
	var rain:=rainy_today(state)
	own.rain_packs=rain_packs(state)+(1 if rain else 0)
	state[STATE_KEY]=own
	inv[FIBER_ITEM]=int(inv.get(FIBER_ITEM,0))-FIBER_PER_BASKET
	var message:=PACK_OK%[str(KIND_NAMES[kind]),packed_total(state),int(done.kitchen),int(done.pickle)]
	if rain:message+=PACK_RAIN_NOTE
	return {"ok":true,"message":message}

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
	if int(inv.get(BASKET_ITEM,0))>=MAX_ITEM:return _fail(BAG_FULL)
	var own:Dictionary=state[STATE_KEY]
	own.claimed[token]=true
	inv[BASKET_ITEM]=int(inv.get(BASKET_ITEM,0))+1
	return {"ok":true,"message":CLAIM_OK}

static func _counts_ok(raw:Variant,keys:Array) -> bool:
	if not raw is Dictionary or raw.size()!=keys.size():return false
	for key:String in keys:
		if not raw.has(key) or not _number(raw[key]):return false
	return true

## Runtime shape check (full consistency is valid()'s job at load time).
static func _shape_ok(own:Variant) -> bool:
	if not own is Dictionary or own.size()!=RECORD_KEYS.size():return false
	for field:String in RECORD_KEYS:
		if not own.has(field):return false
	if not _counts_ok(own.stocked,STOCK_WEATHERS) or not _counts_ok(own.packed,KINDS):return false
	if not _number(own.rain_packs) or not _number(own.day) or not _number(own.done_day):return false
	return own.claimed is Dictionary and own.completed is bool

# ------------------------------------------------------------------ schema --

static func _whole(value:Variant,minimum:float,maximum:float) -> bool:
	return _number(value) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

## state.salt_revisit (optional). Exact keys; stocked exactly sunny/cloudy and packed exactly
## kitchen/pickle, every count a whole number; stocked total <= 6; packed total <= stocked
## total; rain_packs 0..packed total; day/done_day 0..today; day==0 <=> nothing packed; once
## day>0 each kind <= the order of day's season; completed <=> done_day>0; completed => 6
## packed (which then matches the order) and done_day >= day; rain_packs>0 => a rainy Beimen
## day lies between day and done_day (or today); the Beimen gates are repaired; at least one
## known player has raked by hand (only such players can write the record); claimed only
## after completion, values true, keys known players who have raked. Must run after
## SaltPan.valid. Normalises JSON floats to int on success.
static func valid(s:Dictionary) -> bool:
	if not s.has(STATE_KEY):return true
	var own:Variant=s[STATE_KEY]
	if not _shape_ok(own):return false
	var now_day:=int(WEATHER.day_index(s.get("time",0.0)))+1
	var lot_total:=0
	for w:String in STOCK_WEATHERS:
		if not _whole(own.stocked[w],0,TOTAL):return false
		lot_total+=int(own.stocked[w])
	if lot_total>TOTAL:return false
	var pack_total:=0
	for kind:String in KINDS:
		if not _whole(own.packed[kind],0,TOTAL):return false
		pack_total+=int(own.packed[kind])
	if pack_total>lot_total:return false
	if not _whole(own.rain_packs,0,pack_total):return false
	if not _whole(own.day,0,now_day) or not _whole(own.done_day,0,now_day):return false
	if (int(own.day)==0)!=(pack_total==0):return false
	if int(own.day)>0:
		var wanted:=order_for(WEATHER.season_on_day(float(int(own.day)-1)))
		for kind:String in KINDS:
			if int(own.packed[kind])>int(wanted[kind]):return false
	if own.completed!=(int(own.done_day)>0):return false
	if own.completed and (pack_total!=TOTAL or int(own.done_day)<int(own.day)):return false
	if int(own.rain_packs)>0:
		var last:=int(own.done_day) if own.completed else now_day
		var rainy:=false
		for d in range(int(own.day),mini(last,int(own.day)+WEATHER.CYCLE.size())+1):
			if WEATHER.rains(float(d-1),REGION):rainy=true
		if not rainy:return false
	if not unlocked(s):return false
	var players:Variant=s.get("players")
	if not players is Dictionary:return false
	var anyone:=false
	for token in players:
		if player_ready(s,str(token)):anyone=true
	if not anyone:return false
	for token in own.claimed:
		if not own.completed or not token is String or own.claimed[token]!=true:return false
		if not players.has(token) or not player_ready(s,token):return false
	for w:String in STOCK_WEATHERS:own.stocked[w]=int(own.stocked[w])
	for kind:String in KINDS:own.packed[kind]=int(own.packed[kind])
	own.rain_packs=int(own.rain_packs)
	own.day=int(own.day)
	own.done_day=int(own.done_day)
	return true

## Placed salt baskets and basket kits exist only after the revisit. Checks home and every
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
			if str(obj.get("type",""))==BASKET_KIND:return false
			var items:Variant=obj.get("items")
			if items is Dictionary and int(items.get(BASKET_ITEM,0))!=0:return false
	var players:Variant=s.get("players",{})
	if players is Dictionary:
		for token in players:
			var person:Variant=players[token]
			if person is Dictionary and person.get("inventory") is Dictionary and int(person.inventory.get(BASKET_ITEM,0))!=0:return false
	return true
