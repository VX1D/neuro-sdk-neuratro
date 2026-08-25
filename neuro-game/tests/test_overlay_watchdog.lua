rawset(_G, "NEURO_TEST", true)

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
love = setmetatable({
  graphics = setmetatable({
    getFont = function() return FONT end,
    newFont = function() return FONT end,
    getWidth = function() return 1920 end,
    getHeight = function() return 1080 end,
    getScissor = function() return nil end,
    print = noop,
  }, { __index = function() return noop end }),
  timer = { getTime = function() return 0 end },
  math = { random = math.random, noise = function() return 0 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = { persona = "neuro", state = "MENU", ai_highlighted = {} },
  GAME = { dollars = 25 }, TIMERS = { REAL = 0 },
  STAGE = 1, STAGES = { MAIN_MENU = 1, RUN = 2 },
  P_CENTERS = {}, P_CENTER_POOLS = {}, localization = {},
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, FUNCS = {}, STATES = {}, SETTINGS = { paused = false },
}
_G.SMODS = {
  current_mod = { path = "./", config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end,
  Mods = {}, findModByID = function() return nil end,
}
_G.NFS = setmetatable({}, { __index = function() return function() return nil end end })

local check, done = require("tests.helpers").harness("overlay watchdog")

local HotReload = require("core.hot_reload")

local HOT = { "render.hud_overlay", "hud.cards", "hud.prims", "render.panels.shop" }
for _, name in ipairs(HOT) do require(name) end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local ark_names = {}
for name in pairs(HotReload.ARK) do ark_names[#ark_names + 1] = name end
table.sort(ark_names)

check("ark set is non-empty", #ark_names > 0, #ark_names)

local ark_missing = nil
for _, name in ipairs(ark_names) do
  local rel = HotReload._test.rel_of(name)
  if not exists(rel) then ark_missing = ark_missing or (name .. " -> " .. rel) end
end
check("every ark name maps to a file that exists (a typo silently un-arks a module)",
  ark_missing == nil, ark_missing)

local MUST_ARK = {
  ["core.staging"] = "staged-action queue lives in upvalues",
  ["core.dispatcher"] = "in-flight action cursor lives in upvalues",
  ["core.bridge_init"] = "installs engine/SMODS hooks; a second run double-wraps",
  ["core.crash_guards"] = "wraps engine functions; a second run double-wraps",
  ["core.orchestrator"] = "installs the love.update hook and holds the loop state",
  ["core.config"] = "holds the live settings table other modules pin",
  ["hud.state"] = "animation ark: latches, caches and timers span frames",
  ["core.trace"] = "returns a function, so there is no table to swap in place",
  ["core.force_state"] = "holds the reregister callback core.orchestrator injects once at load",
  ["core.lifecycle_registry"] = "owns the field/hook tables modules register into at their load",
}
for _, name in ipairs({ "core.staging", "core.dispatcher", "core.bridge_init", "core.crash_guards",
                        "core.orchestrator", "core.config", "hud.state", "core.trace",
                        "core.force_state", "core.lifecycle_registry" }) do
  check("arked: " .. name .. " (" .. MUST_ARK[name] .. ")", HotReload._test.is_ark(name) == true)
end

check("core.trace returns a function, so identity-preserving swap is impossible",
  type(require("core.trace")) == "function", type(require("core.trace")))

for _, name in ipairs(HOT) do
  check("NOT arked (hot-reloadable): " .. name, HotReload._test.is_ark(name) == false)
end

check("init() resolves the mod base", HotReload.init() == true, HotReload.base())

local watched = HotReload._test.watched()
local watched_set = {}
for _, name in ipairs(watched) do watched_set[name] = true end

check("watched set is non-trivial", #watched > 20, #watched)

local unwatched = nil
for _, name in ipairs(HOT) do
  if not watched_set[name] then unwatched = unwatched or name end
end
check("watched() contains the loaded render/hud modules", unwatched == nil, unwatched)

local base = HotReload.base()
local phantom = nil
for _, name in ipairs(watched) do
  if not exists(base .. HotReload._test.rel_of(name)) then phantom = phantom or name end
end
check("watched() never contains a name with no backing file", phantom == nil, phantom)

local TmpWork = require("tests.tmp_workdir")
local tmpdir = TmpWork.open("neuro_hotreload")
  .. "_" .. (tostring({}):match("0x(%x+)") or tostring(math.random(1e9)))
os.execute("mkdir -p '" .. tmpdir .. "'")
package.path = tmpdir .. "/?.lua;" .. package.path

local function write(rel, body)
  local f = assert(io.open(tmpdir .. "/" .. rel, "wb"))
  f:write(body)
  f:close()
end

local function mod_a(tag)
  return ([[
local A = {}
A.tag = %q
function A.f() return %q end
A.sub = { g = function() return %q end }
return A
]]):format(tag, tag, tag)
end

write("hrtest_a.lua", mod_a("v1"))
write("hrtest_b.lua", [[
local A = require("hrtest_a")
local pinned_fn = A.f
local pinned_sub = A.sub
local B = {}
function B.via_table() return A.f() end
function B.via_pinned() return pinned_fn() end
function B.via_sub() return pinned_sub.g() end
return B
]])

local alias_src = { "local A = require('hrtest_a')", "local C = {}" }
local ALIASES = 24
for i = 1, ALIASES do
  alias_src[#alias_src + 1] = ("local pin%d = A.f"):format(i)
  alias_src[#alias_src + 1] =
    ("local alias%d = { sub = { call = function() return pin%d() end } }"):format(i, i)
  alias_src[#alias_src + 1] = ("C.deep_%d = { a = { b = { c = alias%d } } }"):format(i, i)
  alias_src[#alias_src + 1] = ("C.shal_%d = alias%d"):format(i, i)
end
alias_src[#alias_src + 1] = "return C"
write("hrtest_c.lua", table.concat(alias_src, "\n") .. "\n")

require("hrtest_a")
local B = require("hrtest_b")
local C = require("hrtest_c")
local a_identity = package.loaded["hrtest_a"]

local function stale_aliases(tag)
  local stale = 0
  for i = 1, ALIASES do
    if C["shal_" .. i].sub.call() ~= tag then stale = stale + 1 end
  end
  return stale
end

local function hot(fn)
  local first, last = fn(), nil
  for _ = 1, 300 do last = fn() end
  if first ~= last then return first .. "(interp)!=" .. last .. "(jit)" end
  return last
end

local function routes()
  return hot(B.via_table) .. "/" .. hot(B.via_pinned) .. "/" .. hot(B.via_sub)
end

HotReload._test.reset()
HotReload._test.set_base(tmpdir)

check("snapshot reload succeeds", HotReload.reload(false) == true, HotReload.status().err)
check("baseline routes all three ways to v1", routes() == "v1/v1/v1", routes())

write("hrtest_a.lua", mod_a("v2"))
check("reload after an edit succeeds", HotReload.reload(false) == true, HotReload.status().err)
check("package.loaded table identity is preserved across the swap",
  package.loaded["hrtest_a"] == a_identity)
check("table-routed call sees the new code", hot(B.via_table) == "v2", hot(B.via_table))
check("the file-scope pinned FUNCTION value sees the new code (upvalue rebinding)",
  hot(B.via_pinned) == "v2", hot(B.via_pinned))
check("the file-scope pinned SUB-TABLE sees the new code (upvalue rebinding)",
  hot(B.via_sub) == "v2", hot(B.via_sub))
check("pins under a table the walk can reach both deep and shallow are all rebound",
  stale_aliases("v2") == 0, stale_aliases("v2") .. "/" .. ALIASES .. " stale")

local real_print = print
local function quiet(fn)
  print = noop
  local ok, res = pcall(fn)
  print = real_print
  if not ok then error(res, 0) end
  return res
end

write("hrtest_a.lua", "local A = {} this is not lua ((( return A\n")
local syntax_ok = quiet(function() return HotReload.reload(false) end)
check("a syntax error is refused", syntax_ok == false, syntax_ok)
check("the compile error is reported as a string", type(HotReload.status().err) == "string",
  type(HotReload.status().err))
check("last-good code still runs after a syntax error", routes() == "v2/v2/v2", routes())

write("hrtest_a.lua", "error('boom at chunk load')\n")
local runtime_ok = quiet(function() return HotReload.reload(false) end)
check("a chunk that errors at load is refused", runtime_ok == false, runtime_ok)
check("the load error is reported as a string", type(HotReload.status().err) == "string",
  type(HotReload.status().err))
check("the partial swap is rolled back to last-good", routes() == "v2/v2/v2", routes())
check("rollback preserves table identity too", package.loaded["hrtest_a"] == a_identity)

write("hrtest_a.lua", mod_a("v3"))
check("reload recovers once the file compiles again", HotReload.reload(false) == true,
  HotReload.status().err)
check("the recovery clears the error", HotReload.status().err == nil, HotReload.status().err)
check("every route sees v3 after recovery", routes() == "v3/v3/v3", routes())

local A = package.loaded["hrtest_a"]
A._hot_reload_locked = function() return true end
write("hrtest_a.lua", mod_a("v4"))
local locked_ok = quiet(function() return HotReload.reload(false) end)
check("a locked module does not make the reload report an error", locked_ok == true,
  HotReload.status().err)
check("a locked module keeps running the old code", routes() == "v3/v3/v3", routes())

A._hot_reload_locked = function() return false end
check("the deferred edit lands on the next reload after unlock, with no further file edit",
  HotReload.reload(false) == true, HotReload.status().err)
check("every route sees v4 once the lock releases", routes() == "v4/v4/v4", routes())
check("the aliased pins follow every later reload too", stale_aliases("v4") == 0,
  stale_aliases("v4") .. "/" .. ALIASES .. " stale")

os.execute("rm -rf '" .. tmpdir .. "'")

local ok_dev, Dev = pcall(require, "hud.dev_scenario")
if ok_dev and type(Dev) == "table" and type(Dev.mount) == "function" then
  check("hud.dev_scenario declares _hot_reload_locked as a function",
    type(rawget(Dev, "_hot_reload_locked")) == "function",
    type(rawget(Dev, "_hot_reload_locked")))
else
  require("tests.skip_ledger").note("overlay-watchdog/dev-scenario-lock", 1,
    "hud.dev_scenario mount/unmount API not present, its lock declaration was not checked")
end

local ok_panel, Panel = pcall(require, "hud.tuning_panel")
if ok_panel and type(Panel) == "table" and type(Panel.toggle) == "function" then
  if Panel.is_open() then Panel.toggle() end
  check("hud.tuning_panel declares a state-aware hot-reload lock",
    type(rawget(Panel, "_hot_reload_locked")) == "function",
    type(rawget(Panel, "_hot_reload_locked")))
  check("the tuning panel permits reload while closed", Panel._hot_reload_locked() == false)
  Panel.toggle()
  check("the tuning panel defers reload while its operator pause is active",
    Panel.is_open() and Panel._hot_reload_locked() == true and G.NEURO.llm_paused == true)
  Panel.toggle()
  check("closing the tuning panel releases both pause and reload lock",
    not Panel.is_open() and Panel._hot_reload_locked() == false and G.NEURO.llm_paused == nil)
else
  check("hud.tuning_panel hot-reload lock is reachable", false, tostring(Panel))
end

TmpWork.close()
done()
