extends RefCounted
## C11 石工台 rules shared by World (authority), SaveSchema and the UI. Pure data/static helpers.
##
## Unlock: the station is a normal build that only needs the Q03 公告板修復 flag (`state.board`,
## written by World when the donation or the public fund completes). No mining prerequisite.
##
## Recipes (spec R11/R12 + Q05):
##   stone_floor / small_smelter / spring_stone_bench / inn_stone_footbath  -> route to construction
##   bridge_foundation                                                       -> real craft (stone only)
## New construction of R11 (stone_floor) and R12 (small_smelter) needs a stone workbench on the
## island (HOME layer, anyone's: stations are shared like the C08 bench). Restoring an undo, loading a
## save and moving/removing existing pieces never look at this rule.
##
## Q05 河灣橋 (chosen tuning, the spec gives no component price): the Q03 donation still opens the
## board exactly as before; the river crossing itself now also needs FOUNDATIONS_NEEDED bridge
## foundations, each crafted at the 石工台 for FOUNDATION_COST (10 stone -> 20 stone in total, the
## stone figure of spec Q05). The project lives in the optional root `bridge_project`:
##   absent                      = legacy / already completed world: the bridge is open (grandfathered).
##   {foundations,done}          = C11 shape. Created by World when Q03 completes. done==true is an open bridge
##                                 for good (nothing more is owed); done==false still owes WOOD_NEEDED wood and
##                                 ROPE_NEEDED rope (migration default: both count as 0 donated).
##   {foundations,done,wood,rope}= Q05 shape. World upgrades a pending C11 shape lazily on the first donation or
##                                 craft (never on load), keeping its foundation count. `done` flips exactly when
##                                 foundations==FOUNDATIONS_NEEDED, wood==WOOD_NEEDED and rope==ROPE_NEEDED.
## Q05 河對岸的鈴聲 = 60 wood + 4 rope donated at the board (action `bridge_donate`, capped, backpack only) and
## 2 foundations (20 stone in total) crafted at the 石工台. The 20 stone IS the foundations: nothing else charges stone.
## Rope is hand-woven from fiber (5 fiber = 1 rope, backpack action `handcraft_rope`, fiber from grass and trees).
## Q05 is deliberately NOT gated on Q04 (public kitchen): the C11 route already allowed it after Q03 and no Q04
## step needs the east bank, so gating would only add a blocker to established routes.
## Fishing: once the bridge is open the river beside the deck (FISHING_RECTS) is the 河灣橋釣點 with its own catch.

const Industry=preload("res://scripts/industry.gd")

const KIND:=Industry.STONE_WORKBENCH
const ACTION:="stone_craft"
const FOUNDATION:="bridge_foundation"
const FOUNDATION_NAME:="橋基"
const FOUNDATION_COST:={"stone":10}
const FOUNDATIONS_NEEDED:=2
const WOOD_NEEDED:=60
const ROPE_NEEDED:=4
const DONATE_ACTION:="bridge_donate"
const PROJECT_KEY:="bridge_project"
const BOARD_CELL:=Vector2i(40,29)
const BOARD_REACH:=4.5
## 河灣橋釣點: river tiles north and south of the 3-tile deck (x 55..56, y 29..31). The fishing-meet waters start at
## y 34, so the two never overlap. Before the bridge opens these tiles keep the ordinary river fishing.
const FISHING_RECTS:=[Rect2i(55,26,2,3),Rect2i(55,32,2,2)]
const FISHING_SPOT:="river_bridge_pool"
const FISHING_LABEL:="河灣橋釣點"
## D06 銀線溪魚淺灘 just north of the 河灣橋釣點, reachable from the west at (54,23) or east at (57,24..25).
## Opens with the bridge and always pays minnow; redfish (day) and loach (night) stay exclusive to FISHING_RECTS.
const SHOAL_RECT:=Rect2i(55,23,2,3)
const SHOAL_SPOT:="river_bridge_shoal"
const SHOAL_LABEL:="銀線溪魚淺灘"
## Kinds whose NEW construction goes through the station.
const STATION_BUILDS:=["stone_floor","small_smelter"]
const LOCKED_MSG:="先完成公告板修復，才能建造石工台。"
const STATION_MSG:="先建造石工台，才能規劃石地板與小熔爐。"
const BRIDGE_DONE_MSG:="河灣橋已經開通了。"
const DONATE_WAIT_MSG:="先完成公告板修復（Q03），再來捐河灣橋的材料。"
const DONATE_NONE_MSG:="背包沒有河灣橋還缺的木材或繩索。繩索用 5 份纖維在背包手作。"
const BRIDGE_WAIT_MSG:="先完成公告板修復，再來製作橋基。"
## Ordered recipe list of the dedicated UI. route "craft" = server action, "build" = Build Folio.
const RECIPES:=[
	{"id":"stone_floor","route":"build"},
	{"id":"small_smelter","route":"build"},
	{"id":FOUNDATION,"route":"craft"},
	{"id":"spring_stone_bench","route":"build"},
	{"id":"inn_stone_footbath","route":"build"},
]

static func fresh_project() -> Dictionary:
	return {"foundations":0,"done":false}

## True when the river crossing (bridge tiles) can be walked. Absent project = grandfathered.
static func bridge_open(state:Dictionary) -> bool:
	if state.get("board",false)!=true:return false
	var project:Variant=state.get(PROJECT_KEY)
	if not project is Dictionary:return true
	return project.get("done",false)==true

## Foundations still missing, 0 when there is no pending bridge project.
static func foundations_missing(state:Dictionary) -> int:
	var project:Variant=state.get(PROJECT_KEY)
	if state.get("board",false)!=true or not project is Dictionary or project.get("done",false)==true:return 0
	return maxi(0,FOUNDATIONS_NEEDED-int(project.get("foundations",0)))

## What the pending project still needs: {foundations,wood,rope} (all 0 when nothing is pending).
## A C11-shaped project reads its missing wood/rope as 0 donated (migration default).
static func missing(state:Dictionary) -> Dictionary:
	var out:={"foundations":0,"wood":0,"rope":0}
	if not project_pending(state):return out
	var project:Dictionary=state[PROJECT_KEY]
	out.foundations=maxi(0,FOUNDATIONS_NEEDED-int(project.get("foundations",0)))
	out.wood=maxi(0,WOOD_NEEDED-int(project.get("wood",0)))
	out.rope=maxi(0,ROPE_NEEDED-int(project.get("rope",0)))
	return out

## Compact one-line Q05 status for the objective panel ("" when nothing is pending).
static func progress_text(state:Dictionary) -> String:
	if not project_pending(state):return ""
	var project:Dictionary=state[PROJECT_KEY]
	return "Q05 河灣橋：橋基 %d/%d 木材 %d/%d 繩索 %d/%d"%[int(project.get("foundations",0)),FOUNDATIONS_NEEDED,int(project.get("wood",0)),WOOD_NEEDED,int(project.get("rope",0)),ROPE_NEEDED]

## Full four-field copy of a project (C11 shape gets wood=0, rope=0).
static func upgraded(project:Dictionary) -> Dictionary:
	return {"foundations":int(project.get("foundations",0)),"done":project.get("done",false)==true,
		"wood":int(project.get("wood",0)),"rope":int(project.get("rope",0))}

static func is_complete(project:Dictionary) -> bool:
	return int(project.get("foundations",0))>=FOUNDATIONS_NEEDED and int(project.get("wood",0))>=WOOD_NEEDED and int(project.get("rope",0))>=ROPE_NEEDED

## What one backpack can give right now (exact caps, never more than missing): {wood,rope}.
static func contribution(state:Dictionary,bag:Dictionary) -> Dictionary:
	var need:=missing(state)
	return {"wood":mini(int(need.wood),maxi(0,int(bag.get("wood",0)))),"rope":mini(int(need.rope),maxi(0,int(bag.get("rope",0))))}

## True when the bridge is open and the tile is part of the 河灣橋釣點 (any region-agnostic home tile).
static func fishing_spot(state:Dictionary,p:Vector2i) -> bool:
	if not bridge_open(state):return false
	for rect:Rect2i in FISHING_RECTS:
		if rect.has_point(p):return true
	return false

## True when the bridge is open and the tile is the 銀線溪魚淺灘 (disjoint from FISHING_RECTS).
static func shoal_spot(state:Dictionary,p:Vector2i) -> bool:
	return bridge_open(state) and SHOAL_RECT.has_point(p)

static func project_pending(state:Dictionary) -> bool:
	return state.get("board",false)==true and state.get(PROJECT_KEY) is Dictionary and state[PROJECT_KEY].get("done",false)!=true

## Any stone workbench anchor in an objects layer (HOME layer for rules, snapshot objects for the UI).
static func has_station(objects:Dictionary,owner_token:="") -> bool:
	for piece:Variant in objects.values():
		if piece is Dictionary and piece.get("type")==KIND and Industry.square_part(piece)==0:
			if owner_token.is_empty() or piece.get("owner")==owner_token:return true
	return false

## Optional root validation (no save-version bump): shape, bounds and board/done consistency.
static func valid(s:Dictionary) -> bool:
	if not s.has(PROJECT_KEY):return true
	var project:Variant=s[PROJECT_KEY]
	if not project is Dictionary or (project.size()!=2 and project.size()!=4) or s.get("board",false)!=true:return false
	var count:Variant=project.get("foundations")
	if not whole_within(count,FOUNDATIONS_NEEDED):return false
	if typeof(project.get("done"))!=TYPE_BOOL:return false
	if project.size()==2:
		# C11 shape: done exactly when both foundations exist (an unfinished one owes wood/rope as 0 donated).
		if (project.done==true)!=(int(count)>=FOUNDATIONS_NEEDED):return false
	else:
		if not whole_within(project.get("wood"),WOOD_NEEDED) or not whole_within(project.get("rope"),ROPE_NEEDED):return false
		if (project.done==true)!=(int(count)>=FOUNDATIONS_NEEDED and int(project.wood)>=WOOD_NEEDED and int(project.rope)>=ROPE_NEEDED):return false
		project.wood=int(project.wood)
		project.rope=int(project.rope)
	project.foundations=int(count)
	return true

static func whole_within(value:Variant,limit:int) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)) or floorf(float(value))!=float(value):return false
	return float(value)>=0.0 and float(value)<=float(limit)
