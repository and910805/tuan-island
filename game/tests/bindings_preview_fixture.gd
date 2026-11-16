extends SceneTree

const Bindings=preload("res://scripts/input_bindings.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:quit(1);return
	var input:=Bindings.new()
	input.path=args[0]
	for action in {"move_up":KEY_UP,"move_down":KEY_DOWN,"move_left":KEY_LEFT,"move_right":KEY_RIGHT,
		"inventory":KEY_Q,"interact":KEY_F12,"harvest_area":KEY_P,"area_modifier":KEY_CTRL}:
		var keys:={"move_up":KEY_UP,"move_down":KEY_DOWN,"move_left":KEY_LEFT,"move_right":KEY_RIGHT,
			"inventory":KEY_Q,"interact":KEY_F12,"harvest_area":KEY_P,"area_modifier":KEY_CTRL}
		if not input.rebind(action,keys[action]).ok:quit(1);return
	print("BINDINGS_PREVIEW_READY")
	quit(0)
