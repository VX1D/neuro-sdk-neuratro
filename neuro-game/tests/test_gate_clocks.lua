_G.NEURO_TEST = true

local wall = 0
love = { timer = { getTime = function() return wall end } }

local STATES = { SHOP = 5, BLIND_SELECT = 1 }
_G.G = {
  NEURO = {}, FUNCS = {}, GAME = { dollars = 20, current_round = {}, STOP_USE = 0 },
  TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
  STATES = STATES, STATE = STATES.SHOP,
  CONTROLLER = { locks = {} }, E_MANAGER = { queues = {} },
  shop_jokers = { cards = {}, config = { card_limit = 4 } },
}
_G.SMODS = { Mods = {} }

local check, done = require("tests.helpers").harness("gate-clocks")
local GateClocks = require("core.gate_clocks")
local Utils = require("util.utils")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local SPEEDS = { 0.5, 1, 2, 4 }
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end

-- The dump's own rule: REAL takes dt, TOTAL takes dt*SPEEDFACTOR (game.lua:2588 and 2622).
local function reset_world(gamespeed)
  G.SETTINGS.GAMESPEED = gamespeed
  G.SPEEDFACTOR = gamespeed
  G.TIMERS.REAL, G.TIMERS.TOTAL = 0, 0
end

local function advance(seconds, dt)
  dt = dt or 1 / 240
  local target = G.TIMERS.REAL + seconds
  while G.TIMERS.REAL < target - 1e-12 do
    local step = math.min(dt, target - G.TIMERS.REAL)
    G.TIMERS.REAL = G.TIMERS.REAL + step
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + step * G.SPEEDFACTOR
    wall = wall + step
    Utils.observe_clock()
  end
end

do
  local Lint = require("scripts.gate_clock_check")
  local findings = Lint.run(GateClocks, require("core.config_schema"))
  local detail = {}
  for _, f in ipairs(findings) do detail[#detail + 1] = f.rule .. " @ " .. f.where end
  check("the gate-clock lint is clean", #findings == 0, table.concat(detail, "; "))
end

do
  local Lint = require("scripts.gate_clock_check")
  local Schema = require("core.config_schema")

  local function source_of(path)
    local fh = assert(io.open(path, "r"))
    local src = fh:read("*all")
    fh:close()
    return src
  end

  local function planted(label, path, mutate, want_rule, want_where)
    want_where = want_where or path
    local src = mutate(source_of(path))
    local findings = Lint.run(GateClocks, Schema, { [path] = src })
    local hit, seen = false, {}
    for _, f in ipairs(findings) do
      seen[#seen + 1] = f.rule .. "@" .. f.where
      if f.rule == want_rule and f.where:sub(1, #want_where) == want_where then hit = true end
    end
    check(label .. " is caught by " .. want_rule, hit, table.concat(seen, ","))
  end

  local ENFORCE, FORCE_STATE = "core/enforce.lua", "core/force_state.lua"

  planted("substituting the raw TOTAL reader for a TOTAL gate's accessor", ENFORCE, function(src)
    return (src:gsub('Utils%.gate_now%("enforce_global_cooldown"%)', "Utils.game_now()"))
  end, "raw-clock-bypass")

  planted("aliasing G.TIMERS and reading TOTAL off the alias", ENFORCE, function(src)
    return src .. "\nlocal _T = G.TIMERS\nlocal _stolen = _T.TOTAL\n"
  end, "raw-game-clock")

  planted("rawget on G.TIMERS", ENFORCE, function(src)
    return src .. "\nlocal _stolen = rawget(G.TIMERS, \"TOTAL\")\n"
  end, "raw-game-clock")

  planted("a computed key on G.TIMERS", ENFORCE, function(src)
    return src .. "\nlocal _k = \"TOT\" .. \"AL\"\nlocal _stolen = G.TIMERS[_k]\n"
  end, "raw-game-clock")

  local function m4(src)
    return (src:gsub('Utils%.gate_now%("ack_idle_reask"%)', "(G.TIMERS.REAL)"))
  end
  planted("reading REAL raw in place of a REAL gate's accessor", FORCE_STATE, m4, "raw-game-clock")
  planted("the same read with a bare mention of the gate id left behind", FORCE_STATE, function(src)
    return m4(src) .. "\nlocal _doc = \"ack_idle_reask\"\n"
  end, "raw-game-clock")

  planted("a gate id that is mentioned but never routed", FORCE_STATE, function(src)
    src = src:gsub('Utils%.gate_now%("ack_idle_reask"%)', "Utils.now()")
    src = src:gsub('tuned%("ack_idle_reask"', 'metric("ack_idle_reask"')
    return src .. "\nlocal _doc = \"ack_idle_reask\"\n"
  end, "unwired-gate", "ack_idle_reask")

  do
    local findings = Lint.run(GateClocks, Schema)
    local unwired = {}
    for _, f in ipairs(findings) do
      if f.rule == "unwired-gate" then unwired[#unwired + 1] = f.where end
    end
    check("a gate id handed to a local forwarder still counts as routed",
      #unwired == 0, table.concat(unwired, ","))
  end
end

do
  local ok = true
  for _, gate in ipairs(GateClocks.gates) do
    if type(gate.why) ~= "string" or gate.why == "" then ok = false end
    if gate.clock ~= "REAL" and gate.clock ~= "TOTAL" and gate.clock ~= "WALL" then ok = false end
    if type(gate.file) ~= "string" then ok = false end
  end
  check("every gate carries a clock, a file and a reason", ok)
end

do
  local EXPECTED_UNWIRED = {}
  local unexpected, missing = {}, {}
  local seen = {}
  for _, gate in ipairs(GateClocks.gates) do
    if gate.wired ~= true then
      seen[gate.id] = true
      if not EXPECTED_UNWIRED[gate.id] then unexpected[#unexpected + 1] = gate.id end
    end
  end
  for id in pairs(EXPECTED_UNWIRED) do
    if not seen[id] then missing[#missing + 1] = id end
  end
  check("the unwired gate set is exactly the pinned list",
    #unexpected == 0 and #missing == 0,
    "unexpected: " .. table.concat(unexpected, ",") .. " missing: " .. table.concat(missing, ","))
end

do
  local Lint = require("scripts.gate_clock_check")
  local RULES = {
    { pattern = "[%w_]*wall_at%s*=%s*Utils%.now%f[%W]", why = "named wall, minted from REAL" },
    { pattern = "[%w_]*wall_at%s*=%s*Utils%.gate_now%f[%W]", why = "named wall, minted from a gate" },
    { pattern = "[%w_]*real_at%s*=%s*Utils%.wall_now%f[%W]", why = "named real, minted from WALL" },
    { pattern = "[%w_]*game_at%s*=%s*Utils%.now%f[%W]", why = "named game, minted from REAL" },
  }
  local function scan(path, src)
    local hits = {}
    for _, rule in ipairs(RULES) do
      if src:find(rule.pattern) then hits[#hits + 1] = path .. ": " .. rule.why end
    end
    return hits
  end
  local offenders = {}
  for _, path in ipairs(Lint.source_files()) do
    local fh = io.open(path, "r")
    local src = fh and fh:read("*all") or ""
    if fh then fh:close() end
    for _, hit in ipairs(scan(path, src)) do offenders[#offenders + 1] = hit end
  end
  check("no stamp is named for a clock other than the one that mints it",
    #offenders == 0, table.concat(offenders, ", "))
  check("the clock-name scan is not vacuous",
    #scan("<planted>", "G.NEURO.last_action_wall_at = Utils.now()\n") == 1)
  check("the obsolete clock field is gone",
    (function()
      local fh = io.open("core/neuro_lifecycle.lua", "r")
      local src = fh and fh:read("*all") or ""
      if fh then fh:close() end
      return src:find("last_action_wall_at") == nil
        and src:find("last_action_real_at%s*=%s*Utils%.now") ~= nil
    end)())
end

do
  local function engine(opts)
    local ACC, ACC_state, TOTAL, REAL, peak = 0, nil, 0, 0, 0
    local dt_smooth = 1 / 60
    local frames = math.floor(opts.wall_seconds / dt_smooth)
    for _ = 1, frames do
      local dt = dt_smooth
      REAL = REAL + dt
      if opts.paused then dt = 0 end
      if opts.state ~= ACC_state then ACC = 0 end
      ACC_state = opts.state
      if opts.state == "HAND_PLAYED" or opts.state == "NEW_ROUND" then
        ACC = math.min(ACC + dt * 0.2 * opts.gamespeed, 16)
      else
        ACC = 0
      end
      local spd = (opts.stage_run ~= false and not opts.paused and not opts.screenwipe)
        and opts.gamespeed or 1
      spd = spd + math.max(0, math.abs(ACC) - 2)
      if spd > peak then peak = spd end
      TOTAL = TOTAL + dt * spd
    end
    return REAL, TOTAL, peak
  end

  local real, total, peak = engine({ gamespeed = 4, wall_seconds = 20, state = "HAND_PLAYED" })
  check("twenty wall-seconds of scoring at GAMESPEED 4 runs TOTAL at about 10x, not 4x",
    total / real > 9.5 and total / real < 11, total / real)
  check("the boost tops SPEEDFACTOR out at GAMESPEED + 14", near(peak, 18, 1e-9), peak)

  local _, t1, p1 = engine({ gamespeed = 4, wall_seconds = 5, state = "HAND_PLAYED" })
  check("five wall-seconds already overshoots GAMESPEED", t1 / 5 > 4.2, t1 / 5)
  check("a model that equates SPEEDFACTOR with GAMESPEED cannot produce the peak", p1 > 4, p1)

  local r2, t2, p2 = engine({ gamespeed = 4, wall_seconds = 5, state = "SHOP", stage_run = false })
  check("off the run stage SPEEDFACTOR is 1 whatever GAMESPEED says",
    near(p2, 1, 1e-9) and near(t2, r2, 1e-9), p2 .. " " .. t2 .. " vs " .. r2)

  local r3, t3 = engine({ gamespeed = 4, wall_seconds = 5, state = "SHOP", screenwipe = true })
  check("SPEEDFACTOR stays 1 during a screen wipe", near(t3, r3, 1e-9), t3 .. " vs " .. r3)

end

do
  local Staging = require("core.staging")
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    advance(3)
    check("the glow instant matches the glow_window clock at gamespeed " .. gs,
      near(Staging.glow_now(), Utils.gate_now("glow_window"), 1e-9),
      Staging.glow_now() .. " vs " .. Utils.gate_now("glow_window"))
  end
  reset_world(4)
  advance(3)
  local was = GateClocks.by_id.glow_window.clock
  GateClocks.by_id.glow_window.clock = "TOTAL"
  local moved = near(Staging.glow_now(), G.TIMERS.TOTAL, 1e-9)
  GateClocks.by_id.glow_window.clock = was
  check("the glow instant follows the assignment rather than a hardcoded clock", moved,
    Staging.glow_now() .. " vs " .. G.TIMERS.TOTAL)
  local cards_src = (function()
    local fh = io.open("hud/cards.lua", "r")
    local src = fh and fh:read("*all") or ""
    if fh then fh:close() end
    return src
  end)()
  check("hud/cards.lua takes the glow instant from the module that stamps it",
    cards_src:find("_Staging%.glow_now%(%)") ~= nil)
  check("the glow ramp itself reads no clock of its own",
    cards_src:find("local now = glow_now%(%)") ~= nil)
  reset_world(1)
end

do
  local Lint = require("scripts.gate_clock_check")
  local TOTAL_STAMPS = { "force_dirty_at", "last_action_at", "last_failed_at" }
  local function scan(path, src)
    local readers = { ["Utils%.now"] = true, ["Utils%.wall_now"] = true }
    for name in src:gmatch("local%s+([%w_]+)%s*=%s*Utils%.now%f[%W]") do readers[name] = true end
    for name in src:gmatch("local%s+([%w_]+)%s*=%s*Utils%.wall_now%f[%W]") do readers[name] = true end
    local hits = {}
    for reader in pairs(readers) do
      for _, field in ipairs(TOTAL_STAMPS) do
        if src:find(reader .. "%s*%(%s*%)%s*%-%s*[%w_%.]*" .. field .. "%f[%W]")
          or src:find(field .. "%s*[<>=~]=?%s*" .. reader .. "%s*%(%s*%)") then
          hits[#hits + 1] = path .. ":" .. field
        end
      end
    end
    return hits
  end
  local offenders = {}
  for _, path in ipairs(Lint.source_files()) do
    local fh = io.open(path, "r")
    local src = fh and fh:read("*all") or ""
    if fh then fh:close() end
    for _, hit in ipairs(scan(path, src)) do offenders[#offenders + 1] = hit end
  end
  check("no game-clock stamp is compared against a real-time reader",
    #offenders == 0, table.concat(offenders, ", "))
  local _, planted = nil, scan("<planted>",
    "local game_now = Utils.now\nlocal age = game_now() - n.force_dirty_at\n")
  check("the cross-clock comparison scan is not vacuous", #planted == 1, #planted)
end

for _, gs in ipairs(SPEEDS) do
  reset_world(gs)
  advance(4)
  local diverged = not near(G.TIMERS.REAL, G.TIMERS.TOTAL, 1e-6)
  if gs == 1 then
    check("at gamespeed 1 the two clocks are the same number, so every assignment is a no-op",
      near(G.TIMERS.REAL, G.TIMERS.TOTAL, 1e-9),
      G.TIMERS.REAL .. " vs " .. G.TIMERS.TOTAL)
  else
    check("at gamespeed " .. gs .. " the two clocks have actually diverged", diverged,
      G.TIMERS.REAL .. " vs " .. G.TIMERS.TOTAL)
  end

  local wrong = {}
  for _, gate in ipairs(GateClocks.gates) do
    local want = G.TIMERS.REAL
    if gate.clock == "TOTAL" then want = G.TIMERS.TOTAL
    elseif gate.clock == "WALL" then want = love.timer.getTime() end
    if not near(Utils.gate_now(gate.id), want, 1e-9) then wrong[#wrong + 1] = gate.id end
  end
  check("every gate reads the clock the table assigns it at gamespeed " .. gs,
    #wrong == 0, table.concat(wrong, ","))
end

do
  local Guard = require("core.transition_guard")
  local failsafe = Config.get("NEURO_ENGINE_GATE_FAILSAFE")
  local released = {}
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    Guard.reset()
    G.GAME.STOP_USE = 1
    local at = nil
    for _ = 1, 20000 do
      if Guard.engine_ready() then at = G.TIMERS.REAL break end
      advance(1 / 120, 1 / 120)
    end
    released[gs] = at
    check("the engine gate releases after failsafe/gamespeed wall seconds at gamespeed " .. gs,
      at ~= nil and near(at, failsafe / gs, 0.05), at)
  end
  G.GAME.STOP_USE = 0
  check("at gamespeed 1 the engine gate still releases at exactly the configured failsafe",
    released[1] ~= nil and near(released[1], failsafe, 0.05), released[1])
  check("a slow game no longer trips the failsafe mid-animation",
    released[0.5] ~= nil and released[0.5] > released[1] * 1.9, released[0.5])
  check("a fast game no longer waits the full wall-clock failsafe",
    released[4] ~= nil and released[4] < released[1] * 0.3, released[4])
end

do
  local Guard = require("core.transition_guard")
  local LATCH_CASH_OUT = 1.0
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    Guard.reset()
    Guard.mark("cash_out")
    check("the settling latch is still closed just before it expires at gamespeed " .. gs,
      Guard.reject_reason("cash_out") ~= nil)
    advance(LATCH_CASH_OUT / gs - 0.02)
    local still_closed = Guard.reject_reason("cash_out") ~= nil
    advance(0.04)
    check("the settling latch opens after latch/gamespeed wall seconds at gamespeed " .. gs,
      still_closed and Guard.reject_reason("cash_out") == nil)
  end
end

do
  reset_world(1)
  advance(20)
  local wall_before = Utils.gate_now("result_deadline")
  local real_before = Utils.gate_now("login_anim_block")
  local total_before = Utils.gate_now("state_cooldown")
  G.TIMERS.REAL, G.TIMERS.TOTAL = 0, 0
  check("a run reset rewinds the REAL gates", Utils.gate_now("login_anim_block") < real_before,
    Utils.gate_now("login_anim_block") .. " vs " .. real_before)
  check("a run reset rewinds the TOTAL gates", Utils.gate_now("state_cooldown") < total_before)
  check("a run reset never rewinds a WALL gate",
    Utils.gate_now("result_deadline") >= wall_before,
    Utils.gate_now("result_deadline") .. " vs " .. wall_before)
  local WALL_GATES = { "action_dying_grace", "inbox_poll", "result_deadline",
    "bridge_transition_cooldown" }
  local rewound = {}
  for _, id in ipairs(WALL_GATES) do
    if Utils.gate_now(id) < wall_before then rewound[#rewound + 1] = id end
  end
  check("every gate the table calls WALL survives the reset", #rewound == 0,
    table.concat(rewound, ","))
  local stamped = wall_before
  advance(5)
  check("a grace stamped before a run reset still measures its own length on WALL",
    near(Utils.gate_now("action_dying_grace") - stamped, 5, 1e-6),
    Utils.gate_now("action_dying_grace") - stamped)
  reset_world(1)
end

do
  local lives = {}
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    local start = Utils.gate_now("login_anim_block")
    local window = Config.get("NEURO_LOGIN_ANIM_BLOCK")
    local at = nil
    for _ = 1, 20000 do
      if (Utils.gate_now("login_anim_block") - start) >= window then at = G.TIMERS.REAL break end
      advance(1 / 120, 1 / 120)
    end
    lives[#lives + 1] = at
    check("the login-animation block lasts the same wall time at gamespeed " .. gs,
      at ~= nil and near(at, window, 0.05), at)
  end
  check("the wire-facing gate is identical at every gamespeed",
    near(lives[1], lives[4], 0.05) and near(lives[2], lives[3], 0.05),
    table.concat({ tostring(lives[1]), tostring(lives[2]),
      tostring(lives[3]), tostring(lives[4]) }, " "))
end

do
  local STREAM_CD_FACTOR = { [0.5] = 2.0, [1] = 1.0, [2] = 0.7, [4] = 0.5 }
  local KEY = "NEURO_STATE_COOLDOWN"
  local raw = Config.get_raw(KEY)
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    local scaled = Config.get(KEY)
    local gate = Utils.gate_seconds("state_cooldown", KEY)
    check("Config.get still carries the streaming factor at gamespeed " .. gs,
      near(scaled, raw * STREAM_CD_FACTOR[gs], 1e-9), scaled)
    check("the game-clock gate reads the knob without the streaming factor at gamespeed " .. gs,
      near(gate, raw, 1e-9), gate)
    if gs == 1 then
      check("at gamespeed 1 the gate value is exactly what Config.get returns",
        near(gate, scaled, 1e-9), gate .. " vs " .. scaled)
    else
      check("off gamespeed 1 the factor would have been counted twice at gamespeed " .. gs,
        not near(gate, scaled, 1e-9), gate .. " vs " .. scaled)
    end
  end
  reset_world(0.5)
  check("a wall-clock gate keeps the value Config.get hands it",
    near(Utils.gate_seconds("staging_commit", "NEURO_SHOP_BUY_DELAY"),
      Config.get("NEURO_SHOP_BUY_DELAY"), 1e-9))
  reset_world(1)
end

do
  local Orch = require("core.orchestrator")
  local HudState = require("hud.state")
  local ENTRY_RAW = Config.get_raw("NEURO_ENTRY_CD_SHOP")
  for _, gs in ipairs({ 0.5, 2, 4 }) do
    reset_world(gs)
    G.NEURO.state = "SHOP"
    G.NEURO.last_action_at = nil
    G.NEURO.reserved_dollars = 0
    HudState.state_changed_at_game = Utils.gate_now("state_cooldown")
    local waited = nil
    for _ = 1, 40000 do
      if Orch._neuro_can_act() then waited = G.TIMERS.TOTAL break end
      advance(1 / 120, 1 / 120)
    end
    check("the shop entry gate waits the raw knob in game seconds at gamespeed " .. gs,
      waited ~= nil and near(waited, ENTRY_RAW, 0.05), waited)
  end
  reset_world(0.5)
  advance(10)
  G.NEURO.state = "BLIND_SELECT"
  HudState.state_changed_at_game = nil
  HudState.state_changed_at = G.TIMERS.REAL
  check("the state-cooldown gate never falls back to the wall-clock HUD stamp",
    Orch._neuro_can_act() == true, G.TIMERS.TOTAL - HudState.state_changed_at)

  reset_world(1)
  G.NEURO.state = nil
  HudState.state_changed_at_game = nil
  HudState.state_changed_at = 0
end

do
  local Lifecycle = require("core.neuro_lifecycle")
  local Receipt = require("core.action_receipt")
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    advance(3)
    G.NEURO = {}
    Lifecycle.mark_action_at()
    check("the action stamp the cooldown reads is on the game clock at gamespeed " .. gs,
      near(G.NEURO.last_action_at, G.TIMERS.TOTAL, 1e-9),
      G.NEURO.last_action_at .. " vs " .. G.TIMERS.TOTAL)
    check("the action stamp's wall twin stays on real time at gamespeed " .. gs,
      near(G.NEURO.last_action_real_at, G.TIMERS.REAL, 1e-9),
      G.NEURO.last_action_real_at .. " vs " .. G.TIMERS.REAL)

    Lifecycle.mark_force_dirty()
    check("the force-debounce stamp is on the game clock at gamespeed " .. gs,
      near(G.NEURO.force_dirty_at, G.TIMERS.TOTAL, 1e-9),
      G.NEURO.force_dirty_at .. " vs " .. G.TIMERS.TOTAL)

    Lifecycle.record_failure("play_hand", "action did not apply")
    check("the failure stamp uses the clock of its defer window at gamespeed " .. gs,
      near(G.NEURO.last_failed_at, Utils.gate_now("failure_defer_window"), 1e-9),
      G.NEURO.last_failed_at .. " vs " .. Utils.gate_now("failure_defer_window"))

    Receipt.reset("gate-clocks")
    local receipt = Receipt.create({ id = "gc-" .. gs, name = "buy_from_shop",
      deadline = Receipt.now() + 1, timeout_outcome = "failed",
      probe = function() return "pending" end })
    check("the receipt deadline uses the clock update compares at gamespeed " .. gs,
      near(receipt.started_at, G.TIMERS.TOTAL, 1e-9) and near(receipt.deadline, G.TIMERS.TOTAL + 1, 1e-9),
      receipt.started_at .. "/" .. receipt.deadline .. " vs " .. G.TIMERS.TOTAL)
    Receipt.transition(receipt, "acknowledged")
    Receipt.transition(receipt, "executing")
    Receipt.transition(receipt, "verifying")
    advance(1 / gs + 0.05)
    check("the receipt times out after deadline/gamespeed wall seconds at gamespeed " .. gs,
      #Receipt.update(Receipt.now(), nil) == 1)
    Receipt.reset("gate-clocks")
  end
  reset_world(1)
end

do
  local Dispatcher = require("core.dispatcher")
  local Receipt = require("core.action_receipt")
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    advance(2)
    G.NEURO = { state = "SHOP" }
    local bridge = { send_context = function() return true end,
      send_action_result = function() end, register_actions = function() end }
    Dispatcher._test.execute_action({ id = "gc-lat-" .. gs, name = "sell_card",
      exec = function() return Receipt.outcome("applied", "done") end, bridge = bridge }, bridge)
    check("the dispatcher stamps the action on the game clock at gamespeed " .. gs,
      near(G.NEURO.last_action_at or -1, G.TIMERS.TOTAL, 1e-6),
      tostring(G.NEURO.last_action_at) .. " vs " .. G.TIMERS.TOTAL)
    check("the dispatcher stamps the wall twin on real time at gamespeed " .. gs,
      near(G.NEURO.last_action_real_at or -1, G.TIMERS.REAL, 1e-6),
      tostring(G.NEURO.last_action_real_at) .. " vs " .. G.TIMERS.REAL)
  end
  reset_world(1)
end

do
  local Dispatcher = require("core.dispatcher")
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    advance(2)
    G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
    G.shop_jokers.cards = { { cost = 5, highlighted = false,
      ability = { name = "Joker", set = "Joker" },
      config = { center = { key = "j_joker", set = "Joker" } },
      juice_up = function() end } }
    G.FUNCS.buy_from_shop = function() end
    local handler = Dispatcher.get_action_handler("buy_from_shop")
    local exec = handler and handler({ area = "shop_jokers", index = 1, _action_id = "gc-rec-" .. gs })
    local receipt = type(exec) == "function" and exec() or nil
    local want = math.max(3, Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_DELAY")
      + Utils.gate_seconds("shop_buy_watchdog_grace", "NEURO_SHOP_BUY_WATCHDOG_GRACE") + 1)
    check("the handler stamps the receipt deadline on the game clock at gamespeed " .. gs,
      receipt ~= nil and near(receipt.deadline - G.TIMERS.TOTAL, want, 1e-6),
      receipt and (receipt.deadline - G.TIMERS.TOTAL) or "no receipt")
  end
  reset_world(1)
end

do
  local Lint = require("scripts.gate_clock_check")
  local offenders = {}
  for _, path in ipairs(Lint.source_files()) do
    local fh = io.open(path, "r")
    local src = fh and fh:read("*all") or ""
    if fh then fh:close() end
    if src:find("deadline%s*=%s*Utils%.now") then offenders[#offenders + 1] = path .. ":deadline" end
    if path ~= "core/neuro_lifecycle.lua" and src:find("last_action_at%s*=") then
      offenders[#offenders + 1] = path .. ":last_action_at"
    end
  end
  check("no file outside the stamp owner mints it from the wall clock",
    #offenders == 0, table.concat(offenders, ", "))
end

do
  local Enforce = require("core.enforce")
  local released = {}
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    G.NEURO = { state = "SHOP" }
    Enforce.reset_run_state()
    local throttle = Utils.gate_seconds("enforce_state_throttle", "NEURO_GLOBAL_THROTTLE_SHOP")
    local at
    for _ = 1, 40000 do
      if Enforce.pre_action(nil, "buy_from_shop", {}) then at = G.TIMERS.REAL break end
      advance(1 / 120, 1 / 120)
    end
    released[gs] = at
    check("the shop throttle releases after throttle/gamespeed wall seconds at gamespeed " .. gs,
      at ~= nil and near(at, throttle / gs, 0.05), at)
  end
  check("a fast game no longer waits the full wall-clock throttle",
    released[4] ~= nil and released[1] ~= nil and released[4] < released[1] * 0.3, released[4])
  check("a slow game gets the whole animation before the next action is allowed",
    released[0.5] ~= nil and released[0.5] > released[1] * 1.9, released[0.5])
  reset_world(1)
  Enforce.reset_run_state()
end

do
  local queued, pending, buy_at = {}, {}, nil
  _G.Event = function(cfg)
    cfg.timer = cfg.timer or "TOTAL"
    return cfg
  end
  G.E_MANAGER.add_event = function(_, e)
    e.fires_at = G.TIMERS[e.timer] + (e.delay or 0)
    queued[#queued + 1] = e
    pending[#pending + 1] = e
  end

  local Staging = require("core.staging")
  local Dispatcher = require("core.dispatcher")
  Staging._test.set_validator(function() return true end)
  Staging.set_executor(function(msg)
    local h = Dispatcher.get_action_handler("buy_from_shop")
    local exec = h and h(msg.data.data)
    if type(exec) == "function" then exec() end
  end)

  local lift_at
  local function stage_buy(gs)
    queued, pending, buy_at, lift_at = {}, {}, nil, nil
    reset_world(gs)
    G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
    local card = {
      cost = 5, highlighted = false,
      ability = { name = "Joker", set = "Joker" },
      config = { center = { key = "j_joker", set = "Joker" } },
      juice_up = function() end,
    }
    G.shop_jokers.cards = { card }
    G.FUNCS.buy_from_shop = function() buy_at = G.TIMERS.REAL end
    Staging.reset_run_state()
    Staging.queue({ command = "action", data = { id = "gate-buy-" .. tostring(gs),
      name = "buy_from_shop", data = { area = "shop_jokers", index = 1 } } })
    local dt = 1 / 240
    for _ = 1, math.floor(8 / dt) do
      advance(dt, dt)
      pcall(Staging.update, dt)
      if card.highlighted and not lift_at then lift_at = G.TIMERS.REAL end
      for i = #pending, 1, -1 do
        local e = pending[i]
        if G.TIMERS[e.timer] >= e.fires_at then
          table.remove(pending, i)
          if e.func then pcall(e.func) end
        end
      end
    end
  end

  local function expected_hover_wall(gs)
    local v = Config.get("NEURO_HOVER_SHOP") * Config.get("NEURO_SPEED_MULT") / gs
    return math.max(v, 0.25)
  end

  local function expected_commit_wall(gs)
    local beat = Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_DELAY") / gs
    return math.max(beat, 0.4 - 0.35 * expected_hover_wall(gs))
  end

  for _, gs in ipairs(SPEEDS) do
    stage_buy(gs)
    check("the shop hover keeps its wall-clock length at gamespeed " .. gs,
      lift_at ~= nil and near(lift_at, 0.65 * expected_hover_wall(gs), 0.05), lift_at)
    check("the buy lands one hover plus the commit beat in game-clock seconds at gamespeed " .. gs,
      buy_at ~= nil and near(buy_at, expected_hover_wall(gs) + expected_commit_wall(gs), 0.05), buy_at)
    check("the buy never lands while the card is still lifting at gamespeed " .. gs,
      buy_at ~= nil and buy_at >= 0.65 * expected_hover_wall(gs) + 0.4 - 0.05,
      tostring(buy_at) .. " vs " .. tostring(0.65 * expected_hover_wall(gs) + 0.4))
  end
  reset_world(1)
end

local function advance_paused(seconds, dt)
  dt = dt or 1 / 240
  local target = G.TIMERS.REAL + seconds
  while G.TIMERS.REAL < target - 1e-12 do
    local step = math.min(dt, target - G.TIMERS.REAL)
    G.TIMERS.REAL = G.TIMERS.REAL + step
    wall = wall + step
    Utils.observe_clock()
  end
end

do
  for _, gs in ipairs(SPEEDS) do
    reset_world(gs)
    advance(2)
    G.SETTINGS.paused = true
    local frozen = G.TIMERS.TOTAL
    local before = {}
    for _, gate in ipairs(GateClocks.gates) do before[gate.id] = Utils.gate_now(gate.id) end
    advance_paused(3)
    check("the engine really does freeze G.TIMERS.TOTAL while paused at gamespeed " .. gs,
      near(G.TIMERS.TOTAL, frozen, 1e-9), G.TIMERS.TOTAL .. " vs " .. frozen)
    local stalled = {}
    for _, gate in ipairs(GateClocks.gates) do
      if not near(Utils.gate_now(gate.id) - before[gate.id], 3, 1e-6) then
        stalled[#stalled + 1] = gate.id .. "(+" .. (Utils.gate_now(gate.id) - before[gate.id]) .. ")"
      end
    end
    check("every gate keeps counting real seconds while the game is paused at gamespeed " .. gs,
      #stalled == 0, table.concat(stalled, ","))
    G.SETTINGS.paused = false
  end
  reset_world(1)
end

do
  reset_world(1)
  advance(5)
  G.SETTINGS.paused = true
  local stamped = Utils.gate_now("force_debounce")
  local window = Utils.gate_seconds("force_debounce", "NEURO_FORCE_DEBOUNCE")
  check("the force debounce is a real window, not a zero", window > 0, window)
  advance_paused(10)
  check("a debounce stamped as the pause begins still expires during the pause",
    (Utils.gate_now("force_debounce") - stamped) >= window,
    Utils.gate_now("force_debounce") - stamped)
  local resumed_at = Utils.gate_now("state_cooldown")
  G.SETTINGS.paused = false
  advance(2)
  check("the game clock advances by game seconds again once the pause ends",
    near(Utils.gate_now("state_cooldown") - resumed_at, 2, 1e-6),
    Utils.gate_now("state_cooldown") - resumed_at)
  reset_world(1)
end

done()
