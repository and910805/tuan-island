extends RefCounted

const SERVICE := Vector2i(33,29)
const BLOCKAGES := [Vector2i(33,22),Vector2i(33,25),Vector2i(33,32)]
const REPAIR_COST := {"plank":6,"stone":8,"resin":2}
const NURSERY_COST := {"sapling":1,"fiber":4,"wood":2}
const NURSERY_TIME := 60.0
const NURSERY_YIELD := 3
const REPAIRED_PUMP_RATE := 12
const ACTIONS := ["lanyang_clear","lanyang_donate","nursery_start","nursery_claim"]

static func fresh() -> Dictionary:
	return {"cleared":{},"donations":{"plank":0,"stone":0,"resin":0},"repaired":false,"jobs":{}}

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x,cell.y]

static func next_step(state: Dictionary) -> Dictionary:
	var progress: Dictionary = state.get("lanyang_life",fresh())
	for cell: Vector2i in BLOCKAGES:
		if not progress.cleared.has(key(cell)):
			return {"id":"clear","cell":cell,"action":"沿水圳清開三處枯枝"}
	if progress.repaired:
		return {"id":"nursery","cell":SERVICE,"action":"到星禾的育苗盤培育樹苗"}
	return {"id":"donate","cell":SERVICE,"action":"帶木板、石材與樹脂修閘門"}

static func whole(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= maximum and floor(value) == value

static func valid(state: Dictionary) -> bool:
	var progress = state.get("lanyang_life")
	if not progress is Dictionary or progress.size() != 4 or not progress.get("repaired") is bool:
		return false
	if not progress.get("cleared") is Dictionary or not progress.get("donations") is Dictionary or not progress.get("jobs") is Dictionary:
		return false
	if progress.donations.size() != REPAIR_COST.size():
		return false
	var cleared_keys := []
	for cell in BLOCKAGES:
		cleared_keys.append(key(cell))
	for id in progress.cleared:
		if id not in cleared_keys or not progress.cleared[id] is bool or not progress.cleared[id]:
			return false
	var supplied := true
	for item in REPAIR_COST:
		var count = progress.donations.get(item)
		if not whole(count,REPAIR_COST[item]) or (count > 0 and progress.cleared.size() != BLOCKAGES.size()):
			return false
		supplied = supplied and count == REPAIR_COST[item]
	if progress.repaired != (supplied and progress.cleared.size() == BLOCKAGES.size()):
		return false
	if not progress.repaired and not progress.jobs.is_empty():
		return false
	for actor in progress.jobs:
		var job = progress.jobs[actor]
		if not state.players.has(actor) or not job is Dictionary or job.size() != 1:
			return false
		var ready = job.get("ready")
		if not (ready is int or ready is float) or not is_finite(ready) or ready < NURSERY_TIME or ready > float(state.time) + NURSERY_TIME:
			return false
	return true
