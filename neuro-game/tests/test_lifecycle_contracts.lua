_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("lifecycle contracts")

local states = { SHOP = 1, BLIND_SELECT = 2, SELECTING_HAND = 3 }
local function game(state)
  _G.G = {
    STATE = states[state], STATES = states,
    GAME = {
      dollars = 12, blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = {
        ante = 2,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
    },
    NEURO = {
      run_generation = 5, economy_epoch = 0, shop_visit_epoch = 0,
      _decision_windows = {}, once_serials = {}, decision_serial = 1, state_enter_serial = 1,
    },
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
end

game("SHOP")
local Dispatcher = require("core.dispatcher")
local TxCache = require("core.tx_cache")
local Lifecycle = require("core.neuro_lifecycle")

local results = {}
local bridge = {
  send_action_result = function(_, id, ok, message, code)
    results[#results + 1] = { id = id, ok = ok, message = message, code = code }
  end,
}
do
  local FS = require("core.force_state")
  FS.arm(G.NEURO.state or "SHOP", { "record_plan" }, { record_plan = true }, 0)
  FS.mark_sent(0)
  G.NEURO.force_generation = 4
end
Dispatcher.route_message({
  command = "action",
  data = { id = "stale", name = "record_plan", data = {} },
}, bridge)
check("generation: stale inbound action is rejected before dispatch",
  #results == 1 and results[1].code == "STALE_GENERATION",
  results[1] and results[1].code)
check("generation: a rejection does not re-arm the force",
  results[1] and results[1].ok == true, results[1] and tostring(results[1].ok))
G.NEURO.force_generation = G.NEURO.run_generation
Dispatcher.route_message({
  command = "action",
  data = { id = "current", name = "record_plan", data = {} },
}, bridge)
check("generation: an answer to an offer asked in the current generation passes the gate",
  #results == 2 and results[2].code ~= "STALE_GENERATION", results[2] and results[2].code)

TxCache.store("same-id", true, "generation five")
check("tx cache: current generation finds its transaction", TxCache.get("same-id") ~= nil)
G.NEURO.run_generation = 6
check("tx cache: identical id replays across run generations in one SDK session",
  TxCache.get("same-id") ~= nil)
G.NEURO.run_generation = 5

local description = Lifecycle.registry.describe()
local hooks = {}
for _, name in ipairs(description.run.hooks or {}) do hooks[name] = true end
check("lifecycle: module-owned state has centralized reset hooks",
  hooks.dispatcher and hooks.enforce and hooks.orchestrator and hooks.staging and hooks.transition_guard)
G.NEURO.reserved_dollars = 9
TxCache.store("run-reset-id", true, "settled before run reset")
G.NEURO.joker_intents_ack_identity = "old-intents-ack"
local before_generation = G.NEURO.run_generation
Lifecycle.reset_run_state()
check("lifecycle: reset clears run fields and advances generation",
  G.NEURO.run_generation == before_generation + 1
    and G.NEURO.reserved_dollars == nil)
check("lifecycle: run reset preserves settled action ids for transport redelivery",
  TxCache.get("run-reset-id") ~= nil)
local replayed = {}
Dispatcher.route_message({
  command = "action", run_generation = G.NEURO.run_generation,
  data = { id = "run-reset-id", name = "record_plan", data = {} },
}, {
  send_action_result = function(_, id, ok, message)
    replayed[#replayed + 1] = { id = id, ok = ok, message = message }
  end,
})
check("lifecycle: redelivery after run reset replays the settled result without fresh dispatch",
  #replayed == 1 and replayed[1].id == "run-reset-id"
    and replayed[1].ok == true and replayed[1].message == "settled before run reset",
  replayed[1] and tostring(replayed[1].message) or #replayed)
check("lifecycle: reservation epoch is tied to generation",
  G.NEURO._reservation_epoch == G.NEURO.run_generation)
check("lifecycle: acknowledgement identities are cleared between runs",
  G.NEURO.joker_intents_ack_identity == nil)

do
  local Orchestrator = require("core.orchestrator")
  local TokenLegends = require("facts.token_legends")
  local emitted = {}
  G.NEURO.send_context = function(_, msg, _, receipt)
    emitted[#emitted + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  Orchestrator._emit_state_glossary("SHOP")
  check("glossary: the first pass of a run delivers the common legend",
    emitted[1] == TokenLegends.READABLE_COMMON, emitted[1])
  emitted = {}
  Orchestrator._emit_state_glossary("SHOP")
  check("glossary: a second pass within the same run stays silent",
    #emitted == 0, #emitted)
  Lifecycle.reset_run_state()
  emitted = {}
  Orchestrator._emit_state_glossary("SHOP")
  check("glossary: a run reset does not duplicate immutable transport memory",
    #emitted == 0, emitted[1])
end

local PlanGate = require("core.plan_gate")
local PlanHandler = require("handlers.plan_handlers").handle_record_plan
G.STATE = states.SHOP
G.NEURO.economy_epoch = 0
G.NEURO.shop_visit_epoch = 0
PlanGate.enter_shop()
local write_plan, plan_err = PlanHandler({
  hand_plan = "Play the current blind",
  build_plan = "Add reliable chips",
  money_plan = "Hold enough for interest",
})
check("plan epochs: plan transaction accepted", type(write_plan) == "function", plan_err)
if write_plan then write_plan() end
check("plan epochs: freshly written dependencies are current",
  PlanGate.money_plan_is_current(G.NEURO.plan)
    and PlanGate.build_plan_is_current(G.NEURO.plan))
local economy_before = G.NEURO.economy_epoch
PlanGate.mark_shop_changed("buy_from_shop")
check("plan epochs: a plain purchase leaves the economy dependency alone",
  G.NEURO.economy_epoch == economy_before
    and PlanGate.money_plan_is_current(G.NEURO.plan))
PlanGate.mark_shop_changed("reroll_shop")
check("plan epochs: a reroll invalidates it -- it destroys the options the plan named",
  G.NEURO.economy_epoch == economy_before + 1
    and not PlanGate.money_plan_is_current(G.NEURO.plan))
G.jokers.cards = { { config = { center = { key = "j_changed" } } } }
check("plan epochs: roster change invalidates build dependency",
  not PlanGate.build_plan_is_current(G.NEURO.plan))

G.STATE = states.BLIND_SELECT
G.NEURO.blind_plan_ok = false
local DecisionWindow = require("core.decision_window")
local small = PlanGate.action_requirements("BLIND_SELECT", "select_blind").plan
check("decision scope: small blind requests inline hand and build plans",
  small.hand and small.build and DecisionWindow.evaluate("select_blind") == false)
G.GAME.blind_on_deck = "Big"
G.GAME.round_resets.blind_states.Small = "Defeated"
G.GAME.round_resets.blind_states.Big = "Select"
check("decision scope: Big Blind identity invalidates the previous hand plan",
  PlanGate._test.blind_needs_plan() == true)
G.GAME.blind_on_deck = "Boss"
G.GAME.round_resets.blind_states.Big = "Defeated"
G.GAME.round_resets.blind_states.Boss = "Select"
local boss = PlanGate.action_requirements("BLIND_SELECT", "select_blind").plan
check("decision scope: boss identity requests its own inline plans",
  boss.hand and boss.build and DecisionWindow.evaluate("select_blind") == false)

done()
