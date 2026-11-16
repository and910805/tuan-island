extends SceneTree
const World=preload("res://scripts/world.gd")
const WHO:="logistics-preview-player"
var world:=World.new()
var sequence:=0

func perform(action:String,tile:Vector2i,extra:String="") -> bool:
	var person:Dictionary=world.state.players[WHO]
	person.x=tile.x+0.5
	person.y=tile.y+1.5
	var result:Dictionary=world.act(WHO,"fixture-%d"%sequence,action,tile,extra)
	sequence+=1
	if not result.ok:push_error(str(result))
	return result.ok

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(1);return
	world.add_player(WHO,"小糰")
	var person:Dictionary=world.state.players[WHO]
	person.inventory.merge({"wood":120,"stone":80,"fiber":40,"plank":40,"resin":24,"copper_joint":24,"charcoal":16,"sapling":8,
		"pipe_kit":20,"sawmill_kit":1,"kiln_kit":1,"tank_kit":1,"pump_kit":1,"sprinkler_kit":1},true)
	for x in range(34,54):
		for y in range(32,43):world.state.removed[World.key(Vector2i(x,y))]=true
	var objects:={"40,33":"bench","41,37":"charcoal_kiln","42,40":"sawmill","40,40":"private_chest","44,40":"private_chest",
		"46,36":"sprinkler","49,36":"water_tank","53,36":"water_pump"}
	for x in range(47,53):
		if x!=49:objects["%d,36"%x]="water_pipe"
	for key in objects:
		if not perform("build",World.cell(key),objects[key]):quit(1);return
	if not perform("craft",Vector2i(40,33),"forester_kit"):quit(1);return
	if not perform("build",Vector2i(38,37),"forester"):quit(1);return
	var belts:={"39,37":[1,"wood"],"40,37":[1,"wood"],
		"41,36":[0,"charcoal"],"41,35":[3,"charcoal"],"40,35":[3,"charcoal"],"39,35":[3,"charcoal"],"38,35":[2,"charcoal"],"38,36":[2,"charcoal"],
		"41,40":[1,"wood"],"43,40":[1,"plank"]}
	for index in 6:
		if not perform("craft",Vector2i(40,33),"conveyor_kit"):quit(1);return
	for key in belts:
		var tile:=World.cell(key)
		if not perform("build",tile,"conveyor"):quit(1);return
		if not perform("configure_conveyor",tile,"dir:%d"%belts[key][0]):quit(1);return
		if not perform("configure_conveyor",tile,"filter:"+str(belts[key][1])):quit(1);return
		# All except the first forest output belt are running; the player starts this link.
		if key!="39,37" and not perform("toggle_conveyor",tile):quit(1);return
	for key in ["41,37","42,40"]:
		if not perform("toggle_auto_processing",World.cell(key)):quit(1);return
	for cell in [Vector2i(38,39),Vector2i(36,37)]:
		world.state.forest[World.key(cell)]={"owner":WHO,"growth":World.TREE_TIME,"mature":true}
	# Explicit demo stock: two harvests worth, not a reward granted in a normal game.
	world.state.objects["38,37"].items={"wood":12,"fiber":4,"resin":2}
	world.state.objects["38,37"].fuel=1
	world.state.objects["38,37"].saplings=2
	world.state.objects["40,40"].items={"wood":12}
	for cell in [Vector2i(46,35),Vector2i(45,36),Vector2i(46,37)]:
		world.state.crops[World.key(cell)]={"kind":"radish","owner":WHO,"wet":false,"growth":0,"remaining":1}
	world.state.objects["53,36"].enabled=true
	world.state.objects["46,36"].enabled=true
	person.x=39.5;person.y=38.5
	world.save_path=args[0]
	if not world.save():quit(1);return
	var check:=World.new()
	quit(0 if check.load_world(args[0]) else 1)
