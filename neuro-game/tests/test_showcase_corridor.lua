
-- The centre corridor drains against ONE budget for the whole backlog: the engine hands several
-- cards over in a single frame (dump card.lua:2901-2914 Riff-raff, game.lua:552,554 The Emperor /
-- High Priestess), and the blind is being played underneath while it presents them.

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
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SELECTING_HAND", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 0, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {}, hands = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 },
  STATE = 1, STATES = { SELECTING_HAND = 1, MENU = 2, GAME_OVER = 4, SHOP = 5 },
  STAGE = 2, STAGES = { MAIN_MENU = 1, RUN = 2 },
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("showcase corridor scheduler")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local S = require("hud.state")
local Showcase = require("hud.showcase")
local Utils = require("util.utils")

local DT = 1 / 60
local next_id = 0
local function joker_card(name)
  next_id = next_id + 1
  return {
    config = { center = { key = "j_" .. next_id, set = "Joker", name = name,
      loc_txt = { name = name }, rarity = 1 } },
    ability = { name = name, set = "Joker" },
    sort_id = next_id, cost = 4,
  }
end

local function reset()
  Showcase.reset_run_state()
  G.NEURO.purchase_showcase_queue = {}
  G.NEURO.state = "SELECTING_HAND"
  G.jokers = area({})
  Showcase.update_joker(0)   -- seed the ref diff on an empty row
end

local function occupancy(n)
  reset()
  local cards = {}
  for i = 1, n do cards[i] = joker_card("Gain " .. i) end
  G.jokers.cards = cards
  local now, busy_until = DT, nil
  Showcase.update_joker(now)
  while now < 60 do
    now = now + DT
    Showcase.update_joker(now)
    if S.joker_showcase ~= nil or #S.joker_showcase_q > 0 then busy_until = now else break end
  end
  return (busy_until or DT) - DT
end

local BUDGET = Showcase.JOKER_SHOWCASE_BUDGET
local SPAN = Showcase.JOKER_SHOWCASE_DURATION

do
  local one = occupancy(1)
  check("1a a single gain still gets its full span",
    math.abs(one - SPAN) <= 3 * DT, tostring(one))
  for _, n in ipairs({ 2, 3, 5 }) do
    local occ = occupancy(n)
    check(("1b %d gains in one frame cost one budget, not %d spans"):format(n, n),
      occ <= BUDGET + 3 * DT, tostring(occ))
    check(("1c %d gains are still each given the floor"):format(n),
      occ >= math.min(BUDGET, n * Showcase.JOKER_SHOWCASE_MIN) - 3 * DT, tostring(occ))
  end
end

do
  reset()
  G.NEURO.state = "BUFFOON_PACK"
  local cards = {}
  for i = 1, 14 do cards[i] = joker_card("Pack gain " .. i) end
  G.jokers.cards = cards
  Showcase.update_joker(DT)
  check("2a an in-pack gain queues on the pack side", #S.pack_gained_q > 0, #S.pack_gained_q)
  check("2b and the pack side is capped like every other queue",
    #S.pack_gained_q == Showcase.SHOWCASE_QUEUE_CAP, #S.pack_gained_q)
  check("2c overflow there is observable, not silent",
    Utils.diag_once("showcase_queue_overflow", "probe") == false)
  check("2d and degrading: the surviving head stands for the ones it swallowed",
    (S.pack_gained_q[1].merged or 0) == 14 - Showcase.SHOWCASE_QUEUE_CAP,
    S.pack_gained_q[1].merged)

  reset()
  local before = {}
  for i = 1, 14 do before[i] = joker_card("Before pack " .. i) end
  G.jokers.cards = before
  Showcase.update_joker(DT)
  check("2e precondition: the corridor queue is already at the cap",
    #S.joker_showcase_q == Showcase.SHOWCASE_QUEUE_CAP - 1, #S.joker_showcase_q)
  G.NEURO.state = "BUFFOON_PACK"
  for i = 1, 14 do G.jokers.cards[#G.jokers.cards + 1] = joker_card("In pack " .. i) end
  Showcase.update_joker(2 * DT)
  G.NEURO.state = "SELECTING_HAND"
  Showcase.update_joker(3 * DT)
  check("2e2 the flush re-applies the cap instead of appending past it",
    #S.joker_showcase_q <= Showcase.SHOWCASE_QUEUE_CAP, #S.joker_showcase_q)
  local occ, now = nil, 3 * DT
  while now < 120 do
    now = now + DT
    Showcase.update_joker(now)
    if S.joker_showcase == nil and #S.joker_showcase_q == 0 then occ = now break end
  end
  check("2f so 28 gains cannot buy a minute and a half of presentation",
    occ ~= nil and occ <= BUDGET + SPAN + 10 * DT, tostring(occ))
end

do
  reset()
  G.jokers.cards = { joker_card("Blueprint") }
  Showcase.update_joker(DT)
  check("3a fixture: the corridor owns a card", S.joker_showcase ~= nil)
  G.NEURO.state = "TAROT_PACK"          -- the pack cinematic owns the stage
  S.pack_claim_at = DT
  Showcase.enqueue_purchase({ card = joker_card("Picked"), name = "Picked", cost = 0,
    area = "booster_pick", at = DT })
  local now = DT
  for _ = 1, 4 do now = now + DT; Showcase.update_joker(now) end
  local out_at = S.joker_showcase and S.joker_showcase._out_at
  check("3b a condemned receipt never shortens the showcase it cannot displace",
    out_at ~= nil and out_at > Showcase.JOKER_SHOWCASE_MIN, tostring(out_at))
  local last
  while now < 30 do
    now = now + DT
    Showcase.update_joker(now)
    if S.joker_showcase == nil then last = now break end
  end
  check("3c so the showcase keeps its span rather than being cut to the floor",
    last ~= nil and (last - DT) > SPAN - 4 * DT, tostring(last and (last - DT)))
end

do
  reset()
  G.NEURO.state = "SHOP"
  G.jokers.cards = { joker_card("Blueprint") }
  Showcase.update_joker(DT)
  Showcase.enqueue_purchase({ card = joker_card("Baron"), name = "Baron", cost = 4,
    area = "shop_jokers", at = DT })
  local now, last = DT, nil
  while now < 30 do
    now = now + DT
    Showcase.update_joker(now)
    if S.joker_showcase == nil then last = now break end
  end
  check("4a a showable receipt still shortens the showcase to its floor",
    last ~= nil and (last - DT) <= Showcase.JOKER_SHOWCASE_MIN
      + Showcase.JOKER_SHOWCASE_FADE_OUT + 3 * DT, tostring(last and (last - DT)))
end

done()
