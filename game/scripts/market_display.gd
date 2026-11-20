extends RefCounted
## T071 市集攤位「攤位布置」第一批（純呈現、純函式）：把本人擺上攤位的東西畫成攤位
## 櫃檯前的小掛牌，並依攤上擺了什麼給一句「客人的話」。
##
## 成交由 World.step 在午夜結算。櫃檯掛牌接受本人庫存或公開商品圖示，
## 客人對話使用本人的攤位摘要。這裡只產生呈現資訊。
##
## 公開 API：
##   static func shelf(market_view:Dictionary) -> Array
##       每種貨一筆 {"slot":int,"item":String,"count":int,"themed":bool,"offset":Vector2}
##       依物品 ID 排序、最多 Market.MAX_KINDS 筆；offset 是掛牌左上角相對攤位圖
##       （64×64）左上角的像素位置，掛牌大小為 TAG。格式不對或未解鎖時回傳空陣列。
##   static func themed_items(market_view:Dictionary) -> Array       # 攤上屬於今日主題的物品（已排序）
##   static func remark(market_view:Dictionary,names:Dictionary={}) -> String
##       今天廣場有客人（全島至少一攤開張）時的一句話；沒有客人或未解鎖時回傳空字串。
##       同一個世界日內只隨攤上內容改變。
##   static func remark_line(market_view:Dictionary,names:Dictionary={}) -> String
##       面板用的整行：「客人的話：…」加上 REMARK_NOTE；沒有話時回傳空字串。
const Market=preload("res://scripts/market_stall.gd")
const Decor=preload("res://scripts/market_decor.gd")

const TAG:=Vector2(12,12)
## 四個掛牌並排在櫃檯檯面（攤位圖 x=8..56、y=24..36）。這個範圍讓開攤位兩側客人的
## 身體（腳在攤位格下方 1.5 格，身體上緣在攤位圖 y=38）與客人頭上的小牌子
## （左側到攤位圖 x=6、右側從 x=58 起）。今日主題的掛牌外框是橘色。
const SLOTS:=[Vector2(8,24),Vector2(20,24),Vector2(32,24),Vector2(44,24)]
const REMARK_PREFIX:="客人的話："
const REMARK_NOTE:="（閒聊，不影響結算）"
const REMARK_CLOSED:="「這一攤今天還沒開張呀，先去別攤逛逛。」"
const REMARK_EMPTY:="「攤上空空的，東西都收回去了嗎？」"
const REMARK_THEMED:="「今天想找%s，這攤剛好有%s，先看這個。」"
const REMARK_VARIETY:="「種類真多，每一樣都想看看。」"
const REMARK_OTHER:="「%s看起來不錯，不過今天大家先找%s。」"
const VARIETY_KINDS:=3

static func _stock(market_view:Dictionary) -> Dictionary:
	if market_view.get("unlocked",false)!=true:return {}
	var stock:Variant=market_view.get("stock",{})
	if not stock is Dictionary:return {}
	var result:={}
	for item in stock:
		var count:Variant=stock[item]
		if not item is String or item.is_empty() or not (count is int or count is float):continue
		if int(count)>0:result[item]=int(count)
	return result

static func _themed(market_view:Dictionary,item:String) -> bool:
	var prices:Variant=market_view.get("prices",{})
	if prices is Dictionary and prices.get(item) is Dictionary:return prices[item].get("themed",false)==true
	var theme:=str(market_view.get("theme",""))
	return not theme.is_empty() and Market.category_of(item)==theme

static func shelf(market_view:Dictionary) -> Array:
	var stock:=_stock(market_view)
	var items:Array=stock.keys()
	items.sort()
	var result:=[]
	for index in range(mini(items.size(),SLOTS.size())):
		var item:String=items[index]
		result.append({"slot":index,"item":item,"count":stock[item],"themed":_themed(market_view,item),"offset":SLOTS[index]})
	return result

static func themed_items(market_view:Dictionary) -> Array:
	var result:=[]
	for entry:Dictionary in shelf(market_view):
		if entry.themed:result.append(entry.item)
	return result

static func remark(market_view:Dictionary,names:Dictionary={}) -> String:
	if market_view.get("unlocked",false)!=true:return ""
	var stalls:Variant=market_view.get("stalls_today",0)
	if not (stalls is int or stalls is float) or int(stalls)<=0:return ""
	if market_view.get("open",false)!=true:return REMARK_CLOSED
	var shown:=shelf(market_view)
	if shown.is_empty():return REMARK_EMPTY
	var theme:=str(market_view.get("theme",""))
	var theme_name:=str(Market.CATEGORY_NAMES.get(theme,theme))
	var day_value:Variant=market_view.get("day",0)
	var day_index:=int(day_value) if (day_value is int or day_value is float) else 0
	var themed:=themed_items(market_view)
	if not themed.is_empty():
		var pick:String=themed[posmod(day_index,themed.size())]
		return REMARK_THEMED%[theme_name,str(names.get(pick,pick))]
	if shown.size()>=VARIETY_KINDS:return REMARK_VARIETY
	var other:String=shown[posmod(day_index,shown.size())].item
	return REMARK_OTHER%[str(names.get(other,other)),theme_name]

static func remark_line(market_view:Dictionary,names:Dictionary={}) -> String:
	var said:=remark(market_view,names)
	if said.is_empty():return ""
	var accent:=""
	var decor:Variant=market_view.get("decor",{})
	if market_view.get("open",false) and Decor.valid(decor):
		accent=Decor.remark(decor)
	return REMARK_PREFIX+said+(" "+accent if not accent.is_empty() else "")+REMARK_NOTE
