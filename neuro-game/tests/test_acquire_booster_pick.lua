
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
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
  print = record_print,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "TAROT_PACK", enabled = true,
    purchase_showcase_queue = {}, last_action_at = 0, run_generation = 1,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 1, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 0 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1 },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("acquire booster pick queue")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local queued_events = {}
_G.Event = function(cfg) return cfg end
G.E_MANAGER = {
  add_event = function(_, e) queued_events[#queued_events + 1] = e end,
}

local Handle = require("handlers.use_card")
local Showcase = require("hud.showcase")
local HudState = require("hud.state")
local Acquire = require("render.panels.acquire")
local DrawAcquire = Acquire.draw

local function joker_card(key, name)
  return {
    config = { center = { key = key, set = "Joker", name = name, loc_txt = { name = name }, rarity = 1 } },
    ability = {},
    cost = 1,
  }
end

local function reset_queue()
  G.NEURO.purchase_showcase_queue = {}
  G.NEURO.last_action_at = 0
  queued_events = {}
  HudState.buy_showcase = nil
  Showcase.reset_run_state()
end

local function run_pick(pack_cards, pick_index, fn_impl, pack_choices, use_event_path)
  reset_queue()
  G.GAME.pack_choices = pack_choices or 1
  G.booster_pack = { cards = pack_cards, config = { card_limit = #pack_cards } }
  G.pack_cards = nil
  G.FUNCS.use_card = fn_impl or function() return true end
  if use_event_path then
    G.E_MANAGER = { add_event = function(_, e) queued_events[#queued_events + 1] = e end }
  else
    G.E_MANAGER = nil
  end
  local exec = Handle.handle_use_card({ area = "booster_pack", index = pick_index })
  if type(exec) ~= "function" then
    return nil, "handle_use_card rejected: " .. tostring(exec)
  end
  exec()
  if use_event_path and #queued_events > 0 then
    for _, e in ipairs(queued_events) do
      if e.func then e.func() end
    end
  end
  return G.NEURO.purchase_showcase_queue or {}
end

local q, err
q = run_pick({ joker_card("j_one", "One") }, 1, nil, 1)
check("1-option pack pick enqueues exactly one receipt", type(q) == "table" and #q == 1, err)
check("1-option pick receipt area is booster_pick", q and q[1] and q[1].area == "booster_pick",
  q and q[1] and q[1].area)
check("1-option pick receipt carries no options payload", q and q[1] and q[1].options == nil)
check("1-option pick receipt carries no selected_index payload", q and q[1] and q[1].selected_index == nil)
check("1-option pick receipt carries no picks_left payload", q and q[1] and q[1].picks_left == nil)

q = run_pick({ joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") }, 1, nil, 2)
check("multi-option FIRST pick enqueues exactly one visible receipt (was booster_choice)",
  type(q) == "table" and #q == 1 and q[1] and q[1].area == "booster_pick",
  q and q[1] and q[1].area)
check("multi-option first pick has no dead payload fields",
  q and q[1] and q[1].options == nil and q[1].selected_index == nil and q[1].picks_left == nil)

q = run_pick({ joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") }, 2, nil, 2)
check("multi-option LAST pick enqueues exactly one visible receipt",
  type(q) == "table" and #q == 1 and q[1] and q[1].area == "booster_pick",
  q and q[1] and q[1].area)

q = run_pick({ joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") }, 1,
  function() error("boom") end, 2)
check("throwing use_card callback enqueues nothing",
  type(q) == "table" and #q == 0, err)

q = run_pick({ joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") }, 1,
  function() return false end, 2)
check("use_card callback returning false enqueues nothing", type(q) == "table" and #q == 0)

q = run_pick({ joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") }, 1, nil, 2, true)
check("event-path multi-option pick enqueues exactly one visible receipt",
  type(q) == "table" and #q == 1 and q[1] and q[1].area == "booster_pick",
  q and q[1] and q[1].area)

reset_queue()
G.GAME.pack_choices = 2
G.booster_pack = { cards = { joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") },
  config = { card_limit = 2 } }
G.FUNCS.use_card = function() return true end
G.E_MANAGER = nil
local rc_exec = Handle.handle_use_card({ area = "booster_pack", index = 1, _action_id = "rc-1" })
local rc = rc_exec()
check("receipt path returns an ActionReceipt", type(rc) == "table" and rc.name == "choose_pack_card",
  tostring(rc))
check("receipt path defers the enqueue until on_applied", #G.NEURO.purchase_showcase_queue == 0,
  tostring(#G.NEURO.purchase_showcase_queue))
rc.on_applied()
q = G.NEURO.purchase_showcase_queue
check("receipt on_applied enqueues exactly one booster_pick",
  type(q) == "table" and #q == 1 and q[1] and q[1].area == "booster_pick",
  q and q[1] and q[1].area)

reset_queue()
G.GAME.pack_choices = 2
G.booster_pack = { cards = { joker_card("j_a", "Alpha"), joker_card("j_b", "Beta") },
  config = { card_limit = 2 } }
G.FUNCS.use_card = function() return true end
G.E_MANAGER = nil
local exec = Handle.handle_use_card({ area = "booster_pack", index = 1 })
exec()
Showcase.update_buy(0.2)
check("a pack claim's receipt never reaches the screen -- the cinematic owns that beat",
  HudState.buy_showcase == nil, HudState.buy_showcase and HudState.buy_showcase.area)
check("and it is dropped, not parked -- a queue entry that never plays would stall card_in_flight",
  #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)

do
  local Q1 = require("hud.showcase")
  reset_queue()
  HudState.buy_showcase = nil
  HudState.pack_claim_at, HudState.pack_collapse_req, HudState.pack_collapse_t = nil, nil, nil
  HudState.pack_winners = {}
  G.NEURO.state = "SHOP"
  Q1.enqueue_purchase({ card = joker_card("j_bp", "Blueprint"), name = "Blueprint",
    cost = 10, area = "shop_jokers", at = 0 })
  Q1.update_buy(0)
  check("cross-cut fixture: a plain receipt owns the stage",
    HudState.buy_showcase and HudState.buy_showcase.area == "shop_jokers")
  Q1.enqueue_purchase({ card = joker_card("j_pk", "Picked"), name = "Picked",
    cost = 0, area = "booster_pick", at = 1.0 })
  G.TIMERS.REAL = 1.0
  Q1.update_buy(1.0)
  check("cross-cut fixture: the swap is armed while the pick may still draw",
    HudState.buy_showcase and HudState.buy_showcase.swap_started == 1.0,
    HudState.buy_showcase and tostring(HudState.buy_showcase.swap_started))
  G.NEURO.state = "TAROT_PACK"
  local seen_forbidden, hard_cut, prev_alpha = false, false, nil
  for i = 0, 180 do
    local now = 1.0 + i * (1 / 60)
    G.TIMERS.REAL = now
    Q1.update_buy(now)
    local sc = HudState.buy_showcase
    if sc and sc.area == "booster_pick" then seen_forbidden = true end
    local a = sc and Q1.buy_alpha(sc, now) or 0
    if prev_alpha and prev_alpha > 0.5 and a == 0 then hard_cut = true end
    prev_alpha = a
  end
  check("a receipt the cinematic owns never reaches the stage through the cross-cut either",
    seen_forbidden == false)
  check("and the receipt it would have displaced is not truncated to nothing", hard_cut == false)
  check("the condemned entry is dropped by the queue, not left to be pulled later",
    #G.NEURO.purchase_showcase_queue == 0, #G.NEURO.purchase_showcase_queue)
  reset_queue()
  G.NEURO.state = "TAROT_PACK"
end

do
  local Q2 = require("hud.showcase")
  reset_queue()
  HudState.buy_showcase = nil
  G.NEURO.state = "SHOP"
  local filed = Q2.enqueue_purchase({ card = joker_card("j_ar", "Arcana Pack"), name = "Arcana Pack",
    cost = 4, area = "shop_booster", at = 0 })
  check("a shop_booster receipt is refused at production time", filed == false)
  check("and never enters the queue at all", #G.NEURO.purchase_showcase_queue == 0,
    #G.NEURO.purchase_showcase_queue)
  Q2.update_buy(0.2)
  check("so nothing can pull it onto the stage later", HudState.buy_showcase == nil,
    HudState.buy_showcase and HudState.buy_showcase.area)
  G.NEURO.state = "TAROT_PACK"
end

do
  local Q3 = require("hud.showcase")
  reset_queue()
  HudState.buy_showcase = nil
  HudState.pack_claim_at, HudState.pack_collapse_req, HudState.pack_collapse_t = nil, nil, nil
  HudState.pack_winners = {}
  G.NEURO.state = "SHOP"
  Q3.enqueue_purchase({ card = joker_card("j_pk2", "Picked"), name = "Picked",
    cost = 0, area = "booster_pick", at = 0 })
  Q3.update_buy(0)
  check("live-suppression fixture: the pick receipt is on the stage",
    HudState.buy_showcase and HudState.buy_showcase.area == "booster_pick")
  G.NEURO.state = "TAROT_PACK"   -- the pack state arrives one frame after the receipt was filed
  local prev, vanished, gone_at = 1, false, nil
  for i = 0, 240 do
    local now = i * (1 / 60)
    G.TIMERS.REAL = now
    Q3.update_buy(now)
    local sc = HudState.buy_showcase
    local a = sc and Q3.buy_alpha(sc, now) or 0
    if prev > 0.05 and a == 0 then vanished = true end
    if sc == nil and not gone_at then gone_at = now end
    prev = a
  end
  check("a live receipt that loses the stage fades out instead of vanishing", vanished == false)
  check("and it is gone within one fade of losing it",
    gone_at ~= nil and gone_at <= Q3.BUY_SHOWCASE_FADE_OUT + 2 / 60, tostring(gone_at))
  reset_queue()
  HudState.buy_showcase = nil
  G.NEURO.state = "TAROT_PACK"
end

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end
local THEME = {
  p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
  ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
  WHITE = CLR(), CYAN = CLR(), GOLD = CLR(), _pal = PAL,
  persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
  rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
  font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
  rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
}
local MOTION = { now = 0.5, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 }
local METRICS = {
  rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 4,
  GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
  p_x = 1500, p_y = 100, p_w = 380, p_pad_x = 12, r_U = 4, r_accw = 3, pw_total = 380,
  total_h = 800, content_w = 356, n_cols = 1, title_h = 40, footer_h = 30,
  rp_text_h = 12, rp_line_h = 16, rp_small_line_h = 12, rp_card_line_h = 28, rp_sep_h = 6,
  r_text_h = 12, r_small_text_h = 10,
  c_text_h = 12, c_small_text_h = 10, line_h = 16, small_line_h = 12, small_text_h = 10,
  card_line_h = 28, sep_h = 6, text_h = 12,
  rp_title_text_h = 14, rp_display_text_h = 18, rp_hdr_line_h = 20,
}
local ctx = {
  theme = THEME, motion = MOTION, metrics = METRICS,
  data = { sn = "TAROT_PACK", state_name = "TAROT_PACK" },
  draw = { trunc = function(s) return s end, wrapped_lines = function() return { "a" } end,
    draw_colored_desc = noop, row_h = function() return 16 end,
    draw_desc_lines = noop, print_colored_desc = noop,
    showcase_type_colors = function() return CLR(), CLR() end },
  center_top_y = 8,
}
PRINTED = {}
local ok_sup, sup_err = xpcall(function() DrawAcquire(ctx) end, debug.traceback)
check("a suppressed pick draws without error", ok_sup, sup_err)
check("a suppressed pick takes no room in the centre stack", ctx.center_top_y == 8, ctx.center_top_y)
check("and prints no verb", table.concat(PRINTED, ""):find("PICKED", 1, true) == nil,
  table.concat(PRINTED, ""))

local Q0 = require("hud.showcase")
reset_queue()
HudState.buy_showcase = nil
HudState.pack_claim_at = nil
HudState.pack_collapse_req, HudState.pack_collapse_t = nil, nil
HudState.pack_winners = {}
G.NEURO.state = "SHOP"
Q0.enqueue_purchase({ card = joker_card("j_pick", "Picked"), name = "Picked",
  cost = 0, area = "booster_pick", at = 0 })
Q0.update_buy(0.2)
check("off the pack stage the same receipt is pulled normally",
  HudState.buy_showcase and HudState.buy_showcase.area == "booster_pick",
  HudState.buy_showcase and HudState.buy_showcase.area)
ctx.data.sn, ctx.data.state_name = "SHOP", "SHOP"
ctx.center_top_y = 8
PRINTED = {}
local ok_draw, draw_err = xpcall(function() DrawAcquire(ctx) end, debug.traceback)
check("booster_pick receipt draws without error", ok_draw, draw_err)
check("booster_pick receipt advances the center stack", ctx.center_top_y > 8, ctx.center_top_y)
local picked_text = table.concat(PRINTED, "")
check("booster_pick receipt prints the PICKED label", picked_text:find("PICKED", 1, true) ~= nil)
G.NEURO.state = "TAROT_PACK"

local Q = require("hud.showcase")
reset_queue()
Q.enqueue_purchase({ card = joker_card("j_legacy", "Legacy"), name = "Legacy",
  desc = "-", cost = 0, area = "booster_choice", at = 0 })
Showcase.update_buy(0.5)
local ctx_legacy = ctx
ctx_legacy.motion = { now = 0.7, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 }
ctx_legacy.center_top_y = 8
PRINTED = {}
local ok_legacy, legacy_err = xpcall(function() DrawAcquire(ctx_legacy) end, debug.traceback)
check("a legacy booster_choice-tagged receipt is still rendered (no invisible slot)",
  ok_legacy and ctx_legacy.center_top_y > 8, legacy_err)

done()
