local DUMP_DEFAULT = os.getenv("BALATRO_DUMP") or "dump"

local M = {}

local function read(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("a")
  fh:close()
  return s
end

function M.event_defaults(dump)
  local src = read((dump or DUMP_DEFAULT) .. "/engine/event.lua")
  if not src then return nil, "engine/event.lua not readable" end
  local body = src:match("function Event:init%(config%)(.-)\nend")
  if not body then return nil, "Event:init not found" end

  local out, seen = {}, {}
  local function add(field, default, shape)
    if seen[field] then return end
    seen[field] = true
    out[#out + 1] = { field = field, default = default, shape = shape }
  end

  for field in body:gmatch("if%s+config%.([%w_]+)%s*~=%s*nil%s+then") do
    local blk = body:match("if%s+config%." .. field .. "%s*~=%s*nil%s+then(.-)\n%s*end")
    local els = blk and blk:match("else%s*\n%s*self%.[%w_]+%s*=%s*([^\n]+)")
    add(field, els and els:gsub("%s+$", "") or "?", "if-nil")
  end
  for field, dflt in body:gmatch("self%.([%w_]+)%s*=%s*config%.[%w_]+%s+or%s+([^\n]+)") do
    add(field, (dflt:gsub("%s+$", "")), "or")
  end

  table.sort(out, function(a, b) return a.field < b.field end)
  return out
end

function M.event_fields(dump)
  local src = read((dump or DUMP_DEFAULT) .. "/engine/event.lua")
  if not src then return nil, "engine/event.lua not readable" end
  local seen, out = {}, {}
  for field in src:gmatch("config%.([%w_]+)") do
    if not seen[field] then seen[field] = true; out[#out + 1] = field end
  end
  table.sort(out)
  return out
end

function M.timer_names(dump)
  local src = read((dump or DUMP_DEFAULT) .. "/globals.lua")
  if not src then return nil, "globals.lua not readable" end
  local block = src:match("self%.TIMERS%s*=%s*{(.-)}")
  if not block then return nil, "G.TIMERS not found" end
  local out = {}
  for name in block:gmatch("(%u[%u_]*)%s*=") do out[#out + 1] = name end
  table.sort(out)
  return out
end

function M.gfuncs(dump)
  local root = dump or DUMP_DEFAULT
  local seen, out = {}, {}
  local p = io.popen("grep -rhoE 'G\\.FUNCS\\.[A-Za-z_0-9]+ *= *function|function G\\.FUNCS\\.[A-Za-z_0-9]+' "
    .. root .. " 2>/dev/null")
  if not p then return nil, "grep unavailable" end
  for line in p:lines() do
    local name = line:match("G%.FUNCS%.([A-Za-z_0-9]+)")
    if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  p:close()
  table.sort(out)
  if #out == 0 then return nil, "no G.FUNCS definitions found" end
  return out
end

local function serialise_list(name, list)
  local lines = { "  " .. name .. " = {" }
  for _, v in ipairs(list) do lines[#lines + 1] = string.format("    %q,", v) end
  lines[#lines + 1] = "  },"
  return table.concat(lines, "\n")
end

function M.serialise_all(c)
  local lines = { "return {", "  event_defaults = {" }
  for _, d in ipairs(c.event_defaults) do
    lines[#lines + 1] = string.format("    { field = %q, default = %q, shape = %q },",
      d.field, d.default, d.shape)
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = serialise_list("event_fields", c.event_fields)
  lines[#lines + 1] = serialise_list("timer_names", c.timer_names)
  lines[#lines + 1] = serialise_list("gfuncs", c.gfuncs)
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

function M.collect(dump)
  local d, e1 = M.event_defaults(dump)
  if not d then return nil, e1 end
  local f, e2 = M.event_fields(dump)
  if not f then return nil, e2 end
  local t, e3 = M.timer_names(dump)
  if not t then return nil, e3 end
  local g, e4 = M.gfuncs(dump)
  if not g then return nil, e4 end
  return { event_defaults = d, event_fields = f, timer_names = t, gfuncs = g }
end

function M.serialise(defaults)
  local lines = { "return {" }
  for _, d in ipairs(defaults) do
    lines[#lines + 1] = string.format("  { field = %q, default = %q, shape = %q },",
      d.field, d.default, d.shape)
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

if arg and arg[0] and arg[0]:find("gen_engine_contract") then
  local c, err = M.collect(arg[1])
  if not c then
    io.stderr:write("gen_engine_contract: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  local target = "tests/engine_contract_generated.lua"
  local fh = assert(io.open(target, "w"))
  fh:write(M.serialise_all(c))
  fh:close()
  print(string.format("wrote %s: %d event defaults, %d event fields, %d timers, %d G.FUNCS",
    target, #c.event_defaults, #c.event_fields, #c.timer_names, #c.gfuncs))
end

return M
