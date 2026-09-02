_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("untagged-joker-naming")

local Enforce = require("core.enforce")

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
    STATE = 2, STATES = { SHOP = 2 },
    GAME = { round_resets = { ante = 2 }, dollars = 4, modifiers = {}, current_round = {} },
    NEURO = { _decision_windows = {}, joker_intents = intents, run_generation = 1,
      shop_entry_dollars = 4, shop_visit_epoch = 1 },
    jokers = { cards = jokers, config = { card_limit = 5 } },
    shop = { cards = {} },
    FUNCS = { toggle_shop = function() end },
  }
end

local function indices()
  return table.concat(Enforce.untagged_joker_indices(), ",")
end

shop({ 4 })
check("the untagged joker is identified by its roster index, not by a count",
  indices() == "4", indices())
check("one untagged joker still names the index",
  Enforce.untagged_joker_prose() == "Jokers that carry no tag: 4",
  tostring(Enforce.untagged_joker_prose()))
check("and the verb agrees with the subject in every count (was: '1 joker carry no tag')",
  tostring(Enforce.untagged_joker_prose()):find("1 joker carry", 1, true) == nil,
  tostring(Enforce.untagged_joker_prose()))

shop({ 4, 5 })
check("two untagged jokers are both named",
  Enforce.untagged_joker_prose() == "Jokers that carry no tag: 4 and 5",
  tostring(Enforce.untagged_joker_prose()))

shop({ 2, 4, 5 })
check("three untagged jokers are listed in roster order",
  Enforce.untagged_joker_prose() == "Jokers that carry no tag: 2, 4 and 5",
  tostring(Enforce.untagged_joker_prose()))

shop({})
check("a fully tagged roster states nothing", Enforce.untagged_joker_prose() == nil,
  tostring(Enforce.untagged_joker_prose()))

local CardUtil = require("facts.card_util")
for _, set in ipairs({ { 4 }, { 4, 5 }, { 2, 4, 5 }, {}, { 1, 2, 3, 4, 5 } }) do
  shop(set)
  check("count and index list agree for {" .. table.concat(set, ",") .. "}",
    CardUtil.untagged_joker_count() == #Enforce.untagged_joker_indices(),
    CardUtil.untagged_joker_count() .. " vs " .. #Enforce.untagged_joker_indices())
end

shop({ 4 })
local ok, msg = Enforce.pre_action(nil, "leave_shop")
check("a late leave_shop is still refused", ok == false)
check("the refusal names the index that holds the gate",
  type(msg) == "string" and msg:find("Jokers that carry no tag: 4", 1, true) ~= nil, tostring(msg))
check("the refusal never states a bare count the model can read as an index",
  type(msg) == "string" and msg:find("%d joker[s]? carry") == nil, tostring(msg))

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local TxCache = require("core.tx_cache")
  local ForceHelpers = require("force.force_helpers")
  love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

  shop({ 4 })
  G.TIMERS = { REAL = 100 }
  G.STATES = { SHOP = 5, SELECTING_HAND = 4 }
  G.STATE = 5
  G.STATE_COMPLETE = true
  G.shop_jokers = { cards = {} }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } }
  G.deck = { cards = {} }
  G.GAME.dollars = 10
  G.GAME.used_vouchers = {}
  G.GAME.current_round = { hands_left = 4, discards_left = 2 }
  G.GAME.hands = {}
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  TxCache.reset()
  G.NEURO.enabled = true
  G.NEURO.decision_serial = 1
  G.NEURO.persona = "neuro"
  G.NEURO.dispatcher = Dispatcher
  G.NEURO.actions = Actions
  G.NEURO.send_context = function() return true end
  require("tests.helpers").stage_registered("SHOP", { "leave_shop" })
  G.NEURO.force_inflight = false

  local b = { results = {} }
  function b:send_context() return true end
  function b:send_action_result(id, okv, message, reason)
    self.results[#self.results + 1] = { id = id, ok = okv, message = message, reason = reason }
  end
  b.register_actions = function() end
  b.unregister_actions = function() end
  b.is_transition_cooldown = function() return false end

  Dispatcher.route_message({ command = "action",
    data = { id = "utj-1", name = "leave_shop", data = "{}" } }, b)

  check("the gated leave_shop is refused on the wire",
    #b.results > 0 and b.results[#b.results].ok == false,
    b.results[#b.results] and tostring(b.results[#b.results].reason) or "none")
  check("the correction channel itself carries the cause, not the generic state sentence",
    type(G.NEURO.last_failed_correction) == "string"
      and G.NEURO.last_failed_correction:find("Jokers that carry no tag: 4", 1, true) ~= nil,
    tostring(G.NEURO.last_failed_correction))
  check("the correction does not stop at the generic not-in-this-state sentence",
    type(G.NEURO.last_failed_correction) == "string"
      and G.NEURO.last_failed_correction:find("isn't available in the current state", 1, true) == nil,
    tostring(G.NEURO.last_failed_correction))
  local warning = ForceHelpers.failed_action_warning()
  check("the next force carries the actionable cause, not only 'not available in this state'",
    warning:find("Jokers that carry no tag: 4", 1, true) ~= nil, warning)
  check("and it names the way out",
    warning:find("record_joker_roles", 1, true) ~= nil, warning)
end

done()
