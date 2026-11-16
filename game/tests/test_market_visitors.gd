extends SceneTree
## T071 regression suite for res://scripts/market_visitors.gd: the presentation
## only "customers in front of the plaza stall" plan and the journal's
## 「我的市集攤位」 summary lines. Pure functions (part_of, shown_for,
## shuffle_phase, constants, plan, wish_item, status_line, summary_lines) plus a
## real World integration that feeds World.market_view(token) into plan and
## summary_lines and proves they never write world state.
##
## PRESET (written straight into world state, not earned, same presets as
## test_market_stall.gd): state.picnic (false at first, then set true),
## state.time (start of world day 1, later moved to one second before the next
## midnight), player positions (standing one tile below the stall cell) and
## player inventories (stocked with sellable goods). Each World also gets a
## temp save_path that is removed at the end.
## REALLY EXERCISED: market_stock / market_open via World.act, the midnight
## settlement via World.step (real 0.5 s ticks across midnight),
## World.market_view, and every public function of market_visitors.gd.
const World=preload("res://scripts/world.gd")
const Market=preload("res://scripts/market_stall.gd")
const MV=preload("res://scripts/market_visitors.gd")
const WEATHER=preload("res://scripts/weather.gd")
const DAY:=1440.0
const GUEST_KEYS:=["facing","offset","slot","tint","wish"]
var checks:=0
var failures:=0
var serial:=0
var _cleanup:Array[String]=[]

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)

func finish()->void:
	for file in _cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("MARKET_VISITORS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("market-visitors-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func stall(w)->Vector2i:
	var state:Dictionary=w.state
	return Market.cell_for(state)

static func stand(w,token:String,cell:Vector2i)->void:
	var p:Dictionary=pl(w,token)
	p.x=float(cell.x)+0.5
	p.y=float(cell.y)+1.5

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.market_view(token)
	return v

static func now_of(w)->float:
	return float(w.state.time)

func act(w,token:String,action:String,cell:Vector2i,extra:String="")->Dictionary:
	serial+=1
	var r:Dictionary=w.act(token,"visitors-req-%d"%serial,action,cell,extra)
	return r

## Picnic flag, time, positions and inventories are PRESET exactly like test_market_stall.gd.
func make_world(tokens:Array,day_index:int,picnic:bool)->World:
	var w:=World.new()
	var path:=temp_path("world")
	_cleanup.append(path)
	w.save_path=path
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=DAY*day_index+120.0
	var cell:=Market.CANDIDATES[0] as Vector2i
	for token:String in tokens:
		stand(w,token,cell)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["radish","carrot","soup","salad","bluebell","chime_herb","egg","carp"]:inv[item]=20
	return w

## Base journal view with the same keys as Market.view (world day 4: dish, next flower).
static func make_view(over:Dictionary)->Dictionary:
	var v:={"unlocked":true,"day":4,"theme":"dish","next_theme":"flower","open":false,"pending":false,
		"stalls_today":0,"visitors_estimate":8,"stock":{},"stock_count":0,"till":0,"total":0,"prices":{},"report":{}}
	for key in over:v[key]=over[key]
	return v

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_part_and_shown()
	test_shuffle_and_constants()
	test_plan_rejects()
	test_plan_shapes()
	test_wish_item()
	test_summary_lines()
	test_world_integration()
	finish()

# 1a. part_of / shown_for.
func test_part_and_shown()->void:
	expect(MV.PARTS==6 and MV.MAX_SHOWN==3,"PARTS 6, MAX_SHOWN 3")
	expect(is_equal_approx(WEATHER.DAY_SECONDS,DAY),"Day is 1440 s")
	var width:=DAY/MV.PARTS
	expect(MV.part_of(0.0)==0,"part_of(0)==0")
	for k in range(1,MV.PARTS):
		expect(MV.part_of(width*k-0.01)==k-1,"part_of just below boundary %d is %d"%[k,k-1])
		expect(MV.part_of(width*k)==k,"part_of at boundary %d is %d"%[k,k])
	expect(MV.part_of(1439.9)==MV.PARTS-1,"part_of(1439.9) is the last part")
	expect(MV.part_of(DAY)==0,"Day wrap: part_of(1440)==0")
	expect(MV.part_of(DAY+width+1.0)==1,"Day 1 part 1")
	expect(MV.part_of(DAY*5+720.0)==3,"Day 5 noon is part 3")
	expect(MV.part_of(DAY*3+1439.9)==MV.PARTS-1,"Day 3 end is the last part")
	var inside:=true
	var t:=-DAY
	while t<DAY*3:
		var p:=MV.part_of(t)
		if p<0 or p>=MV.PARTS:inside=false
		t+=7.3
	expect(inside,"part_of always within 0..PARTS-1 (sweep incl. negative time)")
	expect(MV.shown_for(0)==0 and MV.shown_for(-1)==0 and MV.shown_for(-100)==0,"shown_for(<=0)==0")
	expect(MV.shown_for(1)==2,"shown_for(1)==2")
	for n in [2,3,4,8,100,100000]:expect(MV.shown_for(n)==3,"shown_for(%d)==3"%n)

# 1b. shuffle_phase and constants.
func test_shuffle_and_constants()->void:
	for slot:int in range(3):
		var start:float=-slot*2.0+MV.SHUFFLE_PERIOD*4.0
		expect(MV.shuffle_phase(slot,start+MV.SHUFFLE_LENGTH*0.5)>0.0,"slot %d shuffles inside its window"%slot)
		expect(MV.shuffle_phase(slot,start+MV.SHUFFLE_LENGTH+0.1)==0.0,"slot %d still outside its window"%slot)
		expect(MV.shuffle_phase(slot,start+MV.SHUFFLE_PERIOD-0.1)==0.0,"slot %d still just before the next window"%slot)
		var periodic:=true
		var e:=0.013  # grid offset keeps samples away from the window edges
		while e<MV.SHUFFLE_PERIOD:
			if not is_equal_approx(MV.shuffle_phase(slot,e),MV.shuffle_phase(slot,e+MV.SHUFFLE_PERIOD*3.0)):periodic=false
			e+=0.05
		expect(periodic,"slot %d shuffle is periodic"%slot)
	# Staggered: at most one guest shuffles at any time, and every slot does at some time.
	var seen:={}
	var overlap:=false
	var e2:=0.013
	while e2<MV.SHUFFLE_PERIOD:
		var active:=0
		for slot in range(3):
			if MV.shuffle_phase(slot,e2)>0.0:
				active+=1
				seen[slot]=true
		if active>1:overlap=true
		e2+=0.05
	expect(not overlap and seen.size()==3,"Three slots shuffle in staggered windows")
	expect(MV.SLOTS.size()==MV.MAX_SHOWN and MV.FACINGS.size()==MV.MAX_SHOWN and MV.TINTS.size()==MV.MAX_SHOWN,"SLOTS/FACINGS/TINTS sizes == MAX_SHOWN")
	for i in range(MV.MAX_SHOWN):
		var offset:Vector2=MV.SLOTS[i]
		expect(offset.y>=1.0,"Slot %d foot position %s is not inside the stall cell"%[i,str(offset)])
		expect(typeof(MV.FACINGS[i])==TYPE_VECTOR2I and typeof(MV.TINTS[i])==TYPE_COLOR,"Slot %d facing/tint types"%i)
		for j in range(i+1,MV.MAX_SHOWN):expect(MV.SLOTS[i]!=MV.SLOTS[j],"Slots %d and %d differ"%[i,j])

# 2a. plan returns nothing for locked, missing, garbage or zero stalls.
func test_plan_rejects()->void:
	var t:=DAY*2+300.0
	expect(MV.plan({},t).is_empty(),"Empty view -> no guests")
	expect(MV.plan({"unlocked":true},t).is_empty(),"Missing stalls_today -> no guests")
	expect(MV.plan(make_view({"unlocked":false,"stalls_today":3}),t).is_empty(),"Locked view -> no guests")
	expect(MV.plan({"stalls_today":3},t).is_empty(),"Missing unlocked -> no guests")
	for garbage in ["2","",[],[1,2],{},{"n":2},null,Vector2(1,1)]:
		expect(MV.plan(make_view({"stalls_today":garbage}),t).is_empty(),"stalls_today %s -> no guests"%var_to_str(garbage))
	expect(MV.plan(make_view({"stalls_today":0}),t).is_empty(),"0 stalls -> no guests")
	expect(MV.plan(make_view({"stalls_today":-2}),t).is_empty(),"Negative stalls -> no guests")
	expect(MV.plan(make_view({"stalls_today":1.0}),t).size()==2,"Float 1.0 stalls (JSON) -> 2 guests")
	expect(MV.plan(make_view({"stalls_today":2.0}),t).size()==3,"Float 2.0 stalls (JSON) -> 3 guests")

func check_guests(guests:Array,label:String,now:float)->void:
	var wishes:=0
	var last_slot:=-1
	for entry in guests:
		expect(entry is Dictionary,label+": guest is a dictionary")
		if not entry is Dictionary:continue
		var guest:Dictionary=entry
		var keys:Array=guest.keys()
		keys.sort()
		expect(keys==GUEST_KEYS,label+": guest keys %s"%str(keys))
		expect(typeof(guest.get("slot"))==TYPE_INT and typeof(guest.get("offset"))==TYPE_VECTOR2 and typeof(guest.get("facing"))==TYPE_VECTOR2I and typeof(guest.get("tint"))==TYPE_COLOR and typeof(guest.get("wish"))==TYPE_STRING,label+": guest field types")
		var slot:=int(guest.get("slot",-1))
		expect(slot>last_slot and slot>=0 and slot<MV.MAX_SHOWN,label+": slots ascending and in range")
		last_slot=slot
		if slot<0 or slot>=MV.MAX_SHOWN:continue
		expect(guest.offset==MV.SLOTS[slot] and guest.facing==MV.FACINGS[slot] and guest.tint==MV.TINTS[slot],label+": slot %d uses its constants"%slot)
		var wish:=str(guest.get("wish",""))
		if not wish.is_empty():
			wishes+=1
			expect(Market.sellable(wish) and Market.category_of(wish)==Market.theme_of(Market.day(now)),label+": wish %s is a sellable item of today's theme"%wish)
	expect(wishes==1,label+": exactly one guest has a wish (%d)"%wishes)

# 2b. Guest counts, rotation, wishes, determinism, no mutation.
func test_plan_shapes()->void:
	var present:={}
	var absent:={}
	for d:int in range(5):
		for part:int in range(MV.PARTS):
			var t:float=DAY*d+part*(DAY/MV.PARTS)+10.0
			var one:Array=MV.plan(make_view({"stalls_today":1}),t)
			expect(one.size()==2,"1 stall day %d part %d -> 2 guests"%[d,part])
			check_guests(one,"1 stall d%d p%d"%[d,part],t)
			var here:={}
			for guest:Dictionary in one:here[int(guest.slot)]=true
			for slot in range(MV.MAX_SHOWN):
				if here.has(slot):present[slot]=true
				else:absent[slot]=true
			for n in [2,3,9]:
				var many:Array=MV.plan(make_view({"stalls_today":n}),t)
				expect(many.size()==3,"%d stalls day %d part %d -> 3 guests"%[n,d,part])
				check_guests(many,"%d stalls d%d p%d"%[n,d,part],t)
	expect(present.size()==3 and absent.size()==3,"With 1 stall every slot is absent at some time and present at some time")
	# Determinism and no mutation.
	var v:=make_view({"stalls_today":2,"stock":{"radish":3},"report":{"sold":{"radish":1}}})
	var before:=var_to_str(v)
	var a:Array=MV.plan(v,DAY*7+500.0)
	var b:Array=MV.plan(v,DAY*7+500.0)
	expect(var_to_str(a)==var_to_str(b),"plan is deterministic")
	expect(var_to_str(v)==before,"plan does not mutate its input")
	(a[0] as Dictionary).wish="mutated"
	expect(var_to_str(MV.plan(v,DAY*7+500.0))==var_to_str(b),"Mutating a returned guest does not leak into later plans")
	# A price table without items of today's theme -> no wish at all (day 0 is produce).
	var flowers_only:={"bluebell":28,"chime_herb":30}
	var nowish:Array=MV.plan(make_view({"stalls_today":2}),100.0,flowers_only)
	var any_wish:=false
	for guest:Dictionary in nowish:
		if not str(guest.wish).is_empty():any_wish=true
	expect(nowish.size()==3 and not any_wish,"No item in today's theme -> 3 guests, no wish")

# 3. wish_item.
func test_wish_item()->void:
	for theme:String in Market.THEMES:
		var count:=0
		for item:String in Market.sellable_items():
			if Market.category_of(item)==theme:count+=1
		var seen:={}
		var ok:=true
		for d in range(9):
			for part in range(MV.PARTS):
				var wish:=MV.wish_item(theme,d,part)
				if Market.category_of(wish)!=theme:ok=false
				seen[wish]=true
		expect(count>0 and ok,"wish_item(%s) always returns an item of that category"%theme)
		expect(count<=1 or seen.size()>1,"wish_item(%s) varies across days/parts (%d distinct of %d)"%[theme,seen.size(),count])
	expect(MV.wish_item("toys",0,0)=="" and MV.wish_item("",3,2)=="","Unknown theme -> empty wish")
	expect(MV.wish_item("produce",-4,-7)!="","Negative day/part still picks an item")
	expect(MV.wish_item("produce",0,0,{"radish":10,"bluebell":5})=="radish","Custom price table: only radish is produce")
	expect(MV.wish_item("dish",0,0,{"radish":10,"bluebell":5})=="","Custom price table without dishes -> empty")

# 4. status_line / summary_lines.
func test_summary_lines()->void:
	var head:String="今日主題：%s（主題商品＋30%%） · 明日主題：%s"%["料理","花"]
	expect(MV.summary_lines({}).is_empty() and MV.summary_lines(make_view({"unlocked":false})).is_empty(),"Locked -> no summary lines")
	var fresh:Array=MV.summary_lines(make_view({}))
	expect(fresh==[head,"今天還沒開張 · 攤上沒有東西","待領營收 0 鈴幣 · 累計營收 0 鈴幣","上一輪結算：還沒有結算紀錄"],"Fresh view: 4 lines %s"%str(fresh))
	var stocked:=make_view({"stock":{"radish":5},"stock_count":5})
	expect(MV.status_line(stocked)=="今天還沒開張 · 攤上有 %d 件，到廣場西側的攤位開張"%5,"Stocked but closed status")
	expect(MV.summary_lines(stocked).size()==4 and MV.summary_lines(stocked)[1]==MV.status_line(stocked),"Stocked summary uses status_line")
	var open:=make_view({"open":true,"pending":true,"stock":{"soup":7},"stock_count":7,"stalls_today":2,"visitors_estimate":5})
	expect(MV.status_line(open)=="今天營業中 · 攤上 %d 件 · 全島 %d 攤開張 · 預估來客 %d 位，午夜結算"%[7,2,5],"Open status: "+MV.status_line(open))
	expect(MV.status_line(make_view({"pending":true,"stock_count":3}))=="上一輪還在結算","Pending (opened another day) status")
	var paid:Array=MV.summary_lines(make_view({"till":96,"total":300}))
	expect(paid.size()==4 and paid[2]=="待領營收 %d 鈴幣 · 累計營收 %d 鈴幣（到攤位領取）"%[96,300],"Till > 0 adds the collect hint: "+str(paid))
	var report:={"day":3,"theme":"produce","visitors":5,"stalls":2,"coins":148,"sold":{"radish":2,"carp":1,"egg":2}}
	var names:={"radish":"白蘿蔔","carp":"鯉魚"}
	var reported:Array=MV.summary_lines(make_view({"report":report,"total":148,"till":148}),names)
	expect(reported.size()==5,"With a report: 5 lines")
	if reported.size()==5:
		expect(reported[3]=="上一輪結算・第 %d 日（%s）：來客 %d 位 · %d 攤同場 · 收入 %d 鈴幣"%[4,"農漁產",5,2,148],"Report line: "+str(reported[3]))
		expect(reported[4]=="賣出：%s"%"、".join(PackedStringArray(["鯉魚 ×1","egg ×2","白蘿蔔 ×2"])),"Sold line sorted by id with names: "+str(reported[4]))
	var empty_sold:Array=MV.summary_lines(make_view({"report":{"day":0,"theme":"flower","visitors":8,"stalls":1,"coins":0,"sold":{}}}))
	expect(empty_sold.size()==5 and empty_sold[4]=="賣出：這一輪沒有賣出","Empty sold -> 這一輪沒有賣出")
	if empty_sold.size()==5:expect(str(empty_sold[3]).contains("第 1 日（花）"),"Report day 0 shows as 第 1 日 with the flower name")
	expect(MV.summary_lines(make_view({"report":[]})).back()=="上一輪結算：還沒有結算紀錄","Non-dictionary report -> no report lines")

## Expected report lines built from a real market_view report.
static func report_lines(report:Dictionary,names:Dictionary)->Array:
	var sold:Dictionary=report.get("sold",{})
	var keys:Array=sold.keys()
	keys.sort()
	var parts:=PackedStringArray()
	for item in keys:parts.append("%s ×%d"%[str(names.get(item,item)),int(sold[item])])
	var theme:=str(report.get("theme",""))
	return ["上一輪結算・第 %d 日（%s）：來客 %d 位 · %d 攤同場 · 收入 %d 鈴幣"%[int(report.get("day",0))+1,str(Market.CATEGORY_NAMES.get(theme,theme)),int(report.get("visitors",0)),int(report.get("stalls",0)),int(report.get("coins",0))],
		"賣出：%s"%("、".join(parts) if not parts.is_empty() else "這一輪沒有賣出")]

## plan/summary_lines over world views must not change world state.
func read_only(w,tokens:Array,label:String)->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	for token:String in tokens:
		var v:=view(w,token)
		var _guests:Array=MV.plan(v,now_of(w))
		var _lines:Array=MV.summary_lines(v,{"radish":"x"})
		var _status:String=MV.status_line(v)
	expect(var_to_bytes(w.state)==before,label+": plan/summary_lines leave world state byte-identical")

# 5. Real World integration.
func test_world_integration()->void:
	var a:="visitor_ann"
	var b:="visitor_bob"
	var w:=make_world([a,b],1,false)
	expect(MV.plan(view(w,a),now_of(w)).is_empty() and MV.summary_lines(view(w,a)).is_empty(),"Before the picnic: no guests, no journal card")
	read_only(w,[a,b],"Locked world")
	w.state.picnic=true
	var cell:=stall(w)
	expect(cell!=Market.NO_CELL,"Stall cell exists after the picnic")
	expect(MV.plan(view(w,a),now_of(w)).is_empty() and MV.plan(view(w,b),now_of(w)).is_empty(),"Unlocked, nothing open: no guests")
	var fresh:Array=MV.summary_lines(view(w,a))
	expect(fresh.size()==4 and str(fresh.back())=="上一輪結算：還沒有結算紀錄","Unlocked fresh journal card")
	read_only(w,[a,b],"Unlocked idle world")
	stand(w,a,cell)
	expect(bool(act(w,a,"market_stock",cell,"soup:4").get("ok",false)),"Ann stocks soup via World.act")
	expect(bool(act(w,a,"market_stock",cell,"radish:2").get("ok",false)),"Ann stocks radish via World.act")
	expect(MV.plan(view(w,a),now_of(w)).is_empty(),"Stocked but not open: no guests")
	expect(bool(act(w,a,"market_open",cell,"").get("ok",false)),"Ann opens via World.act")
	var va:=view(w,a)
	var vb:=view(w,b)
	var ga:Array=MV.plan(va,now_of(w))
	var gb:Array=MV.plan(vb,now_of(w))
	expect(ga.size()==2 and gb.size()==2,"One open stall: 2 guests in both players' views (%d/%d)"%[ga.size(),gb.size()])
	check_guests(ga,"World 1 stall",now_of(w))
	expect(var_to_str(ga)==var_to_str(gb),"Both players see the same guests")
	expect(vb.stock.is_empty() and int(vb.stock_count)==0 and int(vb.till)==0 and vb.open==false and vb.report.is_empty(),"Bob's view carries none of Ann's stock/till")
	expect(not str(MV.summary_lines(vb)).contains("攤上有 6") and MV.status_line(vb)=="今天還沒開張 · 攤上沒有東西","Bob's card does not show Ann's stock")
	expect(MV.status_line(va)=="今天營業中 · 攤上 %d 件 · 全島 %d 攤開張 · 預估來客 %d 位，午夜結算"%[6,1,int(va.visitors_estimate)],"Ann's status line: "+MV.status_line(va))
	read_only(w,[a,b],"One stall open")
	stand(w,b,cell)
	expect(bool(act(w,b,"market_stock",cell,"bluebell:3").get("ok",false)),"Bob stocks bluebell via World.act")
	expect(bool(act(w,b,"market_open",cell,"").get("ok",false)),"Bob opens via World.act")
	var g3:Array=MV.plan(view(w,a),now_of(w))
	expect(g3.size()==3 and MV.plan(view(w,b),now_of(w)).size()==3,"Two open stalls: 3 guests")
	check_guests(g3,"World 2 stalls",now_of(w))
	read_only(w,[a,b],"Two stalls open")
	# PRESET: jump to one second before midnight, then really step across it.
	w.state.time=DAY*2.0-1.0
	expect(MV.plan(view(w,a),now_of(w)).size()==3,"Just before midnight guests are still there")
	var steps:=0
	while Market.day(now_of(w))<2 and steps<10:
		expect(w.step(0.5,true),"World.step tick %d succeeds"%steps)
		steps+=1
	expect(Market.day(now_of(w))==2,"World.step crossed midnight (%d ticks)"%steps)
	var after:=view(w,a)
	expect(MV.plan(after,now_of(w)).is_empty() and MV.plan(view(w,b),now_of(w)).is_empty(),"After midnight settlement: no guests")
	var report:Dictionary=after.report
	expect(not report.is_empty() and int(report.get("stalls",0))==2 and int(report.get("visitors",0))==Market.visitors_for(2),"Ann's report: 2 stalls, %d visitors (%s)"%[Market.visitors_for(2),str(report)])
	var names:={"soup":"蔬菜湯","radish":"白蘿蔔"}
	var lines:Array=MV.summary_lines(after,names)
	expect(lines.size()==5,"Owner's card has the report lines (%d)"%lines.size())
	if lines.size()==5:expect(lines.slice(3)==report_lines(report,names),"Report lines match market_view.report: %s"%str(lines.slice(3)))
	expect(lines.size()>=3 and lines[1]==MV.status_line(after) and lines[2]=="待領營收 %d 鈴幣 · 累計營收 %d 鈴幣%s"%[int(after.till),int(after.total),"（到攤位領取）" if int(after.till)>0 else ""],"Owner's status and money lines after settlement")
	var vb2:=view(w,b)
	var lb:Array=MV.summary_lines(vb2)
	expect(lb.size()==5 and lb.slice(3)==report_lines(vb2.report,{}),"Bob's card shows his own report")
	read_only(w,[a,b],"Settled world")
