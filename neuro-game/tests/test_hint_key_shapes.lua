_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("hint-key-shapes")

local function fresh()
  _G.G = { NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1, run_generation = 1 },
    GAME = { round = 4, round_resets = { ante = 1 } } }
  package.loaded["facts.fact_hints"] = nil
  return require("facts.fact_hints")
end

do
  local FactHints = fresh()
  FactHints.once_per_run_hint("bp_chain:" .. "Joker copies Blueprint", "text")
  check("a content-signature run hint is queued", FactHints.pending_count() == 1)
  check("hint_is_pending sees it by its short tag",
    FactHints.hint_is_pending("bp_chain") == true)
  FactHints.drop_hint("bp_chain")
  check("drop_hint removes it from the pending view",
    FactHints.hint_is_pending("bp_chain") == false)
  check("and actually empties the queue, not just the view", FactHints.pending_count() == 0)
end

do
  local FactHints = fresh()
  FactHints.once_per_decision_hint("newshape:" .. "some future signature", "text")
  check("hint_is_pending recognizes an unforeseen suffixed shape under dhint:",
    FactHints.hint_is_pending("newshape") == true)
  FactHints.drop_hint("newshape")
  check("drop_hint removes it too", FactHints.hint_is_pending("newshape") == false
    and FactHints.pending_count() == 0)
end

do
  local FactHints = fresh()
  FactHints.once_per_session_hint("gen:" .. "abc|def", "text")
  check("hint_is_pending recognizes a suffixed shape under shint:",
    FactHints.hint_is_pending("gen") == true)
  FactHints.drop_hint("gen")
  check("drop_hint removes it", FactHints.hint_is_pending("gen") == false)
end

do
  local FactHints = fresh()
  FactHints.once_per_run_hint("bp_chain:" .. "X", "text")
  check("a non-bounded prefix does not false-match", FactHints.hint_is_pending("bp_chai") == false)
  check("an unrelated tag does not match", FactHints.hint_is_pending("bp_chainX") == false)
end

do
  local FactHints = fresh()
  FactHints.once_per_state_entry_hint("plain_hint", "text")
  FactHints.once_per_decision_hint("plain_dhint", "text")
  FactHints.once_per_session_hint("plain_shint", "text")
  FactHints.once_per_run_hint("plain_rhint", "text")
  FactHints.once_per_round_hint("plain_rdhint", "text")
  check("all five channels queue their plain tag", FactHints.pending_count() == 5)
  for _, tag in ipairs({ "plain_hint", "plain_dhint", "plain_shint", "plain_rhint",
    "plain_rdhint" }) do
    check("hint_is_pending sees " .. tag, FactHints.hint_is_pending(tag) == true)
  end
  check("an unrelated tag is not pending", FactHints.hint_is_pending("nope") == false)
  FactHints.drop_hint("plain_rdhint")
  check("dropping one leaves the other four queued", FactHints.pending_count() == 4)
end

done()
