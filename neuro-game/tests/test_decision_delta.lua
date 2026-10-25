require("tests.stubs").setup({ love = "timers" })

local H = require("tests.helpers")
local check, done = H.harness("decision-delta")

local DD = require("facts.decision_delta")
local Orch = require("core.orchestrator")
local Window = require("core.window")

local EngineCards = require("tests.engine_cards")
local STATES = EngineCards.states()
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
  prev.hands = { Pair = { level = 1 } }
  cur.hands = { Pair = { level = 3 } }
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
    P_CENTERS = require("tests.engine_centers").centers(),
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
  local replay, replay_candidate = DD.for_force("SHOP")
  check("same-serial journal replay is byte-identical and mints no candidate",
    replay == text and replay_candidate == nil, replay)
  G.GAME.dollars = 4
  local moved, moved_candidate = DD.for_force("SHOP")
  check("a same-serial change since the delivered board is diffed against it, not replayed",
    moved:find("money $10 to $4 (-$6)", 1, true) ~= nil and moved:find("current money $4", 1, true) ~= nil
      and moved_candidate ~= nil, moved)
  DD.commit(moved_candidate)
  check("and a same-serial candidate with a newer mint does commit",
    G.NEURO.decision_snapshot == moved_candidate)
end

do
  local function pc(id, value, suit, enh, facing)
    return { sort_id = id, facing = facing or "front", base = { value = value, suit = suit },
      ability = { set = enh and "Enhanced" or "Default" },
      config = { center = enh and { key = enh, set = "Enhanced" } or {} } }
  end
  local ace_s, ace_h = pc(1, "Ace", "Spades"), pc(2, "Ace", "Hearts", "m_glass")
  local nine = pc(3, "9", "Hearts")
  local secret = pc(4, "5", "Clubs", nil, "back")
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    GAME = { dollars = 51, used_vouchers = {}, hands = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    NEURO = { run_generation = 1, shop_visit_epoch = 1, decision_serial = 40 },
  }
  G.hand = { cards = { ace_s, ace_h, nine, secret } }
  G.playing_cards = { ace_s, ace_h, nine, secret }
  for _, c in ipairs(G.playing_cards) do c.area = G.hand end
  G.NEURO.decision_snapshot = nil
  local _, first = DD.for_force("SMODS_BOOSTER_OPENED")
  DD.commit(first)
  G.GAME.dollars = 45
  local bought, cand = DD.for_force("SMODS_BOOSTER_OPENED")
  DD.commit(cand)
  check("fixture: the pack purchase is reported", (bought or ""):find("money $51 to $45", 1, true) ~= nil, bought)
  ace_s.config.center = { key = "m_mult", set = "Enhanced" }
  ace_s.ability.set = "Enhanced"
  ace_h.config.center = { key = "m_mult", set = "Enhanced" }
  nine.base.value = "10"
  secret.config.center = { key = "m_gold", set = "Enhanced" }
  local after, after_cand = DD.for_force("SMODS_BOOSTER_OPENED")
  after = after or ""
  check("a same-window re-ask after a card changed is not a replay of the stale money line",
    after:find("money $51", 1, true) == nil and after_cand ~= nil, after)
  check("enhancement changes are named per card",
    after:find("Ace of Spades to Ace of Spades (Mult", 1, true) ~= nil
      and after:find("Ace of Hearts (Glass", 1, true) ~= nil, after)
  check("a rank change is named", after:find("9 of Hearts to 10 of Hearts", 1, true) ~= nil, after)
  check("a face-down card's change is never named",
    after:find("Clubs", 1, true) == nil and after:find("Gold", 1, true) == nil, after)
end

local captured_context = nil

local play_card = require("tests.helpers").play_card

local function board()
  captured_context = nil
  H.orch_board({ clock = CLOCK, states = STATES })
  G.playing_cards = {}
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end
  for i = 1, 52 do G.playing_cards[i] = play_card(100 + i) end

  G.NEURO = H.orch_neuro({
    state = "SELECTING_HAND", send_context = "written", send_action_result = "noop", register_actions = "true",
    force_actions = function(_, context)
      captured_context = context
      return true
    end,
    withdraw_actions = "true",
  })
  H.orch_reset()
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

local function phase() return require("tests.helpers").force_phase() end

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
  return tick_until(function() return phase() == "forced" end, 20)
end

local function next_decision()
  require("core.window").reset()
  G.NEURO.decision_serial = (G.NEURO.decision_serial or 0) + 1
end

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
local text_again = DD.for_force()
check("a re-ask on an unchanged board reproduces the same text, not an empty diff",
  text_again == reask_expected, tostring(text_again))
local _, cand_again = DD.for_force()
check("and a re-ask mints no candidate, so nothing can be promoted twice", cand_again == nil)
require("core.validate").note_accepted({ name = "resolve_play" })
local after_answer = DD.for_force() or ""
check("after an answered decision that changed nothing, the replay says nothing changed since it",
  after_answer:find("Since your last decision: nothing changed. Most recent change, from before it: "
    .. "money $10 to $17 (+$7).", 1, true) == 1, after_answer)
check("and still mints no candidate", select(2, DD.for_force()) == nil)
G.GAME.dollars = 11
local after_buy = DD.for_force() or ""
check("a same-window change is reported against the board she last saw, ending at the current bank",
  after_buy:find("money $17 to $11 (-$6)", 1, true) ~= nil and after_buy:find("$10 to", 1, true) == nil,
  after_buy)
require("core.window").reset()
check("fixture: a same-window force is armed after the change", arm_force(), phase())
check("the delivered same-window force carries the fresh diff",
  (captured_context or ""):find("money $17 to $11 (-$6)", 1, true) ~= nil,
  (captured_context or ""):match("Since your last decision[^\n]*") or "(no delta line)")
check("and its board becomes the new baseline",
  G.NEURO.decision_snapshot.window == 2 and G.NEURO.decision_snapshot.board.dollars == 11,
  tostring(G.NEURO.decision_snapshot.board.dollars))
G.GAME.dollars = 17

do
  local glass = { base = { value = "5", suit = "Diamonds" }, facing = "front", shattered = true,
    seal = "Purple", ability = { set = "Enhanced" }, config = { center = { key = "m_glass", set = "Enhanced" } } }
  require("core.destruction_log").record(glass)
  next_decision()
  check("fixture: a force after a destruction is armed", arm_force(), phase())
  local line = (captured_context or ""):match("Since your last decision[^\n]*") or "(no delta line)"
  check("the written force names the destroyed card and how it went",
    line:find("5 of Diamonds (", 1, true) ~= nil and line:find("Purple Seal) shattered", 1, true) ~= nil, line)
end

do
  local Utils = require("util.utils")
  local real_begin, real_build = Utils.begin_text_build, Window.build_payload
  local order = {}
  Utils.begin_text_build = function() order[#order + 1] = "begin"; return real_begin() end
  Window.build_payload = function(...) order[#order + 1] = "build"; return real_build(...) end
  next_decision()
  local armed = arm_force()
  Utils.begin_text_build, Window.build_payload = real_begin, real_build
  local seq = table.concat(order, ",")
  check("the arming pass starts a fresh text build before building the payload",
    armed and seq:find("begin,build", 1, true) ~= nil and seq:find("^build") == nil, seq)
end

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
  local ok = pcall(Window._test.arm, "SELECTING_HAND")
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
  watch_dd(function() G.NEURO.register_actions = function() return false end end)
  local ok = pcall(Window._test.arm, "SELECTING_HAND")
  unwatch_dd()
  check("fixture: the candidate was built and then arming refused it", ok and dd_calls >= 1,
    tostring(ok) .. "/" .. tostring(dd_calls))
  check("fixture: nothing is armed", phase() ~= "forced", phase())
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

CLOCK = 12000
board()
check("fixture: first force delivered before the hand", arm_force(), phase())
check("fixture: anchored at the pre-play board",
  G.NEURO.decision_snapshot and G.NEURO.decision_snapshot.board.dollars == 10)
G.GAME.dollars = 25
require("core.window").reset()
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

-- Using a consumable in the shop temporarily enters PLAY_TAROT, then restores the shop state.
CLOCK = 14000
board()
G.STATE = STATES.SHOP
G.NEURO.state = "SHOP"
G.shop = {}
G.GAME.last_tarot_planet = "c_pluto"
G.consumeables.cards = { EngineCards.consumable("c_fool", { sort_id = 900 }) }
check("fixture: a shop force is delivered with the consumable held", arm_force(), phase())
check("fixture: anchored with one consumable",
  G.NEURO.decision_snapshot ~= nil and next(G.NEURO.decision_snapshot.board.consumables) ~= nil)
G.consumeables.cards = {}
require("core.window").reset()
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
