require("tests.stubs").setup({ love = "lazy" })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("untagged-joker-naming")

local CardUtil = require("facts.card_util")

local function jk(key, sid)
  return { config = { center = { key = key, name = key } },
    ability = { set = "Joker", name = key }, sort_id = sid, sell_cost = 3 }
end

local function shop(untagged)
  local jokers, intents, u = {}, {}, {}
  for _, i in ipairs(untagged) do u[i] = true end
  for i = 1, 5 do
    jokers[i] = jk("j_x" .. i, 100 + i)
    if not u[i] then intents[100 + i] = { tag = "CORE" } end
  end
  _G.G = {
    STATE = ES.SHOP, STATES = ES,
    GAME = { round_resets = { ante = 2 }, dollars = 4, modifiers = {}, current_round = {} },
    NEURO = { joker_intents = intents, run_generation = 1,
      shop_entry_dollars = 4, shop_visit_epoch = 1 },
    jokers = { cards = jokers, config = { card_limit = 5 } },
    shop = { cards = {} },
    FUNCS = { toggle_shop = function() end },
  }
end

local function indices()
  return table.concat(CardUtil.untagged_joker_indices(), ",")
end

shop({ 4 })
check("the untagged joker is identified by its roster index, not by a count",
  indices() == "4", indices())

shop({})
check("a fully tagged roster states nothing", CardUtil.untagged_joker_prose() == nil,
  tostring(CardUtil.untagged_joker_prose()))

for _, set in ipairs({ { 4 }, { 4, 5 }, { 2, 4, 5 }, {}, { 1, 2, 3, 4, 5 } }) do
  shop(set)
  check("count and index list agree for {" .. table.concat(set, ",") .. "}",
    CardUtil.untagged_joker_count() == #CardUtil.untagged_joker_indices(),
    CardUtil.untagged_joker_count() .. " vs " .. #CardUtil.untagged_joker_indices())
end

shop({ 4 })
local exec, msg = require("core.dispatcher").preflight("leave_shop", {})
check("a late leave_shop is still refused", exec == nil)
check("the refusal never states a bare count the model can read as an index",
  type(msg) == "string" and msg:find("%d joker[s]? carry") == nil, tostring(msg))

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local TxCache = require("core.bridge").tx
  local ForceHelpers = require("force.force_helpers")
  love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

  shop({ 4 })
  G.TIMERS = { REAL = 100 }
  require("tests.helpers").in_engine_state("SHOP")
  G.STATE_COMPLETE = true
  G.shop_jokers = { cards = {} }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } }
  G.deck = { cards = {} }
  G.GAME.dollars = 10
  G.GAME.used_vouchers = {}
  G.GAME.current_round = { hands_left = 4, discards_left = 2 }
  G.GAME.hands = {}
  require("core.validate").reset_run_state()
  TxCache.reset()
  G.NEURO.enabled = true
  G.NEURO.decision_serial = 1
  G.NEURO.persona = "neuro"
  G.NEURO.dispatcher = Dispatcher
  G.NEURO.actions = Actions
  G.NEURO.send_context = function() return true end
  require("tests.helpers").stage_registered("SHOP", { "leave_shop" })

  local b = require("tests.helpers").stub_bridge({ results = {}, send_context = "true", register_actions = "noop",
    is_transition_cooldown = "false",
    send_action_result = require("tests.helpers").result_log("results", { "id", "ok", "message", "reason" }) })

  Dispatcher.route_message({ command = "action",
    data = { id = "utj-1", name = "leave_shop", data = "{}" } }, b)

  check("the gated leave_shop is refused on the wire",
    #b.results > 0 and b.results[#b.results].ok == false,
    b.results[#b.results] and tostring(b.results[#b.results].reason) or "none")
  local told = b.results[#b.results] and tostring(b.results[#b.results].message) or ""
  check("it does not stop at the generic not-in-this-state sentence",
    told:find("isn't available in the current state", 1, true) == nil, told)
end

done()
