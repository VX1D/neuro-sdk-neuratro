_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("action contracts")

local states = { SHOP = 1, SELECTING_HAND = 2, BLIND_SELECT = 3 }
_G.G = {
  STATE = states.SHOP, STATES = states,
  GAME = {
    dollars = 10,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = {
      ante = 1, blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
    },
  },
  NEURO = { reserved_dollars = 0, run_generation = 1 },
  FUNCS = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  shop = {}, shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  P_BLINDS = {
    bl_small = { key = "bl_small", name = "Small Blind" },
    bl_big = { key = "bl_big", name = "Big Blind" },
    bl_boss = { key = "bl_boss", name = "Boss Blind" },
  },
}

local Dispatcher = require("core.dispatcher")
local Registry = require("core.action_registry")
local Result = require("core.action_result")
local Actions = require("core.actions")

check("contracts: registry is populated (guards the assertions below from passing vacuously)",
  #Registry.names() >= 20, tostring(#Registry.names()))

local registry_ok, registry_errors = Registry.validate({ require_preflights = true })
check("contracts: every action has schema, prompt, availability and preflight",
  registry_ok, table.concat(registry_errors or {}, "; "))
check("contracts: dispatcher schema is registry schema",
  Dispatcher._test.get_action_schema("use_card") == Registry.get("use_card").schema)
local select_prompt = Registry.prompt("select_blind")
check("contracts: prompt derives enum from schema",
  select_prompt:find('"small"|"big"|"boss"', 1, true) ~= nil, select_prompt)

local chariot = {
  ability = { set = "Tarot", consumeable = { min_highlighted = 1, max_highlighted = 1 } },
  config = { center = { key = "c_chariot", set = "Tarot", name = "The Chariot" } },
}
G.consumeables.cards = { chariot }
check("preflight parity: targeted consumable has no advertised candidate without hand",
  #Registry.candidates("use_card") == 0 and not Actions.is_action_valid("use_card"))
local use_exec, use_err = Dispatcher.preflight("use_card", { area = "consumeables", index = 1 })
check("typed errors: missing consumable target is INVALID_SELECTION or TARGET_UNAVAILABLE",
  use_exec == nil and Result.is_error(use_err)
    and (use_err.reason_code == "INVALID_SELECTION" or use_err.reason_code == "TARGET_UNAVAILABLE"),
  use_err and use_err.reason_code)

G.consumeables.cards = {}
local joker = {
  cost = 4,
  ability = { set = "Joker", name = "Plain Joker" },
  config = { center = { key = "j_plain", set = "Joker", name = "Plain Joker" } },
}
G.shop_jokers.cards = { joker }
local before_reserved = G.NEURO.reserved_dollars
local buys = Registry.candidates("buy_from_shop")
check("preflight purity: enumerating buy candidates does not reserve money",
  G.NEURO.reserved_dollars == before_reserved)
check("preflight parity: affordable exact shop target is advertised",
  #buys == 1 and buys[1].area == "shop_jokers" and buys[1].index == 1)
local buy_exec, buy_err = Dispatcher.preflight("buy_from_shop", buys[1])
check("preflight parity: every advertised buy target passes commit preflight",
  type(buy_exec) == "function", buy_err and buy_err.message or buy_err)
check("preflight purity: direct buy preflight does not reserve money",
  G.NEURO.reserved_dollars == before_reserved)

joker.cost = 20
local expensive = Registry.candidates("buy_from_shop")
local expensive_exec, expensive_err = Dispatcher.preflight("buy_from_shop", { area = "shop_jokers", index = 1 })
check("preflight parity: unaffordable target is not advertised", #expensive == 0)
check("typed errors: affordability has stable reason code",
  expensive_exec == nil and Result.is_error(expensive_err)
    and expensive_err.reason_code == "INSUFFICIENT_FUNDS", expensive_err and expensive_err.reason_code)

local unknown_exec, unknown_err = Registry.preflight("not_an_action", {})
check("typed errors: missing contract preflight is stable",
  unknown_exec == nil and Result.is_error(unknown_err)
    and unknown_err.reason_code == "ACTION_UNAVAILABLE")

G.jokers.cards = { { ability = { set = "Joker", name = "Plain Joker" },
  config = { center = { key = "j_plain", set = "Joker" } } } }
G.STATE = states.SELECTING_HAND
G.GAME.blind = { key = "bl_pillar", name = "The Pillar", debuff = {} }
check("sell_card stays unavailable mid-hand for a boss other than Verdant Leaf",
  not Actions.is_action_valid("sell_card"))
G.GAME.blind = { key = "bl_final_leaf", name = "Verdant Leaf", debuff = {} }
check("sell_card becomes available mid-hand for Verdant Leaf (the only way to lift its all-debuff)",
  Actions.is_action_valid("sell_card"))
G.STATE = states.SHOP
G.GAME.blind = nil
G.jokers.cards = {}

do
  local Config = require("core.config")
  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "off")
  local off_schema = Dispatcher._test.get_action_schema("confirm_play")
  check("confirm_play schema has no required reason once the always-reason flag is off",
    off_schema and off_schema.properties and off_schema.properties.reason == nil,
    off_schema and off_schema.required and table.concat(off_schema.required, ","))

  Config.set("NEURO_CONFIRM_REASON_ALWAYS", "on")
  local on_schema = Dispatcher._test.get_action_schema("confirm_play")
  check("confirm_play schema advertises reason once the always-reason flag is toggled on live",
    on_schema and on_schema.properties and on_schema.properties.reason ~= nil,
    on_schema and on_schema.required and table.concat(on_schema.required, ","))
  local only_answer = on_schema and on_schema.required
    and #on_schema.required == 1 and on_schema.required[1] == "answer"
  check("answer stays the only required field, so answer:\"no\" is never schema-rejected",
    only_answer, on_schema and on_schema.required and table.concat(on_schema.required, ","))

end

done()
