_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("verified-decision-evidence")
local Evidence = require("core.confirmation_evidence")
local Journal = require("core.gameplay_journal")
local Plans = require("handlers.plan_handlers")
local PlanGate = require("core.plan_gate")
local FactHints = require("facts.fact_hints")

local function base_game()
  _G.G = {
    STATE = 1,
    STATES = { SHOP = 1, SELECTING_HAND = 2, ROUND_EVAL = 3 },
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
local candidate = assert(Evidence.candidate(sig, content, { 1, 2, 3, 4, 5 }, "Flush"))
local receipt = { status = "buffered" }
local exact = "Nothing was executed; confirmation is required. Committing Flush -- 10000 to clear."
check("confirmation candidate stages", Evidence.stage(candidate, exact, receipt) == true)
candidate.indices[1] = 99
check("buffered result does not promote", Evidence.step_delivery() == false
  and G.NEURO.pending_confirmation == nil)
receipt.status = "written"
check("written result promotes once", Evidence.step_delivery() == true
  and Evidence.step_delivery() == false)
local rendered, committed = Evidence.render()
check("confirmation replays final wire text byte-for-byte", rendered == exact, rendered)
check("staged identity was sealed", committed.indices[1] == 1, committed.indices[1])
G.NEURO.decision_serial = 22
check("stale confirmation is invisible without renderer mutation", Evidence.render() == nil
  and G.NEURO.pending_confirmation == committed)

base_game()
local rejected_candidate = assert(Evidence.candidate(sig, content, { 1 }, "Flush"))
local rejected = { status = "rejected" }
local prior_confirm = { signature = "prior-signature", content = "prior-content", indices = { 9 } }
local rollback = {
  weak_fired_serial = 20,
  pending_confirmation = { rendered_verdict = "prior verdict" },
  play_confirm = prior_confirm,
}
Evidence.stage(rejected_candidate, exact, rejected, rollback)
check("rejected delivery never promotes", Evidence.step_delivery() == false
  and G.NEURO.confirmation_delivery == nil)
check("rejected delivery atomically restores the preflight confirmation state",
  G.NEURO.weak_fired_serial == 20
    and G.NEURO.pending_confirmation == rollback.pending_confirmation
    and G.NEURO.play_confirm == prior_confirm,
  tostring(G.NEURO.play_confirm and G.NEURO.play_confirm.signature))

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
check("history is exact and explicitly not a forecast",
  history:find("Flush lv.1 scored 1245", 1, true) ~= nil
    and history:find("history, not forecasts", 1, true) ~= nil, history)
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
local note = FactHints.plan_note("hand")
check("typed focus is labelled as the model declaration",
  note:find("Declared hand focus", 1, true) ~= nil
    and note:find("primary Full House, fallback Flush", 1, true) ~= nil, note)
do
  local Actions = require("core.actions")
  local Registry = require("core.action_registry")
  Actions.get_static_actions()
  local focus = Registry.get("set_plan").schema.properties.hand_focus
  check("hand_focus advertises the visible hand names, not a free string",
    type(focus) == "table" and type(focus.properties.primary.enum) == "table",
    focus and focus.properties and focus.properties.primary)
  local names = {}
  for _, n in ipairs(focus.properties.primary.enum) do names[#names + 1] = n end
  table.sort(names)
  check("the enum is exactly the visible hands, in a stable order",
    table.concat(names, ",") == "Flush,Full House", table.concat(names, ","))
  check("the hidden hand type is not offered",
    table.concat(names, ","):find("Flush Five", 1, true) == nil, table.concat(names, ","))
  check("fallback carries the same closed set",
    table.concat(focus.properties.fallback.enum, ",") == table.concat(focus.properties.primary.enum, ","))
end

local old_focus = G.NEURO.plan.hand_focus
local bad_hidden, bad_hidden_err = Plans.prepare_plan({ hand_focus = { primary = "Flush Five" } })
check("hidden hand type is rejected in preflight", bad_hidden == nil
  and tostring(bad_hidden_err):find("currently visible", 1, true) ~= nil, bad_hidden_err)
check("rejection preserves prior focus", G.NEURO.plan.hand_focus == old_focus)
local bad_extra, bad_extra_err = Plans.prepare_plan({ hand_focus = { primary = "Flush", score = 999 } })
check("typed focus rejects undeclared nested fields", bad_extra == nil
  and tostring(bad_extra_err):find("only primary and fallback", 1, true) ~= nil, bad_extra_err)
local rewrite = assert(Plans.prepare_plan({ hand_plan = "Use the live strongest hand." }))
rewrite()
check("rewriting free-text hand plan without focus clears stale typed anchor",
  G.NEURO.plan.hand_focus == nil and G.NEURO.plan.provenance.focus == nil)

local defs = require("core.actions").get_static_actions()
local set_plan
for _, def in ipairs(defs) do if def.name == "set_plan" then set_plan = def break end end
local focus_schema = set_plan and set_plan.schema and set_plan.schema.properties
  and set_plan.schema.properties.hand_focus
check("wire schema is static simple JSON Schema",
  type(focus_schema) == "table" and focus_schema.type == "object"
    and focus_schema.properties.primary.type == "string"
    and focus_schema.additionalProperties == nil)

done()
