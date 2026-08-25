_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("abandon-obligation")

local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local Actions = require("core.actions")
local ForceState = require("core.force_state")
local TxCache = require("core.tx_cache")

local play_card = require("tests.helpers").play_card

local function env(t)
  G.TIMERS.REAL = t
  G.STATES = { SELECTING_HAND = 4 }
  G.STATE = 4
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.CONTROLLER = nil
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
  G.FUNCS = { get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  TxCache.reset()
  Dispatcher.reset_tx()
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 7,
    dispatcher = Dispatcher, actions = Actions }
  require("tests.helpers").stage_registered(nil, { "play_hand", "help" })
end

local function bridge()
  local b = { results = {}, emitted = {} }
  function b:send_context(m) self.emitted[#self.emitted + 1] = tostring(m) return true end
  function b:send_action_result(id, ok, message, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message, reason = reason }
  end
  b.register_actions = function() end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end
  return b
end

local PLAY = '{"indices":[1,2]}'

local function action(id, name)
  return { command = "action", run_generation = 7,
    data = { id = id, name = name or "play_hand", data = name and "{}" or PLAY } }
end

local function abandon(ids)
  return { command = "neuro-bridge/abandon", data = { ids = ids } }
end

local function results_for(b, id)
  local n = 0
  for _, r in ipairs(b.results) do if r.id == id then n = n + 1 end end
  return n
end

for _, entry in ipairs({ "route_message", "handle_message", "validate_message" }) do
  env(1000)
  local b = bridge()
  Dispatcher.handle_message(abandon({ "forged-" .. entry }), b)
  Dispatcher[entry](action("forged-" .. entry), b)
  check("a forged abandon does not silence the action it names: " .. entry,
    results_for(b, "forged-" .. entry) == 1, results_for(b, "forged-" .. entry))
  check("and the terminal answer prevents an SDK force retry without claiming execution: " .. entry,
    b.results[1] and b.results[1].ok == true
      and tostring(b.results[1].message):find("unchanged", 1, true) ~= nil,
    b.results[1] and tostring(b.results[1].ok))
end

do
  env(1100)
  local b = bridge()
  local ids = {}
  for i = 1, 64 do ids[i] = "mass-" .. i end
  Dispatcher.route_message(abandon(ids), b)
  for i = 1, 64 do Dispatcher.route_message(action("mass-" .. i), b) end
  check("one forged frame cannot silence 64 actions", #b.results == 64, #b.results)
end

for _, entry in ipairs({ "route_message", "handle_message", "validate_message" }) do
  env(1200)
  local b = bridge()
  TxCache.store("paid-" .. entry, true, nil, "play_hand", nil)
  Dispatcher.handle_message(abandon({ "paid-" .. entry }), b)
  Dispatcher[entry](action("paid-" .. entry), b)
  check("an abandoned id TxCache already answered is not answered twice: " .. entry,
    #b.results == 0, #b.results)
end

local function abandoned_nothing(label, frame, id)
  env(1300)
  local b = bridge()
  local ok = pcall(Dispatcher.handle_message, frame, b)
  check("a rejected abandon frame does not throw: " .. label, ok)
  Dispatcher.route_message(action(id), b)
  local last = b.results[#b.results]
  check("a rejected abandon frame abandons nothing: " .. label,
    results_for(b, id) == 1 and last.reason ~= "ACTION_UNAVAILABLE",
    last and tostring(last.reason))
end

do
  env(1300)
  local malformed = {
    { "ids is a string", "not-a-list" },
    { "ids is a number", 7 },
    { "ids is a boolean", true },
    { "ids holds a number", { "bad-a", 5 } },
    { "ids holds an empty string", { "" } },
    { "ids is empty", {} },
    { "ids is a map", { first = "bad-b" } },
  }
  for _, case in ipairs(malformed) do
    local b = bridge()
    local ok = pcall(Dispatcher.handle_message, abandon(case[2]), b)
    check("a malformed abandon frame does not throw: " .. case[1], ok)
  end
end

do
  local oversize = {}
  for i = 1, 65 do oversize[i] = "over-" .. i end
  abandoned_nothing("more ids than the cap", abandon(oversize), "over-65")
  abandoned_nothing("one entry of the wrong type", abandon({ "bad-a", 5 }), "bad-a")
  abandoned_nothing("a field the transport never emits",
    { command = "neuro-bridge/abandon", data = { ids = { "extra-1" }, transport_session = 1 } },
    "extra-1")
end

local FS = require("core.force_state")

local function stale_open_force()
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, G.TIMERS.REAL)
  FS.mark_sent(G.TIMERS.REAL)
  G.NEURO.force_generation = (tonumber(G.NEURO.run_generation) or 1) - 1
end

local function prepare(b, id)
  Dispatcher.route_message(action(id .. "-arm"), b)
  return Dispatcher.validate_message(action(id), b)
end

do
  env(1400)
  local b = bridge()
  check("fixture: the job is prepared", prepare(b, "prep-a") == true)
  local before = #b.results
  Dispatcher.route_message(abandon({ "prep-a" }), b)
  check("abandoning a prepared job sends no second result", #b.results == before, #b.results)
  check("and the job is gone from the prepared table",
    Dispatcher.abort_prepared("prep-a", "probe") == false)
  Dispatcher.handle_message(action("prep-a"), b)
  check("and the staging queue re-entry neither runs it nor answers again",
    #b.results == before, #b.results)
end

do
  env(1500)
  local b = bridge()
  check("fixture: the job is prepared", prepare(b, "prep-b") == true)
  TxCache.invalidate("prep-b")
  local before = #b.results
  stale_open_force()
  Dispatcher.handle_message(action("prep-b"), b)
  check("an unpaid prepared job is answered when it is aborted", #b.results == before + 1,
    #b.results - before)
  check("and the answer addresses the aborted id",
    b.results[#b.results] and b.results[#b.results].id == "prep-b",
    b.results[#b.results] and tostring(b.results[#b.results].id))
end

for _, entry in ipairs({ "route_message", "handle_message", "validate_message" }) do
  env(1600)
  local b = bridge()
  Dispatcher.route_message(action("settled-" .. entry, "help"), b)
  check("fixture: the first delivery is answered: " .. entry, #b.results == 1, #b.results)
  local first = b.results[1]
  stale_open_force()
  Dispatcher[entry](action("settled-" .. entry, "help"), b)
  check("a settled id re-delivered under a moved generation is replayed, not re-judged: " .. entry,
    #b.results == 2 and b.results[2].reason == first.reason and b.results[2].ok == first.ok,
    b.results[2] and tostring(b.results[2].reason))
end

for _, entry in ipairs({ "route_message", "handle_message", "validate_message" }) do
  env(1700)
  local b = bridge()
  Dispatcher[entry]({ command = "action", run_generation = 7,
    data = { id = 42, name = "play_hand", data = PLAY } }, b)
  check("an invalid id is answered at " .. entry .. " with no earlier entry involved",
    #b.results == 1 and b.results[1].id == 42, #b.results)

  env(1710)
  b = bridge()
  Dispatcher.handle_message(abandon({ "screen-" .. entry }), b)
  Dispatcher[entry](action("screen-" .. entry), b)
  check("an abandoned id is answered at " .. entry .. " with no earlier entry involved",
    #b.results == 1, #b.results)
end

done()
