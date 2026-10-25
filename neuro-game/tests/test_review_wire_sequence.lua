local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("review-wire-sequence")

local function churn()
  local n, i = 0, 0
  for _, f in ipairs(H.frames()) do
    if not tostring(f.command):find("^neuro%-bridge/") then i = i + 1 end
    local names = type(f.data) == "table" and (f.data.action_names or f.data.actions) or nil
    if i > 2 and (f.command == "actions/unregister" or f.command == "actions/register")
        and type(names) == "table" then
      for _, a in ipairs(names) do
        local nm = type(a) == "table" and a.name or a
        if nm == "play_hand" or nm == "discard_hand" then n = n + 1 end
      end
    end
  end
  return n
end

local function last_force_names()
  local data = H.last_force()
  return data and table.concat(data.action_names or {}, ",")
end

for _, answer in ipairs({ "yes", "no" }) do
  H.board(); H.tick(8)
  local id = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(6)
  local review
  for _, r in ipairs(H.results()) do if r.id == id then review = r end end
  check(answer .. ": the play opens a review with success=true",
    review and review.success == true,
    review and review.message)
  check(answer .. ": the review is forced with resolve_play", last_force_names() == "resolve_play",
    tostring(last_force_names()))
  H.send("resolve_play", { answer = answer }); H.tick(8)
  check(answer .. ": the hand decision is forced again afterwards",
    last_force_names() == "play_hand,discard_hand", tostring(last_force_names()))
  check(answer .. ": play_hand and discard_hand leave once and return once", churn() == 4, tostring(churn()))
  check(answer .. ": the answer takes effect", H.calls.play == (answer == "yes" and 1 or 0),
    tostring(H.calls.play))
end

H.finish(check, done)
