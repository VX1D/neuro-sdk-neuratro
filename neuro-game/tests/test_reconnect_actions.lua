local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("reconnect-actions")

H.board({ confirm_hand = false })
check("fixture: the hand screen is forced", H.wait_force(), H.phase())
local id = H.send("discard_hand", { indices = { 1 } })
H.tick(0.1)
check("fixture: the discard is accepted and staged", (H.result_for(id) or {}).success == true
  and require("core.execute").busy() == "staged", tostring(require("core.execute").busy()))

local mark = #H.frames()
H.inbox({ command = "neuro-bridge/reregister_all", transport_session = "reconnect-2" })
H.tick(2)
check("the reconnect cancels it before it runs", H.calls.discard == 0, tostring(H.calls.discard))
local told
for i = mark + 1, #H.frames() do
  local f = H.frames()[i]
  if f.command == "context" and f.data.message:find("did not complete successfully", 1, true) then
    told = true
  end
end
check("and tells her it was not carried out", told == true, "")

mark = #H.frames()
H.tick(8)
H.inbox({ command = "action", data = { id = id, name = "discard_hand", data = '{"indices":[1]}' } })
H.tick(2)
local fresh = H.results_since(mark, id)
check("an id from the old session is a new action on the new one", #fresh == 1 and fresh[1].success == true
  and H.calls.discard == 1, #fresh .. "/" .. tostring(fresh[1] and fresh[1].success) .. "/" .. H.calls.discard)

mark = #H.frames()
H.inbox({ command = "action", data = { id = id, name = "discard_hand", data = '{"indices":[1]}' } })
H.tick(1)
check("a duplicate within one session gets no second result and never runs twice",
  #H.results_since(mark, id) == 0 and H.calls.discard == 1, tostring(H.calls.discard))

H.finish(check, done)
