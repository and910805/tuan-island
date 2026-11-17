extends SceneTree
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0
var seq:=0
var w

func expect(value:bool,description:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL "+description)

func act(action:String,p:Vector2i,extra:String="",token:String="alice") -> Dictionary:
	seq+=1
	return w.act(token,"test-%d"%seq,action,p,extra)

func _initialize() -> void:
	w=World.new()
	w.add_player("alice","阿米")
	w.add_player("bob","小豆")
	var p:=Vector2i(38,34)
	expect(act("hoe",p).ok,"till nearby ground")
	expect(not act("hoe",p).ok,"cannot retill existing plot")
	expect(act("seed",p,"radish").ok,"sow seed")
	expect(w.state.players.alice.inventory.radish_seed==4,"exactly one seed spent")
	w.step(100,true)
	expect(w.state.crops[World.key(p)].growth==0,"dry crop does not grow")
	expect(act("water",p).ok,"water crop")
	expect(act("plot_harvest_access",p,"owner","bob").ok==false,"Visitor cannot change a plot's permission")
	expect(act("plot_harvest_access",p,"owner").ok,"Owner may lock harvest")
	w.step(100,false)
	expect(w.state.crops[World.key(p)].growth==0,"empty world pauses")
	w.step(91,true)
	expect(not act("harvest",p,"","bob").ok,"Private crop refuses visitor harvest")
	expect(act("plot_harvest_access",p,"island").ok,"Owner can restore shared harvest")
	var result:Dictionary=w.act("alice","one-harvest","harvest",p)
	expect(result.ok,"mature crop harvested")
	expect(w.state.players.alice.inventory.radish==1,"harvest reward")
	w.act("alice","one-harvest","harvest",p)
	expect(w.state.players.alice.inventory.radish==1,"retry does not duplicate")
	expect(not act("harvest",p,"","bob").ok,"another player cannot harvest twice")
	expect(not act("build",Vector2i(2,2),"wall").ok,"out of range denied")
	expect(not act("build",Vector2i(40,30),"wall").ok,"public path protected")
	w.state.players.alice.inventory.wood=100
	w.state.players.alice.inventory.stone=50
	var chest:=Vector2i(38,33)
	expect(act("build",chest,"chest").ok,"build chest")
	expect(w.state.players.alice.inventory.wood==80,"construction consumes exact materials")
	expect(not act("build",chest,"chest","bob").ok,"occupied build rejected")
	expect(act("deposit",chest,"wood").ok,"deposit one wood")
	expect(not act("remove",chest).ok,"nonempty chest cannot be destroyed")
	expect(not act("remove",chest,"","bob").ok,"ownership enforced")
	expect(act("withdraw",chest,"wood","bob").ok,"shared chest withdrawal")
	expect(not act("withdraw",chest,"wood").ok,"no negative chest count")
	expect(act("remove",chest).ok,"empty chest removable")
	expect(w.state.players.alice.inventory.wood==99,"materials refunded except gifted wood")
	expect(act("build",chest,"private_chest").ok,"private chest built")
	expect(act("deposit",chest,"wood").ok,"owner deposits into private chest")
	expect(not act("withdraw",chest,"wood","bob").ok,"other player cannot withdraw private materials")
	expect(not act("deposit",chest,"wood","bob").ok,"other player cannot modify private chest")
	expect(act("withdraw",chest,"wood").ok,"owner withdraws private material")
	expect(act("remove",chest).ok,"empty private chest refunds correctly")
	expect(not act("build",Vector2i(39,33),"wall").ok,"spawn tile stays protected")
	var house:=Vector2i(38,32)
	expect(not act("build",house,"roof").ok,"roof requires a floor")
	expect(act("build",house,"floor").ok,"floor built below roof")
	expect(not act("build",house,"roof","bob").ok,"roof follows floor ownership")
	expect(act("build",house,"door").ok,"door built on floor")
	expect(w.blocked(house),"closed door blocks movement")
	expect(act("door",house).ok,"door can open")
	expect(not w.blocked(house),"open door allows movement")
	expect(act("build",house,"roof").ok,"roof layers above door")
	expect(act("remove",house).ok,"roof is removed before furniture")
	expect(w.state.objects.has(World.key(house)),"roof removal preserves door")
	expect(act("remove",house).ok,"door can be removed")
	expect(act("remove",house).ok,"floor can then be removed")
	var before:Dictionary=w.state.duplicate(true)
	w.save_path="user://missing-test-directory/sub/world.json"
	expect(not act("build",Vector2i(38,32),"floor").ok,"save error rejects commit")
	expect(w.state.players.alice.inventory==before.players.alice.inventory,"failed save rolls materials back")
	expect(w.state.ground==before.ground,"failed save rolls placement back")
	w.save_path=""
	# Merchant checks and currency/quantity invariants.
	w.state.players.alice.x=43.5
	w.state.players.alice.y=31.5
	expect(act("sell",Vector2i(43,29),"radish").ok,"sell harvest")
	expect(w.state.players.alice.coins==144,"sale pays listed amount")
	expect(not act("sell",Vector2i(43,29),"radish").ok,"cannot resell same produce")
	expect(act("buy",Vector2i(43,29),"radish").ok,"buy a seed")
	expect(w.state.players.alice.coins==132,"purchase charges exact amount")
	w.state.players.alice.coins=0
	expect(not act("buy",Vector2i(43,29),"wheat").ok,"insufficient funds rejected")
	# Donation must cap consumption and unlock once.
	w.state.players.alice.x=40.5
	w.state.players.alice.y=31.5
	var wood_before:int=w.state.players.alice.inventory.wood
	expect(act("donate",Vector2i(40,29)).ok,"donate to shared project")
	expect(w.state.board,"bridge opens after target")
	expect(w.state.players.alice.inventory.wood==wood_before-30,"donation only takes required wood")
	expect(not act("donate",Vector2i(40,29)).ok,"project cannot reward twice")
	expect(not w.water(Vector2i(55,30)),"bridge is walkable after project")
	# Test deterministic collision without trusting client position.
	w.state.players.alice.x=40.5
	w.state.players.alice.y=30.5
	for n in range(60):w.move_player("alice",Vector2.UP,1.0/60.0)
	expect(w.state.players.alice.y>30.0,"player cannot walk through board")
	var gatherer:Dictionary=w.state.players.alice
	gatherer.x=39.5
	gatherer.y=34.5
	var tree:=Vector2i(39,35)
	var tree_key:=World.key(tree)
	w.state.forest[tree_key]={"owner":"alice","mature":true,"growth":World.TREE_TIME}
	gatherer.gathering_points=9
	expect(not act("remove",tree).ok,"Level two cannot recover a mature tree")
	for hit in range(3):
		expect(act("axe",tree).ok,"Chop completed resource")
		expect(int(gatherer.gathering_points)==(10 if hit==2 else 9),"Only the final chop grants gathering experience")
	expect(World.gathering_level(gatherer)==3,"Harvest unlocks level three")
	w.state.forest[tree_key]={"owner":"alice","mature":true,"growth":World.TREE_TIME}
	var seedlings:=int(gatherer.inventory.get("sapling",0))
	var reclaimed:Dictionary=act("remove",tree)
	expect(reclaimed.ok and not w.state.forest.has(tree_key) and gatherer.inventory.sapling==seedlings+1,"Level three recovers one mature tree as one seedling")
	var workbench:=Vector2i(40,33)
	gatherer.inventory.wood=50
	gatherer.inventory.stone=10
	expect(act("build",workbench,"bench").ok,"Build bench for crafting progression")
	gatherer.crafting_points=9
	var crafted:Dictionary=w.act("alice","craft-skill","craft",workbench,"sawmill_kit")
	expect(crafted.ok and World.crafting_level(gatherer)==3,"Workbench craft awards the tenth point")
	expect(w.act("alice","craft-skill","craft",workbench,"sawmill_kit")==crafted and gatherer.crafting_points==10,"Craft replay cannot award experience twice")
	expect(not act("craft",workbench,"missing-recipe").ok and gatherer.crafting_points==10,"Invalid recipes cannot award experience")
	var batch:=World.new()
	batch.add_player("builder","Builder")
	var builder:Dictionary=batch.state.players.builder
	builder.x=30.5
	builder.y=41.5
	builder.inventory.wood=150
	var a:=Vector2i(27,39)
	var b:=Vector2i(33,44)
	for y in range(a.y,b.y+1):
		for x in range(a.x,b.x+1):batch.state.removed[World.key(Vector2i(x,y))]=true
	builder.crafting_points=54
	expect(not batch.act("builder","locked-batch","build_area",a,"floor|33|44").ok and builder.inventory.wood==150,"Level five cannot place 42 tiles")
	builder.crafting_points=55
	expect(batch.act("builder","large-batch","build_area",a,"floor|33|44").ok and batch.state.ground.size()==42 and builder.inventory.wood==66,"Level six places all 42 tiles atomically")
	gatherer.explored_regions={}
	for region in World.REGIONS.ALL.slice(1,9):gatherer.explored_regions[region]=true
	gatherer.inventory.plank=4
	gatherer.inventory.fiber=2
	var supply:=Vector2i(40,34)
	expect(act("craft",workbench,"supply_box_kit").ok,"Explorer crafts a portable box")
	expect(act("build",supply,"supply_box").ok,"Explorer places box")
	expect(act("deposit",supply,"wood").ok and not act("remove",supply).ok,"Full box cannot be packed")
	w.state.players.bob.x=40.5
	w.state.players.bob.y=34.5
	expect(not act("withdraw",supply,"wood","bob").ok,"Visitor cannot take supplies")
	expect(act("withdraw",supply,"wood").ok and act("remove",supply).ok and gatherer.inventory.supply_box_kit==1,"Empty box packs back into its kit")
	var borrower:=World.new()
	borrower.add_player("newcomer","Visitor")
	var guest:Dictionary=borrower.state.players.newcomer
	guest.x=World.COPPER_CELL.x-0.5
	guest.y=World.COPPER_CELL.y+0.5
	expect(not borrower.act("newcomer","early","borrow_mine_pick",World.COPPER_CELL).ok,"Loan requires shared picnic")
	borrower.state.picnic=true
	var loan:=borrower.act("newcomer","loan","borrow_mine_pick",World.COPPER_CELL)
	expect(loan.ok and guest.borrowed_mine_pick and not guest.inventory.has("reinforced_pick"),"Loan grants access without an inventory tool")
	expect(borrower.act("newcomer","loan","borrow_mine_pick",World.COPPER_CELL)==loan and not borrower.act("newcomer","again","borrow_mine_pick",World.COPPER_CELL).ok,"Loan cannot grant repeated benefits")
	expect(borrower.act("newcomer","copper","mine_copper",World.COPPER_CELL).ok and guest.inventory.copper_ore==2,"Borrower may gather imported copper")
	guest.region="jinguashi"
	var node:Vector2i=World.JINGUASHI.NODES[0]
	guest.x=node.x-0.5
	guest.y=node.y+0.5
	expect(borrower.act("newcomer","shallow","mine_copper",node).ok,"Loan also covers the shallow mine")
	var loan_path:="user://loan-restart-%d.json"%Time.get_ticks_usec()
	borrower.save_path=loan_path
	expect(borrower.save(),"Save loan before restarting")
	var returning:=World.new()
	expect(returning.load_world(loan_path) and returning.state.players.get("newcomer",{}).get("borrowed_mine_pick",false),"Loan survives restart")
	var returning_guest:Dictionary=returning.state.players.get("newcomer",{})
	expect(not returning_guest.get("inventory",{}).has("reinforced_pick"),"Reload does not turn the loan into merchandise")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(loan_path+suffix):DirAccess.remove_absolute(loan_path+suffix)
	var shared:=World.new()
	for token in ["grower","friend","stranger"]:
		shared.add_player(token,token)
	var plot:=Vector2i(38,34)
	var plot_key:=World.key(plot)
	shared.state.crops[plot_key]={"kind":"radish","growth":World.CROPS.radish.time,"wet":true,"owner":"grower","remaining":1}
	expect(shared.act("grower","grant","plot_harvest_access",plot,"friend:"+"friend".sha256_text().left(16)).ok,"Owner grants access to an online player")
	expect(not shared.act("stranger","deny","harvest",plot).ok,"Unlisted visitor cannot harvest")
	var shared_path:="user://friendly-plot-%d.json"%Time.get_ticks_usec()
	shared.save_path=shared_path
	expect(shared.save(),"Save trusted harvest access")
	var reopened:=World.new()
	expect(reopened.load_world(shared_path) and reopened.state.crops.get(plot_key,{}).get("harvest_friend")=="friend","Trusted player survives save and restart")
	expect(reopened.act("friend","harvest","harvest",plot).ok and reopened.state.players.friend.inventory.get("radish",0)==1,"Designated player can harvest")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(shared_path+suffix):DirAccess.remove_absolute(shared_path+suffix)
	# T017: hand-tool rejections spend nothing and leave the touched layers unchanged.
	var tools:=World.new()
	tools.add_player("tester","Tester")
	var hand:Dictionary=tools.state.players.tester
	hand.x=39.5
	hand.y=34.5
	var field:=Vector2i(38,34)
	var bare:=Vector2i(38,33)
	var trunk:=Vector2i(39,35)
	tools.state.forest[World.key(trunk)]={"owner":"tester","mature":true,"growth":World.TREE_TIME}
	hand.inventory.radish_seed=0
	hand.inventory.sapling=0
	var rejections:=[["water",field,"","water on bare ground"],["axe",bare,"","axe on empty ground"],["pick",trunk,"","pick on a tree"],
		["plant_tree",bare,"","plant tree without a sapling"],["hoe",field,"","hoe"],["seed",field,"radish","seed without radish seeds"]]
	for case in rejections:
		var bag_before:Dictionary=hand.inventory.duplicate(true)
		var layers_before:=[tools.state.crops.duplicate(true),tools.state.forest.duplicate(true),tools.state.damage.duplicate(true)]
		var outcome:Dictionary=tools.act("tester","t017-"+str(case[0]),case[0],case[1],case[2])
		if case[0]=="hoe":
			expect(outcome.ok,"T017 setup: hoe prepares the plot")
			continue
		expect(not outcome.ok and not str(outcome.get("message","")).is_empty(),"T017 rejects "+str(case[3])+" with a reason")
		expect(hand.inventory==bag_before,"T017 "+str(case[3])+" spends nothing")
		expect([tools.state.crops,tools.state.forest,tools.state.damage]==layers_before,"T017 "+str(case[3])+" leaves crops, trees and chop damage unchanged")
	# Persistence round-trip and backup recovery.
	var path:="user://test-world-isolated-%d.json"%Time.get_ticks_usec()
	w.save_path=path
	expect(w.island_project_mask()==1,"Only the completed bridge appears as island news")
	expect(not w.act("alice","news-unfinished","news_read",Vector2i.ZERO,"3").ok,"Cannot mark an unfinished project as read")
	expect(w.act("alice","news-bridge","news_read",Vector2i.ZERO,"1").ok,"Alice acknowledges the bridge")
	expect(w.act("alice","note-1","news_note",Vector2i.ZERO,"橋修好了！").ok,"Island note persists while friends are offline")
	var first_revision:=World.ISLAND_NOTES.revision(w.state)
	expect(w.act("bob","notes-read","news_notes_read",Vector2i.ZERO,str(first_revision)).ok,"Bob can acknowledge the notes he saw")
	expect(w.act("alice","note-2","news_note",Vector2i.ZERO,"等你回來看橋。").ok,"Posting again in the same world tick advances the note revision")
	expect(w.act("bob","notes-retry","news_notes_read",Vector2i.ZERO,str(first_revision)).ok and World.ISLAND_NOTES.unread(w.state,w.state.players.bob)==1,"Acknowledging an older revision leaves a concurrent note unread")
	expect(not w.act("bob","notes-future","news_notes_read",Vector2i.ZERO,str(first_revision+2)).ok,"A future revision cannot be acknowledged")
	expect(not w.act("alice","note-invalid","news_note",Vector2i.ZERO,"one\ntwo").ok,"Multiline note is refused")
	expect(w.save(),"snapshot saved")
	var loaded=World.new()
	expect(loaded.load_world(path),"snapshot loaded")
	expect(loaded.state.players.alice.inventory==w.state.players.alice.inventory,"inventory survives restart")
	expect(loaded.state.board,"world progress survives restart")
	expect(loaded.region_snapshot(World.REGIONS.HOME).island_notes[1].text=="橋修好了！","Published note survives restart")
	expect(World.ISLAND_NOTES.unread(loaded.state,loaded.state.players.bob)==1 and World.ISLAND_NOTES.unread(loaded.state,loaded.state.players.alice)==2,"Note acknowledgments persist separately for each player")
	expect(int(loaded.state.players.alice.get("news_seen",0))==1 and int(loaded.state.players.bob.get("news_seen",0))==0,"News acknowledgement survives restart independently per player")
	expect(World.crafting_level(loaded.state.players.alice)==3,"Crafting skill survives restart")
	expect(World.gathering_level(loaded.state.players.alice)==3,"Gathering skill survives restart")
	w.state.players.alice.coins=77
	expect(w.save(),"second snapshot creates backup")
	var f:=FileAccess.open(path,FileAccess.WRITE)
	f.store_string("corrupt test file")
	f.close()
	var recovered=World.new()
	expect(recovered.load_world(path),"corrupt main snapshot recovers backup")
	expect(recovered.state.players.alice.coins==0,"backup has prior committed state")
	# Cleanup is limited to the uniquely named test files created above.
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WORLD_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
