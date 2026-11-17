extends SceneTree
## W1 core rules for the Tianwei flower nursery slice. Uses hand-built minimal
## states only (seeded fixtures); world integration is covered by W5 tests.

const FN=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Shipping=preload("res://scripts/shipping.gd")
const WEATHER=preload("res://scripts/weather.gd")
const A="flower-core-alpha"
const B="flower-core-beta"
const C="flower-core-gamma"
var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func person() -> Dictionary:
	return {"name":"t","region":"home","inventory":{},"coins":500,"travel_book":{"visited":{"home":true},"legacy_pass":false},"x":1.0,"y":1.0}

func make_state() -> Dictionary:
	var tea_done:Dictionary=Tea.FRESH.duplicate(true)
	tea_done.intro=true
	tea_done.comparison_complete=true
	return {"time":0.0,"players":{A:person(),B:person(),C:person()},"tea_ceramics":{"players":{A:tea_done.duplicate(true),B:tea_done.duplicate(true)}},"flower_nursery":FN.fresh(),"events":[],"regions":{"tianwei":{"crops":{}}}}

func act(state:Dictionary,token:String,action:String,extra:String="",region:String="",cell:Vector2i=Vector2i(-99,-99)) -> Dictionary:
	var site:Array=FN.SITES[action]
	return FN.apply(state,token,action,site[0] if region=="" else region,site[1] if cell==Vector2i(-99,-99) else cell,extra)

## Expects failure, an exact (or contained) message, and no change to state.
func rejects(state:Dictionary,token:String,action:String,extra:String,needle:String,detail:String) -> void:
	var before:=state.duplicate(true)
	var result:=act(state,token,action,extra)
	expect(not result.ok and (needle=="" or result.message.contains(needle)) and state==before,"%s (got %s)"%[detail,str(result)])

func bag(state:Dictionary,token:String=A) -> Dictionary:
	return state.players[token].inventory

func rec(state:Dictionary,token:String=A) -> Dictionary:
	return FN.own_record(state,token)

func visit(state:Dictionary,token:String) -> void:
	state.players[token].travel_book.visited.tianwei=true
	state.players[token].region="tianwei"

func broken(state:Dictionary,change:Callable,detail:String) -> void:
	var copy:=state.duplicate(true)
	change.call(copy)
	var verdict=FN.valid(copy)
	expect(verdict is bool and verdict==false,"valid rejects: "+detail)

func _initialize() -> void:
	constants_checks()
	geography_checks()
	var s:=make_state()
	progression(s)
	validity_checks(s)
	legacy_checks()
	world_constants()
	print("FLOWER_NURSERY_CORE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func constants_checks() -> void:
	expect(FN.FRESH.keys()==["letter","intro","planted","harvested","saving","saved","dyeing","shipped","complete","sugar_day","sugar_bought"],"FRESH has the exact contract key set")
	expect(FN.garden_fresh()=={"given":{"blue_dye":0,"orange_blossom":0,"chime_herb":0},"contributors":{},"complete":false,"completed_at":-1.0},"garden_fresh matches contract")
	expect(FN.fresh().keys()==["players","garden"] and FN.fresh().players.is_empty(),"fresh() root shape")
	expect(FN.CROPS=={"bluebell":{"name":"鈴蘭藍花","time":150.0,"price":28,"seed_price":28,"yield":2},"orange_blossom":{"name":"蜜橙花","time":150.0,"price":28,"seed_price":28,"yield":2},"chime_herb":{"name":"風鈴香草","time":120.0,"price":48,"seed_price":24,"yield":1}},"CROPS literal")
	expect(FN.PLAN.bluebell.plan_days==4 and FN.PLAN.orange_blossom.plan_seasons==["夏","秋"] and FN.PLAN.chime_herb.plan_days==3 and FN.PLAN.chime_herb.plan_seasons==["全季","溫室"] and FN.PLAN.bluebell.plan_seasons==["春"],"PLAN keeps source seasons/days")
	expect(FN.DYE=={"ingredients":{"bluebell":3},"item":"blue_dye","yield":2,"time":30.0},"DYE equals plan R31")
	expect(FN.COOKIE.garden_cookie.ingredients=={"flour":1,"sugar":1,"chime_herb":1} and FN.COOKIE.garden_cookie.time==60.0 and FN.COOKIE.garden_cookie.yield==4 and FN.COOKIE_PRICE==36,"COOKIE recipe/price")
	expect(FN.FORWARD_IDS.size()==10 and "tianwei" in FN.FORWARD_IDS and FN.NAMES.size()==9,"FORWARD_IDS/NAMES sizes")
	for id in FN.NAMES:expect(id in FN.FORWARD_IDS,"NAMES id is forward id: "+id)
	expect(FN.ORDER_PAY==176 and FN.SUGAR_DAILY==2 and FN.PLOT_CAP==6 and FN.MEMENTO==FN.RESERVE and FN.SAVE_SECONDS==60.0,"scalar constants")
	expect(FN.MARKET_PRICES=={"bluebell_seed":28,"orange_blossom_seed":28,"chime_herb_seed":24,"sugar":40},"market prices")
	for kind in FN.FLOWERS:
		expect(int(FN.CROPS[kind].price)>=int(FN.CROPS[kind].seed_price),"price >= seed_price for "+kind)
		expect(int(FN.MARKET_PRICES[FN.SEEDS[kind]])==int(FN.CROPS[kind].seed_price),"market seed price equals plan seed price: "+kind)
	var prices:=Shipping.prices(FN.CROPS,{}, {"garden_cookie":FN.COOKIE_PRICE})
	for item in ["bluebell_seed","orange_blossom_seed","chime_herb_seed","blue_dye","sugar"]:
		expect(not prices.has(item),"not sellable via shipping: "+item)
	expect(prices.garden_cookie==36 and prices.bluebell==28,"flowers and cookie are sellable at contract prices")
	for action in FN.ACTIONS:
		expect(action.length()<=24 and FN.SITES.has(action),"action name/site: "+action)
		for extra in FN.OPTIONS.get(action,[""]):expect(String(extra).length()<=32,"extra length")
	for p in FN.PHASES:
		expect(FN.STORY.has(p) and FN.STORY[p]!="","STORY line for "+p)
	for line in FN.STORY.values():
		expect(not line.contains("她") and not line.replace("其他","").contains("他"),"STORY avoids pronouns")
	expect(FN.REJECT_MESSAGE=="田尾花圃只開放育苗床照顧和花圃工作台。","reject message exact")

func geography_checks() -> void:
	var beds:=0
	for x in range(0,80):
		for y in range(0,60):
			var p:=Vector2i(x,y)
			if not FN.protected(p):
				beds+=1
				expect(FN.land(p) and not FN.blocked(p),"bed cell is land and walkable")
	expect(beds==24,"exactly 24 unprotected nursery cells")
	expect(FN.land(FN.TRANSFER) and not FN.blocked(FN.TRANSFER) and FN.protected(FN.TRANSFER),"transfer cell")
	for p in [FN.FARMER,FN.SEED_TABLE,FN.DYE_TABLE,FN.XINGHE,FN.MARKET,FN.GARDEN_CELL,Vector2i(20,15)]:
		expect(FN.blocked(p) and FN.protected(p) and FN.land(p),"station/shed blocked: "+str(p))
	expect(not FN.land(Vector2i(5,5)) and not FN.land(Vector2i(42,20)),"outside LAND")
	var layer:={}
	for i in 5:layer["%d,22"%(18+i)]={"kind":"","owner":A}
	layer["25,24"]={"kind":"bluebell","owner":B}
	expect(FN.plot_allowed(layer,A),"5 own plots: may hoe")
	layer["23,22"]={"kind":"","owner":A}
	expect(not FN.plot_allowed(layer,A) and FN.plot_allowed(layer,B),"6 own plots: cap reached; others unaffected")

func progression(s:Dictionary) -> void:
	expect(FN.phase(s,C)=="locked" and not FN.unlocked(s,C),"C without tea comparison is locked")
	rejects(s,C,"flower_letter","","","locked player cannot read letter")
	expect(FN.guidance(s,C).phase=="locked","guidance locked")
	expect(FN.phase(s,A)=="letter" and FN.unlocked(s,A) and not FN.route_open(s,A),"A starts at letter")
	rejects(s,A,"flower_intro","","介紹信","intro needs letter")
	var before:=s.duplicate(true)
	expect(not FN.apply(s,A,"flower_letter","tianwei",FN.RECEIVER_HOME,"").ok and not FN.apply(s,A,"flower_letter","home",FN.FARMER,"").ok and not FN.apply(s,A,"flower_letter","home",FN.RECEIVER_HOME,"x").ok and s==before,"wrong region/cell/extra rejected without change")
	expect(act(s,A,"flower_letter").ok and rec(s).letter and FN.route_open(s,A),"letter read")
	rejects(s,A,"flower_letter","","介紹信已收下，可從手帳重看。","letter twice")
	expect(FN.phase(s,A)=="travel" and FN.guidance(s,A).cell==FN.TRANSFER,"phase travel")
	rejects(s,A,"flower_intro","","","intro needs visiting tianwei")
	visit(s,A)
	expect(FN.phase(s,A)=="intro" and FN.guidance(s,A).site=="farmer","phase intro")
	rejects(s,A,"flower_save","bluebell","打聲招呼","save before intro")
	rejects(s,A,"flower_dye","","打聲招呼","dye before intro")
	rejects(s,A,"flower_buy","sugar","打聲招呼","buy before intro")
	rejects(s,A,"flower_give","","打聲招呼","give before intro")
	FN.note_plant(s,A,"bluebell")
	expect(rec(s).planted.is_empty(),"note_plant ignored before intro")
	bag(s).bluebell_seed=FN.LIMIT
	rejects(s,A,"flower_intro","","背包上限","intro rejected whole when bag full")
	bag(s).erase("bluebell_seed")
	expect(act(s,A,"flower_intro").ok and bag(s)=={"bluebell_seed":2,"orange_blossom_seed":2,"chime_herb_seed":2} and rec(s).intro,"intro grants starter seeds")
	rejects(s,A,"flower_intro","","已經給過","starter once")
	expect(FN.phase(s,A)=="plant","phase plant")
	# Simulate world: two plots per flower, seeds consumed, then harvest yields.
	for kind in FN.FLOWERS:
		bag(s)[FN.SEEDS[kind]]=0
		FN.note_plant(s,A,kind)
		expect(FN.phase(s,A)==("harvest" if kind=="chime_herb" else "plant"),"plant progress "+kind)
	FN.note_plant(s,A,"radish")
	expect(rec(s).planted.size()==3,"non-flower plant ignored")
	FN.note_harvest(s,A,"bluebell",4);bag(s).bluebell=4
	FN.note_harvest(s,A,"orange_blossom",4);bag(s).orange_blossom=4
	expect(FN.phase(s,A)=="harvest","still harvest phase")
	FN.note_harvest(s,A,"chime_herb",2);bag(s).chime_herb=2
	expect(FN.phase(s,A)=="save" and rec(s).harvested=={"bluebell":4,"orange_blossom":4,"chime_herb":2},"phase save after harvests")
	var capped:=s.duplicate(true)
	capped.flower_nursery.players[A].harvested.bluebell=FN.LIMIT-1
	FN.note_harvest(capped,A,"bluebell",5)
	expect(capped.flower_nursery.players[A].harvested.bluebell==FN.LIMIT,"harvested capped at LIMIT")
	# A full plant harvest returns one seed packet after 60 s.
	rejects(s,A,"flower_save","radish","","save extra whitelist")
	var unharvested:=s.duplicate(true)
	unharvested.flower_nursery.players[A].harvested.erase("chime_herb")
	unharvested.flower_nursery.players[A].saved.erase("chime_herb")
	rejects(unharvested,A,"flower_save","chime_herb","採收","save needs a tianwei harvest of that kind")
	for kind in FN.FLOWERS:
		var flowers:=int(bag(s)[kind])
		var cost:=FN.save_flower_cost(kind)
		var insufficient:=s.duplicate(true)
		insufficient.players[A].inventory[kind]=cost-1
		rejects(insufficient,A,"flower_save",kind,"留種需要 %d 份"%cost,"one below the recipe refuses "+kind)
		expect(act(s,A,"flower_save",kind).ok and bag(s)[kind]==flowers-cost and rec(s).saving=={"kind":kind,"ready":s.time+60.0},"start saving "+kind)
		rejects(s,A,"flower_save",kind,"已有你的工作","one saving job at a time")
		rejects(s,A,"flower_save_take","","沒有完成的工作","cannot take saved seed early")
		s.time+=59.5
		rejects(s,A,"flower_save_take","","沒有完成的工作","cannot take at 59.5 s")
		s.time+=0.5
		bag(s)[FN.SEEDS[kind]]=FN.LIMIT
		rejects(s,A,"flower_save_take","","工作仍保留","full bag keeps saving job")
		bag(s)[FN.SEEDS[kind]]=0
		expect(act(s,A,"flower_save_take").ok and bag(s)[FN.SEEDS[kind]]==1 and rec(s).saved.has(kind) and rec(s).saving.is_empty(),"take 1 seed for "+kind)
	expect(FN.phase(s,A)=="ship","phase ship")
	var empty_bag:=s.duplicate(true)
	empty_bag.players[A].inventory.bluebell=0
	empty_bag.flower_nursery.players[A].saved.erase("bluebell")
	empty_bag.flower_nursery.players[A].harvested.bluebell=1
	rejects(empty_bag,A,"flower_save","bluebell","留種需要 2 份","save without flower")
	# Order: bag now bluebell 2, orange 2, chime 1, seeds 1/1/1.
	var unsaved:=s.duplicate(true)
	unsaved.flower_nursery.players[A].saved.erase("orange_blossom")
	rejects(unsaved,A,"flower_ship","",FN.UNSAVED_MESSAGE,"ship needs all three saved")
	var short:=s.duplicate(true)
	short.players[A].inventory.chime_herb=0
	short.players[A].inventory.bluebell=1
	rejects(short,A,"flower_ship","","鈴蘭藍花還差 1","ship lists bluebell deficit")
	rejects(short,A,"flower_ship","","風鈴香草還差 1","ship lists chime deficit")
	for seed_id in FN.RESERVE:
		var reserve:=s.duplicate(true)
		reserve.players[A].inventory[seed_id]=0
		rejects(reserve,A,"flower_ship","",FN.RESERVE_MESSAGE,"ship keeps reserve seed "+seed_id)
	var rich:=s.duplicate(true)
	rich.players[A].coins=FN.LIMIT
	rejects(rich,A,"flower_ship","","上限","ship coin limit")
	var coins:=int(s.players[A].coins)
	expect(act(s,A,"flower_ship").ok and s.players[A].coins==coins+176 and bag(s).bluebell==0 and bag(s).orange_blossom==0 and bag(s).chime_herb==0 and rec(s).shipped,"ship pays 176 and deducts order")
	for seed_id in FN.RESERVE:expect(bag(s)[seed_id]==1,"reserve seed kept "+seed_id)
	rejects(s,A,"flower_ship","","已出貨","cannot ship twice")
	expect(FN.phase(s,A)=="garden","phase garden")
	rejects(s,A,"flower_report","","公共花園尚未完成","report before garden")
	# Dye R31 3 -> 2, 30 s.
	rejects(s,A,"flower_dye","","需要 3 朵","dye needs 3 bluebell")
	bag(s).bluebell=4
	expect(act(s,A,"flower_dye").ok and bag(s).bluebell==1 and rec(s).dyeing=={"ready":s.time+30.0},"dye consumes 3 bluebell")
	rejects(s,A,"flower_dye","","已有你的工作","one dye job")
	s.time+=29.0
	rejects(s,A,"flower_dye_take","","沒有完成的工作","dye not ready at 29 s")
	s.time+=1.0
	bag(s).blue_dye=FN.LIMIT-1
	rejects(s,A,"flower_dye_take","","工作仍保留","dye full bag keeps job")
	bag(s).blue_dye=0
	expect(act(s,A,"flower_dye_take").ok and bag(s).blue_dye==2 and rec(s).dyeing.is_empty(),"dye yields 2")
	# Market and sugar daily cap.
	s.time=WEATHER.DAY_SECONDS*3.0+10.0
	coins=int(s.players[A].coins)
	expect(act(s,A,"flower_buy","sugar").ok and act(s,A,"flower_buy","sugar").ok and bag(s).sugar==2 and s.players[A].coins==coins-80,"two sugar per day")
	rejects(s,A,"flower_buy","sugar","今日糖已達 2 份（新的遊戲日才重置）。","third sugar rejected")
	expect(rec(s).sugar_day==3 and rec(s).sugar_bought==2,"sugar counters")
	expect(act(s,A,"flower_buy","chime_herb_seed").ok and bag(s).chime_herb_seed==2 and s.players[A].coins==coins-104,"seed purchase still allowed")
	rejects(s,A,"flower_buy","radish_seed","","market extra whitelist")
	s.time=WEATHER.DAY_SECONDS*4.0
	expect(act(s,A,"flower_buy","sugar").ok and rec(s).sugar_day==4 and rec(s).sugar_bought==1 and bag(s).sugar==3,"sugar resets on new game day")
	var poor:=s.duplicate(true)
	poor.players[A].coins=39
	rejects(poor,A,"flower_buy","sugar","鈴幣不足","sugar needs coins")
	var full:=s.duplicate(true)
	full.players[A].inventory.bluebell_seed=FN.LIMIT
	rejects(full,A,"flower_buy","bluebell_seed","背包上限","buy bag limit")
	# Garden: A gives blue_dye 2 + orange 1 (seeds untouched).
	bag(s).orange_blossom=1
	var seeds_before:=[bag(s).bluebell_seed,bag(s).orange_blossom_seed,bag(s).chime_herb_seed]
	expect(act(s,A,"flower_give").ok and s.flower_nursery.garden.given=={"blue_dye":2,"orange_blossom":1,"chime_herb":0} and bag(s).blue_dye==0 and bag(s).orange_blossom==0,"partial donation")
	expect([bag(s).bluebell_seed,bag(s).orange_blossom_seed,bag(s).chime_herb_seed]==seeds_before,"donation never takes seeds")
	expect(s.flower_nursery.garden.contributors=={A:3} and not s.flower_nursery.garden.complete,"contributor tally")
	rejects(s,A,"flower_give","","沒有可捐的染料、橙花或香草（種子不會被拿走）。","nothing to give")
	expect(FN.valid(s.duplicate(true)),"state valid mid-garden")
	# B joins and over-supplies: only the remainder is taken.
	expect(act(s,B,"flower_letter").ok,"B letter")
	visit(s,B)
	expect(act(s,B,"flower_intro").ok,"B intro")
	s.players[B].inventory.merge({"blue_dye":5,"orange_blossom":5,"chime_herb":5},true)
	var at:=float(s.time)
	expect(act(s,B,"flower_give","","tianwei",Vector2i(38,23)).ok,"give accepted from any garden cell")
	var g:Dictionary=s.flower_nursery.garden
	expect(g.given==FN.GARDEN_NEEDS and g.complete and g.completed_at==at,"garden completes with completed_at")
	expect(s.players[B].inventory.blue_dye==3 and s.players[B].inventory.orange_blossom==2 and s.players[B].inventory.chime_herb==3,"overflow only takes remaining need")
	expect(g.contributors=={A:3,B:7} and s.events==[FN.GARDEN_EVENT],"contributors sum equals given; one event line")
	rejects(s,B,"flower_give","","已完成","give after completion")
	rejects(s,A,"flower_give","","已完成","give after completion (A)")
	expect(s.events.size()==1,"completion settled once")
	# Report.
	rejects(s,B,"flower_report","","合作訂單","report needs shipment")
	expect(FN.phase(s,A)=="report" and FN.guidance(s,A).cell==FN.XINGHE,"phase report")
	expect(not FN.home_seed_allowed(s,A,"bluebell") and FN.home_seed_allowed(s,A,"radish"),"home stall locked before completion")
	var cap:=s.duplicate(true)
	cap.players[A].inventory.orange_blossom_seed=FN.LIMIT
	rejects(cap,A,"flower_report","","背包上限","report bag limit")
	var held:=[bag(s).bluebell_seed,bag(s).orange_blossom_seed,bag(s).chime_herb_seed]
	expect(act(s,A,"flower_report").ok and rec(s).complete and [bag(s).bluebell_seed,bag(s).orange_blossom_seed,bag(s).chime_herb_seed]==[held[0]+1,held[1]+1,held[2]+1],"report grants memento once")
	rejects(s,A,"flower_report","","已完成","memento once")
	expect(FN.phase(s,A)=="complete" and FN.guidance(s,A).phase=="complete","phase complete")
	expect(FN.home_seed_allowed(s,A,"bluebell") and FN.home_seed_allowed(s,A,"chime_herb_seed") and not FN.home_seed_allowed(s,B,"orange_blossom") and not FN.home_seed_allowed(s,C,"bluebell_seed"),"home_seed_allowed by own completion")
	# Late joiner: garden already complete -> after personal steps goes straight to report.
	var late:=s.duplicate(true)
	var lr:Dictionary=late.flower_nursery.players[B]
	for kind in FN.FLOWERS:
		lr.planted[kind]=true;lr.harvested[kind]=1;lr.saved[kind]=true
	expect(FN.phase(late,B)=="ship","late joiner still ships")
	lr.shipped=true
	expect(FN.phase(late,B)=="report","late joiner skips garden to report")
	# Snapshots.
	var pub:=FN.public(s)
	expect(pub.keys()==["garden"] and pub.garden.keys()==["given","complete","completed_at","contributor_count"] and pub.garden.contributor_count==2,"public shape")
	expect(not JSON.stringify(pub).contains(A) and not JSON.stringify(pub).contains(B),"public() contains no token")
	expect(FN.own_view(s,A)=={"own_record":rec(s),"own_given":3} and FN.own_view(s,C).own_given==0 and FN.own_view(s,C).own_record==FN.FRESH,"own_view")
	expect(FN.valid(s.duplicate(true)),"completed state valid")

func validity_checks(s:Dictionary) -> void:
	expect(FN.valid(s.duplicate(true)),"baseline valid")
	var pure:=s.duplicate(true)
	pure.erase("regions")
	expect(FN.valid(pure),"valid without regions.tianwei (pure core)")
	var floats:=s.duplicate(true)
	floats.flower_nursery.players[A].harvested.bluebell=4.0
	floats.flower_nursery.players[A].sugar_bought=1.0
	floats.flower_nursery.players[A].sugar_day=4.0
	floats.flower_nursery.garden.given.blue_dye=4.0
	floats.flower_nursery.garden.contributors[A]=3.0
	expect(FN.valid(floats) and floats.flower_nursery.players[A].harvested.bluebell is int and floats.flower_nursery.players[A].sugar_bought is int and floats.flower_nursery.players[A].sugar_day is int and floats.flower_nursery.garden.given.blue_dye is int and floats.flower_nursery.garden.contributors[A] is int,"whole floats normalized to int")
	broken(s,func(c):c.flower_nursery.extra=1,"extra root key")
	broken(s,func(c):c.flower_nursery.erase("garden"),"missing garden")
	broken(s,func(c):c.flower_nursery.players[A].extra=1,"extra record key")
	broken(s,func(c):c.flower_nursery.players[A].erase("dyeing"),"missing record key")
	broken(s,func(c):c.flower_nursery.players[A].letter="yes","letter type")
	broken(s,func(c):c.flower_nursery.players[A].planted=[],"planted type")
	broken(s,func(c):c.flower_nursery.players["ghost"]=FN.FRESH.duplicate(true),"unknown token")
	broken(s,func(c):c.flower_nursery.players[A].letter=false,"letter must be true")
	broken(s,func(c):c.tea_ceramics.players[A].comparison_complete=false,"letter requires tea comparison")
	broken(s,func(c):c.players[A].travel_book.visited.erase("tianwei"),"intro requires visited")
	broken(s,func(c):c.flower_nursery.players[A].planted.radish=true,"planted key")
	broken(s,func(c):c.flower_nursery.players[A].planted.bluebell=1,"planted value")
	broken(s,func(c):c.flower_nursery.players[A].saved.bluebell=false,"saved value")
	broken(s,func(c):c.flower_nursery.players[A].harvested.bluebell=0,"harvested >= 1")
	broken(s,func(c):c.flower_nursery.players[A].harvested.bluebell=1.5,"harvested whole")
	broken(s,func(c):c.flower_nursery.players[A].planted.erase("bluebell"),"harvested requires planted")
	broken(s,func(c):c.flower_nursery.players[A].harvested.erase("bluebell"),"saved requires harvested")
	broken(s,func(c):c.flower_nursery.players[B].intro=false,"progress requires intro (B contributor)")
	broken(s,func(c):c.flower_nursery.players[A].saving={"kind":"radish","ready":0.0},"saving kind")
	broken(s,func(c):c.flower_nursery.players[A].saving={"kind":"bluebell","ready":float(c.time)+61.0},"saving ready window")
	broken(s,func(c):c.flower_nursery.players[A].saving={"kind":"bluebell","ready":-1.0},"saving ready >= 0")
	broken(s,func(c):c.flower_nursery.players[A].saving={"kind":"bluebell"},"saving shape")
	broken(s,func(c):c.flower_nursery.players[A].dyeing={"ready":float(c.time)+31.0},"dyeing window")
	broken(s,func(c):c.flower_nursery.players[A].dyeing={"ready":1.0,"x":1},"dyeing shape")
	broken(s,func(c):c.flower_nursery.players[A].saved.erase("chime_herb"),"shipped requires all saved")
	broken(s,func(c):c.flower_nursery.players[A].shipped=false,"complete requires shipped")
	broken(s,func(c):c.flower_nursery.players[A].sugar_day=5,"sugar_day <= today")
	broken(s,func(c):c.flower_nursery.players[A].sugar_day=-2,"sugar_day >= -1")
	broken(s,func(c):c.flower_nursery.players[A].sugar_bought=3,"sugar_bought <= 2")
	broken(s,func(c):c.flower_nursery.players[A].sugar_day=-1,"sugar bought needs a day")
	var letter_only:=s.duplicate(true)
	add_d(letter_only,{})
	expect(FN.valid(letter_only),"letter-only record for a new unlocked player is valid")
	broken(s,func(c):add_d(c,{"sugar_bought":1,"sugar_day":0}),"sugar_bought > 0 requires intro")
	broken(s,func(c):add_d(c,{"planted":{"bluebell":true}}),"planted requires intro")
	broken(s,func(c):add_d(c,{"dyeing":{"ready":0.0}}),"dyeing requires intro")
	broken(s,func(c):add_d(c,{"saving":{"kind":"bluebell","ready":0.0}}),"saving requires intro")
	broken(s,func(c):add_d(c,{"intro":true}),"intro requires visited tianwei")
	broken(s,func(c):c.flower_nursery.garden.extra=1,"garden extra key")
	broken(s,func(c):c.flower_nursery.garden.given.blue_dye=5,"given <= need")
	broken(s,func(c):c.flower_nursery.garden.given.erase("chime_herb"),"given exact keys")
	broken(s,func(c):c.flower_nursery.garden.given.sugar=0,"given extra key")
	broken(s,func(c):c.flower_nursery.garden.complete=false,"complete equals all met")
	broken(s,func(c):c.flower_nursery.garden.contributors["ghost"]=1,"contributor must exist")
	broken(s,func(c):c.flower_nursery.garden.contributors[A]=0,"contributor >= 1")
	broken(s,func(c):c.flower_nursery.garden.contributors[A]=4,"contributors sum equals given")
	broken(s,func(c):c.flower_nursery.garden.completed_at=-1.0,"completed_at set when complete")
	broken(s,func(c):c.flower_nursery.garden.completed_at=float(c.time)+1.0,"completed_at <= time")
	var undone:=func(c):
		c.flower_nursery.garden.given.chime_herb=1
		c.flower_nursery.garden.contributors[B]=6
		c.flower_nursery.garden.complete=false
		c.flower_nursery.players[A].complete=false
	var open_garden:=s.duplicate(true)
	undone.call(open_garden)
	open_garden.flower_nursery.garden.completed_at=-1.0
	expect(FN.valid(open_garden.duplicate(true)),"incomplete garden with completed_at -1 valid")
	broken(open_garden,func(c):c.flower_nursery.garden.completed_at=5.0,"completed_at -1 when incomplete")
	broken(open_garden,func(c):c.flower_nursery.players[A].complete=true,"complete requires garden complete")
	broken(s,func(c):c.players[C].region="tianwei","region tianwei requires letter")
	var plots:=func(c):
		for i in 7:c.regions.tianwei.crops["%d,22"%(18+i)]={"kind":"","owner":A,"growth":0.0,"wet":false}
	broken(s,plots,"plot cap 6 per player")
	broken(s,func(c):c.regions.tianwei.crops["18,22"]={"kind":"radish","owner":A},"tianwei crop kind")
	broken(s,func(c):c.regions.tianwei.crops["18,22"]={"kind":"bluebell"},"tianwei crop owner")
	var six:=s.duplicate(true)
	for i in 6:six.regions.tianwei.crops["%d,22"%(18+i)]={"kind":"bluebell","owner":A,"growth":0.0,"wet":false}
	expect(FN.valid(six),"6 plots valid")

const D="flower-core-delta"
func add_d(c:Dictionary,fields:Dictionary) -> void:
	c.players[D]=person()
	var tea_done:Dictionary=Tea.FRESH.duplicate(true)
	tea_done.intro=true
	tea_done.comparison_complete=true
	c.tea_ceramics.players[D]=tea_done
	var r:Dictionary=FN.FRESH.duplicate(true)
	r.letter=true
	r.merge(fields,true)
	c.flower_nursery.players[D]=r

func legacy_base() -> Dictionary:
	var p:=person()
	p.inventory={"wood":3,"radish_seed":2}
	p.collection={"crops":{"radish":true},"fish":{},"meals":{"soup":true},"claimed":{}}
	p.last_seed={"at":0.0,"x":1,"y":1,"cells":["1,1"],"kind":"radish"}
	var stove:={"type":"stove","owner":A,"items":{},"cooking":{"active":{"kind":"soup","ingredients":{"radish":2}},"waiting":[],"ready":[]}}
	var mill:={"type":"mill","owner":A,"processing":{"active":{},"waiting":[{"kind":"flour","ingredients":{"wheat":2}}],"ready":[]}}
	return {"version":24,"players":{A:p},"crops":{"1,1":{"kind":"radish","owner":A}},"objects":{"2,2":{"type":"chest","owner":A,"items":{"wood":1}},"3,3":stove,"4,4":{"type":"stove","owner":A,"job":{"kind":"bread","owner":A,"ingredients":{"wheat":2}}}},"regions":{"lanyang":{"crops":{"5,5":{"kind":"wheat","owner":A}},"objects":{"6,6":{"type":"chest","owner":A,"items":{}},"7,7":mill}}}}

func legacy_checks() -> void:
	expect(FN.legacy_clean(legacy_base()),"clean v24 save accepted")
	var spots:={
		"inventory":func(c,id):c.players[A].inventory[id]=1,
		"home_chest":func(c,id):c.objects["2,2"].items[id]=1,
		"region_chest":func(c,id):c.regions.lanyang.objects["6,6"].items[id]=1,
		"home_crop":func(c,id):c.crops["1,1"].kind=id,
		"region_crop":func(c,id):c.regions.lanyang.crops["5,5"].kind=id,
		"collection_crops":func(c,id):c.players[A].collection.crops[id]=true,
		"collection_meals":func(c,id):c.players[A].collection.meals[id]=true,
		"last_seed":func(c,id):c.players[A].last_seed.kind=id,
		"stove_job_kind":func(c,id):c.objects["4,4"].job.kind=id,
		"stove_job_ingredients":func(c,id):c.objects["4,4"].job.ingredients[id]=1,
		"cooking_active_kind":func(c,id):c.objects["3,3"].cooking.active.kind=id,
		"cooking_active_ingredients":func(c,id):c.objects["3,3"].cooking.active.ingredients[id]=1,
		"cooking_waiting":func(c,id):c.objects["3,3"].cooking.waiting.append({"kind":id,"ingredients":{}}),
		"cooking_ready":func(c,id):c.objects["3,3"].cooking.ready.append({"kind":"soup","ingredients":{id:1}}),
		"processing_waiting":func(c,id):c.regions.lanyang.objects["7,7"].processing.waiting[0].kind=id,
		"processing_active":func(c,id):c.regions.lanyang.objects["7,7"].processing.active={"kind":id,"ingredients":{}},
	}
	for id in FN.FORWARD_IDS:
		if id=="tianwei":continue
		for spot in spots:
			var copy:=legacy_base()
			spots[spot].call(copy,id)
			expect(not FN.legacy_clean(copy),"legacy_clean rejects %s in %s"%[id,spot])
	var t:=legacy_base();t.players[A].travel_book.visited.tianwei=true
	expect(not FN.legacy_clean(t),"legacy rejects visited tianwei")
	t=legacy_base();t.players[A].travel_book.visited.tianwei=false
	expect(not FN.legacy_clean(t),"legacy rejects any visited tianwei key")
	t=legacy_base();t.players[A].region="tianwei"
	expect(not FN.legacy_clean(t),"legacy rejects player in tianwei")
	t=legacy_base();t.regions.tianwei={"crops":{},"objects":{}}
	expect(not FN.legacy_clean(t),"legacy rejects regions.tianwei")
	t=legacy_base();t.flower_nursery=FN.fresh()
	expect(not FN.legacy_clean(t),"legacy rejects flower_nursery root")

## Runs once W5 has merged the flower data into world.gd; PENDING until then.
func world_constants() -> void:
	var text:=FileAccess.get_file_as_string("res://scripts/world.gd")
	var crops_at:=text.find("const CROPS")
	var crops_end:=text.find("const BUILD",crops_at)
	if crops_at<0 or crops_end<0 or not text.substr(crops_at,crops_end-crops_at).contains("\"bluebell\""):
		print("FLOWER_NURSERY_CORE_WORLD_CONSTANTS PENDING (world.gd CROPS has no bluebell yet; W5 integration)")
		return
	var script=load("res://scripts/world.gd")
	expect(script is Script,"world.gd loads for constant comparison")
	if not script is Script:return
	var map:Dictionary=script.get_script_constant_map()
	for kind in FN.CROPS:expect(map.CROPS.get(kind)==FN.CROPS[kind],"World.CROPS equals module: "+kind)
	expect(map.RECIPES.get("garden_cookie")==FN.COOKIE.garden_cookie,"World.RECIPES garden_cookie equals module")
	expect(map.OTHER_SALES.get("garden_cookie")==FN.COOKIE_PRICE,"World.OTHER_SALES garden_cookie 36")
	for id in FN.NAMES:expect(map.NAMES.get(id)==FN.NAMES[id],"World.NAMES equals module: "+id)
	for item in ["bluebell_seed","orange_blossom_seed","chime_herb_seed","blue_dye","sugar"]:
		expect(not map.OTHER_SALES.has(item) and not map.CROPS.has(item),"World does not sell "+item)
	print("FLOWER_NURSERY_CORE_WORLD_CONSTANTS RAN")
