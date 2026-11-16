extends SceneTree

const Art=preload("res://scripts/character_sprite_art.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func expect(condition:bool,description:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(description)

func run() -> void:
	var directions:=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]
	for row in range(directions.size()):
		var facing:Vector2i=directions[row]
		expect(Art.frame_selection("farmer",facing,PI*0.5,false,false)==Vector2i(0,row),"Idle keeps its facing")
		for reduced in [false,true]:
			expect(Art.frame_selection("farmer",facing,0.0,true,reduced)==Vector2i(0,row),"Neutral step keeps its facing")
			expect(Art.frame_selection("farmer",facing,PI*0.5,true,reduced)==Vector2i(1,row),"First stride keeps its facing")
			expect(Art.frame_selection("guest",facing,PI*1.5,true,reduced)==Vector2i(2,row),"Guest uses the second stride")
		expect(Art.frame_selection("farmer",facing,0.3,true,true).x==0,"Reduced motion spends more of the cycle in neutral")
		for npc in ["aru","milu","xiaoli"]:
			var column:=["aru","milu","xiaoli"].find(npc)+3
			expect(Art.frame_selection(npc,facing,PI*0.5,true,false)==Vector2i(column,row),"Resident uses the directional idle frame")
	var art:=Art.new()
	expect(art.setup(),"Character atlas imports as 288 by 192")
	if art.atlas!=null:
		var sheet:=art.atlas.get_image()
		for row in range(4):
			for column in range(6):
				var frame:=sheet.get_region(Rect2i(Vector2i(column,row)*Art.FRAME_SIZE,Art.FRAME_SIZE))
				var used:=frame.get_used_rect()
				expect(used.has_area() and used.position.x>0 and used.position.y>0 and used.end.x<48 and used.end.y<48,"Frame %s has a transparent margin"%Vector2i(column,row))
				expect(used.position.x<=Art.FOOT.x and used.end.x>Art.FOOT.x and absi(used.end.y-Art.FOOT.y)<=2,"Frame %s stays aligned to the foot baseline"%Vector2i(column,row))
	print("CHARACTER_SPRITE_ART checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

