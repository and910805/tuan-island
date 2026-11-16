extends SceneTree
const World=preload("res://scripts/world.gd")
func _initialize() -> void:
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):path=arg.trim_prefix("--save=")
	if path.is_empty():quit(1);return
	var w=World.new()
	for role in ["alpha","beta"]:
		var token:="network-%s-test"%role
		w.add_player(token,role)
		w.state.players[token].x=41.5;w.state.players[token].y=30.5
	w.state.board=true;w.state.picnic=true;w.state.time=60.0
	w.state.festival={"round":1,"active":true,"collected":11,"contributors":{"network-alpha-test":6,"network-beta-test":5},"started":0.0,"finished":0.0,"ready":0.0,"best":0.0}
	w.save_path=path
	quit(0 if w.save() else 1)
