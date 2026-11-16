extends SceneTree
## 第 40 章金瓜石初訪「河邊淘砂金」(scripts/gold_panning.gd) rules test.
## Headless: pure-module checks on hand-built state dictionaries, then World-level
## (World.act / save / load_world). No Session, no network.
##
## PLAYED through GoldPanning.apply / World.act: every scoop / sift / swirl / pick, so every
## record written into state.gold_panning in sections 2-4 and 6 comes from a real action
## (except the hand-built records listed below), and every gold_ore gained comes from a pick.
## WRITTEN DIRECTLY (disclosed): the minimal module states (players with x/y/inventory,
## state.time), the hand-built records used by the view / step_block / apply-matrix / valid()
## tables and by the malformed-record cases, player region/x/y teleports in the World tests
## (standing on the bank in Jinguashi, at the shuttle, at home, in Lanyang; no travel action),
## state.time jumps to the next world day (start of day + 30 s, day length taken from
## Weather.DAY_SECONDS), gold_ore set to LIMIT / LIMIT-1 for BAG_FULL and restored, and the
## tampered / legacy save files.
const World=preload("res://scripts/world.gd")
const GP=preload("res://scripts/gold_panning.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="goldpan-alpha-token-4e2b"
const BETA:="goldpan-beta-token-81c9"
const STRANGER:="goldpan-stranger-token-0000"
const HOME_SPOT:=Vector2(39.5,33.5)
const LANYANG_SPOT:=Vector2(32.5,24.5)
const BANK:=Vector2i(6,26)
const BANK_STAND:=Vector2(6.5,26.5)
const FAR_SPOT:=Vector2(12.5,20.5)
const SHUTTLE_ARRIVAL:=Vector2i(12,20)
const STEP_ORDER:=["scoop","sift","swirl","swirl","swirl","pick"]

var checks:=0
var failures:=0
var serial:=0
var temp_files:=[]
var day_len:=0.0

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	day_len=float(Weather.DAY_SECONDS)
	check_static()
	check_views()
	check_step_block()
	check_apply_order()
	check_apply_matrix()
	check_full_pans()
	check_two_players()
	check_valid()
	check_site()
	check_world()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("GOLD_PANNING_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("gold-panning-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
	for suffix in ["",".bak",".tmp"]:temp_files.append(path+suffix)
	return path

static func canon(value:Variant) -> Variant:
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

static func same(a:Variant,b:Variant) -> bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

## Start of world day `day` (1-based, as GP.today) + 30 s.
func time_on(day:int) -> float:
	return float(day-1)*day_len+30.0

func rec4(at_stage:int,day:int,count:int,tot:int) -> Dictionary:
	return {"stage":at_stage,"day":day,"count":count,"total":tot}

func rec(s:Dictionary,token:String) -> Variant:
	var whole:Variant=s.get(GP.STATE_KEY)
	if not whole is Dictionary:return null
	var players:Variant=(whole as Dictionary).get("players")
	if not players is Dictionary:return null
	return (players as Dictionary).get(token)

static func all_int(value:Variant) -> bool:
	if not value is Dictionary:return false
	for k in value:
		if typeof(value[k])!=TYPE_INT:return false
	return true

func record_is(s:Dictionary,token:String,want:Dictionary,label:String) -> void:
	var got:Variant=rec(s,token)
	expect(got is Dictionary and same(got,want) and all_int(got),"%s: record %s (got %s)"%[label,str(want),str(got)])

func bag_of(s:Dictionary,token:String) -> Dictionary:
	var people:Variant=s.get("players")
	if not people is Dictionary:return {}
	var person:Variant=(people as Dictionary).get(token)
	if not person is Dictionary:return {}
	var inv:Variant=(person as Dictionary).get("inventory")
	if inv is Dictionary:return inv
	return {}

func gold(s:Dictionary,token:String) -> int:
	return int(bag_of(s,token).get(GP.ITEM,0))

## Minimal module state: both players on the bank, one world day.
func bare(t:float=30.0) -> Dictionary:
	return {"time":t,"players":{
		ALPHA:{"x":BANK_STAND.x,"y":BANK_STAND.y,"inventory":{"wood":2}},
		BETA:{"x":6.5,"y":25.5,"inventory":{}}},"notes":["untouched"]}

func bare_refuse(s:Dictionary,token:String,action:String,p:Vector2i,extra:String,in_jg:bool,message:String,label:String) -> void:
	var before:=var_to_bytes(s)
	var copy:Dictionary=s.duplicate(true)
	var r:Dictionary=GP.apply(s,token,action,p,extra,in_jg)
	expect(r.get("ok")==false and str(r.get("message",""))==message,"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(s)==before and s==copy,"%s: state byte-identical"%label)

func bare_ok(s:Dictionary,token:String,extra:String,message:String,label:String) -> bool:
	var r:Dictionary=GP.apply(s,token,GP.ACTION,GP.SITE,extra,true)
	return expect(r.get("ok")==true and str(r.get("message",""))==message,"%s: ok with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func jg(w:World,token:String,at:Vector2) -> void:
	put(w,token,at,GP.REGION)

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"goldpan-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

## Rejected with the exact message and the whole world state byte-identical.
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and str(r.get("message",""))==message,"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func held(w:World,token:String) -> int:
	return int(pl(w,token).inventory.get(GP.ITEM,0))

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func shape(w:World) -> Dictionary:
	var parsed:Variant=JSON.parse_string(JSON.stringify(w.state))
	if parsed is Dictionary:return parsed
	return {}

## Target is either a bare module state (Dictionary) or a World.
func state_of(target:Variant) -> Dictionary:
	if target is Dictionary:return target
	var w:World=target
	return w.state

func step_on(target:Variant,token:String,step:String) -> Dictionary:
	if target is Dictionary:
		var r:Dictionary=GP.apply(target,token,GP.ACTION,GP.SITE,step,true)
		return r
	var w:World=target
	return act(w,token,GP.ACTION,GP.SITE,step)

## Plays `steps` of one pan from an empty pan (6 = whole pan incl. pick), checking the exact
## message, the record, the views and the inventory after every step.
func pan(target:Variant,token:String,label:String,steps:int=6) -> void:
	var s:=state_of(target)
	var now:int=GP.today(s)
	var start:Dictionary=GP.fresh_record()
	var found:Variant=rec(s,token)
	if found is Dictionary:start=(found as Dictionary).duplicate()
	expect(int(start.stage)==0,"%s: premise empty pan"%label)
	var done:int=int(start.count) if int(start.day)==now else 0
	var rest:Dictionary=bag_of(s,token).duplicate(true)
	var gold0:=gold(s,token)
	var plan:=[["scoop",GP.SCOOP_OK],["sift",GP.SIFT_OK],["swirl",GP.SWIRL_OK%2],["swirl",GP.SWIRL_OK%1],["swirl",GP.SWIRL_LAST]]
	for i in mini(steps,5):
		var step:String=plan[i][0]
		var r:=step_on(target,token,step)
		s=state_of(target)
		expect(r.get("ok")==true and str(r.get("message",""))==str(plan[i][1]),"%s: %s #%d ok with '%s' (got '%s')"%[label,step,i,str(plan[i][1]),str(r.get("message",""))])
		record_is(s,token,{"stage":i+1,"day":int(start.day),"count":int(start.count),"total":int(start.total)},"%s after %s #%d"%[label,step,i])
		expect(gold(s,token)==gold0 and same(bag_of(s,token),rest),"%s: inventory untouched after %s #%d"%[label,step,i])
		expect(GP.stage(s,token)==i+1 and GP.next_step(s,token)==str(STEP_ORDER[i+1]) and GP.count_today(s,token)==done and GP.total(s,token)==int(start.total),"%s: views after %s #%d"%[label,step,i])
	if steps<6:return
	var picked:=step_on(target,token,"pick")
	s=state_of(target)
	expect(picked.get("ok")==true and str(picked.get("message",""))==GP.PICK_OK%(done+1),"%s: pick ok with '%s' (got '%s')"%[label,GP.PICK_OK%(done+1),str(picked.get("message",""))])
	record_is(s,token,rec4(0,now,done+1,int(start.total)+1),"%s after pick"%label)
	var want_bag:Dictionary=rest.duplicate(true)
	want_bag[GP.ITEM]=gold0+1
	expect(same(bag_of(s,token),want_bag),"%s: exactly one gold_ore added at the pick, nothing else"%label)
	expect(GP.stage(s,token)==0 and GP.next_step(s,token)=="scoop" and GP.count_today(s,token)==done+1 and GP.total(s,token)==int(start.total)+1,"%s: views after pick"%label)

## Hand-written expectation table of step_block (count 0 today, bag not full).
func row(at_stage:int) -> Dictionary:
	match at_stage:
		0:return {"scoop":"","sift":GP.NEED_SCOOP,"swirl":GP.NEED_SCOOP,"pick":GP.NEED_SCOOP}
		1:return {"scoop":GP.HAS_SAND,"sift":"","swirl":GP.NEED_SIFT,"pick":GP.NOT_YET}
		2:return {"scoop":GP.HAS_SAND,"sift":GP.SIFTED,"swirl":"","pick":GP.NOT_YET}
		3:return {"scoop":GP.HAS_SAND,"sift":GP.SIFTED,"swirl":"","pick":GP.NOT_YET}
		4:return {"scoop":GP.HAS_SAND,"sift":GP.SIFTED,"swirl":"","pick":GP.NOT_YET}
		5:return {"scoop":GP.HAS_SAND,"sift":GP.SIFTED,"swirl":GP.SWIRLED,"pick":""}
	return {}

func expected_block(at_stage:int,step:String,done:int,full:bool) -> String:
	if at_stage==0 and step=="scoop" and done>=3:return GP.DAILY_DONE
	if at_stage==5 and step=="pick" and full:return GP.BAG_FULL
	return str(row(at_stage)[step])

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(day_len>0.0 and Weather.day_index(day_len)==1.0 and Weather.day_index(day_len-0.5)==0.0 and Weather.day_index(0.0)==0.0,"premise: Weather day length %s"%str(day_len))
	expect(GP.ACTIONS==["gold_pan"] and GP.ACTION=="gold_pan","action name")
	expect(GP.STATE_KEY=="gold_panning" and GP.OWN_KEY=="own_gold_panning","state / snapshot keys")
	expect(GP.REGION=="jinguashi" and GP.REGION==World.REGIONS.JINGUASHI,"region is Jinguashi")
	expect(GP.SITE==Vector2i(5,26) and is_equal_approx(GP.REACH,3.2) and GP.DAILY==3,"site / reach / daily")
	expect(GP.ITEM=="gold_ore" and GP.LIMIT==1000000000,"item / limit")
	expect(World.NAMES.get(GP.ITEM)==GP.ITEM_NAME and GP.ITEM_NAME=="含金礦料","gold_ore name matches World.NAMES")
	expect(GP.STEPS==STEP_ORDER and GP.STEP_IDS==["scoop","sift","swirl","pick"],"step tables")
	expect(GP.RECORD_KEYS==["count","day","stage","total"],"record keys sorted")
	expect(GP.DISCLAIMER.contains("非史料") and GP.DISCLAIMER.contains("遊戲設計"),"disclaimer")
	expect(not GP.TITLE.is_empty() and not GP.SITE_NAME.is_empty() and not GP.BLURB.is_empty(),"title / site name / blurb")
	expect(GP.ACTION.length()<=24,"action fits the transport")
	for step:String in GP.STEP_IDS:
		expect(not str(GP.STEP_NAMES.get(step,"")).is_empty(),"step name for %s"%step)
		expect(Session.extra_allowed(GP.ACTION,step),"Session allows extra %s"%step)
	var others:Array=World.JINGUASHI_REVISIT.ACTIONS+World.BOBO_WORKSHOP.ACTIONS+World.LANYANG_REVISIT.ACTIONS+World.TEA_REVISIT.ACTIONS+["pick","mine_copper","quarry","fish","build","travel","transit"]
	expect(not GP.ACTION in others,"gold_pan does not collide with existing actions")
	# Literal message formats.
	expect(GP.SWIRL_OK%2=="洗掉一層砂（還要搖 2 次）。" and GP.SWIRL_OK%1=="洗掉一層砂（還要搖 1 次）。","SWIRL_OK format")
	expect(GP.PICK_OK%1=="揀出一份含金礦料（今天第 1／3 盤）。" and GP.PICK_OK%3=="揀出一份含金礦料（今天第 3／3 盤）。","PICK_OK format")
	expect(GP.DAILY_DONE.contains("3"),"DAILY_DONE names the daily limit")
	var messages:=[GP.NO_PLAYER,GP.WRONG_REGION,GP.BAD_EXTRA,GP.WRONG_CELL,GP.TOO_FAR,GP.HAS_SAND,GP.DAILY_DONE,GP.NEED_SCOOP,GP.SIFTED,GP.NEED_SIFT,GP.SWIRLED,GP.NOT_YET,GP.BAG_FULL,GP.SCOOP_OK,GP.SIFT_OK,GP.SWIRL_OK,GP.SWIRL_LAST,GP.PICK_OK]
	var distinct:={}
	for m:String in messages:
		expect(not m.is_empty(),"message non-empty: %s"%m)
		distinct[m]=true
	expect(distinct.size()==messages.size(),"all %d messages distinct"%messages.size())
	# fresh_record
	var a:Dictionary=GP.fresh_record()
	expect(same(a,rec4(0,0,0,0)) and all_int(a) and a.size()==4,"fresh_record")
	a["stage"]=4
	expect(int(GP.fresh_record().stage)==0,"fresh_record returns a new dictionary each time")
	# today
	expect(GP.today({})==1 and GP.today({"time":0.0})==1 and GP.today({"time":day_len-0.001})==1,"today: day 1")
	expect(GP.today({"time":day_len})==2 and GP.today({"time":time_on(9)})==9,"today: later days")
	expect(GP.today({"time":"abc"})==1 and GP.today({"time":-50.0})==1 and GP.today({"time":[1]})==1,"today: garbage time is day 1")
	# swirls_left
	var left:=[0,3,3,2,1,0]
	for i in 6:expect(GP.swirls_left(i)==int(left[i]),"swirls_left(%d)==%d (got %d)"%[i,int(left[i]),GP.swirls_left(i)])
	expect(GP.swirls_left(-1)==0 and GP.swirls_left(6)==0 and GP.swirls_left(99)==0,"swirls_left out of range is 0")
	# stage_text
	expect(GP.STAGE_TEXT.size()==6,"six stage texts")
	var texts:={}
	for i in 6:
		expect(GP.stage_text(i)==str(GP.STAGE_TEXT[i]) and not GP.stage_text(i).is_empty(),"stage_text(%d)"%i)
		texts[GP.stage_text(i)]=true
	expect(texts.size()==6,"stage texts distinct")
	expect(GP.stage_text(0)=="盤子是空的。" and GP.stage_text(5).contains("金光"),"stage_text literal ends")
	expect(GP.stage_text(-1)==GP.stage_text(0) and GP.stage_text(-99)==GP.stage_text(0),"stage_text clamps low")
	expect(GP.stage_text(6)==GP.stage_text(5) and GP.stage_text(100)==GP.stage_text(5),"stage_text clamps high")

# ------------------------------------------------------------------- views --

func expect_view(snap:Dictionary,token:String,want:Array,label:String) -> void:
	var before:=var_to_bytes(snap)
	var v:Dictionary=GP.view(snap,token)
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==["count","stage","total"] and typeof(v.get("stage"))==TYPE_INT and typeof(v.get("count"))==TYPE_INT and typeof(v.get("total"))==TYPE_INT
		and int(v.stage)==int(want[0]) and int(v.count)==int(want[1]) and int(v.total)==int(want[2]),"%s: view %s (got %s)"%[label,str(want),str(v)])
	expect(GP.stage(snap,token)==int(want[0]) and GP.count_today(snap,token)==int(want[1]) and GP.total(snap,token)==int(want[2]),"%s: stage/count_today/total"%label)
	expect(GP.next_step(snap,token)==str(STEP_ORDER[int(want[0])]),"%s: next_step"%label)
	expect(var_to_bytes(snap)==before,"%s: view leaves the snapshot untouched"%label)

func check_views() -> void:
	expect_view({},"",[0,0,0],"empty dict, no token")
	expect_view({},ALPHA,[0,0,0],"empty dict, token")
	expect_view({"time":time_on(3)},ALPHA,[0,0,0],"no record key, token")
	# Server state with tokens.
	var s:={"time":time_on(4),"players":{ALPHA:{},BETA:{}},GP.STATE_KEY:{"players":{ALPHA:rec4(3,4,2,9),BETA:rec4(0,2,3,3)}}}
	expect_view(s,ALPHA,[3,2,9],"server: alpha today")
	expect_view(s,BETA,[0,0,3],"server: beta's count is from day 2, reads 0 today")
	expect_view(s,STRANGER,[0,0,0],"server: unknown token")
	expect_view(s,"",[0,0,0],"server state without token ignores records")
	s["time"]=time_on(5)
	expect_view(s,ALPHA,[3,0,9],"server: next day the count resets, stage and total stay")
	s["time"]=time_on(4)+day_len-31.0
	expect(GP.today(s)==4,"premise: last second of day 4")
	expect_view(s,ALPHA,[3,2,9],"server: last second of day 4 still counts")
	s["time"]=time_on(2)
	expect_view(s,BETA,[0,3,3],"server: beta on day 2")
	# Client snapshots.
	expect_view({"time":0.0,GP.OWN_KEY:{"stage":3,"count":2,"total":9}},"",[3,2,9],"client snapshot")
	expect_view({"time":0.0,GP.OWN_KEY:{"stage":3,"count":2,"total":9}},ALPHA,[0,0,0],"client snapshot read with a token has no server record")
	expect_view({GP.OWN_KEY:{"stage":9,"count":7,"total":-4}},"",[5,3,0],"client snapshot clamps high / negative total")
	expect_view({GP.OWN_KEY:{"stage":-2,"count":-1,"total":5}},"",[0,0,5],"client snapshot clamps low")
	expect_view({GP.OWN_KEY:{"stage":2.0,"count":1.0,"total":4.0}},"",[2,1,4],"client snapshot JSON floats")
	expect_view({GP.OWN_KEY:{}},"",[0,0,0],"client snapshot empty own record")
	expect_view({GP.OWN_KEY:{"stage":4}},"",[4,0,0],"client snapshot partial own record")
	for junk:Variant in [[],"x",3,null,1.5]:
		expect_view({GP.OWN_KEY:junk},"",[0,0,0],"client snapshot own record is %s"%str(junk))
	expect_view({GP.STATE_KEY:{"players":{ALPHA:rec4(3,1,1,1)}},GP.OWN_KEY:{"stage":1,"count":0,"total":0}},"",[1,0,0],"no token reads own_gold_panning, not the server map")
	# Garbage server records -> zeros.
	var junk_records:={
		"record key is a list":[],
		"record key is a string":"x",
		"players is a list":{"players":[]},
		"players missing":{"other":{}},
		"record is a string":{"players":{ALPHA:"x"}},
		"record missing keys":{"players":{ALPHA:{"stage":2}}},
		"record extra key":{"players":{ALPHA:{"stage":2,"day":0,"count":0,"total":0,"x":1}}},
		"stage is a string":{"players":{ALPHA:{"stage":"2","day":0,"count":0,"total":0}}},
		"stage 6":{"players":{ALPHA:rec4(6,0,0,0)}},
		"stage -1":{"players":{ALPHA:rec4(-1,0,0,0)}},
		"stage 1.5":{"players":{ALPHA:{"stage":1.5,"day":0,"count":0,"total":0}}},
		"count 4":{"players":{ALPHA:rec4(0,1,4,4)}},
		"total -1":{"players":{ALPHA:rec4(0,0,0,-1)}},
		"day 1.5":{"players":{ALPHA:{"stage":0,"day":1.5,"count":1,"total":1}}},
		"stage is bool":{"players":{ALPHA:{"stage":true,"day":0,"count":0,"total":0}}},
	}
	for label:String in junk_records:
		expect_view({"time":time_on(1),"players":{ALPHA:{}},GP.STATE_KEY:junk_records[label]},ALPHA,[0,0,0],"server garbage: "+label)
	expect_view({"time":"abc",GP.STATE_KEY:{"players":{ALPHA:rec4(2,1,2,5)}}},ALPHA,[2,2,5],"garbage time reads as day 1")
	expect_view({"time":time_on(1),GP.STATE_KEY:{"players":{ALPHA:{"stage":2.0,"day":1.0,"count":2.0,"total":5.0}}}},ALPHA,[2,2,5],"server record with JSON floats")

# -------------------------------------------------------------- step_block --

func check_step_block() -> void:
	var t:=time_on(7)
	for at in 6:
		for done:int in [0,3]:
			for full:bool in [false,true]:
				var server:={"time":t,"players":{ALPHA:{}},GP.STATE_KEY:{"players":{ALPHA:rec4(at,7 if done>0 else 0,done,done)}}}
				var client:={"time":t,GP.OWN_KEY:{"stage":at,"count":done,"total":done}}
				var bag:Dictionary={GP.ITEM:GP.LIMIT} if full else {GP.ITEM:GP.LIMIT-1}
				for step:String in GP.STEP_IDS:
					var want:=expected_block(at,step,done,full)
					var tag:="stage %d, %s, %d today, bag %s"%[at,step,done,"full" if full else "ok"]
					var got_server:=GP.step_block(server,step,bag,ALPHA)
					var got_client:=GP.step_block(client,step,bag)
					expect(got_server==want,"step_block server (%s): '%s' (got '%s')"%[tag,want,got_server])
					expect(got_client==want,"step_block client (%s): '%s' (got '%s')"%[tag,want,got_client])
	# Yesterday's three pans do not block today.
	var yesterday:={"time":t,GP.STATE_KEY:{"players":{ALPHA:rec4(0,6,3,3)}}}
	expect(GP.step_block(yesterday,"scoop",{},ALPHA)=="","step_block: yesterday's 3 pans do not block today's scoop")
	var today_three:={"time":t,GP.STATE_KEY:{"players":{ALPHA:rec4(0,7,3,3)}}}
	expect(GP.step_block(today_three,"scoop",{},ALPHA)==GP.DAILY_DONE,"step_block: today's 3 pans block")
	var two:={"time":t,GP.STATE_KEY:{"players":{ALPHA:rec4(0,7,2,9)}}}
	expect(GP.step_block(two,"scoop",{},ALPHA)=="","step_block: 2 pans today still allow a scoop")
	var ready:={"time":t,GP.STATE_KEY:{"players":{ALPHA:rec4(5,0,0,0)}}}
	for inv:Variant in [null,[],"x",{},{"wood":3},{GP.ITEM:0}]:
		expect(GP.step_block(ready,"pick",inv,ALPHA)=="","step_block: pick with inventory %s is allowed"%str(inv))
	expect(GP.step_block(ready,"pick",{GP.ITEM:GP.LIMIT+5},ALPHA)==GP.BAG_FULL,"step_block: over the cap is BAG_FULL")
	for bad:String in ["","dig","SCOOP","swirl ","pick,pick","scoop:1"]:
		expect(GP.step_block(ready,bad,{},ALPHA)==GP.BAD_EXTRA,"step_block: unknown step '%s' (server)"%bad)
		expect(GP.step_block({},bad,{GP.ITEM:GP.LIMIT})==GP.BAD_EXTRA,"step_block: unknown step '%s' (empty)"%bad)
	expect(GP.step_block({},"scoop",{})=="" and GP.step_block({},"sift",{})==GP.NEED_SCOOP,"step_block on an empty snapshot")

# ------------------------------------------------------------ apply order --

func check_apply_order() -> void:
	var s:=bare()
	for action:String in ["pick","jg_revisit_sort","","GOLD_PAN","gold_pan ","gold_panning","scoop"]:
		bare_refuse(s,ALPHA,action,GP.SITE,"scoop",true,GP.BAD_EXTRA,"foreign action '%s'"%action)
	bare_refuse(s,STRANGER,"pick",GP.SITE,"scoop",false,GP.BAD_EXTRA,"foreign action beats unknown player and wrong region")
	bare_refuse(s,STRANGER,GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"unknown player")
	bare_refuse(s,"",GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"empty token")
	bare_refuse(s,STRANGER,GP.ACTION,Vector2i(0,0),"dig",false,GP.NO_PLAYER,"unknown player beats wrong region / bad extra / cell")
	var no_players:=bare()
	no_players.erase("players")
	bare_refuse(no_players,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"state without players")
	var list_players:=bare()
	list_players["players"]=[ALPHA]
	bare_refuse(list_players,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"players is a list")
	var string_person:=bare()
	string_person.players[ALPHA]="x"
	bare_refuse(string_person,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"person is a string")
	for step:String in GP.STEP_IDS:
		bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,step,false,GP.WRONG_REGION,"%s outside Jinguashi"%step)
	bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,"dig",false,GP.WRONG_REGION,"wrong region beats bad extra")
	bare_refuse(s,ALPHA,GP.ACTION,Vector2i(0,0),"scoop",false,GP.WRONG_REGION,"wrong region beats wrong cell")
	for bad:String in ["","Scoop","scoop ","swirl:1","dig","pick,pick","sift\n"]:
		bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,bad,true,GP.BAD_EXTRA,"bad extra '%s'"%bad.c_escape())
	bare_refuse(s,ALPHA,GP.ACTION,BANK,"dig",true,GP.BAD_EXTRA,"bad extra beats wrong cell")
	# Malformed existing records.
	var malformed:={
		"record key is null":null,
		"record key is a list":[],
		"record key is a string":"x",
		"record key is empty":{},
		"record key has an extra key":{"players":{},"extra":1},
		"players is a list":{"players":[]},
		"own record is a string":{"players":{ALPHA:"x"}},
		"own record missing keys":{"players":{ALPHA:{"stage":1}}},
		"own record extra key":{"players":{ALPHA:{"stage":1,"day":0,"count":0,"total":0,"by":"x"}}},
		"own stage 6":{"players":{ALPHA:rec4(6,0,0,0)}},
		"own stage -1":{"players":{ALPHA:rec4(-1,0,0,0)}},
		"own stage string":{"players":{ALPHA:{"stage":"1","day":0,"count":0,"total":0}}},
		"own stage 1.5":{"players":{ALPHA:{"stage":1.5,"day":0,"count":0,"total":0}}},
		"own count 4":{"players":{ALPHA:rec4(0,1,4,4)}},
		"own total -1":{"players":{ALPHA:rec4(0,0,0,-1)}},
		"own day 1.5":{"players":{ALPHA:{"stage":0,"day":1.5,"count":1,"total":1}}},
		"own day above LIMIT":{"players":{ALPHA:rec4(0,GP.LIMIT+1,1,1)}},
	}
	for label:String in malformed:
		var m:=bare()
		m[GP.STATE_KEY]=malformed[label]
		bare_refuse(m,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.BAD_EXTRA,"malformed: "+label)
		bare_refuse(m,ALPHA,GP.ACTION,BANK,"pick",true,GP.BAD_EXTRA,"malformed beats wrong cell: "+label)
		bare_refuse(m,ALPHA,GP.ACTION,GP.SITE,"scoop",false,GP.WRONG_REGION,"wrong region beats malformed: "+label)
	# Another player's malformed record is not touched by alpha's action (ok or not).
	var other:=bare()
	other[GP.STATE_KEY]={"players":{BETA:"x"}}
	var _ignored:Dictionary=GP.apply(other,ALPHA,GP.ACTION,GP.SITE,"scoop",true)
	expect(str(rec(other,BETA))=="x" and typeof(rec(other,BETA))==TYPE_STRING,"alpha's action never rewrites beta's (malformed) record")
	# Wrong cell.
	for cell:Vector2i in [BANK,Vector2i(5,25),Vector2i(5,27),Vector2i(4,26),Vector2i(0,0),Vector2i(-5,26)]:
		bare_refuse(s,ALPHA,GP.ACTION,cell,"scoop",true,GP.WRONG_CELL,"wrong cell %s"%str(cell))
	var far:=bare()
	far.players[ALPHA]["x"]=40.5
	bare_refuse(far,ALPHA,GP.ACTION,BANK,"scoop",true,GP.WRONG_CELL,"wrong cell beats too far")
	# Reach: just outside vs just inside (centre of SITE is (5.5,26.5), REACH 3.2).
	for at:Vector2 in [Vector2(8.71,26.5),Vector2(2.29,26.5),Vector2(5.5,29.71),Vector2(5.5,23.29),Vector2(40.5,30.5)]:
		var f:=bare()
		f.players[ALPHA]["x"]=at.x
		f.players[ALPHA]["y"]=at.y
		bare_refuse(f,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.TOO_FAR,"too far at %s"%str(at))
		bare_refuse(f,ALPHA,GP.ACTION,GP.SITE,"sift",true,GP.TOO_FAR,"too far beats wrong order at %s"%str(at))
	for at:Vector2 in [Vector2(8.69,26.5),Vector2(2.31,26.5),Vector2(5.5,29.69),Vector2(5.5,23.31),Vector2(7.5,28.5)]:
		var n:=bare()
		n.players[ALPHA]["x"]=at.x
		n.players[ALPHA]["y"]=at.y
		bare_ok(n,ALPHA,"scoop",GP.SCOOP_OK,"inside reach at %s"%str(at))
		record_is(n,ALPHA,rec4(1,0,0,0),"scoop inside reach at %s"%str(at))
	var nowhere:=bare()
	(nowhere.players[ALPHA] as Dictionary).erase("x")
	(nowhere.players[ALPHA] as Dictionary).erase("y")
	bare_refuse(nowhere,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.TOO_FAR,"person without x/y is at (0,0)")
	# Inventory checked after distance.
	var no_bag:=bare()
	(no_bag.players[ALPHA] as Dictionary).erase("inventory")
	bare_refuse(no_bag,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"person without an inventory")
	var string_bag:=bare()
	string_bag.players[ALPHA]["inventory"]="x"
	bare_refuse(string_bag,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.NO_PLAYER,"inventory is a string")
	no_bag.players[ALPHA]["x"]=40.5
	bare_refuse(no_bag,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.TOO_FAR,"too far beats missing inventory")
	expect(not s.has(GP.STATE_KEY),"no record is created by any refused action")
	# Wrong-order messages along one pan.
	var o:=bare()
	for at in 6:
		for step:String in GP.STEP_IDS:
			var want:=expected_block(at,step,0,false)
			if not want.is_empty():bare_refuse(o,ALPHA,GP.ACTION,GP.SITE,step,true,want,"wrong order at stage %d: %s"%[at,step])
		var next:String=STEP_ORDER[at]
		expect(GP.step_block(o,next,bag_of(o,ALPHA),ALPHA)=="","stage %d: step_block agrees %s is next"%[at,next])
		var r:Dictionary=GP.apply(o,ALPHA,GP.ACTION,GP.SITE,next,true)
		expect(r.get("ok")==true,"stage %d: %s goes through"%[at,next])
	record_is(o,ALPHA,rec4(0,1,1,1),"one pan done on day 1")

# ----------------------------------------------------------- apply matrix --

func check_apply_matrix() -> void:
	for at in 6:
		for done:int in [0,3]:
			for step:String in GP.STEP_IDS:
				# A stage>0 pan with 3 pans already done TODAY cannot be reached by play (the
				# fourth scoop is refused); its pick is reported, not asserted (see report).
				if at==5 and done==3 and step=="pick":continue
				var s:=bare(time_on(7))
				var start:=rec4(at,7 if done>0 else 0,done,done)
				s[GP.STATE_KEY]={"players":{ALPHA:start.duplicate()}}
				var want:=expected_block(at,step,done,false)
				var tag:="apply matrix stage %d, %s, %d today"%[at,step,done]
				if not want.is_empty():
					bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,step,true,want,tag)
					continue
				var r:Dictionary=GP.apply(s,ALPHA,GP.ACTION,GP.SITE,step,true)
				expect(r.get("ok")==true,"%s: ok (got '%s')"%[tag,str(r.get("message",""))])
				var after:Dictionary=start.duplicate()
				match step:
					"scoop":after.stage=1
					"sift":after.stage=2
					"swirl":after.stage=at+1
					"pick":
						after.stage=0
						after.day=7
						after.count=done+1
						after.total=done+1
				record_is(s,ALPHA,after,tag)
				expect(gold(s,ALPHA)==(1 if step=="pick" else 0),"%s: gold_ore only from a pick"%tag)
	# BAG_FULL in apply.
	var full:=bare(time_on(2))
	full[GP.STATE_KEY]={"players":{ALPHA:rec4(5,1,2,6)}}
	full.players[ALPHA].inventory[GP.ITEM]=GP.LIMIT
	bare_refuse(full,ALPHA,GP.ACTION,GP.SITE,"pick",true,GP.BAG_FULL,"pick with gold_ore at LIMIT")
	bare_refuse(full,ALPHA,GP.ACTION,GP.SITE,"pick",true,GP.BAG_FULL,"pick with gold_ore at LIMIT again")
	record_is(full,ALPHA,rec4(5,1,2,6),"BAG_FULL leaves the pan at stage 5")
	full.players[ALPHA].inventory[GP.ITEM]=GP.LIMIT-1
	bare_ok(full,ALPHA,"pick",GP.PICK_OK%1,"pick with gold_ore at LIMIT-1")
	expect(gold(full,ALPHA)==GP.LIMIT,"gold_ore reaches LIMIT exactly")
	record_is(full,ALPHA,rec4(0,2,1,7),"pick after BAG_FULL counts for today")
	bare_ok(full,ALPHA,"scoop",GP.SCOOP_OK,"a full bag still allows scooping (only the pick checks the bag)")

# -------------------------------------------------------------- full pans --

func check_full_pans() -> void:
	var s:=bare(time_on(3))
	expect(GP.today(s)==3,"premise: day 3")
	expect(not s.has(GP.STATE_KEY),"no record before the first scoop")
	var before_scoop:=var_to_bytes(s)
	pan(s,ALPHA,"day 3 pan 1",1)
	expect(var_to_bytes(s)!=before_scoop and s.has(GP.STATE_KEY),"first successful scoop writes the record")
	record_is(s,ALPHA,rec4(1,0,0,0),"first scoop record")
	expect(not rec(s,BETA) is Dictionary,"only alpha's record is written")
	expect((s[GP.STATE_KEY] as Dictionary).size()==1 and ((s[GP.STATE_KEY] as Dictionary).players as Dictionary).size()==1,"record shape {players:{alpha}}")
	# finish pan 1 by hand from stage 1
	bare_ok(s,ALPHA,"sift",GP.SIFT_OK,"day 3 pan 1 sift")
	bare_ok(s,ALPHA,"swirl",GP.SWIRL_OK%2,"day 3 pan 1 swirl 1")
	bare_ok(s,ALPHA,"swirl",GP.SWIRL_OK%1,"day 3 pan 1 swirl 2")
	bare_ok(s,ALPHA,"swirl",GP.SWIRL_LAST,"day 3 pan 1 swirl 3")
	expect(gold(s,ALPHA)==0,"no gold before the pick")
	bare_ok(s,ALPHA,"pick",GP.PICK_OK%1,"day 3 pan 1 pick")
	record_is(s,ALPHA,rec4(0,3,1,1),"day 3 pan 1 done")
	expect(gold(s,ALPHA)==1 and int(bag_of(s,ALPHA).get("wood",0))==2,"one gold_ore, wood untouched")
	pan(s,ALPHA,"day 3 pan 2")
	record_is(s,ALPHA,rec4(0,3,2,2),"day 3 pan 2 done")
	pan(s,ALPHA,"day 3 pan 3")
	record_is(s,ALPHA,rec4(0,3,3,3),"day 3 pan 3 done")
	expect(gold(s,ALPHA)==3 and GP.count_today(s,ALPHA)==3,"three gold_ore, three pans today")
	bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.DAILY_DONE,"fourth scoop on day 3")
	for step:String in ["sift","swirl","pick"]:bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,step,true,GP.NEED_SCOOP,"after the daily limit: %s"%step)
	s["time"]=time_on(3)+day_len-31.0
	expect(GP.today(s)==3,"premise: last second of day 3")
	bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.DAILY_DONE,"fourth scoop at the end of day 3")
	# Next world day.
	s["time"]=time_on(4)
	expect(GP.today(s)==4 and GP.count_today(s,ALPHA)==0 and GP.total(s,ALPHA)==3,"day 4: count reads 0, total 3")
	bare_ok(s,ALPHA,"scoop",GP.SCOOP_OK,"day 4 scoop")
	record_is(s,ALPHA,rec4(1,3,3,3),"day 4 scoop keeps day/count until the pick")
	expect(GP.count_today(s,ALPHA)==0,"day 4: still 0 finished today")
	for step:String in ["sift","swirl","swirl","swirl"]:
		var r:Dictionary=GP.apply(s,ALPHA,GP.ACTION,GP.SITE,step,true)
		expect(r.get("ok")==true,"day 4 pan 1 %s"%step)
	bare_ok(s,ALPHA,"pick",GP.PICK_OK%1,"day 4 pan 1 pick")
	record_is(s,ALPHA,rec4(0,4,1,4),"day 4: count restarts at 1, total continues")
	# Scooped on day 4, picked on day 5: counts for day 5.
	pan(s,ALPHA,"day 4 pan 2 (no pick)",5)
	record_is(s,ALPHA,rec4(5,4,1,4),"day 4 pan 2 waits at stage 5")
	s["time"]=time_on(5)
	expect(GP.count_today(s,ALPHA)==0 and GP.stage(s,ALPHA)==5,"day 5: unfinished pan kept, count 0")
	bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.HAS_SAND,"day 5: cannot scoop over yesterday's pan")
	bare_ok(s,ALPHA,"pick",GP.PICK_OK%1,"day 5 pick of a day-4 pan")
	record_is(s,ALPHA,rec4(0,5,1,5),"day-4 pan counts as day 5's first")
	expect(gold(s,ALPHA)==5,"five gold_ore after five pans")
	# Skipping days.
	s["time"]=time_on(9)
	pan(s,ALPHA,"day 9 pan 1")
	record_is(s,ALPHA,rec4(0,9,1,6),"day 9 pan 1")
	# Day 9: two more, then the limit, then BAG_FULL on day 10.
	pan(s,ALPHA,"day 9 pan 2")
	pan(s,ALPHA,"day 9 pan 3")
	bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,"scoop",true,GP.DAILY_DONE,"day 9 fourth scoop")
	s["time"]=time_on(10)
	pan(s,ALPHA,"day 10 pan 1 (to stage 5)",5)
	var keep:=gold(s,ALPHA)
	s.players[ALPHA].inventory[GP.ITEM]=GP.LIMIT
	bare_refuse(s,ALPHA,GP.ACTION,GP.SITE,"pick",true,GP.BAG_FULL,"day 10 pick with a full bag")
	record_is(s,ALPHA,rec4(5,9,3,8),"BAG_FULL: stage stays 5, nothing counted")
	expect(gold(s,ALPHA)==GP.LIMIT,"BAG_FULL: gold_ore unchanged")
	s.players[ALPHA].inventory[GP.ITEM]=keep
	bare_ok(s,ALPHA,"pick",GP.PICK_OK%1,"day 10 pick after making room")
	record_is(s,ALPHA,rec4(0,10,1,9),"day 10 pan 1")
	expect(gold(s,ALPHA)==keep+1,"day 10: +1 gold_ore")
	expect(not rec(s,BETA) is Dictionary and bag_of(s,BETA).is_empty(),"beta untouched by alpha's ten pans")
	expect(str(s.get("notes"))==str(["untouched"]),"unrelated state untouched")

# ------------------------------------------------------------- two players --

func check_two_players() -> void:
	var s:=bare(time_on(2))
	bare_ok(s,ALPHA,"scoop",GP.SCOOP_OK,"alpha scoops")
	bare_ok(s,ALPHA,"sift",GP.SIFT_OK,"alpha sifts")
	var steps:=["scoop","sift","swirl","swirl","swirl","pick"]
	for n in 3:
		for step:String in steps:
			var a_rec:=var_to_bytes(rec(s,ALPHA))
			var a_bag:=var_to_bytes(bag_of(s,ALPHA))
			var r:Dictionary=GP.apply(s,BETA,GP.ACTION,GP.SITE,step,true)
			expect(r.get("ok")==true,"beta pan %d %s ok (got '%s')"%[n+1,step,str(r.get("message",""))])
			expect(var_to_bytes(rec(s,ALPHA))==a_rec and var_to_bytes(bag_of(s,ALPHA))==a_bag,"beta pan %d %s leaves alpha's record and bag alone"%[n+1,step])
	record_is(s,BETA,rec4(0,2,3,3),"beta's three pans")
	record_is(s,ALPHA,rec4(2,0,0,0),"alpha still at stage 2")
	expect(gold(s,BETA)==3 and gold(s,ALPHA)==0,"gold only in beta's bag")
	bare_refuse(s,BETA,GP.ACTION,GP.SITE,"scoop",true,GP.DAILY_DONE,"beta's daily limit")
	bare_ok(s,ALPHA,"swirl",GP.SWIRL_OK%2,"alpha continues after beta's pans")
	var b_rec:=var_to_bytes(rec(s,BETA))
	var b_bag:=var_to_bytes(bag_of(s,BETA))
	bare_ok(s,ALPHA,"swirl",GP.SWIRL_OK%1,"alpha swirl 2")
	bare_ok(s,ALPHA,"swirl",GP.SWIRL_LAST,"alpha swirl 3")
	bare_ok(s,ALPHA,"pick",GP.PICK_OK%1,"alpha's first pan counts 1, not beta's 4")
	expect(var_to_bytes(rec(s,BETA))==b_rec and var_to_bytes(bag_of(s,BETA))==b_bag,"alpha's steps leave beta's record and bag alone")
	record_is(s,ALPHA,rec4(0,2,1,1),"alpha's record")
	var keys:Array=((s[GP.STATE_KEY] as Dictionary).players as Dictionary).keys()
	keys.sort()
	var want:=[ALPHA,BETA]
	want.sort()
	expect(keys==want,"records keyed by token")
	expect(GP.view(s,ALPHA).count==1 and GP.view(s,BETA).count==3,"views per token")

# ------------------------------------------------------------------ valid() --

func vs(gp_value:Variant,t:float) -> Dictionary:
	return {"time":t,"players":{ALPHA:{"name":"a"},BETA:{"name":"b"}},GP.STATE_KEY:gp_value}

func valid_case(label:String,gp_value:Variant,want:bool) -> void:
	var s:=vs(gp_value,time_on(5))
	expect(GP.valid(s)==want,"valid() %s: %s"%["accepts" if want else "rejects",label])

func check_valid() -> void:
	expect(GP.valid({"time":time_on(5),"players":{ALPHA:{}}}),"valid(): absent key ok")
	expect(GP.valid({}),"valid(): empty state without the key ok")
	valid_case("no players yet",{"players":{}},true)
	valid_case("fresh record",{"players":{ALPHA:rec4(0,0,0,0)}},true)
	valid_case("first pan in progress",{"players":{ALPHA:rec4(3,0,0,0)}},true)
	valid_case("three pans today",{"players":{ALPHA:rec4(0,5,3,7)}},true)
	valid_case("pan in progress after an older day",{"players":{ALPHA:rec4(5,2,1,1)}},true)
	valid_case("both players",{"players":{ALPHA:rec4(1,4,2,2),BETA:rec4(0,1,1,1)}},true)
	valid_case("total at LIMIT",{"players":{ALPHA:rec4(0,5,3,GP.LIMIT)}},true)
	valid_case("count 1 day 1",{"players":{ALPHA:rec4(0,1,1,1)}},true)
	valid_case("count equals total",{"players":{ALPHA:rec4(2,5,2,2)}},true)
	# Rejected shapes.
	valid_case("record key null",null,false)
	valid_case("record key a list",[],false)
	valid_case("record key a string","x",false)
	valid_case("record key empty",{},false)
	valid_case("extra top-level key",{"players":{},"by":1},false)
	valid_case("extra top-level key with a good record",{"players":{ALPHA:rec4(0,1,1,1)},"day":1},false)
	valid_case("players is a list",{"players":[]},false)
	valid_case("players is null",{"players":null},false)
	valid_case("record is a string",{"players":{ALPHA:"x"}},false)
	valid_case("record is a list",{"players":{ALPHA:[0,0,0,0]}},false)
	valid_case("record extra key",{"players":{ALPHA:{"stage":0,"day":0,"count":0,"total":0,"x":1}}},false)
	for field:String in ["stage","day","count","total"]:
		var r:=rec4(0,1,1,1)
		r.erase(field)
		valid_case("record missing %s"%field,{"players":{ALPHA:r}},false)
	valid_case("unknown token",{"players":{STRANGER:rec4(0,1,1,1)}},false)
	valid_case("unknown token next to a good one",{"players":{ALPHA:rec4(0,1,1,1),STRANGER:rec4(0,0,0,0)}},false)
	valid_case("stage 6",{"players":{ALPHA:rec4(6,1,1,1)}},false)
	valid_case("stage -1",{"players":{ALPHA:rec4(-1,1,1,1)}},false)
	valid_case("day -1",{"players":{ALPHA:rec4(0,-1,1,1)}},false)
	valid_case("count -1",{"players":{ALPHA:rec4(0,1,-1,1)}},false)
	valid_case("total -1",{"players":{ALPHA:rec4(0,0,0,-1)}},false)
	valid_case("count 4 > DAILY",{"players":{ALPHA:rec4(0,5,4,4)}},false)
	valid_case("total above LIMIT",{"players":{ALPHA:rec4(0,5,3,GP.LIMIT+1)}},false)
	valid_case("stage 1.5",{"players":{ALPHA:{"stage":1.5,"day":1,"count":1,"total":1}}},false)
	valid_case("day 2.5",{"players":{ALPHA:{"stage":0,"day":2.5,"count":1,"total":1}}},false)
	valid_case("count 0.5",{"players":{ALPHA:{"stage":0,"day":1,"count":0.5,"total":1}}},false)
	valid_case("total 1.25",{"players":{ALPHA:{"stage":0,"day":1,"count":1,"total":1.25}}},false)
	valid_case("stage string",{"players":{ALPHA:{"stage":"0","day":1,"count":1,"total":1}}},false)
	valid_case("stage bool",{"players":{ALPHA:{"stage":true,"day":1,"count":1,"total":1}}},false)
	valid_case("stage INF",{"players":{ALPHA:{"stage":INF,"day":1,"count":1,"total":1}}},false)
	valid_case("day in the future (today 5)",{"players":{ALPHA:rec4(0,6,1,1)}},false)
	valid_case("day far in the future",{"players":{ALPHA:rec4(0,500,1,1)}},false)
	valid_case("total 0 with day > 0",{"players":{ALPHA:rec4(0,3,0,0)}},false)
	valid_case("total 0 with day and count",{"players":{ALPHA:rec4(0,3,1,0)}},false)
	valid_case("total > 0 with day 0",{"players":{ALPHA:rec4(0,0,0,2)}},false)
	valid_case("total > 0 with day 0 and a count",{"players":{ALPHA:rec4(0,0,1,2)}},false)
	valid_case("total > 0 with count 0",{"players":{ALPHA:rec4(0,3,0,2)}},false)
	valid_case("count > total",{"players":{ALPHA:rec4(0,3,3,2)}},false)
	var bad_players:=vs({"players":{ALPHA:rec4(0,1,1,1)}},time_on(5))
	bad_players["players"]=[ALPHA]
	expect(not GP.valid(bad_players),"valid() rejects: state.players is a list")
	var no_players:=vs({"players":{ALPHA:rec4(0,1,1,1)}},time_on(5))
	no_players.erase("players")
	expect(not GP.valid(no_players),"valid() rejects: state.players missing")
	# No time: today is day 1.
	expect(GP.valid({"players":{ALPHA:{}},GP.STATE_KEY:{"players":{ALPHA:rec4(0,1,1,1)}}}),"valid() without time: day 1 ok")
	expect(not GP.valid({"players":{ALPHA:{}},GP.STATE_KEY:{"players":{ALPHA:rec4(0,2,1,1)}}}),"valid() without time: day 2 is the future")
	# JSON floats normalised on success.
	var floats:=vs({"players":{ALPHA:{"stage":2.0,"day":4.0,"count":1.0,"total":5.0},BETA:{"stage":0.0,"day":0.0,"count":0.0,"total":0.0}}},time_on(5))
	expect(GP.valid(floats),"valid() accepts JSON floats")
	var fa:Variant=rec(floats,ALPHA)
	var fb:Variant=rec(floats,BETA)
	expect(all_int(fa) and same(fa,rec4(2,4,1,5)),"valid() normalises alpha's floats to int (%s)"%str(fa))
	expect(all_int(fb) and same(fb,rec4(0,0,0,0)),"valid() normalises beta's floats to int")
	var partial:=vs({"players":{ALPHA:{"stage":2.0,"day":4.0,"count":1.0,"total":5.0},BETA:rec4(6,0,0,0)}},time_on(5))
	expect(not GP.valid(partial),"valid() rejects when one record is bad")
	var pa:Variant=rec(partial,ALPHA)
	expect(pa is Dictionary and typeof(pa.get("stage"))==TYPE_FLOAT,"a rejected valid() writes nothing (alpha's floats untouched)")
	var round_trip:Variant=JSON.parse_string(JSON.stringify(vs({"players":{ALPHA:rec4(4,5,3,3)}},time_on(5))))
	expect(round_trip is Dictionary and GP.valid(round_trip) and all_int(rec(round_trip,ALPHA)),"valid() on a JSON round trip")

# -------------------------------------------------------------------- site --

func check_site() -> void:
	var w:=World.new()
	w.switch_region(GP.REGION)
	expect(w.blocked(GP.SITE),"SITE is not walkable in Jinguashi")
	expect(w.water(GP.SITE) or not w.is_land(GP.SITE),"SITE is water")
	expect(w.is_land(BANK) and not w.water(BANK) and not w.blocked(BANK),"bank cell (6,26) is land and not blocked")
	expect(w.can_stand(BANK_STAND),"a player can stand on the bank")
	expect(BANK_STAND.distance_to(Vector2(GP.SITE)+Vector2(0.5,0.5))<=GP.REACH,"bank stand within reach")
	expect(w.can_stand(FAR_SPOT) and FAR_SPOT.distance_to(Vector2(GP.SITE)+Vector2(0.5,0.5))>GP.REACH,"shuttle spot is standable and out of reach")
	var seen:={SHUTTLE_ARRIVAL:true}
	var queue:=[SHUTTLE_ARRIVAL]
	while not queue.is_empty():
		var c:Vector2i=queue.pop_front()
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			if not w.can_stand(Vector2(n)+Vector2(0.5,0.5)):continue
			seen[n]=true
			queue.append(n)
	expect(seen.has(BANK),"bank reachable on foot from the shuttle arrival")
	expect(not seen.has(GP.SITE),"SITE itself is not reachable on foot")
	w.switch_region("home")
	expect(not w.state.has(GP.STATE_KEY),"fresh world has no gold_panning record")

# ------------------------------------------------------------------- world --

func check_world() -> void:
	var w:=World.new()
	var path:=temp_path("main")
	w.save_path=path
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	expect(not w.state.has(GP.STATE_KEY),"world: no record before any pan")
	expect(validates(shape(w)),"world: fresh world validates")
	var day:int=GP.today(w.state)
	put(w,ALPHA,HOME_SPOT,"home")
	for step:String in GP.STEP_IDS:refuse(w,ALPHA,GP.ACTION,GP.SITE,step,GP.WRONG_REGION,"world: %s from home"%step)
	put(w,ALPHA,LANYANG_SPOT,"lanyang")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"scoop",GP.WRONG_REGION,"world: scoop from Lanyang")
	jg(w,ALPHA,FAR_SPOT)
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"scoop",GP.TOO_FAR,"world: scoop from the shuttle")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"pick",GP.TOO_FAR,"world: pick from the shuttle")
	jg(w,ALPHA,BANK_STAND)
	refuse(w,ALPHA,GP.ACTION,BANK,"scoop",GP.WRONG_CELL,"world: scoop at the bank cell")
	refuse(w,ALPHA,GP.ACTION,GP.SITE+Vector2i(0,1),"scoop",GP.WRONG_CELL,"world: scoop next to SITE")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"dig",GP.BAD_EXTRA,"world: unknown step")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"",GP.BAD_EXTRA,"world: empty step")
	for step:String in ["sift","swirl","pick"]:refuse(w,ALPHA,GP.ACTION,GP.SITE,step,GP.NEED_SCOOP,"world: %s before scooping"%step)
	expect(not w.state.has(GP.STATE_KEY),"world: refusals write no record")
	# Alpha: three pans.
	var start_gold:=held(w,ALPHA)
	pan(w,ALPHA,"world: alpha pan 1")
	record_is(w.state,ALPHA,rec4(0,day,1,1),"world: alpha pan 1")
	expect(held(w,ALPHA)==start_gold+1,"world: alpha got one gold_ore")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"sift",GP.NEED_SCOOP,"world: sift on an empty pan after a pick")
	pan(w,ALPHA,"world: alpha pan 2")
	pan(w,ALPHA,"world: alpha pan 3 to the gold",5)
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"swirl",GP.SWIRLED,"world: a fourth swirl")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"scoop",GP.HAS_SAND,"world: scoop over sand")
	var keep:=held(w,ALPHA)
	pl(w,ALPHA).inventory[GP.ITEM]=GP.LIMIT
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"pick",GP.BAG_FULL,"world: gold_ore at the cap")
	record_is(w.state,ALPHA,rec4(5,day,2,2),"world: BAG_FULL keeps stage 5")
	pl(w,ALPHA).inventory[GP.ITEM]=keep
	var picked:=ok(w,ALPHA,GP.ACTION,GP.SITE,"pick","world: alpha picks pan 3")
	expect(str(picked.get("message",""))==GP.PICK_OK%3 and held(w,ALPHA)==keep+1,"world: pan 3 message and gold")
	record_is(w.state,ALPHA,rec4(0,day,3,3),"world: alpha three pans")
	refuse(w,ALPHA,GP.ACTION,GP.SITE,"scoop",GP.DAILY_DONE,"world: fourth scoop")
	# Beta, independent.
	jg(w,BETA,BANK_STAND)
	var alpha_rec:=var_to_bytes(canon(rec(w.state,ALPHA)))
	var alpha_bag:=var_to_bytes(canon(pl(w,ALPHA).inventory))
	pan(w,BETA,"world: beta scoops and sifts",2)
	record_is(w.state,BETA,rec4(2,0,0,0),"world: beta at stage 2")
	expect(var_to_bytes(canon(rec(w.state,ALPHA)))==alpha_rec and var_to_bytes(canon(pl(w,ALPHA).inventory))==alpha_bag,"world: beta's steps leave alpha alone")
	expect(held(w,BETA)==0,"world: beta has no gold yet")
	put(w,BETA,HOME_SPOT,"home")
	refuse(w,BETA,GP.ACTION,GP.SITE,"swirl",GP.WRONG_REGION,"world: beta swirls from home")
	jg(w,BETA,BANK_STAND)
	# Save mid-pan and reload.
	expect(w.save(),"world: saves mid-pan")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"world: saved file parses and validates"):return
	var saved:Variant=(base as Dictionary).get(GP.STATE_KEY)
	expect(saved is Dictionary and same(saved,w.state[GP.STATE_KEY]),"world: saved record equals the live record")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"world: reload")
	expect(same(reloaded.state.get(GP.STATE_KEY),w.state.get(GP.STATE_KEY)),"world: record equal after reload (canonical)")
	expect(all_int(rec(reloaded.state,ALPHA)) and all_int(rec(reloaded.state,BETA)),"world: reload normalises record values to int")
	for token:String in [ALPHA,BETA]:
		expect(same(reloaded.state.players[token].inventory,pl(w,token).inventory),"world: %s bag equal after reload"%token.left(14))
	jg(reloaded,ALPHA,BANK_STAND)
	jg(reloaded,BETA,BANK_STAND)
	refuse(reloaded,ALPHA,GP.ACTION,GP.SITE,"scoop",GP.DAILY_DONE,"world: daily limit survives reload")
	var sw:=ok(reloaded,BETA,GP.ACTION,GP.SITE,"swirl","world: beta continues her pan after reload")
	expect(str(sw.get("message",""))==GP.SWIRL_OK%2,"world: unfinished pan kept across reload")
	record_is(reloaded.state,BETA,rec4(3,0,0,0),"world: beta stage 3 after reload")
	reloaded.state["time"]=float(Weather.day_index(float(reloaded.state.time))+1.0)*day_len+30.0
	expect(GP.today(reloaded.state)==day+1,"world: premise next day")
	var sc:=ok(reloaded,ALPHA,GP.ACTION,GP.SITE,"scoop","world: alpha scoops on the next day")
	expect(str(sc.get("message",""))==GP.SCOOP_OK and GP.count_today(reloaded.state,ALPHA)==0 and GP.total(reloaded.state,ALPHA)==3,"world: next day count 0, total 3")
	record_is(reloaded.state,ALPHA,rec4(1,day,3,3),"world: next-day scoop record")
	# Legacy / tampered saves.
	var legacy:Dictionary=(base as Dictionary).duplicate(true)
	legacy.erase(GP.STATE_KEY)
	var fixture:=temp_path("fixture")
	var lw:=World.new()
	expect(validates(legacy) and write_json(fixture,legacy) and lw.load_world(fixture) and not lw.state.has(GP.STATE_KEY),"world: legacy save without the key loads unchanged")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["stage 6","unknown token","record extra key","record missing total","extra top-level key","players is a list",
		"record key is a list","count above total","day in the future","count above daily","total without day","fractional stage","negative total"]
	for label:String in labels:
		var bad:=tampered(base,label,day)
		expect(not validates(bad),"schema rejects: "+label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	var control:=tampered(base,"",day)
	expect(validates(control),"control: an untampered copy validates")

func tampered(base:Dictionary,label:String,day:int) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var gp_rec:Dictionary=s[GP.STATE_KEY]
	var players:Dictionary=gp_rec["players"]
	var a:Dictionary=players[ALPHA]
	var b:Dictionary=players[BETA]
	match label:
		"stage 6":a["stage"]=6
		"unknown token":players[STRANGER]=rec4(0,0,0,0)
		"record extra key":a["by"]="x"
		"record missing total":a.erase("total")
		"extra top-level key":gp_rec["day"]=1
		"players is a list":gp_rec["players"]=[a,b]
		"record key is a list":s[GP.STATE_KEY]=[gp_rec]
		"count above total":a["total"]=2
		"day in the future":a["day"]=day+1
		"count above daily":
			a["count"]=4
			a["total"]=4
		"total without day":b["total"]=1
		"fractional stage":b["stage"]=2.5
		"negative total":a["total"]=-3
	return s
