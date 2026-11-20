extends SceneTree

const World=preload("res://scripts/world.gd")
const Spore=World.SHY_SPORES
const Shy=World.SHY
const A:="shy-spore-player-a"
const B:="shy-spore-player-b"
var world:=World.new()
var checks:=0
var failures:=0

func _initialize()->void:
	var path:="user://shy-spore-%d.json"%Time.get_ticks_usec()
	world.save_path=path
	world.state.board=true
	world.state.picnic=true
	world.state.mine_depths.unlocked=2
	world.add_player(A,"礦洞島民")
	world.add_player(B,"晚來島民")
	for token:String in [A,B]:
		world.state.players[token].merge({"region":Shy.REGION,"x":46.5,"y":22.5},true)
	var initial_fiber:=int(world.state.players[A].inventory.get(Shy.REWARD_ITEM,0))
	expect(not interact(A,"life",Spore.ENTER).ok,"Life mode keeps the quiet approach")
	world.state.world_mode="adventure"
	expect(not interact(A,"early",Spore.FINISH).ok,"A player cannot skip the spores")
	expect(interact(A,"miss",Spore.ENTER).ok,"First warning starts")
	expect(world.shy_spore_view(A).get("lane")==46.5,"First spore uses the player's current side")
	expect(world.shy_spore_view(B).is_empty(),"A friend's route is independent")
	advance(12)
	expect(world.shy_spore_view(A).get("phase")==Spore.Phase.MISSED,"A spore catches the player if they stay in the lane")
	expect(not interact(A,"fail-claim",Spore.FINISH).ok,"A hit cannot qualify for the gift")
	expect(int(world.state.players[A].inventory.get(Shy.REWARD_ITEM,0))==initial_fiber and not world.state.players[A].has(Spore.FIELD),"Failure has no lasting cost or progress")
	expect(interact(A,"try-again",Spore.ENTER).ok,"A fresh attempt can begin immediately")
	walk(A,Vector2.LEFT)
	expect(position(A).x<45.65,"The side cave has enough room to dodge the first lane")
	advance(22)
	expect(world.shy_spore_view(A).get("phase")==Spore.Phase.WARNING and world.shy_spore_view(A).get("lane")==45.5,"Second warning uses the opposite side")
	walk(A,Vector2.RIGHT)
	expect(position(A).x>46.35,"The path to the other side remains open")
	advance(22)
	expect(world.shy_spore_view(A).get("phase")==Spore.Phase.FINISHED,"Both spores pass safely")
	expect(interact(A,"finish",Spore.FINISH).ok,"See the mushroom after both spores")
	expect(world.shy_spore_view(A).is_empty(),"Completion removes the transient state")
	expect(world.act(A,"claim",Shy.CLAIM_ACTION,Shy.MUSHROOM).ok,"Adventure awards the original gift")
	expect(not world.act(A,"claim-again",Shy.CLAIM_ACTION,Shy.MUSHROOM).ok,"The gift cannot be repeated")
	expect(interact(B,"friend-start",Spore.ENTER).ok,"Second player can start a separate round")
	world.shy_forget(B)
	expect(world.shy_spore_view(B).is_empty(),"Disconnect clears a round and does not touch the other player")
	var restored:=World.new()
	expect(restored.load_world(path) and not restored.recovered_from_backup,"Reload the original save")
	var player:Dictionary=restored.state.players[A]
	expect(player[Spore.FIELD].claimed and player.inventory[Shy.REWARD_ITEM]==initial_fiber+Shy.REWARD_COUNT,"The exact original reward survives reconnecting")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHY_SPORES checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func interact(token:String,id:String,extra:String)->Dictionary:
	return world.act(token,id,Spore.ACTION,Shy.MUSHROOM,extra)

func position(token:String)->Vector2:
	var player:Dictionary=world.state.players[token]
	return Vector2(player.x,player.y)

func walk(token:String,direction:Vector2)->void:
	for tick in 4:world.move_player(token,direction,0.067)

func advance(ticks:int)->void:
	for tick in ticks:expect(world.step(0.2,true,false),"World clock advances normally")

func expect(accepted:bool,message:String)->void:
	checks+=1
	if not accepted:
		failures+=1
		push_error(message)
