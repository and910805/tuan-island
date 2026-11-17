extends SceneTree

const World=preload("res://scripts/world.gd")
const Book=preload("res://scripts/island_skill_book.gd")
const TOKEN:="skills-newcomer"
var checks:=0
var failures:=0

func expect(ok:bool,description:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(description)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var world:=World.new()
	world.add_player(TOKEN,"晚到的居民")
	var newcomer:Dictionary=world.state.players[TOKEN]
	var start:=Book.skills(newcomer)
	expect(start.size()==5 and start.all(func(row):return row.level==1 and row.points==0),"Five skills start at level one")
	var example:={"harvests":10,"gathering_points":55,"crafting_points":185,"fish_caught":8,"exploration_points":8}
	var unlocked:=Book.skills(example)
	expect(unlocked.map(func(entry):return entry.level)==[3,6,10,3,6],"The skill pages match the existing unlock levels")
	expect(unlocked[2].next==World.CRAFTING_LEVEL_THRESHOLDS[-1],"Maximum level uses its actual threshold")
	newcomer.x=World.COPPER_CELL.x-0.5
	newcomer.y=World.COPPER_CELL.y+0.5
	expect(not world.act(TOKEN,"too-early","borrow_mine_pick",World.COPPER_CELL).ok,"Only an established public pick can be borrowed")
	world.state.picnic=true
	if DisplayServer.get_name()!="headless":await verify_scene(world)
	expect(world.act(TOKEN,"borrow","borrow_mine_pick",World.COPPER_CELL).ok and not newcomer.inventory.has("reinforced_pick"),
		"An unskilled latecomer gets access without a physical tool")
	expect(world.act(TOKEN,"mine","mine_copper",World.COPPER_CELL).ok and int(newcomer.inventory.copper_ore)==2,"The public pick is usable")
	expect(not world.act(TOKEN,"mine-early","mine_copper",World.COPPER_CELL).ok,"The loan respects the existing mining cooldown")
	var coins:=int(newcomer.coins)
	var stall:=Vector2i(43,29)
	newcomer.x=stall.x+0.5
	newcomer.y=stall.y+0.5
	expect(not world.act(TOKEN,"sell","sell",stall,"reinforced_pick").ok and not newcomer.inventory.has("reinforced_pick")
		and int(newcomer.coins)==coins,"The borrowed tool cannot be turned into a sale")
	verify_mine_loan(world)
	print("ISLAND_SKILL_BOOK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_mine_loan(world:World) -> void:
	var latecomer:="late-mine-worker"
	world.add_player(latecomer,"新來的島民")
	var player:Dictionary=world.state.players[latecomer]
	player.region=World.REGIONS.JINGUASHI
	player.x=World.MINES.ENTRY.x+0.5
	player.y=World.MINES.ENTRY.y+0.5
	expect(world.act(latecomer,"enter-b1","mine_travel",World.MINES.ENTRY,"mine_1").ok,"Latecomer visits the opened mine without crafting a tool")
	var node:Vector2i=World.MINES.NODES[0]
	player.x=node.x+0.5
	player.y=node.y+0.5
	expect(not world.act(latecomer,"no-tool","pick",node).ok,"Unqualified player cannot mine")
	player.x=World.MINES.REST.x+0.5
	player.y=World.MINES.REST.y+0.5
	var inventory:Dictionary=player.inventory.duplicate(true)
	expect(world.act(latecomer,"borrow-at-rest","borrow_mine_pick",World.MINES.REST).ok and player.inventory==inventory,"Shallow rest stop issues only eligibility")
	player.x=node.x+0.5
	player.y=node.y+0.5
	var ore:String=World.MINES.ORES[0]
	var starting_ore:=int(player.inventory.get(ore,0))
	var mined:=world.act(latecomer,"b1-public-pick","pick",node)
	expect(mined.ok and int(player.inventory.get(ore,0))==starting_ore+World.MINES.YIELDS[0],"Borrower extracts normal shallow ore: "+mined.message)
	expect(not world.act(latecomer,"b1-public-cooldown","pick",node).ok,"Borrowed mining follows node cooldown")
	world.state.mine_depths.unlocked=6
	player.region="mine_6"
	expect(not world.act(latecomer,"b6-public-pick","pick",node).ok,"Deep mining retains its owned-tool gate")
	player.inventory.reinforced_pick=1
	expect(world.act(latecomer,"b6-owned-pick","pick",node).ok,"Crafted pick opens deep mining")

func verify_scene(world:World)->void:
	var app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.session.world=world
	app.session.peers[1]=TOKEN
	app.session.own_id=TOKEN
	app.session.snapshot=world.region_snapshot("home")
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._state_changed(app.session.snapshot,TOKEN)
	app._journal()
	await create_timer(0.25).timeout
	var bookmark:Button=app.modal.find_child("IslandSkillBook",true,false) if is_instance_valid(app.modal) else null
	expect(bookmark!=null,"The journal opens the skill guide")
	if bookmark!=null:
		bookmark.pressed.emit()
		await create_timer(0.26).timeout
		var labels:Array=app.modal.find_children("*","Label",true,false)
		expect(labels.any(func(label):return label.text=="農耕 · 1 級"),"The first skill shows live progress")
		expect(labels.any(func(label):return label.text=="○ 10 級 · 工匠署名牌、展示架"),"Unreached rewards are visible")
		var buttons:Array=app.modal.find_children("*","Button",true,false)
		expect(buttons.any(func(button):return button.text=="借用公用鎬" and not button.disabled),"An eligible player near the ore can borrow from the guide")
		for arg:String in OS.get_cmdline_user_args():
			if not arg.begins_with("--skills-preview="):continue
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--skills-preview="))==OK,"Capture the skill page")
	var person:Dictionary=world.state.players[TOKEN]
	var position:=Vector2(person.x,person.y)
	person.region="mine_1"
	person.x=World.MINES.REST.x+0.5
	person.y=World.MINES.REST.y+0.5
	app.session.snapshot=world.region_snapshot("mine_1")
	app._mine_site_menu("rest")
	await create_timer(0.26).timeout
	var loan:=app.modal.find_child("MineBorrowPick",true,false) as Button
	expect(loan!=null and loan.is_visible_in_tree() and not loan.disabled,"Shallow rest stop offers a usable loan button")
	person.region=World.REGIONS.HOME
	person.x=position.x
	person.y=position.y
	var kitchen_view:=world.region_snapshot("home")
	kitchen_view.public_kitchen={"stove":"38,34","seats":["37,34","39,34"],
		"meals":World.PUBLIC_KITCHEN.REQUIREMENTS.duplicate(),"opened":true}
	kitchen_view.objects["38,34"]={"type":"stove","owner":"previous-resident","items":{}}
	app.session.snapshot=kitchen_view
	app.LifeTasks.skill_book(app)
	var actions:Array=app.modal.find_children("*","Button",true,false)
	expect(actions.any(func(control):return control.text=="在地圖找公共廚房"),"A newcomer away from the stove can open the map")
	kitchen_view.players[TOKEN].x=37.5
	kitchen_view.players[TOKEN].y=34.5
	app.LifeTasks.skill_book(app)
	actions=app.modal.find_children("*","Button",true,false)
	var stoves:=actions.filter(func(control):return control.text=="使用公共石灶")
	expect(stoves.size()==1,"A newcomer near the stove gets the cooking shortcut")
	if not stoves.is_empty():
		stoves[0].pressed.emit()
		expect(app.modal is Control and app.modal.get_meta("life_modal_layout","")=="cooking_queue","Shortcut opens the actual stove workbench")
	app.queue_free()
	await process_frame
