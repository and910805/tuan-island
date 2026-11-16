extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize() -> void:
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):path=arg.trim_prefix("--save=")
	if path.is_empty():quit(1);return
	var w=World.new()
	w.add_player("network-alpha-test","甲")
	w.add_player("network-beta-test","乙")
	w.state.objects["38,32"]={"type":"private_chest","owner":"network-alpha-test","items":{"wood":7}}
	w.state.objects["38,33"]={"type":"stove","owner":"network-alpha-test","items":{},"job":{"kind":"bread","ready":0.0,"owner":"network-alpha-test"}}
	w.save_path=path
	quit(0 if w.save() else 1)
