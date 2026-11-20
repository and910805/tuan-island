extends SceneTree
## T071 regression suite for res://scripts/showcase.gd (家園布置題) and its World,
## SaveSchema and Session integration: picnic gate on all six actions, region / sign /
## reach / extra / stale-round gates, place/remove gates (outside the plot, occupied
## tile, unknown kind, not joined, too far), a full solo round meeting the theme and
## finishing early, timeout settlement with the theme unmet, the full-display bonus,
## two-player cooperation (removing a teammate's piece), the 8-player cap, leave /
## rejoin / disconnect / travel drops, exactly-once tickets (paid_round), cooldown,
## display cleared after the cooldown and at the next start, the four-theme rotation,
## the occupied-plot pause, refusals leaving the WHOLE world state byte-identical,
## whole-player equality (minus the showcase record) before/after, save -> reload
## equality, legacy saves, schema tampering, terrain/adjacency/reachability of the sign
## and every plot tile against the real world data, and snapshot privacy.
##
## PRESET (written straight into world state, not earned): state.picnic, state.board and
## festival_story_open (site checks only), state.time (advanced by assignment to reach
## deadlines and cooldowns), player positions (x/y) and regions, inventories (extra
## items so "unchanged" is meaningful), active_tokens (to simulate offline players),
## objects / ground written onto plot or sign cells (pause cases) and, for the schema
## cases only, tampered copies of saved records. Everything else goes through
## World.act and World.step.
const World=preload("res://scripts/world.gd")
const Show=preload("res://scripts/showcase.gd")
const Meet=preload("res://scripts/fishing_meet.gd")
const Harvest=preload("res://scripts/harvest_relay.gd")
const Market=preload("res://scripts/market_stall.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Village=preload("res://scripts/village.gd")
const Session=preload("res://scripts/session.gd")
const START:=1000.0
const HALF:=Vector2(0.5,0.5)
const PRIVATE_A:="showcase-private-alpha-token"
const PRIVATE_B:="showcase-private-beta-token"
const HOME_SPOT:=Vector2(27.5,45.5)   # on plot tile 27,45: 1.0 from the sign centre
const FAR_SPOT:=Vector2(39.5,33.5)    # player spawn: far from the sign and the plot
const PROTECTED_MSG:="這裡是水域或公共通道，請換個位置"
const VIEW_KEYS:=["active","available","best","blocked_cells","can_finish","can_start","categories","cooldown","full","full_goal","joined","joined_count","kinds","last","max_players","participants","pieces","pieces_count","place_reach","placed","plot_cells","plot_rect","requirements","round","rounds","seconds_left","shown","sign","sign_reach","theme","theme_blurb","theme_met","theme_name","tickets","unlocked"]
const PUBLIC_KEYS:=["active","ends","full","full_goal","last","participants","pieces","pieces_count","ready","requirements","round","seconds_left","started","theme","theme_met","theme_name"]
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
	print("SHOWCASE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

static func temp_path(tag:String)->String:
	return OS.get_environment("TEMP").path_join("showcase-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])

static func pl(w,token:String)->Dictionary:
	var p:Dictionary=w.state.players[token]
	return p

static func msg(r:Dictionary)->String:
	return str(r.get("message",""))

static func stand(w,token:String,at:Vector2)->void:
	var p:Dictionary=pl(w,token)
	p.x=at.x
	p.y=at.y

static func show_of(w)->Dictionary:
	var r:Variant=w.state.get("showcase")
	if r is Dictionary:
		var copy:Dictionary=r
		return copy
	return {}

static func entry_of(w,token:String)->Dictionary:
	var e:Variant=show_of(w).get("participants",{}).get(token)
	if e is Dictionary:
		var copy:Dictionary=e
		return copy
	return {}

static func record_of(w,token:String)->Dictionary:
	var r:Variant=pl(w,token).get("showcase")
	if r is Dictionary:
		var copy:Dictionary=r
		return copy
	return {}

static func view(w,token:String)->Dictionary:
	var v:Dictionary=w.showcase_view(token)
	return v

static func round_id(w)->int:
	return int(show_of(w).get("round",0))

## Recursively canonicalizes JSON-ish data: sorted String keys, whole floats as ints.
static func canon(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=[]
		for k in value:keys.append(str(k))
		keys.sort()
		var out:={}
		for k:String in keys:
			var source:Variant=value[k] if value.has(k) else value[StringName(k)]
			out[k]=canon(source)
		return out
	if value is Array:
		var list:=[]
		for item in value:list.append(canon(item))
		return list
	if value is float and is_finite(value) and floorf(value)==value:return int(value)
	return value

static func same(a:Variant,b:Variant)->bool:
	return var_to_bytes(canon(a))==var_to_bytes(canon(b))

## The player record minus request receipts and the activity record itself.
static func person_core(w,token:String)->Dictionary:
	var p:Dictionary=pl(w,token).duplicate(true)
	for field in ["receipts","showcase"]:p.erase(field)
	return p

static func cores(w,tokens:Array)->Dictionary:
	var out:={}
	for token:String in tokens:out[token]=person_core(w,token)
	return out

func act(w,token:String,action:String,cell:Vector2i,extra:String="",request:String="")->Dictionary:
	serial+=1
	var id:String=request if not request.is_empty() else "showcase-req-%d"%serial
	var r:Dictionary=w.act(token,id,action,cell,extra)
	return r

func ok(w,token:String,action:String,cell:Vector2i,extra:String,label:String)->Dictionary:
	var r:=act(w,token,action,cell,extra)
	expect(bool(r.get("ok",false)),label+" ("+msg(r)+")")
	return r

## Stands on `cell` and places `kind` there with the current round id.
func place(w,token:String,cell:Vector2i,kind:String,label:String)->Dictionary:
	stand(w,token,Vector2(cell)+HALF)
	return ok(w,token,"showcase_place",cell,"%d|%s"%[round_id(w),kind],label)

func write_fixture(path:String,data:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

## A rejected action leaves the whole world state byte-identical.
func expect_rejected(w,token:String,action:String,cell:Vector2i,extra:String,label:String,expected:String="")->void:
	var before:PackedByteArray=var_to_bytes(w.state)
	var had_root:bool=w.state.has("showcase")
	var had_record:bool=pl(w,token).has("showcase")
	var r:Dictionary=act(w,token,action,cell,extra)
	expect(not bool(r.get("ok",true)),label+": rejected")
	expect(not msg(r).is_empty(),label+": rejection explains itself ("+msg(r)+")")
	if not expected.is_empty():expect(msg(r)==expected,label+": message is '%s' (got '%s')"%[expected,msg(r)])
	expect(var_to_bytes(w.state)==before,label+": world state byte-identical")
	expect(w.state.has("showcase")==had_root and pl(w,token).has("showcase")==had_record,label+": no showcase field invented")

## A picnic-done world (PRESET) at START with every player standing on plot tile 27,45.
func make_world(tokens:Array,picnic:bool=true)->World:
	var w:=World.new()
	for token:String in tokens:w.add_player(token,token.left(6))
	w.state.picnic=picnic
	w.state.time=START
	for token:String in tokens:
		stand(w,token,HOME_SPOT)
		var inv:Dictionary=pl(w,token).inventory
		for item in ["carp","radish","wood"]:inv[item]=int(inv.get(item,0))+3
	return w

## A kind of `category`, rotating through that category's kinds by `index`.
static func kind_for(category:String,index:int)->String:
	var list:=[]
	for kind:String in Show.KIND_ORDER:
		if Show.category_of(kind)==category:list.append(kind)
	return str(list[index%list.size()])

## Places `counts` {category:n} on free plot cells (row-major) by `token`.
func fill(w,token:String,counts:Dictionary,label:String)->void:
	var cells:=[]
	for cell:Vector2i in Show.plot_cells():
		if not show_of(w).get("pieces",{}).has(Show.cell_key(cell)):cells.append(cell)
	var i:=0
	for category:String in Show.CATEGORIES:
		for n in range(int(counts.get(category,0))):
			place(w,token,cells[i],kind_for(category,n),"%s: %s #%d"%[label,category,n])
			i+=1

func _initialize()->void:
	run.call_deferred()

func run()->void:
	test_constants()
	test_site()
	if failures>0:
		finish()
		return
	test_locked()
	test_gates()
	test_solo_round()
	test_full_bonus()
	test_cooperation_and_cap()
	test_timeout_and_payment()
	test_rotation_and_clearing()
	test_disconnect_and_travel()
	test_replay()
	test_save_reload_and_schema()
	await test_snapshot_privacy()
	finish()

# 1. Constants, kinds, themes and the deterministic rotation.
func test_constants()->void:
	expect(Show.ACTIONS==["showcase_start","showcase_join","showcase_leave","showcase_place","showcase_remove","showcase_finish"],"Six showcase actions")
	expect(is_equal_approx(Show.DURATION,600.0) and is_equal_approx(Show.COOLDOWN,60.0) and Show.MAX_PLAYERS==8 and Show.MAX_ENTRIES==32 and is_equal_approx(Show.SIGN_REACH,3.2) and is_equal_approx(Show.PLACE_REACH,1.6) and Show.FULL_GOAL==16 and Show.MAX_BONUS==2,"600 s, cooldown 60 s, 8 players, 32 entries, sign reach 3.2, place reach 1.6, full goal 16")
	expect(Show.PLOT==Rect2i(27,44,6,4) and Show.SIGN==Vector2i(26,45),"Plot x27..32 y44..47, sign 26,45")
	expect(Show.plot_cells().size()==24 and Show.cells().size()==25 and Show.cells()[0]==Show.SIGN,"24 plot cells, 25 cells with the sign first")
	expect(Show.CATEGORIES==["flower","seat","light"] and Show.KIND_ORDER.size()==8 and Show.KINDS.size()==8,"Three categories, eight kinds")
	var per:={}
	for kind:String in Show.KIND_ORDER:
		expect(Show.KINDS.has(kind) and Show.category_of(kind) in Show.CATEGORIES and not Show.kind_name(kind).is_empty(),"%s has a name and a known category"%kind)
		per[Show.category_of(kind)]=int(per.get(Show.category_of(kind),0))+1
	for category:String in Show.CATEGORIES:
		expect(int(per.get(category,0))>=2,"Category %s has at least two kinds"%category)
		expect(not str(Show.CATEGORY_NAMES.get(category,"")).is_empty(),"Category %s has a name"%category)
	expect(Show.THEME_ORDER.size()==4 and Show.THEMES.size()==4,"Four themes")
	var names:={}
	for theme:String in Show.THEME_ORDER:
		var need:Dictionary=Show.THEMES[theme].need
		var total:=0
		for category:String in Show.CATEGORIES:
			expect(int(need.get(category,0))>=1,"%s needs at least one %s"%[theme,category])
			total+=int(need[category])
		expect(need.size()==3 and total<=Show.FULL_GOAL and total<=24,"%s needs %d pieces (fits the plot, below the full goal)"%[theme,total])
		expect(not Show.theme_name(theme).is_empty() and not str(Show.THEMES[theme].blurb).is_empty(),"%s has a name and a blurb"%theme)
		names[Show.theme_name(theme)]=true
	expect(names.size()==4,"Four distinct theme names")
	expect(Show.theme_of(0)=="" and Show.theme_of(-3)=="","No theme before round 1")
	for r in range(1,13):
		expect(Show.theme_of(r)==Show.THEME_ORDER[(r-1)%4],"Round %d theme %s"%[r,Show.theme_of(r)])
	expect(Show.theme_of(1)=="garden_tea" and Show.theme_of(2)=="sea_breeze" and Show.theme_of(3)=="warm_night" and Show.theme_of(4)=="harvest_corner" and Show.theme_of(5)=="garden_tea","Rotation garden_tea, sea_breeze, warm_night, harvest_corner")
	expect(Show.requirement_text("garden_tea")=="花草 4、座位 3、燈飾 1","Requirement text (%s)"%Show.requirement_text("garden_tea"))
	for row:Array in [[false,false,1],[true,false,2],[false,true,2],[true,true,3]]:
		expect(Show.tickets_for(row[0],row[1])==row[2],"tickets_for(met=%s, full=%s)==%d"%row)
	var other:=Meet.ACTIONS+Harvest.ACTIONS+Market.ACTIONS+["fish_start","fish_catch","build","remove","emote"]
	for action:String in Show.ACTIONS:
		expect(not action in other,"%s does not collide with an existing action"%action)
	# Display helpers.
	var pieces:={"27,44":{"kind":"flower_pot","by":"x"},"28,44":{"kind":"bench","by":"x"},"29,44":{"kind":"lantern","by":"y"}}
	expect(same(Show.category_counts(pieces),{"flower":1,"seat":1,"light":1}),"category_counts")
	expect(not Show.theme_met("garden_tea",pieces) and not Show.theme_met("",pieces) and not Show.full_display(pieces),"Three pieces: theme unmet, not full")
	expect(Show.cell_key(Vector2i(27,44))=="27,44","cell_key")

## Every fixed home landmark the activity cells must neither stand on nor touch.
static func home_landmarks()->Dictionary:
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
	for index in range(Harvest.CELLS.size()):marks["harvest relay cell %d"%index]=Harvest.CELLS[index]
	marks["fishing meet sign"]=Meet.SIGN
	for cell:Vector2i in Meet.SHORE:marks["fishing meet shore "+str(cell)]=cell
	for cell:Vector2i in Meet.water_cells():marks["fishing meet water "+str(cell)]=cell
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
	marks["pump plot 53,36 (preview fixtures)"]=Vector2i(53,36)
	marks["station plot 53,33 (queue session tests)"]=Vector2i(53,33)
	for y in range(24,29):
		for x in [52,53]:marks["industry plot %d,%d"%[x,y]]=Vector2i(x,y)
	return marks

## Build plots players and existing tests commonly use next to the spawn.
const BUILD_PLOTS:=[Rect2i(41,34,3,4),Rect2i(34,33,4,5),Rect2i(46,22,6,8)]

# 2. Site: terrain of every cell, adjacency, reachability, reservation, pause.
func test_site()->void:
	var plain:=World.new()
	var busy:=World.new()
	# PRESET: a mid-game home (bridge, picnic, festival story open).
	busy.state.board=true
	busy.state.picnic=true
	busy.state.festival_story_open=true
	var marks:=home_landmarks()
	for cell:Vector2i in Show.cells():
		var what:="sign" if cell==Show.SIGN else "plot tile"
		for w in [plain,busy]:
			expect(w.is_land(cell) and not w.water(cell),"%s %s is land, not water"%[what,str(cell)])
			expect(w.resource(cell)=="","%s %s has no resource"%[what,str(cell)])
		expect(World.land(cell) and World.base_resource(cell)=="","%s %s: island land with no fixed tree/rock/grass"%[what,str(cell)])
		expect(cell.x!=55 and cell.x!=56,"%s %s is not in the river"%[what,str(cell)])
		expect(Vector2(World.SPAWN).distance_to(Vector2(cell)+HALF)>8.0,"%s %s is more than 8 tiles from the spawn"%[what,str(cell)])
		for mark:String in marks:
			var at:Vector2i=marks[mark]
			expect(maxi(absi(cell.x-at.x),absi(cell.y-at.y))>=2,"%s %s is not on or touching %s %s"%[what,str(cell),mark,str(at)])
		for rect:Rect2i in BUILD_PLOTS:
			expect(not rect.grow(1).has_point(cell),"%s %s does not touch build plot %s"%[what,str(cell),str(rect)])
		expect(not plain.protected(cell) and not plain.blocked(cell),"%s %s free before the picnic"%[what,str(cell)])
		expect(busy.protected(cell),"%s %s reserved (protected) after the picnic"%[what,str(cell)])
		expect(Show.reserved(busy.state,cell) and not Show.reserved(plain.state,cell),"%s %s reserved() only after the picnic"%[what,str(cell)])
	expect(busy.blocked(Show.SIGN) and Show.blocks(busy.state,Show.SIGN),"Sign blocks movement after the picnic")
	for cell:Vector2i in Show.plot_cells():
		expect(not busy.blocked(cell) and busy.can_stand(Vector2(cell)+HALF) and plain.can_stand(Vector2(cell)+HALF),"Plot tile %s stays walkable before and after the picnic"%str(cell))
		expect(not Show.blocks(busy.state,cell),"Plot tile %s does not block"%str(cell))
	# Cells around the activity are not reserved.
	var ring:=0
	for y in range(Show.PLOT.position.y-1,Show.PLOT.end.y+1):
		for x in range(Show.SIGN.x-1,Show.PLOT.end.x+1):
			var p:=Vector2i(x,y)
			if p in Show.cells():continue
			ring+=1
			expect(not Show.reserved(busy.state,p),"Neighbour %s not reserved"%str(p))
	expect(ring>=20,"Checked the surrounding ring (%d cells)"%ring)
	expect(not Show.available(plain.state) and Show.available(busy.state) and World.showcase_available(busy.state),"available only after the picnic (World.showcase_available wraps)")
	# The sign is reachable from a standable cell; the plot is reachable on foot from the spawn.
	var sign_spot:=false
	for y in range(Show.SIGN.y-3,Show.SIGN.y+4):
		for x in range(Show.SIGN.x-3,Show.SIGN.x+4):
			var c:=Vector2(x,y)+HALF
			if c.distance_to(Vector2(Show.SIGN)+HALF)<=Show.SIGN_REACH and busy.can_stand(c):sign_spot=true
	expect(sign_spot,"A standable spot within SIGN_REACH of the sign")
	expect(HOME_SPOT.distance_to(Vector2(Show.SIGN)+HALF)<=Show.SIGN_REACH and busy.can_stand(HOME_SPOT),"HOME_SPOT stands on the plot and reaches the sign")
	var seen:={Vector2i(World.SPAWN):true}
	var queue:=[Vector2i(World.SPAWN)]
	var reached:={}
	while not queue.is_empty():
		var at:Vector2i=queue.pop_front()
		if Show.in_plot(at):reached[at]=true
		for d:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var n:=at+d
			if seen.has(n) or n.x<0 or n.y<0 or n.x>=World.SIZE.x or n.y>=World.SIZE.y:continue
			seen[n]=true
			if busy.can_stand(Vector2(n)+HALF):queue.append(n)
	expect(reached.size()==24,"Every plot tile is reachable on foot from the spawn after the picnic (%d/24)"%reached.size())
	print("SHOWCASE_SITE sign=%s plot=%s reachable=%d"%[str(Show.SIGN),str(Show.PLOT),reached.size()])
	# Before the picnic every cell is ordinary buildable land (floor on all 25).
	var bw:=make_world(["bui"],false)
	pl(bw,"bui").inventory.wood=200
	for cell:Vector2i in Show.cells():
		stand(bw,"bui",Vector2(cell)+Vector2(-0.5,0.5) if cell!=Show.SIGN else Vector2(cell)+Vector2(1.5,0.5))
		var r:=act(bw,"bui","build",cell,"floor")
		expect(bool(r.ok),"Before the picnic %s is buildable land (%s)"%[str(cell),msg(r)])
	# After the picnic building, tilling and tree planting are refused on every reserved cell.
	var rw:=make_world(["bui"])
	pl(rw,"bui").inventory.wood=200
	for cell:Vector2i in Show.cells():
		stand(rw,"bui",Vector2(cell)+Vector2(-0.5,0.5) if cell!=Show.SIGN else Vector2(cell)+Vector2(1.5,0.5))
		expect_rejected(rw,"bui","build",cell,"floor","Build floor on reserved %s"%str(cell),PROTECTED_MSG)
	stand(rw,"bui",HOME_SPOT)
	for action:String in ["hoe","plant_tree"]:
		expect_rejected(rw,"bui",action,Vector2i(28,45),"","%s on a reserved plot tile"%action,PROTECTED_MSG)
	stand(rw,"bui",Vector2(29.5,48.5))
	var beside:=act(rw,"bui","build",Vector2i(30,48),"floor")
	expect(bool(beside.ok),"Building right below the plot (30,48) still works (%s)"%msg(beside))
	# Occupied plot tile (old save / built before the picnic): activity paused, save stays valid.
	var p:=make_world(["bui","oth"])
	var tile:=Vector2i(30,46)
	p.state.picnic=false
	stand(p,"bui",Vector2(tile)+Vector2(-0.5,0.5))
	ok(p,"bui","build",tile,"floor","Build a floor on the plot before the picnic")
	p.state.picnic=true
	expect(not Show.available(p.state) and not Show.reserved(p.state,tile) and Show.reserved(p.state,Vector2i(29,46)),"Occupied tile: unavailable, that tile not reserved, others still reserved")
	expect(Show.blocked_cells(p.state)==[tile] and view(p,"bui").blocked_cells==[tile],"blocked_cells lists exactly the occupied tile")
	expect(not p.protected(tile) and p.protected(Vector2i(29,46)),"World.protected follows the reservation")
	expect_rejected(p,"bui","showcase_start",Show.SIGN,"0","Start while a plot tile is occupied",Show.UNAVAILABLE)
	expect(not view(p,"bui").available and not view(p,"bui").can_start,"View reports unavailable")
	var floor_path:=temp_path("floor")
	_cleanup.append(floor_path)
	p.save_path=floor_path
	expect(p.save(),"Save the world with a floor on the plot")
	var kept:=World.new()
	expect(kept.load_world(floor_path),"A save with a floor on the plot loads")
	expect(kept.state.ground.has(World.key(tile)) and not Show.available(kept.state),"Floor kept and the activity stays paused after reload")
	p.save_path=""
	stand(p,"bui",Vector2(tile)+Vector2(-0.5,0.5))
	ok(p,"bui","remove",tile,"","Owner removes the floor from the plot")
	expect(Show.available(p.state) and p.protected(tile),"Cleared: activity available and the tile reserved again")
	stand(p,"bui",HOME_SPOT)
	ok(p,"bui","showcase_start",Show.SIGN,"0","Start after clearing the plot")
	place(p,"bui",Vector2i(27,44),"lantern","Place before the pause")
	# Occupied sign mid-round: everything but leave refused.
	p.state.objects[World.key(Show.SIGN)]={"type":"lamp","owner":"bui","items":{}}
	expect(not Show.available(p.state) and not Show.reserved(p.state,Show.SIGN) and not Show.blocks(p.state,Show.SIGN),"Occupied sign: unavailable and no longer reserved")
	stand(p,"oth",HOME_SPOT)
	expect_rejected(p,"oth","showcase_join",Show.SIGN,"1","Join while paused",Show.UNAVAILABLE)
	stand(p,"bui",Vector2(28.5,44.5))
	expect_rejected(p,"bui","showcase_place",Vector2i(28,44),"1|stool","Place while paused",Show.UNAVAILABLE)
	expect_rejected(p,"bui","showcase_remove",Vector2i(27,44),"1","Remove while paused",Show.UNAVAILABLE)
	expect_rejected(p,"bui","showcase_finish",Show.SIGN,"1","Finish while paused",Show.UNAVAILABLE)
	ok(p,"bui","showcase_leave",Show.SIGN,"","Leave while paused")
	expect(entry_of(p,"bui").joined==false and show_of(p).pieces.has("27,44"),"Leaving while paused keeps the piece")

# 3. Picnic gate: every action refused, nothing written.
func test_locked()->void:
	var w:=make_world(["lin"],false)
	var before:=person_core(w,"lin")
	for pair:Array in [["showcase_start",Show.SIGN,"0"],["showcase_join",Show.SIGN,"0"],["showcase_leave",Show.SIGN,""],
			["showcase_place",Vector2i(27,45),"0|lantern"],["showcase_remove",Vector2i(27,45),"0"],["showcase_finish",Show.SIGN,"0"]]:
		expect_rejected(w,"lin",str(pair[0]),pair[1],str(pair[2]),"Before picnic "+str(pair[0]),Show.LOCKED)
	expect(not w.state.has("showcase") and not pl(w,"lin").has("showcase"),"No showcase fields written before the picnic")
	expect(same(person_core(w,"lin"),before),"Player record untouched before the picnic")
	var v:=view(w,"lin")
	expect(v.unlocked==false and v.available==false and v.can_start==false and v.can_finish==false and v.round==0,"View says locked")
	w.step(0.5,true)
	expect(not w.state.has("showcase"),"Step writes nothing before the picnic")

# 4. Region, sign, reach, extra and stale-round gates; place/remove/finish gates; ENDING.
func test_gates()->void:
	var w:=make_world(["gus","hal"])
	var S:=Show.SIGN
	var p:Dictionary=pl(w,"gus")
	p.region=World.REGIONS.LANYANG
	for pair:Array in [["showcase_start",S,"0"],["showcase_join",S,"0"],["showcase_leave",S,""],
			["showcase_place",Vector2i(27,45),"0|lantern"],["showcase_remove",Vector2i(27,45),"0"],["showcase_finish",S,"0"]]:
		expect_rejected(w,"gus",str(pair[0]),pair[1],str(pair[2]),"Wrong region "+str(pair[0]),Show.WRONG_REGION)
	p.region=World.REGIONS.HOME
	expect_rejected(w,"gus","showcase_start",Vector2i(27,45),"0","Start at a plot tile",Show.WRONG_SIGN)
	expect_rejected(w,"gus","showcase_start",Meet.SIGN,"0","Start at the fishing meet sign",Show.WRONG_SIGN)
	expect_rejected(w,"gus","showcase_start",S,"1","Stale round id 1 before any round",Show.STALE)
	expect_rejected(w,"gus","showcase_start",S,"","Empty round id",Show.STALE)
	expect_rejected(w,"gus","showcase_start",S,"00","Non-canonical round id",Show.STALE)
	expect_rejected(w,"gus","showcase_join",S,"0","Join with no round",Show.NOT_ACTIVE)
	expect_rejected(w,"gus","showcase_leave",S,"","Leave with no round",Show.NOT_ACTIVE)
	expect_rejected(w,"gus","showcase_leave",S,"x","Leave with an extra",Show.BAD_EXTRA)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"0|lantern","Place with no round",Show.NOT_ACTIVE)
	expect_rejected(w,"gus","showcase_remove",Vector2i(27,45),"0","Remove with no round",Show.NOT_ACTIVE)
	expect_rejected(w,"gus","showcase_finish",S,"0","Finish with no round",Show.NOT_ACTIVE)
	stand(w,"gus",FAR_SPOT)
	expect_rejected(w,"gus","showcase_start",S,"0","Start from the spawn point",Show.TOO_FAR_SIGN)
	stand(w,"gus",Vector2(30.5,45.5))
	expect_rejected(w,"gus","showcase_start",S,"0","Start from 4 tiles east of the sign",Show.TOO_FAR_SIGN)
	expect(not w.state.has("showcase"),"Rejected starts write no round")
	stand(w,"gus",HOME_SPOT)
	var before:=cores(w,["gus","hal"])
	var r:=ok(w,"gus","showcase_start",S,"0","Start round 1 at the sign")
	expect(msg(r)=="第 1 輪家園布置題開始！本輪主題「花園茶會」：花草 4、座位 3、燈飾 1。10 分鐘內在展示地塊擺好布置道具；道具只在活動裡使用，背包不會變動。","Start message names round, theme, needs and the backpack promise (%s)"%msg(r))
	var sh:=show_of(w)
	expect(int(sh.round)==1 and sh.active==true and sh.theme=="garden_tea" and is_equal_approx(float(sh.started),START) and is_equal_approx(float(sh.ends),START+600.0),"Round 1 active with theme garden_tea, ends = started + 600")
	expect(same(sh.participants,{"gus":{"placed":0,"joined":true}}) and (sh.pieces as Dictionary).is_empty() and (sh.last as Dictionary).is_empty(),"Starter auto-joins; empty plot")
	expect(not pl(w,"gus").has("showcase"),"No personal record before settlement")
	expect_rejected(w,"gus","showcase_start",S,"0","Stale double start with round 0",Show.ALREADY_ACTIVE)
	expect_rejected(w,"hal","showcase_start",S,"1","Second start while active",Show.ALREADY_ACTIVE)
	expect_rejected(w,"hal","showcase_join",S,"0","Join with a stale round id",Show.STALE)
	expect_rejected(w,"hal","showcase_join",S,"","Join with an empty round id",Show.STALE)
	expect_rejected(w,"hal","showcase_leave",S,"","Leave before joining",Show.NOT_JOINED)
	expect_rejected(w,"hal","showcase_place",Vector2i(27,45),"1|lantern","Place before joining",Show.NOT_JOINED)
	expect_rejected(w,"hal","showcase_finish",S,"1","Finish before joining",Show.NOT_JOINED)
	stand(w,"hal",FAR_SPOT)
	expect_rejected(w,"hal","showcase_join",S,"1","Join from too far",Show.TOO_FAR_SIGN)
	expect_rejected(w,"hal","showcase_join",Vector2i(27,45),"1","Join at a plot tile",Show.WRONG_SIGN)
	expect_rejected(w,"gus","showcase_join",S,"1","Starter joins again",Show.ALREADY_JOINED)
	# Place gates.
	for bad:String in ["","1","1|","|lantern","1|lantern|x","lantern|1"]:
		var expected:=Show.BAD_EXTRA if bad.split("|").size()!=2 else (Show.STALE if bad.split("|")[0]!="1" else Show.UNKNOWN_KIND)
		expect_rejected(w,"gus","showcase_place",Vector2i(27,45),bad,"Place with extra '%s'"%bad,expected)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"0|lantern","Place with a stale round id",Show.STALE)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"2|lantern","Place with a future round id",Show.STALE)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"1|bonfire","Place an unknown kind",Show.UNKNOWN_KIND)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"1|wood","An inventory item is not a prop",Show.UNKNOWN_KIND)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"1|LANTERN","Kinds are case sensitive",Show.UNKNOWN_KIND)
	for outside:Vector2i in [S,Vector2i(26,44),Vector2i(33,45),Vector2i(27,43),Vector2i(27,48),Vector2i(26,46)]:
		expect_rejected(w,"gus","showcase_place",outside,"1|lantern","Place outside the plot at %s"%str(outside),Show.OUTSIDE_PLOT)
	stand(w,"gus",Vector2(27.5,45.5))
	expect_rejected(w,"gus","showcase_place",Vector2i(29,45),"1|lantern","Place two tiles away",Show.TOO_FAR_TILE)
	expect_rejected(w,"gus","showcase_place",Vector2i(32,47),"1|lantern","Place across the plot",Show.TOO_FAR_TILE)
	expect(show_of(w).pieces.is_empty(),"No piece after the refusals")
	# Reach: standing on, beside and diagonal to the tile all work.
	ok(w,"gus","showcase_place",Vector2i(27,45),"1|lantern","Place on the tile you stand on")
	ok(w,"gus","showcase_place",Vector2i(28,45),"1|stool","Place on the tile beside you")
	ok(w,"gus","showcase_place",Vector2i(28,46),"1|fern","Place diagonally")
	expect(same(show_of(w).pieces,{"27,45":{"kind":"lantern","by":"gus"},"28,45":{"kind":"stool","by":"gus"},"28,46":{"kind":"fern","by":"gus"}}),"Three pieces recorded with kind and placer")
	expect(int(entry_of(w,"gus").placed)==3 and view(w,"gus").shown==3 and view(w,"gus").placed==3,"placed 3, shown 3")
	expect_rejected(w,"gus","showcase_place",Vector2i(27,45),"1|bench","Place on an occupied tile",Show.TILE_TAKEN)
	# Remove gates.
	expect_rejected(w,"gus","showcase_remove",Vector2i(27,44),"1","Remove an empty tile",Show.NO_PIECE)
	expect_rejected(w,"gus","showcase_remove",Vector2i(27,45),"0","Remove with a stale round id",Show.STALE)
	expect_rejected(w,"gus","showcase_remove",Vector2i(27,45),"","Remove with an empty round id",Show.STALE)
	expect_rejected(w,"gus","showcase_remove",S,"1","Remove at the sign",Show.OUTSIDE_PLOT)
	expect_rejected(w,"gus","showcase_remove",Vector2i(30,45),"1","Remove too far",Show.TOO_FAR_TILE)
	expect_rejected(w,"hal","showcase_remove",Vector2i(27,45),"1","Remove before joining",Show.NOT_JOINED)
	# Finish gates.
	expect_rejected(w,"gus","showcase_finish",S,"1","Finish with the theme unmet",Show.NOT_MET)
	expect_rejected(w,"gus","showcase_finish",S,"0","Finish with a stale round id",Show.STALE)
	expect(view(w,"gus").can_finish==false,"View: cannot finish yet")
	# The world never sees the props: no object, ground or inventory change.
	stand(w,"hal",HOME_SPOT)
	expect(not w.state.objects.has("27,45") and not w.state.ground.has("27,45") and same(cores(w,["gus","hal"]),before),"Props never touch world layers or players")
	expect(not w.blocked(Vector2i(27,45)) and w.can_stand(Vector2(27.5,45.5)),"A tile with a prop stays walkable")
	# Time over but not yet stepped.
	w.state.time=START+600.0
	stand(w,"hal",HOME_SPOT)
	expect_rejected(w,"hal","showcase_start",S,"1","Start after the deadline before settlement",Show.ENDING)
	expect_rejected(w,"hal","showcase_join",S,"1","Join after the deadline",Show.ENDING)
	expect_rejected(w,"gus","showcase_place",Vector2i(27,44),"1|lantern","Place after the deadline",Show.ENDING)
	expect_rejected(w,"gus","showcase_remove",Vector2i(27,45),"1","Remove after the deadline",Show.ENDING)
	expect_rejected(w,"gus","showcase_finish",S,"1","Finish after the deadline",Show.ENDING)
	w.step(0.5,true)
	expect(show_of(w).active==false and same(record_of(w,"gus"),{"tickets":1,"rounds":1,"best":3,"paid_round":1}),"Settled by time: gus (theme unmet) gets exactly one ticket")
	expect(same(cores(w,["gus","hal"]),before),"Player records identical after the timeout")

# 5. A full solo round meeting the theme and finishing early.
func test_solo_round()->void:
	var w:=make_world(["sol","obs"])
	stand(w,"obs",FAR_SPOT)
	var before:=cores(w,["sol","obs"])
	ok(w,"sol","showcase_start",Show.SIGN,"0","Solo start")
	var need:Dictionary=Show.THEMES.garden_tea.need
	var placed:=0
	var cells:=Show.plot_cells()
	for category:String in Show.CATEGORIES:
		for n in range(int(need[category])):
			var r:=place(w,"sol",cells[placed],kind_for(category,n),"Solo %s #%d"%[category,n])
			placed+=1
			var counts:=Show.category_counts(show_of(w).pieces)
			expect(msg(r).begins_with("擺上%s。「花園茶會」進度：花草 %d/4、座位 %d/3、燈飾 %d/1。"%[Show.kind_name(kind_for(category,n)),int(counts.flower),int(counts.seat),int(counts.light)]),"Place message %d (%s)"%[placed,msg(r)])
			stand(w,"sol",HOME_SPOT) # positions are compared too: walk back first
			expect(same(cores(w,["sol","obs"]),before),"Whole player records unchanged after piece %d"%placed)
			if placed<8:
				expect(view(w,"sol").theme_met==false and view(w,"sol").can_finish==false,"Theme not met after %d"%placed)
				expect_rejected(w,"sol","showcase_finish",Show.SIGN,"1","Finish too early after %d"%placed,Show.NOT_MET)
			else:
				expect(msg(r).contains("主題完成了"),"Last piece announces the theme is met")
	var v:=view(w,"sol")
	expect(v.theme_met==true and v.can_finish==true and v.full==false and v.pieces_count==8,"Theme met with 8 pieces; finish available; not full")
	for row:Dictionary in v.requirements:expect(row.met==true and int(row.have)==int(row.need),"Requirement %s met exactly"%row.category)
	expect(show_of(w).active==true,"Meeting the theme does not settle automatically")
	expect_rejected(w,"obs","showcase_finish",Show.SIGN,"1","A bystander cannot finish",Show.NOT_JOINED)
	stand(w,"sol",FAR_SPOT)
	var r:=ok(w,"sol","showcase_finish",Vector2i(0,0),"1","Finish early from anywhere at home")
	expect(msg(r)=="「花園茶會」布置完成！地塊上共 8 件，參加者各得 2 張紀念票。展示會保留到冷卻結束。","Finish message (%s)"%msg(r))
	var sh:=show_of(w)
	var now:=float(w.state.time)
	expect(sh.active==false and same(sh.last,{"round":1,"theme":"garden_tea","pieces":8,"met":true,"full":false,"players":1,"tickets":2,"reason":"goal","finished":now}),"Last result summary %s"%str(sh.last))
	expect(is_equal_approx(float(sh.ready),now+60.0),"Cooldown until finished + 60")
	expect(same(record_of(w,"sol"),{"tickets":2,"rounds":1,"best":8,"paid_round":1}),"Solo player paid 2 tickets once")
	expect(not pl(w,"obs").has("showcase"),"A bystander gets nothing")
	stand(w,"sol",HOME_SPOT)
	expect(same(cores(w,["sol","obs"]),before),"Every player record identical after the round")
	expect((sh.pieces as Dictionary).size()==8 and view(w,"obs").pieces_count==8,"The finished display stays visible")
	expect_rejected(w,"sol","showcase_finish",Show.SIGN,"1","Finish twice",Show.NOT_ACTIVE)
	stand(w,"sol",HOME_SPOT)
	expect_rejected(w,"sol","showcase_place",Vector2i(32,47),"1|lantern","Place after settlement",Show.NOT_ACTIVE)
	expect_rejected(w,"sol","showcase_leave",Show.SIGN,"","Leave after settlement",Show.NOT_ACTIVE)
	# Steps after settlement pay nothing more and keep the display during the cooldown.
	var rec:=record_of(w,"sol").duplicate(true)
	var snap:=var_to_bytes(show_of(w))
	w.step(0.5,true)
	w.step(0.5,true)
	expect(same(record_of(w,"sol"),rec) and var_to_bytes(show_of(w))==snap,"Steps during the cooldown change nothing")
	# Cooldown.
	var finished:=float(show_of(w).last.finished)
	w.state.time=finished+30.0
	expect_rejected(w,"sol","showcase_start",Show.SIGN,"1","Start during the cooldown",Show.COOLDOWN_MSG%30)
	expect(view(w,"sol").can_start==false and is_equal_approx(float(view(w,"sol").cooldown),30.0),"View shows 30 s cooldown")
	w.state.time=finished+59.0
	w.step(0.5,true)
	expect((show_of(w).pieces as Dictionary).size()==8,"Display still up just before the cooldown ends")
	w.state.time=finished+60.0
	expect(w.step(0.5,true) or true,"Step at the end of the cooldown")
	expect((show_of(w).pieces as Dictionary).is_empty() and same(show_of(w).last.pieces,8),"Pieces cleared after the cooldown; last keeps the count")
	expect(same(record_of(w,"sol"),rec),"Clearing pays nothing")
	expect_rejected(w,"sol","showcase_start",Show.SIGN,"0","Stale round id after round 1",Show.STALE)
	expect(view(w,"sol").can_start==true,"Cooldown over")
	ok(w,"sol","showcase_start",Show.SIGN,"1","Round 2 starts with id 1")
	expect(int(show_of(w).round)==2 and show_of(w).theme=="sea_breeze" and same(show_of(w).participants,{"sol":{"placed":0,"joined":true}}) and (show_of(w).pieces as Dictionary).is_empty(),"Round 2: sea_breeze, fresh roster and plot")
	expect(int(show_of(w).last.round)==1 and int(show_of(w).last.pieces)==8,"Round 2 keeps round 1 as last result")
	expect(same(cores(w,["sol","obs"]),before),"Player records identical after round 2 starts")

# 6. Full-display bonus: met + full (3 tickets) and full but unmet (2 tickets).
func test_full_bonus()->void:
	var w:=make_world(["ful"])
	var before:=person_core(w,"ful")
	ok(w,"ful","showcase_start",Show.SIGN,"0","Full: start round 1")
	fill(w,"ful",{"flower":8,"seat":6,"light":2},"Full round 1")
	var v:=view(w,"ful")
	expect(v.pieces_count==16 and v.full==true and v.theme_met==true and v.full_goal==16,"16 pieces in three categories: full and met")
	ok(w,"ful","showcase_finish",Show.SIGN,"1","Full: finish")
	expect(int(show_of(w).last.tickets)==3 and show_of(w).last.full==true and same(record_of(w,"ful"),{"tickets":3,"rounds":1,"best":16,"paid_round":1}),"Met + full: 3 tickets")
	w.state.time=float(show_of(w).ready)
	stand(w,"ful",HOME_SPOT)
	ok(w,"ful","showcase_start",Show.SIGN,"1","Full: start round 2 (sea_breeze, display reset by start)")
	expect((show_of(w).pieces as Dictionary).is_empty(),"Starting round 2 cleared the old display")
	fill(w,"ful",{"flower":14,"seat":1,"light":1},"Full round 2")
	expect(view(w,"ful").full==true and view(w,"ful").theme_met==false,"16 pieces but only one seat: full, theme unmet")
	expect_rejected(w,"ful","showcase_finish",Show.SIGN,"2","Full but unmet cannot finish early",Show.NOT_MET)
	w.state.time=float(show_of(w).ends)
	w.step(0.5,true)
	expect(show_of(w).active==false and show_of(w).last.reason=="time" and int(show_of(w).last.tickets)==2 and show_of(w).last.met==false and show_of(w).last.full==true,"Full but unmet by time: 2 tickets")
	expect(same(record_of(w,"ful"),{"tickets":5,"rounds":2,"best":16,"paid_round":2}),"Records add up to 5 tickets over 2 rounds")
	# Fifteen pieces is not full; sixteen of one category is not full either.
	w.state.time=float(show_of(w).ready)
	stand(w,"ful",HOME_SPOT)
	ok(w,"ful","showcase_start",Show.SIGN,"2","Full: start round 3 (warm_night)")
	fill(w,"ful",{"flower":16},"Single-category 16")
	expect(view(w,"ful").pieces_count==16 and view(w,"ful").full==false,"16 flowers only: not full (needs all three categories)")
	stand(w,"ful",Vector2(27.5,44.5))
	ok(w,"ful","showcase_remove",Vector2i(27,44),"3","Remove one flower")
	place(w,"ful",Vector2i(27,44),"lantern","Add a lantern")
	stand(w,"ful",Vector2(28.5,44.5))
	ok(w,"ful","showcase_remove",Vector2i(28,44),"3","Remove another flower")
	expect(view(w,"ful").pieces_count==15 and view(w,"ful").full==false,"15 pieces: not full")
	place(w,"ful",Vector2i(28,44),"bench","Add a bench")
	expect(view(w,"ful").pieces_count==16 and view(w,"ful").full==true,"16 pieces with all three categories: full")
	stand(w,"ful",HOME_SPOT)
	expect(same(person_core(w,"ful"),before),"Whole player record unchanged across three rounds")

# 7. Cooperation: a teammate removes a piece, both contribute, either can finish. Cap of 8.
func test_cooperation_and_cap()->void:
	var w:=make_world(["ann","bob","cat"])
	var before:=cores(w,["ann","bob","cat"])
	ok(w,"ann","showcase_start",Show.SIGN,"0","ann starts")
	ok(w,"bob","showcase_join",Show.SIGN,"1","bob joins")
	var r:=place(w,"ann",Vector2i(27,44),"bench","ann places a bench")
	stand(w,"bob",Vector2(27.5,45.5))
	var rm:=ok(w,"bob","showcase_remove",Vector2i(27,44),"1","bob removes ann's bench (cooperative)")
	expect(msg(rm).begins_with("收起長木椅。"),"Remove message (%s)"%msg(rm))
	expect((show_of(w).pieces as Dictionary).is_empty() and int(entry_of(w,"ann").placed)==1 and view(w,"ann").shown==0,"ann placed 1, shows 0 after bob's removal")
	fill(w,"ann",{"flower":4},"ann flowers")
	fill(w,"bob",{"seat":3,"light":1},"bob seats and light")
	var va:=view(w,"ann")
	expect(va.shown==4 and va.placed==5 and view(w,"bob").shown==4 and view(w,"bob").placed==4,"Display counts: ann 4 (placed 5), bob 4")
	var people:Array=va.participants
	expect(people.size()==2 and people[0].name=="ann" and people[0].shown==4 and people[0].me==true and people[1].name=="bob" and people[1].me==false,"Participants list in token order with display counts")
	expect(va.theme_met==true and va.can_finish==true and view(w,"cat").can_finish==false,"Theme met together; cat (not joined) cannot finish")
	ok(w,"bob","showcase_finish",Show.SIGN,"1","bob finishes for the team")
	for t in ["ann","bob"]:
		expect(same(record_of(w,t),{"tickets":2,"rounds":1,"best":8,"paid_round":1}),"%s paid 2 tickets once"%t)
	expect(not pl(w,"cat").has("showcase"),"cat (never joined) gets nothing")
	for t in ["ann","bob"]:stand(w,t,HOME_SPOT)
	expect(same(cores(w,["ann","bob","cat"]),before),"Whole player records unchanged after the cooperative round")
	# Cap: 8 currently joined; the 9th is refused; leave frees a slot; rejoin keeps counts.
	var tokens:=[]
	for i in range(10):tokens.append("cap%d"%i)
	var c:=make_world(tokens)
	ok(c,"cap0","showcase_start",Show.SIGN,"0","cap0 starts")
	for i in range(1,8):ok(c,tokens[i],"showcase_join",Show.SIGN,"1","%s joins"%tokens[i])
	expect(view(c,"cap0").joined_count==8,"Eight joined")
	expect_rejected(c,"cap8","showcase_join",Show.SIGN,"1","9th joiner",Show.FULL%8)
	place(c,"cap1",Vector2i(30,45),"cushion","cap1 places")
	ok(c,"cap1","showcase_leave",Show.SIGN,"","cap1 leaves")
	expect(view(c,"cap1").joined==false and view(c,"cap1").shown==1 and (show_of(c).pieces as Dictionary).has("30,45"),"Leaver's piece stays on the plot and counts for them")
	stand(c,"cap1",Vector2(30.5,45.5))
	expect_rejected(c,"cap1","showcase_place",Vector2i(30,46),"1|cushion","Leaver cannot place",Show.NOT_JOINED)
	stand(c,"cap8",HOME_SPOT)
	ok(c,"cap8","showcase_join",Show.SIGN,"1","9th joins after a leave")
	stand(c,"cap1",HOME_SPOT)
	expect_rejected(c,"cap1","showcase_join",Show.SIGN,"1","Leaver cannot rejoin while 8 are in",Show.FULL%8)
	ok(c,"cap2","showcase_leave",Show.SIGN,"","cap2 leaves")
	ok(c,"cap1","showcase_join",Show.SIGN,"1","cap1 rejoins the same round")
	expect(int(entry_of(c,"cap1").placed)==1 and entry_of(c,"cap1").joined==true and show_of(c).participants.size()==9,"Rejoin reuses the entry (placed 1), roster 9")
	var v:=view(c,"cap1")
	var keys:Array=v.keys()
	keys.sort()
	expect(keys==VIEW_KEYS,"View has exactly the documented keys (%s)"%str(keys))
	expect(v.kinds.size()==8 and v.kinds[0].id=="flower_pot" and v.kinds[0].category=="flower" and v.kinds[0].category_name=="花草","View lists kinds in KIND_ORDER with categories")
	expect(v.categories.size()==3 and v.requirements.size()==3 and v.requirements[2].category=="light" and int(v.requirements[2].need)==1,"View lists categories and requirements")
	expect(v.plot_cells.size()==24 and v.plot_rect==Show.PLOT and v.sign==Show.SIGN and same(v.pieces,{"30,45":"cushion"}),"View carries the plot and the token-free pieces")
	var mine:=0
	for e:Dictionary in v.participants:
		if e.me:mine+=1
	expect(mine==1 and not JSON.stringify(v).contains("\"cap1\":") and not JSON.stringify(v).contains("\"by\""),"View marks me once, is not keyed by token and has no placer tokens")

# 8. Timeout settlement: zero-piece, leavers, rejoiners, offline and away players paid once.
func test_timeout_and_payment()->void:
	var tokens:=["ta","tb","tc","td","te"]
	var w:=make_world(tokens)
	var before:=cores(w,tokens)
	ok(w,"ta","showcase_start",Show.SIGN,"0","ta starts")
	for t in ["tb","tc","td","te"]:ok(w,t,"showcase_join",Show.SIGN,"1","%s joins"%t)
	place(w,"ta",Vector2i(27,44),"flower_pot","ta places")
	place(w,"tb",Vector2i(28,44),"lantern","tb places")
	ok(w,"tb","showcase_leave",Show.SIGN,"","tb leaves")
	ok(w,"tc","showcase_leave",Show.SIGN,"","tc leaves")
	stand(w,"tc",HOME_SPOT)
	ok(w,"tc","showcase_join",Show.SIGN,"1","tc rejoins")
	w.active_tokens.erase("td") # td goes offline mid-round
	pl(w,"te").region=World.REGIONS.LANYANG # te travels away mid-round
	w.state.time=float(show_of(w).ends)-0.5
	w.step(0.25,true)
	expect(show_of(w).active==true and entry_of(w,"td").joined==false and entry_of(w,"te").joined==false and entry_of(w,"tc").joined==true,"Still active just before the deadline; offline td and away te dropped by step")
	w.state.time=float(show_of(w).ends)
	w.step(0.25,true)
	var sh:=show_of(w)
	expect(sh.active==false and sh.last.reason=="time" and int(sh.last.pieces)==2 and sh.last.met==false and int(sh.last.tickets)==1 and int(sh.last.players)==5,"Timeout with the theme unmet: 1 ticket each, 5 players (%s)"%str(sh.last))
	for t:String in tokens:
		expect(same(record_of(w,t),{"tickets":1,"rounds":1,"best":2,"paid_round":1}),"%s paid exactly once (%s)"%[t,str(record_of(w,t))])
		expect(entry_of(w,t).joined==false,"%s is out after settlement"%t)
	expect(int(entry_of(w,"te").placed)==0 and int(record_of(w,"te").tickets)==1,"Zero-piece, away participant te still gets exactly 1 ticket")
	for t in ["ta","tb"]:stand(w,t,HOME_SPOT)
	pl(w,"te").region=World.REGIONS.HOME
	expect(same(cores(w,tokens),before),"Every participant's player record identical after the timeout")
	expect((sh.pieces as Dictionary).size()==2,"Display kept after the timeout")
	for i in range(3):w.step(0.5,true)
	for t:String in tokens:expect(int(record_of(w,t).tickets)==1 and int(record_of(w,t).rounds)==1,"%s not paid again by later steps"%t)
	# Re-settle guard: force the finished round active again past its end.
	(w.state.showcase as Dictionary).active=true
	w.step(0.5,true)
	for t:String in tokens:expect(int(record_of(w,t).tickets)==1 and int(record_of(w,t).paid_round)==1,"%s: paid_round blocks a re-settlement of round 1"%t)
	# Separate from the other activities' tickets.
	expect(not pl(w,"ta").has("fish_meet") and not pl(w,"ta").has("harvest_relay"),"Showcase tickets are not fishing meet or harvest relay tickets")
	expect(view(w,"td").tickets==1 and view(w,"td").rounds==1 and view(w,"td").best==2,"View shows own tickets/rounds/best")
	# Ticket counter cap.
	(pl(w,"ta").showcase as Dictionary).tickets=Show.MAX_TICKETS
	w.active_tokens["td"]=true
	pl(w,"te").region=World.REGIONS.HOME
	w.state.time=float(w.state.showcase.ready)
	ok(w,"ta","showcase_start",Show.SIGN,"1","Round 2")
	w.state.time=float(w.state.showcase.ends)
	w.step(0.5,true)
	expect(int(record_of(w,"ta").tickets)==Show.MAX_TICKETS and int(record_of(w,"ta").rounds)==2,"Tickets saturate at MAX_TICKETS")
	expect(same(cores(w,tokens),before),"Player records still identical after round 2")

# 9. Theme rotation over 8 rounds; display cleared by step after the cooldown or by the next start.
func test_rotation_and_clearing()->void:
	var w:=make_world(["rot"])
	var seen:=[]
	for r in range(1,9):
		ok(w,"rot","showcase_start",Show.SIGN,str(r-1),"Rotation: start round %d"%r)
		var theme:=str(show_of(w).theme)
		seen.append(theme)
		expect(theme==Show.theme_of(r) and view(w,"rot").theme==theme and view(w,"rot").theme_name==Show.theme_name(theme),"Round %d theme %s in state and view"%[r,theme])
		expect((show_of(w).pieces as Dictionary).is_empty(),"Round %d starts with an empty plot"%r)
		place(w,"rot",Vector2i(27,44+r%4),kind_for("light",r),"Rotation: piece in round %d"%r)
		w.state.time=float(show_of(w).ends)
		w.step(0.5,true)
		expect(show_of(w).active==false and str(show_of(w).last.theme)==theme and (show_of(w).pieces as Dictionary).size()==1,"Round %d settled; display kept"%r)
		w.state.time=float(show_of(w).ready)
		if r%2==1:
			w.step(0.5,true)
			expect((show_of(w).pieces as Dictionary).is_empty(),"Round %d display cleared by step after the cooldown"%r)
		else:
			expect((show_of(w).pieces as Dictionary).size()==1,"Round %d display still there until the next start"%r)
		stand(w,"rot",HOME_SPOT)
	var distinct:={}
	for t:String in seen:distinct[t]=true
	expect(distinct.size()==4 and seen.slice(0,4)==Show.THEME_ORDER and seen.slice(4,8)==Show.THEME_ORDER,"Eight rounds cover all four themes twice in order (%s)"%str(seen))
	expect(same(record_of(w,"rot"),{"tickets":8,"rounds":8,"best":1,"paid_round":8}),"8 rounds, 1 ticket each")

# 10. Disconnect and travel drop the entry; pieces stay; the hook is idempotent.
func test_disconnect_and_travel()->void:
	var w:=make_world(["dia","dib"])
	var before:=cores(w,["dia","dib"])
	ok(w,"dia","showcase_start",Show.SIGN,"0","dia starts")
	ok(w,"dib","showcase_join",Show.SIGN,"1","dib joins")
	place(w,"dia",Vector2i(31,46),"lantern","dia places")
	expect(w.showcase_disconnect("dia"),"Disconnect hook drops dia")
	expect(entry_of(w,"dia").joined==false and (show_of(w).pieces as Dictionary).has("31,46"),"dia is out; the piece stays")
	expect(not w.showcase_disconnect("dia"),"Second disconnect changes nothing")
	expect(not w.showcase_disconnect("nobody"),"Unknown token changes nothing")
	stand(w,"dia",HOME_SPOT)
	ok(w,"dia","showcase_join",Show.SIGN,"1","dia rejoins after reconnecting")
	expect(view(w,"dia").shown==1 and view(w,"dia").placed==1,"Rejoined dia still owns the piece")
	pl(w,"dib").region=World.REGIONS.LANYANG
	expect(w.step(0.5,true),"Step reports the travel drop")
	expect(entry_of(w,"dib").joined==false,"Travelling away drops dib")
	pl(w,"dib").region=World.REGIONS.HOME
	w.active_tokens.erase("dia")
	w.step(0.5,true)
	expect(entry_of(w,"dia").joined==false,"Offline (no hook) is dropped by step")
	var quiet:=var_to_bytes(w.state.showcase)
	w.step(0.5,true)
	expect(var_to_bytes(w.state.showcase)==quiet,"Dropping is not repeated")
	expect(same(cores(w,["dia","dib"]),before),"Player records identical after disconnect and travel")
	# Both out; the timeout still pays both once.
	w.state.time=float(show_of(w).ends)
	w.step(0.5,true)
	for t in ["dia","dib"]:expect(int(record_of(w,t).tickets)==1 and int(record_of(w,t).paid_round)==1,"%s paid once although out at the deadline"%t)

# 11. Request replay returns the receipt without a second piece.
func test_replay()->void:
	var w:=make_world(["rep"])
	ok(w,"rep","showcase_start",Show.SIGN,"0","Start")
	var r:=act(w,"rep","showcase_place",Vector2i(27,45),"1|lantern","replay-place")
	expect(bool(r.ok) and (show_of(w).pieces as Dictionary).size()==1 and int(entry_of(w,"rep").placed)==1,"Place with a fixed request id")
	ok(w,"rep","showcase_remove",Vector2i(27,45),"1","Remove it")
	var again:=act(w,"rep","showcase_place",Vector2i(27,45),"1|lantern","replay-place")
	expect(again==r and (show_of(w).pieces as Dictionary).is_empty() and int(entry_of(w,"rep").placed)==1,"Replayed place returns the receipt and places nothing")

## Tamper cases. `sam` holds a paid record (round 1) in both fixtures; in the active
## fixture round 2 is running with uma and sam, sam having placed two pieces.
static func tampered(good:Dictionary,label:String)->Dictionary:
	var s:Dictionary=good.duplicate(true)
	var sh:Dictionary=s.showcase
	var people:Dictionary=sh.participants
	var pieces:Dictionary=sh.pieces
	var paid:Dictionary=s.players.sam
	var tile:String=str(pieces.keys()[0]) if not pieces.is_empty() else "27,44"
	match label:
		"showcase is an array":s.showcase=[]
		"showcase without picnic":s.picnic=false
		"negative round":sh.round=-1
		"fractional round":sh.round=1.5
		"active not bool":sh.active=1
		"theme wrong for the round":sh.theme="warm_night"
		"theme unknown":sh.theme="disco"
		"ends not started+600":sh.ends=float(sh.started)+300.0
		"started in the future":
			sh.started=float(s.time)+500.0
			sh.ends=float(sh.started)+600.0
		"pieces not a dict":sh.pieces=[]
		"piece outside the plot":pieces["33,44"]=pieces[tile]
		"piece on the sign":pieces["26,45"]=pieces[tile]
		"piece bad key":pieces["here"]=pieces[tile]
		"piece non-canonical key":pieces["027,44"]=pieces[tile]
		"piece spaced key":pieces["27, 46"]=pieces[tile]
		"piece unknown kind":pieces[tile].kind="bonfire"
		"piece inventory item":pieces[tile].kind="wood"
		"piece by a non-participant":pieces[tile].by="tia"
		"piece by a ghost":pieces[tile].by="ghost-token"
		"piece extra field":pieces[tile].glow=1
		"piece missing placer":pieces[tile].erase("by")
		"piece not a dict":pieces[tile]="lantern"
		"more pieces than placed":people.sam.placed=0
		"negative placed":people.sam.placed=-1
		"fractional placed":people.sam.placed=2.5
		"joined not bool":people.sam.joined=1
		"participant not a player":people["ghost-token"]={"placed":0,"joined":false}
		"entry extra field":people.sam.mood=1
		"entry missing field":people.sam.erase("joined")
		"extra root field":sh.mood=1
		"missing root field":sh.erase("ready")
		"last tickets wrong":sh.last.tickets=int(sh.last.tickets)+1
		"last met not bool":sh.last.met=0
		"last full with few pieces":
			sh.last.full=true
			sh.last.tickets=int(sh.last.tickets)+1
		"last reason bogus":sh.last.reason="magic"
		"last round mismatch":sh.last.round=int(sh.last.round)+1
		"last theme wrong":sh.last.theme="sea_breeze" if str(sh.last.theme)!="sea_breeze" else "garden_tea"
		"goal reason unmet":sh.last.reason="goal"
		"ready mismatch":sh.ready=float(sh.ready)+5.0
		"joined while inactive":people.sam.joined=true
		"paid record while active":paid.showcase.paid_round=int(sh.round)
		"record paid_round ahead":paid.showcase.paid_round=int(sh.round)+1
		"record tickets below rounds":paid.showcase.tickets=0
		"record tickets above three per round":paid.showcase.tickets=int(paid.showcase.rounds)*3+1
		"record extra field":paid.showcase.bonus=1
		"record missing for a paid participant":paid.erase("showcase")
		"record is a string":paid.showcase="ticket"
		"record without a round":s.erase("showcase")
		"record best over the plot":paid.showcase.best=25
		"last pieces differ from the display":sh.last.pieces=int(sh.last.pieces)+1
		"last met differs from the display":
			sh.last.met=true
			sh.last.tickets=int(sh.last.tickets)+1
		"last players differ":sh.last.players=int(sh.last.players)+1
	return s

# 12. Save -> reload equality (mid-round and settled), legacy saves, schema tampering.
func test_save_reload_and_schema()->void:
	var path:=temp_path("world")
	var fixture:=temp_path("fixture")
	_cleanup.append(path)
	_cleanup.append(fixture)
	var w:=make_world(["sam","tia","uma"])
	w.save_path=path
	# Round 1 times out with 3 pieces (sam 2, tia 1); round 2 is active mid-way.
	ok(w,"sam","showcase_start",Show.SIGN,"0","sam starts")
	ok(w,"tia","showcase_join",Show.SIGN,"1","tia joins")
	place(w,"sam",Vector2i(27,44),"flower_pot","sam places 1")
	place(w,"sam",Vector2i(28,44),"stool","sam places 2")
	place(w,"tia",Vector2i(29,44),"lantern","tia places")
	w.state.time=float(show_of(w).ends)+0.25
	w.step(0.5,true)
	expect(show_of(w).active==false and int(show_of(w).last.pieces)==3 and (show_of(w).pieces as Dictionary).size()==3,"Round 1 finished by time, display kept")
	expect(w.save(),"World saves after settlement")
	var settled:=World.new()
	expect(settled.load_world(path),"Fresh world reloads the settled save")
	if failures>0:return
	expect(same(show_of(settled),show_of(w)),"Settled round (with its display) survives reload (canonical)")
	for token in ["sam","tia","uma"]:
		expect(same(record_of(settled,token),record_of(w,token)),"%s record survives reload (settled)"%token)
		expect(same(view(settled,token),view(w,token)),"%s view identical after reload (settled)"%token)
	var finished_state:Dictionary=w.state.duplicate(true)
	w.state.time=float(w.state.showcase.ready)+3.5
	stand(w,"uma",HOME_SPOT)
	ok(w,"uma","showcase_start",Show.SIGN,"1","uma starts round 2")
	stand(w,"sam",HOME_SPOT)
	ok(w,"sam","showcase_join",Show.SIGN,"2","sam joins round 2")
	place(w,"sam",Vector2i(30,46),"bench","sam places in round 2")
	place(w,"sam",Vector2i(31,46),"string_lights","sam places again in round 2")
	expect(w.save(),"World saves mid-round")
	var restored:=World.new()
	expect(restored.load_world(path),"Fresh world reloads the mid-round save")
	if failures>0:return
	expect(same(show_of(restored),show_of(w)),"Round state survives reload (canonical)")
	for token in ["sam","tia","uma"]:
		expect(same(record_of(restored,token),record_of(w,token)),"%s record survives reload"%token)
		expect(same(pl(restored,token).inventory,pl(w,token).inventory) and int(pl(restored,token).coins)==int(pl(w,token).coins),"%s inventory and coins survive reload"%token)
		expect(same(view(restored,token),view(w,token)),"%s view identical after reload"%token)
	var rr:=show_of(restored)
	expect(typeof(rr.round)==TYPE_INT and typeof(rr.participants.sam.placed)==TYPE_INT and typeof(rr.last.tickets)==TYPE_INT and typeof(rr.last.pieces)==TYPE_INT and typeof(record_of(restored,"sam").tickets)==TYPE_INT,"Validation normalizes reloaded numbers to ints")
	# The reloaded active round keeps working and settles on the next step.
	restored.active_tokens={"sam":true,"tia":true,"uma":true}
	stand(restored,"sam",Vector2(32.5,46.5))
	ok(restored,"sam","showcase_place",Vector2i(32,46),"2|cushion","sam places after reload")
	restored.state.time=float(restored.state.showcase.ends)
	restored.step(0.5,true)
	expect(show_of(restored).active==false and int(record_of(restored,"uma").paid_round)==2 and int(record_of(restored,"sam").paid_round)==2 and int(record_of(restored,"tia").paid_round)==1,"Reloaded round settles; tia (round 1 only) untouched")
	# Legacy save without the fields.
	var base:Dictionary=w.state.duplicate(true)
	var old:Dictionary=base.duplicate(true)
	old.erase("showcase")
	for token in ["sam","tia","uma"]:(old.players[token] as Dictionary).erase("showcase")
	expect(write_fixture(fixture,old),"Write legacy fixture")
	var legacy:=World.new()
	expect(legacy.load_world(fixture),"Save without showcase fields loads")
	expect(not legacy.state.has("showcase") and not pl(legacy,"sam").has("showcase"),"Loading does not invent showcase fields")
	expect(view(legacy,"sam").round==0 and view(legacy,"sam").can_start==true,"Legacy world starts fresh")
	expect(write_fixture(fixture,base),"Write control fixture")
	var control:=World.new()
	expect(control.load_world(fixture) and same(show_of(control),show_of(w)),"Control fixture (active round) loads")
	expect(write_fixture(fixture,finished_state),"Write finished control fixture")
	expect(World.new().load_world(fixture),"Control fixture (finished round) loads")
	# A finished round whose display was already cleared also loads.
	var cleared:Dictionary=finished_state.duplicate(true)
	cleared.showcase.pieces={}
	expect(write_fixture(fixture,cleared) and World.new().load_world(fixture),"Finished round with a cleared display loads")
	if failures>0:return
	var probe:=World.new()
	var pristine:Dictionary=probe.state.duplicate(true)
	var active_labels:=["showcase is an array","showcase without picnic","negative round","fractional round","active not bool","theme wrong for the round","theme unknown",
		"ends not started+600","started in the future","pieces not a dict","piece outside the plot","piece on the sign","piece bad key","piece non-canonical key","piece spaced key",
		"piece unknown kind","piece inventory item","piece by a non-participant","piece by a ghost","piece extra field","piece missing placer","piece not a dict",
		"more pieces than placed","negative placed","fractional placed","joined not bool","participant not a player","entry extra field","entry missing field",
		"extra root field","missing root field","last tickets wrong","last met not bool","last full with few pieces","last reason bogus","last round mismatch","last theme wrong",
		"goal reason unmet","ready mismatch","paid record while active","record paid_round ahead","record tickets below rounds","record tickets above three per round",
		"record extra field","record is a string","record without a round","record best over the plot"]
	var finished_labels:=["joined while inactive","record missing for a paid participant","last tickets wrong","record paid_round ahead","last pieces differ from the display",
		"last met differs from the display","last players differ","piece outside the plot","more pieces than placed","theme wrong for the round"]
	var count:=0
	for label:String in active_labels:
		var bad:=tampered(base,label)
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"Schema rejects (active round) "+label)
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+label)
		count+=1
	for label:String in finished_labels:
		var bad:=tampered(finished_state,label)
		expect(write_fixture(fixture,bad),"Write tampered fixture: "+label)
		expect(not probe.load_world(fixture),"Schema rejects (finished round) "+label)
		expect(probe.state==pristine,"Rejected load leaves the world untouched: "+label)
		count+=1
	expect(count>=50,"At least 50 tamper cases (%d)"%count)

# 13. Snapshot privacy: hashed participants, token-free pieces, own view only to the owner.
func test_snapshot_privacy()->void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=make_world([PRIVATE_A,PRIVATE_B])
	var w=session.world
	ok(w,PRIVATE_A,"showcase_start",Show.SIGN,"0","Alpha starts")
	ok(w,PRIVATE_B,"showcase_join",Show.SIGN,"1","Beta joins")
	place(w,PRIVATE_A,Vector2i(27,44),"lantern","Alpha places")
	place(w,PRIVATE_B,Vector2i(28,44),"bench","Beta places")
	ok(w,PRIVATE_A,"showcase_leave",Show.SIGN,"","Alpha leaves")
	stand(w,PRIVATE_A,HOME_SPOT)
	ok(w,PRIVATE_A,"showcase_join",Show.SIGN,"1","Alpha rejoins")
	session.peers={1:PRIVATE_A,2:PRIVATE_B}
	var id_a:=PRIVATE_A.sha256_text().left(16)
	var id_b:=PRIVATE_B.sha256_text().left(16)
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		var text:=JSON.stringify(public)
		expect(not text.contains(PRIVATE_A) and not text.contains(PRIVATE_B),"public_state(%s) has no raw token"%region)
		var sc:Dictionary=public.get("showcase",{})
		expect(sc.get("participants",{}).keys().size()==2 and sc.participants.has(id_a) and sc.participants.has(id_b),"public_state(%s) participants keyed by public ids"%region)
		var clean:=true
		for id in public.get("players",{}):
			if (public.players[id] as Dictionary).has("showcase"):clean=false
		expect(clean,"public_state(%s) players carry no showcase record"%region)
	var sc:Dictionary=session.public_state("home").showcase
	expect(same(sc.participants[id_a],{"name":"showca","placed":1,"shown":1,"joined":true}),"Alpha's public entry shows name and counts (%s)"%str(sc.participants[id_a]))
	expect(same(sc.pieces,{"27,44":"lantern","28,44":"bench"}) and int(sc.pieces_count)==2,"Public pieces are cell -> kind only")
	expect(int(sc.round)==1 and sc.active==true and sc.theme=="garden_tea" and sc.theme_met==false and (sc.requirements as Array).size()==3,"Public round summary")
	var keys:Array=sc.keys()
	keys.sort()
	expect(keys==PUBLIC_KEYS,"Public projection keys (%s)"%str(keys))
	expect(w.state.showcase.participants.has(PRIVATE_A) and str(w.state.showcase.pieces["27,44"].by)==PRIVATE_A,"Publishing does not rewrite the live record")
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(snap.has("own_showcase") and same(snap.own_showcase,w.showcase_view(PRIVATE_A)),"own_showcase equals the recipient's own view")
	expect(snap.own_showcase.shown==1 and snap.own_showcase.joined==true,"own_showcase shows the recipient's display count")
	expect(snap.has("showcase") and snap.has("fish_meet") and snap.has("own_fish_meet") and snap.has("own_harvest") and snap.has("harvest_relay"),"Snapshot still carries the sibling activity fields")
	expect(not JSON.stringify(snap).contains(PRIVATE_A) and not JSON.stringify(snap).contains(PRIVATE_B),"Snapshot carries no raw token")
	session.world=null
	session.queue_free()
	await process_frame
