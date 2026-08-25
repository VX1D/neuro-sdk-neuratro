local P = require("core.bridge_protocol")

local check, fails, checks = require("tests.helpers").collector()

local s = P.startup("Balatro")
check("startup.command", s.command == "startup")
check("startup.game", s.game == "Balatro")
check("startup carries no session identifier (SPECIFICATION.md:3-12 envelope)", s.session_id == nil)

local c = P.context("hello", true)
check("context.command", c.command == "context")
check("context.data.message string", c.data.message == "hello")
check("context.data.silent boolean", c.data.silent == true)
check("context silent coerced from truthy", P.context("x", 1).data.silent == true)
check("context silent default false", P.context("x").data.silent == false)
check("context nil message -> empty string", P.context(nil).data.message == "")

local acts = { { name = "a", description = "d", schema = { type = "object" } } }
local r = P.register(acts)
check("register.command", r.command == "actions/register")
check("register.data.actions is the array", r.data.actions == acts)

local u = P.unregister({ "a", "b" })
check("unregister.command", u.command == "actions/unregister")
check("unregister.data.action_names", u.data.action_names[1] == "a" and u.data.action_names[2] == "b")

local f = P.force("STATE", "your move", { "a", "b" }, { ephemeral_context = true, priority = "low" })
check("force.command", f.command == "actions/force")
check("force.data.state", f.data.state == "STATE")
check("force.data.query", f.data.query == "your move")
check("force.data.ephemeral_context", f.data.ephemeral_context == true)
check("force.data.priority", f.data.priority == "low")
check("force priority is passed through verbatim, not defaulted",
  P.force(nil, nil, nil, { priority = "critical" }).data.priority == "critical")
check("force omits priority when the caller sets none (SDK default is \"low\")",
  P.force(nil, nil, nil).data.priority == nil)
check("force.data.action_names", #f.data.action_names == 2)
local f2 = P.force(nil, nil, nil)
check("force omits state when empty (SDK spec: state is optional)", f2.data.state == nil)
check("force query defaults to empty string", f2.data.query == "")
check("force action_names defaults to empty array", type(f2.data.action_names) == "table" and #f2.data.action_names == 0)

local ar = P.result("id-7", 1, "ok")
check("result.command", ar.command == "action/result")
check("result.data.id", ar.data.id == "id-7")
check("result.data.success is boolean true", ar.data.success == true)
check("result.data.message", ar.data.message == "ok")
check("result.success false is boolean false", P.result("i", nil).data.success == false)
local coded = P.result("i", false, "no", "SCHEMA_INVALID")
check("result carries no reason_code anywhere on the frame",
  coded.reason_code == nil and coded.data.reason_code == nil)

print("====================================================")
if #fails == 0 then
  print("==== protocol: all SDK wire shapes conform, 0 FAIL ====")
else
  print(string.format("==== protocol: %d FAIL ====", #fails))
  for _, failure in ipairs(fails) do print("  FAIL " .. failure) end
end
print("PROTOCOL_FAILS=" .. #fails .. " (0 = clean) PROTOCOL_CHECKS=" .. checks())
os.exit(#fails == 0 and 0 or 1)
