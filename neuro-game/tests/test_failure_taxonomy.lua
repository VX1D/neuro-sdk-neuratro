_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("failure-taxonomy")
local function has(text, needle)
  return type(text) == "string" and text:find(needle, 1, true) ~= nil
end

local PlanGate = require("core.plan_gate")
local PlanHandler = require("handlers.plan_handlers").handle_record_plan
local FactHints = require("facts.fact_hints")
local Actions = require("core.actions")
local CardUtil = require("facts.card_util")
local DecisionWindow = require("core.decision_window")
local CtxHelpers = require("context.ctx_helpers")
local Rewards = require("core.rewards")
local Lifecycle = require("core.neuro_lifecycle")
local Protocol = require("core.bridge_protocol")
local Bridge = require("core.bridge")

local function base_game(state)
  _G.G = {
    STATE = state == "SHOP" and 2 or 1,
    STATES = { BLIND_SELECT = 1, SHOP = 2, GAME_OVER = 3 },
    GAME = {
      dollars = 10,
      blind_on_deck = "Small",
      round_resets = {
        ante = 2,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
      current_round = { hands_left = 4, discards_left = 3 },
    },
    NEURO = { _decision_windows = {}, once_serials = {}, decision_serial = 1, state_enter_serial = 1 },
    P_BLINDS = {
      bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_club = { key = "bl_club", name = "The Club" },
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
end

base_game("BLIND_SELECT")
local set_small, set_small_err = PlanHandler({ hand_plan = "Play the strongest made hand" })
check("scope: valid Small plan creates an execution closure", type(set_small) == "function", set_small_err)
if type(set_small) == "function" then set_small() end
check("scope: freshly written plan satisfies this blind", PlanGate._test.blind_needs_plan() == false)
check("scope: current blind note includes current plan", has(FactHints.plan_note("blind"), "strongest made hand"))
check("scope: play window stays agnostic (no per-hand plan echo)", FactHints.plan_note("play") == "")
G.GAME.blind_on_deck = "Big"
G.GAME.round_resets.blind_states.Small = "Defeated"
G.GAME.round_resets.blind_states.Big = "Select"
PlanGate.begin_cycle()
check("scope: changing Small to Big invalidates hand plan in same ante", PlanGate._test.blind_needs_plan() == true)
check("scope: stale plan surfaced in blind-select with a record_plan remedy (valid there)",
  has(FactHints.plan_note("blind"), "Blind changed")
    and has(FactHints.plan_note("blind"), "record_plan"))

G.STATE = G.STATES.SHOP
PlanGate.mark_shop_changed("reroll_shop")
local required = PlanGate.shop_required_fields()
check("plan fields: reroll leaves nothing outstanding", not required.money and not required.hand and not required.build)
local set_money, money_err = PlanHandler({ money_plan = "Hold unless the named upgrade appears" })
check("plan fields: money-only revision satisfies reroll", type(set_money) == "function", money_err)
if type(set_money) == "function" then set_money() end
check("plan fields: completed partial revision clears gate", PlanGate.shop_needs_revision() == false)
PlanGate.mark_shop_changed("buy_from_shop")
required = PlanGate.shop_required_fields()
check("plan fields: purchase leaves the build plan outstanding",
  required.build and not required.money and not required.hand)
local revision_level = DecisionWindow.evaluate("leave_shop")
local inline_required = PlanGate.action_requirements("SHOP", "leave_shop").plan
check("plan fields: leave carries only the outstanding field inline",
  revision_level == false
    and inline_required.build
    and not inline_required.money
    and not inline_required.hand)
local satisfied, satisfied_err = PlanHandler({ money_plan = "Hold for interest" })
check("plan fields: money revision does not satisfy a purchase", satisfied == nil and satisfied_err ~= nil, satisfied)
local revised = PlanHandler({ build_plan = "Keep the scaling pair, drop the flat joker" })
check("plan fields: build revision satisfies a purchase", type(revised) == "function", revised)
if type(revised) == "function" then revised() end
check("plan fields: build revision clears the leave gate", PlanGate.shop_needs_revision() == false)

base_game("SHOP")
local chariot = {
  ability = { set = "Tarot", consumeable = { min_highlighted = 1, max_highlighted = 3 } },
  config = { center = { key = "c_chariot", set = "Tarot" } },
}
G.consumeables.cards = { chariot }
G.hand = nil
check("availability: targeted consumable is unusable without a hand", CardUtil.consumable_usable_now(chariot) == false)
check("availability: use_consumable is not advertised when every owned card lacks targets", Actions.is_action_valid("use_consumable") == false)
G.hand = { cards = { { base = { value = "Ace", suit = "Spades" } } } }
check("availability: targeted consumable becomes available with a hand", CardUtil.consumable_usable_now(chariot) == true)
check("availability: use_consumable becomes valid after target appears", Actions.is_action_valid("use_consumable") == true)

local walkie = {
  ability = { set = "Joker", name = "Walkie Talkie", mult = 4, bonus = 10 },
  config = { center = {
    key = "j_walkie_talkie", set = "Joker", name = "Walkie Talkie",
    loc_txt = { name = "Walkie Talkie", description = { "Played 10s and 4s give +10 Chips and +4 Mult" } },
  } },
}
local walkie_summary = require("core.semantic_registry").render("card_effect_summary", walkie)
check("semantics: Walkie summary retains the 10/4 trigger", has(walkie_summary, "Played 10s and 4s"), walkie_summary)
check("semantics: Walkie summary is not a bare unconditional bonus", walkie_summary ~= "+4 Mult · +10 Chips", walkie_summary)

base_game("SHOP")
G.jokers.cards = {
  { config = { center = { key = "j_joker" } }, ability = { mult = 4 } },
  { config = { center = { key = "j_blueprint" } }, ability = {} },
}
DecisionWindow.reset_field("order_think")
local first_reject = DecisionWindow.evaluate("leave_shop")
check("latch: new composition arms order review", first_reject ~= false)
DecisionWindow.acknowledge("leave_shop")
check("latch: unchanged acknowledged composition stays disarmed after toggle", DecisionWindow.would_reject("leave_shop") == false)
check("latch: unchanged acknowledged composition evaluates cleanly", DecisionWindow.evaluate("leave_shop") == false)
G.jokers.cards[2].config.center.key = "j_baron"
G.jokers.cards[2].ability = { x_mult = 1.5 }
check("latch: a genuinely changed composition re-arms review", DecisionWindow.evaluate("leave_shop") ~= false)

local order_definition = require("core.decision_registry").get("order_think")
local real_scope_key = order_definition.scope.key
order_definition.scope.key = function() error("synthetic pre-execution snapshot failure") end
local failed_snapshot = DecisionWindow.snapshot("leave_shop")
order_definition.scope.key = real_scope_key
local captured_failed_scope = false
for _, entry in ipairs(failed_snapshot or {}) do
  if entry.definition == order_definition then captured_failed_scope = true end
end
check("latch: a failed pre-execution snapshot is not recomputed from post-action state",
  type(failed_snapshot) == "table" and captured_failed_scope == false
    and pcall(DecisionWindow.acknowledge, "leave_shop", failed_snapshot) == true)

local plan_def
for _, def in ipairs(Actions.get_static_actions()) do
  if def.name == "record_plan" then plan_def = def break end
end
check("contract: no plan field advertises a length cap on model-authored prose",
  plan_def and plan_def.schema.properties.hand_plan.maxLength == nil
    and plan_def.schema.properties.build_plan.maxLength == nil
    and plan_def.schema.properties.money_plan.maxLength == nil)
local result = Protocol.result("bad-json", false, "invalid")
check("protocol: reason_code never reaches the frame -- it stays a core/action_result.lua policy class",
  result.reason_code == nil)
check("protocol: action/result data holds exactly id/success/message (SPECIFICATION.md)",
  (function()
    local keys = 0
    for k in pairs(result.data) do
      if k ~= "id" and k ~= "success" and k ~= "message" then return false end
      keys = keys + 1
    end
    return keys == 3
  end)())
check("protocol: successful result omits reason_code", Protocol.result("ok", true, "done").reason_code == nil)
base_game("BLIND_SELECT")
G.STATES.SELECTING_HAND = 4
G.STATE = 4
G.hand = {
  cards = {
    { base = { value = "Ace", suit = "Spades" } },
    { base = { value = "King", suit = "Spades" } },
    { base = { value = "Queen", suit = "Spades" } },
    { base = { value = "Jack", suit = "Spades" } },
    { base = { value = "10", suit = "Spades" } },
    { base = { value = "9", suit = "Spades" } },
  },
  highlighted = {},
  config = { highlighted_limit = 5 },
}
G.NEURO.force_inflight = false
G.NEURO.force_window = nil
require("core.force_state").arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1)
require("core.action_registry").note_registered({ "play_hand" })
require("core.transition_guard").reset()
local dispatched
local result_bridge = {
  send_action_result = function(_, _, ok, message, reason_code)
    dispatched = { ok = ok, message = message, reason_code = reason_code }
  end,
  send_context = function() end,
}
require("core.dispatcher").handle_message({
  command = "action",
  data = { id = "taxonomy-six-cards", name = "play_hand", data = { indices = { 1, 2, 3, 4, 5, 6 } } },
}, result_bridge)
check("protocol: dispatcher classifies schema rejection", dispatched and not dispatched.ok
  and dispatched.reason_code == "SCHEMA_INVALID", dispatched and dispatched.reason_code)

base_game("SHOP")
G.GAME.blind = { name = "Big Blind", boss = false }
G.GAME.round = 4
G.GAME.won = false
G.NEURO.run_generation = 9
local loss1 = Rewards.outcome("SELECTING_HAND", "GAME_OVER")
local loss2 = Rewards.outcome("RUN_SETUP", "GAME_OVER")
check("lifecycle: first terminal notice is emitted", has(loss1, "lost the run"), loss1)
check("lifecycle: repeated GAME_OVER transition in same run is suppressed", loss2 == nil, loss2)
local generation_before = G.NEURO.run_generation
Lifecycle.reset_run_state()
check("lifecycle: run reset increments generation", G.NEURO.run_generation == generation_before + 1)
local loss3 = Rewards.outcome("SELECTING_HAND", "GAME_OVER")
check("lifecycle: a new generation may emit its own terminal outcome", has(loss3, "lost the run"), loss3)
local bridge = setmetatable({ game = "Balatro", session_id = "s", seq = 0 }, { __index = Bridge })
local decorated = bridge:_decorate({ command = "context", data = {} })
check("lifecycle: the generation stays mod-local and never rides a frame", decorated.run_generation == nil)

base_game("BLIND_SELECT")
G.STATE = 4
G.STATES.SELECTING_HAND = 4
G.GAME.blind = { chips = 300 }
G.GAME.chips = 0
G.GAME.hands = {}
G.hand = { cards = { { base = { value = "Ace", suit = "Spades" } } }, highlighted = {}, config = { highlighted_limit = 5 } }
local hand_force = require("force.force_selecting_hand").build()
local play_ix = require("core.action_registry").get("play_hand").schema.properties.indices
check("prompt hardening: the play contract quotes the schema's own count, not a wider one",
  play_ix.minItems == 1 and play_ix.maxItems == 1
    and hand_force and has(hand_force.query, 'play_hand|{"indices":[<pick 1 hand position>]'),
  hand_force and hand_force.query)

done()
