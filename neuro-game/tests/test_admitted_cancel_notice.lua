local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("admitted-cancel-notice")

local function notices()
  local out = {}
  for _, f in ipairs(H.frames()) do
    if f.command == "context" and type(f.data) == "table"
        and (tostring(f.data.message):find("did not complete", 1, true)
          or tostring(f.data.message):find("(play a hand)", 1, true)) then
      out[#out + 1] = f.data.message
    end
  end
  return out
end

do
  H.board({ confirm_hand = false }); H.tick(8)
  local id = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.5)
  local admitted
  for _, r in ipairs(H.results()) do if r.id == id then admitted = r end end
  check("the play is admitted with success=true", admitted and admitted.success == true)
  G.STATE = G.STATES.DRAW_TO_HAND
  H.tick(0.3)
  G.STATE = G.STATES.SELECTING_HAND
  H.tick(8)
  check("the cancelled play never ran", H.calls.play == 0, tostring(H.calls.play))
  local seen = notices()
  check("she is not told: the reference SDK sends nothing when an accepted action never runs",
    #seen == 0, table.concat(seen, " | "))
end

do
  H.board({ confirm_hand = false }); H.tick(8)
  H.send("play_hand", { indices = { 1, 2 } })
  H.tick(10)
  check("a play that runs produces no such notice", H.calls.play == 1 and #notices() == 0,
    H.calls.play .. "/" .. #notices())
end

H.finish(check, done)
