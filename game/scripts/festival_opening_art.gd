extends Control

const Characters=preload("res://scripts/character_sprite_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Sound=preload("res://scripts/soft_audio.gd")
const LANTERN=preload("res://assets/ui-life/paper-tea-lamp.png")
const PAGE=preload("res://assets/ui-inventory/paper.png")
const EXTENT:=Vector2(352,144)
const BACKDROPS:=[
	preload("res://assets/life-art/festival-scenes/tree.png"),
	preload("res://assets/life-art/festival-scenes/table.png"),
	preload("res://assets/life-art/festival-scenes/stall.png"),
]
const ACTORS:=["aru","milu","xiaoli"]
const FEET:=[Vector2(194,100),Vector2(210,104),Vector2(212,100)]
const CUES:=["warm_lantern","meal_serve",Sound.JOURNAL_PAGE]
const CUE_FRAME:=5

var scene_index:=0
var reduced_motion:=false
var sound:Sound
var frame:=12
var characters:=Characters.new()
var voice:AudioStreamPlayer

func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	visibility_changed.connect(_stop_hidden_cue)
	characters.setup()
	if reduced_motion:
		_play_cue()
	else:
		animate(0.0)
		create_tween().tween_method(animate,0.0,12.0,1.6)

func animate(step:float)->void:
	var next:=int(step)
	if frame==next:return
	if frame<CUE_FRAME and next>=CUE_FRAME:_play_cue()
	frame=next
	queue_redraw()

func _play_cue()->void:
	if not is_visible_in_tree() or not is_instance_valid(sound):return
	var cue:String=CUES[scene_index]
	var gain:=sound.cue_gain(cue)
	if gain<=0.0:return
	voice=AudioStreamPlayer.new()
	voice.stream=sound.sounds[cue]
	voice.volume_db=linear_to_db(gain)
	add_child(voice)
	voice.play()

func _stop_hidden_cue()->void:
	if not is_visible_in_tree() and is_instance_valid(voice):voice.stop()

func _draw()->void:
	draw_set_transform(Vector2.ZERO,0.0,size/EXTENT)
	draw_texture(BACKDROPS[scene_index],Vector2.ZERO,Color("d6b6a5"))
	var foot:Vector2=FEET[scene_index]
	var entrance:=Vector2i.LEFT if scene_index==0 else Vector2i.RIGHT
	foot.x-=float(entrance.x)*roundf((12.0-frame)/1.5)
	var facing:=Vector2i.DOWN if frame>=7 else entrance
	characters.draw_person(self,foot,Color.WHITE,ACTORS[scene_index],facing,float(frame),false,reduced_motion)
	match scene_index:
		0:
			var light:=Vector2(176,55+floori(frame/3.0))
			draw_texture_rect(LANTERN,Rect2(light,Vector2(16,16)),false)
			var spark:=Color("ffdfa3")
			for petal in range(8):
				var point:=Vector2(173+petal*5+(frame+petal)%7,37+((petal*7+frame*2)%39))
				draw_rect(Rect2(point,Vector2(2,1)),spark if petal%2==0 else Color("f4abb0"))
		1:
			draw_texture_rect(Items.icon("soup"),Rect2(foot+Vector2(-16,-20),Vector2(14,14)),false)
			for puff in range(3):
				var drift:float=(frame+puff*4)%12
				draw_rect(Rect2(foot+Vector2(-10+puff*3,-17-drift),Vector2(2,2)),Color(1.0,0.93,0.82,0.6-drift*0.025))
		2:
			draw_texture_rect(PAGE,Rect2(foot+Vector2(-18,-19),Vector2(15,15)),false)
			draw_rect(Rect2(foot+Vector2(-13+frame%5,-11),Vector2(4,1)),Color("ae825e"))
