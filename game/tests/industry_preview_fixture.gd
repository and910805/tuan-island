extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(1);return
	var world:=World.new()
	var who:="industry-preview-player"
	world.add_player(who,"小糰")
	var person:Dictionary=world.state.players[who]
	person.inventory.merge({"wood":80,"stone":40,"fiber":20,"resin":12,"copper_ore":20,"copper_joint":4,"pipe_kit":24,"sawmill_kit":1,"kiln_kit":1,"tank_kit":1,"pump_kit":1,"sprinkler_kit":1},true)
	for x in range(38,54):
		for y in range(32,40):world.state.removed[World.key(Vector2i(x,y))]=true
	var objects:={"40,33":"bench","40,35":"sawmill","42,35":"charcoal_kiln","43,36":"sprinkler","46,36":"water_tank","53,36":"water_pump"}
	for x in range(44,53):
		if x!=46 and x!=45:objects["%d,36"%x]="water_pipe"
	var step:=0
	for key in objects:
		var cell:=World.cell(key)
		person.x=cell.x+0.5;person.y=cell.y+1.5
		var result:=world.act(who,"fixture-%d"%step,"build",cell,objects[key])
		step+=1
		if not result.ok:push_error(str(result));quit(1);return
	for cell in [Vector2i(43,35),Vector2i(42,36),Vector2i(43,37)]:
		world.state.crops[World.key(cell)]={"kind":"radish","owner":who,"wet":false,"growth":0,"remaining":1}
	person.x=41.5;person.y=35.5
	world.save_path=args[0]
	quit(0 if world.save() else 1)
