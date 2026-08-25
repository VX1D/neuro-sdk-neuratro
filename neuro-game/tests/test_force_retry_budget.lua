_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("force-retry-budget")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local Actions = require("core.actions")
local TxCache = require("core.tx_cache")
local ActionReceipt = require("core.action_receipt")

local play_card = require("tests.helpers").play_card

local function bridge()
  local b = { results = {} }
  function b:send_action_result(id, ok, message, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason = reason }
    return true, { status = "written" }
  end
  function b:send_context() return true end
  b.register_actions = function() end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end
  return b
end

local function env(t)
  G.TIMERS.REAL = t
  G.STATES = { SELECTING_HAND = 4, SHOP = 5 }
  G.STATE = 4; G.STATE_COMPLETE = true; G.OVERLAY_MENU = nil; G.CONTROLLER = nil
  G.GAME = { dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } }, modifiers = {} }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end }
  require("core.transition_guard").reset()
  ActionReceipt.reset("test")
  Enforce.reset_run_state()
  TxCache.reset()
  local b = bridge()
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, persona = "neuro",
    dispatcher = Dispatcher, actions = Actions,
    send_context = function() return true end }
  require("tests.helpers").stage_registered("SELECTING_HAND",
    { "buy_from_shop", "toggle_shop", "discard_hand" })
  G.NEURO.force_inflight = false
  return b
end

local function counts(b)
  local retried, terminal = 0, 0
  for _, r in ipairs(b.results) do
    if r.ok == false then retried = retried + 1 else terminal = terminal + 1 end
  end
  return retried, terminal
end

local function send(b, msg) Dispatcher.route_message(msg, b) end

local ENFORCE_SRC = (function()
  local fh = assert(io.open("core/enforce.lua", "r"))
  local src = fh:read("*a"); fh:close(); return src
end)()
local REJECT_STREAK_LIMIT = tonumber(ENFORCE_SRC:match("REJECT_STREAK_LIMIT%s*=%s*(%d+)"))

local function bounded(label, b, sends)
  local retried, terminal = counts(b)
  check(label, retried < sends and terminal > 0,
    string.format("sends=%d success:false=%d success:true=%d", sends, retried, terminal))
end

do
  local b = env(700)
  local payloads = { '{"indices":[97]}', '{"indices":[98]}' }
  for i = 1, 30 do
    send(b, { command = "action", data = { id = "m1-" .. i, name = "play_hand",
      data = payloads[(i % 2) + 1] } })
  end
  bounded("M1: a refusal reworded on every retry still runs out of retries", b, 30)
  local before = 0
  for _, r in ipairs(b.results) do
    if r.ok ~= false then break end
    before = before + 1
  end
  check("exactly 2 * REJECT_STREAK_LIMIT refusals reach the wire before the terminal answer",
    before == 2 * REJECT_STREAK_LIMIT,
    "success:false answers before the first success:true: " .. before)
  check("the terminal answer says nothing ran",
    b.results[#b.results].ok == true
      and b.results[#b.results].message:find("Nothing was executed", 1, true) ~= nil,
    b.results[#b.results].message)
end

do
  local b = env(710)
  local vectors = {
    { "play_hand", '{"indices":"nope"}' },        -- SCHEMA_INVALID
    { "buy_from_shop", '{"area":"shop_jokers","index":1}' }, -- state gate
    { "play_hand", '{"indices":[99]}' },          -- validator rejection
  }
  for i = 1, 30 do
    local v = vectors[(i % 3) + 1]
    send(b, { command = "action", data = { id = "m2-" .. i, name = v[1], data = v[2] } })
  end
  bounded("M2: rotating the class of the fault does not renew the budget", b, 30)
end

do
  local b = env(720)
  local ids = { 42, true, {}, "" }
  for i = 1, 30 do
    send(b, { command = "action", data = { id = ids[(i % 4) + 1], name = "play_hand", data = "{}" } })
  end
  bounded("M3: rotating the JSON type of an invalid id does not renew the budget", b, 30)
end

do
  local b = env(730)
  local names = { "play_hand", "discard_hand", "toggle_shop" }
  for i = 1, 30 do
    send(b, { command = "action", data = { id = 42, name = names[(i % 3) + 1], data = "{}" } })
  end
  bounded("M4: rotating which offered action is answered does not renew the budget", b, 30)
end

do
  local b = env(740)
  local ids = { 42, true, {}, "" }
  local names = { "play_hand", "discard_hand", "toggle_shop" }
  for i = 1, 30 do
    send(b, { command = "action",
      data = { id = ids[(i % 4) + 1], name = names[(i % 3) + 1], data = "{}" } })
  end
  bounded("M5: rotating the id type and the action name together is bounded too", b, 30)
end

-- F3: ACTION_UNKNOWN answered success=false with no circuit at all. core/action_result.lua:3-8 makes
-- the terminal form the house rule for every outcome that handled an action without executing it.
do
  local b = env(750)
  for i = 1, 30 do
    send(b, { command = "action",
      data = { id = "u-" .. i, name = "definitely_not_an_action", data = "{}" } })
  end
  bounded("F3: an unknown action name reaches the terminal form instead of refusing forever", b, 30)
  check("the first unknown name still gets its retryable refusal",
    b.results[1].ok == false and b.results[1].reason == "ACTION_UNKNOWN",
    tostring(b.results[1].reason) .. "/" .. tostring(b.results[1].ok))
  check("the terminal unknown-name answer keeps its reason class",
    b.results[#b.results].reason == "ACTION_UNKNOWN", tostring(b.results[#b.results].reason))
end

do
  local b = env(760)
  local r = ActionReceipt.create({ id = "held", name = "play_hand",
    deadline = ActionReceipt.now() + 100000,
    probe = function() return "pending" end, timeout_outcome = "ambiguous" })
  ActionReceipt.transition(r, "acknowledged")
  for i = 1, 30 do
    send(b, { command = "action", data = { id = "v-" .. i, name = "play_hand",
      data = '{"indices":[1,2]}' } })
  end
  bounded("F4: a stuck verification does not refuse every send forever", b, 30)
  ActionReceipt.reset("test")
end

do
  local b = env(770)
  b.is_force_answer = function(_, id) return tostring(id) == "wire-1" end
  G.NEURO.force_window = nil
  G.NEURO.force_inflight = false
  local r = ActionReceipt.create({ id = "held2", name = "play_hand",
    deadline = ActionReceipt.now() + 100000,
    probe = function() return "pending" end, timeout_outcome = "ambiguous" })
  ActionReceipt.transition(r, "acknowledged")
  send(b, { command = "action", data = { id = "wire-1", name = "play_hand",
    data = '{"indices":[1,2]}' } })
  check("the wire, not the local window, decides whether the answer belongs to a force",
    b.results[1] and b.results[1].reason == "TRANSITION_ACKNOWLEDGED",
    b.results[1] and tostring(b.results[1].reason))
  ActionReceipt.reset("test")
end

do
  local b = env(780)
  local payloads = { '{"indices":[97]}', '{"indices":[98]}' }
  for i = 1, 20 do
    send(b, { command = "action", data = { id = "p-" .. i, name = "play_hand",
      data = payloads[(i % 2) + 1] } })
  end
  local _, terminal_before = counts(b)
  check("the exhausted decision is answering terminally before progress", terminal_before > 0)
  b.results = {}
  G.NEURO.decision_serial = G.NEURO.decision_serial + 1
  send(b, { command = "action", data = { id = "p-next", name = "play_hand",
    data = '{"indices":[97]}' } })
  check("the next decision refuses again rather than swallowing the failure",
    b.results[1] and b.results[1].ok == false, b.results[1] and tostring(b.results[1].ok))
end

do
  local b = env(790)
  for i = 1, 20 do
    send(b, { command = "action", data = { id = "q-" .. i, name = "play_hand",
      data = '{"indices":[' .. (90 + (i % 5)) .. ']}' } })
  end
  b.results = {}
  local ActionPolicy = require("core.action_policy")
  check("play_hand is the PROGRESS class this case is about",
    ActionPolicy.NON_PROGRESS["play_hand"] == nil)
  Enforce.note_accepted("play_hand")
  send(b, { command = "action", data = { id = "q-next", name = "play_hand",
    data = '{"indices":[97]}' } })
  check("a PROGRESS action that actually ran buys the decision a fresh retry budget",
    b.results[1] and b.results[1].ok == false, b.results[1] and tostring(b.results[1].ok))
end

do
  local b = env(795)
  for i = 1, 20 do
    send(b, { command = "action", data = { id = "r-" .. i, name = "play_hand",
      data = '{"indices":[' .. (90 + (i % 5)) .. ']}' } })
  end
  b.results = {}
  Enforce.note_accepted("set_plan")
  send(b, { command = "action", data = { id = "r-next", name = "play_hand",
    data = '{"indices":[97]}' } })
  check("a NON_PROGRESS answer does NOT hand the exhausted decision a fresh retry budget",
    b.results[1] and b.results[1].ok == true, b.results[1] and tostring(b.results[1].ok))
end

do
  -- Refusals answered success=false before note_rejection first acknowledges, i.e. before the
  -- decision takes SPECIFICATION.md:188's terminal form.
  local function refusals_before_terminal(fingerprint_of)
    Enforce.reset_run_state()
    G.NEURO = { decision_serial = 1, run_generation = 1 }
    for i = 1, 64 do
      if Enforce.note_rejection("play_hand", fingerprint_of(i)) then return i - 1 end
    end
    return -1
  end
  local varying = refusals_before_terminal(function(i) return "reason-" .. i end)
  local repeated = refusals_before_terminal(function() return "same" end)

  check("core/enforce.lua still states the streak limit as a literal",
    REJECT_STREAK_LIMIT == 3, tostring(REJECT_STREAK_LIMIT))
  check("the window budget is still 2 * REJECT_STREAK_LIMIT, not a number of its own",
    ENFORCE_SRC:find("WINDOW_REFUSAL_BUDGET%s*=%s*2%s*%*%s*REJECT_STREAK_LIMIT") ~= nil,
    tostring(ENFORCE_SRC:match("WINDOW_REFUSAL_BUDGET%s*=%s*([^\n]*)")))
  check("a fingerprint that never repeats spends exactly 2 * REJECT_STREAK_LIMIT refusals",
    varying == 2 * REJECT_STREAK_LIMIT,
    "refusals before the terminal answer: " .. varying .. ", expected " .. (2 * REJECT_STREAK_LIMIT))
  check("a fingerprint that repeats spends exactly REJECT_STREAK_LIMIT refusals",
    repeated == REJECT_STREAK_LIMIT,
    "refusals before the terminal answer: " .. repeated .. ", expected " .. REJECT_STREAK_LIMIT)

  Enforce.reset_run_state()
  G.NEURO = { decision_serial = 1, run_generation = 1 }
  for i = 1, 12 do Enforce.note_rejection("play_hand", "reason-" .. i) end
  G.NEURO.decision_serial = 2
  check("the next decision starts from zero",
    Enforce.note_rejection("play_hand", "reason-fresh") == false)
end

do
  local ActionPolicy = require("core.action_policy")
  for name in pairs(ActionPolicy.NON_PROGRESS) do
    Enforce.reset_run_state()
    G.NEURO = { decision_serial = 1, run_generation = 1 }
    local acknowledged = false
    for i = 1, 40 do
      acknowledged = Enforce.note_rejection("buy_from_shop", "reason-" .. i) or acknowledged
      Enforce.note_accepted(name)
    end
    check("" .. name .. " between refusals cannot renew the decision's budget",
      acknowledged == true)
  end
end

do
  Enforce.reset_run_state()
  G.NEURO = { decision_serial = 1, run_generation = 1 }
  local acknowledged = false
  for i = 1, 40 do
    acknowledged = Enforce.note_rejection("buy_from_shop", "reason-" .. i) or acknowledged
    Enforce.note_accepted("play_hand")
  end
  check("a PROGRESS answer between refusals keeps the decision retryable",
    acknowledged == false)
end

done()
