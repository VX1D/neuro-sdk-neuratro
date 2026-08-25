local M = {}

M.ROOTS = { "core", "handlers", "hud", "render", "force", "facts", "util", "context" }

M.MUST_DECLARE = {
  blocking  = "true",
  blockable = "true",
  timer     = "(self.created_on_pause and 'REAL') or 'TOTAL'",
}

local function read(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("a")
  fh:close()
  return s
end

function M.lua_files(roots)
  local out = {}
  for _, r in ipairs(roots or M.ROOTS) do
    local p = io.popen("find " .. r .. " -name '*.lua' -type f 2>/dev/null")
    if p then
      for line in p:lines() do out[#out + 1] = line end
      p:close()
    end
  end
  table.sort(out)
  return out
end

function M.constructor_body(src, from)
  local depth, i, n, started = 0, from, #src, false
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

function M.top_level_keys(body)
  local depth, keys = 0, {}
  local start = body:find("{")
  if not start then return keys, false end
  local i, n = start, #body
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

local function line_of(src, pos)
  local n = 1
  for _ in src:sub(1, pos):gmatch("\n") do n = n + 1 end
  return n
end

function M.run(contract, roots)
  local findings = {}
  local function add(kind, where, msg)
    findings[#findings + 1] = { kind = kind, where = where, message = msg }
  end

  local known_field, known_timer, known_func = {}, {}, {}
  for _, f in ipairs(contract.event_fields) do known_field[f] = true end
  for _, t in ipairs(contract.timer_names) do known_timer[t] = true end
  for _, g in ipairs(contract.gfuncs) do known_func[g] = true end

  local files = M.lua_files(roots)
  local sites, ctors, adds = 0, 0, 0
  local seen_func = {}

  for _, path in ipairs(files) do
    local src = read(path)
    if src then
      for _ in src:gmatch("Event%s*[%({]") do ctors = ctors + 1 end
      for _ in src:gmatch("add_event%s*%(") do adds = adds + 1 end

      for name in src:gmatch("G%.FUNCS%.([%w_]+)") do
        if not known_func[name] and not seen_func[name] then
          seen_func[name] = true
          add("unknown-gfunc", path, "G.FUNCS." .. name .. " does not exist in the engine")
        end
      end

      local pos = 1
      while true do
        local a = src:find("add_event%s*%(%s*Event%s*%(%s*{", pos)
        if not a then break end
        sites = sites + 1
        local where = path .. ":" .. line_of(src, a)
        local body = M.constructor_body(src, a)
        local keys, stopped = M.top_level_keys(body)
        local declared = {}
        for _, k in ipairs(keys) do
          declared[k] = true
          if not known_field[k] then
            add("unknown-key", where, "Event key '" .. k .. "' is never read by the engine")
          end
        end
        for field in pairs(M.MUST_DECLARE) do
          if not declared[field] then
            add("implicit-default", where,
              "Event omits '" .. field .. "'; the engine default is "
                .. M.MUST_DECLARE[field])
          end
        end
        for t in body:gmatch('timer%s*=%s*"([%w_]+)"') do
          if not known_timer[t] then
            add("unknown-timer", where, "timer '" .. t .. "' is not a G.TIMERS clock")
          end
        end
        if stopped then
          local tail = body:match(".*[%s;]end,?%s*(.-)$") or ""
          if tail:match("[%w_]+%s*=") then
            add("scan-unsound", where, "a key follows 'func'; the key scan cannot see it")
          end
        end
        pos = a + 1
      end
    end
  end

  if sites ~= ctors then
    add("scan-unsound", "*",
      string.format("%d Event constructors present but %d scanned", ctors, sites))
  end
  if adds ~= ctors then
    add("scan-unsound", "*",
      string.format("%d add_event calls but %d Event constructors", adds, ctors))
  end

  return findings, { sites = sites, files = #files }
end

if arg and arg[0] and arg[0]:find("engine_check") then
  package.path = "./?.lua;;" .. package.path
  local contract = require("tests.engine_contract_generated")
  local findings, stats = M.run(contract)
  print(string.format("engine-check: %d files, %d Event sites, %d G.FUNCS in contract",
    stats.files, stats.sites, #contract.gfuncs))
  for _, f in ipairs(findings) do
    print(string.format("  [%s] %s: %s", f.kind, f.where, f.message))
  end
  print(string.format("%d finding(s)", #findings))
  os.exit(#findings == 0 and 0 or 1)
end

return M
