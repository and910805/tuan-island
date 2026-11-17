extends RefCounted

const LIMIT := 16
const LENGTH := 120
const REVISION_LIMIT := 1000000000000
## Append new projects so existing players' read masks retain their meaning.
const PROJECTS := ["河灣橋","蘭陽水圳","田尾公共花園","北門鹽田水門","渡口公共廚房","金瓜石第五層礦道"]
const LOCAL_PROJECTS := [
	["金瓜石升降台","從山城入口可直達已開放的升降台停靠層。"],
	["金瓜石第十五層礦道","最深一層已開放，可從第十四層的下行入口前往。"],
	["礁溪公共泡腳池","暖暖修好了泡腳池，旅人可在外頭休息回暖。"],
	["貓空茶屋","茶屋已開放布置，到展示桌可以借展茶陶組。"],
]
static func project_mask() -> int:
	return (1<<PROJECTS.size())-1

static func news_project_limit() -> int:
	return (1<<(PROJECTS.size()+LOCAL_PROJECTS.size()))-1

static func news_project_names() -> Array:
	var names:=PROJECTS.duplicate()
	for entry in LOCAL_PROJECTS:names.append(entry[0])
	return names

static func revision(state:Dictionary) -> int:
	return int(state.get("island_note_revision",state.get("island_notes",[]).size()))

static func unread(state:Dictionary,person:Dictionary) -> int:
	return mini(state.get("island_notes",[]).size(), revision(state)-int(person.get("island_note_seen",0)))

static func clean(raw:String) -> String:
	if raw.length()>LENGTH:return ""
	for index in raw.length():
		var code:=raw.unicode_at(index)
		if code<32 or code in range(127,160) or code in range(8234,8239) or code in range(8294,8298):return ""
	return raw.strip_edges()

static func valid(notes:Variant, now:float) -> bool:
	if not notes is Array or notes.size()>LIMIT:return false
	for note in notes:
		if not note is Dictionary or note.size()!=3:return false
		if not note.get("sender") is String or note.sender.length()>12:return false
		if not note.get("text") is String or clean(note.text)!=note.text or note.text.is_empty():return false
		var time=note.get("time")
		if not (time is int or time is float) or not is_finite(float(time)) or time<0 or time>now:return false
	return true
