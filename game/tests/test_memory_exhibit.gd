extends SceneTree
## 第 40 章風鈴節廣場「地方記憶展」(scripts/memory_exhibit.gd) rules test.
## Headless, World-level (World.act / save / load_world) plus an in-process Session for
## the public / own snapshot. No network.
##
## EARNED through real World.act: the canal repair (lanyang_clear ×3 + lanyang_donate),
## every first-分水 memory (memory_observe ×3, memory_gate/memory_flow ×3 rounds), the
## plaque (memory_plaque), the whole 蘭陽回訪 (revisit_gate a:3 / b:2, revisit_check ×3)
## and the plaque-kit claim (revisit_claim), every exhibit_view, the build/hoe refusals.
## WRITTEN DIRECTLY (disclosed): state.festival_story_open=true (the festival opening
## needs six projects, the boat and the table lights — far outside this suite; its
## action is covered by the festival suites), board/picnic for the site check,
## player region/x/y (standing spots in Lanyang and at home, no travel action), repair
## materials plank/stone/resin, wood for the build refusal, lamps written onto the
## stand candidate cells (fallback / pause / old-save shape), tampered and legacy save
## files, and synthetic client-shaped snapshots for the helper cases.
## World time is never advanced: everything happens on day 1 (spring, sunny).
const World=preload("res://scripts/world.gd")
const Exhibit=preload("res://scripts/memory_exhibit.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Memory=preload("res://scripts/history_memory.gd")
const Weather=preload("res://scripts/weather.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const Souv=preload("res://scripts/souvenir_exchange.gd")
const Show=preload("res://scripts/showcase.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const Harvest=preload("res://scripts/harvest_relay.gd")
const Market=preload("res://scripts/market_stall.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Village=preload("res://scripts/village.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const ALPHA:="exhibit-alpha-token-71c2"
const BETA:="exhibit-beta-token-09ad"
const LATE:="exhibit-late-token-5e40"
const KIT:="water_share_plaque_kit"
const STAND:=Vector2i(39,26)
const HALF:=Vector2(0.5,0.5)
const NEAR:=Vector2(39.5,27.5)     # tile 39,27: 1.0 from the stand centre
const FAR:=Vector2(39.5,33.5)      # player spawn: 7.0 from the stand centre
const PROTECTED_MSG:="這裡是水域或公共通道，請換個位置"
const BUILD_PLOTS:=[Rect2i(41,34,3,4),Rect2i(34,33,4,5),Rect2i(46,22,6,8)]
const FIRST_FIELD:=Rect2i(45,26,3,2)
const ROW_KEYS:=["blurb","disclaimer","extra","id","lines","name","on_display","project","region","seen","source","story","unread"]

var checks:=0
var failures:=0
var serial:=0
var temp_files:=[]

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	check_static()
	check_site()
	check_locked()
	var w:World=await main_flow()
	if w!=null:
		check_save_reload(w)
	check_reverse_order_and_fallback()
	check_module()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("MEMORY_EXHIBIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("memory-exhibit-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String) -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func home(w:World,token:String,at:Vector2=NEAR) -> void:
	put(w,token,at,"home")

## Stand one tile west of a Lanyang cell (same spot test_lanyang_revisit uses).
func beside(w:World,token:String,cell:Vector2i) -> void:
	put(w,token,Vector2(cell.x-0.5,cell.y+0.5),"lanyang")

func act(w:World,token:String,action:String,p:Vector2i,extra:String="",request:String="") -> Dictionary:
	serial+=1
	return w.act(token,request if not request.is_empty() else "exhibit-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

## Rejected with the exact message (when given) and the whole world state byte-identical.
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
	var before:=var_to_bytes(w.state)
	var had:=pl(w,token).has(Exhibit.RECORD_KEY)
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or str(r.get("message",""))==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(w.state)==before,"%s: whole world state byte-identical"%label)
	expect(pl(w,token).has(Exhibit.RECORD_KEY)==had,"%s: no memory_exhibit record invented"%label)

func view(w:World,token:String,id:String,label:String) -> Dictionary:
	home(w,token)
	return ok(w,token,Exhibit.VIEW_ACTION,Exhibit.stand_cell(w.state),Exhibit.extra_for(id),label)

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## Earned canal repair by `token` (materials written into the bag first).
func earn_repair(w:World,token:String) -> bool:
	for cell:Vector2i in World.LANYANG_LIFE.BLOCKAGES:
		beside(w,token,cell)
		if not act(w,token,"lanyang_clear",cell).ok:return false
	beside(w,token,World.LANYANG_LIFE.SERVICE)
	for item in World.LANYANG_LIFE.REPAIR_COST:pl(w,token).inventory[item]=int(World.LANYANG_LIFE.REPAIR_COST[item])
	return act(w,token,"lanyang_donate",World.LANYANG_LIFE.SERVICE).ok and w.state.lanyang_life.repaired==true

## Earned first 分水 memory (3 observations + 3 rounds) for `token`.
func earn_memory(w:World,token:String) -> bool:
	for cell:Vector2i in Memory.OBSERVATIONS:
		beside(w,token,cell)
		if not act(w,token,"memory_observe",cell).ok:return false
	beside(w,token,Memory.SERVICE)
	for pair in [[2,2],[1,3],[2,1]]:
		if not act(w,token,"memory_gate",Memory.SERVICE,"a:%d"%pair[0]).ok:return false
		if not act(w,token,"memory_gate",Memory.SERVICE,"b:%d"%pair[1]).ok:return false
		if not act(w,token,"memory_flow",Memory.SERVICE).ok:return false
	return w.state.history_memory.players[token].completed==true

func earn_plaque(w:World,token:String) -> bool:
	beside(w,token,Memory.SERVICE)
	if not act(w,token,"memory_plaque",Memory.SERVICE).ok:return false
	w.state.history_memory.players[token].erase("completed_day")  # Legacy record for the day-one fixture.
	return true

## Earned 旱日分流 on day 1 (spring 6/4/2): gates a:3 b:2, then the three fields.
func earn_revisit(w:World,token:String) -> bool:
	beside(w,token,Revisit.GATE_CELL)
	if not act(w,token,Revisit.GATE_ACTION,Revisit.GATE_CELL,"a:3").ok:return false
	if not act(w,token,Revisit.GATE_ACTION,Revisit.GATE_CELL,"b:2").ok:return false
	for field:String in Revisit.FIELDS:
		beside(w,token,Revisit.FIELD_CELLS[field])
		if not act(w,token,Revisit.CHECK_ACTION,Revisit.FIELD_CELLS[field]).ok:return false
	return Revisit.completed(w.state)

func earn_claim(w:World,token:String) -> bool:
	beside(w,token,Revisit.SERVICE)
	return act(w,token,Revisit.CLAIM_ACTION,Revisit.SERVICE).ok

func row(rows:Array,id:String) -> Dictionary:
	for r:Dictionary in rows:
		if r.id==id:return r
	return {}

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(Exhibit.ACTIONS==["exhibit_view"] and Exhibit.VIEW_ACTION.length()<=24,"one action, within the Session name bound")
	expect(Exhibit.CANDIDATES==[Vector2i(39,26),Vector2i(41,23),Vector2i(37,22)] and is_equal_approx(Exhibit.REACH,3.2),"stand candidates and reach")
	expect(Exhibit.EXHIBIT_ORDER==["lanyang","jinguashi","tea_pottery","beimen"] and Exhibit.EXHIBITS.size()==4,"four fixed exhibit slots in order")
	var names:={"lanyang":["分水木牌","宜蘭・蘭陽水圳"],"jinguashi":["礦燈","金瓜石"],"tea_pottery":["陶器","貓空與鶯歌"],"beimen":["鹽籃","臺南北門"]}
	for id:String in Exhibit.EXHIBIT_ORDER:
		expect(str(Exhibit.EXHIBITS[id].name)==str(names[id][0]) and str(Exhibit.EXHIBITS[id].region)==str(names[id][1]),"%s name/region"%id)
		expect(Session.extra_allowed(Exhibit.VIEW_ACTION,Exhibit.extra_for(id)),"%s extra passes the Session transport bound"%id)
	var other:=Revisit.ACTIONS+Souv.ACTIONS+Show.ACTIONS+Meet.ACTIONS+Harvest.ACTIONS+Market.ACTIONS+Warmer.ACTIONS+["memory_observe","memory_gate","memory_flow","memory_plaque","news_read","ferry_news_read","festival_story_open","build","remove"]
	expect(not Exhibit.VIEW_ACTION in other,"action name does not collide with existing actions")
	expect(Exhibit.EMPTY_LINE=="這段回訪故事還沒補齊，展台先空著。","honest empty-pedestal line")
	expect(Revisit.DISCLAIMER.contains("原創") and Revisit.DISCLAIMER.contains("非史料"),"disclaimer reused from the revisit")
	for message:String in [Exhibit.NO_PLAYER,Exhibit.LOCKED,Exhibit.WRONG_REGION,Exhibit.NO_POINT,Exhibit.WRONG_POINT,Exhibit.TOO_FAR,Exhibit.UNKNOWN_EXHIBIT,Exhibit.NOT_ON_DISPLAY,Exhibit.ALREADY_SEEN,Exhibit.BAD_EXTRA,Exhibit.VIEW_OK]:
		expect(not message.is_empty(),"message constant non-empty")
	var hints:={}
	for h:String in [Exhibit.HINT_REVISIT_LOCKED,Exhibit.HINT_NOT_DONE_NOT_READY,Exhibit.HINT_NOT_DONE,Exhibit.HINT_NOT_READY,Exhibit.HINT_UNCLAIMED,Exhibit.HINT_CLAIMED]:hints[h]=true
	expect(hints.size()==6,"six distinct personal hints")
	expect(Exhibit.HINT_NOT_READY=="你還沒走完自己的第一次分水；到蘭陽找星禾補做後，可以領一塊分水木牌。" and Exhibit.HINT_UNCLAIMED=="你的木牌還在星禾那裡等你領。","latecomer hints as planned")

# ----------------------------------------------------------------------- site --

## Every fixed home landmark the stand must neither stand on nor touch (souvenir list +
## the souvenir booth candidates and the community table warmer cells).
static func home_landmarks() -> Dictionary:
	var marks:Dictionary={}
	for npc:String in Village.NPCS:
		if str(Village.NPCS[npc].get("region","home"))=="home":marks["npc "+npc]=Village.NPCS[npc].cell
	for npc:String in Village.FESTIVAL_SPOTS:marks["festival spot "+npc]=Village.FESTIVAL_SPOTS[npc]
	for cell:Vector2i in World.Festival.VISITORS:marks["festival visitor "+str(World.Festival.VISITORS[cell])]=cell
	for index in range(World.Festival.STOPS.size()):marks["festival stop %d"%index]=World.Festival.STOPS[index]
	marks["wind-chime tree"]=World.Festival.TREE_CELL
	marks["notice board"]=Vector2i(40,29)
	marks["seed shop"]=Vector2i(43,29)
	marks["chapter starter"]=World.CHAPTER_ONE.STARTER_CELL
	for index in range(World.SHIPPING.CANDIDATES.size()):marks["shipping candidate %d"%index]=World.SHIPPING.CANDIDATES[index]
	for index in range(World.COMMUNITY.CANDIDATES.size()):marks["community table candidate %d"%index]=World.COMMUNITY.CANDIDATES[index]
	for index in range(Market.CANDIDATES.size()):marks["market candidate %d"%index]=Market.CANDIDATES[index]
	for index in range(Souv.CANDIDATES.size()):marks["souvenir booth candidate %d"%index]=Souv.CANDIDATES[index]
	for index in range(Harvest.CELLS.size()):marks["harvest relay cell %d"%index]=Harvest.CELLS[index]
	marks["fishing meet sign"]=Meet.SIGN
	for cell:Vector2i in Meet.SHORE:marks["fishing meet shore "+str(cell)]=cell
	for cell:Vector2i in Meet.water_cells():marks["fishing meet water "+str(cell)]=cell
	for cell:Vector2i in Show.cells():marks["showcase "+str(cell)]=cell
	for animal:String in World.LIVESTOCK.ANIMALS:
		marks["livestock "+animal]=World.LIVESTOCK.ANIMALS[animal].cell
		marks["livestock collector "+animal]=World.LIVESTOCK.collector_cell(animal)
	for index in range(Bond.RANCH_CELLS.size()):marks["ranch cell %d"%index]=Bond.RANCH_CELLS[index]
	for index in range(Bond.DOCK_CELLS.size()):marks["dock cell %d"%index]=Bond.DOCK_CELLS[index]
	for index in range(Bond.POST_CELLS.size()):marks["post cell %d"%index]=Bond.POST_CELLS[index]
	for index in range(Bond.BELL_CELLS.size()):marks["bell cell %d"%index]=Bond.BELL_CELLS[index]
	var transit:Dictionary=World.TRANSIT.points(World.REGIONS.HOME)
	for point:String in transit:marks["transit "+point]=transit[point].cell
	marks["home exit"]=World.REGIONS.exit_cell(World.REGIONS.HOME)
	marks["home arrival"]=Vector2i(World.REGIONS.spawn(World.REGIONS.HOME))
	marks["player spawn"]=Vector2i(World.SPAWN)
	marks["chicken"]=Vector2i(45,34)
	marks["quarry"]=Vector2i(54,25)
	marks["copper"]=World.COPPER_CELL
	for y in range(29,32):
		for x in [55,56]:marks["bridge %d,%d"%[x,y]]=Vector2i(x,y)
	for y in range(24,29):
		for x in [52,53]:marks["industry plot %d,%d"%[x,y]]=Vector2i(x,y)
	return marks

## Tiles reachable on foot from the spawn (4-neighbour flood over can_stand tile centres).
static func reachable(w) -> Dictionary:
	var seen:={Vector2i(World.SPAWN):true}
	var queue:=[Vector2i(World.SPAWN)]
	while not queue.is_empty():
		var c:Vector2i=queue.pop_front()
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var n:=c+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			if not w.can_stand(Vector2(n)+HALF):continue
			seen[n]=true
			queue.append(n)
	return seen

func check_site() -> void:
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game home (bridge, picnic, festival opened).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var marks:=home_landmarks()
	for cell:Vector2i in Exhibit.CANDIDATES:
		for w in [plain,busy]:
			expect(w.is_land(cell) and not w.water(cell),"candidate %s is land, not water"%str(cell))
			expect(w.resource(cell)=="","candidate %s has no resource"%str(cell))
		expect(World.land(cell) and World.base_resource(cell)=="","candidate %s: island land with no fixed tree/rock/grass"%str(cell))
		for mark:String in marks:
			var at:Vector2i=marks[mark]
			expect(maxi(absi(cell.x-at.x),absi(cell.y-at.y))>=2,"candidate %s is not on or touching %s %s"%[str(cell),mark,str(at)])
		for rect:Rect2i in BUILD_PLOTS:
			expect(not rect.grow(1).has_point(cell),"candidate %s does not touch build plot %s"%[str(cell),str(rect)])
		expect(not FIRST_FIELD.grow(1).has_point(cell),"candidate %s does not touch 小栗留的田"%str(cell))
		expect(not plain.protected(cell) and not plain.blocked(cell),"candidate %s free before the festival"%str(cell))
		for other:Vector2i in Exhibit.CANDIDATES:
			if other!=cell:expect(maxi(absi(cell.x-other.x),absi(cell.y-other.y))>=2,"candidates %s / %s apart"%[str(cell),str(other)])
	# Picnic alone (souvenir booth unlocked) does not reserve the exhibit stand.
	var picnic:=World.new()
	picnic.state.picnic=true
	expect(not picnic.protected(STAND) and not picnic.blocked(STAND) and Exhibit.stand_cell(picnic.state)==Exhibit.NO_CELL,"picnic without the festival: stand not reserved")
	expect(Exhibit.stand_cell(plain.state)==Exhibit.NO_CELL and Exhibit.cell_for(plain.state)==STAND and not Exhibit.paused(plain.state),"before the festival: no stand (first free candidate would be 39,26)")
	expect(Exhibit.stand_cell(busy.state)==STAND and not Exhibit.paused(busy.state) and Exhibit.blocked_cells(busy.state).is_empty(),"after the festival the stand is at 39,26")
	expect(busy.protected(STAND) and busy.blocked(STAND) and Exhibit.reserved(busy.state,STAND),"active stand tile reserved and blocking after the festival")
	for cell:Vector2i in Exhibit.CANDIDATES.slice(1):
		expect(not busy.protected(cell) and not busy.blocked(cell),"unused candidate %s stays free"%str(cell))
	for y in range(STAND.y-1,STAND.y+2):
		for x in range(STAND.x-1,STAND.x+2):
			var p:=Vector2i(x,y)
			if p==STAND:continue
			expect(not Exhibit.reserved(busy.state,p) and busy.blocked(p)==plain.blocked(p) and busy.protected(p)==plain.protected(p),"neighbour %s of the stand unchanged by the festival"%str(p))
	var flood:=reachable(busy)
	expect(busy.can_stand(NEAR) and flood.has(Vector2i(NEAR)) and NEAR.distance_to(Vector2(STAND)+HALF)<=Exhibit.REACH,"tile 39,27 walkable, reachable from the spawn, within reach of the stand")
	expect(FAR.distance_to(Vector2(STAND)+HALF)>Exhibit.REACH,"spawn is out of reach of the stand")
	for cell:Vector2i in Exhibit.CANDIDATES:
		var touching:=false
		for d:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			if flood.has(cell+d):touching=true
		expect(touching,"candidate %s has a reachable standing tile next to it"%str(cell))
	# The souvenir booth and its candidates are unaffected by the festival stand.
	expect(Souv.active_cell(busy.state)==Souv.CANDIDATES[0] and busy.protected(Souv.CANDIDATES[0]),"souvenir booth still at 37,25")

# --------------------------------------------------------------------- locked --

func check_locked() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	home(w,ALPHA)
	expect(not Exhibit.unlocked(w.state) and Exhibit.public(w.state)=={} and Exhibit.on_display_ids(w.state).is_empty(),"locked: helpers")
	for r:Dictionary in Exhibit.exhibits(w.state,ALPHA):
		expect(r.on_display==false and r.unread==false and r.lines==[Exhibit.EMPTY_LINE],"locked: %s not on display"%r.id)
	for id in Exhibit.EXHIBIT_ORDER+["bogus",""]:
		refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,str(id),Exhibit.LOCKED,"locked view '%s'"%id)
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,Vector2i(1,1),"lanyang",Exhibit.LOCKED,"locked view at a random cell")
	expect(not w.protected(STAND) and not w.blocked(STAND),"stand tile free before the festival")
	expect(Exhibit.view_block(w.state,"lanyang",ALPHA)==Exhibit.LOCKED,"locked: view_block")

# ------------------------------------------------------------------ main flow --

## Order A: festival opened first, the revisit completed later.
func main_flow() -> World:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	w.state.festival_story_open=true # PRESET (see header)
	home(w,ALPHA)
	home(w,BETA)
	expect(Exhibit.unlocked(w.state) and Exhibit.stand_cell(w.state)==STAND,"festival opened: stand at 39,26")
	expect(Exhibit.on_display_ids(w.state).is_empty() and Exhibit.unread_count(w.state,ALPHA)==0,"festival before revisit: nothing on display, nothing unread")
	for entry:Dictionary in Exhibit.exhibits(w.state,ALPHA):
		var keys:Array=entry.keys()
		keys.sort()
		expect(keys==ROW_KEYS,"row keys (%s)"%str(keys))
		expect(entry.on_display==false and entry.lines==[Exhibit.EMPTY_LINE] and entry.source=="" and entry.disclaimer=="","%s is an empty pedestal before the revisit"%entry.id)
	expect(Exhibit.recap(w.state)=={} and Exhibit.recap_pages("lanyang",w.state).is_empty(),"no recap before the revisit")
	expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_REVISIT_LOCKED,"hint: revisit not open yet")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.NOT_ON_DISPLAY,"lanyang before the revisit")
	for id:String in ["jinguashi","tea_pottery","beimen"]:
		refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,id,Exhibit.NOT_ON_DISPLAY,"%s (story not implemented)"%id)
	expect(Exhibit.view_block(w.state,"lanyang",ALPHA)==Exhibit.NOT_ON_DISPLAY,"view_block NOT_ON_DISPLAY")
	if not expect(earn_repair(w,ALPHA),"canal repair earned"):return null
	if not expect(earn_memory(w,ALPHA),"alpha's first 分水 earned"):return null
	if not expect(earn_plaque(w,ALPHA),"plaque earned"):return null
	expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_NOT_DONE,"hint: alpha ready, revisit not done")
	expect(Exhibit.personal_hint(w.state,BETA)==Exhibit.HINT_NOT_DONE_NOT_READY,"hint: beta not ready, revisit not done")
	home(w,ALPHA)
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.NOT_ON_DISPLAY,"lanyang with the revisit open but not done")
	if not expect(earn_revisit(w,ALPHA),"旱日分流 earned (a:3 b:2, three fields)"):return null
	home(w,ALPHA)
	# Exhibit updates with progress.
	expect(Exhibit.on_display_ids(w.state)==["lanyang"] and Exhibit.on_display(w.state,"lanyang"),"revisit done: lanyang on display")
	expect(Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"unread 1 for both")
	expect(same(Exhibit.public(w.state),{"cell":STAND,"paused":false,"on_display":["lanyang"],"blocked_cells":[]}),"public block")
	expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_UNCLAIMED and Exhibit.personal_hint(w.state,BETA)==Exhibit.HINT_NOT_READY,"hints: alpha unclaimed, beta not ready")
	var rows:=Exhibit.exhibits(w.state,ALPHA)
	var lan:=row(rows,"lanyang")
	expect(lan.on_display==true and lan.unread==true and lan.seen==false and lan.source==Revisit.PLAQUE_SOURCE and lan.project==Revisit.PLAQUE_PROJECT and lan.disclaimer==Revisit.DISCLAIMER,"lanyang row: provenance + disclaimer")
	var joined:="\n".join(PackedStringArray(lan.lines))
	expect(joined.contains("第 1 日・春季・晴天") and joined.contains("上游 6／中段 4／田尾 2") and joined.contains("上游閘 3 檔、中段閘 2 檔") and joined.contains(Revisit.DISCLAIMER),"lanyang lines carry the recoverable recap (%s)"%joined)
	for id:String in ["jinguashi","tea_pottery","beimen"]:
		expect(row(rows,id).on_display==false and row(rows,id).lines==[Exhibit.EMPTY_LINE],"%s still empty after the revisit"%id)
	var r:=Exhibit.recap(w.state)
	expect(same(r,{"day":1,"season":"spring","season_label":"春季","weather":"sunny","weather_label":"晴天","demand":[6,4,2],"gates":[3,2],
		"order":["upstream","middle","tail"],"order_names":["上游的田","中段的田","田尾的田"],"reason":Revisit.reason_for("spring")}),"recap from the stored record (%s)"%str(r))
	var pages:=Exhibit.recap_pages("lanyang",w.state)
	expect(pages.size()==4,"four recap pages")
	for page:Dictionary in pages:expect(not str(page.title).is_empty() and (page.lines as Array).size()>=2,"page '%s' has a title and lines"%page.title)
	var all_text:=JSON.stringify(pages)
	expect(all_text.contains("6／4／2") and all_text.contains("上游閘調到 3 檔") and all_text.contains("上游的田、中段的田、田尾的田") and all_text.contains("沒有記錄是誰"),"pages: numbers, order, honest no-actor note")
	expect(str((pages[3].lines as Array).back())==Revisit.DISCLAIMER,"last page ends with the disclaimer")
	for id:String in ["jinguashi","tea_pottery","beimen","bogus"]:expect(Exhibit.recap_pages(id,w.state).is_empty(),"no pages for %s"%id)
	# Rejections (whole state byte-identical).
	beside(w,ALPHA,Revisit.GATE_CELL)
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.WRONG_REGION,"view from Lanyang")
	home(w,ALPHA)
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,Exhibit.CANDIDATES[1],"lanyang",Exhibit.WRONG_POINT,"another candidate")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,Vector2i(40,29),"lanyang",Exhibit.WRONG_POINT,"the notice board")
	home(w,ALPHA,FAR)
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.TOO_FAR,"from the spawn")
	home(w,ALPHA,Vector2(39.5,30.0))
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.TOO_FAR,"3.5 tiles away")
	home(w,ALPHA)
	for bad:String in ["","bogus","LANYANG","lanyang|0",KIT,"lanyang "]:
		refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,bad,Exhibit.UNKNOWN_EXHIBIT,"unknown id '%s'"%bad)
	for id:String in ["jinguashi","tea_pottery","beimen"]:
		refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,id,Exhibit.NOT_ON_DISPLAY,"%s still not on display"%id)
	pl(w,ALPHA).inventory["wood"]=20
	refuse(w,ALPHA,"build",STAND,"lamp",PROTECTED_MSG,"build a lamp on the stand")
	refuse(w,ALPHA,"hoe",STAND,"",PROTECTED_MSG,"till the stand")
	# Alpha views: only alpha's record changes.
	var before:Dictionary=w.state.duplicate(true)
	var beta_before:Dictionary=pl(w,BETA).duplicate(true)
	var first:=w.act(ALPHA,"exhibit-replay-1",Exhibit.VIEW_ACTION,STAND,"lanyang")
	expect(first.ok==true and str(first.message)==Exhibit.VIEW_OK%"分水木牌","alpha views lanyang (%s)"%str(first.message))
	expect(same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["lanyang"]}),"alpha's record is exactly seen=[lanyang]")
	var after:Dictionary=w.state.duplicate(true)
	for s:Dictionary in [before,after]:
		s.erase("committed")
		s.players[ALPHA].erase("receipts")
		s.players[ALPHA].erase(Exhibit.RECORD_KEY)
	expect(same(before,after),"nothing else in the world changed")
	expect(same(pl(w,BETA),beta_before) and not pl(w,BETA).has(Exhibit.RECORD_KEY),"beta untouched by alpha's view")
	expect(Exhibit.unread_count(w.state,ALPHA)==0 and Exhibit.unread_count(w.state,BETA)==1,"unread: alpha 0, beta 1")
	expect(row(Exhibit.exhibits(w.state,ALPHA),"lanyang").seen==true and row(Exhibit.exhibits(w.state,BETA),"lanyang").seen==false,"seen per viewer")
	# Resend of the same request id: stored receipt, no change.
	var snap:=var_to_bytes(w.state)
	var second:=w.act(ALPHA,"exhibit-replay-1",Exhibit.VIEW_ACTION,STAND,"lanyang")
	expect(second==first and var_to_bytes(w.state)==snap,"resent request id returns the receipt and changes nothing")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.ALREADY_SEEN,"alpha views again (new request)")
	expect(Exhibit.view_block(w.state,"lanyang",ALPHA)==Exhibit.ALREADY_SEEN and Exhibit.view_block(w.state,"lanyang",BETA)=="","view_block per viewer")
	expect(Exhibit.recap_pages("lanyang",w.state).size()==4,"re-reading stays possible client-side after seen")
	# Snapshot privacy while alpha has seen and beta has not.
	await check_snapshot(w)
	# Beta (never did her own 分水) views independently.
	view(w,BETA,"lanyang","beta views lanyang")
	expect(same(pl(w,BETA).get(Exhibit.RECORD_KEY),{"seen":["lanyang"]}) and same(pl(w,ALPHA).get(Exhibit.RECORD_KEY),{"seen":["lanyang"]}),"both records exactly seen=[lanyang]")
	expect(Exhibit.personal_hint(w.state,BETA)==Exhibit.HINT_NOT_READY,"beta still gets the catch-up hint after viewing")
	# Alpha claims her plaque: hint updates.
	if expect(earn_claim(w,ALPHA),"alpha claims her plaque"):
		expect(Exhibit.personal_hint(w.state,ALPHA)==Exhibit.HINT_CLAIMED and same(Exhibit.own(w.state,ALPHA),{"seen":["lanyang"],"first_share_done":true,"plaque_claimed":true,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"hint/own after the claim")
	home(w,ALPHA)
	# Late joiner: never visited Lanyang, never did 分水.
	w.add_player(LATE,"Late")
	home(w,LATE)
	expect(Exhibit.unread_count(w.state,LATE)==1 and Exhibit.personal_hint(w.state,LATE)==Exhibit.HINT_NOT_READY,"late joiner: unread 1, catch-up hint")
	expect(same(Exhibit.personal(w.state,LATE),{"seen":[],"unread":1,"first_share_done":false,"plaque_claimed":false,"hint":Exhibit.HINT_NOT_READY,
		"sorting_done":false,"lantern_claimed":false,"lantern_hint":Exhibit.HINT_JG_LOCKED,
		"comparison_done":false,"teaware_claimed":false,"teaware_hint":Exhibit.HINT_TEA_NOT_DONE_NOT_READY,
		"raking_done":false,"basket_claimed":false,"basket_hint":Exhibit.HINT_SALT_LOCKED}),"late joiner personal()")
	view(w,LATE,"lanyang","late joiner views lanyang")
	expect(Exhibit.unread_count(w.state,LATE)==0 and same(pl(w,LATE).get(Exhibit.RECORD_KEY),{"seen":["lanyang"]}),"late joiner marked seen")
	# Beta does her own 分水 later: hint becomes "unclaimed", then claimed.
	if expect(earn_memory(w,BETA),"beta's first 分水 earned later"):
		expect(Exhibit.personal_hint(w.state,BETA)==Exhibit.HINT_UNCLAIMED,"beta: plaque waiting at Xinghe")
		expect(earn_claim(w,BETA),"beta claims")
		expect(Exhibit.personal_hint(w.state,BETA)==Exhibit.HINT_CLAIMED,"beta: claimed hint")
	home(w,BETA)
	return w

# ------------------------------------------------------------------ snapshot --

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var saved_path:=w.save_path
	w.save_path=""
	session.peers={1:ALPHA,2:BETA}
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		expect(same(public.get(Exhibit.STATE_KEY),{"cell":STAND,"paused":false,"on_display":["lanyang"],"blocked_cells":[]}),"public_state(%s) carries the public exhibit block"%region)
		var leaked:=false
		for id in public.get("players",{}):
			if (public.players[id] as Dictionary).has(Exhibit.RECORD_KEY):leaked=true
		expect(not leaked and not JSON.stringify(public).contains("\"seen\""),"public_state(%s) carries no seen list"%region)
	session._send_snapshot(1)
	var a:Dictionary=session.snapshot
	expect(same(a.get(Exhibit.OWN_KEY),Exhibit.own(w.state,ALPHA)) and same(a.get(Exhibit.OWN_KEY),{"seen":["lanyang"],"first_share_done":true,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"alpha's own block")
	expect(JSON.stringify(a).count("\""+Exhibit.OWN_KEY+"\"")==1,"exactly one own block")
	expect(not JSON.stringify(a.get(Exhibit.OWN_KEY)).contains(ALPHA) and not JSON.stringify(a).contains(BETA) and not JSON.stringify(a).contains(ALPHA),"no raw token in alpha's snapshot")
	# Client-side helpers give the same answers as the server-side ones.
	expect(same(Exhibit.exhibits(a),Exhibit.exhibits(w.state,ALPHA)),"client exhibits() == server exhibits(alpha)")
	expect(same(Exhibit.personal(a),Exhibit.personal(w.state,ALPHA)),"client personal() == server personal(alpha)")
	expect(same(Exhibit.recap_pages("lanyang",a),Exhibit.recap_pages("lanyang",w.state)),"client recap pages == server")
	expect(Exhibit.stand_cell(a)==STAND and not Exhibit.paused(a) and Exhibit.unread_count(a)==0,"client stand/unread")
	session.peers={1:BETA,2:ALPHA}
	session._send_snapshot(1)
	var b:Dictionary=session.snapshot
	expect(same(b.get(Exhibit.OWN_KEY),{"seen":[],"first_share_done":false,"plaque_claimed":false,"sorting_done":false,"lantern_claimed":false,"comparison_done":false,"teaware_claimed":false,"raking_done":false,"basket_claimed":false}),"beta's own block shows nothing of alpha's")
	expect(Exhibit.unread_count(b)==1 and Exhibit.personal_hint(b)==Exhibit.HINT_NOT_READY,"beta's client: unread 1, catch-up hint")
	expect(Exhibit.view_block(b,"lanyang")=="" and Exhibit.view_block(a,"lanyang")==Exhibit.ALREADY_SEEN,"client view_block per recipient")
	session.world=null
	session.queue_free()
	w.save_path=saved_path
	await process_frame

# ------------------------------------------------------------------- saving --

func check_save_reload(w:World) -> void:
	var path:=temp_path("main")
	var fixture:=temp_path("fixture")
	w.save_path=path
	if not expect(w.save(),"world saves"):return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(path),"reload"):return
	for token in [ALPHA,BETA,LATE]:
		var a:Dictionary=pl(reloaded,token).duplicate(true)
		var b:Dictionary=pl(w,token).duplicate(true)
		a.erase("fish_caught") # load backfills fish_caught=0 (existing migration, not this feature)
		b.erase("fish_caught")
		expect(same(a,b),"%s's whole record survives reload (canonical)"%token)
		expect(same(Exhibit.personal(reloaded.state,token),Exhibit.personal(w.state,token)) and same(Exhibit.exhibits(reloaded.state,token),Exhibit.exhibits(w.state,token)),"%s's exhibit view identical after reload"%token)
	expect(same(Exhibit.public(reloaded.state),Exhibit.public(w.state)),"public block identical after reload")
	home(reloaded,ALPHA)
	refuse(reloaded,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.ALREADY_SEEN,"after reload alpha has still seen it")
	expect(reloaded.protected(STAND) and reloaded.blocked(STAND),"stand reserved after reload")
	var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	# Legacy save without any memory_exhibit record.
	var old:Dictionary=base.duplicate(true)
	for token in old.players:(old.players[token] as Dictionary).erase(Exhibit.RECORD_KEY)
	expect(write_json(fixture,old),"write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"save without memory_exhibit records loads")
	expect(not pl(legacy,ALPHA).has(Exhibit.RECORD_KEY) and Exhibit.unread_count(legacy.state,ALPHA)==1 and Exhibit.unread_count(legacy.state,LATE)==1,"legacy: nothing invented, unread again")
	# An old save from before the festival (no flag, no records) loads.
	var pre:Dictionary=old.duplicate(true)
	pre.erase("festival_story_open")
	expect(validates(pre),"pre-festival save without records validates")
	var fresh:=World.new()
	fresh.add_player("solo","solo")
	expect(validates(fresh.state),"brand-new world validates")
	expect(write_json(fixture,base) and World.new().load_world(fixture),"control fixture loads")
	# Controls for the precondition tampers: the same change without records is accepted.
	var control_closed:Dictionary=old.duplicate(true)
	control_closed.festival_story_open=false
	expect(validates(control_closed),"control: festival closed without records validates")
	var control_norevisit:Dictionary=old.duplicate(true)
	control_norevisit.erase(Revisit.STATE_KEY)
	expect(validates(control_norevisit),"control: no revisit record without exhibit records validates")
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var labels:=["record is a list","record is null","record is a string","extra record key","missing seen","seen is a string","seen is a dictionary","empty seen",
		"unknown id","duplicate id","numeric id","seen jinguashi (not on display)","seen beimen (not on display)","five entries",
		"seen but festival not opened","seen but festival flag missing","seen but revisit not completed","top-level public block in a save","late joiner record tampered"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"schema rejects "+label)
		expect(probe.state==pristine,"rejected load leaves the world untouched: "+label)

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var a:Dictionary=s.players[ALPHA]
	match label:
		"record is a list":a[Exhibit.RECORD_KEY]=["lanyang"]
		"record is null":a[Exhibit.RECORD_KEY]=null
		"record is a string":a[Exhibit.RECORD_KEY]="lanyang"
		"extra record key":a[Exhibit.RECORD_KEY].when=1
		"missing seen":a[Exhibit.RECORD_KEY]={}
		"seen is a string":a[Exhibit.RECORD_KEY].seen="lanyang"
		"seen is a dictionary":a[Exhibit.RECORD_KEY].seen={"lanyang":true}
		"empty seen":a[Exhibit.RECORD_KEY].seen=[]
		"unknown id":a[Exhibit.RECORD_KEY].seen=["lanyang","bogus"]
		"duplicate id":a[Exhibit.RECORD_KEY].seen=["lanyang","lanyang"]
		"numeric id":a[Exhibit.RECORD_KEY].seen=[1]
		"seen jinguashi (not on display)":a[Exhibit.RECORD_KEY].seen=["lanyang","jinguashi"]
		"seen beimen (not on display)":a[Exhibit.RECORD_KEY].seen=["beimen"]
		"five entries":a[Exhibit.RECORD_KEY].seen=["lanyang","jinguashi","tea_pottery","beimen","lanyang"]
		"seen but festival not opened":s.festival_story_open=false
		"seen but festival flag missing":s.erase("festival_story_open")
		"seen but revisit not completed":s.erase(Revisit.STATE_KEY)
		"top-level public block in a save":s[Exhibit.STATE_KEY]={"cell":[39,26],"paused":false,"on_display":["lanyang"],"blocked_cells":[]}
		"late joiner record tampered":s.players[LATE][Exhibit.RECORD_KEY]={"seen":["tea_pottery"]}
	return s

# ------------------------------------------------- reverse order + fallback --

## Order B: the revisit is completed first (festival closed: LOCKED), then the festival
## opens and the exhibit is on display at once. Also the stand fallback and pause.
func check_reverse_order_and_fallback() -> void:
	var w:=World.new()
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	if not expect(earn_repair(w,ALPHA) and earn_memory(w,ALPHA) and earn_plaque(w,ALPHA) and earn_revisit(w,ALPHA),"order B: revisit earned before the festival"):return
	home(w,ALPHA)
	home(w,BETA)
	expect(not Exhibit.unlocked(w.state) and Exhibit.on_display_ids(w.state).is_empty() and Exhibit.public(w.state)=={},"order B: revisit done but festival closed -> nothing shown")
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.LOCKED,"order B: view before the festival")
	expect(not w.protected(STAND),"order B: stand not reserved before the festival")
	w.state.festival_story_open=true # PRESET
	expect(Exhibit.on_display_ids(w.state)==["lanyang"] and Exhibit.unread_count(w.state,ALPHA)==1 and Exhibit.unread_count(w.state,BETA)==1,"order B: opening the festival shows the plaque at once, unread for both")
	expect(w.protected(STAND) and w.blocked(STAND),"order B: stand reserved after opening")
	# Fallback: PRESET lamp on 39,26 (old-save shape: built before the festival).
	w.state.objects[World.key(STAND)]={"type":"lamp","owner":ALPHA,"items":{}}
	var second:Vector2i=Exhibit.CANDIDATES[1]
	expect(Exhibit.stand_cell(w.state)==second and same(Exhibit.public(w.state),{"cell":second,"paused":false,"on_display":["lanyang"],"blocked_cells":[]}),"occupied 39,26: stand falls back to 41,23")
	expect(w.protected(second) and w.blocked(second) and not Exhibit.reserved(w.state,STAND),"fallback tile reserved; the occupied tile is not")
	expect(validates(w.state),"world with a lamp on the first candidate validates")
	home(w,ALPHA,Vector2(41.5,24.5))
	refuse(w,ALPHA,Exhibit.VIEW_ACTION,STAND,"lanyang",Exhibit.WRONG_POINT,"old stand tile after fallback")
	expect(w.act(ALPHA,"exhibit-fallback-1",Exhibit.VIEW_ACTION,second,"lanyang").ok==true,"alpha views at the fallback stand")
	for cell:Vector2i in Exhibit.CANDIDATES:w.state.objects[World.key(cell)]={"type":"lamp","owner":ALPHA,"items":{}}
	expect(Exhibit.stand_cell(w.state)==Exhibit.NO_CELL and Exhibit.paused(w.state) and Exhibit.blocked_cells(w.state)==Exhibit.CANDIDATES,"all occupied: paused, cells to clear listed")
	expect(same(Exhibit.public(w.state),{"cell":Exhibit.NO_CELL,"paused":true,"on_display":["lanyang"],"blocked_cells":Exhibit.CANDIDATES}),"paused public block")
	for cell:Vector2i in Exhibit.CANDIDATES:expect(not Exhibit.reserved(w.state,cell),"paused stand reserves nothing (%s)"%str(cell))
	var paused_msg:=Exhibit.NO_POINT%"(39,26)、(41,23)、(37,22)"
	home(w,BETA)
	refuse(w,BETA,Exhibit.VIEW_ACTION,STAND,"lanyang",paused_msg,"view while paused")
	expect(Exhibit.view_block(w.state,"lanyang",BETA)==paused_msg,"view_block while paused")
	expect(validates(w.state),"world with all three candidates built over validates (old save never invalid)")
	w.state.objects.erase(World.key(Exhibit.CANDIDATES[2]))
	expect(Exhibit.stand_cell(w.state)==Exhibit.CANDIDATES[2],"clearing 37,22 brings the stand back there")
	w.state.objects.erase(World.key(STAND))
	expect(Exhibit.stand_cell(w.state)==STAND,"clearing 39,26 moves it back to the default")
	view(w,BETA,"lanyang","beta views at the default stand")

# --------------------------------------------------------------- module level --

func check_module() -> void:
	var state:={"festival_story_open":true,"objects":{},"players":{"x":{"x":39.5,"y":27.5,"inventory":{}}},
		"lanyang_life":{"repaired":true},"history_memory":{"plaque":true,"players":{}},
		Revisit.STATE_KEY:{"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed":{}},"time":0.0}
	var before:=var_to_bytes(state)
	expect(Exhibit.apply(state,"x","revisit_gate",STAND,"lanyang",true).message==Exhibit.BAD_EXTRA,"module: foreign action")
	expect(Exhibit.apply(state,"nobody",Exhibit.VIEW_ACTION,STAND,"lanyang",true).message==Exhibit.NO_PLAYER,"module: unknown player")
	state.players.x[Exhibit.RECORD_KEY]="broken"
	before=var_to_bytes(state)
	expect(Exhibit.apply(state,"x",Exhibit.VIEW_ACTION,STAND,"lanyang",true).message==Exhibit.BAD_EXTRA and var_to_bytes(state)==before,"module: corrupt record refused without writing")
	state.players.x.erase(Exhibit.RECORD_KEY)
	var r:=Exhibit.apply(state,"x",Exhibit.VIEW_ACTION,STAND,"lanyang",true)
	expect(r.ok==true and same(state.players.x[Exhibit.RECORD_KEY],{"seen":["lanyang"]}),"module: view writes the record")
	# Client-shaped snapshots (no players, own block only).
	var snap:={"festival_story":{"opened":true},Exhibit.STATE_KEY:{"cell":Vector2i(41,23),"paused":false,"on_display":["lanyang"],"blocked_cells":[]},
		Revisit.STATE_KEY:{"gates":[3,2],"day":1,"checked":["upstream","middle","tail"],"completed":true,"claimed_own":false},
		"lanyang_life":{"repaired":true},"history_memory":{"plaque":true,"own_memory":{"completed":false}},
		Exhibit.OWN_KEY:{"seen":[],"first_share_done":false,"plaque_claimed":false}}
	expect(Exhibit.unlocked(snap) and Exhibit.stand_cell(snap)==Vector2i(41,23),"client: stand cell read from the public block (no layers)")
	expect(Exhibit.personal_hint(snap)==Exhibit.HINT_NOT_READY,"client hint: not ready")
	snap[Exhibit.OWN_KEY]={"seen":["lanyang"],"first_share_done":true,"plaque_claimed":false}
	expect(Exhibit.personal_hint(snap)==Exhibit.HINT_UNCLAIMED and Exhibit.unread_count(snap)==0,"client hint: ready, unclaimed; seen")
	snap[Exhibit.OWN_KEY].plaque_claimed=true
	expect(Exhibit.personal_hint(snap)==Exhibit.HINT_CLAIMED,"client hint: claimed")
	snap.erase(Exhibit.OWN_KEY)
	snap.history_memory.own_memory.completed=true
	snap[Revisit.STATE_KEY].claimed_own=true
	expect(Exhibit.personal_hint(snap)==Exhibit.HINT_CLAIMED and Exhibit.seen_ids(snap).is_empty(),"client without own block falls back to revisit fields")
	snap[Exhibit.STATE_KEY]={"cell":Exhibit.NO_CELL,"paused":true,"on_display":["lanyang"],"blocked_cells":Exhibit.CANDIDATES}
	expect(Exhibit.paused(snap) and Exhibit.blocked_cells(snap)==Exhibit.CANDIDATES,"client: paused read from the public block")
	expect(not Exhibit.unlocked({}) and Exhibit.stand_cell({})==Exhibit.NO_CELL and Exhibit.exhibits({}).size()==4,"empty snapshot tolerated")
