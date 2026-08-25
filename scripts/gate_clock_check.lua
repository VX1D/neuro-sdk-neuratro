local M = {}

M.RUNTIME_DIRS = { "core", "force", "util", "handlers", "hud", "render", "facts", "context" }

M.DESCRIPTOR_FILES = {
  ["core/config_schema.lua"] = true,
  ["hud/tuning_panel.lua"] = true,
  ["core/gate_clocks.lua"] = true,
}

M.CLOCK_OWNER = "util/utils.lua"

M.CLOCK_SUBSTITUTES = { ["hud/dev_scenario.lua"] = true }

M.ACCESSORS = { gate_now = true, gate_seconds = true, gate_clock = true }
M.INSTANT_ACCESSORS = { gate_now = true }

local function popen_lines(cmd)
  local pipe = assert(io.popen(cmd, "r"))
  local out = {}
  for line in pipe:lines() do out[#out + 1] = line end
  pipe:close()
  return out
end

function M.source_files()
  local parts = {}
  for _, dir in ipairs(M.RUNTIME_DIRS) do parts[#parts + 1] = dir end
  local files = popen_lines("find " .. table.concat(parts, " ") .. " -name '*.lua' | sort")
  local out = {}
  for _, path in ipairs(files) do
    if not M.DESCRIPTOR_FILES[path] then out[#out + 1] = path end
  end
  return out
end

local function read(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local src = fh:read("*all")
  fh:close()
  return src
end

local function line_of(src, pos)
  local n = 1
  for _ in src:sub(1, pos):gmatch("\n") do n = n + 1 end
  return n
end

local function constructor_body(src, from)
  local depth, i, n, started = 0, from, #src, false
  while i <= n do
    local char = src:sub(i, i)
    if char == "(" or char == "{" then
      depth, started = depth + 1, true
    elseif char == ")" or char == "}" then
      depth = depth - 1
      if started and depth <= 0 then return src:sub(from, i) end
    end
    i = i + 1
  end
  return src:sub(from)
end

local function function_defs(src)
  local defs = {}
  local function collect(pattern)
    for pos, name, param in src:gmatch(pattern) do
      defs[#defs + 1] = { pos = pos, name = name, param = param }
    end
  end
  collect("()local%s+function%s+([%w_]+)%s*%(%s*([%w_]+)")
  collect("()local%s+([%w_]+)%s*=%s*function%s*%(%s*([%w_]+)")
  collect("()function%s+[%w_]+[%.:]([%w_]+)%s*%(%s*([%w_]+)")
  table.sort(defs, function(a, b) return a.pos < b.pos end)
  for i = 1, #defs do
    defs[i].body = src:sub(defs[i].pos, (defs[i + 1] and defs[i + 1].pos - 1) or #src)
  end
  return defs
end

local function route_names(src, seed)
  local names = {}
  for name in pairs(seed) do names[name] = true end
  local defs = function_defs(src)
  local changed = true
  while changed do
    changed = false
    for _, def in ipairs(defs) do
      if not names[def.name] then
        for name in pairs(names) do
          if def.body:find("%f[%w_]" .. name .. "%s*%(%s*" .. def.param .. "%f[^%w_]") then
            names[def.name] = true
            changed = true
            break
          end
        end
      end
    end
  end
  return names
end

function M.routed_ids(src, seed)
  local routed = {}
  for name in pairs(route_names(src, seed)) do
    for pos, id in src:gmatch("()%f[%w_]" .. name .. "%s*%(%s*\"([%w_]+)\"") do
      routed[id] = routed[id] or pos
    end
  end
  return routed
end

function M.run(contract, schema, overlay)
  local function src_of(path)
    if overlay and overlay[path] then return overlay[path] end
    return read(path)
  end
  local findings = {}
  local function add(rule, where, detail)
    findings[#findings + 1] = { rule = rule, where = where, detail = detail }
  end

  local timed_knob, scaled_knob = {}, {}
  for _, def in ipairs(schema.entries) do
    if def.kind == "number" and def.unit == "s" then timed_knob[def.key] = true end
    if def.cd then scaled_knob[def.key] = true end
  end

  local function prefix_is_scaled(prefix)
    for _, def in ipairs(schema.entries) do
      if def.cd and def.key:sub(1, #prefix) == prefix then return true end
    end
    return false
  end

  local knob_owner, prefix_owner, wired_gates_by_file = {}, {}, {}
  for _, gate in ipairs(contract.gates) do
    for _, knob in ipairs(gate.knobs or {}) do
      knob_owner[knob .. "\0" .. gate.file] = gate.id
      if not timed_knob[knob] then
        add("knob-not-timed", gate.id, "'" .. knob .. "' is not a config key with unit 's'")
      end
    end
    if gate.knob_prefix then prefix_owner[gate.knob_prefix .. "\0" .. gate.file] = gate.id end
    if gate.wired ~= true and type(gate.blocked_by) ~= "string" then
      add("undeclared-deferral", gate.id, "unwired gate does not say what blocks it")
    end
    if gate.wired == true then
      wired_gates_by_file[gate.file] = wired_gates_by_file[gate.file] or {}
      wired_gates_by_file[gate.file][#wired_gates_by_file[gate.file] + 1] = gate
    end
  end

  local files = M.source_files()
  local routed_by_file = {}
  for _, path in ipairs(files) do
    local src = src_of(path) or ""
    routed_by_file[path] = M.routed_ids(src, M.ACCESSORS)
    local instant_routed = M.routed_ids(src, M.INSTANT_ACCESSORS)

    if path == "render/neuro-anim.lua" then
      local pos, sites = 1, 0
      while true do
        local event_at = src:find("add_event%s*%(%s*Event%s*%(%s*{", pos)
        if not event_at then break end
        sites = sites + 1
        local body = constructor_body(src, event_at)
        if not body:find("timer%s*=%s*Utils%.gate_clock%s*%(") then
          add("animation-event-clock", path .. ":" .. line_of(src, event_at),
            "animation events must obtain their timer from Utils.gate_clock")
        end
        pos = event_at + 1
      end
      if sites == 0 then
        add("animation-event-clock", path, "no animation Event sites were found")
      end
    end

    for pos, id in src:gmatch("()gate_now%s*%(%s*\"([%w_]+)\"") do
      if not contract.by_id[id] then
        add("unknown-gate", path .. ":" .. line_of(src, pos), "no gate '" .. id .. "' in the table")
      else
        if contract.by_id[id].file ~= path then
          add("gate-off-file", path .. ":" .. line_of(src, pos),
            "gate '" .. id .. "' belongs to " .. contract.by_id[id].file)
        end
      end
    end
    for pos, id in src:gmatch("()gate_seconds%s*%(%s*\"([%w_]+)\"") do
      if not contract.by_id[id] then
        add("unknown-gate", path .. ":" .. line_of(src, pos), "no gate '" .. id .. "' in the table")
      else
        if contract.by_id[id].file ~= path then
          add("gate-off-file", path .. ":" .. line_of(src, pos),
            "gate '" .. id .. "' belongs to " .. contract.by_id[id].file)
        end
      end
    end

    for pos, key in src:gmatch("()\"(NEURO_[%u%d_]+)\"") do
      if timed_knob[key] and not knob_owner[key .. "\0" .. path] then
        add("unclassified-knob", path .. ":" .. line_of(src, pos),
          "'" .. key .. "' is read here but no gate in the table pairs it with this file")
      end
    end
    for pos, prefix in src:gmatch("()\"(NEURO_[%u%d_]+_)\"%s*%.%.") do
      if not prefix_owner[prefix .. "\0" .. path] then
        add("unclassified-knob-prefix", path .. ":" .. line_of(src, pos),
          "keys built from '" .. prefix .. "' are read here but no gate in the table claims them")
      end
    end

    local function double_scaled(pos, key, gate_id)
      local gate = gate_id and contract.by_id[gate_id]
      if not (gate and gate.clock == contract.TOTAL) then return end
      add("double-scaled-knob", path .. ":" .. line_of(src, pos),
        "'" .. key .. "' is a cd knob on TOTAL gate '" .. gate_id .. "'; read it through Utils.gate_seconds")
    end
    local function raw_knob_read(pos, key, gate_id)
      local gate = gate_id and contract.by_id[gate_id]
      if not (gate and gate.wired == true) then return end
      add("raw-knob-bypass", path .. ":" .. line_of(src, pos),
        "'" .. key .. "' is wired gate '" .. gate_id .. "'s own knob; read it through Utils.gate_seconds")
    end
    for pos, key in src:gmatch("()%.get%s*%(%s*\"(NEURO_[%u%d_]+)\"") do
      local gate_id = knob_owner[key .. "\0" .. path]
      if scaled_knob[key] then double_scaled(pos, key, gate_id) end
      raw_knob_read(pos, key, gate_id)
    end
    for pos, prefix in src:gmatch("()%.get%s*%(%s*\"(NEURO_[%u%d_]+_)\"%s*%.%.") do
      local gate_id = prefix_owner[prefix .. "\0" .. path]
      if prefix_is_scaled(prefix) then double_scaled(pos, prefix .. "*", gate_id) end
      raw_knob_read(pos, prefix .. "*", gate_id)
    end

    if path ~= M.CLOCK_OWNER and not M.CLOCK_SUBSTITUTES[path] then
      for pos in src:gmatch("()%f[%w_]TIMERS%f[^%w_]") do
        add("raw-game-clock", path .. ":" .. line_of(src, pos),
          "the game clock is reachable only through " .. M.CLOCK_OWNER)
      end
      local RAW_CLOCK_PATTERN = { REAL = "Utils%.now%f[%W]", TOTAL = "Utils%.game_now%f[%W]",
                                  WALL = "Utils%.wall_now%f[%W]" }
      for _, gate in ipairs(wired_gates_by_file[path] or {}) do
        local pattern = RAW_CLOCK_PATTERN[gate.clock]
        if pattern and not instant_routed[gate.id] then
          local pos = src:find(pattern)
          if pos then
            add("raw-clock-bypass", path .. ":" .. line_of(src, pos),
              "gate '" .. gate.id .. "' has no gate_now/gate_seconds route of its own left in "
                .. path .. ", which still reads " .. gate.clock .. " raw")
          end
        end
      end
    end
  end

  for _, gate in ipairs(contract.gates) do
    if gate.wired == true and not (routed_by_file[gate.file] and routed_by_file[gate.file][gate.id]) then
      add("unwired-gate", gate.id,
        gate.file .. " never reads its clock through gate_now/gate_seconds")
    end
    if not src_of(gate.file) then
      add("missing-file", gate.id, gate.file .. " does not exist")
    end
  end

  return findings, { files = #files, gates = #contract.gates }
end

if arg and arg[0] and arg[0]:find("gate_clock_check") then
  package.path = "./?.lua;;" .. package.path
  local contract = require("core.gate_clocks")
  local schema = require("core.config_schema")
  local findings, stats = M.run(contract, schema)
  print(string.format("gate-clock-check: %d files, %d gates", stats.files, stats.gates))
  for _, f in ipairs(findings) do
    print(string.format("  FAIL %-24s %s -- %s", f.rule, f.where, f.detail))
  end
  if #findings > 0 then
    print(string.format("gate-clock-check: %d findings", #findings))
    os.exit(1)
  end
  print("gate-clock-check: clean")
end

return M
