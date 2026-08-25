
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local RECTS = {}
local record_rect = require("tests.helpers").rect_recorder(function() return RECTS end)
local IMG = { getWidth = function() return 64 end, getHeight = function() return 64 end,
  getDimensions = function() return 64, 64 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  rectangle = record_rect,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "TAROT_PACK", enabled = true,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, pack_choices = 1, round = 1, round_resets = { ante = 1 },
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

local check, done = require("tests.helpers").harness("pack claim")

local Pack = require("render.panels.pack")
local NeuroAnim = require("render.neuro-anim")
local HudState = require("hud.state")

G.ASSET_ATLAS.FIX71 = { image = IMG, px = 71, py = 95 }
G.ASSET_ATLAS.centers = G.ASSET_ATLAS.FIX71

local function CLR() return { 0.6, 0.6, 0.6, 1 } end
local PAL = setmetatable({}, { __index = function() return CLR() end })
local function id(x) return x or 0 end

local function make_card(i)
  return {
    config = { center = { key = "c_fool_" .. i, set = "Tarot", atlas = "FIX71",
      pos = { x = 0, y = 0 }, name = "Card " .. i } },
    ability = { set = "Tarot" }, cost = 3,
  }
end

local function pack_rows_from(cards, sn)
  local rows = { title = "Pack", picks_left = G.GAME.pack_choices, total = #cards,
    pg = CLR(), cards = {} }
  for i, c in ipairs(cards) do
    if not HudState.pack_card_indices[c] then HudState.pack_card_indices[c] = i end
    rows.cards[#rows.cards + 1] = { card = c, name = "Card " .. i, badges = {}, desc = "",
      rc = CLR(), index = HudState.pack_card_indices[c] }
  end
  rows.sn = sn
  return rows
end

local function ctx_for(cards, t, sn)
  local theme = {
    p = CLR(), pg = CLR(), bg = CLR(), ACC = CLR(), FR = CLR(), FRD = CLR(),
    ROW = CLR(), SEL = CLR(), ORANGE = CLR(), GREEN = CLR(), DIM = CLR(),
    WHITE = CLR(), CYAN = CLR(), GOLD = CLR(), _pal = PAL,
    persona_evil = false, persona_neuro = false, persona_name = "Hiyori", pk = "hiyori",
    boss = false, is_round_eval = false,
    rfont_title = FONT, rfont_display = FONT, lfont_title = FONT, font_title = FONT,
    font_display = FONT, font = FONT, panel_font_small = FONT, rfont = FONT,
    rfont_small = FONT, lfont = FONT, lfont_small = FONT, rp_font = FONT,
  }
  return {
    theme = theme,
    motion = { now = t, pulse = 0.5, dt = 0.016, shimr = 0.5, shimg = 0.5, shimb = 0.5 },
    metrics = {
      rn = id, ln = id, cn = id, rp_sh = 1, lp_sh = 1, sw = 1920, sh = 1080, U = 6,
      GUT = 12, PAD_TOP = 8, ACCENT_W = 3, TRACK = 1, TRACK_SM = 1,
      r_text_h = 12, r_small_text_h = 10,
      c_text_h = 12, c_small_text_h = 10, text_h = 12,
    },
    data = { sn = sn, state_name = sn, pack_rows = pack_rows_from(cards, sn) },
    draw = {
      trunc = function(s) return s end,
      wrapped_lines = function(s) return { s } end,
      draw_colored_desc = noop, row_h = function() return 16 end,
      draw_desc_lines = noop, print_colored_desc = noop,
      showcase_type_colors = function() return CLR(), CLR() end,
    },
    center_top_y = 8,
  }
end

local function reset_pack_state()
  HudState.pack_collapse_t, HudState.pack_collapse_snap = nil, nil
  HudState.pack_collapse_req, HudState.pack_collapse_done = nil, nil
  HudState.pack_losers, HudState.pack_disp = nil, nil
  HudState.pack_leave_t, HudState.pack_leave_snap, HudState.pack_leave_n = nil, nil, nil
  HudState.pack_last_sn, HudState.pack_appear_t, HudState.pack_hl_t = nil, nil, nil
  HudState.pack_winners = {}
  HudState.pack_card_indices, HudState.pack_hidden_indices = {}, {}
  HudState.pack_initial_count, HudState.pack_hl = 0, false
  HudState.pack_w_hi = nil
  HudState.pack_env_last, HudState.pack_exit_last = nil, nil
end

local function panel_width()
  local w = 0
  for _, r in ipairs(RECTS) do
    if r.mode == "line" and r.w and r.w > w and r.w < 1900 then w = r.w end
  end
  return w
end

local function frame(cards, t, sn)
  RECTS = {}
  G.TIMERS.REAL = t
  local ctx = ctx_for(cards, t, sn or "TAROT_PACK")
  local ok, err = xpcall(function() Pack.draw(ctx) end, debug.traceback)
  return ok, err
end

local function claim(cards, idx, t)
  local card = cards[idx]
  if t then G.TIMERS.REAL = t end
  NeuroAnim.pick_pack_card(card, { cards = cards })
  table.remove(cards, idx)
  G.GAME.pack_choices = math.max(0, G.GAME.pack_choices - 1)
  return card
end

-- Mirrors the engine's final pick: G.GAME.pack_choices is never touched (button_callbacks.lua:2318-2328).
local function claim_final(cards, idx, t)
  local card = cards[idx]
  if t then G.TIMERS.REAL = t end
  NeuroAnim.pick_pack_card(card, { cards = cards })
  table.remove(cards, idx)
  return card
end

do
  reset_pack_state()
  G.GAME.pack_choices = 1
  local cards = { make_card(1), make_card(2), make_card(3) }
  local ok, err = frame(cards, 1.0)
  check("normal pack draws", ok, err)
  claim(cards, 2, 1.1)
  frame(cards, 1.1)
  check("normal pack: claim starts the collapse", HudState.pack_collapse_t ~= nil)
  check("normal pack: collapse takes a snapshot", HudState.pack_collapse_snap ~= nil)
  local snap = HudState.pack_collapse_snap
  check("normal pack: the claim records its own clock",
    HudState.pack_winners[1] and HudState.pack_winners[1].t0 ~= nil)
  check("normal pack: the snapshot freezes the slots",
    snap and snap.slots and #snap.slots == 3, snap and snap.slots and #snap.slots)
  local winner_slot
  for _, sl in ipairs(snap.slots) do if sl.winner then winner_slot = sl end end
  check("normal pack: the winner slot is anointed in the snapshot",
    winner_slot ~= nil and winner_slot.state == "picked")
  frame(cards, 2.1)
  check("normal pack: the crown beat is still on stage at +1.0s",
    HudState.pack_collapse_t ~= nil and HudState.pack_collapse_done ~= true)
end

do
  reset_pack_state()
  G.GAME.pack_choices = 2
  local cards = { make_card(1), make_card(2), make_card(3), make_card(4), make_card(5) }
  local ok, err = frame(cards, 1.0)
  check("mega pack draws", ok, err)
  local w_before = panel_width()
  claim(cards, 2, 1.1)
  frame(cards, 1.1)
  check("mega pack: first claim starts the collapse", HudState.pack_collapse_t ~= nil)
  check("mega pack: first claim takes a snapshot", HudState.pack_collapse_snap ~= nil)

  frame(cards, 2.9)
  frame(cards, 3.0)
  check("mega pack: the pack stays alive for the second pick",
    HudState.pack_collapse_done ~= true, tostring(HudState.pack_collapse_done))
  local w_after = panel_width()
  check("mega pack: the claimed slot is gone, but the envelope holds its width",
    w_after > 0 and w_after == w_before, tostring(w_before) .. " -> " .. tostring(w_after))
end

do
  local source = assert(io.open("render/panels/pack.lua", "r")):read("*all")
  check("pack.lua carries no pack_picked fade bookkeeping",
    source:find("pack_picked", 1, true) == nil)
  check("pack.lua carries no PICK_FADE constants",
    source:find("PICK_FADE", 1, true) == nil)
end

do
  reset_pack_state()
  G.GAME.pack_choices = 2
  local cards = { make_card(1), make_card(2), make_card(3), make_card(4), make_card(5) }
  frame(cards, 1.0)
  claim(cards, 2, 1.1)
  frame(cards, 1.15)
  local first_snap = HudState.pack_collapse_snap
  check("late join: first collapse armed", first_snap ~= nil and first_snap.n_win == 1)
  claim(cards, 3, 1.9)
  frame(cards, 1.95)
  local snap = HudState.pack_collapse_snap
  check("late join: the stage re-freezes for the second winner",
    snap ~= nil and snap ~= first_snap and snap.n_win == 2,
    snap and snap.n_win)
  check("late join: the late claim skips the slot ceremony",
    HudState.pack_winners[2] and HudState.pack_winners[2]._anoint ~= nil
    and HudState.pack_winners[2]._anoint < 0.2,
    HudState.pack_winners[2] and HudState.pack_winners[2]._anoint)
  frame(cards, 2.9)
  check("late join: the panel waits for the late hero",
    HudState.pack_collapse_t ~= nil, tostring(HudState.pack_collapse_t))
  frame(cards, 3.5)
  frame(cards, 3.6)
  check("late join: the collapse eventually resolves", HudState.pack_collapse_t == nil)
end

do
  reset_pack_state()
  G.GAME.pack_choices = 2
  local cards = { make_card(1), make_card(2), make_card(3), make_card(4), make_card(5) }
  frame(cards, 1.0)
  claim(cards, 2, 1.1)
  frame(cards, 1.15)
  local snap1 = HudState.pack_collapse_snap
  check("shrink-claim: first collapse armed", snap1 ~= nil and snap1.n_win == 1)
  local TLsoft = require("render.panels.pack").TIMELINES.soft
  local lm = 0
  for _, sl in ipairs(snap1.slots) do
    local d = require("render.panels.pack").LOSER_D
      + math.abs(sl.rank - snap1.primary_rank) * require("render.panels.pack").LOSER_SPREAD
    if not sl.winner and d > lm then lm = d end
  end
  local shrink_at = 1.1 + TLsoft.ANOINT + math.max(TLsoft.GLIDE, lm)
  local mid_shrink = shrink_at + 0.5 * TLsoft.SHRINK
  frame(cards, mid_shrink - 0.02)
  local w_pending = panel_width()
  check("shrink-claim: the stage never contracts while a pick is still owed",
    w_pending >= snap1.pk_w - 2,
    tostring(w_pending) .. " vs " .. tostring(snap1.pk_w))
  claim(cards, 3, mid_shrink)
  frame(cards, mid_shrink + 0.02)
  local snap2 = HudState.pack_collapse_snap
  check("shrink-claim: the stage re-freezes for the second winner",
    snap2 ~= nil and snap2 ~= snap1 and snap2.n_win == 2, snap2 and snap2.n_win)
  local w_after = panel_width()
  check("shrink-claim: no width snap across the refreeze",
    math.abs(w_after - w_pending) <= 60,
    tostring(w_pending) .. " -> " .. tostring(w_after))
  frame(cards, mid_shrink + 0.6)
  check("shrink-claim: the panel waits for the late hero", HudState.pack_collapse_t ~= nil)
  frame(cards, mid_shrink + 1.6)
  frame(cards, mid_shrink + 1.7)
  check("shrink-claim: the collapse eventually resolves", HudState.pack_collapse_t == nil)
  check("shrink-claim: the pack latches done with no picks left",
    HudState.pack_collapse_done == true, tostring(HudState.pack_collapse_done))
end

do
  reset_pack_state()
  G.GAME.pack_choices = 1
  local cards = { make_card(1), make_card(2) }
  frame(cards, 1.0)
  local w_partial = panel_width()
  cards[3], cards[4], cards[5] = make_card(3), make_card(4), make_card(5)
  frame(cards, 1.05)
  frame(cards, 1.25)
  local w_full = panel_width()
  check("partial first frame does not freeze the panel width",
    w_full > w_partial, tostring(w_partial) .. " -> " .. tostring(w_full))
end

do
  reset_pack_state()
  G.GAME.pack_choices = 1
  local cards = { make_card(1), make_card(2), make_card(3) }
  frame(cards, 1.0)
  local w_before = panel_width()
  claim_final(cards, 2, 1.1)
  frame(cards, 1.1)
  local snap = HudState.pack_collapse_snap
  check("final pick: collapse takes a snapshot", snap ~= nil)
  local TLsoft = Pack.TIMELINES.soft
  local lm = 0
  for _, sl in ipairs(snap.slots) do
    local d = Pack.LOSER_D + math.abs(sl.rank - snap.primary_rank) * Pack.LOSER_SPREAD
    if not sl.winner and d > lm then lm = d end
  end
  local shrink_at = 1.1 + TLsoft.ANOINT + math.max(TLsoft.GLIDE, lm)
  frame(cards, shrink_at + TLsoft.SHRINK + 0.02)
  local w_after = panel_width()
  check("final pick: SHRINK contracts the stage even though the engine still says one pick is owed",
    w_after > 0 and w_after < 0.6 * w_before,
    tostring(w_before) .. " -> " .. tostring(w_after))
  local collapse_end = shrink_at + TLsoft.SHRINK + TLsoft.HOLD + TLsoft.EXIT
  frame(cards, collapse_end + 0.05)
  check("final pick: the claim is terminal",
    HudState.pack_collapse_done == true, tostring(HudState.pack_collapse_done))
  check("final pick: no card is put back on the stage",
    #HudState.pack_winners == 0 and HudState.pack_initial_count ~= 0,
    #HudState.pack_winners .. " / " .. tostring(HudState.pack_initial_count))
end

do
  reset_pack_state()
  G.GAME.pack_choices = 2
  local cards = { make_card(1), make_card(2), make_card(3) }
  frame(cards, 1.0)
  local w_before = panel_width()
  claim_final(cards, 2, 1.1)
  frame(cards, 1.1)
  local snap = HudState.pack_collapse_snap
  local TLsoft = Pack.TIMELINES.soft
  local lm = 0
  for _, sl in ipairs(snap.slots) do
    local d = Pack.LOSER_D + math.abs(sl.rank - snap.primary_rank) * Pack.LOSER_SPREAD
    if not sl.winner and d > lm then lm = d end
  end
  local shrink_at = 1.1 + TLsoft.ANOINT + math.max(TLsoft.GLIDE, lm)
  frame(cards, shrink_at + 0.5 * TLsoft.SHRINK)
  local w_after = panel_width()
  check("a two-pick pack still holds its leftovers",
    HudState.pack_collapse_done ~= true and w_after >= w_before - 2,
    tostring(HudState.pack_collapse_done) .. " w:" .. tostring(w_before) .. "->" .. tostring(w_after))
end

done()
