extends RefCounted
const Catalog = preload("res://scripts/mine_expansion_catalog.gd")
const ENTRY := Vector2i(28,19)
const UP := Vector2i(11,20)
const DOWN := Vector2i(36,20)
const REST := Vector2i(14,20)
const MUD_REGION := "mine_1"
const MUD_GATE := Vector2i(18,11)
const MUD_REWARD := Vector2i(16,11)
const MUD_ALCOVE_EDGE := 12.0
const MUD_COPPER := 4
const MUD_WINDUP := 1.5
const MUD_RECOVERY := 3.5

static func mud_engaged(player:Dictionary,now:float) -> bool:
	if not player.has("mud_duel"):return false
	var pos:=Vector2(player.x,player.y)
	return now<float(player.mud_duel.strike_at)+MUD_RECOVERY and pos.distance_to(Vector2(MUD_GATE)+Vector2(0.5,0.5))<=3.2
const SERVICE := Vector2i(34,20)
const NODES := [Vector2i(20,20),Vector2i(24,22),Vector2i(28,23)]
const POOL := Rect2i(29,24,4,3)
## T067: B1–B5 are the original shallow works; B6–B15 come from
## mine_expansion_catalog.gd (test_mine_expansion_catalog cross-checks the copies).
const SHALLOW_DEPTH := 5
const MAX_DEPTH := 15
## Hoist cage on B6–B15 only. The surface entry sign lowers to LIFT_LANDINGS
## (surface_landings) only after the Q07 hoist repair.
const LIFT := Vector2i(17,17)
const LIFT_LANDINGS := [6,10,15]
const IDS := ["mine_1","mine_2","mine_3","mine_4","mine_5","mine_6","mine_7","mine_8","mine_9","mine_10","mine_11","mine_12","mine_13","mine_14","mine_15"]
## COSTS[i] is the commission on floor i+1 that opens floor i+2.
const COSTS := [{"wood":6},{"stone":8},{},{"plank":6,"copper_joint":2},
	{"plank":8,"copper_joint":4},{"stone":16,"charcoal":4},{"pipe_kit":2,"tank_kit":1},{"glass":4,"copper_joint":2},
	{"pump_kit":1,"pipe_kit":4},{"plank":12,"resin":4},{"conveyor_kit":2,"stone":12},{"copper_joint":6,"glass":2,"charcoal":4},
	{"plank":10,"fiber":8,"resin":4},{"gold_sample":2,"copper_joint":6,"plank":10}]
const ORES := ["stone","copper_ore","stone","copper_ore","gold_ore",
	"copper_ore","stone","copper_ore","stone","copper_ore","gold_ore","gold_ore","copper_ore","gold_ore","stone"]
const YIELDS := [2,4,4,6,2,4,6,6,4,4,2,2,8,3,4]
const COOLDOWN := 12.0
const BASE_ENERGY_COST := 10

## T067 Q07 「卡住的升降台」: shared, done once at the Jinguashi entry sign
## (World action mine_hoist_repair) after B6 is open. Until then the surface
## sign only walks into B1; deep cages up to the surface always work.
const HOIST_COST := {"copper_joint":12,"plank":4}
const HOIST_DEPTH := 6

static func fresh() -> Dictionary:
	return {"unlocked":1,"ready":{},"pumped":0,"hoist":false}

## True once the shared surface hoist has been repaired.
static func hoist_ready(progress:Dictionary) -> bool:
	var value = progress.get("hoist",false)
	return value is bool and value

## Landings the surface entry sign may lower players to right now.
static func surface_landings(progress:Dictionary) -> Array:
	if not hoist_ready(progress):return []
	return lift_targets(int(progress.get("unlocked",1)))

## Saves written before Q07 lack `hoist`: deep mines that were already open
## (unlocked >= 6) keep their working hoist. No version bump; malformed data is
## left for valid() to reject.
static func migrate(data) -> void:
	if not data is Dictionary or data.has("hoist"):return
	var level = data.get("unlocked")
	# Bracket assignment keeps a String key (dot-assign would add a StringName key).
	if (level is int or level is float) and is_finite(level):data["hoist"] = float(level) >= float(HOIST_DEPTH)

static func depth_of(region:String) -> int:
	return IDS.find(region)+1

## Mine energy spent per strike. Deep hazards are pacing only (no damage).
static func energy_cost(depth:int) -> int:
	if depth<=SHALLOW_DEPTH:return BASE_ENERGY_COST
	return roundi(BASE_ENERGY_COST*Catalog.energy_multiplier(depth))

## Extra +1 finds per strike (B5 keeps its original crystal sand).
static func finds(depth:int) -> Array:
	if depth==4:return ["iron_ore"]
	if depth==SHALLOW_DEPTH:return ["crystal_sand"]
	if depth>SHALLOW_DEPTH and depth<=MAX_DEPTH:return Catalog.entry(depth).get("finds",[]).duplicate()
	return []

static func lift_targets(unlocked:int) -> Array:
	return LIFT_LANDINGS.filter(func(depth):return depth<=unlocked)

static func valid(state: Dictionary) -> bool:
	var data = state.get("mine_depths")
	if not data is Dictionary or data.size()!=4 or not data.get("ready") is Dictionary:return false
	var level = data.get("unlocked")
	if not level is float and not level is int:return false
	if not is_finite(level) or level<1 or level>MAX_DEPTH or floor(level)!=level:return false
	var hoist = data.get("hoist")
	if not hoist is bool or (hoist and level<HOIST_DEPTH):return false
	var pumped = data.get("pumped")
	if (not pumped is int and not pumped is float) or not is_finite(pumped) or pumped<0 or pumped>24 or floor(pumped)!=pumped:return false
	if (level<3 and pumped!=0) or (level>=4 and pumped!=24):return false
	var keys := NODES.map(func(p): return "%d,%d"%[p.x,p.y])
	for region in data.ready:
		if region not in IDS or IDS.find(region)>=level or not data.ready[region] is Dictionary:return false
		for key in data.ready[region]:
			var ready = data.ready[region][key]
			if key not in keys or (not ready is int and not ready is float):return false
			if not is_finite(ready) or ready<0 or ready>float(state.time)+COOLDOWN:return false
	return true
