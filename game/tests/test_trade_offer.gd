extends SceneTree
## T058 regression coverage for the pure helper res://scripts/trade_offer.gd.
## No World/Session access: the helper is not wired into Session yet (see report).
const T = preload("res://scripts/trade_offer.gd")

var checks := 0
var failures := 0

const A := "player-a"
const B := "player-b"
const C := "outsider-c"
const TRADABLE := {"radish": true, "wood": true, "tea": true, "fish": true}
const INV_A := {"radish": 5, "wood": 10, "keepsake": 1}
const INV_B := {"tea": 3, "fish": 2}
const WALLET_A := 500
const WALLET_B := 80

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _open() -> Dictionary:
	var r: Dictionary = T.open("offer-1", A, B, 1000.0)
	return r.get("offer", {})

func _inv(token: String) -> Dictionary:
	return INV_A if token == A else INV_B

func _wallet(token: String) -> int:
	return WALLET_A if token == A else WALLET_B

func _edit(offer: Dictionary, token: String, lines: Variant, coins: Variant) -> Dictionary:
	return T.set_side(offer, token, lines, coins, TRADABLE, _inv(token), _wallet(token))

## Both sides filled and both confirmed at the current revision.
func _ready_offer() -> Dictionary:
	var o := _open()
	o = _edit(o, A, [["radish", 2]], 10).offer
	o = _edit(o, B, [["tea", 1]], 0).offer
	o = T.confirm(o, A, o.revision).offer
	o = T.confirm(o, B, o.revision).offer
	return o

func _initialize() -> void:
	_test_open()
	_test_edit_resets_both_confirmations()
	_test_unchanged_edit()
	_test_honest_versions()
	_test_outsider_rejection()
	_test_invalid_terms()
	_test_one_sided_and_duplicate_confirm()
	_test_unconfirm()
	_test_cancel_and_reopen()
	_test_disconnect_sweep()
	_test_expiry()
	_test_validate_schema()
	_test_json_reload()
	_test_parsers()
	_test_settlement()
	_test_view()
	expect(checks > 0, "Checks executed")
	print("TRADE_OFFER_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

# ---------------------------------------------------------------- open

func _test_open() -> void:
	var r: Dictionary = T.open("offer-1", A, B, 1000.0)
	expect(r.ok and T.validate(r.offer), "Open produces a valid offer")
	var o: Dictionary = r.offer
	expect(o.status == T.STATUS_OPEN and o.revision == 0 and o.reason == "", "Fresh offer is open at revision 0")
	expect(o.confirmed[A] == T.UNCONFIRMED and o.confirmed[B] == T.UNCONFIRMED, "Fresh offer has no confirmations")
	expect(not T.is_ready(o), "Fresh offer is not ready")
	var self_trade: Dictionary = T.open("offer-x", A, A, 1000.0)
	expect(not self_trade.ok and self_trade.message == T.MSG_SELF and not self_trade.has("offer"), "Self trade rejected")
	for bad in [["", A, B, 1.0], ["id", "", B, 1.0], ["id", A, "", 1.0], ["x".repeat(T.MAX_ID + 1), A, B, 1.0],
			["id", "t".repeat(T.MAX_TOKEN + 1), B, 1.0], ["id", A, B, -1.0], ["id", A, B, INF], ["id", A, B, NAN],
			["id", A, B, T.MAX_UTC + 1.0]]:
		var b: Dictionary = T.open(bad[0], bad[1], bad[2], bad[3])
		expect(not b.ok and b.message == T.MSG_BAD and not b.has("offer"), "Invalid open rejected: %s" % str(bad))

# ---------------------------------------------------------------- edits

func _test_edit_resets_both_confirmations() -> void:
	var o := _ready_offer()
	expect(T.is_ready(o), "Fixture is ready")
	var rev := int(o.revision)
	var snapshot := o.duplicate(true)
	var r := _edit(o, A, [["radish", 3]], 10)
	expect(o == snapshot, "set_side does not mutate its input offer")
	expect(r.ok and not r.unchanged, "A's real edit accepted")
	expect(r.offer.revision == rev + 1, "Edit bumps revision by exactly one")
	expect(r.offer.confirmed[A] == T.UNCONFIRMED and r.offer.confirmed[B] == T.UNCONFIRMED, "A's edit clears both confirmations")
	expect(not T.is_ready(r.offer), "Edited offer is not ready")
	expect(T.validate(r.offer), "Edited offer still validates")
	# Partner edit (B) after only A confirmed.
	var p: Dictionary = T.confirm(r.offer, A, r.offer.revision).offer
	expect(p.confirmed[A] == p.revision, "A confirms new revision")
	var q := _edit(p, B, [["fish", 1]], 0)
	expect(q.ok and q.offer.confirmed[A] == T.UNCONFIRMED and q.offer.confirmed[B] == T.UNCONFIRMED, "Partner's edit clears the other side's confirmation")
	# Coin-only change also counts as an edit.
	var s := _edit(q.offer, A, [["radish", 3]], 11)
	expect(s.ok and not s.unchanged and s.offer.revision == q.offer.revision + 1, "Coin-only edit bumps revision")
	# Removing everything is also a change.
	var e := _edit(s.offer, A, [], 0)
	expect(e.ok and not e.unchanged and (e.offer.sides[A].items as Dictionary).is_empty() and e.offer.sides[A].coins == 0, "Clearing a side is a change")
	# Line order does not matter; sides are canonicalised.
	var o2 := _open()
	var x := _edit(o2, A, [["wood", 1], ["radish", 1]], 0)
	var y := _edit(x.offer, A, [["radish", 1], ["wood", 1]], 0)
	expect(y.ok and y.unchanged and y.offer.revision == x.offer.revision, "Reordered identical lines are unchanged")
	expect((x.offer.sides[A].items as Dictionary).keys() == ["radish", "wood"], "Items stored in sorted key order")
	# Revision ceiling.
	var capped := _open()
	capped.revision = T.MAX_REVISION
	capped.confirmed[A] = T.MAX_REVISION
	expect(T.validate(capped), "Offer at revision ceiling validates")
	var over := _edit(capped, A, [["radish", 1]], 0)
	expect(not over.ok and over.message == T.MSG_REVISION and not over.has("offer"), "Edit past revision ceiling rejected")

func _test_unchanged_edit() -> void:
	var o := _ready_offer()
	var r := _edit(o, A, [["radish", 2]], 10)
	expect(r.ok and r.unchanged, "Identical resubmission reports unchanged")
	expect(r.offer.revision == o.revision, "Unchanged edit keeps revision")
	expect(r.offer.confirmed[A] == o.revision and r.offer.confirmed[B] == o.revision, "Unchanged edit keeps both confirmations")
	expect(T.is_ready(r.offer), "Unchanged edit keeps readiness")
	var f := _edit(o, A, [["radish", 2.0]], 10.0)
	expect(f.ok and f.unchanged, "Whole-float quantities (JSON) equal int content")

# ---------------------------------------------------------------- versions

func _test_honest_versions() -> void:
	var o := _open()
	o = _edit(o, A, [["radish", 2]], 0).offer
	var seen_by_b := int(o.revision)
	o = _edit(o, A, [["radish", 4]], 0).offer # A changes terms while B is reviewing.
	var stale: Dictionary = T.confirm(o, B, seen_by_b)
	expect(not stale.ok and stale.message == T.MSG_STALE, "Confirm of an older revision rejected")
	expect(stale.has("offer") and stale.offer.confirmed[B] == T.UNCONFIRMED and stale.offer.revision == o.revision, "Stale reply carries current offer without confirming")
	var future: Dictionary = T.confirm(o, B, int(o.revision) + 1)
	expect(not future.ok and future.message == T.MSG_STALE, "Confirm of a future revision rejected")
	for bad in [-1, -5, 1.5, "1", true, null, INF, NAN, T.MAX_REVISION + 1, [1], {}]:
		var r: Dictionary = T.confirm(o, B, bad)
		expect(not r.ok and r.message == T.MSG_STALE, "Malformed revision rejected: %s" % str(bad))
	var as_float: Dictionary = T.confirm(o, B, float(o.revision))
	expect(as_float.ok and as_float.offer.confirmed[B] == o.revision, "Whole-float current revision (JSON) accepted")
	# ABA: content returns to what B saw, but the revision has moved on.
	var aba := _open()
	aba = _edit(aba, A, [["radish", 1]], 0).offer
	var rev_seen := int(aba.revision)
	aba = _edit(aba, A, [["radish", 5]], 0).offer
	aba = _edit(aba, A, [["radish", 1]], 0).offer
	expect(aba.revision == rev_seen + 2, "ABA edits keep advancing revision")
	var replay: Dictionary = T.confirm(aba, B, rev_seen)
	expect(not replay.ok and replay.message == T.MSG_STALE, "Replayed confirm cannot accept ABA-restored content")
	# Confirm before an edit never carries into the edited revision.
	var c := _open()
	c = _edit(c, A, [["radish", 1]], 0).offer
	c = T.confirm(c, B, c.revision).offer
	c = _edit(c, A, [["radish", 2]], 0).offer
	c = T.confirm(c, A, c.revision).offer
	expect(not T.is_ready(c), "Earlier confirm does not count for edited revision")
	var st: Dictionary = T.stage_settlement(c, {"inventory": INV_A, "coins": WALLET_A}, {"inventory": INV_B, "coins": WALLET_B}, TRADABLE)
	expect(not st.ok and st.message == T.MSG_NOT_READY and not st.has("a"), "Settlement refuses mixed-revision confirmations")

# ---------------------------------------------------------------- outsiders

func _test_outsider_rejection() -> void:
	var o := _ready_offer()
	var snapshot := o.duplicate(true)
	var e: Dictionary = T.set_side(o, C, [["radish", 1]], 0, TRADABLE, {"radish": 9}, 100)
	expect(not e.ok and e.message == T.MSG_NOT_PARTY and not e.has("offer"), "Outsider cannot edit")
	var cf: Dictionary = T.confirm(o, C, o.revision)
	expect(not cf.ok and cf.message == T.MSG_NOT_PARTY, "Outsider cannot confirm")
	var u: Dictionary = T.unconfirm(o, C)
	expect(not u.ok and u.message == T.MSG_NOT_PARTY, "Outsider cannot unconfirm")
	var x: Dictionary = T.cancel(o, C, T.REASON_PLAYER)
	expect(not x.ok and x.message == T.MSG_NOT_PARTY, "Outsider cannot cancel")
	expect(T.view(o, C).is_empty(), "Outsider cannot view")
	for token in ["", "PLAYER-A", "player-a ", "offer-1"]:
		expect(not T.confirm(o, token, o.revision).ok, "Near-miss token rejected: '%s'" % token)
		expect(not T.involves(o, token), "Near-miss token not involved: '%s'" % token)
	expect(T.other_party(o, A) == B and T.other_party(o, B) == A and T.other_party(o, C) == "", "other_party mapping")
	expect(o == snapshot, "Rejected outsider calls leave offer untouched")

# ---------------------------------------------------------------- invalid terms

func _test_invalid_terms() -> void:
	var o := _open()
	var snapshot := o.duplicate(true)
	var bad_lines := [
		[null, T.MSG_LINES], [{}, T.MSG_LINES], ["radish", T.MSG_LINES],
		[[["radish"]], T.MSG_LINES], [[["radish", 1, 1]], T.MSG_LINES], [[{"radish": 1}], T.MSG_LINES],
		[[["radish", 0]], T.MSG_LINES], [[["radish", -1]], T.MSG_LINES], [[["radish", 1.5]], T.MSG_LINES],
		[[["radish", "1"]], T.MSG_LINES], [[["radish", true]], T.MSG_LINES], [[["radish", INF]], T.MSG_LINES],
		[[["radish", T.MAX_QUANTITY + 1]], T.MSG_LINES], [[["", 1]], T.MSG_LINES], [[[7, 1]], T.MSG_LINES],
		[[["x".repeat(T.MAX_ITEM_ID + 1), 1]], T.MSG_LINES],
		[[["radish", 1], ["radish", 1]], T.MSG_DUP],
		[[["keepsake", 1]], T.MSG_UNTRADABLE], [[["hoe", 1]], T.MSG_UNTRADABLE],
		[[["radish", 6]], T.MSG_OWN], [[["tea", 1]], T.MSG_OWN],
	]
	for entry in bad_lines:
		var r := _edit(o, A, entry[0], 0)
		expect(not r.ok and r.message == entry[1] and not r.has("offer"), "Invalid lines rejected (%s): %s" % [entry[1], str(entry[0])])
	var too_many := []
	for i in T.MAX_LINES + 1:
		too_many.append(["radish", 1])
	var tm := _edit(o, A, too_many, 0)
	expect(not tm.ok and tm.message == T.MSG_LINES, "Line count bound")
	for coins in [-1, 1.5, "10", true, null, INF, NAN, T.MAX_COINS + 1]:
		var r := _edit(o, A, [], coins)
		expect(not r.ok and r.message == T.MSG_LINES, "Invalid coin amount rejected: %s" % str(coins))
	var broke := _edit(o, B, [], WALLET_B + 1)
	expect(not broke.ok and broke.message == T.MSG_WALLET, "Offering more coins than wallet rejected")
	var exact := _edit(o, B, [], WALLET_B)
	expect(exact.ok, "Offering exactly the wallet accepted")
	for wallet in [-1, 1.5, "500", null, T.MAX_COINS + 1]:
		var r: Dictionary = T.set_side(o, A, [], 1, TRADABLE, INV_A, wallet)
		expect(not r.ok and r.message == T.MSG_WALLET, "Invalid wallet snapshot rejected: %s" % str(wallet))
	# Holdings are checked against the editor's inventory, not the partner's.
	var cross: Dictionary = T.set_side(o, A, [["tea", 1]], 0, TRADABLE, INV_A, WALLET_A)
	expect(not cross.ok and cross.message == T.MSG_OWN, "Cannot offer partner's items")
	expect(o == snapshot, "Rejected edits leave offer untouched")
	# Invalid terms against a ready offer must not disturb confirmations.
	var primed := _ready_offer()
	var rs := primed.duplicate(true)
	expect(not _edit(primed, A, [["radish", 99]], 0).ok and primed == rs and T.is_ready(primed), "Rejected edit keeps prior confirmations intact")
	# Corrupt offer input.
	var corrupt := _open()
	corrupt.erase("sides")
	expect(_edit(corrupt, A, [], 1).message == T.MSG_BAD, "Corrupt offer rejected by set_side")
	expect(T.confirm(corrupt, A, 0).message == T.MSG_BAD, "Corrupt offer rejected by confirm")
	expect(T.unconfirm(corrupt, A).message == T.MSG_BAD, "Corrupt offer rejected by unconfirm")
	expect(T.cancel(corrupt, A, T.REASON_PLAYER).message == T.MSG_BAD, "Corrupt offer rejected by cancel")

# ---------------------------------------------------------------- confirmations

func _test_one_sided_and_duplicate_confirm() -> void:
	var empty := _open()
	var ec: Dictionary = T.confirm(empty, A, 0)
	expect(not ec.ok and ec.message == T.MSG_EMPTY, "Cannot confirm a trade with nothing on either side")
	# One-sided content (gift) is allowed once both confirm.
	var gift: Dictionary = _edit(_open(), A, [["wood", 2]], 0).offer
	gift = T.confirm(gift, A, gift.revision).offer
	expect(not T.is_ready(gift), "Only giver confirmed: not ready")
	var one: Dictionary = T.confirm(gift, B, gift.revision)
	expect(one.ok and one.ready, "One-sided content with both confirmations is ready")
	# One-sided confirmation.
	var o: Dictionary = _edit(_open(), A, [["radish", 1]], 0).offer
	o = _edit(o, B, [["tea", 1]], 0).offer
	var r1: Dictionary = T.confirm(o, A, o.revision)
	expect(r1.ok and not r1.ready, "First confirmation alone is not ready")
	expect(r1.offer.confirmed[A] == o.revision and r1.offer.confirmed[B] == T.UNCONFIRMED, "Only confirming party recorded")
	var v: Dictionary = T.view(r1.offer, B)
	expect(not v.i_confirmed and v.they_confirmed and not v.ready, "Partner view reflects one-sided confirmation")
	var st: Dictionary = T.stage_settlement(r1.offer, {"inventory": INV_A, "coins": WALLET_A}, {"inventory": INV_B, "coins": WALLET_B}, TRADABLE)
	expect(not st.ok and st.message == T.MSG_NOT_READY and not st.has("cancelled"), "One-sided confirmation cannot settle and does not cancel")
	# Duplicate confirmation from the same party is idempotent.
	var r2: Dictionary = T.confirm(r1.offer, A, o.revision)
	expect(r2.ok and not r2.ready and r2.offer == r1.offer, "Duplicate confirm by same party is idempotent and not ready")
	var r3: Dictionary = T.confirm(r2.offer, B, o.revision)
	expect(r3.ok and r3.ready, "Second distinct party makes it ready")
	var r4: Dictionary = T.confirm(r3.offer, B, o.revision)
	expect(r4.ok and r4.ready and r4.offer == r3.offer and r4.offer.revision == o.revision, "Duplicate confirm after ready is harmless")
	var r5: Dictionary = T.confirm(r3.offer, A, int(o.revision) - 1)
	expect(not r5.ok and r5.message == T.MSG_STALE, "Duplicate confirm with stale revision rejected even when ready")

func _test_unconfirm() -> void:
	var o := _ready_offer()
	var u: Dictionary = T.unconfirm(o, A)
	expect(u.ok and u.offer.confirmed[A] == T.UNCONFIRMED and u.offer.confirmed[B] == o.revision, "Unconfirm clears only caller")
	expect(not T.is_ready(u.offer) and u.offer.revision == o.revision, "Unconfirm drops readiness without bumping revision")
	var again: Dictionary = T.unconfirm(u.offer, A)
	expect(again.ok and again.offer == u.offer, "Double unconfirm is idempotent")
	var re: Dictionary = T.confirm(u.offer, A, o.revision)
	expect(re.ok and re.ready, "Re-confirm after unconfirm restores readiness")

# ---------------------------------------------------------------- cancel / reopen

func _test_cancel_and_reopen() -> void:
	var o := _ready_offer()
	var snapshot := o.duplicate(true)
	var c: Dictionary = T.cancel(o, B, T.REASON_PLAYER)
	expect(o == snapshot, "cancel does not mutate input")
	expect(c.ok and c.cancelled and c.message == T.MSG_CANCELLED, "Party cancel accepted")
	var x: Dictionary = c.offer
	expect(x.status == T.STATUS_CANCELLED and x.reason == T.REASON_PLAYER, "Cancelled status and reason recorded")
	expect(x.confirmed[A] == T.UNCONFIRMED and x.confirmed[B] == T.UNCONFIRMED, "Cancel clears confirmations")
	expect(x.sides == o.sides and x.revision == o.revision, "Cancel keeps terms for audit")
	expect(T.validate(x) and not T.is_open(x) and not T.is_ready(x), "Cancelled offer valid but closed")
	expect(_edit(x, A, [["radish", 1]], 0).message == T.MSG_CLOSED, "Cannot edit a cancelled offer")
	expect(T.confirm(x, A, x.revision).message == T.MSG_CLOSED, "Cannot confirm a cancelled offer")
	expect(T.unconfirm(x, A).message == T.MSG_CLOSED, "Cannot unconfirm a cancelled offer")
	var twice: Dictionary = T.cancel(x, A, T.REASON_PLAYER)
	expect(not twice.ok and twice.message == T.MSG_CLOSED and not twice.has("cancelled"), "Double cancel rejected")
	var st: Dictionary = T.stage_settlement(x, {"inventory": INV_A, "coins": WALLET_A}, {"inventory": INV_B, "coins": WALLET_B}, TRADABLE)
	expect(not st.ok and st.message == T.MSG_CLOSED, "Cancelled offer cannot settle")
	for reason in ["", "bored", "PLAYER", T.STATUS_CANCELLED]:
		var bad: Dictionary = T.cancel(o, A, reason)
		expect(not bad.ok and bad.message == T.MSG_BAD, "Unknown cancel reason rejected: '%s'" % reason)
	var server: Dictionary = T.cancel(o, "", T.REASON_REGION)
	expect(server.ok and server.offer.reason == T.REASON_REGION, "Server (empty token) may cancel with system reason")
	for reason in T.REASONS:
		expect(T.cancel(o, A, reason).ok, "Every documented reason accepted: %s" % reason)
	# Settled offers are closed too.
	var settled: Dictionary = T.stage_settlement(o, {"inventory": INV_A, "coins": WALLET_A}, {"inventory": INV_B, "coins": WALLET_B}, TRADABLE).offer
	expect(settled.status == T.STATUS_SETTLED and T.validate(settled), "Settled fixture valid")
	expect(T.cancel(settled, A, T.REASON_PLAYER).message == T.MSG_CLOSED, "Cannot cancel a settled offer")
	expect(_edit(settled, A, [], 1).message == T.MSG_CLOSED, "Cannot edit a settled offer")
	# Reopen = a brand new offer; nothing carries over from the cancelled one.
	var reopened: Dictionary = T.open("offer-2", A, B, 2000.0)
	expect(reopened.ok and reopened.offer.revision == 0 and reopened.offer.sides[A].items.is_empty(), "Reopen starts empty at revision 0")
	var carry: Dictionary = T.confirm(reopened.offer, A, x.revision)
	expect(not carry.ok, "Old revision/confirmation cannot be carried into reopened offer")
	# Helper has no registry: reusing an id produces a fresh offer. Session must guard id reuse.
	var reuse: Dictionary = T.open(str(x.id), A, B, 2000.0)
	expect(reuse.ok and reuse.offer.status == T.STATUS_OPEN, "Helper itself does not prevent id reuse (Session gap)")

# ---------------------------------------------------------------- disconnect

func _test_disconnect_sweep() -> void:
	var ab := _ready_offer()
	var ac: Dictionary = _edit(T.open("offer-ac", A, C, 1000.0).offer, A, [["wood", 1]], 0).offer
	var bc: Dictionary = T.open("offer-bc", B, C, 1000.0).offer
	var done: Dictionary = T.cancel(T.open("offer-old", A, B, 1000.0).offer, A, T.REASON_PLAYER).offer
	var offers := {"offer-1": ab, "offer-ac": ac, "offer-bc": bc, "offer-old": done, "junk": "not-a-dict"}
	var snapshot := offers.duplicate(true)
	expect(T.blocks_sleep(offers), "Open offers block sleep")
	var sweep: Dictionary = T.cancel_involving(offers, A, T.REASON_DISCONNECT)
	expect(offers == snapshot, "Sweep does not mutate input map")
	var ids: Array = sweep.cancelled
	ids.sort()
	expect(ids == ["offer-1", "offer-ac"], "Disconnect cancels exactly the open offers involving the token")
	var out: Dictionary = sweep.offers
	expect(out.size() == offers.size(), "Sweep keeps every entry")
	expect(out["offer-1"].status == T.STATUS_CANCELLED and out["offer-1"].reason == T.REASON_DISCONNECT, "Ready offer cancelled on disconnect")
	expect(out["offer-1"].confirmed[A] == T.UNCONFIRMED and out["offer-1"].confirmed[B] == T.UNCONFIRMED, "Disconnect clears confirmations")
	expect(out["offer-ac"].reason == T.REASON_DISCONNECT, "Other open offer of the leaver cancelled")
	expect(out["offer-bc"] == bc and T.is_open(out["offer-bc"]), "Unrelated offer untouched")
	expect(out["offer-old"] == done and out["offer-old"].reason == T.REASON_PLAYER, "Already-cancelled offer keeps original reason")
	expect(out["junk"] == "not-a-dict", "Non-dictionary entries passed through")
	expect(T.blocks_sleep(out), "Remaining open offer still blocks sleep")
	var st: Dictionary = T.stage_settlement(out["offer-1"], {"inventory": INV_A, "coins": WALLET_A}, {"inventory": INV_B, "coins": WALLET_B}, TRADABLE)
	expect(not st.ok and st.message == T.MSG_CLOSED and not st.has("a"), "Disconnected ready offer can never settle")
	var again: Dictionary = T.cancel_involving(out, A, T.REASON_DISCONNECT)
	expect((again.cancelled as Array).is_empty() and again.offers == out, "Repeat disconnect sweep is a no-op")
	var all: Dictionary = T.cancel_involving(out, "", T.REASON_RELOAD)
	expect(all.cancelled == ["offer-bc"] and not T.blocks_sleep(all.offers), "Empty token sweeps all open offers (reload)")
	var nobody: Dictionary = T.cancel_involving(offers, "ghost", T.REASON_DISCONNECT)
	expect((nobody.cancelled as Array).is_empty() and nobody.offers == offers, "Unknown token cancels nothing")
	var bad_reason: Dictionary = T.cancel_involving(offers, A, "bogus")
	expect((bad_reason.cancelled as Array).is_empty() and bad_reason.offers == offers, "Invalid sweep reason cancels nothing")
	expect(not T.blocks_sleep({}) and not T.blocks_sleep({"x": done}), "No open offers: sleep allowed")

func _test_expiry() -> void:
	var o := _open()
	expect(not T.expired(o, 1000.0) and not T.expired(o, 1000.0 + T.OPEN_TTL - 0.001), "Within TTL not expired")
	expect(T.expired(o, 1000.0 + T.OPEN_TTL), "TTL boundary expires")
	expect(T.expired(o, 999.0), "Clock regression treated as expired")
	expect(not T.expired(o, NAN) and not T.expired(o, INF), "Non-finite clock ignored")
	var x: Dictionary = T.cancel(o, "", T.REASON_EXPIRED).offer
	expect(not T.expired(x, 1.0e9), "Closed offer never reports expired")

# ---------------------------------------------------------------- schema

func _test_validate_schema() -> void:
	var good := _ready_offer()
	expect(T.validate(good), "Ready offer validates")
	for bad in [null, [], "offer", 1]:
		expect(not T.validate(bad), "Non-dictionary rejected")
	for label in ["missing reason", "same parties", "unknown status", "negative revision", "fractional revision",
			"confirm above revision", "confirm below -1", "extra party", "missing side", "extra side field",
			"negative coins", "zero quantity", "cancelled without reason", "open with reason", "unknown reason",
			"settled unready", "negative created", "string created", "infinite created"]:
		expect(not T.validate(_mutated(good, label)), "validate rejects: %s" % label)

func _mutated(good: Dictionary, label: String) -> Dictionary:
	var o := good.duplicate(true)
	match label:
		"missing reason": o.erase("reason")
		"same parties": o.b = o.a
		"unknown status": o.status = "pending"
		"negative revision": o.revision = -1
		"fractional revision": o.revision = 1.5
		"confirm above revision": o.confirmed[A] = int(o.revision) + 1
		"confirm below -1": o.confirmed[A] = -2
		"extra party": o.confirmed[C] = -1
		"missing side": o.sides.erase(B)
		"extra side field": o.sides[A]["note"] = "x"
		"negative coins": o.sides[A].coins = -1
		"zero quantity": o.sides[A].items["radish"] = 0
		"cancelled without reason": o.status = T.STATUS_CANCELLED
		"open with reason": o.reason = T.REASON_PLAYER
		"unknown reason":
			o.status = T.STATUS_CANCELLED
			o.reason = "bogus"
		"settled unready":
			o.status = T.STATUS_SETTLED
			o.confirmed[A] = T.UNCONFIRMED
		"negative created": o.created_utc = -1.0
		"string created": o.created_utc = "1000"
		"infinite created": o.created_utc = INF
	return o

func _test_json_reload() -> void:
	var o: Dictionary = _edit(_open(), A, [["wood", 3], ["radish", 2]], 7).offer
	o = _edit(o, B, [["tea", 1]], 0).offer
	o = T.confirm(o, A, o.revision).offer
	var reloaded: Variant = JSON.parse_string(JSON.stringify(o))
	expect(T.validate(reloaded), "JSON-reloaded offer validates")
	var canon: Dictionary = T.canonical(reloaded)
	expect(canon == T.canonical(o), "Canonical reload equals live canonical")
	expect(var_to_bytes(canon) == var_to_bytes(T.canonical(o)), "Canonical reload is byte-identical")
	expect(canon.revision is int and canon.confirmed[A] is int and canon.sides[A].coins is int, "Canonical restores int types")
	var r: Dictionary = T.confirm(reloaded, B, (reloaded as Dictionary).revision)
	expect(r.ok and r.ready, "Reloaded offer confirmable with float revision")
	var same := _edit(reloaded, A, [["radish", 2], ["wood", 3]], 7)
	expect(same.ok and same.unchanged, "Reloaded offer recognises identical content")

func _test_parsers() -> void:
	var e: Dictionary = T.parse_edit(JSON.stringify({"offer": "offer-1", "items": [["radish", 1]], "coins": 5}))
	expect(e.ok and e.offer_id == "offer-1" and int(e.coins) == 5 and e.lines is Array and e.lines.size() == 1 \
		and e.lines[0][0] == "radish" and int(e.lines[0][1]) == 1, "parse_edit happy path")
	for bad in ["", "[]", "{", "{\"offer\":\"o\",\"items\":[]}", "{\"offer\":\"\",\"items\":[],\"coins\":0}",
			"{\"offer\":\"o\",\"items\":[],\"coins\":0,\"x\":1}", "{\"offer\":1,\"items\":[],\"coins\":0}",
			" ".repeat(T.MAX_EXTRA_BYTES + 1)]:
		expect(not T.parse_edit(bad).ok, "parse_edit rejects: %s" % bad.left(40))
	var c: Dictionary = T.parse_confirm(JSON.stringify({"offer": "offer-1", "revision": 3}))
	expect(c.ok and c.offer_id == "offer-1" and c.revision == 3 and c.revision is int, "parse_confirm happy path")
	for bad in ["{\"offer\":\"o\"}", "{\"offer\":\"o\",\"revision\":-1}", "{\"offer\":\"o\",\"revision\":1.5}",
			"{\"offer\":\"o\",\"revision\":\"1\"}", "{\"offer\":\"o\",\"revision\":1,\"x\":0}", "null",
			" ".repeat(T.MAX_EXTRA_BYTES + 1)]:
		var r: Dictionary = T.parse_confirm(bad)
		expect(not r.ok and r.message == T.MSG_BAD, "parse_confirm rejects: %s" % bad.left(40))
	# Parsed edit flows through set_side, whose validation is authoritative.
	var forged: Dictionary = T.parse_edit(JSON.stringify({"offer": "offer-1", "items": [["keepsake", 1]], "coins": 0}))
	expect(forged.ok and not _edit(_open(), A, forged.lines, forged.coins).ok, "Parse is structural only; set_side rejects untradable")

# ---------------------------------------------------------------- settlement

func _test_settlement() -> void:
	var o := _ready_offer() # A gives radish x2 + 10 coins; B gives tea x1.
	var sa := {"inventory": INV_A.duplicate(true), "coins": WALLET_A}
	var sb := {"inventory": INV_B.duplicate(true), "coins": WALLET_B}
	var sa0 := sa.duplicate(true)
	var sb0 := sb.duplicate(true)
	var o0 := o.duplicate(true)
	var r: Dictionary = T.stage_settlement(o, sa, sb, TRADABLE)
	expect(sa == sa0 and sb == sb0 and o == o0, "Staging never mutates inputs")
	expect(r.ok and r.message == T.MSG_SETTLED and r.offer.status == T.STATUS_SETTLED, "Ready offer settles")
	expect(r.a.inventory.radish == 3 and r.a.inventory.tea == 1 and r.a.coins == WALLET_A - 10, "A receives/debits correctly")
	expect(r.b.inventory.tea == 2 and r.b.inventory.radish == 2 and r.b.coins == WALLET_B + 10, "B receives/debits correctly")
	expect(r.a.inventory.keepsake == 1 and r.b.inventory.fish == 2, "Unrelated items preserved")
	expect(T.validate(r.offer), "Settled offer validates")
	expect(T.stage_settlement(r.offer, sa, sb, TRADABLE).message == T.MSG_CLOSED, "Settled offer cannot settle twice")
	# Holdings dropped since confirmation: cancel, charge nobody.
	var short_a := {"inventory": {"radish": 1, "wood": 10}, "coins": WALLET_A}
	var s1: Dictionary = T.stage_settlement(o, short_a, sb, TRADABLE)
	expect(not s1.ok and s1.cancelled and s1.message == T.MSG_SHORT and not s1.has("a") and not s1.has("b"), "Item shortage cancels with no replacement state")
	expect(s1.offer.status == T.STATUS_CANCELLED and s1.offer.reason == T.REASON_SHORTAGE and T.validate(s1.offer), "Shortage cancellation persisted shape")
	var s2: Dictionary = T.stage_settlement(o, {"inventory": INV_A, "coins": 9}, sb, TRADABLE)
	expect(not s2.ok and s2.cancelled and s2.message == T.MSG_SHORT, "Coin shortage cancels")
	var s3: Dictionary = T.stage_settlement(o, sa, {"inventory": {"fish": 2}, "coins": WALLET_B}, TRADABLE)
	expect(not s3.ok and s3.cancelled and s3.message == T.MSG_SHORT, "Partner shortage cancels both")
	# Exact holdings settle and World-style zero-count keys are kept.
	var exact: Dictionary = _edit(_open(), A, [["radish", 1]], 0).offer
	exact = _edit(exact, B, [["tea", 1]], 0).offer
	exact = T.confirm(T.confirm(exact, A, exact.revision).offer, B, exact.revision).offer
	var ok_exact: Dictionary = T.stage_settlement(exact, {"inventory": {"radish": 1}, "coins": 0}, {"inventory": {"tea": 1}, "coins": 0}, TRADABLE)
	expect(ok_exact.ok and ok_exact.a.inventory.radish == 0 and ok_exact.a.inventory.tea == 1, "Exact holdings settle; zero keys kept")
	# Incoming goods never fund outgoing: A offers tea (owned at edit time), has none at
	# settlement, and would only receive tea from B in the same swap.
	var loop: Dictionary = T.set_side(_open(), A, [["tea", 1]], 0, TRADABLE, {"tea": 1}, 0).offer
	loop = _edit(loop, B, [["tea", 1]], 0).offer
	loop = T.confirm(T.confirm(loop, A, loop.revision).offer, B, loop.revision).offer
	var no_fund: Dictionary = T.stage_settlement(loop, {"inventory": {}, "coins": 0}, {"inventory": {"tea": 1}, "coins": 0}, TRADABLE)
	expect(not no_fund.ok and no_fund.cancelled and no_fund.message == T.MSG_SHORT and not no_fund.has("a"), "Incoming goods cannot fund outgoing goods")
	# Capacity ceilings.
	var full_inv := {"inventory": {"tea": T.ITEM_LIMIT, "radish": 5, "wood": 10}, "coins": WALLET_A}
	var f1: Dictionary = T.stage_settlement(o, full_inv, sb, TRADABLE)
	expect(not f1.ok and f1.cancelled and f1.message == T.MSG_FULL, "Item ceiling cancels")
	var f2: Dictionary = T.stage_settlement(o, sa, {"inventory": INV_B, "coins": T.MAX_COINS - 5}, TRADABLE)
	expect(not f2.ok and f2.cancelled and f2.message == T.MSG_FULL, "Wallet ceiling cancels")
	# Tradability revoked after confirmation.
	var no_tea := TRADABLE.duplicate()
	no_tea.erase("tea")
	var t1: Dictionary = T.stage_settlement(o, sa, sb, no_tea)
	expect(not t1.ok and t1.cancelled and t1.message == T.MSG_UNTRADABLE, "Newly untradable item cancels")
	# Malformed state snapshots are rejected without cancelling.
	for bad in [{}, {"inventory": [], "coins": 0}, {"inventory": {}, "coins": -1}, {"inventory": {}, "coins": "5"}]:
		var m: Dictionary = T.stage_settlement(o, bad, sb, TRADABLE)
		expect(not m.ok and m.message == T.MSG_BAD and not m.has("cancelled"), "Malformed snapshot rejected: %s" % str(bad))
	var corrupt_inv: Dictionary = T.stage_settlement(o, {"inventory": {"radish": "5"}, "coins": WALLET_A}, sb, TRADABLE)
	expect(not corrupt_inv.ok and corrupt_inv.cancelled, "Corrupt inventory count treated as shortage")

# ---------------------------------------------------------------- view

func _test_view() -> void:
	var o: Dictionary = _edit(_open(), A, [["radish", 2]], 10).offer
	o = _edit(o, B, [["tea", 1]], 0).offer
	o = T.confirm(o, A, o.revision).offer
	var va: Dictionary = T.view(o, A)
	var vb: Dictionary = T.view(o, B)
	expect(va.partner == B and vb.partner == A, "View partner")
	expect(va.mine == vb.theirs and va.theirs == vb.mine, "Both parties see both sides symmetrically")
	expect(va.i_confirmed and not va.they_confirmed and vb.they_confirmed and not vb.i_confirmed, "View confirmation flags")
	expect(va.revision == o.revision and not va.ready, "View revision and readiness")
	va.mine.coins = 999
	expect(o.sides[A].coins == 10, "View is a copy")
	var corrupt := o.duplicate(true)
	corrupt.status = "weird"
	expect(T.view(corrupt, A).is_empty(), "Invalid offer has no view")
