local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("action-echo-channel")

local function last_force() return H.last_force() or {} end

local function echoes()
  local out = {}
  for _, f in ipairs(H.frames()) do
    local text = f.command == "context" and tostring(f.data.message) or ""
    if text:find("After the completed action", 1, true) or text:find("Effect of your", 1, true) then
      out[#out + 1] = text
    end
  end
  return out
end

H.board({ confirm_hand = false, hands = 4, discards = 2 })
check("fixture: the hand screen is forced", H.wait_force(), H.phase())
H.send("discard_hand", { indices = { 1, 2 } })
check("the discard is followed by the next decision", H.wait_force(), H.phase())
local state = tostring(last_force().state)
check("its state carries the discards left", state:find("4 hands and 1 discard left", 1, true) ~= nil, state)

H.send("play_hand", { indices = { 1 } })
check("the play is followed by the next decision", H.wait_force(), H.phase())
state = tostring(last_force().state)
check("its state carries the hands left", state:find("3 hands and 1 discard left", 1, true) ~= nil, state)

H.board({ confirm_hand = true, hands = 4, discards = 2 })
check("fixture: forced with the review on", H.wait_force(), H.phase())
H.send("play_hand", { indices = { 1 } })
check("the review is asked as its own decision", H.wait_force() and last_force().action_names[1] == "resolve_play",
  table.concat(last_force().action_names or {}, ","))
H.send("resolve_play", { answer = "no" })
check("the declined review is followed by the hand decision",
  H.wait_force() and table.concat(last_force().action_names or {}, ","):find("play_hand", 1, true) ~= nil,
  table.concat(last_force().action_names or {}, ","))

check("no applied hand action echoed itself as context", #echoes() == 0, table.concat(echoes(), " | "))
H.finish(check, done)
