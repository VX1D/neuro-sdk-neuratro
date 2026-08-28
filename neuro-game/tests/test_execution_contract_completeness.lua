_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("execution-contract-completeness")
local Actions = require("core.actions")
local Execution = require("core.action_execution")

local NO_GENERIC_WRAP = { confirm_play = true }

local mutating = {}
for _, definition in ipairs(Actions.get_static_actions()) do
  if not NO_GENERIC_WRAP[definition.name] then
    mutating[#mutating + 1] = definition.name
  end
end
table.sort(mutating)

local ok, missing, extra = Execution.validate(mutating)
check("all mutating actions have exactly one execution contract",
  ok, "missing=" .. table.concat(missing, ",") .. " extra=" .. table.concat(extra, ","))
check("registry contains 27 mutating actions", #mutating == 27, #mutating)

local counts = { native = 0, sync = 0, async = 0 }
for _, name in ipairs(mutating) do
  local class = Execution.classification(name)
  check(name .. " has a known execution class", counts[class] ~= nil, class)
  if counts[class] ~= nil then counts[class] = counts[class] + 1 end
end
check("execution classes cover the full registry",
  counts.native + counts.sync + counts.async == 27,
  string.format("native=%d sync=%d async=%d", counts.native, counts.sync, counts.async))

done()
