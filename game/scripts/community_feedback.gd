extends RefCounted
## Presentation-only public kitchen scene response. Never preloads World, never
## mutates its inputs, never awards anything and never reads snapshot clocks.
##
## observe() compares HOME snapshots; sample() returns a short-lived visual cue:
##   {} when inactive / reduced motion, otherwise
##   {"kind":"contribute"|"opened", "age":float, "meals":Array[String]}

const PK := preload("res://scripts/public_kitchen.gd")
const Shared := preload("res://scripts/community.gd")
const SHARED_DURATION := 1.35
const CLAIM_DURATION := 0.8

const DURATION_CONTRIBUTE := 2.0
const DURATION_OPENED := 4.0
const CONTRIBUTE := "contribute"
const OPENED := "opened"

## Last valid registered HOME kitchen observed: {stove, seats, meals, opened} or {}.
var _last: Dictionary = {}
## Active cue: {kind, start, meals} or {}.
var _event: Dictionary = {}
var _shared_starts: Dictionary = {}
var _claim_starts: Dictionary = {}

func reset() -> void:
	_last = {}
	_event = {}
	_shared_starts.clear()
	_claim_starts.clear()

static func _valid_time(now: float) -> bool:
	return is_finite(now) and now >= 0.0

## Private copy of a valid registered HOME kitchen, else {}.
static func _kitchen(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():return {}
	var region = snapshot.get("region_id", PK.HOME)
	if not region is String or region != PK.HOME:return {}
	var data = snapshot.get("public_kitchen")
	if not PK.shape_ok(data) or data.stove == "":return {}
	var meals := {}
	for item in PK.MEALS:meals[item] = int(data.meals[item])
	var seats: Array[String] = []
	for seat in data.seats:seats.append(str(seat))
	return {"stove":str(data.stove), "seats":seats, "meals":meals, "opened":bool(data.opened)}

static func _same_site(a: Dictionary, b: Dictionary) -> bool:
	return a.stove == b.stove and a.seats == b.seats

func observe(previous: Dictionary, next: Dictionary, now: float) -> void:
	if not _valid_time(now):
		reset()
		return
	_observe_shared(previous,next,now)
	var after := _kitchen(next)
	if after.is_empty():
		# Region switch, unregistered/reset or malformed kitchen: clear everything.
		_last = {}
		_event = {}
		return
	if previous.is_empty():
		# Initial snapshot, join or reconnect: adopt silently.
		_event = {}
		_last = after
		return
	var before := _kitchen(previous)
	if before.is_empty():
		# A previous region/reset snapshot is not a contribution baseline, even
		# if this helper still holds an older HOME snapshot.
		_event = {}
		_last = after
		return
	if not _same_site(before, after):
		_event = {}
		_last = after
		return
	if before.opened and not after.opened:
		_event = {}
		_last = after
		return
	var increased: Array[String] = []
	for item in PK.MEALS:
		var delta: int = int(after.meals[item]) - int(before.meals[item])
		if delta < 0:
			_event = {}
			_last = after
			return
		if delta > 0:increased.append(item)
	# Deduplicate an already observed transition without extending its lifetime.
	if after == _last:return
	_last = after
	if not before.opened and after.opened:
		_event = {"kind":OPENED, "start":now, "meals":increased}
		return
	if increased.is_empty():return  # repeated/replayed snapshot: keep original start
	if _active_kind(now) == OPENED:return  # opening wins while it is still playing
	_event = {"kind":CONTRIBUTE, "start":now, "meals":increased}

func _observe_shared(previous:Dictionary,next:Dictionary,now:float)->void:
	var before:Dictionary=previous.get("community",{})
	var after:Dictionary=next.get("community",{})
	if previous.get("region_id","home")!="home" or next.get("region_id","home")!="home" or Shared.table_cell(next)==Shared.NO_CELL or before.get("table")!=after.get("table") or float(next.get("time",0))<float(previous.get("time",0)):
		_shared_starts.clear()
		_claim_starts.clear()
		return
	for dish:String in Shared.DISHES:
		var plate:String=Shared.DISHES[dish]
		var old_count:=int(before.get(dish,{}).get("portions",0))
		var latest:Dictionary=after.get(dish,{})
		if latest.is_empty():
			_shared_starts.erase(plate)
			_claim_starts.erase(plate)
			continue
		var new_count:=int(latest.get("portions",0))
		if old_count==0 and new_count>0:
			_shared_starts[plate]=now
			_claim_starts.erase(plate)
		elif new_count<old_count:
			_claim_starts[plate]=now
			_shared_starts.erase(plate)

func sample_shared(now:float,reduced:bool)->Dictionary:
	return _sample_plates(_shared_starts,SHARED_DURATION,now,reduced)

func sample_claims(now:float,reduced:bool)->Dictionary:
	return _sample_plates(_claim_starts,CLAIM_DURATION,now,reduced)

func _sample_plates(starts:Dictionary,duration:float,now:float,reduced:bool)->Dictionary:
	if reduced or not _valid_time(now):return {}
	var progress:Dictionary={}
	for plate:String in starts:
		var age:=now-float(starts[plate])
		if age>=0.0 and age<duration:
			progress[plate]=age/duration
	return progress

func _duration(kind: String) -> float:
	return DURATION_OPENED if kind == OPENED else DURATION_CONTRIBUTE

func _active_kind(now: float) -> String:
	if _event.is_empty():return ""
	var age: float = now - float(_event.start)
	if age < 0.0 or age >= _duration(_event.kind):return ""
	return _event.kind

func sample(now: float, reduced: bool) -> Dictionary:
	if reduced or not _valid_time(now) or _event.is_empty():return {}
	var kind: String = _event.kind
	var age: float = now - float(_event.start)
	if age < 0.0:return {}
	if age >= _duration(kind):
		_event = {}
		return {}
	var meals: Array[String] = []
	for item in _event.meals:meals.append(item)
	return {"kind":kind, "age":age, "meals":meals}
