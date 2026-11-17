extends SceneTree
const World=preload("res://scripts/world.gd")
const Shelter=preload("res://scripts/sheep_shelter.gd")
const Art=preload("res://scripts/livestock_scene_art.gd")
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:
	var world:=World.new()
	var data:Dictionary=world.state.duplicate(true)
	data.region_id="home"
	data.picnic=true
	data.sheep_comfort_fixtures=3
	data.time=1440.0
	var state:=data.duplicate(true)
	var shelter:=Shelter.new()
	expect(shelter.route_clear(data),"The actual pasture route is clear under normal terrain rules")
	shelter.observe(data,0.0)
	expect(shelter.offset(0.5,false)==Vector2.ZERO,"Cloudy sheep rests at feed station")
	data.time=2880.0
	shelter.observe(data,1.0)
	expect(shelter.offset(1.0,false)==Vector2.ZERO,"Rain begins without teleporting")
	var middle:=shelter.offset(2.1,false)
	expect(middle.x>0 and middle.x<32 and middle.y==0,"Sheep walks one clear tile toward shelter")
	expect(shelter.walking_frame(1.2,false)!=shelter.walking_frame(1.36,false),"Hooves alternate while walking")
	expect(shelter.facing_right(),"The trip into the right-hand shelter faces right")
	expect(shelter.offset(3.3,false)==Shelter.SHELTER_OFFSET and not shelter.walking(3.3,false),"Sheep arrives and stops walking")
	shelter.observe(data,2.0)
	expect(shelter.offset(2.1,false)==middle,"Duplicate snapshot does not restart the walk")
	expect(shelter.offset(1.2,true)==Shelter.SHELTER_OFFSET and shelter.walking_frame(1.2,true)==-1,"Reduced motion shows the same shelter state without travel")
	var joined:=Shelter.new()
	joined.observe(data,8.0)
	expect(joined.offset(8.0,false)==Shelter.SHELTER_OFFSET and not joined.walking(8.0,false),"Joining during rain uses the current shelter state without replay")
	data.time=4320.0
	shelter.observe(data,4.0)
	expect(shelter.offset(4.0,false)==Shelter.SHELTER_OFFSET and not shelter.facing_right(),"Rain stops and the return begins facing left")
	expect(shelter.offset(6.3,false)==Vector2.ZERO,"Sheep returns to feed station")
	data.time=2880.0
	shelter.observe(data,7.0)
	expect(not shelter.walking(7.0,false) and shelter.offset(7.0,false)==Shelter.SHELTER_OFFSET,"Time rewind resets the presentation baseline")
	data.sheep_comfort_fixtures=0
	shelter.observe(data,8.0)
	expect(shelter.offset(8.0,false)==Vector2.ZERO,"A sheep cannot shelter without a constructed canopy")
	data.sheep_comfort_fixtures=2
	shelter.observe(data,8.1)
	expect(shelter.offset(8.1,false)==Vector2.ZERO,"A mat alone does not count as a roof")
	data.sheep_comfort_fixtures=3
	data.objects["51,35"]={"type":"wall","owner":"qa"}
	shelter.observe(data,9.0)
	expect(shelter.offset(10.0,false)==Vector2.ZERO and shelter.status.contains("障礙"),"Wall blocks the shelter route with an explanation")
	data.objects["51,35"]={"type":"door","owner":"qa","open":false}
	expect(not shelter.route_clear(data),"Closed door blocks sheep travel")
	data.objects["51,35"].open=true
	expect(shelter.route_clear(data),"Open door follows original movement passability")
	data.objects.clear()
	data.forest["51,35"]={"mature":true}
	expect(not shelter.route_clear(data),"A planted mature tree blocks shelter travel")
	data.forest.clear()
	data.ground["51,35"]={"type":"floor","owner":"qa"}
	expect(shelter.route_clear(data),"The floor itself is passable")
	data.ground["51,35"].owner_visit=true
	expect(not shelter.route_clear(data),"Shared sheep does not enter a private visitor-restricted floor")
	data.ground.clear()
	shelter.observe(data,10.0)
	data.objects["51,35"]={"type":"wall","owner":"qa"}
	shelter.observe(data,10.5)
	expect(shelter.offset(11.0,false)==Vector2.ZERO and not shelter.walking(11.0,false),"A newly placed wall cancels an in-flight walk")
	data.objects.clear()
	data.region_id="maokong"
	shelter.observe(data,12.0,true)
	expect(shelter.offset(12.0,false)==Vector2.ZERO,"No sheep travel in another region")
	data.region_id="home"
	data.picnic=false
	shelter.observe(data,13.0,true)
	expect(shelter.offset(13.0,false)==Vector2.ZERO,"Picnic still gates animal visibility")
	var a:=Art.build_image("sheep","idle",0,Vector2i.ZERO,false,0,true)
	var b:=Art.build_image("sheep","idle",0,Vector2i.ZERO,false,1,true)
	expect(a.get_data()!=b.get_data(),"Two actual leg images differ")
	var inventory_before:Dictionary=state.get("players",{}).duplicate(true)
	var copy:=state.duplicate(true)
	shelter.observe(state,20.0,true)
	expect(state==copy and state.get("players",{})==inventory_before,"Observing does not mutate any input world record")
	print("SHEEP_SHELTER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
