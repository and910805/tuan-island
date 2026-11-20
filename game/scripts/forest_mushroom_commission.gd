extends RefCounted
## C12 D05 森林菇湯：阿榆的「林間濕氣」常駐委託（內容設定集「菌床與森林委託」）。
##
## 純規則模組：不讀寫檔案、不預載 World、不看現實時鐘、不用亂數。位置與地形（樹、距離）由
## World 以伺服器內的玩家座標與地圖判定，這裡只管階段、材料、報酬與敘述。
##
## 實際地圖對應（設定集的「蜜葉森林」在程式裡沒有獨立區域）：
##   - 森林 = 家園（風鈴渡口）外圈自然生長的樹林：World.resource()=="tree" 且不是玩家種的樹，
##     並且離渡口公告板至少 FOREST_MIN_DISTANCE 格。村中央與野餐區的零星樹不算遠征。
##   - 菌床 = 金瓜石第五層（mine_5）：星夜菇只能種在那裡（World.crop_terrain_problem）。
##   - 與貓空茶園的竹林、霧竹溪谷無關。
##
## 階段（個人，永久，與季節無關，不會錯過）：
##   0 尚未接下 → 1 已向阿榆接下 → 2 已在林子看過 → 3 已交件（食譜解鎖）
## 開放條件：渡口公告板已修好（state.board == true）。之後任何時候都可以接。
##
## 不送材料：接下與查看不給任何東西；交件只扣 NEEDS，報酬只有鈴幣，且低於材料的商店價值
## （星夜菇 36×2 ＋ 風鈴香草 48 = 120），不構成套利，也不繞過公共廚房灶台的原料需求。
##
## 整合契約：見 work/claude-agents/d05-integration-contract.md。

const ACTION:="forest_mushroom_order"
const SURVEY_POINT:="forest_mushroom_tree"
const NO_TREE:=Vector2i(-1,-1)
const KEY:="forest_mushroom_commission"
const RESIDENT:="aru"
const DISH:="forest_mushroom_soup"
const REGION:="home"           # == Regions.HOME
const BOARD:=Vector2i(40,29)   # 渡口公告板，同 World 其他公告板動作
const FOREST_MIN_DISTANCE:=14.0
const REACH:=3.2
const LIMIT:=1000000000        # 鈴幣與背包上限，同 world.gd

const STAGE_NONE:=0
const STAGE_ACCEPTED:=1
const STAGE_SURVEYED:=2
const STAGE_DONE:=3

const TITLE:="林間的濕氣"
const NEEDS:={"star_mushroom":2,"chime_herb":1}
const ITEM_NAMES:={"star_mushroom":"星夜菇","chime_herb":"風鈴香草"}
const REWARD_COINS:=90
const ACCEPT:="accept"
const SURVEY:="survey"
const DELIVER:="deliver"
const EXTRAS:=[ACCEPT,SURVEY,DELIVER]

const LOCKED_TEXT:="先修好渡口公告板，阿榆才有空聊林子的事。"
const COOKING_LOCK:="先向阿榆接下〈林間的濕氣〉，到渡口外圍觀察樹林，再帶星夜菇和風鈴香草交件。"
const COOKING_BUTTON:="完成阿榆〈林間的濕氣〉後解鎖"
const SOURCE_NOTE:="星夜菇要在金瓜石第五層的洞內菌床栽培；風鈴香草在田尾育苗床栽培。"
const FICTION_NOTE:="蜜葉林、洞內菌床與這道湯的由來皆為遊戲原創情節。"

const LINES:={
	"ask":"阿榆：「鋸木台邊的舊樹墩冒出一圈白菇，兩天就乾成紙片。去外圈的林子看看，那邊的樹蔭是不是比較濕？」",
	"survey":"樹蔭下的落葉堆裡有幾朵小菇，被風一吹就垂了頭。林子太亮也太乾，菇只能零星冒頭，要穩穩長，得找又暗又不透風的地方。",
	"after_survey":"阿榆：「又暗又不透風……那不就是金瓜石第五層的洞內菌床？星夜菇在那裡能長，再配一把風鈴香草提味，我來煮一鍋。」",
	"thanks":"阿榆把菇和香草一起下鍋，湯香把整個渡口都引來了。「林子教我們它缺什麼，洞裡剛好有。這份做法，也寫給你一份。」",
}

# --- 讀取 ---------------------------------------------------------------

static func whole(value:Variant,maximum:int)->bool:
	if value is int:return value>=0 and value<=maximum
	if value is float:
		var f:float=value
		return not is_nan(f) and not is_inf(f) and f>=0.0 and f<=float(maximum) and f==floorf(f)
	return false

## 存檔欄位的合法性：缺省合法；存在時只能是 1..3 的整數，且公告板已修好。
static func valid(value:Variant,state:Dictionary)->bool:
	if not whole(value,STAGE_DONE) or int(value)<STAGE_ACCEPTED:return false
	return state.get("board",false)==true

static func stage(player:Dictionary)->int:
	var value:Variant=player.get(KEY,0)
	return int(value) if whole(value,STAGE_DONE) else STAGE_NONE

## 公共廚房灶台解鎖用的唯一判斷（Codex 接 kitchen_stove.gd 時只讀這個）。
static func done(player:Dictionary)->bool:
	return stage(player)==STAGE_DONE

static func open(state:Dictionary)->bool:
	return state.get("board",false)==true

static func count_of(value:Variant)->int:
	if value is int:return value if value>=0 and value<=LIMIT else -1
	if value is float:
		var f:float=value
		if is_nan(f) or is_inf(f) or f<0.0 or f>float(LIMIT) or f!=floorf(f):return -1
		return int(f)
	return -1

static func missing(inv:Dictionary)->Dictionary:
	var short:={}
	for item:String in NEEDS:
		var held:=count_of(inv.get(item,0))
		if held<0:held=0
		if held<int(NEEDS[item]):short[item]=int(NEEDS[item])-held
	return short

static func needs_text(items:Dictionary=NEEDS)->String:
	var parts:PackedStringArray=[]
	for item:String in items:parts.append("%s ×%d"%[ITEM_NAMES.get(item,item),int(items[item])])
	return "、".join(parts)

## 距離判斷：離公告板夠遠才算「外圈林子」。
static func forest_cell(cell:Vector2i)->bool:
	return Vector2(cell).distance_to(Vector2(BOARD))>=FOREST_MIN_DISTANCE

## 唯讀摘要（給 UI／快照）：stage、next（下一步行動鍵）、text（下一步說明）、missing。
static func view(state:Dictionary,player:Dictionary)->Dictionary:
	var current:=stage(player)
	var out:={"stage":current,"open":open(state),"done":current==STAGE_DONE,"next":"","text":"","missing":{},"title":TITLE,
		"needs":NEEDS.duplicate(),"reward_coins":REWARD_COINS,"dish":DISH,"fiction_note":FICTION_NOTE}
	if current==STAGE_DONE:
		out.text="森林菇湯的做法已收進食譜，可在公共廚房灶台煮。"
		return out
	if not open(state):
		out.text=LOCKED_TEXT
		return out
	match current:
		STAGE_NONE:
			out.next=ACCEPT
			out.text="到渡口找阿榆，聽他說林子裡的事。"
		STAGE_ACCEPTED:
			out.next=SURVEY
			out.text="走到離渡口公告板 %d 格以外的自然樹林，在樹旁察看濕氣。"%int(FOREST_MIN_DISTANCE)
		_:
			var short:=missing(player.get("inventory",{}))
			out.missing=short
			out.next=DELIVER
			out.text="帶 %s 回渡口交給阿榆。%s"%[needs_text(),SOURCE_NOTE] if short.is_empty() else "還差 %s。%s"%[needs_text(short),SOURCE_NOTE]
	return out

# --- 寫入（只在 World 驗證位置後呼叫；先驗證、再一次性寫入） ------------------

static func _result(ok:bool,message:String)->Dictionary:
	return {"ok":ok,"message":message}

static func accept(state:Dictionary,player:Dictionary)->Dictionary:
	if not open(state):return _result(false,LOCKED_TEXT)
	if stage(player)>=STAGE_ACCEPTED:return _result(false,"阿榆已經交代過林子的事了。")
	if player.has(KEY):return _result(false,"委託紀錄異常，暫不處理。")
	player[KEY]=STAGE_ACCEPTED
	return _result(true,LINES.ask)

static func survey(state:Dictionary,player:Dictionary)->Dictionary:
	if not open(state):return _result(false,LOCKED_TEXT)
	var current:=stage(player)
	if current==STAGE_NONE:return _result(false,"先向阿榆問問林子的事。")
	if current>=STAGE_SURVEYED:return _result(false,"這片林子你已經看過了。")
	player[KEY]=STAGE_SURVEYED
	return _result(true,LINES.survey+" "+LINES.after_survey)

static func deliver(state:Dictionary,player:Dictionary)->Dictionary:
	if not open(state):return _result(false,LOCKED_TEXT)
	var current:=stage(player)
	if current==STAGE_DONE:return _result(false,"森林菇湯的做法已經在你的食譜裡了。")
	if current<STAGE_SURVEYED:return _result(false,"先到林子裡看看，再回來交給阿榆。")
	var inv:Variant=player.get("inventory")
	if not inv is Dictionary:return _result(false,"背包資料異常，委託暫不結算。")
	var short:=missing(inv)
	if not short.is_empty():return _result(false,"還差 %s。%s"%[needs_text(short),SOURCE_NOTE])
	for item:String in NEEDS:
		if count_of((inv as Dictionary).get(item,0))<int(NEEDS[item]):return _result(false,"材料資料異常，委託暫不結算。")
	var coins:=count_of(player.get("coins",0))
	if coins<0:return _result(false,"鈴幣資料異常，委託暫不結算。")
	if coins>LIMIT-REWARD_COINS:return _result(false,"鈴幣已達上限。")
	for item:String in NEEDS:
		(inv as Dictionary)[item]=count_of((inv as Dictionary)[item])-int(NEEDS[item])
	player.coins=coins+REWARD_COINS
	player[KEY]=STAGE_DONE
	return _result(true,"%s 交給阿榆，鈴幣 +%d。%s"%[needs_text(),REWARD_COINS,LINES.thanks])
