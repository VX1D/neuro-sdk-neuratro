_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("decision-delta")

local DD = require("facts.decision_delta")
local Orch = require("core.orchestrator")
local FS = require("core.force_state")
local Window = require("core.force_window")

local STATES = { HAND_PLAYED = 2, DRAW_TO_HAND = 3, SELECTING_HAND = 4, SHOP = 5,
  PLAY_TAROT = 6, BLIND_SELECT = 7 }
local CLOCK = 5000

local function board_of(dollars, jokers, consumables, deck)
  local names = {}
  local function tally(list)
    local t = {}
    for _, k in ipairs(list or {}) do
      t[k] = (t[k] or 0) + 1
      names[k] = k:gsub("^j_", ""):gsub("^c_", "")
    end
    return t
  end
  return { dollars = dollars, jokers = tally(jokers), consumables = tally(consumables),
    deck = deck, names = names }
end

local function rendered(prev, cur) return DD.render(prev, cur) or "" end

check("field: dollars up",
  rendered(board_of(10, {}, {}, 52), board_of(17, {}, {}, 52)):find("money $10 to $17 (+$7)", 1, true) ~= nil,
  rendered(board_of(10, {}, {}, 52), board_of(17, {}, {}, 52)))
check("field: dollars down",
  rendered(board_of(10, {}, {}, 52), board_of(4, {}, {}, 52)):find("money $10 to $4 (-$6)", 1, true) ~= nil,
  rendered(board_of(10, {}, {}, 52), board_of(4, {}, {}, 52)))
check("field: deck up",
  rendered(board_of(5, {}, {}, 52), board_of(5, {}, {}, 53)):find("deck 52 to 53 cards", 1, true) ~= nil,
  rendered(board_of(5, {}, {}, 52), board_of(5, {}, {}, 53)))
check("field: deck down",
  rendered(board_of(5, {}, {}, 52), board_of(5, {}, {}, 51)):find("deck 52 to 51 cards", 1, true) ~= nil,
  rendered(board_of(5, {}, {}, 52), board_of(5, {}, {}, 51)))
check("field: joker gained",
  rendered(board_of(5, {}, {}, 52), board_of(5, { "j_blueprint" }, {}, 52)):find("jokers gained blueprint", 1, true) ~= nil,
  rendered(board_of(5, {}, {}, 52), board_of(5, { "j_blueprint" }, {}, 52)))
check("field: joker lost",
  rendered(board_of(5, { "j_baron" }, {}, 52), board_of(5, {}, {}, 52)):find("jokers lost baron", 1, true) ~= nil,
  rendered(board_of(5, { "j_baron" }, {}, 52), board_of(5, {}, {}, 52)))
check("field: consumable gained",
  rendered(board_of(5, {}, {}, 52), board_of(5, {}, { "c_fool" }, 52)):find("consumables gained fool", 1, true) ~= nil,
  rendered(board_of(5, {}, {}, 52), board_of(5, {}, { "c_fool" }, 52)))
check("field: consumable removal stays causally neutral",
  rendered(board_of(5, {}, { "c_fool" }, 52), board_of(5, {}, {}, 52)):find("consumables removed fool", 1, true) ~= nil,
  rendered(board_of(5, {}, { "c_fool" }, 52), board_of(5, {}, {}, 52)))

check("multiset: jokers 2 -> 1 is seen",
  rendered(board_of(5, { "j_baron", "j_baron" }, {}, 52), board_of(5, { "j_baron" }, {}, 52))
    :find("jokers lost baron", 1, true) ~= nil,
  rendered(board_of(5, { "j_baron", "j_baron" }, {}, 52), board_of(5, { "j_baron" }, {}, 52)))
check("multiset: jokers 1 -> 2 is seen",
  rendered(board_of(5, { "j_baron" }, {}, 52), board_of(5, { "j_baron", "j_baron" }, {}, 52))
    :find("jokers gained baron", 1, true) ~= nil,
  rendered(board_of(5, { "j_baron" }, {}, 52), board_of(5, { "j_baron", "j_baron" }, {}, 52)))
check("multiset: consumables 2 -> 1 is seen",
  rendered(board_of(5, {}, { "c_fool", "c_fool" }, 52), board_of(5, {}, { "c_fool" }, 52))
    :find("consumables removed fool", 1, true) ~= nil,
  rendered(board_of(5, {}, { "c_fool", "c_fool" }, 52), board_of(5, {}, { "c_fool" }, 52)))
check("multiset: consumables 1 -> 2 is seen",
  rendered(board_of(5, {}, { "c_fool" }, 52), board_of(5, {}, { "c_fool", "c_fool" }, 52))
    :find("consumables gained fool", 1, true) ~= nil,
  rendered(board_of(5, {}, { "c_fool" }, 52), board_of(5, {}, { "c_fool", "c_fool" }, 52)))
do
  local txt = rendered(board_of(5, { "j_baron" }, {}, 52), board_of(5, { "j_blueprint" }, {}, 52))
  check("multiset: a simultaneous unrelated add and remove reports both",
    txt:find("jokers gained blueprint", 1, true) ~= nil and txt:find("jokers lost baron", 1, true) ~= nil, txt)
end
check("no change renders nothing at all, not an empty summary",
  DD.render(board_of(5, { "j_baron" }, {}, 52), board_of(5, { "j_baron" }, {}, 52)) == nil)

do
  local prev, cur = board_of(5, {}, {}, 52), board_of(5, {}, {}, 52)
  prev.vouchers, prev.voucher_names = {}, { v_crystal_ball = "Crystal Ball" }
  cur.vouchers, cur.voucher_names = { v_crystal_ball = 1 }, { v_crystal_ball = "Crystal Ball" }
  check("field: voucher gained",
    rendered(prev, cur):find("vouchers gained Crystal Ball", 1, true) ~= nil, rendered(prev, cur))
end
do
  local prev, cur = board_of(5, {}, {}, 52), board_of(5, {}, {}, 52)
  prev.hands = { Pair = { level = 1, name = "Pair" } }
  cur.hands = { Pair = { level = 3, name = "Pair" } }
  check("field: public hand level changed",
    rendered(prev, cur):find("Pair level 1 to 3", 1, true) ~= nil, rendered(prev, cur))
end
do
  local prev, cur = board_of(5, {}, {}, 52), board_of(5, {}, {}, 52)
  prev.joker_slots, cur.joker_slots = { count = 3, limit = 5 }, { count = 3, limit = 6 }
  prev.consumable_slots, cur.consumable_slots = { count = 1, limit = 2 }, { count = 1, limit = 3 }
  local text = rendered(prev, cur)
  check("field: capacities changed",
    text:find("Joker slots capacity 5 to 6", 1, true) ~= nil
      and text:find("consumable slots capacity 2 to 3", 1, true) ~= nil, text)
end

do
  _G.G = {
    GAME = { dollars = 10, used_vouchers = {}, hands = {} }, playing_cards = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    NEURO = { run_generation = 9, shop_visit_epoch = 3, decision_serial = 11 },
  }
  local Journal = require("core.gameplay_journal")
  local event = assert(Journal.seal({ kind = "shop_reroll", paid = 5,
    used_free_reroll = false }, "delta-journal-1"))
  assert(Journal.publish(event))
  local text, candidate = DD.for_force("SHOP")
  check("journal text is minted inside the decision candidate",
    text:find("This shop visit: rerolled for $5", 1, true) ~= nil
      and candidate.journal.through_sequence == 1
      and candidate.journal.rendered_text ~= nil, text)
  DD.commit(candidate)
  G.GAME.dollars = 999
  local replay, replay_candidate = DD.for_force("SHOP")
  check("same-serial journal replay is byte-identical and mints no candidate",
    replay == text and replay_candidate == nil, replay)
end

local receipt_mode = "written"
local captured_context = nil

local play_card = require("tests.helpers").play_card

local function board()
  captured_context = nil
  _G.G = {
    STATE = STATES.SELECTING_HAND, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = CLOCK }, SETTINGS = { GAMESPEED = 1 },
    GAME = {
      dollars = 10, chips = 0, used_vouchers = {}, modifiers = {}, STOP_USE = 0,
      blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 1, blind_on_deck = "Small",
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Small Blind" },
      hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_hook = { key = "bl_hook", name = "The Hook" } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} }, playing_cards = {},
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    CONTROLLER = { locks = {} }, blind_select = {}, E_MANAGER = { queues = {} },
  }
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end
  for i = 1, 52 do G.playing_cards[i] = play_card(100 + i) end

  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    _decision_windows = {}, once_serials = {}, decision_serial = 1,
    state_enter_serial = 1, reserved_dollars = 0, state = "SELECTING_HAND",
    update = function() end,
    send_context = function() end,
    send_action_result = function() end,
    register_actions = function() return true end,
    unregister_actions = function() end,
    force_actions = function(_, context)
      captured_context = context
      if receipt_mode == "written" then return true, { status = "written", written_at = CLOCK } end
      return true, { status = "buffered" }
    end,
    cancel_force_actions = function() return { status = "written", written_at = CLOCK } end,
    complete_force_cancellation = function() return true end,
  }
  require("core.transition_guard").reset()
  require("core.enforce").reset_run_state()
  require("core.action_receipt").reset("decision-delta")
  require("core.action_registry").reset()
  require("core.tx_cache").reset()
  Orch.reset_run_state()
end

local dd_calls = 0
local dd_real = DD.for_force
local function watch_dd(after)
  dd_calls = 0
  DD.for_force = function(...)
    dd_calls = dd_calls + 1
    local text, candidate = dd_real(...)
    if after then after() end
    return text, candidate
  end
end
local function unwatch_dd()
  DD.for_force = dd_real
end

local function phase() return require("tests.helpers").force_phase(FS) end

local function tick_until(pred, max_seconds)
  local budget = math.floor((max_seconds or 30) / 0.1)
  for _ = 1, budget do
    if pred() then return true end
    CLOCK = CLOCK + 0.1
    G.TIMERS.REAL = CLOCK
    local ok = pcall(Orch.update, 0.1)
    if not ok then return false end
  end
  return pred()
end

local function arm_force()
  return tick_until(function() return phase() == Window.FORCED end, 20)
end

local function next_decision()
  FS.invalidate("test_next_decision")
  G.NEURO.decision_serial = (G.NEURO.decision_serial or 0) + 1
  G.NEURO.force_dirty = true
end

receipt_mode = "written"
CLOCK = 5000
board()
check("fixture: the first force is armed and written", arm_force(), phase())
check("the first force of a run carries no delta line",
  (captured_context or ""):find("Since your last decision", 1, true) == nil)
check("but it did commit an anchor",
  type(G.NEURO.decision_snapshot) == "table" and G.NEURO.decision_snapshot.window == 1,
  tostring(G.NEURO.decision_snapshot and G.NEURO.decision_snapshot.window))

local first_anchor = G.NEURO.decision_snapshot
G.GAME.dollars = 17
next_decision()
check("second force armed", arm_force(), phase())
check("a written force reports the money that moved since the previous one",
  (captured_context or ""):find("money $10 to $17 (+$7)", 1, true) ~= nil,
  (captured_context or ""):match("Since your last decision[^\n]*"))
check("and the anchor advanced off the first snapshot",
  G.NEURO.decision_snapshot ~= first_anchor and G.NEURO.decision_snapshot.window == 2)

local reask_expected = G.NEURO.decision_snapshot.rendered_delta
check("precondition: the text being re-asked is non-empty",
  type(reask_expected) == "string" and reask_expected ~= "",
  tostring(reask_expected))
G.GAME.dollars = 999
local text_again = DD.for_force()
check("a re-ask on the same serial reproduces the same text, not a fresh diff",
  text_again == reask_expected, tostring(text_again))
local _, cand_again = DD.for_force()
check("and a re-ask mints no candidate, so nothing can be promoted twice", cand_again == nil)
G.GAME.dollars = 17

receipt_mode = "buffered"
CLOCK = 6000
board()
check("fixture: the buffered force is armed", arm_force(), phase())
check("a buffered force does not commit an anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

CLOCK = 7000
board()
local pending_receipt = { status = "buffered" }
G.NEURO.force_actions = function(_, context)
  captured_context = context
  return true, pending_receipt
end
check("fixture: armed while buffered", arm_force(), phase())
check("still uncommitted while only buffered", G.NEURO.decision_snapshot == nil)
G.GAME.dollars = 999
pending_receipt.status = "written"
pending_receipt.written_at = CLOCK
tick_until(function() return G.NEURO.decision_snapshot ~= nil end, 10)
check("once the frame is written the anchor commits",
  type(G.NEURO.decision_snapshot) == "table", tostring(G.NEURO.decision_snapshot))
check("and it commits the board that was rendered, not one re-sampled at commit time",
  G.NEURO.decision_snapshot.board ~= nil and G.NEURO.decision_snapshot.board.dollars == 10,
  tostring(G.NEURO.decision_snapshot.board and G.NEURO.decision_snapshot.board.dollars))

CLOCK = 8000
board()
local rejected_receipt = { status = "buffered" }
G.NEURO.force_actions = function(_, context)
  captured_context = context
  return true, rejected_receipt
end
check("fixture: armed while buffered (rejection case)", arm_force(), phase())
rejected_receipt.status = "rejected"
tick_until(function() return phase() ~= Window.FORCED end, 10)
check("a rejected delivery never commits an anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

CLOCK = 9000
board()
G.NEURO.force_actions = function(_, context)
  captured_context = context
  return true, { status = "buffered" }
end
check("fixture: armed while buffered (timeout case)", arm_force(), phase())
tick_until(function() return phase() ~= Window.FORCED end, FS.FORCE_LIVENESS_TIMEOUT + 30)
check("a delivery that timed out never commits an anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

receipt_mode = "written"

CLOCK = 9500
board()
G.NEURO.force_actions = function(_, context)
  captured_context = context
  return false
end
tick_until(function() return false end, 3)
check("a synchronous send failure never commits an anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

CLOCK = 9700
board()
do
  local NeuroState = require("core.state")
  local real_get = NeuroState.get_state_name
  watch_dd()
  NeuroState.get_state_name = function() return "SHOP" end
  local ok = pcall(Orch._step_force_arming, "SELECTING_HAND", CLOCK)
  NeuroState.get_state_name = real_get
  unwatch_dd()
  check("fixture: the stale arming pass ran and actually built a payload", ok and dd_calls >= 1,
    tostring(ok) .. "/" .. tostring(dd_calls))
end
check("a payload discarded as stale never commits an anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

CLOCK = 9800
board()
do
  watch_dd(function() G.NEURO.force_inflight = true end)
  local ok = pcall(Orch._step_force_arming, "SELECTING_HAND", CLOCK)
  unwatch_dd()
  G.NEURO.force_inflight = nil
  check("fixture: the candidate was built and then arming refused it", ok and dd_calls >= 1,
    tostring(ok) .. "/" .. tostring(dd_calls))
  check("fixture: nothing is armed", phase() ~= Window.FORCED, phase())
end
check("a payload that failed to arm never commits an anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

CLOCK = 10000
board()
local ContextReadable = require("context.context_readable")
G.NEURO.decision_snapshot = { window = 0, board = DD.capture(), rendered_delta = nil }
G.GAME.dollars = 42
watch_dd()
local diag = ContextReadable.build("SELECTING_HAND", { "play_hand" }) or ""
local diag_calls = dd_calls
unwatch_dd()
check("a diagnostic volatile build carries no delta block",
  diag:find("Since your last decision", 1, true) == nil,
  diag:match("Since your last decision[^\n]*") or "(absent)")
check("and it never even asks for a candidate, so none can be minted and dropped",
  diag_calls == 0, tostring(diag_calls))

CLOCK = 11000
board()
check("fixture: armed and committed before the reset", arm_force() and G.NEURO.decision_snapshot ~= nil)
require("core.neuro_lifecycle").reset_run_state()
check("a run reset clears the committed anchor",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

receipt_mode = "written"
CLOCK = 12000
board()
check("fixture: first force delivered before the hand", arm_force(), phase())
check("fixture: anchored at the pre-play board",
  G.NEURO.decision_snapshot and G.NEURO.decision_snapshot.board.dollars == 10)
G.GAME.dollars = 25
for _, st in ipairs({ STATES.HAND_PLAYED, STATES.DRAW_TO_HAND, STATES.SELECTING_HAND }) do
  G.STATE = st
  CLOCK = CLOCK + 0.5
  G.TIMERS.REAL = CLOCK
  pcall(Orch.update, 0.5)
end
check("fixture: the interstitials moved the serial without delivering a force",
  (G.NEURO.decision_serial or 0) > 1, tostring(G.NEURO.decision_serial))
check("the force after a played hand reports the whole play, not an empty diff",
  arm_force() and (captured_context or ""):find("money $10 to $25", 1, true) ~= nil,
  (captured_context or ""):match("Since your last decision[^\n]*") or "(no delta line)")

CLOCK = 13000
board()
local late_receipt = { status = "buffered" }
G.NEURO.force_actions = function(_, context)
  captured_context = context
  return true, late_receipt
end
check("fixture: armed and buffered", arm_force(), phase())
G.STATE = STATES.BLIND_SELECT
CLOCK = CLOCK + 0.5
G.TIMERS.REAL = CLOCK
pcall(Orch.update, 0.5)
G.NEURO.force_actions = function() return false end
local superseded_dollars = G.GAME.dollars
late_receipt.status = "written"
late_receipt.written_at = CLOCK
tick_until(function() return G.NEURO.decision_snapshot ~= nil end, 3)
check("a superseded window written late still anchors, because that frame did reach the outbox",
  type(G.NEURO.decision_snapshot) == "table"
    and G.NEURO.decision_snapshot.board.dollars == superseded_dollars,
  tostring(G.NEURO.decision_snapshot))

CLOCK = 13500
board()
local orphan = { status = "buffered" }
G.NEURO.force_actions = function(_, context)
  captured_context = context
  return true, orphan
end
check("fixture: armed and buffered (orphan case)", arm_force(), phase())
local orphan_window = FS.window()
FS.invalidate("test_replace_window")
G.NEURO.force_window = { phase = "successor", state = "SELECTING_HAND" }
check("fixture: a different window object now owns the slot", FS.window() ~= orphan_window)
G.NEURO.force_actions = function() return false end
orphan.status = "written"
orphan.written_at = CLOCK
tick_until(function() return false end, 3)
check("a frame whose window was replaced does not commit its stale candidate",
  G.NEURO.decision_snapshot == nil, tostring(G.NEURO.decision_snapshot))

-- T: using a consumable in the shop parks the shop in PLAY_TAROT and restores it
-- (core/state_kinds.lua:16-20). The interlude must not swallow the change.
CLOCK = 14000
board()
G.STATE = STATES.SHOP
G.NEURO.state = "SHOP"
G.consumeables.cards = { { sort_id = 900, ability = { set = "Tarot", name = "The Fool" },
  config = { center = { key = "c_fool", set = "Tarot", name = "The Fool" } } } }
check("fixture: a shop force is delivered with the consumable held", arm_force(), phase())
check("fixture: anchored with one consumable",
  G.NEURO.decision_snapshot ~= nil and next(G.NEURO.decision_snapshot.board.consumables) ~= nil)
G.consumeables.cards = {}
for _, st in ipairs({ STATES.PLAY_TAROT, STATES.SHOP }) do
  G.STATE = st
  CLOCK = CLOCK + 0.5
  G.TIMERS.REAL = CLOCK
  pcall(Orch.update, 0.5)
end
check("the consumable spent across the PLAY_TAROT interlude is still reported",
  arm_force() and (captured_context or ""):find("consumables removed", 1, true) ~= nil,
  (captured_context or ""):match("Since your last decision[^\n]*") or "(no delta line)")

do
  local base = { dollars = 0, jokers = {}, consumables = {}, names = {}, joker_instances = {
    ["11"] = { name = "Egg", index = 1, sell = 4 },
    ["12"] = { name = "Egg", index = 2, sell = 4 },
  } }
  local current = { dollars = 0, jokers = {}, consumables = {}, names = {}, joker_instances = {
    ["11"] = { name = "Egg", index = 1, sell = 7 },
    ["12"] = { name = "Egg", index = 2, sell = 4 },
  } }
  local text = DD.render(base, current) or ""
  check("sell growth is compared by stable Joker instance", text:find("Egg (#1) $4 to $7", 1, true) ~= nil, text)
  current.joker_instances["11"] = nil
  check("a sold Joker does not fabricate a sell-growth observation",
    (DD.render(base, current) or ""):find("joker sell value", 1, true) == nil)
end

done()
