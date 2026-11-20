extends RefCounted

## D03 one-slot meal buff plus the fixed-point stamina carry. Everything about the slot lives here:
## typed schema, authoritative read/expiry, apply/replace rules, and every stamina writer helper.
##
## Player fields (both optional; absent = no buff / zero carry):
##   meal_buff        {"id":String in EFFECTS,"until":float world seconds}   one slot, never stacks
##   mine_energy_frac int 0..19, twentieths of a point owed: true stamina = mine_energy - frac/20
## Legacy `ginger_warm_until` (old saves) is read as a ginger_tea slot when no meal_buff is saved, and is
## still written while ginger warmth is the active effect so old readers and saves keep working.
## Item ids and the eat RPC (eat_meal / drink_ginger_tea) are unchanged; only the optional `extra`
## carries a replace confirmation.

const FIELD:="meal_buff"
const FRAC_FIELD:="mine_energy_frac"
const LEGACY_GINGER:="ginger_warm_until"
const SCALE:=20
const MAX_ENERGY:=100
## One twentieth-point ledger: a discounted strike pays 19/20 of its base cost, exactly 5% less.
const DISCOUNT_NUM:=19
const CONFIRM:="replace"
const SALAD:="salad"
const GINGER:="ginger_tea"
const EFFECTS:={
	"salad":{"seconds":360.0,"name":"菜園沙拉","summary":"採礦耗體 −5%"},
	"ginger_tea":{"seconds":480.0,"name":"暖薑茶","summary":"保暖"},
}

static func seconds_for(id:String)->float:
	return float(EFFECTS.get(id,{}).get("seconds",0.0))

static func label_for(id:String)->String:
	return str(EFFECTS.get(id,{}).get("name",id))

# ---- schema -------------------------------------------------------------------------------------

## True when the optional fields on `person` are well typed (legacy ginger is checked by the caller's
## existing rule). `time` is the saved world clock.
static func valid(person:Dictionary,time:float)->bool:
	if person.has(FRAC_FIELD):
		var frac:Variant=person[FRAC_FIELD]
		if not (frac is int or (frac is float and floorf(frac)==frac)) or int(frac)<0 or int(frac)>=SCALE:return false
	if not person.has(FIELD):return true
	var slot:Variant=person[FIELD]
	if not slot is Dictionary or slot.size()!=2 or not slot.has("id") or not slot.has("until"):return false
	if not slot.id is String or not EFFECTS.has(slot.id):return false
	var until:Variant=slot.until
	if not (until is float or until is int) or not is_finite(float(until)):return false
	return float(until)>=0.0 and float(until)<=time+seconds_for(slot.id)

# ---- authoritative read / expiry ------------------------------------------------------------------

## The active effect as {"id","until","left"}, or {} when none. Expired records read as none.
static func read(person:Dictionary,time:float)->Dictionary:
	var slot:Variant=person.get(FIELD)
	if slot is Dictionary and EFFECTS.has(slot.get("id","")):
		var left:=float(slot.get("until",0.0))-time
		if left>0.0:return {"id":str(slot.id),"until":float(slot.until),"left":left}
		return {}
	var legacy:=float(person.get(LEGACY_GINGER,0.0))-time
	if legacy>0.0:return {"id":GINGER,"until":float(person[LEGACY_GINGER]),"left":legacy}
	return {}

static func active_id(person:Dictionary,time:float)->String:
	return str(read(person,time).get("id",""))

static func has(person:Dictionary,id:String,time:float)->bool:
	return active_id(person,time)==id

## Drop an expired record (and expired legacy ginger) so saves stay tidy.
static func expire(person:Dictionary,time:float)->void:
	if read(person,time).is_empty():
		person.erase(FIELD)
		if float(person.get(LEGACY_GINGER,0.0))<=time:person.erase(LEGACY_GINGER)

## Remaining whole seconds for UI, 0 when not active.
static func seconds_left(person:Dictionary,id:String,time:float)->int:
	var effect:=read(person,time)
	return ceili(float(effect.left)) if effect.get("id","")==id else 0

static func clock_text(seconds:int)->String:
	return "%d:%02d"%[seconds/60,seconds%60]

# ---- apply / replace ------------------------------------------------------------------------------

## Whether eating `id` now needs an explicit confirmation because another effect holds the slot.
static func needs_confirm(person:Dictionary,id:String,time:float)->bool:
	var current:=active_id(person,time)
	return not current.is_empty() and current!=id

static func replace_prompt(person:Dictionary,id:String,time:float)->String:
	return "目前有「%s」效果，吃下去會取代它（%s）。再按一次確認。"%[label_for(active_id(person,time)),label_for(id)]

## Claim the single slot. Same id refreshes to a full duration (never extends past it, never stacks).
static func apply(person:Dictionary,id:String,time:float)->void:
	person.erase(LEGACY_GINGER)
	person[FIELD]={"id":id,"until":time+seconds_for(id)}
	if id==GINGER:person[LEGACY_GINGER]=time+seconds_for(id)

## Efficiency multiplier numerator (of SCALE) that a strike pays right now.
static func strike_numerator(person:Dictionary,time:float)->int:
	return DISCOUNT_NUM if has(person,SALAD,time) else SCALE

# ---- stamina helpers (the only writers of mine_energy outside new-player seeding) ----------------

static func energy(person:Dictionary)->int:
	return int(person.get("mine_energy",MAX_ENERGY))

static func frac(person:Dictionary)->int:
	return int(person.get(FRAC_FIELD,0))

## Exact stamina in twentieths of a point.
static func twentieths(person:Dictionary)->int:
	return energy(person)*SCALE-frac(person)

static func whole_points(person: Dictionary) -> int:
	return twentieths(person) / SCALE

static func refill(person:Dictionary)->void:
	person.mine_energy=MAX_ENERGY
	person.erase(FRAC_FIELD)

## Falling from exhaustion clears the active meal and its legacy mirror.
## A voluntary refill at a rest station keeps both effect and duration.
static func recover_from_exhaustion(person:Dictionary)->void:
	refill(person)
	person.erase(FIELD)
	person.erase(LEGACY_GINGER)

## Whole-point restore, capped at 100. Reaching the cap clears the carry. Returns points gained.
static func restore(person:Dictionary,amount:int)->int:
	var before := twentieths(person)
	var recovered := mini(MAX_ENERGY*SCALE, before+maxi(0,amount)*SCALE)
	if recovered <= before:return 0
	set_twentieths(person,recovered)
	return recovered/SCALE-before/SCALE

## True when a strike of base `cost` would exhaust the player (pays out, sends them to rest).
static func exhausts(person:Dictionary,cost:int,time:float)->bool:
	return twentieths(person)<=cost*strike_numerator(person,time)

## Spend one strike. Caller already checked `exhausts` (exhausted strikes refill instead).
static func spend(person:Dictionary,cost:int,time:float)->void:
	set_twentieths(person,maxi(0,twentieths(person)-cost*strike_numerator(person,time)))

static func set_twentieths(person:Dictionary,value:int)->void:
	var ceiling:=(value+SCALE-1)/SCALE
	person.mine_energy=ceiling
	var carry:=ceiling*SCALE-value
	if carry>0:person[FRAC_FIELD]=carry
	else:person.erase(FRAC_FIELD)
