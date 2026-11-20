extends RefCounted
## 害羞菇: four short synthesized cues (rustle / peek / splash / open). Depends only on the
## pure Shy rules so it loads without World/Session.
##
## Loudness follows the same setting as the sleepy stone guardian's bells:
## SoftAudio.cue_gain(GAIN_KIND), i.e. master_volume * ambience_volume. At zero nothing is
## created or played. Every cue is deterministic (the rustle noise is a fixed-seed LCG).

const Shy=preload("res://scripts/shy_mushroom.gd")
## Same sample rate as SoftAudio.RATE.
const RATE:=22050
const PLAYER_NAME:="ShyMushroomCue"
## Which soft_audio cue family decides the gain (the chimes: master x ambience).
const GAIN_KIND:="ceramic_chime"
const CUES:=[Shy.CUE_RUSTLE,Shy.CUE_PEEK,Shy.CUE_SPLASH,Shy.CUE_OPEN]
## Seconds per cue. The splash is shorter than STAGGER so the open arpeggio never cuts it off.
const DURATIONS:={"shy_rustle":0.46,"shy_peek":0.36,"shy_splash":0.26,"shy_open":0.66}
## Peak amplitude (fraction of full scale) each cue is normalized to.
const PEAKS:={"shy_rustle":0.13,"shy_peek":0.11,"shy_splash":0.12,"shy_open":0.11}
const STAGGER:=0.28
const FADE_IN:=0.005
const FADE_OUT:=0.025

static var _streams:Dictionary={}

static func reset_cache() -> void:
	_streams.clear()

static func valid_cue(cue:String) -> bool:
	return cue in CUES

## Soft sine note with a quiet octave partial: quick attack, squared decay.
static func note(t:float,frequency:float,duration:float) -> float:
	if t<0.0 or t>=duration:return 0.0
	var envelope:=minf(t/0.012,1.0)*pow(1.0-t/duration,2.0)
	return envelope*(sin(TAU*frequency*t)+sin(TAU*2.0*frequency*t)*0.18)

static func _rustle(samples:int) -> PackedFloat32Array:
	var out:=PackedFloat32Array()
	out.resize(samples)
	var seed_state:=20261119
	var low:=0.0
	var slow:=0.0
	# Three soft shuffles: start time, length, loudness.
	var bursts:=[[0.02,0.12,0.8],[0.17,0.10,1.0],[0.30,0.14,0.65]]
	for i in samples:
		seed_state=(seed_state*1103515245+12345)&0x7fffffff
		var white:=float(seed_state)/float(0x3fffffff)-1.0
		# Band-limited: low-pass, then remove the slow drift so it stays a dry shuffle.
		low+=(white-low)*0.32
		slow+=(low-slow)*0.04
		var t:=float(i)/RATE
		var envelope:=0.0
		for burst in bursts:
			var phase:=(t-float(burst[0]))/float(burst[1])
			if phase>0.0 and phase<1.0:envelope+=pow(sin(PI*phase),2.0)*float(burst[2])
		out[i]=(low-slow)*envelope
	return out

static func _peek(samples:int) -> PackedFloat32Array:
	var out:=PackedFloat32Array()
	out.resize(samples)
	for i in samples:
		var t:=float(i)/RATE
		out[i]=note(t,523.25,0.16)+note(t-0.14,698.46,0.21)
	return out

static func _splash(samples:int) -> PackedFloat32Array:
	var out:=PackedFloat32Array()
	out.resize(samples)
	var phase_a:=0.0
	var phase_b:=0.0
	for i in samples:
		var t:=float(i)/RATE
		# Main droplet falls 1500 -> ~520 Hz; a smaller echo drop follows.
		var hz_a:=520.0+980.0*exp(-t/0.035)
		phase_a+=TAU*hz_a/RATE
		var wave:=sin(phase_a)*minf(t/0.004,1.0)*exp(-t/0.05)
		var later:=t-0.11
		if later>=0.0:
			var hz_b:=430.0+700.0*exp(-later/0.03)
			phase_b+=TAU*hz_b/RATE
			wave+=sin(phase_b)*minf(later/0.004,1.0)*exp(-later/0.04)*0.55
		out[i]=wave
	return out

static func _open(samples:int) -> PackedFloat32Array:
	var out:=PackedFloat32Array()
	out.resize(samples)
	for i in samples:
		var t:=float(i)/RATE
		out[i]=note(t,523.25,0.36)+note(t-0.13,659.25,0.36)+note(t-0.26,783.99,0.38)
	return out

## Cached per cue; null for anything that is not one of the four Shy.CUE_* ids.
static func make_stream(cue:String) -> AudioStream:
	if not valid_cue(cue):return null
	if _streams.has(cue):return _streams[cue]
	var samples:=int(RATE*float(DURATIONS[cue]))
	var wave:PackedFloat32Array
	match cue:
		Shy.CUE_RUSTLE:wave=_rustle(samples)
		Shy.CUE_PEEK:wave=_peek(samples)
		Shy.CUE_SPLASH:wave=_splash(samples)
		_:wave=_open(samples)
	var fade_in:=int(RATE*FADE_IN)
	var fade_out:=int(RATE*FADE_OUT)
	var peak:=0.0
	for i in samples:
		var edge:=minf(1.0,minf(float(i)/fade_in,float(samples-1-i)/fade_out))
		wave[i]*=edge
		peak=maxf(peak,absf(wave[i]))
	var scale:=float(PEAKS[cue])/peak if peak>0.0 else 0.0
	var bytes:=PackedByteArray()
	bytes.resize(samples*2)
	for i in samples:
		bytes.encode_s16(i*2,int(wave[i]*scale*32767.0))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=RATE
	stream.stereo=false
	stream.data=bytes
	_streams[cue]=stream
	return stream

## Linear gain a cue would play at right now; 0 when audio is off or unavailable.
static func gain(main) -> float:
	if not is_instance_valid(main):return 0.0
	var sound=main.get("sound")
	if not is_instance_valid(sound) or not sound is Node or not sound.has_method("cue_gain"):return 0.0
	var amount:=float(sound.cue_gain(GAIN_KIND))
	return amount if is_finite(amount) and amount>0.0 else 0.0

static func play(main,cue:String) -> void:
	if not valid_cue(cue):return
	var amount:=gain(main)
	var sound=main.get("sound") if is_instance_valid(main) else null
	if not is_instance_valid(sound) or not sound is Node or not sound.is_inside_tree():return
	var voice:=sound.get_node_or_null(PLAYER_NAME) as AudioStreamPlayer
	if amount<=0.0:
		if voice!=null:voice.stop()
		return
	if voice==null:
		voice=AudioStreamPlayer.new()
		voice.name=PLAYER_NAME
		sound.add_child(voice)
	# Let the mushroom's own cue replace the generic "action" blip that accompanies the notice.
	var shared=sound.get("player")
	if shared is AudioStreamPlayer and shared.playing and str(sound.get("cue_kind"))=="action":shared.stop()
	voice.stop()
	voice.volume_db=linear_to_db(amount)
	voice.stream=make_stream(cue)
	voice.play()

## Plays `cues` in order: the first valid one now, each later one STAGGER seconds after the
## previous, on main's scene tree timer. A main freed in the meantime is a silent no-op.
## Outside the scene tree nothing plays (a player cannot start there).
static func play_all(main,cues:Array) -> void:
	if not is_instance_valid(main):return
	var queue:Array[String]=[]
	for cue in cues:
		if cue is String and valid_cue(cue):queue.append(cue)
	if queue.is_empty():return
	play(main,queue[0])
	if queue.size()<2 or not main is Node or not main.is_inside_tree():return
	var id:int=main.get_instance_id()
	var tree:SceneTree=main.get_tree()
	for index in range(1,queue.size()):
		var cue:String=queue[index]
		tree.create_timer(STAGGER*index).timeout.connect(func():
			var target=instance_from_id(id)
			if is_instance_valid(target):play(target,cue))
