_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("joker-order-requirement")

local PlanGate = require("core.plan_gate")
local PlanTransaction = require("core.plan_transaction")
local DecisionWindow = require("core.decision_window")

local function xmult(key, value)
  return { config = { center = { key = key, name = key } },
    ability = { set = "Joker", name = key, x_mult = value }, sort_id = key, sell_cost = 3 }
end
local function flat(key, value)
  return { config = { center = { key = key, name = key } },
    ability = { set = "Joker", name = key, mult = value }, sort_id = key, sell_cost = 3 }
end

local function shop(cards)
  local intents = {}
  for _, c in ipairs(cards) do intents[c.sort_id] = { tag = "CORE" } end
  _G.G = {
    STATE = 2, STATES = { SHOP = 2, BLIND_SELECT = 3 },
    GAME = { round_resets = { ante = 2, blind_choices = {} }, dollars = 8, modifiers = {},
      current_round = {} },
    NEURO = { state = "SHOP", _decision_windows = {}, run_generation = 1, shop_visit_epoch = 1,
      economy_epoch = 1, joker_intents = intents },
    jokers = { cards = cards, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop = { cards = {} }, shop_jokers = { cards = {} },
    FUNCS = { toggle_shop = function() end },
  }
end

local function requires_order()
  return PlanGate.action_requirements("SHOP", "leave_shop").joker_order ~= nil
end

local function leave(data)
  local tx, err = PlanTransaction.prepare("leave_shop", data or {})
  return tx, err
end

shop({ flat("j_joker", 4), xmult("j_cavendish", 3) })
check("a +Mult joker ahead of the xMult is already the best order, so nothing is required",
  not requires_order())
local _, err = leave()
check("that order leaves the shop without a confirmation", err == nil, err and err.message)

shop({ xmult("j_cavendish", 3), flat("j_joker", 4) })
check("a +Mult joker behind the xMult makes the confirmation required", requires_order())

local _, blocked = leave()
check("leave_shop is refused while the order is unconfirmed",
  blocked ~= nil and blocked.reason_code == "PRECONDITION_FAILED",
  blocked and (tostring(blocked.reason_code) .. " " .. tostring(blocked.message)))
check("the refusal names both slots and the two ways out",
  blocked ~= nil and blocked.message:find("slot 2", 1, true)
    and blocked.message:find("slot 1", 1, true)
    and blocked.message:find("set_joker_order", 1, true)
    and blocked.message:find("joker_order_confirmed", 1, true),
  blocked and blocked.message)

check("confirming the order lets leave_shop through", select(2, leave({ joker_order_confirmed = true })) == nil)
check("the confirmation is remembered, so the same order is not asked about twice",
  not requires_order())
check("a plain leave_shop passes once the order is confirmed", select(2, leave()) == nil)

G.jokers.cards = { xmult("j_cavendish", 3), flat("j_joker", 4), flat("j_greedy_joker", 3) }
check("a changed arrangement asks again rather than riding the old confirmation", requires_order())

G.jokers.cards = { flat("j_joker", 4), flat("j_greedy_joker", 3), xmult("j_cavendish", 3) }
check("rearranging so every +Mult fires first satisfies the gate without a confirmation",
  not requires_order() and select(2, leave()) == nil)

shop({ xmult("j_cavendish", 3), flat("j_joker", 4) })
leave({ joker_order_confirmed = true })
check("the confirmation is scoped to the shop visit", requires_order() == false)
PlanGate.enter_shop()
check("the next shop visit asks about the same order again", requires_order())

check("the soft order nudge stands down while the required gate holds the exit",
  DecisionWindow.evaluate("leave_shop") == false)

shop({ flat("j_joker", 4), xmult("j_cavendish", 3) })
check("the soft order nudge still covers a roster with no inversion",
  DecisionWindow.evaluate("leave_shop") == "soft_reject")

shop({ xmult("j_cavendish", 3), flat("j_joker", 4) })
local force = require("force.force_shop").build()
check("the shop force advertises the confirmation on leave_shop itself",
  force ~= nil and force.query:find("joker_order_confirmed", 1, true) ~= nil,
  force and force.query)

done()
