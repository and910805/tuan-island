extends SceneTree
## 第 40 章金瓜石初訪「運礦路線」(scripts/ore_route.gd) rules test.
## Headless: pure-module checks on hand-built state dictionaries, then World-level
## (World.act / save / load_world). No Session, no network.
##
## PLAYED through Route.apply / World.act: every load / push / unload, so every record written
## into state.ore_route in the full-cart, two-player and World sections comes from a real action
## (except the hand-built records listed below), and every coin gained comes from an unload.
## WRITTEN DIRECTLY (disclosed): the minimal module states (players with x/y/coins/inventory,
## state.time); the hand-built records used by the view / cart_label / step_block / apply-matrix /
## valid() tables, the malformed-record cases and the "full today plus a cart on the way" tamper;
## player x/y moves to the cart's current cell (centre, or a standable cell next to it in the
## second World cart) before each step — there is no walking simulation, but a TOO_FAR probe is
## made from the previous spot whenever it is out of reach; player region/x/y teleports in the
## World tests (Jinguashi stops, the shuttle arrival, home, Lanyang; no travel action);
## state.time jumps to the next world day (start of day + 30 s, day length from
## Weather.DAY_SECONDS); coins set to LIMIT-PAY+1 / LIMIT-PAY (and non-numeric values in the bare
## module) for PURSE_FULL / NO_PLAYER and restored; the tampered / legacy save files.
## NOT COVERED here: Session snapshots (own_ore_route), the UI page, world_view drawing, art.
const World=preload("res://scripts/world.gd")
const Route=preload("res://scripts/ore_route.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="orecart-alpha-token-5d1a"
const BETA:="orecart-beta-token-93f7"
const STRANGER:="orecart-stranger-token-0000"
const HOME_SPOT:=Vector2(39.5,33.5)
const LANYANG_SPOT:=Vector2(32.5,24.5)
const FAR_SPOT:=Vector2(12.5,20.5)
const SHUTTLE_ARRIVAL:=Vector2i(12,20)
const LOAD_STAND:=Vector2(31.5,20.5)

var checks:=0
var failures:=0
var serial:=0
var temp_files:=[]
var day_len:=0.0
## Standable spot next to each STOP (off the track when possible), filled by check_site().
var beside:={}
## When true, World carts stand on beside[cell] instead of the cell centre.
var use_beside:=false

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	day_len=float(Weather.DAY_SECONDS)
	check_static()
	check_pure_tables()
	check_views()
	check_cart_label()
	check_step_block()
	check_apply_order()
	check_apply_matrix()
	check_full_carts()
	check_two_players()
	check_valid()
	check_site()
	check_world()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("ORE_ROUTE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("ore-route-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

static func center(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

## Start of world day `day` (1-based, as Route.today) + 30 s.
func time_on(day:int) -> float:
	return float(day-1)*day_len+30.0

func rec4(at_stage:int,day:int,count:int,tot:int) -> Dictionary:
	return {"stage":at_stage,"day":day,"count":count,"total":tot}

func rec(s:Dictionary,token:String) -> Variant:
	var whole:Variant=s.get(Route.STATE_KEY)
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

func person_of(s:Dictionary,token:String) -> Dictionary:
	var people:Variant=s.get("players")
	if not people is Dictionary:return {}
	var person:Variant=(people as Dictionary).get(token)
	if person is Dictionary:return person
	return {}

func bag_of(s:Dictionary,token:String) -> Dictionary:
	var inv:Variant=person_of(s,token).get("inventory")
	if inv is Dictionary:return inv
	return {}

func coins_of(s:Dictionary,token:String) -> int:
	var c:Variant=person_of(s,token).get("coins")
	if c is int or c is float:return int(c)
	return -1

## Minimal module state: both players at the load platform, day 1 by default.
func bare(t:float=30.0) -> Dictionary:
	return {"time":t,"players":{
		ALPHA:{"x":LOAD_STAND.x,"y":LOAD_STAND.y,"coins":50,"inventory":{"wood":2}},
		BETA:{"x":LOAD_STAND.x,"y":LOAD_STAND.y+0.5,"coins":0,"inventory":{}}},"notes":["untouched"]}

func place(s:Dictionary,token:String,cell:Vector2i) -> void:
	var person:Dictionary=s.players[token]
	person["x"]=float(cell.x)+0.5
	person["y"]=float(cell.y)+0.5

func bare_refuse(s:Dictionary,token:String,action:String,p:Vector2i,extra:String,in_jg:bool,message:String,label:String) -> void:
	var before:=var_to_bytes(s)
	var copy:Dictionary=s.duplicate(true)
	var r:Dictionary=Route.apply(s,token,action,p,extra,in_jg)
	expect(r.get("ok")==false and str(r.get("message",""))==message,"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(s)==before and s==copy,"%s: state byte-identical"%label)

## Applies `extra` at the cart's current cell (the person must already stand there).
func bare_ok(s:Dictionary,token:String,extra:String,message:String,label:String) -> bool:
	var cell:=Route.cart_cell(Route.stage(s,token))
	var r:Dictionary=Route.apply(s,token,Route.ACTION,cell,extra,true)
	return expect(r.get("ok")==true and str(r.get("message",""))==message,"%s: ok with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func jg(w:World,token:String,at:Vector2) -> void:
	put(w,token,at,Route.REGION)

func act(w:World,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return w.act(token,"orecart-req-%d"%serial,action,p,extra)

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

func spot_for(cell:Vector2i) -> Vector2:
	if use_beside and beside.has(cell):return beside[cell]
	return center(cell)

## Walks (teleports) `token` to the cart and applies `step` there. When the previous spot is out
## of reach, first proves the step is refused with TOO_FAR. Returns the result plus "probed".
func step_on(target:Variant,token:String,step:String,label:String) -> Dictionary:
	var s:=state_of(target)
	var cell:=Route.cart_cell(Route.stage(s,token))
	var person:=person_of(s,token)
	var here:=Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))
	var probed:=false
	if here.distance_to(center(cell))>Route.REACH:
		probed=true
		if target is Dictionary:bare_refuse(target,token,Route.ACTION,cell,step,true,Route.TOO_FAR,"%s: %s before walking to the cart"%[label,step])
		else:refuse(target,token,Route.ACTION,cell,step,Route.TOO_FAR,"%s: %s before walking to the cart"%[label,step])
	var spot:=spot_for(cell)
	var r:Dictionary
	if target is Dictionary:
		var d:Dictionary=target
		d.players[token]["x"]=spot.x
		d.players[token]["y"]=spot.y
		r=Route.apply(d,token,Route.ACTION,cell,step,true)
	else:
		var w:World=target
		jg(w,token,spot)
		r=act(w,token,Route.ACTION,cell,step)
	var out:Dictionary=r.duplicate()
	out["probed"]=probed
	return out

func expected_label(at_stage:int,done:int) -> String:
	if at_stage==0:return Route.LABEL_FULL if done>=2 else Route.LABEL_IDLE
	if at_stage==7:return Route.LABEL_END
	return Route.LABEL_PUSH%(at_stage-1)

## Plays `steps` of one cart from an empty cart (8 = load + 6 pushes + unload), checking the exact
## message, the record, the views, the coins and the inventory after every step. Returns the
## number of TOO_FAR walk probes made.
func cart(target:Variant,token:String,label:String,steps:int=8) -> int:
	var s:=state_of(target)
	var now:int=Route.today(s)
	var start:Dictionary=Route.fresh_record()
	var found:Variant=rec(s,token)
	if found is Dictionary:start=(found as Dictionary).duplicate()
	expect(int(start.stage)==0,"%s: premise empty cart at the load platform"%label)
	var done:int=int(start.count) if int(start.day)==now else 0
	var bag:Variant=canon(bag_of(s,token))
	var coins0:=coins_of(s,token)
	var probes:=0
	for i in mini(steps,7):
		var step:String="load" if i==0 else "push"
		var want:String=Route.LOAD_OK if i==0 else (Route.PUSH_LAST if i==6 else Route.PUSH_OK%[i,6-i])
		var r:=step_on(target,token,step,"%s #%d"%[label,i])
		if bool(r.probed):probes+=1
		s=state_of(target)
		expect(r.get("ok")==true and str(r.get("message",""))==want,"%s: %s #%d ok with '%s' (got '%s')"%[label,step,i,want,str(r.get("message",""))])
		record_is(s,token,{"stage":i+1,"day":int(start.day),"count":int(start.count),"total":int(start.total)},"%s after %s #%d"%[label,step,i])
		expect(coins_of(s,token)==coins0 and same(bag_of(s,token),bag),"%s: coins and inventory untouched after %s #%d"%[label,step,i])
		var nxt:String="unload" if i+1==7 else "push"
		expect(Route.stage(s,token)==i+1 and Route.next_step(s,token)==nxt and Route.count_today(s,token)==done and Route.total(s,token)==int(start.total),"%s: views after %s #%d"%[label,step,i])
		expect(Route.cart_label(s,token)==expected_label(i+1,done) and Route.stage_text(Route.stage(s,token))==Route.stage_text(i+1),"%s: label after %s #%d"%[label,step,i])
	if steps<8:return probes
	var r2:=step_on(target,token,"unload","%s unload"%label)
	if bool(r2.probed):probes+=1
	s=state_of(target)
	var msg:=Route.UNLOAD_OK%[Route.PAY,mini(done+1,Route.DAILY)]
	expect(r2.get("ok")==true and str(r2.get("message",""))==msg,"%s: unload ok with '%s' (got '%s')"%[label,msg,str(r2.get("message",""))])
	record_is(s,token,rec4(0,now,mini(done+1,Route.DAILY),int(start.total)+1),"%s after unload"%label)
	expect(coins_of(s,token)==coins0+Route.PAY,"%s: exactly +%d coins at the unload (%d -> %d)"%[label,Route.PAY,coins0,coins_of(s,token)])
	expect(typeof(person_of(s,token).get("coins"))==TYPE_INT,"%s: coins stay an int"%label)
	expect(same(bag_of(s,token),bag),"%s: inventory untouched by the unload"%label)
	expect(Route.stage(s,token)==0 and Route.next_step(s,token)=="load" and Route.count_today(s,token)==mini(done+1,Route.DAILY) and Route.total(s,token)==int(start.total)+1,"%s: views after unload"%label)
	expect(Route.cart_cell(Route.stage(s,token))==Route.STOPS[0],"%s: empty cart is back at the load platform"%label)
	return probes

## Hand-written expectation table of step_block (count 0 today, purse not full).
func row(at_stage:int) -> Dictionary:
	match at_stage:
		0:return {"load":"","push":Route.NEED_LOAD,"unload":Route.NEED_LOAD}
		1,2,3,4,5,6:return {"load":Route.LOADED,"push":"","unload":Route.NOT_THERE}
		7:return {"load":Route.LOADED,"push":Route.AT_END,"unload":""}
	return {}

func expected_block(at_stage:int,step:String,done:int,full:bool) -> String:
	if at_stage==0 and step=="load" and done>=2:return Route.DAILY_DONE
	if at_stage==7 and step=="unload" and full:return Route.PURSE_FULL
	return str(row(at_stage)[step])

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(day_len>0.0 and Weather.day_index(day_len)==1.0 and Weather.day_index(day_len-0.5)==0.0 and Weather.day_index(0.0)==0.0,"premise: Weather day length %s"%str(day_len))
	expect(Route.ACTIONS==["ore_cart"] and Route.ACTION=="ore_cart","action name")
	expect(Route.STATE_KEY=="ore_route" and Route.OWN_KEY=="own_ore_route","state / snapshot keys")
	expect(Route.REGION=="jinguashi" and Route.REGION==World.REGIONS.JINGUASHI,"region is Jinguashi")
	expect(World.ORE_ROUTE==Route,"World.ORE_ROUTE is ore_route.gd")
	expect(is_equal_approx(Route.REACH,2.0) and Route.DAILY==2 and Route.PAY==12 and Route.LIMIT==1000000000,"reach / daily / pay / limit")
	expect(Route.STEP_IDS==["load","push","unload"],"step ids")
	expect(Route.RECORD_KEYS==["count","day","stage","total"],"record keys sorted")
	expect(Route.DISCLAIMER.contains("非史料") and Route.DISCLAIMER.contains("遊戲設計"),"disclaimer")
	for text:String in [Route.TITLE,Route.LOAD_NAME,Route.UNLOAD_NAME,Route.CART_NAME,Route.BLURB,Route.HOW]:
		expect(not text.is_empty(),"text non-empty: %s"%text.left(12))
	expect(Route.ACTION.length()<=24,"action fits the transport")
	for step:String in Route.STEP_IDS:
		expect(not str(Route.STEP_NAMES.get(step,"")).is_empty(),"step name for %s"%step)
		expect(Session.extra_allowed(Route.ACTION,step),"Session allows extra %s"%step)
	var others:Array=World.GOLD_PANNING.ACTIONS+World.JINGUASHI_REVISIT.ACTIONS+World.BOBO_WORKSHOP.ACTIONS+World.LANYANG_REVISIT.ACTIONS+World.TEA_REVISIT.ACTIONS+["pick","mine_copper","quarry","fish","build","travel","transit","gold_pan"]
	expect(not Route.ACTION in others,"ore_cart does not collide with existing actions")
	# Geometry: STOPS / TRACK.
	expect(Route.STOPS.size()==7 and Route.PUSHES==Route.STOPS.size()-1 and Route.LAST==Route.STOPS.size(),"PUSHES==STOPS.size()-1, LAST==STOPS.size()")
	expect(Route.TRACK.size()==23,"23 track cells (got %d)"%Route.TRACK.size())
	var seen:={}
	for cell:Vector2i in Route.TRACK:
		expect(not seen.has(cell),"track cell %s not duplicated"%str(cell))
		seen[cell]=true
	for i in range(1,Route.TRACK.size()):
		var a:Vector2i=Route.TRACK[i-1]
		var b:Vector2i=Route.TRACK[i]
		expect(absi(a.x-b.x)+absi(a.y-b.y)==1,"track %d->%d is one orthogonal step (%s -> %s)"%[i-1,i,str(a),str(b)])
	var stop_seen:={}
	var last_index:=-1
	for i in Route.STOPS.size():
		var stop:Vector2i=Route.STOPS[i]
		expect(not stop_seen.has(stop),"stop %d not duplicated"%i)
		stop_seen[stop]=true
		var index:=Route.TRACK.find(stop)
		expect(index>last_index,"stop %d %s is on the track after stop %d (index %d)"%[i,str(stop),i-1,index])
		last_index=index
	expect(Route.STOPS[0]==Route.TRACK[0] and Route.STOPS[Route.STOPS.size()-1]==Route.TRACK[Route.TRACK.size()-1],"track starts at the load platform and ends at the unload platform")
	for i in range(1,Route.STOPS.size()):
		expect(center(Route.STOPS[i-1]).distance_to(center(Route.STOPS[i]))>Route.REACH,"stop %d is out of reach from stop %d (you have to walk)"%[i,i-1])
	expect(not Route.TRACK.has(World.GOLD_PANNING.SITE),"track does not cross the gold-panning site")
	expect(center(Route.STOPS[0])==LOAD_STAND,"premise: LOAD_STAND is the load platform centre")
	# Literal message formats.
	expect(Route.PUSH_OK%[1,5]=="台車往前推了一段（第 1／6 段，還剩 5 段）。" and Route.PUSH_OK%[5,1]=="台車往前推了一段（第 5／6 段，還剩 1 段）。","PUSH_OK format")
	expect(Route.UNLOAD_OK%[12,1]=="礦料卸到接駁站了，領到運礦工資 12 鈴幣（今天第 1／2 車）。空車由礦場的人推回坑口。","UNLOAD_OK format (1)")
	expect(Route.UNLOAD_OK%[12,2]=="礦料卸到接駁站了，領到運礦工資 12 鈴幣（今天第 2／2 車）。空車由礦場的人推回坑口。","UNLOAD_OK format (2)")
	expect(Route.DAILY_DONE.contains("2") and Route.LABEL_FULL.contains("2"),"DAILY_DONE / LABEL_FULL name the daily limit")
	expect(Route.LOAD_OK.contains("六段"),"LOAD_OK names the six segments")
	var messages:=[Route.NO_PLAYER,Route.WRONG_REGION,Route.BAD_EXTRA,Route.WRONG_CELL,Route.TOO_FAR,Route.LOADED,Route.DAILY_DONE,Route.NEED_LOAD,Route.AT_END,Route.NOT_THERE,Route.PURSE_FULL,Route.LOAD_OK,Route.PUSH_OK,Route.PUSH_LAST,Route.UNLOAD_OK]
	var distinct:={}
	for m:String in messages:
		expect(not m.is_empty(),"message non-empty: %s"%m)
		distinct[m]=true
	expect(distinct.size()==messages.size(),"all %d messages distinct"%messages.size())
	var labels:={Route.LABEL_IDLE:true,Route.LABEL_FULL:true,Route.LABEL_PUSH:true,Route.LABEL_END:true,Route.STAGE_IDLE:true,Route.STAGE_MOVING:true,Route.STAGE_END:true}
	expect(labels.size()==7,"labels / stage texts distinct")
	# fresh_record
	var a:Dictionary=Route.fresh_record()
	expect(same(a,rec4(0,0,0,0)) and all_int(a) and a.size()==4,"fresh_record")
	a["stage"]=4
	expect(int(Route.fresh_record().stage)==0,"fresh_record returns a new dictionary each time")
	# today
	expect(Route.today({})==1 and Route.today({"time":0.0})==1 and Route.today({"time":day_len-0.001})==1,"today: day 1")
	expect(Route.today({"time":day_len})==2 and Route.today({"time":time_on(9)})==9,"today: later days")
	expect(Route.today({"time":"abc"})==1 and Route.today({"time":-50.0})==1 and Route.today({"time":[1]})==1,"today: garbage time is day 1")

# --------------------------------------------------------------- pure tables --

func check_pure_tables() -> void:
	# step_at
	var steps:={-99:"load",-1:"load",0:"load",1:"push",2:"push",3:"push",4:"push",5:"push",6:"push",7:"unload",8:"unload",99:"unload"}
	for at:int in steps:
		expect(Route.step_at(at)==str(steps[at]),"step_at(%d)=='%s' (got '%s')"%[at,str(steps[at]),Route.step_at(at)])
	# cart_cell
	var cells:={-5:Vector2i(31,20),0:Vector2i(31,20),1:Vector2i(31,20),2:Vector2i(28,21),3:Vector2i(26,23),4:Vector2i(23,23),
		5:Vector2i(20,23),6:Vector2i(16,23),7:Vector2i(14,21),8:Vector2i(14,21),100:Vector2i(14,21)}
	for at:int in cells:
		expect(Route.cart_cell(at)==cells[at],"cart_cell(%d)==%s (got %s)"%[at,str(cells[at]),str(Route.cart_cell(at))])
	# pushes_left
	var left:={-3:6,0:6,1:6,2:5,3:4,4:3,5:2,6:1,7:0,8:0,99:0}
	for at:int in left:
		expect(Route.pushes_left(at)==int(left[at]),"pushes_left(%d)==%d (got %d)"%[at,int(left[at]),Route.pushes_left(at)])
	# stage_text
	var texts:={
		-1:"空台車停在坑口的裝礦台。",
		0:"空台車停在坑口的裝礦台。",
		1:"裝好的台車停在軌道上（已推 0／6 段）。",
		2:"裝好的台車停在軌道上（已推 1／6 段）。",
		3:"裝好的台車停在軌道上（已推 2／6 段）。",
		4:"裝好的台車停在軌道上（已推 3／6 段）。",
		5:"裝好的台車停在軌道上（已推 4／6 段）。",
		6:"裝好的台車停在軌道上（已推 5／6 段）。",
		7:"台車停在接駁站的卸礦台，等著卸礦。",
		8:"台車停在接駁站的卸礦台，等著卸礦。",
		50:"台車停在接駁站的卸礦台，等著卸礦。",
	}
	for at:int in texts:
		expect(Route.stage_text(at)==str(texts[at]),"stage_text(%d) (got '%s')"%[at,Route.stage_text(at)])
	var distinct:={}
	for at in 8:distinct[Route.stage_text(at)]=true
	expect(distinct.size()==8,"eight distinct stage texts")
	expect(Route.LABEL_PUSH%0=="運礦台車・往前推（已推 0／6 段）" and Route.LABEL_PUSH%5=="運礦台車・往前推（已推 5／6 段）","LABEL_PUSH format")

# ------------------------------------------------------------------- views --

func expect_view(snap:Dictionary,token:String,want:Array,label:String) -> void:
	var before:=var_to_bytes(snap)
	var v:Dictionary=Route.view(snap,token)
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==["count","stage","total"] and typeof(v.get("stage"))==TYPE_INT and typeof(v.get("count"))==TYPE_INT and typeof(v.get("total"))==TYPE_INT
		and int(v.stage)==int(want[0]) and int(v.count)==int(want[1]) and int(v.total)==int(want[2]),"%s: view %s (got %s)"%[label,str(want),str(v)])
	expect(Route.stage(snap,token)==int(want[0]) and Route.count_today(snap,token)==int(want[1]) and Route.total(snap,token)==int(want[2]),"%s: stage/count_today/total"%label)
	expect(Route.next_step(snap,token)==Route.step_at(int(want[0])),"%s: next_step"%label)
	expect(var_to_bytes(snap)==before,"%s: view leaves the snapshot untouched"%label)

func check_views() -> void:
	expect_view({},"",[0,0,0],"empty dict, no token")
	expect_view({},ALPHA,[0,0,0],"empty dict, token")
	expect_view({"time":time_on(3)},ALPHA,[0,0,0],"no record key, token")
	# Server state with tokens.
	var s:={"time":time_on(4),"players":{ALPHA:{},BETA:{}},Route.STATE_KEY:{"players":{ALPHA:rec4(3,4,2,9),BETA:rec4(7,2,2,3)}}}
	expect_view(s,ALPHA,[3,2,9],"server: alpha today")
	expect_view(s,BETA,[7,0,3],"server: beta's count is from day 2, reads 0 today")
	expect_view(s,STRANGER,[0,0,0],"server: unknown token")
	expect_view(s,"",[0,0,0],"server state without token ignores records")
	s["time"]=time_on(5)
	expect_view(s,ALPHA,[3,0,9],"server: next day the count resets, stage and total stay")
	s["time"]=time_on(4)+day_len-31.0
	expect(Route.today(s)==4,"premise: last second of day 4")
	expect_view(s,ALPHA,[3,2,9],"server: last second of day 4 still counts")
	s["time"]=time_on(2)
	expect_view(s,BETA,[7,2,3],"server: beta on day 2")
	# Client snapshots.
	expect_view({"time":0.0,Route.OWN_KEY:{"stage":3,"count":2,"total":9}},"",[3,2,9],"client snapshot")
	expect_view({"time":0.0,Route.OWN_KEY:{"stage":3,"count":2,"total":9}},ALPHA,[0,0,0],"client snapshot read with a token has no server record")
	expect_view({Route.OWN_KEY:{"stage":9,"count":7,"total":-4}},"",[7,2,0],"client snapshot clamps high / negative total")
	expect_view({Route.OWN_KEY:{"stage":-2,"count":-1,"total":5}},"",[0,0,5],"client snapshot clamps low")
	expect_view({Route.OWN_KEY:{"stage":7.0,"count":1.0,"total":4.0}},"",[7,1,4],"client snapshot JSON floats")
	expect_view({Route.OWN_KEY:{"stage":2.7,"count":1.2,"total":4.9}},"",[2,1,4],"client snapshot fractional floats truncate")
	expect_view({Route.OWN_KEY:{"stage":NAN,"count":INF,"total":"3"}},"",[0,0,0],"client snapshot NaN / INF / text")
	expect_view({Route.OWN_KEY:{"stage":true,"count":[1],"total":{"a":1}}},"",[0,0,0],"client snapshot bool / list / dict values")
	expect_view({Route.OWN_KEY:{"stage":1.0e30,"count":2,"total":1.0e30}},"",[7,2,Route.LIMIT],"client snapshot huge numbers clamp")
	expect_view({Route.OWN_KEY:{}},"",[0,0,0],"client snapshot empty own record")
	expect_view({Route.OWN_KEY:{"stage":4}},"",[4,0,0],"client snapshot partial own record")
	for junk:Variant in [[],"x",3,null,1.5]:
		expect_view({Route.OWN_KEY:junk},"",[0,0,0],"client snapshot own record is %s"%str(junk))
	expect_view({Route.STATE_KEY:{"players":{ALPHA:rec4(3,1,1,1)}},Route.OWN_KEY:{"stage":1,"count":0,"total":0}},"",[1,0,0],"no token reads own_ore_route, not the server map")
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
		"stage 8":{"players":{ALPHA:rec4(8,0,0,0)}},
		"stage -1":{"players":{ALPHA:rec4(-1,0,0,0)}},
		"stage 1.5":{"players":{ALPHA:{"stage":1.5,"day":0,"count":0,"total":0}}},
		"count 3":{"players":{ALPHA:rec4(0,1,3,3)}},
		"total -1":{"players":{ALPHA:rec4(0,0,0,-1)}},
		"day 1.5":{"players":{ALPHA:{"stage":0,"day":1.5,"count":1,"total":1}}},
		"stage is bool":{"players":{ALPHA:{"stage":true,"day":0,"count":0,"total":0}}},
		"stage NaN":{"players":{ALPHA:{"stage":NAN,"day":0,"count":0,"total":0}}},
	}
	for label:String in junk_records:
		expect_view({"time":time_on(1),"players":{ALPHA:{}},Route.STATE_KEY:junk_records[label]},ALPHA,[0,0,0],"server garbage: "+label)
	expect_view({"time":"abc",Route.STATE_KEY:{"players":{ALPHA:rec4(2,1,2,5)}}},ALPHA,[2,2,5],"garbage time reads as day 1")
	expect_view({"time":time_on(1),Route.STATE_KEY:{"players":{ALPHA:{"stage":7.0,"day":1.0,"count":2.0,"total":5.0}}}},ALPHA,[7,2,5],"server record with JSON floats")

# -------------------------------------------------------------- cart_label --

func check_cart_label() -> void:
	var t:=time_on(6)
	for at in 8:
		for done in 3:
			var want:=expected_label(at,done)
			var server:={"time":t,"players":{ALPHA:{}},Route.STATE_KEY:{"players":{ALPHA:rec4(at,6 if done>0 else 0,done,done)}}}
			var client:={"time":t,Route.OWN_KEY:{"stage":at,"count":done,"total":done}}
			expect(Route.cart_label(server,ALPHA)==want,"cart_label server stage %d, %d today: '%s' (got '%s')"%[at,done,want,Route.cart_label(server,ALPHA)])
			expect(Route.cart_label(client)==want,"cart_label client stage %d, %d today: '%s' (got '%s')"%[at,done,want,Route.cart_label(client)])
	var yesterday:={"time":t,Route.STATE_KEY:{"players":{ALPHA:rec4(0,5,2,2)}}}
	expect(Route.cart_label(yesterday,ALPHA)==Route.LABEL_IDLE,"cart_label: yesterday's two carts read as idle today")
	expect(Route.cart_label({})==Route.LABEL_IDLE and Route.cart_label({},ALPHA)==Route.LABEL_IDLE,"cart_label on an empty snapshot")
	expect(Route.cart_label({Route.OWN_KEY:"junk"})==Route.LABEL_IDLE,"cart_label with a junk own record")
	expect(Route.cart_label({Route.OWN_KEY:{"stage":99,"count":9}})==Route.LABEL_END,"cart_label clamps a huge stage to the unload platform")

# -------------------------------------------------------------- step_block --

func check_step_block() -> void:
	var t:=time_on(7)
	for at in 8:
		for done in 3:
			for full:bool in [false,true]:
				var server:={"time":t,"players":{ALPHA:{}},Route.STATE_KEY:{"players":{ALPHA:rec4(at,7 if done>0 else 0,done,done)}}}
				var client:={"time":t,Route.OWN_KEY:{"stage":at,"count":done,"total":done}}
				var person:Dictionary={"coins":Route.LIMIT-Route.PAY+1} if full else {"coins":Route.LIMIT-Route.PAY}
				for step:String in Route.STEP_IDS:
					var want:=expected_block(at,step,done,full)
					var tag:="stage %d, %s, %d today, purse %s"%[at,step,done,"full" if full else "ok"]
					var got_server:=Route.step_block(server,step,person,ALPHA)
					var got_client:=Route.step_block(client,step,person)
					expect(got_server==want,"step_block server (%s): '%s' (got '%s')"%[tag,want,got_server])
					expect(got_client==want,"step_block client (%s): '%s' (got '%s')"%[tag,want,got_client])
	# Yesterday's two carts do not block today.
	var yesterday:={"time":t,Route.STATE_KEY:{"players":{ALPHA:rec4(0,6,2,2)}}}
	expect(Route.step_block(yesterday,"load",{},ALPHA)=="","step_block: yesterday's 2 carts do not block today's load")
	var today_two:={"time":t,Route.STATE_KEY:{"players":{ALPHA:rec4(0,7,2,2)}}}
	expect(Route.step_block(today_two,"load",{},ALPHA)==Route.DAILY_DONE,"step_block: today's 2 carts block")
	var one:={"time":t,Route.STATE_KEY:{"players":{ALPHA:rec4(0,7,1,9)}}}
	expect(Route.step_block(one,"load",{},ALPHA)=="","step_block: 1 cart today still allows a load")
	var ready:={"time":t,Route.STATE_KEY:{"players":{ALPHA:rec4(7,0,0,0)}}}
	for person:Variant in [null,[],"x",{},{"wood":3},{"coins":"abc"},{"coins":0},{"coins":Route.LIMIT-Route.PAY},{"coins":float(Route.LIMIT-Route.PAY)},{"coins":NAN},{"coins":-5}]:
		expect(Route.step_block(ready,"unload",person,ALPHA)=="","step_block: unload with person %s is allowed"%str(person))
	for person:Variant in [{"coins":Route.LIMIT-Route.PAY+1},{"coins":Route.LIMIT},{"coins":float(Route.LIMIT)},{"coins":Route.LIMIT+5},{"coins":1.0e20}]:
		expect(Route.step_block(ready,"unload",person,ALPHA)==Route.PURSE_FULL,"step_block: unload with person %s is PURSE_FULL"%str(person))
	var mid:={"time":t,Route.STATE_KEY:{"players":{ALPHA:rec4(4,0,0,0)}}}
	expect(Route.step_block(mid,"unload",{"coins":Route.LIMIT},ALPHA)==Route.NOT_THERE,"step_block: NOT_THERE beats PURSE_FULL")
	expect(Route.step_block({},"unload",{"coins":Route.LIMIT})==Route.NEED_LOAD,"step_block: NEED_LOAD beats PURSE_FULL")
	for bad:String in ["","dig","LOAD","push ","unload,unload","load:1","ore_cart"]:
		expect(Route.step_block(ready,bad,{},ALPHA)==Route.BAD_EXTRA,"step_block: unknown step '%s' (server)"%bad)
		expect(Route.step_block({},bad,{"coins":Route.LIMIT})==Route.BAD_EXTRA,"step_block: unknown step '%s' (empty)"%bad)
	expect(Route.step_block({},"load",{})=="" and Route.step_block({},"push",{})==Route.NEED_LOAD,"step_block on an empty snapshot")

# ------------------------------------------------------------ apply order --

func check_apply_order() -> void:
	var s:=bare()
	for action:String in ["pick","gold_pan","","ORE_CART","ore_cart ","ore_route","load","push"]:
		bare_refuse(s,ALPHA,action,Route.STOPS[0],"load",true,Route.BAD_EXTRA,"foreign action '%s'"%action)
	bare_refuse(s,STRANGER,"pick",Route.STOPS[0],"load",false,Route.BAD_EXTRA,"foreign action beats unknown player and wrong region")
	bare_refuse(s,STRANGER,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"unknown player")
	bare_refuse(s,"",Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"empty token")
	bare_refuse(s,STRANGER,Route.ACTION,Vector2i(0,0),"dig",false,Route.NO_PLAYER,"unknown player beats wrong region / bad extra / cell")
	var no_players:=bare()
	no_players.erase("players")
	bare_refuse(no_players,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"state without players")
	var list_players:=bare()
	list_players["players"]=[ALPHA]
	bare_refuse(list_players,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"players is a list")
	var string_person:=bare()
	string_person.players[ALPHA]="x"
	bare_refuse(string_person,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"person is a string")
	for step:String in Route.STEP_IDS:
		bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],step,false,Route.WRONG_REGION,"%s outside Jinguashi"%step)
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],"dig",false,Route.WRONG_REGION,"wrong region beats bad extra")
	bare_refuse(s,ALPHA,Route.ACTION,Vector2i(0,0),"load",false,Route.WRONG_REGION,"wrong region beats wrong cell")
	for bad:String in ["","Load","load ","push:1","dig","unload,unload","push\n","ore_cart"]:
		bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],bad,true,Route.BAD_EXTRA,"bad extra '%s'"%bad.c_escape())
	bare_refuse(s,ALPHA,Route.ACTION,Vector2i(0,0),"dig",true,Route.BAD_EXTRA,"bad extra beats wrong cell")
	# Malformed existing records.
	var malformed:={
		"record key is null":null,
		"record key is a list":[],
		"record key is a string":"x",
		"record key is empty":{},
		"record key has an extra key":{"players":{},"extra":1},
		"players is a list":{"players":[]},
		"players is null":{"players":null},
		"own record is a string":{"players":{ALPHA:"x"}},
		"own record is null":{"players":{ALPHA:null}},
		"own record missing keys":{"players":{ALPHA:{"stage":1}}},
		"own record extra key":{"players":{ALPHA:{"stage":1,"day":0,"count":0,"total":0,"by":"x"}}},
		"own stage 8":{"players":{ALPHA:rec4(8,0,0,0)}},
		"own stage -1":{"players":{ALPHA:rec4(-1,0,0,0)}},
		"own stage string":{"players":{ALPHA:{"stage":"1","day":0,"count":0,"total":0}}},
		"own stage 1.5":{"players":{ALPHA:{"stage":1.5,"day":0,"count":0,"total":0}}},
		# (a NaN stage is covered by the view / valid() tables: NaN != NaN breaks the s==copy compare)
		"own stage INF":{"players":{ALPHA:{"stage":INF,"day":0,"count":0,"total":0}}},
		"own count 3":{"players":{ALPHA:rec4(0,1,3,3)}},
		"own total -1":{"players":{ALPHA:rec4(0,0,0,-1)}},
		"own day 1.5":{"players":{ALPHA:{"stage":0,"day":1.5,"count":1,"total":1}}},
		"own day above LIMIT":{"players":{ALPHA:rec4(0,Route.LIMIT+1,1,1)}},
	}
	for label:String in malformed:
		var m:=bare()
		m[Route.STATE_KEY]=malformed[label]
		bare_refuse(m,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.BAD_EXTRA,"malformed: "+label)
		bare_refuse(m,ALPHA,Route.ACTION,Vector2i(0,0),"unload",true,Route.BAD_EXTRA,"malformed beats wrong cell: "+label)
		bare_refuse(m,ALPHA,Route.ACTION,Route.STOPS[0],"load",false,Route.WRONG_REGION,"wrong region beats malformed: "+label)
	# Another player's malformed record is not touched by alpha's action.
	var other:=bare()
	other[Route.STATE_KEY]={"players":{BETA:"x"}}
	var loaded:Dictionary=Route.apply(other,ALPHA,Route.ACTION,Route.STOPS[0],"load",true)
	expect(loaded.get("ok")==true,"alpha may load next to beta's malformed record")
	expect(str(rec(other,BETA))=="x" and typeof(rec(other,BETA))==TYPE_STRING,"alpha's action never rewrites beta's (malformed) record")
	# Wrong cell (cart at the load platform, stage 0).
	var wrong:=[Route.STOPS[1],Route.STOPS[6],Route.TRACK[1],Vector2i(31,19),Vector2i(32,20),Vector2i(0,0),Vector2i(-31,-20),World.GOLD_PANNING.SITE]
	for cell:Vector2i in wrong:
		bare_refuse(s,ALPHA,Route.ACTION,cell,"load",true,Route.WRONG_CELL,"wrong cell %s"%str(cell))
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[6],"unload",true,Route.WRONG_CELL,"unload at the unload platform while the cart is at the load platform")
	var far:=bare()
	far.players[ALPHA]["x"]=60.5
	bare_refuse(far,ALPHA,Route.ACTION,Route.STOPS[1],"load",true,Route.WRONG_CELL,"wrong cell beats too far")
	# The cart is elsewhere (stage 3 -> STOPS[2]): the load cell is now the wrong cell.
	var away:=bare()
	away[Route.STATE_KEY]={"players":{ALPHA:rec4(3,0,0,0)}}
	expect(Route.cart_cell(3)==Route.STOPS[2],"premise: stage 3 cart at STOPS[2]")
	bare_refuse(away,ALPHA,Route.ACTION,Route.STOPS[0],"push",true,Route.WRONG_CELL,"push at the load cell while the cart is at STOPS[2] (standing there)")
	bare_refuse(away,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.WRONG_CELL,"load at the load cell while the cart is out (WRONG_CELL beats LOADED)")
	place(away,ALPHA,Route.STOPS[6])
	bare_refuse(away,ALPHA,Route.ACTION,Route.STOPS[6],"unload",true,Route.WRONG_CELL,"unload at the unload platform while the cart is at STOPS[2]")
	bare_refuse(away,ALPHA,Route.ACTION,Route.STOPS[2],"push",true,Route.TOO_FAR,"push at the cart cell from the unload platform")
	place(away,ALPHA,Route.STOPS[2])
	bare_refuse(away,ALPHA,Route.ACTION,Route.STOPS[2],"unload",true,Route.NOT_THERE,"unload at the cart mid-route")
	bare_refuse(away,ALPHA,Route.ACTION,Route.STOPS[2],"load",true,Route.LOADED,"load at the cart mid-route")
	bare_ok(away,ALPHA,"push",Route.PUSH_OK%[3,3],"push at the cart mid-route")
	record_is(away,ALPHA,rec4(4,0,0,0),"stage 3 -> 4")
	# Reach: centre of STOPS[0] is (31.5,20.5), REACH 2.0.
	for at:Vector2 in [Vector2(33.51,20.5),Vector2(29.49,20.5),Vector2(31.5,22.51),Vector2(31.5,18.49),Vector2(32.92,21.92),Vector2(40.5,30.5)]:
		var f:=bare()
		f.players[ALPHA]["x"]=at.x
		f.players[ALPHA]["y"]=at.y
		bare_refuse(f,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.TOO_FAR,"too far at %s"%str(at))
		bare_refuse(f,ALPHA,Route.ACTION,Route.STOPS[0],"push",true,Route.TOO_FAR,"too far beats wrong order at %s"%str(at))
		f.players[ALPHA]["coins"]="abc"
		bare_refuse(f,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.TOO_FAR,"too far beats non-numeric coins at %s"%str(at))
	for at:Vector2 in [Vector2(33.49,20.5),Vector2(29.51,20.5),Vector2(31.5,22.49),Vector2(31.5,18.51),Vector2(32.9,21.9),Vector2(31.0,20.0)]:
		var n:=bare()
		n.players[ALPHA]["x"]=at.x
		n.players[ALPHA]["y"]=at.y
		bare_ok(n,ALPHA,"load",Route.LOAD_OK,"inside reach at %s"%str(at))
		record_is(n,ALPHA,rec4(1,0,0,0),"load inside reach at %s"%str(at))
	var nowhere:=bare()
	(nowhere.players[ALPHA] as Dictionary).erase("x")
	(nowhere.players[ALPHA] as Dictionary).erase("y")
	bare_refuse(nowhere,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.TOO_FAR,"person without x/y is at (0,0)")
	# Coins checked after distance, before the step rules.
	for junk:Variant in ["abc",null,[],{},true]:
		var c:=bare()
		c.players[ALPHA]["coins"]=junk
		bare_refuse(c,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"coins is %s"%str(junk))
	var no_coins:=bare()
	(no_coins.players[ALPHA] as Dictionary).erase("coins")
	bare_refuse(no_coins,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"person without coins")
	bare_refuse(no_coins,ALPHA,Route.ACTION,Route.STOPS[0],"push",true,Route.NO_PLAYER,"missing coins beats NEED_LOAD")
	no_coins[Route.STATE_KEY]={"players":{ALPHA:rec4(1,0,0,0)}}
	bare_refuse(no_coins,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"missing coins beats LOADED")
	var no_coins_full:=bare(time_on(2))
	no_coins_full.players[ALPHA]["coins"]="12"
	no_coins_full[Route.STATE_KEY]={"players":{ALPHA:rec4(0,2,2,2)}}
	bare_refuse(no_coins_full,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.NO_PLAYER,"text coins beat DAILY_DONE")
	var float_coins:=bare()
	float_coins.players[ALPHA]["coins"]=50.0
	bare_ok(float_coins,ALPHA,"load",Route.LOAD_OK,"float coins are fine for a load")
	expect(typeof(float_coins.players[ALPHA].coins)==TYPE_FLOAT,"a load does not touch the coins")
	expect(not s.has(Route.STATE_KEY),"no record is created by any refused action")
	# Wrong-order and wrong-cell messages along one cart.
	var o:=bare()
	for at in 8:
		var cell:=Route.cart_cell(at)
		place(o,ALPHA,cell)
		for step:String in Route.STEP_IDS:
			var want:=expected_block(at,step,0,false)
			if not want.is_empty():bare_refuse(o,ALPHA,Route.ACTION,cell,step,true,want,"wrong order at stage %d: %s"%[at,step])
		var next:=Route.step_at(at)
		for stop:Vector2i in Route.STOPS:
			if stop!=cell:bare_refuse(o,ALPHA,Route.ACTION,stop,next,true,Route.WRONG_CELL,"stage %d: %s at %s (cart at %s)"%[at,next,str(stop),str(cell)])
		expect(Route.step_block(o,next,person_of(o,ALPHA),ALPHA)=="","stage %d: step_block agrees %s is next"%[at,next])
		var r:Dictionary=Route.apply(o,ALPHA,Route.ACTION,cell,next,true)
		expect(r.get("ok")==true,"stage %d: %s goes through"%[at,next])
	record_is(o,ALPHA,rec4(0,1,1,1),"one cart done on day 1")
	expect(coins_of(o,ALPHA)==50+Route.PAY,"one cart paid once")

# ----------------------------------------------------------- apply matrix --

func check_apply_matrix() -> void:
	for at in 8:
		for done in 3:
			for step:String in Route.STEP_IDS:
				# stage 7 with 2 carts already done TODAY is the tampered "full today plus a cart
				# on the way" record; it is asserted here (count stays at DAILY) and again below.
				var s:=bare(time_on(7))
				var start:=rec4(at,7 if done>0 else 0,done,done)
				s[Route.STATE_KEY]={"players":{ALPHA:start.duplicate()}}
				place(s,ALPHA,Route.cart_cell(at))
				var want:=expected_block(at,step,done,false)
				var tag:="apply matrix stage %d, %s, %d today"%[at,step,done]
				if not want.is_empty():
					bare_refuse(s,ALPHA,Route.ACTION,Route.cart_cell(at),step,true,want,tag)
					continue
				var r:Dictionary=Route.apply(s,ALPHA,Route.ACTION,Route.cart_cell(at),step,true)
				var after:Dictionary=start.duplicate()
				var msg:=""
				match step:
					"load":
						after.stage=1
						msg=Route.LOAD_OK
					"push":
						after.stage=at+1
						msg=Route.PUSH_LAST if at==6 else Route.PUSH_OK%[at,6-at]
					"unload":
						after.stage=0
						after.day=7
						after.count=mini(done+1,Route.DAILY)
						after.total=done+1
						msg=Route.UNLOAD_OK%[Route.PAY,mini(done+1,Route.DAILY)]
				expect(r.get("ok")==true and str(r.get("message",""))==msg,"%s: ok with '%s' (got '%s')"%[tag,msg,str(r.get("message",""))])
				record_is(s,ALPHA,after,tag)
				expect(coins_of(s,ALPHA)==(50+Route.PAY if step=="unload" else 50),"%s: coins only from an unload"%tag)
				expect(same(bag_of(s,ALPHA),{"wood":2}),"%s: inventory untouched"%tag)
				expect(rec(s,BETA)==null and coins_of(s,BETA)==0,"%s: beta untouched"%tag)
	# PURSE_FULL in apply.
	var full:=bare(time_on(2))
	full[Route.STATE_KEY]={"players":{ALPHA:rec4(7,1,2,6)}}
	place(full,ALPHA,Route.STOPS[6])
	full.players[ALPHA]["coins"]=Route.LIMIT-Route.PAY+1
	bare_refuse(full,ALPHA,Route.ACTION,Route.STOPS[6],"unload",true,Route.PURSE_FULL,"unload with coins LIMIT-PAY+1")
	full.players[ALPHA]["coins"]=Route.LIMIT
	bare_refuse(full,ALPHA,Route.ACTION,Route.STOPS[6],"unload",true,Route.PURSE_FULL,"unload with coins at LIMIT")
	record_is(full,ALPHA,rec4(7,1,2,6),"PURSE_FULL leaves the cart at the unload platform")
	full.players[ALPHA]["coins"]=Route.LIMIT-Route.PAY
	bare_ok(full,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"unload with coins LIMIT-PAY")
	expect(coins_of(full,ALPHA)==Route.LIMIT,"coins reach LIMIT exactly")
	record_is(full,ALPHA,rec4(0,2,1,7),"unload after PURSE_FULL counts for today")
	place(full,ALPHA,Route.STOPS[0])
	bare_ok(full,ALPHA,"load",Route.LOAD_OK,"a full purse still allows loading (only the unload checks the purse)")
	# Float coins become an int at the unload.
	var fl:=bare(time_on(2))
	fl[Route.STATE_KEY]={"players":{ALPHA:rec4(7,0,0,0)}}
	place(fl,ALPHA,Route.STOPS[6])
	fl.players[ALPHA]["coins"]=50.0
	bare_ok(fl,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"unload with float coins")
	expect(typeof(fl.players[ALPHA].coins)==TYPE_INT and int(fl.players[ALPHA].coins)==62,"float coins normalised to int 62")
	# total at LIMIT stays at LIMIT.
	var cap:=bare(time_on(3))
	cap[Route.STATE_KEY]={"players":{ALPHA:rec4(7,2,1,Route.LIMIT)}}
	place(cap,ALPHA,Route.STOPS[6])
	bare_ok(cap,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"unload with total at LIMIT")
	record_is(cap,ALPHA,rec4(0,3,1,Route.LIMIT),"total capped at LIMIT")

# -------------------------------------------------------------- full carts --

func check_full_carts() -> void:
	var s:=bare(time_on(3))
	expect(Route.today(s)==3,"premise: day 3")
	expect(not s.has(Route.STATE_KEY),"no record before the first load")
	var before_load:=var_to_bytes(s)
	var probes:=cart(s,ALPHA,"day 3 cart 1 (load only)",1)
	expect(probes==0,"load from the platform needs no walk")
	expect(var_to_bytes(s)!=before_load and s.has(Route.STATE_KEY),"first successful load writes the record")
	record_is(s,ALPHA,rec4(1,0,0,0),"first load record")
	expect(not rec(s,BETA) is Dictionary,"only alpha's record is written")
	expect((s[Route.STATE_KEY] as Dictionary).size()==1 and ((s[Route.STATE_KEY] as Dictionary).players as Dictionary).size()==1,"record shape {players:{alpha}}")
	# Finish cart 1 by hand, exact messages.
	var plan:=[[Route.PUSH_OK%[1,5],2],[Route.PUSH_OK%[2,4],3],[Route.PUSH_OK%[3,3],4],[Route.PUSH_OK%[4,2],5],[Route.PUSH_OK%[5,1],6],[Route.PUSH_LAST,7]]
	for i in plan.size():
		place(s,ALPHA,Route.cart_cell(Route.stage(s,ALPHA)))
		bare_ok(s,ALPHA,"push",str(plan[i][0]),"day 3 cart 1 push %d"%(i+1))
		record_is(s,ALPHA,rec4(int(plan[i][1]),0,0,0),"day 3 cart 1 push %d"%(i+1))
		expect(Route.pushes_left(Route.stage(s,ALPHA))==5-i,"pushes_left after push %d"%(i+1))
	expect(coins_of(s,ALPHA)==50,"no pay before the unload")
	place(s,ALPHA,Route.STOPS[6])
	bare_ok(s,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"day 3 cart 1 unload")
	record_is(s,ALPHA,rec4(0,3,1,1),"day 3 cart 1 done")
	expect(coins_of(s,ALPHA)==50+Route.PAY and same(bag_of(s,ALPHA),{"wood":2}),"+12 coins, inventory untouched")
	# Cart 2 (helper walks from the unload platform back to the load platform).
	place(s,ALPHA,Route.STOPS[0])
	probes=cart(s,ALPHA,"day 3 cart 2")
	expect(probes==6,"cart 2: every push after the first and the unload needed a walk (got %d)"%probes)
	record_is(s,ALPHA,rec4(0,3,2,2),"day 3 cart 2 done")
	expect(coins_of(s,ALPHA)==50+2*Route.PAY and Route.count_today(s,ALPHA)==2,"24 coins, two carts today")
	expect(Route.cart_label(s,ALPHA)==Route.LABEL_FULL,"label shows the daily limit")
	place(s,ALPHA,Route.STOPS[0])
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.DAILY_DONE,"third load on day 3")
	for step:String in ["push","unload"]:bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],step,true,Route.NEED_LOAD,"after the daily limit: %s"%step)
	s["time"]=time_on(3)+day_len-31.0
	expect(Route.today(s)==3,"premise: last second of day 3")
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.DAILY_DONE,"third load at the end of day 3")
	# Next world day.
	s["time"]=time_on(4)
	expect(Route.today(s)==4 and Route.count_today(s,ALPHA)==0 and Route.total(s,ALPHA)==2,"day 4: count reads 0, total 2")
	expect(Route.cart_label(s,ALPHA)==Route.LABEL_IDLE,"day 4: label idle again")
	bare_ok(s,ALPHA,"load",Route.LOAD_OK,"day 4 load")
	record_is(s,ALPHA,rec4(1,3,2,2),"day 4 load keeps day/count until the unload")
	expect(Route.count_today(s,ALPHA)==0,"day 4: still 0 delivered today")
	for i in 6:
		place(s,ALPHA,Route.cart_cell(Route.stage(s,ALPHA)))
		var r:Dictionary=Route.apply(s,ALPHA,Route.ACTION,Route.cart_cell(Route.stage(s,ALPHA)),"push",true)
		expect(r.get("ok")==true,"day 4 cart 1 push %d"%(i+1))
	place(s,ALPHA,Route.STOPS[6])
	bare_ok(s,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"day 4 cart 1 unload")
	record_is(s,ALPHA,rec4(0,4,1,3),"day 4: count restarts at 1, total continues")
	# Cart left mid-route overnight: loaded on day 4, unloaded on day 5 -> counts for day 5.
	cart(s,ALPHA,"day 4 cart 2 (left at stage 4)",4)
	record_is(s,ALPHA,rec4(4,4,1,3),"day 4 cart 2 waits at stage 4")
	s["time"]=time_on(5)
	expect(Route.count_today(s,ALPHA)==0 and Route.stage(s,ALPHA)==4 and Route.cart_cell(Route.stage(s,ALPHA))==Route.STOPS[3],"day 5: cart kept at STOPS[3], count 0")
	place(s,ALPHA,Route.STOPS[0])
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.WRONG_CELL,"day 5: the load platform is empty, the cart is out")
	place(s,ALPHA,Route.STOPS[3])
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[3],"load",true,Route.LOADED,"day 5: cannot load over yesterday's cart")
	for i in 3:
		place(s,ALPHA,Route.cart_cell(Route.stage(s,ALPHA)))
		var want:String=Route.PUSH_LAST if i==2 else Route.PUSH_OK%[4+i,2-i]
		bare_ok(s,ALPHA,"push",want,"day 5 push %d of a day-4 cart"%(i+1))
	place(s,ALPHA,Route.STOPS[6])
	bare_ok(s,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"day 5 unload of a day-4 cart")
	record_is(s,ALPHA,rec4(0,5,1,4),"day-4 cart counts as day 5's first")
	expect(coins_of(s,ALPHA)==50+4*Route.PAY,"four carts paid")
	# Skipping days.
	s["time"]=time_on(9)
	cart(s,ALPHA,"day 9 cart 1")
	record_is(s,ALPHA,rec4(0,9,1,5),"day 9 cart 1")
	cart(s,ALPHA,"day 9 cart 2")
	place(s,ALPHA,Route.STOPS[0])
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.DAILY_DONE,"day 9 third load")
	# PURSE_FULL on day 10.
	s["time"]=time_on(10)
	cart(s,ALPHA,"day 10 cart 1 (to the unload platform)",7)
	var keep:=coins_of(s,ALPHA)
	s.players[ALPHA]["coins"]=Route.LIMIT-Route.PAY+1
	place(s,ALPHA,Route.STOPS[6]) # 距離檢查在 PURSE_FULL 之前，人要先站到卸礦台旁
	bare_refuse(s,ALPHA,Route.ACTION,Route.STOPS[6],"unload",true,Route.PURSE_FULL,"day 10 unload with a full purse")
	record_is(s,ALPHA,rec4(7,9,2,6),"PURSE_FULL: stage stays 7, nothing counted")
	s.players[ALPHA]["coins"]=keep
	bare_ok(s,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"day 10 unload after spending")
	record_is(s,ALPHA,rec4(0,10,1,7),"day 10 cart 1")
	expect(coins_of(s,ALPHA)==keep+Route.PAY,"day 10: +12 coins")
	expect(same(bag_of(s,ALPHA),{"wood":2}),"alpha's inventory untouched by seven carts")
	expect(not rec(s,BETA) is Dictionary and bag_of(s,BETA).is_empty() and coins_of(s,BETA)==0,"beta untouched by alpha's carts")
	expect(str(s.get("notes"))==str(["untouched"]),"unrelated state untouched")
	# Tampered "full today plus a cart on the way": the unload pays but count stays at DAILY.
	var t:=bare(time_on(6))
	t[Route.STATE_KEY]={"players":{ALPHA:rec4(5,6,2,9)}}
	expect(Route.valid(vs_of(t)),"premise: the tampered record passes valid() (see report)")
	place(t,ALPHA,Route.STOPS[4])
	bare_ok(t,ALPHA,"push",Route.PUSH_OK%[5,1],"tampered: push 5")
	place(t,ALPHA,Route.STOPS[5])
	bare_ok(t,ALPHA,"push",Route.PUSH_LAST,"tampered: push 6")
	place(t,ALPHA,Route.STOPS[6])
	bare_ok(t,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,2],"tampered: unload reports 2/2, not 3/2")
	record_is(t,ALPHA,rec4(0,6,2,10),"tampered: count stays at DAILY, total continues")
	expect(coins_of(t,ALPHA)==50+Route.PAY,"tampered: the unload still pays")
	place(t,ALPHA,Route.STOPS[0])
	bare_refuse(t,ALPHA,Route.ACTION,Route.STOPS[0],"load",true,Route.DAILY_DONE,"tampered: next load refused")

## A copy of a bare module state shaped for valid() (players keep their tokens).
func vs_of(s:Dictionary) -> Dictionary:
	return s.duplicate(true)

# ------------------------------------------------------------- two players --

func check_two_players() -> void:
	var s:=bare(time_on(2))
	bare_ok(s,ALPHA,"load",Route.LOAD_OK,"alpha loads")
	bare_ok(s,ALPHA,"push",Route.PUSH_OK%[1,5],"alpha pushes 1")
	place(s,ALPHA,Route.STOPS[1])
	bare_ok(s,ALPHA,"push",Route.PUSH_OK%[2,4],"alpha pushes 2")
	record_is(s,ALPHA,rec4(3,0,0,0),"alpha at stage 3")
	# Beta's cart is her own: alpha's cart cell is the wrong cell for her.
	place(s,BETA,Route.STOPS[2])
	bare_refuse(s,BETA,Route.ACTION,Route.STOPS[2],"push",true,Route.WRONG_CELL,"beta cannot push alpha's cart")
	place(s,BETA,Route.STOPS[0])
	for n in 2:
		var a_rec:=var_to_bytes(rec(s,ALPHA))
		var a_person:=var_to_bytes(person_of(s,ALPHA))
		cart(s,BETA,"beta cart %d"%(n+1))
		expect(var_to_bytes(rec(s,ALPHA))==a_rec and var_to_bytes(person_of(s,ALPHA))==a_person,"beta cart %d leaves alpha's record, coins and bag alone"%(n+1))
	record_is(s,BETA,rec4(0,2,2,2),"beta's two carts")
	record_is(s,ALPHA,rec4(3,0,0,0),"alpha still at stage 3")
	expect(coins_of(s,BETA)==2*Route.PAY and coins_of(s,ALPHA)==50,"pay only to beta")
	place(s,BETA,Route.STOPS[0])
	bare_refuse(s,BETA,Route.ACTION,Route.STOPS[0],"load",true,Route.DAILY_DONE,"beta's daily limit")
	var b_rec:=var_to_bytes(rec(s,BETA))
	var b_person:=var_to_bytes(person_of(s,BETA))
	for i in 4:
		place(s,ALPHA,Route.cart_cell(Route.stage(s,ALPHA)))
		var want:String=Route.PUSH_LAST if i==3 else Route.PUSH_OK%[3+i,3-i]
		bare_ok(s,ALPHA,"push",want,"alpha continues after beta's carts, push %d"%(3+i))
	place(s,ALPHA,Route.STOPS[6])
	bare_ok(s,ALPHA,"unload",Route.UNLOAD_OK%[Route.PAY,1],"alpha's first cart counts 1, not beta's 3")
	expect(var_to_bytes(rec(s,BETA))==b_rec and var_to_bytes(person_of(s,BETA))==b_person,"alpha's steps leave beta's record, coins and bag alone")
	record_is(s,ALPHA,rec4(0,2,1,1),"alpha's record")
	expect(coins_of(s,ALPHA)==50+Route.PAY,"alpha paid once")
	var keys:Array=((s[Route.STATE_KEY] as Dictionary).players as Dictionary).keys()
	keys.sort()
	var want_keys:=[ALPHA,BETA]
	want_keys.sort()
	expect(keys==want_keys,"records keyed by token")
	expect(Route.view(s,ALPHA).count==1 and Route.view(s,BETA).count==2,"views per token")
	expect(Route.cart_label(s,ALPHA)==Route.LABEL_IDLE and Route.cart_label(s,BETA)==Route.LABEL_FULL,"labels per token")

# ------------------------------------------------------------------ valid() --

func vs(value:Variant,t:float) -> Dictionary:
	return {"time":t,"players":{ALPHA:{"name":"a"},BETA:{"name":"b"}},Route.STATE_KEY:value}

func valid_case(label:String,value:Variant,want:bool) -> void:
	var s:=vs(value,time_on(5))
	expect(Route.valid(s)==want,"valid() %s: %s"%["accepts" if want else "rejects",label])

func check_valid() -> void:
	expect(Route.valid({"time":time_on(5),"players":{ALPHA:{}}}),"valid(): absent key ok")
	expect(Route.valid({}),"valid(): empty state without the key ok")
	valid_case("no players yet",{"players":{}},true)
	valid_case("fresh record",{"players":{ALPHA:rec4(0,0,0,0)}},true)
	valid_case("first cart on the way",{"players":{ALPHA:rec4(3,0,0,0)}},true)
	valid_case("first cart at the unload platform",{"players":{ALPHA:rec4(7,0,0,0)}},true)
	valid_case("two carts today",{"players":{ALPHA:rec4(0,5,2,7)}},true)
	valid_case("cart on the way after an older day",{"players":{ALPHA:rec4(6,2,1,1)}},true)
	valid_case("both players",{"players":{ALPHA:rec4(1,4,2,2),BETA:rec4(0,1,1,1)}},true)
	valid_case("total at LIMIT",{"players":{ALPHA:rec4(0,5,2,Route.LIMIT)}},true)
	valid_case("count 1 day 1",{"players":{ALPHA:rec4(0,1,1,1)}},true)
	valid_case("count equals total",{"players":{ALPHA:rec4(2,5,2,2)}},true)
	valid_case("full today plus a cart on the way (shape-valid)",{"players":{ALPHA:rec4(5,5,2,9)}},true)
	# Rejected shapes.
	valid_case("record key null",null,false)
	valid_case("record key a list",[],false)
	valid_case("record key a string","x",false)
	valid_case("record key a number",3,false)
	valid_case("record key empty",{},false)
	valid_case("extra top-level key",{"players":{},"by":1},false)
	valid_case("extra top-level key with a good record",{"players":{ALPHA:rec4(0,1,1,1)},"day":1},false)
	valid_case("players is a list",{"players":[]},false)
	valid_case("players is null",{"players":null},false)
	valid_case("players is a string",{"players":"x"},false)
	valid_case("record is a string",{"players":{ALPHA:"x"}},false)
	valid_case("record is a list",{"players":{ALPHA:[0,0,0,0]}},false)
	valid_case("record is null",{"players":{ALPHA:null}},false)
	valid_case("record is empty",{"players":{ALPHA:{}}},false)
	valid_case("record extra key",{"players":{ALPHA:{"stage":0,"day":0,"count":0,"total":0,"x":1}}},false)
	for field:String in ["stage","day","count","total"]:
		var r:=rec4(0,1,1,1)
		r.erase(field)
		valid_case("record missing %s"%field,{"players":{ALPHA:r}},false)
		var swapped:=rec4(0,1,1,1)
		swapped.erase(field)
		swapped[field.to_upper()]=0
		valid_case("record has %s in upper case"%field,{"players":{ALPHA:swapped}},false)
	valid_case("unknown token",{"players":{STRANGER:rec4(0,1,1,1)}},false)
	valid_case("unknown token next to a good one",{"players":{ALPHA:rec4(0,1,1,1),STRANGER:rec4(0,0,0,0)}},false)
	valid_case("integer token",{"players":{5:rec4(0,1,1,1)}},false)
	valid_case("stage 8",{"players":{ALPHA:rec4(8,1,1,1)}},false)
	valid_case("stage -1",{"players":{ALPHA:rec4(-1,1,1,1)}},false)
	valid_case("day -1",{"players":{ALPHA:rec4(0,-1,1,1)}},false)
	valid_case("count -1",{"players":{ALPHA:rec4(0,1,-1,1)}},false)
	valid_case("total -1",{"players":{ALPHA:rec4(0,0,0,-1)}},false)
	valid_case("count 3 > DAILY",{"players":{ALPHA:rec4(0,5,3,3)}},false)
	valid_case("total above LIMIT",{"players":{ALPHA:rec4(0,5,2,Route.LIMIT+1)}},false)
	valid_case("stage 1.5",{"players":{ALPHA:{"stage":1.5,"day":1,"count":1,"total":1}}},false)
	valid_case("day 2.5",{"players":{ALPHA:{"stage":0,"day":2.5,"count":1,"total":1}}},false)
	valid_case("count 0.5",{"players":{ALPHA:{"stage":0,"day":1,"count":0.5,"total":1}}},false)
	valid_case("total 1.25",{"players":{ALPHA:{"stage":0,"day":1,"count":1,"total":1.25}}},false)
	valid_case("stage string",{"players":{ALPHA:{"stage":"0","day":1,"count":1,"total":1}}},false)
	valid_case("count string",{"players":{ALPHA:{"stage":0,"day":1,"count":"1","total":1}}},false)
	valid_case("stage bool",{"players":{ALPHA:{"stage":true,"day":1,"count":1,"total":1}}},false)
	valid_case("day null",{"players":{ALPHA:{"stage":0,"day":null,"count":1,"total":1}}},false)
	valid_case("stage INF",{"players":{ALPHA:{"stage":INF,"day":1,"count":1,"total":1}}},false)
	valid_case("stage NaN",{"players":{ALPHA:{"stage":NAN,"day":1,"count":1,"total":1}}},false)
	valid_case("total INF",{"players":{ALPHA:{"stage":0,"day":1,"count":1,"total":INF}}},false)
	valid_case("day in the future (today 5)",{"players":{ALPHA:rec4(0,6,1,1)}},false)
	valid_case("day far in the future",{"players":{ALPHA:rec4(0,500,1,1)}},false)
	valid_case("total 0 with day > 0",{"players":{ALPHA:rec4(0,3,0,0)}},false)
	valid_case("total 0 with day and count",{"players":{ALPHA:rec4(0,3,1,0)}},false)
	valid_case("total > 0 with day 0",{"players":{ALPHA:rec4(0,0,0,2)}},false)
	valid_case("total > 0 with day 0 and a count",{"players":{ALPHA:rec4(0,0,1,2)}},false)
	valid_case("total > 0 with count 0",{"players":{ALPHA:rec4(0,3,0,2)}},false)
	valid_case("count > total",{"players":{ALPHA:rec4(0,3,2,1)}},false)
	valid_case("good alpha, bad beta",{"players":{ALPHA:rec4(0,1,1,1),BETA:rec4(9,0,0,0)}},false)
	var bad_players:=vs({"players":{ALPHA:rec4(0,1,1,1)}},time_on(5))
	bad_players["players"]=[ALPHA]
	expect(not Route.valid(bad_players),"valid() rejects: state.players is a list")
	var no_players:=vs({"players":{ALPHA:rec4(0,1,1,1)}},time_on(5))
	no_players.erase("players")
	expect(not Route.valid(no_players),"valid() rejects: state.players missing")
	# No time: today is day 1.
	expect(Route.valid({"players":{ALPHA:{}},Route.STATE_KEY:{"players":{ALPHA:rec4(0,1,1,1)}}}),"valid() without time: day 1 ok")
	expect(not Route.valid({"players":{ALPHA:{}},Route.STATE_KEY:{"players":{ALPHA:rec4(0,2,1,1)}}}),"valid() without time: day 2 is the future")
	# JSON floats normalised on success.
	var floats:=vs({"players":{ALPHA:{"stage":7.0,"day":4.0,"count":2.0,"total":5.0},BETA:{"stage":0.0,"day":0.0,"count":0.0,"total":0.0}}},time_on(5))
	expect(Route.valid(floats),"valid() accepts JSON floats")
	var fa:Variant=rec(floats,ALPHA)
	var fb:Variant=rec(floats,BETA)
	expect(all_int(fa) and same(fa,rec4(7,4,2,5)),"valid() normalises alpha's floats to int (%s)"%str(fa))
	expect(all_int(fb) and same(fb,rec4(0,0,0,0)),"valid() normalises beta's floats to int")
	var partial:=vs({"players":{ALPHA:{"stage":2.0,"day":4.0,"count":1.0,"total":5.0},BETA:rec4(8,0,0,0)}},time_on(5))
	expect(not Route.valid(partial),"valid() rejects when one record is bad")
	var pa:Variant=rec(partial,ALPHA)
	expect(pa is Dictionary and typeof(pa.get("stage"))==TYPE_FLOAT,"a rejected valid() writes nothing (alpha's floats untouched)")
	var round_trip:Variant=JSON.parse_string(JSON.stringify(vs({"players":{ALPHA:rec4(4,5,2,3)}},time_on(5))))
	expect(round_trip is Dictionary and Route.valid(round_trip) and all_int(rec(round_trip,ALPHA)),"valid() on a JSON round trip")

# -------------------------------------------------------------------- site --

func check_site() -> void:
	var w:=World.new()
	w.switch_region(Route.REGION)
	var arrival:=center(SHUTTLE_ARRIVAL)
	expect(w.can_stand(arrival),"shuttle arrival is standable")
	var seen:={SHUTTLE_ARRIVAL:true}
	var queue:=[SHUTTLE_ARRIVAL]
	while not queue.is_empty():
		var c:Vector2i=queue.pop_front()
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			if not w.can_stand(center(n)):continue
			seen[n]=true
			queue.append(n)
	for cell:Vector2i in Route.TRACK:
		expect(w.is_land(cell) and not w.water(cell),"track %s is land"%str(cell))
		expect(not w.blocked(cell),"track %s is not blocked"%str(cell))
		expect(w.can_stand(center(cell)),"a player can stand on track %s"%str(cell))
		expect(seen.has(cell),"track %s reachable on foot from the shuttle arrival"%str(cell))
	for i in Route.STOPS.size():
		var stop:Vector2i=Route.STOPS[i]
		expect(seen.has(stop),"stop %d %s reachable on foot from the shuttle arrival"%[i,str(stop)])
		# A standable spot next to the stop, off the track when possible, within reach.
		var found:=Vector2.INF
		for off_track:bool in [true,false]:
			if found!=Vector2.INF:break
			for o:Vector2i in [Vector2i(0,1),Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
				var n:=stop+o
				if off_track and Route.TRACK.has(n):continue
				if not seen.has(n) or not w.can_stand(center(n)):continue
				if center(n).distance_to(center(stop))>Route.REACH:continue
				found=center(n)
				break
		if expect(found!=Vector2.INF,"stop %d has a reachable standable spot next to it"%i):beside[stop]=found
	expect(FAR_SPOT.distance_to(center(Route.STOPS[0]))>Route.REACH and w.can_stand(FAR_SPOT),"shuttle spot is standable and out of reach of the load platform")
	w.switch_region("home")
	expect(not w.state.has(Route.STATE_KEY),"fresh world has no ore_route record")

# ------------------------------------------------------------------- world --

func check_world() -> void:
	var w:=World.new()
	var path:=temp_path("main")
	w.save_path=path
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	expect(not w.state.has(Route.STATE_KEY),"world: no record before any cart")
	expect(validates(shape(w)),"world: fresh world validates")
	var inv_a:Variant=canon(pl(w,ALPHA).inventory)
	var inv_b:Variant=canon(pl(w,BETA).inventory)
	var coins_a:=int(pl(w,ALPHA).coins)
	var coins_b:=int(pl(w,BETA).coins)
	var day:int=Route.today(w.state)
	put(w,ALPHA,HOME_SPOT,"home")
	for step:String in Route.STEP_IDS:refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],step,Route.WRONG_REGION,"world: %s from home"%step)
	put(w,ALPHA,LANYANG_SPOT,"lanyang")
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],"load",Route.WRONG_REGION,"world: load from Lanyang")
	put(w,ALPHA,LOAD_STAND,"lanyang")
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],"load",Route.WRONG_REGION,"world: load from the same coordinates in Lanyang")
	jg(w,ALPHA,FAR_SPOT)
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],"load",Route.TOO_FAR,"world: load from the shuttle")
	jg(w,ALPHA,LOAD_STAND)
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[1],"load",Route.WRONG_CELL,"world: load at the first stop")
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[6],"unload",Route.WRONG_CELL,"world: unload at the unload platform with an empty cart")
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],"dig",Route.BAD_EXTRA,"world: unknown step")
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],"",Route.BAD_EXTRA,"world: empty step")
	for step:String in ["push","unload"]:refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],step,Route.NEED_LOAD,"world: %s before loading"%step)
	expect(not w.state.has(Route.STATE_KEY),"world: refusals write no record")
	# Alpha: two carts, standing on each stop, then next to each stop.
	use_beside=false
	var probes:=cart(w,ALPHA,"world: alpha cart 1")
	expect(probes==6,"world: cart 1 needed a walk before every push but the first and before the unload (got %d)"%probes)
	record_is(w.state,ALPHA,rec4(0,day,1,1),"world: alpha cart 1")
	expect(int(pl(w,ALPHA).coins)==coins_a+Route.PAY,"world: alpha paid 12")
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[6],"unload",Route.WRONG_CELL,"world: unload again after the cart went back")
	jg(w,ALPHA,LOAD_STAND)
	use_beside=true
	cart(w,ALPHA,"world: alpha cart 2 (standing next to each stop)")
	use_beside=false
	record_is(w.state,ALPHA,rec4(0,day,2,2),"world: alpha two carts")
	expect(int(pl(w,ALPHA).coins)==coins_a+2*Route.PAY,"world: alpha paid 24")
	jg(w,ALPHA,LOAD_STAND)
	refuse(w,ALPHA,Route.ACTION,Route.STOPS[0],"load",Route.DAILY_DONE,"world: third load")
	expect(same(pl(w,ALPHA).inventory,inv_a),"world: alpha's inventory unchanged by two carts")
	# Beta, independent, left mid-route.
	jg(w,BETA,LOAD_STAND)
	var alpha_rec:=var_to_bytes(canon(rec(w.state,ALPHA)))
	var alpha_coins:=int(pl(w,ALPHA).coins)
	cart(w,BETA,"world: beta loads and pushes three times",4)
	record_is(w.state,BETA,rec4(4,0,0,0),"world: beta at stage 4")
	expect(var_to_bytes(canon(rec(w.state,ALPHA)))==alpha_rec and int(pl(w,ALPHA).coins)==alpha_coins and same(pl(w,ALPHA).inventory,inv_a),"world: beta's steps leave alpha alone")
	expect(int(pl(w,BETA).coins)==coins_b,"world: beta not paid yet")
	put(w,BETA,center(Route.STOPS[3]),"home")
	refuse(w,BETA,Route.ACTION,Route.STOPS[3],"push",Route.WRONG_REGION,"world: beta pushes from home")
	jg(w,BETA,center(Route.STOPS[3]))
	# Save mid-route and reload.
	expect(w.save(),"world: saves mid-route")
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary and validates(base),"world: saved file parses and validates"):return
	var saved:Variant=(base as Dictionary).get(Route.STATE_KEY)
	expect(saved is Dictionary and same(saved,w.state[Route.STATE_KEY]),"world: saved record equals the live record")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"world: reload")
	expect(same(reloaded.state.get(Route.STATE_KEY),w.state.get(Route.STATE_KEY)),"world: record equal after reload (canonical)")
	expect(all_int(rec(reloaded.state,ALPHA)) and all_int(rec(reloaded.state,BETA)),"world: reload normalises record values to int")
	for token:String in [ALPHA,BETA]:
		expect(same(reloaded.state.players[token].inventory,pl(w,token).inventory),"world: %s bag equal after reload"%token.left(14))
		expect(int(reloaded.state.players[token].coins)==int(pl(w,token).coins),"world: %s coins equal after reload"%token.left(14))
	jg(reloaded,ALPHA,LOAD_STAND)
	jg(reloaded,BETA,center(Route.STOPS[3]))
	refuse(reloaded,ALPHA,Route.ACTION,Route.STOPS[0],"load",Route.DAILY_DONE,"world: daily limit survives reload")
	refuse(reloaded,BETA,Route.ACTION,Route.STOPS[0],"push",Route.WRONG_CELL,"world: beta's cart is not back at the platform after reload")
	var pu:=ok(reloaded,BETA,Route.ACTION,Route.STOPS[3],"push","world: beta continues her cart after reload")
	expect(str(pu.get("message",""))==Route.PUSH_OK%[4,2],"world: mid-route cart kept across reload")
	record_is(reloaded.state,BETA,rec4(5,0,0,0),"world: beta stage 5 after reload")
	for i in 2:
		jg(reloaded,BETA,center(Route.cart_cell(Route.stage(reloaded.state,BETA))))
		ok(reloaded,BETA,Route.ACTION,Route.cart_cell(Route.stage(reloaded.state,BETA)),"push","world: beta push after reload %d"%(i+1))
	jg(reloaded,BETA,center(Route.STOPS[6]))
	var un:=ok(reloaded,BETA,Route.ACTION,Route.STOPS[6],"unload","world: beta unloads after reload")
	expect(str(un.get("message",""))==Route.UNLOAD_OK%[Route.PAY,1] and int(reloaded.state.players[BETA].coins)==coins_b+Route.PAY,"world: beta's first cart paid 12")
	record_is(reloaded.state,BETA,rec4(0,day,1,1),"world: beta's cart counted")
	# Next day: alpha's count resets; PURSE_FULL through World.act.
	reloaded.state["time"]=float(Weather.day_index(float(reloaded.state.time))+1.0)*day_len+30.0
	expect(Route.today(reloaded.state)==day+1,"world: premise next day")
	jg(reloaded,ALPHA,LOAD_STAND)
	cart(reloaded,ALPHA,"world: alpha next-day cart to the unload platform",7)
	record_is(reloaded.state,ALPHA,rec4(7,day,2,2),"world: next-day cart waits at the unload platform")
	var keep:=int(reloaded.state.players[ALPHA].coins)
	reloaded.state.players[ALPHA]["coins"]=Route.LIMIT-Route.PAY+1
	jg(reloaded,ALPHA,center(Route.STOPS[6])) # 距離檢查在 PURSE_FULL 之前
	refuse(reloaded,ALPHA,Route.ACTION,Route.STOPS[6],"unload",Route.PURSE_FULL,"world: unload with a full purse")
	reloaded.state.players[ALPHA]["coins"]=keep
	var un2:=ok(reloaded,ALPHA,Route.ACTION,Route.STOPS[6],"unload","world: alpha unloads on the next day")
	expect(str(un2.get("message",""))==Route.UNLOAD_OK%[Route.PAY,1] and int(reloaded.state.players[ALPHA].coins)==keep+Route.PAY,"world: next-day cart is today's first, paid 12")
	record_is(reloaded.state,ALPHA,rec4(0,day+1,1,3),"world: next-day record")
	expect(same(reloaded.state.players[ALPHA].inventory,inv_a) and same(reloaded.state.players[BETA].inventory,inv_b),"world: inventories unchanged throughout (the cart needs no items)")
	expect(validates(shape(reloaded)),"world: state after the reload carts validates")
	# Legacy / tampered saves.
	var legacy:Dictionary=(base as Dictionary).duplicate(true)
	legacy.erase(Route.STATE_KEY)
	var fixture:=temp_path("fixture")
	var lw:=World.new()
	expect(validates(legacy) and write_json(fixture,legacy) and lw.load_world(fixture) and not lw.state.has(Route.STATE_KEY),"world: legacy save without the key loads unchanged")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["stage 8","unknown token","record extra key","record missing total","extra top-level key","players is a list",
		"record key is a list","count above total","day in the future","count above daily","total without day","fractional stage","negative total","stage text"]
	for label:String in labels:
		var bad:=tampered(base,label,day)
		expect(not validates(bad),"schema rejects: "+label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	var control:=tampered(base,"",day)
	expect(validates(control),"control: an untampered copy validates")

## base (saved mid-route): alpha {0,day,2,2}, beta {4,0,0,0}.
func tampered(base:Dictionary,label:String,day:int) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var or_rec:Dictionary=s[Route.STATE_KEY]
	var players:Dictionary=or_rec["players"]
	var a:Dictionary=players[ALPHA]
	var b:Dictionary=players[BETA]
	match label:
		"stage 8":a["stage"]=8
		"unknown token":players[STRANGER]=rec4(0,0,0,0)
		"record extra key":a["by"]="x"
		"record missing total":a.erase("total")
		"extra top-level key":or_rec["day"]=1
		"players is a list":or_rec["players"]=[a,b]
		"record key is a list":s[Route.STATE_KEY]=[or_rec]
		"count above total":a["total"]=1
		"day in the future":a["day"]=day+1
		"count above daily":
			a["count"]=3
			a["total"]=3
		"total without day":b["total"]=1
		"fractional stage":b["stage"]=2.5
		"negative total":a["total"]=-3
		"stage text":b["stage"]="4"
	return s
