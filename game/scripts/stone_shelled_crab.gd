extends RefCounted
## 石殼蟹 (plan section 16): cozy, non-combat "look, then mend the little cart beside it" encounter
## in the B5 east cave.
##
## STANDALONE and PURE: no World/Session/UI references, no randomness, no clock. The host passes the
## player position and a READ-ONLY inventory in; every function returns new data and never mutates
## its arguments, so World.act stays the only authority and request-id receipts replay identically.
## Wired into World.act (`_crab_action`); client contract in
## work/claude-agents/stone-crab-server-integration/client-contract.md.
##
## The LIFE-mode solution is "修好旁邊運礦車". The plan's adventure alternative ("等待露出軟殼") is
## the additive `crab_shell` route at the end of this file: same stage ladder, record and gift.
##
## Persisted per-player record (JSON-safe): {"stage":0..2,"claimed":bool}
##   stage 0 tucked under its ore, 1 alert (after the player looks at it), 2 settled beside the
##   mended cart. There is no transient host memory: nothing to forget on reload or reconnect.

const NAME:="石殼蟹"
const REGION:="mine_5"
const DEPTH:=5
## All three cells are the top row of the B5 east cave's inner span (mine_layout
## Rect2i(45,22,3,5)): a back wall with rock above, so even with all three solid nothing else is
## cut off (survey point (46,24) and the dead-end nook Rect2i(46,27,2,2) stay open).
## The side cart is a separate small prop; the mainline freight cart stays at Mines.SERVICE.
const CART:=Vector2i(45,22)
const CRAB:=Vector2i(47,22)
## Where it sidesteps to once the cart is mended (snug against the cart).
const CRAB_REST:=Vector2i(46,22)
const REACH:=1.8
const SURVEY_ACTION:="crab_survey"
const REPAIR_ACTION:="crab_repair"
const CLAIM_ACTION:="crab_claim"
const ACTIONS:=["crab_survey","crab_repair","crab_claim"]
## One board for the cracked side, one joint for the loose wheel. Both are already required by
## the B4 commission that opens B5 (Mines.COSTS[3]), so every player who can stand here can make them.
const REPAIR_COST:={"plank":2,"copper_joint":1}
const REWARD_ITEM:="gold_ore"
const REWARD_COUNT:=2
## Audio cue ids (synthesis is added at integration); the visual cue is the atlas frame.
const CUE_CLACK:="crab_clack"
const CUE_HAMMER:="crab_hammer"
const CUE_WHEEL:="crab_wheel"
const CUE_SCUTTLE:="crab_scuttle"
const CUE_CHIME:="crab_chime"
const CUES:=["crab_clack","crab_hammer","crab_wheel","crab_scuttle","crab_chime"]
const ATLAS_PATH:="res://assets/mine/stone-shelled-crab.png"
const ATLAS_SIZE:=Vector2i(64,80)
const FRAME_SIZE:=Vector2i(32,40)
const FOOT:=Vector2i(16,38)
const FRAME_TUCKED:=0
const FRAME_ALERT:=1
const FRAME_SIDESTEP:=2
const FRAME_RELAXED:=3
const CART_ATLAS_PATH:="res://assets/mine/stone-crab-cart.png"
const CART_ATLAS_SIZE:=Vector2i(96,40)
const CART_FRAME_SIZE:=Vector2i(48,40)
const CART_FOOT:=Vector2i(24,38)
const CART_BROKEN:=0
const CART_MENDED:=1

static func fresh() -> Dictionary:
	return {"stage":0,"claimed":false}

static func valid(record) -> bool:
	if not record is Dictionary or record.size()!=2:return false
	var stage=record.get("stage")
	if not (stage is int or stage is float) or not is_finite(stage) or floor(stage)!=stage or stage<0 or stage>2:return false
	var claimed=record.get("claimed")
	if not claimed is bool:return false
	return not (claimed and int(stage)<2)

static func available(region:String,unlocked_depth:int) -> bool:
	return region==REGION and unlocked_depth>=DEPTH

## Cells the encounter draws on. The host decides how to keep player builds off them.
static func footprint() -> Array:
	return [CART,CRAB,CRAB_REST]

static func near(pos:Vector2,cell:Vector2i) -> bool:
	return pos.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=REACH

static func settled(record:Dictionary) -> bool:
	return int(record.get("stage",0))>=2

## The cell the crab stands on for this player's record.
static func crab_cell(record:Dictionary) -> Vector2i:
	return CRAB_REST if settled(record) else CRAB

static func _held(inventory:Dictionary,item:String) -> int:
	var amount=inventory.get(item,0)
	if not (amount is int or amount is float) or not is_finite(amount):return 0
	return maxi(0,int(amount))

## What the player still lacks for the repair: {} when everything is in the bag.
static func missing(inventory:Dictionary) -> Dictionary:
	var lack:={}
	for item:String in REPAIR_COST:
		var short:=int(REPAIR_COST[item])-_held(inventory,item)
		if short>0:lack[item]=short
	return lack

static func _result(ok:bool,message:String,record:Dictionary,outcome:String,cues:Array=[]) -> Dictionary:
	return {"ok":ok,"message":message,"record":record.duplicate(true),"outcome":outcome,"cues":cues.duplicate(),
		"consume":{},"missing":{}}

## Interact on the crab: just look at it. Free, unlimited, no timing.
static func survey(record:Dictionary,pos:Vector2) -> Dictionary:
	if not near(pos,crab_cell(record)):return _result(false,"請靠近石殼蟹。",record,"far")
	if settled(record):return _result(true,"石殼蟹靠在修好的小礦車旁，瞇著眼睛很安心。",record,"settled")
	if int(record.get("stage",0))==1:
		return _result(true,"牠的眼睛一直望向旁邊那台壞掉的小礦車：木板裂了，一顆輪子掉在旁邊。",record,"alert",[CUE_CLACK])
	var next:=record.duplicate(true)
	next.stage=1
	return _result(true,"石頭底下探出兩顆小眼睛，小螯喀喀敲了兩下，又望向旁邊壞掉的小礦車。",next,"look",[CUE_CLACK])

## Interact on the side cart. The host spends exactly `consume` from the actor's own bag and only
## when it is non-empty; a refusal (too early, short of materials, far) costs and loses nothing.
static func repair(record:Dictionary,pos:Vector2,inventory:Dictionary) -> Dictionary:
	if not near(pos,CART):return _result(false,"請靠近小礦車。",record,"far")
	if settled(record):return _result(false,"小礦車已經修好了，兩顆輪子都穩穩的。",record,"settled")
	if int(record.get("stage",0))<1:
		return _result(false,"這台小礦車裂了一塊板、掉了一顆輪子。旁邊那塊石頭好像動了一下，先看看牠吧。",record,"too_early")
	var lack:=missing(inventory)
	if not lack.is_empty():
		var out:=_result(false,"修小礦車需要木板 ×%d、銅接頭 ×%d。材料湊齊再回來，牠會等你。"%[int(REPAIR_COST.plank),int(REPAIR_COST.copper_joint)],record,"short")
		out["missing"]=lack
		return out
	var next:=record.duplicate(true)
	next.stage=2
	var done:=_result(true,"你補上木板、裝回輪子。石殼蟹喀喀地橫著走到礦車旁，舒服地靠了上去。",next,"repair",[CUE_HAMMER,CUE_WHEEL,CUE_SCUTTLE])
	done["consume"]=REPAIR_COST.duplicate()
	return done

## Optional one-time personal gift. The host must still check inventory capacity before committing.
static func claim(record:Dictionary,pos:Vector2) -> Dictionary:
	if not near(pos,crab_cell(record)):return _result(false,"請靠近石殼蟹。",record,"far")
	if not settled(record):return _result(false,"牠還縮在石頭底下，眼睛望著壞掉的小礦車。",record,"waiting")
	if bool(record.get("claimed",false)):return _result(false,"這份小禮物已經收下了。",record,"claimed")
	var next:=record.duplicate(true)
	next.claimed=true
	var out:=_result(true,"牠用小螯從礦車裡推出兩顆亮亮的小礦石給你。",next,"claim",[CUE_CHIME])
	out["reward"]={"item":REWARD_ITEM,"count":REWARD_COUNT}
	return out

## Crab atlas frame. `responding` shows the sidestep frame for the moment right after the repair.
static func frame(record:Dictionary,responding:bool=false) -> int:
	var stage:=int(record.get("stage",0))
	if stage>=2:return FRAME_SIDESTEP if responding else FRAME_RELAXED
	return FRAME_ALERT if stage==1 else FRAME_TUCKED

static func frame_rect(index:int) -> Rect2i:
	return Rect2i(Vector2i(index%2,index/2)*FRAME_SIZE,FRAME_SIZE)

static func cart_frame(record:Dictionary) -> int:
	return CART_MENDED if settled(record) else CART_BROKEN

static func cart_rect(index:int) -> Rect2i:
	return Rect2i(Vector2i(index*CART_FRAME_SIZE.x,0),CART_FRAME_SIZE)

## ---- Host integration helpers (pure) ----

## Tile layers that can hold player-made content. A legacy save may already have a chest, floor,
## crop, roof or sapling on one of the three cells; the encounter then stays hidden (and the cart
## is not solid) until the owner clears it. Keys are the world's "x,y" tile keys.
const SITE_LAYERS:=["objects","ground","roofs","crops","forest"]

static func tile_key(cell:Vector2i) -> String:
	return "%d,%d"%[cell.x,cell.y]

static func cell_occupied(layers:Dictionary,cell:Vector2i) -> bool:
	var tile:=tile_key(cell)
	for field:String in SITE_LAYERS:
		var layer=layers.get(field)
		if layer is Dictionary and layer.has(tile):return true
	return false

## `layers` is the mine_5 layer set ({"objects":{...},"ground":{...},...}); missing layers are empty.
static func site_clear(layers:Dictionary) -> bool:
	for cell:Vector2i in footprint():
		if cell_occupied(layers,cell):return false
	return true

## ---- Adventure-mode alternative (plan section 16: "等待露出軟殼") ----
## Additive: adventure worlds keep the repair route above and gain this one. Same stage ladder,
## same record, same one-time gift. No health, damage, countdown-to-fail or attempt counter: a
## mistimed tap costs nothing and the player may simply wait again.
##
## `watch` is host memory only ({} or {"open_at":world_seconds}); it is never saved and is dropped
## on disconnect, so a reload or reconnect just means waiting once more.
const SHELL_ACTION:="crab_shell"
const SHELL_WAIT:="wait"
const SHELL_TAP:="tap"
const ADVENTURE_ACTIONS:=["crab_shell"]
## Telegraph (ground ring + rumble) before the shell lifts, then how long the soft shell shows.
const SHELL_WINDUP:=3.0
const SHELL_WINDOW:=2.5
const CUE_RUMBLE:="crab_rumble"
const CUE_SOFT:="crab_soft"
const ADVENTURE_CUES:=["crab_rumble","crab_soft"]

static func _shell_result(ok:bool,message:String,record:Dictionary,outcome:String,watch:Dictionary,cues:Array=[]) -> Dictionary:
	var out:=_result(ok,message,record,outcome,cues)
	out["watch"]=watch.duplicate(true)
	return out

## -INF when there is no usable cycle.
static func shell_open_at(watch:Dictionary) -> float:
	var at=watch.get("open_at")
	if not (at is int or at is float) or not is_finite(at):return -INF
	return float(at)

## True while a wait cycle is still running (telegraph or soft-shell window).
static func shell_active(watch:Dictionary,now:float) -> bool:
	var at:=shell_open_at(watch)
	return at!=-INF and now<at+SHELL_WINDOW

static func _shell_gate(record:Dictionary,pos:Vector2,watch:Dictionary) -> Dictionary:
	if not near(pos,crab_cell(record)):return _shell_result(false,"請靠近石殼蟹。",record,"far",watch)
	if settled(record):return _shell_result(false,"石殼蟹已經靠在小礦車旁休息了。",record,"settled",watch)
	if int(record.get("stage",0))<1:return _shell_result(false,"牠還縮在石頭底下，先看看牠吧。",record,"too_early",watch)
	return {}

## Start waiting. The reply's watch.open_at tells the client when the ring closes and the shell lifts.
static func shell_wait(record:Dictionary,watch:Dictionary,pos:Vector2,now:float) -> Dictionary:
	var gate:=_shell_gate(record,pos,watch)
	if not gate.is_empty():return gate
	if shell_active(watch,now):return _shell_result(false,"牠正在慢慢抬起石殼，再等一下。",record,"watching",watch)
	return _shell_result(true,"石殼蟹腳邊的地面亮起一圈，石殼咔啦咔啦地慢慢抬起來……等牠露出軟殼。",record,"windup",{"open_at":now+SHELL_WINDUP},[CUE_RUMBLE])

## Gentle tap. Only lands while the soft shell shows; too early or too late changes nothing.
static func shell_tap(record:Dictionary,watch:Dictionary,pos:Vector2,now:float) -> Dictionary:
	var gate:=_shell_gate(record,pos,watch)
	if not gate.is_empty():return gate
	var at:=shell_open_at(watch)
	if at==-INF or now>=at+SHELL_WINDOW:return _shell_result(false,"牠已經把石殼蓋回去了。不要緊，再等一次就好。",record,"late",watch)
	if now<at:return _shell_result(false,"石殼還蓋得緊緊的，等地上的圈合起來再輕輕碰。",record,"early",watch)
	var next:=record.duplicate(true)
	next.stage=2
	return _shell_result(true,"你輕輕碰了一下軟殼。石殼蟹嚇得喀喀橫走，一頭頂上小礦車——鬆掉的輪子剛好卡了回去，牠乾脆靠在車旁不走了。",next,"soft",{},[CUE_SOFT,CUE_WHEEL,CUE_SCUTTLE])
