extends SceneTree
const World=preload("res://scripts/world.gd")
const WHO:="seeder-preview-player"
var seq:=0

func perform(w,action:String,cell:Vector2i,extra:String="") -> bool:
	seq+=1
	var result:Dictionary=w.act(WHO,"demo-seeder-%d"%seq,action,cell,extra)
	if not result.ok:push_error(str(result))
	return result.ok

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(1);return
	var w:=World.new()
	w.add_player(WHO,"小糰")
	var p:Dictionary=w.state.players[WHO]
	p.inventory.merge({"wood":60,"stone":60,"fiber":40,"plank":60,"copper_joint":50,"charcoal":20,"resin":30,"radish_seed":20,"lettuce_seed":3,"tomato_seed":3},true)
	for x in range(34,54):
		for y in range(32,42):w.state.removed[World.key(Vector2i(x,y))]=true
	p.x=40.5;p.y=34.5
	if not perform(w,"build",Vector2i(40,33),"bench"):quit(1);return
	for recipe in ["tiller","seeder","sprinkler_kit"]:
		if not perform(w,"craft",Vector2i(40,33),recipe):quit(1);return
	p.x=43.5;p.y=36.5
	if not perform(w,"build",Vector2i(44,36),"sprinkler"):quit(1);return
	if not perform(w,"refill_sprinkler",Vector2i(44,36)):quit(1);return
	if not perform(w,"toggle_sprinkler",Vector2i(44,36)):quit(1);return
	p.x=42.5;p.y=36.5
	if not perform(w,"till_area",Vector2i(42,36)):quit(1);return
	for x in range(45,48):
		for y in range(35,38):w.state.crops[World.key(Vector2i(x,y))]={"kind":"","growth":0.0,"wet":false,"owner":WHO}
	w.state.crops["46,36"]={"kind":"carrot","owner":WHO,"wet":true,"growth":70,"remaining":1}
	w.state.crops["45,37"].owner="demo-neighbor"
	for key in ["46,35","47,35","46,37"]:w.state.crops.erase(key)
	w.state.forest["46,37"]={"growth":20,"mature":false,"owner":"demo-neighbor"}
	w.state.ground["46,35"]={"type":"path","owner":WHO,"items":{}}
	w.state.objects["47,35"]={"type":"chair","owner":WHO,"items":{}}
	w.save_path=args[0]
	if not w.save():quit(1);return
	var verify:=World.new()
	quit(0 if verify.load_world(args[0]) else 1)
