extends RefCounted

const CropArt=preload("res://scripts/crop_sprite_art.gd")
const CharacterArt=preload("res://scripts/character_sprite_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const INK:=Color("354334")

static func surface(fill:Color,border:Color,horizontal:float,vertical:float) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left=horizontal
	style.content_margin_right=horizontal
	style.content_margin_top=vertical
	style.content_margin_bottom=vertical
	return style

static func panel_style() -> StyleBoxTexture:
	var style:=Pixel.texture_style("life_paper",8,12)
	for side in [SIDE_LEFT,SIDE_RIGHT]:style.set_content_margin(side,16)
	for side in [SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,12)
	return style

static func compact_style() -> StyleBoxTexture:
	return badge_style()

static func badge_style() -> StyleBoxTexture:
	return Pixel.texture_style("hud_badge",8,9)

static func toolbar_style() -> StyleBoxTexture:
	return Pixel.texture_style("hud_wood",8,10)

static func apply(base:Theme) -> Theme:
	var theme:=Pixel.make(base)
	var normal:=theme.get_stylebox("normal","Button")
	var hover:=theme.get_stylebox("hover","Button")
	var pressed:=theme.get_stylebox("pressed","Button")
	var disabled:=Pixel.texture_style("normal",3,8)
	disabled.modulate_color=Color("d8caae")
	var focus:=theme.get_stylebox("focus","Button")
	theme.set_stylebox("disabled","Button",disabled)
	for state in ["font_color","font_hover_color","font_focus_color"]:
		theme.set_color(state,"Button",INK)
	theme.set_color("font_pressed_color","Button",Color("fff7df"))
	theme.set_color("font_hover_pressed_color","Button",Color("fff7df"))
	theme.set_color("font_disabled_color","Button",Color("6d6555"))
	theme.set_color("font_color","Label",INK)
	theme.set_color("font_shadow_color","Label",Color.TRANSPARENT)
	theme.set_color("font_color","LineEdit",INK)
	theme.set_stylebox("normal","LineEdit",Pixel.texture_style("paper",3,8))
	theme.set_stylebox("focus","LineEdit",focus)
	theme.set_stylebox("panel","PanelContainer",panel_style())

	for type in ["TabBar","TabContainer"]:
		theme.set_stylebox("tab_unselected",type,normal)
		theme.set_stylebox("tab_hovered",type,hover)
		theme.set_stylebox("tab_selected",type,pressed)
		theme.set_stylebox("tab_disabled",type,disabled)
		theme.set_stylebox("tab_focus",type,focus)
		theme.set_color("font_unselected_color",type,INK)
		theme.set_color("font_hovered_color",type,INK)
		theme.set_color("font_selected_color",type,Color("fff7df"))
		theme.set_color("font_disabled_color",type,Color("6d6555"))
	for type in ["HScrollBar","VScrollBar"]:
		theme.set_stylebox("scroll",type,Pixel.texture_style("paper",3,6))
		theme.set_stylebox("scroll_focus",type,Pixel.texture_style("button_hover",3,6))
		theme.set_stylebox("grabber",type,Pixel.texture_style("hover",3,4))
		theme.set_stylebox("grabber_highlight",type,Pixel.texture_style("button_hover",3,4))
		theme.set_stylebox("grabber_pressed",type,Pixel.texture_style("button_pressed",3,4))
	theme.set_stylebox("background","ProgressBar",Pixel.texture_style("paper",3,4))
	theme.set_stylebox("fill","ProgressBar",Pixel.texture_style("hover",3,4))
	theme.set_color("font_color","ProgressBar",INK)
	return theme

static func icon(kind:String) -> Texture2D:
	if kind in ["pumpkin","pumpkin_seed"]:return preload("res://scripts/bakery_art.gd").icon(kind)
	if kind=="bobo":return preload("res://scripts/bobo_art.gd").icon("portrait")
	var row:=CropArt.ROWS.find(kind.trim_suffix("_seed"))
	if row>=0:
		return atlas_region(CropArt.ATLAS_PATH,Rect2(96,row*32,32,32))
	var resident:=["aru","milu","xiaoli"].find(kind)
	if resident>=0:
		var frame_x:=(resident+3)*CharacterArt.FRAME_SIZE.x
		return atlas_region(CharacterArt.ATLAS_PATH,Rect2(frame_x+6,2,36,32))
	return null

static func atlas_region(path:String,region:Rect2) -> Texture2D:
	if not ResourceLoader.exists(path):return null
	var atlas:=load(path) as Texture2D
	if atlas==null or not Rect2(Vector2.ZERO,atlas.get_size()).encloses(region):return null
	var result:=AtlasTexture.new()
	result.atlas=atlas
	result.region=region
	result.filter_clip=true
	return result
