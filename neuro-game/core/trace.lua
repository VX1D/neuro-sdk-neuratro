-- opt-in crash trace, single writer across modules (two openers would truncate each other)
local _crashlog = nil
local trace = function(_) end
local env = os.getenv("NEURO_TRACE")
if env and env ~= "" and env ~= "0" then
  local appdata = os.getenv("APPDATA")
  local path = appdata and (appdata .. "\\Balatro\\neuro_crash_trace.log") or "neuro_crash_trace.log"
  _crashlog = io.open(path, "w")
  if _crashlog then _crashlog:write("=== neuro-game crash trace ===\n"); _crashlog:flush() end
  trace = function(msg)
    local s = "[TRACE] " .. tostring(msg)
    print(s)
    if _crashlog then _crashlog:write(s .. "\n"); _crashlog:flush() end
  end
end
return trace
