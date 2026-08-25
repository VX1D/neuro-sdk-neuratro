
local Audit = require("tools.sdk_wire_audit")
local check, done = require("tests.helpers").harness("sdk-wire-audit")
local TmpWork = require("tests.tmp_workdir")
local dir = TmpWork.open("sdk_wire_audit")
os.execute("mkdir -p '" .. dir .. "'")

local function write(path, lines)
  local f = assert(io.open(path, "wb"))
  for _, line in ipairs(lines) do f:write(line, "\n") end
  f:close()
end

local inbox, outbox = dir .. "/in.jsonl", dir .. "/out.jsonl"
write(inbox, {
  '{"command":"action","data":{"id":"a1","name":"play_hand","data":"{}"}}',
})
write(outbox, {
  '{"command":"startup","game":"Balatro"}',
  '{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand","description":"d","schema":{"type":"object"}}]}}',
  '{"command":"actions/force","game":"Balatro","data":{"query":"q","action_names":["play_hand"]}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"a1","success":true,"message":"ok"}}',
})
check("a complete correlated exchange passes", #Audit.scan(inbox, outbox) == 0)

write(outbox, {
  '{"command":"context","game":"Balatro","data":{"message":"bad first","silent":true}}',
  '{"command":"actions/force","game":"Balatro","data":{"query":"q","action_names":["missing"]}}',
  '{"command":"actions/force","game":"Balatro","data":{"query":"q2","action_names":["missing"]}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"a1","success":false,"message":"expired force; not executed"}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"a1","success":false,"message":"again"}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"foreign","success":true}}',
})
local kinds = {}
for _, v in ipairs(Audit.scan(inbox, outbox)) do kinds[v.kind] = true end
check("audit catches startup ordering", kinds.startup_not_first == true)
check("audit catches overlapping forces", kinds.overlapping_force == true)
check("audit catches duplicate results", kinds.duplicate_result == true)
check("audit catches results without an inbound action", kinds.result_without_action == true)
check("audit catches terminal prose paired with retry=true", kinds.terminal_result_requests_retry == true)

write(outbox, {
  '{"command":"startup","game":"Balatro"}',
  '{"command":"actions/force","game":"Balatro","data":{"query":"q","action_names":["play_hand"],"reason_code":"INTERNAL"}}',
  '{"command":"context","game":"Balatro","data":{"message":"m"},"seq":12}',
  '{"command":"shutdown/ready","game":"Balatro"}',
  '{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"x__force_3","description":"d"}]}}',
})
kinds = {}
for _, v in ipairs(Audit.scan(inbox, outbox)) do kinds[v.kind] = true end
check("audit catches undeclared data fields", kinds.undeclared_data_field == true)
check("audit catches undeclared envelope fields", kinds.undeclared_wire_field == true)
check("audit catches commands outside the C2S set", kinds.unknown_command == true)
check("audit catches action names outside the SDK lowercase separator recommendation",
  kinds.invalid_action_name == true)

write(inbox, {
  '{"command":"action","data":{"id":"l1","name":"play_hand_force_7","data":"{}"}}',
  '{"command":"action","data":{"id":"l2","name":"play_hand_force_7","data":"{}"}}',
  '{"command":"action","data":{"id":"l3","name":"play_hand_force_7","data":"{}"}}',
})
write(outbox, {
  '{"command":"startup","game":"Balatro"}',
  '{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"play_hand_force_7","description":"d"}]}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"l1","success":true,"message":"expired force; not executed"}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"l2","success":true,"message":"expired force; not executed"}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"l3","success":true,"message":"expired force; not executed"}}',
})
kinds = {}
for _, v in ipairs(Audit.scan(inbox, outbox)) do kinds[v.kind] = true end
check("audit classifies terminal acknowledgements without execution",
  kinds.ack_without_execution == true)
check("audit detects a repeated unchanged terminal acknowledgement loop",
  kinds.semantic_livelock == true)

write(inbox, {
  '{"command":"action","data":{"id":"forced-id","name":"cash_out_force_1","data":"{}"}}',
  '{"command":"action","data":{"id":"foreign-id","name":"set_plan","data":"{}"}}',
})
write(outbox, {
  '{"command":"startup","game":"Balatro"}',
  '{"command":"actions/register","game":"Balatro","data":{"actions":[{"name":"cash_out_force_1","description":"d"},{"name":"set_plan","description":"d"},{"name":"cash_out_force_2","description":"d"}]}}',
  '{"command":"actions/force","game":"Balatro","data":{"query":"q","action_names":["cash_out_force_1"]}}',
  '{"command":"action/result","game":"Balatro","data":{"id":"foreign-id","success":true}}',
  '{"command":"actions/force","game":"Balatro","data":{"query":"q2","action_names":["cash_out_force_2"]}}',
})
kinds = {}
for _, v in ipairs(Audit.scan(inbox, outbox)) do kinds[v.kind] = true end
check("audit correlates result ids before closing an active force", kinds.overlapping_force == true)

os.execute("rm -rf '" .. dir .. "'")
TmpWork.close()
done()
