extends ScrollContainer

var stick_direction:=0.0

func _ready() -> void:
	set_process(false)

func _input(event:InputEvent) -> void:
	if not is_visible_in_tree():return
	if event is InputEventJoypadMotion and event.axis==JOY_AXIS_RIGHT_Y:
		stick_direction=event.axis_value if absf(event.axis_value)>=0.25 else 0.0
		set_process(stick_direction!=0.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
		var bar:=get_v_scroll_bar()
		bar.value+=bar.page if event.keycode==KEY_PAGEDOWN else -bar.page
		get_viewport().set_input_as_handled()

func _process(delta:float) -> void:
	get_v_scroll_bar().value+=stick_direction*420.0*delta
