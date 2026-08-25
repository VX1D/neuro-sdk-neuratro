
local check, done = require("tests.helpers").harness("anim settle")

_G.G = {
  TIMERS = { REAL = 0, TOTAL = 0 },
  SETTINGS = { GAMESPEED = 1 },
  SPEEDFACTOR = 1,
  NEURO = {},
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
}
_G.SMODS = { current_mod = { path = "./", config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end, Mods = {} }
love = setmetatable({
  timer = { getTime = function() return G.TIMERS.REAL end },
  graphics = setmetatable({}, { __index = function() return function() end end }),
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

local queue = {}
_G.Event = function(c) c.timer = c.timer or "TOTAL"; return c end
G.E_MANAGER = { queues = { base = queue }, add_event = function(_, e)
  e.at = G.TIMERS[e.timer] + (e.delay or 0)
  queue[#queue + 1] = e
end }

local NeuroAnim = require("render.neuro-anim")

local function fail_count(site)
  return (NeuroAnim._anim_fails and NeuroAnim._anim_fails[site]) or 0
end

local function reset()
  for i = #queue, 1, -1 do queue[i] = nil end
  G.TIMERS.REAL, G.TIMERS.TOTAL = 0, 0
  G.SETTINGS.GAMESPEED = 1
  G.pack_cards, G.booster_pack = nil, nil
  G.shop_jokers, G.shop_vouchers, G.shop_booster = nil, nil, nil
  G.play = { name = "G.play" }
  G.jokers = nil
end

local function moveable(fired)
  return {
    STATIONARY = false,
    juice_up = function(self) fired[#fired + 1] = G.TIMERS.REAL; self.juiced = true end,
  }
end

local function step(seconds, speed, hook)
  local frames = math.floor(seconds * 60)
  for _ = 1, frames do
    G.TIMERS.REAL = G.TIMERS.REAL + 1 / 60
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + (speed or 1) / 60
    if hook then hook(G.TIMERS.REAL) end
    for i = #queue, 1, -1 do
      local e = queue[i]
      if e.func and G.TIMERS[e.timer] >= e.at then
        table.remove(queue, i)
        pcall(e.func)
      end
    end
  end
end

do
  reset()
  local fired = {}
  local card = moveable(fired)
  NeuroAnim.on_buy(card)
  step(0.30)
  local early = #fired
  card.STATIONARY = true
  step(0.50)
  check("a juice on a moving card is deferred, not fired (" .. early .. " early)",
    early == 0)
  check("the deferred juice still fires once the card settles (" .. #fired .. ")", #fired == 1)
end

do
  reset()
  local before = fail_count("settle_card_expired")
  local fired = {}
  local card = moveable(fired)
  NeuroAnim.on_buy(card)
  step(NeuroAnim.card_settle_budget + 1.0)
  check("a card that never settles is not juiced (" .. #fired .. ")", #fired == 0)
  check("and giving up on it is reported, not silent ("
    .. (fail_count("settle_card_expired") - before) .. ")",
    fail_count("settle_card_expired") - before == 1)
  check("the give-up is bounded by the card budget, not by the queue ("
    .. #queue .. " left)", #queue == 0)
end

-- The blocker holds for as long as the engine's own cashout chain does: up to seven eval rows at
-- delay(0.2) + a 0.5 `before` each, a 0.6 divider, a defeat event up to 1.18 and one event per
-- dollar (dump functions/common_events.lua:1126-1300). Measured span 3.63-10 s of TOTAL.
local ENGINE_CHAIN_TOTAL_MIN = 3.63
local ENGINE_CHAIN_TOTAL_MAX = 10.0

local function blocking_chain(total_seconds)
  return { blocking = true, blockable = true, timer = "TOTAL",
           drain_at = G.TIMERS.TOTAL + total_seconds }
end

local function drive_blocked_juice(speed, chain_total)
  reset()
  G.SETTINGS.GAMESPEED = speed
  local fired = {}
  local card = moveable(fired)
  card.STATIONARY = true
  local blocker = blocking_chain(chain_total)
  queue[#queue + 1] = blocker
  NeuroAnim.on_buy(card)
  local wall = (chain_total / speed) + 2.0
  step(wall, speed, function()
    if blocker and G.TIMERS.TOTAL >= blocker.drain_at then
      for i = #queue, 1, -1 do if queue[i] == blocker then table.remove(queue, i) end end
      blocker = nil
    end
  end)
  return #fired
end

do
  reset()
  local fired = {}
  local card = moveable(fired)
  card.STATIONARY = true
  local blocker = { blocking = true, blockable = true }
  queue[#queue + 1] = blocker
  NeuroAnim.on_buy(card)
  step(0.40)
  local early = #fired
  for i = #queue, 1, -1 do if queue[i] == blocker then table.remove(queue, i) end end
  step(0.40)
  check("a stationary card is not juiced while the engine queue is busy (" .. early .. " early)",
    early == 0)
  check("the juice lands once the engine queue drains (" .. #fired .. ")", #fired == 1)
end

for _, speed in ipairs({ 0.5, 1, 2, 4 }) do
  for _, chain in ipairs({ ENGINE_CHAIN_TOTAL_MIN, ENGINE_CHAIN_TOTAL_MAX }) do
    local n = drive_blocked_juice(speed, chain)
    check(string.format(
      "the cashout beat survives a %.2f s TOTAL engine chain at GAMESPEED %s (%d fired)",
      chain, tostring(speed), n), n == 1)
  end
end

do
  local before = fail_count("settle_engine_expired")
  local n = drive_blocked_juice(1, NeuroAnim.engine_settle_budget + 2.0)
  check("a chain past the engine budget drops the beat (" .. n .. ")", n == 0)
  check("and says so (" .. (fail_count("settle_engine_expired") - before) .. ")",
    fail_count("settle_engine_expired") - before == 1)
end

do
  reset()
  local fired = {}
  local card = moveable(fired)
  card.STATIONARY = true
  card.juice = { scale = 0.4 }
  NeuroAnim.on_buy(card)
  step(0.40)
  local clobbers = #fired
  card.juice = nil
  step(0.40)
  check("an in-flight engine juice is never clobbered (" .. clobbers .. " clobbers)",
    clobbers == 0)
  check("our juice fires after the engine's own juice finishes (" .. #fired .. ")", #fired == 1)
end

-- The engine fills the shop areas from an event gated on the shop panel settling (dump
-- game.lua:3265-3351, delay 0.2 on TOTAL), so a fixture that pre-populates them cannot see the race
-- the live path runs. Here the cards arrive late, and late by a different wall amount per speed.
local function shop_beat_at(speed, fill_total)
  reset()
  G.SETTINGS.GAMESPEED = speed
  local fired = {}
  local card = moveable(fired)
  card.STATIONARY = true
  local filled = false
  NeuroAnim.on_shop_enter()
  step((NeuroAnim.shop_fill_budget + 1.0) / speed, speed, function()
    if not filled and G.TIMERS.TOTAL >= fill_total then
      filled = true
      G.shop_jokers = { cards = { card } }
    end
  end)
  return fired[1], #fired
end

for _, speed in ipairs({ 0.5, 1, 2, 4 }) do
  local t, n = shop_beat_at(speed, 0.6)
  check(string.format("the shop entry beat waits for the engine to fill the shop at GAMESPEED %s"
    .. " (%s, n=%d)", tostring(speed), tostring(t), n), n == 1)
end

do
  local before = fail_count("shop_fill_expired")
  local _, n = shop_beat_at(1, 30.0)
  check("a shop that never fills drops the beat (" .. n .. ")", n == 0)
  check("and says so (" .. (fail_count("shop_fill_expired") - before) .. ")",
    fail_count("shop_fill_expired") - before == 1)
end

do
  reset()
  local order = {}
  local cards = {}
  for i = 1, 5 do
    local idx = i
    cards[i] = { STATIONARY = false,
      juice_up = function() order[#order + 1] = idx end }
  end
  G.shop_jokers = { cards = cards }
  NeuroAnim.on_shop_enter()
  step(0.50)
  for _, c in ipairs(cards) do c.STATIONARY = true end
  step(1.50)
  local monotone = #order == 5
  for i = 2, #order do if order[i] <= order[i - 1] then monotone = false end end
  check("the entry ripple keeps its left-to-right order (" .. table.concat(order, ",") .. ")",
    monotone)
end

do
  reset()
  local hits = {}
  local cards = {}
  for i = 1, 3 do
    cards[i] = { STATIONARY = true, juice_up = function(self) hits[self] = (hits[self] or 0) + 1 end }
  end
  G.shop_jokers = { cards = cards }
  NeuroAnim.on_shop_enter()
  step(1.5)
  NeuroAnim.on_shop_enter()
  step(1.5)
  NeuroAnim.on_shop_enter()
  step(1.5)
  local total = 0
  for _, n in pairs(hits) do total = total + n end
  check("three shop entries juice each card once (" .. total .. " of 3)", total == 3)
end

do
  reset()
  local fired = {}
  local card = moveable(fired)
  card.highlighted = true
  local bp = { cards = { card }, remove_from_highlighted = function() end }
  NeuroAnim.pick_pack_card(card, bp)
  check("a successful remove_from_highlighted is not followed by a raw highlight write",
    card.highlighted == true)

  reset()
  local fired2 = {}
  local card2 = moveable(fired2)
  card2.highlighted = true
  local bad = { cards = { card2 }, remove_from_highlighted = function() error("boom") end }
  NeuroAnim.pick_pack_card(card2, bad)
  check("a failing remove_from_highlighted still clears the flag", card2.highlighted == false)

  reset()
  local fired3 = {}
  local card3 = moveable(fired3)
  card3.highlighted = true
  NeuroAnim.pick_pack_card(card3, { cards = { card3 } })
  check("a pack area without remove_from_highlighted still clears the flag",
    card3.highlighted == false)
end

do
  local src = io.open("render/neuro-anim.lua", "r"):read("a")
  local function body(fn_name)
    local a = src:find("function NeuroAnim%." .. fn_name)
    if not a then return "" end
    local b = src:find("\nend", a) or #src
    return src:sub(a, b)
  end

  local pick = body("pick_pack_card")
  local hover = body("hover_pack_card")
  check("pick_pack_card emits no caption",
    pick ~= "" and not pick:find("float_text", 1, true))
  check("hover_pack_card emits no caption",
    hover ~= "" and not hover:find("float_text", 1, true))
end

do
  local ENGINE_JUICE_S = 0.4
  local ENGINE_FLIGHT_S = 0.25
  local GateClocks = require("core.gate_clocks")
  local card_b = NeuroAnim.card_settle_budget
  local engine_b = NeuroAnim.engine_settle_budget
  local poll = NeuroAnim.settle_poll

  check(string.format("the card half covers the spring motion it waits on (%.2f >= %.2f s REAL)",
    card_b, ENGINE_JUICE_S + ENGINE_FLIGHT_S), card_b >= ENGINE_JUICE_S + ENGINE_FLIGHT_S)
  check(string.format("the card half does not outlive the action it decorates (%.2f <= 2.0 s)",
    card_b), card_b <= 2.0)
  check(string.format("the engine half covers the chain it waits on (%.2f >= %.2f s TOTAL)",
    engine_b, ENGINE_CHAIN_TOTAL_MAX), engine_b >= ENGINE_CHAIN_TOTAL_MAX)
  check("the card half is measured on REAL, where the springs run",
    GateClocks.clock_of("anim_card_beat") == "REAL")
  check("the engine half is measured on TOTAL, where the queue runs",
    GateClocks.clock_of("anim_engine_settle") == "TOTAL")
  check("choreography that precedes a commit is measured on the commit's clock",
    GateClocks.clock_of("anim_commit_lead") == "TOTAL")
  check(string.format("the settle poll is finer than the tightest stagger (%.3f <= %.3f)",
    poll, NeuroAnim.Motion.STAGGER_TIGHT), poll <= NeuroAnim.Motion.STAGGER_TIGHT)
  check(string.format("settle polling is bounded by a finite deadline (%.2f s TOTAL, %.3f s poll)",
    engine_b, poll), engine_b > 0 and poll > 0)
end

done()
