extends SceneTree
## T067 暖岩片 warm_stone + 共餐桌保溫底座 (scripts/table_warmer.gd) rules test.
## Headless, World-level (World.act / save / load_world), plus an in-process Session
## for the public snapshot. No network.
##
## EARNED through real World.act: alpha's six warm_stone (3 strikes on B12 + 3 on B13),
## the picnic (World.act "picnic"), the installation, every serve / claim, the festival
## opening.
## WRITTEN DIRECTLY (disclosed): state.board=true, picnic soup 2 / bread 1, the
## mine_depths record {"unlocked":15,"ready":{},"pumped":24,"hoist":true}, player
## region/x/y (relocating into mines and back home, wrong-region / too-far cases),
## mine_energy=100 before each strike, reinforced_pick 1, state.time jumps past node
## cooldowns, copper_joint 2 / stone 4 (alpha) and other material / trout_hotpot /
## watermelon_platter counts, beta's warm_stone at the 1e9 cap, lamps + dock_stage +
## project mask for the festival fixture, and the tampered / legacy save files.
const World=preload("res://scripts/world.gd")
const Community=preload("res://scripts/community.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const Mines=preload("res://scripts/mine_depths.gd")
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Session=preload("res://scripts/session.gd")
const ALPHA:="warmer-alpha-token-7f3a"
const BETA:="warmer-beta-token-91c2"
const GUESTS:=["warmer-guest-1-aa","warmer-guest-2-bb","warmer-guest-3-cc","warmer-guest-4-dd","warmer-guest-5-ee"]
const TABLE:=Vector2i(39,30)
const BOARD:=Vector2i(40,29)
const NEAR:=Vector2(40.5,30.5)
const CAP:=1000000000

var checks:=0
var failures:=0
var serial:=0
var temp_files:=[]

class FestivalWorld extends World:
	var project_fixture:=0
	func island_project_mask() -> int:
		return project_fixture

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	check_static()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	check_mining_world()
	main_flow(w,path)
	check_plain_before_install()
	check_festival()
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("TABLE_WARMER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("table-warmer-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

static func bag_of(inv:Dictionary) -> Dictionary:
	var out:={}
	for item in inv:
		if int(inv[item])!=0:out[str(item)]=int(inv[item])
	return out

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func put(w:World,token:String,at:Vector2,region:String="home") -> void:
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

func setinv(w:World,token:String,item:String,count:int) -> void:
	w.state.players[token]["inventory"][item]=count

func act(w:World,token:String,action:String,p:Vector2i,extra:String="",request:String="") -> Dictionary:
	serial+=1
	return w.act(token,request if not request.is_empty() else "warmer-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

## Rejected with the exact message and the whole world state byte-identical (canonical).
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> void:
	var before:=var_to_bytes(canon(w.state))
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or str(r.get("message",""))==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)

func strike(w:World,token:String,depth:int,node:int) -> Dictionary:
	var at:Vector2i=Mines.NODES[node]
	put(w,token,Vector2(at.x-0.5,at.y+0.5),Mines.IDS[depth-1])
	pl(w,token)["mine_energy"]=100
	w.state.time=float(w.state.time)+Mines.COOLDOWN+1.0
	return act(w,token,"mine_extract",at)

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func picnic(w:World,token:String) -> bool:
	w.state["board"]=true
	setinv(w,token,"soup",2)
	setinv(w,token,"bread",1)
	put(w,token,NEAR)
	var r:=act(w,token,"picnic",BOARD)
	return bool(r.ok) and Community.table_cell(w.state)==TABLE

# ---------------------------------------------------------------- static API --

func check_static() -> void:
	expect(World.NAMES.get("warm_stone")=="暖岩片","warm_stone is a registered item named 暖岩片")
	expect(Warmer.ACTIONS==["warmer_install","serve_hotpot_warm"] and Warmer.INSTALL_ACTION=="warmer_install" and Warmer.SERVE_ACTION=="serve_hotpot_warm","action names")
	expect(Warmer.INSTALL_COST=={"warm_stone":6,"copper_joint":2,"stone":4} and Warmer.install_cost()==Warmer.INSTALL_COST,"install cost warm_stone 6 / copper_joint 2 / stone 4")
	expect(Warmer.WARM_PORTIONS==6 and Community.WARM_HOTPOT_PORTIONS==6 and Community.HOTPOT_PORTIONS==4,"six warm portions; plain round stays four")
	for item in Warmer.ITEM_NAMES:expect(World.NAMES.get(item)==Warmer.ITEM_NAMES[item],"helper name for %s matches World.NAMES"%item)
	for action:String in Warmer.ACTIONS:
		expect(action.length()<=24 and Session.extra_allowed(action,""),"%s passes the Session transport bounds"%action)
		expect(action not in Community.ACTIONS,"%s is not routed through the plain community branch"%action)
	expect(not World.OTHER_SALES.has("warm_stone") and not World.CROPS.has("warm_stone") and not World.FISH.has("warm_stone"),"warm_stone has no sale price (like ochre_earth)")
	expect(not World.OTHER_SALES.has("ochre_earth"),"control: ochre_earth has no sale price either")
	var rows:=Warmer.materials({"warm_stone":4,"stone":9})
	expect(rows.size()==3 and rows[0].item=="warm_stone" and rows[0].have==4 and rows[0].need==6 and rows[0].short==2 and rows[1].short==2 and rows[2].short==0,"materials() reports have/need/short in cost order")
	expect(Warmer.missing({"warm_stone":4,"stone":9})=={"warm_stone":2,"copper_joint":2} and Warmer.missing_text({"warm_stone":4,"stone":9})=="暖岩片 2、銅接頭 2","missing() and missing_text()")
	expect(Warmer.missing_text({"warm_stone":6,"copper_joint":2,"stone":4}).is_empty(),"nothing missing with the exact cost")
	var snap:={"picnic":true,"community":{"table":"39,30"}}
	expect(Warmer.install_block({"picnic":false,"community":{"table":""}},{})==Warmer.LOCKED,"install_block before picnic")
	expect(Warmer.install_block(snap,{"warm_stone":5,"copper_joint":2,"stone":4})==Warmer.SHORT%"暖岩片 1","install_block when short")
	expect(Warmer.can_install(snap,{"warm_stone":6,"copper_joint":2,"stone":4}),"can_install with the exact cost")
	expect(Warmer.serve_block(snap,{"trout_hotpot":6})==Warmer.NOT_INSTALLED,"serve_block without base")
	var on:={"picnic":true,"community":{"table":"39,30"},"table_warmer":{"installed":true}}
	expect(Warmer.installed(on) and not Warmer.installed(snap) and Warmer.install_block(on,{"warm_stone":6,"copper_joint":2,"stone":4})==Warmer.ALREADY,"installed() and ALREADY")
	expect(Warmer.serve_block(on,{"trout_hotpot":5})==Warmer.HOTPOT_SHORT and Warmer.can_serve_warm(on,{"trout_hotpot":6}),"serve_block hotpot count")
	on.community["hotpot"]={"portions":1,"total":6}
	expect(Warmer.serve_block(on,{"trout_hotpot":6})==Warmer.STILL_SERVING,"serve_block while portions remain")
	expect(Warmer.round_total({"portions":1,"total":6})==6 and Warmer.round_total({"portions":1})==4 and Warmer.round_total(null)==4,"round_total")
	expect(Warmer.public(on)=={"installed":true} and Warmer.public(snap)=={},"public()")
	var bare:={"players":{"x":{"x":40.5,"y":30.5,"inventory":{}}},"picnic":true,"community":{"table":"39,30"}}
	expect(Warmer.apply(bare,"nobody",Warmer.INSTALL_ACTION,TABLE,"",true).message==Warmer.NO_PLAYER,"unknown player refused at module level")
	expect(Warmer.apply(bare,"x","serve_hotpot",TABLE,"",true).message==Warmer.BAD_EXTRA,"foreign action refused at module level")

# -------------------------------------------------------------------- mining --

func check_mining_world() -> void:
	var w:=World.new()
	w.add_player("miner","Miner")
	w.state.mine_depths={"unlocked":15,"ready":{},"pumped":24,"hoist":true}
	setinv(w,"miner","reinforced_pick",1)
	for depth in [11,12,13,14]:
		var before:=bag_of(pl(w,"miner").inventory)
		var r:=strike(w,"miner",depth,0)
		var gained:=bag_of(pl(w,"miner").inventory)
		var expected:=before.duplicate()
		expected[Mines.ORES[depth-1]]=int(expected.get(Mines.ORES[depth-1],0))+int(Mines.YIELDS[depth-1])
		for found in Catalog.DEPTHS[depth].finds:expected[found]=int(expected.get(found,0))+1
		expect(r.ok and same(gained,expected),"B%d strike gives ore + one of each find, nothing else (got %s)"%[depth,str(gained)])
		var warm:=int(gained.get("warm_stone",0))-int(before.get("warm_stone",0))
		if depth in [12,13]:
			expect(warm==1 and str(r.message).contains("暖岩片 +1"),"B%d strike adds warm_stone +1 and names it (%s)"%[depth,str(r.message)])
		else:
			expect(warm==0 and not str(r.message).contains("暖岩片"),"B%d strike gives no warm_stone (%s)"%[depth,str(r.message)])
	setinv(w,"miner","warm_stone",CAP)
	var before_cap:=bag_of(pl(w,"miner").inventory)
	var capped:=strike(w,"miner",12,1)
	var after_cap:=bag_of(pl(w,"miner").inventory)
	expect(capped.ok and int(after_cap.warm_stone)==CAP and not str(capped.message).contains("暖岩片"),"warm_stone at the cap is skipped, strike still pays (%s)"%str(capped.message))
	expect(int(after_cap.get("stone",0))==int(before_cap.get("stone",0))+1 and int(after_cap.get("gold_ore",0))==int(before_cap.get("gold_ore",0))+int(Mines.YIELDS[11]),"capped B12 strike still gives gold ore and the stone find")

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> void:
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	for g:String in GUESTS:w.add_player(g,g.left(10))
	w.state.mine_depths={"unlocked":15,"ready":{},"pumped":24,"hoist":true}
	setinv(w,ALPHA,"reinforced_pick",1)
	# Earn six warm stones: three strikes on B12, three on B13.
	for depth in [12,13]:
		for node in 3:
			var had:=int(pl(w,ALPHA).inventory.get("warm_stone",0))
			var r:=strike(w,ALPHA,depth,node)
			expect(r.ok and int(pl(w,ALPHA).inventory.get("warm_stone",0))==had+1,"alpha earns warm_stone on B%d node %d"%[depth,node])
	expect(int(pl(w,ALPHA).inventory.warm_stone)==6,"alpha earned exactly six warm stones")
	put(w,ALPHA,NEAR)
	put(w,BETA,Vector2(38.5,30.5))
	for i in GUESTS.size():put(w,GUESTS[i],Vector2(37.5+i,31.5) if i<4 else Vector2(41.5,29.5))
	setinv(w,ALPHA,"copper_joint",2)
	setinv(w,ALPHA,"stone",4)
	setinv(w,BETA,"warm_stone",6)
	setinv(w,BETA,"copper_joint",2)
	setinv(w,BETA,"stone",4)
	expect(w.save(),"pre-picnic world saves")
	# Before the picnic.
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.LOCKED,"install before picnic")
	refuse(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"",Warmer.LOCKED,"warm serve before picnic")
	expect(picnic(w,ALPHA),"real picnic sets the shared table at 39,30")
	var pre_install:=temp_path("pre-install")
	expect(w.save() and DirAccess.copy_absolute(path,pre_install)==OK,"snapshot of the pre-install save")
	# Rejections after the picnic.
	setinv(w,ALPHA,"trout_hotpot",6)
	refuse(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"",Warmer.NOT_INSTALLED,"warm serve without base")
	put(w,ALPHA,Vector2(29.5,20.5),"jinguashi")
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.WRONG_REGION,"install from Jinguashi")
	put(w,ALPHA,NEAR)
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,Vector2i(40,31),"",Warmer.WRONG_CELL,"install at a neighbour cell")
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,BOARD,"",Warmer.WRONG_CELL,"install at the board")
	put(w,ALPHA,Vector2(39.5,35.5))
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.TOO_FAR,"install from five tiles away")
	put(w,ALPHA,NEAR)
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"x",Warmer.BAD_EXTRA,"install with a non-empty extra")
	for item:String in Warmer.COST_ORDER:
		var need:=int(Warmer.INSTALL_COST[item])
		setinv(w,ALPHA,item,need-1)
		refuse(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.SHORT%("%s 1"%Warmer.ITEM_NAMES[item]),"install one %s short"%item)
		setinv(w,ALPHA,item,need)
	# Install.
	var alpha_before:=bag_of(pl(w,ALPHA).inventory)
	var beta_before:=bag_of(pl(w,BETA).inventory)
	var coins_before:=[int(pl(w,ALPHA).coins),int(pl(w,BETA).coins)]
	expect(not w.state.has("table_warmer"),"no table_warmer key before installation")
	var installed:=act(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"","install-once")
	expect(installed.ok and str(installed.message)==Warmer.INSTALLED_OK,"alpha installs the warmer (%s)"%str(installed.message))
	var alpha_after:=alpha_before.duplicate()
	for item in Warmer.INSTALL_COST:alpha_after[item]=int(alpha_after[item])-int(Warmer.INSTALL_COST[item])
	alpha_after=bag_of(alpha_after)
	expect(same(bag_of(pl(w,ALPHA).inventory),alpha_after),"install deducts exactly the cost from alpha (got %s)"%str(bag_of(pl(w,ALPHA).inventory)))
	expect(same(bag_of(pl(w,BETA).inventory),beta_before) and int(pl(w,ALPHA).coins)==coins_before[0] and int(pl(w,BETA).coins)==coins_before[1],"beta's bag and both purses untouched")
	expect(same(w.state.get("table_warmer"),{"installed":true}),"state.table_warmer == {installed:true}")
	var replay_before:=var_to_bytes(canon(w.state))
	expect(act(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"","install-once")==installed and var_to_bytes(canon(w.state))==replay_before,"replayed request id returns the receipt without applying twice")
	refuse(w,BETA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.ALREADY,"beta (with materials) cannot install a second base")
	for item in Warmer.INSTALL_COST:setinv(w,ALPHA,item,int(Warmer.INSTALL_COST[item]))
	refuse(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.ALREADY,"alpha cannot install again")
	for item in Warmer.INSTALL_COST:setinv(w,ALPHA,item,int(alpha_after.get(item,0)))
	expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"installed world saves and validates")
	# Warm serve.
	setinv(w,ALPHA,"trout_hotpot",5)
	refuse(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"",Warmer.HOTPOT_SHORT,"warm serve with five hotpots")
	refuse(w,BETA,Warmer.SERVE_ACTION,TABLE,"",Warmer.HOTPOT_SHORT,"beta warm serve with no hotpot")
	refuse(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"now",Warmer.BAD_EXTRA,"warm serve with extra")
	refuse(w,ALPHA,Warmer.SERVE_ACTION,Vector2i(40,31),"",Warmer.WRONG_CELL,"warm serve at the wrong cell")
	setinv(w,ALPHA,"trout_hotpot",6)
	var served:=ok(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"","alpha serves six warm portions")
	expect(str(served.get("message",""))==Warmer.WARM_SERVED,"warm serve message")
	expect(int(pl(w,ALPHA).inventory.trout_hotpot)==0 and same(w.state.community.hotpot,{"portions":6,"claimed":{},"total":6}),"six hotpots in, six portions on the table with total 6")
	setinv(w,ALPHA,"trout_hotpot",10)
	refuse(w,ALPHA,Warmer.SERVE_ACTION,TABLE,"",Warmer.STILL_SERVING,"warm serve while portions remain")
	refuse(w,ALPHA,"serve_hotpot",TABLE,"","餐桌上還有雪點鱒魚火鍋，先留給晚點回來的島民。","plain serve while warm portions remain")
	setinv(w,ALPHA,"trout_hotpot",0)
	# Six distinct islanders claim once each.
	var claimers:=[ALPHA,BETA]+GUESTS.slice(0,4)
	var total_out:=0
	for i in claimers.size():
		var who:String=claimers[i]
		var had:=int(pl(w,who).inventory.get("trout_hotpot",0))
		var r:=act(w,who,"claim_hotpot",TABLE)
		expect(r.ok and int(pl(w,who).inventory.get("trout_hotpot",0))==had+1 and int(w.state.community.hotpot.portions)==5-i,"claimer %d takes one warm portion"%(i+1))
		total_out+=int(pl(w,who).inventory.get("trout_hotpot",0))-had
		if i==2:
			expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"half-claimed warm round (portions 3, three claimed, total 6) validates")
	expect(total_out==6 and int(w.state.community.hotpot.portions)==0 and w.state.community.hotpot.claimed.size()==6 and int(w.state.community.hotpot.total)==6,"conservation: 6 in, 6 out")
	refuse(w,BETA,"claim_hotpot",TABLE,"","雪點鱒魚火鍋已經分完了。","re-claim after the round is empty")
	refuse(w,GUESTS[4],"claim_hotpot",TABLE,"","雪點鱒魚火鍋已經分完了。","seventh islander gets nothing")
	# Plain four-portion round still works after installation.
	setinv(w,ALPHA,"trout_hotpot",4)
	ok(w,ALPHA,"serve_hotpot",TABLE,"","plain serve after installation")
	expect(same(w.state.community.hotpot,{"portions":4,"claimed":{}}) and int(pl(w,ALPHA).inventory.trout_hotpot)==0,"plain round is four portions without total")
	ok(w,GUESTS[4],"claim_hotpot",TABLE,"","the seventh islander claims from the plain round")
	refuse(w,GUESTS[4],"claim_hotpot",TABLE,"","你已領過這一輪，剩下的留給其他島民。","one portion per islander per plain round")
	# Watermelon is unaffected and has no warm variant.
	setinv(w,ALPHA,"watermelon_platter",6)
	refuse(w,ALPHA,"serve_watermelon_warm",TABLE,"","","no warm watermelon action")
	ok(w,ALPHA,"serve_watermelon",TABLE,"","watermelon served")
	expect(same(w.state.community.watermelon,{"portions":4,"claimed":{}}) and int(pl(w,ALPHA).inventory.watermelon_platter)==2,"watermelon stays a four-portion round")
	ok(w,BETA,"claim_watermelon",TABLE,"","beta claims watermelon")
	# Save → reload in a fresh World.
	expect(w.save(),"final world saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads the save")
	for field in ["table_warmer","community","picnic","mine_depths"]:
		expect(same(reloaded.state.get(field),w.state.get(field)),"state.%s equal after reload"%field)
	for token in [ALPHA,BETA]+GUESTS:
		expect(same(bag_of(reloaded.state.players[token].inventory),bag_of(pl(w,token).inventory)),"%s bag equal after reload"%token.left(16))
	refuse(reloaded,GUESTS[4],"claim_hotpot",TABLE,"","你已領過這一輪，剩下的留給其他島民。","claims survive reload")
	refuse(reloaded,BETA,Warmer.INSTALL_ACTION,TABLE,"",Warmer.ALREADY,"base survives reload")
	check_snapshot(reloaded)
	check_saves(path,pre_install)

func check_snapshot(w:World) -> void:
	var session:=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=w
	var keep:=w.save_path
	w.save_path=""
	session.peers={1:ALPHA,2:BETA}
	var tokens:=[ALPHA,BETA]+GUESTS
	for region in ["home","jinguashi","mine_12"]:
		var public:Dictionary=session.public_state(region)
		expect(same(public.get("table_warmer"),{"installed":true}),"public_state(%s) carries table_warmer {installed:true}"%region)
		var text:=JSON.stringify(public)
		var leaked:=false
		for token:String in tokens:
			if text.contains(token):leaked=true
		expect(not leaked,"public_state(%s) contains no raw player token"%region)
		for dish in Community.DISHES:
			if public.get("community",{}).has(dish):expect(not public.community[dish].has("claimed"),"public_state(%s) strips %s claims"%[region,dish])
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	expect(Warmer.installed(snap) and same(snap.table_warmer,{"installed":true}),"alpha's received snapshot shows the base")
	expect(snap.community.hotpot.get("claimed_own")==false and not snap.community.hotpot.has("claimed"),"own claim flag only, no claim map")
	var text2:=JSON.stringify(snap)
	var leaked2:=false
	for token:String in tokens:
		if text2.contains(token):leaked2=true
	expect(not leaked2,"alpha's snapshot contains no raw player token")
	var fresh:=World.new()
	fresh.add_player("solo","Solo")
	session.world=fresh
	session.peers={1:"solo"}
	expect(not session.public_state("home").has("table_warmer"),"a world without the base publishes no table_warmer key")
	session.world=null
	session.queue_free()
	w.save_path=keep

# ------------------------------------------------------------------- saves --

func check_saves(path:String,pre_install:String) -> void:
	var base:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(base is Dictionary,"saved world parses"):return
	# Make the hotpot a half-claimed warm round for the tamper base.
	var claimed:={}
	claimed[ALPHA]=true
	claimed[BETA]=true
	base.community["hotpot"]={"portions":4,"claimed":claimed,"total":6}
	expect(validates(base),"control: half-claimed warm round with the base validates")
	var fixture:=temp_path("fixture")
	expect(write_json(fixture,base) and World.new().load_world(fixture),"control fixture loads")
	# Old-shape saves: no table_warmer key.
	var legacy:=World.new()
	expect(legacy.load_world(pre_install) and not legacy.recovered_from_backup and not legacy.state.has("table_warmer"),"pre-install save (no key) loads without migration")
	var old:Dictionary=base.duplicate(true)
	old.erase("table_warmer")
	old.community["hotpot"]={"portions":3,"claimed":{ALPHA:true},}
	expect(write_json(fixture,old) and World.new().load_world(fixture),"old-shape save with a plain round and no key loads")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["warmer is a list","warmer is a string","warmer is null","warmer empty","installed false","installed string","installed int",
		"extra warmer key","installed without picnic","installed without a table","total on watermelon","total 4","total 8","total string",
		"total fractional","total without base","portions not total minus claimed","portions above total","meal with a fourth key",
		"warm meal without claimed","claimed by a stranger","claimed value false"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)
	expect(labels.size()>=15,"at least 15 tamper cases (%d)"%labels.size())

func tampered(base:Dictionary,label:String) -> Dictionary:
	var s:Dictionary=base.duplicate(true)
	var hot:Dictionary=s.community.hotpot
	match label:
		"warmer is a list":s.table_warmer=[true]
		"warmer is a string":s.table_warmer="installed"
		"warmer is null":s.table_warmer=null
		"warmer empty":s.table_warmer={}
		"installed false":s.table_warmer={"installed":false}
		"installed string":s.table_warmer={"installed":"true"}
		"installed int":s.table_warmer={"installed":1}
		"extra warmer key":s.table_warmer={"installed":true,"by":ALPHA}
		"installed without picnic":
			s.picnic=false
			s.community={"table":""}
		"installed without a table":
			s.community={"table":""}
		"total on watermelon":s.community["watermelon"]={"portions":6,"claimed":{},"total":6}
		"total 4":hot.total=4;hot.portions=2
		"total 8":hot.total=8;hot.portions=6
		"total string":hot.total="6"
		"total fractional":hot.total=6.5
		"total without base":s.erase("table_warmer")
		"portions not total minus claimed":hot.portions=5
		"portions above total":hot.portions=7;hot.claimed={}
		"meal with a fourth key":hot["warm"]=true
		"warm meal without claimed":
			hot.erase("claimed")
			hot["claimers"]={}
		"claimed by a stranger":
			hot.claimed["stranger-token"]=true
			hot.portions=3
		"claimed value false":hot.claimed[ALPHA]=false
	return s

# ------------------------------------------- plain round served before install --

func check_plain_before_install() -> void:
	var path:=temp_path("plain")
	var w:=World.new()
	w.save_path=path
	w.add_player(ALPHA,"Alpha")
	w.add_player(BETA,"Beta")
	put(w,BETA,Vector2(38.5,30.5))
	expect(picnic(w,ALPHA),"plain-first world: real picnic")
	setinv(w,ALPHA,"trout_hotpot",4)
	ok(w,ALPHA,"serve_hotpot",TABLE,"","plain-first: serve a four-portion round before installation")
	ok(w,BETA,"claim_hotpot",TABLE,"","plain-first: beta claims one")
	for item in Warmer.INSTALL_COST:setinv(w,ALPHA,item,int(Warmer.INSTALL_COST[item]))
	ok(w,ALPHA,Warmer.INSTALL_ACTION,TABLE,"","plain-first: install while a plain round is on the table")
	expect(same(w.state.community.hotpot,{"portions":3,"claimed":{BETA:true}}),"plain round untouched by installation (no total added)")
	var again:=World.new()
	expect(w.save() and again.load_world(path),"plain round served before installation stays valid after installation and reload")
	refuse(again,ALPHA,Warmer.SERVE_ACTION,TABLE,"",Warmer.STILL_SERVING,"plain-first: warm serve waits for the plain round")
	ok(again,ALPHA,"claim_hotpot",TABLE,"","plain-first: alpha claims after reload")
	expect(int(again.state.community.hotpot.portions)==2,"plain round continues 4→3→2")

# ------------------------------------------------------------------ festival --

func check_festival() -> void:
	for warm in [false,true]:
		var path:=temp_path("festival-%s"%str(warm))
		var w:=FestivalWorld.new()
		w.save_path=path
		w.add_player("host","Host")
		expect(picnic(w,"host"),"festival fixture: real picnic (warm=%s)"%str(warm))
		w.state["dock_stage"]=2
		w.project_fixture=World.ISLAND_NOTES.project_mask()
		for tile in [Vector2i(38,30),Vector2i(41,31)]:
			w.state.objects[World.key(tile)]={"type":"lamp","owner":"host","items":{}}
		for item in Warmer.INSTALL_COST:setinv(w,"host",item,int(Warmer.INSTALL_COST[item]))
		ok(w,"host",Warmer.INSTALL_ACTION,TABLE,"","festival fixture: install the base")
		expect(not w.festival_story_view().meal,"no meal before serving")
		refuse(w,"host","festival_story_open",BOARD,"","請先完成六項工程、準備共餐，並在共餐桌周圍放兩盞燈。","festival refuses without a meal (warm=%s)"%str(warm))
		setinv(w,"host","trout_hotpot",6)
		ok(w,"host",Warmer.SERVE_ACTION if warm else "serve_hotpot",TABLE,"","festival fixture serves a %s round"%("warm" if warm else "plain"))
		expect(w.festival_story_view().meal,"festival meal condition met by the %s round"%("warm" if warm else "plain"))
		ok(w,"host","festival_story_open",BOARD,"","festival opens with a %s round"%("warm" if warm else "plain"))
		expect(int(w.state.community.hotpot.portions)==(6 if warm else 4),"opening leaves the portions on the table")
