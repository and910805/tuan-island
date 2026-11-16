extends SceneTree
## W1 core rules for the Beimen salt-pan slice (chapter 4 increment). Uses
## hand-built minimal states only; world/session integration is covered by the
## salt world/schema/session tests.

const SP=preload("res://scripts/salt_pan.gd")
const FN=preload("res://scripts/flower_nursery.gd")
const WEATHER=preload("res://scripts/weather.gd")
const A="salt-core-alpha-token"
const B="salt-core-beta-token"
const LATE="salt-core-late-joiner-token"
const TENTH="salt-core-tenth-player-token"
const NOFLOWER="salt-core-no-flower-token"
const BOX_A="0123456789abcdef0123456789abcdef"
const BOX_B="fedcba9876543210fedcba9876543210"
const DAY:=1440.0
var OWNERS:Array[String]=[]
var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func near(a:float,b:float) -> bool:
	return absf(a-b)<1e-9

func person() -> Dictionary:
	return {"name":"t","region":"home","inventory":{},"coins":500,"travel_book":{"visited":{"home":true},"legacy_pass":false},"x":1.0,"y":1.0}

func all_tokens() -> Array[String]:
	var out:Array[String]=[A,B,LATE,TENTH]
	out.append_array(OWNERS)
	return out

func make_state() -> Dictionary:
	var players:={}
	var flowers:={}
	for token in all_tokens():
		players[token]=person()
		var done:Dictionary=FN.FRESH.duplicate(true)
		done.letter=true
		done.complete=true
		flowers[token]=done
	players[NOFLOWER]=person()
	var fn:=FN.fresh()
	fn.players=flowers
	var regions:={"beimen":{"crops":{},"objects":{},"ground":{},"roofs":{},"forest":{},"removed":{},"damage":{},"next_network_check":0.0,"next_logistics_check":0.0}}
	return {"time":0.0,"players":players,"flower_nursery":fn,"salt_pan":SP.fresh(),"events":[],"objects":{},"regions":regions}

func objs(state:Dictionary) -> Dictionary:
	return state.regions.beimen.objects

func act(state:Dictionary,token:String,action:String,p:Vector2i,extra:String="",region:String="") -> Dictionary:
	var where:=region
	if where=="":where="home" if action in SP.HOME_ACTIONS else "beimen"
	return SP.apply(state,token,action,where,p,extra,objs(state),float(state.time))

func rejects(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,needle:String,detail:String) -> void:
	var before:=state.duplicate(true)
	var result:=act(state,token,action,p,extra)
	expect(not result.ok and (needle=="" or str(result.message).contains(needle)) and state==before,"%s (got %s)"%[detail,str(result)])

func accepts(state:Dictionary,token:String,action:String,p:Vector2i,extra:String,detail:String) -> Dictionary:
	var result:=act(state,token,action,p,extra)
	expect(result.ok,"%s (got %s)"%[detail,str(result)])
	return result

func tick(state:Dictionary,t1:float) -> Dictionary:
	var r:=SP.step(state,float(state.time),t1,objs(state))
	expect(r.ok,"step ok %s..%s"%[state.time,t1])
	state.time=t1
	return r

func rec(state:Dictionary,token:String) -> Dictionary:
	return SP.own_record(state,token)

func bag(state:Dictionary,token:String) -> Dictionary:
	return state.players[token].inventory

func pan_cell(i:int) -> Vector2i:
	return SP.pan_rect(i).position+Vector2i(1,1)

func wheel_cell(lot:int) -> Vector2i:
	return SP.wheel_socket(lot).position

func rake_cell(lot:int) -> Vector2i:
	return SP.rake_socket(lot).position

## Puts a player through letter, travel and intro.
func arrive(state:Dictionary,token:String) -> void:
	accepts(state,token,"salt_letter",SP.XIAOLI_HOME,"","letter "+token)
	state.players[token].travel_book.visited.beimen=true
	state.players[token].region="beimen"
	accepts(state,token,"salt_intro",SP.SALT_WORKER,"","intro "+token)

func repair_all(state:Dictionary,token:String) -> void:
	bag(state,token).merge({"plank":18,"resin":3,"stone":12},true)
	for g in 3:
		for item in ["plank","resin","stone"]:
			act(state,token,"salt_gate_give",Vector2i(8,SP.GATE_ROWS[g]+1),item)

## A hand cycle on a public pan starting at a sunny instant.
func hand_cycle(state:Dictionary,token:String,pan:int) -> void:
	var start:=float(state.time)
	accepts(state,token,"salt_flood",pan_cell(pan),"","flood for hand cycle")
	tick(state,start+SP.NEED)
	accepts(state,token,"salt_rake",pan_cell(pan),"","rake for hand cycle")

func broken(state:Dictionary,change:Callable,detail:String) -> void:
	var copy:=state.duplicate(true)
	change.call(copy)
	var verdict=SP.valid(copy)
	expect(verdict is bool and verdict==false,"valid rejects: "+detail)

func _initialize() -> void:
	for i in 8:OWNERS.append("salt-core-owner-%d-token"%i)
	constants_checks()
	layout_checks()
	time_checks()
	progression_checks()
	automation_checks()
	apprentice_checks()
	equivalence_checks()
	step_guard_checks()
	validation_checks()
	legacy_checks()
	privacy_checks()
	print("SALT_PAN_CORE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

# ---------------------------------------------------------------- constants

func constants_checks() -> void:
	expect(SP.SAVE_VERSION==26 and SP.REGION=="beimen","version and region")
	expect(SP.ACTIONS.size()==15 and "salt_box_take" in SP.ACTIONS,"15 salt actions")
	for action in SP.ACTIONS:expect(action.length()<=16,"action name short: "+action)
	expect(SP.HOME_ACTIONS==["salt_letter","salt_order"],"home actions")
	expect(SP.ITEMS.keys()==["sea_salt","salt_wheel_kit","salt_rake_kit","salt_grilled_fish"],"exactly four items")
	expect(SP.FORWARD_IDS.size()==6 and "beimen" in SP.FORWARD_IDS and "salt_pan" in SP.FORWARD_IDS,"forward ids")
	expect(SP.RECIPE.salt_grilled_fish.ingredients=={"minnow":1,"sea_salt":1} and SP.RECIPE.salt_grilled_fish.time==15.0,"salt fish recipe")
	expect(not SP.RECIPE.has("grilled_fish"),"grilled_fish untouched")
	expect(SP.SALT_FISH_PRICE==34 and SP.ORDER=={"sea_salt":4,"salt_grilled_fish":2} and SP.ORDER_PAY==120,"order values")
	expect(SP.CAP_MIN==3 and SP.CAP_MAX==999 and SP.CAP_DEFAULT==60 and SP.YIELD==3,"cap constants")
	expect(SP.NEED==480.0 and SP.SHIFT_SECONDS==4320.0 and SP.MAX_TIME==1.0e12,"time constants")
	expect(SP.LOT_ORIGINS.size()==10 and SP.PUBLIC_LOT==8 and SP.APPRENTICE_LOT==9 and SP.PAN_COUNT==20,"lot counts")
	for id in SP.STATUS_IDS:expect(SP.STATUS_TEXT.has(id),"status text "+id)
	expect(SP.STATUS_TEXT.rain=="下雨天水車暫停引水；已經成的鹽照常收進箱子，不會流失。","rain text accurate")
	expect(SP.STATUS_TEXT.off=="已暫停：水車與收鹽台都不動，成鹽會留在鹽田裡。","off text")
	expect(SP.STATUS_TEXT.waiting=="正在曬鹽。","waiting text")
	for phase in SP.PHASES:expect(SP.STORY.has(phase),"story line "+phase)
	var jargon:=["切片","設計選擇","lot","socket","tick","status","save","protocol","debug"]
	var texts:Array=SP.STATUS_TEXT.values()+SP.STORY.values()+[SP.REJECT_MESSAGE,SP.GATE_EVENT,SP.CRAFT_LOCKED_MESSAGE,SP.NOTE_TEXT,SP.CAP_MESSAGE,SP.FREE_LOT_MESSAGE,SP.BUSY_FORMAT]
	for text in texts:
		for word in jargon:expect(not str(text).to_lower().contains(word),"no jargon '%s' in %s"%[word,text])
	expect(SP.NOTE_TEXT.contains("遊戲原創"),"heritage note marks fiction")
	expect(SP.NOTE_TEXT.contains("1818 年遷至現址") and not SP.NOTE_TEXT.contains("可追溯"),"heritage note uses the verified relocation wording (1818 遷至現址)")

# ---------------------------------------------------------------- layout

func layout_checks() -> void:
	expect(SP.land(Vector2i(6,10)) and SP.land(Vector2i(51,41)) and not SP.land(Vector2i(5,20)) and not SP.land(Vector2i(52,20)),"land rect")
	expect(SP.water(Vector2i(3,20)) and not SP.water(Vector2i(6,20)) and not SP.blocked(Vector2i(6,20)) and not SP.blocked(Vector2i(7,30)),"sea west, dike walkable")
	for g in 3:
		var oy:int=SP.GATE_ROWS[g]
		expect(SP.gate_at(Vector2i(8,oy+1))==g and SP.gate_at(Vector2i(9,oy+1))==g and SP.blocked(Vector2i(8,oy+1)),"gate %d 2x1 solid"%g)
		expect(SP.water(Vector2i(8,oy)) and SP.water(Vector2i(9,oy+2)) and SP.blocked(Vector2i(9,oy)),"gate %d channel water"%g)
		expect(SP.site_at(Vector2i(9,oy+1))=="gate:%d"%g,"gate site")
	var pan_cells:={}
	var all_sockets:={}
	for i in SP.PAN_COUNT:
		var r:=SP.pan_rect(i)
		expect(r.size==Vector2i(3,3) and SP.lot_of_pan(i)==i/2,"pan %d rect"%i)
		for x in range(r.position.x,r.end.x):
			for y in range(r.position.y,r.end.y):
				var c:=Vector2i(x,y)
				expect(not pan_cells.has(c),"pans don't overlap")
				pan_cells[c]=true
				if not (SP.pan_at(c)==i and SP.blocked(c) and SP.lot_at(c)==i/2):expect(false,"pan cell %s"%c)
	checks+=1
	for lot in 10:
		var o:Vector2i=SP.LOT_ORIGINS[lot]
		expect(SP.pan_rect(lot*2)==Rect2i(o.x+1,o.y,3,3) and SP.pan_rect(lot*2+1)==Rect2i(o.x+5,o.y,3,3),"lot %d pans"%lot)
		for y in 3:expect(not SP.blocked(Vector2i(o.x+4,o.y+y)) and SP.lot_at(Vector2i(o.x+4,o.y+y))==lot,"lot %d divider walkable"%lot)
		if lot==SP.PUBLIC_LOT:
			expect(SP.wheel_socket(lot)==Rect2i() and SP.rake_socket(lot)==Rect2i() and SP.chest_sockets(lot).is_empty(),"public pool has no sockets")
			continue
		expect(SP.wheel_socket(lot)==Rect2i(o.x-1,o.y+1,2,1) and SP.rake_socket(lot)==Rect2i(o.x+3,o.y+3,2,1),"lot %d sockets"%lot)
		for c in [SP.wheel_socket(lot).position,SP.wheel_socket(lot).end-Vector2i(1,1),SP.rake_socket(lot).position,SP.rake_socket(lot).end-Vector2i(1,1)]:
			expect(SP.blocked(c) and SP.lot_at(c)==lot and SP.protected(c),"socket solid %s"%c)
			expect(not all_sockets.has(c),"sockets unique")
			all_sockets[c]=true
		expect(SP.site_at(SP.wheel_socket(lot).position)=="wheel:%d"%lot and SP.site_at(SP.rake_socket(lot).position+Vector2i(1,0))=="rake:%d"%lot,"socket sites")
		if lot==SP.APPRENTICE_LOT:
			expect(SP.chest_sockets(lot).is_empty(),"apprentice uses the cooperative chest")
			continue
		var sockets:=SP.chest_sockets(lot)
		expect(sockets==[Vector2i(o.x+2,o.y+3),Vector2i(o.x+5,o.y+3)],"lot %d chest sockets"%lot)
		for c in sockets:
			expect(not SP.blocked(c) and not SP.protected(c) and SP.chest_socket_lot(c)==lot and SP.lot_at(c)==lot,"chest socket buildable %s"%c)
			var adjacent:=false
			for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				if SP.rake_socket(lot).has_point(c+d):adjacent=true
			expect(adjacent,"chest socket next to rake socket")
	var buildable:=0
	for x in 80:
		for y in 60:
			if not SP.protected(Vector2i(x,y)):buildable+=1
	expect(buildable==16,"exactly 16 buildable cells (got %d)"%buildable)
	expect(SP.blocked(SP.APPRENTICE_CHEST) and SP.site_at(SP.APPRENTICE_CHEST)=="coop_chest" and SP.lot_at(SP.APPRENTICE_CHEST)==9,"cooperative chest solid prop")
	expect(SP.blocked(SP.SALT_WORKER) and SP.site_at(SP.SALT_WORKER)=="worker","worker")
	expect(SP.blocked(SP.HERITAGE_SIGN) and SP.site_at(SP.HERITAGE_SIGN)=="heritage","heritage sign")
	expect(SP.blocked(SP.PUBLIC_SIGN) and SP.site_at(SP.PUBLIC_SIGN)=="public_sign","public sign")
	expect(SP.blocked(SP.TRANSFER) and SP.site_at(SP.TRANSFER)=="transfer","transfer")
	expect(SP.BUS_SHELTER.has_point(SP.TRANSFER) and SP.blocked(Vector2i(49,25)) and SP.blocked(Vector2i(50,25)) and not SP.blocked(Vector2i(SP.ARRIVAL)) and SP.land(Vector2i(50,25)),"3-tile bus shelter is solid; arrival cell stays free")
	expect(SP.blocked(Vector2i(14,34)) and SP.blocked(Vector2i(35,38)) and SP.blocked(Vector2i(42,13)) and SP.blocked(Vector2i(47,15)),"heritage view and shed solid")
	var arrival:=Vector2i(floori(SP.ARRIVAL.x),floori(SP.ARRIVAL.y))
	expect(SP.land(arrival) and not SP.blocked(arrival),"arrival standable")
	expect(SP.site_at(Vector2i(30,40))=="" and SP.lot_at(Vector2i(30,40))==-1 and SP.pan_at(Vector2i(30,40))==-1,"plain ground")

# ---------------------------------------------------------------- time

func time_checks() -> void:
	expect(SP.evaporation_rate("sunny")==1.0 and SP.evaporation_rate("cloudy")==0.5 and SP.evaporation_rate("rainy")==-0.25 and SP.evaporation_rate("snow")==0.0 and SP.evaporation_rate("indoor",{"region":"beimen"})==0.0,"rates")
	var r:=SP.advance(0.0,0.0,480.0)
	expect(r.ok and r.salt and r.at==480.0,"sunny crystallises at exactly 480")
	r=SP.advance(0.0,0.0,479.5)
	expect(r.ok and not r.salt and r.p==479.5 and r.at==479.5,"sunny partial")
	r=SP.advance(0.0,0.0,1.0e9)
	expect(r.ok and r.salt and r.at==480.0,"t* independent of t1")
	r=SP.advance(0.0,DAY,DAY+960.0)
	expect(r.ok and r.salt and r.at==DAY+960.0,"cloudy takes 960")
	r=SP.advance(0.0,DAY,DAY+959.0)
	expect(r.ok and not r.salt and near(r.p,479.5),"cloudy partial")
	r=SP.advance(100.0,2.0*DAY,2.0*DAY+200.0)
	expect(r.ok and not r.salt and near(r.p,50.0),"rain dilutes brine")
	r=SP.advance(10.0,2.0*DAY,2.0*DAY+100.0)
	expect(r.ok and not r.salt and r.p==0.0,"rain floors at 0")
	r=SP.advance(0.0,1200.0,5000.0)
	expect(r.ok and r.salt and r.at==1920.0,"midnight span sunny->cloudy t*=1920 (got %s)"%r)
	r=SP.advance(0.0,2.0*DAY-100.0,10000.0)
	expect(r.ok and r.salt and r.at==3.0*DAY+480.0,"cloudy->rainy->sunny t*=4800 (got %s)"%r)
	r=SP.advance(470.0,1430.0,1440.0)
	expect(r.ok and r.salt and r.at==1440.0,"crystallises exactly on midnight")
	r=SP.advance(100.0,2.0*DAY,2.0*DAY+10.0)
	expect(r.ok and near(r.p,97.5),"midnight belongs to new (rainy) day")
	r=SP.advance(100.0,2.0*DAY-10.0,2.0*DAY)
	expect(r.ok and near(r.p,105.0),"before midnight is the old (cloudy) day")
	r=SP.advance(SP.NEED,5.0,6.0)
	expect(r.ok and r.salt and r.at==5.0,"already full")
	for bad in [[NAN,0.0,1.0],[0.0,NAN,1.0],[0.0,0.0,INF],[0.0,10.0,5.0],[0.0,-1.0,5.0],[0.0,0.0,2.0e12],[-1.0,0.0,1.0],[481.0,0.0,1.0],["x",0.0,1.0]]:
		r=SP.advance(bad[0],bad[1],bad[2])
		expect(not r.ok,"advance rejects %s"%[bad])
	# every start point in the cycle crystallises within the segment guard
	for d in 14:
		for frac in [0.0,0.3,0.99]:
			for p0 in [0.0,240.0,479.0]:
				var t0:float=d*DAY+float(frac)*DAY
				r=SP.advance(p0,t0,t0+10.0*DAY)
				expect(r.ok and r.salt and r.at<=t0+3.0*DAY,"crystallises within 3 day-segments from day %d %.2f p=%s"%[d,frac,p0])
	expect(SP.first_dry(100.0)==100.0 and SP.first_dry(2.0*DAY+5.0)==3.0*DAY and SP.first_dry(2.0*DAY)==3.0*DAY and SP.first_dry(3.0*DAY)==3.0*DAY,"first dry instant")
	expect(SP.raining(2.0*DAY) and not SP.raining(2.0*DAY-0.001) and not SP.raining(3.0*DAY),"rain day bounds")
	var v:=SP.pan_view({"s":"brine","p":0.0,"t":0.0,"f":"hand"},120.0)
	expect(v.s=="brine" and near(v.ratio,0.25) and v.eta_minutes==6 and not v.diluted and not v.covered,"pan view brine (got %s)"%v)
	v=SP.pan_view({"s":"brine","p":0.0,"t":0.0,"f":"hand"},600.0)
	expect(v.s=="salt" and v.ratio==1.0 and v.eta_minutes==0,"pan view becomes salt lazily")
	v=SP.pan_view({"s":"salt","p":480.0,"t":0.0,"f":"hand"},2.0*DAY+30.0)
	expect(v.s=="salt" and v.covered and not v.diluted,"salt covered in rain")
	v=SP.pan_view({"s":"brine","p":100.0,"t":2.0*DAY,"f":"hand"},2.0*DAY+40.0)
	expect(v.s=="brine" and v.diluted and near(v.ratio,90.0/480.0),"brine diluted in rain")
	v=SP.pan_view(SP.fresh_pan(),0.0)
	expect(v.s=="empty" and v.eta_minutes==-1,"empty view")

# ---------------------------------------------------------------- progression

func progression_checks() -> void:
	var s:=make_state()
	expect(SP.phase(s,NOFLOWER)=="locked" and SP.phase(s,A)=="letter","locked / letter")
	rejects(s,NOFLOWER,"salt_letter",SP.XIAOLI_HOME,"","田尾公共花園","locked player gets no letter")
	var before:=s.duplicate(true)
	var res:=SP.apply(s,A,"salt_letter","beimen",SP.XIAOLI_HOME,"",objs(s),0.0)
	expect(not res.ok and s==before,"letter only at home")
	res=SP.apply(s,A,"salt_letter","home",Vector2i(40,29),"",objs(s),0.0)
	expect(not res.ok and s==before,"letter only at Xiaoli")
	rejects(s,A,"salt_intro",SP.SALT_WORKER,"","北門寄來的信","intro before letter")
	accepts(s,A,"salt_letter",SP.XIAOLI_HOME,"","letter")
	expect(SP.route_open(s,A) and not SP.route_open(s,B),"route opens per player")
	rejects(s,A,"salt_letter",SP.XIAOLI_HOME,"","已收下","letter once")
	expect(SP.phase(s,A)=="travel","travel phase")
	rejects(s,A,"salt_intro",SP.SALT_WORKER,"","抵達北門","intro needs arrival")
	s.players[A].travel_book.visited.beimen=true
	expect(SP.phase(s,A)=="intro","intro phase")
	rejects(s,A,"salt_intro",Vector2i(44,18),"","對應的地方","intro only at the worker cell")
	accepts(s,A,"salt_intro",SP.SALT_WORKER,"","intro")
	var echo:=accepts(s,A,"salt_intro",SP.SALT_WORKER,"","intro echo")
	expect(echo.message.begins_with("阿曬：") and rec(s,A).intro,"intro echo keeps state")
	expect(SP.phase(s,A)=="gates","gates phase")
	expect(SP.guidance(s,A).region=="beimen" and SP.guidance(s,A).cell==Vector2i(8,14) and SP.guidance(s,A).phase=="gates","gate guidance")
	accepts(s,A,"salt_note",SP.HERITAGE_SIGN,"","note")
	expect(rec(s,A).note,"note flag")
	rejects(s,A,"salt_note",Vector2i(24,34),"","","note only at the sign")
	# gates: flood refused before repair
	rejects(s,A,"salt_flood",pan_cell(16),"","閘門還沒修好","no flood before gates")
	rejects(s,A,"salt_gate_give",Vector2i(8,14),"plank","背包沒有","give with empty bag")
	rejects(s,A,"salt_gate_give",Vector2i(8,14),"wood","木板、樹脂或石材","bad material")
	rejects(s,A,"salt_gate_give",Vector2i(10,14),"plank","","not a gate cell")
	bag(s,A).plank=100
	var give:=accepts(s,A,"salt_gate_give",Vector2i(8,14),"plank","over-donation takes need only")
	expect(int(bag(s,A).plank)==94 and int(s.salt_pan.gates[0].plank)==6 and s.salt_pan.givers.has(A),"over-donation capped at 6")
	expect(give.message.contains("×6"),"give message count")
	rejects(s,A,"salt_gate_give",Vector2i(9,14),"plank","已經不缺","gate cap")
	# B helps (needs intro first)
	accepts(s,B,"salt_letter",SP.XIAOLI_HOME,"","B letter")
	s.players[B].travel_book.visited.beimen=true
	bag(s,B).stone=2
	rejects(s,B,"salt_gate_give",Vector2i(8,14),"stone","阿曬","B needs intro")
	accepts(s,B,"salt_intro",SP.SALT_WORKER,"","B intro")
	accepts(s,B,"salt_gate_give",Vector2i(8,14),"stone","B partial stone")
	expect(int(s.salt_pan.gates[0].stone)==2 and int(bag(s,B).stone)==0,"partial donation")
	bag(s,A).merge({"resin":10,"stone":30},true)
	s.time=100.0
	for g in 3:
		for item in ["plank","resin","stone"]:
			var r:=act(s,A,"salt_gate_give",Vector2i(8,SP.GATE_ROWS[g]+1),item)
			if g==2 and item=="stone":
				expect(r.ok and r.get("event","")==SP.GATE_EVENT and r.message.contains("三道閘門都修好了"),"completion reported once")
			elif g==0 and item=="plank":
				expect(not r.ok,"gate 0 plank already full")
			else:
				expect(r.ok and not r.has("event"),"gate %d %s ok without event"%[g,item])
	expect(float(s.salt_pan.repaired_at)==100.0 and s.events.count(SP.GATE_EVENT)==1,"repaired_at settles once")
	expect(int(bag(s,A).plank)==82 and int(bag(s,A).resin)==7 and int(bag(s,A).stone)==30-10,"exact materials taken")
	s.time=200.0
	for item in ["plank","resin","stone"]:rejects(s,A,"salt_gate_give",Vector2i(8,21),item,"已經不缺","no donation after repair "+item)
	expect(float(s.salt_pan.repaired_at)==100.0 and s.events.count(SP.GATE_EVENT)==1,"single settlement")
	expect(SP.phase(s,A)=="first_salt" and SP.valid(s.duplicate(true)),"first_salt + valid")
	# late joiner skips gates
	expect(SP.phase(s,B)=="first_salt","B also first_salt")
	# flood/rake on the public pool
	rejects(s,A,"salt_rake",pan_cell(16),"","剛被收完了","rake empty public pan")
	accepts(s,A,"salt_flood",pan_cell(16),"","flood public pan")
	expect(s.salt_pan.pans[16]=={"s":"brine","p":0.0,"t":200.0,"f":"hand"},"flood state")
	rejects(s,B,"salt_flood",pan_cell(16),"","已經有海水","flood twice")
	s.time=600.0
	rejects(s,A,"salt_rake",pan_cell(16),"","鹽還沒結成","rake before salt")
	s.time=680.0
	expect(SP.pan_view(s.salt_pan.pans[16],680.0).s=="salt","public pan ready lazily")
	accepts(s,B,"salt_rake",SP.pan_rect(16).position,"","B rakes first (any cell of the pan)")
	rejects(s,A,"salt_rake",pan_cell(16),"","剛被收完了","first rake wins; A gets nothing")
	expect(int(bag(s,B).get("sea_salt",0))==3 and int(bag(s,A).get("sea_salt",0))==0,"no duplication")
	expect(rec(s,B).raked==1 and rec(s,B).wheel_raked==0 and rec(s,A).raked==0,"raked credit")
	expect(s.salt_pan.pans[16]=={"s":"empty","p":0.0,"t":680.0,"f":""},"raked pan empty")
	# rain: flood refused, hand rake works
	s.time=2.0*DAY+10.0
	rejects(s,A,"salt_flood",pan_cell(17),"",SP.RAIN_FLOOD_MESSAGE,"rain blocks hand flood")
	s.time=4.0*DAY+940.0
	accepts(s,A,"salt_flood",pan_cell(17),"","flood near end of sunny day 4")
	tick(s,5.0*DAY+100.0)
	expect(s.salt_pan.pans[17].s=="salt" and float(s.salt_pan.pans[17].t)==4.0*DAY+1420.0,"crystallised at t* before the rain")
	tick(s,5.0*DAY+1400.0)
	expect(s.salt_pan.pans[17].s=="salt" and s.salt_pan.pans[17].p==SP.NEED,"rain never reduces formed salt")
	accepts(s,A,"salt_rake",pan_cell(17),"","hand rake works in rain")
	expect(rec(s,A).raked==1 and int(bag(s,A).sea_salt)==3,"A raked in rain")
	expect(SP.phase(s,A)=="claim" and SP.guidance(s,A).cell==SP.pan_rect(0).position,"claim phase guidance")
	expect(SP.craft_allowed(s,A,"salt_wheel_kit") and not SP.craft_allowed(s,A,"salt_rake_kit") and SP.craft_allowed(s,A,"plank"),"craft gates after first rake")
	expect(not SP.craft_allowed(s,TENTH,"salt_wheel_kit"),"no wheel kit before raking")
	# claim / release
	rejects(s,A,"salt_claim",pan_cell(16),"",SP.STATUS_TEXT.reserve,"public pool never claimable")
	rejects(s,A,"salt_claim",Vector2i(30,40),"","","claim needs a lot cell")
	accepts(s,A,"salt_claim",pan_cell(0),"","A claims lot 0")
	expect(SP.owned_lot(s,A)==0 and s.salt_pan.lots[0].owner==A,"owner set")
	rejects(s,A,"salt_claim",pan_cell(2),"","只能照顧一區","one lot per player")
	rejects(s,A,"salt_claim",pan_cell(0),"","已經是你","claim own lot")
	rejects(s,B,"salt_claim",SP.chest_sockets(0)[0],"",SP.CLAIMED_MESSAGE,"second claimant loses")
	rejects(s,B,"salt_flood",pan_cell(0),"","其他島民","foreign lot pan")
	rejects(s,B,"salt_flood",pan_cell(2),"","還沒有人認領","unclaimed lot pan")
	rejects(s,B,"salt_release",pan_cell(0),"","不是你","release foreign lot")
	accepts(s,B,"salt_claim",wheel_cell(1),"","B claims lot 1 via its wheel socket")
	s.time=6.0*DAY+10.0
	accepts(s,B,"salt_flood",pan_cell(2),"","B floods own pan")
	rejects(s,B,"salt_release",pan_cell(2),"","鹽收完","release needs empty pans")
	s.salt_pan.pans[2]=SP.fresh_pan()
	objs(s)["24,16"]={"type":"chest","owner":B,"items":{}}
	rejects(s,B,"salt_release",pan_cell(2),"","箱子搬走","release needs empty chest sockets")
	objs(s).erase("24,16")
	bag(s,B).salt_wheel_kit=1
	accepts(s,B,"salt_install",wheel_cell(1),"wheel","B installs wheel")
	rejects(s,B,"salt_release",pan_cell(2),"","拆回背包","release needs machines removed")
	accepts(s,B,"salt_uninstall",wheel_cell(1)+Vector2i(1,0),"wheel","B uninstalls wheel")
	expect(int(bag(s,B).salt_wheel_kit)==1,"kit returned")
	accepts(s,B,"salt_release",SP.rake_socket(1).position,"","B releases lot 1")
	expect(s.salt_pan.lots[1]==SP.fresh_lot(),"released lot fresh")
	expect(SP.valid(s.duplicate(true)),"valid after progression")

# ---------------------------------------------------------------- automation

## Returns a state where A owns lot 0 at a sunny time (day 7 = cycle day 0).
func automation_state() -> Dictionary:
	var s:=make_state()
	arrive(s,A)
	s.time=50.0
	repair_all(s,A)
	s.time=7.0*DAY
	hand_cycle(s,A,16)
	accepts(s,A,"salt_claim",pan_cell(0),"","claim lot 0")
	return s

func automation_checks() -> void:
	var s:=automation_state()
	var t0:=float(s.time)
	expect(SP.phase(s,A)=="wheel" and SP.status(s,A,objs(s),t0).id=="manual","wheel phase / manual status")
	rejects(s,A,"salt_install",wheel_cell(0),"wheel","鹽田水車組","install needs kit")
	rejects(s,A,"salt_install",rake_cell(0),"wheel","水車座","wheel kit only on wheel socket")
	rejects(s,A,"salt_install",pan_cell(16),"wheel",SP.STATUS_TEXT.reserve,"no machines in public pool")
	bag(s,A).salt_wheel_kit=2
	rejects(s,A,"salt_install",rake_cell(0),"rake","先裝好水車","rake needs wheel")
	accepts(s,A,"salt_install",wheel_cell(0),"wheel","install wheel")
	expect(int(bag(s,A).salt_wheel_kit)==1 and s.salt_pan.lots[0].wheel,"kit consumed")
	rejects(s,A,"salt_install",wheel_cell(0),"wheel","已經裝好","second wheel")
	rejects(s,B,"salt_install",wheel_cell(1),"wheel","","install on foreign lot")
	expect(SP.phase(s,A)=="rake" and SP.status(s,A,objs(s),t0).id=="wheel_only","rake phase / wheel_only")
	# wheel refills both empty pans at the first instant
	tick(s,t0+1.0)
	for i in [0,1]:expect(s.salt_pan.pans[i]=={"s":"brine","p":0.0,"t":t0,"f":"wheel"},"wheel refilled pan %d at step start"%i)
	tick(s,t0+SP.NEED+5.0)
	expect(s.salt_pan.pans[0].s=="salt" and float(s.salt_pan.pans[0].t)==t0+SP.NEED,"wheel pan crystallised at t*")
	expect(SP.status(s,A,objs(s),float(s.time)).id=="wheel_only","still wheel only")
	accepts(s,A,"salt_rake",pan_cell(0),"","hand rake wheel pan")
	expect(rec(s,A).wheel_raked==1 and rec(s,A).raked==2,"wheel credit")
	expect(SP.craft_allowed(s,A,"salt_rake_kit"),"rake kit unlocked")
	var raked_at:=float(s.time)
	tick(s,raked_at+10.0)
	expect(s.salt_pan.pans[0]=={"s":"brine","p":0.0,"t":raked_at,"f":"wheel"},"wheel refills a hand-raked pan at the raking instant on a dry day")
	# rain pauses wheel refill: rake pan 1 on a rainy day, refill at next midnight
	tick(s,9.0*DAY+100.0)
	expect(s.salt_pan.pans[1].s=="salt" and float(s.salt_pan.pans[1].t)==t0+SP.NEED,"pan 1 salt since its t*")
	accepts(s,A,"salt_rake",pan_cell(1),"","hand rake pan 1 in rain on day 9")
	expect(rec(s,A).wheel_raked==2,"second wheel credit")
	s.time=9.0*DAY+1000.0
	# day 9 = cycle 2 = rainy
	expect(SP.raining(float(s.time)),"day 9 rains")
	tick(s,9.0*DAY+1100.0)
	expect(s.salt_pan.pans[1].s=="empty","rain blocks wheel fill")
	tick(s,10.0*DAY+30.0)
	expect(s.salt_pan.pans[1]=={"s":"brine","p":0.0,"t":10.0*DAY,"f":"wheel"},"wheel refills at the next midnight")
	# rake
	bag(s,A).salt_rake_kit=1
	accepts(s,A,"salt_install",rake_cell(0)+Vector2i(1,0),"rake","install rake")
	expect(SP.phase(s,A)=="automate" and SP.status(s,A,objs(s),float(s.time)).id=="unset","automate/unset")
	rejects(s,A,"salt_auto_toggle",rake_cell(0),"",SP.STATUS_TEXT.unset,"toggle needs chest")
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"14,16|60","放一個箱子","cfg needs chest object")
	var cell:="14,16"
	objs(s)[cell]={"type":"chest","owner":B,"items":{"wood":2},"box_id":BOX_A}
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"14,16|2",SP.CAP_MESSAGE,"cap < 3 rejected")
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"14,16|0",SP.CAP_MESSAGE,"cap 0 rejected")
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"14,16|1000","重新選擇","4-digit cap rejected")
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"24,16|60","箱位","other lot socket rejected")
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"14,16;60","重新選擇","bad extra")
	rejects(s,A,"salt_auto_cfg",wheel_cell(0),"14,16|60","","cfg only at rake socket")
	objs(s)["17,16"]={"type":"private_chest","owner":B,"items":{},"box_id":BOX_B}
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"17,16|60",SP.STATUS_TEXT.owner,"someone else's private chest")
	objs(s).erase("17,16")
	objs(s)["17,16"]={"type":"chest","owner":A,"items":{}}
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"17,16|60","還沒準備好","chest without box id")
	objs(s).erase("17,16")
	accepts(s,A,"salt_auto_cfg",rake_cell(0),"14,16|9","cfg cap 9")
	expect(s.salt_pan.lots[0].chest==cell and s.salt_pan.lots[0].box==BOX_A and int(s.salt_pan.lots[0].cap)==9,"cfg stored")
	expect(SP.status(s,A,objs(s),float(s.time)).id=="off","off status")
	accepts(s,A,"salt_auto_toggle",rake_cell(0),"","toggle on")
	rejects(s,A,"salt_auto_cfg",rake_cell(0),"14,16|9","先暫停","cfg while on")
	rejects(s,A,"salt_uninstall",rake_cell(0),"rake","先暫停","uninstall rake while on")
	rejects(s,A,"salt_uninstall",wheel_cell(0),"wheel","先拆下收鹽台","uninstall wheel before rake")
	var now:=float(s.time)
	expect(SP.status(s,A,objs(s),now).id in ["waiting","running"],"working status")
	var probe:=s.duplicate(true)
	probe.salt_pan.pans[0]={"s":"brine","p":10.0,"t":now,"f":"wheel"}
	probe.salt_pan.pans[1]={"s":"brine","p":20.0,"t":now,"f":"wheel"}
	expect(SP.status(probe,A,objs(probe),now)=={"id":"waiting","text":"正在曬鹽。"},"both pans drying -> waiting")
	probe.salt_pan.pans[1]={"s":"salt","p":SP.NEED,"t":now,"f":"wheel"}
	expect(SP.status(probe,A,objs(probe),now).id=="running","a pan about to be collected -> running")
	# pans 0 (brine since day9+100? recomputed) and 1 (brine since day10)
	tick(s,now+2000.0)
	expect(rec(s,A).auto_raked>=1 and int(objs(s)[cell].items.sea_salt)>=3,"collector delivered")
	expect(int(objs(s)[cell].items.wood)==2,"other chest items untouched")
	expect(SP.phase(s,A)=="order","order phase after automation")
	expect(int(objs(s)[cell].items.sea_salt)%3==0 and int(objs(s)[cell].items.sea_salt)<=9,"never exceeds cap")
	# run a long time: chest fills to exactly 9 and stays (full)
	tick(s,float(s.time)+3.0*DAY)
	expect(int(objs(s)[cell].items.sea_salt)==9,"filled up to cap exactly")
	var st:=SP.status(s,A,objs(s),float(s.time))
	expect(st.id=="full" and st.text==SP.STATUS_TEXT.full,"full status at chest+3>cap (got %s)"%st)
	var salt_pans:=0
	for i in [0,1]:
		if s.salt_pan.pans[i].s=="salt":salt_pans+=1
	expect(salt_pans==2,"salt kept in pans while full")
	var held_auto:int=rec(s,A).auto_raked
	expect(held_auto==3,"three automatic deliveries (got %d)"%held_auto)
	# withdraw 1 -> 8 + 3 > 9 still full; withdraw to 6 -> collects one
	objs(s)[cell].items.sea_salt=7
	expect(SP.status(s,A,objs(s),float(s.time)).id=="full","7+3>9 full")
	objs(s)[cell].items.sea_salt=6
	expect(SP.status(s,A,objs(s),float(s.time)).id!="full","6+3<=9 not full")
	var at_withdraw:=float(s.time)
	tick(s,at_withdraw+1.0)
	expect(int(objs(s)[cell].items.sea_salt)==9 and rec(s,A).auto_raked==4,"collected at step start after withdraw")
	# rain status, collector still works in rain
	objs(s)[cell].items.sea_salt=0
	var rain_t:=16.0*DAY+10.0 # cycle day 2
	expect(SP.raining(rain_t),"day 16 rains")
	s.time=rain_t-5.0
	tick(s,rain_t)
	var before_rain:=int(objs(s)[cell].items.sea_salt)
	expect(SP.status(s,A,objs(s),rain_t).id=="rain","rain status")
	s.salt_pan.pans[0]={"s":"salt","p":SP.NEED,"t":rain_t,"f":"wheel"}
	tick(s,rain_t+10.0)
	expect(int(objs(s)[cell].items.sea_salt)==before_rain+3,"collector works in rain")
	expect(s.salt_pan.pans[0].s=="empty","collected pan empty in rain (no refill)")
	# invalid / owner statuses never move items
	var items_before:Dictionary=objs(s)[cell].items.duplicate(true)
	objs(s)[cell].box_id=BOX_B
	expect(SP.status(s,A,objs(s),float(s.time)).id=="invalid","box id mismatch -> invalid")
	s.salt_pan.pans[1]={"s":"salt","p":SP.NEED,"t":float(s.time),"f":"wheel"}
	tick(s,float(s.time)+5.0)
	expect(objs(s)[cell].items==items_before and s.salt_pan.pans[1].s=="salt","invalid chest: nothing moved")
	objs(s)[cell]={"type":"private_chest","owner":B,"items":items_before.duplicate(true),"box_id":BOX_A}
	expect(SP.status(s,A,objs(s),float(s.time)).id=="owner","foreign private chest -> owner")
	tick(s,float(s.time)+5.0)
	expect(objs(s)[cell].items==items_before,"owner status: nothing moved")
	objs(s)[cell].owner=A
	expect(SP.status(s,A,objs(s),float(s.time)).id!="owner","own private chest ok")
	objs(s).erase(cell)
	expect(SP.status(s,A,objs(s),float(s.time)).id=="invalid","removed chest -> invalid")
	objs(s)[cell]={"type":"bench","owner":A,"items":{},"box_id":BOX_A}
	expect(SP.status(s,A,objs(s),float(s.time)).id=="invalid","non-chest -> invalid")
	objs(s)[cell]={"type":"chest","owner":A,"items":items_before.duplicate(true),"box_id":BOX_A}
	# off: nothing moves, wheel also stops
	accepts(s,A,"salt_auto_toggle",rake_cell(0),"","toggle off")
	s.salt_pan.pans[0]=SP.fresh_pan()
	s.salt_pan.pans[0].t=float(s.time)
	var off_before:Dictionary=s.salt_pan.duplicate(true)
	var off_items:Dictionary=objs(s)[cell].items.duplicate(true)
	var off_t:=17.0*DAY+5.0
	var r:=SP.step(s,float(s.time),off_t,objs(s))
	s.time=off_t
	expect(r.ok and not r.changed and s.salt_pan==off_before and objs(s)[cell].items==off_items,"off: wheel and collector idle")
	expect(SP.status(s,A,objs(s),off_t).id=="off","off status again")
	accepts(s,A,"salt_uninstall",rake_cell(0),"rake","uninstall rake")
	expect(s.salt_pan.lots[0].chest=="" and s.salt_pan.lots[0].box=="" and not s.salt_pan.lots[0].rake and int(bag(s,A).salt_rake_kit)==1,"rake uninstalled and cleared")
	expect(SP.valid(s.duplicate(true)),"valid after automation")
	# order and report
	rejects(s,A,"salt_order",SP.XIAOLI_HOME,"","委託還不夠","order needs items")
	bag(s,A).merge({"sea_salt":10,"salt_grilled_fish":3},true)
	var coins:=int(s.players[A].coins)
	rejects(s,A,"salt_report",SP.SALT_WORKER,"","小栗","report before order")
	var wrong:=SP.apply(s,A,"salt_order","beimen",SP.XIAOLI_HOME,"",objs(s),float(s.time))
	expect(not wrong.ok,"order only at home")
	accepts(s,A,"salt_order",SP.XIAOLI_HOME,"","order")
	expect(int(bag(s,A).sea_salt)==6 and int(bag(s,A).salt_grilled_fish)==1 and int(s.players[A].coins)==coins+120 and rec(s,A).order,"order settled")
	rejects(s,A,"salt_order",SP.XIAOLI_HOME,"","交過了","order once")
	expect(SP.phase(s,A)=="report","report phase")
	accepts(s,A,"salt_report",SP.SALT_WORKER,"","report")
	expect(SP.phase(s,A)=="complete" and rec(s,A).complete,"complete")
	rejects(s,A,"salt_report",SP.SALT_WORKER,"","已經完成","report once")
	expect(SP.guidance(s,A).cell==SP.HERITAGE_SIGN,"complete guidance")
	expect(SP.valid(s.duplicate(true)),"valid at completion")
	# order phase gate for someone not automated
	var s2:=automation_state()
	bag(s2,A).merge({"sea_salt":10,"salt_grilled_fish":3},true)
	rejects(s2,A,"salt_order",SP.XIAOLI_HOME,"","收鹽台自動收","order needs automation first")
	# coin cap
	s.players[A].coins=SP.LIMIT
	# status reserve
	expect(SP.unit_status(s,SP.PUBLIC_LOT,objs(s),0.0).id=="reserve","reserve status")
	expect(SP.status(s,TENTH,objs(s),0.0).id=="","no unit no status")

# ---------------------------------------------------------------- apprentice

func saturated_state() -> Dictionary:
	var s:=make_state()
	arrive(s,A)
	s.time=50.0
	repair_all(s,A)
	s.time=7.0*DAY
	for lot in 8:
		var token:String=OWNERS[lot]
		arrive(s,token)
		s.salt_pan.players[token].raked=1
	return s

func apprentice_checks() -> void:
	var s:=saturated_state()
	arrive(s,LATE)
	arrive(s,TENTH)
	var app_cell:=pan_cell(18)
	rejects(s,LATE,"salt_claim",app_cell,"","親手收一次鹽","shift needs a first rake")
	hand_cycle(s,LATE,16)
	hand_cycle(s,TENTH,17)
	for lot in 7:accepts(s,OWNERS[lot],"salt_claim",pan_cell(lot*2),"","owner %d claims"%lot)
	rejects(s,LATE,"salt_claim",app_cell,"",SP.FREE_LOT_MESSAGE,"free lot -> claim your own")
	expect(not SP.apprentice_eligible(s,LATE) and SP.own_view(s,LATE,objs(s),float(s.time)).apprentice.message==SP.FREE_LOT_MESSAGE,"not eligible while a lot is free")
	accepts(s,OWNERS[7],"salt_claim",pan_cell(14),"","owner 7 claims (saturated)")
	expect(SP.free_lots(s)==0 and SP.apprentice_eligible(s,LATE),"saturated -> eligible")
	rejects(s,OWNERS[0],"salt_claim",app_cell,"","已經有自己的鹽田區","owners cannot take a shift")
	expect(SP.phase(s,LATE)=="claim" and SP.guidance(s,LATE).cell==SP.pan_rect(18).position,"claim guidance points to apprentice")
	var take_t:=float(s.time)
	accepts(s,LATE,"salt_claim",SP.APPRENTICE_CHEST,"","late joiner takes the shift")
	expect(s.salt_pan.apprentice.tenant==LATE and float(s.salt_pan.apprentice.since)==take_t,"tenant + since")
	rejects(s,LATE,"salt_claim",app_cell,"","正在學徒區輪班","double take")
	# STAGED-FIX: a busy claim now joins the fair waiting list (was: refused).
	var busy:=act(s,TENTH,"salt_claim",app_cell)
	expect(busy.ok and busy.message==SP.QUEUE_BUSY_FORMAT%[72,1] and SP.queue_position(s,TENTH)==1 and s.salt_pan.apprentice.tenant==LATE,"10th player queues, 72 minutes (got %s)"%busy.message)
	rejects(s,TENTH,"salt_claim",app_cell,"","第 1 位","queued claim again changes nothing")
	rejects(s,TENTH,"salt_flood",app_cell,"","另一位島民輪班","only the tenant floods")
	var tv:=SP.own_view(s,TENTH,objs(s),take_t)
	expect(tv.apprentice.busy and not tv.apprentice.mine and not tv.apprentice.eligible and tv.apprentice.ends_in_minutes==72,"busy view")
	var lv:=SP.own_view(s,LATE,objs(s),take_t)
	expect(lv.apprentice.mine and lv.unit.kind=="apprentice" and lv.unit.index==9 and lv.unit.chest=="47,23" and lv.lot==-1,"tenant view")
	expect(SP.phase(s,LATE)=="wheel","tenant wheel phase")
	# kits via the same actions
	bag(s,LATE).salt_wheel_kit=1
	accepts(s,LATE,"salt_install",wheel_cell(9),"wheel","tenant installs own wheel")
	expect(SP.phase(s,LATE)=="rake" and SP.status(s,LATE,objs(s),take_t).id=="wheel_only","tenant rake phase")
	tick(s,take_t+SP.NEED+1.0)
	expect(s.salt_pan.pans[18].s=="salt" and s.salt_pan.pans[18].f=="wheel" and s.salt_pan.pans[19].s=="salt","apprentice wheel pans crystallised")
	rejects(s,TENTH,"salt_rake",app_cell,"","另一位島民輪班","only tenant rakes")
	accepts(s,LATE,"salt_rake",app_cell,"","tenant hand-rakes a wheel pan")
	expect(rec(s,LATE).wheel_raked==1 and SP.craft_allowed(s,LATE,"salt_rake_kit"),"tenant earns wheel_raked")
	bag(s,LATE).salt_rake_kit=1
	accepts(s,LATE,"salt_install",rake_cell(9),"rake","tenant installs own rake")
	expect(SP.status(s,LATE,objs(s),float(s.time)).id=="off","apprentice starts paused")
	rejects(s,LATE,"salt_auto_cfg",rake_cell(9),"47,23|2",SP.CAP_MESSAGE,"apprentice cap < 3")
	rejects(s,LATE,"salt_auto_cfg",rake_cell(9),"14,16|30","合作社收鹽箱","apprentice must name the cooperative chest")
	accepts(s,LATE,"salt_auto_cfg",rake_cell(9),"47,23|30","apprentice cfg")
	expect(int(s.salt_pan.apprentice.cap)==30,"apprentice cap stored")
	accepts(s,LATE,"salt_auto_toggle",rake_cell(9),"","apprentice on")
	expect(SP.status(s,LATE,objs(s),float(s.time)).id in ["running","waiting"],"apprentice running")
	var kits_before:=int(bag(s,LATE).get("salt_wheel_kit",0))
	tick(s,float(s.time)+2.0)
	# pan 19 was salt -> collected at step start, graduation immediately
	expect(int(s.salt_pan.coop_box.get(LATE,0))==3 and rec(s,LATE).auto_raked==1,"automatic delivery to coop box")
	expect(s.salt_pan.apprentice==SP.fresh_apprentice(),"graduation frees the shift")
	expect(int(bag(s,LATE).salt_wheel_kit)==kits_before+1 and int(bag(s,LATE).salt_rake_kit)==1,"graduation returns both kits")
	for i in [18,19]:
		var pan:Dictionary=s.salt_pan.pans[i]
		expect(pan.s=="empty" and pan.f=="" or pan.f=="hand","apprentice pan %d reset to hand"%i)
	expect(SP.phase(s,LATE)=="order","late joiner reaches order")
	expect(SP.valid(s.duplicate(true)),"valid after graduation")
	# vacant apprentice pans untouched by time
	var vacant:Array=s.salt_pan.pans.slice(18,20).duplicate(true)
	tick(s,float(s.time)+600.0)
	for j in 2:
		var was:Dictionary=vacant[j]
		var now_pan:Dictionary=s.salt_pan.pans[18+j]
		if was.s=="empty":expect(now_pan==was,"vacant empty pan %d never refilled"%j)
		else:expect(now_pan.f=="hand" and now_pan.s in ["brine","salt"],"vacant pan %d keeps brine/salt as a hand pan"%j)
	# coop box ownership
	rejects(s,TENTH,"salt_box_take",SP.APPRENTICE_CHEST,"","沒有你的海鹽","others cannot take")
	rejects(s,LATE,"salt_box_take",Vector2i(46,23),"","","box take only at the chest")
	var salt_before:=int(bag(s,LATE).get("sea_salt",0))
	accepts(s,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","owner takes compartment")
	expect(int(bag(s,LATE).sea_salt)==salt_before+3 and not s.salt_pan.coop_box.has(LATE),"compartment emptied")
	# LIMIT-bounded take keeps remainder
	s.salt_pan.coop_box[LATE]=9
	bag(s,LATE).sea_salt=SP.LIMIT-4
	var partial:=accepts(s,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","bounded take")
	expect(int(bag(s,LATE).sea_salt)==SP.LIMIT and int(s.salt_pan.coop_box[LATE])==5 and partial.message.contains("其餘 5 份"),"remainder stays")
	bag(s,LATE).sea_salt=SP.LIMIT
	rejects(s,LATE,"salt_box_take",SP.APPRENTICE_CHEST,"","上限","full bag")
	bag(s,LATE).sea_salt=10
	# order -> report -> complete for the late joiner
	bag(s,LATE).salt_grilled_fish=2
	s.players[LATE].region="home"
	accepts(s,LATE,"salt_order",SP.XIAOLI_HOME,"","late joiner order")
	s.players[LATE].region="beimen"
	accepts(s,LATE,"salt_report",SP.SALT_WORKER,"","late joiner report")
	expect(SP.phase(s,LATE)=="complete","late joiner completes without a private lot")
	rejects(s,LATE,"salt_claim",app_cell,"","已經會用收鹽台","graduate cannot retake")
	# 10th player: shift, wheel only, expiry
	var t10:=float(s.time)
	accepts(s,TENTH,"salt_claim",app_cell,"","10th takes the freed shift")
	expect(rec(s,TENTH).wheel_raked==0,"no inherited wheel credit")
	if s.salt_pan.pans[18].s=="salt":
		accepts(s,TENTH,"salt_rake",app_cell,"","10th rakes vacant leftover")
		expect(rec(s,TENTH).wheel_raked==0,"leftover pan gives only raked credit (f reset)")
	bag(s,TENTH).salt_wheel_kit=1
	accepts(s,TENTH,"salt_install",wheel_cell(9),"wheel","10th installs wheel")
	tick(s,t10+SP.SHIFT_SECONDS-1.0)
	expect(s.salt_pan.apprentice.tenant==TENTH,"shift still running before expiry")
	var rec_before:=rec(s,TENTH)
	tick(s,t10+SP.SHIFT_SECONDS+0.5)
	expect(s.salt_pan.apprentice==SP.fresh_apprentice() and int(bag(s,TENTH).salt_wheel_kit)==1,"expiry returns kit and frees shift")
	expect(rec(s,TENTH)==rec_before,"expiry keeps record progress")
	for i in [18,19]:
		var pan:Dictionary=s.salt_pan.pans[i]
		expect((pan.s=="empty" and pan.f=="") or pan.f=="hand","expiry resets pan %d to hand"%i)
	accepts(s,TENTH,"salt_claim",app_cell,"","same player may re-take an empty shift")
	# voluntary release returns kits
	bag(s,TENTH).salt_wheel_kit=1
	accepts(s,TENTH,"salt_install",wheel_cell(9),"wheel","reinstall")
	accepts(s,TENTH,"salt_release",app_cell,"","voluntary release")
	expect(int(bag(s,TENTH).salt_wheel_kit)==1 and s.salt_pan.apprentice.tenant=="","release returns kit")
	rejects(s,TENTH,"salt_release",app_cell,"","沒有在學徒區","release when not tenant")
	# STAGED-FIX: shift end at LIMIT never defers (root finding): the overflow
	# kit goes to the owner's escrow and the station is released immediately.
	accepts(s,TENTH,"salt_claim",app_cell,"","take again")
	accepts(s,TENTH,"salt_install",wheel_cell(9),"wheel","install again")
	bag(s,TENTH).salt_wheel_kit=SP.LIMIT
	var rel:=accepts(s,TENTH,"salt_release",app_cell,"","release at LIMIT")
	expect(s.salt_pan.apprentice.tenant=="" and int(bag(s,TENTH).salt_wheel_kit)==SP.LIMIT and SP.escrow_of(s,TENTH).salt_wheel_kit==1 and rel.message.contains("合作社收鹽箱"),"release at LIMIT escrows the kit, no item loss")
	expect(SP.valid(s.duplicate(true)),"valid with escrowed kit")
	accepts(s,TENTH,"salt_claim",app_cell,"","take once more")
	accepts(s,TENTH,"salt_install",wheel_cell(9),"wheel","install from inventory")
	bag(s,TENTH).salt_wheel_kit=SP.LIMIT
	var since:=float(s.salt_pan.apprentice.since)
	tick(s,since+SP.SHIFT_SECONDS+10.0)
	expect(s.salt_pan.apprentice.tenant=="" and int(bag(s,TENTH).salt_wheel_kit)==SP.LIMIT and SP.escrow_of(s,TENTH).salt_wheel_kit==2,"expiry at LIMIT releases at once and escrows, no item loss")
	expect(SP.valid(s.duplicate(true)),"valid after expiry at LIMIT")
	bag(s,TENTH).salt_wheel_kit=5
	accepts(s,TENTH,"salt_box_take",SP.APPRENTICE_CHEST,"","owner claims escrowed kits")
	expect(int(bag(s,TENTH).salt_wheel_kit)==7 and not s.salt_pan.kit_box.has(TENTH),"escrow emptied into inventory")
	expect(SP.valid(s.duplicate(true)),"valid at end of apprentice checks")

# ---------------------------------------------------------------- equivalence

func busy_state() -> Dictionary:
	var s:=saturated_state()
	arrive(s,LATE)
	hand_cycle(s,LATE,16)
	for lot in 8:accepts(s,OWNERS[lot],"salt_claim",pan_cell(lot*2),"","owner claims")
	accepts(s,LATE,"salt_claim",pan_cell(18),"","shift")
	# lot 0: full automation, big cap; lot 1: wheel only; lot 2: small cap fills;
	# lot 3: hand brine; apprentice: automation that graduates mid-run.
	var boxes:=[BOX_A,BOX_B,"00112233445566778899aabbccddeeff"]
	for lot in 3:
		var token:String=OWNERS[lot]
		s.salt_pan.lots[lot].wheel=true
		if lot!=1:
			var cell:=SP.chest_sockets(lot)[0]
			objs(s)[SP.key(cell)]={"type":"chest","owner":token,"items":{"sea_salt":1},"box_id":boxes[lot]}
			s.salt_pan.lots[lot].merge({"rake":true,"on":true,"chest":SP.key(cell),"box":boxes[lot],"cap":999 if lot==0 else 12},true)
	s.salt_pan.players[OWNERS[1]].wheel_raked=0
	s.salt_pan.pans[6]={"s":"brine","p":100.0,"t":float(s.time),"f":"hand"}
	s.salt_pan.apprentice.merge({"wheel":true,"rake":true,"on":true,"cap":60},true)
	s.salt_pan.pans[16]={"s":"brine","p":0.0,"t":float(s.time),"f":"hand"}
	return s

func equivalence_checks() -> void:
	var base:=busy_state()
	expect(SP.valid(base.duplicate(true)),"busy fixture valid")
	var t0:=float(base.time)
	expect(t0==floorf(t0),"integer start time")
	var one:=base.duplicate(true)
	var many:=base.duplicate(true)
	var r:=SP.step(one,t0,t0+10.0*DAY,objs(one))
	expect(r.ok and r.changed,"10-day single step ok")
	one.time=t0+10.0*DAY
	var all_ok:=true
	for k in 14400:
		var rr:=SP.step(many,t0+float(k),t0+float(k+1),objs(many))
		if not rr.ok:all_ok=false
	many.time=t0+10.0*DAY
	expect(all_ok,"14400 one-second steps ok")
	expect(var_to_bytes(one.salt_pan)==var_to_bytes(many.salt_pan),"salt_pan bit-identical")
	expect(var_to_bytes(objs(one))==var_to_bytes(objs(many)),"chest items bit-identical")
	expect(var_to_bytes(one.players)==var_to_bytes(many.players),"inventories bit-identical")
	expect(int(objs(one)["14,16"].items.sea_salt)>1+30,"lot 0 delivered many times (got %s)"%objs(one)["14,16"].items)
	expect(int(objs(one)["34,16"].items.sea_salt)==10,"small cap lot stops at 10 (1+3*3 <= 12)")
	expect(one.salt_pan.lots[1].wheel and one.salt_pan.pans[2].s=="salt" and one.salt_pan.pans[3].s=="salt","wheel-only lot ends with salt waiting for a hand")
	expect(one.salt_pan.apprentice.tenant=="" and int(one.salt_pan.coop_box.get(LATE,0))==3,"apprentice graduated after one delivery")
	expect(int(one.players[LATE].inventory.get("salt_wheel_kit",0))==1 and int(one.players[LATE].inventory.get("salt_rake_kit",0))==1,"kits back")
	expect(one.salt_pan.pans[6].s=="salt" and one.salt_pan.pans[16].s=="salt","non-automated pans crystallise in step")
	expect(SP.valid(one.duplicate(true)),"valid after long run")
	# restart: a reloaded copy continues identically
	var cont_a:=one.duplicate(true)
	var cont_b:Dictionary=bytes_to_var(var_to_bytes(one))
	SP.step(cont_a,float(cont_a.time),float(cont_a.time)+DAY,objs(cont_a))
	SP.step(cont_b,float(cont_b.time),float(cont_b.time)+DAY,objs(cont_b))
	expect(var_to_bytes(cont_a.salt_pan)==var_to_bytes(cont_b.salt_pan) and var_to_bytes(objs(cont_a))==var_to_bytes(objs(cont_b)),"restart continues identically")
	# uneven chunking also matches
	var odd:=base.duplicate(true)
	var cur:=t0
	var sizes:=[0.25,7.0,333.3,1439.75,0.5,2880.0,1.0]
	var idx:=0
	while cur<t0+10.0*DAY:
		var nxt:=minf(cur+float(sizes[idx%sizes.size()]),t0+10.0*DAY)
		SP.step(odd,cur,nxt,objs(odd))
		cur=nxt
		idx+=1
	expect(var_to_bytes(odd.salt_pan)==var_to_bytes(one.salt_pan) and var_to_bytes(objs(odd))==var_to_bytes(objs(one)),"uneven chunks identical")

# ---------------------------------------------------------------- step guards

func step_guard_checks() -> void:
	var s:=busy_state()
	var t:=float(s.time)
	for bad in [[NAN,t+1.0],[t,INF],[t,t-1.0],[-5.0,1.0],[t,2.0e12],["a",t],[t,null]]:
		var before:=s.duplicate(true)
		var r:=SP.step(s,bad[0],bad[1],objs(s))
		expect(not r.ok and not r.changed and s==before,"step rejects %s without mutation"%[bad])
	var wrecked:=s.duplicate(true)
	wrecked.salt_pan.lots[0].cap=999999
	var snap:=wrecked.duplicate(true)
	var r2:=SP.step(wrecked,t,t+DAY,objs(wrecked))
	expect(not r2.ok and wrecked==snap,"out-of-range cap (unbounded events) rejected without mutation")
	wrecked=s.duplicate(true)
	wrecked.salt_pan.pans[3].p=NAN
	snap=wrecked.duplicate(true)
	r2=SP.step(wrecked,t,t+DAY,objs(wrecked))
	expect(not r2.ok and str(wrecked)==str(snap),"non-finite pan rejected")
	wrecked=s.duplicate(true)
	wrecked.salt_pan.pans[0]={"s":"brine","p":0.0,"t":t+50.0,"f":"hand"}
	snap=wrecked.duplicate(true)
	r2=SP.step(wrecked,t,t+10.0,objs(wrecked))
	expect(not r2.ok and wrecked==snap,"pan from the future rejected atomically")
	var idle:=make_state()
	var r3:=SP.step(idle,0.0,1.0e6,{})
	expect(r3.ok and not r3.changed,"idle step unchanged")
	var r4:=SP.step(s,t,t,objs(s))
	expect(r4.ok,"zero-length step ok")

# ---------------------------------------------------------------- validation

func validation_checks() -> void:
	var fresh:=make_state()
	expect(SP.valid(fresh.duplicate(true)),"fresh valid")
	var s:=busy_state()
	SP.step(s,float(s.time),float(s.time)+DAY,objs(s))
	s.time=float(s.time)+DAY
	expect(SP.valid(s.duplicate(true)),"busy valid")
	# JSON round trip normalises numbers
	var json:Dictionary=JSON.parse_string(JSON.stringify(s))
	expect(SP.valid(json),"JSON round trip valid")
	expect(json.salt_pan.lots[0].cap is int and json.salt_pan.players[A].raked is int and json.salt_pan.pans[0].p is float,"normalised types")
	var tok:=OWNERS[0]
	broken(s,func(c):c.erase("salt_pan"),"missing root")
	broken(s,func(c):c.salt_pan.extra=1,"extra root key")
	broken(s,func(c):c.salt_pan.erase("coop_box"),"missing coop_box")
	broken(s,func(c):c.time=NAN,"time NaN")
	broken(s,func(c):c.time=-1.0,"negative time")
	broken(s,func(c):c.salt_pan.players["ghost"]=SP.RECORD.duplicate(true),"record for unknown player")
	broken(s,func(c):c.salt_pan.players[A].extra=1,"record extra key")
	broken(s,func(c):c.salt_pan.players[A].erase("note"),"record missing key")
	broken(s,func(c):c.salt_pan.players[A].letter=false,"record without letter")
	broken(s,func(c):c.salt_pan.players[A].intro=1,"bool as number")
	broken(s,func(c):c.salt_pan.players[A].raked=-1,"negative raked")
	broken(s,func(c):c.salt_pan.players[A].raked=1.5,"fractional raked")
	broken(s,func(c):c.salt_pan.players[A].raked=SP.LIMIT+1,"raked over LIMIT")
	broken(s,func(c):c.salt_pan.players[A].wheel_raked=int(c.salt_pan.players[A].raked)+1,"wheel_raked > raked")
	broken(s,func(c):c.salt_pan.players[TENTH]=SP.RECORD.duplicate(true);c.salt_pan.players[TENTH].letter=true;c.salt_pan.players[TENTH].raked=1,"raked without intro")
	broken(s,func(c):c.salt_pan.players[A].raked=0;c.salt_pan.players[A].wheel_raked=0;c.salt_pan.players[A].auto_raked=1,"auto_raked without raked")
	broken(s,func(c):c.salt_pan.players[A].complete=true,"complete without order")
	broken(s,func(c):c.flower_nursery.players[A].complete=false,"letter without flower completion")
	broken(s,func(c):c.players[A].travel_book.visited.erase("beimen"),"intro without visit")
	broken(s,func(c):c.players[TENTH].region="beimen","in beimen without letter")
	broken(s,func(c):c.salt_pan.gates[0].plank=7,"gate over need")
	broken(s,func(c):c.salt_pan.gates.pop_back(),"gate count")
	broken(s,func(c):c.salt_pan.gates[1].extra=0,"gate extra key")
	broken(s,func(c):c.salt_pan.gates[0].plank=5,"repaired but gate short")
	broken(s,func(c):c.salt_pan.repaired_at=float(c.time)+1.0,"repaired in the future")
	broken(s,func(c):c.salt_pan.givers["ghost"]=true,"unknown giver")
	broken(s,func(c):c.salt_pan.givers[A]=1,"giver value not true")
	broken(fresh,func(c):c.salt_pan.repaired_at=0.0,"repaired while gates empty")
	broken(fresh,func(c):c.salt_pan.gates[0].plank=1,"donation without giver")
	broken(fresh,func(c):c.salt_pan.pans[0]={"s":"brine","p":0.0,"t":0.0,"f":"hand"},"brine before repair")
	broken(s,func(c):c.salt_pan.pans.pop_back(),"pan count")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"mud","p":0.0,"t":0.0,"f":""},"bad pan state")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"empty","p":1.0,"t":0.0,"f":""},"empty with progress")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"empty","p":0.0,"t":0.0,"f":"hand"},"empty with source")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"brine","p":480.0,"t":0.0,"f":"hand"},"brine at NEED")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"brine","p":-1.0,"t":0.0,"f":"hand"},"negative brine")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"brine","p":1.0,"t":0.0,"f":""},"brine without source")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"salt","p":479.0,"t":0.0,"f":"wheel"},"salt below NEED")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"salt","p":480.0,"t":float(c.time)+1.0,"f":"wheel"},"pan time in the future")
	broken(s,func(c):c.salt_pan.pans[5]={"s":"salt","p":480.0,"t":NAN,"f":"wheel"},"pan time NaN")
	broken(s,func(c):c.salt_pan.pans[5].extra=1,"pan extra key")
	broken(s,func(c):c.salt_pan.lots.pop_back(),"lot count")
	broken(s,func(c):c.salt_pan.lots[1].owner=tok,"two lots one owner")
	broken(s,func(c):c.salt_pan.lots[0].owner="ghost","unknown owner")
	broken(s,func(c):c.salt_pan.players[tok].raked=0,"owner without raked")
	broken(s,func(c):c.salt_pan.lots[1].rake=true;c.salt_pan.lots[1].wheel=false,"rake without wheel")
	broken(s,func(c):c.salt_pan.lots[0].cap=2,"cap below 3")
	broken(s,func(c):c.salt_pan.lots[0].cap=1000,"cap above 999")
	broken(s,func(c):c.salt_pan.lots[0].cap=5.5,"fractional cap")
	broken(s,func(c):c.salt_pan.lots[0].box="","chest without box")
	broken(s,func(c):c.salt_pan.lots[0].box="XYZ","bad box id")
	broken(s,func(c):c.salt_pan.lots[0].chest="24,16","chest on another lot's socket")
	broken(s,func(c):c.salt_pan.lots[1].on=true,"on without rake")
	broken(s,func(c):c.salt_pan.lots[0].on="yes","on not bool")
	broken(s,func(c):c.salt_pan.lots[0].extra=1,"lot extra key")
	broken(fresh,func(c):c.salt_pan.lots[0].cap=61,"unowned lot not fresh (cap)")
	broken(fresh,func(c):c.salt_pan.lots[0].wheel=true,"unowned lot with wheel")
	var app_state:=saturated_state()
	arrive(app_state,LATE)
	hand_cycle(app_state,LATE,16)
	for lot in 8:accepts(app_state,OWNERS[lot],"salt_claim",pan_cell(lot*2),"","claim")
	accepts(app_state,LATE,"salt_claim",pan_cell(18),"","shift")
	expect(SP.valid(app_state.duplicate(true)),"apprentice fixture valid")
	broken(app_state,func(c):c.salt_pan.apprentice.tenant="ghost","unknown tenant")
	broken(app_state,func(c):c.salt_pan.apprentice.tenant=OWNERS[0],"tenant owns a lot")
	broken(app_state,func(c):c.salt_pan.apprentice.since=float(c.time)+1.0,"since in the future")
	broken(app_state,func(c):c.salt_pan.apprentice.since=-1.0,"negative since")
	broken(app_state,func(c):c.salt_pan.apprentice.rake=true,"apprentice rake without wheel")
	broken(app_state,func(c):c.salt_pan.apprentice.on=true,"apprentice on without rake")
	broken(app_state,func(c):c.salt_pan.apprentice.cap=2,"apprentice cap below 3")
	broken(app_state,func(c):c.salt_pan.apprentice.extra=1,"apprentice extra key")
	broken(fresh,func(c):c.salt_pan.apprentice.since=5.0,"vacant apprentice not fresh")
	broken(app_state,func(c):c.salt_pan.coop_box[LATE]=0,"empty compartment stored")
	broken(app_state,func(c):c.salt_pan.coop_box["ghost"]=3,"compartment of unknown player")
	broken(app_state,func(c):c.salt_pan.coop_box[NOFLOWER]=3,"compartment without record")
	broken(app_state,func(c):c.salt_pan.coop_box[LATE]=2.5,"fractional compartment")
	broken(s,func(c):c.regions.beimen.crops["20,40"]={"kind":"radish"},"crops in beimen")
	broken(s,func(c):c.regions.beimen.forest["20,40"]={},"forest in beimen")
	broken(s,func(c):c.regions.beimen.objects["30,40"]={"type":"chest","owner":A,"items":{}},"chest off socket")
	broken(s,func(c):c.regions.beimen.objects["17,16"]={"type":"bench","owner":A,"items":{}},"non-chest on socket")
	broken(s,func(c):c.regions.beimen.objects["17,16"]={"type":"chest","owner":A},"chest without items")
	var ok_chest:=s.duplicate(true)
	ok_chest.regions.beimen.objects["17,16"]={"type":"private_chest","owner":tok,"items":{}}
	expect(SP.valid(ok_chest),"private chest on a socket valid")

# ---------------------------------------------------------------- legacy

func legacy_checks() -> void:
	var old:={"time":5.0,"players":{A:person()},"objects":{"1,1":{"type":"chest","owner":A,"items":{"wood":3}}},"regions":{"tianwei":{"objects":{}}}}
	expect(SP.legacy_clean(old),"clean legacy save")
	var cases:={
		"salt_pan root":func(c):c.salt_pan={},
		"beimen region":func(c):c.regions.beimen={},
		"player in beimen":func(c):c.players[A].region="beimen",
		"visited beimen":func(c):c.players[A].travel_book.visited.beimen=true,
		"collection":func(c):c.players[A].collection={"dishes":{"salt_grilled_fish":1}},
		"home chest":func(c):c.objects["1,1"].items.sea_salt=1,
		"region chest":func(c):c.regions.tianwei.objects["2,2"]={"type":"chest","owner":A,"items":{"salt_rake_kit":1}},
		"cooking active":func(c):c.objects["3,3"]={"type":"stove","owner":A,"items":{},"cooking":{"active":{"kind":"salt_grilled_fish"},"waiting":[],"ready":[]}},
		"cooking waiting":func(c):c.objects["3,3"]={"type":"stove","owner":A,"items":{},"cooking":{"active":{},"waiting":[{"kind":"soup","ingredients":{"sea_salt":1}}],"ready":[]}},
		"processing ready":func(c):c.regions.tianwei.objects["4,4"]={"type":"sawmill","owner":A,"items":{},"processing":{"active":{},"waiting":[],"ready":[{"kind":"salt_wheel_kit"}]}},
		"job":func(c):c.objects["5,5"]={"type":"stove","owner":A,"items":{},"job":{"kind":"salt_grilled_fish"}},
	}
	for id in SP.ITEMS:
		cases["inventory "+id]=func(c):c.players[A].inventory[id]=1
	for label in cases:
		var copy:=old.duplicate(true)
		cases[label].call(copy)
		expect(not SP.legacy_clean(copy),"legacy rejects "+label)

# ---------------------------------------------------------------- privacy

func privacy_checks() -> void:
	var s:=busy_state()
	SP.step(s,float(s.time),float(s.time)+600.0,objs(s))
	s.time=float(s.time)+600.0
	var pub:=SP.public(s,float(s.time))
	expect(pub.keys()==["gates","needs","repaired","giver_count","pans","lots","apprentice","weather"],"public keys")
	expect(pub.gates.size()==3 and pub.pans.size()==20 and pub.lots.size()==8 and pub.repaired and pub.giver_count==1,"public shape")
	expect(pub.lots[0].keys()==["taken","wheel","rake","active","mine"] and pub.lots[0].mine==false,"lot shape")
	expect(pub.pans[0].keys()==["s","p","t","f"],"pan shape")
	expect(pub.apprentice.keys()==["taken","wheel","rake","active","ends_at"],"apprentice shape")
	expect(pub.weather.keys()==["id","label","raining"],"weather shape")
	var pub_text:=var_to_str(pub)
	for token in all_tokens():expect(not pub_text.contains(token),"public has no token "+token)
	for box in [BOX_A,BOX_B]:expect(not pub_text.contains(box),"public has no box id")
	expect(not pub_text.contains("14,16") and not pub_text.contains("chest"),"public has no chest settings")
	var view:=SP.own_view(s,OWNERS[1],objs(s),float(s.time))
	expect(view.keys()==["record","phase","guidance","lot","unit","apprentice","coop_box","free_lots","can_craft","order"],"own_view keys")
	expect(view.unit.keys()==["kind","index","wheel","rake","chest","cap","on","status"],"unit keys")
	expect(view.lot==1 and view.unit.kind=="lot" and view.unit.status.id=="wheel_only","own unit")
	var view_text:=var_to_str(view)
	for token in all_tokens():expect(not view_text.contains(token),"own_view has no token "+token)
	expect(not view_text.contains("14,16") and not view_text.contains(BOX_A),"no other owner's chest")
	expect(not view_text.contains("999"),"no other owner's cap")
	var mine:=SP.own_view(s,OWNERS[0],objs(s),float(s.time))
	expect(mine.unit.chest=="14,16" and mine.unit.cap==999 and not var_to_str(mine).contains(BOX_A),"own chest shown without box id")
	var outsider:=SP.own_view(s,TENTH,objs(s),float(s.time))
	expect(outsider.lot==-1 and outsider.unit.kind=="" and outsider.coop_box==0 and outsider.order.pay==120,"outsider view")
	expect(outsider.order.need=={"sea_salt":4,"salt_grilled_fish":2},"order need")
