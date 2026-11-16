extends RefCounted
## 望安開場（規劃書 ch.03／ch.05）：玩家搭船來到澎湖・望安，在風鈴渡口下船，
## 小栗在種子攤東北邊留了一小塊田（chapter_one.STARTER_PLOT）。
## 全部由既有狀態推導：沒有新的存檔欄位、協定、物品或伺服器規則。
const CHAPTER_ONE=preload("res://scripts/chapter_one.gd")
const PLACE:="澎湖・望安"
const SCENE:="風鈴渡口"
const ARRIVAL:="你搭船來到澎湖・望安，在風鈴渡口下了船。"
## 規劃書 ch.05 的開場台詞（逐字）。
const OPENING_LINE:="小栗在渡口旁留了一塊地給你。先種一株蘿蔔，收成後帶到出貨箱。"
const PLOT_TAG:="小栗留的田"
const PLOT_LABEL_ID:="wangan_plot"
const HEADING:="第一件事・種一株蘿蔔"

## 新島民的下船點（World.SPAWN）附近多遠以內仍算「剛下船」。
const ARRIVAL_REACH:=3.0

## 「剛下船的新島民」：在家園、第一章還沒有人出貨、本人沒有採收紀錄（計數與
## 第一章紀錄都為 0）、沒有建造過，家園上也沒有本人的作物、物件、地板或種下的樹，
## 而且還站在下船點 World.SPAWN 附近（ARRIVAL_REACH 格內）。走遠、開田或換地區
## 後就不再是「剛下船」：卡片自動收起，下次上線也不再出現（回到一般的歡迎提示）。
## 伺服器 state（owner = token）與用戶端快照（owner = 公開 id）結果相同；只讀。
static func is_new_arrival(s:Dictionary,owner:String) -> bool:
	if not fresh_player(s,owner):return false
	var person:Dictionary=s.players[owner]
	var spawn:Vector2=preload("res://scripts/world.gd").SPAWN
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(spawn)<=ARRIVAL_REACH

## The state half of is_new_arrival (no position rule).
static func fresh_player(s:Dictionary,owner:String) -> bool:
	var chapter=s.get("chapter_one")
	if not chapter is Dictionary or chapter.get("shipped",true)!=false:return false
	if str(s.get("region_id","home"))!="home":return false
	var people=s.get("players")
	if not people is Dictionary or not people.get(owner) is Dictionary:return false
	var person:Dictionary=people[owner]
	if str(person.get("region","home"))!="home":return false
	if int(person.get("harvests",0))!=0 or int(person.get("builds",0))!=0:return false
	var records=chapter.get("harvests",{})
	if records is Dictionary and records.has(owner):return false
	for layer in ["crops","objects","ground","forest"]:
		var entries=s.get(layer,{})
		if not entries is Dictionary:continue
		for entry in entries.values():
			if entry is Dictionary and str(entry.get("owner",""))==owner:return false
	return true

## The plot marker is drawn while the first-crop steps run (until the first
## shipment) and the plot is still usable for this player: a free cell or one
## of their own plots inside it. Fully occupied plots show no marker.
static func marker_shown(s:Dictionary,owner:String) -> bool:
	if CHAPTER_ONE.first_crop_step(s,owner).is_empty():return false
	if not CHAPTER_ONE.starter_plot_free(s).is_empty():return true
	var crops=s.get("crops",{})
	if not crops is Dictionary:return false
	for cell in CHAPTER_ONE.STARTER_PLOT:
		var plot=crops.get("%d,%d"%[cell.x,cell.y])
		if plot is Dictionary and str(plot.get("owner",""))==owner:return true
	return false

static func plot_rect() -> Rect2i:
	var top_left:=CHAPTER_ONE.STARTER_PLOT[0]
	var bottom_right:=CHAPTER_ONE.STARTER_PLOT[0]
	for cell in CHAPTER_ONE.STARTER_PLOT:
		top_left=Vector2i(mini(top_left.x,cell.x),mini(top_left.y,cell.y))
		bottom_right=Vector2i(maxi(bottom_right.x,cell.x),maxi(bottom_right.y,cell.y))
	return Rect2i(top_left,bottom_right-top_left+Vector2i.ONE)
