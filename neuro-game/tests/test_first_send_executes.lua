require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("first-send-executes")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local Execute = require("core.execute")
local TxCache = require("core.bridge").tx

local n = 0
local function send(name, data)
  local results = {}
  G.NEURO.send_action_result = function(_, _, ok, message, code)
    results[#results + 1] = { ok = ok, message = message, code = code }
    return true
  end
  G.NEURO.withdraw_actions = function() return true end
  n = n + 1
  local id = "first-send-" .. n
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), G.NEURO)
  return results[1] or {}
end

do
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  FP.build("SMODS_BOOSTER_OPENED")
  G.NEURO.gates = nil
  local count = #G.pack_cards.cards
  local bad = send("choose_pack_card", { area = "booster_pack", index = count + 1 })
  check("an out-of-range pick still fails with the valid range",
    bad.ok == false and tostring(bad.message):find("Use 1-" .. count, 1, true) ~= nil, tostring(bad.message))
  local first = send("choose_pack_card", { area = "booster_pack", index = 1 })
  check("pack: the first pick is admitted for execution, nothing held back",
    first.ok == true and first.code == "ACTION_ACCEPTED" and first.message == nil,
    tostring(first.code) .. " " .. tostring(first.message))
end

do
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  FP.build("SMODS_BOOSTER_OPENED")
  G.NEURO.gates = nil
  local first = send("skip_pack", nil)
  check("pack: the first skip_pack is admitted for execution, nothing held back",
    first.ok == true and first.code == "ACTION_ACCEPTED" and first.message == nil,
    tostring(first.code) .. " " .. tostring(first.message))
end

do
  LB.load("RUN_SETUP", "Run setup overlay active")
  FP.build("RUN_SETUP")
  G.NEURO.gates = nil
  G.SETTINGS = G.SETTINGS or {}
  local started = 0
  G.FUNCS.start_setup_run = function() started = started + 1 end
  local first = send("start_run", "{}")
  check("setup: the first start_run is admitted for execution, nothing held back",
    first.ok == true and first.code == "ACTION_ACCEPTED" and first.message == nil,
    tostring(first.code) .. " " .. tostring(first.message))
  pcall(Execute.step, G.TIMERS.REAL)
  check("setup: the run actually starts from that first send", started == 1, tostring(started))
end

do
  local Registry = require("core.action_registry")
  local function says_first_send_is_held(name)
    local d = tostring((Registry.get(name) or {}).description)
    return d:find("first", 1, true) ~= nil and d:find("returns a review", 1, true) ~= nil
      and (d:find("executes nothing", 1, true) ~= nil or d:find("plays nothing", 1, true) ~= nil)
  end
  require("core.config").set("NEURO_CONFIRM_HAND", "on")
  require("core.actions").get_static_actions()
  for _, name in ipairs({ "play_hand", "leave_shop", "buy_from_shop", "sell_card" }) do
    check(name .. ": the registered description says a first send can return a review and execute nothing",
      says_first_send_is_held(name), (Registry.get(name) or {}).description)
  end
end

done()
