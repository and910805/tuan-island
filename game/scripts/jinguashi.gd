extends RefCounted

const NODES := [Vector2i(28,20),Vector2i(30,22),Vector2i(33,23)]
const ENTRANCE_FOOTPRINT := Rect2i(24,16,9,3)
const COOLDOWN := 12.0
const YIELD := 4

static func valid(state: Dictionary) -> bool:
	var data = state.get("jinguashi")
	if not data is Dictionary or data.size() != 1 or not data.get("ready") is Dictionary:
		return false
	var keys := NODES.map(func(p: Vector2i): return "%d,%d" % [p.x,p.y])
	for key in data.ready:
		var expiry = data.ready[key]
		if key not in keys or not (expiry is int or expiry is float) or not is_finite(expiry) or expiry < 0 or expiry > float(state.time) + COOLDOWN:
			return false
	return true
