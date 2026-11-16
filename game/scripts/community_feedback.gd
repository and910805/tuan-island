extends RefCounted
## Presentation-only public kitchen scene response. Never preloads World, never
## mutates its inputs, never awards anything and never reads snapshot clocks.
##
## observe() compares HOME snapshots; sample() returns a short-lived visual cue:
##   {} when inactive / reduced motion, otherwise
##   {"kind":"contribute"|"opened", "age":float, "meals":Array[String]}

const PK := preload("res://scripts/public_kitchen.gd")

const DURATION_CONTRIBUTE := 2.0
const DURATION_OPENED := 4.0
const CONTRIBUTE := "contribute"
const OPENED := "opened"

## Last valid registered HOME kitchen observed: {stove, seats, meals, opened} or {}.
var _last: Dictionary = {}
## Active cue: {kind, start, meals} or {}.
var _event: Dictionary = {}

func reset() -> void:
	_last = {}
	_event = {}

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
	var after := _kitchen(next)
	if after.is_empty():
		# Region switch, unregistered/reset or malformed kitchen: clear everything.
		reset()
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
