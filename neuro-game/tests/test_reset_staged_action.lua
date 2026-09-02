love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 300 } }

local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Staging = require("core.staging")
local Lifecycle = require("core.neuro_lifecycle")
local ConfirmationEvidence = require("core.confirmation_evidence")
local check, done = require("tests.helpers").harness("reset-staged-action")

local play_card = require("tests.helpers").play_card

G.TIMERS.REAL = 300
G.STATES = { SELECTING_HAND = 4 }
G.STATE = 4
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
  get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
}
require("core.transition_guard").reset()

local corrections = {}

G.NEURO = {
  enabled = true, persona = "neuro",
  decision_serial = 5,
  state = "SELECTING_HAND",
  state_enter_serial = 1,
  economy_epoch = 0,
  shop_visit_epoch = 0,
  last_quality_reject = "1,2",
  last_quality_review_serial = 0,
  weak_fired_serial = 0,
  _decision_windows = {},
  once_serials = {},
  dispatcher = Dispatcher,
  actions = Actions,
  send_context = function(self, text) corrections[#corrections + 1] = tostring(text); return true end,
  register_actions = function() end,
  unregister_actions = function() end,
}

Staging.reset_run_state()
require("tests.helpers").stage_registered("SELECTING_HAND", { "play_hand", "discard_hand", "resolve_play" })
require("core.tx_cache").reset()

local journal_phases = {}
local bridge = {
  results = {},
  contexts = {},
  send_action_result = function(self, id, ok, msg, reason)
    self.results[#self.results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
    return true, { status = "written", kind = "test" }
  end,
  send_context = function(self, msg)
    self.contexts[#self.contexts + 1] = tostring(msg)
  end,
  register_actions = function() end,
  record_action_phase = function(_, id, name, phase, details)
    journal_phases[#journal_phases + 1] = { id = id, name = name, phase = phase, details = details }
  end,
}

local function play_msg(id)
  return { command = "action",
    data = { id = id, name = "play_hand", data = '{"indices":[1,2]}' } }
end

local function confirm_msg(id)
  local tx = require("core.hand_transaction").current()
  return { command = "action",
    data = { id = id, name = "resolve_play", data = string.format(
      '{"transaction_id":%d,"answer":"yes"}', tx.id) } }
end

check("the first send consumes the decision window",
  Staging.queue(play_msg("reset-test-0"), bridge) == false)
check("the delivered confirmation becomes actionable",
  ConfirmationEvidence.step_delivery() == true)

G.TIMERS.REAL = G.TIMERS.REAL + 5
local queued = Staging.queue(confirm_msg("reset-test-1"), bridge)
check("the action is staged", queued == true, type(queued))
check("staging is busy", Staging.is_busy() == true)
check("Neuro has already received optimistic success=true",
  #bridge.results == 2 and bridge.results[2].id == "reset-test-1" and bridge.results[2].ok == true,
  #bridge.results)

journal_phases = {}
corrections = {}
Lifecycle.reset_run_state()

check("correct_optimistic sets last_failed_action",
  G.NEURO.last_failed_action == "resolve_play",
  tostring(G.NEURO.last_failed_action))
check("last_failed_reason identifies the run reset",
  G.NEURO.last_failed_reason ~= nil
    and tostring(G.NEURO.last_failed_reason):find("run state reset", 1, true) ~= nil,
  tostring(G.NEURO.last_failed_reason))
do
  local warning = require("force.force_helpers").failed_action_warning()
  check("the correction travels on the ephemeral force channel",
    warning:find("resolve_play", 1, true) ~= nil
      and warning:find("the game state is unchanged -- choose again", 1, true) ~= nil,
    warning)
  check("the staged action does not enter the retained context channel",
    #corrections == 0 and #bridge.contexts == 0,
    #corrections .. "/" .. #bridge.contexts .. " " .. tostring(corrections[1] or bridge.contexts[1]))
end
check("the journal contains the aborted phase",
  #journal_phases > 0 and journal_phases[1].phase == "aborted",
  #journal_phases > 0 and journal_phases[1].phase)
check("the journal id matches",
  #journal_phases > 0 and journal_phases[1].id == "reset-test-1")

done()
