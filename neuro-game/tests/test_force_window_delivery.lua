local H = require("tests.hand_pipeline_harness")
local Window = require("core.window")
local Metrics = require("util.metrics")
local check, done = require("tests.helpers").harness("force-window-delivery")

local function index_of(pred, from)
  for i, f in ipairs(H.frames()) do
    if i > (from or 0) and pred(f) then return i end
  end
end

do
  H.board({ confirm_hand = false })
  check("A: fixture forced", H.wait_force(), H.phase())
  local w, b = Window.current(), G.NEURO
  check("A: fixture liveness outlasts the owed deadline", Window.liveness_timeout(w) > 8,
    tostring(Window.liveness_timeout(w)))
  local real, lose = b.send_action_result, true
  b.send_action_result = function(self, ...)
    if lose then
      lose = false
      return false
    end
    return real(self, ...)
  end
  local undelivered = Metrics._counters.action_result_undelivered or 0
  local forces = H.count("actions/force")
  local id = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.2)
  check("A: the lost result is counted", (Metrics._counters.action_result_undelivered or 0) == undelivered + 1,
    tostring(Metrics._counters.action_result_undelivered))
  check("A: the force its lost success emptied is withdrawn at once", w.phase == "ended"
    and w.ended_by == "result_undelivered", tostring(w.phase) .. "/" .. tostring(w.ended_by))
  check("A: and the force lock is released", not b._force_open, tostring(b._force_open))
  check("A: the result is still owed", H.result_for(id) == nil)
  check("A: a fresh force follows well before the owed deadline", H.wait_force() and H.count("actions/force") == forces + 1,
    forces .. "->" .. H.count("actions/force"))
  local successor = Window.current()
  H.tick(6)
  local n = 0
  for _, r in ipairs(H.results()) do if r.id == id then n = n + 1 end end
  check("A: the owed result is paid once, as success", n == 1 and H.result_for(id).success == true,
    n .. "/" .. tostring(H.result_for(id) and H.result_for(id).message))
  check("A: paying it leaves the successor force open", successor ~= nil and successor.phase == "forced"
    and Window.current() == successor, tostring(successor and successor.phase) .. "/" .. tostring(successor and successor.ended_by))
  check("A: and sends no other force", H.count("actions/force") == forces + 1, forces .. "->" .. H.count("actions/force"))
  check("A: nothing was played", H.calls.play == 0, tostring(H.calls.play))
  b.send_action_result = real
end

do
  H.board({ confirm_hand = false })
  check("B: fixture forced", H.wait_force(), H.phase())
  local w, b = Window.current(), G.NEURO
  local real = b.send_action_result
  local attempts = 0
  b.send_action_result = function() attempts = attempts + 1; return false end
  H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.2)
  check("B: the emptied force is withdrawn at once", w.phase == "ended" and w.ended_by == "result_undelivered",
    tostring(w.phase) .. "/" .. tostring(w.ended_by))
  check("B: a fresh force follows", H.wait_force(), H.phase())
  local successor = Window.current()
  H.tick(27)
  check("B: the owed result is retried, not dropped after one try", attempts >= 3, tostring(attempts))
  check("B: abandoning it past the server's window leaves the successor open",
    (Metrics._counters.action_result_owed_abandoned or 0) >= 1 and successor.phase == "forced",
    tostring(Metrics._counters.action_result_owed_abandoned) .. "/" .. tostring(successor.phase) .. "/" .. tostring(successor.ended_by))
  b.send_action_result = real
  check("B: nothing was played", H.calls.play == 0, tostring(H.calls.play))
end

do
  H.board({ confirm_hand = false })
  G.STATE = H.STATES.SHOP; G.NEURO.state = "SHOP"; G.shop = {}
  G.GAME.dollars = 30; G.NEURO.shop_visit_epoch = 1
  check("C: fixture forced the shop", H.wait_force(), H.phase())
  local b = G.NEURO
  local real, lose = b.send_action_result, true
  b.send_action_result = function(self, ...)
    if lose then lose = false; return false end
    return real(self, ...)
  end
  local id = H.send("record_plan", { money_plan = "Bank the cash." })
  H.tick(0.3)
  G.STATE = H.STATES.SELECTING_HAND
  H.tick(0.4)
  check("C: the hand force followed the screen change", H.wait_force(), H.phase())
  G.STATE = H.STATES.SHOP; G.shop = {}
  H.tick(0.4)
  check("C: a same-named shop force replaced it", H.wait_force(), H.phase())
  local successor, forces = Window.current(), H.count("actions/force")
  H.tick(3)
  check("C: the old result is paid", H.result_for(id) ~= nil, tostring(H.result_for(id)))
  check("C: the successor force is still open", successor.phase == "forced" and Window.current() == successor,
    tostring(successor.phase) .. "/" .. tostring(successor.ended_by))
  check("C: and no other force went out", H.count("actions/force") == forces, forces .. "->" .. H.count("actions/force"))
  b.send_action_result = real
end

H.finish(check, done)
