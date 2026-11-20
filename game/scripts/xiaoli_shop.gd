extends RefCounted

const NAME_KEY:="xiaoli_shop_name"
const SCALE_KEY:="xiaoli_scale_claimed"
const SCALE_ITEM:="xiaoli_memorial_scale"
const SCALE_NAME:="小栗的紀念秤"
const SIGN_ACTION:="xiaoli_shop_sign"
const SCALE_ACTION:="xiaoli_shop_scale"
const MAX_NAME:=12
const BAD_NAME:="店名最多 12 字，可以留空。請移除冒號或換行。"
const DEFAULT_NAME:="渡口小店"
const PRESETS:={"chestnut":"小栗的種子舖","tomorrow":"明天也在"}

static func valid_name(value:Variant) -> bool:
	if not value is String or value.length()>MAX_NAME or value!=value.strip_edges():return false
	for i in value.length():
		var code:int=value.unicode_at(i)
		if code<32 or code==58 or (code>=127 and code<=159) or (code>=0x200b and code<=0x206f):return false
	return true

static func shop_name(person:Dictionary,choice:String) -> String:
	var custom:=str(person.get(NAME_KEY,PRESETS.get(choice,"")))
	return DEFAULT_NAME if custom.is_empty() else custom

static func valid_save(person:Dictionary,finished:bool) -> bool:
	if person.has(NAME_KEY) and (not finished or not valid_name(person[NAME_KEY])):return false
	return not person.has(SCALE_KEY) or (finished and person[SCALE_KEY] is bool and person[SCALE_KEY])

static func claim_scale(person:Dictionary) -> Dictionary:
	if person.get(SCALE_KEY,false):return {"ok":false,"message":"紀念秤已放進背包了。"}
	var bag:Dictionary=person.inventory
	if int(bag.get(SCALE_ITEM,0))>=1000000000:return {"ok":false,"message":"背包中的紀念秤已達上限。"}
	bag[SCALE_ITEM]=int(bag.get(SCALE_ITEM,0))+1
	person[SCALE_KEY]=true
	return {"ok":true,"message":"小栗把紀念秤交給你了，可以在背包裡查看。"}
