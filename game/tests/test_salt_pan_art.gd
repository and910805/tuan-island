extends SceneTree
## Beimen salt art adapters (salt_art.gd + salt_world_art.gd frame rules +
## inventory icons + provenance). Headless-capable: image data only.
const SaltArt=preload("res://scripts/salt_art.gd")
const SaltWorldArt=preload("res://scripts/salt_world_art.gd")
const PropsArt=preload("res://scripts/salt_props_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const VISIBLE:=8
var checks:=0
var failures:=0

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:run.call_deferred()

func image_of(texture:Texture2D)->Image:
	if texture==null:return null
	var image:=texture.get_image()
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

## alpha>threshold bounds (inclusive end) of a region; Rect2i() when empty.
func bounds(image:Image,region:Rect2i,threshold:int=VISIBLE)->Rect2i:
	var mn:=Vector2i(1<<20,1<<20)
	var mx:=Vector2i(-1,-1)
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if image.get_pixel(x,y).a8>threshold:
				mn=mn.min(Vector2i(x,y))
				mx=mx.max(Vector2i(x,y))
	if mx.x<0:return Rect2i()
	return Rect2i(mn,mx-mn+Vector2i.ONE)

func full(image:Image)->Rect2i:
	return Rect2i(Vector2i.ZERO,image.get_size())

func differing(a:Image,b:Image)->int:
	var n:=0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x,y)!=b.get_pixel(x,y):n+=1
	return n

## Pixels that differ outside every rect of `skip`.
func differing_outside(a:Image,b:Image,skip:Array)->int:
	var n:=0
	for y in a.get_height():
		for x in a.get_width():
			var masked:=false
			for r in skip:
				if (r as Rect2i).has_point(Vector2i(x,y)):masked=true
			if not masked and a.get_pixel(x,y)!=b.get_pixel(x,y):n+=1
	return n

func differing_in(a:Image,b:Image,region:Rect2i)->int:
	var n:=0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if a.get_pixel(x,y)!=b.get_pixel(x,y):n+=1
	return n

func source(sheet:String)->Image:
	var image:=Image.load_from_file(ProjectSettings.globalize_path(SaltArt.sheet_path(sheet)))
	if image:image.convert(Image.FORMAT_RGBA8)
	return image

## Every visible (alpha>8) source pixel of `clip` lies inside `window`.
func inside(src:Image,clip:Rect2i,window:Rect2i)->bool:
	var b:=bounds(src,clip)
	return b.has_area() and window.encloses(b)

func run()->void:
	SaltArt.clear_cache()
	# ---------------------------------------------------- sheets and sizes
	for sheet in SaltArt.SHEETS:
		var src:=source(sheet)
		expect(src!=null and src.get_size()==SaltArt.SHEETS[sheet]["size"],"%s sheet present at declared size"%sheet)
	var terrain_src:=source("terrain")
	for i in 16:
		var tex:=SaltArt.terrain_texture(i)
		expect(tex!=null and tex.get_size()==Vector2(32,32),"terrain %d is 32x32"%i)
		var image:=image_of(tex)
		if image:expect(bounds(image,full(image),254)==full(image),"terrain %d fully opaque"%i)
		var w:=SaltArt.terrain_window(i)
		var col:int=SaltArt.TERRAIN_BOUNDS[i%4]
		var row:int=SaltArt.TERRAIN_BOUNDS[i/4]
		var own_cell:=Rect2i(col,row,int(SaltArt.TERRAIN_BOUNDS[i%4+1])-col,int(SaltArt.TERRAIN_BOUNDS[i/4+1])-row)
		expect(Rect2i(0,0,1254,1254).encloses(w) and w==own_cell,"terrain %d window is exactly its own sheet cell %s"%[i,w])
		expect(absf(float(w.size.x)/w.size.y-1.0)<0.004,"terrain %d cell aspect drift < 0.4%%"%i)
		if terrain_src:
			var poisoned:=terrain_src.duplicate() as Image
			poisoned.fill(Color(1,0,1,1))
			poisoned.blit_rect(terrain_src,w,w.position)
			expect(differing(image_of(tex),SaltArt.render_window(poisoned,w,w,SaltArt.TILE))==0,"terrain %d: no neighbouring cell bleeds in"%i)
	expect(terrain_src!=null,"terrain source readable")
	expect(SaltArt.terrain_texture("sea")==SaltArt.terrain_texture(4),"terrain names map to indices and cache")

	# ---------------------------------------------------- pans: fixed window, identical anchors
	var pan_src:=source("pans")
	var pan_bounds:={}
	for state in SaltArt.PAN_STATES:
		var tex:=SaltArt.pan_texture(state)
		expect(tex!=null and tex.get_size()==Vector2(96,96),"pan %s is 96x96 (3x3 tiles)"%state)
		var image:=image_of(tex)
		if image==null:continue
		expect(image.get_pixel(0,0).a8<=VISIBLE and image.get_pixel(95,0).a8<=VISIBLE,"pan %s keeps transparent corners"%state)
		pan_bounds[state]=bounds(image,full(image),128)
		expect(SaltArt.pan_window(state).size==SaltArt.PAN_WINDOW.size,"pan %s uses the one shared window size"%state)
		expect(inside(pan_src,SaltArt.pan_cell(state),SaltArt.pan_window(state)),"pan %s: no visible source pixel outside the window"%state)
	var ref:Rect2i=pan_bounds.get("empty",Rect2i())
	expect(ref.has_area() and ref.size.x>=88 and ref.size.y>=82,"pan art fills most of the 3x3 footprint (%s)"%ref)
	expect(ref.position.y<=6 and 96-ref.end.y<=6 and absi(ref.position.y-(96-ref.end.y))<=2,"pan rim centred vertically on the 3x3 footprint (%s)"%ref)
	expect(ref.position.x<=4 and 96-ref.end.x<=4,"pan rim spans the footprint width (%s)"%ref)
	for state in pan_bounds:
		var b:Rect2i=pan_bounds[state]
		expect(absi(b.position.x-ref.position.x)<=1 and absi(b.end.x-ref.end.x)<=1 and absi(b.position.y-ref.position.y)<=1 and absi(b.end.y-ref.end.y)<=1,"pan %s anchors match empty within 1px (%s vs %s)"%[state,b,ref])
	var empty_img:=image_of(SaltArt.pan_texture("empty"))
	for state in ["brine","evaporating_1","evaporating_2","salt","diluted","covered"]:
		expect(differing(empty_img,image_of(SaltArt.pan_texture(state)))>800,"pan %s visibly differs from empty"%state)
	# Progress reads dark->light: mean luminance of the interior rises brine->evap1->evap2->salt-ish.
	var lum:={}
	for state in ["brine","evaporating_1","evaporating_2"]:
		var image:=image_of(SaltArt.pan_texture(state))
		var total:=0.0
		for y in range(24,72):
			for x in range(24,72):total+=image.get_pixel(x,y).get_luminance()
		lum[state]=total
	expect(float(lum.brine)<float(lum.evaporating_1) and float(lum.evaporating_1)<float(lum.evaporating_2),"brine -> evaporation gets lighter %s"%lum)

	# ---------------------------------------------------- machines: idle/running/empty share feet
	var machine_src:=source("machines")
	expect(SaltArt.errors.is_empty(),"adapter recorded no load errors so far %s"%[SaltArt.errors])
	for id in SaltArt.MACHINES:
		var tex:=SaltArt.machine_texture(id)
		expect(tex!=null and tex.get_size()==Vector2(64,64),"%s is 64x64"%id)
		var image:=image_of(tex)
		if image==null:continue
		var b:=bounds(image,full(image))
		expect(b.end.y-1==63,"%s feet on native row 63 (%s)"%[id,b])
		expect(image.get_pixel(0,0).a8<=VISIBLE,"%s transparent background"%id)
	for id in SaltArt.FOUNDATIONS:
		expect(inside(machine_src,SaltArt.machine_clip(id),SaltArt.machine_window(id)),"%s: no visible source pixel clipped"%id)
		expect(SaltArt.machine_window(id).size==PropsArt.WINDOW_SIZE,"%s uses the props scale (576 -> 64)"%id)
	for base in SaltArt.MACHINE_KINDS:
		var idle_tex:=PropsArt.prop_texture(base)
		expect(SaltArt.machine_texture(base)==idle_tex and SaltArt.prop_texture(base)==idle_tex,"%s idle frame IS the salt_props_art texture (same object)"%base)
		var idle:=image_of(idle_tex)
		var working:=image_of(SaltArt.machine_texture(base+"_working"))
		var pad:=image_of(SaltArt.machine_texture(base+"_empty"))
		if idle==null or working==null or pad==null:
			expect(false,"%s frames available"%base)
			continue
		var bi:=bounds(idle,full(idle))
		var bw:=bounds(working,full(working))
		var bp:=bounds(pad,full(pad))
		expect(bi.end.y==bw.end.y and bw.end.y==bp.end.y,"%s idle/working/empty share the foot row (%d/%d/%d)"%[base,bi.end.y,bw.end.y,bp.end.y])
		expect(absi(bi.position.x-bw.position.x)<=1,"%s working frame keeps the frame's left edge (%d vs %d)"%[base,bi.position.x,bw.position.x])
		expect(absi(bi.size.y-bw.size.y)<=3,"%s working frame keeps the height (%d vs %d)"%[base,bi.size.y,bw.size.y])
		expect(bp.size.y<bi.size.y-10,"%s empty pad is a low foundation, not the machine"%base)
		expect(SaltArt.MACHINE_ANCHOR==PropsArt.FOOT_ANCHOR,"%s anchors identical across sheets"%base)
		expect(SaltArt.machine_texture(base+"_working")==SaltArt.running_frame(base,int(SaltArt.WORKING_PHASE[base])),"%s _working is the stable-base running composite, never the raw redraw"%base)
		# Running phases: pixel-identical to idle outside the animated ROIs, changed inside.
		var rois:=SaltArt.animated_rois(base)
		expect(rois.size()==2,"%s has two clipped animated regions"%base)
		var prev:Image=null
		var first:Image=null
		for phase in SaltArt.RUN_PHASES:
			var frame:=image_of(SaltArt.running_frame(base,phase))
			if frame==null:
				expect(false,"%s running phase %d available"%[base,phase])
				continue
			expect(differing_outside(idle,frame,rois)==0,"%s phase %d: body pixel-identical to idle outside the ROIs"%[base,phase])
			var inside_roi:=0
			for roi in rois:inside_roi+=differing_in(idle,frame,roi)
			expect(inside_roi>=4,"%s phase %d: changes inside the ROIs (%d px)"%[base,phase,inside_roi])
			if base=="waterwheel":
				var alpha_moved:=0
				for y in 64:
					for x in 64:
						if idle.get_pixel(x,y).a8!=frame.get_pixel(x,y).a8:alpha_moved+=1
				expect(alpha_moved==0,"waterwheel phase %d: silhouette/alpha unchanged (flow pixels only)"%phase)
			if prev:expect(differing(prev,frame)>=3,"%s phase %d differs from the previous phase"%[base,phase])
			if first==null:first=frame
			prev=frame
		if prev and first:expect(differing(prev,first)>=3,"%s last phase differs from phase 0 (loop keeps moving)"%base)
	expect(SaltArt.grains().size()>=2,"collector salt grains are real working-frame pixels (%d)"%SaltArt.grains().size())

	# ---------------------------------------------------- frame rules (motion only while running)
	var idle_wheel:=SaltArt.prop_texture("waterwheel")
	var idle_rake:=SaltArt.prop_texture("salt_collector")
	for kind in SaltArt.MACHINE_KINDS:
		var idle_tex:=SaltArt.prop_texture(kind)
		for status in ["off","full","invalid","unset","waiting","wheel_only","manual","reserve","owner","idle",""]:
			for t in [0.0,0.15,0.3,0.45,7.77]:
				expect(SaltArt.machine_frame(kind,status,t,false)==idle_tex,"%s status '%s' at t=%s is exactly the idle texture"%[kind,status,t])
		for t in [0.0,0.15,0.3,0.45,7.77]:
			expect(SaltArt.machine_frame(kind,"running",t,true)==idle_tex,"%s reduced motion: idle at t=%s"%[kind,t])
			expect(SaltArt.machine_frame(kind,"running",t,false)==SaltArt.running_frame(kind,SaltArt.machine_phase(t)),"%s running at t=%s shows its phase"%[kind,t])
		expect(SaltArt.machine_frame(kind,"running",0.0,false)!=SaltArt.machine_frame(kind,"running",0.15,false) and SaltArt.machine_frame(kind,"running",0.15,false)!=SaltArt.machine_frame(kind,"running",0.3,false),"%s running frames advance t0->t1->t2"%kind)
	expect(SaltArt.machine_frame("waterwheel","rain",0.15,false)==idle_wheel and SaltArt.machine_frame("waterwheel","running",0.15,false,true)==idle_wheel,"rain stops the waterwheel flow")
	expect(SaltArt.machine_frame("salt_collector","rain",0.15,false)==SaltArt.running_frame("salt_collector",1) and SaltArt.machine_frame("salt_collector","running",0.15,false,true)==SaltArt.running_frame("salt_collector",1),"rain does not stop the collector")
	expect(SaltArt.machine_frame("salt_collector","rain",0.15,true)==idle_rake,"rain raking still frozen in reduced motion")
	expect(SaltArt.machine_frame("pump","running",0.0,false)==null,"unknown machine kind -> null")
	expect(SaltArt.machine_phase(-0.01)==3 and SaltArt.machine_phase(0.0)==0 and SaltArt.machine_phase(0.6)==0,"phase wraps")
	# World-art gating from the public snapshot (lots[i].active / apprentice.active).
	var running_data:={"salt_pan":{"repaired":true,"weather":{"raining":false},"lots":[{"taken":true,"wheel":true,"rake":true,"active":true,"mine":false},{"taken":true,"wheel":true,"rake":true,"active":false,"mine":false}],"apprentice":{"taken":true,"wheel":true,"rake":true,"active":true}},"time":100.0}
	for lot in [0,Salt.APPRENTICE_LOT]:
		expect(SaltWorldArt.wheel_running(running_data,lot) and SaltWorldArt.collector_running(running_data,lot),"active unit %d runs"%lot)
	expect(not SaltWorldArt.wheel_running(running_data,1) and not SaltWorldArt.collector_running(running_data,1),"inactive (switched-off) unit stays still")
	for t in [0.0,0.15,0.3,0.5,0.9,7.77]:
		expect(SaltWorldArt.machine_texture_for("wheel",true,true,t,true)==idle_wheel and SaltWorldArt.machine_texture_for("rake",true,true,t,true)==idle_rake,"reduced motion: running machines draw the idle texture at t=%s"%t)
		expect(SaltWorldArt.machine_texture_for("wheel",true,false,t,false)==idle_wheel and SaltWorldArt.machine_texture_for("rake",true,false,t,false)==idle_rake,"not running: idle texture at t=%s"%t)
		expect(SaltWorldArt.machine_texture_for("wheel",false,true,t,false)==SaltArt.machine_texture("waterwheel_empty") and SaltWorldArt.machine_texture_for("rake",false,true,t,false)==SaltArt.machine_texture("salt_collector_empty"),"not installed: empty pad at t=%s"%t)
		expect(SaltWorldArt.machine_texture_for("wheel",true,true,t,false)==SaltArt.running_frame("waterwheel",SaltArt.machine_phase(t)),"running wheel phase at t=%s"%t)
		expect(SaltWorldArt.machine_texture_for("rake",true,true,t,false,true)==SaltArt.running_frame("salt_collector",SaltArt.machine_phase(t)),"collector keeps raking in rain at t=%s"%t)
		expect(SaltWorldArt.machine_texture_for("wheel",true,true,t,false,true)==idle_wheel,"wet wheel never flows at t=%s"%t)
		expect(SaltWorldArt.machine_frame(true,true,t,true)=="idle" and SaltWorldArt.machine_frame(true,false,t,false)=="idle" and SaltWorldArt.machine_frame(false,true,t,false)=="empty","frame names at t=%s"%t)
	var seen:={}
	for i in 20:seen[SaltWorldArt.machine_frame(true,true,i*0.075,false)]=true
	expect(seen.size()==SaltArt.RUN_PHASES and not seen.has("idle"),"running machine cycles through its %d stable-base phases %s"%[SaltArt.RUN_PHASES,seen])
	var rain_data:=running_data.duplicate(true)
	rain_data.salt_pan.weather.raining=true
	expect(not SaltWorldArt.wheel_running(rain_data,0) and not SaltWorldArt.wheel_running(rain_data,Salt.APPRENTICE_LOT),"rain pauses the waterwheel")
	expect(SaltWorldArt.collector_running(rain_data,0) and SaltWorldArt.collector_running(rain_data,Salt.APPRENTICE_LOT),"collector keeps working in rain")
	for status in ["off","invalid","unset","owner","full","waiting"]:
		var own_data:=running_data.duplicate(true)
		own_data.salt_pan["own"]={"unit":{"kind":"lot","index":0,"status":{"id":status,"text":""}}}
		expect(not SaltWorldArt.wheel_running(own_data,0) and not SaltWorldArt.collector_running(own_data,0),"own unit status %s: machines still"%status)
		own_data.salt_pan["own"]={"unit":{"kind":"apprentice","index":0,"status":{"id":status,"text":""}}}
		expect(not SaltWorldArt.wheel_running(own_data,Salt.APPRENTICE_LOT) and SaltWorldArt.wheel_running(own_data,0),"own apprentice status %s stills only the apprentice station"%status)
	var own_running:=running_data.duplicate(true)
	own_running.salt_pan["own"]={"unit":{"kind":"lot","index":0,"status":{"id":"running","text":""}}}
	expect(SaltWorldArt.wheel_running(own_running,0) and SaltWorldArt.collector_running(own_running,0),"own running unit moves")
	expect(not SaltWorldArt.wheel_running({},0) and not SaltWorldArt.collector_running({},3),"empty snapshot: nothing runs")
	# Ground and pans never alternate: sea/channel cells are static base tiles.
	expect(not SaltWorldArt.new().has_method("channel_frame") and not SaltWorldArt.new().has_method("glints"),"no channel flip / invented glints in the scene art")
	for p in [Vector2i(8,13),Vector2i(9,15),Vector2i(2,20),Vector2i(5,20)]:
		expect(not SaltWorldArt.terrain_for(p).ends_with("_b"),"water cell %s uses the base tile (%s)"%[p,SaltWorldArt.terrain_for(p)])

	# ---------------------------------------------------- pan view -> art state
	expect(SaltWorldArt.view_state({"s":"empty"})=="empty","empty")
	expect(SaltWorldArt.view_state({"s":"brine","ratio":0.1})=="brine","fresh brine")
	expect(SaltWorldArt.view_state({"s":"brine","ratio":0.5})=="evaporating_1","half")
	expect(SaltWorldArt.view_state({"s":"brine","ratio":0.9})=="evaporating_2","late")
	expect(SaltWorldArt.view_state({"s":"brine","ratio":0.9,"diluted":true})=="diluted","rain dilutes brine")
	expect(SaltWorldArt.view_state({"s":"salt"})=="salt","salt")
	expect(SaltWorldArt.view_state({"s":"salt","covered":true})=="covered","rain covers salt")
	expect(SaltArt.panel_art("pan","brine_alt")==null and SaltArt.panel_art("pan","covered")==SaltArt.pan_texture("covered"),"panel art never hands out the drifting brine_alt frame")
	expect(SaltArt.panel_art("portrait","salt_worker")==SaltArt.portrait_texture() and SaltArt.panel_art("portrait","xiaoli")==null and SaltArt.panel_art("heritage","x")==null,"panel art: portrait only for 阿曬, nothing invented")
	var heritage:=SaltArt.panel_art("heritage","jingzaijiao")
	expect(heritage!=null and Vector2i(heritage.get_size())==Vector2i(288,192) and heritage==SaltArt.heritage_texture("jingzaijiao") and heritage.resource_path=="res://assets/salt/salt-heritage-jingzaijiao.png","panel art: 井仔腳 heritage journal illustration is the delivered 288x192 PNG")

	# ---------------------------------------------------- structures
	var struct_src:=source("structures")
	for id in SaltArt.STRUCTURES:
		var tex:=SaltArt.structure_texture(id)
		var size:Vector2i=SaltArt.structure_size(id)
		expect(tex!=null and Vector2i(tex.get_size())==size,"%s native %s"%[id,size])
		if id=="sign":expect(size==Vector2i(32,48),"sign uses the 32x48 actor-class canvas (%s)"%size)
		else:expect(size.x%32==0 and size.y%32==0,"%s canvas is a 32px multiple"%id)
		var image:=image_of(tex)
		if image==null:continue
		var b:=bounds(image,full(image))
		expect(b.end.y>=size.y-1,"%s feet on the last native row (%s)"%[id,b])
		expect(absf((b.position.x+b.end.x)/2.0-size.x/2.0)<=1.5,"%s horizontally centred on its anchor"%id)
		expect(image.get_pixel(0,0).a8<=VISIBLE,"%s transparent background"%id)
		var spec:Dictionary=SaltArt.STRUCTURES[id]
		expect(inside(struct_src,spec.clip,spec.window),"%s: no visible source pixel clipped"%id)
		expect(SaltArt.structure_anchor(id)==Vector2i(size.x/2,size.y),"%s bottom-centre anchor"%id)
	var shed:=image_of(SaltArt.structure_texture("shed"))
	if shed:expect(bounds(shed,full(shed)).size.x<=192,"shed stays inside its 6-tile footprint width")
	for id in ["sign","coop_chest"]:
		var image:=image_of(SaltArt.structure_texture(id))
		if image==null:continue
		var lowest:=bounds(image,Rect2i(0,image.get_height()-3,image.get_width(),3))
		expect(lowest.size.x<=32,"%s ground contact fits its 1x1 footprint (%d px)"%[id,lowest.size.x])
	# Bus shelter: 96x64, drawn bottom-centred over SaltPan.BUS_SHELTER (3x1 solid).
	expect(SaltArt.structure_size("bus_stop")==Vector2i(Salt.BUS_SHELTER.size.x*32,64),"bus shelter canvas is %d tiles wide x 2 tall"%Salt.BUS_SHELTER.size.x)
	var shelter:=image_of(SaltArt.structure_texture("bus_stop"))
	if shelter:
		var contact:=bounds(shelter,Rect2i(0,shelter.get_height()-3,shelter.get_width(),3))
		expect(contact.has_area() and contact.position.x>=0 and contact.end.x<=Salt.BUS_SHELTER.size.x*32,"bus shelter ground contact stays on its 3-tile footprint (%s)"%contact)
		expect(bounds(shelter,full(shelter)).size.y>=56,"bus shelter roof stands above a 46px actor (%s)"%bounds(shelter,full(shelter)))
	var shelter_feet:=SaltWorldArt.shelter_feet(Vector2.ZERO)
	expect(shelter_feet.x==(Salt.BUS_SHELTER.position.x+Salt.BUS_SHELTER.size.x*0.5)*32 and shelter_feet.y>(Salt.BUS_SHELTER.end.y-1)*32 and shelter_feet.y<=Salt.BUS_SHELTER.end.y*32,"shelter feet bottom-centred on BUS_SHELTER %s"%shelter_feet)
	expect(Salt.BUS_SHELTER.has_point(Salt.TRANSFER) and Salt.TRANSFER==Salt.BUS_SHELTER.position and not Salt.BUS_SHELTER.has_point(Vector2i(Salt.ARRIVAL)),"TRANSFER is the shelter's west cell, arrival stays outside")
	var shelter_listed:=false
	for item in SaltWorldArt.footprints():
		if item.id=="bus_stop":shelter_listed=item.rect==Salt.BUS_SHELTER
	expect(shelter_listed,"scene footprint of the bus stop is SaltPan.BUS_SHELTER")

	# ---------------------------------------------------- resident + portrait
	var resident_src:=source("resident")
	var feet_rows:={}
	for pose in SaltArt.POSES:
		var tex:=SaltArt.resident_texture(pose)
		expect(tex!=null and tex.get_size()==Vector2(32,48),"阿曬 %s is 32x48"%pose)
		var image:=image_of(tex)
		if image==null:continue
		var b:=bounds(image,full(image))
		feet_rows[pose]=b.end.y
		expect(b.position.y>=0 and b.position.x>=0 and b.end.x<=32,"阿曬 %s inside canvas"%pose)
		expect(inside(resident_src,Rect2i(SaltArt.POSES[pose],Vector2i(627,627)),SaltArt.resident_window(pose)),"阿曬 %s not clipped"%pose)
	expect(feet_rows.size()==4 and feet_rows.values().min()==48 and feet_rows.values().max()==48,"all poses stand on row 47 %s"%feet_rows)
	var portrait:=SaltArt.portrait_texture()
	expect(portrait!=null and portrait.get_size()==Vector2(64,64),"portrait is 64x64")
	var face:=image_of(portrait)
	if face:
		expect(face.get_pixel(0,0).a8<=VISIBLE,"portrait transparent background")
		expect(bounds(face,full(face)).size.x>=40,"portrait bust fills the frame")
	expect(inside(source("portrait"),Rect2i(0,0,1254,1254),SaltArt.PORTRAIT_WINDOW) or bounds(source("portrait"),Rect2i(0,0,1254,1254)).end.y-SaltArt.PORTRAIT_WINDOW.end.y<=19,"portrait window keeps the bust (at most one native row clipped)")

	# ---------------------------------------------------- items
	var item_src:=source("items")
	var fish_salt:Image=null
	for id in SaltArt.ITEMS:
		var tex:=Items.icon(id)
		expect(tex!=null and tex.get_size()==Vector2(32,32),"inventory icon %s 32x32"%id)
		expect(tex==SaltArt.item_texture(id),"inventory icon %s comes from salt-items.png"%id)
		var image:=image_of(tex)
		if image==null:continue
		expect(image.get_pixel(0,0).a8<=VISIBLE and image.get_pixel(31,31).a8<=VISIBLE,"%s transparent corners"%id)
		expect(bounds(image,full(image)).size.x>=20,"%s readable size"%id)
		expect(inside(item_src,Rect2i(SaltArt.ITEMS[id],Vector2i(627,627)),SaltArt.item_window(id)),"%s not clipped"%id)
		if id=="salt_grilled_fish":fish_salt=image
	var old_fish:=image_of(Items.icon("grilled_fish"))
	expect(old_fish!=null and fish_salt!=null and old_fish.get_size()==fish_salt.get_size(),"both fish icons present")
	if old_fish and fish_salt:expect(differing(old_fish,fish_salt)>200,"salt_grilled_fish icon differs from grilled_fish icon")
	expect(Items.icon("grilled_fish") is AtlasTexture and (Items.icon("grilled_fish") as AtlasTexture).atlas.resource_path=="res://assets/ui-inventory/items.png","grilled_fish keeps its original atlas icon")
	var distinct:={}
	for id in SaltArt.ITEMS:distinct[SaltArt.item_texture(id)]=true
	expect(distinct.size()==4,"4 distinct salt icons")

	# ---------------------------------------------------- unknown / missing => null, never a stand-in
	for bad in ["","nope","Sea_Salt","brine_alt "]:
		expect(SaltArt.item_texture(bad)==null and SaltArt.pan_texture(bad)==null and SaltArt.machine_texture(bad)==null and SaltArt.structure_texture(bad)==null and SaltArt.resident_texture(bad)==null,"unknown id '%s' -> null"%bad)
	expect(SaltArt.terrain_texture(16)==null and SaltArt.terrain_texture(-1)==null and SaltArt.terrain_texture("lava")==null,"unknown terrain -> null")
	expect(SaltArt.structure_anchor("nope")==Vector2i(-1,-1),"unknown structure anchor")
	for sheet in SaltArt.SHEETS:
		SaltArt.set_sheet_path(sheet,"res://assets/salt/missing-%s.png"%sheet)
	expect(SaltArt.cache.is_empty(),"set_sheet_path clears cache")
	expect(SaltArt.terrain_texture(0)==null and SaltArt.pan_texture("salt")==null and SaltArt.machine_texture("waterwheel_working")==null,"missing sheets -> null (terrain/pans/machines)")
	expect(SaltArt.structure_texture("shed")==null and SaltArt.resident_texture()==null and SaltArt.portrait_texture()==null and SaltArt.item_texture("sea_salt")==null,"missing sheets -> null (structures/resident/portrait/items)")
	expect(SaltArt.machine_texture("waterwheel")==null and SaltArt.machine_frame("waterwheel","running",0.2,false)==null and SaltArt.machine_frame("salt_collector","off",0.2,false)==null,"missing props sheet -> no idle or running machine (no stand-in)")
	expect(not SaltArt.errors.is_empty(),"missing sheets are recorded in SaltArt.errors")
	expect(SaltArt.cache.is_empty(),"failed loads never populate the cache")
	SaltArt.set_sheet_path("pans",ProjectSettings.globalize_path("res://assets/salt/salt-items.png"))
	expect(SaltArt.pan_texture("salt")==null,"wrong-size sheet -> null")
	expect(SaltArt.errors.size()==1 and SaltArt.errors[0].begins_with("wrong size"),"wrong-size sheet recorded %s"%[SaltArt.errors])
	SaltArt.set_sheet_path("pans",ProjectSettings.globalize_path("res://assets/salt/salt-pan-states.png"))
	var absolute:=image_of(SaltArt.pan_texture("salt"))
	for sheet in SaltArt.SHEETS:SaltArt.set_sheet_path(sheet,"")
	expect(PropsArt.source_path==PropsArt.DEFAULT_SOURCE_PATH and PropsArt.prop_texture("gate_broken")!=null,"restoring the props sheet hands the shared gate adapter back its delivered PNG")
	expect(SaltArt.running_frame("waterwheel",1)!=null and SaltArt.errors.is_empty(),"restored paths load again without errors %s"%[SaltArt.errors])
	var imported:=image_of(SaltArt.pan_texture("salt"))
	# fix_alpha_border recolours transparent and faint edge pixels (measured up
	# to alpha ~19): compare alpha everywhere and colour on solid art (>=128).
	var same:=absolute!=null and imported!=null
	if same:
		for y in 96:
			for x in 96:
				var raw:=absolute.get_pixel(x,y)
				var got:=imported.get_pixel(x,y)
				if raw.a8!=got.a8 or (raw.a8>=128 and raw!=got):same=false
	expect(same,"lossless import matches the raw PNG (alpha everywhere, colour where visible)")
	var canvas_ok:=not SaltArt.draw_anchored(null,null,Vector2.ZERO,Vector2i.ZERO)
	expect(canvas_ok,"draw_anchored reports false without art")

	# ---------------------------------------------------- provenance
	var text:=FileAccess.get_file_as_string("res://assets/salt/provenance.json")
	var prov=JSON.parse_string(text)
	expect(prov is Dictionary and prov.get("files") is Dictionary,"provenance.json present")
	if prov is Dictionary and prov.get("files") is Dictionary:
		for sheet in SaltArt.SHEETS:
			var file:String=SaltArt.SHEETS[sheet]["file"]
			var entry=prov.files.get(file,{})
			expect(entry is Dictionary and str(entry.get("sha256",""))==FileAccess.get_sha256("res://assets/salt/"+file),"provenance sha256 for %s"%file)
			expect(entry is Dictionary and str(entry.get("source","")).begins_with("work/salt/art-source/"),"provenance source for %s"%file)
		var props=prov.files.get("salt-props.png",{})
		expect(props is Dictionary and str(props.get("sha256",""))==FileAccess.get_sha256("res://assets/salt/salt-props.png"),"provenance sha256 for salt-props.png")
	print("SALT_PAN_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
