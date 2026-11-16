extends SceneTree
const World=preload("res://scripts/world.gd")
const WHO:="forestry-preview-player"
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
	person.inventory.merge({"wood":100,"stone":60,"fiber":20,"plank":20,"resin":14,"copper_joint":12,"charcoal":14,"sapling":8,
		"pipe_kit":24,"sawmill_kit":1,"kiln_kit":1,"tank_kit":1,"pump_kit":1,"sprinkler_kit":1},true)
	for x in range(34,54):
		for y in range(32,43):world.state.removed[World.key(Vector2i(x,y))]=true
	var objects:={"40,33":"bench","40,35":"sawmill","42,35":"charcoal_kiln","43,36":"sprinkler","46,36":"water_tank","53,36":"water_pump"}
	for x in range(44,53):
		if x!=46:objects["%d,36"%x]="water_pipe"
	for key in objects:
		if not perform("build",World.cell(key),objects[key]):quit(1);return
	if not perform("craft",Vector2i(40,33),"forester_kit"):quit(1);return
	if not perform("build",Vector2i(38,38),"forester"):quit(1);return
	# Pre-grown demo forest only. Normal new worlds still take 180 online seconds.
	for entry in [[Vector2i(38,36),180.0],[Vector2i(40,38),130.0],[Vector2i(36,38),25.0]]:
		var cell:Vector2i=entry[0]
		world.state.forest[World.key(cell)]={"owner":WHO,"growth":entry[1],"mature":entry[1]>=World.TREE_TIME}
	for cell in [Vector2i(43,35),Vector2i(42,36),Vector2i(43,37)]:
		world.state.crops[World.key(cell)]={"kind":"radish","owner":WHO,"wet":false,"growth":0,"remaining":1}
	world.state.objects["53,36"].enabled=true
	world.state.objects["43,36"].enabled=true
	person.x=38.5;person.y=39.5
	world.save_path=args[0]
	quit(0 if world.save() else 1)
