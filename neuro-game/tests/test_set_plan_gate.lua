_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("set-plan-gate")

local Tuning = require("core.config")

local function fresh_G()
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    P_BLINDS = {},
    GAME = {
      dollars = 8, interest_cap = 25,
      round_resets = { ante = 2, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = {},
    },
    NEURO = { once_serials = {}, shop_visit_epoch = 1, economy_epoch = 1 },
    jokers = { cards = {}, config = { card_limit = 5 } }, consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {
      { ability = { set = "Joker", name = "Joker" }, config = { center = { key = "j_joker", set = "Joker" } }, cost = 4 },
    } }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    shop = {}, FUNCS = { buy_from_shop = function() end, reroll_shop = function() end, toggle_shop = function() end },
  }
end

local Actions = require("core.actions")
Actions.is_action_valid = function(n)
  return n == "leave_shop" or n == "buy_from_shop" or n == "reroll_shop" or n == "record_plan"
end
local FS = require("force.force_shop")

local function move_line(res)
  local q = (res or {}).query or ""
  return q:match("Your move:(.*)") or ""
end
local function has_action(res, name)
  for _, a in ipairs((res or {}).actions or {}) do if a == name then return true end end
  return false
end

do
  fresh_G()
  G.NEURO.econ_plan_ok = false
  G.NEURO.shop_plan_revision_required = {}
  local res = FS.build()
  local ml = move_line(res)
  check("buy-locked: buy remains in the SDK action list", has_action(res, "buy_from_shop"), table.concat(res.actions or {}, ","))
  check("buy-locked: reroll remains in the SDK action list", has_action(res, "reroll_shop"), table.concat(res.actions or {}, ","))
  check("buy candidate embeds required money plan", ml:find('"plan":{"money_plan":"..."}', 1, true) ~= nil, ml)
  check("record_plan is not promoted as the only unlock", ml:find("record_plan", 1, true) == nil, ml)
end

do
  fresh_G()
  G.NEURO.econ_plan_ok = false
  G.NEURO.shop_plan_revision_required = { money = true }
  local res = FS.build()
  local ml = move_line(res)
  check("revision: leave_shop remains in the SDK action list", has_action(res, "leave_shop"),
    table.concat(res.actions or {}, ","))
  check("revision: toggle candidate embeds required money plan",
    ml:find('leave_shop|{"plan":{"money_plan":"..."}}', 1, true) ~= nil, ml)
  check("revision: standalone record_plan remains in the SDK list", has_action(res, "record_plan"),
    table.concat(res.actions or {}, ","))
end

do
  fresh_G()
  local PlanGate = require("core.plan_gate")
  G.NEURO.econ_plan_ok = true
  G.NEURO.shop_plan_revision_required = {}
  G.NEURO.plan = { money = "hold for interest", money_scope = PlanGate.current_economy_scope() }
  local res = FS.build()
  local ml = move_line(res)
  check("unconstrained: buy_from_shop is offered (not locked)", has_action(res, "buy_from_shop"),
    table.concat(res.actions or {}, ","))
  check("unconstrained: record_plan is NOT pushed as a move bullet (avoids spam)",
    ml:find("record_plan", 1, true) == nil, ml)
  check("unconstrained: record_plan still available in the SDK list for optional use",
    has_action(res, "record_plan"), table.concat(res.actions or {}, ","))
end

done()
