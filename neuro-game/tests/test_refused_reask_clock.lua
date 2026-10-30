local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("refused-reask-clock")

local function forces()
  local n = 0
  for _, f in ipairs(H.frames()) do if f.command == "actions/force" then n = n + 1 end end
  return n
end

H.board({ confirm_hand = false })
require("core.config").set("NEURO_FORCE_LIVENESS_TIMEOUT", 180)
check("fixture forced", H.wait_force(), H.phase())
local before, start = forces(), G.TIMERS.REAL
H.send("discard_hand", { indices = { 99 } })
H.tick(10)
H.send("not_an_action", {})
local waited
for _ = 1, 40 do
  H.tick(5)
  if forces() > before then waited = G.TIMERS.REAL - start break end
end
check("a refusal is re-asked on the refusal clock even when another call arrives in between, not after the 180 s timeout",
  waited and waited < 60, tostring(waited))

local query
for _, f in ipairs(H.frames()) do if f.command == "actions/force" then query = f.data.query end end
check("the re-ask quotes her last actionable refusal, not the unknown call after it",
  tostring(query):find("^Your last answer was refused: Index 99 is out of range") ~= nil, tostring(query):sub(1, 200))
H.board({ confirm_hand = false })
local Help = require("tests.helpers")
G.jokers = Help.card_area({ cards = { Help.flat_mult_joker("j_joker", "Joker"), Help.flat_mult_joker("j_greedy_joker", "Greedy Joker") },
  config = { card_limit = 5, type = "joker" } })
require("core.config").set("NEURO_FORCE_LIVENESS_TIMEOUT", 180)
check("second fixture forced", H.wait_force(), H.phase())
before = forces()
H.send("discard_hand", { indices = { 99 } })
H.tick(1)
local refused_window = G.NEURO.force_window
local accepted = H.send("set_joker_order", { from_index = 1, to_index = 2 })
H.tick(1)
check("the call after the refusal is accepted", (H.result_for(accepted) or {}).success == true)
for _ = 1, 20 do H.tick(5) end
check("an accepted call after a refusal ends the window, so one fresh force follows, not a refusal re-ask",
  refused_window.ended_by == "answered" and forces() == before + 1, tostring(forces() - before))
H.board({ confirm_hand = false })
require("core.config").set("NEURO_FORCE_LIVENESS_TIMEOUT", 180)
check("third fixture forced", H.wait_force(), H.phase())
G.NEURO.reask_refusal = { state = H.phase() and G.NEURO.force_window and G.NEURO.force_window.state, reason = "old run refusal" }
require("core.window").reset()
check("a reset forgets the last refusal, so a new run's first force does not quote the old one",
  G.NEURO.reask_refusal == nil, tostring(G.NEURO.reask_refusal and G.NEURO.reask_refusal.reason))
done()
