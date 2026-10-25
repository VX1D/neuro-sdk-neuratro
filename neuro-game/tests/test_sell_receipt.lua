require("tests.stubs").setup({ love = "lazy" })
local ES = require("tests.engine_cards").states()
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} },
  STATES = ES, STATE = ES.SHOP, TIMERS = { REAL = 100 } }

local D = require("core.dispatcher")
G.NEURO.dispatcher = D
G.NEURO.state = "SHOP"

local check, done = require("tests.helpers").harness("sell-receipt")

local function jk(nm)
  return require("tests.engine_cards").card({ ability = { set = "Joker", name = nm }, sell_cost = 2,
    config = { center = { key = "j_" .. nm:lower():gsub(" ", "_"), set = "Joker", loc_txt = { name = nm } } } })
end

local function pump()
  local Staging = require("core.staging")
  for _ = 1, 300 do
    if not require("core.execute").busy() then return end
    G.TIMERS.REAL = G.TIMERS.REAL + 0.25
    Staging.update()
    require("core.execute").step(G.TIMERS.REAL)
  end
end
local PlanGate = require("core.gate")
local function arm_sell_plan()
  G.NEURO.plan = {
    build = "Keep the remaining jokers.",
    build_scope = PlanGate.current_build_scope(),
    money = "Sell the selected joker.",
    money_scope = PlanGate.current_economy_scope(),
  }
  G.NEURO.econ_plan_ok = true
end

local DecisionDelta = require("facts.decision_delta")
local function force_delivered()
  local _, candidate = DecisionDelta.for_force("SHOP")
  DecisionDelta.commit(candidate)
end
local function sell_for_cash(e)
  for i, card in ipairs(G.jokers.cards) do
    if card == e.config.ref_table then
      table.remove(G.jokers.cards, i)
      G.GAME.dollars = G.GAME.dollars + card.sell_cost
      break
    end
  end
end

do
  G.GAME.dollars = 5
  G.jokers = { cards = { jk("Green Joker"), jk("Abstract Joker"), jk("Ice Cream") },
    config = { card_limit = 5 } }
  G.FUNCS.sell_card = sell_for_cash
  force_delivered()
  arm_sell_plan()
  local _, review = D.get_action_handler("sell_card")({ area = "jokers", index = 1,
    name = "Green Joker" })
  require("core.gate").delivered(review)
  local results, contexts = {}, {}
  local bridge = {
    send_action_result = require("tests.helpers").result_log(results, { "id", "ok", "msg", "reason" }),
    send_context = function(_, msg) contexts[#contexts + 1] = msg return true end,
  }
  require("tests.helpers").stage_registered(nil, { "sell_card" })
  D.route_message({ command = "action",
    data = { id = "sr-1", name = "sell_card", data = '{"area":"jokers","index":1,"name":"Green Joker"}' } }, bridge)
  pump()
  check("sell result acknowledges validated admission before execution, with no prose",
    results[1] and results[1].ok == true
      and results[1].reason == "ACTION_ACCEPTED"
      and results[1].msg == nil,
    results[1] and results[1].msg)
  check("the sale sends no context", contexts[1] == nil, tostring(contexts[1]))
  local delta = DecisionDelta.for_force("SHOP") or ""
  check("the next force's state carries the sale: the joker gone and its price banked",
    delta:find("jokers lost Green Joker", 1, true) ~= nil and delta:find("money $5 to $7 (+$2)", 1, true) ~= nil,
    delta)
end

do
  G.TIMERS.REAL = G.TIMERS.REAL + 30
  G.jokers = { cards = { jk("Lusty Joker") }, config = { card_limit = 5 } }
  G.GAME.dollars = 7
  force_delivered()
  arm_sell_plan()
  local _, review = D.get_action_handler("sell_card")({ area = "jokers", index = 1,
    name = "Lusty Joker" })
  require("core.gate").delivered(review)
  G.FUNCS.sell_card = sell_for_cash
  local results, contexts = {}, {}
  local bridge = {
    send_action_result = require("tests.helpers").result_log(results, { "id", "ok", "msg", "reason" }),
    send_context = function(_, msg) contexts[#contexts + 1] = msg return true end,
  }
  require("tests.helpers").stage_registered(nil, { "sell_card" })
  D.route_message({ command = "action",
    data = { id = "sr-2", name = "sell_card", data = '{"area":"jokers","index":1,"name":"Lusty Joker"}' } }, bridge)
  pump()
  check("last-joker result acknowledges validated admission before execution, with no prose",
    results[1] and results[1].ok == true
      and results[1].reason == "ACTION_ACCEPTED"
      and results[1].msg == nil,
    results[1] and results[1].msg)
  check("the last-joker sale sends no context", contexts[1] == nil, tostring(contexts[1]))
  local delta = DecisionDelta.for_force("SHOP") or ""
  check("and the next force's state carries it",
    delta:find("jokers lost Lusty Joker", 1, true) ~= nil and delta:find("money $7 to $9 (+$2)", 1, true) ~= nil,
    delta)
end

done()
