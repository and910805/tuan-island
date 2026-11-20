extends SceneTree

const World=preload("res://scripts/world.gd")
const Trial=World.GUARDIAN_TRIAL
const Guardian=World.GUARDIAN
const A:="guardian-trial-first"
const B:="guardian-trial-second"
var world:=World.new()
var checks:=0
var failures:=0

func _initialize()->void:
	var path:="user://guardian-trial-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	world.state.board=true
	world.state.picnic=true
	world.state.mine_depths.unlocked=4
	world.state.mine_depths.pumped=24
	for token:String in [A,B]:
		world.add_player(token,"石像洞島民")
		world.state.players[token].merge({"region":Guardian.REGION,"x":34.5,"y":11.6},true)
	var initial_sand:=amount(A)
	expect(not act(A,"life",Trial.START).ok,"Life mode keeps the windbell puzzle")
	world.state.world_mode="adventure"
	expect(not act(A,"early",Trial.FINISH).ok,"Adventurers cannot skip the strikes")
	expect(act(A,"miss",Trial.START).ok,"The first strike is telegraphed")
	var warning:=world.guardian_trial_view(A)
	expect(warning.phase==Trial.Phase.WARNING and warning.bounds==[33.5,10.0,2.0,4.0],"The initial targeted column covers the actor")
	expect(world.guardian_trial_view(B).is_empty(),"The other player has no hazard in their view")
	advance(11)
	expect(world.guardian_trial_view(A).get("phase")==Trial.Phase.MISSED,"Standing in the warning area is a miss")
	expect(amount(A)==initial_sand and not world.state.players[A].has(World.GUARDIAN_FIELD),"Missing spends nothing and grants no progress")
	expect(act(A,"retry",Trial.START).ok,"The player can safely retry")
	walk(A,Vector2.LEFT,6)
	expect(position(A).x<33.34,"The actual room has an open side lane")
	advance(11)
	expect(world.guardian_trial_view(A).get("phase")==Trial.Phase.IMPACT,"The first strike lands outside the player")
	advance(4)
	warning=world.guardian_trial_view(A)
	expect(warning.phase==Trial.Phase.WARNING and warning.attack==1 and warning.bounds[2]==Trial.ARENA.size.x and warning.bounds[3]==Trial.WIDTH,"The second warning is perpendicular")
	walk(A,Vector2.DOWN,7)
	expect(position(A).y>12.76,"The actual room has an open rear lane")
	advance(14)
	expect(world.guardian_trial_view(A).get("phase")==Trial.Phase.SAFE,"Two successful dodges end the attack")
	expect(not act(A,"far-finish",Trial.FINISH).ok,"The player must return to the guardian")
	walk(A,Vector2.UP,7)
	walk(A,Vector2.RIGHT,6)
	expect(act(A,"finish",Trial.FINISH).ok,"Return to wake the statue")
	expect(world.guardian_trial_view(A).is_empty(),"A completed encounter removes its transient state")
	var reward:=world.act(A,"claim","guardian_claim",Guardian.GUARDIAN)
	expect(reward.ok and amount(A)==initial_sand+Guardian.REWARD_COUNT,"Both paths use the same two-crystal-sand gift")
	expect(not world.act(A,"again","guardian_claim",Guardian.GUARDIAN).ok and amount(A)==initial_sand+Guardian.REWARD_COUNT,"The gift is unique")
	expect(act(B,"leave",Trial.START).ok,"Second player can begin a separate round")
	world.guardian_trial_forget(B)
	expect(world.guardian_trial_view(B).is_empty(),"The disconnect hook discards the temporary round")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup,"Original save reopens")
	expect(saved.state.players[A][World.GUARDIAN_FIELD].claimed and saved.state.players[A].inventory[Guardian.REWARD_ITEM]==initial_sand+Guardian.REWARD_COUNT,"The exact reward is retained")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("STONE_GUARDIAN_TRIAL checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func act(token:String,id:String,extra:String)->Dictionary:
	return world.act(token,id,Trial.KEY,Guardian.GUARDIAN,extra)

func position(token:String)->Vector2:
	var player:Dictionary=world.state.players[token]
	return Vector2(player.x,player.y)

func amount(token:String)->int:
	return int(world.state.players[token].inventory.get(Guardian.REWARD_ITEM,0))

func walk(token:String,direction:Vector2,ticks:int)->void:
	for tick in ticks:world.move_player(token,direction,0.067)

func advance(ticks:int)->void:
	for tick in ticks:expect(world.step(0.2,true,false),"The production clock advances")

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
