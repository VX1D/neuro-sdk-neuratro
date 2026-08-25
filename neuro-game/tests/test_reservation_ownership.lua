_G.NEURO_TEST = true
local clock = 100
if not love then love = {} end
love.timer = { getTime = function() return clock end }
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("reservation-ownership")
local Dispatcher = require("core.dispatcher")
local Enforce = require("core.enforce")
local saved_pre_action = Enforce.pre_action
Enforce.pre_action = function() return true end

local function stage_registered_actions(state)
  require("core.action_registry").note_registered(
    require("core.actions").get_valid_actions_for_state(state))
end

clock = clock + 20
_G.G = {
  STATE = 2, STATES = { MENU = 1, SHOP = 2 },
  GAME = { dollars = 20, current_round = { reroll_cost = 5, free_rerolls = 0 }, modifiers = {} },
  FUNCS = {},
  NEURO = { state = "SHOP", state_enter_serial = 1, decision_serial = 1, run_generation = 1 },
  jokers = { cards = {} },
}
local card = {
  ability = { set = "Joker", name = "Sale Joker" },
  config = { center = { key = "j_sale", set = "Joker", loc_txt = { name = "Sale Joker" } } },
  sell_cost = 3, sort_id = "j_sale",
}
G.jokers.cards = { card }
G.NEURO.last_sell_reject = "sell:1:j_sale"
G.NEURO.last_sell_review_serial = 1
stage_registered_actions("SHOP")

G.NEURO.consumed_actions = { play_hand = true }
G.NEURO.consumed_action_owner = "job-B"

local b = {
  send_action_result = function()
    return false, { status = "rejected" }
  end,
  record_action_phase = function() return true end,
  unregister_actions = function() end,
  is_transition_cooldown = function() return false end,
}
local message = {
  command = "action", run_generation = 1,
  data = { id = "sell-A", name = "sell_card",
    data = { area = "jokers", index = 1, plan = { money_plan = "sell", build_plan = "sell" } } },
}

Dispatcher.validate_message(message, b)

check("job sell-A's rollback does not release job-B's unrelated reservation",
  G.NEURO.consumed_action_owner == "job-B"
    and G.NEURO.consumed_actions and G.NEURO.consumed_actions.play_hand == true,
  "owner=" .. tostring(G.NEURO.consumed_action_owner))

local ForceState = require("core.force_state")
G.NEURO.pack_exit_pending = "job-B"
ForceState.correct_optimistic("use_card", "cancelled", "job-A", "job-A was cancelled")
check("an unrelated job's correct_optimistic does not release job-B's pack_exit_pending",
  G.NEURO.pack_exit_pending == "job-B", tostring(G.NEURO.pack_exit_pending))

ForceState.correct_optimistic("use_card", "cancelled", "job-B", "job-B was cancelled")
check("correct_optimistic still releases pack_exit_pending for its actual owner",
  G.NEURO.pack_exit_pending == nil, tostring(G.NEURO.pack_exit_pending))

Enforce.pre_action = saved_pre_action
done()
