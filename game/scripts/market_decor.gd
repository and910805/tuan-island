extends RefCounted
const MARKET=preload("res://scripts/market_stall.gd")
const PLAZA_TURN:=60.0
const CLOTH:={"natural":"原色棉布","indigo":"藍染布","leaf":"葉紋布"}
const SIGN:={"plain":"素木招牌","windbell":"風鈴招牌","flower":"花飾招牌"}
const REWARD_CLOTH:="chestnut"
const REWARD_SIGN:="chestnut_badge"
const REWARD_STYLE:={"cloth":REWARD_CLOTH,"sign":REWARD_SIGN}
const REWARD_NAMES:={"cloth":"栗棕攤布","sign":"栗果招牌"}
const REWARD_LOCK:="和小栗完成〈第一位回頭客〉後，可使用這個樣式。"
const REMARKS:={
	"natural|windbell":"風鈴叮叮咚咚的，原色棉布看起來好舒服。",
	"natural|flower":"小花掛在招牌上，攤位看起來很親切。",
	"indigo|plain":"藍染布很耐看，攤位顯得很安靜。",
	"indigo|windbell":"藍布配上風鈴聲，涼涼的好有味道。",
	"indigo|flower":"藍染布配小花，真是好看的搭配。",
	"leaf|plain":"葉紋布讓攤位有種山野的感覺。",
	"leaf|windbell":"葉子花紋加上風鈴，像有風從林子裡吹來。",
	"leaf|flower":"葉紋布和花飾招牌，整個攤位都明亮起來了。"
}
static func default_style() -> Dictionary:
	return {"cloth":"natural","sign":"plain"}
static func choices(kind:String,include_reward:bool) -> Dictionary:
	var table:Dictionary=CLOTH if kind=="cloth" else SIGN
	if not include_reward:return table
	var available:=table.duplicate()
	available[REWARD_STYLE[kind]]=REWARD_NAMES[kind]
	return available
static func valid(raw:Variant) -> bool:
	if typeof(raw)!=TYPE_DICTIONARY:return false
	var d:Dictionary=raw
	if d.size()!=2 or not d.has("cloth") or not d.has("sign"):return false
	var c:Variant=d["cloth"]
	var s:Variant=d["sign"]
	if typeof(c)!=TYPE_STRING or typeof(s)!=TYPE_STRING:return false
	return (CLOTH.has(c) or c==REWARD_CLOTH) and (SIGN.has(s) or s==REWARD_SIGN)
static func valid_for_player(raw:Variant,has_reward:bool) -> bool:
	return valid(raw) and (has_reward or (raw.cloth!=REWARD_CLOTH and raw.sign!=REWARD_SIGN))
static func style(person:Dictionary) -> Dictionary:
	var raw:Variant=person.get("market_decor",null)
	if valid(raw):return {"cloth":raw["cloth"],"sign":raw["sign"]}
	return default_style()

## A single physical stall displays the open plaza vendors in world-clock order.
## Product kinds are sign artwork. Quantities and sales stay in own_market.
static func plaza_display(state:Dictionary,cart_owners:Dictionary) -> Dictionary:
	if not MARKET.unlocked(state):return {}
	var now:=float(state.time)
	var today:=MARKET.day(now)
	var vendors:Array[String]=[]
	for token:String in state.players:
		if cart_owners.has(token):continue
		var market:Dictionary=state.players[token].get("market",{})
		if market.get("pending",false) and int(market.get("open_day",-1))==today and not market.get("stock",{}).is_empty():
			vendors.append(token)
	if vendors.is_empty():return {}
	vendors.sort()
	var vendor:String=vendors[posmod(floori(now/PLAZA_TURN),vendors.size())]
	var person:Dictionary=state.players[vendor]
	var goods:Array=person.market.stock.keys()
	goods.sort()
	return {"vendor":vendor.sha256_text().left(16),"name":str(person.name),"style":style(person),"goods":goods.slice(0,MARKET.MAX_KINDS)}
static func change(person:Dictionary,extra:String,has_reward:bool=false) -> Dictionary:
	var parts:=extra.split("|",true)
	if parts.size()!=2:return {"ok":false,"message":"請選擇攤位布置。"}
	var kind:String=parts[0]
	var choice:String=parts[1]
	if kind!="cloth" and kind!="sign":return {"ok":false,"message":"沒有這種布置。"}
	var table:=choices(kind,true)
	if not table.has(choice):return {"ok":false,"message":"沒有這個樣式。"}
	if choice==REWARD_STYLE[kind] and not has_reward:return {"ok":false,"message":REWARD_LOCK}
	var now:=style(person)
	if now[kind]==choice:return {"ok":false,"message":"攤位已經是「%s」了。"%table[choice]}
	now[kind]=choice
	person["market_decor"]=now
	return {"ok":true,"message":"攤位換成「%s」了。"%table[choice]}
static func remark(decor:Dictionary) -> String:
	if not valid(decor):return ""
	if decor.sign==REWARD_SIGN:return "栗果招牌很醒目，下次也認得出這個攤位。"
	if decor.cloth==REWARD_CLOTH:return "栗棕色的攤布暖暖的，遠遠看就知道走對了。"
	var key:String="%s|%s"%[decor["cloth"],decor["sign"]]
	return REMARKS.get(key,"")
