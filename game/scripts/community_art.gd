extends RefCounted

const Furniture=preload("res://scripts/furniture_sprite_art.gd")
const PK=preload("res://scripts/public_kitchen.gd")
const Items=preload("res://assets/ui-inventory/items.png")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const SOUP:=Rect2(96,64,32,32)
const BREAD:=Rect2(128,64,32,32)
const RADISH:=Rect2(96,0,32,32)
const LETTUCE:=Rect2(128,0,32,32)
const SALAD:=Rect2(0,128,32,32)  # InventoryItemArt.IDS index 24
const MEAL_REGIONS:={"soup":SOUP,"bread":BREAD,"salad":SALAD}
const STEAM:=Color("fff2d4")
const SPARKLE:=Color("ffe7a0")
const DURATION_CONTRIBUTE:=2.0
const DURATION_OPENED:=4.0
const PLATE_OFFSETS:={"trout_hotpot":-18.0,"corn_chowder":0.0,"watermelon_platter":18.0}

static func draw_plates_served(canvas:CanvasItem,at:Vector2,event:Dictionary)->void:
	for plate:String in event:
		var progress:float=event[plate]
		var lift:=roundf(24.0*(1.0-pow(1.0-progress,2.0)))
		var alpha:=minf(progress*10.0,(1.0-progress)*3.0)
		var texture:=ItemArt.icon(plate)
		if texture==null:continue
		var center:=at.round()+Vector2(16+float(PLATE_OFFSETS[plate]),-4-lift)
		canvas.draw_texture_rect(texture,Rect2(center-Vector2(9,9),Vector2(18,18)),false,Color(1.0,1.0,1.0,alpha))
		var glint:=Color(SPARKLE,alpha)
		var spark:=center+Vector2(10,-5)
		canvas.draw_rect(Rect2(spark-Vector2(1,0),Vector2(3,1)),glint)
		canvas.draw_rect(Rect2(spark-Vector2(0,1),Vector2(1,3)),glint)

static func draw_portions_taken(canvas:CanvasItem,at:Vector2,event:Dictionary)->void:
	for plate:String in event:
		var progress:float=event[plate]
		var extent:=roundf(12.0-5.0*progress)
		var offset:=Vector2(float(PLATE_OFFSETS[plate]),-3.0-16.0*progress)
		var center:=(at+Vector2(16,0)+offset).round()
		var image:=ItemArt.icon(plate)
		var tint:=Color(1.0,1.0,1.0,1.0-progress)
		canvas.draw_texture_rect(image,Rect2(center-Vector2.ONE*extent*0.5,Vector2.ONE*extent),false,tint)

## Old 4-arg callers keep the original picnic spread. `kitchen` may be the
## public_kitchen Dictionary or a snapshot containing it; `feedback` is a
## CommunityFeedback.sample() result. `tea` is the plain tea view world_view derives
## ({"placed":true[,"style","left","cold"]}) or a raw tea_service record (see the
## 茶陶上桌 notes below); {} (default) draws nothing extra, so the output is
## pixel-identical to the 9-arg call.
## None of them is mutated.
## `chowder` (玉米濃湯 portions left on the table) adds a small tureen at the back-right
## of the tabletop (see CHOWDER_RECT); 0 (default) draws nothing, so older calls are unchanged.
static func draw_table(canvas:CanvasItem,at:Vector2,elapsed:float,reduced_motion:bool,kitchen:Dictionary={},feedback:Dictionary={},portions:=0,fruit:=0,warmer:=false,tea:Dictionary={},chowder:=0) -> void:
	var origin:=at.floor()
	# T067 保溫底座: drawn first so the table legs stand on it; it shows 3px past
	# both sides and along the bottom of the cell. Static in every motion mode.
	if warmer:draw_warmer(canvas,origin)
	if not Furniture.draw_sprite(canvas,origin,"table"):return
	if warmer:_draw_warmer_trim(canvas,origin)
	# 茶陶上桌: a small tea stand against the table's left end (outside the dishes,
	# the warmer slab and its copper caps; see TEA_RECT). Before the dishes so they win.
	if not tea.is_empty():draw_tea_set(canvas,origin,tea,elapsed,reduced_motion)
	# 玉米濃湯: drawn before the other dishes, so the nearer ones (watermelon tray, bread,
	# salad, a centred hotpot) overlap its lower part and it reads as standing behind them.
	if chowder>0:
		var spread:=portions<=0 and fruit<=0 and _opened(kitchen)
		draw_chowder(canvas,origin,chowder,spread)
		if not reduced_motion:
			var bowl:=CHOWDER_OPENED_RECT if spread else CHOWDER_RECT
			_draw_steam(canvas,origin+bowl.position+Vector2(2,0),elapsed,false)
	var soup_at:Vector2
	if portions>0:
		soup_at=origin+Vector2(2 if fruit>0 else 7,1)
		canvas.draw_texture_rect(ItemArt.icon("trout_hotpot"),Rect2(soup_at,Vector2(18,18)),false)
		# Up to four bowls keep the original 4px spacing; a warm round of six packs
		# narrower 3px bowls into the same 24px strip.
		var seats:=mini(portions,6)
		var wide:=seats<=4
		for seat in seats:
			var plate:=origin+Vector2(5+seat*6,19) if wide else origin+Vector2(4+seat*4,19)
			canvas.draw_rect(Rect2(plate,Vector2(4 if wide else 3,2)),Color("f6df9a"))
			canvas.draw_rect(Rect2(plate+Vector2(1,-1),Vector2(2 if wide else 1,1)),Color("fff3cb"))
	elif fruit>0:
		soup_at=origin+Vector2(2,5)
		canvas.draw_texture_rect_region(Items,Rect2(soup_at,Vector2(11,11)),SOUP)
	elif _opened(kitchen):
		soup_at=origin+Vector2(2,5)
		canvas.draw_texture_rect_region(Items,Rect2(soup_at,Vector2(11,11)),SOUP)
		canvas.draw_texture_rect_region(Items,Rect2(origin+Vector2(12,8),Vector2(10,10)),BREAD)
		canvas.draw_texture_rect_region(Items,Rect2(origin+Vector2(21,4),Vector2(10,10)),SALAD)
	else:
		soup_at=origin+Vector2(5,4)
		canvas.draw_texture_rect_region(Items,Rect2(soup_at,Vector2(12,12)),SOUP)
		canvas.draw_texture_rect_region(Items,Rect2(origin+Vector2(17,7),Vector2(11,11)),BREAD)
	_draw_steam(canvas,soup_at+Vector2(3,0),elapsed,reduced_motion)
	if fruit>0:_draw_watermelon(canvas,origin+Vector2(17,5),fruit)
	if reduced_motion:return
	match str(feedback.get("kind","")):
		"contribute":_draw_contribute(canvas,origin,feedback)
		"opened":_draw_opened(canvas,origin,feedback)

const WARM_EDGE:=Color("4a220e")
const WARM_LIGHT:=Color("ffcf6e")
const WARM_TOP:=Color("f0a03c")
const WARM_FRONT:=Color("9a4520")
const WARM_DARK:=Color("6a2e14")
const WARM_GLOW:=Color("fff0a8")
const WARM_SEAM:=Color("ffb63f")
const COPPER:=Color("c97a3e")
const COPPER_LIGHT:=Color("f2c08a")
const COPPER_DARK:=Color("7d4322")
## Screen-space rectangle (relative to the table cell origin) the base occupies.
const WARMER_RECT:=Rect2(-3,19,38,13)

## T067 保溫底座: a low warm-amber stone slab under the table (top face, front
## face with seams, a copper band and a few glowing specks). Program-drawn, static.
static func draw_warmer(canvas:CanvasItem,origin:Vector2) -> void:
	var o:=origin.floor()
	canvas.draw_rect(Rect2(o+Vector2(-2,31),Vector2(36,1)),Color(0.16,0.09,0.04,0.35))
	canvas.draw_rect(Rect2(o+Vector2(-3,19),Vector2(38,12)),WARM_EDGE)
	canvas.draw_rect(Rect2(o+Vector2(-2,20),Vector2(36,5)),WARM_TOP)
	canvas.draw_rect(Rect2(o+Vector2(-2,20),Vector2(36,1)),WARM_LIGHT)
	canvas.draw_rect(Rect2(o+Vector2(-2,25),Vector2(36,1)),COPPER)
	canvas.draw_rect(Rect2(o+Vector2(-2,26),Vector2(36,4)),WARM_FRONT)
	canvas.draw_rect(Rect2(o+Vector2(-2,29),Vector2(36,1)),WARM_DARK)
	# Glowing seams between the stone blocks of the front face (reads as "warm").
	for x in [5,14,23]:canvas.draw_rect(Rect2(o+Vector2(x,26),Vector2(1,3)),WARM_SEAM)
	canvas.draw_rect(Rect2(o+Vector2(8,27),Vector2(3,1)),WARM_SEAM)
	canvas.draw_rect(Rect2(o+Vector2(18,28),Vector2(3,1)),WARM_SEAM)
	for p:Vector2 in [Vector2(0,22),Vector2(3,23),Vector2(10,22),Vector2(19,23),Vector2(26,22),Vector2(30,23),Vector2(1,27),Vector2(30,27)]:
		canvas.draw_rect(Rect2(o+p,Vector2(1,1)),WARM_GLOW)

## Copper corner caps outside the table's own footprint (drawn after the sprite).
static func _draw_warmer_trim(canvas:CanvasItem,origin:Vector2) -> void:
	var o:=origin.floor()
	for corner:Vector2 in [Vector2(-3,19),Vector2(32,19),Vector2(-3,28),Vector2(32,28)]:
		canvas.draw_rect(Rect2(o+corner,Vector2(3,3)),COPPER)
		canvas.draw_rect(Rect2(o+corner,Vector2(3,1)),COPPER_LIGHT)
		canvas.draw_rect(Rect2(o+corner+Vector2(0,2),Vector2(3,1)),COPPER_DARK)

## 茶陶上桌 tea set. Program-drawn, palette from tea_revisit_art.gd (ivory/indigo pot,
## cream cups, red-brown tray) plus a walnut stand. Everything is relative to the
## table cell origin and stays inside TEA_RECT (x -26..0, y -6..29): left of the
## table top (x>=2), above the warmer slab (y>=19 for x>=-3) and its caps.
##   stand  slab x -26..0 y 16..18, legs x -24..-23 / -7..-6 y 19..28, stretcher y 23,
##          shadow x -25..-5 y 29
##   tray   x -25..0 y 5..15 (top edge y 5, surface y 6..13, front face y 14)
##   pot    body x -24..-18 y 6..12 (indigo band y 9), lid y 5, knob (-21,3..4),
##          handle x -26..-25, spout x -17
##   cups   4×4 each, seen from above (3/4 view): a cream rim ring (top row x+1..2, side
##          columns x+0 / x+3 on rows 1..2, bottom row x+1..2; the four corners show the
##          tray so the cup reads round) around a 2×2 surface (TEA_SURFACE, x+1..2 y+1..2).
##          Columns x -15 / -10 / -5, back row y 5..8 (cups 0..2), front row y 10..13 (3..5).
##          No indigo band on cups (the pot keeps it).
##   steam  above the knob (x -25..-17, y -8..2), only while fresh (not cold) cups remain
## Surface by state (strong value / hue steps; every pair of means ≥ 0.25 RGB distance):
##   never brewed  TEA_CUP_CLEAN d3c7a6, clean pale inside, no steam
##   drunk         TEA_CUP_CLEAN with one TEA_DREG 2e2016 dot at TEA_DREG_AT (x+2,y+2)
##   fresh light   TEA_LIGHT 9cba34 green-gold        cold light  TEA_LIGHT_COLD 6e7a4c
##   fresh deep    TEA_DEEP a8581c amber-brown         cold deep   TEA_DEEP_COLD 5c4232
## Serving n → the first n cups full, the rest drunk, steam wisp; cold (brewed on an
## earlier world day, n cups still in the pot) → the first n cups in the cold colour, the
## rest drunk, NO steam; finished (n=0) → all six drunk, no steam.
##
## `tea` shapes accepted by draw_table / draw_tea_set / tea_state:
##   * plain view from the caller (world_view derives it with TeaService.current_round on
##     the whole snapshot, which knows the world time):
##       {"placed":true}                                         # never brewed
##       {"placed":true,"style":"light"|"deep","left":int,"cold":bool}
##   * a raw tea_service record (client {"placed":true,"round":{...}} or server
##     {"lender":...}); the record alone carries no world time, so it never draws cold.
const TeaService=preload("res://scripts/tea_service.gd")
const TeaArt=preload("res://scripts/tea_revisit_art.gd")
const TEA_RECT:=Rect2(-26,-6,27,36)
## Cup slots (top-left of each 4×4 cup) relative to the table cell origin.
const TEA_CUPS:=[Vector2(-15,5),Vector2(-10,5),Vector2(-5,5),Vector2(-15,10),Vector2(-10,10),Vector2(-5,10)]
## The 2×2 tea surface inside each cup (offsets from the cup slot) and the dreg pixel.
const TEA_SURFACE:=[Vector2(1,1),Vector2(2,1),Vector2(1,2),Vector2(2,2)]
const TEA_DREG_AT:=Vector2(2,2)
## Rim pixels (offsets from the cup slot): top, sides, bottom; corners stay tray.
const TEA_RIM:=[Vector2(1,0),Vector2(2,0),Vector2(0,1),Vector2(3,1),Vector2(0,2),Vector2(3,2),Vector2(1,3),Vector2(2,3)]
const TEA_LIGHT:=Color("9cba34")
const TEA_DEEP:=Color("a8581c")
## Cold (yesterday's) tea: the same hues, greyer and darker than the fresh colours.
const TEA_LIGHT_COLD:=Color("6e7a4c")
const TEA_DEEP_COLD:=Color("5c4232")
## Clean inside of an empty cup (shaded below the cream rim) and the dark dreg dot.
const TEA_CUP_CLEAN:=Color("d3c7a6")
const TEA_DREG:=Color("2e2016")
const STAND_LIGHT:=Color("a77a50")
const STAND_WOOD:=Color("7c5636")
const STAND_DARK:=Color("4f3420")

## {"placed":bool,"style":""|"light"|"deep","portions":int,"brewed":bool,"cold":bool}
## for either `tea` shape above; "portions" is the number of cups still holding tea
## (drinkable or cold).
static func tea_state(tea:Dictionary) -> Dictionary:
	if tea.has("style"):
		var style_found:Variant=tea.get("style")
		var style:String=str(style_found) if TeaService.STYLES.has(style_found) else ""
		var raw:Variant=tea.get("left",0)
		var count:int=clampi(int(raw),0,TeaService.CUPS) if (raw is int or raw is float) and not style.is_empty() else 0
		return {"placed":tea.get("placed")==true,"style":style,"portions":count,"brewed":not style.is_empty(),"cold":not style.is_empty() and tea.get("cold")==true}
	var wrapped:={TeaService.STATE_KEY:tea}
	var on_table:bool=TeaService.placed(wrapped)
	var now:Dictionary=TeaService.current_round(wrapped)
	var left:int=clampi(int(now.get("left",0)),0,TeaService.CUPS) if not now.is_empty() else 0
	return {"placed":on_table,"style":str(now.get("style","")),"portions":left,"brewed":not now.is_empty(),"cold":false}

static func tea_colour(style:String,cold:bool=false) -> Color:
	if cold:return TEA_DEEP_COLD if style=="deep" else TEA_LIGHT_COLD
	return TEA_DEEP if style=="deep" else TEA_LIGHT

static func draw_tea_set(canvas:CanvasItem,origin:Vector2,tea:Dictionary,elapsed:float,reduced_motion:bool) -> void:
	var st:=tea_state(tea)
	if not st.placed:return
	var o:=origin.floor()
	# Stand: a low walnut side table flush with the table's left end.
	canvas.draw_rect(Rect2(o+Vector2(-25,29),Vector2(21,1)),TeaArt.SHADOW)
	canvas.draw_rect(Rect2(o+Vector2(-24,19),Vector2(2,10)),STAND_DARK)
	canvas.draw_rect(Rect2(o+Vector2(-7,19),Vector2(2,10)),STAND_DARK)
	canvas.draw_rect(Rect2(o+Vector2(-22,23),Vector2(15,1)),STAND_WOOD)
	canvas.draw_rect(Rect2(o+Vector2(-26,16),Vector2(27,1)),STAND_LIGHT)
	canvas.draw_rect(Rect2(o+Vector2(-26,17),Vector2(27,1)),STAND_WOOD)
	canvas.draw_rect(Rect2(o+Vector2(-26,18),Vector2(27,1)),STAND_DARK)
	# Tray (same wood as the 茶陶組 sprite).
	canvas.draw_rect(Rect2(o+Vector2(-25,5),Vector2(26,11)),TeaArt.TRAY_DARK)
	canvas.draw_rect(Rect2(o+Vector2(-24,5),Vector2(24,1)),TeaArt.TRAY_LIGHT)
	canvas.draw_rect(Rect2(o+Vector2(-24,6),Vector2(24,8)),TeaArt.TRAY)
	canvas.draw_rect(Rect2(o+Vector2(-24,14),Vector2(24,1)),TeaArt.TRAY_FACE)
	# Teapot: ivory body with the indigo band, lid, knob, C handle and spout.
	canvas.draw_rect(Rect2(o+Vector2(-24,6),Vector2(7,7)),TeaArt.OUTLINE)
	canvas.draw_rect(Rect2(o+Vector2(-23,7),Vector2(5,5)),TeaArt.GLAZE)
	canvas.draw_rect(Rect2(o+Vector2(-23,9),Vector2(5,1)),TeaArt.BLUE)
	canvas.draw_rect(Rect2(o+Vector2(-23,11),Vector2(5,1)),TeaArt.GLAZE_DARK)
	canvas.draw_rect(Rect2(o+Vector2(-23,7),Vector2(1,1)),TeaArt.GLAZE_LIGHT)
	canvas.draw_rect(Rect2(o+Vector2(-23,5),Vector2(5,1)),TeaArt.OUTLINE)
	canvas.draw_rect(Rect2(o+Vector2(-22,5),Vector2(3,1)),TeaArt.BLUE)
	canvas.draw_rect(Rect2(o+Vector2(-21,3),Vector2(1,2)),TeaArt.OUTLINE)
	canvas.draw_rect(Rect2(o+Vector2(-26,7),Vector2(1,4)),TeaArt.OUTLINE)
	canvas.draw_rect(Rect2(o+Vector2(-25,7),Vector2(1,1)),TeaArt.OUTLINE)
	canvas.draw_rect(Rect2(o+Vector2(-25,10),Vector2(1,1)),TeaArt.OUTLINE)
	canvas.draw_rect(Rect2(o+Vector2(-17,7),Vector2(1,4)),TeaArt.OUTLINE)
	# Six cups seen from above: cream rim ring around a 2×2 surface. The first `portions`
	# hold tea (cold tea in the grey-dark colour); the others are clean before the first
	# brew and keep one dark dreg dot once a round has been brewed.
	var cold:bool=st.cold
	var cup_tint:=tea_colour(str(st.style),cold)
	var left:int=st.portions
	for index in TEA_CUPS.size():
		var cup:Vector2=o+TEA_CUPS[index]
		for rim:Vector2 in TEA_RIM:canvas.draw_rect(Rect2(cup+rim,Vector2(1,1)),TeaArt.CREAM)
		canvas.draw_rect(Rect2(cup+Vector2(1,1),Vector2(2,2)),cup_tint if index<left else TEA_CUP_CLEAN)
		if index>=left and st.brewed:canvas.draw_rect(Rect2(cup+TEA_DREG_AT,Vector2(1,1)),TEA_DREG)
	if left>0 and not cold:_draw_tea_steam(canvas,o+Vector2(-22,2),elapsed,reduced_motion)

## One small wisp above the teapot knob, same approach as _draw_steam (two rising
## pixel puffs fading out). Reduced motion: one static wisp.
static func _draw_tea_steam(canvas:CanvasItem,base:Vector2,elapsed:float,reduced:bool) -> void:
	if reduced or not is_finite(elapsed):
		var still:=STEAM
		still.a=0.45
		canvas.draw_rect(Rect2(base+Vector2(1,-2),Vector2(1,2)),still)
		canvas.draw_rect(Rect2(base+Vector2(2,-4),Vector2(1,1)),still)
		return
	for index in 2:
		var phase:=fposmod(elapsed*0.45+float(index)*0.5,1.0)
		var rise:=floorf(phase*6.0)
		var drift:=roundf(sin(phase*TAU+float(index)*2.0))
		var point:=base+Vector2(float(index)+drift,-1.0-rise)
		var tint:=STEAM
		tint.a=0.5*(1.0-phase)
		canvas.draw_rect(Rect2(point,Vector2(2,1)),tint)
		canvas.draw_rect(Rect2(point+Vector2(1,-1),Vector2(1,1)),tint)

static func _draw_watermelon(canvas:CanvasItem,at:Vector2,portions:int)->void:
	canvas.draw_texture_rect(ItemArt.icon("watermelon_platter"),Rect2(at-Vector2(1,0),Vector2(16,14)),false)
	for index in mini(portions,4):
		var mark:=at+Vector2(2+index*3,12)
		canvas.draw_rect(Rect2(mark,Vector2(2,1)),Color("e9b590"))

## 玉米濃湯 on the shared table: a 10×7 blue-banded tureen of yellow soup standing at the
## back-right of the tabletop (its base on the table's back edge). It is drawn before the
## other dishes: the watermelon tray, the bread or a centred hotpot cover its lower rows;
## the two soup rows with the kernel dots (one per portion left, up to four) stay visible.
## With the opened-kitchen spread the salad sits there, so the tureen moves up three
## pixels (CHOWDER_OPENED_RECT) and shows above the salad. The bowl itself stays still.
const CHOWDER_RECT:=Rect2(21,3,10,7)
const CHOWDER_OPENED_RECT:=Rect2(21,0,10,7)
const CHOWDER_EDGE:=Color("4a3a2e")
const CHOWDER_SOUP:=Color("f6d25a")
const CHOWDER_KERNEL:=Color("d98f1f")
const CHOWDER_BODY:=Color("f3efe2")
const CHOWDER_BAND:=Color("5f8fb0")
const CHOWDER_KERNELS:=[Vector2(2,1),Vector2(4,2),Vector2(6,1),Vector2(7,2)]
static func draw_chowder(canvas:CanvasItem,origin:Vector2,portions:int,opened_spread:=false) -> void:
	var at:=origin+(CHOWDER_OPENED_RECT.position if opened_spread else CHOWDER_RECT.position)
	canvas.draw_rect(Rect2(at+Vector2(1,0),Vector2(8,1)),CHOWDER_EDGE)
	canvas.draw_rect(Rect2(at+Vector2(0,1),Vector2(10,5)),CHOWDER_EDGE)
	canvas.draw_rect(Rect2(at+Vector2(2,6),Vector2(6,1)),CHOWDER_EDGE)
	canvas.draw_rect(Rect2(at+Vector2(1,1),Vector2(8,2)),CHOWDER_SOUP)
	canvas.draw_rect(Rect2(at+Vector2(1,3),Vector2(8,3)),CHOWDER_BODY)
	canvas.draw_rect(Rect2(at+Vector2(1,4),Vector2(8,1)),CHOWDER_BAND)
	for index in mini(portions,CHOWDER_KERNELS.size()):
		canvas.draw_rect(Rect2(at+CHOWDER_KERNELS[index],Vector2(1,1)),CHOWDER_KERNEL)

static func _opened(kitchen:Dictionary) -> bool:
	var data=kitchen.get("public_kitchen",kitchen)
	return data is Dictionary and PK.shape_ok(data) and data.opened

static func _age(feedback:Dictionary,duration:float) -> float:
	var age=feedback.get("age")
	if not (age is float or age is int) or not is_finite(float(age)):return -1.0
	return float(age) if float(age)>=0.0 and float(age)<duration else -1.0

static func _meals(feedback:Dictionary) -> Array[String]:
	var out:Array[String]=[]
	var list=feedback.get("meals",[])
	if not list is Array:return out
	for item in list:
		if item is String and MEAL_REGIONS.has(item) and not item in out:out.append(item)
	return out

## Two or three faint pixel wisps above the soup. Reduced motion: one static wisp.
static func _draw_steam(canvas:CanvasItem,base:Vector2,elapsed:float,reduced:bool) -> void:
	if reduced or not is_finite(elapsed):
		var still:=STEAM
		still.a=0.35
		canvas.draw_rect(Rect2(base+Vector2(2,-3),Vector2(2,2)),still)
		canvas.draw_rect(Rect2(base+Vector2(3,-5),Vector2(1,1)),still)
		return
	for index in 3:
		var phase:=fposmod(elapsed*0.4+float(index)/3.0,1.0)
		var rise:=floorf(phase*8.0)
		var drift:=roundf(sin(phase*TAU+float(index)*2.0))
		var point:=base+Vector2(float(index*2)+drift,-1.0-rise)
		var tint:=STEAM
		tint.a=0.45*(1.0-phase)
		canvas.draw_rect(Rect2(point,Vector2(2,1)),tint)
		canvas.draw_rect(Rect2(point+Vector2(1,-1),Vector2(1,1)),tint)

## Contributed dish icons float up ~16px above the table and fade out.
static func _draw_contribute(canvas:CanvasItem,origin:Vector2,feedback:Dictionary) -> void:
	var age:=_age(feedback,DURATION_CONTRIBUTE)
	if age<0.0:return
	var meals:=_meals(feedback)
	if meals.is_empty():return
	var t:=age/DURATION_CONTRIBUTE
	var rise:=floorf(16.0*(1.0-pow(1.0-t,2.0)))
	var fade:=Color(1,1,1,clampf((1.0-t)*1.6,0.0,1.0))
	var start_x:=16.0-floorf(float(meals.size()*11)*0.5)
	for index in meals.size():
		var pos:=origin+Vector2(start_x+index*11,-8.0-rise)
		canvas.draw_texture_rect_region(Items,Rect2(pos,Vector2(10,10)),MEAL_REGIONS[meals[index]],fade)

## Opening: the three dishes hop gently above the table with a few soft sparkles.
static func _draw_opened(canvas:CanvasItem,origin:Vector2,feedback:Dictionary) -> void:
	var age:=_age(feedback,DURATION_OPENED)
	if age<0.0:return
	var t:=age/DURATION_OPENED
	var alpha:=clampf(minf(age/0.4,(DURATION_OPENED-age)/1.0),0.0,1.0)
	var order:=["soup","bread","salad"]
	for index in order.size():
		var hop:=floorf(maxf(0.0,sin(age*PI*1.5-float(index)*0.6))*4.0)
		var rise:=floorf(10.0*minf(t*3.0,1.0))
		var pos:=origin+Vector2(1+index*11,-10.0-rise-hop)
		canvas.draw_texture_rect_region(Items,Rect2(pos,Vector2(10,10)),MEAL_REGIONS[order[index]],Color(1,1,1,alpha))
	# Eight tiny twinkles on a ring (<= 24px from the table centre).
	var centre:=origin+Vector2(16,-4)
	var frame:=int(age*6.0)
	for index in 8:
		if (frame+index)%3==0:continue
		var angle:=float(index)*TAU/8.0+t*0.8
		var radius:=18.0+float(index%2)*5.0
		var point:=(centre+Vector2(cos(angle),sin(angle)*0.6)*radius).floor()
		var tint:=SPARKLE
		tint.a=0.55*alpha
		canvas.draw_rect(Rect2(point,Vector2(1,1)),tint)
		if (frame+index)%3==1:
			canvas.draw_rect(Rect2(point+Vector2(-1,0),Vector2(3,1)),tint*Color(1,1,1,0.6))
			canvas.draw_rect(Rect2(point+Vector2(0,-1),Vector2(1,3)),tint*Color(1,1,1,0.6))

static func draw_shop_detail(canvas:CanvasItem,at:Vector2,snapshot:Dictionary) -> void:
	if not snapshot.get("chapter_one",{}).get("shipped",false):return
	canvas.draw_texture_rect_region(Items,Rect2(at+Vector2(2,17),Vector2(11,11)),RADISH)
	canvas.draw_texture_rect_region(Items,Rect2(at+Vector2(20,17),Vector2(10,10)),LETTUCE)
