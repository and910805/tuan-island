extends RefCounted
## B6 搬運路線。多人冒險時，另一位島民在轉角與卸貨處守望。

const NAME:="迷路搬運鼠"
const REGION:="mine_6"
const DEPTH:=6
const START:=Vector2(21.5,25.2)
const MIDDLE:=Vector2(23.0,26.15)
const DELIVERY:=Vector2(24.5,27.1)
const REST:=Vector2(25.1,26.6)
const CRATE:=Vector2i(25,27)
const FIELD:="lost_porter"
const POINT:="mine_porter"
const WATCH_POINTS:=[Vector2(22.5,26.5),Vector2(25.5,26.5)]
const WATCH_LABELS:=["轉角守望","材料箱守望"]
const WATCH_RADIUS:=0.42
const ROUTE_CELLS:=[Vector2i(21,25),Vector2i(22,25),Vector2i(22,26),Vector2i(23,26),Vector2i(24,26),Vector2i(24,27),Vector2i(25,26),CRATE]
const REACH:=1.4
const REWARD_ITEM:="iron_ore"
const REWARD_COUNT:=2
const ACTIONS:=["porter_offer","porter_wait","porter_deliver","porter_claim"]

enum Stage { WAITING, TO_MIDDLE, TO_CRATE, DELIVERED, REWARDED }

const STEPS:=[
	{"cell":Vector2i(21,25),"at":START,"prompt":"問問搬運鼠","message":"搬運鼠把大背包往上扶了扶。和牠走到轉角歇一下。"},
	{"cell":Vector2i(23,26),"at":MIDDLE,"prompt":"等等搬運鼠","message":"搬運鼠追上來了。接下來送到右邊的材料箱。"},
	{"cell":CRATE,"at":Vector2(25.5,27.5),"prompt":"把材料送到箱子","message":"材料送到了！搬運鼠卸下背包，朝你笑了。"},
	{"cell":CRATE,"at":Vector2(25.5,27.5),"prompt":"收下搬運鼠的謝禮","message":"搬運鼠送了你兩份鐵礦。"},
]

static func available(region:String,unlocked_depth:int)->bool:
	return region==REGION and unlocked_depth>=DEPTH

static func site_clear(layers:Dictionary)->bool:
	for cell:Vector2i in ROUTE_CELLS:
		var key:="%d,%d"%[cell.x,cell.y]
		if layers.get("objects",{}).has(key) or layers.get("forest",{}).has(key) or layers.get("crops",{}).has(key):
			return false
	return true

static func valid(stage:Variant)->bool:
	return (stage is int or stage is float) and is_finite(stage) and floor(stage)==stage and stage>=Stage.WAITING and stage<=Stage.REWARDED

static func watch_index(stage:int)->int:
	return stage-Stage.TO_MIDDLE if stage in [Stage.TO_MIDDLE,Stage.TO_CRATE] else -1

static func visible_step(stage:int,snapshot:Dictionary)->Dictionary:
	var step:=next_step(stage)
	var index:=watch_index(stage)
	var watches:Array=snapshot.get("porter_watches",[])
	if index>=0 and watches.size()==WATCH_POINTS.size() and not watches[index]:
		step.prompt="請同伴守住"+("轉角" if index==0 else "材料箱旁")
	return step

static func next_step(stage:int)->Dictionary:
	if stage<Stage.WAITING or stage>=Stage.REWARDED:return {}
	var step:Dictionary=STEPS[stage].duplicate()
	step.action=ACTIONS[stage]
	return step

static func mouse_feet(stage:int)->Vector2:
	if stage<Stage.TO_MIDDLE:return START
	if stage<Stage.TO_CRATE:return MIDDLE
	return DELIVERY if stage==Stage.TO_CRATE else REST

static func interaction_points(snapshot:Dictionary,person:Dictionary)->Dictionary:
	if not snapshot.get("porter_available",false) or person.is_empty():return {}
	var step:=next_step(int(person.get(FIELD,Stage.WAITING)))
	if step.is_empty() or Vector2(person.x,person.y).distance_to(step.at)>REACH:return {}
	return {POINT:step.at}

static func advance(stage:int,action:String,target:Vector2i,position:Vector2,reward_fits:=true)->Dictionary:
	if stage==Stage.REWARDED:
		return outcome(false,stage,"已經收下搬運鼠的謝禮。")
	var step:=next_step(stage)
	if step.is_empty() or action!=step.action:
		return outcome(false,stage,"先陪搬運鼠走完目前這一段。")
	if target!=step.cell or position.distance_to(step.at)>REACH:
		return outcome(false,stage,"走近搬運鼠或材料箱再互動。")
	if stage==Stage.DELIVERED and not reward_fits:
		return outcome(false,stage,"背包放不下鐵礦，空出位置再回來領。")
	return outcome(true,stage+1,str(step.message),REWARD_COUNT if stage==Stage.DELIVERED else 0)

static func outcome(ok:bool,stage:int,message:String,reward:=0)->Dictionary:
	return {"ok":ok,"stage":stage,"message":message,"reward":reward}
