_G.NEURO_TEST = true

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 0, TOTAL = 0 },
  STATES = { SHOP = 1 }, STATE = 1,
  SETTINGS = { paused = false },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("glow timing")

local Cards = require("hud.cards")
local step = Cards.glow_step
local wvalid = Cards.glow_window_valid

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end
local function smooth(f)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return f * f * (3 - 2 * f)
end

do
  check("valid: nil window rejected", wvalid(nil, 1) == false)
  check("valid: missing t1 rejected", wvalid({ t0 = 1 }, 1) == false)
  check("valid: sub-minimum duration rejected", wvalid({ t0 = 10, t1 = 10.04 }, 10) == false)
  check("valid: zero duration rejected", wvalid({ t0 = 10, t1 = 10 }, 10) == false)
  check("valid: before t0 rejected", wvalid({ t0 = 10, t1 = 12 }, 9.9) == false)
  check("valid: live window accepted", wvalid({ t0 = 10, t1 = 12 }, 10.5) == true)
end

do
  local lv = step(11, 0, 0.016, true, { t0 = 10, t1 = 12 })
  check("ramp: level tracks window midpoint", near(lv, 0.5), lv)
  lv = step(10.6, 0, 0.016, true, { t0 = 10, t1 = 12 })
  check("ramp: 2s window is not the fixed 0.6s ramp", near(lv, 0.3), lv)
  lv = step(10.6, 0, 0.016, true, { t0 = 10, t1 = 10.6 })
  check("ramp: 0.6s window completes at its own end", near(lv, 1), lv)
end

do
  for _, dur in ipairs({ 0.32, 0.6, 1.0 }) do
    local t0 = 10
    local lv, _, commit = step(t0 + dur, 0, 0.016, true, { t0 = t0, t1 = t0 + dur })
    check(string.format("commit: peak lands at window end (%.2fs)", dur),
      near(lv, 1) and near(commit, 1), lv .. "/" .. commit)
    local lv2, _, commit2 = step(t0 + dur * 0.97, 0, 0.016, true, { t0 = t0, t1 = t0 + dur })
    check(string.format("commit: not peaked before window end (%.2fs)", dur),
      lv2 < 1 and commit2 < 1, lv2 .. "/" .. commit2)
  end
  local lv, _, commit = step(12.1, 0, 0.016, true, { t0 = 10, t1 = 12 })
  check("commit: held at peak past window end while active", near(lv, 1) and near(commit, 1))
  local lv3 = step(10.5, 0.9, 0.016, true, { t0 = 10, t1 = 12 })
  check("ramp: level never regresses inside a window", near(lv3, 0.9), lv3)
end

do
  local lv, alpha, commit = step(0, 0, 0.016, true, nil)
  check("fallback: no window ramps at fixed rate", near(lv, 0.016 / 0.6), lv)
  check("fallback: alpha is smoothstep of level", near(alpha, smooth(lv)), alpha)
  check("fallback: commit is smoothstep of shifted level", near(commit, smooth((lv - 0.35) / 0.65)), commit)
  lv = step(0, 0, 0.5, true, nil)
  check("fallback: frame delta clamped", near(lv, 0.05 / 0.6), lv)
  lv = step(10, 0, 0.016, true, { t0 = 10, t1 = 10.04 })
  check("fallback: sub-minimum window uses fixed rate", near(lv, 0.016 / 0.6), lv)
  lv = step(20, 0.5, 0.016, false, { t0 = 10, t1 = 12 })
  check("fallback: inactive decays toward zero", near(lv, 0.5 - 0.016 / 0.6), lv)
  lv = step(20, 0, 0.016, false, nil)
  check("fallback: idle stays at zero", lv == 0, lv)
end

local Staging = require("core.staging")
local Config = require("core.config")

local GS_MIN, GS_MAX = 0.5, 4
local HOVER_FLOOR = 0.25
local PER_CARD_FLOOR = 0.20
local HOLD_FLOOR = 0.30
local LIFT_FRAC = 0.65
local ENGINE_LIFT = 0.4

local function clamped_gs()
  local gs = tonumber(G.SETTINGS and G.SETTINGS.GAMESPEED) or 1
  if gs < GS_MIN then return GS_MIN end
  if gs > GS_MAX then return GS_MAX end
  return gs
end

local function paced(key, floor_s)
  local v = Config.get(key) * Config.get("NEURO_SPEED_MULT") / clamped_gs()
  if v < floor_s then return floor_s end
  return v
end

local GATE = { NEURO_SHOP_BUY_DELAY = "shop_buy_block", NEURO_PACK_PICK_DELAY = "pack_pick_block" }
local Utils = require("util.utils")
local function commit_of(key, hover_eff)
  local c = key and (Utils.gate_seconds(GATE[key], key) / clamped_gs()) or 0
  local floor_s = ENGINE_LIFT - (1 - LIFT_FRAC) * hover_eff
  if c < floor_s then return floor_s end
  return c
end

local function make_bridge()
  local b = { results = {} }
  function b:send_action_result(id, ok, message)
    self.results[#self.results + 1] = { id = id, ok = ok, message = message }
  end
  function b:send_context() return true end
  function b:register_actions() end
  function b:force_actions() end
  function b:send() end
  return b
end

local function shop_card()
  return {
    cost = 4, sell_cost = 1,
    ability = { set = "Joker", name = "Mock" },
    config = { center = {} },
    juice_up = function() end,
  }
end

local function tick_to(t)
  G.TIMERS.REAL = t
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  Staging.update()
end

local exec_log = {}
Staging._test.set_validator(function() return true end)
Staging.set_executor(function(msg)
  exec_log[#exec_log + 1] = { id = msg.data.id, at = G.TIMERS.REAL }
end)

local function fresh_stage(id, t_start, real_validation)
  Staging.reset_run_state()
  exec_log = {}
  G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
  if real_validation then
    G.NEURO.dispatcher = require("core.dispatcher")
    G.NEURO.actions = require("core.actions")

    G.NEURO.persona = "neuro"
    G.NEURO.state = "SHOP"
    G.NEURO.econ_plan_ok = true
    G.GAME = {
      dollars = 20, bankrupt_at = 0,
      current_round = { hands_left = 4, discards_left = 3 },
      round_resets = { ante = 1 },
    }
    G.jokers = { cards = {}, config = { card_limit = 5 } }
    local PlanGate = require("core.plan_gate")
    G.NEURO.plan = {
      money = "buy the mock joker",
      money_scope = PlanGate.current_economy_scope(),
    }
  end
  local card = shop_card()
  G.shop_jokers = { cards = { card } }
  G.TIMERS.REAL = t_start
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  local msg = { command = "action", data = { id = id, name = "buy_from_shop",
    data = '{"area":"shop_jokers","index":1}' } }
  local bridge = make_bridge()
  require("tests.helpers").stage_registered(nil, { "buy_from_shop" })
  local ok = Staging.queue(msg, bridge)
  return card, ok, bridge
end

do
  local hover_dur = paced("NEURO_HOVER_SHOP", HOVER_FLOOR)
  local commit = commit_of("NEURO_SHOP_BUY_DELAY", hover_dur)
  local win_dur = hover_dur + commit
  local card, ok = fresh_stage("glow-1", 5)
  check("stage: buy queues", ok == true)
  local w = G.NEURO.ai_glow and G.NEURO.ai_glow[card]
  check("stage: glow window published for hovered card", type(w) == "table")
  check("stage: window start is stage time", w and near(w.t0, 5), w and w.t0)
  check("stage: window spans the hover plus the engine commit beat",
    w and near(w.t1 - w.t0, win_dur), w and (w.t1 - w.t0))

  tick_to(5 + hover_dur * 0.30)
  check("lift: card not lifted early in the window", not card.highlighted)
  tick_to(5 + hover_dur * 0.60)
  check("lift: card not lifted before the commit point", not card.highlighted)
  tick_to(5 + hover_dur * 0.66)
  check("lift: card lifted in the tail of the window", card.highlighted == true)
  check("lift: lifted card carries the ai flag", G.NEURO.ai_highlighted[card] == true)

  tick_to(5 + hover_dur + 0.02)
  tick_to(5 + hover_dur + 0.05)
  check("fire: executor ran at window end", #exec_log == 1)
  check("fire: execution not before the window closed",
    exec_log[1] and exec_log[1].at >= 5 + hover_dur, exec_log[1] and exec_log[1].at)
  check("fire: glow window outlives execution by the commit beat",
    G.NEURO.ai_glow[card] ~= nil and near(G.NEURO.ai_glow[card].t1, 5 + win_dur))
  check("fire: highlight cleared at execution", not card.highlighted)

  local peak_lv, _, peak_commit = step(5 + win_dur, 0, 0.016, true, w)
  check("fire: glow peaks exactly when the buy resolves",
    near(peak_lv, 1) and near(peak_commit, 1))
  local early_lv = step(5 + win_dur - commit * 0.5, 0, 0.016, true, w)
  check("fire: glow has not peaked halfway through the commit beat", early_lv < 1)
end

do
  Config.set("NEURO_SPEED_MULT", 0.3)
  local hover_dur = paced("NEURO_HOVER_SHOP", HOVER_FLOOR)
  local commit = commit_of("NEURO_SHOP_BUY_DELAY", hover_dur)
  local card = fresh_stage("glow-2", 20)
  local w = G.NEURO.ai_glow[card]
  check("speed: hover part of the window follows the speed multiplier",
    w and near(w.t1 - w.t0, hover_dur + commit), w and (w.t1 - w.t0))
  check("speed: commit beat is not shrunk by the speed multiplier",
    near(commit, Config.get_raw("NEURO_SHOP_BUY_DELAY")))
  tick_to(20 + hover_dur * 0.5)
  check("speed: no lift at half of a short window", not card.highlighted)
  tick_to(20 + hover_dur * 0.7)
  check("speed: lift still lands in the tail at low speed", card.highlighted == true)
  tick_to(20 + hover_dur + 0.02)
  tick_to(20 + hover_dur + 0.04)
  check("speed: fast window still executes", #exec_log == 1)
  Config.reset("NEURO_SPEED_MULT")
end

do
  local ENGINE_SPRING_SETTLE = 0.17
  for _, mult in ipairs({ 0.1, 0.3, 1.0, 2.0 }) do
    Config.set("NEURO_SPEED_MULT", mult)
    local base = 100 + mult * 10
    local card = fresh_stage("glow-lift-" .. tostring(mult), base)
    local w = G.NEURO.ai_glow[card]
    local lift_at = nil
    local t = base
    while t <= (w and w.t1 or base) + 0.5 do
      tick_to(t)
      if card.highlighted and not lift_at then lift_at = t break end
      t = t + 0.005
    end
    check("engine: lift happens inside the window at speed mult " .. tostring(mult),
      lift_at ~= nil and w ~= nil and lift_at < w.t1, lift_at)
    check("engine: lift-to-resolve never shorter than the card spring at speed mult "
      .. tostring(mult),
      lift_at ~= nil and w ~= nil and (w.t1 - lift_at) >= ENGINE_SPRING_SETTLE,
      lift_at and w and (w.t1 - lift_at))
  end
  Config.reset("NEURO_SPEED_MULT")
end

local GAMESPEED_TABLE = {
  { 0.5, 1.20, 1.18, 2.00, 0.82 },
  { 1, 0.60, 0.79, 1.00, 0.21 },
  { 2, 0.30, 0.595, 0.595, 0 },
  { 4, 0.25, 0.5625, 0.5625, 0 },
}

do
  for _, row in ipairs(GAMESPEED_TABLE) do
    local gs, hover_eff, buy = row[1], row[2], row[4]
    G.SETTINGS = G.SETTINGS or {}
    G.SETTINGS.GAMESPEED = gs
    G.SPEEDFACTOR = gs
    check("engine: the hover shrinks with game speed " .. tostring(gs),
      near(paced("NEURO_HOVER_SHOP", HOVER_FLOOR), hover_eff), paced("NEURO_HOVER_SHOP", HOVER_FLOOR))
    local card = fresh_stage("glow-gs-" .. tostring(gs), 200 + gs)
    local w = G.NEURO.ai_glow[card]
    check("engine: the buy window matches the speed table at game speed " .. tostring(gs),
      w ~= nil and near(w.t1 - w.t0, buy), w and (w.t1 - w.t0))
  end
  for _, cs in ipairs({ { 0.1, GAMESPEED_TABLE[1][4], 210 }, { 16, GAMESPEED_TABLE[4][4], 211 } }) do
    G.SETTINGS.GAMESPEED = cs[1]
    G.SPEEDFACTOR = cs[1]
    local card = fresh_stage("glow-gs-clamp-" .. tostring(cs[1]), cs[3])
    local w = G.NEURO.ai_glow[card]
    check("engine: a game speed outside the engine range clamps to the table end at " .. tostring(cs[1]),
      w ~= nil and near(w.t1 - w.t0, cs[2]), w and (w.t1 - w.t0))
  end
  G.SETTINGS.GAMESPEED = 1
  G.SPEEDFACTOR = 1
end

do
  Staging._test.set_validator(nil)
  local card, ok, bridge = fresh_stage("glow-3", 40, true)
  check("cancel: real validator accepts and sends the first success ack",
    ok == true and #bridge.results == 1 and bridge.results[1].id == "glow-3"
      and bridge.results[1].ok == true)
  tick_to(40.1)
  Staging.on_state_change()
  check("cancel: glow window cleared on cancel", G.NEURO.ai_glow[card] == nil)
  check("cancel: no highlight left behind", not card.highlighted)
  check("cancel: no extra action result on cancel", #bridge.results == 1)
  check("cancel: nothing executed", #exec_log == 0)
  Staging._test.set_validator(function() return true end)
end

do
  Staging.reset_run_state()
  exec_log = {}
  G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
  local c1, c2 = shop_card(), shop_card()
  G.hand = { cards = { c1, c2 }, highlighted = {}, config = { card_limit = 5 } }
  G.TIMERS.REAL = 60
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  local msg = { command = "action", data = { id = "glow-4", name = "play_hand",
    data = '{"indices":[1,2]}' } }
  Staging.queue(msg, make_bridge())
  local per = paced("NEURO_HOVER_PER_CARD", PER_CARD_FLOOR)
  local hold = paced("NEURO_HOLD_ALL_SELECTED", HOLD_FLOOR)
  local w1, w2 = G.NEURO.ai_glow[c1], G.NEURO.ai_glow[c2]
  check("multi: both cards get windows", type(w1) == "table" and type(w2) == "table")
  check("multi: starts staggered by the per-card hover",
    w1 and w2 and near(w2.t0 - w1.t0, per), w1 and w2 and (w2.t0 - w1.t0))
  check("multi: both windows end at the shared execute time",
    w1 and w2 and near(w1.t1, w2.t1) and near(w1.t1, 60 + 2 * per + hold),
    w1 and w1.t1)
  Staging.on_state_change()
  Staging.reset_run_state()
end

do
  Staging.reset_run_state()
  exec_log = {}
  G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
  local c1, c2 = shop_card(), shop_card()
  G.hand = { cards = { c1, c2 }, highlighted = {}, config = { card_limit = 5 } }
  G.TIMERS.REAL = 70
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  Staging.queue({ command = "action", data = { id = "glow-hold", name = "play_hand",
    data = '{"indices":[1,2]}' } }, make_bridge())
  local w = G.NEURO.ai_glow[c1]
  Config.set("NEURO_HOLD_ALL_SELECTED", 3.0)
  local t = 70
  while w and t <= w.t1 + 1.0 do
    tick_to(t)
    if #exec_log > 0 then break end
    t = t + 0.005
  end
  Config.reset("NEURO_HOLD_ALL_SELECTED")
  check("multi: retuning the hold mid-action cannot desync execution from the glow window",
    w ~= nil and #exec_log == 1 and near(exec_log[1].at, w.t1, 0.02),
    exec_log[1] and (exec_log[1].at - (w and w.t1 or 0)))
  Staging.reset_run_state()
end

local Prims = require("hud.prims")

local BUY_PAYLOAD  = '{"area":"shop_jokers","index":1}'
local TRAY_PAYLOAD = '{"area":"consumeables","index":1}'
local PACK_PAYLOAD = '{"area":"booster_pack","index":1}'

local function into_shop(card) G.shop_jokers = { cards = { card } } end
local function into_tray(card) G.consumeables = { cards = { card } } end
local function into_pack(card) G.pack_cards = { cards = { card } } end

local function stage(id, t_start, name, payload, prep)
  Staging.reset_run_state()
  exec_log = {}
  G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
  G.shop_jokers, G.consumeables, G.pack_cards = nil, nil, nil
  local card = shop_card()
  prep(card)
  G.TIMERS.REAL = t_start
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  Staging.queue({ command = "action",
    data = { id = id, name = name, data = payload } }, make_bridge())
  return card
end

local function win_of(card) return G.NEURO.ai_glow and G.NEURO.ai_glow[card] end
local function width_of(card)
  local w = win_of(card)
  return w and (w.t1 - w.t0) or -1
end

local function shop_width()
  local h = paced("NEURO_HOVER_SHOP", HOVER_FLOOR)
  return h + commit_of("NEURO_SHOP_BUY_DELAY", h)
end

local function tray_width()
  local h = paced("NEURO_HOVER_USE", HOVER_FLOOR)
  return h + commit_of(nil, h)
end

local function pack_width()
  local h = paced("NEURO_HOVER_USE", HOVER_FLOOR)
  return h + commit_of("NEURO_PACK_PICK_DELAY", h)
end

do
  local shop_hover = Config.get("NEURO_HOVER_SHOP")
  local use_hover = Config.get("NEURO_HOVER_USE")

  check("split: the shop hover and the card-use hover are separate settings",
    type(shop_hover) == "number" and type(use_hover) == "number",
    tostring(shop_hover) .. "/" .. tostring(use_hover))

  local c = stage("split-buy", 300, "buy_from_shop", BUY_PAYLOAD, into_shop)
  check("split: shop buy runs on the shop hover",
    near(width_of(c), shop_width()), width_of(c))
  c = stage("split-tray", 310, "use_consumable", TRAY_PAYLOAD, into_tray)
  check("split: consumable use runs on the card-use hover plus the engine lift floor",
    near(width_of(c), tray_width()), width_of(c))
  c = stage("split-pack", 320, "choose_pack_card", PACK_PAYLOAD, into_pack)
  check("split: pack pick runs on the card-use hover plus its commit beat",
    near(width_of(c), pack_width()), width_of(c))

  Config.set("NEURO_HOVER_SHOP", 0.15)
  local tray_before = tray_width()
  c = stage("split-tray-cut", 330, "use_consumable", TRAY_PAYLOAD, into_tray)
  check("split: cutting the shop hover leaves card use alone",
    near(width_of(c), tray_before), width_of(c))
  c = stage("split-buy-cut", 340, "buy_from_shop", BUY_PAYLOAD, into_shop)
  check("split: cutting the shop hover moves the buy down to the hover floor",
    near(width_of(c), HOVER_FLOOR + commit_of("NEURO_SHOP_BUY_DELAY", HOVER_FLOOR))
      and near(paced("NEURO_HOVER_SHOP", HOVER_FLOOR), HOVER_FLOOR), width_of(c))
  Config.reset("NEURO_HOVER_SHOP")

  Config.set("NEURO_HOVER_USE", 2.0)
  c = stage("split-buy-stretch", 350, "buy_from_shop", BUY_PAYLOAD, into_shop)
  check("split: stretching the card-use hover leaves the buy alone",
    near(width_of(c), shop_width()), width_of(c))
  c = stage("split-tray-stretch", 360, "use_consumable", TRAY_PAYLOAD, into_tray)
  check("split: stretching the card-use hover does move card use",
    near(width_of(c), tray_width()), width_of(c))
  Config.reset("NEURO_HOVER_USE")
end

do
  G.SETTINGS.GAMESPEED = 2
  G.SPEEDFACTOR = 4
  local card = fresh_stage("glow-accel", 250)
  local w = win_of(card)
  check("engine: the hover clock follows GAMESPEED, not the accelerator's SPEEDFACTOR",
    w ~= nil and near(w.t1 - w.t0, shop_width()), w and (w.t1 - w.t0))
  G.SETTINGS.GAMESPEED = 1
  G.SPEEDFACTOR = 1
  Staging.reset_run_state()
end

for _, cs in ipairs({ { 2, 1.0, 80 }, { 4, 1.0, 90 }, { 4, 0.3, 100 }, { 16, 1.0, 110 } }) do
  local gs, mult, base = cs[1], cs[2], cs[3]
  Staging.reset_run_state()
  exec_log = {}
  G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
  G.SETTINGS.GAMESPEED = gs
  G.SPEEDFACTOR = gs
  Config.set("NEURO_SPEED_MULT", mult)
  local c1, c2 = shop_card(), shop_card()
  G.hand = { cards = { c1, c2 }, highlighted = {}, config = { card_limit = 5 } }
  G.TIMERS.REAL = base
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  Staging.queue({ command = "action", data = { id = "glow-multi-" .. base, name = "play_hand",
    data = '{"indices":[1,2]}' } }, make_bridge())
  local per = paced("NEURO_HOVER_PER_CARD", PER_CARD_FLOOR)
  local hold = paced("NEURO_HOLD_ALL_SELECTED", HOLD_FLOOR)
  local w1, w2 = G.NEURO.ai_glow[c1], G.NEURO.ai_glow[c2]
  local label = string.format("game speed %s at speed mult %s", tostring(gs), tostring(mult))
  check("multi: the stagger and the shared hold both scale with " .. label,
    w1 ~= nil and w2 ~= nil and near(w2.t0 - w1.t0, per) and near(w1.t1, base + 2 * per + hold),
    w1 and (w1.t1 - base))
  Config.reset("NEURO_SPEED_MULT")
  G.SETTINGS.GAMESPEED = 1
  G.SPEEDFACTOR = 1
  Staging.reset_run_state()
end

do
  G.SETTINGS.GAMESPEED = 4
  G.SPEEDFACTOR = 4
  Config.set("NEURO_SPEED_MULT", 0.3)
  check("multi: the per-card hover cannot fall below its floor",
    near(paced("NEURO_HOVER_PER_CARD", PER_CARD_FLOOR), PER_CARD_FLOOR),
    paced("NEURO_HOVER_PER_CARD", PER_CARD_FLOOR))
  check("multi: the shared hold cannot fall below its floor",
    near(paced("NEURO_HOLD_ALL_SELECTED", HOLD_FLOOR), HOLD_FLOOR),
    paced("NEURO_HOLD_ALL_SELECTED", HOLD_FLOOR))
  Config.reset("NEURO_SPEED_MULT")
  G.SETTINGS.GAMESPEED = 1
  G.SPEEDFACTOR = 1
end

do
  local c = stage("tag-buy", 400, "buy_from_shop", BUY_PAYLOAD, into_shop)
  check("attack: the shop buy window carries the attack tag", win_of(c).attack == true)
  c = stage("tag-tray", 410, "use_consumable", TRAY_PAYLOAD, into_tray)
  check("attack: consumable use carries no attack tag", not win_of(c).attack)
  c = stage("tag-pack", 420, "choose_pack_card", PACK_PAYLOAD, into_pack)
  check("attack: pack pick carries no attack tag", not win_of(c).attack)

  Staging.reset_run_state()
  G.NEURO = { ai_highlighted = setmetatable({}, { __mode = "k" }) }
  local c1, c2 = shop_card(), shop_card()
  G.hand = { cards = { c1, c2 }, highlighted = {}, config = { card_limit = 5 } }
  G.TIMERS.REAL = 430
  G.TIMERS.TOTAL = G.TIMERS.REAL * clamped_gs()
  Staging.queue({ command = "action", data = { id = "tag-play", name = "play_hand",
    data = '{"indices":[1,2]}' } }, make_bridge())
  check("attack: a played hand carries no attack tag",
    not win_of(c1).attack and not win_of(c2).attack)
  Staging.reset_run_state()
end

do
  local gain = Cards.shop_attack_gain
  check("attack: the shaping gain is a named constant", type(gain) == "number" and gain > 1, gain)
  for _, x in ipairs({ 0, 0.1, 0.25, 0.5, 0.9, 1 }) do
    check("attack: an untagged glow keeps the raw ramp at " .. x,
      Cards.glow_alpha(x, nil) == x, Cards.glow_alpha(x, nil))
    check("attack: a tagged glow is the shared shaping at " .. x,
      near(Cards.glow_alpha(x, true), Prims.ease_out_cubic01(math.min(1, x * gain))),
      Cards.glow_alpha(x, true))
    check("attack: the shaping never dims the ramp at " .. x,
      Cards.glow_alpha(x, true) >= x - 1e-12, Cards.glow_alpha(x, true))
  end
  check("attack: the shaping saturates at the reciprocal of the gain",
    near(Cards.shop_attack01(1 / gain), 1), Cards.shop_attack01(1 / gain))
end

do
  local painters = Cards.glow_painters
  local orig = { evil = painters.evil, neuro = painters.neuro }
  local seen = {}
  painters.evil = function(_, a) seen.evil = a end
  painters.neuro = function(_, a) seen.neuro = a end
  local vt = { x = 0, y = 0, w = 1, h = 1.4, scale = 1 }
  local RAW = 0.4

  G.NEURO = G.NEURO or {}
  local function paint(tag)
    seen = {}
    for _, p in ipairs({ "evil", "neuro" }) do
      G.NEURO.persona = p
      Cards.run_glow({}, vt, RAW, 0.5, 3.0, tag)
    end
  end

  paint(nil)
  check("attack: an untagged glow reaches both personas as the raw ramp",
    seen.evil == RAW and seen.neuro == RAW,
    tostring(seen.evil) .. "/" .. tostring(seen.neuro))

  paint(true)
  local shaped = Cards.glow_alpha(RAW, true)
  check("attack: the shop shaping reaches both personas identically",
    seen.evil ~= nil and near(seen.evil, shaped) and near(seen.neuro, shaped),
    tostring(seen.evil) .. "/" .. tostring(seen.neuro))
  check("attack: the shop shaping actually lands the glow sooner", shaped > RAW, shaped)

  painters.evil, painters.neuro = orig.evil, orig.neuro
  G.NEURO.persona = nil
end

local function first_lift(card, base, w, step_s)
  local t = base
  while w and t <= w.t1 do
    tick_to(t)
    if card.highlighted then return t end
    t = t + step_s
  end
  return nil
end

do
  local MIN_MARGIN = 0.2
  local cases = {
    { id = "margin-buy", name = "buy_from_shop", payload = BUY_PAYLOAD,
      prep = into_shop, label = "shop buy" },
    { id = "margin-pack", name = "choose_pack_card", payload = PACK_PAYLOAD,
      prep = into_pack, label = "pack pick" },
  }
  for _, cs in ipairs(cases) do
    local base = 500
    local card = stage(cs.id, base, cs.name, cs.payload, cs.prep)
    local w = win_of(card)
    local lift_at = first_lift(card, base, w, 0.001)
    check("margin: " .. cs.label .. " lifts before it resolves",
      lift_at ~= nil and w ~= nil and lift_at < w.t1, lift_at)
    local slack = (lift_at and w) and ((w.t1 - lift_at) - ENGINE_LIFT) or -1
    check("margin: " .. cs.label .. " leaves the lift motion room to finish",
      slack >= MIN_MARGIN, slack)
  end
  Staging.reset_run_state()
end

do
  local STEP = 0.0005
  for _, row in ipairs(GAMESPEED_TABLE) do
    local gs, hover_eff, lift_end, buy, margin = row[1], row[2], row[3], row[4], row[5]
    G.SETTINGS.GAMESPEED = gs
    G.SPEEDFACTOR = gs
    local base = 600 + gs
    local card = stage("margin-gs-" .. tostring(gs), base, "buy_from_shop", BUY_PAYLOAD, into_shop)
    local w = win_of(card)
    local lift_at = first_lift(card, base, w, STEP)
    local rel_lift = lift_at and (lift_at - base) or -1
    check("margin: the lift starts on the scaled hover at game speed " .. tostring(gs),
      lift_at ~= nil and near(rel_lift, LIFT_FRAC * hover_eff, STEP), rel_lift)
    local ends_at = rel_lift + ENGINE_LIFT
    check("margin: the lift motion ends where the speed table says at game speed " .. tostring(gs),
      lift_at ~= nil and near(ends_at, lift_end, STEP), ends_at)
    local slack = (lift_at and w) and ((w.t1 - base) - ends_at) or -1
    check("margin: the buy never resolves before the lift motion at game speed " .. tostring(gs),
      lift_at ~= nil and w ~= nil and near(w.t1 - base, buy) and slack >= -STEP
        and near(slack, margin, STEP), slack)
  end
  G.SETTINGS.GAMESPEED = 1
  G.SPEEDFACTOR = 1
  Staging.reset_run_state()
end

do
  for _, gs in ipairs({ 0.5, 1, 2, 4 }) do
    G.SETTINGS = G.SETTINGS or {}
    G.SETTINGS.GAMESPEED = gs
    local card = fresh_stage("entry-" .. tostring(gs), 500 + gs)
    local w = G.NEURO.ai_glow[card]
    check("entry: window carries the lift fraction at gamespeed " .. tostring(gs),
      w ~= nil and type(w.lift01) == "number" and w.lift01 > 0 and w.lift01 < 1,
      w and tostring(w.lift01))
    if w and w.lift01 then
      local lv = w.lift01
      local at_lift = Cards.glow_alpha(lv * lv * (3 - 2 * lv), true, w.lift01)
      check(string.format("entry: alpha is fully present when the card lifts at gamespeed %s (%.3f)",
        tostring(gs), at_lift), at_lift >= 0.99)
      local before = (lv * 0.5) ^ 2 * (3 - 2 * lv * 0.5)
      check(string.format("entry: alpha is not yet full halfway to the lift at gamespeed %s",
        tostring(gs)), Cards.glow_alpha(before, true, w.lift01) < 0.99)
      local flat = Cards.glow_alpha(lv * lv * (3 - 2 * lv), true, nil)
      check(string.format("entry: deriving the gain beats the fixed one at gamespeed %s (%.3f vs %.3f)",
        tostring(gs), at_lift, flat), at_lift >= flat)
    end
  end
  G.SETTINGS.GAMESPEED = 1
end

done()
