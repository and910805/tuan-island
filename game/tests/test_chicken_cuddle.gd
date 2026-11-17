extends SceneTree
const World=preload("res://scripts/world.gd")
const Care=World.CHICKEN_CUDDLE
const Schema=preload("res://scripts/save_schema.gd")
var checks:=0
var failures:=0
const ONE:="chicken-cuddle-one"
const TWO:="chicken-cuddle-two"
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func valid(data:Dictionary)->bool:
	return Schema.validate(data,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
func _initialize()->void:
	var world:=World.new()
	for token in [ONE,TWO]:
		world.add_player(token,token)
		world.state.players[token].x=45.5
		world.state.players[token].y=35.5
	var bag:Dictionary=world.state.players[ONE].inventory.duplicate(true)
	expect(not world.act(ONE,"wrong","chicken_hug",Vector2i.ZERO).ok,"Must use the actual chicken station")
	expect(world.act(ONE,"hug","chicken_hug",World.CHICKEN_CELL).ok,"Chicken can be cuddled with normal early-game stock")
	expect(Care.holder(world.state,world.active_tokens)==ONE and world.state.animal.bond==1,"Exactly one shared holder and one care bond")
	expect(world.state.players[ONE].inventory==bag and world.state.animal.egg_ready==-1.0,"No inventory or egg production award")
	expect(world.act(ONE,"hug","chicken_hug",World.CHICKEN_CELL).ok and world.state.animal.bond==1,"Same receipt never adds another bond")
	expect(not world.act(TWO,"race","chicken_hug",World.CHICKEN_CELL).ok,"Second person cannot duplicate shared hen")
	expect(not world.act(TWO,"steal","chicken_release",Vector2i.ZERO).ok,"Other person cannot release your hen")
	expect(not world.act(ONE,"tools","hoe",Vector2i(44,35)).ok,"Authoritative hand-tool guard")
	var before:=Vector2(world.state.players[ONE].x,world.state.players[ONE].y)
	world.move_player(ONE,Vector2.DOWN,0.1)
	expect(Vector2(world.state.players[ONE].x,world.state.players[ONE].y)!=before,"Carrying does not disable normal collision-checked movement")
	expect(world.act(ONE,"release","chicken_release",Vector2i.ZERO).ok and Care.holder(world.state).is_empty(),"Owner can return hen before timeout")
	expect(not world.act(ONE,"cooldown","chicken_hug",World.CHICKEN_CELL).ok and not world.act(ONE,"pet-cooldown","pet",World.CHICKEN_CELL).ok,"Release cannot bypass shared pet cooldown")
	expect(world.step(30.1,true),"Advance normal world time")
	expect(world.act(TWO,"second","chicken_hug",World.CHICKEN_CELL).ok,"Friend can care after cooldown")
	expect(world.step(Care.SECONDS+0.1,true) and Care.holder(world.state).is_empty(),"Eight seconds automatically returns hen")
	expect(not world.state.animal.has(Care.FIELD),"Timeout clears marker in the same atomic tick")
	world.step(30.1,true)
	world.act(ONE,"offline-hug","chicken_hug",World.CHICKEN_CELL)
	world.active_tokens.erase(ONE)
	expect(Care.holder(world.state,world.active_tokens).is_empty() and world.step(0.1,true),"Inactive owner returns hen without another reward")
	expect(not world.state.animal.has(Care.FIELD),"Inactive carry marker is cleaned by atomic tick")
	world.active_tokens[ONE]=true
	world.step(30.1,true)
	world.act(ONE,"save-hug","chicken_hug",World.CHICKEN_CELL)
	expect(valid(world.state.duplicate(true)),"New optional marker validates")
	var saved:="user://cuddle-save-%d.json"%OS.get_process_id()
	world.save_path=saved
	expect(world.save(),"Save during hug")
	var loaded:=World.new()
	expect(loaded.load_world(saved) and not loaded.state.animal.has(Care.FIELD),"Restart safely returns hen to coop")
	expect(loaded.state.animal.bond==world.state.animal.bond and loaded.state.animal.last_pet==world.state.animal.last_pet,"Restart preserves care bond and cooldown")
	for invalid in [false,17,{},"unknown-profile"]:
		var bad:Dictionary=world.state.duplicate(true)
		bad.animal[Care.FIELD]=invalid
		expect(not valid(bad),"Invalid holder rejected: "+str(invalid))
	world.act(ONE,"release-for-failure","chicken_release",Vector2i.ZERO)
	world.step(30.1,true)
	var copy:=world.state.duplicate(true)
	world.save_path=OS.get_environment("TEMP") # Existing directory forces a safe save refusal.
	expect(not world.act(ONE,"failed-save","chicken_hug",World.CHICKEN_CELL).ok and world.state==copy,"Failed save rolls back complete hold, bond and receipt")
	var travel_world:=World.new()
	travel_world.add_player(ONE,"旅人")
	travel_world.state.picnic=true
	travel_world.state.players[ONE].x=45.5
	travel_world.state.players[ONE].y=35.5
	travel_world.act(ONE,"travel-hug","chicken_hug",World.CHICKEN_CELL)
	var exit_cell:Vector2i=World.REGIONS.exit_cell("home")
	travel_world.state.players[ONE].x=exit_cell.x+0.5
	travel_world.state.players[ONE].y=exit_cell.y+0.5
	expect(travel_world.act(ONE,"travel-away","travel",exit_cell,World.REGIONS.LANYANG).ok and not travel_world.state.animal.has(Care.FIELD),"Actual travel action returns hen in the same saved transaction")
	var egg_world:=World.new()
	for token in [ONE,TWO]:
		egg_world.add_player(token,"照料者")
		egg_world.state.players[token].x=45.5
		egg_world.state.players[token].y=35.5
	egg_world.state.animal.egg_ready=0.1 # Existing incubation is a test fixture.
	egg_world.act(ONE,"egg-hug","chicken_hug",World.CHICKEN_CELL)
	egg_world.step(0.2,true)
	expect(egg_world.act(TWO,"egg-claim","egg",World.CHICKEN_CELL).ok and int(egg_world.state.players[TWO].inventory.get("egg",0))==1,"Existing incubation and another player's egg collection continue during hug")
	expect(Care.holder(egg_world.state,egg_world.active_tokens)==ONE,"Collecting an egg does not duplicate or release held hen")
	var step_world:=World.new()
	step_world.add_player(ONE,"照料者")
	step_world.state.players[ONE].x=45.5
	step_world.state.players[ONE].y=35.5
	step_world.act(ONE,"atomic-hug","chicken_hug",World.CHICKEN_CELL)
	var before_tick:=step_world.state.duplicate(true)
	step_world.save_path=OS.get_environment("TEMP")
	expect(not step_world.step(8.1,true) and step_world.state==before_tick,"Expiry save failure restores the complete pre-tick world")
	step_world.save_path=""
	expect(step_world.step(8.1,true) and not step_world.state.animal.has(Care.FIELD) and step_world.state.animal.bond==1,"Recovered expiry removes marker once without another reward")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(saved+suffix):DirAccess.remove_absolute(saved+suffix)
	print("CHICKEN_CUDDLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
