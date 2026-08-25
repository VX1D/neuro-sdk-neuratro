_G.NEURO_TEST = true

love = { timer = { getTime = function() return G.TIMERS.REAL end } }
_G.G = {
  NEURO = {}, FUNCS = {}, GAME = { dollars = 20, current_round = {} },
  TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = { GAMESPEED = 1 }, SPEEDFACTOR = 1,
  STATES = { SHOP = 5 }, STATE = 5,
  shop_jokers = { cards = {}, config = { card_limit = 4 } },
}
_G.SMODS = { Mods = {} }

local queued = {}
local pending = {}
_G.Event = function(cfg)
  cfg.timer = cfg.timer or "TOTAL"
  return cfg
end
G.E_MANAGER = {
  add_event = function(_, e)
    e.fires_at = G.TIMERS[e.timer] + (e.delay or 0)
    queued[#queued + 1] = e
    pending[#pending + 1] = e
  end,
}

local check, done = require("tests.helpers").harness("buy clock")
local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)
local Staging = require("core.staging")
local Dispatcher = require("core.dispatcher")

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local Utils = require("util.utils")
local function commit_beat()
  return Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_DELAY")
end

local buy_at
local function reset_world(gamespeed)
  queued, pending, buy_at = {}, {}, nil
  G.SETTINGS.GAMESPEED = gamespeed
  G.SPEEDFACTOR = gamespeed
  G.TIMERS.REAL, G.TIMERS.TOTAL = 0, 0
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
  return card
end

local dispatch_at
Staging._test.set_validator(function() return true end)
Staging.set_executor(function(msg)
  dispatch_at = G.TIMERS.REAL
  local h = Dispatcher.get_action_handler("buy_from_shop")
  local exec = h and h(msg.data.data)
  if type(exec) == "function" then exec() end
end)

local function drive(seconds)
  local dt = 1 / 60
  for _ = 1, math.floor(seconds / dt) do
    G.TIMERS.REAL = G.TIMERS.REAL + dt
    G.TIMERS.TOTAL = G.TIMERS.TOTAL + dt * G.SPEEDFACTOR
    pcall(Staging.update, dt)
    for i = #pending, 1, -1 do
      local e = pending[i]
      if G.TIMERS[e.timer] >= e.fires_at then
        table.remove(pending, i)
        if e.func then pcall(e.func) end
      end
    end
  end
end

local function stage_buy(gamespeed)
  local card = reset_world(gamespeed)
  dispatch_at = nil
  Staging.queue({ command = "action", data = { id = "buy-" .. tostring(gamespeed),
    name = "buy_from_shop", data = { area = "shop_jokers", index = 1 } } })
  drive(6)
  return card
end

stage_buy(1)
local delayed = {}
for _, e in ipairs(queued) do
  if (e.delay or 0) > 0 then delayed[#delayed + 1] = e end
end
local NeuroAnim = require("render.neuro-anim")
local poll = NeuroAnim.settle_poll
local buy_path, polls = {}, 0
for _, e in ipairs(delayed) do
  if poll and math.abs(e.delay - poll) < 1e-9 then
    polls = polls + 1
  else
    buy_path[#buy_path + 1] = e
  end
end
check("the buy path itself queues exactly two delayed events (" .. #buy_path .. ")",
  #buy_path == 2)
local settle_budget = NeuroAnim.engine_settle_budget
local max_polls = (poll and poll > 0 and settle_budget) and math.ceil(settle_budget / poll) or nil
check("decorative settle polling stays inside the settle deadline (" .. polls .. " of "
  .. tostring(max_polls) .. ")",
  max_polls ~= nil and polls <= max_polls)
delayed = buy_path
check("resolve event runs on the game clock", delayed[1] and delayed[1].timer == "TOTAL",
  delayed[1] and delayed[1].timer)
check("watchdog runs on the game clock", delayed[2] and delayed[2].timer == "TOTAL",
  delayed[2] and delayed[2].timer)
check("resolve delay is the commit beat in game-clock seconds",
  delayed[1] and near(delayed[1].delay, commit_beat()),
  delayed[1] and delayed[1].delay)
check("watchdog delay is the commit beat plus its grace",
  delayed[2] and near(delayed[2].delay, commit_beat()
    + Utils.gate_seconds("shop_buy_watchdog_grace", "NEURO_SHOP_BUY_WATCHDOG_GRACE")),
  delayed[2] and delayed[2].delay)
check("the engine buy actually ran", buy_at ~= nil)

local function expected_buy_at()
  return Config.get("NEURO_HOVER_SHOP") * Config.get("NEURO_SPEED_MULT") + commit_beat()
end

check("the buy lands one shop hover plus the commit beat after staging",
  buy_at ~= nil and near(buy_at, expected_buy_at(), 1 / 15), buy_at)

Config.set("NEURO_HOVER_USE", 3.0)
stage_buy(1)
check("the buy clock ignores the card-use hover",
  buy_at ~= nil and near(buy_at, expected_buy_at(), 1 / 15), buy_at)
Config.reset("NEURO_HOVER_USE")

Config.set("NEURO_HOVER_SHOP", 1.2)
stage_buy(1)
check("the buy clock follows the shop hover",
  buy_at ~= nil and near(buy_at, expected_buy_at(), 1 / 15), buy_at)
Config.reset("NEURO_HOVER_SHOP")
stage_buy(1)

local SPEEDS = { 0.5, 1, 2, 4 }
local gaps, game_gaps = {}, {}
for _, gs in ipairs(SPEEDS) do
  stage_buy(gs)
  gaps[#gaps + 1] = (buy_at and dispatch_at) and (buy_at - dispatch_at) or -1
  game_gaps[#game_gaps + 1] = gaps[#gaps] >= 0 and gaps[#gaps] * gs or -1
end
local commit = commit_beat()

local ENGINE_LIFT_S, LIFT_FRAC, HOVER_FLOOR_S = 0.4, 0.65, 0.25
local function shop_hover(gs)
  return math.max(Config.get("NEURO_HOVER_SHOP") * Config.get("NEURO_SPEED_MULT"), HOVER_FLOOR_S * gs)
end
local function lift_ends_at(gs) return LIFT_FRAC * shop_hover(gs) + ENGINE_LIFT_S * gs end
local function expected_commit(gs)
  return math.max(commit, ENGINE_LIFT_S * gs - (1 - LIFT_FRAC) * shop_hover(gs))
end

for i, gs in ipairs(SPEEDS) do
  check("dispatch-to-buy gap is the commit beat floored by the lift at gamespeed " .. tostring(gs),
    game_gaps[i] >= 0 and near(game_gaps[i], expected_commit(gs), 1 / 30), game_gaps[i])
  check("the click never lands inside the card lift at gamespeed " .. tostring(gs),
    game_gaps[i] >= 0 and (shop_hover(gs) + game_gaps[i]) >= lift_ends_at(gs) - 1 / 30,
    tostring(shop_hover(gs) + game_gaps[i]) .. " vs " .. tostring(lift_ends_at(gs)))
end
check("at 1x and below the beat already clears the lift, so the floor adds nothing",
  near(game_gaps[1], commit, 1 / 30) and near(game_gaps[2], commit, 1 / 30),
  tostring(game_gaps[1]) .. " " .. tostring(game_gaps[2]))
check("a fast game still spends less wall time on the commit than a 1x game (#133 survives)",
  gaps[4] >= 0 and gaps[2] >= 0 and gaps[4] < gaps[2],
  tostring(gaps[4]) .. " vs " .. tostring(gaps[2]))

done()
