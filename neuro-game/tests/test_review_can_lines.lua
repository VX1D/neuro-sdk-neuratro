local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("review-can-lines")

local LINES = { play = "play_hand", discard = "discard_hand" }

local function forces()
  local out = {}
  for _, fr in ipairs(H.frames()) do
    if fr.command == "actions/force" then out[#out + 1] = fr.data end
  end
  return out
end

local function check_force(key, f)
  local offered = {}
  for _, name in ipairs(f.action_names or {}) do offered[name] = true end
  for label, name in pairs(LINES) do
    local verdict = f.state:match("Can " .. label .. ": (%a+)")
    check(key .. ": 'Can " .. label .. "' present", verdict ~= nil)
    check(key .. ": 'Can " .. label .. ": " .. tostring(verdict) .. "' agrees with the offer",
      (verdict == "yes") == (offered[name] == true), table.concat(f.action_names or {}, ","))
  end
end

H.board({}); H.tick(8)
local before = forces()
check("a hand force was sent", #before > 0)
check_force("hand decision", before[#before])

H.send("play_hand", { indices = { 1, 2 } }); H.tick(3)
local after = forces()
local review = after[#after]
check("the review force offers only resolve_play",
  #after > #before and table.concat(review.action_names or {}, ",") == "resolve_play",
  table.concat(review.action_names or {}, ","))
check_force("review", review)

done()
