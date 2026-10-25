require("tests.stubs").setup({ love = "lazy" })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("verified-decision-evidence")
local Gate = require("core.gate")
local Journal = require("core.gameplay_journal")
local Plans = require("handlers.plan_handlers")
local PlanGate = require("core.gate")
local FactHints = require("facts.fact_hints")

local function base_game()
  _G.G = {
    STATE = ES.SHOP,
    STATES = ES,
    GAME = {
      chips = 10,
      round = 7,
      blind_on_deck = "Small",
      blind = { name = "The Fish", config = { blind = { key = "bl_fish" } } },
      round_resets = {
        ante = 4,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_fish" },
      },
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
      hands = {
        ["Full House"] = { visible = true, level = 6 },
        Flush = { visible = true, level = 1 },
        ["Flush Five"] = { visible = false, level = 1 },
      },
      used_vouchers = {},
      dollars = 10,
    },
    NEURO = {
      run_generation = 9,
      decision_serial = 21,
      plan_revision = 0,
    },
    E_MANAGER = { queues = {} },
    play = { cards = {} },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
  }
end

base_game()
local sig, content = "11,12,13,14,15", "sealed-content"
local fields = Gate.proposal_fields({ signature = sig, content = content, indices = { 1, 2, 3, 4, 5 }, hand_type = "Flush" })
local exact = "Nothing was executed; confirmation is required. Committing Flush -- 10000 to clear."
local proposal = Gate.open_proposal(fields, exact)
check("the delivered confirmation opens the proposal", proposal ~= nil and Gate.proposal() == proposal)
fields.indices[1] = 99
check("confirmation replays final wire text byte-for-byte", proposal.verdict == exact, proposal.verdict)
check("the proposal's identity was sealed", proposal.indices[1] == 1, proposal.indices[1])
G.NEURO.decision_serial = 22
check("a proposal from an earlier decision is no longer valid", Gate.proposal_valid(proposal) == false)

base_game()
local stale_fields = Gate.proposal_fields({ signature = sig, content = content, indices = { 1 }, hand_type = "Flush" })
G.NEURO.decision_serial = 23
check("a review from an earlier decision never opens a proposal",
  Gate.open_proposal(stale_fields, exact) == nil and Gate.proposal() == nil)

base_game()
G.NEURO.last_play = {
  kind = "play", action_id = "play-1", run_generation = 9,
  ante = 4, round = 7, blind_key = "bl_fish", hand_type = "Flush", hand_level = 1,
  played = 5, scored = 4, pre_chips = 10,
}
G.E_MANAGER.queues.base = { { blocking = true } }
G.GAME.chips = 1255
check("outcome waits for engine settlement", Journal.observe_settled("SELECTING_HAND") == false
  and G.NEURO.gameplay_journal == nil)
G.E_MANAGER.queues.base = {}
G.play.cards = { {} }
check("outcome waits for play area", Journal.observe_settled("SELECTING_HAND") == false)
G.play.cards = {}
check("settled outcome publishes actual delta", Journal.observe_settled("SELECTING_HAND") == true)
check("same action id finalizes once", Journal.observe_settled("SELECTING_HAND") == false
  and #G.NEURO.gameplay_journal.hand_outcomes == 1)
local history = Journal.render("SELECTING_HAND", 0, {}) or ""
check("history is exact",
  history:find("Flush lv.1 scored 1245", 1, true) ~= nil, history)
check("history does not alter transaction cursor", select(2, Journal.render("SELECTING_HAND", 0, {})) == 0)

for i = 2, 14 do
  Journal.publish_hand_outcome({
    action_id = "play-" .. i, run_generation = 9, ante = 4, round = 7,
    blind_key = "bl_fish", hand_type = "Full House", hand_level = 6,
    played_count = 5, scored_count = 5, chips_delta = i * 100,
  })
end
check("hand outcome memory is bounded", #G.NEURO.gameplay_journal.hand_outcomes == Journal.MAX_HAND_OUTCOMES)
local bounded = Journal.render("SHOP", 0, {}) or ""
local occurrences = 0
for _ in bounded:gmatch("scored ") do occurrences = occurrences + 1 end
check("rendered outcome history is independently bounded", occurrences == Journal.MAX_RENDERED_HAND_OUTCOMES,
  occurrences)
Journal.prune_delivered({ journal = { through_sequence = 999, shop_visit_epoch = 99 } })
check("shop delivery pruning preserves hand outcomes",
  #G.NEURO.gameplay_journal.hand_outcomes == Journal.MAX_HAND_OUTCOMES)

base_game()
G.NEURO.last_play = {
  kind = "play", action_id = "reset-score", run_generation = 9,
  ante = 4, round = 7, blind_key = "bl_fish", hand_type = "Flush", hand_level = 1,
  played = 5, scored = 5, pre_chips = 500,
}
G.GAME.chips = 0
check("score reset cannot mint a negative outcome", Journal.observe_settled("BLIND_SELECT") == false
  and G.NEURO.gameplay_journal == nil and G.NEURO.last_play.outcome_observed == true)

base_game()
local focus_commit, focus_err = Plans.prepare_plan({
  hand_plan = "Build Full House first; use Flush only as fallback.",
  hand_focus = { primary = "Full House", fallback = "Flush" },
})
check("visible typed hand focus prepares", type(focus_commit) == "function", focus_err)
focus_commit()
check("typed focus is scope-bound and stored",
  G.NEURO.plan.hand_focus.primary == "Full House"
    and G.NEURO.plan.hand_focus.fallback == "Flush"
    and PlanGate.hand_focus_is_current(G.NEURO.plan))
local note = require("tests.helpers").plan_frame("hand")
check("typed focus reaches the plan frame",
  note:find("primary Full House, fallback Flush", 1, true) ~= nil, note)
do
  local Actions = require("core.actions")
  local Registry = require("core.action_registry")
  Actions.get_static_actions()
  local focus = Registry.get("record_plan").schema.properties.hand_focus
  check("hand_focus is an enum of the visible hands in the registered schema",
    type(focus) == "table" and table.concat(focus.properties.primary.enum or {}, ",") == "Flush,Full House"
      and focus.properties.primary.type == "string",
    focus and focus.properties and focus.properties.primary)
  check("fallback is the same enum",
    table.concat(focus.properties.fallback.enum or {}, ",") == "Flush,Full House")
  local signature = Actions.catalogue_signature()
  G.GAME.hands["Flush Five"].visible = true
  check("revealing a secret hand moves the catalogue signature, so the enum re-registers",
    Actions.catalogue_signature() ~= signature)
  Actions.get_static_actions()
  check("and the re-registered enum offers it",
    table.concat(Registry.get("record_plan").schema.properties.hand_focus.properties.primary.enum or {}, ",")
      == "Flush,Flush Five,Full House")
  G.GAME.hands["Flush Five"].visible = false
  check("hiding it again restores the signature, so only a visibility change re-registers",
    Actions.catalogue_signature() == signature)
  Actions.get_static_actions()
  local _, listed = Plans.prepare_plan({ hand_focus = { primary = "Flush Five" } })
  check("the refusal lists exactly the visible hands, in a stable order",
    tostring(listed):find("Flush, Full House.", 1, true) ~= nil, tostring(listed))
end

local old_focus = G.NEURO.plan.hand_focus
local bad_hidden, bad_hidden_err = Plans.prepare_plan({ hand_focus = { primary = "Flush Five" } })
check("hidden hand type is rejected in preflight", bad_hidden == nil, bad_hidden_err)
check("rejection preserves prior focus", G.NEURO.plan.hand_focus == old_focus)
local extra_ok = Plans.prepare_plan({ hand_focus = { primary = "Flush", score = 999 } })
check("typed focus ignores an undeclared nested field instead of failing the action",
  extra_ok ~= nil, tostring(extra_ok))
local rewrite = assert(Plans.prepare_plan({ hand_plan = "Use the live strongest hand." }))
rewrite()
check("rewriting free-text hand plan without focus clears stale typed anchor",
  G.NEURO.plan.hand_focus == nil and G.NEURO.plan.provenance.focus == nil)

local defs = require("core.actions").get_static_actions()
local record_plan
for _, def in ipairs(defs) do if def.name == "record_plan" then record_plan = def break end end
local focus_schema = record_plan and record_plan.schema and record_plan.schema.properties
  and record_plan.schema.properties.hand_focus
check("wire schema is static simple JSON Schema",
  type(focus_schema) == "table" and focus_schema.type == "object"
    and focus_schema.properties.primary.type == "string"
    and focus_schema.additionalProperties == nil)

done()
