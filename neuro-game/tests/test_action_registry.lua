
local R = require("core.action_registry")
local check, done = require("tests.helpers").harness("action-registry")

R.reset()

check("DYING_GRACE is 10 seconds (NeuroActionHandler.cs WaitForSeconds(10))",
  R.DYING_GRACE == 10, R.DYING_GRACE)

check("start: an empty registry knows no action names",
  R.is_registered("play_hand") == false
    and R.is_recently_unregistered("play_hand", 0) == false
    and next(R.snapshot().registered) == nil)

R.note_registered({ "play_hand", "discard_hand" })
check("note_registered marks names as registered",
  R.is_registered("play_hand") == true and R.is_registered("discard_hand") == true)
check("note_registered exposes registered names in the snapshot",
  next(R.snapshot().registered) ~= nil)
check("note_registered leaves names outside the list unknown",
  R.is_registered("sell_card") == false)
check("note_registered: a newly registered action is not in the grace period",
  R.is_recently_unregistered("play_hand", 100) == false)

R.note_unregistered({ "play_hand" }, 100)
check("note_unregistered removes registration from the name",
  R.is_registered("play_hand") == false)
check("note_unregistered leaves untouched names registered",
  R.is_registered("discard_hand") == true)
check("note_unregistered moves the name into the dying set",
  R.is_recently_unregistered("play_hand", 100) == true)

check("the grace period remains active just before 10 seconds",
  R.is_recently_unregistered("play_hand", 109.9) == true)
check("the grace period expires exactly at 10 seconds",
  R.is_recently_unregistered("play_hand", 110) == false)
check("the withdrawal itself outlives the grace",
  R.is_withdrawn("play_hand") == true and R.snapshot().withdrawn.play_hand == true)
check("a name never withdrawn is not remembered as withdrawn",
  R.is_withdrawn("discard_hand") == false and R.is_withdrawn("sell_card") == false)
R.note_registered({ "play_hand" })
check("re-registering forgets the withdrawal",
  R.is_withdrawn("play_hand") == false)
R.note_unregistered({ "play_hand" }, 100)

R.reset()
R.note_registered({ "play_hand" })
R.note_unregistered({ "play_hand" }, 200)
check("the grace period is measured per name from withdrawal time",
  R.is_recently_unregistered("play_hand", 209) == true
    and R.is_recently_unregistered("play_hand", 211) == false)

R.reset()
R.note_registered({ "play_hand", "discard_hand" })
R.note_unregistered({ "play_hand" }, 300)
R.note_unregistered({ "discard_hand" }, 306)
check("two names have independent grace-period stamps",
  R.is_recently_unregistered("play_hand", 308) == true
    and R.is_recently_unregistered("discard_hand", 308) == true)
check("an older grace period expires while a newer one remains active",
  R.is_recently_unregistered("play_hand", 311) == false
    and R.is_recently_unregistered("discard_hand", 311) == true)

R.reset()
R.note_registered({ "play_hand" })
R.note_unregistered({ "play_hand" }, 400)
R.note_registered({ "play_hand" })
check("re-registration clears the grace period (_dyingActions.RemoveAll)",
  R.is_recently_unregistered("play_hand", 401) == false)
check("re-registration: the action name is registered again",
  R.is_registered("play_hand") == true)

R.reset()
R.note_registered({ "play_hand", "sell_card" })
R.note_unregistered({ "play_hand" }, 500)
local snap = R.snapshot()
check("snapshot separates registered names from dying names",
  snap.registered.sell_card == true and snap.registered.play_hand == nil
    and snap.dying.play_hand == 500 and snap.dying.sell_card == nil)
snap.registered.injected = true
snap.dying.play_hand = 1
check("snapshot: mutating the copy does not affect the registry",
  R.is_registered("injected") == false
    and R.snapshot().dying.play_hand == 500)

check("prune: nothing is removed before the grace period expires",
  (function()
    R.prune(505)
    return R.snapshot().dying.play_hand == 500
  end)())
check("prune removes an entry after its grace period",
  (function()
    R.prune(510)
    return R.snapshot().dying.play_hand == nil
  end)())

R.reset()
R.note_registered({ "play_hand" })
R.note_unregistered({ "discard_hand" }, 600)
R.reset()
check("reset clears registered and dying names",
  R.is_registered("play_hand") == false
    and R.is_recently_unregistered("discard_hand", 601) == false
    and next(R.snapshot().registered) == nil)
check("reset: the post-reset snapshot is empty",
  next(R.snapshot().registered) == nil and next(R.snapshot().dying) == nil)

check("note_registered accepts one name as a string",
  (function()
    R.reset()
    R.note_registered("play_hand")
    return R.is_registered("play_hand") == true
  end)())
check("note_unregistered accepts one name as a string",
  (function()
    R.note_unregistered("play_hand", 700)
    return R.is_registered("play_hand") == false
      and R.is_recently_unregistered("play_hand", 701) == true
  end)())

R.reset()

check("Registry.now exists and returns a number",
  type(R.now) == "function" and type(R.now()) == "number")

do
  local saved_love = _G.love
  local love_clk = 100.0
  _G.love = { timer = { getTime = function() return love_clk end } }

  R.reset()
  R.note_registered({ "play_hand" })
  R.note_unregistered({ "play_hand" }) -- without passing now -> uses R.now()

  check("note_unregistered uses R.now() when time is omitted",
    R.snapshot().dying.play_hand == 100.0)

  love_clk = 105.0
  check("is_recently_unregistered uses the default clock during grace (5s)",
    R.is_recently_unregistered("play_hand") == true)

  love_clk = 111.0
  check("is_recently_unregistered uses the default clock after grace (11s)",
    R.is_recently_unregistered("play_hand") == false)

  local saved_G = _G.G
  local Dispatcher = require("core.dispatcher")
  _G.G = {
    NEURO = { dispatcher = Dispatcher, actions = require("core.actions"), run_generation = 1, state = "SELECTING_HAND" },
    FUNCS = {}, GAME = { current_round = { hands_left = 4, discards_left = 3 } },
    STATES = { SELECTING_HAND = 4 }, STATE = 4,
    TIMERS = { REAL = 17.0 }, -- REAL = 17 when love = 5 (fixed offset after entering menu)
    hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
  }

  local results = {}
  local bridge = {
    send_action_result = function(_, id, ok, msg, reason)
      results[#results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
    end,
    send_context = function() return true end,
    unregister_actions = function() end,
  }

  love_clk = 5.0
  G.TIMERS.REAL = 17.0
  R.reset()
  R.note_unregistered({ "play_hand" }, love_clk)

  love_clk = 6.0 -- 1 s elapsed in real time
  G.TIMERS.REAL = 18.0
  results = {}
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "desync-1", name = "play_hand", data = '{"indices":[1]}' } }, bridge)

  check("clock divergence: an action unregistered one second ago returns ACTION_UNREGISTERED despite REAL > DYING_GRACE",
    results[1] and results[1].ok == true and results[1].reason == "ACTION_UNREGISTERED",
    results[1] and tostring(results[1].reason))
  check("a withdrawal inside the grace is reported as recent",
    results[1] and results[1].msg:find("withdrawn moments ago", 1, true) ~= nil,
    results[1] and tostring(results[1].msg))

  love_clk = 100.0
  G.TIMERS.REAL = 12.0
  R.reset()
  R.note_unregistered({ "play_hand" }, love_clk)

  love_clk = 130.0 -- 30 s elapsed in real time
  G.TIMERS.REAL = 13.0 -- in-game only 1 s elapsed
  results = {}
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "desync-2", name = "play_hand", data = '{"indices":[1]}' } }, bridge)

  check("an action withdrawn 30 s ago keeps ACTION_UNREGISTERED past DYING_GRACE",
    results[1] and results[1].ok == true and results[1].reason == "ACTION_UNREGISTERED",
    results[1] and tostring(results[1].reason))
  check("and says it was withdrawn, without claiming the withdrawal was recent",
    results[1] and results[1].msg:find("was withdrawn", 1, true) ~= nil
      and results[1].msg:find("moments ago", 1, true) == nil,
    results[1] and tostring(results[1].msg))
  check("the withdrawn action is terminally acknowledged so its dead force is not retried (SPECIFICATION.md:184-188)",
    results[1] and results[1].ok == true, results[1] and tostring(results[1].ok))

  results = {}
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "desync-3", name = "no_such_action_at_all", data = "{}" } }, bridge)
  check("a name the game never had is still ACTION_UNKNOWN",
    results[1] and results[1].reason == "ACTION_UNKNOWN",
    results[1] and tostring(results[1].reason))

  love_clk = 200.0
  G.TIMERS.REAL = 50.0
  R.reset()
  R.note_unregistered({ "play_hand" }, love_clk)

  G.TIMERS.REAL = 0.0 -- run reset
  love_clk = 205.0 -- 5 s elapsed
  check("after resetting TIMERS.REAL the grace period remains active at 5s",
    R.is_recently_unregistered("play_hand") == true)

  love_clk = 211.0 -- 11 s elapsed
  check("after resetting TIMERS.REAL the grace period expires at 11s",
    R.is_recently_unregistered("play_hand") == false)

  _G.love = saved_love
  _G.G = saved_G
end

do
  local saved_love = _G.love
  _G.love = nil

  R.reset()
  local t0 = os.time()
  R.note_unregistered({ "play_hand" })
  local stamp = R.snapshot().dying.play_hand
  check("without love the fallback stamps os.time wall time",
    type(stamp) == "number" and stamp >= t0 and stamp <= os.time())

  check("without love the fallback reads the same wall clock and grace starts immediately",
    R.is_recently_unregistered("play_hand", os.time()) == true)

  R.reset()
  R.note_unregistered({ "play_hand" }) -- now == nil
  check("note_unregistered(now=nil) stamps the current R.now() time",
    R.snapshot().dying.play_hand ~= nil and R.snapshot().dying.play_hand >= t0)

  check("is_recently_unregistered(now=nil) compares against R.now()",
    R.is_recently_unregistered("play_hand") == true)

  R.prune() -- now == nil
  check("prune(now=nil) preserves a fresh entry",
    R.snapshot().dying.play_hand ~= nil)

  R.reset()
  R.note_unregistered({ "play_hand" }, os.time() - (R.DYING_GRACE + 10))
  R.prune() -- now == nil
  check("prune(now=nil) removes an old entry by consulting the clock",
    R.snapshot().dying.play_hand == nil)

  _G.love = saved_love
end

R.reset()

do
  local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*all")
    f:close()
    return text
  end

  local RUNTIME_DIRS = { "core", "force", "util", "handlers", "hud", "render", "facts", "context" }
  local files = {}
  do
    local pipe = assert(io.popen("find " .. table.concat(RUNTIME_DIRS, " ") .. " -name '*.lua' | sort", "r"))
    for line in pipe:lines() do files[#files + 1] = line end
    pipe:close()
  end
  check("ownership: the scan actually reaches the runtime tree",
    #files > 50 and read("core/bridge.lua") ~= nil, #files)

  local function call_sites(pattern)
    local found = {}
    for _, path in ipairs(files) do
      local src = (read(path) or ""):gsub("function%s+[%w_%.:]+", " ")
      if src:find(pattern) then found[#found + 1] = path end
    end
    table.sort(found)
    return found
  end

  local register_sites = call_sites("[:%.]register_actions%s*%(")
  local sees_orchestrator = false
  for _, path in ipairs(register_sites) do
    if path == "core/orchestrator.lua" then sees_orchestrator = true end
  end
  check("ownership: the scan still sees a real call site after stripping definitions",
    sees_orchestrator, table.concat(register_sites, ","))

  local reset_callers = call_sites("[:%.]reset_tx")
  check("ownership: reset_tx -- the only way to clear the registry -- has exactly one caller",
    #reset_callers == 1 and reset_callers[1] == "core/bridge.lua", table.concat(reset_callers, ","))

  local retract_callers = call_sites("[:%.]unregister_actions%s*%(")
  check("ownership: no runtime file dictates a retraction by name",
    #retract_callers == 0, table.concat(retract_callers, ","))

  local sweep_callers = call_sites("[:%.]unregister_all%s*%(")
  check("ownership: unregister_all is only ever called from the shutdown path",
    #sweep_callers == 1 and sweep_callers[1] == "core/bridge_init.lua",
    table.concat(sweep_callers, ","))

  local init = read("core/bridge_init.lua") or ""
  local startup_at = init:find("send_startup()", 1, true)
  local register_at = init:find("_register_valid_actions(state_name)", 1, true)
  check("ownership: bridge_init rebuilds the registration after send_startup",
    startup_at ~= nil and register_at ~= nil and register_at > startup_at,
    tostring(startup_at) .. "/" .. tostring(register_at))
  check("ownership: setup_neuro_bridge is idempotent only after initialization completes",
    init:find("G.NEURO._bridge_init_complete", 1, true) ~= nil)
end

done()
