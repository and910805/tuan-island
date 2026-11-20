extends SceneTree

const World=preload("res://scripts/world.gd")
const Porter=World.PORTER
const ALPHA:="porter-test-alpha"
const BETA:="porter-test-beta"
var checks:=0
var failures:=0
var world:World

func _initialize()->void:
	var path:="user://porter-world-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(ALPHA,"山城島民")
	world.add_player(BETA,"同行島民")
	outcome(ALPHA,"locked",0,false,"Other floors cannot start the escort")
	world.state.picnic=true
	world.state.board=true
	world.state.mine_depths.unlocked=6
	world.state.mine_depths.pumped=24
	place(ALPHA,Porter.DELIVERY)
	place(BETA,Porter.START)
	world.switch_region(Porter.REGION)
	var crate_key:=World.key(Porter.CRATE)
	world.state.objects[crate_key]={"type":"chest","owner":ALPHA,"items":{}}
	world.switch_region(World.REGIONS.HOME)
	expect(world.save(),"Legacy world with an occupied route saves")
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"Legacy world without Porter progress loads from primary")
	world=reloaded
	outcome(BETA,"occupied",0,false,"Existing furniture keeps the encounter hidden")
	expect(world.act(ALPHA,"old-chest","remove",Porter.CRATE).ok,"Old furniture can still be removed")
	expect(not world.act(ALPHA,"new-chest","build",Porter.CRATE,"chest").ok,"New furniture cannot occupy the escort route")
	world.switch_region(Porter.REGION)
	var crate_center:=Vector2(Porter.CRATE)+Vector2(0.5,0.5)
	expect(not world.can_stand(crate_center) and world.can_stand(Porter.DELIVERY),"The supply crate is solid and its access is open")
	place(ALPHA,crate_center)
	world.move_player(ALPHA,Vector2.LEFT,0.05)
	var walker:Dictionary=world.state.players[ALPHA]
	expect(Vector2(walker.x,walker.y).distance_to(crate_center)>0.8,"A legacy player saved on the crate can step out")

	place(ALPHA,Porter.START)
	var start:=outcome(ALPHA,"begin",0,true,"Start at the mouse")
	expect(outcome(ALPHA,"begin",0,true,"Replaying a stored request is safe")==start,"Replay returns the same reply")
	outcome(ALPHA,"wrong-order",2,false,"Cannot skip the bend")
	expect(progress(BETA)==Porter.Stage.WAITING,"The second player's progress is independent")
	place(ALPHA,Porter.MIDDLE)
	outcome(ALPHA,"wait",1,true,"Wait at the bend")

	reloaded=World.new()
	expect(reloaded.load_world(path) and not reloaded.recovered_from_backup,"Mid-route main file loads")
	world=reloaded
	expect(progress(ALPHA)==Porter.Stage.TO_CRATE,"Escort resumes from the confirmed waypoint")
	place(ALPHA,Porter.DELIVERY)
	outcome(ALPHA,"deliver",2,true,"Drop the cargo at the crate")
	expect(int(inventory(ALPHA).get(Porter.REWARD_ITEM,0))==0,"Delivering does not pay before claiming")
	inventory(ALPHA)[Porter.REWARD_ITEM]=World.ITEM_CATALOG.saved_count_limit(Porter.REWARD_ITEM)
	outcome(ALPHA,"full",3,false,"A full bag leaves the gift pending")
	expect(progress(ALPHA)==Porter.Stage.DELIVERED,"Failed claim preserves the completed delivery")
	inventory(ALPHA).erase(Porter.REWARD_ITEM)
	outcome(ALPHA,"claim",3,true,"Claim the two ore")
	outcome(ALPHA,"claim",3,true,"Replay the same claim")
	outcome(ALPHA,"claim-again",3,false,"A fresh claim cannot pay twice")
	expect(int(inventory(ALPHA).get(Porter.REWARD_ITEM,0))==Porter.REWARD_COUNT,"Exactly one gift credited")
	expect(inventory(BETA).get(Porter.REWARD_ITEM,0)==0,"No other bag receives the gift")
	reloaded=World.new()
	expect(reloaded.load_world(path) and reloaded.state.players[ALPHA].get(Porter.FIELD)==Porter.Stage.REWARDED,"Claim status survives cold load")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("LOST_PORTER_MOUSE_WORLD checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func place(token:String,position:Vector2)->void:
	var player:Dictionary=world.state.players[token]
	player.region=Porter.REGION
	player.x=position.x
	player.y=position.y

func outcome(token:String,id:String,stage:int,expected:bool,message:String)->Dictionary:
	var step:=Porter.next_step(stage)
	var result:=world.act(token,id,step.action,step.cell)
	expect(result.ok==expected,message+" · "+str(result.message))
	return result

func progress(token:String)->int:
	return int(world.state.players[token].get(Porter.FIELD,Porter.Stage.WAITING))

func inventory(token:String)->Dictionary:
	return world.state.players[token].inventory

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
