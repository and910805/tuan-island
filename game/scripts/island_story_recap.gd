extends RefCounted
## T075 returning-player recap for the ferry dock chapter.
## Pure and deterministic: reads either a world state or a client snapshot
## (session snapshot with `festival_story`) and returns player-facing
## Traditional Chinese recap data. Never mutates its input.
##
## Marker bits (store per player, e.g. as `ferry_recap_seen`):
##   bits 0-1  dock stage 0..2
##   bit  2    festival opening happened
##   bit  3    bamboo-valley boat route visible
## A negative / missing marker means "never saw a recap" (legacy players).

const Transit=preload("res://scripts/transit.gd")

const DOCK_STAGES:=2
const REPLAY_SCENES:=3
const NO_MARKER:=-1
const BIT_OPENED:=4
const BIT_BAMBOO:=8

const PIER_TITLE:="渡口碼頭修好了"
const PIER_BODY:="大家交齊木板與石材，渡口碼頭重新站穩了。"
const BOAT_TITLE:="合作小船完工"
const BOAT_BODY:="小船已就緒，從風鈴渡口就能直接出航。"
const OPENING_TITLE:="風鈴節開幕了"
const OPENING_BODY:="六項工程、共餐料理和燈光都備齊，大家沿著燈光回到渡口。"
const REPLAY_TITLE:="重看風鈴節開幕回憶"
const PENDING_PIER:="碼頭待修：到渡口公告板查看工程材料。"
const PENDING_BOAT:="碼頭已修好，小船還在等材料：到渡口公告板查看。"
const PENDING_FESTIVAL:="小船已就緒，接著到渡口公告板籌備風鈴節。"
const PENDING_BAMBOO:="霧竹溪谷航線會在茶園故事開放後加入。"
const DONE_ALL:="渡口的故事都已完成，可以隨時重看開幕回憶。"

## Normalized progress. Tolerates legacy snapshots (missing keys, JSON floats,
## out-of-range numbers, wrong types) without crashing.
static func read_progress(snapshot:Variant)->Dictionary:
	var s:Dictionary=snapshot if snapshot is Dictionary else {}
	var view:Dictionary=s.get("festival_story",{}) if s.get("festival_story") is Dictionary else {}
	var stage:=0
	var raw:Variant=s.get("dock_stage")
	if raw is int or raw is float:
		stage=clampi(int(raw),0,DOCK_STAGES)
	elif _true(view.get("boat_ready")):
		# Older client snapshots only carried the festival view.
		stage=DOCK_STAGES
	var opened:=_true(s.get("festival_story_open")) or _true(view.get("opened"))
	if opened:stage=DOCK_STAGES # opening requires the boat; repair impossible legacy combos
	var bamboo:=_tea_open(s)
	var destinations:Array[Dictionary]=[]
	if stage>=DOCK_STAGES:
		for region in [Transit.Springs.REGION,Transit.Bamboo.REGION]:
			if region==Transit.Bamboo.REGION and not bamboo:continue
			destinations.append({"region":region,"label":str(Transit.STATIONS[region].name)})
	return {"dock_stage":stage,"boat_ready":stage>=DOCK_STAGES,"festival_opened":opened,
		"bamboo_route":bamboo and stage>=DOCK_STAGES,"destinations":destinations,
		"projects":int(view.get("projects",0)) if (view.get("projects") is int or view.get("projects") is float) else -1,
		"meal":_true(view.get("meal")),
		"lights":int(view.get("lights",0)) if (view.get("lights") is int or view.get("lights") is float) else -1}

static func marker(snapshot:Variant)->int:
	var p:=read_progress(snapshot)
	return int(p.dock_stage)|(BIT_OPENED if p.festival_opened else 0)|(BIT_BAMBOO if p.bamboo_route else 0)

## Builds the recap. `seen_marker` is the value of marker() the player last
## acknowledged; pass NO_MARKER (or any non-int) for a player without one.
static func build(snapshot:Variant,seen_marker:Variant=NO_MARKER)->Dictionary:
	var p:=read_progress(snapshot)
	var seen:=int(seen_marker) if (seen_marker is int or seen_marker is float) and int(seen_marker)>=0 else NO_MARKER
	var seen_stage:=0 if seen<0 else clampi(seen&3,0,DOCK_STAGES)
	var seen_opened:=seen>=0 and (seen&BIT_OPENED)!=0
	var seen_bamboo:=seen>=0 and (seen&BIT_BAMBOO)!=0
	var stage:=int(p.dock_stage)
	var entries:Array[Dictionary]=[]
	if stage>=1:
		entries.append(_entry("dock_pier",PIER_TITLE,PIER_BODY,seen_stage<1))
	if stage>=2:
		entries.append(_entry("dock_boat",BOAT_TITLE,BOAT_BODY,seen_stage<2))
		var labels:PackedStringArray=[]
		for d in p.destinations:labels.append(str(d.label))
		var route_body:="合作小船直航：%s。"%"、".join(labels)
		if not p.bamboo_route:route_body+=PENDING_BAMBOO
		entries.append(_entry("boat_routes","小船航線",route_body,seen_stage<2 or (p.bamboo_route and not seen_bamboo)))
	if p.festival_opened:
		entries.append(_entry("festival_opening",OPENING_TITLE,OPENING_BODY,not seen_opened))
		var replay:=_entry("festival_replay",REPLAY_TITLE,"在手帳的居民回憶裡可重看 %d 幕開幕回憶。"%REPLAY_SCENES,false)
		replay.action="festival_story"
		replay.scenes=REPLAY_SCENES
		entries.append(replay)
	var fresh:PackedStringArray=[]
	for e in entries:
		if e.new:fresh.append(str(e.title))
	var headline:="你不在的時候：%s。"%"、".join(fresh) if not fresh.is_empty() else "渡口這邊沒有新的變化。"
	return {"marker":marker(snapshot),"has_news":not fresh.is_empty(),"headline":headline,
		"entries":entries,"next_step":_next_step(p),"can_replay":bool(p.festival_opened)}

static func _entry(id:String,title:String,body:String,is_new:bool)->Dictionary:
	return {"id":id,"title":title,"body":body,"new":is_new,"action":"","scenes":0}

static func _next_step(p:Dictionary)->String:
	var stage:=int(p.dock_stage)
	if stage==0:return PENDING_PIER
	if stage==1:return PENDING_BOAT
	if p.festival_opened:return DONE_ALL
	var parts:PackedStringArray=[]
	if int(p.lights)>=0:parts.append("共餐桌旁燈飾 %d／2"%mini(int(p.lights),2))
	if int(p.projects)>=0:parts.append("共餐料理%s"%("已備妥" if p.meal else "待準備"))
	return PENDING_FESTIVAL if parts.is_empty() else "%s（%s）"%[PENDING_FESTIVAL,"・".join(parts)]

## Mirrors chapter_one.phase(state)=="complete" without crashing on legacy
## snapshots that lack `board` or chapter fields.
static func _tea_open(s:Dictionary)->bool:
	var chapter:Variant=s.get("chapter_one")
	if not chapter is Dictionary:return false
	return _true(chapter.get("shipped")) and _true(s.get("board")) and _true(chapter.get("watered")) and _true(s.get("picnic"))

static func _true(value:Variant)->bool:
	return value is bool and value
