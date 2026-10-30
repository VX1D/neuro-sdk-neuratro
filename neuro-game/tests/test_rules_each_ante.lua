-- BEST_PRACTICES.md:9: rules go out at startup and again at key moments; here, once per ante of a run.
local H = require("tests.hand_pipeline_harness")
local Guide = require("facts.token_legends").ACTION_SEMANTICS_V1
local check, done = require("tests.helpers").harness("rules-each-ante")

local function guides()
  local n = 0
  for _, f in ipairs(H.frames()) do
    if f.command == "context" and type(f.data) == "table" and f.data.message == Guide.text then n = n + 1 end
  end
  return n
end

H.board()
G.STAGES = G.STAGES or { RUN = 2 }
G.STAGE = G.STAGES.RUN
G.GAME.pseudorandom = G.GAME.pseudorandom or { seed = "TESTSEED" }
G.GAME.round_resets = G.GAME.round_resets or {}
G.GAME.round_resets.ante = 1
H.tick(8)
check("the guide is sent in ante 1", guides() == 1, tostring(guides()))
local function new_state()
  G.STATE = G.STATES.DRAW_TO_HAND; H.tick(0.3)
  G.STATE = G.STATES.SELECTING_HAND; H.tick(8)
end
new_state()
G.GAME.round = (G.GAME.round or 1) + 1
new_state()
check("it is not repeated in a later round of the same ante", guides() == 1, tostring(guides()))
G.GAME.round_resets.ante = 2
new_state()
check("it is sent again when the next ante starts", guides() == 2, tostring(guides()))
new_state()
check("and only once in that ante", guides() == 2, tostring(guides()))

H.finish(check, done)
