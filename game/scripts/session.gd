extends Node

const World = preload("res://scripts/world.gd")
const SkillBook = preload("res://scripts/island_skill_book.gd")
const Membership = preload("res://scripts/world_membership.gd")
const AdmissionStore = preload("res://scripts/admission_store.gd")
const WriteGuard = preload("res://scripts/world_write_guard.gd")
const BlueprintProtocol = preload("res://scripts/blueprint_protocol.gd")
const SnapshotWire = preload("res://scripts/snapshot_wire.gd")
const CropSprites = preload("res://scripts/crop_sprite_art.gd")
const ViewProjection = preload("res://scripts/view_projection.gd")
## 45: chapter 4 Beimen cooperative salt pans (save 26): beimen region, sea_salt,
## salt machine kits, salt_grilled_fish; salt_* actions through request_action
## (gate/rake/install/uninstall/auto_cfg/order/box_take correlated; extras use the
## plain 32-character bound). Snapshots carry the shared token-free `salt_pan`
## projection plus the recipient's own view in `salt_pan.own`; `mine` flags are
## set for that recipient only. Older clients cannot render or route it.
## 44: chapter 3 Tianwei cooperative flower nursery (save 25): tianwei region,
## flower crops/seeds, blue_dye, sugar, garden_cookie; flower_* actions through
## request_action (flower_ship / flower_give correlated). Snapshots carry the
## shared `flower_nursery.garden` (no tokens) plus the recipient's own record in
## `flower_nursery.own`. Older clients cannot render or route it and are rejected.
## 43: basic world-clock weather and calendar-day crop watering (save 24 unchanged).
## Older clients cannot present the rain/daily-drying rules and are rejected.
## 42: Q05 bakery (save 24): pumpkin crop, flour mill processor (input_wheat
## buffer, wheat/flour conveyor filters), pumpkin_pie recipe; mill_kit/mill
## gated on public_kitchen.opened. Same actions/RPCs; older clients rejected.
## 41: public kitchen (save 23): correlated kitchen_register / kitchen_contribute
## through the existing request_action path (no new RPC); shared public_kitchen
## in every snapshot. 40: explicit chest + backpack material sourcing (save 22):
## prepare_material_box and sourced extras on SOURCE_ACTIONS. 39: sawmill/
## charcoal_kiln `processing` queues (save 21). 38: stove cooking queues.
## 47: chicken cuddle/release; optional owner marker is hashed in public snapshots.
## 46: sheep grooming action and optional last_care marker; older clients must update.
## 48: cow care actor marker, redacted to public ID in snapshots.
const PROTOCOL := 53
const VERSION_MISMATCH_NOTICE := "遊戲版本過舊或不相容，請更新遊戲後再加入。"
const ROOM_CAPACITY := Membership.LIMIT
const CONNECTION_CAPACITY := ROOM_CAPACITY + 4
const KITCHEN_REGISTER := "kitchen_register"
const KITCHEN_CONTRIBUTE := "kitchen_contribute"
const CHEST_HISTORY_READ := World.SAVE_SCHEMA.CHEST_HISTORY.READ_ACTION
## Actions whose result is returned to the requester with its exact sequence via
## action_completed (a festival/world notice is never an acknowledgement).
const CORRELATED_ACTIONS := ["ship", "undo_build", "cook", "queue_cook", "claim_cook", "cancel_cook", "cancel_queued_cook",
	"order_accept",
	"axe", "pick", "night_vote", "till_area", "seed_area", "harvest_area",
	"start_processing", "queue_processing", "claim_processing", "cancel_processing", "cancel_processing_job",
	"feed_processing", "unload_processing_input", "toggle_auto_processing", "collect_processing_output",
	"assemble", "pet", "feed", "egg", "chicken_hug", "chicken_release", "livestock_pet", "livestock_brush", "livestock_feed", "livestock_collect", "livestock_adopt", "collector_collect",
	"craft", "stone_craft", "prepare_material_box", KITCHEN_REGISTER, KITCHEN_CONTRIBUTE, "flower_ship", "flower_give",
	"salt_gate_give", "salt_rake", "salt_install", "salt_uninstall", "salt_auto_cfg", "salt_order", "salt_box_take", "beach_treasure", "cooking_relay", "lost_chicks", "party_cart", "lantern_stroll", World.RESIDENT_GOALS.ARU_PARK_PHOTO,
	"guardian_listen", "guardian_ring", "guardian_sit", "guardian_claim", World.GUARDIAN_TRIAL.KEY,
	"shy_wait", "shy_claim", World.SHY_SPORES.ACTION,
	"crab_survey", "crab_repair", "crab_claim", "crab_shell", World.MEADOW_ADVENTURE.ACTION, World.MILL_RESTORATION.SERVICE]+World.PORTER.ACTIONS+World.MEADOW.ACTIONS
## Existing actions that may carry a sourced extra `recipe|box_cell|box_id|digest16`.
## A plain extra (no "|") keeps the old backpack-only meaning and the old bound.
const SOURCE_ACTIONS := ["craft", "cook", "queue_cook", "start_processing", "queue_processing"]
const PREPARE_ACTION := "prepare_material_box"
const PLAIN_EXTRA_MAX := 32
const SOURCED_EXTRA_MAX := 96
const SOURCE_RECIPE_MAX := 32
const SOURCE_BOX_ID_LENGTH := 32
const SOURCE_DIGEST_LENGTH := 16
signal identity_status(info: Dictionary)
signal action_completed(sequence: int, action: String, result: Dictionary)
## T017 hand-tool action feedback. A server-confirmed success of one of these
## actions becomes a short-lived public event in the snapshots of recipients in
## the same region: {"tool_actions":{"epoch":..,"events":[{n,actor,tool,x,y[,tx,ty]}]}}.
## Session memory only (never World state or saves); no new RPC and no protocol
## change: older clients ignore the extra snapshot key. actor = public id.
const TOOL_ACTION_EVENTS := ["hoe","seed","water","harvest","axe","pick","build","remove","plant_tree","move_object"]
const TOOL_ACTION_TTL_MS := 1500
const TOOL_ACTION_MAX := 32
var tool_actions: Array = []
var tool_action_counter := 0
var tool_action_epoch := ""
## Test hook: empty = Time.get_ticks_msec(); tests may inject a Callable returning int ms.
var tool_action_clock: Callable
signal blueprint_quoted(request_id: int, result: Dictionary)
signal blueprint_applied(nonce: String, result: Dictionary)
signal changed(snapshot:Dictionary, own_id:String)
signal notice(message:String, success:bool)
signal connected_world
signal disconnected_world
var world = null
var peers:Dictionary={}
var returning_peers:Dictionary={}
var solo_rest_enabled:=false
## Render-only hint for the verified private single-player host (T091): the own
## player's pose before and after the latest physics-tick move. Never saved or sent.
var solo_motion:Dictionary={}
const NIGHT_VOTE_TTL_MS:=30000
var night_vote:Dictionary={}
var night_vote_serial:=0
var directions:Dictionary={}
var sequences:Dictionary={}
var rates:Dictionary={}
const EMOTES := {"hello":"你好！","thanks":"謝謝！","help":"來幫忙！"}
## T07: host-validated pouring emotes (see World.tea_set_nearby); not offered by the generic menu.
const TEA_SET_EMOTES:=World.INDUSTRY.TEA_SET_EMOTES
const MAP_SIGNALS := {"wood":"需要木材","meet":"來這裡","build":"這裡要蓋房"}
const MAP_SIGNAL_MS := 30000
var map_signals:Dictionary={}
var emote_sent_at:Dictionary={}
signal emote_received(actor:String,region:String,caption:String)
signal chat_received(region:String,sender:String,message:String)
const CHAT_LENGTH:=World.ISLAND_NOTES.LENGTH
var chat_sent_at:Dictionary={}
var note_sent_at:Dictionary={}
signal island_note_result(sequence:int,success:bool)
var pending:Dictionary={}
var snapshot:Dictionary={}
var _snapshot_bases:Dictionary={}
const VIEW_INTEREST_ACTION:="view_interest"
var _view_interests:Dictionary={}
var _sent_view_interest:=Vector2i.ZERO
var _sent_view_interest_epoch:=-1
# T046 (see view_projection.gd). Server: the projection level each peer opted
# in to (1: crops/forest/removed, 2: also ground/roofs/edges), and the
# {epoch,at,level} of each one's last complete layer seed. Client: opt-in flag,
# the highest level to ask for, the extra last sent, whole-island holds and the
# last known far cells.
var _view_layers:Dictionary={}
var _view_seeds:Dictionary={}
var view_refresh_ms:=ViewProjection.REFRESH_MS
## Server: choose a projection's rows before the per-recipient copy and redaction.
## false trims after them instead (the earlier order); kept as the parity reference.
var view_early_projection:=true
var view_layers_opt_in:=false
var view_layers_level:=ViewProjection.MAX_LEVEL
var _sent_view_extra:=""
var _full_view_holds:Dictionary={}
var _view_cache:=ViewProjection.new()
var _snapshot_frame:=0
var _received_snapshot_base:Dictionary={}
var _received_snapshot_frame:=0
var own_id:=""
var profile:Dictionary={}
var room_key:=""
var desired_name:="島民"
var counter:=0
var broadcast_clock:=0.0
var save_clock:=0.0
## T090 opt-in server timing (T090_PROFILE=1, default off). Stats are
## phase -> [count,total_usec,max_usec]; only counts and durations are kept.
const T090_WINDOW_MS:=5000
const T090_SLOW_TICK_USEC:=50000
const T090_LEAF_PHASES:=["step","move","public","personal","encode","send","save"]
var t090_enabled:=OS.get_environment("T090_PROFILE")=="1"
var t090_stats:Dictionary={}
var t090_tick_usec:Dictionary={}
var t090_slow_by:Dictionary={}
var t090_slow_ticks:=0
var t090_window_start:=0
var t090_in_tick:=false
var t090_movement_inputs:Dictionary={}
var t090_last_input_nonzero:Dictionary={}
var accepting:=true
var storage_paused:=false
var storage_report_state:=""
var storage_report_delay:=0.0
var storage_report_request:HTTPRequest
var local_paused:=false
var headless:=false
var session_nonce:=""
const MOVEMENT_INPUT_TIMEOUT_MS:=400
var _last_server_tick_ms:=-1
var last_movement:Dictionary={}
var controller_holds:Dictionary={}
var shutting_down:=false
var membership: Membership
var identity_url := ""
var identity_world := ""
var identity_secret := ""
var identity_tls: TLSOptions
var identity_requests := {}
var identities := {}
var identity_rejected := {}
var connection_serial := 0
var client_ticket := ""
var client_invite := ""
var authenticated_client := false
var identity_clock := 0.0
var directory_address := ""
var directory_dirty := false
var directory_request: HTTPRequest
var directory_clock := 0.0
var directory_retry := 0.0
var directory_invite := {}
var admission_store = AdmissionStore.new()
var admission_recovery_required := false
var identity_save_path := ""
var write_guard = WriteGuard.new()
## Blueprint transport. Empty clock = Time.get_ticks_msec(); tests may inject
## a Callable returning int milliseconds. Limiter stamps are per live peer.
var blueprint_clock: Callable
var blueprint_counter := 0
var blueprint_quote_stamps := {}
var blueprint_apply_stamps := {}
## Client side: set by welcome(), cleared on join/loss/shutdown, so requests are
## never sent before the server has attached this peer (it would drop them).
var blueprint_welcomed := false

func configure_directory(address: String, world_name: String, mode: String = "生活", allow_test_loopback: bool = false) -> Error:
	if shutting_down or membership == null or world != null or not write_guard.is_held() or not Membership.valid_text(world_name, 64) or mode != "生活":
		return ERR_INVALID_PARAMETER
	if address.length() > 512 or address.contains("@") or address.contains("#") or address.contains("?"):
		return ERR_INVALID_PARAMETER
	var pattern := RegEx.new()
	pattern.compile("^wss://([A-Za-z0-9.-]+|\\[[0-9A-Fa-f:]+\\])(?::([0-9]{1,5}))?(/[^\\s]*)?$")
	var match_address := pattern.search(address)
	var valid_secure := match_address != null and (match_address.get_string(2).is_empty() or int(match_address.get_string(2)) in range(1, 65536))
	if not valid_secure and not (allow_test_loopback and loopback_url(address, "ws")):
		return ERR_INVALID_PARAMETER
	if not membership.set_world_name(world_name):
		return ERR_CANT_CREATE
	directory_address = address
	return OK

static func loopback_url(url: String, scheme: String) -> bool:
	var matcher := RegEx.new()
	matcher.compile("^" + scheme + "://127[.]0[.]0[.]1:([0-9]{1,5})(/[^\\s#]*)?$")
	var found := matcher.search(url)
	return found != null and int(found.get_string(1)) in range(1, 65536)

func configure_identity(api_url: String, world_id: String, server_secret: String, membership_path: String, owner_account: String, allow_test_loopback: bool = false, tls_options: TLSOptions = null, world_path: String = "") -> Error:
	if shutting_down or world != null or membership != null or world_id.is_empty() or server_secret.is_empty() or membership_path.is_empty() or owner_account.is_empty() or world_path.is_empty():
		return ERR_INVALID_PARAMETER
	if tls_options != null and tls_options.is_unsafe_client():
		return ERR_INVALID_PARAMETER
	if not api_url.begins_with("https://") and not (allow_test_loopback and loopback_url(api_url, "http")):
		return ERR_INVALID_PARAMETER
	if api_url.contains("@") or api_url.contains("?") or api_url.contains("#"):
		return ERR_INVALID_PARAMETER
	if not world_path.is_empty():
		if not AdmissionStore.safe_pair(AdmissionStore.canonical(world_path),AdmissionStore.canonical(membership_path)):
			return ERR_INVALID_PARAMETER
	var locked: Error = write_guard.acquire([world_path,membership_path])
	if locked != OK:
		notice.emit("這份世界或成員資料正在使用中，或無法取得保存鎖。請先關閉另一個伺服器。",false)
		return locked
	# Recovery precedes roster migration/initialization and directory name writes.
	if AdmissionStore.has_pending(membership_path):
		if world_path.is_empty() or not AdmissionStore.recover(world_path, membership_path, world_id):
			return _configuration_failed(ERR_FILE_CORRUPT)
	if not world_path.is_empty() and not FileAccess.file_exists(membership_path) and (
		FileAccess.file_exists(world_path) or FileAccess.file_exists(world_path+".bak")):
		# Existing worlds require their original account mapping; never silently
		# create replacement owners when a membership file has been lost.
		return _configuration_failed(ERR_FILE_CORRUPT)
	var roster := Membership.new()
	if FileAccess.file_exists(membership_path):
		if not roster.open(membership_path):
			return _configuration_failed(ERR_FILE_CORRUPT)
		if not roster.is_owner(owner_account):
			return _configuration_failed(ERR_UNAUTHORIZED)
	elif not roster.initialize(membership_path, world_id, owner_account, "島主"):
		return _configuration_failed(ERR_CANT_CREATE)
	membership = roster
	identity_url = api_url.trim_suffix("/")
	identity_world = world_id
	identity_secret = server_secret
	identity_tls = tls_options
	identity_save_path = AdmissionStore.canonical(world_path) if not world_path.is_empty() else ""
	return OK

func _configuration_failed(error: Error) -> Error:
	write_guard.release()
	return error

func join_authenticated(address: String, port: int, ticket: String, invite: String, allow_test_loopback: bool = false, tls_options: TLSOptions = null) -> Error:
	if ticket.is_empty() or address.contains("@") or (tls_options != null and tls_options.is_unsafe_client()):
		return ERR_INVALID_PARAMETER
	if not address.begins_with("wss://") and not (allow_test_loopback and loopback_url(address, "ws")):
		return ERR_INVALID_PARAMETER
	var err := join(address, port, "", "", tls_options)
	if err == OK:
		authenticated_client = true
		client_ticket = ticket
		client_invite = invite
	return err


func _ready() -> void:
	name="Session"
	session_nonce=Crypto.new().generate_random_bytes(16).hex_encode()
	tool_action_epoch=Crypto.new().generate_random_bytes(6).hex_encode()
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_failed)
	multiplayer.server_disconnected.connect(_lost)
	var profile_path:="user://profile.json"
	if FileAccess.file_exists(profile_path):
		var data=JSON.parse_string(FileAccess.get_file_as_string(profile_path))
		if data is Dictionary:profile=data
	if not profile.has("token"):
		profile={"token":Crypto.new().generate_random_bytes(24).hex_encode()}
		var f:=FileAccess.open(profile_path,FileAccess.WRITE)
		if f:f.store_string(JSON.stringify(profile))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):profile.token=arg.trim_prefix("--profile=")

func host(port:int, nickname:String, save_file:String, key_value:String="", bind_ip:String="127.0.0.1", dedicated:bool=false, transport:String="enet", solo:bool=false, world_mode:String="") -> Error:
	if shutting_down or world != null or save_file.is_empty():return ERR_INVALID_PARAMETER
	if world_mode not in ["","life","adventure"]:return ERR_INVALID_PARAMETER
	if transport not in ["enet","websocket"]:return ERR_INVALID_PARAMETER
	if membership != null and (not dedicated or transport != "websocket"):return ERR_INVALID_PARAMETER
	if membership != null and ProjectSettings.globalize_path(membership.path).simplify_path() == ProjectSettings.globalize_path(save_file).simplify_path():return ERR_INVALID_PARAMETER
	if membership != null and save_file.is_empty():return ERR_INVALID_PARAMETER
	if not identity_save_path.is_empty() and AdmissionStore.canonical(save_file)!=identity_save_path:return ERR_INVALID_PARAMETER
	if membership != null and AdmissionStore.has_pending(membership.path):
		# A journal created since configuration must not be ignored by this host.
		return ERR_BUSY
	if membership == null and transport=="websocket" and bind_ip not in ["127.0.0.1","::1","localhost"] and key_value.length()<12:
		notice.emit("對外 WebSocket 測試房間需設定至少 12 字元的房間密碼。",false)
		return ERR_INVALID_PARAMETER
	var guarded_paths: Array[String] = [save_file]
	if membership != null:guarded_paths.append(membership.path)
	var locked: Error = write_guard.acquire(guarded_paths)
	if locked != OK:
		notice.emit("這座小島已在另一個視窗開啟，或無法取得保存鎖。沒有載入或改寫存檔。",false)
		return locked
	multiplayer.server_relay=false
	world=World.new()
	if not world.load_world(save_file):
		notice.emit("存檔無法讀取，已保留原檔，沒有建立新檔覆蓋。",false)
		world=null
		if membership == null:write_guard.release()
		return ERR_FILE_CORRUPT
	var new_save:bool=not world.recovered_from_backup and not FileAccess.file_exists(save_file)
	if new_save and world_mode=="adventure":world.state.world_mode="adventure"
	if not new_save and not world_mode.is_empty() and world.state.get("world_mode","life")!=world_mode:
		notice.emit("這份存檔的玩法模式與選擇不同。",false)
		world=null
		if membership==null:write_guard.release()
		return ERR_INVALID_PARAMETER
	var recovered:bool=world.recovered_from_backup
	if membership!=null:world.public_build_access=membership.can_build_public
	var peer:MultiplayerPeer
	var err:Error
	if transport=="websocket":
		var socket:=WebSocketMultiplayerPeer.new()
		socket.inbound_buffer_size=4194304
		socket.outbound_buffer_size=4194304
		socket.max_queued_packets=128
		err=socket.create_server(port,bind_ip)
		peer=socket
	else:
		var enet:=ENetMultiplayerPeer.new()
		enet.set_bind_ip(bind_ip)
		err=enet.create_server(port,CONNECTION_CAPACITY)
		peer=enet
	if err!=OK:
		world=null
		if membership == null:write_guard.release()
		notice.emit("無法開啟房間，連接埠可能已被其他房間使用。",false)
		return err
	multiplayer.multiplayer_peer=peer
	room_key=key_value
	headless=dedicated
	_last_server_tick_ms=-1
	solo_rest_enabled=solo and not dedicated and bind_ip=="127.0.0.1"
	if not dedicated:_register(1,profile.token,nickname)
	print("SERVER_READY port=%d bind=%s transport=%s"%[port,bind_ip,transport])
	if recovered:notice.emit("主存檔無法讀取，已使用上一份備份恢復；原檔會另行保留。",true)
	mark_directory_dirty()
	return OK

func join(address:String,port:int,nickname:String,key_value:String,tls_options:TLSOptions=null) -> Error:
	_received_snapshot_base.clear()
	_received_snapshot_frame=0
	_sent_view_interest=Vector2i.ZERO
	_sent_view_interest_epoch=-1
	_sent_view_extra=""
	_view_cache.reset()
	blueprint_welcomed = false
	authenticated_client = false
	client_ticket = ""
	client_invite = ""
	desired_name=nickname.left(12)
	room_key=key_value
	var peer:MultiplayerPeer
	var err:Error
	if address.begins_with("ws://") or address.begins_with("wss://"):
		var socket:=WebSocketMultiplayerPeer.new()
		socket.inbound_buffer_size=4194304
		socket.outbound_buffer_size=4194304
		socket.max_queued_packets=128
		err=socket.create_client(SnapshotWire.offer_cells(address),tls_options)
		peer=socket
	else:
		var enet:=ENetMultiplayerPeer.new()
		err=enet.create_client(address,port)
		peer=enet
	if err!=OK:return err
	multiplayer.multiplayer_peer=peer
	return OK

func _peer_connected(id:int) -> void:
	if multiplayer.is_server():
		if admission_recovery_required:multiplayer.multiplayer_peer.disconnect_peer(id);return
		if pending.size()+peers.size()>=CONNECTION_CAPACITY:multiplayer.multiplayer_peer.disconnect_peer(id);return
		pending[id]=Time.get_ticks_msec()

func _connected() -> void:
	if authenticated_client:
		if client_ticket.is_empty():return
		register_authenticated.rpc_id(1, PROTOCOL, client_ticket, client_invite)
		client_ticket = ""
		client_invite = ""
	else:
		register_player.rpc_id(1,PROTOCOL,profile.token,desired_name,room_key)

func _failed() -> void:
	blueprint_welcomed = false
	notice.emit("連不上這個房間。請確認位址、連接埠與房間是否開啟。",false)
	disconnected_world.emit()

func _lost() -> void:
	blueprint_welcomed = false
	if shutting_down:return
	notice.emit("與世界失去連線，已停止操作。重新加入可取回已保存的進度。",false)
	disconnected_world.emit()

func _registration_available(id:int,token:String) -> bool:
	for other in peers:
		if peers[other]==token:
			_send_notice(id,"同一位島民已經在線，請先離開另一個視窗。",false)
			return false
	if peers.size()>=ROOM_CAPACITY:
		_send_notice(id,"這個世界已經有 %d 位島民了。"%ROOM_CAPACITY,false)
		return false
	return not admission_recovery_required

func _register(id:int,token:String,nickname:String) -> bool:
	if not _registration_available(id,token):return false
	var returning:bool=world.state.players.has(token)
	var before:Dictionary=world.state.duplicate(true)
	world.add_player(token,nickname if not nickname.strip_edges().is_empty() else "島民",World.WANGAN_COAST.FERRY_LANDING)
	if not world.save():
		world.state=before
		world.active_tokens.erase(token)
		_send_notice(id,"無法保存角色，請稍後再試。",false)
		return false
	_attach_registered(id,token,returning)
	return true

func _attach_registered(id:int,token:String,returning:bool=false) -> void:
	peers[id]=token
	returning_peers[id]=returning
	directions[id]=Vector2.ZERO
	last_movement[id]=Time.get_ticks_msec()
	sequences[id]=0
	rates[id]=[]
	_blueprint_attach(id)
	pending.erase(id)
	if night_vote.is_empty():_send_snapshot(id)
	else:_end_night_vote("有島民加入，已取消這次休息投票。")
	if id==1:connected_world.emit()
	else:welcome.rpc_id(id)

func commit_identity_admission(id:int,claim:Dictionary,invite:String) -> Dictionary:
	if admission_recovery_required or not accepting or world == null or membership == null:
		return {"ok":false,"code":"RECOVERING","message":"小島正在保護存檔，請待伺服器恢復後再加入。"}
	var plan := membership.plan_admission(claim.account_id,claim.display_name,invite)
	if not plan.ok:
		if plan.code=="WORLD_BLOCKED":
			return {"ok":false,"code":plan.code,"message":"你的帳號目前被這座島封鎖。"}
		return {"ok":false,"code":plan.code,"message":"這座島的成員席位已滿。" if plan.code=="WORLD_FULL" else "邀請已失效，請向島主索取新的邀請。"}
	if not _registration_available(id,plan.character):
		return {"ok":false,"code":"ALREADY_ONLINE","message":"此島民已在線，或目前連線名額已滿。"}
	var draft := World.new()
	draft.state = world.state.duplicate(true)
	var returning:bool=draft.state.players.has(plan.character)
	draft.add_player(plan.character,claim.display_name.left(12),World.WANGAN_COAST.FERRY_LANDING)
	if not admission_store.commit(world.save_path,membership.path,identity_world,draft.state,plan.state):
		if AdmissionStore.has_pending(membership.path):
			freeze_admission_writes()
			return {"ok":false,"code":"RECOVERING","message":"入島資料等待恢復，島嶼已暫停寫入。請待伺服器重啟後再加入。"}
		return {"ok":false,"code":"SAVE_FAILED","message":"小島暫時無法保存，尚未新增席位。請稍後再試。"}
	membership.adopt_committed(plan.state)
	world.state = draft.state
	world.active_tokens[plan.character] = true
	world.recovered_from_backup = false
	world.last_saved_at=Membership.now()
	return {"ok":true,"character":plan.character,"returning":returning}

func freeze_admission_writes() -> void:
	admission_recovery_required = true
	accepting = false
	directory_dirty = false
	directory_invite.clear()
	if is_instance_valid(directory_request):
		directory_request.queue_free()
		directory_request = null
	for id in directions:directions[id]=Vector2.ZERO
	for id in peers:_send_notice(id,"入島資料等待恢復，世界已暫停寫入。請待伺服器重啟後再加入。",false)

@rpc("any_peer","call_remote","reliable")
func register_player(version:int,token:String,nickname:String,key_value:String) -> void:
	if not multiplayer.is_server() or world==null:return
	var id:=multiplayer.get_remote_sender_id()
	if peers.has(id):return
	if membership != null:
		_send_notice(id,"此世界需要已驗證帳號。",false)
		return
	if version!=PROTOCOL:
		_send_notice(id,VERSION_MISMATCH_NOTICE,false)
		return
	if token.length()<12 or token.length()>64 or key_value!=room_key:
		_send_notice(id,"房間密碼不正確，無法加入。",false)
		return
	_register(id,token,nickname.left(12))

@rpc("authority","call_remote","reliable")
func welcome() -> void:
	blueprint_welcomed = true
	connected_world.emit()

func _peer_left(id:int) -> void:
	_snapshot_bases.erase(id)
	_view_interests.erase(id)
	_view_layers.erase(id)
	_view_seeds.erase(id)
	returning_peers.erase(id)
	map_signals.erase(id)
	emote_sent_at.erase(id)
	chat_sent_at.erase(id)
	note_sent_at.erase(id)
	_blueprint_forget(id)
	var previous: Dictionary = identities.get(id, {})
	identity_requests.erase(id)
	identities.erase(id)
	identity_rejected.erase(id)
	if world!=null:
		if peers.has(id):
			world.cancel_trades(peers[id])
			world.active_tokens.erase(peers[id])
			world.guardian_trial_forget(peers[id])
			world.shy_forget(peers[id]) # 害羞菇的安靜等待只在連線期間有效；重連後重新計時。
			world.crab_forget(peers[id]) # 石殼蟹冒險路線的等待同樣只在連線期間有效。
			world.release_story_seats(peers[id]) # 暖暖座位等故事姿勢只屬於本人，離線即釋放。
			World.LOST_CHICKS.return_bucket(world.state,peers[id])
			World.PARTY_CART.return_member(world.state,peers[id])
			World.LANTERN_STROLL.return_lantern(world.state,peers[id])
			if str(world.state.animal.get(World.CHICKEN_CUDDLE.FIELD,""))==peers[id]:World.CHICKEN_CUDDLE.clear(world.state.animal)
			if str(world.state.animal.get(World.CHICKEN_FEED_FOLLOW.FIELD,""))==peers[id]:world.state.animal.erase(World.CHICKEN_FEED_FOLLOW.FIELD)
			if str(world.state.livestock.get("cow",{}).get(World.COW_CARE.FIELD,""))==peers[id]:World.COW_CARE.clear(world.state)
			world.harvest_disconnect(peers[id]) # T071：放下模型蔬菜並退出這一輪（下面一起存檔）
			world.fish_meet_disconnect(peers[id]) # T071：退出河岸釣魚會這一輪（貢獻保留，下面一起存檔）
			world.showcase_disconnect(peers[id]) # T071：退出家園布置題這一輪（道具留在地塊上，下面一起存檔）
			_forget_tool_actions(_public_actor(peers[id]))
		peers.erase(id)
		if not night_vote.is_empty():_end_night_vote("有島民離開，已取消這次休息投票。")
		directions.erase(id)
		last_movement.erase(id)
		t090_last_input_nonzero.erase(id)
		controller_holds.erase(id)
		sequences.erase(id)
		rates.erase(id)
		pending.erase(id)
		if not admission_recovery_required and not world.save():
			accepting=false
			storage_paused=true
	if not admission_recovery_required and not previous.is_empty():
		membership.touch(previous.account_id)
		mark_directory_dirty()

func _t090_begin() -> int:
	return Time.get_ticks_usec() if t090_in_tick else -1

func _t090_end(phase:String,started:int) -> void:
	if started<0:return
	var spent:=Time.get_ticks_usec()-started
	var row:Array=t090_stats.get(phase,[0,0,0])
	row[0]+=1
	row[1]+=spent
	row[2]=maxi(int(row[2]),spent)
	t090_stats[phase]=row
	t090_tick_usec[phase]=int(t090_tick_usec.get(phase,0))+spent

func _t090_text(phase:String) -> String:
	var row:Array=t090_stats.get(phase,[0,0,0])
	return "%s=%d/%.2f/%.2f"%[phase,row[0],float(row[1])/1000.0,float(row[2])/1000.0]

func _t090_movement_input(id:int,direction:Vector2,now:int) -> void:
	if not t090_enabled:return
	var counts:Array=t090_movement_inputs.get(id,[0,0,0])
	var nonzero:=direction!=Vector2.ZERO
	if nonzero:counts[0]+=1
	var previous:int=last_movement.get(id,now)
	if previous>0 and t090_last_input_nonzero.get(id,false):
		counts[1]=maxi(int(counts[1]),now-previous)
	t090_last_input_nonzero[id]=nonzero
	t090_movement_inputs[id]=counts

func _t090_finish_tick(spent:int) -> void:
	var row:Array=t090_stats.get("tick",[0,0,0])
	row[0]+=1
	row[1]+=spent
	row[2]=maxi(int(row[2]),spent)
	t090_stats["tick"]=row
	if spent>=T090_SLOW_TICK_USEC:
		# Attribute a slow tick to its largest leaf phase; "other" is the unmeasured rest.
		var worst:="other"
		var worst_usec:=0
		var measured:=0
		for phase:String in T090_LEAF_PHASES:
			var usec:=int(t090_tick_usec.get(phase,0))
			measured+=usec
			if usec>worst_usec:
				worst=phase
				worst_usec=usec
		if spent-measured>worst_usec:worst="other"
		t090_slow_ticks+=1
		t090_slow_by[worst]=int(t090_slow_by.get(worst,0))+1
	var now:=Time.get_ticks_msec()
	if t090_window_start==0:t090_window_start=now
	if now-t090_window_start<T090_WINDOW_MS:return
	var tick_total:=maxi(1,int(row[1]))
	var shares:=PackedStringArray()
	var measured_total:=0
	for phase:String in T090_LEAF_PHASES:
		var total:int=int(t090_stats.get(phase,[0,0,0])[1])
		measured_total+=total
		shares.append("%s:%d%%"%[phase,roundi(100.0*float(total)/float(tick_total))])
	shares.append("other:%d%%"%maxi(0,roundi(100.0*float(tick_total-measured_total)/float(tick_total))))
	var slow:=PackedStringArray()
	for phase:String in t090_slow_by:slow.append("%s:%d"%[phase,t090_slow_by[phase]])
	# Fields are count/total_ms/max_ms. Broadcast includes all snapshot phases.
	var fields:=PackedStringArray()
	for phase:String in ["tick","bcast"]+T090_LEAF_PHASES:fields.append(_t090_text(phase))
	print("SERVER_T090 window_ms=%d peers=%d %s slow50=%d slow_by=%s share=%s"%[now-t090_window_start,peers.size()," ".join(fields),t090_slow_ticks,",".join(slow) if not slow.is_empty() else "-",",".join(shares)])
	if not t090_movement_inputs.is_empty():
		print("SERVER_T090_INPUT unix=%.3f nonzero_gap_expired=%s"%[Time.get_unix_time_from_system(),JSON.stringify(t090_movement_inputs)])
		t090_movement_inputs.clear()
	t090_stats.clear()
	t090_slow_by.clear()
	t090_slow_ticks=0
	t090_window_start=now

func _physics_process(dt:float) -> void:
	if not t090_enabled:
		_server_tick(dt)
		return
	if world==null or not multiplayer.is_server():return
	t090_tick_usec.clear()
	var started:=Time.get_ticks_usec()
	t090_in_tick=true
	_server_tick(dt)
	t090_in_tick=false
	_t090_finish_tick(Time.get_ticks_usec()-started)

func _solo_pose() -> Dictionary:
	if not solo_rest_enabled or world==null or peers.size()!=1 or not peers.has(1) or not world.state.players.has(peers[1]):return {}
	var p:Dictionary=world.state.players[peers[1]]
	return {"region":str(world.player_region(peers[1])),"epoch":int(p.get("travel_epoch",0)),"pos":Vector2(p.x,p.y)}

func _solo_motion_record(before:Dictionary) -> void:
	var after:=_solo_pose()
	if before.is_empty() or after.is_empty():
		solo_motion={}
		return
	var from:Vector2=before.pos
	var to:Vector2=after.pos
	# A region or epoch change, or a jump no walking step explains, is a teleport: no sweep.
	if before.region!=after.region or before.epoch!=after.epoch or from.distance_to(to)>0.5:from=to
	solo_motion={"id":own_id,"region":after.region,"epoch":after.epoch,"from":from,"to":to,"frame":Engine.get_physics_frames()}

func _server_tick(dt:float) -> void:
	if world==null or not multiplayer.is_server():return
	if headless:
		var tick_ms:=Time.get_ticks_msec()
		var recovering:=_last_server_tick_ms>=0 and tick_ms-_last_server_tick_ms>MOVEMENT_INPUT_TIMEOUT_MS
		_last_server_tick_ms=tick_ms
		# The default peer poll runs after physics. After a long frame, read
		# queued input before applying the ordinary movement expiry rule.
		if recovering:
			multiplayer.poll()
			if world==null or not multiplayer.is_server():return
	_tick_storage_report(dt)
	if admission_recovery_required:return
	if not night_vote.is_empty() and (Time.get_ticks_msec()>=int(night_vote.until) or fposmod(float(world.state.time),World.WEATHER.DAY_SECONDS)>=World.REST_DAWN):
		_end_night_vote("休息投票已結束，島上的時間照常前進。")
	if accepting and not (local_paused and peers.size()==1 and peers.has(1)):
		var step_started:=_t090_begin()
		var stepped:bool=world.step(dt,peers.size()>0)
		_t090_end("step",step_started)
		if not stepped:
			accepting=false
			storage_paused=world.step_error==World.STEP_FAIL_SAVE
			# step_error tells a rolled-back salt tick (data fault, nothing saved) from a
			# storage failure; both pause the world without writing a half-finished tick.
			var notice:="北門鹽田的資料出現異常，世界已暫停以保護進度，請管理員檢查世界資料後重新開啟。" if world.step_error==World.STEP_FAIL_SALT else "設備保存失敗，世界已暫停操作，請檢查儲存空間後重新進入。"
			for id in peers:_send_notice(id,notice,false)
			return
		for pickup in world.gather_pickup_events:
			_record_tool_action(pickup.token,"gather_pickup",pickup.tile,"",pickup.items.keys())
			var parts:=PackedStringArray()
			for item:String in pickup.items:parts.append("%s +%d"%[World.NAMES[item],pickup.items[item]])
			for id in peers:
				if peers[id]==pickup.token:_send_notice(id,"撿到 "+"、".join(parts),true)
		var move_started:=_t090_begin()
		var solo_before:=_solo_pose()
		for id in peers:
			if controller_holds.has(id) or not identity_allows_play(id):
				directions[id] = Vector2.ZERO
				continue
			if Time.get_ticks_msec()-int(last_movement.get(id,0))>MOVEMENT_INPUT_TIMEOUT_MS:
				if t090_enabled and directions.get(id,Vector2.ZERO)!=Vector2.ZERO:
					var counts:Array=t090_movement_inputs.get(id,[0,0,0])
					counts[2]+=1
					t090_movement_inputs[id]=counts
				directions[id]=Vector2.ZERO
			world.move_player(peers[id],directions.get(id,Vector2.ZERO),dt)
		_solo_motion_record(solo_before)
		_t090_end("move",move_started)
	elif accepting:
		# Hold the latest authoritative position during pause. Falling back to the
		# previous snapshot here can briefly pull the character and camera backward.
		_solo_motion_record(_solo_pose())
	else:
		solo_motion={}
	broadcast_clock+=dt
	save_clock+=dt
	# At 60 physics ticks, six binary floating-point steps can total a hair
	# under 0.1. Waiting for tick seven leaves a visible gap at the client.
	if broadcast_clock>=0.1-0.000001:
		broadcast_clock=fposmod(maxf(0.0,broadcast_clock-0.1),0.1)
		var broadcast_started:=_t090_begin()
		_begin_broadcast_share()
		for id in peers:_send_snapshot(id)
		_end_broadcast_share()
		_t090_end("bcast",broadcast_started)
	if save_clock>=10.0:
		save_clock=0
		var save_started:=_t090_begin()
		var saved:bool=world.save()
		_t090_end("save",save_started)
		if not saved:
			accepting=false
			storage_paused=true
			for id in peers:_send_notice(id,"世界保存遇到問題，暫停操作以保護進度。",false)
	var now:=Time.get_ticks_msec()
	for id in pending.keys():
		if now-int(pending[id])>10000:
			pending.erase(id)
			identity_requests.erase(id)
			identity_rejected.erase(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)

	if membership != null:
		tick_directory(dt)
		identity_clock += dt
		var periodic := identity_clock >= 10.0
		if periodic:
			identity_clock = 0.0
		for id in identities.keys():
			if (periodic or not identity_allows_play(id)) and not identity_requests.has(id):
				identity_request(id, "validate", {"admission_id": identities[id].admission_id})

func identity_allows_play(id: int) -> bool:
	return not admission_recovery_required and (membership == null or (identities.has(id) and valid_identity_expiry(identities[id].expires)))

func input_direction(d:Vector2) -> void:
	if shutting_down:return
	if world!=null and peers.has(1):
		directions[1]=Vector2.ZERO if controller_holds.has(1) or night_vote.get("yes",{}).has(1) else d.limit_length()
		last_movement[1]=Time.get_ticks_msec()
	elif multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
		movement.rpc_id(1,d.limit_length(),str(snapshot.get("region_id","home")),int(snapshot.get("players",{}).get(own_id,{}).get("travel_epoch",0)))

@rpc("any_peer","call_remote","unreliable_ordered",1)
func movement(d:Vector2,region:String,epoch:int) -> void:
	var id:=multiplayer.get_remote_sender_id()
	if world!=null and peers.has(id) and not controller_holds.has(id) and not night_vote.get("yes",{}).has(id) and context_matches(id,region,epoch) and identity_allows_play(id) and is_finite(d.x) and is_finite(d.y):
		var now:=Time.get_ticks_msec()
		_t090_movement_input(id,d,now)
		directions[id]=d.limit_length()
		last_movement[id]=now

func perform(action:String,p:Vector2i,extra:String="") -> int:
	if shutting_down:return 0
	counter+=1
	if world!=null:_action(1,counter,action,p,extra)
	elif multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
		request_action.rpc_id(1,counter,action,p,extra,str(snapshot.get("region_id","home")),int(snapshot.get("players",{}).get(own_id,{}).get("travel_epoch",0)))
	elif action==World.RESIDENT_GOALS.ARU_PARK_PHOTO:
		# Lost link: nothing was sent, so release a pending photo confirmation as refused.
		receive_action_completed.call_deferred(counter,action,{"ok":false})
	return counter

## `project_layers` (or `view_layers_opt_in`) asks the server for the T046 home
## layer projection. Without it the request is exactly the legacy one. Passing
## World.SIZE, or holding a full view, asks for the whole island. The level asked
## for is `view_layers_level`, lowered to what the server advertises.
func update_view_interest(half:Vector2i,project_layers:=false) -> void:
	if not snapshot.get("view_interest",false) or snapshot.get("region_id")!=World.REGIONS.HOME:
		_sent_view_interest=Vector2i.ZERO
		_sent_view_extra=""
		return
	if shutting_down or world!=null or multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
	half=World.SIZE if not _full_view_holds.is_empty() else half.clamp(Vector2i.ONE,World.SIZE)
	var extra:=""
	if project_layers or view_layers_opt_in:
		extra=ViewProjection.opt_in(mini(view_layers_level,ViewProjection.offered_level(snapshot.get(ViewProjection.ADVERT))))
	var player:Dictionary=snapshot.get("players",{}).get(own_id,{})
	var epoch:=int(player.get("travel_epoch",0))
	if half==_sent_view_interest and epoch==_sent_view_interest_epoch and extra==_sent_view_extra:return
	_sent_view_interest=half
	_sent_view_interest_epoch=epoch
	_sent_view_extra=extra
	request_action.rpc_id(1,0,VIEW_INTEREST_ACTION,half,extra,World.REGIONS.HOME,epoch)

## While any reason is held, the next update_view_interest asks for the whole island.
func hold_full_view(reason:String) -> void:
	_full_view_holds[reason]=true

func release_full_view(reason:String) -> void:
	_full_view_holds.erase(reason)

## Sets or clears one hold; for callers that re-evaluate a condition every frame.
func set_full_view(reason:String,held:bool) -> void:
	if held:_full_view_holds[reason]=true
	else:_full_view_holds.erase(reason)

## False while the shown snapshot is a projection whose far cells may be stale.
func view_complete() -> bool:
	return ViewProjection.complete(snapshot)

## False only while ground, roofs and edges are a phase 2 projection.
func structure_view_complete() -> bool:
	return ViewProjection.structure_complete(snapshot)

@rpc("any_peer","call_remote","reliable",2)
func request_action(sequence:int,action:String,p:Vector2i,extra:String,region:String,epoch:int) -> void:
	var id:=multiplayer.get_remote_sender_id()
	if action==VIEW_INTEREST_ACTION:
		if region==World.REGIONS.HOME and context_matches(id,region,epoch) and identity_allows_play(id):
			_view_interests[id]=p.clamp(Vector2i.ONE,World.SIZE)
			_view_layers[id]=ViewProjection.level_of(extra)
		return
	# Controller recovery affects only the sending peer and may arrive across a region transition.
	if world!=null and (action in ["controller_hold","controller_resume"] or context_matches(id,region,epoch)):
		_action(id,sequence,action,p,extra)
	elif action in ["night_vote",World.RESIDENT_GOALS.ARU_PARK_PHOTO] and peers.has(id):
		_complete_shipping(id,sequence,action,{"ok":false})

func context_matches(id:int,region:String,epoch:int) -> bool:
	if world==null or not peers.has(id):return false
	var token:String=peers[id]
	return world.player_region(token)==region and int(world.state.players[token].get("travel_epoch",0))==epoch

func _action(id:int,sequence:int,action:String,p:Vector2i,extra:String) -> void:
	if not peers.has(id):return
	if not accepting or not identity_allows_play(id):
		if action=="night_vote" or action==World.RESIDENT_GOALS.ARU_PARK_PHOTO:_complete_shipping(id,sequence,action,{"ok":false})
		return
	if sequence<=int(sequences[id]) or sequence>int(sequences[id])+1000:return
	# This existing buffer action has 25 characters; retain the general bound
	# while allowing its exact registered name through both host and peer paths.
	if abs(p.x)>1000 or abs(p.y)>1000 or (action.length()>24 and action!="collect_processing_output"):return
	if not extra_allowed(action,extra):return
	sequences[id]=sequence
	if action=="controller_hold" or action=="controller_resume":
		if action=="controller_hold":controller_holds[id]=true
		else:controller_holds.erase(id)
		directions[id]=Vector2.ZERO
		last_movement[id]=0
		if action=="controller_hold" and not night_vote.is_empty():_end_night_vote("有島民的手把已斷線，已取消休息投票。")
		return
	if controller_holds.has(id):
		if action=="night_vote" or action==World.RESIDENT_GOALS.ARU_PARK_PHOTO:_complete_shipping(id,sequence,action,{"ok":false})
		return
	var now:=Time.get_ticks_msec()
	var recent:Array=rates[id]
	while not recent.is_empty() and now-int(recent[0])>1000:recent.pop_front()
	if recent.size()>=12:
		var result := {"ok": false, "message": "操作太快了，稍等一下再試。"}
		_send_notice(id,result.message,false)
		_complete_shipping(id,sequence,action,result)
		if action=="news_note":_reply_island_note(id,sequence,false)
		if action==CHEST_HISTORY_READ:_complete_shipping(id,sequence,action,result)
		return
	recent.append(now)
	if membership!=null:
		if action in ["dock_project_start","festival_story_open"] and not _can_start_large_projects(id):
			_send_notice(id,"請由島主或管理員啟動這項工程。",false)
			return
		if action=="dock_repair" and int(world.state.get("dock_stage",0))==0 and not world.state.get("dock_project_started",false):
			_send_notice(id,"等島主或管理員宣布開工後，就能交付材料。",false)
			return
	if action=="night_rest":
		_attempt_night_rest(id)
		return
	if action=="night_vote":
		var accepted:=_change_night_vote(id,extra,now)
		_complete_shipping(id,sequence,action,{"ok":accepted})
		return
	if action not in [World.WALL_FIXTURES.WATER_CHIME_RING,World.INDUSTRY.PAVILION_INSPECT,CHEST_HISTORY_READ] and not night_vote.is_empty() and night_vote.yes.has(id):
		_end_night_vote("有島民繼續活動，已取消這次休息投票。")
	if action=="map_signal":
		_change_map_signal(id,p,extra,now)
		return
	if action=="emote":
		var tea_emote:bool=TEA_SET_EMOTES.has(extra)
		if not (EMOTES.has(extra) or tea_emote) or now-int(emote_sent_at.get(id,-3000))<2000:return
		# Pouring emotes only work beside a placed tea set (any owner). Checked before the
		# shared cooldown is spent, so a refused attempt never blocks the generic emotes.
		if tea_emote and not world.tea_set_nearby(peers[id]):
			_send_notice(id,"請靠近擺著小陶茶具的桌子。",false)
			return
		emote_sent_at[id]=now
		var region:String=world.player_region(peers[id])
		var actor:=_public_actor(peers[id])
		for recipient:int in peers:
			if world.player_region(peers[recipient])!=region or not identity_allows_play(recipient):continue
			if recipient==1:receive_emote(actor,region,extra)
			elif _can_send(recipient):receive_emote.rpc_id(recipient,actor,region,extra)
		return
	if action=="island_chat":
		var message:=chat_text(extra)
		if message.is_empty() or now-int(chat_sent_at.get(id,-3000))<1500:return
		chat_sent_at[id]=now
		var region:String=world.player_region(peers[id])
		var sender:String=world.state.players[peers[id]].name
		for recipient:int in peers:
			if world.player_region(peers[recipient])!=region or not identity_allows_play(recipient):continue
			if recipient==1:receive_island_chat(region,sender,message)
			elif _can_send(recipient):receive_island_chat.rpc_id(recipient,region,sender,message)
		return
	# Sequence is monotonically increasing per live session; persisted request IDs
	# include a fresh session nonce so restarting cannot collide with an old action.
	var request_id:="%s-%d-%d"%[session_nonce,id,sequence]
	if action=="news_note" and now-int(note_sent_at.get(id,-10000))<5000:
		_send_notice(id,"請稍等一下再留言。",false)
		_reply_island_note(id,sequence,false)
		return
	if action=="trade_open":
		var target: String = ""
		for candidate: String in peers.values():
			if _public_actor(candidate)==extra:
				target=candidate
				break
		extra=target
	# A stored receipt means World only replays an earlier answer; never animate it twice.
	var actor:String=peers[id]
	var person_before:Dictionary=world.state.players.get(actor,{})
	var replayed:bool=(action in TOOL_ACTION_EVENTS or action=="fish_catch") and person_before.get("receipts",{}).has(request_id)
	var cast_ready:=float(person_before.get("fishing",{}).get("ready",-1.0)) if action=="fish_catch" else -1.0
	var earlier_levels:=SkillBook.core_levels(world.state.players.get(actor,{}))
	var earlier_assists:Dictionary={}
	if action in ["axe","pick"] and not replayed:
		for member:String in world.gather_assist_candidates(actor,p):
			var helper:Dictionary=world.state.players[member]
			earlier_assists[member]={"count":int(helper.get("gathering_assists",0)),"levels":SkillBook.core_levels(helper)}
	var result:Dictionary=world.act(actor,request_id,action,p,extra)
	if action==CHEST_HISTORY_READ:
		_complete_shipping(id,sequence,action,result)
		return
	if result.ok and action in ["livestock_pet","livestock_brush","livestock_feed"]:
		result=result.duplicate()
		result["animal"]=extra
	if result.ok and not replayed and action in TOOL_ACTION_EVENTS:_record_tool_action(peers[id],action,p,extra)
	if result.ok and not replayed and cast_ready>=0.0:
		var fish:=str(result.get("fish_meet",result.get("fish_species","")))
		if World.FISH.has(fish):
			_record_tool_action(actor,"fish_reel",p,"",[],{"fish":fish,"ready":cast_ready,"released":result.has("fish_meet")})
	if result.ok and action=="news_note":note_sent_at[id]=now
	if result.ok and (action in ["travel","transit","mine_travel"] or result.get("mine_exhausted",false)):
		directions[id]=Vector2.ZERO
		last_movement[id]=0
	var action_success:bool=result.ok and not result.get("trade_refused",false)
	var message:String=result.message
	if action_success:
		var advancement:=SkillBook.advancement(earlier_levels,world.state.players.get(actor,{}))
		if not advancement.is_empty():message+="\n"+advancement
	_send_notice(id,message,action_success)
	if action_success and not earlier_assists.is_empty():
		for peer_id:int in peers:
			var member:String=peers[peer_id]
			if not earlier_assists.has(member):continue
			var previous:Dictionary=earlier_assists[member]
			var helper:Dictionary=world.state.players[member]
			if int(helper.get("gathering_assists",0))<=int(previous.count):continue
			var advancement:=SkillBook.advancement(previous.levels,helper)
			var cooperation:="記下了一次合作採集。"
			if not advancement.is_empty():cooperation+="\n"+advancement
			_send_notice(peer_id,cooperation,true)
	if action in [World.WALL_FIXTURES.WATER_CHIME_RING,World.INDUSTRY.PAVILION_INSPECT]:
		_complete_shipping(id,sequence,action,result)
		return
	for peer_id in peers:_send_snapshot(peer_id)
	if action=="news_note":_reply_island_note(id,sequence,result.ok)
	_complete_shipping(id,sequence,action,result)

## Transport-level extra bound, checked before a sequence is consumed. Only the
## five SOURCE_ACTIONS with a "|" payload get the larger sourced bound, and only
## when the payload matches the wire grammar; every other action keeps its
## previous limit (ship / mine_auto_config byte limits, else 32 characters).
## World still owns every semantic check (recipe, adjacency, access, digest).
static func extra_allowed(action:String,extra:String) -> bool:
	if action=="night_rest":return extra.is_empty()
	if action=="night_vote":
		if extra=="open":return true
		if extra.length()>24:return false
		var parts:=extra.split(":")
		return parts.size()==2 and parts[0] in ["yes","no"] and parts[1].is_valid_int() and int(parts[1])>0
	if action=="map_signal":return extra=="cancel" or MAP_SIGNALS.has(extra)
	if action==World.INDUSTRY.DESK_DRAFT_ACTION:return extra.length()<=World.ISLAND_NOTES.LENGTH
	if action==World.RESIDENT_GOALS.ACTION and extra.begins_with(World.RESIDENT_GOALS.FUTURE_PREFIX):
		return extra.length()<=World.RESIDENT_GOALS.FUTURE_PREFIX.length()+World.ISLAND_NOTES.LENGTH
	if action==World.BARK_FRAME.ACTION:return World.BARK_FRAME.packet_allowed(extra)
	if action==World.WELCOME_SIGN.WRITE:
		return extra.length()<=World.WELCOME_SIGN.MAX_BYTES and extra.to_utf8_buffer().size()<=World.WELCOME_SIGN.MAX_BYTES
	if action in ["island_chat","news_note",World.RESIDENT_GOALS.TREE_NOTE_ACTION]:return not chat_text(extra).is_empty()
	if action in ["trade_edit","trade_confirm"]:
		return extra.to_utf8_buffer().size()<=World.TRADE.MAX_EXTRA_BYTES
	if action=="trade_cancel":
		return extra.to_utf8_buffer().size()<=World.TRADE.MAX_ID
	if action == "ship":
		return extra.length() <= World.SHIPPING.MAX_BYTES and extra.to_utf8_buffer().size() <= World.SHIPPING.MAX_BYTES
	if action == "mine_auto_config":
		return extra.length()<=World.MINE_AUTO_FREIGHT.MAX_BYTES and extra.to_utf8_buffer().size()<=World.MINE_AUTO_FREIGHT.MAX_BYTES
	if action in World.CHEST_EXACT_MOVES:
		return extra.length()<=PLAIN_EXTRA_MAX+11
	if action in SOURCE_ACTIONS and extra.contains("|"):
		return sourced_extra_valid(extra)
	if action == PREPARE_ACTION:
		return extra.length() <= PLAIN_EXTRA_MAX and source_cell_valid(extra)
	if action == KITCHEN_REGISTER:
		return kitchen_seats_valid(extra)
	if action == KITCHEN_CONTRIBUTE:
		return extra.is_empty()
	return extra.length() <= PLAIN_EXTRA_MAX

func solo_rest_reason() -> String:
	if not solo_rest_enabled or world==null or peers.size()!=1 or not peers.has(1):
		return "這個選項目前只在單機小島開放。"
	if not accepting:return "小島目前暫停寫入，無法結算休息。"
	return world.night_rest_reason(peers[1])

func _attempt_night_rest(id:int) -> void:
	if id!=1:
		_send_notice(id,"這個選項目前只在單機小島開放。",false)
		return
	var reason:=solo_rest_reason()
	if not reason.is_empty():
		_send_notice(id,reason,false)
		return
	directions[id]=Vector2.ZERO
	last_movement[id]=0
	var result:Dictionary=world.rest_until_dawn(peers[id])
	if result.ok:_send_snapshot(id)
	_send_notice(id,result.message,result.ok)

func _night_vote_problem() -> String:
	if solo_rest_enabled or not accepting:return "目前無法開始多人休息投票。"
	for voter:int in peers:
		if controller_holds.has(voter) or not identity_allows_play(voter):return "等所有在線島民都能操作後再投票。"
		var reason:String=world.night_rest_reason(peers[voter])
		if not reason.is_empty():return reason
	return ""

func _change_night_vote(id:int,choice:String,now:int) -> bool:
	if not night_vote.is_empty() and now>=int(night_vote.until):
		_end_night_vote("休息投票已逾時，島上的時間照常前進。")
	if choice=="open":
		if not night_vote.is_empty():
			_send_notice(id,"已有一場休息投票，請查看目前的投票。",false)
			return false
	else:
		if night_vote.is_empty() or int(choice.get_slice(":",1))!=int(night_vote.id):
			_send_notice(id,"這場休息投票已結束。",false)
			return false
		if choice.begins_with("no:"):
			_end_night_vote("有島民想繼續活動，已取消休息投票。")
			return true
	var problem:=_night_vote_problem()
	if not problem.is_empty():
		if night_vote.is_empty():_send_notice(id,problem,false)
		else:_end_night_vote(problem)
		return false
	if choice=="open":
		night_vote_serial+=1
		night_vote={"id":night_vote_serial,"until":now+NIGHT_VOTE_TTL_MS,"yes":{}}
	night_vote.yes[id]=true
	directions[id]=Vector2.ZERO
	last_movement[id]=0
	if night_vote.yes.size()==peers.size():
		var result:Dictionary=world.rest_until_dawn(peers[id])
		_end_night_vote(result.message,result.ok)
		return bool(result.ok)
	for peer_id:int in peers:_send_snapshot(peer_id)
	return true

func _end_night_vote(message:String,success:bool=false) -> void:
	night_vote.clear()
	for id:int in peers:
		_send_snapshot(id)
		_send_notice(id,message,success)

func night_vote_view(id:int) -> Dictionary:
	if solo_rest_enabled:return {}
	if night_vote.is_empty():return {"id":0,"total":peers.size()}
	return {"id":night_vote.id,"total":peers.size(),"yes":night_vote.yes.size(),
		"mine":night_vote.yes.has(id),"seconds":maxi(0,ceili((int(night_vote.until)-Time.get_ticks_msec())/1000.0))}

## kitchen_register extra: "seat_a|seat_b", at most 32 ASCII bytes, exactly two
## canonical NON-NEGATIVE "x,y" cells (no sign/spaces/leading zeros), distinct
## and sorted strictly ascending by String comparison (seat_a < seat_b), the
## same order SaveSchema stores public_kitchen.seats in. World still checks
## ownership, type, range, region and access.
static func kitchen_seats_valid(extra:String) -> bool:
	if extra.length() > PLAIN_EXTRA_MAX or extra.to_utf8_buffer().size() != extra.length():return false
	var parts:PackedStringArray=extra.split("|")
	if parts.size() != 2:return false
	for part in parts:
		if part.begins_with("-") or not source_cell_valid(part):return false
	return parts[0] < parts[1]

## recipe|box_cell|box_id|digest16, at most 96 ASCII bytes. recipe: 1..32
## printable non-space ASCII; box_cell: canonical "x,y"; box_id: 32 lowercase
## hex after an explicit prepare_material_box; digest: 16 lowercase hex.
static func sourced_extra_valid(extra:String) -> bool:
	if extra.length() > SOURCED_EXTRA_MAX or extra.to_utf8_buffer().size() != extra.length():return false
	var parts:PackedStringArray=extra.split("|")
	if parts.size() != 4:return false
	var recipe:String=parts[0]
	if recipe.is_empty() or recipe.length() > SOURCE_RECIPE_MAX:return false
	for c in recipe:
		var code:int=c.unicode_at(0)
		if code < 0x21 or code > 0x7e:return false
	if not source_cell_valid(parts[1]):return false
	if not _lower_hex(parts[2],SOURCE_BOX_ID_LENGTH):return false
	return _lower_hex(parts[3],SOURCE_DIGEST_LENGTH)

## Canonical "x,y" (optional leading minus, no spaces/plus/leading zeros).
static func source_cell_valid(text:String) -> bool:
	if text.length() > PLAIN_EXTRA_MAX:return false
	var parts:PackedStringArray=text.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return false
	if parts[0].trim_prefix("-").length() > 6 or parts[1].trim_prefix("-").length() > 6:return false
	return text == "%d,%d" % [int(parts[0]),int(parts[1])]

static func _lower_hex(text:String,size:int) -> bool:
	if text.length() != size:return false
	for c in text:
		if not "0123456789abcdef".contains(c):return false
	return true

func _complete_shipping(id: int, sequence: int, action: String, result: Dictionary) -> void:
	# Undo also needs an authoritative completion to release a failed submission
	# for retry (for example a temporary save failure), without guessing from text.
	# Cooking needs the exact request sequence too: a festival/world notice is
	# not an acknowledgement of a queued dish or cancellation. Processing queue
	# operations (protocol 39) use the same correlated path; no new RPC.
	# 害羞菇: an ordinary `water` routed to the mushroom carries `shy`, so the actor gets its cue too.
	if action in CORRELATED_ACTIONS or result.has("shy") or action in World.COMMUNITY.ACTIONS or action in [World.WALL_FIXTURES.WATER_CHIME_RING,World.INDUSTRY.PAVILION_INSPECT,CHEST_HISTORY_READ]:
		if id == 1:receive_action_completed(sequence,action,result)
		elif _can_send(id):receive_action_completed.rpc_id(id,sequence,action,result)

@rpc("authority","call_remote","reliable",3)
func receive_action_completed(sequence: int, action: String, result: Dictionary) -> void:
	action_completed.emit(sequence,action,result)

# ---------------------------------------------------------------------------
# Blueprint transport (docs/blueprint-integration.md 第三段傳輸 API 固定介面).
# Dedicated RPCs: never routed through _action, sequences, rates or movement.
# Session never re-sends a submission by itself; a later frontend controller
# owns the pending fixed intent (same nonce/design/origin/turns/hash/context).
# Results flagged not_sent were definitely never delivered to the world.
# ---------------------------------------------------------------------------

func _blueprint_now() -> int:
	if blueprint_clock.is_valid():return int(blueprint_clock.call())
	return Time.get_ticks_msec()

func _blueprint_attach(id:int) -> void:
	blueprint_quote_stamps[id]=[]
	blueprint_apply_stamps[id]=[]

func _blueprint_forget(id:int) -> void:
	blueprint_quote_stamps.erase(id)
	blueprint_apply_stamps.erase(id)

func _blueprint_stamps(store:Dictionary,id:int) -> Array:
	if not store.get(id) is Array:store[id]=[]
	return store[id]

## "" when this process can submit now; otherwise why nothing was sent.
func _blueprint_unavailable() -> String:
	if shutting_down:return "世界已關閉，藍圖沒有送出。"
	if world!=null:
		return "" if peers.has(1) else "這台主機沒有操作中的島民，無法使用藍圖。"
	var link:=multiplayer.multiplayer_peer
	if link==null or link is OfflineMultiplayerPeer or multiplayer.is_server() or not blueprint_welcomed:
		return "尚未連上世界，藍圖沒有送出。"
	if link.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:
		return "尚未連上世界，藍圖沒有送出。"
	return ""

## Own region/epoch from the current snapshot unless given; {} if unknown.
func _blueprint_context(region:String,epoch:int) -> Dictionary:
	var people=snapshot.get("players",{})
	var mine=people.get(own_id) if people is Dictionary and not own_id.is_empty() else null
	if (region.is_empty() or epoch<0) and not mine is Dictionary:return {}
	return {"region":region if not region.is_empty() else str(snapshot.get("region_id","home")),
		"epoch":epoch if epoch>=0 else int(mine.get("travel_epoch",0))}

func _blueprint_send_refusal(design:String,origin:Vector2i,turns:Variant) -> Dictionary:
	var unavailable:=_blueprint_unavailable()
	if not unavailable.is_empty():return BlueprintProtocol.failure(unavailable,"not_sent")
	var problem:String=BlueprintProtocol.bounds_problem(design,origin,turns)
	if not problem.is_empty():return BlueprintProtocol.failure(problem,"not_sent")
	return {}

## Returns a request ID (1..1e9, wrapping) that blueprint_quoted echoes. Every
## outcome, including local refusals, arrives deferred, after this returns.
func quote_blueprint(raw:Variant,origin:Vector2i,turns:Variant=0) -> int:
	blueprint_counter=blueprint_counter%BlueprintProtocol.MAX_REQUEST_ID+1
	var request_id:=blueprint_counter
	var design:String=BlueprintProtocol.encode_design(raw)
	var refusal:=_blueprint_send_refusal(design,origin,turns)
	var context:={}
	if refusal.is_empty():
		context=_blueprint_context("",-1)
		if context.is_empty():
			refusal=BlueprintProtocol.failure("尚未取得目前位置，藍圖沒有送出。","stale_context")
			refusal.not_sent=true
	if not refusal.is_empty():
		receive_blueprint_quote.call_deferred(request_id,refusal)
	elif world!=null:
		_handle_blueprint_quote.call_deferred(1,request_id,design,origin,turns,context.region,context.epoch)
	elif rpc_id(1,"request_blueprint_quote",request_id,design,origin,turns,context.region,context.epoch)!=OK:
		receive_blueprint_quote.call_deferred(request_id,BlueprintProtocol.failure("連線傳送失敗，藍圖沒有送出。","not_sent"))
	return request_id

## Fixed-intent submission; blueprint_applied echoes `nonce`. region/epoch
## default to the current own snapshot. Results always arrive deferred.
func submit_blueprint(nonce:String,raw:Variant,origin:Vector2i,turns:Variant,expected_hash:String,region:String="",epoch:int=-1) -> void:
	var design:String=BlueprintProtocol.encode_design(raw)
	var refusal:=_blueprint_send_refusal(design,origin,turns)
	if refusal.is_empty() and not (BlueprintProtocol.valid_nonce(nonce) and BlueprintProtocol.valid_hash(expected_hash)):
		refusal=BlueprintProtocol.failure("施工編號或報價資料無效，請重新報價。","not_sent")
	var context:={}
	if refusal.is_empty():
		context=_blueprint_context(region,epoch)
		if context.is_empty():
			refusal=BlueprintProtocol.failure("尚未取得目前位置，藍圖沒有送出。","stale_context")
			refusal.not_sent=true
	if not refusal.is_empty():
		receive_blueprint_result.call_deferred(nonce,refusal)
	elif world!=null:
		_handle_blueprint_apply.call_deferred(1,nonce,design,origin,turns,expected_hash,context.region,context.epoch)
	elif rpc_id(1,"request_blueprint_apply",nonce,design,origin,turns,expected_hash,context.region,context.epoch)!=OK:
		receive_blueprint_result.call_deferred(nonce,BlueprintProtocol.failure("連線傳送失敗，藍圖沒有送出。","not_sent"))

@rpc("any_peer","call_remote","reliable",2)
func request_blueprint_quote(request_id:int,design_json:String,origin:Vector2i,turns:Variant,region:String,epoch:int) -> void:
	if not multiplayer.is_server():return
	_handle_blueprint_quote(multiplayer.get_remote_sender_id(),request_id,design_json,origin,turns,region,epoch)

@rpc("any_peer","call_remote","reliable",2)
func request_blueprint_apply(nonce:String,design_json:String,origin:Vector2i,turns:Variant,expected_hash:String,region:String,epoch:int) -> void:
	if not multiplayer.is_server():return
	_handle_blueprint_apply(multiplayer.get_remote_sender_id(),nonce,design_json,origin,turns,expected_hash,region,epoch)

## Caller gate shared by quote/apply: {} allowed; {drop:true} for an
## unidentified remote peer (nothing to correlate, no reply); else a failure.
func _blueprint_caller_refusal(id:int) -> Dictionary:
	if world==null or shutting_down:
		return BlueprintProtocol.failure("世界已關閉，藍圖沒有送出。","not_sent") if id==1 else {"drop":true}
	if not peers.has(id):
		return BlueprintProtocol.failure("這台主機沒有操作中的島民，無法使用藍圖。","not_sent") if id==1 else {"drop":true}
	if not accepting or not identity_allows_play(id):
		return BlueprintProtocol.failure("世界目前暫停操作，藍圖沒有施工。")
	return {}

func _handle_blueprint_quote(id:int,request_id:int,design_json:String,origin:Vector2i,turns:Variant,region:String,epoch:int) -> void:
	var refusal:=_blueprint_caller_refusal(id)
	if refusal.get("drop")==true:return
	if refusal.is_empty() and not BlueprintProtocol.valid_request_id(request_id):
		refusal=BlueprintProtocol.failure("報價請求編號無效。")
	if refusal.is_empty():
		var problem:String=BlueprintProtocol.bounds_problem(design_json,origin,turns)
		if not problem.is_empty():refusal=BlueprintProtocol.failure(problem)
	if refusal.is_empty() and not BlueprintProtocol.take(_blueprint_stamps(blueprint_quote_stamps,id),_blueprint_now(),
			BlueprintProtocol.QUOTE_LIMIT,BlueprintProtocol.QUOTE_WINDOW_MS):
		refusal=BlueprintProtocol.failure("報價太頻繁了，稍等一下再試。","rate_limited")
	if refusal.is_empty() and not context_matches(id,region,epoch):
		refusal=BlueprintProtocol.failure("位置或區域已變動，請重新報價。","stale_context")
	var parsed:={}
	if refusal.is_empty():
		parsed=BlueprintProtocol.parse_design(design_json)
		if parsed.get("ok")!=true:refusal=BlueprintProtocol.failure("藍圖資料格式錯誤。")
	if not refusal.is_empty():
		_reply_blueprint_quote(id,request_id,refusal)
		return
	var quote=world.quote_blueprint(peers[id],parsed.raw,origin,turns)
	_reply_blueprint_quote(id,request_id,BlueprintProtocol.sanitize(quote,World.NAMES))

func _handle_blueprint_apply(id:int,nonce:String,design_json:String,origin:Vector2i,turns:Variant,expected_hash:String,region:String,epoch:int) -> void:
	# Replies echo the nonce; an oversized one is truncated (it can never match).
	var reply_nonce:=nonce.left(BlueprintProtocol.NONCE_LENGTH*2)
	var refusal:=_blueprint_caller_refusal(id)
	if refusal.get("drop")==true:return
	if refusal.is_empty() and night_vote.get("yes",{}).has(id):
		_end_night_vote("有島民正在確認施工，已取消這次休息投票。")
	if refusal.is_empty() and not (BlueprintProtocol.valid_nonce(nonce) and BlueprintProtocol.valid_hash(expected_hash)):
		refusal=BlueprintProtocol.failure("施工編號或報價資料無效，請重新報價。")
	if refusal.is_empty():
		var problem:String=BlueprintProtocol.bounds_problem(design_json,origin,turns)
		if not problem.is_empty():refusal=BlueprintProtocol.failure(problem)
	# Receipt re-sends also pass this limiter, so replies stay rate-bounded.
	if refusal.is_empty() and not BlueprintProtocol.take(_blueprint_stamps(blueprint_apply_stamps,id),_blueprint_now(),
			BlueprintProtocol.APPLY_LIMIT,BlueprintProtocol.APPLY_WINDOW_MS):
		refusal=BlueprintProtocol.failure("施工送出太頻繁了，稍等一下再試。","rate_limited")
	if refusal.is_empty():
		# Read-only receipt before context: a completed submission stays
		# confirmable after travel/reconnect, but only for this same
		# authenticated, currently allowed player (caller gate above).
		var receipt=world.blueprint_receipt(peers[id],nonce)
		if receipt is Dictionary and not receipt.is_empty():
			_send_snapshot(id)
			_reply_blueprint_result(id,reply_nonce,BlueprintProtocol.sanitize(receipt,World.NAMES))
			return
	if refusal.is_empty() and not context_matches(id,region,epoch):
		refusal=BlueprintProtocol.failure("位置或區域已變動，請重新報價。","stale_context")
	var parsed:={}
	if refusal.is_empty():
		parsed=BlueprintProtocol.parse_design(design_json)
		if parsed.get("ok")!=true:refusal=BlueprintProtocol.failure("藍圖資料格式錯誤。")
	if not refusal.is_empty():
		_reply_blueprint_result(id,reply_nonce,refusal)
		return
	var result=world.apply_blueprint(peers[id],nonce,parsed.raw,origin,turns,expected_hash)
	# Snapshots first (same reliable channel 3), then the completion.
	if result is Dictionary and result.get("ok")==true:
		for peer_id in peers:_send_snapshot(peer_id)
	_reply_blueprint_result(id,reply_nonce,BlueprintProtocol.sanitize(result,World.NAMES))

func _reply_blueprint_quote(id:int,request_id:int,result:Dictionary) -> void:
	if id==1:receive_blueprint_quote(request_id,result)
	elif _can_send(id):receive_blueprint_quote.rpc_id(id,request_id,result)

func _reply_blueprint_result(id:int,nonce:String,result:Dictionary) -> void:
	if id==1:receive_blueprint_result(nonce,result)
	elif _can_send(id):receive_blueprint_result.rpc_id(id,nonce,result)

@rpc("authority","call_remote","reliable",3)
func receive_blueprint_quote(request_id:int,result:Dictionary) -> void:
	blueprint_quoted.emit(request_id,result)

@rpc("authority","call_remote","reliable",3)
func receive_blueprint_result(nonce:String,result:Dictionary) -> void:
	blueprint_applied.emit(nonce,result)

static func _public_actor(token:Variant) -> String:
	return String(token).sha256_text().left(16)

## Same output as _public_actor; `ids` is a per-call memo keyed by String(token)
## and must never outlive one public_state call.
static func _public_actor_memo(ids:Dictionary,token:Variant) -> String:
	var key:String=String(token)
	var cached:Variant=ids.get(key)
	if cached!=null:return cached
	var public_id:String=key.sha256_text().left(16)
	ids[key]=public_id
	return public_id

## Stove cooking queue (protocol 38): cooking={active:{..},waiting:[..],ready:[..]}.
## Runs only on public_state's fresh deep copy, never on World state, so every
## call/region redacts exactly once and nothing is hashed twice. Every record
## owner (including owners who are offline / not in peers) becomes the public
## actor16hex; malformed queue shapes are dropped instead of risking raw tokens.
##
## For the current single-job UI, a DERIVED `job` is added when the queue has a
## ready or active record: the oldest ready record (by completion time), else the
## active one; no projection when both are empty. It carries only
## kind/owner/ready/ingredients/yield/recipe_version, with `ready` = the record's
## completed (or finish) time and the already-public owner (not re-hashed). It is
## display-only and NON-AUTHORITATIVE: World never stores it or saves it, and
## claim_cook/cancel_cook/queue_cook/cancel_queued_cook remain World's decision.
## World never keeps a legacy `job` beside `cooking`; if one ever appears it is
## left as the (already redacted) authority and no projection replaces it.
func _publish_cooking(obj:Dictionary,ids:Dictionary) -> void:
	_publish_queue(obj,"cooking",true,ids)

## Sawmill/charcoal kiln processing queue (protocol 39): same canonical shape in
## obj.processing and the same once-only owner redaction on the fresh copy. The
## display-only `job` projection (oldest ready, else active) lets existing
## IndustryArt/IndustryUI draw the station; it uses the legacy processing job
## shape kind/owner/ready/ingredients/yield (no recipe_version, never `auto`).
## It is never written to World state or saved; an authoritative legacy job, if
## somehow present, is left as-is and not replaced.
func _publish_processing(obj:Dictionary,ids:Dictionary) -> void:
	_publish_queue(obj,"processing",false,ids)

func _publish_queue(obj:Dictionary,field:String,with_recipe_version:bool,ids:Dictionary) -> void:
	var queue=obj[field]
	if not queue is Dictionary:
		obj.erase(field)
		return
	var active=queue.get("active")
	if active!=null:
		if not active is Dictionary:queue.erase("active")
		elif active.has("owner"):active.owner=_public_actor_memo(ids,active.owner)
	for lane in ["waiting","ready"]:
		if not queue.has(lane):continue
		if not queue[lane] is Array:
			queue.erase(lane)
			continue
		var kept:Array=[]
		for entry in queue[lane]:
			if not entry is Dictionary:continue
			if entry.has("owner"):entry.owner=_public_actor_memo(ids,entry.owner)
			kept.append(entry)
		queue[lane]=kept
	if obj.has("job"):return
	var source:Dictionary={}
	var oldest:=0.0
	for entry in queue.get("ready",[]):
		var at:=_cooking_done_at(entry)
		if source.is_empty() or at<oldest:
			source=entry
			oldest=at
	if source.is_empty() and queue.get("active") is Dictionary:source=queue.active
	if source.is_empty():return
	var ingredients=source.get("ingredients",{})
	obj.job={"kind":String(source.get("kind","")),"owner":String(source.get("owner","")),
		"ready":_cooking_done_at(source),
		"ingredients":ingredients.duplicate(true) if ingredients is Dictionary else {},
		"yield":int(source.get("yield",0))}
	if with_recipe_version:obj.job["recipe_version"]=int(source.get("recipe_version",1))

static func _cooking_done_at(entry:Dictionary) -> float:
	for field in ["completed","finish"]:
		if entry.has(field):return float(entry[field])
	return 0.0

## Periodic-broadcast reuse of recipient- AND region-independent computations.
## Only active inside the periodic loop on a dedicated server. A listen host
## can run callbacks synchronously during delivery, so its snapshots build fresh.
## Each recipient receives its own copy of any reusable data.
var _bcast_active:=false
var _bcast_shared:Dictionary={}
var _bcast_cell_positions:Dictionary={}

func _begin_broadcast_share() -> void:
	_bcast_active=not peers.has(1)

func _end_broadcast_share() -> void:
	_bcast_active=false
	_bcast_shared.clear()
	_bcast_cell_positions.clear()

func _shared(key:String,build:Callable) -> Variant:
	if not _bcast_active:return build.call()
	if not _bcast_shared.has(key):_bcast_shared[key]=build.call()
	var value:Variant=_bcast_shared[key]
	return value.duplicate(true) if value is Dictionary or value is Array else value

## `view`: see World.region_snapshot. Rows it leaves out are never copied or redacted
## here; every row that is sent goes through the same redaction as without it.
func public_state(region:String="home",recipient:String="",view:Dictionary={},goal_facts:Dictionary={}) -> Dictionary:
	var public_ids:Dictionary={} # per-call only; never cache owner tokens across calls
	var out:Dictionary=world._region_snapshot_source(region,true,recipient,view)
	# These records are either private or replaced below with public projections.
	# Omit them before the deep copy so the broadcast skips private history.
	for field in [
		"events","harvest_relay","fish_meet","showcase","mine_auto_freight","mine_survey","tea_ceramics",
		"flower_nursery","salt_pan",World.OUTLYING_COMMISSIONS.STATE_KEY,World.TABLE_WARMER.STATE_KEY,
		World.RESIDENT_GOALS.MURAL_KEY,World.GOLD_PANNING.STATE_KEY,World.ORE_ROUTE.STATE_KEY,
		World.LANYANG_REVISIT.STATE_KEY,World.JINGUASHI_REVISIT.STATE_KEY,World.TEA_SERVICE.STATE_KEY,
		World.TEA_REVISIT.STATE_KEY,World.TEA_REVISIT.HOUSE_KEY,World.SALT_REVISIT.STATE_KEY,
		World.SALT_BRINE.STATE_KEY,World.MEMORY_EXHIBIT.STATE_KEY,
	]:
		out.erase(field)
	out=out.duplicate(true)
	if region!=World.REGIONS.Bamboo.REGION:out.erase(World.REGIONS.Bamboo.CUT_FIELD)
	var cuddler:=World.CHICKEN_CUDDLE.holder(world.state,world.active_tokens)
	out.animal.erase(World.CHICKEN_CUDDLE.FIELD)
	if region=="home" and not cuddler.is_empty():out.animal[World.CHICKEN_CUDDLE.FIELD]=_public_actor(cuddler)
	var feeder:=World.CHICKEN_FEED_FOLLOW.holder(world.state,world.active_tokens)
	out.animal.erase(World.CHICKEN_FEED_FOLLOW.FIELD)
	if region=="home":
		out.chicken_feed_follow=true
		if not feeder.is_empty():out.animal[World.CHICKEN_FEED_FOLLOW.FIELD]=_public_actor(feeder)
	var cow_actor:=World.COW_CARE.active_actor(world.state,world.active_tokens)
	if out.get("livestock",{}).has("cow"):
		out.livestock.cow.erase(World.COW_CARE.FIELD)
		if region=="home" and not cow_actor.is_empty():out.livestock.cow[World.COW_CARE.FIELD]=_public_actor(cow_actor)
	var exhibits:Dictionary={}
	for token:String in world.state.players:
		var exhibitor:Dictionary=world.state.players[token]
		var pieces:Array=exhibitor.get("collection_display",[])
		if not pieces.is_empty():exhibits[_public_actor(token)]={"name":str(exhibitor.name),"items":pieces.duplicate()}
	if not exhibits.is_empty():out.collection_exhibits=exhibits
	if out.has("public_fund"):out.public_fund.erase("contributors")
	for dish in World.COMMUNITY.DISHES:
		if out.get("community",{}).has(dish):out.community[dish].erase("claimed")
	# T067 共餐桌保溫底座：公開白名單 {"installed":true}；未加裝時沒有這個鍵。
	if World.TABLE_WARMER.installed(world.state):out[World.TABLE_WARMER.STATE_KEY]=World.TABLE_WARMER.public(world.state)
	# 第 40 章蘭陽回訪：公開 gates/day/checked/completed；領取名單（token）不公開，
	# 收件人只會在 _send_snapshot 拿到自己的 claimed_own。沒有紀錄時沒有這個鍵。
	if world.state.has(World.LANYANG_REVISIT.STATE_KEY):out[World.LANYANG_REVISIT.STATE_KEY]=World.LANYANG_REVISIT.public(world.state)
	# 第 40 章金瓜石回訪：公開 crates/day/sent/completed/done_day；領取名單不公開，
	# 收件人只會在 _send_snapshot 拿到自己的 claimed_own。沒有紀錄時沒有這個鍵。
	if world.state.has(World.JINGUASHI_REVISIT.STATE_KEY):out[World.JINGUASHI_REVISIT.STATE_KEY]=World.JINGUASHI_REVISIT.public(world.state)
	# 第 40 章貓空與鶯歌回訪：公開 jars/filled/day/completed/done_day；領取名單不公開，
	# 收件人只會在 _send_snapshot 拿到自己的 claimed_own。沒有紀錄時沒有這個鍵。
	# 第 40 章茶陶上桌：公開 {"placed":true[,"round":{"style","portions"}]}；出借人與喝過的名單
	# （token）不公開，收件人只會在 _send_snapshot 拿到自己的 lender_own／sipped_own。
	# 第 40 章金瓜石河邊淘砂金：各人的盤子與盤數（token）不公開；收件人只會在 _send_snapshot
	# 拿到自己的 own_gold_panning（只在金瓜石山城）。
	if World.TEA_SERVICE.placed(world.state):out[World.TEA_SERVICE.STATE_KEY]=World.TEA_SERVICE.public(world.state)
	if world.state.has(World.TEA_REVISIT.STATE_KEY):out[World.TEA_REVISIT.STATE_KEY]=World.TEA_REVISIT.public(world.state)
	# 第 40 章臺南北門回訪：公開 stocked/packed/rain_packs/day/completed/done_day；領取名單不公開，
	# 收件人只會在 _send_snapshot 拿到自己的 claimed_own。沒有紀錄時沒有這個鍵。
	if world.state.has(World.SALT_REVISIT.STATE_KEY):out[World.SALT_REVISIT.STATE_KEY]=World.SALT_REVISIT.public(world.state)
	# 第 40 章北門儲滷槽：公開 {"level":桶數}；沒有 token。沒有紀錄時沒有這個鍵。
	if world.state.has(World.SALT_BRINE.STATE_KEY):out[World.SALT_BRINE.STATE_KEY]=World.SALT_BRINE.public(world.state)
	# 第 40 章地方記憶展：公開只有展台格、是否暫停與展出中的展品；未開幕時沒有這個鍵。
	# 誰看過哪件展品只在本人的 own_memory_exhibit（_send_snapshot）。
	if World.MEMORY_EXHIBIT.unlocked(world.state):out[World.MEMORY_EXHIBIT.STATE_KEY]=World.MEMORY_EXHIBIT.public(world.state)
	# T066 N01-3: transient Aru bench scene ({} idle). Actor ids use the same hash as players' public ids.
	out.aru_bench_scene={}
	if region==World.REGIONS.HOME:
		out.aru_bench_scene=World.ARU_BENCH.public_scene(world.aru_bench_scene(),World.key,_public_actor)
	var rest_fixtures:=0
	for saved_player:Dictionary in world.state.players.values():
		rest_fixtures|=int(saved_player.get(World.RESIDENT_GOALS.REST_KIT_KEY,0))
		if rest_fixtures==World.RESIDENT_GOALS.REST_KIT_MASK:break
	out.bobo_rest_fixtures=rest_fixtures
	var mural:=World.RESIDENT_GOALS.mural_public(world.state)
	if not mural.is_empty():out[World.RESIDENT_GOALS.MURAL_KEY]=mural
	var garden:=World.RESIDENT_GOALS
	if out.has(garden.GARDEN_KEY):
		for pot:Dictionary in out[garden.GARDEN_KEY]:
			pot.name=garden.GARDEN_NPCS.get(pot.author,{}).get("name","") if pot.npc else str(world.state.players.get(pot.author,{}).get("name","島民"))
			pot.author=_public_actor(pot.author) if not pot.npc else pot.author
	var visible:Dictionary={}
	for id in peers:
		var token:String=peers[id]
		if not world.state.players.has(token) or world.player_region(token)!=region:continue
		# Redaction only edits top-level keys. Copy nested values after removing
		# private fields so offline players and their histories are never copied.
		var person:Dictionary=world.state.players[token].duplicate()
		person.erase("receipts")
		person.erase(World.MUSHROOM_MAIL.RECORD)
		if token!=recipient:person.erase(World.INDUSTRY.DESK_DRAFT_FIELD)
		if token!=recipient:person.erase(World.INDUSTRY.HOME_REST_FIELD)
		if token!=recipient:person.erase("gathering_assists")
		person.exploration_points=World.exploration_points(person)
		person.erase("explored_regions")
		person.erase("travel_book")
		person.erase("resident_participation")
		person.erase("bonds")
		var voyage:=World.RESIDENT_GOALS
		if person.has(voyage.VOYAGE_START):
			var harbor_pos:Vector2=voyage.voyage_position(float(out.time)-float(person[voyage.VOYAGE_START]))
			person.x=harbor_pos.x
			person.y=harbor_pos.y
			person.at_sea=true
			var leader:String=person.get(voyage.VOYAGE_CAPTAIN,"")
			if not leader.is_empty() and leader in peers.values():
				person.voyage_captain=_public_actor(leader)
		person.erase(voyage.VOYAGE_CAPTAIN)
		person.erase(voyage.VOYAGE_PHOTO)
		person.erase(voyage.VOYAGE_START)
		person.erase(voyage.VOYAGE_DONE)
		person.erase(World.RESIDENT_GOALS.ARU_PHOTO_KEY)
		person.erase(World.RESIDENT_GOALS.ARU_REST_KEY)
		person.erase(World.RESIDENT_GOALS.SHEEP_SHELTER_KEY)
		person.erase(World.RESIDENT_GOALS.TEA_CHAIR_KEY)
		person.erase(World.RESIDENT_GOALS.TEA_SETUP_KEY)
		person.erase(World.RESIDENT_GOALS.TEA_TOPICS_KEY)
		person.erase(World.RESIDENT_GOALS.PAINT_INVITES_KEY)
		person.erase(World.RESIDENT_GOALS.GROWTH_KEY)
		person.erase(World.RESIDENT_GOALS.GROWTH_LOG_KEY)
		person.erase(World.RESIDENT_GOALS.ADDRESS_KEY)
		person.erase(World.RESIDENT_GOALS.POSTCARD_CLUES_KEY)
		person.erase(World.RESIDENT_GOALS.FUTURE_NOTE_KEY)
		person.erase(World.RESIDENT_GOALS.GUEST_ROOM_KEY)
		person.erase(World.WARM_SPRINGS.CRACK_KEY)
		person.erase(World.WANGAN_MEMORY.KEY)
		person.erase(World.WANGAN_MEMORY.WEIR_KEY)
		person.erase(World.WANGAN_MEMORY.LOG_KEY)
		person.erase(World.CHAPTER_ONE.PERSONAL_START)
		person.erase(World.RESIDENT_GOALS.GUEST_CLOTH_KEY)
		person.erase(World.RESIDENT_GOALS.BELL_INSPECT_KEY)
		person.erase(World.RESIDENT_GOALS.REST_KIT_KEY)
		person.erase(World.BOBO_EMPTY_CART.FIELD) # T066 N03-4 空礦車進度只給本人（own_bobo_empty_cart，只在金瓜石）
		person.erase(World.RESIDENT_GOALS.RECIPE_PAGE_KEY)
		person.erase(World.RESIDENT_GOALS.ROUTE_KEY)
		person.erase(World.MILU_SUPPER.KEY) # N02-4 supper dish/guests only for the owner (own_milu_supper)
		person.erase(World.RESIDENT_GOALS.SKETCH_KEY)
		person.erase(World.RESIDENT_GOALS.CROP_TRADE_KEY)
		person.erase(World.TRANSACTION_LEDGER.FIRST_SHOP_KEY)
		person.erase(World.RESIDENT_GOALS.CHICKEN_FED_KEY)
		person.erase(World.RESIDENT_GOALS.SHEEP_STEP_KEY) # N06-4 看羊時間只給本人（own_mianmian_step_time）
		person.erase(World.RESIDENT_GOALS.RECORD_KEY) # T066「一起做的事」只給本人（data.resident_goals）
		person.erase(World.XIAOLI_SHOP.NAME_KEY)
		person.erase(World.XIAOLI_SHOP.SCALE_KEY)
		person.erase(World.RESIDENT_GOALS.KEEPSAKE_KEY) # T066 紀念小物領取紀錄只給本人（data.resident_goals 的 keepsake）
		person.erase("market")
		person.erase("market_decor")
		person.erase(World.SPRING_GARDEN.KEY)
		person.erase(World.SEA_BREEZE_FAIR.KEY)
		person.erase(World.AUTUMN_FEAST.KEY)
		person.erase(World.WARM_LANTERN_NIGHT.KEY)
		person.erase(World.LANTERN_STROLL.KEY)
		if region==World.REGIONS.HOME and World.LANTERN_STROLL.wearing(world.state,token):
			person["stroll_lantern"]=true
		person.erase(World.BEACH_TREASURE.KEY)
		person.erase(World.COOKING_RELAY.KEY)
		person.erase("summer_market") # C12 D14 食譜紀錄只給本人（data.own_summer_market）
		person.erase(World.FOREST_MUSHROOM.KEY)
		person.erase("harvest_relay")
		person.erase("fish_meet")
		person.erase("showcase")
		person.erase("souvenir") # T071 紀念票兌換紀錄只給本人（data.own_souvenir）
		person.erase("news_seen")
		person.erase("island_note_seen")
		person.erase("ferry_recap_seen")
		person.erase(World.MEMORY_EXHIBIT.RECORD_KEY) # 第 40 章記憶展補看紀錄只給本人
		person.erase("outlying_boat_arrival")
		person["peer"]=id
		visible[_public_actor_memo(public_ids,token)]=person.duplicate(true)
	out.players=visible
	var contributors:Dictionary={}
	for token in out.festival.contributors:
		contributors[_public_actor_memo(public_ids,token)]={"name":world.state.players[token].name,"count":out.festival.contributors[token]}
	out.festival.contributors=contributors
	# T071 豐收接力：參加者以公開 id（sha256 前 16 碼）為鍵，只含名字、手上的模型菜與計數。
	out.harvest_relay=_shared("harvest_relay",func():return World.HARVEST.public(world.state))
	# T071 河岸釣魚會：參加者以公開 id 為鍵，只含名字、記錄筆數與是否在場。
	out.fish_meet=_shared("fish_meet",func():return World.FISH_MEET.public(world.state))
	# T071 家園布置題：參加者以公開 id 為鍵；道具只有格子與種類，沒有放置者 token。
	out.showcase=_shared("showcase",func():return World.SHOWCASE.public(world.state))
	if region==World.REGIONS.HOME:out[World.AUTUMN_FEAST.KEY]=World.AUTUMN_FEAST.public_view(world.state)
	if region==World.REGIONS.HOME:out[World.LANTERN_STROLL.KEY]=World.LANTERN_STROLL.public_view(world.state)
	if region==World.REGIONS.HOME:out[World.WARM_LANTERN_NIGHT.KEY]=World.WARM_LANTERN_NIGHT.public_view(world.state)
	if region==World.REGIONS.HOME:out[World.BEACH_TREASURE.KEY]=World.BEACH_TREASURE.public_view(world.state)
	if region==World.PARTY_CART.REGION:out[World.PARTY_CART.KEY]=World.PARTY_CART.public_view(world.state)
	# Protocol 52: Jinguashi only; a world-wide Boolean, never says whose bond goal opened it.
	if region==World.PARTY_CART.SURFACE:out.party_cart_unlocked=world.party_cart_unlocked()
	if region==World.REGIONS.HOME:out[World.LOST_CHICKS.KEY]=World.LOST_CHICKS.public_view(world.state)
	if region==World.REGIONS.HOME:out[World.COOKING_RELAY.KEY]=World.COOKING_RELAY.public_view(world.state,world.active_tokens)
	for edge in out.edges.values():
		edge.owner=_public_actor_memo(public_ids,edge.owner)
	# A subscribed box can be sent outside the viewport for its owner. Use
	# the region's actual floor policy even when ground rows were filtered.
	var plot_ground:Dictionary=world._layers_of(region).ground
	# The resident goal reads world.state.objects. A projected or different
	# region's layer cannot answer whether the player has a bed there.
	var observe_bed:bool=goal_facts.has("own_bed") and region==world._region and view.is_empty() and not recipient.is_empty()
	if observe_bed:goal_facts.own_bed=false
	for field in ["objects","ground","roofs","forest","crops"]:
		var record_bed:bool=observe_bed and field=="objects"
		for cell_key in out[field]:
			var obj:Dictionary=out[field][cell_key]
			var kind:Variant=obj.get("type")
			if record_bed and kind=="bed" and str(obj.get("owner",""))==recipient:
				goal_facts.own_bed=true
				record_bed=false
			if field=="ground" and obj.has("visit_guest"):
				var visitor:String=obj.visit_guest
				if recipient in [obj.owner,visitor]:obj.visit_guest=_public_actor(visitor)
				else:obj.erase("visit_guest")
			if field=="objects":
				if kind=="chest" and not World.PLOT_PERMISSIONS.can_take(recipient,obj,plot_ground.get(cell_key,{})).ok:
					obj.items={}
					obj.erase("box_id")
					obj.locked=true
				obj.erase("guest_withdraw")
				if obj.has("withdraw_guest"):
					var guest:String=obj.withdraw_guest
					if recipient==guest:obj["guest_withdraw"]=true
					if recipient==obj.owner:obj.withdraw_guest=_public_actor(guest)
					else:obj.erase("withdraw_guest")
			if kind==World.INDUSTRY.ACORN_CABINET and not World.PLOT_PERMISSIONS.can_take(recipient,obj).ok:
				obj.items={}
				obj.locked=true
			if kind==World.INDUSTRY.TEA_SNACK_SHELF and not World.PLOT_PERMISSIONS.can_take(recipient,obj).ok:
				var display:Array[String]=[]
				for tier in World.INDUSTRY.SNACK_TIER_NAMES.size():
					display.append(World.INDUSTRY.snack_lead(obj,tier))
				obj[World.INDUSTRY.SNACK_VISUAL_FIELD]=display
				obj[World.INDUSTRY.SNACK_FIELD]=World.INDUSTRY.fresh_snack_tiers()
				obj.locked=true
			if kind==World.INDUSTRY.COAST_CART and obj.get("market_cart_open",false):
				var goods:Array=World.MARKET.record(world.state.players.get(obj.owner,{})).stock.keys()
				goods.sort()
				obj.market_cart_goods=goods.slice(0,2)
			if obj.has("owner"):obj.owner=_public_actor_memo(public_ids,obj.owner)
			if field=="crops" and obj.has("harvest_friend"):
				obj.harvest_friend=_public_actor_memo(public_ids,obj.harvest_friend)
			if obj.has("job"):obj.job.owner=_public_actor_memo(public_ids,obj.job.owner)
			if obj.has("cooking"):_publish_cooking(obj,public_ids)
			if obj.has("processing"):_publish_processing(obj,public_ids)
	# Protocol 41: one shared world-scoped kitchen, identical for every region
	# and recipient. Whitelisted cells/counts/flag only; it carries no player
	# identity (donor ownership stays on the already-hashed object owners).
	out.public_kitchen=_shared("public_kitchen",func():return World.SAVE_SCHEMA.public_kitchen_public(world.state))
	if out.has("station_life"):out.station_life.players={}
	if out.has("lanyang_life"):out.lanyang_life.jobs={}
	if out.has("history_memory"):out.history_memory.players={}
	# Protocol 44: per-player flower records stay server-side; every region and
	# recipient gets the same token-free shared garden projection.
	out.flower_nursery=_shared("flower_nursery",func():return World.FLOWER_NURSERY.public(world.state))
	# Protocol 45: salt records, givers and lot owners/settings stay server-side;
	# every region and recipient gets the same token-free shared projection.
	out.salt_pan=_shared("salt_pan",func():return World.SALT_PAN.public(world.state,float(world.state.time)).duplicate(true))
	if out.has("mine_freight"):out.mine_freight.jobs={}
	if out.has("bobo_workshop"):
		out.bobo_workshop.jobs={}
		out.bobo_workshop.done={}
	# Story progress uses the same public actor IDs as residents and devices.
	# Never send reusable local-profile tokens as chapter dictionary keys.
	if out.has("chapter_one"):
		for field in ["harvests","starter_claims"]:
			var public_entries:Dictionary={}
			for token in out.chapter_one[field]:
				public_entries[_public_actor_memo(public_ids,token)]=out.chapter_one[field][token]
			out.chapter_one[field]=public_entries
	return out

func _can_start_large_projects(id:int) -> bool:
	var account := str(identities.get(id, {}).get("account_id", ""))
	return membership == null or (not membership.is_blocked(account) and membership.role(account) in ["owner", "admin"])

func _count_region_population() -> Dictionary:
	var counts:Dictionary={}
	for region in World.REGIONS.ALL:counts[region]=0
	for peer_id in peers:
		counts[world.player_region(peers[peer_id])]+=1
	return counts

func _send_snapshot(id:int) -> void:
	if admission_recovery_required:return
	if id!=1 and not _can_send(id):return
	var data:=_snapshot_data(id,_view_plan(id))
	var player_id:String=String(peers[id]).sha256_text().left(16)
	if id==1:
		var local_send_started:=_t090_begin()
		receive_state(data,player_id)
		_t090_end("send",local_send_started)
		return
	var transport:=multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if transport!=null:
		var connection:=transport.get_peer(id)
		if connection!=null and SnapshotWire.accepts(connection.get_requested_url()):
			var url:=connection.get_requested_url()
			_send_wire_snapshot(id,data,player_id,SnapshotWire.accepts_delta(url),SnapshotWire.accepts_cells(url))
			return
	var send_started:=_t090_begin()
	receive_state.rpc_id(id,data,player_id)
	_t090_end("send",send_started)

## T046: what the persistent home layers of this peer's next snapshot hold, decided
## once before the snapshot is built so that rows a projection leaves out are never
## copied or redacted. Updates the peer's layer seed exactly as the send did before.
##   home      the recipient is a remote peer on the home island
##   tracked   it reported a view window; `interest` is that window around the player
##   level     projection level it opted in to (0: none, only crop growth is coarsened)
##   full      level>0 and this packet carries complete layers (seed, refresh, whole island)
func _view_plan(id:int) -> Dictionary:
	var plan:={"home":false,"tracked":false,"interest":Rect2i(),"level":0,"full":false}
	if id==1 or world.player_region(peers[id])!=World.REGIONS.HOME:
		_view_seeds.erase(id)
		return plan
	plan.home=true
	if not _view_interests.has(id):return plan
	plan.tracked=true
	var player:Dictionary=world.state.players[peers[id]]
	var center:=Vector2i(Vector2(player.x,player.y).floor())
	var half:Vector2i=_view_interests[id]
	var interest:=Rect2i(center-half,half*2+Vector2i.ONE)
	plan.interest=interest
	var level:=int(_view_layers.get(id,0))
	plan.level=level
	if level<=0:
		_view_seeds.erase(id)
		return plan
	# Complete layers on the first packet of each stay at home and of each
	# level, on a bounded refresh and while the whole island is requested;
	# a projection otherwise.
	var epoch:=int(player.get("travel_epoch",0))
	var now:=Time.get_ticks_msec()
	var seeded:Dictionary=_view_seeds.get(id,{})
	if interest.encloses(Rect2i(Vector2i.ZERO,World.SIZE)) or seeded.get("epoch")!=epoch or seeded.get("level")!=level or now-int(seeded.at)>=view_refresh_ms:
		_view_seeds[id]={"epoch":epoch,"at":now,"level":level}
		plan.full=true
	return plan

## The complete per-recipient snapshot for `plan` (see _view_plan). Sends nothing.
func _snapshot_data(id:int,plan:Dictionary) -> Dictionary:
	var public_started:=_t090_begin()
	# A projected packet only ever holds the rows ViewProjection accepts, and nothing
	# below reads a home layer as a whole (the site checks run in mine regions, crop
	# and market summaries read the world), so those rows are chosen before the copy.
	var early:bool=view_early_projection and plan.level>0 and not plan.full
	var view:Dictionary={}
	if early:
		view={"rect":plan.interest,"own":peers[id],"layers":ViewProjection.layers(plan.level)}
		if _bcast_active:view.positions=_bcast_cell_positions
	var goal_facts:={"own_bed":null}
	var data:=public_state(world.player_region(peers[id]),peers[id],view,goal_facts)
	_t090_end("public",public_started)
	var personal_started:=_t090_begin()
	data["edge_construction"]=data.region_id==World.REGIONS.HOME
	if data.region_id==World.REGIONS.HOME:
		data[World.MILL_RESTORATION.SITE_VISIBLE]=_shared("public_mill_site",func():return World.MILL_RESTORATION.site_clear(world.state))
		if data[World.MILL_RESTORATION.SITE_VISIBLE] and World.MILL_RESTORATION.repaired(world.state):
			data[World.MILL_RESTORATION.BUSY]=_shared("public_mill_busy",func():return World.MILL_RESTORATION.busy(world.state))
	data["chest_exact_transfer"]=true
	data["chest_history"]=true
	if membership!=null:
		data["can_start_large_projects"]=_can_start_large_projects(id)
		data["can_build_public_plot"]=membership.can_build_public(peers[id])
	data["room_population"]=peers.size()
	data["room_capacity"]=ROOM_CAPACITY
	data["region_population"]=_shared("region_population",_count_region_population)
	if data.has("lanyang_life"):
		data.lanyang_life["own_job"]=world.state.lanyang_life.jobs.get(peers[id],{}).duplicate(true)
	if data.has("history_memory"):
		data.history_memory["own_memory"]=world.state.history_memory.players.get(peers[id],World.HISTORY_MEMORY.fresh_record()).duplicate(true)
	var route_actor:String=peers[id]
	if data.region_id==World.GUARDIAN.REGION and bool(data.get("picnic",false)) and world.state.get("world_mode")=="adventure":
		data[World.GUARDIAN_TRIAL.KEY]=world.guardian_trial_view(route_actor)
	if data.region_id==World.SHY.REGION and bool(data.get("picnic",false)) and world.state.get("world_mode")=="adventure":
		data[World.SHY_SPORES.VIEW]=world.shy_spore_view(route_actor)
	if bool(data.get("picnic",false)) and data.region_id==World.MEADOW.REGION and int(data.mine_depths.unlocked)>=World.MEADOW.DEPTH:
		data[World.MEADOW.AVAILABLE]=World.MEADOW.site_clear(data)
		if data[World.MEADOW.AVAILABLE] and world.state.get("world_mode")=="adventure":
			data[World.MEADOW_ADVENTURE.VIEW]=world.meadow_adventure_view(route_actor)
	if bool(data.get("picnic",false)) and World.PORTER.available(data.region_id,int(data.mine_depths.unlocked)):
		data.porter_available=World.PORTER.site_clear(data)
		if data.porter_available:
			var team:Array=world.porter_team()
			if team.size()>=2:
				data.porter_watches=[]
				for index in World.PORTER.WATCH_POINTS.size():
					data.porter_watches.append(not world.porter_watcher(team,route_actor,index).is_empty())
	data.own_mushroom_mail=World.MUSHROOM_MAIL.view(world.state,world.state.players[route_actor])
	var house:=World.TEA_SERVICE.public_house(world.state,route_actor)
	if not house.is_empty():
		data[World.TEA_REVISIT.HOUSE_KEY]=house
	if data.has("history_memory"):
		var panned:=World.GOLD_PANNING.total(world.state,route_actor)>0
		var delivered:=World.ORE_ROUTE.total(world.state,route_actor)>0
		if panned or delivered:
			data.history_memory["mine_fieldwork"]={"panned":panned,"delivered":delivered}
	if data.has(World.LANYANG_REVISIT.STATE_KEY):
		data[World.LANYANG_REVISIT.STATE_KEY]["claimed_own"]=World.LANYANG_REVISIT.claimed_own(world.state,route_actor)
	if data.has(World.JINGUASHI_REVISIT.STATE_KEY):
		data[World.JINGUASHI_REVISIT.STATE_KEY]["claimed_own"]=World.JINGUASHI_REVISIT.claimed_own(world.state,route_actor)
	if world.player_region(route_actor)==World.GOLD_PANNING.REGION:
		data[World.GOLD_PANNING.OWN_KEY]=World.GOLD_PANNING.view(world.state,route_actor)
		data[World.ORE_ROUTE.OWN_KEY]=World.ORE_ROUTE.view(world.state,route_actor)
		data[World.BOBO_EMPTY_CART.OWN_KEY]=World.BOBO_EMPTY_CART.own_value(world.state.players[route_actor]) # 只送本人的整數，沒有紀錄為 0
	if data.has(World.TEA_REVISIT.STATE_KEY):
		data[World.TEA_REVISIT.STATE_KEY]["claimed_own"]=World.TEA_REVISIT.claimed_own(world.state,route_actor)
	if data.has(World.TEA_SERVICE.STATE_KEY):
		data[World.TEA_SERVICE.STATE_KEY]["lender_own"]=World.TEA_SERVICE.lender_own(world.state,route_actor)
		data[World.TEA_SERVICE.STATE_KEY]["sipped_own"]=World.TEA_SERVICE.sipped_own(world.state,route_actor)
	if data.has(World.SALT_REVISIT.STATE_KEY):
		data[World.SALT_REVISIT.STATE_KEY]["claimed_own"]=World.SALT_REVISIT.claimed_own(world.state,route_actor)
	if World.TRANSIT.boat_open(world.state):
		var region:String=world.player_region(route_actor)
		var arrival:Dictionary={}
		if world.state.players[route_actor].get("outlying_boat_arrival",false):
			arrival={"region":region,"mode":World.OUTLYING_COMMISSIONS.BOAT_MODE}
		data.own_outlying_commissions={}
		for commission_id:String in World.OUTLYING_COMMISSIONS.ids():
			data.own_outlying_commissions[commission_id]=World.OUTLYING_COMMISSIONS.status(world.state,route_actor,commission_id,{"arrival":arrival})
	data.resident_memories=preload("res://scripts/resident_story_catalog.gd").available_beats(world.state,route_actor)
	# T066: relationship progress is personal; only the recipient's own summary is sent.
	data.resident_bonds=World.RESIDENT_BOND.view(world.state.players[route_actor],float(world.state.time))
	data.resident_goals=World.RESIDENT_GOALS.view(world.state.players[route_actor],world.state,route_actor,data.resident_bonds,goal_facts.own_bed) # T066「一起做的事」本人摘要。
	var xiaoli_done:=World.RESIDENT_GOALS.done(world.state.players[route_actor],"xiaoli")
	if xiaoli_done.has(4):
		var patron:Dictionary=world.state.players[route_actor]
		data.own_xiaoli_shop={"name":World.XIAOLI_SHOP.shop_name(patron,str(xiaoli_done[4])),"input":str(patron.get(World.XIAOLI_SHOP.NAME_KEY,World.XIAOLI_SHOP.PRESETS.get(xiaoli_done[4],""))),"scale":bool(patron.get(World.XIAOLI_SHOP.SCALE_KEY,false))}
	if World.RESIDENT_GOALS.done(world.state.players[route_actor],"xiaoli").has(1):
		data.own_shop_history=World.TRANSACTION_LEDGER.shop_history(world.state,route_actor)
		data.own_first_shop_trade=world.state.players[route_actor].get(World.TRANSACTION_LEDGER.FIRST_SHOP_KEY,{}).duplicate(true)
	if world.player_region(route_actor)=="maokong":
		var seats:={}
		for resident:Dictionary in world.state.players.values():
			var choice:String=resident.get(World.RESIDENT_GOALS.TEA_CHAIR_KEY,"")
			if World.RESIDENT_GOALS.TEA_CHAIRS.has(choice):seats[choice]=true
			if seats.size()==World.RESIDENT_GOALS.TEA_CHAIRS.size():break
		data.chacha_tea_chairs=seats
	if world.player_region(route_actor)==World.REGIONS.HOME:
		var sheep_corner:=0
		for resident:Dictionary in world.state.players.values():
			sheep_corner|=int(resident.get(World.RESIDENT_GOALS.SHEEP_SHELTER_KEY,0))
			if sheep_corner==World.RESIDENT_GOALS.SHEEP_COMFORT_MASK:break
		data.sheep_comfort_fixtures=sheep_corner
		data.aru_bench_open=not data.get("aru_bench_scene",{}).is_empty()
	# T066 N06-1: only the viewer's own first-feed time, only at home (drives a local chicken approach).
	if world.player_region(route_actor)==World.REGIONS.HOME and world.state.players[route_actor].has(World.RESIDENT_GOALS.CHICKEN_FED_KEY):
		data.own_mianmian_feed_time=float(world.state.players[route_actor][World.RESIDENT_GOALS.CHICKEN_FED_KEY])
	# N06-4: same idea for the quiet sheep watch; only the viewer's own time, only at home.
	if world.player_region(route_actor)==World.REGIONS.HOME and world.state.players[route_actor].has(World.RESIDENT_GOALS.SHEEP_STEP_KEY):
		data.own_mianmian_step_time=float(world.state.players[route_actor][World.RESIDENT_GOALS.SHEEP_STEP_KEY])
	data.own_sheep_corner=int(world.state.players[route_actor].get(World.RESIDENT_GOALS.SHEEP_SHELTER_KEY,0))
	data.own_chacha_tea_chair=str(world.state.players[route_actor].get(World.RESIDENT_GOALS.TEA_CHAIR_KEY,""))
	data.own_chacha_tea_setup=str(world.state.players[route_actor].get(World.RESIDENT_GOALS.TEA_SETUP_KEY,""))
	data.own_diandian_mural=World.RESIDENT_GOALS.mural_contributed(world.state,route_actor)
	data.own_diandian_invites=world.state.players[route_actor].get(World.RESIDENT_GOALS.PAINT_INVITES_KEY,[]).duplicate()
	data.own_xinghe_growth=world.state.players[route_actor].get(World.RESIDENT_GOALS.GROWTH_KEY,{}).duplicate()
	data.own_xinghe_growth_log=world.state.players[route_actor].get(World.RESIDENT_GOALS.GROWTH_LOG_KEY,{}).duplicate()
	data.own_luoluo_address=World.RESIDENT_GOALS.address_progress(world.state.players[route_actor])
	data.own_luoluo_postcard_clues=World.RESIDENT_GOALS.postcard_clues(world.state.players[route_actor])
	data.own_luoluo_future_note=World.RESIDENT_GOALS.future_note(world.state.players[route_actor])
	data.own_guest_room=world.state.players[route_actor].get(World.RESIDENT_GOALS.GUEST_ROOM_KEY,false)
	data.own_inn_cracks=int(world.state.players[route_actor].get(World.WARM_SPRINGS.CRACK_KEY,0))
	data.own_guest_cloth=world.state.players[route_actor].get(World.RESIDENT_GOALS.GUEST_CLOTH_KEY,false)
	data.own_wangan_house=world.state.players[route_actor].get(World.WANGAN_MEMORY.KEY,false)
	data.own_wangan_weir=int(world.state.players[route_actor].get(World.WANGAN_MEMORY.WEIR_KEY,0))
	data.own_wangan_log=world.state.players[route_actor].get(World.WANGAN_MEMORY.LOG_KEY,false)
	data.own_lingpopo_bell=int(world.state.players[route_actor].get(World.RESIDENT_GOALS.BELL_INSPECT_KEY,0))
	data.own_forest_mushroom=World.FOREST_MUSHROOM.view(world.state,world.state.players[route_actor]) # C12 D05：本人的林間委託階段。
	data.own_bobo_rest_kit=int(world.state.players[route_actor].get(World.RESIDENT_GOALS.REST_KIT_KEY,0))
	data.own_milu_recipe_pages=int(world.state.players[route_actor].get(World.RESIDENT_GOALS.RECIPE_PAGE_KEY,0))
	data[World.MILU_SUPPER.VIEW_KEY]=World.MILU_SUPPER.view(world.state.players[route_actor])
	data.own_achao_route_marks=int(world.state.players[route_actor].get(World.RESIDENT_GOALS.ROUTE_KEY,0))
	data.own_crop_sketches=world.state.players[route_actor].get(World.RESIDENT_GOALS.SKETCH_KEY,{}).duplicate()
	data.own_market=world.market_view(route_actor) # T071：攤位庫存、裝飾、錢箱、結算只給本人。
	if data.region_id==World.REGIONS.HOME:
		data.market_plaza=_shared("market_plaza",func():
			if not World.MARKET.unlocked(world.state):return {}
			var carts:Dictionary={}
			for obj:Dictionary in world.home_layer("objects").values():
				if obj.get("type")==World.INDUSTRY.COAST_CART and obj.get("market_cart_open",false):carts[obj.owner]=true
			return World.MARKET_DECOR.plaza_display(world.state,carts))
	data.own_spring_garden=World.SPRING_GARDEN.view(world.state,route_actor)
	data[World.SEA_BREEZE_FAIR.VIEW_KEY]=World.SEA_BREEZE_FAIR.view(world.state,route_actor)
	data[World.AUTUMN_FEAST.VIEW_KEY]=World.AUTUMN_FEAST.view(world.state,route_actor)
	data[World.WARM_LANTERN_NIGHT.VIEW_KEY]=World.WARM_LANTERN_NIGHT.view(world.state,route_actor)
	data[World.BEACH_TREASURE.VIEW_KEY]=World.BEACH_TREASURE.view(world.state,route_actor)
	if data.region_id==World.PARTY_CART.REGION:data[World.PARTY_CART.VIEW_KEY]=World.PARTY_CART.view(world.state,route_actor)
	if data.region_id==World.REGIONS.HOME:data[World.LANTERN_STROLL.VIEW_KEY]=World.LANTERN_STROLL.view(world.state,route_actor)
	data[World.LOST_CHICKS.VIEW_KEY]=World.LOST_CHICKS.view(world.state,route_actor)
	data[World.COOKING_RELAY.VIEW_KEY]=World.COOKING_RELAY.view(world.state,route_actor,world.active_tokens)
	data.own_summer_market=world.summer_market_view(route_actor) # C12 D14：夏季市集試吃與食譜狀態只給本人。
	data.own_harvest=world.harvest_view(route_actor) # T071：豐收接力本人摘要與紀念票。
	data.own_fish_meet=world.fish_meet_view(route_actor) # T071：河岸釣魚會本人摘要與紀念票。
	data.own_showcase=world.showcase_view(route_actor) # T071：家園布置題本人摘要與紀念票。
	# T071：紀念票餘額、兌換目錄與紀錄只給本人。專服共用全島的擺設計數。
	var souvenir_placements:Variant=null
	if _bcast_active:souvenir_placements=_shared("souvenir_placements",func():return World.SOUVENIR.placed_by_owner(world.state))
	data.own_souvenir=world.souvenir_view(route_actor,souvenir_placements)
	data[World.MEMORY_EXHIBIT.OWN_KEY]=World.MEMORY_EXHIBIT.own(world.state,route_actor) # 第 40 章記憶展：本人看過哪些、分水與木牌狀態。
	if _bcast_active:
		var crop_summaries:Dictionary=_shared("crop_summaries",func():return world.crop_summaries(peers.values()))
		data.own_crop_summary=crop_summaries[route_actor]
	else:
		data.own_crop_summary=world.own_crop_summary(route_actor)
	data.festival_story=_shared("festival_story",func():return world.festival_story_view())
	data.ferry_story_recap=World.ISLAND_STORY_RECAP.build(data,world.state.players[route_actor].get("ferry_recap_seen",World.ISLAND_STORY_RECAP.NO_MARKER))
	var resident:Dictionary=world.state.players[route_actor]
	data.island_news={"completed":int(_shared("island_news_mask",func():return world.island_news_project_mask())),"seen":int(resident.get("news_seen",0)),
		"notes_unread":World.ISLAND_NOTES.unread(world.state,resident),"note_revision":int(_shared("island_note_revision",func():return World.ISLAND_NOTES.revision(world.state))),
		"returning":returning_peers.get(id,false)}
	data.erase("island_note_revision")
	data.resident_participation=preload("res://scripts/resident_story_catalog.gd").participation(world.state,route_actor)
	var trade: Dictionary=world.trade_view(route_actor)
	if not trade.is_empty():trade.partner=_public_actor(trade.partner)
	data.own_trade=trade
	if data.has("public_fund"):data.public_fund.own_given=int(world.state.public_fund.contributors.get(route_actor,0))
	for dish in World.COMMUNITY.DISHES:
		if data.get("community",{}).has(dish):
			data.community[dish].claimed_own=world.state.community[dish].claimed.has(route_actor)
	data.mine_survey={"own_record":World.MINE_SURVEY.own_record(world.state,route_actor)}
	data.tea_ceramics={"own_record":World.TEA_CERAMICS.own_record(world.state,route_actor)}
	data.flower_nursery.own=World.FLOWER_NURSERY.own_view(world.state,route_actor)
	_project_salt(data,route_actor)
	data.own_construction_undo=world.undo_summary(route_actor).duplicate(true)
	# T055: daily order board (status, deadlines, gating) for the recipient only.
	var order_channels:Array[String]=["village"]
	if data.get("wangan_star_walk",false):order_channels.append("dock")
	if data.region_id==World.REGIONS.LANYANG and data.get("lanyang_life",{}).get("repaired",false):
		order_channels.append("lanyang")
	var order_boards:Dictionary=world.order_boards(route_actor,order_channels)
	data.order_board=order_boards.get("village",{})
	if "dock" in order_channels:data.dock_order_board=order_boards.get("dock",{})
	if "lanyang" in order_channels:data.lanyang_order_board=order_boards.get("lanyang",{})
	var route_region:String=world.player_region(route_actor)
	data.mine_auto_freight={"route":world.state.mine_auto_freight.routes.get(route_actor,{}).duplicate(true),
		"sources":World.MINE_FREIGHT.own_chests(world.state.regions[route_region].objects,route_actor) if route_region in World.MINE_AUTO_FREIGHT.REGIONS else [],
		"status":World.MINE_AUTO_FREIGHT.status(world.state,route_actor)}
	if data.has("mine_freight"):
		var token: String=peers[id]
		data.mine_freight["own_job"]=world.state.mine_freight.jobs.get(token,{}).duplicate(true)
		data.mine_freight["own_home_chests"]=World.MINE_FREIGHT.own_chests(world.state.objects,token)
	if data.has("bobo_workshop"):
		var token: String=peers[id]
		data.bobo_workshop.own_job=world.state.bobo_workshop.jobs.get(token,{}).duplicate(true)
		data.bobo_workshop.own_done=world.state.bobo_workshop.done.get(token,false)
	if data.has("station_life"):
		data.station_life.own_story=World.STATION_LIFE.story(world.state,peers[id]).duplicate(true)
	var player_id:String=String(peers[id]).sha256_text().left(16)
	data.players[player_id]["travel_book"]=world.state.players[peers[id]].travel_book.duplicate(true)
	data["own_postcards"]=World.POSTCARDS.earned(world.state.players[peers[id]])
	if world.state.players[peers[id]].get(World.CHAPTER_ONE.PERSONAL_START,false):
		data.players[player_id][World.CHAPTER_ONE.PERSONAL_START]=true
	for obj in data.objects.values():
		if obj.type in World.PRIVATE_BOXES and obj.owner!=player_id:
			if not obj.get("guest_withdraw",false):obj.items={}
			obj.erase("freight_id")
			# Material-source identity of someone else's private chest is a
			# capability hint; only the owner may see it (protocol 40).
			obj.erase("box_id")
			obj.locked=true
	for visible_id in data.players:
		if visible_id!=player_id:
			data.players[visible_id].erase("inventory")
			data.players[visible_id].erase(World.MILL_RESTORATION.JOB)
			data.players[visible_id].erase(World.SAVE_SCHEMA.FLOUR_STALL_KEY)
			data.players[visible_id].erase(World.SAVE_SCHEMA.SUGAR_STALL_KEY)
			data.players[visible_id].erase("mud_alcove")
			data.players[visible_id].erase("mud_duel")
			data.players[visible_id].erase(World.GUARDIAN_FIELD)
			data.players[visible_id].erase(World.SHY_FIELD)
			data.players[visible_id].erase(World.CRAB_FIELD)
			data.players[visible_id].erase(World.PORTER.FIELD)
			data.players[visible_id].erase(World.MEADOW.FIELD)
			data.players[visible_id].erase("crop_care")
			data.players[visible_id].erase("collection_donations")
			data.players[visible_id].erase("collection_acquired")
			data.players[visible_id].erase("fox_tracks")
			data.players[visible_id].erase("squirrel_day")
			data.players[visible_id].erase("seal_seen")
			data.players[visible_id].erase("windbell_deer_seen")
			data.players[visible_id].erase("hedgehog_visit_day")
			data.players[visible_id].erase("hedgehog_observed_day")
			data.players[visible_id].erase("fox_hint_until")
			for field:String in World.Rabbit.PET_FIELDS:
				if data.players[visible_id].has(field):
					var companion:Dictionary=data.players[visible_id][field]
					var visible_pet:={"following":companion.following}
					if field==World.Dog.FIELD or field==World.Cat.FIELD:
						visible_pet.last_play=companion.get("last_play","")
					if field==World.Cat.FIELD:
						visible_pet.last_pet=companion.get("last_pet",-30.0)
					data.players[visible_id][field]=visible_pet
			data.players[visible_id].erase("coins")
			data.players[visible_id].erase("orders")
			data.players[visible_id].erase(World.WARM_SPRINGS.WARMTH_FIELD)
			data.players[visible_id].erase(World.MEAL_BUFF.FIELD)
			data.players[visible_id].erase(World.MEAL_BUFF.FRAC_FIELD)
	var interest:Rect2i=plan.interest
	if plan.home:
		data.view_interest=true
		data[ViewProjection.ADVERT]=ViewProjection.MAX_LEVEL
		if plan.tracked:
			for key:String in data.damage.keys():
				if not interest.has_point(World.cell(key)):data.damage.erase(key)
			var level:int=plan.level
			if level<=0:_project_crop_growth(data.crops,interest,player_id)
			elif plan.full:ViewProjection.mark_full(data,Rect2i(Vector2i.ZERO,World.SIZE),level)
			elif early:ViewProjection.mark_projected(data,interest,level)
			else:ViewProjection.project(data,interest,player_id,level)
	data.tool_actions=tool_action_view(str(data.region_id),interest,player_id,data.players)
	data.map_signals=map_signal_view(str(data.region_id),Time.get_ticks_msec())
	if not solo_rest_enabled:data.night_vote=night_vote_view(id)
	_t090_end("personal",personal_started)
	return data

static func _project_crop_growth(crops:Dictionary,interest:Rect2i,own:String) -> void:
	for key:String in crops:
		var crop:Dictionary=crops[key]
		if crop.get("owner","")==own or crop.get("kind","").is_empty() or interest.has_point(World.cell(key)):continue
		crop.growth=CropSprites.stage_growth(crop)

func _send_wire_snapshot(id:int,data:Dictionary,player_id:String,use_delta:bool,cell_deltas:=false) -> void:
	var encode_started:=_t090_begin()
	var packet:=data
	var base:Dictionary=_snapshot_bases.get(id,{})
	var new_keyframe:=false
	if use_delta:
		# A complete and a projected packet never share a base, nor do two levels:
		# the cell patch between them would list every far cell.
		new_keyframe=(base.is_empty() or int(base.count)>=SnapshotWire.KEYFRAME_INTERVAL or base.data.region_id!=data.region_id
			or base.data.get(ViewProjection.FULL)!=data.get(ViewProjection.FULL)
			or base.data.get(ViewProjection.LEVEL)!=data.get(ViewProjection.LEVEL))
		if new_keyframe:
			_snapshot_frame+=1
			packet=SnapshotWire.keyframe(data,_snapshot_frame)
		else:
			packet=SnapshotWire.difference(data,base.data,int(base.frame),cell_deltas)
	packet=SnapshotWire.encode(packet)
	_t090_end("encode",encode_started)
	var send_started:=_t090_begin()
	receive_state.rpc_id(id,packet,player_id)
	_t090_end("send",send_started)
	if not use_delta:return
	if new_keyframe:
		_snapshot_bases[id]={"data":data.duplicate(true),"frame":_snapshot_frame,"count":1}
	else:
		base.count+=1

func _change_map_signal(id:int,cell:Vector2i,kind:String,now:int) -> void:
	if kind=="cancel":
		map_signals.erase(id)
		_send_notice(id,"已取消你的地圖標記。",true)
		return
	var token:String=peers[id]
	var person:Dictionary=world.state.players[token]
	var region:String=world.player_region(token)
	var distance:=Vector2(person.x,person.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))
	if not Rect2i(Vector2i.ZERO,World.SIZE).has_point(cell) or not World.land(cell,region) or distance>4.0:
		_send_notice(id,"請瞄準附近的地面再放標記。",false)
		return
	map_signals[id]={"region":region,"cell":cell,"kind":kind,"until":now+MAP_SIGNAL_MS}
	_send_notice(id,"已標記「%s」，同區域的玩家可在周邊地圖查看。"%MAP_SIGNALS[kind],true)

func map_signal_view(region:String,now:int) -> Array:
	var visible:Array=[]
	for id in map_signals.keys():
		var entry:Dictionary=map_signals[id]
		var remaining:int=entry.until-now
		if remaining<=0:
			map_signals.erase(id)
		elif entry.region==region:
			visible.append({"cell":entry.cell,"kind":entry.kind,"remaining":remaining})
	return visible

func _tool_action_now() -> int:
	if tool_action_clock.is_valid():return int(tool_action_clock.call())
	return Time.get_ticks_msec()

## Records one confirmed hand-tool success. Only the public actor id, the tool
## name and the target cell (plus the destination for move_object) are kept;
## Gather pickup also carries public ground item kinds, without quantities.
func _record_tool_action(token:String,action:String,p:Vector2i,extra:String,pickup_items:Array=[],reel:Dictionary={}) -> void:
	var now:=_tool_action_now()
	_prune_tool_actions(now)
	tool_action_counter+=1
	var event:={"n":tool_action_counter,"actor":_public_actor(token),"tool":action,"x":p.x,"y":p.y}
	if action=="move_object":
		var to:=extra.split(",")
		if to.size()==2 and to[0].is_valid_int() and to[1].is_valid_int():
			event.tx=int(to[0])
			event.ty=int(to[1])
	if action=="gather_pickup":event.items=pickup_items
	if action=="fish_reel":event.merge(reel)
	tool_actions.append({"at":now,"region":world.player_region(token),"event":event})
	while tool_actions.size()>TOOL_ACTION_MAX:tool_actions.pop_front()

func _prune_tool_actions(now:int) -> void:
	while not tool_actions.is_empty() and now-int(tool_actions[0].at)>TOOL_ACTION_TTL_MS:tool_actions.pop_front()

func _forget_tool_actions(actor:String) -> void:
	tool_actions=tool_actions.filter(func(entry):return entry.event.actor!=actor)

## Same-region, unexpired events for one recipient (fresh copies).
func tool_action_view(region:String,interest:=Rect2i(),own:="",players:Dictionary={}) -> Dictionary:
	_prune_tool_actions(_tool_action_now())
	var events:Array=[]
	for entry in tool_actions:
		if entry.region!=region:continue
		var event:Dictionary=entry.event
		if interest.has_area() and event.actor!=own:
			var player:Dictionary=players.get(event.actor,{})
			var source:=Vector2i(floori(float(player.x)),floori(float(player.y))) if not player.is_empty() else Vector2i(-1000,-1000)
			var target:=Vector2i(int(event.x),int(event.y))
			var destination:=Vector2i(int(event.tx),int(event.ty)) if event.has("tx") and event.has("ty") else target
			if not interest.has_point(source) and not interest.has_point(target) and not interest.has_point(destination):continue
		events.append(event.duplicate())
	var payload:Dictionary={"epoch":tool_action_epoch,"events":events}
	if interest.has_area():payload.cursor=tool_action_counter
	return payload

## Protocol 45 per-recipient salt projection: own view (built from the live
## beimen object layer, whatever region the recipient is in) and the `mine`
## flags of the recipient's own private lot / apprentice shift only.
func _project_salt(data:Dictionary,token:String) -> void:
	var salt=data.get("salt_pan")
	if not salt is Dictionary:return
	var beimen:Dictionary=world.state.objects if world._region==World.SALT_PAN.REGION else world.state.regions[World.SALT_PAN.REGION].objects
	var own:Dictionary=World.SALT_PAN.own_view(world.state,token,beimen,float(world.state.time)).duplicate(true)
	salt.own=own
	var lots=salt.get("lots")
	if lots is Array:
		for i in lots.size():
			if lots[i] is Dictionary:lots[i].mine=false
		var lot:int=int(own.get("lot",-1))
		if lot>=0 and lot<lots.size() and lots[lot] is Dictionary:lots[lot].mine=true
	var apprentice=salt.get("apprentice")
	if apprentice is Dictionary:
		var shift=own.get("apprentice",{})
		apprentice.mine=shift is Dictionary and shift.get("mine",false)==true

@rpc("authority","call_remote","reliable",3)
func receive_state(data:Dictionary,player_id:String) -> void:
	if data.has(SnapshotWire.COMPRESSED):
		data=SnapshotWire.decode(data)
		if data.is_empty():return
	if data.has(SnapshotWire.SET):
		data=SnapshotWire.restore(data,_received_snapshot_base,_received_snapshot_frame)
		if data.is_empty():return
	elif data.has(SnapshotWire.FRAME):
		var frame:Variant=data[SnapshotWire.FRAME]
		if not frame is int or frame<=_received_snapshot_frame or not data.get("players") is Dictionary:return
		data=data.duplicate()
		data.erase(SnapshotWire.FRAME)
		_received_snapshot_frame=frame
		_received_snapshot_base=data.duplicate(true)
	else:
		_received_snapshot_base.clear()
		_received_snapshot_frame=0
	# Only a packet that decoded and restored reaches the far-cell cache.
	data=_view_cache.compose(data,player_id)
	snapshot=data
	own_id=player_id
	changed.emit(data,player_id)

func _send_notice(id:int,message:String,success:bool) -> void:
	if id==1:receive_notice(message,success)
	elif _can_send(id):receive_notice.rpc_id(id,message,success)

func _can_send(id:int) -> bool:
	if shutting_down or not multiplayer.get_peers().has(id):return false
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		var socket:WebSocketPeer=multiplayer.multiplayer_peer.get_peer(id)
		return socket!=null and socket.get_ready_state()==WebSocketPeer.STATE_OPEN
	var transport:=multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport==null:return false
	var remote:=transport.get_peer(id)
	return remote!=null and remote.get_state()==ENetPacketPeer.STATE_CONNECTED and remote.get_channels()>0

@rpc("authority","call_remote","reliable",2)
func receive_notice(message:String,success:bool) -> void:
	notice.emit(message,success)

@rpc("authority","call_remote","reliable",2)
func receive_emote(actor:String,region:String,id:String) -> void:
	if EMOTES.has(id):emote_received.emit(actor,region,EMOTES[id])
	elif TEA_SET_EMOTES.has(id):emote_received.emit(actor,region,TEA_SET_EMOTES[id])

static func chat_text(raw:String) -> String:
	return World.ISLAND_NOTES.clean(raw)

@rpc("authority","call_remote","reliable",2)
func receive_island_chat(region:String,sender:String,message:String) -> void:
	chat_received.emit(region,sender,message)

func _reply_island_note(id:int,sequence:int,success:bool) -> void:
	if id==1:receive_island_note_result(sequence,success)
	elif _can_send(id):receive_island_note_result.rpc_id(id,sequence,success)

@rpc("authority","call_remote","reliable",3)
func receive_island_note_result(sequence:int,success:bool) -> void:
	island_note_result.emit(sequence,success)

func shutdown() -> bool:
	# A decided admission must recover before any subsequent world write. Quitting
	# is allowed, retaining its journal for the next server start.
	if not admission_recovery_required and world!=null and not world.save():
		notice.emit("最後一次保存失敗。世界仍開著，可以重試保存。",false)
		return false
	shutting_down=true
	blueprint_welcomed=false
	multiplayer.multiplayer_peer.close()
	peers.clear()
	_snapshot_bases.clear()
	_view_interests.clear()
	_view_layers.clear()
	_view_seeds.clear()
	_view_cache.reset()
	_sent_view_interest=Vector2i.ZERO
	_sent_view_interest_epoch=-1
	_sent_view_extra=""
	returning_peers.clear()
	solo_rest_enabled=false
	solo_motion={}
	night_vote.clear()
	controller_holds.clear()
	map_signals.clear()
	blueprint_quote_stamps.clear()
	blueprint_apply_stamps.clear()
	identities.clear()
	identity_requests.clear()
	identity_rejected.clear()
	if is_instance_valid(directory_request):
		directory_request.queue_free()
		directory_request = null
	if is_instance_valid(storage_report_request):
		storage_report_request.queue_free()
		storage_report_request=null
	directory_invite.clear()
	world=null
	write_guard.release()
	return true

@rpc("any_peer", "call_remote", "reliable")
func register_authenticated(version: int, ticket: String, invite: String) -> void:
	if not multiplayer.is_server() or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not pending.has(id) or identity_requests.has(id) or identity_rejected.has(id) or peers.has(id):
		return
	if version != PROTOCOL:
		reject_identity(id, VERSION_MISMATCH_NOTICE, "VERSION_MISMATCH")
		return
	if membership == null or ticket.is_empty() or ticket.length() > 256 or invite.length() > 64 or not accepting:
		reject_identity(id, "需要相容版本與有效登入。")
		return
	identity_request(id, "redeem", {"ticket": ticket}, invite)

func identity_request(id: int, endpoint: String, payload: Dictionary, invite: String = "") -> void:
	var request := HTTPRequest.new()
	request.timeout = 4.0
	request.max_redirects = 0
	request.body_size_limit = 8192
	if identity_tls != null:
		request.set_tls_options(identity_tls)
	add_child(request)
	connection_serial += 1
	var serial := connection_serial
	identity_requests[id] = serial
	payload.world_id = identity_world
	request.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if world == null or identity_requests.get(id) != serial or not _can_send(id):
			return
		identity_requests.erase(id)
		if admission_recovery_required:return
		var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and status == 200 else null
		if not valid_identity_claim(data):
			reject_identity(id, "帳號驗證失敗，請重新登入後再加入。")
			return
		if endpoint == "validate":
			var previous: Dictionary = identities.get(id, {})
			if previous.get("account_id") != data.account_id or previous.get("admission_id") != data.admission_id:
				reject_identity(id, "登入已失效。")
			else:
				identities[id] = data
				if previous.get("display_name") != data.display_name and membership.rename(data.account_id, data.display_name):
					mark_directory_dirty()
			return
		if not pending.has(id) or peers.has(id) or not accepting:
			return
		for claim in identities.values():
			if claim.account_id == data.account_id:
				reject_identity(id, "此帳號已在世界內。")
				return
		var committed := commit_identity_admission(id,data,invite)
		if not committed.ok:
			reject_identity(id,committed.message,committed.code)
			return
		identities[id] = data
		_attach_registered(id,committed.character,committed.returning)
		mark_directory_dirty()
		for peer_id in identities:
			send_membership(peer_id)
	, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + identity_secret])
	if request.request(identity_url + "/v1/" + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload)) != OK:
		request.queue_free()
		identity_requests.erase(id)
		reject_identity(id, "登入服務無法連線。")

func valid_identity_claim(data: Variant) -> bool:
	return data is Dictionary and data.get("ok") == true and data.get("world_id") == identity_world and (
		Membership.valid_text(data.get("account_id"), 128) and Membership.valid_text(data.get("display_name"), 24) and
		Membership.valid_text(data.get("admission_id"), 256) and valid_identity_expiry(data.get("expires")))

static func valid_identity_expiry(expires: Variant) -> bool:
	return (expires is float or expires is int) and is_finite(expires) and expires > Time.get_unix_time_from_system()

func reject_identity(id: int, message: String, code: String = "JOIN_DENIED") -> void:
	if pending.has(id):
		identity_rejected[id] = true
	if _can_send(id):
		receive_identity.rpc_id(id, {"ok": false, "operation": "join", "message": message, "code":code})
		_send_notice(id, message, false)
	if identities.has(id):
		_peer_left(id)
		multiplayer.multiplayer_peer.disconnect_peer(id)

func send_membership(id: int) -> void:
	var info := membership.read(identities[id].account_id)
	info.erase("character")
	info["ok"] = true
	info["operation"] = "membership"
	if _can_send(id):
		receive_identity.rpc_id(id, info)

func request_invite_rotation(ttl: int = 3600) -> void:
	manage_invite.rpc_id(1, "rotate", ttl)

func request_invite_revocation() -> void:
	manage_invite.rpc_id(1, "revoke", 0)

func request_admin_change(target_id: String, enabled: bool) -> void:
	manage_invite.rpc_id(1, "admin:" + target_id, int(enabled))

func request_member_kick(target_id: String) -> void:
	manage_invite.rpc_id(1, "kick:" + target_id, 0)

func request_member_block(target_id: String, enabled: bool) -> void:
	manage_invite.rpc_id(1, "block:" + target_id, int(enabled))

func request_public_builder(target_id: String, enabled: bool) -> void:
	manage_invite.rpc_id(1, "public_build:" + target_id, int(enabled))

func _disconnect_member(account: String, kick_actor := "") -> bool:
	if account.is_empty(): return false
	for peer_id in identities.keys():
		if identities[peer_id].account_id != account: continue
		if not kick_actor.is_empty() and not membership.record_kick(kick_actor, account): return false
		_peer_left(peer_id)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return true
	return false

func _block_member(id: int, target_id: String, enabled: bool) -> void:
	var account := membership.set_blocked(identities[id].account_id, target_id, enabled)
	if not account.is_empty():
		if enabled: _disconnect_member(account)
		for peer_id in identities:
			if identity_allows_play(peer_id): send_membership(peer_id)
	receive_identity.rpc_id(id, {"ok": not account.is_empty(), "operation": "block_member", "enabled": enabled})

func _manage_admin(id: int, target_id: String, enabled: bool) -> void:
	var success := membership.set_admin(identities[id].account_id, target_id, enabled)
	if success:
		mark_directory_dirty()
		for peer_id in identities:
			if identity_allows_play(peer_id):
				send_membership(peer_id)
				if peers.has(peer_id):_send_snapshot(peer_id)
	receive_identity.rpc_id(id, {"ok": success, "operation": "admin_change", "enabled": enabled})

@rpc("any_peer", "call_remote", "reliable")
func manage_invite(operation: String, ttl: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or membership == null or not accepting or not identity_allows_play(id) or not _can_send(id):
		return
	# Use the existing passport RPC so older clients keep the same RPC table.
	if operation.begins_with("admin:") and ttl in [0, 1]:
		_manage_admin(id, operation.trim_prefix("admin:"), ttl == 1)
		return
	if operation.begins_with("kick:") and ttl == 0:
		var actor: String = identities[id].account_id
		var target := membership.managed_account(actor, operation.trim_prefix("kick:"))
		var success := _disconnect_member(target, actor)
		if success:
			for peer_id in identities:
				if membership.is_owner(identities[peer_id].account_id) and identity_allows_play(peer_id): send_membership(peer_id)
		receive_identity.rpc_id(id, {"ok": success, "operation": "kick_member"})
		return
	if operation.begins_with("block:") and ttl in [0, 1]:
		_block_member(id, operation.trim_prefix("block:"), ttl == 1)
		return
	if operation.begins_with("public_build:") and ttl in [0, 1]:
		var success := membership.set_public_builder(identities[id].account_id, operation.trim_prefix("public_build:"), ttl == 1)
		if success:
			for peer_id in identities:
				if identity_allows_play(peer_id):
					send_membership(peer_id)
					if peers.has(peer_id):_send_snapshot(peer_id)
		receive_identity.rpc_id(id, {"ok":success,"operation":"public_builder","enabled":ttl==1})
		return
	if operation not in ["rotate", "revoke"]:
		return
	var account: String = identities[id].account_id
	var result: Dictionary = membership.rotate(account, ttl) if operation == "rotate" else {"ok": membership.revoke(account)}
	result["operation"] = operation
	if result.ok: send_membership(id)
	if result.ok and not directory_address.is_empty():
		directory_invite = {"account": account, "operation": operation, "code": result.get("code", "")}
		result.erase("code")
		result["synced"] = false
		result["message"] = "已儲存，目錄同步中。"
		mark_directory_dirty()
	receive_identity.rpc_id(id, result)

@rpc("authority", "call_remote", "reliable")
func receive_identity(info: Dictionary) -> void:
	identity_status.emit(info)

func mark_directory_dirty() -> void:
	if directory_address.is_empty() or shutting_down or admission_recovery_required:
		return
	directory_dirty = true
	directory_retry = 0.0

func _tick_storage_report(dt:float) -> void:
	if membership==null or shutting_down:return
	var state:="running"
	if admission_recovery_required:state="recovery_required"
	elif storage_paused or not world.save_error.is_empty():state="save_failed"
	elif not accepting:state="paused"
	if state!=storage_report_state:
		storage_report_state=state
		storage_report_delay=0.0
	storage_report_delay-=dt
	if storage_report_request!=null or storage_report_delay>0.0:return
	storage_report_delay=10.0
	var request:=HTTPRequest.new()
	request.timeout=4.0
	request.max_redirects=0
	request.body_size_limit=8192
	if identity_tls!=null:request.set_tls_options(identity_tls)
	add_child(request)
	storage_report_request=request
	request.request_completed.connect(func(_result:int,_status:int,_headers:PackedStringArray,_body:PackedByteArray)->void:
		storage_report_request=null
		request.queue_free()
	,CONNECT_ONE_SHOT)
	var headers:=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+identity_secret])
	var body:=JSON.stringify({"world_id":identity_world,"state":state,"last_saved":world.last_saved_at})
	if request.request(identity_url+"/v1/world-storage",headers,HTTPClient.METHOD_POST,body)!=OK:
		storage_report_request=null
		request.queue_free()

func tick_directory(dt: float) -> void:
	if directory_address.is_empty() or shutting_down or admission_recovery_required:
		return
	directory_clock += dt
	directory_retry -= dt
	if directory_clock >= 10.0:
		directory_dirty = true
	if directory_dirty and directory_request == null and directory_retry <= 0:
		publish_directory()

func publish_directory() -> void:
	if admission_recovery_required:return
	var online: Array = []
	for claim in identities.values():
		online.append(claim.account_id)
	var data := membership.publish_snapshot(online)
	if data.is_empty():
		directory_retry = 2.0
		return
	data.merge({"world_id": identity_world, "address": directory_address, "protocol": PROTOCOL,
		"mode": "冒險" if world.state.get("world_mode")=="adventure" else "生活"})
	directory_dirty = false
	directory_clock = 0.0
	var request := HTTPRequest.new()
	request.timeout = 4.0
	request.max_redirects = 0
	request.body_size_limit = 8192
	if identity_tls != null:
		request.set_tls_options(identity_tls)
	add_child(request)
	directory_request = request
	var invitation := directory_invite
	request.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		directory_request = null
		if shutting_down or world == null or admission_recovery_required:
			return
		var reply = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and status == 200 else null
		if not reply is Dictionary or reply.get("ok") != true or reply.get("revision") != data.revision:
			directory_dirty = true
			directory_retry = 2.0
			return
		if not invitation.is_empty() and is_same(invitation, directory_invite):
			directory_invite = {}
			for id in identities:
				if identities[id].account_id != invitation.account or not identity_allows_play(id) or not _can_send(id):
					continue
				var response := {"ok": true, "synced": true, "operation": invitation.operation,
					"message": "目錄已同步。", "generation": data.invite.generation}
				if invitation.operation == "rotate" and data.invite.expires > Membership.now():
					var encoded := Marshalls.raw_to_base64(identity_world.to_utf8_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
					response["code"] = "TI1.%s.%s" % [encoded, invitation.code]
					response["expires"] = data.invite.expires
				receive_identity.rpc_id(id, response)
	, CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + identity_secret])
	if request.request(identity_url + "/v1/publish", headers, HTTPClient.METHOD_POST, JSON.stringify(data)) != OK:
		request.queue_free()
		directory_request = null
		directory_dirty = true
		directory_retry = 2.0
