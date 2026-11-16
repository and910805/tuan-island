extends SceneTree
const World=preload("res://scripts/world.gd")
const WHO:="tiller-preview-player"
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(1);return
	var w:=World.new()
	w.add_player(WHO,"小糰")
	var p:Dictionary=w.state.players[WHO]
	p.inventory.merge({"wood":60,"stone":50,"fiber":20,"plank":30,"copper_joint":20,"charcoal":10,"resin":12,"radish_seed":20},true)
	for x in range(34,54):
		for y in range(32,42):w.state.removed[World.key(Vector2i(x,y))]=true
	p.x=40.5;p.y=34.5
	if not w.act(WHO,"demo-bench","build",Vector2i(40,33),"bench").ok:quit(1);return
	if not w.act(WHO,"demo-craft","craft",Vector2i(40,33),"tiller").ok:quit(1);return
	w.state.crops["46,36"]={"kind":"carrot","owner":WHO,"wet":true,"growth":70,"remaining":1}
	w.state.crops["45,37"]={"kind":"radish","owner":"demo-neighbor","wet":true,"growth":30,"remaining":1}
	w.state.forest["46,37"]={"growth":20,"mature":false,"owner":"demo-neighbor"}
	w.state.ground["46,35"]={"type":"path","owner":WHO,"items":{}}
	w.state.objects["47,35"]={"type":"chair","owner":WHO,"items":{}}
	p.x=42.5;p.y=36.5
	w.save_path=args[0]
	if not w.save():quit(1);return
	var verify:=World.new()
	quit(0 if verify.load_world(args[0]) else 1)
