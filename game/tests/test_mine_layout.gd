extends SceneTree

const World=preload("res://scripts/world.gd")
const Layout=preload("res://scripts/mine_layout.gd")
const MINES=World.MINES
const ACTOR="mine-layout-tester"
const NEIGHBORS=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const CAVE_ENTRANCES=[Vector2i(16,15),Vector2i(40,21),Vector2i(24,29),Vector2i(34,15),Vector2i(40,24)]
const CAVE_INTERIORS=[Vector2i(16,12),Vector2i(44,21),Vector2i(24,33),Vector2i(34,11),Vector2i(44,24)]

var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func _initialize() -> void:
	var world:=World.new()
	var path:=OS.get_environment("TEMP").path_join("mine-layout-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	world.save_path=path
	world.add_player(ACTOR,"Mine Layout")
	world.state.mine_depths.unlocked=5
	world.state.mine_depths.pumped=24
	for depth in range(1,6):
		check_layout(world,depth)
	check_persistence(world,path)
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("MINE_LAYOUT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func check_layout(world:World,depth:int) -> void:
	var region:String=MINES.IDS[depth-1]
	world.switch_region(region)
	var extent:=Layout.bounds(depth).grow(2)
	var original_cells_preserved:=true
	var expected_water:=true
	var boundary_blocked:=true
	var expected_protection:=true
	var walkable:Dictionary={}
	var new_land:=0
	var new_pump_sites:=0
	for y in range(extent.position.y,extent.end.y):
		for x in range(extent.position.x,extent.end.x):
			var cell:=Vector2i(x,y)
			var land:=world.is_land(cell)
			var old_land:=Layout.BASE_RECT.has_point(cell)
			var pool:bool=depth==3 and MINES.POOL.has_point(cell)
			var protected:bool=cell in [MINES.UP,MINES.DOWN,MINES.REST,MINES.SERVICE,Vector2i(12,20)] or cell in MINES.NODES
			if old_land and not land:original_cells_preserved=false
			if world.water(cell)!=(not land or pool):expected_water=false
			if world.protected(cell)!=protected:expected_protection=false
			var can_stand:=world.can_stand(Vector2(cell)+Vector2(0.5,0.5))
			if (not land or pool) and can_stand:boundary_blocked=false
			if can_stand:walkable[cell]=true
			if land and not old_land:
				new_land+=1
				if World.INDUSTRY.near_river(world,cell):new_pump_sites+=1
	expect(original_cells_preserved and new_land>0,"B%d retains base land and adds side cave land"%depth)
	expect(expected_water and boundary_blocked,"B%d retains water and blocks off-map movement"%depth)
	expect(expected_protection,"B%d retains only original protected tiles"%depth)
	expect(new_pump_sites==0,"B%d side cave has no pump source"%depth)

	var reached:Dictionary={MINES.UP:true}
	var queue:Array[Vector2i]=[MINES.UP]
	var cursor:=0
	while cursor<queue.size():
		var cell:=queue[cursor]
		cursor+=1
		for direction:Vector2i in NEIGHBORS:
			var neighbor:=cell+direction
			if walkable.has(neighbor) and not reached.has(neighbor):
				reached[neighbor]=true
				queue.append(neighbor)
	expect(reached.size()==walkable.size(),"B%d all walkable tiles connect to the ascent"%depth)
	expect(reached.has(CAVE_INTERIORS[depth-1]),"B%d side cave interior is reachable"%depth)
	var entry:Vector2i=CAVE_ENTRANCES[depth-1]
	var width:=0
	for direction:Vector2i in [Vector2i.ZERO]+NEIGHBORS:
		var cell:=entry+direction
		if not reached.has(cell) or Layout.BASE_RECT.has_point(cell):continue
		for inward:Vector2i in NEIGHBORS:
			if Layout.BASE_RECT.has_point(cell+inward):width+=1
	expect(width>=2,"B%d cave entrance has two or more walkable connections"%depth)

func check_persistence(world:World,path:String) -> void:
	world.switch_region(World.REGIONS.HOME)
	var player:Dictionary=world.state.players[ACTOR]
	player.region="mine_2"
	player.inventory.wood=40
	player.x=38.5
	player.y=21.5
	var old_cell:=Vector2i(37,21)
	expect(world.act(ACTOR,"old-equipment","build",old_cell,"chest").ok,"Place equipment on original floor")
	var old_load:=World.new()
	expect(old_load.load_world(path) and old_load.state.regions.mine_2.objects.has(World.key(old_cell)),"Original floor equipment loads from save")

	for step in range(6):
		world.move_player(ACTOR,Vector2.RIGHT,1.0/3.6)
	expect(Vector2(player.x,player.y).is_equal_approx(Vector2(44.5,21.5)),"Player walks through side cave entrance")
	var cave_cell:=Vector2i(44,22)
	var moved_cell:=Vector2i(45,22)
	expect(world.act(ACTOR,"side-build","build",cave_cell,"chest").ok,"Build a chest in the side cave")
	expect(world.act(ACTOR,"side-move","move_object",cave_cell,World.key(moved_cell)).ok,"Move chest between side cave cells")
	var reload:=World.new()
	expect(reload.load_world(path),"Load world with a side cave player and moved chest")
	var objects:Dictionary=reload.state.regions.mine_2.objects
	expect(objects.has(World.key(old_cell)) and objects.has(World.key(moved_cell)) and not objects.has(World.key(cave_cell)),"Both original and moved equipment persist")
	var saved:Dictionary=reload.state.players[ACTOR]
	expect(saved.region=="mine_2" and Vector2(saved.x,saved.y).is_equal_approx(Vector2(44.5,21.5)),"Player position persists in the side cave")
