extends SceneTree

const World=preload("res://scripts/world.gd")
const Rules=World.LANTERN_STROLL
const Schema=preload("res://scripts/save_schema.gd")
var checks:=0
var failures:=0
var sequence:=0

func assert_case(ok:bool,message:String)->void:
	checks+=1
	if ok:return
	failures+=1
	push_error(message)

func act(world:World,actor:String,tile:Vector2i,command:String,place_here:=true)->bool:
	if place_here:
		world.state.players[actor].x=tile.x+0.5
		world.state.players[actor].y=tile.y+0.5
	sequence+=1
	return world.act(actor,"stroll-qa-%d"%sequence,Rules.ACTION,tile,command).ok

func _initialize()->void:
	var world:=World.new()
	for who:String in ["walker","visitor"]:
		world.add_player(who,who)
	var actor:="walker"
	var sign:=Rules.SIGN
	var first:Vector2i=Rules.SITES.grove.cell
	assert_case(not act(world,actor,sign,"start"),"Picnic gates activity")
	world.state.picnic=true
	assert_case(not act(world,actor,first,"start"),"Exact sign required")
	assert_case(not act(world,actor,sign,"start",false),"Distant request rejected")
	var obstruction:=World.key(first)
	world.state.objects[obstruction]={"type":"wall","owner":actor}
	assert_case(not act(world,actor,sign,"start"),"Cannot launch a blocked route")
	world.state.objects.erase(obstruction)
	assert_case(act(world,actor,sign,"start"),"Launch on a walkable route")
	var round:=Rules.public_view(world.state)
	assert_case(round.remaining==300 and Rules._valid_route(round.route),"Route is a 300-second connected tour")
	assert_case(act(world,actor,sign,"companion:1"),"Optional solo companion")
	assert_case(not act(world,"visitor",sign,"join:01"),"Non-canonical round refused")
	assert_case(act(world,"visitor",first,"join:1"),"Visitor joins at checkpoint")
	assert_case(not act(world,actor,sign,"companion:1"),"Companion is a solo option")
	assert_case(not act(world,actor,sign,"stamp:1:grove:safe"),"Wrong tile rejected")
	assert_case(not act(world,actor,first,"stamp:1:grove:freeform"),"Only preset wishes")
	for id:String in Rules.ORDER:
		assert_case(act(world,actor,Rules.SITES[id].cell,"stamp:1:%s:safe"%id),"Stamp %s"%id)
		assert_case(not act(world,actor,Rules.SITES[id].cell,"stamp:1:%s:friends"%id),"No duplicate stamp %s"%id)
	assert_case(Rules.view(world.state,actor).tickets==1 and Rules.view(world.state,"visitor").stamps.is_empty(),"One private ticket for three stamps")
	assert_case(act(world,actor,first,"leave:1") and not Rules.view(world.state,actor).joined,"Leave anywhere")
	assert_case(act(world,actor,first,"join:1") and Rules.view(world.state,actor).tickets==1,"Rejoin does not grant more tickets")
	assert_case(act(world,actor,sign,"redeem"),"Ticket trades for decoration")
	assert_case(not act(world,actor,sign,"redeem"),"Duplicate redemption refused")
	assert_case(world.state.players[actor].inventory.get(Rules.PRIZE,0)==1,"Exactly one kit")
	assert_case(world.state.players[actor].coins==120,"Coins unchanged")
	var copy:Dictionary=JSON.parse_string(JSON.stringify(world.state))
	assert_case(Schema.validate(copy,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validates and preserves the current route")
	copy=JSON.parse_string(JSON.stringify(world.state))
	copy[Rules.KEY].route[1]="48,42"
	assert_case(not Schema.validate(copy,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save rejects a broken route")
	copy=JSON.parse_string(JSON.stringify(world.state))
	copy.players[actor][Rules.KEY].spent=2
	assert_case(not Schema.validate(copy,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save rejects overspent tickets")
	assert_case(world.step(301.0,true,false),"World finishes walk at deadline")
	assert_case(Rules.public_view(world.state).phase=="results" and not Rules.view(world.state,actor).joined,"End returns lantern")
	assert_case(Rules.view(world.state,"visitor").tickets==0,"Unfinished route earns no ticket")
	assert_case(act(world,actor,sign,"start") and Rules.view(world.state,actor).stamps.is_empty(),"Next round starts with empty route")
	assert_case(Rules.view(world.state,actor).earned==1 and not act(world,actor,first,"stamp:1:grove:safe"),"Credit persists and old actions refuse")
	print("LANTERN_STROLL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
