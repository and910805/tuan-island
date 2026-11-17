extends RefCounted

const Weather=preload("res://scripts/weather.gd")

const SERVICE := Vector2i(33,29)
const OBSERVATIONS := [Vector2i(33,22),Vector2i(33,25),Vector2i(33,32)]
const DEMANDS := [[4,4,4],[2,6,4],[4,2,6]]
const ACTIONS := ["memory_observe","memory_gate","memory_flow","memory_plaque"]

static func fresh() -> Dictionary:
	return {"players":{},"plaque":false}

static func fresh_record() -> Dictionary:
	return {"seen":[],"round":0,"gates":[0,0],"completed":false}

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x,cell.y]

static func distribution(gates: Array) -> Array:
	var first := 2 * int(gates[0])
	var second := mini(12 - first,2 * int(gates[1]))
	return [first,second,12-first-second]

static func integer(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= maximum and floor(value) == value

static func valid(state: Dictionary) -> bool:
	var memory = state.get("history_memory")
	if not memory is Dictionary or memory.size() != 2 or not memory.get("players") is Dictionary or not memory.get("plaque") is bool:
		return false
	if not state.lanyang_life.repaired and (memory.plaque or not memory.players.is_empty()):
		return false
	var allowed := OBSERVATIONS.map(key)
	var has_completed := false
	for actor in memory.players:
		var record = memory.players[actor]
		if not state.players.has(actor) or not record is Dictionary or record.size() != (5 if record.has("completed_day") else 4):
			return false
		if not record.get("seen") is Array or not record.get("gates") is Array or record.gates.size() != 2:
			return false
		if not integer(record.get("round"),DEMANDS.size()) or not record.get("completed") is bool:
			return false
		if not integer(record.gates[0],3) or not integer(record.gates[1],3):
			return false
		var seen := {}
		for site in record.seen:
			if site not in allowed or seen.has(site):return false
			seen[site] = true
		if seen.is_empty():return false
		var finished: bool = record.round == DEMANDS.size()
		if record.completed != finished:
			return false
		if record.has("completed_day") and (not finished or not integer(record.completed_day,int(Weather.day_index(state.time)))):
			return false
		if (seen.size() < allowed.size() or finished) and (record.gates[0] != 0 or record.gates[1] != 0):
			return false
		if seen.size() < allowed.size() and record.round != 0:
			return false
		has_completed = has_completed or finished
	return not memory.plaque or has_completed

static func apply(state: Dictionary, actor: String, action: String, cell: Vector2i, value: String) -> Dictionary:
	if not state.lanyang_life.repaired:
		return result(false,"先修好蘭陽水圳。")
	var memory: Dictionary = state.history_memory
	var record: Dictionary = memory.players.get(actor,fresh_record())
	if action == "memory_observe":
		if cell not in OBSERVATIONS or not value.is_empty():
			return result(false,"請靠近水圳觀察點。")
		var id := key(cell)
		if id in record.seen:
			return result(false,"這一處已記在觀察簿。")
		record.seen.append(id)
		memory.players[actor] = record
		return result(true,"已把水口的配置記進觀察簿。")
	if cell != SERVICE:
		return result(false,"請到橋邊找星禾。")
	if action == "memory_plaque":
		if not record.completed or memory.plaque or not value.is_empty():
			return result(false,"完成配水練習後可一起設置紀念牌。")
		memory.plaque = true
		return result(true,"已在橋邊設置配水紀念牌。")
	if record.seen.size() != OBSERVATIONS.size() or record.completed:
		return result(false,"請先完成三處觀察，再開始配水練習。")
	if action == "memory_gate":
		if value not in ["a:0","a:1","a:2","a:3","b:0","b:1","b:2","b:3"]:
			return result(false,"閘門只可調整為零到三檔。")
		record.gates[0 if value.begins_with("a") else 1] = int(value.right(1))
		return result(true,"已調整練習閘門。")
	if action != "memory_flow" or not value.is_empty() or distribution(record.gates) != DEMANDS[int(record.round)]:
		return result(false,"目前配水量不符合這一輪需求。")
	record.round = int(record.round) + 1
	record.gates = [0,0]
	record.completed = record.round == DEMANDS.size()
	if record.completed:
		record.completed_day=int(Weather.day_index(state.time))
	return result(true,"完成三輪配水練習。" if record.completed else "這一輪配水成功。")

static func result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message}
