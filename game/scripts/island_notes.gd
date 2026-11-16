extends RefCounted

const LIMIT := 16
const LENGTH := 120
## Append new projects so existing players' read masks retain their meaning.
const PROJECTS := ["河灣橋","蘭陽水圳","田尾公共花園","北門鹽田水門","渡口公共廚房","金瓜石第五層礦道"]
static func project_mask() -> int:
	return (1<<PROJECTS.size())-1

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
