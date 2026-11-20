extends SceneTree
## T066 N06-4 rules: the quiet sheep watch, six-second readiness, replay, wool hat, local animation helper.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Weather:=preload("res://scripts/weather.gd")
const Step:=preload("res://scripts/mianmian_sheep_step.gd")
const Hat:=preload("res://scripts/mianmian_wool_hat_art.gd")
const TOKEN:="step-owner"
const OTHER:="step-guest"
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func day_time(rainy:bool) -> float:
	for day in range(0,60):
		if Weather.rains(float(day),"home")==rainy:return float(day)*Weather.DAY_SECONDS+30.0
	return -1.0

func act(w:World,token:String,action:String,cell:Vector2i,extra:="") -> Dictionary:
	return w.act(token,"r%d"%randi(),action,cell,extra)

func own_cell(w:World,token:String) -> Vector2i:
	return Vector2i(floori(float(w.state.players[token].x)),floori(float(w.state.players[token].y)))

func place(w:World,token:String,cell:Vector2i) -> void:
	var p:Dictionary=w.state.players[token]
	p.x=cell.x+0.5
	p.y=cell.y+0.5
	p.region=World.REGIONS.HOME

func run() -> void:
	var sheep:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	var w:=World.new()
	w.save_path=OS.get_environment("TEMP").path_join("mianmian-step-%d.json"%OS.get_process_id())
	w.state.picnic=true
	for token in [TOKEN,OTHER]:
		w.add_player(token,"看羊的人")
		place(w,token,sheep)
		w.state.players[token].bonds={"mianmian":{"points":24,"talk_day":-1,"gift_day":-1}}
	var dry:=day_time(false)
	var wet:=day_time(true)
	expect(dry>=0.0 and wet>=0.0,"The weather table has a dry and a rainy day")
	w.state.time=dry
	var me:Dictionary=w.state.players[TOKEN]
	expect(not act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok and not me.has(Goals.SHEEP_STEP_KEY),"No shelter yet: refused, nothing stored")
	me[Goals.SHEEP_SHELTER_KEY]=Goals.SHEEP_COMFORT_MASK
	place(w,TOKEN,sheep+Vector2i(8,0))
	expect(not act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok,"Standing far away is refused")
	place(w,TOKEN,sheep)
	me.bonds={"mianmian":{"points":6,"talk_day":-1,"gift_day":-1}}
	expect(not act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok,"Before best friends: refused")
	me.bonds={"mianmian":{"points":24,"talk_day":-1,"gift_day":-1}}
	w.state.time=wet
	expect(not act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok and not me.has(Goals.SHEEP_STEP_KEY),"Rain without calm mode: refused")
	expect(not act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep,"bogus").ok,"Unknown option refused")
	w.state.time=dry
	var first:Dictionary=act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep)
	expect(first.ok and is_equal_approx(float(me[Goals.SHEEP_STEP_KEY]),dry),"A clear day starts the watch")
	expect(not Goals.need_met("sheep_step",w.state,TOKEN),"Not ready on the same frame")
	expect(not act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok and is_equal_approx(float(me[Goals.SHEEP_STEP_KEY]),dry),"Pressing again while it walks keeps the first time")
	expect(not w.state.players[OTHER].has(Goals.SHEEP_STEP_KEY),"The other player has no watch record")
	expect(not act(w,TOKEN,Goals.ACTION,World.bond_place(w.state,"mianmian")[1],"mianmian:4::").ok,"Reporting too early is refused")
	w.state.time=dry+Goals.SHEEP_STEP_SECONDS
	expect(Goals.need_met("sheep_step",w.state,TOKEN) and not Goals.need_met("sheep_step",w.state,OTHER),"Ready after six seconds, only for the watcher")
	expect(act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok and is_equal_approx(float(me[Goals.SHEEP_STEP_KEY]),dry),"A later press keeps the first time and says it is done")
	var mm:Vector2i=World.bond_place(w.state,"mianmian")[1]
	place(w,TOKEN,mm)
	expect(not act(w,TOKEN,Goals.WOOL_HAT_ACTION,own_cell(w,TOKEN)).ok and not me.has(Goals.WOOL_HAT_KEY),"Hat is locked before the event")
	var report:Dictionary=act(w,TOKEN,Goals.ACTION,mm,"mianmian:4::")
	expect(report.ok and Goals.done(me,"mianmian").has(4),"Reporting completes the event")
	expect(not act(w,TOKEN,Goals.ACTION,mm,"mianmian:4::").ok,"Second report refused")
	var hat_result:Dictionary=act(w,TOKEN,Goals.WOOL_HAT_ACTION,own_cell(w,TOKEN))
	expect(hat_result.ok and me.get(Goals.WOOL_HAT_KEY)==true,"Hat goes on after the event: %s"%str(hat_result))
	expect(not w.state.players[OTHER].has(Goals.WOOL_HAT_KEY) and not act(w,OTHER,Goals.WOOL_HAT_ACTION,own_cell(w,OTHER)).ok,"The hat is personal")
	expect(w.save() and w.load_world(w.save_path),"Save and reload with the hat on")
	me=w.state.players[TOKEN]
	expect(me.get(Goals.WOOL_HAT_KEY)==true and Goals.done(me,"mianmian").has(4),"Hat and completion survive reload")
	expect(act(w,TOKEN,Goals.WOOL_HAT_ACTION,own_cell(w,TOKEN)).ok and not me.has(Goals.WOOL_HAT_KEY),"Hat comes off again")
	# Replay after completion restarts the walk on a later day.
	place(w,TOKEN,sheep)
	w.state.time=dry+20.0
	expect(act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep).ok and is_equal_approx(float(me[Goals.SHEEP_STEP_KEY]),dry+20.0),"Replay restarts the local walk")
	# Rain is allowed in calm mode (reduced motion).
	w.state.time=wet+1000.0
	if Weather.rains(Weather.day_index(w.state.time),"home"):expect(act(w,TOKEN,Goals.SHEEP_STEP_ACTION,sheep,"calm").ok,"Calm mode allows a rainy day")
	# Local animation helper.
	var snap:Dictionary={"own_mianmian_step_time":100.0}
	expect(not Step.active({},105.0) and not Step.active(snap,99.0) and not Step.active(snap,100.0+Step.TOTAL+0.1),"Helper is inactive without a record or outside its window")
	expect(Step.offset(snap,false,100.0)==Vector2.ZERO and Step.offset(snap,false,101.5).x==Step.UNDER_EAVE,"Sheep starts at the station and rests under the eave")
	expect(Step.offset(snap,false,103.0)==Vector2(Step.ONE_STEP,0),"After the stride it stands one step out")
	expect(Step.offset(snap,true,101.0)==Vector2(Step.ONE_STEP,0),"Reduced motion shows the finished pose")
	expect(Step.offset(snap,false,104.2).x<=Step.UNDER_EAVE and Step.walking(snap,false,100.5) and not Step.walking(snap,true,100.5),"Walking flag follows the timeline and respects reduced motion")
	expect(Hat.texture().get_size()==Vector2(Hat.WIDTH,Hat.HEIGHT),"Hat art has its own size")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(w.save_path+suffix):DirAccess.remove_absolute(w.save_path+suffix)
	print("MIANMIAN_STEP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
