_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("schema-gate-order")

local Enforce = require("core.enforce")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local ActionReceipt = require("core.action_receipt")
local Helpers = require("tests.helpers")

local play_card = require("tests.helpers").play_card

local function tarot()
  return {
    sort_id = "c_fool", sell_cost = 1,
    ability = { set = "Tarot", name = "The Fool", consumeable = true },
    config = { center = { key = "c_fool", set = "Tarot", loc_txt = { name = "The Fool" } } },
    juice_up = function() end, highlight = function() end,
  }
end

local function selecting_hand_env() require("tests.helpers").selecting_hand_env() end

local function shop_env()
  G.TIMERS.REAL = 100
  G.STATES = { SHOP = 5 }
  G.STATE = 5
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = { dollars = 10, used_vouchers = {}, round_resets = { ante = 2 },
    current_round = {}, modifiers = {} }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = { tarot() }, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } }
  G.deck = { cards = {} }
  G.shop_jokers = { cards = {} }
  G.FUNCS = { sell_card = function() end }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
end

local function run_stream(state_name, action, gen, count)
  if state_name == "SHOP" then shop_env() else selecting_hand_env() end
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions,
    shop_visit_epoch = 1, state = state_name, state_enter_serial = 1 }
  local log = {}
  local bridge = {
    send_action_result = function(_, _, ok, message, code)
      log[#log + 1] = { ok = ok, message = message, code = code }
    end,
    send_context = function() end,
    register_actions = function() end,
    unregister_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
  require("core.tx_cache").reset()
  Helpers.stage_registered(nil, { action })
  for i = 1, count do
    G.TIMERS.REAL = G.TIMERS.REAL + 100
    G.NEURO.force_inflight = false
    ActionReceipt.reset("stream")
    if state_name == "SHOP" then G.consumeables.cards = { tarot() } end
    FS.arm(state_name, { action }, { [action] = true }, 1)
    Dispatcher.handle_message({ command = "action",
      data = { id = state_name .. "-" .. action .. "-" .. i, name = action, data = gen(i) } }, bridge)
  end
  return log
end

local function count_matching(log, needle)
  local n = 0
  for i = 1, #log do
    if log[i].message and tostring(log[i].message):find(needle, 1, true) then n = n + 1 end
  end
  return n
end

local function count_code(log, code)
  local n = 0
  for i = 1, #log do
    if log[i].code == code then n = n + 1 end
  end
  return n
end

local function count_failed(log)
  local n = 0
  for i = 1, #log do
    if log[i].ok == false then n = n + 1 end
  end
  return n
end

local function count_ok(log)
  local n = 0
  for i = 1, #log do
    if log[i].ok == true then n = n + 1 end
  end
  return n
end

do
  local log = run_stream("SELECTING_HAND", "play_hand",
    function() return '{"indices":[1,2,3,4,5,6]}' end, 40)
  check("an oversized selection is answered by the schema, every single time",
    count_matching(log, "at most 5") == 40, count_matching(log, "at most 5") .. "/" .. #log)
  check("it is never answered with the repeat cap instead",
    count_matching(log, "repeated") == 0, count_matching(log, "repeated"))
  check("the first refusal is SCHEMA_INVALID and unsuccessful",
    log[1] and log[1].ok == false and log[1].code == "SCHEMA_INVALID",
    log[1] and tostring(log[1].code) .. "/" .. tostring(log[1].ok))
  check("an invalid payload gets a bounded SDK retry budget",
    count_failed(log) == 3, count_failed(log))
  check("identical failures become terminal acknowledgements without execution",
    count_ok(log) == 37 and log[40].message:find("Nothing was executed", 1, true) ~= nil,
    count_ok(log))
  check("the refusal never relabels its failure class",
    count_code(log, "SCHEMA_INVALID") == 40 and count_code(log, "POLICY_ACKNOWLEDGED") == 0,
    count_code(log, "SCHEMA_INVALID") .. "/" .. count_code(log, "POLICY_ACKNOWLEDGED"))
  check("the last refusal still carries the schema reason",
    log[#log] and log[#log].message:find("at most 5", 1, true) ~= nil,
    log[#log] and log[#log].message)
end

do
  local log = run_stream("SELECTING_HAND", "discard_hand", function(i)
    if i <= 3 then return '{"indices":[1,2,3,4,5,6]}' end
    if i == 4 then return '{"indices":[1]}' end
    return '{"indices":[1,2,3,4,5,6]}'
  end, 5)
  check("a valid send lands between two refusals, each keeping its own verdict",
    log[4] and log[4].ok == true and log[5] and log[5].ok == false and log[5].code == "SCHEMA_INVALID",
    log[5] and tostring(log[5].code) .. "/" .. tostring(log[5].ok))
end

local BASELINE = '{"indices":[1,2]}'
local VECTORS = {
  { "V1: a duplicate index", function(i) return (i % 2 == 0) and BASELINE or '{"indices":[1,1]}' end },
  { "V2: an omitted payload", function(i) return (i % 2 == 0) and BASELINE or nil end },
  { "V3: string indices", function(i) return (i % 2 == 0) and BASELINE or '{"indices":["1","2"]}' end },
  { "V4: an array payload", function(i) return (i % 2 == 0) and BASELINE or '[]' end },
  { "V5: an out-of-range index",
    function(i) return (i % 2 == 0) and BASELINE or '{"indices":[1,2,99]}' end },
}

do
  local base_log = run_stream("SELECTING_HAND", "discard_hand", function() return BASELINE end, 40)
  check("an identical selection still reaches the repeat cap",
    count_matching(base_log, "repeated") == 10, count_matching(base_log, "repeated"))
  for _, vector in ipairs(VECTORS) do
    local log = run_stream("SELECTING_HAND", "discard_hand", vector[2], 80)
    local blocked = count_matching(log, "repeated")
    check(vector[1] .. " interleaved does not launder the streak", blocked == 10, blocked)
  end
end

do
  local PLAN = ',"plan":{"hand_plan":"p","build_plan":"b","money_plan":"m"}'
  local SELL = '{"area":"consumeables","index":1' .. PLAN .. '}'
  local base_log = run_stream("SHOP", "sell_card", function() return SELL end, 80)
  check("an identical sell still reaches the repeat cap",
    count_matching(base_log, "repeated") == 60, count_matching(base_log, "repeated"))

  local alias_log = run_stream("SHOP", "sell_card", function(i)
    return (i % 2 == 0) and SELL or ('{"area":"consumables","index":1' .. PLAN .. '}')
  end, 80)
  check("the accepted spelling of one area does not split the streak",
    count_matching(alias_log, "repeated") == 60, count_matching(alias_log, "repeated"))

  local name_log = run_stream("SHOP", "sell_card", function(i)
    return (i % 2 == 0) and SELL
      or ('{"area":"consumeables","index":1,"name":"The Fool"' .. PLAN .. '}')
  end, 80)
  check("the optional target confirmation does not split the streak",
    count_matching(name_log, "repeated") == 60, count_matching(name_log, "repeated"))
end

done()
