-- Load-time smoke test: require EVERY mod module under a permissive love/SMODS/G stub and
-- report any that error at require time. Byte-compilation (luajit -bl) only checks syntax;
-- this catches module-level execution errors (bad require path, nil index at load, a stripped
-- dependency) -- the same class of failure as a broken SMODS entry, but for internals.
--
-- luajit tests/run_loadcheck.lua   (exit 0 = all modules load)

package.path = "./?.lua;;" .. package.path

-- permissive love stub: any love.<subsystem>.<fn>(...) is a no-op returning a chainable stub
local function noop() return nil end
local function stub_table()
  return setmetatable({}, {
    __index = function(_, _) return function(...) return nil end end,
  })
end
love = setmetatable({
  timer = { getTime = function() return 0 end },
  graphics = stub_table(),
  audio = stub_table(),
  system = stub_table(),
  window = stub_table(),
  filesystem = stub_table(),
  math = { random = math.random, noise = function() return 0 end },
  keyboard = stub_table(),
  mouse = stub_table(),
  event = stub_table(),
  thread = stub_table(),
}, { __index = function(_, _) return function(...) return nil end end })

_G.G = {
  NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 0 },
  STATES = {}, SETTINGS = { paused = false }, C = stub_table(),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, localization = {},
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {} }
_G.NFS = stub_table()

-- discover every module: every .lua under the mod except tests/ and the SMODS entry
-- (entry installs love hooks / requires the design harness; not a plain module)
local SKIP = {
  ["neuro-game"] = true,        -- SMODS entry chunk, not a require()-able module
  ["golden_test"] = true,       -- gitignored offline harness
}

-- relies on POSIX find (fine for this Linux-only offline gate)
local ROOTS = { "core", "context", "force", "facts", "handlers", "hud", "render", "util" }

local function list_lua_modules()
  local out = {}
  local p = io.popen('find ' .. table.concat(ROOTS, " ") .. ' -name "*.lua" 2>/dev/null')
  if not p then return out end
  for path in p:lines() do
    local mod = path:gsub("^%./", ""):gsub("%.lua$", ""):gsub("/", ".")
    out[#out + 1] = mod
  end
  p:close()
  return out
end

local mods = list_lua_modules()
table.sort(mods)

print("====================================================")
print("[load] require-time smoke test (" .. #mods .. " modules)")
print("====================================================")

local fails = {}
local ok_count = 0
for _, mod in ipairs(mods) do
  local leaf = mod:match("([^.]+)$")
  if not SKIP[leaf] then
    local ok, err = pcall(require, mod)
    if ok then
      ok_count = ok_count + 1
    else
      fails[#fails + 1] = mod .. "  ->  " .. tostring(err):gsub("\n.*", "")
    end
  end
end

print(string.format("[load] %d loaded ok", ok_count))
print("====================================================")
if #fails == 0 then
  print(string.format("==== loadcheck: %d modules, 0 FAIL ====", ok_count))
else
  print(string.format("==== loadcheck: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("====================================================")
print("LOADCHECK_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
