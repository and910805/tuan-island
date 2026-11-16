extends "res://tests/test_flower_journey.gd"
## Chapter 4 Beimen salt pans: EARNED headless World journey (flower_exec_salt_journey).
##
## PROGRAM VERIFICATION WITH AN ACCELERATED IN-PROCESS CLOCK, NOT HUMAN PACING.
## The unmodified earned flower journey (test_flower_journey.gd, its own
## assertions included) runs first; the SAME `world` then continues into the salt
## chapter. Only World.act (after walking passable tiles with World.move_player),
## validated transit actions and World.step(dt,true) are used; waits are
## compressed by calling step() in chunks. No item, coin, flag or record is ever
## injected: gate materials come from axe/pick, the bench, the reinforced pick,
## the copper practice vein, copper joints and a sawmill; minnows from
## fish_start/fish_catch; salt_grilled_fish from the stove cook flow.
## Every extra islander (C..L) also EARNS chapters one-to-three prerequisites
## through the tea route and the flower nursery (each frees their nursery beds
## afterwards), so no seeded-prerequisite helper is used.
##
## Player A: salt_letter -> transit home->tianwei->beimen -> intro -> gates (A gives
## most, flower late joiner B closes the last gap) -> manual pool flood, rainy day
## (flood refused, brine dilutes, salt kept and raked in rain) -> claim lot ->
## wheel kit (craft gate checked before the first rake) -> wheel pan hand-raked ->
## rake kit -> chest + cfg + on -> automatic delivery; full / invalid / off /
## recovery -> fish minnows, cook, salt_order (120 once) -> salt_report -> note ->
## releases the lot. Saves are reloaded into new Worlds mid-brine and while the
## automation runs (byte comparison + identical continued progress).
## Saturation: C..J claim all 8 private lots, K earns manual -> wheel -> automatic
## delivery on the apprentice station with own kits, takes the cooperative box,
## orders and reports; L waits (busy message) and takes the shift afterwards.
## Prints SALT_PAN_JOURNEY_TESTS checks=N failures=M and quits 1 on failure.

const S=preload("res://scripts/salt_pan.gd")
const SALT_LABEL:="program verification: earned actions, accelerated in-process clock (not human pacing)"
const TRACK:=["sea_salt","plank","resin","stone","salt_wheel_kit","salt_rake_kit","minnow","salt_grilled_fish"]
const KIT_IDS:=["salt_wheel_kit","salt_rake_kit"]
const EXTRA:=["c","d","e","f","g","h","i","j","k","l"]
const EXPECTED_SALT_A:=["letter","travel","intro","gates","first_salt","claim","wheel","rake","automate","order","report","complete"]
const EXPECTED_SALT_B:=["letter","travel","intro","gates","first_salt"]
const EXPECTED_SALT_OWNER:=["letter","travel","intro","first_salt","claim","wheel"]
const EXPECTED_SALT_K:=["letter","travel","intro","first_salt","claim","wheel","rake","automate","order","report","complete"]
const EXPECTED_SALT_L:=["letter","travel","intro","first_salt","claim","wheel","claim","wheel","claim"]

var started_ms:=0
## token -> {item:int,...,"coins":int} expected salt-chapter holdings.
var sledger:={}
var salt_phases:={}
var salt_reloads:=0
var consumed_salt:=0
var crafted:={"salt_wheel_kit":0,"salt_rake_kit":0}
var last_tenant:=""
var last_app_kits:={"wheel":false,"rake":false}
var bench_cell:=Vector2i(-1,-1)
var saw_cells:={}
var stove_cell:=Vector2i(40,34)
var names:={}

func _initialize() -> void:
	started_ms=Time.get_ticks_msec()
	super._initialize()

func finish() -> void:
	var runtime:=Time.get_ticks_msec()-started_ms
	print("SALT_PAN_JOURNEY label=\"%s\" actions=%d walk_tiles=%d reloads=%d salt_reloads=%d world_seconds=%.1f runtime_ms=%d"%[SALT_LABEL,actions,walking,reloads,salt_reloads,float(world.state.get("time",0.0)),runtime])
	for token in salt_phases:print("SALT_PAN_JOURNEY phases %s=%s"%[token,JSON.stringify(salt_phases[token])])
	print("SALT_PAN_JOURNEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

func expect(condition:bool,message:String) -> bool:
	checks+=1
	if not condition:
		failures+=1
		failed=true
		push_error("SALT_PAN_JOURNEY FAIL: "+message)
	return condition

# ---------------------------------------------------------------- journey

func run() -> void:
	super.run()
	if failed:return
	print("SALT_PAN_JOURNEY flower prerequisite journey passed (checks so far %d, world_seconds %.1f)"%[checks,float(world.state.time)])
	names[TOKEN_A]="Bloom A"
	names[TOKEN_B]="Bloom B"
	for token in [TOKEN_A,TOKEN_B]:ledger_on[token]=false
	old_ids()
	salt_a_start()
	if failed:return
	salt_b_last_gap()
	if failed:return
	salt_a_manual()
	if failed:return
	salt_a_machines()
	if failed:return
	salt_a_order_report()
	if failed:return
	salt_a_release()
	if failed:return
	saturate()
	if failed:return
	apprentice()
	if failed:return
	var gate_events:=0
	for line in world.state.events:
		if str(line)==S.GATE_EVENT:gate_events+=1
	expect(gate_events==1,"exactly one gate repair event (got %d)"%gate_events)
	expect_same(salt_phases[TOKEN_A],EXPECTED_SALT_A,"player A salt phase sequence")
	expect_same(salt_phases[TOKEN_B],EXPECTED_SALT_B,"player B salt phase sequence")
	for id in EXTRA.slice(0,8):expect_same(salt_phases[tk(id)],EXPECTED_SALT_OWNER,"lot owner %s salt phases"%id)
	expect_same(salt_phases[tk("k")],EXPECTED_SALT_K,"apprentice K salt phases")
	expect_same(salt_phases[tk("l")],EXPECTED_SALT_L,"waiting L salt phases")
	salt_reload("final",0.0)

func old_ids() -> void:
	expect_same(World.RECIPES.grilled_fish,{"name":"香煎鯽魚","ingredients":{"carp":1},"time":10.0,"yield":1},"grilled_fish recipe unchanged")
	expect(int(World.OTHER_SALES.grilled_fish)==26 and World.NAMES.grilled_fish=="香煎鯽魚","grilled_fish price/name unchanged")
	expect_same(World.RECIPES.salt_grilled_fish,S.RECIPE.salt_grilled_fish,"salt_grilled_fish recipe matches SaltPan")
	expect(int(World.OTHER_SALES.salt_grilled_fish)==S.SALT_FISH_PRICE,"salt_grilled_fish sells 34")
	expect(not World.OTHER_SALES.has("sea_salt") and not World.CROPS.has("sea_salt") and not World.FISH.has("sea_salt"),"sea_salt is never sellable")
	for kit in KIT_IDS:expect_same(World.CRAFT[kit],S.CRAFT[kit],kit+" craft recipe matches SaltPan")

# ---------------------------------------------------------------- player A

func salt_a_start() -> void:
	tok=TOKEN_A
	start_salt(TOKEN_A)
	expect(S.phase(world.state,tok)=="letter","A: salt chapter opens at the letter after the flower chapter")
	expect(world.player_region(tok)=="home","A starts at home")
	# Everything A needs for gates (2 full + planks of the third), both kits and the chest.
	produce({"plank":32,"resin":4,"stone":14,"fiber":4,"copper_joint":3,"wood_extra":20})
	if failed:return
	refuse_salt("craft",bench_cell,"salt_wheel_kit",S.CRAFT_LOCKED_MESSAGE)
	refuse_salt("salt_order",S.XIAOLI_HOME,"","先在渡口向小栗收下北門寄來的信。")
	refuse_salt("sell",RECEIVER,"sea_salt","這件商品尚未上架")
	sact("salt_letter",S.XIAOLI_HOME)
	refuse_salt("salt_letter",S.XIAOLI_HOME,"","北門的信已收下，可從手帳重看。")
	expect(S.phase(world.state,tok)=="travel","A: phase travel after the letter")
	strav(FERRY,"tianwei")
	expect(travel_has("tianwei",tianwei_cell(),S.REGION),"A: beimen listed at the tianwei transfer after the letter")
	strav(tianwei_cell(),S.REGION)
	expect(Vector2(person().x,person().y)==S.ARRIVAL,"A arrived at the salt-field stop")
	refuse_salt("salt_gate_give",gate_cell(0),"plank","先到合作社工寮前和阿曬打聲招呼。")
	refuse_salt("build",Vector2i(30,18),"chest",S.REJECT_MESSAGE)
	refuse_salt("axe",Vector2i(30,18),"",S.REJECT_MESSAGE)
	sact("salt_intro",S.SALT_WORKER)
	expect(S.phase(world.state,tok)=="gates","A: phase gates after intro")
	refuse_salt("salt_flood",pan_cell(16),"","閘門還沒修好，海水引不進來。")
	refuse_salt("salt_claim",pan_cell(0),"","先在保留手作池親手收一次鹽，阿曬才會分鹽田區給你。")
	refuse_salt("salt_gate_give",gate_cell(0),"wood","請選擇要捐的材料：木板、樹脂或石材。")
	for g in 2:
		for item in S.GATE_MATERIALS:give_gate(g,item)
	give_gate(2,"plank")
	refuse_salt("salt_gate_give",gate_cell(0),"plank","這道閘門已經不缺這項材料。")
	expect(not S.repaired(world.state) and S.phase(world.state,tok)=="gates","A alone has not repaired the third gate")

func give_gate(g:int,item:String) -> void:
	var had:=int(world.state.salt_pan.gates[g][item])
	var take:=mini(int(S.GATE_NEEDS_EACH[item])-had,int(bag().get(item,0)))
	expect(take>0,"%s has %s for gate %d"%[tok,item,g])
	sact("salt_gate_give",gate_cell(g),item,{item:-take})
	expect(int(world.state.salt_pan.gates[g][item])==had+take,"gate %d %s +%d recorded"%[g,item,take])
	expect(world.state.salt_pan.givers.get(tok)==true,"%s recorded as a gate giver"%tok)

# ---------------------------------------------------------------- player B (last gap)

func salt_b_last_gap() -> void:
	tok=TOKEN_B
	start_salt(TOKEN_B)
	expect(world.player_region(tok)==F.REGION,"B finished the flower chapter in tianwei")
	expect(not travel_has(F.REGION,tianwei_cell(),S.REGION),"beimen hidden from B before B's letter")
	strav(tianwei_cell(),"home")
	gather({"resin":1,"stone":4})
	sact("salt_letter",S.XIAOLI_HOME)
	strav(FERRY,"tianwei")
	strav(tianwei_cell(),S.REGION)
	sact("salt_intro",S.SALT_WORKER)
	var events_before:int=world.state.events.size()
	give_gate(2,"stone")
	expect(not S.repaired(world.state),"third gate still needs resin")
	var held:=int(bag().get("resin",0))
	var result:=sact("salt_gate_give",gate_cell(2),"resin",{"resin":-1})
	expect(held>=1 and str(result.message).contains("三道閘門都修好了") and result.get("event")==S.GATE_EVENT,"B's resin closes the last gap: "+str(result.message))
	expect(float(world.state.salt_pan.repaired_at)==float(world.state.time),"repaired_at is the donation time")
	expect(world.state.events.size()==events_before+1 and world.state.events.back()==S.GATE_EVENT,"gate event appended exactly once")
	expect(world.state.salt_pan.givers.has(TOKEN_A) and world.state.salt_pan.givers.has(TOKEN_B),"both A and B are gate givers")
	for g in 3:expect(S.gate_full(world.state.salt_pan.gates[g]),"gate %d full"%g)
	refuse_salt("salt_gate_give",gate_cell(2),"stone","這道閘門已經不缺這項材料。")
	expect(S.phase(world.state,TOKEN_A)=="first_salt" and S.phase(world.state,TOKEN_B)=="first_salt","A and B move to first_salt")

# ---------------------------------------------------------------- A manual pool + rain

func salt_a_manual() -> void:
	tok=TOKEN_A
	if raining():
		refuse_salt("salt_flood",pan_cell(16),"",S.RAIN_FLOOD_MESSAGE)
		wait(next_midnight()-now())
	sact("salt_flood",pan_cell(16))
	var pan16:Dictionary=world.state.salt_pan.pans[16]
	expect(pan16.s=="brine" and pan16.f=="hand" and float(pan16.t)==now(),"public pan 16 flooded by hand")
	refuse_salt("salt_flood",pan_cell(16),"","這方鹽田已經有海水或鹽了。")
	refuse_salt("salt_rake",pan_cell(16),"","鹽還沒結成，約 %d 分鐘後再來。"%maxi(1,S.eta(world.state.salt_pan.pans[16],now())))
	wait_until(func():return world.state.salt_pan.pans[16].s=="salt",120.0,5000.0,"pan 16 crystallises")
	# Next rainy day; pan 17 is flooded 200 s before it so it is still brine.
	var rain_day:=WEATHER.day_index(now())+1.0
	while WEATHER.outdoor_id(rain_day)!="rainy":rain_day+=1.0
	var rain_start:=rain_day*WEATHER.DAY_SECONDS
	wait(maxf(0.0,rain_start-200.0-now()))
	expect(not raining(),"flood time before the rain is dry")
	sact("salt_flood",pan_cell(17))
	wait(60.0)
	salt_reload("brine-mid-evaporation",100.0)
	if failed:return
	expect(world.state.salt_pan.pans[17].s=="brine","pan 17 still brine after the reload")
	wait(maxf(0.0,rain_start-now()))
	expect(raining(),"it is raining in beimen now")
	var before_view:=S.pan_view(world.state.salt_pan.pans[17],now())
	wait(300.0)
	var rain_view:=S.pan_view(world.state.salt_pan.pans[17],now())
	expect(rain_view.s=="brine" and rain_view.diluted and float(rain_view.ratio)<float(before_view.ratio),"brine dilutes in rain (%.3f -> %.3f)"%[float(before_view.ratio),float(rain_view.ratio)])
	var formed:Dictionary=world.state.salt_pan.pans[16]
	var formed_view:=S.pan_view(formed,now())
	expect(formed.s=="salt" and float(formed.p)==S.NEED and formed_view.covered,"formed salt survives the rain under straw mats")
	sact("salt_rake",pan_cell(16),"",{"sea_salt":S.YIELD})
	expect(int(S.own_record(world.state,tok).raked)==1,"A raked once (in rain)")
	refuse_salt("salt_flood",pan_cell(16),"",S.RAIN_FLOOD_MESSAGE)
	refuse_salt("salt_rake",pan_cell(16),"",S.RAKED_MESSAGE)
	expect(S.phase(world.state,tok)=="claim","A: phase claim after the first rake")
	refuse_salt("salt_claim",pan_cell(16),"",S.STATUS_TEXT.reserve)
	sact("salt_claim",pan_cell(0))
	expect(S.owned_lot(world.state,tok)==0,"A owns lot 0")
	refuse_salt("salt_claim",pan_cell(2),"","每位島民只能照顧一區鹽田區。")
	expect(S.phase(world.state,tok)=="wheel","A: phase wheel")

# ---------------------------------------------------------------- A machines

func salt_a_machines() -> void:
	tok=TOKEN_A
	var wheel_at:=S.wheel_socket(0).position
	var rake_at:=S.rake_socket(0).position
	var chest_at:=S.chest_sockets(0)[0]
	refuse_salt("salt_install",wheel_at,"wheel","背包沒有鹽田水車組，回家在工作台做一組。")
	strav(S.TRANSFER,"home")
	craft_kit("salt_wheel_kit")
	refuse_salt("craft",bench_cell,"salt_rake_kit",S.CRAFT_LOCKED_MESSAGE)
	strav(FERRY,S.REGION)
	refuse_salt("salt_install",wheel_at,"rake","水車要裝在水車座，收鹽台要裝在收鹽台座。")
	refuse_salt("salt_install",rake_at,"rake","先裝好水車，再裝收鹽台。")
	sact("salt_install",wheel_at,"wheel",{"salt_wheel_kit":-1})
	expect(status_id(tok)=="wheel_only","A lot status wheel_only")
	expect(S.phase(world.state,tok)=="rake","A: phase rake")
	wait_until(func():return wheel_salt_pan(0)>=0,120.0,6000.0,"wheel-filled pan crystallises")
	if failed:return
	var pan:=wheel_salt_pan(0)
	sact("salt_rake",pan_cell(pan),"",{"sea_salt":S.YIELD})
	expect(int(S.own_record(world.state,tok).wheel_raked)==1,"A hand-raked a wheel pan")
	strav(S.TRANSFER,"home")
	craft_kit("salt_rake_kit")
	strav(FERRY,S.REGION)
	sact("salt_install",rake_at,"rake",{"salt_rake_kit":-1})
	expect(status_id(tok)=="unset" and S.phase(world.state,tok)=="automate","A: rake installed, no chest chosen, phase automate")
	refuse_salt("salt_auto_toggle",rake_at,"",S.STATUS_TEXT.unset)
	refuse_salt("salt_auto_cfg",rake_at,"%d,%d|2"%[chest_at.x,chest_at.y],S.CAP_MESSAGE)
	refuse_salt("salt_auto_cfg",rake_at,"%d,%d|60"%[chest_at.x,chest_at.y],"請先在收鹽台旁的箱位放一個箱子。")
	# B may not build on A's chest socket.
	tok=TOKEN_B
	refuse_salt("build",S.chest_sockets(0)[1],"chest",World.SALT_SOCKET_MSG)
	tok=TOKEN_A
	sact("build",chest_at,"chest")
	sact("salt_auto_cfg",rake_at,"%d,%d|60"%[chest_at.x,chest_at.y])
	expect(status_id(tok)=="off","status off before enabling")
	sact("salt_auto_toggle",rake_at)
	expect(status_id(tok) in ["running","waiting","rain"],"status running/waiting/rain after enabling (%s)"%status_id(tok))
	wait(60.0)
	salt_reload("automation-running",900.0)
	if failed:return
	wait_until(func():return chest_salt(chest_at)>=S.YIELD,120.0,6000.0,"first automatic delivery")
	if failed:return
	var record:=S.own_record(world.state,tok)
	expect(int(record.auto_raked)>=1 and chest_salt(chest_at)==S.YIELD*int(record.auto_raked),"auto deliveries == chest salt (%d / %d)"%[int(record.auto_raked),chest_salt(chest_at)])
	expect(S.phase(world.state,tok)=="order","A: phase order after the first automatic delivery")
	# Full: cap 3 with salt already in the chest.
	refuse_salt("salt_auto_cfg",rake_at,"%d,%d|3"%[chest_at.x,chest_at.y],"先暫停收鹽台，再更換收鹽箱或上限。")
	sact("salt_auto_toggle",rake_at)
	sact("salt_auto_cfg",rake_at,"%d,%d|3"%[chest_at.x,chest_at.y])
	sact("salt_auto_toggle",rake_at)
	expect(status_id(tok)=="full","status full with a low cap")
	var full_salt:=chest_salt(chest_at)
	var full_auto:=int(S.own_record(world.state,tok).auto_raked)
	wait(1440.0)
	expect(chest_salt(chest_at)==full_salt and int(S.own_record(world.state,tok).auto_raked)==full_auto,"full chest: no delivery for a whole day")
	expect(lot_salt_pans(0)>=1,"salt waits in the pans while the chest is full")
	# Invalid: chest emptied and removed, then replaced by a new chest.
	while chest_salt(chest_at)>0 and not failed:sact("withdraw",chest_at,"sea_salt",{"sea_salt":1})
	sact("remove",chest_at)
	expect(status_id(tok)=="invalid","status invalid once the chest is removed")
	sact("build",chest_at,"chest")
	expect(status_id(tok)=="invalid","status invalid for a replacement chest")
	var pans_before:Array=world.state.salt_pan.pans.slice(0,2).duplicate(true)
	wait(600.0)
	expect(chest_salt(chest_at)==0 and int(S.own_record(world.state,tok).auto_raked)==full_auto,"invalid chest receives nothing")
	for i in 2:
		if pans_before[i].s=="salt":expect(world.state.salt_pan.pans[i].s=="salt","salt stays in pan %d while invalid"%i)
	# Off: nothing moves.
	sact("salt_auto_toggle",rake_at)
	expect(status_id(tok)=="off","status off")
	var off_pans:Array=world.state.salt_pan.pans.slice(0,2).duplicate(true)
	var off_salt:=lot_salt_pans(0)
	wait(600.0)
	expect(chest_salt(chest_at)==0 and lot_salt_pans(0)>=off_salt,"off: no collection, formed salt kept")
	for i in 2:
		if off_pans[i].s=="empty":expect(world.state.salt_pan.pans[i].s=="empty","off: wheel does not refill pan %d"%i)
	# Recover with the new chest.
	sact("salt_auto_cfg",rake_at,"%d,%d|60"%[chest_at.x,chest_at.y])
	sact("salt_auto_toggle",rake_at)
	wait_until(func():return chest_salt(chest_at)>=S.YIELD,120.0,6000.0,"delivery resumes after recovery")
	if failed:return
	expect(int(S.own_record(world.state,tok).auto_raked)>full_auto,"auto_raked grows after recovery")
	while chest_salt(chest_at)>0 and not failed:sact("withdraw",chest_at,"sea_salt",{"sea_salt":1})

# ---------------------------------------------------------------- A order + report

func salt_a_order_report() -> void:
	tok=TOKEN_A
	strav(S.TRANSFER,"home")
	order_flow()
	strav(FERRY,S.REGION)
	report_flow()
	sact("salt_note",S.HERITAGE_SIGN)
	expect(S.own_record(world.state,tok).note==true,"heritage note read")
	salt_reload("chapter-complete",0.0)

func order_flow() -> void:
	expect(S.phase(world.state,tok)=="order","%s: phase order"%tok)
	fish_minnows(2)
	var short:=PackedStringArray()
	for item in S.ORDER:
		var held:=int(bag().get(item,0))
		if held<int(S.ORDER[item]):short.append("%s還差 %d"%[S.ITEMS[item],int(S.ORDER[item])-held])
	expect(not short.is_empty(),"order not yet complete before cooking")
	refuse_salt("salt_order",S.XIAOLI_HOME,"","委託還不夠：%s。"%"、".join(short))
	for n in 2:
		sact("cook",stove_cell,"salt_grilled_fish",{"minnow":-1,"sea_salt":-1})
		refuse_salt("claim_cook",stove_cell,"","還要 15 秒就好了")
		wait(15.0)
		sact("claim_cook",stove_cell,"",{"salt_grilled_fish":1})
	expect(int(bag().get("sea_salt",0))>=4,"%s holds 4 sea salt for the order"%tok)
	sact("salt_order",S.XIAOLI_HOME,"",{"sea_salt":-4,"salt_grilled_fish":-2,"coins":S.ORDER_PAY})
	refuse_salt("salt_order",S.XIAOLI_HOME,"","海鹽委託已經交過了。")
	expect(S.phase(world.state,tok)=="report","%s: phase report"%tok)

func report_flow() -> void:
	refuse_salt("salt_order",S.XIAOLI_HOME,"",World.SALT_HOME_MSG)
	sact("salt_report",S.SALT_WORKER)
	refuse_salt("salt_report",S.SALT_WORKER,"","北門這一段已經完成，可從手帳重看。")
	expect(S.phase(world.state,tok)=="complete","%s: phase complete"%tok)

# ---------------------------------------------------------------- A releases the lot

func salt_a_release() -> void:
	tok=TOKEN_A
	var wheel_at:=S.wheel_socket(0).position
	var rake_at:=S.rake_socket(0).position
	var chest_at:=S.chest_sockets(0)[0]
	if world.state.salt_pan.lots[0].on:sact("salt_auto_toggle",rake_at)
	refuse_salt("salt_uninstall",wheel_at,"wheel","先拆下收鹽台，再拆水車。")
	sact("salt_uninstall",rake_at,"rake",{"salt_rake_kit":1})
	sact("salt_uninstall",wheel_at,"wheel",{"salt_wheel_kit":1})
	if lot_busy(0):refuse_salt("salt_release",pan_cell(0),"","先把兩方鹽田的鹽收完，再歸還鹽田區。")
	for i in 2:
		wait_until(func():return world.state.salt_pan.pans[i].s!="brine",120.0,6000.0,"lot 0 pan %d settles"%i)
		if world.state.salt_pan.pans[i].s=="salt":sact("salt_rake",pan_cell(i),"",{"sea_salt":S.YIELD})
	while chest_salt(chest_at)>0 and not failed:sact("withdraw",chest_at,"sea_salt",{"sea_salt":1})
	refuse_salt("salt_release",pan_cell(0),"","先把收鹽台旁的箱子搬走，再歸還鹽田區。")
	sact("remove",chest_at)
	sact("salt_release",pan_cell(0))
	expect_same(world.state.salt_pan.lots[0],S.fresh_lot(),"lot 0 back to fresh")
	expect(S.phase(world.state,tok)=="complete","release keeps A's completed record")

# ---------------------------------------------------------------- saturation C..J

func saturate() -> void:
	for id in EXTRA:
		earned_flower(tk(id))
		if failed:return
	for index in 8:
		var token:=tk(EXTRA[index])
		tok=token
		arrive(token)
		if failed:return
		public_rake()
		if failed:return
		if index==0:refuse_salt("salt_claim",pan_cell(18),"",S.FREE_LOT_MESSAGE)
		sact("salt_claim",pan_cell(index*2))
		expect(S.owned_lot(world.state,token)==index and S.phase(world.state,token)=="wheel","%s owns lot %d"%[token,index])
	expect(S.free_lots(world.state)==0,"all 8 private lots are taken")

## Fresh islander: chapter one is shared, so the tea route and the flower
## nursery are earned exactly like the flower late joiner, on nursery row 1.
func earned_flower(token:String) -> void:
	tok=token
	names[token]="Salt "+token.right(1).to_upper()
	world.add_player(token,str(names[token]))
	tea_route()
	if failed:return
	start_ledger()
	act("flower_letter",F.RECEIVER_HOME)
	travel(FERRY,Tea.YINGGE)
	travel(World.TRANSIT.points(Tea.YINGGE).transfer.cell,F.REGION)
	act("flower_intro",F.FARMER)
	grant(F.STARTER)
	var beds:Array[Vector2i]=[]
	for x in 6:beds.append(F.NURSERY_BEDS.position+Vector2i(x,1))
	var kinds:=["bluebell","bluebell","orange_blossom","orange_blossom","chime_herb","chime_herb"]
	for i in kinds.size():
		act("hoe",beds[i])
		plant(beds[i],kinds[i])
	grow(beds)
	for c in beds:harvest(c)
	for kind in F.FLOWERS:save_seed(kind)
	act("flower_ship",F.MARKET)
	for kind in F.ORDER:led(kind,-int(F.ORDER[kind]))
	coins_ledger[tok]+=F.ORDER_PAY
	act("flower_report",F.XINGHE)
	grant(F.MEMENTO)
	expect_bag("%s flower report"%token)
	expect(F.phase(world.state,token)=="complete","%s earned the flower chapter"%token)
	for c in beds:act("remove",c)
	ledger_on[token]=false

## From tianwei (end of the flower chapter) to the salt fields with the letter.
func arrive(token:String) -> void:
	tok=token
	start_salt(token)
	strav(tianwei_cell(),"home")
	sact("salt_letter",S.XIAOLI_HOME)
	strav(FERRY,"tianwei")
	strav(tianwei_cell(),S.REGION)
	sact("salt_intro",S.SALT_WORKER)

## Rake one salt pan of the public manual pool, flooding it first if needed.
func public_rake() -> void:
	var raked:=int(S.own_record(world.state,tok).raked)
	for guard in 200:
		if failed:return
		for i in [16,17]:
			if world.state.salt_pan.pans[i].s=="salt":
				sact("salt_rake",pan_cell(i),"",{"sea_salt":S.YIELD})
				expect(int(S.own_record(world.state,tok).raked)==raked+1,"%s raked on the public pool"%tok)
				return
		if not raining():
			for i in [16,17]:
				if world.state.salt_pan.pans[i].s=="empty":sact("salt_flood",pan_cell(i))
		wait(120.0)
	expect(false,"%s: public pool never produced salt"%tok)

# ---------------------------------------------------------------- apprentice K, waiting L

func apprentice() -> void:
	var k:=tk("k")
	var l:=tk("l")
	for token in [k,l]:
		tok=token
		arrive(token)
		if token==l:refuse_salt("salt_claim",pan_cell(18),"","先在保留手作池親手收一次鹽，阿曬才會分鹽田區給你。")
		public_rake()
		if failed:return
		refuse_salt("salt_claim",pan_cell(0),"",S.CLAIMED_MESSAGE)
		expect(S.phase(world.state,token)=="claim" and S.apprentice_eligible(world.state,token),"%s eligible for the apprentice station"%token)
	# K prepares both kits' materials at home first; only the wheel kit is unlocked.
	tok=k
	strav(S.TRANSFER,"home")
	produce({"plank":14,"resin":2,"stone":6,"fiber":4,"copper_joint":3,"wood_extra":0})
	if failed:return
	craft_kit("salt_wheel_kit")
	refuse_salt("craft",bench_cell,"salt_rake_kit",S.CRAFT_LOCKED_MESSAGE)
	strav(FERRY,S.REGION)
	sact("salt_claim",pan_cell(18))
	expect(world.state.salt_pan.apprentice.tenant==k and float(world.state.salt_pan.apprentice.since)==now(),"K holds the apprentice shift")
	expect(S.phase(world.state,k)=="wheel","K: phase wheel on the apprentice station")
	# L waits while K's shift runs: joins the fair waiting list at place 1.
	tok=l
	var minutes:=maxi(1,int(ceilf((float(world.state.salt_pan.apprentice.since)+S.SHIFT_SECONDS-now())/60.0)))
	var busy:=sact("salt_claim",pan_cell(18))
	expect(str(busy.message)==S.QUEUE_BUSY_FORMAT%[minutes,1] and S.queue_position(world.state,l)==1,"L joins the waiting list at place 1: "+str(busy.message))
	expect(world.state.salt_pan.apprentice.tenant==k,"K keeps the shift while L waits")
	refuse_salt("salt_claim",pan_cell(18),"",S.QUEUE_BUSY_FORMAT%[minutes,1])
	refuse_salt("salt_flood",pan_cell(18),"","學徒區正由另一位島民輪班。")
	tok=k
	var wheel_at:=S.wheel_socket(S.APPRENTICE_LOT).position
	var rake_at:=S.rake_socket(S.APPRENTICE_LOT).position
	sact("salt_install",wheel_at,"wheel",{"salt_wheel_kit":-1})
	expect(S.phase(world.state,k)=="rake","K: phase rake")
	wait_until(func():return wheel_salt_pan(S.APPRENTICE_LOT)>=0,120.0,6000.0,"apprentice wheel pan crystallises")
	if failed:return
	sact("salt_rake",pan_cell(wheel_salt_pan(S.APPRENTICE_LOT)),"",{"sea_salt":S.YIELD})
	expect(int(S.own_record(world.state,k).wheel_raked)==1,"K hand-raked a wheel pan")
	strav(S.TRANSFER,"home")
	craft_kit("salt_rake_kit")
	strav(FERRY,S.REGION)
	sact("salt_install",rake_at,"rake",{"salt_rake_kit":-1})
	expect(S.phase(world.state,k)=="automate","K: phase automate")
	refuse_salt("salt_auto_cfg",rake_at,"14,16|60","學徒區的鹽會收進合作社收鹽箱。")
	sact("salt_auto_cfg",rake_at,"%d,%d|60"%[S.APPRENTICE_CHEST.x,S.APPRENTICE_CHEST.y])
	sact("salt_auto_toggle",rake_at)
	expect(world.state.salt_pan.apprentice.tenant==k and float(world.state.salt_pan.apprentice.since)+S.SHIFT_SECONDS>now(),"K's shift still running before the delivery")
	wait_until(func():return world.state.salt_pan.apprentice.tenant!=k,60.0,6000.0,"K graduates on the first automatic delivery")
	if failed:return
	var box:=int(world.state.salt_pan.coop_box.get(k,0))
	expect(box>=S.YIELD and int(S.own_record(world.state,k).auto_raked)>=1,"cooperative box holds K's salt (%d)"%box)
	expect_same(world.state.salt_pan.apprentice,S.fresh_apprentice(),"apprentice station reset after graduation")
	expect(int(bag().get("salt_wheel_kit",0))==1 and int(bag().get("salt_rake_kit",0))==1,"K's own kits returned on graduation")
	expect(S.phase(world.state,k)=="order","K: phase order")
	tok=l
	refuse_salt("salt_box_take",S.APPRENTICE_CHEST,"","合作社收鹽箱裡沒有你的海鹽或機器組。")
	tok=k
	sact("salt_box_take",S.APPRENTICE_CHEST,"",{"sea_salt":box})
	expect(not world.state.salt_pan.coop_box.has(k),"K's compartment emptied")
	refuse_salt("salt_box_take",S.APPRENTICE_CHEST,"","合作社收鹽箱裡沒有你的海鹽或機器組。")
	refuse_salt("salt_claim",pan_cell(18),"","你已經會用收鹽台了，學徒區留給還在學的島民。")
	# L heads the list and takes the offered shift, which later expires.
	tok=l
	expect(float(world.state.salt_pan.waitlist.offer_at)+S.OFFER_SECONDS>now(),"L's offer window is still open")
	sact("salt_claim",pan_cell(18))
	expect(world.state.salt_pan.apprentice.tenant==l and S.queue_position(world.state,l)==0,"L takes the shift after K graduated")
	var l_record:=S.own_record(world.state,l)
	var expiry:=float(world.state.salt_pan.apprentice.since)+S.SHIFT_SECONDS
	wait(expiry-now()-1.0)
	expect(world.state.salt_pan.apprentice.tenant==l,"L's shift still runs 1 s before expiry")
	wait(2.0)
	expect(world.state.salt_pan.apprentice.tenant=="","L's shift expired after 3 game days")
	expect_same(S.own_record(world.state,l),l_record,"expiry keeps L's record")
	expect(S.phase(world.state,l)=="claim","L back to claim after expiry")
	sact("salt_claim",pan_cell(18))
	expect(world.state.salt_pan.apprentice.tenant==l,"L may re-take an empty shift")
	sact("salt_release",pan_cell(18))
	expect(world.state.salt_pan.apprentice.tenant=="","L released the shift")
	tok=k
	strav(S.TRANSFER,"home")
	order_flow()
	strav(FERRY,S.REGION)
	report_flow()

# ---------------------------------------------------------------- production

## Earned materials at home: trees, rocks, a bench, the reinforced pick, copper
## joints from the practice vein and planks from the player's own sawmill.
## Targets are what the player must HOLD afterwards for the salt chapter.
func produce(want:Dictionary) -> void:
	expect(world.player_region(tok)=="home","%s produces at home"%tok)
	var plank_jobs:=maxi(0,int(ceil((int(want.plank)-int(bag().get("plank",0)))/2.0)))
	var joints:=maxi(0,int(want.copper_joint)-int(bag().get("copper_joint",0)))
	var need_bench:=bench_cell==Vector2i(-1,-1)
	var need_pick:=int(bag().get("reinforced_pick",0))<1
	var wood:=int(want.wood_extra)+plank_jobs*4+joints+(20 if need_bench else 0)+(6 if need_pick else 0)+8
	var stone:=int(want.stone)+(5 if need_bench else 0)+(4 if need_pick else 0)+4
	var fiber:=int(want.fiber)+(2 if need_pick else 0)
	gather({"wood":wood,"stone":stone,"fiber":fiber,"resin":int(want.resin)})
	if failed:return
	if need_bench:
		bench_cell=open_cell()
		if not expect(bench_cell!=Vector2i(-1,-1),"open cell for a bench"):return
		sact("build",bench_cell,"bench",{"stone":-5})
	if need_pick:craft("reinforced_pick")
	while int(bag().get("copper_ore",0))<joints*2 and not failed:
		var ready:=float(world.state.copper.ready)-now()
		if ready>0.0:wait(ready)
		sact("pick",World.COPPER_CELL)
	for n in joints:craft("copper_joint")
	if plank_jobs>0:
		if not saw_cells.has(tok):
			craft("sawmill_kit")
			var cell:=open_cell()
			if not expect(cell!=Vector2i(-1,-1),"open cell for a sawmill"):return
			sact("build",cell,"sawmill")
			saw_cells[tok]=cell
		var saw:Vector2i=saw_cells[tok]
		for n in plank_jobs:
			sact("start_processing",saw,"plank")
			refuse_salt("claim_processing",saw,"","加工尚未完成")
			wait(float(World.INDUSTRY.PROCESS.plank.time))
			sact("claim_processing",saw,"",{"plank":int(World.INDUSTRY.PROCESS.plank.yield)})
	for item in ["plank","resin","stone","fiber","copper_joint"]:
		expect(int(bag().get(item,0))>=int(want[item]),"%s holds %s >= %d (has %d)"%[tok,item,int(want[item]),int(bag().get(item,0))])

func gather(want:Dictionary) -> void:
	for guard in 120:
		if failed:return
		var woody:=false
		for item in ["wood","fiber","resin"]:
			if want.has(item) and int(bag().get(item,0))<int(want[item]):woody=true
		if woody:
			hit_resource("tree")
			continue
		if want.has("stone") and int(bag().get("stone",0))<int(want.stone):
			hit_resource("rock")
			continue
		return
	expect(false,"%s could not gather %s"%[tok,JSON.stringify(want)])

func hit_resource(kind:String) -> void:
	var target:=find_resource(kind)
	if not expect(target!=Vector2i(-1,-1),"reachable "+kind):return
	var needed:=3 if kind=="tree" else 2
	for guard in needed:
		if failed or world.resource(target)!=kind:return
		var last:=int(world.state.damage.get(World.key(target),0))+1>=needed
		var delta:={}
		if last:delta={"resin":1} if kind=="tree" else {"stone":5}
		sact("axe" if kind=="tree" else "pick",target,"",delta)

func craft(recipe:String) -> void:
	var delta:={}
	for item in World.CRAFT[recipe].ingredients:delta[item]=-int(World.CRAFT[recipe].ingredients[item])
	delta[recipe]=int(delta.get(recipe,0))+int(World.CRAFT[recipe].yield)
	sact("craft",bench_cell,recipe,delta)

func craft_kit(kit:String) -> void:
	expect(S.craft_allowed(world.state,tok,kit),"%s may craft %s"%[tok,kit])
	craft(kit)

func fish_minnows(count:int) -> void:
	var spot:=water_spot()
	if not expect(spot!=Vector2i(-1,-1),"reachable fishing spot"):return
	var caught:=0
	for guard in 12:
		if failed or caught>=count:return
		sact("fish_start",spot)
		refuse_salt("fish_catch",spot,"","魚還沒咬鉤，再稍等一下")
		wait(3.0)
		var fish:String=World.Collections.FRESHWATER_FISH[int(person().get("fish_caught",0))%World.Collections.FRESHWATER_FISH.size()]
		sact("fish_catch",spot,"",{"minnow":1} if fish=="minnow" else {})
		if fish=="minnow":caught+=1
	expect(caught>=count,"%s caught %d minnows"%[tok,count])

func water_spot() -> Vector2i:
	for y in range(34,46):
		for x in [55,56]:
			var c:=Vector2i(x,y)
			if world.water(c) and not route(c).is_empty():return c
	return Vector2i(-1,-1)

## A free home tile with all eight neighbours standable (never seals a path).
func open_cell() -> Vector2i:
	var origin:=Vector2i(int(person().x),int(person().y))
	for distance in range(3,14):
		for y in range(origin.y-distance,origin.y+distance+1):
			for x in range(origin.x-distance,origin.x+distance+1):
				var c:=Vector2i(x,y)
				if maxi(absi(x-origin.x),absi(y-origin.y))!=distance:continue
				if not world.is_land(c) or world.water(c) or world.protected(c) or world.resource(c)!="" or world.blocked(c):continue
				var k:=World.key(c)
				if world.state.crops.has(k) or world.state.objects.has(k) or world.state.ground.has(k) or world.state.roofs.has(k) or world.state.forest.has(k):continue
				var open:=true
				for dy in [-1,0,1]:
					for dx in [-1,0,1]:
						var n:=c+Vector2i(dx,dy)
						var nk:=World.key(n)
						if world.blocked(n) or world.state.crops.has(nk) or world.protected(n):open=false
				if open and not route(c).is_empty():return c
	return Vector2i(-1,-1)

# ---------------------------------------------------------------- salt act helpers

func tk(id:String) -> String:
	return "salt-journey-"+id

func start_salt(token:String) -> void:
	var held:Dictionary=world.state.players[token].inventory
	var counts:={}
	for item in TRACK:counts[item]=int(held.get(item,0))
	counts.coins=int(world.state.players[token].coins)
	sledger[token]=counts
	salt_phases[token]=[]
	for item in ["sea_salt","salt_wheel_kit","salt_rake_kit","salt_grilled_fish"]:
		expect(int(held.get(item,0))==0,"%s holds no %s before the salt chapter"%[token,item])
	salt_check("start "+token)

func sact(action:String,target:Vector2i,extra:String="",delta:Dictionary={}) -> Dictionary:
	if failed:return {"ok":false,"message":"skipped"}
	var result:=act(action,target,extra)
	if result.ok:
		# World-wide counters change in the same transaction as the act.
		if action=="craft" and extra in KIT_IDS:crafted[extra]=int(crafted[extra])+1
		if action=="cook" and extra=="salt_grilled_fish":consumed_salt+=int(S.RECIPE.salt_grilled_fish.ingredients.sea_salt)
		if action=="salt_order":consumed_salt+=int(S.ORDER.sea_salt)
	if result.ok and sledger.has(tok):
		for item in delta:
			if sledger[tok].has(item):sledger[tok][item]=int(sledger[tok][item])+int(delta[item])
	salt_check("%s %s %s"%[tok,action,extra])
	return result

func refuse_salt(action:String,target:Vector2i,extra:String,message:String) -> void:
	refuse(action,target,extra,message)
	salt_check("refused "+action)

func strav(gate:Vector2i,destination:String) -> void:
	travel(gate,destination)
	salt_check("%s transit %s"%[tok,destination])

func wait(seconds:float,chunk:float=240.0) -> void:
	var left:=seconds
	while left>0.000001 and not failed:
		var dt:=minf(chunk,left)
		expect(world.step(dt,true),"world step %.1f"%dt)
		left-=dt
		salt_check("step")

func wait_until(condition:Callable,chunk:float,limit:float,label:String) -> void:
	var spent:=0.0
	while not failed:
		if condition.call():return
		if spent>=limit:
			expect(false,"timed out waiting: "+label)
			return
		wait(chunk)
		spent+=chunk

## Ledger, conservation and phase bookkeeping after every salt act / step.
func salt_check(label:String) -> void:
	if failed:return
	var data:Dictionary=world.state.salt_pan
	var app:Dictionary=data.apprentice
	if last_tenant!="" and str(app.tenant)!=last_tenant and sledger.has(last_tenant):
		# Shift end returns the tenant's installed kits (graduation / release).
		if last_app_kits.wheel:sledger[last_tenant].salt_wheel_kit=int(sledger[last_tenant].salt_wheel_kit)+1
		if last_app_kits.rake:sledger[last_tenant].salt_rake_kit=int(sledger[last_tenant].salt_rake_kit)+1
	last_tenant=str(app.tenant)
	last_app_kits={"wheel":app.wheel==true,"rake":app.rake==true}
	for token in sledger:
		var player:Dictionary=world.state.players[token]
		var got:={}
		for item in TRACK:got[item]=int(player.inventory.get(item,0))
		got.coins=int(player.coins)
		if got!=sledger[token]:
			expect(false,"%s: %s holdings %s != ledger %s"%[label,token,JSON.stringify(got),JSON.stringify(sledger[token])])
			return
	checks+=1
	# World-wide sea salt conservation: produced by rakes and collectors only.
	var produced:=0
	for token in data.players:produced+=S.YIELD*(int(data.players[token].raked)+int(data.players[token].auto_raked))
	var held:=0
	for token in world.state.players:held+=int(world.state.players[token].inventory.get("sea_salt",0))
	for layer in [world.state.objects]+world.state.regions.values().map(func(r):return r.objects):
		for obj in layer.values():
			if obj is Dictionary and obj.get("items") is Dictionary:held+=int(obj.items.get("sea_salt",0))
	for token in data.coop_box:held+=int(data.coop_box[token])
	if not expect(held==produced-consumed_salt,"%s: sea salt conserved (held %d, produced %d, consumed %d)"%[label,held,produced,consumed_salt]):return
	for kit in KIT_IDS:
		var part:="wheel" if kit=="salt_wheel_kit" else "rake"
		var count:=0
		for token in world.state.players:count+=int(world.state.players[token].inventory.get(kit,0))
		for lot in data.lots:
			if lot[part]==true:count+=1
		if app[part]==true:count+=1
		for token in data.kit_box:count+=int(data.kit_box[token].get(kit,0))
		if not expect(count==int(crafted[kit]),"%s: %s conserved (%d vs crafted %d)"%[label,kit,count,int(crafted[kit])]):return
	for token in salt_phases:
		var current:=S.phase(world.state,token)
		var seen:Array=salt_phases[token]
		if seen.is_empty() or seen.back()!=current:
			seen.append(current)
			on_salt_phase(token,current)

## Hook for the lead's capture harness (work/salt/lead/salt_earned_dump.gd).
func on_salt_phase(_token:String,_phase:String) -> void:
	pass

## Save, reload into a NEW World through SaveSchema, compare bytes, then run the
## old and the new world forward by `advance` seconds and require identical results.
func salt_reload(label:String,advance:float) -> void:
	if failed:return
	expect(world.save(),label+": explicit save")
	var reopened:=World.new()
	if not expect(reopened.load_world(save_path) and not reopened.recovered_from_backup,label+": save loads through SaveSchema"):return
	expect(int(reopened.state.version)==int(World.SAVE_SCHEMA.VERSION),label+": saved version is SaveSchema.VERSION")
	for token in world.active_tokens:reopened.add_player(token,str(names.get(token,world.state.players[token].name)))
	compare_worlds(world,reopened,label+" (on load)")
	if advance>0.0:
		var old:World=world
		old.save_path=""
		var before:=canon_bytes(reopened.state.salt_pan)
		var ratios_before:=pan_ratios(reopened)
		var left:=advance
		while left>0.000001 and not failed:
			var dt:=minf(120.0,left)
			expect(old.step(dt,true) and reopened.step(dt,true),label+": both worlds step")
			left-=dt
		compare_worlds(old,reopened,label+" (after %.0f s)"%advance)
		expect(canon_bytes(reopened.state.salt_pan)!=before or pan_ratios(reopened)>ratios_before,label+": salt pans progressed after the reload (ratio sum %.3f -> %.3f)"%[ratios_before,pan_ratios(reopened)])
	world=reopened
	salt_reloads+=1
	salt_check("reload "+label)

## Type-preserving value bytes with dictionary keys sorted and keys as String:
## a save is written with JSON.stringify (sorted String keys), while live code
## that assigns `dict.field = v` creates StringName keys. Values keep their types.
func canon_bytes(v:Variant) -> PackedByteArray:
	return var_to_bytes(_canon(v))

func _canon(v:Variant) -> Variant:
	if v is Dictionary:
		var keys:Array=v.keys()
		keys.sort_custom(func(x,y):return str(x)<str(y))
		var out:={}
		for k in keys:out[str(k)]=_canon(v[k])
		return out
	if v is Array:
		var out:=[]
		for item in v:out.append(_canon(item))
		return out
	return v

func compare_worlds(a:World,b:World,label:String) -> void:
	expect(canon_bytes(a.state.salt_pan)==canon_bytes(b.state.salt_pan),label+": salt_pan bytes identical "+first_diff(_canon(a.state.salt_pan),_canon(b.state.salt_pan),"salt_pan"))
	expect(canon_bytes(a.state.regions[S.REGION].objects)==canon_bytes(b.state.regions[S.REGION].objects),label+": beimen chests bytes identical "+first_diff(_canon(a.state.regions[S.REGION].objects),_canon(b.state.regions[S.REGION].objects),"objects"))
	expect(is_equal_approx(float(a.state.time),float(b.state.time)),label+": world time identical")
	for token in a.state.players:
		var ia:Variant=a.state.players[token].inventory
		var ib:Variant=b.state.players[token].inventory
		expect(canon_bytes(ia)==canon_bytes(ib),label+": inventory bytes identical for "+token+" "+first_diff(_canon(ia),_canon(ib),"inventory"))
		expect(int(a.state.players[token].coins)==int(b.state.players[token].coins) and a.state.players[token].region==b.state.players[token].region,label+": coins/region identical for "+token)

## First differing path including Variant types (diagnostics only).
func first_diff(a:Variant,b:Variant,path:String) -> String:
	if typeof(a)!=typeof(b):return "%s: %s(%s) vs %s(%s)"%[path,type_string(typeof(a)),str(a).left(80),type_string(typeof(b)),str(b).left(80)]
	if a is Dictionary:
		if a.keys()!=b.keys():return "%s keys %s vs %s"%[path,str(a.keys()).left(200),str(b.keys()).left(200)]
		for k in a:
			var d:=first_diff(a[k],b[k],path+"."+str(k))
			if d!="":return d
		return ""
	if a is Array:
		if a.size()!=b.size():return "%s size %d vs %d"%[path,a.size(),b.size()]
		for i in a.size():
			var d:=first_diff(a[i],b[i],"%s[%d]"%[path,i])
			if d!="":return d
		return ""
	return "" if a==b else "%s: %s vs %s"%[path,str(a),str(b)]

# ---------------------------------------------------------------- queries

## Sum of brine/salt progress ratios (lazy integration is not persisted until a transition).
func pan_ratios(w:World) -> float:
	var total:=0.0
	for pan in w.state.salt_pan.pans:total+=float(S.pan_view(pan,float(w.state.time)).ratio)
	return total

func now() -> float:
	return float(world.state.time)

func raining() -> bool:
	return S.raining(now())

func next_midnight() -> float:
	return (WEATHER.day_index(now())+1.0)*WEATHER.DAY_SECONDS

func tianwei_cell() -> Vector2i:
	return World.TRANSIT.points(F.REGION).transfer.cell

func pan_cell(i:int) -> Vector2i:
	return S.pan_rect(i).position+Vector2i(1,1)

func gate_cell(g:int) -> Vector2i:
	return Vector2i(9,int(S.GATE_ROWS[g])+1)

func beimen_objects() -> Dictionary:
	return world.state.regions[S.REGION].objects

func chest_salt(cell:Vector2i) -> int:
	var obj:Dictionary=beimen_objects().get(World.key(cell),{})
	return int(obj.get("items",{}).get("sea_salt",0))

func status_id(token:String) -> String:
	return str(S.status(world.state,token,beimen_objects(),now()).id)

func wheel_salt_pan(lot:int) -> int:
	for i in [lot*2,lot*2+1]:
		var pan:Dictionary=world.state.salt_pan.pans[i]
		if pan.s=="salt" and pan.f=="wheel":return i
	return -1

func lot_salt_pans(lot:int) -> int:
	var count:=0
	for i in [lot*2,lot*2+1]:
		if world.state.salt_pan.pans[i].s=="salt":count+=1
	return count

func lot_busy(lot:int) -> bool:
	for i in [lot*2,lot*2+1]:
		if world.state.salt_pan.pans[i].s!="empty":return true
	return false
