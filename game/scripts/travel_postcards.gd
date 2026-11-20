extends RefCounted

const RACK:="sea_breeze_postcard_rack"
const SLOTS:="postcard_display"
const PUT:="postcard_rack_put"
const TAKE:="postcard_rack_take"
const CAPACITY:=3
const UNLOCK_MESSAGE:="完成洛洛的〈沒有地址的信〉後可建造。"
const CARDS:={
	"toucheng":"頭城車站",
	"jinguashi":"金瓜石山城",
	"maokong":"貓空合作茶園",
	"yingge":"鶯歌合作陶坊",
	"tianwei":"田尾合作花圃",
	"beimen":"北門鹽田",
}

static func earned(person:Dictionary)->Array[String]:
	var cards:Array[String]=[]
	var visited:Dictionary=person.get("travel_book",{}).get("visited",{})
	var explored:Dictionary=person.get("explored_regions",{})
	for id:String in CARDS:
		if visited.get(id,false)==true or explored.get(id,false)==true:cards.append(id)
	return cards

static func valid_display(value:Variant)->bool:
	if not value is Array or value.is_empty() or value.size()>CAPACITY:return false
	var seen:={}
	for id in value:
		if not id is String or not CARDS.has(id) or seen.has(id):return false
		seen[id]=true
	return true
