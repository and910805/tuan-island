extends RefCounted
## T071 市集攤位「客人演出」與手帳「我的市集攤位」摘要（純呈現、純函式）。
##
## 這裡不決定任何買賣：成交仍只在 World.step 的午夜結算（market_stall.gd）。
## 畫面上的客人只是「今天廣場上有攤位開張」的表示，不擋路、不能互動、不寫入
## 任何狀態，也不代表哪一件東西已經賣出。輸入只有每位用戶端本來就收到的
## snapshot.own_market（其中 stalls_today 是全島開張攤數，不含身分與貨品）與
## 世界時間；不讀別人的攤位內容，不用亂數，不看現實時鐘。
##
## 公開 API：
##   static func part_of(now:float) -> int                         # 一個世界日分成 PARTS 段
##   static func shown_for(stalls:int) -> int                      # 0 攤→0、1 攤→2、2 攤以上→3
##   static func wish_item(theme:String,day:int,part:int,prices:Dictionary={}) -> String
##   static func plan(market_view:Dictionary,now:float,prices:Dictionary={}) -> Array
##       每位客人 {"slot":int,"offset":Vector2,"facing":Vector2i,"tint":Color,"wish":String}
##       offset 是相對攤位格左上角的腳底位置（格為單位）；wish 只有一位客人非空。
##   static func shuffle_phase(slot:int,elapsed:float) -> float    # >0 時該客人正在原地踏步
##   static func status_line(market_view:Dictionary) -> String
##   static func summary_lines(market_view:Dictionary,names:Dictionary={}) -> Array   # 手帳摘要（字串陣列）
const Market=preload("res://scripts/market_stall.gd")
const WEATHER=preload("res://scripts/weather.gd")

const PARTS:=6
const MAX_SHOWN:=3
## 腳底位置（相對攤位格，格為單位）。攤位圖寬兩格、以攤位格為中心；前兩位站在
## 攤位正面兩側，第三位在右前方稍遠處。三個位置都讓開攤位正前方 (0.5,1.4) 一帶
## ——玩家整理攤位時站的地方——身體範圍（30×48 像素）互不重疊。
const SLOTS:=[Vector2(-0.6,1.5),Vector2(1.6,1.5),Vector2(2.6,2.3)]
const FACINGS:=[Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP]
## 沿用玩家角色圖格加染色（專用客人像素圖待做）。
const TINTS:=[Color(0.84,0.93,1.0),Color(1.0,0.88,0.78),Color(0.90,1.0,0.84)]
const SHUFFLE_PERIOD:=6.0
const SHUFFLE_LENGTH:=0.7

static func part_of(now:float) -> int:
	var within:=fposmod(now,WEATHER.DAY_SECONDS)
	return clampi(int(floor(within*PARTS/WEATHER.DAY_SECONDS)),0,PARTS-1)

static func shown_for(stalls:int) -> int:
	if stalls<=0:return 0
	return 2 if stalls==1 else MAX_SHOWN

## 今天主題類別裡的一樣東西（依世界日與時段固定輪替）；沒有可選時回傳空字串。
static func wish_item(theme:String,day_index:int,part:int,prices:Dictionary={}) -> String:
	var options:=[]
	for item:String in Market.sellable_items(prices):
		if Market.category_of(item,prices)==theme:options.append(item)
	if options.is_empty():return ""
	return str(options[posmod(day_index*5+part,options.size())])

static func plan(market_view:Dictionary,now:float,prices:Dictionary={}) -> Array:
	if market_view.get("unlocked",false)!=true:return []
	var stalls_value:Variant=market_view.get("stalls_today",0)
	if not (stalls_value is int or stalls_value is float):return []
	var shown:=shown_for(int(stalls_value))
	if shown<=0:return []
	var day_index:=Market.day(now)
	var part:=part_of(now)
	# 只有一攤時三個位置輪流空一個；兩攤以上三個位置都有人。
	var absent:=posmod(day_index+part,MAX_SHOWN) if shown<MAX_SHOWN else -1
	var wisher:=posmod(day_index+part+1,MAX_SHOWN)
	var wish:=wish_item(Market.theme_of(day_index),day_index,part,prices)
	var result:=[]
	for slot in range(MAX_SHOWN):
		if slot==absent:continue
		result.append({"slot":slot,"offset":SLOTS[slot],"facing":FACINGS[slot],"tint":TINTS[slot],
			"wish":wish if slot==wisher else ""})
	return result

## 原地踏步的相位：每 SHUFFLE_PERIOD 秒踏 SHUFFLE_LENGTH 秒，三位錯開；其餘時間回傳 0。
static func shuffle_phase(slot:int,elapsed:float) -> float:
	var t:=fposmod(elapsed+slot*2.0,SHUFFLE_PERIOD)
	if t>=SHUFFLE_LENGTH:return 0.0
	return maxf(0.001,t/SHUFFLE_LENGTH*TAU)

static func status_line(market_view:Dictionary) -> String:
	var count:=int(market_view.get("stock_count",0))
	if market_view.get("open",false)==true:
		return "今天營業中 · 攤上 %d 件 · 全島 %d 攤開張 · 預估來客 %d 位，午夜結算"%[count,int(market_view.get("stalls_today",0)),int(market_view.get("visitors_estimate",0))]
	if market_view.get("pending",false)==true:return "上一輪還在結算"
	if count>0:return "今天還沒開張 · 攤上有 %d 件，到廣場西側的攤位開張"%count
	return "今天還沒開張 · 攤上沒有東西"

## 手帳「島嶼近況」的市集卡片。未解鎖時回傳空陣列。只讀本人的 own_market。
static func summary_lines(market_view:Dictionary,names:Dictionary={}) -> Array:
	if market_view.get("unlocked",false)!=true:return []
	var lines:=[]
	lines.append("今日主題：%s（主題商品＋30%%） · 明日主題：%s"%[_category(market_view.get("theme","")),_category(market_view.get("next_theme",""))])
	lines.append(status_line(market_view))
	var till:=int(market_view.get("till",0))
	var money:="待領營收 %d 鈴幣 · 累計營收 %d 鈴幣"%[till,int(market_view.get("total",0))]
	if till>0:money+="（到攤位領取）"
	lines.append(money)
	var report:Variant=market_view.get("report",{})
	if not report is Dictionary or report.is_empty():
		lines.append("上一輪結算：還沒有結算紀錄")
		return lines
	var sold:Variant=report.get("sold",{})
	var parts:=PackedStringArray()
	if sold is Dictionary:
		var keys:Array=sold.keys()
		keys.sort()
		for item in keys:parts.append("%s ×%d"%[str(names.get(item,item)),int(sold[item])])
	lines.append("上一輪結算・第 %d 日（%s）：來客 %d 位 · %d 攤同場 · 收入 %d 鈴幣"%[int(report.get("day",0))+1,_category(report.get("theme","")),int(report.get("visitors",0)),int(report.get("stalls",0)),int(report.get("coins",0))])
	lines.append("賣出：%s"%("、".join(parts) if not parts.is_empty() else "這一輪沒有賣出"))
	return lines

static func _category(category:Variant) -> String:
	var id:=str(category)
	return str(Market.CATEGORY_NAMES.get(id,id)) if not id.is_empty() else "—"
