extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const Survey=World.MINE_SURVEY
const Schema=preload("res://scripts/save_schema.gd")
const ALPHA="survey-alpha-test"
const BETA="survey-beta-test"
var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func place(world:World,actor:String,region:String,cell:Vector2i) -> void:
	var player:Dictionary=world.state.players[actor]
	player.region=region
	player.x=cell.x+0.5
	player.y=cell.y+0.5

func valid(state:Dictionary) -> bool:
	return Schema.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func _initialize() -> void:
	var path:=OS.get_environment("TEMP").path_join("mine-survey-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var world:=World.new()
	world.save_path=path
	world.add_player(ALPHA,"Alpha")
	world.add_player(BETA,"Beta")
	world.state.mine_depths.unlocked=5
	world.state.mine_depths.pumped=24
	var first:Vector2i=Survey.POINTS[1]
	var table:Vector2i=world.bobo_sites().table
	place(world,ALPHA,"jinguashi",table+Vector2i.RIGHT)
	expect(not world.act(ALPHA,"early","survey_claim",table).ok,"Incomplete surveys cannot claim")
	place(world,ALPHA,"mine_2",first)
	expect(not world.act(ALPHA,"wrong-region","survey_observe",first).ok,"Wrong floor cannot record observation")
	place(world,ALPHA,"mine_1",first+Vector2i(0,5))
	expect(not world.act(ALPHA,"far","survey_observe",first).ok,"Distant observation rejected")
	place(world,ALPHA,"mine_1",first+Vector2i.RIGHT)
	expect(not world.act(ALPHA,"unexpected-extra","survey_observe",first,"5").ok,"Caller cannot supply observation identity")
	world.state.regions.mine_1.objects[World.key(first)]={"type":"chest","owner":ALPHA,"items":{}}
	var before:=world.state.duplicate(true)
	world.save_path=path.path_join("missing").path_join("world.json")
	expect(not world.act(ALPHA,"first","survey_observe",first).ok and world.state==before,"Failed observation save rolls back")
	world.save_path=path
	var first_result:=world.act(ALPHA,"first","survey_observe",first)
	expect(first_result.ok and Survey.own_record(world.state,ALPHA).seen=={"1":true},"Occupied observation point remains interactive")
	expect(world.act(ALPHA,"first","survey_observe",first)==first_result,"Same request replays the original result")
	before=world.state.duplicate(true)
	expect(world.act(ALPHA,"reread","survey_observe",first).ok and world.state==before,"Re-reading is successful and does not mutate progress")
	for depth in range(2,6):
		var point:Vector2i=Survey.POINTS[depth]
		place(world,ALPHA,World.MINES.IDS[depth-1],point)
		expect(world.act(ALPHA,"observe-%d"%depth,"survey_observe",point).ok,"Record observation on level %d"%depth)
	expect(Survey.own_record(world.state,BETA)==Survey.FRESH,"Progress belongs to the observing player")
	place(world,ALPHA,"mine_5",table)
	expect(not world.act(ALPHA,"claim-wrong-region","survey_claim",table).ok,"Claim requires Jinguashi")
	place(world,ALPHA,"jinguashi",table+Vector2i(0,5))
	expect(not world.act(ALPHA,"claim-far","survey_claim",table).ok,"Claim requires proximity to the table")
	place(world,ALPHA,"jinguashi",table+Vector2i.RIGHT)
	world.state.players[ALPHA].inventory.gold_sample=Survey.REWARD_LIMIT
	before=world.state.duplicate(true)
	expect(not world.act(ALPHA,"full","survey_claim",table).ok and world.state==before,"Overflow leaves the reward claimable")
	world.state.players[ALPHA].inventory.gold_sample=0
	before=world.state.duplicate(true)
	world.save_path=path.path_join("missing").path_join("world.json")
	expect(not world.act(ALPHA,"claim","survey_claim",table).ok and world.state==before,"Failed claim save rolls back both the item and claim")
	world.save_path=path
	var claim:=world.act(ALPHA,"claim","survey_claim",table)
	expect(claim.ok and world.act(ALPHA,"claim","survey_claim",table)==claim,"Claim request replays the original success")
	expect(not world.act(ALPHA,"again","survey_claim",table).ok and world.state.players[ALPHA].inventory.gold_sample==1,"Fresh claim request cannot award a duplicate")
	var reopened:=World.new()
	expect(reopened.load_world(path) and reopened.state.version==26 and Survey.own_record(reopened.state,ALPHA).claimed,"Claim persists in a v14 save")
	var legacy:=reopened.state.duplicate(true)
	legacy.version=13;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	legacy.erase("mine_survey")
	expect(valid(legacy) and legacy.version==26 and legacy.mine_survey==Survey.fresh(),"v13 migration starts with empty survey records")
	var malformed:=reopened.state.duplicate(true)
	malformed.mine_survey.players[ALPHA].seen.erase("1")
	expect(not valid(malformed),"Schema rejects a claimed partial survey")
	malformed=reopened.state.duplicate(true)
	malformed.mine_survey.players["unknown"]=Survey.FRESH.duplicate(true)
	expect(not valid(malformed),"Schema rejects survey records for unknown players")
	var session:=Session.new()
	session.world=world
	session.peers[1]=ALPHA
	expect(not session.public_state("jinguashi").has("mine_survey"),"Public state excludes all private records")
	session._send_snapshot(1)
	expect(session.snapshot.get("mine_survey",{})=={"own_record":Survey.own_record(world.state,ALPHA)},"Alpha receives only their record")
	session.peers[1]=BETA
	session._send_snapshot(1)
	expect(session.snapshot.get("mine_survey",{})=={"own_record":Survey.FRESH},"Beta cannot see Alpha's survey record")
	session.free()
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("MINE_SURVEY_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
