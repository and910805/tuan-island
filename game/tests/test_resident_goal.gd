extends SceneTree
## T066「一起做的事」regression suite for res://scripts/resident_goals.gd and its
## World, SaveSchema and in-process Session integration: catalog integrity, every
## one of the 28 goals (stage gate, missing items, every option, every step order,
## prerequisites ("needs") and check order, exact inventory deltas, record,
## repeat), World-layer refusals (region, cell, reach, unknown resident, residents
## not yet present, malformed extra), the six needs ids at need_met level and
## through World.act, needs checked only once (undone afterwards), two
## independent players, request-id replay, save/reload, legacy saves, schema
## tampering and snapshot privacy (including other players' needs rows).
##
## REAL ACTIONS (through World.act): every resident_goal request, the
## resident_talk / resident_gift done after a goal, every refusal.
## WRITTEN DIRECTLY INTO STATE (disclosed PRESET): bond points
## (player.bonds[resident]={points,talk_day:-1,gift_day:-1}, never earned by
## talking here), inventory counts, player region/x/y (standing spots, no travel
## action), state.picnic and state.dock_stage (resident presence gates), the
## legacy and tampered save files, and the batch-2 prerequisites:
##   own_bed       state.objects["x,y"]={type:"bed"|"chest",owner:token,items:{}}
##                 at off-map keys (-200-n,-200), and removing such beds again;
##   glass_crafted player.greenhouse_glass_crafted (true/false/1/"true"/erased);
##   market_round  player.market (MarketStall.fresh() with open_day 0 and a
##                 zero-sale day-0 report, fresh() alone, a string) or erased;
##   festival_done state.festival = Festival.fresh() with round/active replaced;
##   known_three   bonds of achao, chacha, diandian at 1 point (or erased);
##   fair_weather  state.time moved FORWARD by whole days (time of day kept) to
##                 the next rainy / non-rainy day of weather.gd's cycle; the save
##                 test also sets state.time once to day 1. This is the only
##                 time change; nothing ticks.
## Every outdoor region shares one weather cycle, so "only home's weather
## matters" is shown with an indoor (never-raining) player region. Nothing
## depends on the real clock or on randomness (temp file names only).
##
## Batch 3 (keepsakes): every keepsake kit and every player.bond_keepsakes entry
## checked after a completion or claim was produced THROUGH World.act
## (resident_goal / resident_keepsake). FIXTURES written directly (disclosed at
## each site): "old completions" (player.bond_goals written with a goal done and
## no bond_keepsakes / no kit), tampered bond_goals / bond_keepsakes values,
## kit counts at MAX_ITEM or MAX_ITEM-1, a kit set to 0 ("lost"), and the
## batch-2 / tampered save files (bond_keepsakes and kits erased or altered).
const World=preload("res://scripts/world.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Weather=preload("res://scripts/weather.gd")
const Festival=preload("res://scripts/festival.gd")
const MarketStall=preload("res://scripts/market_stall.gd")
## World.gd literals: bond place gate and the generic 3.2-tile reach gate.
const MSG_PLACE:="請走到這位居民身邊。"
const MSG_FAR:="靠近一點，才能和它互動"
## resident_goals.gd literals.
const MSG_REOPEN:="請重新打開關係事件。"
const MSG_NO_GOAL:="這一階還沒有可以一起做的事。"
const MSG_PICK:="請先選一個做法。"
const MSG_STEPS:="三個步驟都要做過一次。"
const PERMS:=["012","021","102","120","201","210"]
const BAD_STEPS:=["","0","01","0123","001","011","000","013","300","0a1","a01","-01","01 "]
const TWELVE:=["achao","aru","bobo","chacha","diandian","lingpopo","luoluo","mianmian","milu","nuannuan","xiaoli","xinghe"]
const ALLOWED_FIELDS:=["title","task","items","options","steps","order","needs","quote","keepsake"]
const ALL_GOALS:=["achao 1","aru 1","aru 2","bobo 1","bobo 2","bobo 4","chacha 2","chacha 3","diandian 2","lingpopo 2","lingpopo 3","lingpopo 4",
	"luoluo 2","luoluo 3","luoluo 4","mianmian 1","mianmian 3","mianmian 4","milu 1","milu 3","nuannuan 1","nuannuan 2","nuannuan 4",
	"xiaoli 2","xiaoli 3","xiaoli 4","xinghe 2","xinghe 3"]
const WANT_NEEDS:={"aru 1":["own_bed"],"mianmian 4":["fair_weather"],"xinghe 3":["glass_crafted"],"lingpopo 4":["festival_done"],
	"xiaoli 3":["market_round"],"luoluo 2":["known_three"]}
## Literal copies of resident_goals.gd NEEDS (labels the player reads).
const NEED_TEXT:={
	"own_bed":"家園裡有一張你放的小床",
	"glass_crafted":"自己燒過一次溫室玻璃",
	"market_round":"你的市集攤位結算過一輪",
	"festival_done":"島上完成過一次風鈴接力",
	"known_three":"認識洛洛以外的三位居民",
	"fair_weather":"今天渡口沒有下雨",
}
## Literal copy of the batch-3 keepsake goals ("resident stage" -> kind).
const KEEPSAKE_GOALS:={"aru 1":"keepsake_aru","milu 3":"keepsake_milu","bobo 1":"keepsake_bobo","chacha 2":"keepsake_chacha",
	"achao 1":"keepsake_achao","mianmian 3":"keepsake_mianmian","xinghe 2":"keepsake_xinghe","lingpopo 3":"keepsake_lingpopo",
	"xiaoli 4":"keepsake_xiaoli","luoluo 4":"keepsake_luoluo","diandian 2":"keepsake_diandian","nuannuan 1":"keepsake_nuannuan"}
## resident_goals.gd batch-3 literals.
const MSG_KEEPSAKE_TAIL:="紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"
const MSG_RECORD_BAD:="關係紀錄有誤。"
const MSG_NO_KEEPSAKE:="這件事的紀念收在手帳裡，沒有可以領的小物。"
## Residents used to satisfy known_three (none of them has a needs goal).
const KNOWN_OTHERS:=["achao","chacha","diandian"]
const WATCHER:="goal-watcher-token-5c1a"
const PRIVATE_A:="goal-private-alpha-token-77e2"
const PRIVATE_B:="goal-private-beta-token-0f93"
const SAM:="goal-save-sam-token-41bd"
const KIM:="goal-needs-kim-token-93aa"
var checks:=0
var failures:=0
var serial:=0
var flows:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("RESIDENT_GOAL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_catalog()
	test_keepsake_catalog()
	for resident:String in Goals.GOALS:
		for stage:int in Goals.GOALS[resident]:
			goal_flow(resident,stage)
	expect(flows==28,"goal_flow ran for all 28 goals (%d)"%flows)
	test_world_rejections()
	test_gates()
	test_need_rules()
	test_needs_through_world()
	test_needs_once_and_save()
	test_players_and_replay()
	test_keepsake_claim()
	test_save_reload_and_schema()
	await test_session_snapshot()
	finish()

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String)->String:
	var path:=OS.get_environment("TEMP").path_join("resident-goal-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])
	_cleanup.append(path)
	return path

static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			out[k]=canon(value[k] if value.has(k) else value[StringName(k)])
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_equal_approx(value,roundf(value)) and absf(value)<9.0e15:return int(value)
	if value is StringName:return str(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

static func rec(points:int,talk:int,gift:int)->Dictionary:
	return {"points":points,"talk_day":talk,"gift_day":gift}

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func cell_of(w,resident:String)->Vector2i:
	var state:Dictionary=w.state
	var place:Array=World.bond_place(state,resident)
	var found:Vector2i=place[1]
	return found

static func region_of(w,resident:String)->String:
	var state:Dictionary=w.state
	var place:Array=World.bond_place(state,resident)
	return str(place[0])

static func go(w,token:String,region:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p["region"]=region
	stand(w,token,cell)

static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p["x"]=float(cell.x)+0.5
	p["y"]=float(cell.y)+1.5

## PRESET: writes the bond record directly (no talk/gift).
static func set_points(w,token:String,resident:String,points:int)->void:
	var p:Dictionary=pl(w,token)
	var bonds:Dictionary={}
	if p.get("bonds") is Dictionary:bonds=p.bonds
	bonds[resident]=rec(points,-1,-1)
	p["bonds"]=bonds

## PRESET: every item of `cost` set to cost+more.
static func fill(w,token:String,cost:Dictionary,more:int)->void:
	var inv:Dictionary=pl(w,token).inventory
	for item in cost:inv[item]=int(cost[item])+more

static func set_item(w,token:String,item:String,count:int)->void:
	var inv:Dictionary=pl(w,token).inventory
	inv[item]=count

static func goals_of(w,token:String)->Variant:
	var p:Dictionary=pl(w,token)
	if not p.has(Goals.RECORD_KEY):return null
	var value:Variant=p[Goals.RECORD_KEY]
	if value is Dictionary:
		var copy:Dictionary=value.duplicate(true)
		return copy
	return value

static func view_row(w,token:String,resident:String,stage:int)->Dictionary:
	var v:Dictionary=Goals.view(pl(w,token))
	var own:Dictionary=v.get(resident,{})
	var row:Dictionary=own.get(str(stage),{})
	return row

static func extra_of(resident:String,stage:int,option:String,steps:String)->String:
	return "%s:%d:%s:%s"%[resident,stage,option,steps]

static func option_ids(e:Dictionary)->Array:
	var out:Array=[]
	var options:Array=e.get("options",[])
	for found in options:
		var o:Dictionary=found
		out.append(str(o.get("id","")))
	if out.is_empty():out.append("")
	return out

static func right_steps(e:Dictionary)->String:
	if not e.has("steps"):return ""
	if not e.has("order"):return "012"
	var text:=""
	var order:Array=e.order
	for index in order:text+=str(index)
	return text

static func stage_msg(resident:String,stage:int)->String:
	return "和%s的關係到「%s」之後，才能一起做這件事。"%[Bond.name_of(resident),Bond.stage_name(stage)]

static func done_msg(e:Dictionary)->String:
	return "〈%s〉已經一起完成了，手帳可以重看。"%str(e.get("title",""))

static func order_msg(resident:String)->String:
	return "順序不太對。%s說不急，再看一次圖示。"%Bond.name_of(resident)

static func short_msg(item:String,held:int,needed:int)->String:
	return "還差%s %d／%d。"%[str(World.NAMES.get(item,item)),held,needed]

static func success_msg(resident:String,e:Dictionary)->String:
	var quote:Array=e.get("quote",["",""])
	return "%s：「%s」你們一起完成了〈%s〉，手帳記下紀念「%s」。"%[Bond.name_of(resident),str(quote[0]),str(e.get("title","")),str(e.get("keepsake",""))]

## Batch 3: success message of `resident stage`, with the keepsake sentence
## appended only on the twelve keepsake goals.
static func goal_msg(resident:String,stage:int)->String:
	var base:=success_msg(resident,Goals.goal(resident,stage))
	return base if ks_kind(resident,stage).is_empty() else base+MSG_KEEPSAKE_TAIL

static func ks_kind(resident:String,stage:int)->String:
	return str(KEEPSAKE_GOALS.get("%s %d"%[resident,stage],""))

static func ks_name(resident:String,stage:int)->String:
	return str(Goals.goal(resident,stage).get("keepsake",""))

## Expected view entry "keepsake" of a keepsake goal.
static func want_keepsake(resident:String,stage:int,claimed:bool)->Dictionary:
	var kind:=ks_kind(resident,stage)
	return {"kind":kind,"item":kind+"_kit","name":ks_name(resident,stage),"claimed":claimed}

## `row` plus the expected keepsake entry when the goal has one.
static func with_keepsake(row:Dictionary,resident:String,stage:int,claimed:bool)->Dictionary:
	var out:Dictionary=row.duplicate(true)
	if not ks_kind(resident,stage).is_empty():out["keepsake"]=want_keepsake(resident,stage,claimed)
	return out

static func claim_msg(resident:String,stage:int)->String:
	return "%s把紀念小物「%s」交給你，已放進背包。在家園工坊的「生活」頁選它就能擺到家園。"%[Bond.name_of(resident),ks_name(resident,stage)]

static func claimed_msg(resident:String,stage:int)->String:
	return "「%s」已經領過了。"%ks_name(resident,stage)

static func not_done_claim_msg(resident:String,stage:int)->String:
	return "先和%s一起完成〈%s〉，才有紀念小物。"%[Bond.name_of(resident),str(Goals.goal(resident,stage).get("title",""))]

static func cap_msg(resident:String,stage:int)->String:
	return "背包裡的「%s」已經放不下了，先整理背包。"%ks_name(resident,stage)

## {kit item: int count} for every keepsake kit key present in the inventory.
static func kit_counts(person:Dictionary)->Dictionary:
	var out:={}
	var held:Variant=person.get("inventory")
	if not held is Dictionary:return out
	for item:String in Goals.keepsake_items():
		if held.has(item):out[item]=int(held[item])
	return out

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

func act(w,token:String,action:String,cell:Vector2i,extra:String,request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "goal-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func do_goal(w,token:String,cell:Vector2i,extra:String,request:String="")->Dictionary:
	return act(w,token,Goals.ACTION,cell,extra,request)

## Rejected (with the exact message unless `message` is empty) and the whole
## world state byte-identical after canonicalisation.
func refuse(w,token:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	refuse_act(w,token,Goals.ACTION,cell,extra,message,label)

## Same as refuse() for any action (used for resident_keepsake).
func refuse_act(w,token:String,action:String,cell:Vector2i,extra:String,message:String,label:String)->void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or msg(r)==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),msg(r)])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func write_fixture(path:String,data:Variant)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func validates(data:Variant)->bool:
	var parsed:Variant=JSON.parse_string(JSON.stringify(data))
	if not parsed is Dictionary:return false
	return Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

static func items_ok(items:Variant)->bool:
	if not items is Dictionary or items.is_empty():return false
	for item in items:
		if not item is String or not World.NAMES.has(item):return false
		var count:Variant=items[item]
		if not count is int or int(count)<=0:return false
	return true

# ------------------------------------------------------------- needs helpers --

## True when `text` names no need id (quoted) and no need label.
static func no_need_rows(text:String)->bool:
	for id:String in NEED_TEXT:
		if text.contains("\"%s\""%id) or text.contains(str(NEED_TEXT[id])):return false
	return true

static func need_msg(label:String)->String:
	return "還不能一起做這件事：要先「%s」。"%label

## Independent expectation of need_label: literal text, known_three with the
## count of residents other than luoluo at stage >= 1, capped at 3.
static func want_label(need:String,person:Dictionary)->String:
	if need=="known_three":
		var count:=0
		for other:String in Bond.RESIDENTS:
			if other!="luoluo" and Bond.stage(person,other)>=1:count+=1
		return "%s（目前 %d 位）"%[str(NEED_TEXT["known_three"]),mini(3,count)]
	return str(NEED_TEXT.get(need,need))

## Expected needs rows of `e`; every need met unless `met` says otherwise.
static func want_rows(e:Dictionary,person:Dictionary,met:Dictionary)->Array:
	var rows:Array=[]
	var needs:Array=e.get("needs",[])
	for need:String in needs:
		rows.append({"id":need,"label":want_label(need,person),"met":bool(met.get(need,true))})
	return rows

## Expected open/locked view row: needs rows only on goals that have needs.
static func want_row(e:Dictionary,person:Dictionary,state_name:String,met:Dictionary)->Dictionary:
	var row:Dictionary={"state":state_name,"choice":""}
	if e.has("needs"):row["needs"]=want_rows(e,person,met)
	return row

## Locked row shape: needs key (with the goal's need ids) iff the goal has needs;
## batch 3: an unclaimed keepsake entry iff the goal has a keepsake.
static func locked_row_ok(resident:String,key:String,row:Dictionary)->bool:
	if str(row.get("state",""))!="locked" or str(row.get("choice","?"))!="":return false
	var e:Dictionary=Goals.goal(resident,int(key))
	var has_ks:=not ks_kind(resident,int(key)).is_empty()
	var want_size:=2+(1 if e.has("needs") else 0)+(1 if has_ks else 0)
	if row.size()!=want_size:return false
	if has_ks:
		var ks_found:Variant=row.get("keepsake")
		if not ks_found is Dictionary or not same(ks_found,want_keepsake(resident,int(key),false)):return false
	if not e.has("needs"):return true
	if not row.get("needs") is Array:return false
	var rows:Array=row["needs"]
	var ids:Array=[]
	for found in rows:
		if not found is Dictionary:return false
		var d:Dictionary=found
		ids.append(str(d.get("id","")))
	var want:Array=e["needs"]
	return ids==want

## Goals.view with the world state and the player's token (as Session sends it).
static func view_at(w,token:String,resident:String,stage:int)->Dictionary:
	var state:Dictionary=w.state
	var v:Dictionary=Goals.view(pl(w,token),state,token)
	var own:Dictionary=v.get(resident,{})
	var row:Dictionary=own.get(str(stage),{})
	return row

static func market_with_report()->Dictionary:
	var m:Dictionary=MarketStall.fresh()
	m["open_day"]=0
	m["report"]={"day":0,"visitors":0,"stalls":0,"theme":MarketStall.theme_of(0),"sold":{},"coins":0}
	return m

static func festival_at(number:int,active:bool)->Dictionary:
	var f:Dictionary=Festival.fresh()
	f["round"]=number
	f["active"]=active
	return f

## PRESET: moves state.time forward by whole days to the next day (possibly
## today) whose home weather is rainy / not rainy.
static func move_weather(w,rainy:bool)->void:
	var now:float=float(w.state.time)
	for k in range(0,15):
		var t:float=now+float(k)*Weather.DAY_SECONDS
		if Weather.rains(Weather.day_index(t),"home")==rainy:
			w.state["time"]=t
			return

## PRESET: an object of `kind` owned by `owner` at an off-map key.
func put_object(w,owner:String,kind:String)->String:
	serial+=1
	var k:String=World.key(Vector2i(-200-serial,-200))
	var objects:Dictionary=w.state.objects
	objects[k]={"type":kind,"owner":owner,"items":{}}
	return k

static func clear_beds(w,owner:String)->void:
	var objects:Dictionary=w.state.objects
	for k in objects.keys():
		var obj:Variant=objects[k]
		if obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==owner:objects.erase(k)

## PRESET: makes one prerequisite hold (met) or not hold for `token`.
func set_need(w,token:String,need:String,met:bool)->void:
	var p:Dictionary=pl(w,token)
	match need:
		"own_bed":
			clear_beds(w,token)
			if met:put_object(w,token,"bed")
		"glass_crafted":
			p["greenhouse_glass_crafted"]=met
		"market_round":
			if met:p["market"]=market_with_report()
			else:p.erase("market")
		"festival_done":
			w.state["festival"]=festival_at(1 if met else 0,false)
		"known_three":
			for other:String in KNOWN_OTHERS:
				if met:
					set_points(w,token,other,int(Bond.THRESHOLDS[0]))
				elif p.get("bonds") is Dictionary:
					var bonds:Dictionary=p["bonds"]
					bonds.erase(other)
		"fair_weather":
			move_weather(w,not met)
		_:
			expect(false,"unknown need "+need)

## A player standing at `resident` at exactly `stage`, holding the exact cost.
func ready_player(w,token:String,resident:String,stage:int,option:String)->Vector2i:
	w.add_player(token,"丁")
	var cell:Vector2i=cell_of(w,resident)
	go(w,token,region_of(w,resident),cell)
	set_points(w,token,resident,int(Bond.THRESHOLDS[stage-1]))
	fill(w,token,Goals.cost(Goals.goal(resident,stage),option),0)
	return cell

# ------------------------------------------------------------------ catalog --

func test_catalog()->void:
	expect(Goals.ACTION=="resident_goal" and Goals.RECORD_KEY=="bond_goals" and Goals.STEP_COUNT==3,"ACTION resident_goal, RECORD_KEY bond_goals, STEP_COUNT 3")
	expect(World.RESIDENT_GOALS.ACTION==Goals.ACTION,"World wires the same RESIDENT_GOALS module")
	expect(Goals.ACTION not in Bond.ACTIONS,"resident_goal is not one of the bond talk/gift actions")
	var keys:Array=Goals.GOALS.keys()
	keys.sort()
	expect(keys==TWELVE,"GOALS covers exactly the twelve bond residents (%s)"%str(keys))
	var count:=0
	var ordered:Array=[]
	var tags:Array=[]
	var with_needs:Dictionary={}
	for resident in Goals.GOALS:
		expect(resident is String and resident in Bond.RESIDENTS,"GOALS resident %s is in Bond.RESIDENTS"%str(resident))
		var stages:Dictionary=Goals.GOALS[resident]
		expect(not stages.is_empty(),"%s has at least one goal"%str(resident))
		for stage in stages:
			count+=1
			var tag:="%s %s"%[str(resident),str(stage)]
			tags.append(tag)
			expect(stage is int and int(stage)>=1 and int(stage)<=4,tag+": stage is an int within 1..4")
			var e:Dictionary=stages[stage]
			for field in e:
				expect(field in ALLOWED_FIELDS,"%s: field %s is a known goal field"%[tag,str(field)])
			for field in ["title","task","keepsake"]:
				expect(e.get(field) is String and not str(e.get(field)).strip_edges().is_empty(),"%s: %s is a non-empty string"%[tag,field])
			var quote:Variant=e.get("quote")
			var quote_ok:bool=quote is Array and quote.size()==2
			if quote_ok:
				for line in quote:
					if not line is String or str(line).strip_edges().is_empty():quote_ok=false
			expect(quote_ok,tag+": quote has exactly 2 non-empty lines")
			expect(Goals.has_goal(str(resident),int(stage)) and Goals.goal(str(resident),int(stage))==e,tag+": has_goal/goal find it")
			expect(e.has("items") or e.has("options") or e.has("steps") or e.has("needs"),tag+": asks for items, a choice, steps or a prerequisite")
			if e.has("needs"):
				var needs:Variant=e.get("needs")
				var needs_ok:bool=needs is Array and not (needs as Array).is_empty()
				var seen:Array=[]
				if needs_ok:
					for need in needs:
						if not need is String or not Goals.NEEDS.has(need) or need in seen:needs_ok=false
						seen.append(need)
				expect(needs_ok,tag+": needs is a non-empty list of unique known need ids (%s)"%str(needs))
				with_needs[tag]=needs
			if e.has("items"):
				expect(items_ok(e.get("items")),tag+": items are known item ids with positive int counts")
			if e.has("options"):
				var opts:Variant=e.get("options")
				var opts_ok:bool=opts is Array and opts.size()>=2
				var ids:Array=[]
				if opts_ok:
					for o in opts:
						if not o is Dictionary:
							opts_ok=false
							continue
						var option:Dictionary=o
						var id:Variant=option.get("id")
						if not id is String or str(id).is_empty() or str(id).contains(":") or id in ids:opts_ok=false
						ids.append(id)
						if not option.get("label") is String or str(option.get("label")).strip_edges().is_empty():opts_ok=false
						for field in option:
							if field not in ["id","label","items"]:opts_ok=false
						if option.has("items") and not items_ok(option.get("items")):opts_ok=false
				expect(opts_ok,tag+": at least two options, unique non-empty ids, labels, valid per-option items (%s)"%str(ids))
			if e.has("steps"):
				var steps:Variant=e.get("steps")
				var steps_ok:bool=steps is Array and steps.size()==3
				if steps_ok:
					for step_name in steps:
						if not step_name is String or str(step_name).strip_edges().is_empty():steps_ok=false
				expect(steps_ok,tag+": exactly 3 non-empty steps")
			if e.has("order"):
				ordered.append(tag)
				expect(e.has("steps"),tag+": order only on a goal with steps")
				var order:Variant=e.get("order")
				var perm_ok:bool=order is Array and order.size()==3
				if perm_ok:
					for index in order:
						if not index is int:perm_ok=false
					var sorted_order:Array=(order as Array).duplicate()
					sorted_order.sort()
					if sorted_order!=[0,1,2]:perm_ok=false
				expect(perm_ok,tag+": order is a permutation of 0..2 (%s)"%str(order))
	expect(count==28 and Goals.total()==28,"28 goals in total (counted %d, total() %d)"%[count,Goals.total()])
	tags.sort()
	expect(tags==ALL_GOALS,"the 28 goals are exactly the batch 1 + batch 2 list (%s)"%str(tags))
	expect(same(with_needs,WANT_NEEDS),"exactly aru 1, mianmian 4, xinghe 3, lingpopo 4, xiaoli 3, luoluo 2 carry needs (%s)"%str(with_needs))
	expect(Goals.NEEDS==NEED_TEXT,"NEEDS has exactly the six ids with their labels (%s)"%str(Goals.NEEDS))
	expect(Goals.KNOWN_NEEDED==3,"KNOWN_NEEDED is 3")
	ordered.sort()
	expect(ordered==["achao 1","lingpopo 2"],"only achao 1 and lingpopo 2 have a fixed order (%s)"%str(ordered))
	expect(right_steps(Goals.goal("achao",1))=="210" and right_steps(Goals.goal("lingpopo",2))=="102","fixed orders: achao 210, lingpopo 102")
	# Batch 2 costs.
	expect(Goals.cost(Goals.goal("aru",1),"")=={"wood":10},"cost aru 1 = 10 wood")
	expect(Goals.cost(Goals.goal("mianmian",1),"")=={"feed":1},"cost mianmian 1 = 1 feed")
	expect(Goals.cost(Goals.goal("xinghe",3),"")=={"glass":2,"copper_joint":2},"cost xinghe 3 = 2 glass + 2 copper joints")
	for option_id:String in ["none","chestnut","tomorrow"]:
		expect(Goals.cost(Goals.goal("xiaoli",4),option_id)=={"plank":2},"cost xiaoli 4 %s = 2 planks"%option_id)
	for costless:Array in [["bobo",4,"home"],["mianmian",4,""],["lingpopo",4,""],["xiaoli",3,""],["luoluo",2,""],["luoluo",4,"blank"],["nuannuan",4,"pool"]]:
		expect(Goals.cost(Goals.goal(str(costless[0]),int(costless[1])),str(costless[2])).is_empty(),"%s %d costs nothing"%[str(costless[0]),int(costless[1])])
	for bad:Array in [["tom",1],["aru",3],["aru",0],["aru",5],["milu",2],["milu",4],["luoluo",1],["xinghe",4],["achao",2],["diandian",4],["",1]]:
		expect(not Goals.has_goal(str(bad[0]),int(bad[1])) and Goals.goal(str(bad[0]),int(bad[1])).is_empty(),"no goal for %s %d"%[str(bad[0]),int(bad[1])])
	# sequence()
	expect(Goals.sequence("012")==[0,1,2] and Goals.sequence("210")==[2,1,0] and Goals.sequence("102")==[1,0,2],"sequence parses permutations in order")
	for bad:String in BAD_STEPS:
		expect(Goals.sequence(bad).is_empty(),"sequence('%s') is rejected"%bad)
	# cost()
	expect(Goals.cost(Goals.goal("bobo",2),"siding")=={"copper_joint":2,"plank":2},"cost bobo 2 siding = shared items only")
	expect(Goals.cost(Goals.goal("lingpopo",3),"salad")=={"copper_joint":2,"glass":2,"salad":1},"cost lingpopo 3 salad = shared items + the dish")
	expect(Goals.cost(Goals.goal("milu",3),"carrot_soup")=={"carrot_soup":2},"cost milu 3 carrot_soup = per-option items only")
	expect(Goals.cost(Goals.goal("xinghe",2),"bluebell_chime")=={"bluebell":2,"chime_herb":2},"cost xinghe 2 bluebell_chime")
	expect(Goals.cost(Goals.goal("chacha",3),"").is_empty() and Goals.cost(Goals.goal("luoluo",3),"aloud").is_empty(),"chacha 3 and luoluo 3 cost nothing")
	var scratch:Dictionary=Goals.cost(Goals.goal("aru",2),"")
	scratch["plank"]=99
	expect(Goals.cost(Goals.goal("aru",2),"")=={"plank":4},"cost() returns a copy (mutating it does not change the catalog)")
	# done() / completed() / view()
	expect(Goals.done({},"milu").is_empty() and Goals.done({"bond_goals":[]},"milu").is_empty() and Goals.done({"bond_goals":{"milu":"1"}},"milu").is_empty(),"done() tolerates missing/odd records")
	expect(Goals.done({"bond_goals":{"milu":{"1":"","3":"soup"}}},"milu")=={1:"",3:"soup"},"done() maps stage strings to ints")
	expect(Goals.completed({"bond_goals":{"milu":{"1":"","3":"soup"},"bobo":{"2":"shed"}}})==3,"completed() counts every done goal")
	var fresh:Dictionary=Goals.view({})
	var fresh_keys:Array=fresh.keys()
	fresh_keys.sort()
	expect(fresh_keys==TWELVE,"view lists all twelve residents")
	var all_locked:=true
	for resident:String in Goals.GOALS:
		var own:Dictionary=fresh.get(resident,{})
		var want:Array=[]
		for stage:int in Goals.GOALS[resident]:want.append(str(stage))
		var got:Array=own.keys()
		got.sort()
		want.sort()
		if got!=want:all_locked=false
		for key in own:
			if not own[key] is Dictionary or not locked_row_ok(resident,str(key),own[key]):all_locked=false
	expect(all_locked,"fresh view: every goal stage listed and locked; needs rows exactly on goals with needs")
	var stateless:Dictionary=fresh.get("luoluo",{})
	expect(stateless.get("2",{})=={"state":"locked","choice":"","needs":[{"id":"known_three","label":str(NEED_TEXT["known_three"])+"（目前 0 位）","met":false}]},
		"view(person) without state: needs rows present with met=false, no crash (%s)"%str(stateless.get("2")))
	var no_state_rows:=true
	for resident:String in fresh:
		var own:Dictionary=fresh[resident]
		for key in own:
			var row:Dictionary=own[key]
			if row.has("needs"):
				for need_row in row["needs"]:
					if not need_row is Dictionary or need_row.get("met")!=false:no_state_rows=false
	expect(no_state_rows,"view(person) without state: every needs row has met=false")
	# Batch 3: milu 3 carries a keepsake entry; done via a direct record (no bond_keepsakes) -> unclaimed.
	var some:Dictionary=Goals.view({"bonds":{"milu":rec(14,-1,-1)},"bond_goals":{"milu":{"3":"soup"}}})
	expect(some.get("milu",{})=={"1":{"state":"open","choice":""},"3":with_keepsake({"state":"done","choice":"soup"},"milu",3,false)},"view: milu 1 open, 3 done with its choice and an unclaimed keepsake (%s)"%str(some.get("milu")))

# --------------------------------------------------------- the 28 goal flows --

func goal_flow(resident:String,stage:int)->void:
	flows+=1
	var e:Dictionary=Goals.goal(resident,stage)
	var tag:="%s %d"%[resident,stage]
	var w:=World.new()
	w.state["picnic"]=true  # PRESET: residents gated by the picnic are present
	w.state["dock_stage"]=1  # PRESET: achao is present
	var token:="goal-main-%s-%d"%[resident,stage]
	w.add_player(token,"甲")
	w.add_player(WATCHER,"乙")
	var region:=region_of(w,resident)
	var cell:=cell_of(w,resident)
	go(w,token,region,cell)
	go(w,WATCHER,region,cell)
	var threshold:=int(Bond.THRESHOLDS[stage-1])
	set_points(w,WATCHER,resident,threshold)
	var opts:=option_ids(e)
	var first:String=str(opts[0])
	var steps:=right_steps(e)
	var good:=extra_of(resident,stage,first,steps)
	var cost:Dictionary=Goals.cost(e,first)
	# Batch 3: "" for the 16 goals without a keepsake.
	var kind:=ks_kind(resident,stage)
	var kit:=kind+"_kit" if not kind.is_empty() else ""
	var claim_extra:="%s:%d"%[resident,stage]
	expect(Goals.keepsake_kind(resident,stage)==kind,"%s: keepsake_kind is '%s'"%[tag,kind])
	# 0. PRESET: every prerequisite of this goal holds for both players.
	var needs:Array=e.get("needs",[])
	for need:String in needs:
		set_need(w,token,need,true)
		set_need(w,WATCHER,need,true)
		expect(Goals.need_met(need,w.state,token) and Goals.need_met(need,w.state,WATCHER),"%s: preset makes %s hold for both players"%[tag,need])
	# 1. One stage short.
	set_points(w,token,resident,threshold-1)
	fill(w,token,cost,1)
	expect(Bond.stage(pl(w,token),resident)==stage-1,tag+": preset bond is exactly one stage short")
	expect(str(view_row(w,token,resident,stage).get("state",""))=="locked",tag+": view shows locked")
	var full:=view_at(w,token,resident,stage)
	expect(full==with_keepsake(want_row(e,pl(w,token),"locked",{}),resident,stage,false),"%s: locked view row with state (needs rows iff the goal has needs, unclaimed keepsake iff it has one) (%s)"%[tag,str(full)])
	refuse(w,token,cell,good,stage_msg(resident,stage),tag+": one stage short")
	# 2. Reach the stage.
	set_points(w,token,resident,threshold)
	expect(Bond.stage(pl(w,token),resident)==stage,tag+": preset bond reaches the stage exactly")
	expect(str(view_row(w,token,resident,stage).get("state",""))=="open",tag+": view shows open")
	full=view_at(w,token,resident,stage)
	expect(full==with_keepsake(want_row(e,pl(w,token),"open",{}),resident,stage,false),"%s: open view row with state, needs all met (%s)"%[tag,str(full)])
	expect(full.has("keepsake")!=kind.is_empty(),"%s: view row has a keepsake key iff the goal has a keepsake"%tag)
	# 2b. Claim (through World.act) before the goal is done.
	if kind.is_empty():refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,MSG_NO_KEEPSAKE,tag+": claim on a goal without a keepsake (open)")
	else:refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,not_done_claim_msg(resident,stage),tag+": claim before the goal is done")
	# 3. Option and step validation.
	if e.has("options"):
		refuse(w,token,cell,extra_of(resident,stage,"nope",steps),MSG_PICK,tag+": invalid option id")
		refuse(w,token,cell,extra_of(resident,stage,"",steps),MSG_PICK,tag+": empty option")
		refuse(w,token,cell,extra_of(resident,stage,first.to_upper(),steps),MSG_PICK,tag+": option id in the wrong case")
		refuse(w,token,cell,extra_of(resident,stage,first+" ",steps),MSG_PICK,tag+": option id with a trailing space")
	else:
		refuse(w,token,cell,extra_of(resident,stage,"soup",steps),MSG_REOPEN,tag+": option on an option-less goal")
		refuse(w,token,cell,extra_of(resident,stage,"x",steps),MSG_REOPEN,tag+": option 'x' on an option-less goal")
	if e.has("steps"):
		for bad:String in BAD_STEPS:
			refuse(w,token,cell,extra_of(resident,stage,first,bad),MSG_STEPS,"%s: steps '%s'"%[tag,bad])
		if e.has("order"):
			for perm:String in PERMS:
				if perm!=steps:refuse(w,token,cell,extra_of(resident,stage,first,perm),order_msg(resident),"%s: wrong order %s"%[tag,perm])
	else:
		refuse(w,token,cell,extra_of(resident,stage,first,"012"),MSG_REOPEN,tag+": steps on a step-less goal")
		refuse(w,token,cell,extra_of(resident,stage,first,"0"),MSG_REOPEN,tag+": one step on a step-less goal")
	# 3b. Each prerequisite unmet (everything else satisfied), and check order.
	for need:String in needs:
		var ntag:="%s %s"%[tag,need]
		set_need(w,token,need,false)
		fill(w,token,cost,1)
		expect(not Goals.need_met(need,w.state,token),ntag+": preset makes the prerequisite fail")
		var unmet_msg:=need_msg(want_label(need,pl(w,token)))
		expect(Goals.need_label(need,w.state,token)==want_label(need,pl(w,token)),ntag+": need_label is the literal label")
		full=view_at(w,token,resident,stage)
		expect(full==with_keepsake(want_row(e,pl(w,token),"open",{need:false}),resident,stage,false),"%s: view row shows the need unmet (%s)"%[ntag,str(full)])
		refuse(w,token,cell,good,unmet_msg,ntag+": unmet with stage, option, steps and items satisfied")
		# Stage comes first.
		set_points(w,token,resident,threshold-1)
		refuse(w,token,cell,good,stage_msg(resident,stage),ntag+": stage short and need unmet -> stage message")
		set_points(w,token,resident,threshold)
		# Option comes before needs.
		if e.has("options"):
			refuse(w,token,cell,extra_of(resident,stage,"",steps),MSG_PICK,ntag+": option missing and need unmet -> option message")
		else:
			refuse(w,token,cell,extra_of(resident,stage,"soup",steps),MSG_REOPEN,ntag+": stray option and need unmet -> reopen message")
		# Steps come before needs.
		if e.has("steps"):
			refuse(w,token,cell,extra_of(resident,stage,first,"0"),MSG_STEPS,ntag+": steps incomplete and need unmet -> steps message")
			if e.has("order"):
				for perm:String in PERMS:
					if perm!=steps:
						refuse(w,token,cell,extra_of(resident,stage,first,perm),order_msg(resident),"%s: wrong order %s and need unmet -> order message"%[ntag,perm])
						break
		else:
			refuse(w,token,cell,extra_of(resident,stage,first,"012"),MSG_REOPEN,ntag+": stray steps and need unmet -> reopen message")
		# Needs come before items.
		for item:String in cost:
			fill(w,token,cost,1)
			var short_inv:Dictionary=pl(w,token).inventory
			short_inv.erase(item)
			refuse(w,token,cell,good,unmet_msg,"%s: %s absent and need unmet -> need message"%[ntag,item])
		if not cost.is_empty():
			var empty_inv:Dictionary=pl(w,token).inventory
			for item:String in cost:empty_inv.erase(item)
			refuse(w,token,cell,good,unmet_msg,ntag+": every cost item absent and need unmet -> need message")
		fill(w,token,cost,1)
		set_need(w,token,need,true)
		expect(Goals.need_met(need,w.state,token),ntag+": preset restores the prerequisite")
	# 4. Missing items: each cost item one short, then absent.
	if cost.is_empty():
		expect(not e.has("items"),tag+": no cost means no items field")
	for item:String in cost:
		var needed:=int(cost[item])
		fill(w,token,cost,0)
		set_item(w,token,item,needed-1)
		refuse(w,token,cell,good,short_msg(item,needed-1,needed),"%s: %s one short"%[tag,item])
		var inv:Dictionary=pl(w,token).inventory
		inv.erase(item)
		refuse(w,token,cell,good,short_msg(item,0,needed),"%s: %s absent"%[tag,item])
	expect(not pl(w,token).has(Goals.RECORD_KEY),tag+": no refusal wrote a bond_goals key")
	expect(not pl(w,token).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,token)).is_empty(),tag+": no refusal wrote bond_keepsakes or a keepsake kit")
	# 5. Success: only the cost items change, by exactly the cost (plus one kit on the 12 keepsake goals).
	fill(w,token,cost,1)
	set_item(w,token,"radish",3)
	var p:Dictionary=pl(w,token)
	if not kind.is_empty():
		var open_ks:Dictionary=view_at(w,token,resident,stage).get("keepsake",{})
		expect(open_ks.get("claimed")==false,"%s: keepsake claimed=false before completing (%s)"%[tag,str(open_ks)])
	var inv_before:Dictionary=p.inventory.duplicate(true)
	var bonds_before:Dictionary=(p.bonds as Dictionary).duplicate(true)
	var stories_before:Variant=p.get("stories",{})
	if stories_before is Dictionary:stories_before=(stories_before as Dictionary).duplicate(true)
	var coins_before:=int(p.get("coins",0))
	var bond_view:Dictionary=Bond.view(p,float(w.state.time))
	var watcher_before:=var_to_bytes(canon(pl(w,WATCHER)))
	var r:=do_goal(w,token,cell,good)
	expect(bool(r.get("ok",false)),"%s: completes with option '%s' steps '%s' (got '%s')"%[tag,first,steps,msg(r)])
	expect(msg(r)==goal_msg(resident,stage),"%s: exact success message (got '%s')"%[tag,msg(r)])
	expect(msg(r).contains(str(e.title)) and msg(r).contains(str(e.keepsake)),tag+": message names the title and the keepsake")
	if kind.is_empty():
		expect(msg(r)==success_msg(resident,e) and not msg(r).contains(MSG_KEEPSAKE_TAIL),tag+": no keepsake -> message unchanged from batch 2")
	else:
		expect(msg(r).ends_with(MSG_KEEPSAKE_TAIL) and msg(r)==success_msg(resident,e)+MSG_KEEPSAKE_TAIL,tag+": message ends with the keepsake sentence")
	p=pl(w,token)
	var expected:Dictionary=inv_before.duplicate(true)
	for item:String in cost:expected[item]=int(inv_before[item])-int(cost[item])
	if not kind.is_empty():
		expect(not inv_before.has(kit),tag+": no kit held before completing")
		expected[kit]=1
	expect(p.inventory==expected,"%s: inventory changed by exactly %s%s (got %s)"%[tag,str(cost),"" if kind.is_empty() else " and +1 "+kit,str(p.inventory)])
	var kit_total:=0
	for item:String in Goals.keepsake_items():kit_total+=int(p.inventory.get(item,0))
	expect(kit_total==(0 if kind.is_empty() else 1),"%s: exactly %d keepsake kit(s) of any kind held"%[tag,0 if kind.is_empty() else 1])
	if kind.is_empty():
		expect(not p.has(Goals.KEEPSAKE_KEY),tag+": no keepsake -> no bond_keepsakes key created")
	else:
		expect(p.get(Goals.KEEPSAKE_KEY)=={kind:true},"%s: bond_keepsakes is exactly {%s:true} (got %s)"%[tag,kind,str(p.get(Goals.KEEPSAKE_KEY))])
		expect(Goals.valid_keepsakes(p.get(Goals.KEEPSAKE_KEY),p),tag+": the granted record passes valid_keepsakes")
	var want_record:Dictionary={resident:{str(stage):first}}
	expect(p.get(Goals.RECORD_KEY)==want_record,"%s: bond_goals is exactly %s (got %s)"%[tag,str(want_record),str(p.get(Goals.RECORD_KEY))])
	expect(Goals.done(p,resident)=={stage:first} and Goals.completed(p)==1,tag+": done()/completed() see one goal")
	expect(p.bonds==bonds_before and Bond.view(p,float(w.state.time))==bond_view,tag+": bond points, stage and daily flags unchanged")
	expect(p.get("stories",{})==stories_before and int(p.get("coins",0))==coins_before,tag+": stories and coins unchanged")
	expect(var_to_bytes(canon(pl(w,WATCHER)))==watcher_before,tag+": the other player's whole record is byte-identical")
	var row:=view_row(w,token,resident,stage)
	expect(str(row.get("state",""))=="done" and str(row.get("choice","?"))==first,"%s: view shows done with choice '%s' (%s)"%[tag,first,str(row)])
	full=view_at(w,token,resident,stage)
	expect(full==with_keepsake({"state":"done","choice":first},resident,stage,true),"%s: done view row with state carries no needs key (keepsake claimed=true iff it has one) (%s)"%[tag,str(full)])
	if not kind.is_empty():
		var done_ks:Dictionary=full.get("keepsake",{})
		expect(done_ks.get("claimed")==true,"%s: keepsake claimed flipped to true"%tag)
		var watcher_ks:Dictionary=view_at(w,WATCHER,resident,stage).get("keepsake",{})
		expect(watcher_ks.get("claimed")==false,tag+": the other player's keepsake stays unclaimed")
	expect(str(view_row(w,WATCHER,resident,stage).get("state",""))=="open",tag+": the other player's view stays open")
	# 6. Repeat refused, even with items in hand.
	fill(w,token,cost,1)
	refuse(w,token,cell,good,done_msg(e),tag+": repeat")
	if opts.size()>1:refuse(w,token,cell,extra_of(resident,stage,str(opts[1]),steps),done_msg(e),tag+": repeat with another option")
	# 6b. Claim (through World.act) after a batch-3 completion: already granted / nothing to claim.
	if kind.is_empty():refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,MSG_NO_KEEPSAKE,tag+": claim on a done goal without a keepsake")
	else:refuse_act(w,token,Goals.CLAIM_ACTION,cell,claim_extra,claimed_msg(resident,stage),tag+": claim after a batch-3 completion -> already claimed")
	# 7. Talk still works and only changes the bond record.
	var points_before:=int(Bond.record(pl(w,token),resident).points)
	r=act(w,token,"resident_talk",cell,resident)
	expect(bool(r.get("ok",false)),"%s: talk after the goal still works (got '%s')"%[tag,msg(r)])
	expect(int(Bond.record(pl(w,token),resident).points)==mini(Bond.LIMIT,points_before+1),tag+": talk adds its one point (capped at the bond limit)")
	expect(pl(w,token).get(Goals.RECORD_KEY)==want_record,tag+": talk leaves bond_goals unchanged")
	# 8. Every other option and every free order on separate players.
	for i in range(1,opts.size()):
		solo(w,e,resident,stage,region,cell,str(opts[i]),steps,"%s option %s"%[tag,str(opts[i])])
	if e.has("steps") and not e.has("order"):
		for perm:String in PERMS:
			if perm!=steps:solo(w,e,resident,stage,region,cell,first,perm,"%s free order %s"%[tag,perm])
	# 9. The watcher completes the same goal on their own.
	fill(w,WATCHER,cost,0)
	var main_before:=var_to_bytes(canon(pl(w,token)))
	r=do_goal(w,WATCHER,cell,good)
	expect(bool(r.get("ok",false)),"%s: the other player completes the same goal (got '%s')"%[tag,msg(r)])
	expect(pl(w,WATCHER).get(Goals.RECORD_KEY)==want_record,tag+": the other player's own record")
	if kind.is_empty():
		expect(not pl(w,WATCHER).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,WATCHER)).is_empty(),tag+": the other player gets no keepsake either")
	else:
		expect(pl(w,WATCHER).get(Goals.KEEPSAKE_KEY)=={kind:true} and kit_counts(pl(w,WATCHER))=={kit:1},tag+": the other player gets their own kit and record")
	expect(var_to_bytes(canon(pl(w,token)))==main_before,tag+": the first player's whole record unchanged by the second")
	# 10. Needs are checked once: undoing them leaves both records done and valid.
	if not needs.is_empty():
		for need:String in needs:
			set_need(w,token,need,false)
			set_need(w,WATCHER,need,false)
			expect(not Goals.need_met(need,w.state,token) and not Goals.need_met(need,w.state,WATCHER),"%s: %s undone for both players"%[tag,need])
		for who:String in [token,WATCHER]:
			full=view_at(w,who,resident,stage)
			expect(full==with_keepsake({"state":"done","choice":first},resident,stage,true),"%s: still done without a needs key after the prerequisite is undone (%s)"%[tag,str(full)])
			expect(Goals.valid(goals_of(w,who),pl(w,who)),tag+": the record still passes Goals.valid after the prerequisite is undone")
		fill(w,token,cost,1)
		refuse(w,token,cell,good,done_msg(e),tag+": repeat with the prerequisite undone -> already-done message")

## A fresh player in the same world completes the goal with `option`/`steps`.
func solo(w,e:Dictionary,resident:String,stage:int,region:String,cell:Vector2i,option:String,steps:String,label:String)->void:
	serial+=1
	var token:="goal-solo-%d"%serial
	w.add_player(token,"丙")
	go(w,token,region,cell)
	set_points(w,token,resident,int(Bond.THRESHOLDS[stage-1]))
	var needs:Array=e.get("needs",[])
	for need:String in needs:set_need(w,token,need,true)
	var cost:Dictionary=Goals.cost(e,option)
	fill(w,token,cost,0)
	set_item(w,token,"radish",1)
	var before:Dictionary=pl(w,token).inventory.duplicate(true)
	var r:=do_goal(w,token,cell,extra_of(resident,stage,option,steps))
	expect(bool(r.get("ok",false)),"%s: accepted (got '%s')"%[label,msg(r)])
	var expected:Dictionary=before.duplicate(true)
	for item:String in cost:expected[item]=int(before[item])-int(cost[item])
	var kind:=ks_kind(resident,stage)
	if not kind.is_empty():expected[kind+"_kit"]=1  # batch 3: one kit granted
	expect(pl(w,token).inventory==expected,"%s: charged exactly %s%s"%[label,str(cost),"" if kind.is_empty() else " (+1 kit)"])
	var want:Dictionary={resident:{str(stage):option}}
	expect(pl(w,token).get(Goals.RECORD_KEY)==want,"%s: record %s (got %s)"%[label,str(want),str(pl(w,token).get(Goals.RECORD_KEY))])
	if kind.is_empty():expect(not pl(w,token).has(Goals.KEEPSAKE_KEY),label+": no bond_keepsakes key")
	else:expect(pl(w,token).get(Goals.KEEPSAKE_KEY)=={kind:true},label+": bond_keepsakes {%s:true}"%kind)
	expect(msg(r)==goal_msg(resident,stage),"%s: exact success message (got '%s')"%[label,msg(r)])

# ------------------------------------------------------ World-layer refusals --

func test_world_rejections()->void:
	var w:=World.new()
	var t:="goal-reject-token"
	w.add_player(t,"甲")
	var aru:=cell_of(w,"aru")
	var milu:=cell_of(w,"milu")
	go(w,t,"home",aru)
	set_points(w,t,"aru",6)
	set_item(w,t,"plank",5)
	var good:="aru:2::012"
	refuse(w,t,aru+Vector2i.RIGHT,good,MSG_PLACE,"aimed at the tile beside aru")
	refuse(w,t,aru+Vector2i.DOWN,good,MSG_PLACE,"aimed at the tile below aru")
	stand(w,t,milu)
	refuse(w,t,milu,good,MSG_PLACE,"aru's goal aimed at milu's cell")
	var p:Dictionary=pl(w,t)
	p["x"]=float(aru.x)+0.5
	p["y"]=float(aru.y)+5.5
	refuse(w,t,aru,good,MSG_FAR,"five tiles away from aru")
	stand(w,t,aru)
	for unknown:String in ["tom:2::012","Aru:2::012",":2::012","","::",":::"]:
		refuse(w,t,aru,unknown,MSG_PLACE,"unknown resident '%s'"%unknown)
	for malformed:String in ["aru","aru:2","aru:2:","aru:2::012:","aru:2::012:x","aru:x::012","aru:::012","aru:2.0::012","aru:two::012"]:
		refuse(w,t,aru,malformed,MSG_REOPEN,"malformed extra '%s'"%malformed)
	for nogoal:String in ["aru:0::","aru:3::","aru:4::","aru:5::","aru:-2::","aru:99::012"]:
		refuse(w,t,aru,nogoal,MSG_NO_GOAL,"stage without a goal '%s'"%nogoal)
	# aru 1 is a batch-2 goal now (needs own_bed; this player has no bed).
	refuse(w,t,aru,"aru:1::012",MSG_REOPEN,"aru 1 with steps is malformed")
	refuse(w,t,aru,"aru:1::",need_msg(str(NEED_TEXT["own_bed"])),"aru 1 without an own bed -> need message")
	# Wrong region: a player elsewhere aimed at the resident's coordinates.
	p=pl(w,t)
	p["region"]="jinguashi"
	refuse(w,t,aru,good,"","jinguashi player aimed at aru's home cell")
	set_points(w,t,"bobo",1)
	set_points(w,t,"nuannuan",1)
	set_points(w,t,"chacha",14)
	set_points(w,t,"diandian",6)
	set_points(w,t,"xinghe",6)
	set_item(w,t,"stone",8)
	set_item(w,t,"wood",8)
	set_item(w,t,"bluebell",2)
	set_item(w,t,"orange_blossom",2)
	for spec:Array in [["bobo","bobo:1::"],["nuannuan","nuannuan:1::"],["chacha","chacha:3::012"],["diandian","diandian:2:knees:"],["xinghe","xinghe:2:bluebell_orange:"]]:
		var target:=cell_of(w,str(spec[0]))
		go(w,t,"home",target)
		refuse(w,t,target,str(spec[1]),MSG_PLACE,"home player aimed at %s's %s cell"%[str(spec[0]),region_of(w,str(spec[0]))])
	go(w,t,"lanyang",cell_of(w,"bobo"))
	refuse(w,t,cell_of(w,"bobo"),"bobo:1::","","lanyang player aimed at bobo's cell")
	go(w,t,"maokong",cell_of(w,"xinghe"))
	refuse(w,t,cell_of(w,"xinghe"),"xinghe:2:bluebell_orange:","","maokong player aimed at xinghe's cell")
	expect(not pl(w,t).has(Goals.RECORD_KEY),"no World-layer refusal wrote bond_goals")
	go(w,t,"home",aru)
	var r:=do_goal(w,t,aru,good)
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"aru":{"2":""}},"after all refusals the right aru request succeeds (got '%s')"%msg(r))

# Residents not yet present (PRESET flags on a fresh world: picnic false, dock_stage 0).
func test_gates()->void:
	var specs:Array=[["mianmian",3,"ball",Bond.RANCH_LOCKED,"picnic"],["luoluo",3,"letter",Bond.POST_LOCKED,"picnic"],
		["lingpopo",2,"",Bond.BELL_LOCKED,"picnic"],["lingpopo",3,"salad",Bond.BELL_LOCKED,"picnic"],["achao",1,"",Bond.DOCK_LOCKED,"dock_stage"]]
	for spec:Array in specs:
		var resident:=str(spec[0])
		var stage:=int(spec[1])
		var option:=str(spec[2])
		var gate:=str(spec[3])
		var tag:="gate %s %d"%[resident,stage]
		var e:Dictionary=Goals.goal(resident,stage)
		var w:=World.new()
		var t:="goal-gate-token"
		w.add_player(t,"甲")
		expect(w.state.get("picnic",false)!=true and int(w.state.get("dock_stage",0))==0,tag+": fresh world has no picnic and no dock repair")
		var region:=region_of(w,resident)
		var cell:=cell_of(w,resident)
		go(w,t,region,cell)
		set_points(w,t,resident,int(Bond.THRESHOLDS[stage-1]))
		var cost:Dictionary=Goals.cost(e,option)
		fill(w,t,cost,0)
		var good:=extra_of(resident,stage,option,right_steps(e))
		refuse(w,t,cell,good,gate,tag+": before the gate opens")
		if str(spec[4])=="picnic":w.state["dock_stage"]=1
		else:w.state["picnic"]=true
		cell=cell_of(w,resident)
		go(w,t,region,cell)
		refuse(w,t,cell,good,gate,tag+": the other gate does not open it")
		if str(spec[4])=="picnic":w.state["picnic"]=true
		else:w.state["dock_stage"]=1
		cell=cell_of(w,resident)
		go(w,t,region,cell)
		var r:=do_goal(w,t,cell,good)
		expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={resident:{str(stage):option}},"%s: once present the same request succeeds (got '%s')"%[tag,msg(r)])

# ------------------------------------------- needs: need_met / need_label --

func test_need_rules()->void:
	var me:="goal-need-self"
	var other:="goal-need-other"
	# own_bed
	var objects:Dictionary={}
	var s:Dictionary={"players":{me:{},other:{}},"objects":objects}
	expect(not Goals.need_met("own_bed",s,me),"own_bed: no bed -> false")
	objects["3,4"]={"type":"bed","owner":other,"items":{}}
	expect(not Goals.need_met("own_bed",s,me),"own_bed: a bed owned by another token -> false")
	expect(Goals.need_met("own_bed",s,other),"own_bed: that bed counts for its owner")
	objects["5,4"]={"type":"chest","owner":me,"items":{}}
	objects["6,4"]={"type":"bench","owner":me,"items":{}}
	expect(not Goals.need_met("own_bed",s,me),"own_bed: own objects that are not a bed -> false")
	objects["7,4"]={"type":"bed","owner":me,"items":{}}
	expect(Goals.need_met("own_bed",s,me),"own_bed: own bed -> true")
	expect(not Goals.need_met("own_bed",{"players":{me:{}}},me),"own_bed: no objects layer -> false")
	expect(not Goals.need_met("own_bed",{"players":{"":{}},"objects":{"1,1":{"type":"bed","owner":""}}},""),"own_bed: an empty token never matches")
	# glass_crafted
	for sample:Array in [[{},"missing"],[{"greenhouse_glass_crafted":false},"false"],[{"greenhouse_glass_crafted":1},"int 1"],[{"greenhouse_glass_crafted":"true"},"string 'true'"]]:
		expect(not Goals.need_met("glass_crafted",{"players":{me:sample[0]}},me),"glass_crafted: %s -> false"%str(sample[1]))
	expect(Goals.need_met("glass_crafted",{"players":{me:{"greenhouse_glass_crafted":true}}},me),"glass_crafted: true -> true")
	expect(not Goals.need_met("glass_crafted",{"players":{other:{"greenhouse_glass_crafted":true}}},me),"glass_crafted: another player's glass does not count")
	expect(not Goals.need_met("glass_crafted",{},me),"glass_crafted: no players table -> false")
	# market_round
	for sample:Array in [[{},"no market"],[{"market":MarketStall.fresh()},"fresh market, empty report"],[{"market":{"report":{}}},"empty report"],
			[{"market":"open"},"market not a dictionary"],[{"market":{"report":[1]}},"report a list"],[{"market":{"report":"x"}},"report a string"],[{"market":{}},"market without report"]]:
		expect(not Goals.need_met("market_round",{"players":{me:sample[0]}},me),"market_round: %s -> false"%str(sample[1]))
	expect(Goals.need_met("market_round",{"players":{me:{"market":market_with_report()}}},me),"market_round: non-empty report -> true")
	expect(Goals.need_met("market_round",{"players":{me:{"market":{"report":{"day":0}}}}},me),"market_round: any non-empty report dictionary -> true")
	expect(not Goals.need_met("market_round",{"players":{other:{"market":market_with_report()}}},me),"market_round: another player's report does not count")
	# festival_done (island-wide; the token need not be a player)
	expect(not Goals.need_met("festival_done",{"players":{me:{}}},me),"festival_done: missing festival -> false")
	expect(not Goals.need_met("festival_done",{"festival":"done"},me),"festival_done: festival not a dictionary -> false")
	expect(not Goals.need_met("festival_done",{"festival":festival_at(0,false)},me),"festival_done: round 0 -> false")
	expect(not Goals.need_met("festival_done",{"festival":festival_at(1,true)},me),"festival_done: round 1 still active -> false")
	expect(Goals.need_met("festival_done",{"festival":festival_at(1,false)},me),"festival_done: round 1 finished -> true")
	expect(Goals.need_met("festival_done",{"festival":festival_at(2,true)},me),"festival_done: round 2 active (round 1 finished before) -> true")
	expect(Goals.need_met("festival_done",{"festival":festival_at(3,false)},"someone-absent"),"festival_done: counts for a token that is not even a player")
	# known_three
	var person:Dictionary={"bonds":{"luoluo":rec(24,-1,-1)}}
	var ks:Dictionary={"players":{me:person}}
	var known_label:=str(NEED_TEXT["known_three"])
	expect(not Goals.need_met("known_three",ks,me) and Goals.known_count(person,"luoluo")==0,"known_three: luoluo's own bond does not count")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 0 位）","known_three label with luoluo only: 0 (%s)"%Goals.need_label("known_three",ks,me))
	var bonds:Dictionary=person["bonds"]
	bonds["aru"]=rec(1,-1,-1)
	bonds["milu"]=rec(1,-1,-1)
	bonds["achao"]=rec(0,-1,-1)
	expect(not Goals.need_met("known_three",ks,me),"known_three: two others (plus one at 0 points) -> false")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 2 位）","known_three label: 2 (%s)"%Goals.need_label("known_three",ks,me))
	bonds["bobo"]=rec(1,-1,-1)
	expect(Goals.need_met("known_three",ks,me),"known_three: three others -> true")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 3 位）","known_three label: 3 (%s)"%Goals.need_label("known_three",ks,me))
	bonds["chacha"]=rec(6,-1,-1)
	bonds["diandian"]=rec(24,-1,-1)
	expect(Goals.need_met("known_three",ks,me) and Goals.known_count(person,"luoluo")==5,"known_three: five others -> true (known_count 5)")
	expect(Goals.need_label("known_three",ks,me)==known_label+"（目前 3 位）","known_three label is capped at 3 (%s)"%Goals.need_label("known_three",ks,me))
	expect(Goals.need_label("known_three",{},me)==known_label+"（目前 0 位）","known_three label without state: 0")
	expect(not Goals.need_met("known_three",{"players":{other:person}},me),"known_three: another player's bonds do not count")
	# fair_weather: only state.time and the home region's weather matter.
	var rainy_day:=-1
	var dry_day:=-1
	for d in range(0,14):
		if Weather.rains(float(d),"home"):
			if rainy_day<0:rainy_day=d
		elif dry_day<0:dry_day=d
	if expect(rainy_day>=0 and dry_day>=0,"weather.gd cycle has a rainy and a dry home day (%d, %d)"%[rainy_day,dry_day]):
		var rainy_time:float=float(rainy_day)*Weather.DAY_SECONDS+30.0
		var dry_time:float=float(dry_day)*Weather.DAY_SECONDS+30.0
		expect(not Goals.need_met("fair_weather",{"players":{me:{"region":"home"}},"time":rainy_time},me),"fair_weather: rainy day -> false")
		expect(Goals.need_met("fair_weather",{"players":{me:{"region":"home"}},"time":dry_time},me),"fair_weather: non-rainy day -> true")
		expect(Goals.need_met("fair_weather",{"time":int(dry_time)},me),"fair_weather: int time works")
		expect(not Goals.need_met("fair_weather",{"players":{me:{}}},me),"fair_weather: no time -> false")
		expect(not Goals.need_met("fair_weather",{"time":"0"},me),"fair_weather: time not a number -> false")
		expect(not Weather.rains(float(rainy_day),"mine_1"),"control: mine_1 is indoor and never rains on the rainy day")
		expect(not Goals.need_met("fair_weather",{"players":{me:{"region":"mine_1"}},"time":rainy_time},me),"fair_weather: a player indoors still sees the home rain -> false")
		expect(Goals.need_met("fair_weather",{"players":{me:{"region":"mine_1"}},"time":dry_time},me),"fair_weather: player region does not matter on a dry day -> true")
	# Labels, unknown ids, needs_view.
	for id:String in NEED_TEXT:
		if id!="known_three":
			expect(Goals.need_label(id,{},me)==str(NEED_TEXT[id]),"need_label(%s) is the literal label"%id)
		expect(not Goals.need_met(id,{},me),"need_met(%s) with an empty state -> false"%id)
	expect(Goals.need_label("nope",{},me)=="nope" and not Goals.need_met("nope",s,me),"unknown need id: label is the id, never met")
	expect(Goals.needs_view(Goals.goal("aru",1),s,me)==[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":true}],"needs_view aru 1 with an own bed")
	expect(Goals.needs_view(Goals.goal("aru",1),s,"goal-need-nobody")==[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":false}],"needs_view aru 1 for a token without a bed")
	expect(Goals.needs_view(Goals.goal("milu",1),s,me).is_empty(),"needs_view of a goal without needs is empty")
	# view(): open/locked rows with needs reflect the state; done rows and goals without needs have no needs key.
	var viewer:Dictionary={"bonds":{"aru":rec(1,-1,-1),"luoluo":rec(6,-1,-1),"milu":rec(14,-1,-1)},"bond_goals":{"milu":{"1":""}}}
	var vs:Dictionary={"players":{me:viewer},"objects":{"9,9":{"type":"bed","owner":me,"items":{}}},"festival":festival_at(1,false),"time":dry_day*Weather.DAY_SECONDS+1.0}
	var v:Dictionary=Goals.view(viewer,vs,me)
	expect(v["aru"]["1"]==with_keepsake({"state":"open","choice":"","needs":[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":true}]},"aru",1,false),"view: aru 1 open, own_bed met, keepsake unclaimed (%s)"%str(v["aru"]["1"]))
	expect(v["luoluo"]["2"]=={"state":"open","choice":"","needs":[{"id":"known_three","label":known_label+"（目前 2 位）","met":false}]},"view: luoluo 2 open, known_three unmet with count 2 (%s)"%str(v["luoluo"]["2"]))
	expect(v["lingpopo"]["4"]=={"state":"locked","choice":"","needs":[{"id":"festival_done","label":str(NEED_TEXT["festival_done"]),"met":true}]},"view: lingpopo 4 locked, festival_done met (%s)"%str(v["lingpopo"]["4"]))
	expect(v["mianmian"]["4"]=={"state":"locked","choice":"","needs":[{"id":"fair_weather","label":str(NEED_TEXT["fair_weather"]),"met":true}]},"view: mianmian 4 locked, fair_weather met")
	expect(v["xinghe"]["3"]=={"state":"locked","choice":"","needs":[{"id":"glass_crafted","label":str(NEED_TEXT["glass_crafted"]),"met":false}]},"view: xinghe 3 locked, glass_crafted unmet")
	expect(v["xiaoli"]["3"]=={"state":"locked","choice":"","needs":[{"id":"market_round","label":str(NEED_TEXT["market_round"]),"met":false}]},"view: xiaoli 3 locked, market_round unmet")
	expect(v["milu"]["1"]=={"state":"done","choice":""} and v["milu"]["3"]==with_keepsake({"state":"open","choice":""},"milu",3,false) and v["aru"]["2"]=={"state":"locked","choice":""},"view: goals without needs carry no needs key")
	# FIXTURE: aru 1 written as done directly (no bond_keepsakes) -> keepsake unclaimed.
	viewer["bond_goals"]={"aru":{"1":""},"milu":{"1":""}}
	v=Goals.view(viewer,vs,me)
	expect(v["aru"]["1"]==with_keepsake({"state":"done","choice":""},"aru",1,false),"view: a done goal with needs carries no needs key (%s)"%str(v["aru"]["1"]))
	# apply() directly: state omitted -> needs unmet; need before items.
	var solo_person:Dictionary={"bonds":{"aru":rec(1,-1,-1)}}
	var inv:Dictionary={"wood":10}
	var parts:=PackedStringArray(["aru","1","",""])
	var r:Dictionary=Goals.apply(solo_person,inv,parts,World.NAMES)
	expect(not bool(r.get("ok",true)) and msg(r)==need_msg(str(NEED_TEXT["own_bed"])),"apply without state: needs unmet (got '%s')"%msg(r))
	expect(inv=={"wood":10} and not solo_person.has(Goals.RECORD_KEY),"apply refusal changes neither inventory nor record")
	var bed_state:Dictionary={"players":{"goal-need-tk":solo_person},"objects":{"1,1":{"type":"bed","owner":"goal-need-tk","items":{}}}}
	var empty_inv:Dictionary={}
	r=Goals.apply(solo_person,empty_inv,parts,World.NAMES,{"players":{"goal-need-tk":solo_person}},"goal-need-tk")
	expect(not bool(r.get("ok",true)) and msg(r)==need_msg(str(NEED_TEXT["own_bed"])),"apply: need unmet and wood missing -> need message (got '%s')"%msg(r))
	r=Goals.apply(solo_person,empty_inv,parts,World.NAMES,bed_state,"goal-need-tk")
	expect(not bool(r.get("ok",true)) and msg(r)==short_msg("wood",0,10),"apply: need met, wood missing -> items message (got '%s')"%msg(r))
	r=Goals.apply(solo_person,inv,parts,World.NAMES,bed_state,"goal-need-tk")
	expect(bool(r.get("ok",false)) and inv=={"wood":0,"keepsake_aru_kit":1} and solo_person.get(Goals.RECORD_KEY)=={"aru":{"1":""}},"apply with state and an own bed succeeds, granting the aru kit (got '%s', %s)"%[msg(r),str(inv)])
	expect(solo_person.get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true} and msg(r)==goal_msg("aru",1),"apply aru 1: bond_keepsakes written and keepsake sentence appended")

# ---------------------------------------------- needs through World.act --

func test_needs_through_world()->void:
	var w:=World.new()
	w.state["picnic"]=true  # PRESET
	w.state["dock_stage"]=1  # PRESET
	# own_bed (aru 1)
	var t:="goal-act-bed"
	var o:="goal-act-bed-other"
	var cell:=ready_player(w,t,"aru",1,"")
	var bed_msg:=need_msg(str(NEED_TEXT["own_bed"]))
	refuse(w,t,cell,"aru:1::",bed_msg,"act own_bed: no bed")
	w.add_player(o,"乙")
	put_object(w,o,"bed")
	refuse(w,t,cell,"aru:1::",bed_msg,"act own_bed: only another player's bed")
	put_object(w,t,"chest")
	put_object(w,t,"bench")
	refuse(w,t,cell,"aru:1::",bed_msg,"act own_bed: own chest and bench, no bed")
	put_object(w,t,"bed")
	var r:=do_goal(w,t,cell,"aru:1::")
	expect(bool(r.get("ok",false)) and msg(r)==goal_msg("aru",1),"act own_bed: own bed -> accepted (got '%s')"%msg(r))
	expect(pl(w,t).get(Goals.RECORD_KEY)=={"aru":{"1":""}} and int(pl(w,t).inventory.get("wood",-1))==0,"act own_bed: record written, 10 wood paid")
	# The other player's bed counts for them.
	go(w,o,"home",cell)
	set_points(w,o,"aru",1)
	set_item(w,o,"wood",10)
	r=do_goal(w,o,cell,"aru:1::")
	expect(bool(r.get("ok",false)),"act own_bed: the other player's own bed counts for them (got '%s')"%msg(r))
	# glass_crafted (xinghe 3)
	t="goal-act-glass"
	cell=ready_player(w,t,"xinghe",3,"")
	var glass_msg:=need_msg(str(NEED_TEXT["glass_crafted"]))
	var p:Dictionary=pl(w,t)
	p.erase("greenhouse_glass_crafted")
	refuse(w,t,cell,"xinghe:3::",glass_msg,"act glass_crafted: missing")
	for bad:Variant in [false,1,"true"]:
		p["greenhouse_glass_crafted"]=bad
		refuse(w,t,cell,"xinghe:3::",glass_msg,"act glass_crafted: %s"%str(bad))
	p["greenhouse_glass_crafted"]=true
	r=do_goal(w,t,cell,"xinghe:3::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"xinghe":{"3":""}},"act glass_crafted: true -> accepted (got '%s')"%msg(r))
	# market_round (xiaoli 3)
	t="goal-act-market"
	cell=ready_player(w,t,"xiaoli",3,"")
	var market_msg:=need_msg(str(NEED_TEXT["market_round"]))
	p=pl(w,t)
	p.erase("market")
	refuse(w,t,cell,"xiaoli:3::",market_msg,"act market_round: no market")
	p["market"]=MarketStall.fresh()
	refuse(w,t,cell,"xiaoli:3::",market_msg,"act market_round: empty report")
	p["market"]="open"
	refuse(w,t,cell,"xiaoli:3::",market_msg,"act market_round: market not a dictionary")
	p["market"]=market_with_report()
	r=do_goal(w,t,cell,"xiaoli:3::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"xiaoli":{"3":""}},"act market_round: non-empty report -> accepted (got '%s')"%msg(r))
	# festival_done (lingpopo 4)
	t="goal-act-festival"
	cell=ready_player(w,t,"lingpopo",4,"")
	var festival_msg:=need_msg(str(NEED_TEXT["festival_done"]))
	w.state["festival"]=festival_at(0,false)
	refuse(w,t,cell,"lingpopo:4::",festival_msg,"act festival_done: round 0")
	w.state["festival"]=festival_at(1,true)
	refuse(w,t,cell,"lingpopo:4::",festival_msg,"act festival_done: round 1 active")
	w.state["festival"]=festival_at(1,false)
	r=do_goal(w,t,cell,"lingpopo:4::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"lingpopo":{"4":""}},"act festival_done: round 1 finished -> accepted (got '%s')"%msg(r))
	var t2:="goal-act-festival-two"
	cell=ready_player(w,t2,"lingpopo",4,"")
	w.state["festival"]=festival_at(2,true)
	r=do_goal(w,t2,cell,"lingpopo:4::")
	expect(bool(r.get("ok",false)) and pl(w,t2).get(Goals.RECORD_KEY)=={"lingpopo":{"4":""}},"act festival_done: round 2 active -> accepted (got '%s')"%msg(r))
	# known_three (luoluo 2)
	t="goal-act-known"
	cell=ready_player(w,t,"luoluo",2,"")
	var known_label:=str(NEED_TEXT["known_three"])
	refuse(w,t,cell,"luoluo:2::",need_msg(known_label+"（目前 0 位）"),"act known_three: only luoluo known")
	set_points(w,t,"aru",1)
	set_points(w,t,"milu",1)
	set_points(w,t,"achao",0)
	refuse(w,t,cell,"luoluo:2::",need_msg(known_label+"（目前 2 位）"),"act known_three: two others known")
	set_points(w,t,"bobo",1)
	r=do_goal(w,t,cell,"luoluo:2::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"luoluo":{"2":""}},"act known_three: three others -> accepted (got '%s')"%msg(r))
	# fair_weather (mianmian 4)
	t="goal-act-weather"
	cell=ready_player(w,t,"mianmian",4,"")
	var weather_msg:=need_msg(str(NEED_TEXT["fair_weather"]))
	move_weather(w,true)
	expect(Weather.rains(Weather.day_index(float(w.state.time)),"home"),"preset: today is rainy at home")
	refuse(w,t,cell,"mianmian:4::",weather_msg,"act fair_weather: rainy day")
	move_weather(w,false)
	expect(not Weather.rains(Weather.day_index(float(w.state.time)),"home"),"preset: today is not rainy at home")
	cell=cell_of(w,"mianmian")
	go(w,t,"home",cell)
	r=do_goal(w,t,cell,"mianmian:4::")
	expect(bool(r.get("ok",false)) and pl(w,t).get(Goals.RECORD_KEY)=={"mianmian":{"4":""}},"act fair_weather: non-rainy day -> accepted (got '%s')"%msg(r))

# ------------------------------ needs checked once, batch-2 save round trip --

func test_needs_once_and_save()->void:
	var path:=temp_path("needs")
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=true  # PRESET
	w.state["time"]=Weather.DAY_SECONDS+100.0  # PRESET: day 1 (a day-0 market report is then valid)
	move_weather(w,false)
	w.add_player(KIM,"金")
	var p:Dictionary=pl(w,KIM)
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	for pair:Array in [["aru",1],["xinghe",14],["xiaoli",24],["lingpopo",24],["luoluo",24],["mianmian",24],["bobo",24],["nuannuan",24]]:
		set_points(w,KIM,str(pair[0]),int(pair[1]))
	for pair:Array in [["wood",10],["glass",2],["copper_joint",2],["plank",2],["feed",1]]:
		set_item(w,KIM,str(pair[0]),int(pair[1]))
	for need:String in NEED_TEXT:
		set_need(w,KIM,need,true)
		expect(Goals.need_met(need,w.state,KIM),"save preset: %s holds"%need)
	var specs:Array=[["aru",1,""],["mianmian",4,""],["mianmian",1,""],["xinghe",3,""],["xiaoli",3,""],["xiaoli",4,"chestnut"],
		["lingpopo",4,""],["luoluo",2,""],["luoluo",4,"stay"],["bobo",4,"rest"],["nuannuan",4,"porch"]]
	var want:Dictionary={}
	for spec:Array in specs:
		var resident:=str(spec[0])
		var stage:=int(spec[1])
		var option:=str(spec[2])
		var cell:=cell_of(w,resident)
		go(w,KIM,region_of(w,resident),cell)
		var r:=do_goal(w,KIM,cell,extra_of(resident,stage,option,""))
		expect(bool(r.get("ok",false)),"save: %s %d '%s' done (got '%s')"%[resident,stage,option,msg(r)])
		var own:Dictionary=want.get(resident,{})
		own[str(stage)]=option
		want[resident]=own
	p=pl(w,KIM)
	p["region"]="home"
	p["x"]=home_x
	p["y"]=home_y
	expect(same(goals_of(w,KIM),want),"all eleven batch-2 goals recorded (%s)"%str(goals_of(w,KIM)))
	var held:Dictionary=p.inventory
	expect(int(held.get("wood",-1))==0 and int(held.get("glass",-1))==0 and int(held.get("copper_joint",-1))==0 and int(held.get("plank",-1))==0 and int(held.get("feed",-1))==0,"batch-2 costs paid exactly")
	# Batch 3 (granted through World.act above): aru 1, xiaoli 4 and luoluo 4 carry keepsakes.
	var want_kits:Dictionary={"keepsake_aru_kit":1,"keepsake_xiaoli_kit":1,"keepsake_luoluo_kit":1}
	var want_keepsakes:Dictionary={"keepsake_aru":true,"keepsake_xiaoli":true,"keepsake_luoluo":true}
	expect(kit_counts(p)==want_kits,"exactly the aru, xiaoli and luoluo kits granted (%s)"%str(kit_counts(p)))
	expect(same(p.get(Goals.KEEPSAKE_KEY),want_keepsakes),"bond_keepsakes holds exactly those three kinds (%s)"%str(p.get(Goals.KEEPSAKE_KEY)))
	# Undo every prerequisite: remove the bed, start a new festival round, rainy day, etc.
	clear_beds(w,KIM)
	p["greenhouse_glass_crafted"]=false
	p.erase("market")
	w.state["festival"]=festival_at(2,true)
	var bonds:Dictionary=p.bonds
	for other:String in KNOWN_OTHERS:bonds.erase(other)
	move_weather(w,true)
	for need:String in NEED_TEXT:
		# known_three cannot be undone here: the completed goals themselves require bonds
		# with seven residents other than 洛洛 (removing them would invalidate the save).
		if need in ["festival_done","known_three"]:continue
		expect(not Goals.need_met(need,w.state,KIM),"after undo: %s no longer holds"%need)
	expect(Goals.need_met("known_three",w.state,KIM),"after undo: known_three still holds through the bonds the done goals need")
	# A new active round keeps festival_done true (round 1 was finished before).
	expect(Goals.need_met("festival_done",w.state,KIM),"after undo: festival round 2 active still counts as done")
	for spec:Array in specs:
		var row:=view_at(w,KIM,str(spec[0]),int(spec[1]))
		expect(row==with_keepsake({"state":"done","choice":str(spec[2])},str(spec[0]),int(spec[1]),true),"after undo: %s %d still done, no needs key (%s)"%[str(spec[0]),int(spec[1]),str(row)])
	expect(Goals.valid(goals_of(w,KIM),pl(w,KIM)),"after undo: Goals.valid still accepts the record")
	for spec:Array in specs:
		if not Goals.goal(str(spec[0]),int(spec[1])).has("needs"):continue
		var cell:=cell_of(w,str(spec[0]))
		go(w,KIM,region_of(w,str(spec[0])),cell)
		refuse(w,KIM,cell,extra_of(str(spec[0]),int(spec[1]),"",""),done_msg(Goals.goal(str(spec[0]),int(spec[1]))),"after undo: repeat %s %d -> already done"%[str(spec[0]),int(spec[1])])
	p=pl(w,KIM)
	p["region"]="home"
	p["x"]=home_x
	p["y"]=home_y
	var live_view:Dictionary=Goals.view(pl(w,KIM),w.state,KIM)
	expect(w.save(),"needs world saves")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,"needs save parses"):return
	expect(validates(parsed),"save with batch-2 goals done and prerequisites undone passes SaveSchema")
	var restored:=World.new()
	if not expect(restored.load_world(path),"needs save reloads"):return
	expect(same(goals_of(restored,KIM),want),"batch-2 bond_goals survive reload (%s)"%str(goals_of(restored,KIM)))
	expect(same(pl(restored,KIM).get(Goals.KEEPSAKE_KEY),want_keepsakes) and kit_counts(pl(restored,KIM))==want_kits,"bond_keepsakes and kits survive reload")
	var restored_state:Dictionary=restored.state
	expect(same(Goals.view(pl(restored,KIM),restored_state,KIM),live_view),"reloaded view with state equals the live view")
	var aru:=cell_of(restored,"aru")
	stand(restored,KIM,aru)
	set_item(restored,KIM,"wood",10)
	refuse(restored,KIM,aru,"aru:1::",done_msg(Goals.goal("aru",1)),"after reload: aru 1 still done")

# ----------------------------------------- two players, replay, talk and gift --

func test_players_and_replay()->void:
	var w:=World.new()
	var a:="goal-pair-alpha"
	var b:="goal-pair-beta"
	w.add_player(a,"甲")
	w.add_player(b,"乙")
	var milu:=cell_of(w,"milu")
	for t:String in [a,b]:
		stand(w,t,milu)
		set_points(w,t,"milu",1)
		set_item(w,t,"soup",3)
		set_item(w,t,"radish",2)
	var b_before:=var_to_bytes(canon(pl(w,b)))
	var r:=do_goal(w,a,milu,"milu:1::","goal-replay-milu-1")
	expect(bool(r.get("ok",false)) and int(pl(w,a).inventory.soup)==2,"A completes milu 1 and pays one soup (got '%s')"%msg(r))
	expect(var_to_bytes(canon(pl(w,b)))==b_before,"A's goal leaves B's whole record byte-identical")
	expect(str(view_row(w,b,"milu",1).get("state",""))=="open","B's milu 1 is still open")
	var state_before:=var_to_bytes(canon(w.state))
	var replay:=do_goal(w,a,milu,"milu:1::","goal-replay-milu-1")
	expect(replay==r,"replayed request id returns the stored receipt")
	expect(var_to_bytes(canon(w.state))==state_before and int(pl(w,a).inventory.soup)==2,"replay applies nothing (soup charged once, world byte-identical)")
	refuse(w,a,milu,"milu:1::",done_msg(Goals.goal("milu",1)),"A repeats milu 1 with a new request id")
	var a_before:=var_to_bytes(canon(pl(w,a)))
	r=do_goal(w,b,milu,"milu:1::")
	expect(bool(r.get("ok",false)) and pl(w,b).get(Goals.RECORD_KEY)=={"milu":{"1":""}} and int(pl(w,b).inventory.soup)==2,"B completes the same goal independently (got '%s')"%msg(r))
	expect(var_to_bytes(canon(pl(w,a)))==a_before,"B's goal leaves A's whole record byte-identical")
	# Talk and gift still work afterwards; bond progress unaffected by the goal.
	var today:=Bond.day(float(w.state.time))
	r=act(w,a,"resident_gift",milu,"milu:radish")
	expect(bool(r.get("ok",false)) and pl(w,a).bonds=={"milu":rec(2,-1,today)},"A's common gift after the goal adds its point (got '%s')"%msg(r))
	r=act(w,a,"resident_talk",milu,"milu")
	expect(bool(r.get("ok",false)) and pl(w,a).bonds=={"milu":rec(3,today,today)},"A's talk after the goal adds its point")
	expect(pl(w,a).get(Goals.RECORD_KEY)=={"milu":{"1":""}},"talk and gift leave bond_goals unchanged")
	set_item(w,a,"soup",4)
	refuse(w,a,milu,"milu:3:soup:",stage_msg("milu",3),"A's milu 3 still needs the 信任 stage (a goal adds no points)")

# ------------------------------------------- batch 3: keepsake catalog --

func test_keepsake_catalog()->void:
	expect(Goals.KEEPSAKE_KEY=="bond_keepsakes" and Goals.CLAIM_ACTION=="resident_keepsake" and Goals.KIT_SUFFIX=="_kit" and Goals.MAX_ITEM==1000000000,
		"KEEPSAKE_KEY bond_keepsakes, CLAIM_ACTION resident_keepsake, KIT_SUFFIX _kit, MAX_ITEM 1e9")
	expect(Goals.ACTIONS==[Goals.ACTION,Goals.CLAIM_ACTION] and World.RESIDENT_GOALS.CLAIM_ACTION==Goals.CLAIM_ACTION,"ACTIONS is [resident_goal, resident_keepsake]; World wires the same claim action")
	expect(Goals.CLAIM_ACTION not in Bond.ACTIONS,"resident_keepsake is not a bond talk/gift action")
	var kinds:Array=Goals.KEEPSAKES.keys()
	kinds.sort()
	var ordered:Array=Goals.KEEPSAKE_ORDER.duplicate()
	ordered.sort()
	var want_kinds:Array=KEEPSAKE_GOALS.values()
	want_kinds.sort()
	expect(want_kinds.size()==12 and kinds==want_kinds and ordered==want_kinds and Goals.KEEPSAKE_ORDER.size()==12,
		"KEEPSAKES and KEEPSAKE_ORDER hold exactly the twelve batch-3 kinds once each (%s)"%str(Goals.KEEPSAKE_ORDER))
	var want_items:Array=[]
	for kind:String in Goals.KEEPSAKE_ORDER:want_items.append(kind+"_kit")
	expect(Goals.keepsake_items()==want_items,"keepsake_items() lists kind+_kit in KEEPSAKE_ORDER order (%s)"%str(Goals.keepsake_items()))
	var trade:Dictionary=World.trade_items()
	var residents_seen:Array=[]
	for kind:String in Goals.KEEPSAKE_ORDER:
		var entry:Dictionary=Goals.KEEPSAKES[kind]
		var resident:=str(entry.get("resident",""))
		var stage:=int(entry.get("stage",0))
		var tag:="%s %d"%[resident,stage]
		var item:=kind+"_kit"
		var fields:Array=entry.keys()
		fields.sort()
		expect(fields==["blurb","name","resident","stage"],"%s: fields are resident, stage, name, blurb (%s)"%[kind,str(fields)])
		expect(entry.get("stage") is int and str(KEEPSAKE_GOALS.get(tag,""))==kind,"%s: points at %s, one of the twelve keepsake goals"%[kind,tag])
		expect(Goals.has_goal(resident,stage),"%s: its goal %s exists"%[kind,tag])
		expect(kind=="keepsake_"+resident and resident not in residents_seen,"%s: one keepsake per resident, named after the resident"%kind)
		residents_seen.append(resident)
		expect(str(entry.get("name",""))==str(Goals.goal(resident,stage).get("keepsake","?")),"%s: name equals the goal's keepsake text"%kind)
		expect(entry.get("blurb") is String and not str(entry.get("blurb")).strip_edges().is_empty(),"%s: non-empty blurb"%kind)
		expect(Goals.keepsake_kind(resident,stage)==kind,"%s: keepsake_kind(%s) finds it"%[kind,tag])
		expect(Goals.keepsake_item(kind)==item and Goals.is_keepsake_item(item) and Goals.is_keepsake_kind(kind),"%s: keepsake_item / is_keepsake_item / is_keepsake_kind agree"%kind)
		expect(not Goals.is_keepsake_item(kind) and not Goals.is_keepsake_kind(item) and Goals.keepsake_item(item).is_empty(),"%s: kind and item ids are not interchangeable"%kind)
		var recipe:Variant=World.BUILD.get(kind)
		expect(recipe is Dictionary and recipe=={"name":str(entry.get("name","")),item:1},"%s: World.BUILD recipe is exactly {name, %s:1} (%s)"%[kind,item,str(recipe)])
		expect(str(World.NAMES.get(item,""))==str(entry.get("name","")),"%s: World.NAMES[%s] is the keepsake name"%[kind,item])
		expect(not trade.has(item),"%s: trade_items() excludes the kit"%kind)
		expect(not World.OTHER_SALES.has(item) and not World.CROPS.has(item) and not World.OTHER_SALES.has(kind) and not World.CROPS.has(kind),"%s: no sale price (OTHER_SALES / CROPS)"%kind)
	expect(trade.has("wood") and trade.has("plank"),"control: trade_items() still lists ordinary materials")
	var with_kind:Array=[]
	for tag:String in ALL_GOALS:
		var parts:=tag.split(" ")
		var found:=Goals.keepsake_kind(str(parts[0]),int(parts[1]))
		expect(found==str(KEEPSAKE_GOALS.get(tag,"")),"%s: keepsake_kind is '%s' (got '%s')"%[tag,str(KEEPSAKE_GOALS.get(tag,"")),found])
		if not found.is_empty():with_kind.append(tag)
	expect(with_kind.size()==12 and ALL_GOALS.size()-with_kind.size()==16,"12 goals carry a keepsake, 16 do not (%s)"%str(with_kind))
	for bad:Array in [["aru",2],["tom",1],["",1],["aru",0],["milu",1],["xiaoli",3]]:
		expect(Goals.keepsake_kind(str(bad[0]),int(bad[1])).is_empty(),"no keepsake for %s %d"%[str(bad[0]),int(bad[1])])
	for bad:String in ["","keepsake_tom","keepsake_aru_kit","trio_keepsake","Keepsake_aru"]:
		expect(Goals.keepsake_item(bad).is_empty() and not Goals.is_keepsake_kind(bad),"'%s' is not a keepsake kind"%bad)
	for bad:String in ["","_kit","keepsake_tom_kit","keepsake_aru","keepsake_aru_kit_kit","trio_keepsake_kit","keepsake_aru_Kit"]:
		expect(not Goals.is_keepsake_item(bad),"'%s' is not a keepsake item"%bad)
	# valid_keepsakes() directly (FIXTURE persons written here).
	var done_aru:Dictionary={"bonds":{"aru":rec(1,-1,-1)},"bond_goals":{"aru":{"1":""}}}
	expect(Goals.valid_keepsakes({"keepsake_aru":true},done_aru),"valid_keepsakes accepts a done goal's kind")
	var bad_records:Array=[{},[],"keepsake_aru",null,true,{"keepsake_aru":false},{"keepsake_aru":1},{"keepsake_aru":"true"},
		{"keepsake_milu":true},{"keepsake_tom":true},{"keepsake_aru_kit":true},{"keepsake_aru":true,"keepsake_milu":true}]
	for bad:Variant in bad_records:
		expect(not Goals.valid_keepsakes(bad,done_aru),"valid_keepsakes rejects %s"%str(bad))
	expect(not Goals.valid_keepsakes({"keepsake_aru":true},{"bonds":{"aru":rec(1,-1,-1)}}),"valid_keepsakes rejects a kind when bond_goals is absent")

# ------------------------------------- batch 3: claim through World.act --

func test_keepsake_claim()->void:
	var w:=World.new()
	w.state["picnic"]=true  # PRESET
	w.state["dock_stage"]=1  # PRESET
	var t:="goal-claim-old"
	w.add_player(t,"甲")
	var aru:=cell_of(w,"aru")
	var milu:=cell_of(w,"milu")
	var aru_region:=region_of(w,"aru")
	var milu_region:=region_of(w,"milu")
	set_points(w,t,"aru",6)
	set_points(w,t,"milu",1)
	set_item(w,t,"radish",2)
	# FIXTURE (written directly): aru 1 and milu 1 completed before batch 3 —
	# bond_goals only, no bond_keepsakes and no kit.
	var p:Dictionary=pl(w,t)
	p[Goals.RECORD_KEY]={"aru":{"1":""},"milu":{"1":""}}
	expect(Goals.valid(goals_of(w,t),pl(w,t)) and not pl(w,t).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,t)).is_empty(),"claim fixture: valid old completion without keepsake record or kit")
	var row:=view_at(w,t,"aru",1)
	expect(row==with_keepsake({"state":"done","choice":""},"aru",1,false),"old completion: aru 1 done, keepsake unclaimed (%s)"%str(row))
	# Refusals (all through World.act); each leaves the whole world byte-identical.
	go(w,t,milu_region,milu)
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"aru:1",MSG_PLACE,"claim: aru's keepsake aimed at milu's cell")
	go(w,t,aru_region,aru)
	refuse_act(w,t,Goals.CLAIM_ACTION,aru+Vector2i.RIGHT,"aru:1",MSG_PLACE,"claim: aimed at the tile beside aru")
	p=pl(w,t)
	p["x"]=float(aru.x)+0.5
	p["y"]=float(aru.y)+5.5
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1",MSG_FAR,"claim: five tiles away from aru")
	stand(w,t,aru)
	p["region"]="jinguashi"
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1","","claim: jinguashi player aimed at aru's home cell")
	p["region"]=aru_region
	for unknown:String in ["tom:1","Aru:1",":1","","milu:3"]:
		refuse_act(w,t,Goals.CLAIM_ACTION,aru,unknown,MSG_PLACE,"claim: wrong resident '%s'"%unknown)
	for malformed:String in ["aru","aru:","aru:x","aru:1:","aru:1::","aru:1.0","aru:one"]:
		refuse_act(w,t,Goals.CLAIM_ACTION,aru,malformed,MSG_REOPEN,"claim: malformed extra '%s'"%malformed)
	for none:String in ["aru:2","aru:3","aru:0","aru:-1","aru:99"]:
		refuse_act(w,t,Goals.CLAIM_ACTION,aru,none,MSG_NO_KEEPSAKE,"claim: no keepsake for '%s'"%none)
	go(w,t,milu_region,milu)
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"milu:1",MSG_NO_KEEPSAKE,"claim: milu 1 is done but has no keepsake")
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"milu:3",not_done_claim_msg("milu",3),"claim: milu 3 not done yet")
	expect(not pl(w,t).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(w,t)).is_empty(),"no claim refusal wrote bond_keepsakes or a kit")
	# Success (through World.act).
	go(w,t,aru_region,aru)
	var inv_before:Dictionary=pl(w,t).inventory.duplicate(true)
	var goals_before:Variant=goals_of(w,t)
	var r:=act(w,t,Goals.CLAIM_ACTION,aru,"aru:1")
	expect(bool(r.get("ok",false)) and msg(r)==claim_msg("aru",1),"claim: old aru 1 completion claims its keepsake (got '%s')"%msg(r))
	var expected:Dictionary=inv_before.duplicate(true)
	expected["keepsake_aru_kit"]=1
	expect(pl(w,t).inventory==expected,"claim: inventory gains exactly one keepsake_aru_kit (got %s)"%str(pl(w,t).inventory))
	expect(pl(w,t).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true},"claim: bond_keepsakes is exactly {keepsake_aru:true}")
	expect(same(goals_of(w,t),goals_before),"claim leaves bond_goals unchanged")
	row=view_at(w,t,"aru",1)
	expect(row==with_keepsake({"state":"done","choice":""},"aru",1,true),"claim: view shows the aru keepsake claimed (%s)"%str(row))
	expect(Goals.valid_keepsakes(pl(w,t).get(Goals.KEEPSAKE_KEY),pl(w,t)),"claim: the record passes valid_keepsakes")
	# Second claim refused, and still refused after the kit is gone (no re-issue).
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1",claimed_msg("aru",1),"claim: second claim")
	expect(int(pl(w,t).inventory.get("keepsake_aru_kit",0))==1,"claim: second claim leaves exactly one kit")
	set_item(w,t,"keepsake_aru_kit",0)  # PRESET: the kit is gone
	refuse_act(w,t,Goals.CLAIM_ACTION,aru,"aru:1",claimed_msg("aru",1),"claim: kit lost, not re-issued")
	# A batch-3 completion (through World.act) grants it; a claim afterwards is refused.
	set_points(w,t,"milu",14)
	set_item(w,t,"soup",2)
	go(w,t,milu_region,milu)
	r=do_goal(w,t,milu,"milu:3:soup:")
	expect(bool(r.get("ok",false)) and msg(r)==goal_msg("milu",3),"claim world: milu 3 completed through resident_goal (got '%s')"%msg(r))
	expect(int(pl(w,t).inventory.get("keepsake_milu_kit",0))==1 and pl(w,t).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true,"keepsake_milu":true},"completion adds the milu kit and kind to the existing record")
	refuse_act(w,t,Goals.CLAIM_ACTION,milu,"milu:3",claimed_msg("milu",3),"claim after a batch-3 completion")
	expect(Goals.valid_keepsakes(pl(w,t).get(Goals.KEEPSAKE_KEY),pl(w,t)),"claim world: record with both kinds passes valid_keepsakes")
	# bond_goals not a dictionary (FIXTURE: tampered record).
	var bt:="goal-claim-bad-goals"
	w.add_player(bt,"乙")
	set_points(w,bt,"aru",1)
	var bp:Dictionary=pl(w,bt)
	bp[Goals.RECORD_KEY]="aru"
	go(w,bt,aru_region,aru)
	refuse_act(w,bt,Goals.CLAIM_ACTION,aru,"aru:1",MSG_RECORD_BAD,"claim: bond_goals not a dictionary")
	# bond_keepsakes not a dictionary blocks both claim and apply (FIXTURES: old aru 1
	# completion plus a tampered bond_keepsakes; soup preset for milu 3).
	var nt:="goal-claim-bad-keepsakes"
	w.add_player(nt,"丙")
	set_points(w,nt,"aru",1)
	set_points(w,nt,"milu",14)
	var odd_values:Array=["claimed",[],5,true,null]
	for odd:Variant in odd_values:
		var np:Dictionary=pl(w,nt)
		np[Goals.RECORD_KEY]={"aru":{"1":""}}
		np[Goals.KEEPSAKE_KEY]=odd
		set_item(w,nt,"soup",2)
		go(w,nt,aru_region,aru)
		refuse_act(w,nt,Goals.CLAIM_ACTION,aru,"aru:1",MSG_RECORD_BAD,"claim: bond_keepsakes is %s"%str(odd))
		go(w,nt,milu_region,milu)
		refuse(w,nt,milu,"milu:3:soup:",MSG_RECORD_BAD,"apply milu 3: bond_keepsakes is %s"%str(odd))
		expect(int(pl(w,nt).inventory.get("soup",0))==2 and kit_counts(pl(w,nt)).is_empty() and same(goals_of(w,nt),{"aru":{"1":""}}),"bond_keepsakes %s: nothing consumed, no kit, bond_goals unchanged"%str(odd))
	# Kit count at MAX_ITEM blocks claim and apply; nothing consumed (FIXTURE: old
	# aru 1 completion; PRESET kit counts).
	var ft:="goal-claim-full"
	w.add_player(ft,"丁")
	set_points(w,ft,"aru",1)
	set_points(w,ft,"milu",14)
	var fp:Dictionary=pl(w,ft)
	fp[Goals.RECORD_KEY]={"aru":{"1":""}}
	set_item(w,ft,"keepsake_aru_kit",Goals.MAX_ITEM)
	go(w,ft,aru_region,aru)
	refuse_act(w,ft,Goals.CLAIM_ACTION,aru,"aru:1",cap_msg("aru",1),"claim: kit already at MAX_ITEM")
	expect(not pl(w,ft).has(Goals.KEEPSAKE_KEY),"capped claim writes no bond_keepsakes")
	set_item(w,ft,"keepsake_aru_kit",Goals.MAX_ITEM-1)
	r=act(w,ft,Goals.CLAIM_ACTION,aru,"aru:1")
	expect(bool(r.get("ok",false)) and int(pl(w,ft).inventory.get("keepsake_aru_kit",0))==Goals.MAX_ITEM and pl(w,ft).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true},"claim at MAX_ITEM-1 succeeds and reaches the cap (got '%s')"%msg(r))
	set_item(w,ft,"soup",2)
	set_item(w,ft,"keepsake_milu_kit",Goals.MAX_ITEM)
	go(w,ft,milu_region,milu)
	refuse(w,ft,milu,"milu:3:soup:",cap_msg("milu",3),"apply milu 3: kit already at MAX_ITEM")
	expect(int(pl(w,ft).inventory.get("soup",0))==2 and same(goals_of(w,ft),{"aru":{"1":""}}) and pl(w,ft).get(Goals.KEEPSAKE_KEY)=={"keepsake_aru":true},"capped apply consumes nothing and writes no record")
	set_item(w,ft,"keepsake_milu_kit",Goals.MAX_ITEM-1)
	r=do_goal(w,ft,milu,"milu:3:soup:")
	expect(bool(r.get("ok",false)) and int(pl(w,ft).inventory.get("soup",-1))==0 and int(pl(w,ft).inventory.get("keepsake_milu_kit",0))==Goals.MAX_ITEM,"apply at MAX_ITEM-1 succeeds and reaches the cap (got '%s')"%msg(r))
	# Residents not yet present: the claim uses the same presence gate (FIXTURE: old achao 1 completion).
	var g:=World.new()
	var gt:="goal-claim-gate"
	g.add_player(gt,"戊")
	set_points(g,gt,"achao",1)
	var gp:Dictionary=pl(g,gt)
	gp[Goals.RECORD_KEY]={"achao":{"1":""}}
	var achao:=cell_of(g,"achao")
	go(g,gt,region_of(g,"achao"),achao)
	refuse_act(g,gt,Goals.CLAIM_ACTION,achao,"achao:1",Bond.DOCK_LOCKED,"claim: achao not present before the dock repair")
	g.state["dock_stage"]=1  # PRESET
	achao=cell_of(g,"achao")
	go(g,gt,region_of(g,"achao"),achao)
	r=act(g,gt,Goals.CLAIM_ACTION,achao,"achao:1")
	expect(bool(r.get("ok",false)) and kit_counts(pl(g,gt))=={"keepsake_achao_kit":1},"claim: once achao is present the old completion claims its kit (got '%s')"%msg(r))

# ------------------------------------------------ save, reload and schema --

func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	var legacy_path:=temp_path("legacy")
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=true  # PRESET
	w.add_player(SAM,"山")
	var p:Dictionary=pl(w,SAM)
	var home_x:float=float(p.x)
	var home_y:float=float(p.y)
	set_points(w,SAM,"milu",14)
	set_points(w,SAM,"bobo",6)
	set_points(w,SAM,"xinghe",6)
	set_points(w,SAM,"aru",6)
	for pair:Array in [["soup",1],["carrot_soup",2],["copper_joint",2],["plank",2],["orange_blossom",2],["chime_herb",2],["radish",1]]:
		set_item(w,SAM,str(pair[0]),int(pair[1]))
	var milu:=cell_of(w,"milu")
	go(w,SAM,"home",milu)
	expect(bool(do_goal(w,SAM,milu,"milu:1::").get("ok",false)),"save: milu 1 done")
	expect(bool(do_goal(w,SAM,milu,"milu:3:carrot_soup:").get("ok",false)),"save: milu 3 carrot_soup done")
	go(w,SAM,region_of(w,"bobo"),cell_of(w,"bobo"))
	expect(bool(do_goal(w,SAM,cell_of(w,"bobo"),"bobo:2:siding:").get("ok",false)),"save: bobo 2 siding done in jinguashi")
	go(w,SAM,region_of(w,"xinghe"),cell_of(w,"xinghe"))
	expect(bool(do_goal(w,SAM,cell_of(w,"xinghe"),"xinghe:2:orange_chime:").get("ok",false)),"save: xinghe 2 orange_chime done in lanyang")
	p=pl(w,SAM)
	p["region"]="home"
	p["x"]=home_x
	p["y"]=home_y
	var live:Variant=goals_of(w,SAM)
	var want_live:Dictionary={"milu":{"1":"","3":"carrot_soup"},"bobo":{"2":"siding"},"xinghe":{"2":"orange_chime"}}
	expect(live is Dictionary and same(live,want_live),"live bond_goals before saving (%s)"%str(live))
	# Batch 3 (granted through World.act above): milu 3 and xinghe 2 carry keepsakes, milu 1 and bobo 2 do not.
	var want_keepsakes:Dictionary={"keepsake_milu":true,"keepsake_xinghe":true}
	var want_kits:Dictionary={"keepsake_milu_kit":1,"keepsake_xinghe_kit":1}
	expect(same(pl(w,SAM).get(Goals.KEEPSAKE_KEY),want_keepsakes),"live bond_keepsakes before saving (%s)"%str(pl(w,SAM).get(Goals.KEEPSAKE_KEY)))
	expect(kit_counts(pl(w,SAM))==want_kits,"live kits before saving (%s)"%str(kit_counts(pl(w,SAM))))
	var live_bonds:Dictionary=(pl(w,SAM).bonds as Dictionary).duplicate(true)
	expect(w.save(),"world saves")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed is Dictionary,"save parses"):return
	var base:Dictionary=parsed
	expect(validates(base),"control: the saved world passes SaveSchema (bond_keepsakes after grants)")
	var restored:=World.new()
	if not expect(restored.load_world(path),"fresh world reloads the save"):return
	var loaded:Variant=goals_of(restored,SAM)
	expect(loaded is Dictionary and var_to_bytes(canon(loaded))==var_to_bytes(canon(live)),"bond_goals survive reload byte-identical after canonicalising (%s)"%str(loaded))
	expect(same(pl(restored,SAM).get(Goals.KEEPSAKE_KEY),want_keepsakes),"bond_keepsakes survive reload (%s)"%str(pl(restored,SAM).get(Goals.KEEPSAKE_KEY)))
	expect(Goals.keepsake_claimed(pl(restored,SAM),"keepsake_milu") and Goals.keepsake_claimed(pl(restored,SAM),"keepsake_xinghe"),"reloaded values are still bool true")
	expect(kit_counts(pl(restored,SAM))==want_kits,"kits survive reload (%s)"%str(kit_counts(pl(restored,SAM))))
	expect(var_to_bytes(canon(pl(restored,SAM).bonds))==var_to_bytes(canon(live_bonds)),"bonds survive reload")
	var milu_loaded:Dictionary=pl(restored,SAM).bonds.milu
	expect(typeof(milu_loaded.points)==TYPE_INT,"reloaded bond points are ints again")
	expect(same(Goals.view(pl(restored,SAM)),Goals.view(pl(w,SAM))),"reloaded goals view equals the live view")
	stand(restored,SAM,milu)
	set_item(restored,SAM,"soup",2)
	refuse(restored,SAM,milu,"milu:1::",done_msg(Goals.goal("milu",1)),"milu 1 still done after reload")
	refuse_act(restored,SAM,Goals.CLAIM_ACTION,milu,"milu:3",claimed_msg("milu",3),"after reload: milu 3 keepsake still claimed")
	var aru:=cell_of(restored,"aru")
	stand(restored,SAM,aru)
	set_item(restored,SAM,"plank",4)
	var r:=do_goal(restored,SAM,aru,"aru:2::201")
	expect(bool(r.get("ok",false)),"a new goal after reload succeeds (got '%s')"%msg(r))
	expect(restored.save(),"restored world saves again")
	var again:=World.new()
	expect(again.load_world(path) and same(goals_of(again,SAM),{"milu":{"1":"","3":"carrot_soup"},"bobo":{"2":"siding"},"xinghe":{"2":"orange_chime"},"aru":{"2":""}}),"second reload keeps the old and the new record")
	expect(same(pl(again,SAM).get(Goals.KEEPSAKE_KEY),want_keepsakes) and kit_counts(pl(again,SAM))==want_kits,"second reload keeps bond_keepsakes and kits (aru 2 has no keepsake)")
	# FIXTURE: legacy save without bond_goals (it predates batch 3 too: no bond_keepsakes, no kits).
	var old:Dictionary=base.duplicate(true)
	var old_sam:Dictionary=old.players[SAM]
	old_sam.erase(Goals.RECORD_KEY)
	old_sam.erase(Goals.KEEPSAKE_KEY)
	var old_inv:Dictionary=old_sam["inventory"]
	for item:String in Goals.keepsake_items():old_inv.erase(item)
	expect(validates(old),"legacy save without bond_goals passes SaveSchema")
	expect(write_fixture(legacy_path,old),"write legacy fixture")
	var legacy:=World.new()
	if not expect(legacy.load_world(legacy_path),"legacy save loads"):return
	expect(not pl(legacy,SAM).has(Goals.RECORD_KEY),"loading does not invent bond_goals")
	expect(not pl(legacy,SAM).has(Goals.KEEPSAKE_KEY),"loading does not invent bond_keepsakes")
	expect(str(view_row(legacy,SAM,"milu",1).get("state",""))=="open" and str(view_row(legacy,SAM,"milu",3).get("state",""))=="open","legacy view: milu 1 and 3 open")
	stand(legacy,SAM,milu)
	set_item(legacy,SAM,"soup",1)
	r=do_goal(legacy,SAM,milu,"milu:1::")
	expect(bool(r.get("ok",false)) and pl(legacy,SAM).get(Goals.RECORD_KEY)=={"milu":{"1":""}},"legacy player completes milu 1 (got '%s')"%msg(r))
	expect(not pl(legacy,SAM).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(legacy,SAM)).is_empty(),"legacy milu 1 (no keepsake) creates no bond_keepsakes and no kit")
	# FIXTURE: a batch-2 save — milu 3 and xinghe 2 done, but no bond_keepsakes field and no kits.
	var batch2:Dictionary=base.duplicate(true)
	var b2_sam:Dictionary=batch2.players[SAM]
	b2_sam.erase(Goals.KEEPSAKE_KEY)
	var b2_inv:Dictionary=b2_sam["inventory"]
	for item:String in Goals.keepsake_items():b2_inv.erase(item)
	expect(validates(batch2),"old (batch-2) save: bond_keepsakes absent while keepsake goals are done passes SaveSchema")
	var b2_path:=temp_path("batch2")
	expect(write_fixture(b2_path,batch2),"write batch-2 fixture")
	var b2:=World.new()
	if not expect(b2.load_world(b2_path),"batch-2 save loads"):return
	b2.save_path=b2_path
	expect(not pl(b2,SAM).has(Goals.KEEPSAKE_KEY) and kit_counts(pl(b2,SAM)).is_empty(),"batch-2 load invents neither bond_keepsakes nor kits")
	var b2_row:=view_at(b2,SAM,"milu",3)
	expect(b2_row==with_keepsake({"state":"done","choice":"carrot_soup"},"milu",3,false),"batch-2 view: milu 3 done, keepsake unclaimed (%s)"%str(b2_row))
	# Claim through World.act at milu.
	go(b2,SAM,region_of(b2,"milu"),cell_of(b2,"milu"))
	r=act(b2,SAM,Goals.CLAIM_ACTION,cell_of(b2,"milu"),"milu:3")
	expect(bool(r.get("ok",false)) and msg(r)==claim_msg("milu",3),"batch-2 player claims the milu 3 keepsake (got '%s')"%msg(r))
	expect(kit_counts(pl(b2,SAM))=={"keepsake_milu_kit":1} and pl(b2,SAM).get(Goals.KEEPSAKE_KEY)=={"keepsake_milu":true},"claim grants one milu kit and marks only milu claimed")
	expect(same(goals_of(b2,SAM),want_live),"claim leaves bond_goals unchanged")
	b2_row=view_at(b2,SAM,"milu",3)
	expect(b2_row==with_keepsake({"state":"done","choice":"carrot_soup"},"milu",3,true),"batch-2 view after the claim: milu 3 claimed (%s)"%str(b2_row))
	b2_row=view_at(b2,SAM,"xinghe",2)
	expect(b2_row==with_keepsake({"state":"done","choice":"orange_chime"},"xinghe",2,false),"batch-2 view after the claim: xinghe 2 still unclaimed (%s)"%str(b2_row))
	refuse_act(b2,SAM,Goals.CLAIM_ACTION,cell_of(b2,"milu"),"milu:3",claimed_msg("milu",3),"batch-2 player claims milu 3 twice")
	var b2p:Dictionary=pl(b2,SAM)
	b2p["region"]="home"
	b2p["x"]=home_x
	b2p["y"]=home_y
	expect(b2.save(),"batch-2 world saves after the claim")
	var b2_saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(b2_path))
	expect(b2_saved is Dictionary and validates(b2_saved),"save after a claim passes SaveSchema")
	var b2_again:=World.new()
	expect(b2_again.load_world(b2_path) and pl(b2_again,SAM).get(Goals.KEEPSAKE_KEY)=={"keepsake_milu":true} and kit_counts(pl(b2_again,SAM))=={"keepsake_milu_kit":1},"claimed record and kit survive reload")
	# Tampering: control first, then each case differs only by its field.
	expect(write_fixture(fixture,base),"write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same(goals_of(control,SAM),want_live),"control: the untampered fixture loads with its bond_goals")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:Array=["unknown resident","resident id in the wrong case","stage key without a goal (milu 2)","stage key without a goal (milu 4)",
		"stage key 0","stage key 5","stage key 01","stage key ' 1'","stage key 1.0","value int","value null","value bool","value list",
		"invalid option id","option id in the wrong case","missing option on an option goal","option of another goal",
		"option on an option-less goal","empty per-resident dict","per-resident string","per-resident list","empty top dict",
		"top list","top string","top number","top null","stage recorded without a bond (xiaoli 2)","stage recorded without a bond (chacha 3)",
		"bond lowered below a recorded stage","bond removed under a recorded stage"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_fixture(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	# Batch 3: player.bond_keepsakes tampering (FIXTURES written directly from the saved base).
	var ks_labels:Array=["keepsakes empty dict","keepsakes list","keepsakes string","keepsakes number","keepsakes null","keepsakes bool",
		"unknown kind","kit id used as kind","kind in the wrong case","value false","value 1","value string 'true'","value null",
		"kind whose goal is not done (bobo 1)","kind whose goal is not done (aru 1)","goal record removed under a keepsake",
		"bond_goals erased under keepsakes"]
	for label:String in ks_labels:
		var bad:=tampered_keepsakes(base,label)
		expect(write_fixture(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects bond_keepsakes: "+label)
		expect(not probe.load_world(fixture),"load_world rejects bond_keepsakes: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	var subset:Dictionary=base.duplicate(true)
	var subset_sam:Dictionary=subset.players[SAM]
	subset_sam[Goals.KEEPSAKE_KEY]={"keepsake_xinghe":true}
	expect(validates(subset),"schema accepts bond_keepsakes naming only some of the done keepsake goals")
	expect(not FileAccess.file_exists(fixture+".bak"),"the tamper fixture never had a backup to fall back to")

func tampered_keepsakes(base:Dictionary,label:String)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	var person:Dictionary=s.players[SAM]
	var record:Dictionary=person[Goals.KEEPSAKE_KEY]
	var goals:Dictionary=person[Goals.RECORD_KEY]
	match label:
		"keepsakes empty dict":person[Goals.KEEPSAKE_KEY]={}
		"keepsakes list":person[Goals.KEEPSAKE_KEY]=["keepsake_milu"]
		"keepsakes string":person[Goals.KEEPSAKE_KEY]="keepsake_milu"
		"keepsakes number":person[Goals.KEEPSAKE_KEY]=1
		"keepsakes null":person[Goals.KEEPSAKE_KEY]=null
		"keepsakes bool":person[Goals.KEEPSAKE_KEY]=true
		"unknown kind":record["keepsake_tom"]=true
		"kit id used as kind":record["keepsake_milu_kit"]=true
		"kind in the wrong case":
			record.erase("keepsake_milu")
			record["Keepsake_milu"]=true
		"value false":record["keepsake_milu"]=false
		"value 1":record["keepsake_milu"]=1
		"value string 'true'":record["keepsake_milu"]="true"
		"value null":record["keepsake_milu"]=null
		"kind whose goal is not done (bobo 1)":record["keepsake_bobo"]=true
		"kind whose goal is not done (aru 1)":record["keepsake_aru"]=true
		"goal record removed under a keepsake":goals.erase("xinghe")
		"bond_goals erased under keepsakes":person.erase(Goals.RECORD_KEY)
		_:expect(false,"unknown keepsake tamper label "+label)
	return s

func tampered(base:Dictionary,label:String)->Dictionary:
	var s:Dictionary=base.duplicate(true)
	var person:Dictionary=s.players[SAM]
	var goals:Dictionary=person[Goals.RECORD_KEY]
	var milu:Dictionary=goals["milu"]
	var bobo:Dictionary=goals["bobo"]
	var bonds:Dictionary=person["bonds"]
	match label:
		"unknown resident":goals["tom"]={"1":""}
		"resident id in the wrong case":goals["Aru"]={"2":""}
		"stage key without a goal (milu 2)":milu["2"]=""
		"stage key without a goal (milu 4)":milu["4"]=""
		"stage key 0":milu["0"]=""
		"stage key 5":milu["5"]=""
		"stage key 01":
			milu.erase("1")
			milu["01"]=""
		"stage key ' 1'":
			milu.erase("1")
			milu[" 1"]=""
		"stage key 1.0":
			milu.erase("1")
			milu["1.0"]=""
		"value int":milu["1"]=1
		"value null":milu["1"]=null
		"value bool":milu["1"]=true
		"value list":milu["1"]=[]
		"invalid option id":milu["3"]="stew"
		"option id in the wrong case":milu["3"]="Carrot_soup"
		"missing option on an option goal":milu["3"]=""
		"option of another goal":bobo["2"]="soup"
		"option on an option-less goal":milu["1"]="soup"
		"empty per-resident dict":goals["aru"]={}
		"per-resident string":goals["aru"]="2"
		"per-resident list":goals["aru"]=["2"]
		"empty top dict":person[Goals.RECORD_KEY]={}
		"top list":person[Goals.RECORD_KEY]=[]
		"top string":person[Goals.RECORD_KEY]="milu"
		"top number":person[Goals.RECORD_KEY]=5
		"top null":person[Goals.RECORD_KEY]=null
		"stage recorded without a bond (xiaoli 2)":goals["xiaoli"]={"2":"tree"}
		"stage recorded without a bond (chacha 3)":goals["chacha"]={"3":""}
		"bond lowered below a recorded stage":
			var m:Dictionary=bonds["milu"]
			m["points"]=13
		"bond removed under a recorded stage":bonds.erase("milu")
		_:expect(false,"unknown tamper label "+label)
	return s

# ------------------------------------------------- in-process Session snapshot --

func test_session_snapshot()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	var w=session.world
	w.add_player(PRIVATE_A,"甲")
	w.add_player(PRIVATE_B,"乙")
	var milu:=cell_of(w,"milu")
	stand(w,PRIVATE_A,milu)
	stand(w,PRIVATE_B,milu)
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("resident_goals"),"recipient snapshot has resident_goals")
	var own:Dictionary=snap.get("resident_goals",{})
	var ws:Dictionary=w.state
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A),"fresh: resident_goals equals the recipient's own view (with world state and token)")
	var own_keys:Array=own.keys()
	own_keys.sort()
	expect(own_keys==TWELVE,"resident_goals lists all twelve residents")
	var locked:=true
	for resident in own:
		var stages:Dictionary=own[resident]
		for key in stages:
			if not stages[key] is Dictionary or not locked_row_ok(str(resident),str(key),stages[key]):locked=false
	expect(locked,"fresh: every goal is locked (needs rows exactly on goals with needs)")
	set_points(w,PRIVATE_A,"milu",1)
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	var m:Dictionary=own.get("milu",{})
	var milu3_locked:=with_keepsake({"state":"locked","choice":""},"milu",3,false)
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A) and m=={"1":{"state":"open","choice":""},"3":milu3_locked},"stage 1: milu 1 open, milu 3 locked (%s)"%str(m))
	set_item(w,PRIVATE_A,"soup",1)
	var r:=do_goal(w,PRIVATE_A,milu,"milu:1::")
	expect(bool(r.get("ok",false)),"Session world: alpha completes milu 1 (got '%s')"%msg(r))
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	m=own.get("milu",{})
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A) and m=={"1":{"state":"done","choice":""},"3":milu3_locked},"done: milu 1 done, milu 3 still locked (%s)"%str(m))
	expect(pl(w,PRIVATE_A).has(Goals.RECORD_KEY),"publishing does not strip the live record")
	var players:Dictionary=snap.get("players",{})
	var clean:=true
	for id in players:
		var person:Dictionary=players[id]
		if person.has(Goals.RECORD_KEY) or person.has("resident_goals"):clean=false
	var dump:=JSON.stringify(players)
	expect(clean and not players.is_empty(),"snapshot players entries carry no bond_goals / resident_goals")
	expect(not dump.contains(PRIVATE_A) and not dump.contains(PRIVATE_B),"snapshot players entries contain no token")
	expect(not JSON.stringify(snap).contains("\"bond_goals\""),"the whole snapshot never names bond_goals")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(not text.contains("\"bond_goals\"") and not text.contains("\"resident_goals\""),"public_state(%s) carries no goal records"%region)
		expect(not text.contains(PRIVATE_A) and not text.contains(PRIVATE_B),"public_state(%s) carries no token"%region)
	# Batch-2 needs rows: alpha reaches luoluo 2 and knows three other residents.
	set_points(w,PRIVATE_A,"luoluo",6)
	for other:String in KNOWN_OTHERS:set_points(w,PRIVATE_A,other,1)
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	var alpha_label:=str(NEED_TEXT["known_three"])+"（目前 3 位）"
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A),"needs: alpha's resident_goals equals alpha's view with state")
	var luoluo_rows:Dictionary=own.get("luoluo",{})
	expect(luoluo_rows.get("2",{})=={"state":"open","choice":"","needs":[{"id":"known_three","label":alpha_label,"met":true}]},"needs: alpha's luoluo 2 open with known_three met (%s)"%str(luoluo_rows.get("2")))
	var aru_rows:Dictionary=own.get("aru",{})
	expect(aru_rows.get("1",{})==with_keepsake({"state":"locked","choice":"","needs":[{"id":"own_bed","label":str(NEED_TEXT["own_bed"]),"met":false}]},"aru",1,false),"needs: alpha's aru 1 locked with own_bed unmet (%s)"%str(aru_rows.get("1")))
	players=snap.get("players",{})
	dump=JSON.stringify(players)
	# Need ids and labels occur only in resident_goals.gd, so their absence means
	# no needs row leaked ("needs" itself is also a salt-pan public key).
	expect(no_need_rows(dump) and not dump.contains(alpha_label),"needs: snapshot players entries carry no needs rows (ids or labels)")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(no_need_rows(text) and not text.contains(alpha_label) and not text.contains("\"bond_goals\""),"needs: public_state(%s) carries no needs rows, need labels or bond_goals"%region)
	# Beta's own snapshot.
	session.peers={1:PRIVATE_B,2:PRIVATE_A}
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	expect(own==Goals.view(pl(w,PRIVATE_B),ws,PRIVATE_B) and own.get("milu",{})=={"1":{"state":"locked","choice":""},"3":milu3_locked},"beta's resident_goals is beta's own (milu locked)")
	expect(own!=Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A),"beta's resident_goals is not alpha's")
	var beta_luoluo:Dictionary=own.get("luoluo",{})
	expect(beta_luoluo.get("2",{})=={"state":"locked","choice":"","needs":[{"id":"known_three","label":str(NEED_TEXT["known_three"])+"（目前 0 位）","met":false}]},"beta's luoluo 2 row shows beta's own count, not alpha's (%s)"%str(beta_luoluo.get("2")))
	expect(not JSON.stringify(snap).contains(alpha_label),"beta's whole snapshot never contains alpha's needs label")
	expect(not JSON.stringify(snap).contains("\"bond_goals\""),"beta's whole snapshot never names bond_goals")
	players=snap.get("players",{})
	dump=JSON.stringify(players)
	expect(not dump.contains("\"bond_goals\"") and not dump.contains(PRIVATE_A) and not dump.contains(PRIVATE_B),"beta's snapshot of alpha has no bond_goals and no token")
	expect(no_need_rows(dump),"beta's snapshot of alpha carries no needs rows")
	# Batch 3: alpha earns the milu 3 keepsake through World.act; bond_keepsakes stays private.
	set_points(w,PRIVATE_A,"milu",14)
	set_item(w,PRIVATE_A,"soup",2)
	stand(w,PRIVATE_A,milu)
	r=do_goal(w,PRIVATE_A,milu,"milu:3:soup:")
	expect(bool(r.get("ok",false)) and pl(w,PRIVATE_A).get(Goals.KEEPSAKE_KEY)=={"keepsake_milu":true},"Session world: alpha completes milu 3 and gets the keepsake (got '%s')"%msg(r))
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	m=own.get("milu",{})
	expect(own==Goals.view(pl(w,PRIVATE_A),ws,PRIVATE_A) and m.get("3",{})==with_keepsake({"state":"done","choice":"soup"},"milu",3,true),"keepsake: alpha's milu 3 done with the keepsake claimed (%s)"%str(m.get("3")))
	expect(not JSON.stringify(snap).contains("\"%s\""%Goals.KEEPSAKE_KEY),"alpha's whole snapshot never names bond_keepsakes")
	expect(pl(w,PRIVATE_A).has(Goals.KEEPSAKE_KEY),"publishing does not strip the live bond_keepsakes")
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		expect(not JSON.stringify(public).contains("\"%s\""%Goals.KEEPSAKE_KEY),"keepsake: public_state(%s) carries no bond_keepsakes"%region)
	session.peers={1:PRIVATE_B,2:PRIVATE_A}
	session._send_snapshot(1)
	snap=session.snapshot
	own=snap.get("resident_goals",{})
	expect(own.get("milu",{})=={"1":{"state":"locked","choice":""},"3":milu3_locked},"keepsake: beta's milu 3 stays locked and unclaimed")
	expect(not JSON.stringify(snap).contains("\"%s\""%Goals.KEEPSAKE_KEY),"beta's whole snapshot never names bond_keepsakes")
	session.world=null
	session.queue_free()
	await process_frame
