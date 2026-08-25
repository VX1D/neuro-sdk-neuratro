_G.NEURO_TEST = true  -- reaches module internals published only behind the test seam

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
  NEURO = { persona = "neuro", state = "TAROT_PACK", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 2, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
  play = {},
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })
_G.Event = function(cfg) return cfg end
_G.attention_text = function() end

local check, done = require("tests.helpers").harness("acquire animation diagnostics")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local queued = {}
local function fake_manager()
  queued = {}
  return { add_event = function(_, e) queued[#queued + 1] = e end }
end
local function run_all()
  local i = 1
  while i <= #queued do
    local e = queued[i]
    if e.func then e.func() end
    i = i + 1
  end
end

local NeuroAnim = require("render.neuro-anim")
local HUD = require("render.hud_overlay")
local Utils = require("util.utils")

local function joker_card()
  return {
    config = { center = { key = "j_test", set = "Joker", name = "T", loc_txt = { name = "T" }, rarity = 1 } },
    ability = {},
    cost = 1,
  }
end

local function site_count(name)
  return (NeuroAnim._anim_fails and NeuroAnim._anim_fails[name]) or 0
end

local function hud_count(name)
  return (HUD._pcall_fails and HUD._pcall_fails[name]) or 0
end

local function capture_prints()
  local captured = {}
  local orig = print
  print = function(...) captured[#captured + 1] = table.concat({ ... }, " ") end
  return captured, function() print = orig end
end

local juice_card_1000 = joker_card()
juice_card_1000.juice_up = function() error("forced juice failure") end
juice_card_1000.STATIONARY = true
local captured, restore = capture_prints()
G.E_MANAGER = nil
for i = 1, 1000 do
  NeuroAnim.pick_pack_card(juice_card_1000, { cards = { juice_card_1000 } })
end
restore()
check("1000 repeated juice failures increment the counter", site_count("juice") == 1000,
  site_count("juice"))
check("1000 repeated juice failures log only once", #captured == 1, #captured)

G.E_MANAGER = nil
local juice_card = joker_card()
juice_card.juice_up = function() error("forced juice failure") end
juice_card.STATIONARY = true
NeuroAnim.pick_pack_card(juice_card, { cards = { juice_card } })
check("juice failure increments the neuro-anim juice counter", site_count("juice") == 1001,
  site_count("juice"))

G.E_MANAGER = nil
local rm_card = joker_card()
local rm_bp = { cards = { rm_card }, remove_from_highlighted = function() error("forced unhighlight failure") end }
NeuroAnim.pick_pack_card(rm_card, rm_bp)
check("highlight_remove failure increments its counter", site_count("highlight_remove") == 1,
  site_count("highlight_remove"))
check("highlight_remove failure still falls back to set_highlight", rm_card.highlighted == false,
  tostring(rm_card.highlighted))

G.E_MANAGER = nil
local hl_card = joker_card()
local hl_bp = { cards = { hl_card }, add_to_highlighted = function() error("forced highlight failure") end }
NeuroAnim.hover_pack_card(hl_card, hl_bp)
check("highlight_add failure increments its counter", site_count("highlight_add") == 1, site_count("highlight_add"))

G.E_MANAGER = fake_manager()
G.shop_jokers = { cards = 5 }
G.shop_vouchers = nil
G.shop_booster = nil
NeuroAnim.on_shop_enter()
run_all()
G.shop_jokers = area({})
check("after callback failure increments its counter", site_count("after") == 1, site_count("after"))

G.E_MANAGER = { queues = 5, add_event = function(_, e) queued[#queued + 1] = e end }
queued = {}
local imm_card = joker_card()
imm_card.juice_up = function() end
imm_card.STATIONARY = true
NeuroAnim.on_buy(imm_card)
run_all()
check("immediate callback failure increments its counter", site_count("immediate") == 1, site_count("immediate"))

local bad_width = { getWidth = function() error("forced width failure") end }
captured, restore = capture_prints()
for i = 1, 1000 do
  HUD.trunc("hello world", 4, bad_width)
end
restore()
check("1000 throwing font width calls increment the counter", hud_count("font_width") == 1000,
  hud_count("font_width"))
check("1000 throwing font width calls log only once", #captured == 1, #captured)

local bad_wrap = { getWrap = function() error("forced wrap failure") end }
captured, restore = capture_prints()
for i = 1, 1000 do
  HUD.wrapped_lines("hello world " .. i, 4, bad_wrap)
end
restore()
check("1000 throwing font wrap calls increment the counter", hud_count("font_wrap") == 1000,
  hud_count("font_wrap"))
check("1000 throwing font wrap calls log only once", #captured == 1, #captured)
check("font wrap failure keeps the single-line fallback", HUD.wrapped_lines("hello", 4, bad_wrap)[1] == "hello")

local orig_safe = Utils.safe_description
Utils.safe_description = function() error("forced description failure") end
captured, restore = capture_prints()
for i = 1, 1000 do
  HUD.safe_showcase_desc({ loc_txt = "x" }, joker_card())
end
restore()
Utils.safe_description = orig_safe
check("1000 throwing safe_description calls increment the counter", hud_count("safe_desc") == 1000,
  hud_count("safe_desc"))
check("1000 throwing safe_description calls log only once", #captured == 1, #captured)

check("all instrumented neuro-anim sites are counted", site_count("juice") >= 1
  and site_count("highlight_remove") >= 1 and site_count("highlight_add") >= 1
  and site_count("after") >= 1 and site_count("immediate") >= 1)

do
  local Showcase = require("hud.showcase")
  local S = require("hud.state")
  Showcase.reset_run_state()
  local claimed = joker_card()
  claimed.sort_id = 9001
  G.NEURO = G.NEURO or {}
  G.NEURO.state = "BUFFOON_PACK"
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = G.consumeables or { cards = {}, config = { card_limit = 2 } }
  G.E_MANAGER = fake_manager()

  Showcase.update_joker(0)
  NeuroAnim.pick_pack_card(claimed, { cards = { claimed } })
  run_all()
  G.jokers.cards[1] = claimed
  Showcase.update_joker(0.05)

  check("pick_pack_card files the claim, so the gain scan stays silent",
    S.joker_showcase == nil and #S.joker_showcase_q == 0 and #S.pack_gained_q == 0,
    tostring(S.joker_showcase and S.joker_showcase.label) .. "/"
      .. #S.joker_showcase_q .. "/" .. #S.pack_gained_q)
end

done()
