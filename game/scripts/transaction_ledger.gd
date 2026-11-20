extends RefCounted
## T015 persistent transaction / economy audit journal (server-only).
##
## NOT the same thing as `player.receipts` (per-player request dedupe, 128 FIFO,
## unchanged) nor the 200-entry container display log the plan mentions (ch.22).
##
## Save root `state.ledger` (optional, no save VERSION bump; absent in every
## older save and created lazily by the first journaled commit):
##   {"seq":int, "dropped":int, "entries":[committed...], "rejected":[rejected...]}
## seq      last sequence number handed out (shared by both lists, never reused)
## dropped  committed entries rotated out of `entries` so far (FIFO)
##
## Committed entry (written in the SAME state as the change and the request
## receipt, i.e. inside the same atomic save(); a failed save rolls all three back):
##   seq, c (state.committed after this commit), t (world time), ok:true,
##   act (action), kind (KINDS), by (actor pseudonym), rid (request digest),
##   d {pid:{"coins":delta,"items":{item:delta}}}   only non-zero deltas
##   box [{"r":region,"cell":"x,y","type":object type,["owner":pid],"items":{item:delta}}]
##   [trunc:true] when a bound below cut the deltas (never expected in play)
## Rejected entry (bounded separately so rejection spam can never evict commits):
##   seq, t, ok:false, act, by, rid, reason (player-facing message, cut to 48)
##
## Privacy: pid = sha256(token)[0,16] (the pseudonym Session already publishes);
## rid = sha256(request_id)[0,24]. No raw token, no request text, no full
## inventory, no coin balances: only per-operation deltas.
##
## Journaling rule (diff of `before` vs committed state, so no action can be
## forgotten by a hand-maintained list): an entry is written when ANY coins
## changed, ANY object contents changed, ANOTHER player's inventory changed, the
## action is a trade action, or the actor LOST items (crafting, building,
## shipping, delivery, donation...). Pure self item gains (harvest, gather,
## fishing) are not economy transactions and are skipped, and so is pure
## self material spending of ROUTINE_ACTIONS (build/sow/feed).
## Scope: request commits only (World.act + World.apply_blueprint). step()
## settlements (market till, auto freight, conveyors, salt, livestock) and
## value held outside coins/inventory/object items are NOT journaled yet.

const STATE_KEY := "ledger"
const Industry=preload("res://scripts/industry.gd")
const Shipping=preload("res://scripts/shipping.gd")
const CropCatalog=preload("res://scripts/crop_catalog.gd")
const FIRST_SHOP_KEY:="xiaoli_first_trade"
## Retention: newest CAP committed entries and newest REJECT_CAP rejections.
## Kept small on purpose: step()/act() deep-copy the whole state every call.
const CAP := 256
const REJECT_CAP := 64
## In-memory rejections waiting for the next successful commit (World field).
const PENDING_CAP := REJECT_CAP
const PLAYERS_MAX := 8
const BOXES_MAX := 8
const ITEM_KINDS_MAX := 32
const ACT_MAX := 40
const REASON_MAX := 48
const TYPE_MAX := 32
const PID_LENGTH := 16
const RID_LENGTH := 24
const DELTA_MAX := 1000000000000.0
const KINDS := ["trade","container","transfer","sale","purchase","craft","consume"]
const COMMITTED_KEYS := ["seq","c","t","ok","act","kind","by","rid","d","box"]
const REJECTED_KEYS := ["seq","t","ok","act","by","rid","reason"]
const ROOT_KEYS := ["seq","dropped","entries","rejected"]
const PRIVATE_BOXES := ["private_chest","supply_box",Industry.ACORN_CABINET]
const TRADE_ACTIONS := ["trade_open","trade_edit","trade_confirm","trade_cancel"]
const CHEST_EXACT_MOVES := ["deposit_exact","withdraw_exact"]
const CHEST_MOVES := ["deposit","withdraw","deposit_half","withdraw_half","deposit_all","withdraw_all"] + CHEST_EXACT_MOVES
## Self-only material spending of these actions is not an economy transaction.
const ROUTINE_ACTIONS := ["build","build_area","seed","seed_area","nursery_sow","plant_tree","feed"]
## Actions whose REJECTIONS are journaled (committed entries never depend on
## this list; they come from the diff).
const ECONOMY_ACTIONS := ["trade_open","trade_edit","trade_confirm","trade_cancel",
	"buy","sell","donate","assemble",Industry.POT_RACK_PUT,Industry.POT_RACK_TAKE,Industry.COUNTER_PUT,Industry.COUNTER_TAKE,Industry.TEA_CABINET_PUT,Industry.TEA_CABINET_TAKE,Industry.SNACK_PUT,Industry.SNACK_TAKE] + CHEST_MOVES

static func fresh() -> Dictionary:
	return {"seq":0,"dropped":0,"entries":[],"rejected":[]}

static func pid(token: String) -> String:
	return token.sha256_text().left(PID_LENGTH)

static func rid(request_id: String) -> String:
	return request_id.sha256_text().left(RID_LENGTH)

static func is_economy_action(action: String) -> bool:
	return action in ECONOMY_ACTIONS or action.begins_with("ship") or action.begins_with("sell") or action.begins_with("buy") or action.contains("donate") or action=="blueprint"

static func _item_delta(a, b) -> Dictionary:
	var before_items: Dictionary = a if a is Dictionary else {}
	var after_items: Dictionary = b if b is Dictionary else {}
	if before_items == after_items:return {}
	var names: Dictionary = {}
	for item in before_items:names[str(item)] = true
	for item in after_items:names[str(item)] = true
	var keys: Array = names.keys()
	keys.sort()
	var out: Dictionary = {}
	for item in keys:
		var change := int(after_items.get(item, 0)) - int(before_items.get(item, 0))
		if change != 0:out[item] = change
	return out

static func _cap_items(items: Dictionary, entry: Dictionary) -> Dictionary:
	if items.size() <= ITEM_KINDS_MAX:return items
	entry.trunc = true
	var out: Dictionary = {}
	for item in items.keys().slice(0, ITEM_KINDS_MAX):out[item] = items[item]
	return out

static func _layers(s: Dictionary) -> Dictionary:
	# Home-oriented state: home objects at the root, regional ones under regions.
	var out: Dictionary = {"home": s.get("objects", {})}
	var regions = s.get("regions", {})
	if regions is Dictionary:
		for region in regions:
			var layer = regions[region]
			if layer is Dictionary and layer.get("objects") is Dictionary:out[region] = layer.objects
	return out

static func _held_items(obj:Variant)->Variant:
	if not obj is Dictionary:return null
	# T07: the tea table's set lives in a flag, not in `items`; count it so a put/take shows as a transfer.
	if obj.get("type")==Industry.BAMBOO_TEA_TABLE and Industry.has_tea_set(obj):
		var held:Dictionary=obj.get("items",{}).duplicate()
		held[Industry.TEA_SET]=1
		return held
	# T11: both shelf tiers count as one container so a put/take shows as a transfer.
	if obj.get("type")==Industry.TEA_SNACK_SHELF:
		var shelved:Dictionary={}
		for tier in Industry.SNACK_TIER_NAMES.size():
			var stored:Dictionary=Industry.snack_tier(obj,tier)
			for item in stored:shelved[item]=int(shelved.get(item,0))+int(stored[item])
		return shelved
	if obj.get("type")!=Industry.POT_RACK or not obj.has("rack_pots"):return obj.get("items")
	var items:Dictionary={}
	for flower:String in obj.rack_pots:
		if flower.is_empty():continue
		items[Industry.POT_RACK_EMPTY]=int(items.get(Industry.POT_RACK_EMPTY,0))+1
		if flower!=Industry.POT_RACK_EMPTY:items[flower]=int(items.get(flower,0))+1
	return items

## Economic difference of two HOME-oriented states. Pure; never mutates.
static func diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var players: Dictionary = {}
	var tokens: Dictionary = {}
	for token in before.get("players", {}):tokens[token] = true
	for token in after.get("players", {}):tokens[token] = true
	for token in tokens:
		var a: Dictionary = before.get("players", {}).get(token, {})
		var b: Dictionary = after.get("players", {}).get(token, {})
		var change: Dictionary = {}
		var coins := int(b.get("coins", 0)) - int(a.get("coins", 0))
		if coins != 0:change.coins = coins
		var items := _item_delta(a.get("inventory"), b.get("inventory"))
		if not items.is_empty():change.items = items
		if not change.is_empty():players[str(token)] = change
	var boxes: Array = []
	var before_layers := _layers(before)
	var after_layers := _layers(after)
	var regions: Array = after_layers.keys()
	for region in before_layers:
		if not regions.has(region):regions.append(region)
	regions.sort()
	for region in regions:
		var a_layer: Dictionary = before_layers.get(region, {})
		var b_layer: Dictionary = after_layers.get(region, {})
		var cells: Dictionary = {}
		for cell in a_layer:cells[cell] = true
		for cell in b_layer:cells[cell] = true
		var keys: Array = cells.keys()
		keys.sort()
		for cell in keys:
			var a_obj = a_layer.get(cell, {})
			var b_obj = b_layer.get(cell, {})
			var a_items = _held_items(a_obj)
			var b_items = _held_items(b_obj)
			if not a_items is Dictionary and not b_items is Dictionary:continue
			var items := _item_delta(a_items, b_items)
			if items.is_empty():continue
			var source: Dictionary = b_obj if b_obj is Dictionary and not b_obj.is_empty() else a_obj
			var box: Dictionary = {"r":str(region), "cell":str(cell), "type":str(source.get("type", "")).left(TYPE_MAX), "items":items}
			if source.get("owner") is String and not str(source.owner).is_empty():box.owner = pid(source.owner)
			boxes.append(box)
	return {"players":players, "boxes":boxes}

## Builds the committed entry for one successful request, or {} when the
## commit is not an economy transaction. Sequence fields are set by append().
static func committed_entry(action: String, token: String, request_id: String, before: Dictionary, after: Dictionary) -> Dictionary:
	var change := diff(before, after)
	var players: Dictionary = change.players
	var boxes: Array = change.boxes
	var mine: Dictionary = players.get(token, {})
	var others := players.size() - (1 if players.has(token) else 0)
	var coins_moved := false
	for who in players:
		if players[who].has("coins"):coins_moved = true
	var lost := false
	var gained := false
	for item in mine.get("items", {}):
		if int(mine.items[item]) < 0:lost = true
		else:gained = true
	var trade := action in TRADE_ACTIONS
	# Routine construction / sowing / feeding that only spends the actor's own
	# materials would flood the bounded journal and evict real trades; their
	# material use is already captured by T034 construction history or is
	# plain farming. Anything else they touch (coins, boxes, others) still logs.
	var routine_loss := lost and not gained and action in ROUTINE_ACTIONS
	if routine_loss:lost = false
	if not (coins_moved or not boxes.is_empty() or others > 0 or lost or (trade and not players.is_empty())):return {}
	var kind := "consume"
	if trade:kind = "trade"
	elif not boxes.is_empty():kind = "container"
	elif others > 0:kind = "transfer"
	elif int(mine.get("coins", 0)) > 0:kind = "sale"
	elif int(mine.get("coins", 0)) < 0:kind = "purchase"
	elif lost and gained:kind = "craft"
	var entry: Dictionary = {"ok":true, "act":action.left(ACT_MAX), "kind":kind, "by":pid(token), "rid":rid(request_id)}
	var d: Dictionary = {}
	var order: Array = players.keys()
	order.sort()
	if players.has(token):
		order.erase(token)
		order.push_front(token)
	for who in order:
		if d.size() >= PLAYERS_MAX:
			entry.trunc = true
			break
		var row: Dictionary = (players[who] as Dictionary).duplicate(true)
		if row.has("items"):row.items = _cap_items(row.items, entry)
		d[pid(who)] = row
	entry.d = d
	var kept: Array = []
	for box in boxes:
		if kept.size() >= BOXES_MAX:
			entry.trunc = true
			break
		box.items = _cap_items(box.items, entry)
		kept.append(box)
	entry.box = kept
	return entry

static func rejected_entry(action: String, token: String, request_id: String, message: String, now: float) -> Dictionary:
	return {"t":now, "ok":false, "act":action.left(ACT_MAX), "by":pid(token), "rid":rid(request_id), "reason":message.left(REASON_MAX)}

static func _root(s: Dictionary) -> Dictionary:
	if not s.get(STATE_KEY) is Dictionary:s[STATE_KEY] = fresh()
	return s[STATE_KEY]

## Appends a committed entry (and any pending rejections, oldest first) to the
## live state. Caller then saves; on save failure the caller restores `before`
## which drops all of it together with the change and the receipt.
static func append(s: Dictionary, entry: Dictionary, pending: Array, now: float) -> void:
	if entry.is_empty() and pending.is_empty():return
	var root := _root(s)
	for rejected in pending:
		root.seq = int(root.seq) + 1
		var row: Dictionary = (rejected as Dictionary).duplicate(true)
		row.seq = int(root.seq)
		root.rejected.append(row)
	while root.rejected.size() > REJECT_CAP:root.rejected.pop_front()
	if entry.is_empty():return
	root.seq = int(root.seq) + 1
	var row := entry.duplicate(true)
	row.seq = int(root.seq)
	row.c = int(s.get("committed", 0))
	row.t = now
	root.entries.append(row)
	while root.entries.size() > CAP:
		root.entries.pop_front()
		root.dropped = int(root.dropped) + 1

## Entries `token` may read, newest last, as copies. A viewer sees an entry when
## they are its actor, a party in `d`, or it touched a box they may open
## (shared chests: any member; private boxes: the recorded owner only). Non-actor
## viewers only get their own `d` row (both rows for a trade they took part in)
## and only boxes they may open; rejections only to their own actor.
## Player-facing shop history. Publish only the buyer/seller's own deltas.
static func shop_history(s:Dictionary,token:String) -> Array:
	var entries:Array=s.get(STATE_KEY,{}).get("entries",[])
	var actor:=pid(token)
	var result:Array=[]
	for i in range(entries.size()-1,-1,-1):
		var entry:Dictionary=entries[i]
		if entry.by!=actor or entry.act not in ["buy","sell","ship"]:continue
		var row:=_shop_row(entry,float(entry.t))
		if row.is_empty():continue
		result.append(row)
		if result.size()==10:break
	return result

static func _shop_row(entry:Dictionary,at:float) -> Dictionary:
	if entry.is_empty():return {}
	var own:Dictionary=entry.d.get(entry.by,{})
	if own.is_empty():return {}
	return {"action":entry.act,"time":at,"coins":own.get("coins",0),"items":own.get("items",{}).duplicate()}

## The two story milestones keep their exact committed receipts when the shared ledger rotates.
static func remember_first_shop_trade(player:Dictionary,step:String,entry:Dictionary,at:float) -> void:
	var row:=_shop_row(entry,at)
	if row.is_empty():return
	var first:Dictionary=player.get(FIRST_SHOP_KEY,{})
	if not first.has(step):
		first[step]=row
		player[FIRST_SHOP_KEY]=first

static func valid_first_shop_trade(player:Dictionary,progress:int,sold:int,bought:int,crops:Dictionary) -> bool:
	if not player.has(FIRST_SHOP_KEY):return true
	var first:Variant=player[FIRST_SHOP_KEY]
	if not first is Dictionary or first.is_empty() or first.size()>2:return false
	for step in first:
		var row:Variant=first[step]
		if not row is Dictionary or row.size()!=4 or not _time(row.get("time")) or not _items_valid(row.get("items")):return false
		var items:Dictionary=row.items
		match step:
			"sale":
				if progress<sold or row.get("action") not in ["sell","ship"] or not _int(row.get("coins"),1,Shipping.MAX_COINS):return false
				if items.size()>(1 if row.action=="sell" else Shipping.MAX_LINES):return false
				var has_crop:=false
				for item:String in items:
					if not _int(items[item],-Shipping.MAX_COINS,-1):return false
					if crops.has(CropCatalog.base_kind(item)):has_crop=true
				if not has_crop:return false
			"seed":
				if progress!=bought or row.get("action")!="buy" or items.size()!=1 or not _int(row.get("coins"),-Shipping.MAX_COINS,-1):return false
				var item:String=items.keys()[0]
				if not item.ends_with("_seed") or not crops.has(item.trim_suffix("_seed")) or items[item]!=1:return false
			_:return false
		row.coins=int(row.coins)
		row.time=float(row.time)
	return true

static func view(s: Dictionary, token: String, limit: int = 64) -> Array:
	var out: Array = []
	var root = s.get(STATE_KEY)
	if not root is Dictionary or not s.get("players", {}).has(token):return out
	var me := pid(token)
	for entry in root.get("entries", []):
		if entry.get("by") == me:
			out.append(entry.duplicate(true))
			continue
		var party: bool = entry.get("d", {}).has(me)
		var boxes: Array = []
		for box in entry.get("box", []):
			var private: bool = str(box.get("type", "")) in PRIVATE_BOXES
			if (not private) or box.get("owner") == me:boxes.append((box as Dictionary).duplicate(true))
		if not party and boxes.is_empty():continue
		var copy: Dictionary = entry.duplicate(true)
		copy.box = boxes
		if not (party and entry.get("kind") == "trade"):
			var own: Dictionary = {}
			if party:own[me] = entry.d[me].duplicate(true)
			copy.d = own
		out.append(copy)
	for entry in root.get("rejected", []):
		if entry.get("by") == me:out.append(entry.duplicate(true))
	out.sort_custom(func(a, b):return int(a.seq) < int(b.seq))
	if out.size() > limit:out = out.slice(out.size() - limit)
	return out

# ---------------------------------------------------------------- validation

static func _hex(value, length: int) -> bool:
	if not value is String or value.length() != length:return false
	for ch in value:
		if not ch in "0123456789abcdef":return false
	return true

static func _int(value, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum

static func _time(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= 0.0

static func _items_valid(items) -> bool:
	if not items is Dictionary or items.is_empty() or items.size() > ITEM_KINDS_MAX:return false
	for item in items:
		if not item is String or item.is_empty() or item.length() > 64:return false
		if not _int(items[item], -DELTA_MAX, DELTA_MAX) or int(items[item]) == 0:return false
		items[item] = int(items[item])
	return true

static func _cell(value) -> bool:
	if not value is String:return false
	var parts: PackedStringArray = value.split(",")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() and value == "%d,%d" % [int(parts[0]), int(parts[1])]

static func _keys(entry: Dictionary, keys: Array) -> bool:
	var extra := entry.size() - keys.size()
	for k in keys:
		if not entry.has(k):return false
	if extra == 0:return true
	return extra == 1 and entry.get("trunc") == true

static func _committed_valid(entry, regions: Array, committed: int) -> bool:
	if not entry is Dictionary or not _keys(entry, COMMITTED_KEYS):return false
	if entry.ok != true or not entry.kind in KINDS:return false
	if not entry.act is String or entry.act.is_empty() or entry.act.length() > ACT_MAX:return false
	if not _hex(entry.by, PID_LENGTH) or not _hex(entry.rid, RID_LENGTH):return false
	if not _int(entry.c, 1, committed) or not _time(entry.t):return false
	entry.c = int(entry.c)
	entry.t = float(entry.t)
	if not entry.d is Dictionary or entry.d.size() > PLAYERS_MAX:return false
	for who in entry.d:
		var row = entry.d[who]
		if not _hex(who, PID_LENGTH) or not row is Dictionary or row.is_empty():return false
		for field in row:
			if field == "coins":
				if not _int(row.coins, -DELTA_MAX, DELTA_MAX) or int(row.coins) == 0:return false
				row.coins = int(row.coins)
			elif field == "items":
				if not _items_valid(row.items):return false
			else:return false
	if not entry.box is Array or entry.box.size() > BOXES_MAX:return false
	for box in entry.box:
		if not box is Dictionary or not box.get("r") in regions or not _cell(box.get("cell")):return false
		if not box.get("type") is String or box.type.length() > TYPE_MAX or not _items_valid(box.get("items")):return false
		var size := 4
		if box.has("owner"):
			if not _hex(box.owner, PID_LENGTH):return false
			size = 5
		if box.size() != size:return false
	return true

static func _rejected_valid(entry) -> bool:
	if not entry is Dictionary or entry.size() != REJECTED_KEYS.size() or not _keys(entry, REJECTED_KEYS):return false
	if entry.ok != false or not entry.act is String or entry.act.is_empty() or entry.act.length() > ACT_MAX:return false
	if not _hex(entry.by, PID_LENGTH) or not _hex(entry.rid, RID_LENGTH):return false
	if not entry.reason is String or entry.reason.length() > REASON_MAX:return false
	if not _time(entry.t):return false
	entry.t = float(entry.t)
	return true

## Save validation. Absent root = legacy save (valid, nothing added). Present
## root must match exactly; any malformed field rejects the whole save so the
## loader falls back to `.bak` (never silently strips audit data). Normalizes
## JSON floats back to ints in place.
static func valid(s: Dictionary, regions: Array) -> bool:
	if not s.has(STATE_KEY):return true
	var root = s[STATE_KEY]
	if not root is Dictionary or root.size() != ROOT_KEYS.size():return false
	for k in ROOT_KEYS:
		if not root.has(k):return false
	if not _int(root.seq, 0, DELTA_MAX) or not _int(root.dropped, 0, DELTA_MAX):return false
	root.seq = int(root.seq)
	root.dropped = int(root.dropped)
	if not root.entries is Array or root.entries.size() > CAP:return false
	if not root.rejected is Array or root.rejected.size() > REJECT_CAP:return false
	var committed := int(s.get("committed", 0)) if _int(s.get("committed", 0), 0, DELTA_MAX) else 0
	for list in [root.entries, root.rejected]:
		var last := 0
		for entry in list:
			if not entry is Dictionary or not _int(entry.get("seq"), 1, root.seq):return false
			entry.seq = int(entry.seq)
			if int(entry.seq) <= last:return false
			last = int(entry.seq)
	var last_c := 0
	for entry in root.entries:
		if not _committed_valid(entry, regions, committed):return false
		if int(entry.c) < last_c:return false
		last_c = int(entry.c)
	for entry in root.rejected:
		if not _rejected_valid(entry):return false
	# A sequence counter below the retained rows plus everything rotated out
	# means the root was edited by hand.
	if int(root.seq) < root.entries.size() + root.rejected.size() + int(root.dropped):return false
	return true
