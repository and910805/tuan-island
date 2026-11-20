extends RefCounted

const RECORD:="mushroom_mail"
const READ:="mushroom_mail_read"
const CLAIM:="mushroom_mail_claim"
const ARRIVAL:="arrival"
const BRIDGE:="river_bridge"
const LUOLUO:="luoluo_reply"
const Goals=preload("res://scripts/resident_goals.gd")
const Stone=preload("res://scripts/stone_workshop.gd")
const LETTERS:={
	ARRIVAL:{"sender":"小栗","title":"家門口的第一封信","body":"歡迎在渡口落腳。窗邊若還有一點空地，就把這幾顆種子種下吧。等葉子冒出來，再帶朋友來看看。","items":{"radish_seed":3,"wheat_seed":2}},
	BRIDGE:{"sender":"阿榆","title":"橋那頭的花也開了","body":"河灣橋接好了。傍晚那邊風大，走過去記得戴好帽子。我把布置路邊剩下的纖維留給你。","items":{"fiber":4}},
	LUOLUO:{"sender":"洛洛","title":"給幫忙送信的你","body":"信已平安送到，謝謝你一起認路。以後信封偶爾會落進門邊的蘑菇郵箱，路過時記得翻一翻。","items":{}},
}
const ITEM_LIMIT_MESSAGE:="背包放不下整份包裹，清出空間後再來領取。"

static func eligible(state:Dictionary,player:Dictionary,id:String)->bool:
	match id:
		ARRIVAL:return true
		# Q05 completion, not Q03: an absent project (old save) counts as an already open bridge.
		BRIDGE:return Stone.bridge_open(state) or player.get(RECORD,{}).has(BRIDGE)
		LUOLUO:return Goals.done(player,"luoluo").has(1)
	return false

static func view(state:Dictionary,player:Dictionary)->Dictionary:
	var mail:Dictionary={}
	var status:Dictionary=player.get(RECORD,{})
	for id:String in LETTERS:
		if eligible(state,player,id):mail[id]=status.get(id,"new")
	return mail

static func has_pending(inbox:Dictionary)->bool:
	for id:String in inbox:
		if inbox[id]=="new" or (inbox[id]=="read" and not LETTERS.get(id,{}).get("items",{}).is_empty()):
			return true
	return false

static func valid(record:Variant)->bool:
	if not record is Dictionary or record.is_empty() or record.size()>LETTERS.size():return false
	for id in record:
		if not id is String or not LETTERS.has(id) or not record[id] is String:return false
		if record[id]=="read":continue
		if record[id]!="claimed" or LETTERS[id].items.is_empty():return false
	return true
