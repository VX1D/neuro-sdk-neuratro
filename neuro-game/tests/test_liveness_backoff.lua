local H = require("tests.hand_pipeline_harness")
local Window = require("core.window")
local Metrics = require("util.metrics")
local check, done = require("tests.helpers").harness("liveness-backoff")

local forces, scanned = {}, 0
local function force_times()
  local log = H.log_raw or {}
  for i = scanned + 1, #log do
    if log[i].command == "actions/force" then forces[#forces + 1] = log[i] end
  end
  scanned = #log
  return forces
end

H.board()
local base = Window.liveness_timeout(Window.current())
local cap = base * 2 ^ Window.LIVENESS_MAX_DOUBLINGS
local sent_at = {}
local last = 0
local stop = H.CLOCK + base * (1 + 2 + 2 + 2 + 2 + 2) + 60
while H.CLOCK < stop do
  H.tick(0.5, 0.5)
  local n = #force_times()
  if n > last then
    for _ = last + 1, n do sent_at[#sent_at + 1] = H.CLOCK end
    last = n
  end
end

local gaps = {}
for i = 2, #sent_at do gaps[#gaps + 1] = math.floor(sent_at[i] - sent_at[i - 1] + 0.5) end
local shown = table.concat(gaps, ",")
local function near(gap, want) return gap and math.abs(gap - want) <= 3 end
check("the first re-ask waits the base timeout", near(gaps[1], base), shown)
check("a lost force is replaced within twice the base timeout (BEST_PRACTICES.md:35)", cap <= base * 2, tostring(cap))
check("the next unanswered repeat doubles the wait once", near(gaps[2], base * 2), shown)
check("the wait stops growing at the cap", near(gaps[3], cap) and near(gaps[4], cap) and near(gaps[5], cap), shown)
check("and the decision keeps being asked at the cap", #gaps >= 6 and near(gaps[6], cap), shown)
check("every repeat offers the same decision", (function()
  for _, f in ipairs(force_times()) do
    if table.concat(f.data.action_names, ",") ~= "play_hand,discard_hand" then return false end
  end
  return true
end)(), shown)
check("each withdrawal is counted under its reason",
  (Metrics._counters.force_cancel_reason_liveness_timeout or 0) >= #gaps,
  tostring(Metrics._counters.force_cancel_reason_liveness_timeout))

H.send("play_hand", { indices = { 1, 2 } })
H.tick(8)
check("an answer resets the backoff to the base timeout",
  Window.liveness_timeout(Window.current()) == base, tostring(Window.liveness_timeout(Window.current())))

H.finish(check, done)
