local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("delta-after-held-play")

local function delta_line(force)
  return (force and force.state or ""):match("Since your last decision[^\n]*") or "(no delta line)"
end

H.board(); H.tick(8)
check("fixture: the first hand force is out", H.phase() == "forced", H.phase())
G.GAME.dollars = 17
H.send("play_hand", { indices = { 1, 2 } }); H.tick(6)
local review = H.last_force()
check("fixture: the play is held for review", review and review.action_names[1] == "resolve_play",
  review and table.concat(review.action_names, ","))
check("the review force reports the change since the force she answered",
  delta_line(review):find("money $10 to $17 (+$7)", 1, true) ~= nil, delta_line(review))

H.send("resolve_play", { answer = "no" }); H.tick(6)
local again = H.last_force()
check("fixture: declining re-offers the hand", again and again ~= review
  and again.action_names[1] == "play_hand", again and table.concat(again.action_names, ","))
check("the force after a decision that changed nothing does not claim the old change is new",
  delta_line(again):find("nothing changed", 1, true) ~= nil, delta_line(again))

require("tests.tmp_workdir").close()
done()
