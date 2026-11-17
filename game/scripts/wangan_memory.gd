extends RefCounted

const SITE:=Vector2i(48,31)
const POINT:="wangan_house_memory"
const ACTION:="wangan_house_record"
const COURT_POINT:="wangan_house_courtyard"
const COURT:=Rect2i(44,37,3,3)
const HOUSE_WALL:=Rect2i(COURT.position,Vector2i(COURT.size.x,1))
const COURT_SIGN:=COURT.position+Vector2i(1,1)
const KEY:="wangan_house_memory_seen"
const ANSWER:="coral_basalt"
const SOURCE_BOOK:="https://tcmb.culture.tw/zh-tw/detail?id=20100414000001&indexCode=BOCH_CountryCulture_13"
const WEIR_SITE:=Vector2i(49,34)
const WEIR_LOOKOUT:=Vector2i(50,57)
const WEIR_SITES:=[WEIR_SITE,WEIR_LOOKOUT]
const WEIR_POINT:="wangan_weir_memory"
const WEIR_LOOKOUT_POINT:="wangan_weir_lookout"
const WEIR_ACTION:="wangan_weir_observe"
const WEIR_KEY:="wangan_weir_progress"
const WEIR_SOURCE:="https://penghu.info/OB73717F8E1BAF54468E"
const SHUIAN_SOURCE:="https://penghu.info/OB9059439D7C9E54B00F"
const TIDE_SOURCE:="https://twh.boch.gov.tw/taiwan/intro.aspx?id=13&lang=zh_tw"
const LOG_ACTION:="wangan_harbor_log"
const LOG_KEY:="wangan_harbor_log_done"

static func courtyard_available(state:Dictionary)->bool:
	for layer:String in ["objects","ground","roofs","forest","crops"]:
		var entries:Dictionary=state.get(layer,{})
		for y in range(COURT.position.y,COURT.end.y):
			for x in range(COURT.position.x,COURT.end.x):
				if entries.has("%d,%d"%[x,y]):return false
	return true

static func observation_site(state:Dictionary,position:Vector2)->Vector2i:
	var sign_center:=Vector2(COURT_SIGN)+Vector2(0.5,0.5)
	var original_center:=Vector2(SITE)+Vector2(0.5,0.5)
	if position.distance_squared_to(sign_center)<position.distance_squared_to(original_center) and courtyard_available(state):
		return COURT_SIGN
	return SITE

static func log_ready(person:Dictionary)->bool:
	return person.get(KEY,false)==true and person.get(WEIR_KEY,0)==2

static func finish_log(person:Dictionary)->Dictionary:
	if person.get(LOG_KEY,false):return {"ok":false,"message":"〈潮水回來以前〉已經收進手帳。"}
	if not log_ready(person):return {"ok":false,"message":"先把花宅和石滬的觀察都帶回來吧。"}
	person[LOG_KEY]=true
	return {"ok":true,"message":"你和阿潮整理了〈潮水回來以前〉，現在可以從手帳重讀。"}

static func observe_tide(person:Dictionary,phase:String,high_tide:bool)->Dictionary:
	var current:=int(person.get(WEIR_KEY,0))
	if current==0 and phase=="high":
		if not high_tide:return {"ok":false,"message":"現場潮位偏低，等潮水回來再記錄漲潮。"}
		person[WEIR_KEY]=1
		return {"ok":true,"message":"記下漲潮時，魚群可以從水較深的地方游進石滬。"}
	if current==1 and phase=="low":
		if high_tide:return {"ok":false,"message":"現場潮位偏高，等石滬露出水面再記錄退潮。"}
		person[WEIR_KEY]=2
		return {"ok":true,"message":"已把完整的潮汐觀察收進地方記憶。"}
	return {"ok":false,"message":"請依序觀察漲潮與退潮。"}

static func record(person:Dictionary,value:String)->Dictionary:
	if person.get(KEY,false):return {"ok":false,"message":"這頁已收進你的手帳。"}
	if value!=ANSWER:return {"ok":false,"message":"再看看老屋旁那兩種在地的石材。"}
	person[KEY]=true
	return {"ok":true,"message":"已把〈花宅的兩種石頭〉收進地方記憶。"}
