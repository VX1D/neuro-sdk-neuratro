
local check, done = require("tests.helpers").harness("event flags")

local ROOTS = { "core", "handlers", "hud", "render", "force", "facts", "util", "context" }

local function list_lua(dir, out)
  local p = io.popen("find " .. dir .. " -name '*.lua' -type f 2>/dev/null")
  if not p then return out end
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end

local files = {}
for _, r in ipairs(ROOTS) do list_lua(r, files) end
table.sort(files)

local function constructor_body(src, from)
  local depth, i, n = 0, from, #src
  local started = false
  while i <= n do
    local c = src:sub(i, i)
    if c == "(" or c == "{" then depth = depth + 1; started = true
    elseif c == ")" or c == "}" then
      depth = depth - 1
      if started and depth <= 0 then return src:sub(from, i) end
    end
    i = i + 1
  end
  return src:sub(from)
end

local C = require("tests.engine_contract_generated")
local CONTRACT = C.event_defaults
local MUST_DECLARE = {
  blocking  = "true",
  blockable = "true",
  timer     = "(self.created_on_pause and 'REAL') or 'TOTAL'",
}

local contract_by_field = {}
for _, d in ipairs(CONTRACT) do contract_by_field[d.field] = d end

do
  local unknown, drifted = {}, {}
  for field, expected in pairs(MUST_DECLARE) do
    local d = contract_by_field[field]
    if not d then
      unknown[#unknown + 1] = field
    elseif d.default ~= expected then
      drifted[#drifted + 1] = field .. " (" .. d.default .. ")"
    end
  end
  check("every policed field still exists in the engine contract ("
    .. table.concat(unknown, ", ") .. ")", #unknown == 0)
  check("no policed engine default has drifted (" .. table.concat(drifted, ", ") .. ")",
    #drifted == 0)
end

local sites, missing_by_field = 0, {}
for field in pairs(MUST_DECLARE) do missing_by_field[field] = {} end

for _, path in ipairs(files) do
  local fh = io.open(path, "r")
  if fh then
    local src = fh:read("a")
    fh:close()
    local pos = 1
    while true do
      local s = src:find("add_event%s*%(%s*Event%s*%(%s*{", pos)
      if not s then break end
      sites = sites + 1
      local body = constructor_body(src, s)
      local line = 1
      for _ in src:sub(1, s):gmatch("\n") do line = line + 1 end
      for field in pairs(MUST_DECLARE) do
        if not body:find(field, 1, true) then
          local bucket = missing_by_field[field]
          bucket[#bucket + 1] = path .. ":" .. line
        end
      end
      pos = s + 1
    end
  end
end

local raw_ctors, raw_adds = 0, 0
for _, path in ipairs(files) do
  local fh = io.open(path, "r")
  if fh then
    local src = fh:read("a")
    fh:close()
    for _ in src:gmatch("Event%s*[%({]") do raw_ctors = raw_ctors + 1 end
    for _ in src:gmatch("add_event%s*%(") do raw_adds = raw_adds + 1 end
  end
end
check("found the mod's Event constructions (" .. sites .. ")", sites > 0)
check(string.format("the scanner sees every Event constructor in the tree (%d scanned, %d present)",
  sites, raw_ctors), sites == raw_ctors)
check(string.format("every queued event is an inline Event literal (%d add_event, %d Event)",
  raw_adds, raw_ctors), raw_adds == raw_ctors)
for field in pairs(MUST_DECLARE) do
  local bucket = missing_by_field[field]
  check("every Event declares " .. field .. " explicitly ("
    .. table.concat(bucket, ", ") .. ")", #bucket == 0)
end

local Event = { init = function(cfg)
  local blocking = true
  if cfg.blocking ~= nil then blocking = cfg.blocking end
  return blocking
end, init_timer = function(cfg) return cfg.timer or "TOTAL" end }
check("engine default for an undeclared blocking is true", Event.init({}) == true)
check("an undeclared blocking is not implied by blockable", Event.init({ blockable = false }) == true)
check("engine default for an undeclared timer is TOTAL", Event.init_timer({}) == "TOTAL")
check("a declared timer survives the constructor", Event.init_timer({ timer = "REAL" }) == "REAL")

do
  local script_path = io.open("scripts/gen_engine_contract.lua") and "scripts/gen_engine_contract.lua" or "../scripts/gen_engine_contract.lua"
  local ok_gen, Gen = pcall(dofile, script_path)
  local live = ok_gen and Gen and Gen.collect and Gen.collect() or nil
  if not live then
    require("tests.skip_ledger").note("event-flags/engine-freshness", 1,
      "engine dump not present on this machine, tests/engine_contract_generated.lua "
      .. "was not checked against the installed engine")
  else
    local vendored = Gen.serialise_all(C)
    local regenerated = Gen.serialise_all(live)
    check("the vendored engine contract still matches the installed engine",
      vendored == regenerated,
      vendored == regenerated and "" or "run: luajit scripts/gen_engine_contract.lua")
  end
end

local function top_level_keys(body)
  local depth, keys = 0, {}
  local i, n = 1, #body
  local start = body:find("{")
  if not start then return keys end
  i = start
  while i <= n do
    local ch = body:sub(i, i)
    if ch == "{" or ch == "(" then
      depth = depth + 1
    elseif ch == "}" or ch == ")" then
      depth = depth - 1
      if depth <= 0 then break end
    elseif depth == 1 then
      local key, rest = body:match("^([%w_]+)%s*=()", i)
      if key and body:sub(i - 1, i - 1):match("[%s{,]") then
        keys[#keys + 1] = key
        if key == "func" then return keys, true end
        i = rest - 1
      end
    end
    i = i + 1
  end
  return keys, false
end

do
  local known_field = {}
  for _, f in ipairs(C.event_fields) do known_field[f] = true end
  local known_timer = {}
  for _, t in ipairs(C.timer_names) do known_timer[t] = true end

  local unknown_keys, bad_timers, func_not_last = {}, {}, {}
  for _, path in ipairs(files) do
    local fh = io.open(path, "r")
    if fh then
      local src = fh:read("a")
      fh:close()
      local pos = 1
      while true do
        local a = src:find("add_event%s*%(%s*Event%s*%(%s*{", pos)
        if not a then break end
        local body = constructor_body(src, a)
        local line = 1
        for _ in src:sub(1, a):gmatch("\n") do line = line + 1 end
        local keys, stopped_at_func = top_level_keys(body)
        for _, key in ipairs(keys) do
          if not known_field[key] then
            unknown_keys[#unknown_keys + 1] = path .. ":" .. line .. " " .. key
          end
        end
        if stopped_at_func then
          local tail = body:match(".*[%s;]end,?%s*(.-)$") or ""
          if tail:match("[%w_]+%s*=") then
            func_not_last[#func_not_last + 1] = path .. ":" .. line
          end
        end
        for t in body:gmatch('timer%s*=%s*"([%w_]+)"') do
          if not known_timer[t] then
            bad_timers[#bad_timers + 1] = path .. ":" .. line .. " " .. t
          end
        end
        pos = a + 1
      end
    end
  end
  check("no Event is given a key the engine never reads ("
    .. table.concat(unknown_keys, ", ") .. ")", #unknown_keys == 0)
  check("func stays the last key so the key scan stays sound ("
    .. table.concat(func_not_last, ", ") .. ")", #func_not_last == 0)
  check("every declared timer is a real G.TIMERS clock ("
    .. table.concat(bad_timers, ", ") .. ")", #bad_timers == 0)
end

do
  local known = {}
  for _, name in ipairs(C.gfuncs) do known[name] = true end
  local missing = {}
  for _, path in ipairs(files) do
    local fh = io.open(path, "r")
    if fh then
      local src = fh:read("a")
      fh:close()
      for name in src:gmatch("G%.FUNCS%.([%w_]+)") do
        if not known[name] and not missing[name] then
          missing[name] = true
          missing[#missing + 1] = path .. " -> " .. name
        end
      end
    end
  end
  check("every G.FUNCS the mod names exists in the engine ("
    .. table.concat(missing, ", ") .. ")", #missing == 0)
  check("the contract captured a plausible G.FUNCS surface (" .. #C.gfuncs .. ")",
    #C.gfuncs > 150)
end

do
  local check_path = io.open("scripts/engine_check.lua") and "scripts/engine_check.lua" or "../scripts/engine_check.lua"
  local ok_chk, Check = pcall(dofile, check_path)
  check("the standalone checker loads", ok_chk and type(Check) == "table" and Check.run ~= nil)
  if ok_chk and Check and Check.run then
    local findings, stats = Check.run(C)
    local lines = {}
    for _, f in ipairs(findings) do
      lines[#lines + 1] = f.kind .. " " .. f.where
    end
    check("the standalone checker reports no findings (" .. table.concat(lines, ", ") .. ")",
      #findings == 0)
    check("the standalone checker sees the same Event sites as this test ("
      .. stats.sites .. " vs " .. sites .. ")", stats.sites == sites)
  end
end

done()
