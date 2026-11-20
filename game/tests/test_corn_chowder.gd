extends SceneTree
## 玉米濃湯 corn_chowder: the third shared-table dish (scripts/world.gd RECIPES /
## OTHER_SALES / NAMES, scripts/community.gd DISHES / ACTIONS / share_dish).
## Headless, single process, real World (World.act / World.step / save / load_world),
## isolated temp save files. No network.
##
## EARNED through real World.act / World.step: the picnic, the stove (build), the
## milk (livestock_feed + World.step + livestock_collect), the first four chowder
## portions (queue_cook + World.step + claim_cook), every serve / claim / sell / ship.
## WRITTEN DIRECTLY (every line marked # PRESET, counted in `presets`): player
## positions / region, state.board, picnic soup 2 / bread 1, wood / stone for the
## stove, feed for the cow, sweet_corn counts, chowder / hotpot / watermelon bag
## counts for rejection and second-round cases, and the tampered save files.
const World=preload("res://scripts/world.gd")
const Community=preload("res://scripts/community.gd")
const Coll=preload("res://scripts/collections.gd")
const Schema=preload("res://scripts/save_schema.gd")
const A:="chowder-alpha-token-3b1e"
const B:="chowder-beta-token-c7d2"
const C:="chowder-gamma-token-9e41"
const D:="chowder-delta-token-52aa"
const E:="chowder-epsilon-token-0f6c"
const TABLE:=Vector2i(39,30)
const BOARD:=Vector2i(40,29)
const STALL:=Vector2i(43,29)
const NEAR:=Vector2(40.5,30.5)
const DISH:="corn_chowder"
const TITLE:="玉米濃湯"
const MSG_PLACE:="請到風鈴渡口的共餐桌分食。"
const MSG_SHORT:="需要四份玉米濃湯才能上桌。"
const MSG_STILL:="餐桌上還有玉米濃湯，先留給晚點回來的島民。"
const MSG_GONE:="玉米濃湯已經分完了。"
const MSG_AGAIN:="你已領過這一輪，剩下的留給其他島民。"
const MSG_SERVED:="玉米濃湯上桌了。四份會留在餐桌，島民可以各領一份。"
const MSG_CLAIMED:="已領取一份玉米濃湯。"
const NO_STOVE:=Vector2i(-1,-1)

var checks:=0
var failures:=0
var presets:=0
var serial:=0
var temp_files:=[]

func expect(value:bool,message:String) -> bool:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+message)
	return value

func _initialize() -> void:
	check_data()
	var path:=temp_path("main")
	var w:=World.new()
	w.save_path=path
	main_flow(w,path)
	for file in temp_files:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("CORN_CHOWDER_PRESETS presets=%d"%presets)
	print("CORN_CHOWDER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ------------------------------------------------------------------ helpers --

func temp_path(tag:String) -> String:
	var path:=OS.get_environment("TEMP").path_join("corn-chowder-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(6).hex_encode()])
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

static func shifted(base:Dictionary,delta:Dictionary) -> Dictionary:
	var out:Dictionary=base.duplicate()
	for item in delta:
		out[item]=int(out.get(item,0))+int(delta[item])
		if int(out[item])==0:out.erase(item)
	return out

func pl(w:World,token:String) -> Dictionary:
	return w.state.players[token]

func count(w:World,token:String,item:String) -> int:
	return int(pl(w,token).inventory.get(item,0))

func meals_of(w:World,token:String) -> Dictionary:
	var collection:Dictionary=pl(w,token).get("collection",{})
	var meals:Dictionary=collection.get("meals",{})
	return meals

## Every call is a direct state write (PRESET); counted.
func put(w:World,token:String,at:Vector2,region:String="home") -> void:
	presets+=1
	var p:Dictionary=w.state.players[token]
	p["region"]=region
	p["x"]=at.x
	p["y"]=at.y

## Every call is a direct state write (PRESET); counted.
func setinv(w:World,token:String,item:String,amount:int) -> void:
	presets+=1
	w.state.players[token]["inventory"][item]=amount

func act(w:World,token:String,action:String,p:Vector2i,extra:String="",request:String="") -> Dictionary:
	serial+=1
	return w.act(token,request if not request.is_empty() else "chowder-req-%d"%serial,action,p,extra)

func ok(w:World,token:String,action:String,p:Vector2i,extra:String,label:String) -> Dictionary:
	var r:=act(w,token,action,p,extra)
	expect(bool(r.get("ok",false)),"%s (got '%s')"%[label,str(r.get("message",""))])
	return r

## Rejected (with the exact message when given) and the whole in-memory world
## state byte-identical (canonical var_to_bytes, no JSON reload in between).
func refuse(w:World,token:String,action:String,p:Vector2i,extra:String,message:String,label:String) -> Dictionary:
	var before:=var_to_bytes(canon(w.state))
	var time_before:=float(w.state.time)
	var r:=act(w,token,action,p,extra)
	expect(not bool(r.get("ok",true)) and (message.is_empty() or str(r.get("message",""))==message),"%s: refused with '%s' (got ok=%s '%s')"%[label,message,str(r.get("ok")),str(r.get("message",""))])
	expect(var_to_bytes(canon(w.state))==before,"%s: whole world state byte-identical"%label)
	expect(float(w.state.time)==time_before,"%s: world time unchanged"%label)
	return r

func write_json(path:String,data:Variant) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func validates(data:Dictionary) -> bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func ship_payload(amount:int,total:int) -> String:
	return JSON.stringify([[[DISH,amount]],total])

# ---------------------------------------------------------------------- data --

func check_data() -> void:
	expect(World.RECIPES.has(DISH),"corn_chowder is a stove recipe")
	var recipe:Dictionary=World.RECIPES.get(DISH,{})
	expect(same(recipe,{"name":"玉米濃湯","ingredients":{"sweet_corn":2,"milk":1},"time":30.0,"yield":4}),"recipe is exactly 玉米濃湯 / sweet_corn 2 + milk 1 / 30 s / yield 4 (got %s)"%str(recipe))
	expect(str(recipe.get("name",""))==TITLE and float(recipe.get("time",0.0))==30.0 and int(recipe.get("yield",0))==4,"recipe name, time and yield fields")
	var ingredients:Dictionary=recipe.get("ingredients",{})
	expect(ingredients.size()==2 and int(ingredients.get("sweet_corn",0))==2 and int(ingredients.get("milk",0))==1,"recipe ingredients exactly sweet_corn 2 + milk 1")
	expect(str(World.NAMES.get(DISH,""))==TITLE,"NAMES.corn_chowder == 玉米濃湯")
	expect(int(World.OTHER_SALES.get(DISH,0))==30,"OTHER_SALES.corn_chowder == 30")
	expect(Coll.is_meal(DISH),"Collections.is_meal(corn_chowder)")
	var prices:Dictionary=World.SHIPPING.prices(World.CROPS,World.FISH,World.OTHER_SALES)
	expect(int(prices.get(DISH,0))==30,"shipping price table lists corn_chowder at 30")
	expect(int(prices.get("milk",0))==36,"shipping price table lists milk at 36")
	expect(World.NAMES.has("milk") and World.NAMES.has("sweet_corn"),"both ingredients are named items")
	expect(same(Community.DISHES,{"hotpot":"trout_hotpot","watermelon":"watermelon_platter","chowder":"corn_chowder"}),"Community.DISHES has exactly hotpot / watermelon / chowder")
	expect(Community.ACTIONS==["serve_hotpot","claim_hotpot","serve_watermelon","claim_watermelon","serve_chowder","claim_chowder"] and Community.ACTIONS.size()==6,"Community.ACTIONS has exactly six actions")
	expect(World.COMMUNITY.DISHES==Community.DISHES and World.COMMUNITY.ACTIONS==Community.ACTIONS,"World routes through the same community module")

# --------------------------------------------------------------- main world --

func main_flow(w:World,path:String) -> void:
	for token:String in [A,B,C,D,E]:w.add_player(token,token.left(12))
	put(w,A,NEAR) # PRESET
	put(w,B,Vector2(38.5,31.5)) # PRESET
	put(w,C,Vector2(40.5,31.5)) # PRESET
	put(w,D,Vector2(39.5,32.0)) # PRESET
	put(w,E,Vector2(41.5,29.5)) # PRESET
	before_picnic(w)
	# The real picnic.
	w.state["board"]=true # PRESET
	presets+=1
	setinv(w,A,"soup",2) # PRESET
	setinv(w,A,"bread",1) # PRESET
	ok(w,A,"picnic",BOARD,"","real picnic at the board")
	expect(bool(w.state.picnic) and Community.table_cell(w.state)==TABLE,"picnic places the shared table at 39,30")
	expect(not w.state.community.has("chowder"),"no chowder round before anyone serves")
	cooking(w)
	table(w,path)
	selling(w)
	saves(w,path)

func before_picnic(w:World) -> void:
	expect(not bool(w.state.get("picnic",false)),"fresh world has no picnic")
	setinv(w,A,DISH,4) # PRESET
	refuse(w,A,"serve_chowder",TABLE,"",MSG_PLACE,"serve before the picnic")
	refuse(w,B,"claim_chowder",TABLE,"",MSG_PLACE,"claim before the picnic")
	refuse(w,A,"serve_chowder",BOARD,"",MSG_PLACE,"serve at the board before the picnic")
	setinv(w,A,DISH,0) # PRESET

# ------------------------------------------------------------------- cooking --

## Builds a real stove via World.act "build" at the first legal cell found
## away from the table, shipping box, stall and cow pen.
func build_stove(w:World) -> Vector2i:
	setinv(w,A,"wood",12) # PRESET
	setinv(w,A,"stone",15) # PRESET
	var cow:Vector2i=World.LIVESTOCK.ANIMALS["cow"]["cell"]
	presets+=1 # PRESET: A is repositioned south of each candidate cell during the scan
	for y in range(32,46):
		for x in range(28,54):
			var c:=Vector2i(x,y)
			if Vector2(c).distance_to(Vector2(40,30))<4.5 or Vector2(c).distance_to(Vector2(cow))<4.0:continue
			var p:Dictionary=pl(w,A)
			p["x"]=float(x)+0.5 # PRESET (counted once above)
			p["y"]=float(y)+1.5 # PRESET (counted once above)
			serial+=1
			var r:=w.act(A,"chowder-stove-%d"%serial,"build",c,"stove")
			if bool(r.get("ok",false)):return c
	return NO_STOVE

func near_stove(w:World,stove:Vector2i) -> void:
	put(w,A,Vector2(stove)+Vector2(0.5,1.5)) # PRESET

func cooking(w:World) -> void:
	var stove:=build_stove(w)
	if not expect(stove!=NO_STOVE,"a real stove is built through World.act"):return
	var placed:Dictionary=w.state.objects.get(World.key(stove),{})
	expect(str(placed.get("type",""))=="stove" and count(w,A,"wood")==0 and count(w,A,"stone")==0,"stove placed and paid for")
	near_stove(w,stove)
	var milk_name:=str(World.NAMES["milk"])
	var corn_name:=str(World.NAMES["sweet_corn"])
	# Missing milk.
	setinv(w,A,"sweet_corn",2) # PRESET
	refuse(w,A,"queue_cook",stove,DISH,"缺少%s 1"%milk_name,"queue chowder with no milk")
	refuse(w,A,"cook",stove,DISH,"缺少%s 1"%milk_name,"plain cook chowder with no milk")
	# Earn one milk from the cow.
	var spec:Dictionary=World.LIVESTOCK.ANIMALS["cow"]
	expect(str(spec.get("item",""))=="milk","the cow produces milk")
	var cow:Vector2i=spec["cell"]
	put(w,A,Vector2(cow)+Vector2(0.5,1.5)) # PRESET
	setinv(w,A,"feed",1) # PRESET
	ok(w,A,"livestock_adopt",cow,"cow","adopt the cow first")
	ok(w,A,"livestock_feed",cow,"cow","feed the cow")
	expect(w.step(World.LIVESTOCK.DAY*int(spec.get("days",1)),true),"advance one cow interval through World.step")
	ok(w,A,"livestock_collect",cow,"cow","collect the milk")
	expect(count(w,A,"milk")==1,"exactly one milk earned")
	near_stove(w,stove)
	# Only one corn.
	setinv(w,A,"sweet_corn",1) # PRESET
	refuse(w,A,"queue_cook",stove,DISH,"缺少%s 2"%corn_name,"queue chowder with one corn")
	refuse(w,A,"queue_cook",stove,"corn_chowder_x","還沒有這份食譜","queue an unknown recipe id")
	# Queue for real with one spare corn.
	setinv(w,A,"sweet_corn",3) # PRESET
	var bag_before:=bag_of(pl(w,A).inventory)
	var t0:=float(w.state.time)
	var queued:=ok(w,A,"queue_cook",stove,DISH,"queue corn chowder")
	expect(str(queued.get("kind",""))==DISH and bool(queued.get("started",false)),"queue result names corn_chowder and starts immediately")
	expect(same(bag_of(pl(w,A).inventory),shifted(bag_before,{"sweet_corn":-2,"milk":-1})),"queue removes exactly 2 corn + 1 milk (got %s)"%str(bag_of(pl(w,A).inventory)))
	expect(count(w,A,"sweet_corn")==1 and count(w,A,"milk")==0 and count(w,A,DISH)==0,"spare corn kept, milk spent, no chowder yet")
	expect(float(w.state.time)==t0,"queueing does not advance world time")
	var queue:Dictionary=w.state.objects[World.key(stove)].get("cooking",{})
	var active:Dictionary=queue.get("active",{})
	expect(str(active.get("kind",""))==DISH and absf(float(active.get("finish",0.0))-(t0+30.0))<0.001,"active job is corn_chowder finishing 30 s later")
	refuse(w,A,"claim_cook",stove,"","","claim right after queueing")
	expect(w.step(29.0,true) and absf(float(w.state.time)-(t0+29.0))<0.001,"World.step advances 29 s")
	var early:=refuse(w,A,"claim_cook",stove,"","","claim one second early")
	expect(str(early.get("message","")).begins_with("還要") and str(early.get("message","")).ends_with("秒就好了"),"early claim says how long is left (%s)"%str(early.get("message","")))
	expect(count(w,A,DISH)==0 and not meals_of(w,A).has(DISH),"nothing granted early")
	var cooked_before:=int(pl(w,A).get("cooked",0))
	expect(w.step(1.5,true),"World.step past the finish")
	var t1:=float(w.state.time)
	var claimed:=ok(w,A,"claim_cook",stove,"","claim the finished chowder")
	expect(str(claimed.get("message",""))=="完成了！%s +4"%TITLE and int(claimed.get("yield",0))==4,"claim message and yield 4 (%s)"%str(claimed.get("message","")))
	expect(count(w,A,DISH)==4,"claim gives exactly four portions")
	expect(meals_of(w,A).has(DISH) and pl(w,A).get("meals_discoveries",{}).has(DISH),"claim records the corn_chowder meal discovery")
	expect(int(pl(w,A).get("cooked",0))==cooked_before+1,"cooked counter +1")
	expect(World.cooking_idle(w.state.objects[World.key(stove)]),"stove queue is idle again")
	expect(float(w.state.time)==t1,"claiming does not advance world time")
	refuse(w,A,"claim_cook",stove,"","石灶現在沒有料理","second claim on the empty stove")

# --------------------------------------------------------------- shared table --

func table(w:World,path:String) -> void:
	put(w,A,NEAR) # PRESET
	var t0:=float(w.state.time)
	# A holds the four cooked portions.
	expect(count(w,A,DISH)==4,"alpha carries the four cooked portions to the table")
	setinv(w,A,DISH,3) # PRESET
	refuse(w,A,"serve_chowder",TABLE,"",MSG_SHORT,"serve with three portions")
	setinv(w,A,DISH,4) # PRESET
	refuse(w,B,"serve_chowder",TABLE,"",MSG_SHORT,"serve with none")
	refuse(w,A,"claim_chowder",TABLE,"",MSG_GONE,"claim before anything is served")
	refuse(w,A,"serve_chowder",Vector2i(40,31),"",MSG_PLACE,"serve at a neighbour cell")
	refuse(w,A,"serve_chowder",BOARD,"",MSG_PLACE,"serve at the board")
	refuse(w,A,"serve_chowder",TABLE,"x",MSG_PLACE,"serve with a non-empty extra")
	refuse(w,A,"serve_chowder",TABLE,"4",MSG_PLACE,"serve with a numeric extra")
	put(w,A,Vector2(29.5,20.5),"jinguashi") # PRESET
	refuse(w,A,"serve_chowder",TABLE,"","","serve from Jinguashi")
	refuse(w,A,"claim_chowder",TABLE,"","","claim from Jinguashi")
	put(w,A,NEAR) # PRESET
	# Serve.
	var others:Dictionary={}
	for token:String in [B,C,D,E]:others[token]=bag_of(pl(w,token).inventory)
	var served:=ok(w,A,"serve_chowder",TABLE,"","alpha serves four chowder")
	expect(str(served.get("message",""))==MSG_SERVED,"serve message")
	expect(count(w,A,DISH)==0,"serving removes all four from the bag")
	expect(same(w.state.community.get("chowder"),{"portions":4,"claimed":{}}),"table holds {portions:4, claimed:{}}")
	expect(not w.state.community.has("hotpot") and not w.state.community.has("watermelon"),"serving chowder does not create other dishes")
	for token:String in others:expect(same(bag_of(pl(w,token).inventory),others[token]),"%s bag untouched by the serve"%token.left(16))
	# Second serve while portions remain.
	setinv(w,E,DISH,4) # PRESET
	refuse(w,E,"serve_chowder",TABLE,"",MSG_STILL,"second serve while portions remain")
	# Claims: B has never cooked.
	expect(not meals_of(w,B).has(DISH) and int(pl(w,B).get("cooked",0))==0,"beta never cooked or discovered chowder")
	var claimed:=ok(w,B,"claim_chowder",TABLE,"","beta claims one")
	expect(str(claimed.get("message",""))==MSG_CLAIMED and count(w,B,DISH)==1 and int(w.state.community.chowder.portions)==3,"beta gets one, three left")
	expect(meals_of(w,B).has(DISH) and pl(w,B).get("meals_discoveries",{}).has(DISH) and int(pl(w,B).get("cooked",0))==0,"claiming records the meal discovery for a non-cook")
	refuse(w,B,"claim_chowder",TABLE,"",MSG_AGAIN,"beta claims twice in one round")
	var first:=act(w,C,"claim_chowder",TABLE,"","chowder-claim-gamma")
	expect(bool(first.get("ok",false)) and count(w,C,DISH)==1 and int(w.state.community.chowder.portions)==2,"gamma claims one, two left")
	var replay_before:=var_to_bytes(canon(w.state))
	expect(act(w,C,"claim_chowder",TABLE,"","chowder-claim-gamma")==first and var_to_bytes(canon(w.state))==replay_before,"replayed request id returns the receipt without a second portion")
	expect(w.save() and validates(JSON.parse_string(FileAccess.get_file_as_string(path))),"half-claimed chowder round saves and validates")
	ok(w,D,"claim_chowder",TABLE,"","delta claims one")
	ok(w,A,"claim_chowder",TABLE,"","alpha (the cook) claims one too")
	var meal_round:Dictionary=w.state.community.chowder
	expect(int(meal_round.portions)==0 and meal_round.claimed.size()==4 and meal_round.claimed.has(A) and meal_round.claimed.has(B) and meal_round.claimed.has(C) and meal_round.claimed.has(D),"four distinct claimants empty the round")
	expect(count(w,A,DISH)+count(w,B,DISH)+count(w,C,DISH)+count(w,D,DISH)==4,"conservation: four in, four out")
	refuse(w,E,"claim_chowder",TABLE,"",MSG_GONE,"fifth islander after four claims")
	refuse(w,B,"claim_chowder",TABLE,"",MSG_GONE,"earlier claimant after the round is finished")
	# New round.
	refuse(w,B,"serve_chowder",TABLE,"",MSG_SHORT,"new round still needs four portions")
	ok(w,E,"serve_chowder",TABLE,"","epsilon serves a new round after the old one is finished")
	expect(count(w,E,DISH)==0 and same(w.state.community.chowder,{"portions":4,"claimed":{}}),"new round resets to four portions with no claims")
	ok(w,B,"claim_chowder",TABLE,"","beta claims again in the new round")
	expect(count(w,B,DISH)==2 and int(w.state.community.chowder.portions)==3,"beta now holds two, three left")
	# Hotpot and watermelon are unaffected and share the table.
	var chowder_before:Dictionary=w.state.community.chowder.duplicate(true)
	setinv(w,A,"trout_hotpot",4) # PRESET
	setinv(w,A,"watermelon_platter",4) # PRESET
	ok(w,A,"serve_hotpot",TABLE,"","hotpot served beside the chowder")
	ok(w,A,"serve_watermelon",TABLE,"","watermelon served beside the chowder")
	var community:Dictionary=w.state.community
	expect(same(community.get("hotpot"),{"portions":4,"claimed":{}}) and same(community.get("watermelon"),{"portions":4,"claimed":{}}) and same(community.get("chowder"),chowder_before),"all three dishes on the table at once, chowder untouched")
	expect(count(w,A,"trout_hotpot")==0 and count(w,A,"watermelon_platter")==0,"hotpot and watermelon serves take their own items")
	ok(w,C,"claim_hotpot",TABLE,"","gamma takes hotpot")
	ok(w,C,"claim_watermelon",TABLE,"","gamma takes watermelon")
	ok(w,C,"claim_chowder",TABLE,"","gamma takes chowder too")
	expect(int(community.hotpot.portions)==3 and int(community.watermelon.portions)==3 and int(community.chowder.portions)==2,"each dish counts its own portions")
	expect(count(w,C,"trout_hotpot")==1 and count(w,C,"watermelon_platter")==1 and count(w,C,DISH)==2,"one of each dish for gamma")
	expect(same(community.hotpot.claimed,{C:true}) and same(community.chowder.claimed,{B:true,C:true}),"claims are tracked per dish")
	refuse(w,C,"claim_chowder",TABLE,"",MSG_AGAIN,"gamma cannot take a second chowder")
	refuse(w,B,"serve_hotpot",TABLE,"","餐桌上還有%s，先留給晚點回來的島民。"%str(World.NAMES["trout_hotpot"]),"hotpot still-serving rule unchanged")
	expect(float(w.state.time)==t0,"world time never advanced outside World.step during the table rounds")

# ------------------------------------------------------------------- selling --

func selling(w:World) -> void:
	# Beta sells the two claimed portions at the stall.
	put(w,B,Vector2(43.5,30.5)) # PRESET
	var coins_b:=int(pl(w,B).coins)
	expect(count(w,B,DISH)==2,"beta holds two claimed chowder")
	var sold:=ok(w,B,"sell",STALL,DISH,"beta sells chowder")
	expect(int(pl(w,B).coins)==coins_b+60 and count(w,B,DISH)==0,"two chowder sell for 30 each")
	expect(str(sold.get("message",""))=="售出 2 個，獲得 60 鈴幣","sell message (%s)"%str(sold.get("message","")))
	refuse(w,B,"sell",STALL,DISH,"背包裡沒有這種收成","sell with no chowder left")
	# Alpha sells one earned portion.
	put(w,A,Vector2(43.5,30.5)) # PRESET
	var coins_a:=int(pl(w,A).coins)
	expect(count(w,A,DISH)==1,"alpha holds the one claimed chowder")
	ok(w,A,"sell",STALL,DISH,"alpha sells one chowder")
	expect(int(pl(w,A).coins)==coins_a+30 and count(w,A,DISH)==0,"one chowder sells for 30")
	# Gamma ships the two claimed portions.
	var box:=World.SHIPPING.cell_for(w.state)
	expect(box!=World.SHIPPING.NO_CELL,"shipping box is available")
	put(w,C,Vector2(box)+Vector2(0.5,1.5)) # PRESET
	var coins_c:=int(pl(w,C).coins)
	refuse(w,C,"ship",box,ship_payload(2,58),"預覽金額已變更，請重新確認。","ship with a stale total")
	refuse(w,C,"ship",box,ship_payload(3,90),"持有數量已變更，請重新確認。","ship more than held")
	var shipped:=ok(w,C,"ship",box,ship_payload(2,60),"gamma ships two chowder")
	expect(int(shipped.get("total",0))==60 and int(pl(w,C).coins)==coins_c+60 and count(w,C,DISH)==0,"two chowder ship for 30 each")
	put(w,A,NEAR) # PRESET
	put(w,B,Vector2(38.5,31.5)) # PRESET
	put(w,C,Vector2(40.5,31.5)) # PRESET

# --------------------------------------------------------------------- saves --

func saves(w:World,path:String) -> void:
	expect(w.save(),"final world saves")
	var reloaded:=World.new()
	reloaded.save_path=path
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"fresh World reloads the save")
	expect(same(reloaded.state.get("community"),w.state.get("community")),"community (with chowder) equal after reload")
	expect(same(reloaded.state.community.get("chowder"),{"portions":2,"claimed":{B:true,C:true}}),"chowder round {portions:2, claimed:B,C} after reload")
	for token:String in [A,B,C,D,E]:
		expect(same(bag_of(reloaded.state.players[token].inventory),bag_of(pl(w,token).inventory)),"%s bag equal after reload"%token.left(16))
		expect(same(meals_of(reloaded,token),meals_of(w,token)),"%s meal discoveries equal after reload"%token.left(16))
	refuse(reloaded,B,"claim_chowder",TABLE,"",MSG_AGAIN,"claims survive reload")
	setinv(reloaded,B,DISH,4) # PRESET
	refuse(reloaded,B,"serve_chowder",TABLE,"",MSG_STILL,"leftover portions survive reload")
	var text:=FileAccess.get_file_as_string(path)
	var base:Variant=JSON.parse_string(text)
	if not expect(base is Dictionary,"saved world parses"):return
	expect(validates(base),"control: saved world with three dishes validates")
	var control:Dictionary=base.duplicate(true)
	control.community={"table":"39,30","chowder":{"portions":0,"claimed":{A:true,B:true,C:true,D:true}}}
	expect(validates(control),"control: a fully claimed chowder round validates")
	control.community={"table":"39,30","chowder":{"portions":4,"claimed":{}}}
	expect(validates(control),"control: a fresh chowder round alone validates")
	var fixture:=temp_path("fixture")
	expect(write_json(fixture,base) and World.new().load_world(fixture),"control fixture loads")
	var probe:=World.new()
	var pristine:=var_to_bytes(canon(probe.state))
	var labels:=["portions not four minus claimed","portions above four","negative portions","unknown claimant",
		"claimed value false","total on chowder","total six on chowder","unknown dish key","chowder while table is empty",
		"chowder not a dictionary","portions string","claimed missing"]
	for label:String in labels:
		var bad:=tampered(base,label)
		expect(write_json(fixture,bad),"write tampered fixture: "+label)
		expect(not validates(bad),"schema rejects: "+label)
		expect(not probe.load_world(fixture),"load_world rejects: "+label)
		expect(var_to_bytes(canon(probe.state))==pristine,"rejected load leaves the world untouched: "+label)

func tampered(base:Dictionary,label:String) -> Dictionary:
	presets+=1 # PRESET: tampered save fixture
	var s:Dictionary=base.duplicate(true)
	var community:Dictionary=s.community
	match label:
		"portions not four minus claimed":community["chowder"]={"portions":3,"claimed":{B:true,C:true}}
		"portions above four":community["chowder"]={"portions":5,"claimed":{}}
		"negative portions":community["chowder"]={"portions":-1,"claimed":{A:true,B:true,C:true,D:true,E:true}}
		"unknown claimant":community["chowder"]={"portions":1,"claimed":{B:true,C:true,"chowder-stranger-token":true}}
		"claimed value false":community["chowder"]={"portions":2,"claimed":{B:false,C:true}}
		"total on chowder":community["chowder"]={"portions":2,"claimed":{B:true,C:true},"total":4}
		"total six on chowder":community["chowder"]={"portions":6,"claimed":{},"total":6}
		"unknown dish key":community["soup"]={"portions":4,"claimed":{}}
		"chowder while table is empty":s.community={"table":"","chowder":{"portions":4,"claimed":{}}}
		"chowder not a dictionary":community["chowder"]=4
		"portions string":community["chowder"]={"portions":"2","claimed":{B:true,C:true}}
		"claimed missing":community["chowder"]={"portions":4,"claimers":{}}
	return s
