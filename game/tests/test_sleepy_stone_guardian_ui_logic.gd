extends SceneTree
## Focused test for the guardian UI/audio modules. Preloads only the guardian scripts
## (no World/Session/main); the panel is driven through a small stand-in for main.

const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const UI=preload("res://scripts/sleepy_stone_guardian_ui.gd")
const Bell=preload("res://scripts/sleepy_stone_guardian_audio.gd")
var checks:=0
var failures:=0

class FakeSession extends RefCounted:
	var snapshot:Dictionary={}
	var own_id:="p1"
	var sent:Array=[]
	func perform(action:String,cell:Vector2i,extra:String="") -> int:
		sent.append([action,cell,extra])
		return sent.size()

class FakeSound extends Node:
	var reduced_motion:=false
	var master_volume:=1.0
	var ambience_volume:=0.25
	var player:AudioStreamPlayer
	var cue_kind:=""
	func cue_gain(_kind:String) -> float:
		return master_volume*ambience_volume

class FakeMain extends Node:
	var session:=FakeSession.new()
	var sound:FakeSound
	var modal:PanelContainer
	var modal_feedback:Label
	var controller_navigation:=false
	var closes:=0
	func _open_modal(title:String) -> VBoxContainer:
		_close_modal()
		modal=PanelContainer.new()
		add_child(modal)
		var column:=VBoxContainer.new()
		modal.add_child(column)
		column.add_child(label(title,25))
		var content:=VBoxContainer.new()
		column.add_child(content)
		modal_feedback=label("",14)
		column.add_child(modal_feedback)
		return content
	func _close_modal() -> void:
		if modal==null:return
		closes+=1
		var old:=modal
		modal=null
		modal_feedback=null
		# Like main.gd: leave the tree now, free at the end of the frame.
		remove_child(old)
		old.queue_free()
	func label(text:String,_size:int=17) -> Label:
		var l:=Label.new()
		l.text=text
		return l
	func button(text:String,callback:Callable) -> Button:
		var b:=Button.new()
		b.text=text
		b.pressed.connect(callback)
		return b
	func _layout_preview() -> void:
		pass

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	check_playback()
	check_text()
	check_options()
	check_points_and_labels()
	check_stream()
	await process_frame
	check_panel()
	print("SLEEPY_STONE_GUARDIAN_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func notes_for(bells:Array) -> Array:
	var out:Array=[]
	for b:int in bells:out.append({"bell":b,"hz":Guardian.PITCH_HZ[b],"shape":Guardian.SHAPES[b],"name":Guardian.BELL_NAMES[b]})
	return out

func check_playback() -> void:
	expect(UI.playback_step(3,0.0)==0 and UI.playback_step(3,0.59)==0,"First note is lit for the first 0.6 s")
	expect(UI.playback_step(3,0.61)==-1 and UI.playback_step(3,0.79)==-1,"Gap between notes is dark")
	expect(UI.playback_step(3,0.81)==1 and UI.playback_step(3,1.39)==1 and UI.playback_step(3,1.41)==-1,"Second note window")
	expect(UI.playback_step(3,1.61)==2 and UI.playback_step(3,2.19)==2,"Third note window")
	expect(UI.playback_step(3,2.21)==-1 and UI.playback_step(3,2.5)==-1 and UI.playback_step(3,99.0)==-1,"Nothing lit after the end")
	expect(UI.playback_step(2,1.61)==-1,"A two-note hum has no third step")
	expect(UI.playback_step(3,-0.1)==-1 and UI.playback_step(0,0.1)==-1 and UI.playback_step(-2,0.1)==-1,"Before start / empty hum")
	expect(UI.playback_step(3,NAN)==-1 and UI.playback_step(3,INF)==-1,"Non-finite time lights nothing")
	for t in [0.0,0.3,0.9,1.7]:expect(UI.playback_step(3,t,true)==-1,"Reduced motion never animates (t=%s)"%t)
	expect(is_equal_approx(UI.playback_duration(2),1.4) and is_equal_approx(UI.playback_duration(3),2.2),"Duration is notes*0.8-0.2")
	expect(UI.playback_duration(0)==0.0 and UI.playback_duration(-1)==0.0,"Empty hum has no duration")
	for n in [2,3]:
		var seen:Array=[]
		var t:=0.0
		while t<UI.playback_duration(n)+0.5:
			var step:=UI.playback_step(n,t)
			if step>=0 and (seen.is_empty() or seen[-1]!=step):seen.append(step)
			t+=0.05
		expect(seen==range(n),"Every note lights exactly once, in order (%d notes: %s)"%[n,seen])

func check_text() -> void:
	var notes:=notes_for([0,1,2])
	expect(UI.sequence_text(notes,1)=="● 低音鈴 → 【▲ 中音鈴】 → ■ 高音鈴","Sequence text with the middle note lit: "+UI.sequence_text(notes,1))
	expect(UI.sequence_text(notes,-1)=="● 低音鈴 → ▲ 中音鈴 → ■ 高音鈴","Sequence text after playback keeps the whole order")
	expect(UI.sequence_text(notes_for([2,0]),0)=="【■ 高音鈴】 → ● 低音鈴","Two-note phrase")
	expect(UI.sequence_text([],0)=="" and UI.sequence_text([{"bell":9},{"x":1},"junk"],0)=="","Malformed notes are skipped")
	expect(UI.sequence_text([{"bell":1.0}],-1)=="▲ 中音鈴","JSON float bell index is accepted")
	expect(UI.numbered_text(notes)=="1 ● 低音鈴　2 ▲ 中音鈴　3 ■ 高音鈴","Numbered static form: "+UI.numbered_text(notes))
	expect(UI.progress_text({"round":0,"calm":0,"claimed":false},1)=="已接上 1／2　·　陪伴 0／3","Round 0 progress")
	expect(UI.progress_text({"round":1,"calm":1,"claimed":false},1)=="已接上 1／3　·　陪伴 1／3","Round 1 progress with a quiet visit")
	expect(UI.progress_text({"round":1,"calm":0,"claimed":false},9).begins_with("已接上 3／3"),"Progress never exceeds the phrase length")
	expect(UI.progress_text({"round":2,"calm":0,"claimed":false},0)=="","No progress line once awake")
	for record in [{"round":0,"calm":0,"claimed":false},{"round":1,"calm":0,"claimed":false},{"round":2,"calm":0,"claimed":false},{"round":2,"calm":0,"claimed":true}]:
		var words:=UI.status_text(record)
		expect(not words.is_empty(),"Status text exists for %s"%str(record))
		for bad in ["倒數","失敗","扣","秒"]:expect(not words.contains(bad),"Status text has no timer/penalty wording (%s)"%bad)
	expect(UI.clean_record(null)==Guardian.fresh() and UI.clean_record("x")==Guardian.fresh(),"Absent record reads as fresh")
	expect(UI.clean_record({"round":1.0,"calm":2.0,"claimed":true})=={"round":1,"calm":2,"claimed":true},"JSON floats are normalised")
	expect(UI.clean_record({"round":99,"calm":-4,"claimed":"yes"})=={"round":2,"calm":0,"claimed":false},"Out-of-range values are clamped")
	expect(UI.record_of({"players":{"p1":{"sleepy_guardian":{"round":1,"calm":0,"claimed":false}}}},"p1").round==1,"Own record is read from the snapshot")
	expect(UI.record_of({"players":{"p1":{}}},"p1")==Guardian.fresh() and UI.record_of({},"p1")==Guardian.fresh(),"Missing record or player is fresh")

func ids(options:Array) -> Array:
	var out:Array=[]
	for option:Dictionary in options:out.append(option.id)
	return out

func check_options() -> void:
	var asleep:=UI.menu_options(Guardian.fresh(),-1)
	expect(ids(asleep)==["listen","ring_0","ring_1","ring_2","sit","leave"],"Asleep menu order: %s"%str(ids(asleep)))
	var labels:Array=[]
	for option:Dictionary in asleep:labels.append(option.label)
	expect(labels==["聽石像哼","敲 ●低音鈴","敲 ▲中音鈴","敲 ■高音鈴","靜靜陪牠","離開"],"Asleep menu labels: %s"%str(labels))
	expect(asleep[0].action=="guardian_listen" and asleep[0].cell==Guardian.GUARDIAN,"Listen targets the statue")
	for i in 3:expect(asleep[i+1].action=="guardian_ring" and asleep[i+1].cell==Guardian.BELLS[i],"Ring %d targets its own bell cell"%i)
	expect(asleep[4].action=="guardian_sit" and asleep[4].cell==Guardian.GUARDIAN,"Sit targets the statue")
	expect(asleep[5].action=="","Leave sends nothing")
	for option:Dictionary in asleep:
		expect(option.action=="" or option.action in Guardian.ACTIONS,"Option uses a contract action")
		expect(option.has("id") and option.has("label") and option.has("action") and option.has("cell"),"Descriptor shape")
	expect(asleep[0].focus and not asleep[2].focus,"Statue entry focuses listen")
	var at_bell:=UI.menu_options(Guardian.fresh(),1)
	expect(at_bell[2].focus and not at_bell[0].focus and not at_bell[1].focus,"Opening at the mid bell focuses its ring option")
	var round1:=UI.menu_options({"round":1,"calm":2,"claimed":false},-1)
	expect(ids(round1)==ids(asleep),"Round 1 keeps listen, bells and the sit route")
	var awake:=UI.menu_options({"round":2,"calm":0,"claimed":false},-1)
	expect(ids(awake)==["claim","leave"] and awake[0].label=="收下謝禮" and awake[0].action=="guardian_claim" and awake[0].cell==Guardian.GUARDIAN,"Awake and unclaimed offers the reward")
	var claimed:=UI.menu_options({"round":2,"calm":3,"claimed":true},2)
	expect(ids(claimed)==["leave"] and claimed[0].focus,"Claimed leaves only the exit")
	# Reach mirrors Guardian.near per target cell.
	var middle:=Vector2(34.0,11.5)
	var flags:Array=[]
	for option:Dictionary in asleep:flags.append(UI.option_enabled(option,middle))
	expect(flags==[true,true,true,false,true,true],"Between low and mid bell: high bell is out of reach (%s)"%str(flags))
	var east:=Vector2(36.5,12.0)
	flags=[]
	for option:Dictionary in asleep:flags.append(UI.option_enabled(option,east))
	expect(flags==[false,false,true,true,false,true],"By the high bell: statue and low bell are out of reach (%s)"%str(flags))
	expect(UI.button_name("ring_0")=="GuardianRing0" and UI.button_name("listen")=="GuardianListen","Stable node names")

func check_points_and_labels() -> void:
	var points:=UI.points({},{},"mine_4",4)
	expect(points.size()==4,"Exactly four interact points")
	expect(points.get("mine_guardian")==Vector2(34.5,10.5),"Statue point is the design cell centre")
	expect(points.get("mine_guardian_bell_0")==Vector2(32.5,11.5) and points.get("mine_guardian_bell_1")==Vector2(35.5,11.5) and points.get("mine_guardian_bell_2")==Vector2(37.5,12.5),"Bell points are the design cell centres")
	expect(UI.points({},{},"mine_4",15).size()==4,"Still there when deeper floors are open")
	for case in [["mine_4",3],["mine_4",0],["mine_3",4],["mine_5",5],["mine_8",8],["mine_14",15],["home",15],["jinguashi",4],["",4]]:
		expect(UI.points({},{},case[0],case[1]).is_empty(),"No points for %s unlocked %d"%case)
	for id:String in points:
		expect(Guardian.near(points[id],Guardian.GUARDIAN) or Guardian.bell_at(Vector2i(points[id].floor()))>=0,"Point %s sits on a guardian cell"%id)
	expect(UI.bell_of("mine_guardian_bell_2")==2 and UI.bell_of("mine_guardian")==-1 and UI.bell_of("mine_guardian_bell_3")==-1 and UI.bell_of("mine_guardian_bell_x")==-1 and UI.bell_of("")==-1,"Bell index from point id")
	expect(UI.label("mine_guardian",Guardian.fresh())=="打瞌睡石像","Statue label while asleep")
	expect(UI.label("mine_guardian",{"round":1,"calm":0,"claimed":false})=="打瞌睡石像","Statue label after the first phrase")
	expect(UI.label("mine_guardian",{"round":2,"calm":0,"claimed":false})=="石像 · 有謝禮","Statue label when a gift waits")
	expect(UI.label("mine_guardian",{"round":2,"calm":0,"claimed":true})=="醒著的石像","Statue label once claimed")
	expect(UI.label("mine_guardian_bell_0",{})=="●低音鈴" and UI.label("mine_guardian_bell_1",{})=="▲中音鈴" and UI.label("mine_guardian_bell_2",{})=="■高音鈴","Bell labels carry shape and name")
	expect(UI.label("mine_survey",{})=="" and UI.label("mine_guardian_bell_7",{})=="","Unknown ids have no label")

func check_stream() -> void:
	var sizes:Array=[]
	for bell in 3:
		var stream:=Bell.make_stream(bell) as AudioStreamWAV
		expect(stream!=null,"Bell %d has a WAV stream"%bell)
		if stream==null:continue
		expect(stream.mix_rate==22050 and stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,"Bell %d is 22.05 kHz 16-bit mono"%bell)
		expect(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"Bell %d does not loop"%bell)
		expect(stream.data.size()==int(22050*Bell.DURATION)*2,"Bell %d has the expected sample count (%d bytes)"%[bell,stream.data.size()])
		expect(is_equal_approx(stream.get_length(),float(int(22050*Bell.DURATION))/22050.0),"Bell %d lasts about %.2f s (got %.3f)"%[bell,Bell.DURATION,stream.get_length()])
		expect(stream.get_length()<=UI.STEP_ON+UI.STEP_GAP,"Bell %d ends before the next hum step starts"%bell)
		expect(Bell.make_stream(bell)==stream,"Bell %d stream is cached"%bell)
		var peak:=0
		var crossings:=0
		var last:=0
		var count:=stream.data.size()/2
		for i in count:
			var v:=stream.data.decode_s16(i*2)
			peak=maxi(peak,absi(v))
			if i>0 and last<0 and v>=0:crossings+=1
			last=v
		expect(peak>1000 and peak<12000,"Bell %d is audible but soft (peak %d of 32767)"%[bell,peak])
		expect(absi(stream.data.decode_s16(0))<200 and absi(stream.data.decode_s16((count-1)*2))<200,"Bell %d starts and ends near silence"%bell)
		sizes.append(crossings)
	expect(sizes.size()==3 and sizes[0]<sizes[1] and sizes[1]<sizes[2],"Low, mid, high bells have rising cycle counts (%s)"%str(sizes))
	expect(Bell.make_stream(-1)==null and Bell.make_stream(3)==null,"Unknown bell has no stream")

func snapshot_at(pos:Vector2,record=null,region:="mine_4",unlocked:=4) -> Dictionary:
	var person:={"x":pos.x,"y":pos.y}
	if record!=null:person["sleepy_guardian"]=record
	return {"region_id":region,"mine_depths":{"unlocked":unlocked},"players":{"p1":person}}

func find_button(main:FakeMain,name:String) -> Button:
	return main.modal.find_child(name,true,false) as Button if main.modal!=null else null

func text_of(main:FakeMain,name:String) -> String:
	var node:=main.modal.find_child(name,true,false) as Label
	return node.text if node!=null else "<missing>"

func check_panel() -> void:
	var main:=FakeMain.new()
	main.sound=FakeSound.new()
	main.add_child(main.sound)
	root.add_child(main)
	var middle:=Vector2(34.0,11.5)
	main.set_meta(UI.CLOCK_META,100.0)
	# Not available: nothing opens.
	main.session.snapshot=snapshot_at(middle,null,"mine_4",3)
	UI.open(main,"mine_guardian")
	expect(main.modal==null and UI.lit_bell(main)==-1,"Menu does not open before B4 is unlocked")
	main.session.snapshot=snapshot_at(middle)
	UI.open(main,"mine_guardian_bell_1")
	expect(UI.is_open(main),"Menu opens on an open B4")
	for name in ["GuardianListen","GuardianRing0","GuardianRing1","GuardianRing2","GuardianSit","GuardianLeave"]:
		expect(find_button(main,name)!=null,"Button %s exists"%name)
	expect(find_button(main,"GuardianClaim")==null,"No reward button while asleep")
	expect(not find_button(main,"GuardianRing0").disabled and not find_button(main,"GuardianRing1").disabled and find_button(main,"GuardianRing2").disabled,"Only reachable bells are enabled")
	# The label stays short (large text); the step-closer cue is the tooltip plus the reach hint line.
	expect(find_button(main,"GuardianRing2").text.begins_with("敲 ■高音鈴") and find_button(main,"GuardianRing2").tooltip_text=="走近一點","Out-of-reach bell says to step closer")
	expect(find_button(main,"GuardianRing1").get_meta("guardian_focus"),"The bell that opened the menu is the default focus")
	expect(text_of(main,"GuardianProgress")=="已接上 0／2　·　陪伴 0／3","Fresh progress line: "+text_of(main,"GuardianProgress"))
	expect(text_of(main,"GuardianSequenceText").contains("2 個音"),"Before listening the panel says how to hear the hum")
	find_button(main,"GuardianListen").pressed.emit()
	find_button(main,"GuardianRing0").pressed.emit()
	find_button(main,"GuardianSit").pressed.emit()
	expect(main.session.sent==[["guardian_listen",Guardian.GUARDIAN,""],["guardian_ring",Guardian.BELLS[0],""],["guardian_sit",Guardian.GUARDIAN,""]],"Buttons send the contract actions and cells: %s"%str(main.session.sent))
	expect(UI.is_open(main),"Acting keeps the menu open")
	# Listen: notes light one at a time and stay readable afterwards.
	var listen:={"ok":true,"message":"石像在睡夢中哼了 2 個音：●低音鈴 ■高音鈴","guardian":{"outcome":"listen","round":0,"calm":0,"claimed":false,"entered":0,"notes":notes_for([0,2])}}
	UI.handle_result(main,"guardian_listen",listen)
	var voice:=main.sound.get_node_or_null(Bell.PLAYER_NAME) as AudioStreamPlayer
	expect(voice!=null and voice.stream==Bell.make_stream(0),"First hum note plays the low bell stream")
	expect(UI.lit_bell(main)==0,"First note lights the low bell")
	expect(text_of(main,"GuardianSequenceText")=="石像哼的順序：【● 低音鈴】 → ■ 高音鈴","Panel text marks the lit note: "+text_of(main,"GuardianSequenceText"))
	var chip0:=main.modal.find_child("GuardianNote0",true,false)
	var chip1:=main.modal.find_child("GuardianNote1",true,false)
	expect(chip0!=null and chip1!=null and chip0.get_meta("guardian_lit") and not chip1.get_meta("guardian_lit"),"Chip 1 is lit, chip 2 is not")
	expect(chip0!=null and (chip0.get_child(0) as Label).text=="1  ● 低音鈴","Chip shows order, shape and name")
	main.set_meta(UI.CLOCK_META,100.7)
	UI.refresh(main)
	expect(UI.lit_bell(main)==-1 and text_of(main,"GuardianSequenceText")=="石像哼的順序：● 低音鈴 → ■ 高音鈴","Gap between notes lights nothing")
	main.set_meta(UI.CLOCK_META,100.9)
	UI.refresh(main)
	expect(UI.lit_bell(main)==2 and voice!=null and voice.stream==Bell.make_stream(2),"Second note lights and plays the high bell")
	main.set_meta(UI.CLOCK_META,103.0)
	UI.refresh(main)
	expect(UI.lit_bell(main)==-1,"Nothing is lit after the hum")
	expect(text_of(main,"GuardianSequenceText")=="石像哼的順序：● 低音鈴 → ■ 高音鈴" and main.modal.find_child("GuardianNote1",true,false)!=null,"The whole sequence stays readable after playback")
	expect(text_of(main,"GuardianMessage")==listen.message,"Server message is shown")
	# Free replay restarts from the first note.
	UI.handle_result(main,"guardian_listen",listen)
	expect(UI.lit_bell(main)==0,"Listening again replays from the start")
	# Correct bell: flash, progress, playback stops.
	UI.handle_result(main,"guardian_ring",{"ok":true,"message":"石像的耳朵動了動。","guardian":{"outcome":"progress","round":0,"calm":0,"claimed":false,"entered":1,"bell":0}})
	expect(UI.lit_bell(main)==0 and voice!=null and voice.stream==Bell.make_stream(0),"Rung bell flashes and sounds")
	expect(text_of(main,"GuardianProgress")=="已接上 1／2　·　陪伴 0／3","Progress after one correct bell: "+text_of(main,"GuardianProgress"))
	chip0=main.modal.find_child("GuardianNote0",true,false)
	expect(chip0!=null and (chip0.get_child(0) as Label).text.ends_with("✓"),"Echoed note is ticked")
	main.set_meta(UI.CLOCK_META,104.0)
	UI.refresh(main)
	expect(UI.lit_bell(main)==-1,"Flash ends on its own")
	# Wrong bell: gentle message, progress back to the phrase start, notes kept, nothing else lost.
	var wrong_message:="石像的眉毛皺了一下，翻個身。再聽一次牠的哼聲吧。"
	UI.handle_result(main,"guardian_ring",{"ok":true,"message":wrong_message,"guardian":{"outcome":"wrong","round":0,"calm":0,"claimed":false,"entered":0,"bell":1}})
	expect(UI.lit_bell(main)==1,"A wrong bell still rings and flashes")
	expect(text_of(main,"GuardianMessage")==wrong_message and text_of(main,"GuardianProgress").begins_with("已接上 0／2"),"Wrong bell only restarts the phrase")
	expect(text_of(main,"GuardianSequenceText")=="石像哼的順序：● 低音鈴 → ■ 高音鈴" and UI.is_open(main),"Heard notes stay after a wrong bell")
	# Closing and reopening keeps what was heard (walking to another bell needs no memory).
	UI.handle_result(main,"guardian_ring",{"ok":true,"message":"石像的耳朵動了動。","guardian":{"outcome":"progress","round":0,"calm":0,"claimed":false,"entered":1,"bell":0}})
	main._close_modal()
	expect(not UI.is_open(main),"Menu closes")
	main.set_meta(UI.CLOCK_META,110.0)
	expect(UI.lit_bell(main)==-1,"Nothing lit while closed")
	main.session.snapshot=snapshot_at(Vector2(36.5,12.0))
	UI.open(main,"mine_guardian_bell_2")
	expect(text_of(main,"GuardianSequenceText")=="石像哼的順序：● 低音鈴 → ■ 高音鈴" and text_of(main,"GuardianProgress").begins_with("已接上 1／2"),"Reopening by another bell shows the same hum and progress")
	expect(UI.lit_bell(main)==-1,"Reopening does not replay by itself")
	expect(find_button(main,"GuardianListen").disabled and not find_button(main,"GuardianRing2").disabled and find_button(main,"GuardianSit").disabled,"Reach follows the new position")
	expect((main.modal.find_child("GuardianReachHint",true,false) as Label).visible,"A hint explains greyed options")
	# Round complete: snapshot first, then the result; the old phrase is dropped.
	main.session.snapshot=snapshot_at(Vector2(36.5,12.0),{"round":1,"calm":0,"claimed":false})
	UI.refresh(main)
	UI.handle_result(main,"guardian_ring",{"ok":true,"message":"石像呼嚕聲變小了。牠好像想再哼一段更長的。","guardian":{"outcome":"round","round":1,"calm":0,"claimed":false,"entered":0,"bell":2}})
	expect(text_of(main,"GuardianProgress")=="已接上 0／3　·　陪伴 0／3" and text_of(main,"GuardianSequenceText").contains("3 個音"),"Second round asks for a fresh listen: "+text_of(main,"GuardianProgress"))
	expect(main.modal.find_child("GuardianNote0",true,false)==null or not (main.modal.find_child("GuardianSequence",true,false) as Control).visible,"Old notes are not shown for the new round")
	# Reduced motion: whole numbered sequence at once, no stepping.
	main.sound.reduced_motion=true
	main.session.snapshot=snapshot_at(middle,{"round":1,"calm":0,"claimed":false})
	main.set_meta(UI.CLOCK_META,120.0)
	UI.handle_result(main,"guardian_listen",{"ok":true,"message":"哼","guardian":{"outcome":"listen","round":1,"calm":0,"claimed":false,"entered":0,"notes":notes_for([1,0,2])}})
	expect(text_of(main,"GuardianSequenceText")=="石像哼的順序：1 ▲ 中音鈴　2 ● 低音鈴　3 ■ 高音鈴","Reduced motion shows the numbered sequence: "+text_of(main,"GuardianSequenceText"))
	expect(UI.lit_bell(main)==-1,"Reduced motion lights no hum step")
	chip0=main.modal.find_child("GuardianNote0",true,false)
	expect(chip0!=null and not chip0.get_meta("guardian_lit"),"Reduced motion chips are static")
	main.set_meta(UI.CLOCK_META,120.9)
	UI.refresh(main)
	expect(voice!=null and voice.stream==Bell.make_stream(0),"Reduced motion still plays the tones in order")
	main.sound.reduced_motion=false
	# Audio off: no tone is started.
	main.sound.ambience_volume=0.0
	expect(Bell.gain(main)==0.0,"Zero ambience volume means zero bell gain")
	if voice!=null:voice.stream=null
	UI.handle_result(main,"guardian_ring",{"ok":true,"message":"石像的耳朵動了動。","guardian":{"outcome":"progress","round":1,"calm":0,"claimed":false,"entered":1,"bell":1}})
	expect(voice!=null and voice.stream==null and not voice.playing,"Muted bell does not play")
	expect(UI.lit_bell(main)==1 and text_of(main,"GuardianProgress").begins_with("已接上 1／3"),"Muted play still shows the bell and progress")
	main.sound.ambience_volume=0.25
	Bell.play(null,1)
	Bell.play(main,9)
	expect(true,"Bell.play tolerates a missing main and an unknown bell")
	# Sit route.
	main.session.snapshot=snapshot_at(middle,{"round":1,"calm":1,"claimed":false})
	UI.handle_result(main,"guardian_sit",{"ok":true,"message":"你在石像旁邊坐下。再陪牠一下下就好。","guardian":{"outcome":"sit","round":1,"calm":1,"claimed":false,"entered":1}})
	expect(text_of(main,"GuardianProgress").ends_with("陪伴 1／3"),"Sitting shows 陪伴 1／3: "+text_of(main,"GuardianProgress"))
	# Awake: reward offered, puzzle options gone.
	main.session.snapshot=snapshot_at(middle,{"round":2,"calm":3,"claimed":false})
	UI.handle_result(main,"guardian_sit",{"ok":true,"message":"你安靜陪了牠一會兒，牠自己慢慢醒來，笑了一下。","guardian":{"outcome":"awake","round":2,"calm":3,"claimed":false,"entered":0}})
	expect(find_button(main,"GuardianClaim")!=null and not find_button(main,"GuardianClaim").disabled,"Awake offers the reward")
	expect(find_button(main,"GuardianListen")==null or find_button(main,"GuardianListen").is_queued_for_deletion(),"Awake hides the listen option")
	find_button(main,"GuardianClaim").pressed.emit()
	expect(main.session.sent[-1]==["guardian_claim",Guardian.GUARDIAN,""],"Claim sends the contract action")
	main.session.snapshot=snapshot_at(middle,{"round":2,"calm":3,"claimed":true})
	UI.handle_result(main,"guardian_claim",{"ok":true,"message":"石像讓出身後的凹槽，裡面有一小撮晶砂。","guardian":{"outcome":"claim","round":2,"calm":3,"claimed":true,"entered":0}})
	var claim_button:=find_button(main,"GuardianClaim")
	expect(claim_button==null or claim_button.is_queued_for_deletion(),"Claimed removes the reward option")
	expect(find_button(main,"GuardianLeave")!=null,"Leave remains")
	expect(main.get_meta(UI.META,{}).size()>0 and not JSON.stringify(main.get_meta(UI.META,{})).contains("p1"),"UI state never holds a player id")
	# A result without the guardian sub-dictionary degrades to the message only.
	UI.handle_result(main,"guardian_listen",{"ok":false,"message":"牠已經醒了，正眨著琥珀色的眼睛看你。"})
	expect(text_of(main,"GuardianMessage")=="牠已經醒了，正眨著琥珀色的眼睛看你。","Plain result still shows its message")
	UI.handle_result(main,"mine_extract",{"ok":true,"message":"x"})
	expect(text_of(main,"GuardianMessage")!="x","Other actions are ignored")
	# Leave button closes; walking away closes; leaving the region clears everything.
	var before:=main.closes
	find_button(main,"GuardianLeave").pressed.emit()
	expect(main.closes==before+1 and not UI.is_open(main),"Leave closes the menu")
	main.session.snapshot=snapshot_at(middle)
	UI.open(main,"mine_guardian")
	main.session.snapshot=snapshot_at(Vector2(34.5,20.0))
	UI.refresh(main)
	expect(not UI.is_open(main),"Menu closes when the player is far from the nook")
	main.session.snapshot=snapshot_at(middle)
	UI.open(main,"mine_guardian")
	main.session.snapshot=snapshot_at(middle,null,"mine_5",5)
	UI.refresh(main)
	expect(not UI.is_open(main) and not main.has_meta(UI.META),"Leaving mine_4 closes the menu and drops all state")
	expect(UI.lit_bell(main)==-1,"Nothing lit after cleanup")
	main.free()
