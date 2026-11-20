extends SceneTree
## T066 N07-2 rules: the four-cell bed plan, tutorial seedlings for out-of-season flowers, replay safety,
## and the flower-rack unlock. Headless, single World.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Weather:=preload("res://scripts/weather.gd")
const TOKEN:="bed-owner"
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func day_in(season:String) -> float:
	for day in range(0,120):
		if Weather.season_on_day(day)==season:return float(day)*Weather.DAY_SECONDS+30.0
	return -1.0

func fresh(token:String) -> World:
	var w:=World.new()
	w.save_path=OS.get_environment("TEMP").path_join("xinghe-bed-%d-%s.json"%[OS.get_process_id(),token])
	w.add_player(token,"規劃花圃的人")
	var p:Dictionary=w.state.players[token]
	p.bonds={"xinghe":{"points":6,"talk_day":-1,"gift_day":-1}}
	var where:Array=World.bond_place(w.state,"xinghe")
	p.region=str(where[0])
	p.x=where[1].x+0.5
	p.y=where[1].y+0.5
	return w

func cell(w:World) -> Vector2i:
	return World.bond_place(w.state,"xinghe")[1]

func bag(w:World,items:Dictionary) -> Dictionary:
	var inv:Dictionary=w.state.players[TOKEN].inventory
	for key in ["bluebell","orange_blossom","chime_herb"]:inv.erase(key)
	for key in items:inv[key]=items[key]
	return inv

func report(w:World,choice:String) -> Dictionary:
	return w.act(TOKEN,"r%d"%randi(),Goals.ACTION,cell(w),"xinghe:2:%s:"%choice)

func run() -> void:
	var spring:=day_in("spring")
	var summer:=day_in("summer")
	expect(spring>=0.0 and summer>=0.0,"Calendar has spring and summer")
	var w:=fresh(TOKEN)
	var me:Dictionary=w.state.players[TOKEN]
	w.state.time=spring
	bag(w,{"bluebell":2,"orange_blossom":2})
	for bad in ["bluebell_orange-0001","bluebell_orange-0111","bluebell_orange-01","bluebell_orange-0012","nope-0011","bluebell_orange-0011-0"]:
		expect(not report(w,bad).ok and not Goals.done(me,"xinghe").has(2),"Malformed plan refused: "+bad)
	expect(int(me.inventory.bluebell)==2 and int(me.inventory.orange_blossom)==2,"Refusals keep the bag")
	# Spring: bluebell grows, orange does not -> orange cells use tutorial seedlings.
	var spring_run:Dictionary=report(w,"bluebell_orange-0110")
	expect(spring_run.ok and Goals.done(me,"xinghe").get(2,"")=="bluebell_orange-0110","Spring plan is accepted and recorded with its layout: %s"%str(spring_run))
	expect(int(me.inventory.bluebell)==0 and int(me.inventory.orange_blossom)==2,"Only the in-season flower is spent; seedlings cover the rest")
	expect("教學苗" in str(spring_run.message),"The message says tutorial seedlings were used")
	expect(not report(w,"bluebell_orange-0110").ok and not report(w,"bluebell_chime-0011").ok,"Reporting again is refused")
	expect(Goals.flower_rack_unlocked(me),"The flower rack opens after the plan")
	expect(w.save() and w.load_world(w.save_path),"Save and reload")
	me=w.state.players[TOKEN]
	expect(Goals.done(me,"xinghe").get(2,"")=="bluebell_orange-0110" and Goals.valid(me.get(Goals.RECORD_KEY),me),"The layout survives reload and validates")
	var view:Dictionary=Goals.view(me,w.state,TOKEN)
	expect(view.xinghe["2"].state=="done" and view.xinghe["2"].choice=="bluebell_orange-0110","The private view carries the layout")
	# Summer: orange is in season, bluebell is not.
	var b:=fresh(TOKEN)
	me=b.state.players[TOKEN]
	b.state.time=summer
	w=b
	bag(w,{"orange_blossom":1})
	var short:Dictionary=report(w,"bluebell_orange-0101")
	expect(not short.ok and "蜜橙花" in str(short.message),"Summer needs real orange blossoms: %s"%str(short))
	bag(w,{"orange_blossom":2})
	expect(report(w,"bluebell_orange-0101").ok and int(me.inventory.orange_blossom)==0,"Summer plan spends orange only")
	# Herb has no season: a herb pair always needs real herbs.
	w=fresh(TOKEN)
	me=w.state.players[TOKEN]
	w.state.time=summer
	bag(w,{"chime_herb":1})
	expect(not report(w,"bluebell_chime-0011").ok,"Herb cells always need real herbs")
	bag(w,{"chime_herb":2})
	expect(report(w,"bluebell_chime-0011").ok and int(me.inventory.chime_herb)==0,"Herb pair completes with two herbs and a seedling bluebell")
	# The bare option stays valid for older clients and saves.
	w=fresh(TOKEN)
	me=w.state.players[TOKEN]
	w.state.time=spring
	bag(w,{"bluebell":2,"orange_blossom":2})
	expect(report(w,"bluebell_orange").ok and int(me.inventory.bluebell)==0 and int(me.inventory.orange_blossom)==0,"Bare option keeps the old full hand-in")
	# Rack gate: locked without either story.
	var plain:=fresh(TOKEN)
	expect(not Goals.flower_rack_unlocked(plain.state.players[TOKEN]),"Rack locked for a new player")
	plain.state.players[TOKEN].greenhouse_reported=true
	expect(Goals.flower_rack_unlocked(plain.state.players[TOKEN]),"The old winter report still opens it")
	# Season table matches the crop table the world grows by.
	for flower in Goals.FLOWER_SEASONS:expect(World.CROP_SEASONS.get(flower,[])==Goals.FLOWER_SEASONS[flower],"Season table matches World for "+flower)
	expect(not World.CROP_SEASONS.has("chime_herb") or Goals.FLOWER_SEASONS.has("chime_herb"),"Herb season handling agrees with World")
	for path in [w.save_path,plain.save_path]:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("XINGHE_BED_PLAN_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
