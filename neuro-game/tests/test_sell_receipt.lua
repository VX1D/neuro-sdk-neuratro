_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} },
  STATES = { SHOP = 5 }, STATE = 5, TIMERS = { REAL = 100 } }

local D = require("core.dispatcher")
G.NEURO.dispatcher = D
G.NEURO.state = "SHOP"

local check, done = require("tests.helpers").harness("sell-receipt")

local function jk(nm)
  return { ability = { set = "Joker", name = nm }, sell_cost = 2,
    config = { center = { key = "j_" .. nm:lower():gsub(" ", "_"), set = "Joker", loc_txt = { name = nm } } } }
end

local function pump(contexts)
  local Staging = require("core.staging")
  for _ = 1, 300 do
    if #contexts > 0 then return end
    G.TIMERS.REAL = G.TIMERS.REAL + 0.25
    Staging.update()
  end
end
local PlanGate = require("core.plan_gate")
local function arm_sell_plan()
  G.NEURO.plan = {
    build = "Keep the remaining jokers.",
    build_scope = PlanGate.current_build_scope(),
    money = "Sell the selected joker.",
    money_scope = PlanGate.current_economy_scope(),
  }
  G.NEURO.econ_plan_ok = true
end

do
  G.jokers = { cards = { jk("Green Joker"), jk("Abstract Joker"), jk("Ice Cream") },
    config = { card_limit = 5 } }
  G.FUNCS.sell_card = function(e)
    for i, card in ipairs(G.jokers.cards) do
      if card == e.config.ref_table then table.remove(G.jokers.cards, i) break end
    end
  end
  G.NEURO.last_sell_reject = "sell:0:Green Joker"
  arm_sell_plan()
  local results, contexts = {}, {}
  local bridge = {
    send_action_result = function(_, id, ok, msg) results[#results + 1] = { ok = ok, msg = msg } end,
    send_context = function(_, msg) contexts[#contexts + 1] = msg return true end,
  }
  require("tests.helpers").stage_registered(nil, { "sell_card" })
  D.route_message({ command = "action",
    data = { id = "sr-1", name = "sell_card", data = '{"area":"jokers","index":1}' } }, bridge)
  pump(contexts)
  check("sell result is neutral before execution",
    results[1] and results[1].ok == true and results[1].msg == nil, results[1] and results[1].msg)
  check("legacy sale text follows execution as context",
    contexts[1] == "After the completed action 'sell_card': Sold: Green Joker for $2", contexts[1])
end

do
  G.TIMERS.REAL = G.TIMERS.REAL + 30  -- clear the inter-action cooldown
  G.jokers = { cards = { jk("Lusty Joker") }, config = { card_limit = 5 } }
  G.NEURO.last_sell_reject = "sell:0:Lusty Joker"
  G.FUNCS.sell_card = function(e)
    for i, card in ipairs(G.jokers.cards) do
      if card == e.config.ref_table then table.remove(G.jokers.cards, i) break end
    end
  end
  arm_sell_plan()
  local results, contexts = {}, {}
  local bridge = {
    send_action_result = function(_, id, ok, msg) results[#results + 1] = { ok = ok, msg = msg } end,
    send_context = function(_, msg) contexts[#contexts + 1] = msg return true end,
  }
  require("tests.helpers").stage_registered(nil, { "sell_card" })
  D.route_message({ command = "action",
    data = { id = "sr-2", name = "sell_card", data = '{"area":"jokers","index":1}' } }, bridge)
  pump(contexts)
  check("last-joker result is neutral before execution",
    results[1] and results[1].ok == true and results[1].msg == nil, results[1] and results[1].msg)
  check("last-joker legacy context follows execution",
    contexts[1] == "After the completed action 'sell_card': Sold: Lusty Joker for $2", contexts[1])
end

done()
