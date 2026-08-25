_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local Actions = require("core.actions")
local Enforce = require("core.enforce")
local CardUtil = require("facts.card_util")
local H = require("handlers.plan_handlers").handle_set_joker_intents

local check, done = require("tests.helpers").harness("joker-tag-requirement")

local function jk(key, sid, name)
  return { config = { center = { key = key, name = name or key } },
    ability = { set = "Joker", name = name or key }, sort_id = sid, sell_cost = 3 }
end

local function shop(jokers, intents)
  _G.G = {
    STATE = 2, STATES = { SHOP = 2, BLIND_SELECT = 3 },
    GAME = { round_resets = { ante = 2 }, dollars = 4, modifiers = {}, current_round = {} },
    NEURO = { _decision_windows = {}, joker_intents = intents or {}, run_generation = 1,
      shop_entry_dollars = 4, shop_visit_epoch = 1 },
    jokers = { cards = jokers, config = { card_limit = 5 } },
    shop = { cards = {} },
    FUNCS = { toggle_shop = function() end },
  }
end

local function tag(index, t)
  local exec = H({ intents = { { index = index, tag = t } } })
  if type(exec) == "function" then exec() end
end

local function offered(name)
  for _, n in ipairs(Actions.get_valid_actions_for_state("SHOP")) do
    if n == name then return true end
  end
  return false
end

shop({})
check("an empty roster leaves toggle_shop on the list", offered("toggle_shop"))

shop({ jk("j_blueprint", 101, "Blueprint"), jk("j_ice_cream", 102, "Ice Cream") })
check("untagged jokers count", CardUtil.untagged_joker_count() == 2, CardUtil.untagged_joker_count())
check("an untagged roster takes toggle_shop off the offered list", not offered("toggle_shop"))
check("set_joker_intents stays offered so the requirement is satisfiable", offered("set_joker_intents"))
check("other shop actions are untouched", offered("sell_card") and offered("reroll_shop"))

tag(1, "CORE")
check("a partly tagged roster still withholds toggle_shop", not offered("toggle_shop"))

tag(2, "SCALING")
check("toggle_shop returns once every joker carries a tag", offered("toggle_shop"),
  table.concat(Actions.get_valid_actions_for_state("SHOP"), ","))

shop({ jk("j_blueprint", 101, "Blueprint") })
local ok, msg = Enforce.pre_action(nil, "toggle_shop")
check("a late toggle_shop is refused", ok == false)
check("the refusal states the fact and names the way out",
  type(msg) == "string" and msg:find("carry no tag", 1, true) ~= nil
    and msg:find("set_joker_intents", 1, true) ~= nil, msg)

done()
