_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local fixture = require("tests.fixtures.first_run_failures")
local check, done = require("tests.helpers").harness("first-run replay")

local function base_game(state)
  local states = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4 }
  _G.G = {
    STATE = states[state], STATES = states,
    GAME = {
      dollars = 10, blind_on_deck = "Small", round = 11,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = {
        ante = 4,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
      blind = { name = "Big Blind" },
    },
    P_BLINDS = {
      bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_club = { key = "bl_club", name = "The Club" },
    },
    NEURO = {
      run_generation = 1, _decision_windows = {}, once_serials = {},
      decision_serial = 1, state_enter_serial = 1,
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
end

check("fixture: recovered session id", fixture.session_id == "1784708839498")
check("fixture: all historical failures lacked codes",
  fixture.source.all_failed_results == 37 and fixture.source.failed_results_with_reason_code == 0)

base_game("SHOP")
local chariot = {
  ability = { set = "Tarot", consumeable = { min_highlighted = 1, max_highlighted = 1 } },
  config = { center = { key = "c_chariot", set = "Tarot", name = "The Chariot" } },
}
G.consumeables.cards = { chariot }
local CardUtil = require("facts.card_util")
local Actions = require("core.actions")
check("replay Chariot: all four records describe zero-card hands",
  #fixture.chariot == 4 and (function() for _, row in ipairs(fixture.chariot) do if row.hand_count ~= 0 then return false end end return true end)())
check("replay Chariot: targeted consumable is not usable without hand", not CardUtil.consumable_usable_now(chariot))
check("replay Chariot: use_consumable is not advertised without any usable card", not Actions.is_action_valid("use_consumable"))
G.hand = { cards = { { base = { value = "Ace", suit = "Spades" } } } }
check("replay Chariot: same card becomes usable with a target", CardUtil.consumable_usable_now(chariot))

base_game("SHOP")
local function stack_roster(keys)
  G.jokers.cards = {}
  for _, key in ipairs(keys) do
    local ability = (key == "j_baron" or key == "j_ancient") and { x_mult = 1.5 } or { mult = 4 }
    G.jokers.cards[#G.jokers.cards + 1] = { config = { center = { key = key } }, ability = ability }
  end
end
local DecisionWindow = require("core.decision_window")
stack_roster(fixture.reorder.stable_roster)
check("replay reorder: the fixture order leaves +Mult jokers behind an xMult, so the exit gate is required",
  require("core.plan_gate").action_requirements("SHOP", "leave_shop").joker_order ~= nil)
check("replay reorder: the nudge stands down while the required gate holds the exit",
  DecisionWindow.evaluate("leave_shop") == false)
stack_roster({ "j_scary_face", "j_blue_joker", "j_walkie_talkie", "j_baron", "j_ancient" })
DecisionWindow.reset_field("order_think")
check("replay reorder: every +Mult ahead of the xMults leaves no inversion to require",
  require("core.plan_gate").action_requirements("SHOP", "leave_shop").joker_order == nil)
check("replay reorder: new roster arms review", DecisionWindow.evaluate("leave_shop") == "soft_reject")
DecisionWindow.acknowledge("leave_shop")
check("replay reorder: unchanged roster stays acknowledged", DecisionWindow.evaluate("leave_shop") == false)
G.jokers.cards[#G.jokers.cards + 1] = { config = { center = { key = "j_new" } } }
check("replay reorder: changed roster re-arms review", DecisionWindow.evaluate("leave_shop") == "soft_reject")

base_game("BLIND_SELECT")
local PlanGate = require("core.plan_gate")
local PlanHandler = require("handlers.plan_handlers").handle_record_plan
local set_small, plan_err = PlanHandler({ hand_plan = "Play the current blind" })
check("replay stale plan: initial plan accepted", type(set_small) == "function", plan_err)
if set_small then set_small() end
G.GAME.blind_on_deck = "Big"
G.GAME.round_resets.blind_states.Small = "Defeated"
G.GAME.round_resets.blind_states.Big = "Select"
PlanGate.begin_cycle()
check("replay stale plan: same-ante blind change invalidates plan", PlanGate._test.blind_needs_plan())
local blind_level = DecisionWindow.evaluate("select_blind")
local blind_required = PlanGate.action_requirements("BLIND_SELECT", "select_blind").plan
check("replay stale plan: same-ante blind change requests inline plan",
  blind_level == false and blind_required.hand and blind_required.build, blind_level)

local CtxHelpers = require("context.ctx_helpers")
local walkie = {
  ability = { set = "Joker", name = "Walkie Talkie", mult = 4, bonus = 10 },
  config = { center = {
    key = fixture.conditional_semantics.card_key, set = "Joker", name = "Walkie Talkie",
    loc_txt = { name = "Walkie Talkie", description = { "Played 10s and 4s give +10 Chips and +4 Mult" } },
  } },
}
local summary = require("core.semantic_registry").render("card_effect_summary", walkie)
check("replay semantics: Walkie trigger survives", summary:find("10s and 4s", 1, true) ~= nil, summary)
check("replay semantics: affected force accounting retained",
  fixture.conditional_semantics.affected_force_count == 111
    and fixture.conditional_semantics.state_counts.SHOP
      + fixture.conditional_semantics.state_counts.HAND
      + fixture.conditional_semantics.state_counts.OTHER == 111)

base_game("SHOP")
G.NEURO.plan = { hand = "old hand", build = "old build", money = "old money" }
local very_long = string.rep("x", 4000)
local commit = PlanHandler({ build_plan = very_long })
check("replay length: a 4000-character plan field is accepted", type(commit) == "function")
if type(commit) == "function" then commit() end
check("replay length: the field is stored verbatim, never truncated",
  G.NEURO.plan.build == very_long, #tostring(G.NEURO.plan.build))
check("replay length: the untouched fields are left alone",
  G.NEURO.plan.hand == "old hand" and G.NEURO.plan.money == "old money")

base_game("GAME_OVER")
local Rewards = require("core.rewards")
local Lifecycle = require("core.neuro_lifecycle")
local first_loss = Rewards.outcome("SELECTING_HAND", "GAME_OVER")
local duplicate_loss = Rewards.outcome("SELECTING_HAND", "GAME_OVER")
check("replay lifecycle: terminal outcome is idempotent", first_loss ~= nil and duplicate_loss == nil)
local old_generation = G.NEURO.run_generation
Lifecycle.reset_run_state()
check("replay lifecycle: reset advances generation and clears plan",
  G.NEURO.run_generation == old_generation + 1 and G.NEURO.plan == nil)
check("replay lifecycle: new generation may emit its own outcome",
  Rewards.outcome("SELECTING_HAND", "GAME_OVER") ~= nil)

local Registry = require("core.action_registry")
local SemanticRegistry = require("core.semantic_registry")
local registry_ok = Registry.validate()
local semantic_ok = SemanticRegistry.validate()
local decision_ok = DecisionWindow._test.validate_registry()
check("registry: base action contracts complete", registry_ok)
check("registry: semantic projections complete", semantic_ok)
check("registry: all decision windows scoped", decision_ok)

done()
