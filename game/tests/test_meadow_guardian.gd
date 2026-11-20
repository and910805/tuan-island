extends SceneTree

const World=preload("res://scripts/world.gd")
const Meadow=World.MEADOW
const A:="meadow-fixture-a"
const B:="meadow-fixture-b"
var path:="user://meadow-fixture-%d.json"%Time.get_ticks_usec()
var checks:=0
var failures:=0
var world:=World.new()

func _initialize()->void:
	world.save_path=path
	world.add_player(A,"大廳島民")
	world.add_player(B,"晚到島民")
	expect(not act(A,"locked",Meadow.OFFER,Meadow.TABLES[0]).ok,"Locked floor rejects offerings")
	world.state.picnic=true
	world.state.board=true
	world.state.mine_depths.unlocked=Meadow.DEPTH
	world.state.mine_depths.pumped=24
	place(A,Vector2(20.5,28.5))
	place(B,Vector2(26.5,28.5))
	bag(A)[Meadow.ITEM]=3
	world.switch_region(Meadow.REGION)
	var old_cell:Vector2i=Meadow.TABLES[0]
	world.state.objects[World.key(old_cell)]={"type":"chest","owner":A,"items":{}}
	world.switch_region(World.REGIONS.HOME)
	expect(world.save(),"Existing save holds a cabinet at a future offering table")
	reload_world()
	expect(not act(A,"occupied",Meadow.OFFER,old_cell).ok,"Legacy furniture hides the encounter")
	expect(world.act(A,"clear","remove",old_cell).ok,"Its owner can remove legacy furniture")
	expect(not world.act(A,"place","build",old_cell,"chest").ok,"The clear site is reserved")
	world.switch_region(Meadow.REGION)
	for cell:Vector2i in Meadow.FOOTPRINT:
		expect(world.blocked(cell),"The footprint is solid at "+str(cell))
	place(A,Vector2(old_cell)+Vector2(0.5,0.5))
	world.move_player(A,Vector2.DOWN,0.05)
	expect(world.can_stand(position(A)),"A legacy player can step off a newly occupied tile")
	world.switch_region(World.REGIONS.HOME)
	expect(not act(A,"far-table",Meadow.OFFER,Meadow.TABLES[2]).ok,"Cannot place an offering across the chamber")
	expect(not act(B,"short",Meadow.OFFER,Meadow.TABLES[2]).ok,"Requires a radish from the player's own bag")
	expect(record(A)==0 and record(B)==0 and bag(A).get(Meadow.ITEM)==3,"Rejection leaves progress and belongings intact")

	expect(act(A,"first",Meadow.OFFER,old_cell).ok and record(A)==1 and bag(A).get(Meadow.ITEM)==2,"First table takes exactly one radish")
	expect(act(A,"first",Meadow.OFFER,old_cell).ok and bag(A).get(Meadow.ITEM)==2,"A retried request spends only once")
	expect(not act(A,"duplicate",Meadow.OFFER,old_cell).ok,"A different request cannot offer twice to the same table")
	place(A,Vector2(24.4,26.25))
	expect(not act(A,"early",Meadow.CLAIM,Meadow.CENTER).ok,"Claim requires all three offerings")
	reload_world()
	expect(record(A)==1 and record(B)==0,"Saved progress resumes and stays personal")
	for index:int in [2,1]:
		var cell:Vector2i=Meadow.TABLES[index]
		place(A,Vector2(cell)+Vector2(0.5,1.5))
		expect(act(A,"offer-%d"%index,Meadow.OFFER,cell).ok,"Table can be completed out of order")
	expect(record(A)==Meadow.ALL_TABLES and bag(A).get(Meadow.ITEM)==0,"Three tables ready, three radishes spent")
	expect(not act(A,"distant-claim",Meadow.CLAIM,Meadow.CENTER).ok,"Cannot claim from behind the central table")
	place(A,Vector2(24.4,26.25))
	bag(A)["gold_ore"]=World.ITEM_CATALOG.saved_count_limit("gold_ore")
	expect(not act(A,"full",Meadow.CLAIM,Meadow.CENTER).ok,"Full bag defers reward")
	expect(record(A)==Meadow.ALL_TABLES and not bag(A).has("crystal_sand"),"Full bag does not partly pay or consume the claim")
	bag(A).erase("gold_ore")
	expect(act(A,"claim",Meadow.CLAIM,Meadow.CENTER).ok,"The guardian gives the reward")
	expect(act(A,"claim",Meadow.CLAIM,Meadow.CENTER).ok,"Claim request can be retried")
	expect(not act(A,"second-claim",Meadow.CLAIM,Meadow.CENTER).ok,"A new request cannot claim again")
	expect(record(B)==0 and not bag(B).has("gold_ore"),"The friend keeps their own progress and bag")
	reload_world()
	expect(record(A)==Meadow.CLAIMED,"Claim survives cold load")
	for item:String in Meadow.REWARD:
		expect(bag(A).get(item)==Meadow.REWARD[item],"Exactly the intended reward survives reload: "+item)
	test_adventure()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MEADOW_GUARDIAN checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func test_adventure()->void:
	const Trial=World.MEADOW_ADVENTURE
	expect(not world.act(B,"wrong-mode",Trial.ACTION,Meadow.CENTER,Trial.WAKE).ok,"The host refuses adventure actions in life mode")
	world.state.world_mode="adventure"
	world.add_player(A,"大廳島民")
	world.add_player(B,"晚到島民")
	world.state.players[A].erase(Meadow.FIELD)
	place(A,Vector2(24.5,26.5))
	place(B,Vector2(22.5,26.5))
	expect(world.act(A,"wake-missed",Trial.ACTION,Meadow.CENTER,Trial.WAKE).ok,"A nearby player can start an adventure round")
	for tick in 7:expect(world.step(0.5,true,false),"Time advances while the adventurers wait")
	expect(world.meadow_adventure_view(A).is_empty(),"Players caught by the pulse can retry")
	expect(world.act(A,"wake-retry",Trial.ACTION,Meadow.CENTER,Trial.WAKE).ok,"Host starts another round")
	place(A,Vector2(20.5,28.5))
	place(B,Vector2(26.5,28.5))
	for tick in 7:expect(world.step(0.5,true,false),"Time advances while the team is clear")
	expect(world.meadow_adventure_view(A).get("phase")==Trial.Phase.LANTERNS,"Host clock opens the lantern phase")
	expect(world.act(A,"light-zero",Trial.ACTION,Meadow.TABLES[0],Trial.LIGHT).ok,"First player lights one lantern")
	expect(world.act(B,"light-two",Trial.ACTION,Meadow.TABLES[2],Trial.LIGHT).ok,"Second player lights one lantern")
	place(A,Vector2(23.5,28.5))
	expect(world.act(A,"light-one",Trial.ACTION,Meadow.TABLES[1],Trial.LIGHT).ok,"First player lights the last lantern")
	place(A,Vector2(24.5,26.5))
	place(B,Vector2(22.5,26.5))
	expect(world.act(A,"calm-a",Trial.ACTION,Meadow.CENTER,Trial.CALM).ok,"First player calms the guardian")
	expect(record(A)==0 and record(B)==0,"Only the complete team earns the claim")
	expect(world.act(B,"calm-b",Trial.ACTION,Meadow.CENTER,Trial.CALM).ok,"Second player completes the finale")
	expect(world.meadow_adventure_view(A).is_empty(),"The completed event releases the room")
	reload_world()
	expect(record(A)==Meadow.ALL_TABLES and record(B)==Meadow.ALL_TABLES,"Both reward claims commit to the same save")
	expect(act(B,"team-claim",Meadow.CLAIM,Meadow.CENTER).ok and bag(B).get("gold_ore")==Meadow.REWARD.gold_ore,"Adventure pays the same reward as the offerings")

func reload_world()->void:
	var copy:=World.new()
	expect(copy.load_world(path) and not copy.recovered_from_backup,"Loads primary save")
	world=copy

func position(token:String)->Vector2:
	var p:Dictionary=world.state.players[token]
	return Vector2(p.x,p.y)

func place(token:String,at:Vector2)->void:
	world.state.players[token].merge({"region":Meadow.REGION,"x":at.x,"y":at.y},true)

func record(token:String)->int:
	return int(world.state.players[token].get(Meadow.FIELD,0))

func bag(token:String)->Dictionary:
	return world.state.players[token].inventory

func act(token:String,id:String,action:String,tile:Vector2i)->Dictionary:
	return world.act(token,id,action,tile)

func expect(accepted:bool,label:String)->void:
	checks+=1
	if not accepted:
		failures+=1
		push_error(label)
