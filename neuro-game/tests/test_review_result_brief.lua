require("tests.stubs").setup({ love = "lazy", G = "board" })

local check, done = require("tests.helpers").harness("review-result-brief")
local Gate = require("core.gate")
local Router = require("force.force_router")
local TD = require("tests.test_deadlock")
local BRIEF_MAX = 160

local function force_query(state)
  local f = Router.get_force_for_state(state)
  return f and f.query or "", f
end

local function offers(f, name)
  for _, list in ipairs({ f and f.actions or {}, f and f.tools or {} }) do
    for _, n in ipairs(list) do if n == name then return true end end
  end
  return false
end

do
  TD.apply_mock(require("tests.helpers").scenario("Normal: affordable joker, affordable booster, $10").mock())
  require("tests.helpers").in_engine_state("SHOP")
  G.NEURO.persona, G.NEURO.gates, G.NEURO.force_window = "neuro", nil, nil
  G.NEURO.shop_entry_dollars, G.GAME.dollars = 14, 3
  local rejection = Gate.check("admission", "leave_shop", {})
  local brief = Gate.result_message(rejection)
  check("interest: the result is one short brief", brief ~= nil and #brief <= BRIEF_MAX
    and brief:find("$14", 1, true) == nil, tostring(brief))
  local review = rejection and rejection.message or ""
  check("interest: the review does not state the banks", review:find("$14", 1, true) == nil, review)
  Gate.delivered(rejection, review)
  local query, f = force_query("SHOP")
  check("interest: the shop force that follows carries the whole review and offers leave_shop",
    query:find(review, 1, true) ~= nil and offers(f, "leave_shop"), query)
  G.GAME.dollars = 4
  check("interest: the carried review is restated while it still applies",
    force_query("SHOP"):find(review, 1, true) ~= nil, force_query("SHOP"))
  check("interest: the next leave_shop goes through", Gate.check("admission", "leave_shop", {}) == nil)
  check("interest: and the review leaves the force with it",
    force_query("SHOP"):find(review, 1, true) == nil, force_query("SHOP"))
end

do
  TD.apply_mock(require("tests.helpers").scenario("Normal: affordable joker, affordable booster, $10").mock())
  require("tests.helpers").in_engine_state("SHOP")
  G.NEURO.persona, G.NEURO.gates, G.NEURO.force_window = "neuro", nil, nil
  local text = "Buying Grabber for $10 leaves $0. A voucher lasts the whole run and cannot be sold or undone."
  local rejection = Gate.check("handler", "buy_from_shop", {}, { target = "Grabber", text = function() return text end })
  local brief = Gate.result_message(rejection)
  check("voucher: the result is one short brief", brief ~= nil and #brief <= BRIEF_MAX, tostring(brief))
  Gate.delivered(rejection, rejection.message)
  local query, f = force_query("SHOP")
  check("voucher: the shop force that follows carries the review and offers buy_from_shop",
    query:find(text, 1, true) ~= nil and offers(f, "buy_from_shop"), query)
end

do
  local H = require("tests.hand_pipeline_harness")
  H.board(); H.tick(8)
  local id = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(6)
  local result
  for _, r in ipairs(H.results()) do if r.id == id then result = r end end
  local verdict = Gate.proposal() and Gate.proposal().verdict or ""
  local facts = Gate.proposal() and Gate.proposal().facts or ""
  check("play: the wire result is success=true and only the brief",
    result and result.success == true and result.message == require("handlers.hand_handlers").PLAY_REVIEW_BRIEF
      and #result.message <= BRIEF_MAX, result and result.message)
  local force
  for _, fr in ipairs(H.frames()) do if fr.command == "actions/force" then force = fr.data end end
  check("play: the resolve_play force carries the whole review, its contract in query and its facts in state",
    facts:find("^Selection %[1,2%]") ~= nil
      and force and (force.action_names or {})[1] == "resolve_play" and force.query:find(verdict, 1, true) ~= nil
      and force.state:find("Selection [1,2]", 1, true) ~= nil,
    verdict .. " || " .. tostring(force and force.query))
  check("play: the review is said once, in the force", not result.message:find("Selection [", 1, true))
  require("tests.tmp_workdir").close()
end

done()
