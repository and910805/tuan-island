extends RefCounted
## 打瞌睡石像: the three windbell tones (low / mid / high), synthesized like soft_audio's
## chime cues. Depends only on the pure Guardian rules so it loads without World/Session.
##
## Loudness follows the same setting as soft_audio's chime cues: SoftAudio.cue_gain(GAIN_KIND),
## i.e. master_volume * ambience_volume. At zero nothing is created or played.

const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
## Same sample rate as SoftAudio.RATE.
const RATE:=22050
const DURATION:=0.62
const PLAYER_NAME:="SleepyGuardianBell"
## Which soft_audio cue family decides the gain (the chimes: master x ambience).
const GAIN_KIND:="ceramic_chime"

static var _streams:Dictionary={}

## Same envelope and partials as SoftAudio.note().
static func note(t:float,frequency:float,duration:float) -> float:
	if t<0.0 or t>=duration:return 0.0
	var envelope:=minf(t/0.012,1.0)*pow(1.0-t/duration,2.0)
	return envelope*(sin(TAU*frequency*t)*0.095+sin(TAU*2.0*frequency*t)*0.018)

static func valid_bell(bell:int) -> bool:
	return bell>=0 and bell<Guardian.PITCH_HZ.size()

## Short soft chime at Guardian.PITCH_HZ[bell]; mirrors the "ceramic_chime" recipe
## (fundamental plus a quieter, shorter inharmonic partial). Cached per bell.
static func make_stream(bell:int) -> AudioStream:
	if not valid_bell(bell):return null
	if _streams.has(bell):return _streams[bell]
	var hz:=float(Guardian.PITCH_HZ[bell])
	var samples:=int(RATE*DURATION)
	var bytes:=PackedByteArray()
	bytes.resize(samples*2)
	for i in range(samples):
		var t:=float(i)/RATE
		var wave:=note(t,hz,DURATION-0.03)*0.64+note(t,hz*1.616,0.24)*0.24
		bytes.encode_s16(i*2,int(wave*32767.0))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=RATE
	stream.stereo=false
	stream.data=bytes
	_streams[bell]=stream
	return stream

## Linear gain the bell would play at right now; 0 when audio is off or unavailable.
static func gain(main) -> float:
	if not is_instance_valid(main):return 0.0
	var sound=main.get("sound")
	if not is_instance_valid(sound) or not sound is Node or not sound.has_method("cue_gain"):return 0.0
	var amount:=float(sound.cue_gain(GAIN_KIND))
	return amount if is_finite(amount) and amount>0.0 else 0.0

static func play(main,bell:int) -> void:
	if not valid_bell(bell):return
	var amount:=gain(main)
	var sound=main.get("sound") if is_instance_valid(main) else null
	if not is_instance_valid(sound) or not sound is Node:return
	var voice:=sound.get_node_or_null(PLAYER_NAME) as AudioStreamPlayer
	if amount<=0.0:
		if voice!=null:voice.stop()
		return
	if voice==null:
		voice=AudioStreamPlayer.new()
		voice.name=PLAYER_NAME
		sound.add_child(voice)
	# The generic 440 Hz "action" blip that accompanies the result notice would sit on top
	# of the bell pitch the player is trying to hear; let the bell replace it.
	var shared=sound.get("player")
	if shared is AudioStreamPlayer and shared.playing and str(sound.get("cue_kind"))=="action":shared.stop()
	voice.stop()
	voice.volume_db=linear_to_db(amount)
	voice.stream=make_stream(bell)
	voice.play()
