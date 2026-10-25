require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("preflight-refusals")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local Window = require("core.window")
local TxCache = require("core.bridge").tx
local Registry = require("core.action_registry")
local ActionSchema = require("core.action_schema")

local function has(text, needle) return type(text) == "string" and text:find(needle, 1, true) ~= nil end

local sends = 0
local function send(name, data)
  sends = sends + 1
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  local results = {}
  local bridge = G.NEURO
  bridge.send_action_result = Helpers.result_log(results, { "id", "ok", "message" }, true)
  bridge.withdraw_actions = Helpers.yes
  local id = "pre-" .. sends
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), bridge)
  require("core.execute").step(G.TIMERS.REAL)
  return results
end

local function captured_prints(fn)
  local lines, real = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, "\t")
  end
  local ok, err = pcall(fn)
  print = real
  assert(ok, err)
  return lines
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.jokers.cards = { LB.joker("j_joker", 901), LB.joker("j_greedy_joker", 902) }
  FP.build("SHOP")
  Registry.bind_preflight("set_joker_order", function()
    local t = nil
    return t.boom
  end)
  local results
  local lines = captured_prints(function() results = send("set_joker_order", { from_index = 1, to_index = 2 }) end)
  local r = results[1] or {}
  check("exception in a validator: exactly one result", #results == 1, #results)
  check("exception in a validator: failing result", r.ok == false, tostring(r.ok))
  check("exception text carries no Lua error detail",
    type(r.message) == "string" and not has(r.message, "attempt to") and not r.message:find("%.lua")
      and not has(r.message, "Action validation failed"), r.message)
  local logged = false
  for _, l in ipairs(lines) do
    if has(l, "[neuro-game]") and has(l, "attempt to") then logged = true end
  end
  check("the raw exception is logged with the [neuro-game] prefix", logged, table.concat(lines, "|"))
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.jokers.cards = { LB.joker("j_joker", 901), LB.joker("j_greedy_joker", 902) }
  FP.build("SHOP")
  Registry.bind_preflight("set_joker_order", function() return nil end)
  local results = send("set_joker_order", { from_index = 1, to_index = 2 })
  local r = results[1] or {}
  check("reasonless refusal: one failing result",
    #results == 1 and r.ok == false, r.message)
end

do
  local function def(name) return { name = name, description = "d" } end
  for _, good in ipairs({ "play_hand", "play-hand", "a1", "x" }) do
    check("action name accepted: " .. good, ActionSchema.valid_definition(def(good)) == true)
  end
  for _, bad in ipairs({ "playHand", "Play_hand", "play hand", "play.hand", "", "é" }) do
    check("action name rejected: '" .. bad .. "'", ActionSchema.valid_definition(def(bad)) == false)
  end
end

done()
