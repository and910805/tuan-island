extends RefCounted

const KIND:="inn_welcome_sign"
const WRITE:="write_welcome_sign"
const LIMITS:=[12,24,24]
const MAX_BYTES:=420
const Notes=preload("res://scripts/island_notes.gd")

static func valid(lines:Variant) -> bool:
	if not lines is Array or lines.size()!=LIMITS.size():return false
	for i in LIMITS.size():
		var value=lines[i]
		if not value is String or value.length()>LIMITS[i] or value!=Notes.clean(value):return false
		for index in value.length():
			if value.unicode_at(index) in [0x061c,0x200e,0x200f,0x2028,0x2029]:return false
	return true

static func decode(payload:String) -> Array:
	if payload.length()>MAX_BYTES or payload.to_utf8_buffer().size()>MAX_BYTES:return []
	var lines=JSON.parse_string(payload)
	return lines if valid(lines) else []
