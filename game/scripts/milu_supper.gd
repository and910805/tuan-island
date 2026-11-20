extends RefCounted
## N02-4 optional extras for Milu's "remember to keep a bowl for yourself" story.
## Authoritative, personal and purely cosmetic: it never changes who may complete N02-4
## (that still needs the player's own successful shared-table serve and the hand-in near Milu),
## never adds shared portions, and never touches public table contention or seating.
##
## Player key `milu_supper` = {"dish":String,"guests":Array[String]}
##   dish   canonical item id from COMMUNITY.DISHES.values(), or "" for a player who served
##          before this field existed (legacy) — no migration guesses the dish.
##   guests 0..2 distinct ids from INVITEES, seats in this player's own story scene only.
## The key is omitted until there is something to remember. Other players never see it.
const COMMUNITY=preload("res://scripts/community.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")

const KEY:="milu_supper"
const VIEW_KEY:="own_milu_supper"
const ACTION:="milu_supper_invite"
const INVITEES:=["aru","xiaoli","lingpopo"]
const MAX_GUESTS:=2
const RESIDENT:="milu"
const STAGE:=4
const REACH:=3.2

const WRONG_PLACE:="請到風鈴渡口的共餐桌邊再邀請朋友。"
const NOT_OPEN:="米露的〈記得替自己留一碗〉還沒開始，或已經完成了。"
const NOT_SERVED:="先親手把料理端上共餐桌，再邀朋友入座。"
const BAD_GUEST:="只能邀請阿榆、小栗或鈴婆婆。"
const ABSENT:="這位朋友現在不在島上。"
const FULL:="餐桌邊只留得下兩個位置。"

static func empty() -> Dictionary:
	return {"dish":"","guests":[]}

static func dishes() -> Array:
	return COMMUNITY.DISHES.values()

static func served(person:Dictionary) -> bool:
	var events:Variant=person.get("resident_participation")
	return events is Dictionary and events.get(Goals.SHARED_MEAL_EVENT,false)==true

## True while the player's own N02-4 is neither done nor locked behind the bond stage.
static func open(person:Dictionary) -> bool:
	return Bond.stage(person,RESIDENT)>=STAGE and not Goals.done(person,RESIDENT).has(STAGE)

static func completed(person:Dictionary) -> bool:
	return Goals.done(person,RESIDENT).has(STAGE)

## Normalised copy of the stored record; defaults for absent or unusable data (read only).
static func view(person:Dictionary) -> Dictionary:
	var result:=empty()
	var raw:Variant=person.get(KEY)
	if not raw is Dictionary or not valid_shape(raw):return result
	result.dish=str(raw.get("dish",""))
	for id:Variant in raw.get("guests",[]):result.guests.append(str(id))
	return result

## Shape only: {} or exactly {dish,guests} with known values.
static func valid_shape(record:Variant) -> bool:
	if not record is Dictionary:return false
	if record.is_empty():return true
	if record.size()!=2 or not record.get("dish") is String or not record.get("guests") is Array:return false
	if not (record.dish.is_empty() or record.dish in dishes()):return false
	if record.guests.size()>MAX_GUESTS:return false
	var seen:={}
	for id:Variant in record.guests:
		if not id is String or id not in INVITEES or seen.has(id):return false
		seen[id]=true
	return true

## Save check: strict shape, and nothing is remembered before this player really served;
## guests also need Milu's stage 4 to have been reached. No migration, no repair.
static func valid(record:Variant,person:Dictionary) -> bool:
	if not valid_shape(record):return false
	if record.is_empty():return true
	if not record.dish.is_empty() and not served(person):return false
	if not record.guests.is_empty() and (not served(person) or Bond.stage(person,RESIDENT)<STAGE):return false
	return true

## Called after this player's successful ordinary (or warm hotpot) serve. Remembers the actual
## dish until the person's own N02-4 is done; invited guests are kept. Returns true when written.
static func record_serve(person:Dictionary,item:String) -> bool:
	if item not in dishes() or completed(person):return false
	var record:=view(person)
	record.dish=item
	person[KEY]=record
	return true

## Toggle one guest. `extra` is the NPC id. Everything is checked before anything is written.
static func apply(state:Dictionary,person:Dictionary,at_home:bool,p:Vector2i,dist:float,extra:String) -> Dictionary:
	var table:Vector2i=COMMUNITY.table_cell(state)
	if not at_home or state.get("picnic",false)!=true or table==COMMUNITY.NO_CELL or p!=table or dist>REACH:
		return _fail(WRONG_PLACE)
	if not open(person):return _fail(NOT_OPEN)
	if not served(person):return _fail(NOT_SERVED)
	if extra not in INVITEES:return _fail(BAD_GUEST)
	var raw:Variant=person.get(KEY)
	if raw!=null and not valid(raw,person):return _fail(NOT_OPEN)
	var record:=view(person)
	var guests:Array=record.guests
	var name:String=Bond.name_of(extra)
	if extra in guests:
		guests.erase(extra)
		_store(person,record)
		return {"ok":true,"message":"已取消給%s的共餐邀請。"%name}
	if not Bond.present(state,extra):return _fail(ABSENT)
	if guests.size()>=MAX_GUESTS:return _fail(FULL)
	guests.append(extra)
	var ordered:Array=[]
	for id:String in INVITEES:
		if id in guests:ordered.append(id)
	record.guests=ordered
	_store(person,record)
	return {"ok":true,"message":"%s答應來參加共餐。"%name}

static func _store(person:Dictionary,record:Dictionary) -> void:
	if str(record.dish).is_empty() and record.guests.is_empty():person.erase(KEY)
	else:person[KEY]=record

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
