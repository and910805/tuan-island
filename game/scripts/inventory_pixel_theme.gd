extends RefCounted

const DIRECTORY:="res://assets/ui-inventory/"

static func make(base:Theme) -> Theme:
	var theme:=base.duplicate() as Theme if base else Theme.new()
	theme.set_type_variation("ItemSlot","Button")
	var names:Dictionary={"normal":"normal","hover":"hover","pressed":"selected","hover_pressed":"pressed","disabled":"normal","focus":"focus"}
	for state in names:
		theme.set_stylebox(state,"ItemSlot",texture_style(names[state],3,0))
	var button_states:Dictionary={"normal":"button_normal","hover":"button_hover","pressed":"button_pressed","hover_pressed":"button_pressed","focus":"focus"}
	for state in button_states:
		var button_style:=texture_style(button_states[state],3,0)
		for side in [SIDE_LEFT,SIDE_RIGHT]:button_style.set_content_margin(side,12)
		for side in [SIDE_TOP,SIDE_BOTTOM]:button_style.set_content_margin(side,8)
		theme.set_stylebox(state,"Button",button_style)
	for state in ["font_color","font_hover_color","font_focus_color"]:
		theme.set_color(state,"Button",Color("3d422d"))
	for state in ["font_pressed_color","font_hover_pressed_color"]:
		theme.set_color(state,"Button",Color("fff3cf"))
	return theme

static func frame_style() -> StyleBoxTexture:
	return texture_style("frame",8,10)

static func paper_style() -> StyleBoxTexture:
	return texture_style("paper",3,8)

static func texture_style(asset:String,border:int,inset:int) -> StyleBoxTexture:
	var style:=StyleBoxTexture.new()
	style.texture=load(DIRECTORY+asset+".png") as Texture2D
	style.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,border)
		style.set_content_margin(side,inset)
	return style

