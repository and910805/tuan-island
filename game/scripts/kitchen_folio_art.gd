extends RefCounted
## Display-only styles and icon lookups for the public kitchen story cookbook.
## Reuses the existing ui-inventory nine-slice textures and the ui-life icon
## atlas; no new assets and no procedurally drawn substitute artwork.

const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/life_ui_theme.gd")
const LIFE_ICONS:="res://assets/ui-life/icons.png"
## Same cell order as life_ui_shell.gd ICON_IDS (5 columns of 32 px).
const LIFE_ICON_IDS:=["hoe","water","harvest","axe","pick","build","remove","fish","map","journal","weather","calendar","settings","bell","letter","home","sign","trophy","blueprint","chest"]
const RIBBON_INK:=Color("fff3cf")
const WARN_FILL:=Color("f6dcc0")

static func life_icon(id:String)->Texture2D:
	var index:=LIFE_ICON_IDS.find(id)
	if index<0:return null
	return Art.atlas_region(LIFE_ICONS,Rect2((index%5)*32,floori(index/5.0)*32,32,32))

static func padded(asset:String,border:int,horizontal:int,vertical:int)->StyleBoxTexture:
	var style:=Pixel.texture_style(asset,border,0)
	for side in [SIDE_LEFT,SIDE_RIGHT]:style.set_content_margin(side,horizontal)
	for side in [SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,vertical)
	return style

## Cream page of the open cookbook.
static func page_style()->StyleBoxTexture:
	return padded("paper",3,10,6)

## Page-heading ribbon (same texture as a pressed button; light ink on top).
static func ribbon_style()->StyleBoxTexture:
	return padded("button_pressed",3,10,4)

## Recipe card for one meal.
static func card_style()->StyleBoxTexture:
	return padded("normal",3,6,5)

## Warm story sheet inside the memory page.
static func story_style()->StyleBoxTexture:
	return padded("life_paper",8,12,8)

## Slot frame around a speaker portrait.
static func portrait_style()->StyleBoxTexture:
	return padded("selected",3,4,4)

## Compact strip for the next-step guide / status line.
static func strip_style()->StyleBoxTexture:
	return padded("normal",3,6,3)

static func warning_style(border:Color)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=WARN_FILL
	style.border_color=border
	style.set_border_width_all(2)
	style.set_content_margin_all(6)
	style.anti_aliasing=false
	return style

## Bookmark-like story tab: tighter padding than the default Pixel button.
static func apply_tab(button:Button)->void:
	var states:={"normal":"button_normal","hover":"button_hover","pressed":"button_pressed","hover_pressed":"button_pressed","focus":"focus"}
	for state in states:
		button.add_theme_stylebox_override(state,padded(states[state],3,8,4))
	var disabled:=padded("button_normal",3,8,4)
	disabled.modulate_color=Color(1,1,1,0.55)
	button.add_theme_stylebox_override("disabled",disabled)
