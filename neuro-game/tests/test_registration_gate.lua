require("tests.stubs").setup({ love = "timers" })

local H = require("tests.helpers")
local check, done = H.harness("registration-gate")

local STATES = require("tests.engine_cards").states()
local CLOCK = 5000

local Window = { REGISTERED = "registered", FORCED = "forced", ENDED = "ended" }
local Metrics = require("util.metrics")

local play_card = H.play_card

local forces

local function board(register_ok)
  H.orch_board({ state = "SELECTING_HAND", clock = CLOCK, states = STATES })
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  forces = {}
  G.NEURO = H.orch_neuro({
    state = "SELECTING_HAND", send_context = "written", send_action_result = "noop",
    register_actions = function(_self, _defs) return register_ok end,
    force_actions = function(_self, _ctx, _query, actions)
      forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
      return true, { status = "written", written_at = G.TIMERS.REAL }
    end,
  })
  require("core.validate").reset_run_state()
  H.orch_reset()
end

local T = H.orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)
local tick_for = T.tick_for

local function phase() return H.force_phase() end

do
  CLOCK = 5000
  board(true)
  tick_for(30)
  check("fixture: with registration succeeding, a force is armed and sent",
    #forces >= 1 and phase() == Window.FORCED, #forces .. "/" .. phase())
end

do
  CLOCK = 5000
  local before = Metrics._counters["action_registration_failed"] or 0
  board(false)
  tick_for(30)
  check("no force is ever armed while registration keeps failing",
    #forces == 0 and phase() ~= Window.FORCED, #forces .. "/" .. phase())
  check("the registration failure is counted",
    (Metrics._counters["action_registration_failed"] or 0) > before,
    tostring(Metrics._counters["action_registration_failed"]))
end

done()
