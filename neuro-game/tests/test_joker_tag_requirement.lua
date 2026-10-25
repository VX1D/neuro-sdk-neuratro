require("tests.stubs").setup({ love = "lazy" })
local ES = require("tests.engine_cards").states()

local Actions = require("core.actions")
local CardUtil = require("facts.card_util")
local H = require("handlers.plan_handlers").handle_record_joker_roles

local check, done = require("tests.helpers").harness("joker-tag-requirement")

local function jk(key, sid, name)
  return { config = { center = { key = key, name = name or key } },
    ability = { set = "Joker", name = name or key }, sort_id = sid, sell_cost = 3 }
end

local function shop(jokers, intents)
  _G.G = {
    STATE = ES.SHOP, STATES = ES,
    GAME = { round_resets = { ante = 2 }, dollars = 4, modifiers = {}, current_round = {} },
    NEURO = { joker_intents = intents or {}, run_generation = 1,
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
check("an empty roster leaves leave_shop on the list", offered("leave_shop"))

local Dispatcher = require("core.dispatcher")
shop({ jk("j_blueprint", 101, "Blueprint"), jk("j_ice_cream", 102, "Ice Cream") })
check("untagged jokers count", CardUtil.untagged_joker_count() == 2, CardUtil.untagged_joker_count())
check("an untagged roster keeps leave_shop on the list", offered("leave_shop"))
check("record_joker_roles stays usable so the requirement is satisfiable either way", offered("record_joker_roles"))
check("other shop actions are untouched", offered("sell_card") and offered("reroll_shop"))
local bare, why = Dispatcher.preflight("leave_shop", {})
check("leaving with untagged jokers is refused and changes nothing", bare == nil, tostring(bare))
check("the refusal states the fact and names the intents way out",
  type(why) == "string" and why:find("these jokers carry none: 1, 2.", 1, true) ~= nil
    and why:find("`intents`", 1, true) ~= nil, tostring(why))

tag(1, "CORE")
local partial, partial_why = Dispatcher.preflight("leave_shop", {})
check("a partly tagged roster names only the joker still untagged",
  partial == nil and tostring(partial_why):find("these jokers carry none: 2.", 1, true) ~= nil, tostring(partial_why))
local covered = Dispatcher.preflight("leave_shop", { intents = { { index = 2, tag = "SCALING" } } })
check("leave_shop carrying the missing tag is admitted", type(covered) == "function", tostring(covered))
covered()
check("running it records the carried tag before leaving", CardUtil.untagged_joker_count() == 0,
  CardUtil.untagged_joker_count())

tag(2, "SCALING")
check("leave_shop stays on the list once every joker carries a tag", offered("leave_shop"),
  table.concat(Actions.get_valid_actions_for_state("SHOP"), ","))
check("and it is admitted without intents", type(Dispatcher.preflight("leave_shop", {})) == "function")

done()
