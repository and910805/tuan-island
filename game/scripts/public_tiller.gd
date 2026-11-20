extends RefCounted
## T064 公用耕田機：晚加入的島民在渡口的農機架登記後，取得「可使用手推耕田機」的資格。
## 資格是角色上的布林旗標，不是物品：不進背包，所以不能出貨、交易、放箱或上架。
## 每次整地仍用本人的木炭，冷卻、範圍與農田歸屬完全沿用 tiller.gd 與 world.gd 的既有規則。
## 開放條件與公用鎬相同（渡口野餐後）：耕田機的配方本來就只受材料限制，銅接頭要到
## 野餐開放礦料後才做得出來，所以借用不會早於島上可自製的階段。播種機、收割機不外借。

const ACTION:="borrow_public_tiller"
const FIELD:="borrowed_tiller"
const ITEM:="tiller"
const POINT:="public_tiller"
const NO_SITE:=Vector2i(-1,-1)
## 廣場東南、往牧場路上的空地；都不在村路、居民站位或其他活動的候選格上。
## 依序取第一格沒有被建物、地板、屋頂、農田或種下的樹占用的格子（舊存檔相容）。
const SITES:Array[Vector2i]=[Vector2i(46,32),Vector2i(47,32),Vector2i(45,32),Vector2i(46,33)]
## 四格都被舊存檔的私人物件占用時，農機架不出現，改在渡口公告板登記。
const DESK:=Vector2i(40,29)
const ART_PATH:="res://assets/life-art/public-tiller-rack.png"
const REACH:=3.2

const OPENED:="已登記公用耕田機。按耕田機鍵拿起來用，每次成功整地消耗自己的 1 份木炭。"
const LOCKED:="渡口野餐後，公用耕田機才開放借用。"
const OWNED:="你已有自己的手推耕田機，把公用的留給其他島民。"
const ALREADY:="你已登記過公用耕田機，直接拿起來用就可以。"
const WRONG_PLACE:="請到渡口廣場東南的農機架登記借用。"
const WRONG_PLACE_DESK:="農機架的位置被占用了，請到渡口公告板登記借用。"
const NEED_MACHINE:="先在工作台製作手推耕田機，或到渡口農機架借用公用耕田機"

static var art:Texture2D
static var art_checked:=false

static func open(snapshot:Dictionary) -> bool:
	return bool(snapshot.get("picnic",false))

## 農機架所在格；未開放或四格都被占用時為 NO_SITE。
static func site(snapshot:Dictionary) -> Vector2i:
	if not open(snapshot):return NO_SITE
	for cell:Vector2i in SITES:
		var key:="%d,%d"%[cell.x,cell.y]
		var occupied:=false
		for field:String in ["objects","ground","roofs","crops","forest"]:
			if snapshot.get(field,{}).has(key):
				occupied=true
				break
		if not occupied:return cell
	return NO_SITE

## 開放後，農機架那一格保留為公共設施並擋路（與出貨箱、市集攤位相同的做法）。
static func reserved(snapshot:Dictionary,cell:Vector2i) -> bool:
	return cell in SITES and cell==site(snapshot)

## 登記借用要對準的格子：農機架；沒有農機架時改用公告板。未開放時為 NO_SITE。
static func loan_cell(snapshot:Dictionary) -> Vector2i:
	if not open(snapshot):return NO_SITE
	var rack:=site(snapshot)
	return rack if rack!=NO_SITE else DESK

static func borrowed(person:Dictionary) -> bool:
	return person.get(FIELD,false)==true

static func owns(person:Dictionary) -> bool:
	return int(person.get("inventory",{}).get(ITEM,0))>0

## 整地動作的唯一資格判斷：自己做的機器，或公用耕田機的借用資格。
static func can_till(person:Dictionary) -> bool:
	return owns(person) or borrowed(person)

## 不能借用的原因；可借用時回傳空字串。伺服器規則與介面共用，不改任何狀態。
static func problem(snapshot:Dictionary,person:Dictionary,region:String,cell:Vector2i) -> String:
	if not open(snapshot):return LOCKED
	var target:=loan_cell(snapshot)
	if region!="home" or cell!=target:return WRONG_PLACE if target!=DESK else WRONG_PLACE_DESK
	if owns(person):return OWNED
	if borrowed(person):return ALREADY
	return ""

## 伺服器端登記。只寫入本人的旗標，不動背包與世界其他資料。
static func borrow(snapshot:Dictionary,person:Dictionary,region:String,cell:Vector2i) -> Dictionary:
	var reason:=problem(snapshot,person,region,cell)
	if not reason.is_empty():return {"ok":false,"message":reason}
	person[FIELD]=true
	return {"ok":true,"message":OPENED}

## 存檔檢查：欄位可缺（舊存檔），存在時必須是布林，且不能早於野餐開放。
static func valid(person:Dictionary,snapshot:Dictionary) -> bool:
	if not person.has(FIELD):return true
	if not person[FIELD] is bool:return false
	return not person[FIELD] or open(snapshot)

## 地圖標籤：讓走近的人直接看懂能做什麼。
static func label(person:Dictionary) -> String:
	if owns(person):return "公用耕田機"
	return "公用耕田機・已登記" if borrowed(person) else "借用公用耕田機"

## 地圖道具圖。圖檔到位並匯入後用圖檔；還沒匯入但檔案已在專案內時直接讀檔；
## 都沒有時回傳 null，由呼叫端畫既有的簡單告示牌，不會中斷畫面。
static func texture() -> Texture2D:
	if art_checked:return art
	art_checked=true
	if ResourceLoader.exists(ART_PATH):art=load(ART_PATH) as Texture2D
	elif FileAccess.file_exists(ART_PATH):
		var image:=Image.load_from_file(ART_PATH)
		if image!=null and not image.is_empty():art=ImageTexture.create_from_image(image)
	return art
