extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize() -> void:
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):path=arg.trim_prefix("--save=")
	if path.is_empty():push_error("An explicit isolated --save path is required");quit(1);return
	var w=World.new()
	var owner:="showcase-isolated-player"
	w.add_player(owner,"展示島民")
	w.state.players[owner].x=35.5
	w.state.players[owner].y=37.5
	w.state.players[owner].inventory={"wood":120,"stone":45,"fiber":38,"radish_seed":5,"lettuce_seed":3,"wheat_seed":3,"feed":2,"soup":2}
	w.state.players[owner].builds=40
	w.state.players[owner].harvests=12
	w.state.players[owner].stories={"aru":4,"milu":4}
	w.state.board=true
	w.state.picnic=true
	w.state.donations={"wood":30,"stone":10}
	w.state.picnic_materials={"soup":2,"bread":1}
	for x in range(31,45):
		for y in range(32,42):w.state.removed[World.key(Vector2i(x,y))]=true
	for x in range(33,38):
		for y in range(34,39):
			var k:=World.key(Vector2i(x,y))
			w.state.ground[k]={"type":"floor","owner":owner,"items":{}}
			w.state.roofs[k]={"type":"roof","owner":owner,"items":{}}
			if x in [33,37] or y in [34,38]:w.state.objects[k]={"type":"wall","owner":owner,"items":{}}
	var decor:={"35,38":"door","36,34":"window","34,35":"bed","36,35":"private_chest","34,36":"stove","36,36":"table","36,37":"chair","38,38":"lamp","32,38":"lamp","38,34":"bench","38,35":"chest"}
	for k in decor:w.state.objects[k]={"type":decor[k],"owner":owner,"items":{},"open":true}
	for k in {"32,36":"sofa","32,34":"planter","38,36":"long_bench","39,38":"sign"}:
		var kind:String={"32,36":"sofa","32,34":"planter","38,36":"long_bench","39,38":"sign"}[k]
		w.state.objects[k]={"type":kind,"owner":owner,"items":{}}
	for x in range(40,44):
		for y in range(35,39):
			var kind:String=["radish","lettuce","wheat","carrot","potato","tomato"][(x+y)%6]
			w.state.crops[World.key(Vector2i(x,y))]={"kind":kind,"growth":float(World.CROPS[kind].time)*(0.2 if y==38 else 1.0),"wet":true,"remaining":int(World.CROPS[kind].get("cycles",1)),"owner":owner}
	w.save_path=path
	if not w.save():quit(1);return
	print("SHOWCASE_FIXTURE_SAVED (automatically built test scene)")
	quit()
