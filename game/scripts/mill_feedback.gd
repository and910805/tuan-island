extends RefCounted
## Pure presentation helper for the Q05 flour mill (no canvas, IO, clocks or
## global state). It only READS a mill object as found in World state or in a
## Session public snapshot and never writes it, the save, or any inventory.
##
## Authoritative inputs it understands (see World/Logistics/SaveSchema/Session):
## - manual queue  `processing` {active:{}|record, waiting:[..], ready:[..]}
##   (CookingQueue shape, owners may be redacted). When present it wins; the
##   Session display-only `job` projection beside it is ignored.
## - legacy manual `job` {kind,owner,ready,ingredients,yield} (no `auto`).
## - automatic `job` {.., auto:true}: runs from the `input_wheat` buffer and,
##   once due, Logistics moves its yield into `items` (output buffer, cap 32).
## - `auto_enabled` (bool), `input_wheat` (0..32), `items` {flour:n}.
##
## Anything contradictory or of the wrong recipe is classified "invalid" and
## produces no overlay at all (never phantom processing).
##
## Coordinates returned by sample() are LOCAL to the 32x48 mill sprite (its
## top-left), matched to res://assets/bakery/mill.png: hopper throat ~x14,y16-19,
## outlet chute mouth ~x11-13,y33, flour sack mouth ~x9-14,y34-35.
const Industry=preload("res://scripts/industry.gd")
const Logistics=preload("res://scripts/logistics.gd")

const STATION:="mill"
const KIND:="flour"
const INPUT_FIELD:="input_wheat"
const FPS:=6.0
const PROGRESS_TRACK:=Rect2(8,0,16,3)
const PROGRESS_INNER:=14
const READY_BADGE:=Rect2(20,-6,12,12)
const OUTPUT_BADGE:=Rect2(21,34,10,10)
const MAX_PIPS:=4
const FLOUR:=Color("f6eedb")
const GRAIN:=Color("e2b043")
const DUST_DRIFT:=[0,1,0,-1]
const PUFF_X:=[11,13,12]
const DUST_CYCLE:=12
const GRAIN_CYCLE:=8

const PHASES:=["invalid","idle","working","blocked","ready","buffered"]

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value,minimum:int,maximum:int) -> bool:
	return _number(value) and floorf(float(value))==float(value) and float(value)>=minimum and float(value)<=maximum

static func duration() -> float:
	return float(Industry.PROCESS.get(KIND,{}).get("time",0.0))

static func recipe_yield() -> int:
	return int(Industry.PROCESS.get(KIND,{}).get("yield",1))

static func output_cap() -> int:
	return Logistics.PROCESS_OUTPUT_CAP

static func input_cap() -> int:
	return Logistics.PROCESS_INPUT_CAP

## Fixed-key status. Every count is a plain int, progress in [0,1].
static func _status(phase:String) -> Dictionary:
	return {"valid":phase!="invalid","phase":phase,"mode":"idle","working":false,"progress":0.0,
		"ready":0,"queued":0,"buffered":0,"wheat":0,"auto_enabled":false,"blocked":false,
		"active_kind":"","ready_kind":""}

static func invalid() -> Dictionary:
	return _status("invalid")

## A queue record of the mill recipe (shape only; World/SaveSchema own the
## exact validation). `phase` is "active", "waiting" or "ready".
static func _record_ok(record,phase:String) -> bool:
	if not record is Dictionary or Industry.PROCESS.get(record.get("kind",""),{}).get("station","")!=STATION:return false
	if not _whole(record.get("yield"),1,1000000000):return false
	if phase=="active":
		var started=record.get("started")
		var finish=record.get("finish")
		return _number(started) and _number(finish) and float(finish)>float(started)
	if phase=="ready":return _number(record.get("completed"))
	return true

## Classify one mill object at authoritative world time `world_time`.
static func classify(obj,world_time) -> Dictionary:
	if not obj is Dictionary or obj.get("type")!=STATION or not _number(world_time):return invalid()
	var now:=float(world_time)
	if now<0.0:return invalid()
	var auto_enabled=obj.get("auto_enabled",false)
	if not auto_enabled is bool:return invalid()
	var wheat=obj.get(INPUT_FIELD,0)
	if not _whole(wheat,0,input_cap()):return invalid()
	var items=obj.get("items",{})
	if not items is Dictionary:return invalid()
	for item in items:
		if item==KIND:continue
		# The output buffer may only ever hold this station's product.
		if not _whole(items[item],0,0):return invalid()
	var flour=items.get(KIND,0)
	if not _whole(flour,0,output_cap()):return invalid()
	var out:=_status("idle")
	out.auto_enabled=auto_enabled
	out.wheat=int(wheat)
	out.buffered=int(flour)
	if auto_enabled:out.mode="auto"
	var job=obj.get("job")
	if obj.has("job") and not job is Dictionary:return invalid()
	if obj.has("processing"):
		var queue=obj.get("processing")
		if auto_enabled or not queue is Dictionary:return invalid()
		# Session only ever projects a manual job; an auto job here is contradictory.
		if job is Dictionary and job.get("auto",false)!=false:return invalid()
		var active=queue.get("active")
		var waiting=queue.get("waiting")
		var ready=queue.get("ready")
		if not active is Dictionary or not waiting is Array or not ready is Array:return invalid()
		if active.is_empty() and not waiting.is_empty():return invalid()
		if not active.is_empty() and not _record_ok(active,"active"):return invalid()
		for record in waiting:
			if not _record_ok(record,"waiting"):return invalid()
		for record in ready:
			if not _record_ok(record,"ready"):return invalid()
		out.mode="manual"
		out.queued=waiting.size()
		out.ready=ready.size()
		if not ready.is_empty():out.ready_kind=ready[0].kind
		if not active.is_empty():
			var started:=float(active.started)
			var finish:=float(active.finish)
			if started<0.0 or started>now:return invalid()
			if finish>now:
				out.working=true
				out.active_kind=active.kind
				out.progress=clampf((now-started)/(finish-started),0.0,1.0)
			else:
				# Due but not yet advanced by World: finished work, never animated.
				out.ready+=1
				if out.ready_kind.is_empty():out.ready_kind=active.kind
	elif job is Dictionary:
		if job.get("kind")!=KIND or not _number(job.get("ready")):return invalid()
		if job.has("yield") and not _whole(job.yield,1,1000000000):return invalid()
		var is_auto=job.get("auto",false)
		if not is_auto is bool:return invalid()
		var ready_at:=float(job.ready)
		var span:=duration()
		if ready_at>now:
			out.working=true
			out.active_kind=KIND
			out.progress=clampf(1.0-(ready_at-now)/span,0.0,1.0) if span>0.0 else 0.0
		if is_auto:
			# An in-flight auto job keeps running even after auto is switched off
			# (Logistics completes it regardless), so it is real work.
			out.mode="auto"
			if not out.working and out.buffered+int(job.get("yield",recipe_yield()))>output_cap():out.blocked=true
		else:
			out.mode="manual"
			if not out.working:
				out.ready=1
				out.ready_kind=KIND
	if out.working:out.phase="working"
	elif out.blocked:out.phase="blocked"
	elif out.ready>0:out.phase="ready"
	elif out.buffered>0:out.phase="buffered"
	return out

## Deterministic draw description for `status` at presentation clock `clock`.
## Returns {motion, pixels:[{rect,color}], progress:{track,fill}|{}, badges:[..]}.
## Reduced motion keeps only static readable state (no frame dependence).
static func sample(status:Dictionary,clock,reduced:bool) -> Dictionary:
	var out:={"motion":false,"pixels":[],"progress":{},"badges":[]}
	if not status.get("valid",false):return out
	var working:bool=status.get("working",false)
	if working:
		var powder:=GRAIN if status.get("active_kind")=="feed" else FLOUR
		var fill:=clampi(int(floorf(float(status.get("progress",0.0))*PROGRESS_INNER)),0,PROGRESS_INNER)
		out.progress={"track":PROGRESS_TRACK,"fill":Rect2(PROGRESS_TRACK.position+Vector2(1,1),Vector2(fill,1))}
		# Flour leaving the outlet chute into the sack: always shown while working.
		out.pixels.append({"rect":Rect2(12,33,1,2),"color":_tint(powder,0.9)})
		if reduced or not _number(clock):
			out.pixels.append({"rect":Rect2(14,17,1,1),"color":GRAIN})
		else:
			out.motion=true
			var frame:=int(floorf(fposmod(float(clock),3600.0)*FPS))
			# Falling grain in the hopper throat (feeds the stones).
			var g:=frame%GRAIN_CYCLE
			if g<4:out.pixels.append({"rect":Rect2(14,15+g,1,1),"color":GRAIN})
			# Puff where the stream lands in the sack.
			out.pixels.append({"rect":Rect2(float(PUFF_X[frame%PUFF_X.size()]),35,1,1),"color":_tint(powder,0.8)})
			# Three tiny dust motes rising and fading above the sack mouth.
			for index in 3:
				var step:=(frame+index*4)%DUST_CYCLE
				var t:=float(step)/float(DUST_CYCLE)
				var drift:=int(DUST_DRIFT[(int(frame/3.0)+index)%DUST_DRIFT.size()])
				out.pixels.append({"rect":Rect2(float(10+index*2+drift),34-int(floorf(t*4.0)),1,1),"color":_tint(powder,0.75*(1.0-t))})
	if int(status.get("ready",0))>0:
		out.badges.append({"kind":"manual_ready","rect":READY_BADGE,"count":int(status.ready),"full":false,"item":str(status.get("ready_kind",KIND))})
	if int(status.get("buffered",0))>0 or status.get("blocked",false):
		out.badges.append({"kind":"auto_output","rect":OUTPUT_BADGE,"count":int(status.get("buffered",0)),
			"full":status.get("blocked",false) or int(status.get("buffered",0))>=output_cap()})
	return out

static func _tint(color:Color,alpha:float) -> Color:
	var c:=color
	c.a=clampf(alpha,0.0,1.0)
	return c

## Short caption suffix for the focused world label ("" when nothing to say).
static func caption(status:Dictionary) -> String:
	if not status.get("valid",false):return ""
	if status.working:
		var suffix:=" · 加工中 %d%%"%int(floorf(float(status.progress)*100.0))
		if status.ready>0:suffix+=" · %d 批待領"%int(status.ready)
		return suffix
	if status.ready>0:return " · 可領取 ×%d"%int(status.ready)
	if status.blocked:return " · 輸出已滿"
	if status.buffered>0:return " · 麵粉 ×%d"%int(status.buffered)
	if status.auto_enabled:return " · 小麥 %d／%d"%[int(status.wheat),input_cap()]
	return ""
