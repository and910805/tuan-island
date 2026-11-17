extends SceneTree
## T048 四季休眠與再生作物 — native render check of the dormant crop look (cool grey-blue
## DORMANT_TINT + two small「z」marks, crop_sprite_art.draw_crop(...,dormant)) and the HUD
## tool hint (Main.dormant_crop_hint) at 1024×640 and 1280×800. Run non-headless:
##   --script res://tests/test_season_dormancy_scene.gd -- --profile=isolated-regression
## Screenshots go to outputs/作物休眠預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_corn_chowder_scene.gd / test_water_tower_quota_scene.gd (host save,
## settle/grab/shot, view_to_pixels cell mapping, nearest-neighbour close-up crops, ending).
##
## FIELD (home, row y=37, all plots mine, all wet, nothing else on the row):
##   x=40 a tomato 70%（夏）        x=41 b same tomato under a greenhouse_roof
##   x=42 c pumpkin 70%（秋）       x=43 d ripe tomato, remaining 3
##   x=44 e strawberry at regrow_start, remaining 2（春）
##   x=45 f watermelon 70%（夏, harvest atlas）  x=46 g bluebell 70%（春, FlowerArt sheet）
##   x=47 h empty tilled plot
## Day 29 (index 28) = first autumn day, day 15 (index 14) = first summer day; both are
## sunny in weather.gd's 7-day cycle (index % 7 == 0), so no weather tint / rain marks.
## Dormant in autumn: a e f g.  Dormant in summer: c e g.
##
## PRESET / FIXTURE (not human play, nothing here goes through a player action):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.removed written for base-resource tiles in x 38..49, y 35..40, and any
##    objects / ground / crops / roofs on those tiles erased;
##  * state.crops written for the eight plots a..h (erased again before the final save);
##  * state.roofs written: a greenhouse_roof over plot b (erased again before the save);
##  * state.time written to the first autumn day 08:00 and the first summer day 08:00;
##  * the local player is teleported by writing region/x/y;
##  * app.view.reduced_motion set directly (on for every capture);
##  * pointer stand-ins (main._process is off): app.target, app.view.target,
##    app.view.show_target, app.view.selected written directly; the tool itself is chosen
##    with the real app._select_tool("water"/"harvest"/"hoe").
## REALLY EXERCISED: Session._send_snapshot -> world_view._draw -> draw_crop_tile ->
##  crop_dormant (World.plot_dormant on the snapshot incl. roofs) -> crop_sprite_art.draw_crop
##  (crops.png / BakeryArt / FlowerArt paths) on the native renderer; main._refresh_hud ->
##  dormant_crop_hint / WeatherForecast.water_hint into the HUD ToolHint label.
## NOT EXERCISED: World.step growth across seasons, watering / harvesting actions, input.
##
## SHOTS per size (5): autumn, autumn_hint_a, summer, crop_autumn (×4), crop_summer (×4)
##  -> 10 in total.
## Season changes no world art outside the crops (weather is sunny on both days, world_view
## draws nothing else by season); the HUD calendar / status text does change, so the
## "nothing else changed" band check excludes every HUD panel rect.
const World=preload("res://scripts/world.gd")
const Weather=preload("res://scripts/weather.gd")
const WeatherForecast=preload("res://scripts/weather_forecast.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const CropArt=preload("res://scripts/crop_sprite_art.gd")
const BakeryArt=preload("res://scripts/bakery_art.gd")
const FlowerArt=preload("res://scripts/flower_art.gd")
const Main=preload("res://scripts/main.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const ROW:=37
const A:=Vector2i(40,ROW)
const B:=Vector2i(41,ROW)
const C:=Vector2i(42,ROW)
const D:=Vector2i(43,ROW)
const E:=Vector2i(44,ROW)
const F:=Vector2i(45,ROW)
const G:=Vector2i(46,ROW)
const H:=Vector2i(47,ROW)
const LETTERS:=["a","b","c","d","e","f","g","h"]
const PLOT_CELLS:={"a":A,"b":B,"c":C,"d":D,"e":E,"f":F,"g":G,"h":H}
const KINDS:={"a":"tomato","b":"tomato","c":"pumpkin","d":"tomato","e":"strawberry","f":"watermelon","g":"bluebell","h":""}
const DORMANT_AUTUMN:=["a","e","f","g"]
const DORMANT_SUMMER:=["c","e","g"]
## South of the row, centred on it; the name label stays below y=38.5.
const VIEW_SPOT:=Vector2(44.0,40.8)
const AUTUMN_TIME:=28.0*1440.0+480.0
const SUMMER_TIME:=14.0*1440.0+480.0
const RIPE_HINT:=Color("ffe7a0")
const HINT_A:="太陽番茄休眠中 · 夏季會接著長（進度保留） · 還能收 3 次 · 蓋溫室玻璃棚可不分季節"
const HINT_E:="蜜香草莓休眠中 · 春季會接著長（進度保留） · 還能收 2 次 · 蓋溫室玻璃棚可不分季節"
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var written:=PackedStringArray()
var mark_area:={}
var shadow_only:Array[Vector2i]=[]

func _initialize()->void:run.call_deferred()

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)
		print("FAIL %s"%message)

func finish()->void:
	if finished:return
	finished=true
	print("SEASON_DORMANCY_FILES %d"%written.size())
	for file in written:print("SEASON_DORMANCY_FILE %s"%file)
	print("SEASON_DORMANCY_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func save_image(image:Image,step:String,want:Vector2i)->void:
	var file:String=output.path_join("%s_%s.png"%[tag,step])
	expect(image.save_png(file)==OK,"native screenshot saved %s"%file.get_file())
	shots+=1
	written.append(file)
	print("SEASON_DORMANCY_SHOT %s"%file)
	expect(FileAccess.file_exists(file),"Screenshot file exists %s"%file.get_file())
	var back:=Image.load_from_file(file)
	expect(back!=null and not back.is_empty() and back.get_size()==want,"Screenshot file %s has size %s"%[file.get_file(),str(want)])
	if back!=null and not back.is_empty():expect(colour_variety(back)>=12,"Screenshot file is not blank %s (%d colours)"%[file.get_file(),colour_variety(back)])

func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func shot(step:String)->Image:
	var image:=await grab()
	expect(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	expect(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s) %s"%[tag,step,str(image.get_size())])
	expect(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	save_image(image,step,root.size)
	return image

func person()->Dictionary:
	return w.state.players[id]

func k(c:Vector2i)->String:
	return World.key(c)

func cell_of(letter:String)->Vector2i:
	var c:Vector2i=PLOT_CELLS[letter]
	return c

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	await settle()

func colour_near(a:Color,b:Color,tolerance:float=0.03)->bool:
	return absf(a.r-b.r)<=tolerance and absf(a.g-b.g)<=tolerance and absf(a.b-b.b)<=tolerance

# ------------------------------------------------------------------ state --

func growth_at(kind:String,share:float)->float:
	return float(World.CROPS[kind].time)*share

func plot(kind:String,growth:float,remaining:int)->Dictionary:
	return {"kind":kind,"growth":growth,"wet":true,"owner":id,"remaining":remaining}

func write_field()->void:
	for x in range(38,50):
		for y in range(35,41):
			var c:=Vector2i(x,y)
			if World.base_resource(c)!="":w.state.removed[k(c)]=true  # PRESET
			for field:String in ["objects","ground","crops","roofs"]:
				if w.state.has(field) and (w.state[field] as Dictionary).has(k(c)):(w.state[field] as Dictionary).erase(k(c))  # PRESET
	var crops:Dictionary=w.state.crops
	crops[k(A)]=plot("tomato",growth_at("tomato",0.7),3)  # PRESET
	crops[k(B)]=plot("tomato",growth_at("tomato",0.7),3)  # PRESET
	crops[k(C)]=plot("pumpkin",growth_at("pumpkin",0.7),1)  # PRESET
	crops[k(D)]=plot("tomato",growth_at("tomato",1.0),3)  # PRESET
	crops[k(E)]=plot("strawberry",World.regrow_start("strawberry"),2)  # PRESET
	crops[k(F)]=plot("watermelon",growth_at("watermelon",0.7),1)  # PRESET
	crops[k(G)]=plot("bluebell",growth_at("bluebell",0.7),1)  # PRESET
	crops[k(H)]={"kind":"","growth":0.0,"wet":true,"owner":id}  # PRESET
	w.state.roofs[k(B)]={"type":"greenhouse_roof","owner":id,"items":{}}  # PRESET

func erase_field()->void:
	for letter:String in LETTERS:(w.state.crops as Dictionary).erase(k(cell_of(letter)))  # PRESET cleanup
	(w.state.roofs as Dictionary).erase(k(B))  # PRESET cleanup

func set_time(t:float)->void:
	w.state.time=t  # PRESET
	await refresh()

func pointer_off()->void:
	app.view.show_target=false  # PRESET (pointer stand-in)

# ------------------------------------------------------------- pixel helpers --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## Screen pixels per view pixel (the world zoom as rendered).
func px_scale()->float:
	return maxf(1.0,view_to_pixels(Rect2(0,0,10,10)).size.x/10.0)

## A GUI global rect in screenshot pixels.
func gui_box(r:Rect2)->Rect2i:
	var xf:Transform2D=root.get_final_transform()
	var a:Vector2=xf*r.position
	var b:Vector2=xf*r.end
	return Rect2i(Vector2i(a.round()),Vector2i((b-a).round()))

func cell_origin(c:Vector2i)->Vector2:
	var at:Vector2=app.view.screen(Vector2(c))
	return at

func cell_box(c:Vector2i)->Rect2i:
	return pixel_box(Rect2(cell_origin(c),Vector2(32,32)))

## Screenshot pixel at the centre of view pixel (i,j) of cell c.
func screen_pixel(c:Vector2i,i:int,j:int)->Vector2i:
	var p:Vector2=view_to_pixels(Rect2(cell_origin(c)+Vector2(i+0.5,j+0.5),Vector2.ZERO)).position
	return Vector2i(int(floorf(p.x)),int(floorf(p.y)))

## 32×32 samples of a cell (one per view pixel), row-major.
func cell_samples(image:Image,c:Vector2i)->PackedColorArray:
	var out:=PackedColorArray()
	out.resize(1024)
	var bounds:=Rect2i(Vector2i.ZERO,image.get_size())
	for j in 32:
		for i in 32:
			var q:=screen_pixel(c,i,j)
			out[j*32+i]=image.get_pixel(q.x,q.y) if bounds.has_point(q) else Color(0,0,0,0)
	return out

func all_samples(image:Image)->Dictionary:
	var result:={}
	if image==null or image.is_empty():return result
	for letter:String in LETTERS:result[letter]=cell_samples(image,cell_of(letter))
	return result

func row_box()->Rect2i:
	return pixel_box(Rect2(cell_origin(A),Vector2(8*32,32)))

## Plots plus the greenhouse roof overhang (8 px above row y=37) and a small margin.
func crop_box()->Rect2i:
	return pixel_box(Rect2(cell_origin(A)+Vector2(-4,-12),Vector2(8*32+8,32+18)))

## ×4 nearest-neighbour close-up strip of the plots for review.
func save_crop(image:Image,step:String)->void:
	if image==null or image.is_empty():return
	var whole:=crop_box()
	var box:=whole.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	expect(box==whole and box.size.x>0 and box.size.y>0,"Close-up region fully on screen (%s_%s) %s"%[tag,step,str(whole)])
	if box.size.x<=0 or box.size.y<=0:return
	var crop:=image.get_region(box)
	crop.resize(box.size.x*4,box.size.y*4,Image.INTERPOLATE_NEAREST)
	save_image(crop,step,crop.get_size())

func hud_rects()->Array[Rect2i]:
	var result:Array[Rect2i]=[]
	if not is_instance_valid(app.hud) or not (app.hud as CanvasItem).is_visible_in_tree():return result
	for child in (app.hud as Node).get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree() or c.size.x<=0 or c.size.y<=0:continue
		result.append(gui_box(c.get_global_rect()))
	return result

## Pixels changed inside `region` but outside every rect in `exclude` (exact compare).
func changed_outside(a:Image,b:Image,region:Rect2i,exclude:Array[Rect2i])->int:
	if a==null or b==null or a.get_size()!=b.get_size():return -1
	region=region.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if region.size.x<=0 or region.size.y<=0:return -1
	var changed:=0
	for x in range(region.position.x,region.end.x):
		for y in range(region.position.y,region.end.y):
			var skip:=false
			for r:Rect2i in exclude:
				if r.has_point(Vector2i(x,y)):
					skip=true
					break
			if skip:continue
			if a.get_pixel(x,y)!=b.get_pixel(x,y):changed+=1
	return changed

# ---------------------------------------------------------------- sprites --

func texture_image(texture:Texture2D)->Image:
	if texture==null:return null
	var source:Image=texture.get_image()
	if source==null or source.is_empty():return null
	var image:=source.duplicate() as Image
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

## The 32×32 plant sprite draw_crop uses for `kind` at `stage` (alpha = opaque area).
func plant_sprite(kind:String,stage:int)->Image:
	if kind=="pumpkin":return texture_image(BakeryArt.growth_texture(stage))
	if FlowerArt.has_crop(kind):return texture_image(FlowerArt.crop_texture(kind,stage))
	var art=app.view.crop_art
	if art==null:return null
	var atlas:Texture2D=art.atlas
	var row:=CropArt.ROWS.find(kind)
	if kind in CropArt.KITCHEN_GARDEN_ROWS:
		atlas=art.kitchen_garden
		row=CropArt.KITCHEN_GARDEN_ROWS.find(kind)
	elif kind in CropArt.HARVEST_ROWS:
		atlas=art.harvest
		row=CropArt.HARVEST_ROWS.find(kind)
	var whole:=texture_image(atlas)
	if whole==null:return null
	if row<0:return null
	return whole.get_region(Rect2i(stage*CropArt.CELL.x,row*CropArt.CELL.y,CropArt.CELL.x,CropArt.CELL.y))

func plot_stage(letter:String)->int:
	var crop:Dictionary=w.state.crops.get(k(cell_of(letter)),{})
	return CropArt.stage_for(crop)

# ----------------------------------------------------------------- checks --

## Rule check on the snapshot the view draws from: World.plot_dormant / view.crop_dormant.
func logic_check(season:String,dormant:Array)->void:
	var snap:Dictionary=app.session.snapshot
	var t:float=float(snap.get("time",0.0))
	expect(Weather.season_on_day(Weather.day_index(t))==season,"Snapshot day is %s (%s): day %d"%[season,tag,int(Weather.day_index(t))+1])
	var info:Dictionary=WeatherArt.current(app.view.data)
	expect(str(info.get("id",""))=="sunny","Sunny on the %s day, no weather tint (%s): %s"%[season,tag,str(info.get("id",""))])
	var crops:Dictionary=snap.get("crops",{})
	var roofs:Dictionary=snap.get("roofs",{})
	var region:String=str(snap.get("region_id",World.REGIONS.HOME))
	expect(region==World.REGIONS.HOME,"Snapshot region is home (%s): %s"%[tag,region])
	expect(roofs.has(k(B)),"Snapshot carries the greenhouse roof over plot b (%s)"%tag)
	for letter:String in LETTERS:
		var c:=cell_of(letter)
		var crop:Dictionary=crops.get(k(c),{})
		expect(not crop.is_empty() and str(crop.get("kind",""))==str(KINDS[letter]),"Snapshot plot %s holds %s (%s %s)"%[letter,str(KINDS[letter]),season,tag])
		var want:bool=letter in dormant
		var rule:bool=World.plot_dormant(crop,roofs.get(k(c),{}),region,c,t)
		var drawn:bool=app.view.crop_dormant(c,crop)
		expect(rule==want and drawn==want,"Plot %s dormant=%s in %s (%s): plot_dormant %s, view.crop_dormant %s"%[letter,str(want),season,tag,str(rule),str(drawn)])

## Every DORMANT_PIXELS position (and every shadow-only position) has the mark colours on the
## dormant plots; the awake plots have no mark colour there.
func marks_check(samples:Dictionary,season:String,dormant:Array)->void:
	if samples.is_empty():
		expect(false,"No samples for the %s marks check (%s)"%[season,tag])
		return
	for letter:String in LETTERS:
		var c:=cell_of(letter)
		var s:PackedColorArray=samples[letter]
		var hits:=0
		var miss:=""
		for p:Vector2i in CropArt.DORMANT_PIXELS:
			var colour:Color=s[p.y*32+p.x]
			if colour_near(colour,CropArt.DORMANT_MARK):hits+=1
			elif miss.is_empty():miss="view px %s screen px %s colour %s"%[str(p),str(screen_pixel(c,p.x,p.y)),colour.to_html(false)]
		var shade:=0
		var shade_miss:=""
		for p:Vector2i in shadow_only:
			var colour:Color=s[p.y*32+p.x]
			if colour_near(colour,CropArt.DORMANT_MARK_SHADE):shade+=1
			elif shade_miss.is_empty():shade_miss="view px %s screen px %s colour %s"%[str(p),str(screen_pixel(c,p.x,p.y)),colour.to_html(false)]
		var total:int=CropArt.DORMANT_PIXELS.size()
		if letter in dormant:
			expect(hits==total,"Plot %s (%s %s): %d/%d z-mark pixels in DORMANT_MARK; first miss %s"%[letter,season,tag,hits,total,miss])
			expect(shade==shadow_only.size(),"Plot %s (%s %s): %d/%d mark shadow pixels in DORMANT_MARK_SHADE; first miss %s"%[letter,season,tag,shade,shadow_only.size(),shade_miss])
		else:
			# Plot b is under the greenhouse roof's pale glass: allow a few near-matches there.
			var limit:=3 if letter=="b" else 0
			expect(hits<=limit,"Plot %s (%s %s) is awake: %d z-mark positions have the mark colour (max %d)"%[letter,season,tag,hits,limit])

## dormant vs awake capture of one plot: soil (sprite alpha 0, outside the mark) identical,
## opaque plant pixels changed and darker / bluer (mean R relative to B lower).
func seasonal_pair(letter:String,dormant:PackedColorArray,awake:PackedColorArray,label:String)->void:
	var kind:String=KINDS[letter]
	var stage:=plot_stage(letter)
	var sprite:=plant_sprite(kind,stage)
	expect(sprite!=null and sprite.get_size()==Vector2i(32,32),"Plant sprite for plot %s (%s stage %d) available (%s)"%[letter,kind,stage,label])
	if sprite==null or sprite.get_size()!=Vector2i(32,32):return
	var soil:=0
	var soil_changed:=0
	var soil_first:=""
	var opaque:=0
	var opaque_changed:=0
	var dr:=0.0;var db:=0.0;var dl:=0.0
	var ar:=0.0;var ab:=0.0;var al:=0.0
	for j in 32:
		for i in 32:
			if mark_area.has(Vector2i(i,j)):continue
			var alpha:float=sprite.get_pixel(i,j).a
			var x:Color=dormant[j*32+i]
			var y:Color=awake[j*32+i]
			if alpha<=0.0:
				soil+=1
				if x!=y:
					soil_changed+=1
					if soil_first.is_empty():soil_first="view px (%d,%d) screen px %s %s vs %s"%[i,j,str(screen_pixel(cell_of(letter),i,j)),x.to_html(false),y.to_html(false)]
			elif alpha>=0.99:
				opaque+=1
				if x!=y:
					opaque_changed+=1
					dr+=x.r;db+=x.b;dl+=x.r+x.g+x.b
					ar+=y.r;ab+=y.b;al+=y.r+y.g+y.b
	print("NOTE %s plot %s: soil %d px (%d changed), plant %d px (%d changed), dormant R/B %.3f awake R/B %.3f"%[label,letter,soil,soil_changed,opaque,opaque_changed,dr/maxf(db,0.001),ar/maxf(ab,0.001)])
	expect(soil>=64,"Plot %s has soil around the sprite (%s): %d px"%[letter,label,soil])
	expect(soil_changed==0,"Plot %s soil identical dormant vs awake (%s): %d px changed, first %s"%[letter,label,soil_changed,soil_first])
	expect(opaque>=20,"Plot %s sprite has an opaque area (%s): %d px"%[letter,label,opaque])
	expect(opaque_changed*2>=opaque,"Plot %s plant pixels tinted while dormant (%s): %d/%d changed"%[letter,label,opaque_changed,opaque])
	if opaque_changed>0 and db>0.001 and ab>0.001:
		expect(dr/db<ar/ab*0.97,"Plot %s dormant plant is bluer: mean R/B %.3f vs awake %.3f (%s)"%[letter,dr/db,ar/ab,label])
		expect(dl<al,"Plot %s dormant plant is darker: %.1f vs %.1f (%s)"%[letter,dl,al,label])
	else:expect(false,"Plot %s tint comparison has data (%s)"%[letter,label])

func cell_mismatches(x:PackedColorArray,y:PackedColorArray)->int:
	var n:=0
	for index in range(mini(x.size(),y.size())):
		if x[index]!=y[index]:n+=1
	return n

func ripe_hint_check(samples:Dictionary,season:String)->void:
	if not samples.has("d"):return
	var s:PackedColorArray=samples["d"]
	for p:Vector2i in [Vector2i(27,7),Vector2i(24,4),Vector2i(29,5)]:
		var colour:Color=s[p.y*32+p.x]
		expect(colour_near(colour,RIPE_HINT),"Plot d ripe hint at view px %s (%s %s): %s"%[str(p),season,tag,colour.to_html(false)])

func on_screen_check(label:String)->void:
	var box:=row_box()
	print("NOTE %s: zoom %.2f, %.2f screen px per view px, plot row %s"%[label,float(app.view.view_zoom()),px_scale(),str(box)])
	expect(Rect2i(Vector2i.ZERO,root.size).encloses(box),"Whole plot row on screen (%s) %s"%[label,str(box)])
	for r:Rect2i in hud_rects():
		if r.intersects(box):print("NOTE %s: HUD rect %s overlaps the plot row %s"%[label,str(r),str(box)])

# -------------------------------------------------------------------- HUD --

func aim(c:Vector2i)->void:
	app.target=c  # PRESET (pointer stand-in; main._process is off)
	app.view.target=c  # PRESET
	app.view.show_target=true  # PRESET
	app.view.selected=str(app.selected)  # PRESET
	await refresh()

func hint_text()->String:
	return str(app.selected_label.text) if is_instance_valid(app.selected_label) else ""

func hint_fits(label:String)->void:
	var l:Label=app.selected_label
	expect(l!=null and l.is_visible_in_tree(),"HUD tool hint shown (%s)"%label)
	if l==null:return
	var box:=gui_box(l.get_global_rect())
	expect(Rect2i(Vector2i.ZERO,root.size).encloses(box),"HUD tool hint inside the viewport (%s) %s"%[label,str(box)])
	var font:Font=l.get_theme_font("font")
	var font_size:int=l.get_theme_font_size("font_size")
	var width:float=font.get_string_size(l.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x if font!=null else 0.0
	print("NOTE %s: tool hint 「%s」 %.0f px wide in a %.0f px label at %s"%[label,l.text,width,l.size.x,str(box)])
	expect(font!=null and width<=l.size.x+0.5,"HUD tool hint text fits its label width (%s): %.0f > %.0f"%[label,width,l.size.x])
	expect(l.get_visible_line_count()>=l.get_line_count(),"HUD tool hint not clipped (%s)"%label)

func hint_flow()->void:
	app._select_tool("water")
	expect(str(app.selected)=="water","Water tool selected (%s)"%tag)
	# Reticle on plot a (dormant tomato).
	await aim(A)
	var snap:Dictionary=app.session.snapshot
	var want:String=Main.dormant_crop_hint(snap,A)
	expect(want==HINT_A,"dormant_crop_hint for plot a (%s): 「%s」"%[tag,want])
	expect(hint_text()==want,"Water hint on plot a equals dormant_crop_hint (%s): 「%s」"%[tag,hint_text()])
	hint_fits("water a "+tag)
	await shot("autumn_hint_a")
	# Reticle on plot c (growing pumpkin): the normal water hint.
	await aim(C)
	snap=app.session.snapshot
	expect(Main.dormant_crop_hint(snap,C)=="","No dormant hint for the growing pumpkin (%s): 「%s」"%[tag,Main.dormant_crop_hint(snap,C)])
	var water:String=WeatherForecast.water_hint(snap)
	expect(hint_text()==water,"Water hint on plot c is the normal water hint (%s): 「%s」 want 「%s」"%[tag,hint_text(),water])
	hint_fits("water c "+tag)
	# Greenhouse plot b and ripe plot d: never dormant, normal hint.
	for c:Vector2i in [B,D,H]:
		await aim(c)
		expect(hint_text()==WeatherForecast.water_hint(app.session.snapshot),"Water hint on %s is the normal water hint (%s): 「%s」"%[k(c),tag,hint_text()])
	# Harvest tool on plot e (strawberry waiting for spring, two harvests left).
	app._select_tool("harvest")
	await aim(E)
	snap=app.session.snapshot
	want=Main.dormant_crop_hint(snap,E)
	expect(want==HINT_E,"dormant_crop_hint for plot e (%s): 「%s」"%[tag,want])
	expect(hint_text()==want,"Harvest hint on plot e equals dormant_crop_hint (%s): 「%s」"%[tag,hint_text()])
	hint_fits("harvest e "+tag)
	app._select_tool("hoe")
	pointer_off()
	await refresh()

# ------------------------------------------------------------------- flow --

func size_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	app.view.reduced_motion=true  # PRESET
	pointer_off()
	write_field()
	await set_time(AUTUMN_TIME)
	await stand(VIEW_SPOT)
	expect(app.view.crop_art!=null,"Crop sprite art loaded (crops.png) (%s)"%tag)
	on_screen_check("autumn "+tag)
	# 1. Autumn overview.
	logic_check("autumn",DORMANT_AUTUMN)
	var autumn:Image=await shot("autumn")
	save_crop(autumn,"crop_autumn")
	var fall:=all_samples(autumn)
	marks_check(fall,"autumn",DORMANT_AUTUMN)
	ripe_hint_check(fall,"autumn")
	# 2. HUD hint (water on a / c, harvest on e).
	await hint_flow()
	# 3. First summer day.
	await set_time(SUMMER_TIME)
	logic_check("summer",DORMANT_SUMMER)
	var summer:Image=await shot("summer")
	save_crop(summer,"crop_summer")
	var hot:=all_samples(summer)
	marks_check(hot,"summer",DORMANT_SUMMER)
	ripe_hint_check(hot,"summer")
	if fall.is_empty() or hot.is_empty():return
	# 4. Per-plot comparisons.
	seasonal_pair("a",fall["a"],hot["a"],"tomato autumn vs summer "+tag)
	seasonal_pair("f",fall["f"],hot["f"],"watermelon autumn vs summer "+tag)
	seasonal_pair("c",hot["c"],fall["c"],"pumpkin summer vs autumn "+tag)
	for letter:String in ["b","d","e","g","h"]:
		var n:=cell_mismatches(fall[letter],hot[letter])
		expect(n==0,"Plot %s identical in autumn and summer (%s): %d px differ"%[letter,tag,n])
	expect(cell_mismatches(fall["c"],hot["f"])>0,"Awake pumpkin and watermelon show distinct plants "+tag)
	expect(cell_mismatches(hot["c"],fall["f"])>0,"Dormant pumpkin and watermelon show distinct plants "+tag)
	# 5. Nothing else in the field band changes with the season (HUD panels excluded: the
	#    calendar / status text legitimately changes).
	var band:=pixel_box(Rect2(cell_origin(Vector2i(39,36)),Vector2(10*32,2.5*32)))
	var exclude:Array[Rect2i]=[row_box().grow(1)]
	exclude.append_array(hud_rects())
	var outside:=changed_outside(autumn,summer,band,exclude)
	print("NOTE %s: field band %s, %d px changed outside the plots and HUD"%[tag,str(band),outside])
	expect(outside==0,"Only the plot row changes between autumn and summer in the field band (%s): %d px"%[tag,outside])

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		expect(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/作物休眠預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	expect(DisplayServer.get_name()!="headless","Runs on a native renderer")
	for p:Vector2i in CropArt.DORMANT_PIXELS:
		mark_area[p]=true
		mark_area[p+Vector2i.ONE]=true
	for p:Vector2i in CropArt.DORMANT_PIXELS:
		var s:Vector2i=p+Vector2i.ONE
		if not (s in CropArt.DORMANT_PIXELS) and not (s in shadow_only):shadow_only.append(s)
	path=OS.get_environment("TEMP").path_join("season-dormancy-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"休眠旅人",path)!=OK:expect(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	WanganUI.dismiss(app)
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
		if failures>80:break
	expect(shots==10,"5 screenshots per size (%d)"%shots)
	erase_field()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
