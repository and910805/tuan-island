extends Control

signal gate_changed(which:String,level:int)
signal flow_requested

const TERRAIN=preload("res://assets/village-preview/terrain.png")
const RESIDENT=preload("res://assets/lanyang-life/atlas.png")
const CROPS=preload("res://assets/life-art/crops.png")
const FIELD_NAMES:=["上田","中田","下田"]

var levels:=[0,0]
var needs:=[4,4,4]
var reduced:=true
var pulse:=0.0
var landscape:Control
var readings:Label
var gates:Array[Button]=[]
var round_number:=1
var field_labels:Array[Label]=[]
var released:=false
var submitted_allocation:Array[int]=[]

func _ready()->void:
	custom_minimum_size=Vector2(620,350)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var column:=VBoxContainer.new()
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption:=Label.new()
	caption.text="沿水路看三塊田，調整甲、乙閘"
	column.add_child(caption)
	landscape=Control.new()
	landscape.custom_minimum_size.y=190
	landscape.size_flags_vertical=Control.SIZE_EXPAND_FILL
	landscape.clip_contents=true
	column.add_child(landscape)
	landscape.draw.connect(draw_landscape)
	var fields:=HBoxContainer.new()
	column.add_child(fields)
	for name_text in FIELD_NAMES:
		var name_label:=Label.new()
		name_label.text=name_text
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		fields.add_child(name_label)
		field_labels.append(name_label)
	readings=Label.new()
	column.add_child(readings)
	var dialogue:=Label.new()
	dialogue.text="維修者：「先看每塊田需要多少，再開閘試水。」"
	column.add_child(dialogue)
	var row:=HBoxContainer.new()
	column.add_child(row)
	for index in range(2):
		var gate:=Button.new()
		gate.custom_minimum_size.y=42
		row.add_child(gate)
		gates.append(gate)
		gate.pressed.connect(func():
			gate_changed.emit("a" if index==0 else "b",(levels[index]+1)%4)
		)
	var flow:=Button.new()
	flow.text="試放水"
	flow.custom_minimum_size.y=42
	row.add_child(flow)
	flow.pressed.connect(func():
		submitted_allocation=allocation_for_gates()
		released=true
		landscape.queue_redraw()
		if not reduced:pulse=0.8;set_process(true)
		flow_requested.emit()
	)
	set_process(false)
	update_readings()

func configure(gate_levels:Array,target:Array,round_index:int,reduced_motion:bool)->void:
	if gate_levels!=levels and round_index+1==round_number:released=false
	levels=gate_levels.duplicate()
	needs=target.duplicate()
	reduced=reduced_motion
	if reduced:pulse=0.0;set_process(false)
	var next_round:=clampi(round_index+1,1,3)
	round_number=next_round
	update_readings()

func update_readings()->void:
	if not is_instance_valid(readings):return
	var first:=clampi(int(levels[0]),0,3)*2
	var second:=mini(12-first,clampi(int(levels[1]),0,3)*2)
	readings.text="第 %d／3 輪・目前／需求"%round_number
	var allocation:=[first,second,12-first-second]
	for index in range(3):
		field_labels[index].text="%s  %d／%d"%[FIELD_NAMES[index],allocation[index],needs[index]]
	for index in range(2):
		gates[index].text="%s閘 · 第 %d 檔"%["甲" if index==0 else "乙",levels[index]]
	landscape.queue_redraw()

func _process(delta:float)->void:
	pulse=maxf(0,pulse-delta)
	landscape.queue_redraw()
	if pulse==0:set_process(false)

func draw_landscape()->void:
	var width:=ceili(landscape.size.x/32)
	var allocation:=submitted_allocation if not submitted_allocation.is_empty() else allocation_for_gates()
	for y in range(ceili(landscape.size.y/32)):
		for x in range(width):
			var field:=mini(2,floori((x+0.5)*96.0/landscape.size.x))
			var section_x:=fposmod((x+0.5)*96.0/landscape.size.x,1.0)
			var plot:=y>=2 and section_x>0.16 and section_x<0.84
			var branch:=plot and absf(section_x-0.5)<=16.0*3.0/landscape.size.x
			var index:=9 if y==1 or branch else (5 if plot else 0)
			var region:=Rect2((index%4)*32,(index/4)*32,32,32)
			var tint:=Color.WHITE
			if released and plot and allocation[field]>0:tint=Color.WHITE.lerp(Color("9bc2ad"),minf(0.65,float(allocation[field])/12.0))
			landscape.draw_texture_rect_region(TERRAIN,Rect2(x*32,y*32,32,32),region,tint)
			if plot and not branch:
				landscape.draw_texture_rect_region(CROPS,Rect2(x*32+3,y*32+1,26,26),Rect2(32,64,32,32))
	for index in range(2):
		var x:=floorf((index+0.5)*landscape.size.x/96.0)*32.0
		landscape.draw_texture_rect_region(RESIDENT,Rect2(x,32,32,32),Rect2(80,0,32,32))
	landscape.draw_texture_rect_region(RESIDENT,Rect2(16,-7,48,48),Rect2(0,0,48,48))
	if pulse>0:
		var distance:=1.0-pulse/0.8
		for field in range(3):
			if allocation[field]<=0:continue
			var center:=floorf((field+0.5)*landscape.size.x/96.0)*32.0+16.0
			var y:=roundf(44+distance*(landscape.size.y-58))
			var spread:=clampi(allocation[field]*3,6,27)
			landscape.draw_texture_rect_region(TERRAIN,Rect2(roundf(center-spread/2.0),y,spread,12),Rect2(32,64,32,32),Color(1.35,1.35,1.35,0.88))

func allocation_for_gates()->Array[int]:
	var first:=clampi(int(levels[0]),0,3)*2
	var second:=mini(12-first,clampi(int(levels[1]),0,3)*2)
	return [first,second,12-first-second]
