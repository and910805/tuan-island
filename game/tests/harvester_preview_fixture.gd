extends SceneTree
const World=preload("res://scripts/world.gd")
const WHO:="harvester-preview-player"
var seq:=0

func perform(w,action:String,cell:Vector2i,extra:String="") -> bool:
	seq+=1
	var result:Dictionary=w.act(WHO,"demo-harvester-%d"%seq,action,cell,extra)
	if not result.ok:push_error(str(result))
	return result.ok

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(1);return
	var w:=World.new()
	w.add_player(WHO,"小糰")
	var p:Dictionary=w.state.players[WHO]
	p.inventory.merge({"wood":80,"stone":80,"fiber":50,"plank":80,"copper_joint":70,"charcoal":26,"resin":40},true)
	for kind in World.CROPS:p.inventory[kind+"_seed"]=10
	for x in range(34,54):
		for y in range(32,42):w.state.removed[World.key(Vector2i(x,y))]=true
	p.x=40.5;p.y=34.5
	if not perform(w,"build",Vector2i(40,33),"bench"):quit(1);return
	for recipe in ["tiller","seeder","harvester","sprinkler_kit"]:
		if not perform(w,"craft",Vector2i(40,33),recipe):quit(1);return
	p.x=43.5;p.y=37.5
	if not perform(w,"build",Vector2i(44,37),"sprinkler"):quit(1);return
	if not perform(w,"refill_sprinkler",Vector2i(44,37)):quit(1);return
	if not perform(w,"toggle_sprinkler",Vector2i(44,37)):quit(1);return
	p.x=42.5;p.y=36.5
	if not perform(w,"till_area",Vector2i(42,36)):quit(1);return
	var kinds:=["radish","lettuce","wheat","carrot","tomato","potato","radish","wheat","tomato"]
	var index:=0
	for y in range(35,38):
		for x in range(41,44):
			var kind:String=kinds[index]
			index+=1
			if not perform(w,"seed",Vector2i(x,y),kind):quit(1);return
			# Mature demo plants, not a claim of growing these crops from scratch.
			var plot:Dictionary=w.state.crops[World.key(Vector2i(x,y))]
			plot.growth=float(World.CROPS[kind].time)
			plot.wet=true
	for tile in {"45,35":"radish","45,36":"wheat","47,36":"potato"}:
		var kind:String={"45,35":"radish","45,36":"wheat","47,36":"potato"}[tile]
		w.state.crops[tile]={"kind":kind,"owner":WHO,"wet":true,"growth":World.CROPS[kind].time,"remaining":1}
	w.state.crops["46,36"]={"kind":"carrot","owner":WHO,"wet":false,"growth":0,"remaining":1}
	w.state.crops["47,37"]={"kind":"tomato","owner":WHO,"wet":false,"growth":0,"remaining":3}
	w.state.crops["45,37"]={"kind":"tomato","owner":"demo-neighbor","wet":true,"growth":World.CROPS.tomato.time,"remaining":3}
	w.state.forest["46,37"]={"growth":20,"mature":false,"owner":"demo-neighbor"}
	w.state.ground["46,35"]={"type":"path","owner":WHO,"items":{}}
	w.state.objects["47,35"]={"type":"chair","owner":WHO,"items":{}}
	w.save_path=args[0]
	if not w.save():quit(1);return
	var verify:=World.new()
	quit(0 if verify.load_world(args[0]) else 1)
