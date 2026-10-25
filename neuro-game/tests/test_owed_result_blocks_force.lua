require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("owed-result-blocks-force")

local STATES = require("tests.engine_cards").states()
local CLOCK = 7000

local Helpers = require("tests.helpers")
local Execute = require("core.execute")
local Win = require("core.window")
local TxCache = require("core.bridge").tx

local function board()
  Helpers.orch_board({ state = "SELECTING_HAND", clock = CLOCK, states = STATES })
  for i = 1, 5 do G.hand.cards[i] = Helpers.play_card(i) end
end

local T = Helpers.orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)

do
  local forces, deliverable = 0, false
  board()
  G.NEURO = Helpers.orch_neuro({
    state = "SELECTING_HAND", send_context = "written",
    send_action_result = function() return deliverable end,
    register_actions = "true", force_actions = function() forces = forces + 1 return true end,
    withdraw_actions = "true",
  })
  Win.reset()
  Helpers.orch_reset()

  check("fixture: the first force went out",
    T.tick_until(function() return Helpers.force_phase() == "forced" end, 15) and forces == 1, forces)
  local name = G.NEURO.force_window.names[1]
  TxCache.open("owed-1", name, G.TIMERS.REAL)
  local delivered = Execute.answer(G.NEURO, "owed-1", name, true, nil)
  check("fixture: the result could not be delivered and its force was withdrawn",
    delivered == false and G.NEURO.force_window.ended_by == "result_undelivered",
    tostring(G.NEURO.force_window.ended_by))
  check("fixture: the id is still owed", Helpers.is_owed("owed-1"))

  T.tick_for(10)
  check("no successor force opens while the result is owed", forces == 1, forces)

  deliverable = true
  G.NEURO.answer_owed_results = require("core.bridge").answer_owed_results
  check("the owed result is paid", G.NEURO:answer_owed_results(0) == 1 and not Helpers.is_owed("owed-1"))
  check("then the game asks again", T.tick_until(function() return forces == 2 end, 15), forces)
end

done()
