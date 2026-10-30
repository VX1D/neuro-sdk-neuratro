love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 300 } }

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Staging = require("core.staging")
local Lifecycle = require("core.neuro_lifecycle")
local check, done = require("tests.helpers").harness("reset-staged-action")

local play_card = require("tests.helpers").play_card

G.TIMERS.REAL = 300
require("tests.helpers").in_engine_state("SELECTING_HAND")
G.GAME = {
  dollars = 10, chips = 0, used_vouchers = {},
  current_round = { hands_left = 3, discards_left = 2 },
  round_resets = { ante = 1 },
  hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
}
G.hand = {
  cards = { play_card(1), play_card(2), play_card(3) },
  highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 },
}
G.jokers = { cards = {}, config = { card_limit = 5 } }
G.consumeables = { cards = {}, config = { card_limit = 2 } }
G.FUNCS = {
  get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
}
require("core.validate").reset_run_state()

local corrections = {}

G.NEURO = require("tests.helpers").started_bridge({
  enabled = true, persona = "neuro",
  decision_serial = 5,
  state = "SELECTING_HAND",
  state_enter_serial = 1,
  economy_epoch = 0,
  shop_visit_epoch = 0,
  last_quality_reject = "1,2",
  last_quality_review_serial = 0,
  weak_fired_serial = 0,
  once_serials = {},
  dispatcher = Dispatcher,
  actions = Actions,
  send_context = function(self, text) corrections[#corrections + 1] = tostring(text); return true end,
  register_actions = function() end,
})

Staging.reset_run_state()
require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand", "discard_hand", "resolve_play" })
require("core.bridge").tx.reset()

local bridge = {
  results = {},
  contexts = {},
  send_action_result = require("tests.helpers").result_log("results", { "id", "ok", "msg", "reason" }, true),
  send_context = function(self, msg)
    self.contexts[#self.contexts + 1] = tostring(msg)
  end,
  register_actions = function() end,
}

local function play_msg(id)
  return { command = "action",
    data = { id = id, name = "play_hand", data = '{"indices":[1,2]}' } }
end

local function confirm_msg(id)
  return { command = "action",
    data = { id = id, name = "resolve_play", data = '{"answer":"yes"}' } }
end

local Execute = require("core.execute")
Dispatcher.route_message(play_msg("reset-test-0"), bridge)
check("the first send consumes the decision window without staging anything",
  Execute.busy() == nil and bridge.results[1] and bridge.results[1].reason == "CONFIRMATION_REQUIRED")
check("the delivered confirmation becomes actionable",
  require("handlers.hand_handlers").confirm_ready())

G.TIMERS.REAL = G.TIMERS.REAL + 5
Dispatcher.route_message(confirm_msg("reset-test-1"), bridge)
check("the action is staged", Execute.busy() == "staged", tostring(Execute.busy()))
check("staging is busy", Staging.is_busy() == true)
check("staging preparation publishes the admission result before execution",
  #bridge.results == 2 and bridge.results[2].id == "reset-test-1"
    and bridge.results[2].ok == true and bridge.results[2].reason == "ACTION_ACCEPTED",
  #bridge.results)

corrections = {}
Lifecycle.reset_run_state()

check("the cancelled action is recorded as the last failure",
  G.NEURO.last_failed_action == "resolve_play",
  tostring(G.NEURO.last_failed_action))
check("last_failed_reason identifies the run reset",
  G.NEURO.last_failed_reason ~= nil
    and tostring(G.NEURO.last_failed_reason):find("run state reset", 1, true) ~= nil,
  tostring(G.NEURO.last_failed_reason))
do
  check("the staged action does not enter the retained context channel",
    #corrections == 0 and #bridge.contexts == 0,
    #corrections .. "/" .. #bridge.contexts .. " " .. tostring(corrections[1] or bridge.contexts[1]))
end

done()
