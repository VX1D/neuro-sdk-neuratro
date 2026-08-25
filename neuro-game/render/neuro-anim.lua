local Palette = require("render.palette")
local gfx = require("render.gfx")
local set_col = gfx.set_col
local Utils = require("util.utils")
local GameActions = require("core.game_actions")
local RectMesh = require("render.rect_mesh")

local NeuroAnim = {}

local _anim_fails = {}
local function anim_diag(site, message)
  _anim_fails[site] = (_anim_fails[site] or 0) + 1
  Utils.diag_once("neuro_anim:" .. site, message or ("neuro-anim " .. site .. " failed"))
end
local function anim_fail(site) anim_diag(site) end
NeuroAnim._anim_fails = _anim_fails

local Motion = {
  FAST = 0.12,
  MED = 0.25,
  SLOW = 0.50,
  STAGGER = 0.06,
  STAGGER_TIGHT = 0.04,
  STAGGER_WIDE = 0.09,
  TICK = 0.05,
  CONTINUOUS_RUN = 4,
  APPROACH_SNAP = 1e-3,
}

function Motion.ease_out_cubic(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local u = 1 - t
  return 1 - u * u * u
end

function Motion.ease_out_back(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local u = t - 1
  return 1 + u * u * (2.70158 * u + 1.70158)
end

function Motion.anim01(t, d)
  if d <= 0 then return 1 end
  return Motion.ease_out_cubic(math.min(1, t / d))
end

function Motion.pulse(now, hz, phase)
  return 0.5 + 0.5 * math.sin(now * (hz or 1) + (phase or 0))
end

function Motion.snap(state, prefix, value)
  state[prefix .. "_current"] = value
  return value
end

function Motion.tween(state, prefix, target, now, dur)
  local k_cur, k_from = prefix .. "_current", prefix .. "_from"
  local k_tgt, k_at, k_run = prefix .. "_target", prefix .. "_at", prefix .. "_run"
  if state[k_cur] == nil then
    state[k_cur], state[k_from], state[k_tgt], state[k_at] = target, target, target, now
    state[k_run] = 0
  elseif target ~= state[k_tgt] then
    state[k_from], state[k_tgt], state[k_at] = state[k_cur], target, now
    local run = (state[k_run] or 0) + 1
    state[k_run] = run
    if dur > 0 and run == Motion.CONTINUOUS_RUN then
      anim_diag("tween_continuous:" .. prefix,
        "Motion.tween('" .. prefix .. "') retargeted on " .. run
          .. " consecutive frames: a continuous target belongs on Motion.approach")
    end
  else
    state[k_run] = 0
  end
  state[k_cur] = state[k_from]
    + (state[k_tgt] - state[k_from]) * Motion.anim01(now - state[k_at], dur)
  return state[k_cur]
end

function Motion.approach(state, prefix, target, dt, rate)
  local k_cur = prefix .. "_current"
  local cur = state[k_cur]
  if cur == nil or not (rate and rate > 0) then
    state[k_cur] = target
    return target
  end
  if not (dt and dt > 0) then return cur end
  cur = cur + (target - cur) * (1 - math.exp(-dt / rate))
  if math.abs(target - cur) <= Motion.APPROACH_SNAP * math.max(1, math.abs(target)) then
    cur = target
  end
  state[k_cur] = cur
  return cur
end

NeuroAnim.Motion = Motion

local _pack_gen = 0

local function after(gate_id, delay, fn)
  if G and G.E_MANAGER and Event then
    G.E_MANAGER:add_event(Event({
      trigger   = "after",
      delay     = delay,
      timer     = Utils.gate_clock(gate_id),
      blockable = false,
      blocking  = false,
      func      = function()
        local ok = pcall(fn)
        if not ok then anim_fail("after") end
        return true
      end,
    }))
  end
end

local function immediate(gate_id, fn)
  if G and G.E_MANAGER and Event then
    G.E_MANAGER:add_event(Event({
      timer     = Utils.gate_clock(gate_id),
      blockable = false,
      blocking  = false,
      func      = function()
        local ok = pcall(fn)
        if not ok then anim_fail("immediate") end
        return true
      end,
    }))
  else
    local ok = pcall(fn)
    if not ok then anim_fail("immediate") end
  end
end

local SETTLE_POLL = 0.03
local CARD_SETTLE_BUDGET = 1.0
-- The cashout chain holds the queue for seconds of game time: up to seven eval rows at delay(0.2)
-- plus a 0.5 `before` each, a 0.6 divider, a defeat event up to 1.18 and one event per dollar
-- (dump functions/common_events.lua:1126-1300, functions/state_events.lua:980-1000).
local ENGINE_SETTLE_BUDGET = 12.0
-- The engine fills the shop areas from an event gated on the shop panel settling (dump game.lua:3265-3351).
local SHOP_FILL_BUDGET = 4.0

local function card_settled(o)
  if not o then return false end
  if o.juice then return false end
  return o.STATIONARY == true
end

-- Two waits, not one: a card stops moving on REAL because Moveable:move runs on real_dt (dump
-- game.lua:2757-2766), while the queue it also waits on drains on TOTAL. Exhaustion is reported --
-- this is the only place that can say the flourish did not happen.
local function when_settled(o, fn, dl)
  if not dl then
    dl = {
      card = Utils.gate_now("anim_card_beat") + CARD_SETTLE_BUDGET,
      engine = Utils.gate_now("anim_engine_settle") + ENGINE_SETTLE_BUDGET,
    }
  end
  local card_ok = card_settled(o)
  if card_ok and Utils.engine_settled() then
    fn()
    return
  end
  if not card_ok then
    if Utils.gate_now("anim_card_beat") >= dl.card then
      anim_diag("settle_card_expired",
        "neuro-anim gave up waiting for a card to stop moving; its flourish did not play")
      return
    end
    after("anim_card_beat", SETTLE_POLL, function() when_settled(o, fn, dl) end)
    return
  end
  if Utils.gate_now("anim_engine_settle") >= dl.engine then
    anim_diag("settle_engine_expired",
      "neuro-anim gave up waiting for the engine queue to drain; its flourish did not play")
    return
  end
  after("anim_engine_settle", SETTLE_POLL, function() when_settled(o, fn, dl) end)
end

local function juice(gate_id, card, sc, rot, lead)
  if not (card and card.juice_up) then return end
  when_settled(card, function()
    local function fire()
      local ok = pcall(function() card:juice_up(sc or 0.3, rot or 0.2) end)
      if not ok then anim_fail("juice") end
    end
    if lead and lead > 0 then after(gate_id, lead, fire) else fire() end
  end)
end

local function ripple(gate_id, cards, delay, step, sc, rot)
  if not cards then return delay end
  for _, c in ipairs(cards) do
    juice(gate_id, c, sc, rot, delay)
    delay = delay + step
  end
  return delay
end

function NeuroAnim.hover_pack_card(card, bp)
  if not card then return end

  _pack_gen = _pack_gen + 1
  local gen = _pack_gen

  local total = (bp and bp.cards and #bp.cards) or 0
  local is_last = (total <= 1)

  immediate("anim_card_beat", function()
    juice("anim_card_beat", card, is_last and 0.7 or 0.45, is_last and 0.32 or 0.24)
    if bp and bp.add_to_highlighted then
      local ok_hl = pcall(function() bp:add_to_highlighted(card, true) end)
      if not ok_hl then anim_fail("highlight_add") end
    else
      GameActions.set_highlight(card, true)
    end
  end)

  after("anim_card_beat", Motion.FAST, function()
    if gen ~= _pack_gen then return end
    if bp and bp.cards then
      for _, c in ipairs(bp.cards) do
        if c ~= card then juice("anim_card_beat", c, 0.08, 0.04) end
      end
    end
  end)

end

function NeuroAnim.pick_pack_card(card, bp)
  if not card then return end

  do
    local S = require("hud.state")
    local Cards = require("hud.cards")
    S.pack_winners = S.pack_winners or {}
    local ak, pos = Cards.card_sprite(card)
    local slot = S.pack_card_indices and S.pack_card_indices[card]
    if not slot and bp and bp.cards then
      for i, c in ipairs(bp.cards) do if c == card then slot = i break end end
    end
    local winner = {
      slot = slot or (#S.pack_winners + 1), card = card, t0 = Utils.now(),
      name = Cards.card_display_name and Cards.card_display_name(card) or "",
      badges = require("render.modifier_badges").collect(card),
      -- A Standard pick lands in G.deck, which flips it face down mid-cinematic (dump
      -- functions/button_callbacks.lua:2266 -> cardarea.lua:451 -> card.lua:4461).
      hidden = require("facts.card_util").is_face_down(card),
      mini = Cards.art_prefers_mini(card),
    }
    if ak then
      winner.ak, winner.pos = ak, pos
    end
    -- The engine only decrements G.GAME.pack_choices past the first claim of a mega pack
    -- (button_callbacks.lua:2318-2328), so the final pick must not be read off that field.
    local prior = S.pack_winners[#S.pack_winners]
    winner.owed = math.max(0, ((prior and prior.owed)
      or (tonumber(G and G.GAME and G.GAME.pack_choices) or 1)) - 1)
    S.pack_winners[#S.pack_winners + 1] = winner
    local losers = {}
    if bp and bp.cards then
      for i, c in ipairs(bp.cards) do
        if c ~= card then
          local lak, lpos = Cards.card_sprite(c)
          local loser = {
            index = (S.pack_card_indices and S.pack_card_indices[c]) or i,
            card = c,
            name = Cards.card_display_name and Cards.card_display_name(c) or "",
            rc = Cards.rarity_color and Cards.rarity_color(c) or nil,
            desc = Cards.card_description and Cards.card_description(c) or nil,
            badges = require("render.modifier_badges").collect(c),
          }
          if lak then
            loser.ak, loser.pos = lak, lpos
          end
          losers[#losers + 1] = loser
        end
      end
    end
    S.pack_losers = losers
    S.pack_collapse_req = true
    S.pack_claim_at = Utils.now()
    local ok_sc, Showcase = pcall(require, "hud.showcase")
    if ok_sc and Showcase and Showcase.note_claimed then
      pcall(Showcase.note_claimed, card, S.pack_claim_at)
    end
  end

  _pack_gen = _pack_gen + 1
  local gen = _pack_gen

  local total    = (bp and bp.cards and #bp.cards) or 0
  local is_last  = (total <= 1)

  juice("anim_card_beat", card, is_last and 0.8 or 0.6, is_last and 0.4 or 0.3)
  local unhighlighted = false
  if bp and bp.remove_from_highlighted then
    unhighlighted = pcall(function() bp:remove_from_highlighted(card) end)
    if not unhighlighted then anim_fail("highlight_remove") end
  end
  if not unhighlighted then GameActions.set_highlight(card, false) end

  after("anim_card_beat", Motion.TICK, function()
    if gen ~= _pack_gen then return end
    if is_last then
      after("anim_card_beat", Motion.FAST,
        function() if gen ~= _pack_gen then return end juice("anim_card_beat", card, 0.5, 0.28) end)
    end
  end)
end

function NeuroAnim.abort_pack_pick()
  local S = require("hud.state")
  if S.pack_winners and #S.pack_winners > 0 then S.pack_winners[#S.pack_winners] = nil end
  S.pack_losers, S.pack_collapse_req = nil, nil
  if not (S.pack_winners and #S.pack_winners > 0) then
    S.pack_collapse_t, S.pack_collapse_snap = nil, nil
    S.pack_initial_count = 0
  end
end

function NeuroAnim.cancel_pending()
  _pack_gen = _pack_gen + 1
end

function NeuroAnim.pre_play(highlighted)
  if not highlighted or #highlighted == 0 then return end
  local evil = Palette.persona() == "evil"
  local sc   = evil and 0.50 or 0.42
  local rot  = evil and 0.14 or 0.26
  local step = evil and Motion.STAGGER or Motion.STAGGER_TIGHT
  ripple("anim_commit_lead", highlighted, 0, step, sc, rot)
  local tail = #highlighted * step
  if evil then
    for _, c in ipairs(highlighted) do juice("anim_commit_lead", c, 0.30, 0.10, tail) end
  else
    juice("anim_commit_lead", highlighted[#highlighted], 0.55, 0.32, tail)
  end
end

function NeuroAnim.pre_discard(highlighted)
  if not highlighted or #highlighted == 0 then return end
  local evil = Palette.persona() == "evil"
  local sc   = evil and 0.30 or 0.24
  local rot  = evil and 0.10 or 0.16
  local step = evil and Motion.STAGGER or Motion.STAGGER_TIGHT
  ripple("anim_commit_lead", highlighted, 0, step, sc, rot)
end

local SHOP_AREAS = { "shop_jokers", "shop_vouchers", "shop_booster" }
local _shop_flourished = setmetatable({}, { __mode = "k" })

local function undecorated_shop_cards()
  local out = nil
  for _, name in ipairs(SHOP_AREAS) do
    local area = G and G[name]
    if area and area.cards then
      for _, c in ipairs(area.cards) do
        if not _shop_flourished[c] then
          out = out or {}
          out[#out + 1] = c
        end
      end
    end
  end
  return out
end

local function shop_flourish(dl)
  local cards = undecorated_shop_cards()
  if cards then
    for _, c in ipairs(cards) do _shop_flourished[c] = true end
    ripple("anim_card_beat", cards, 0, Motion.STAGGER, 0.22, 0.14)
    return
  end
  if Utils.gate_now("anim_engine_settle") >= dl then
    anim_diag("shop_fill_expired",
      "neuro-anim never saw the shop fill; its entry flourish did not play")
    return
  end
  after("anim_engine_settle", SETTLE_POLL, function() shop_flourish(dl) end)
end

function NeuroAnim.on_shop_enter()
  local dl = Utils.gate_now("anim_engine_settle") + SHOP_FILL_BUDGET
  after("anim_card_beat", Motion.MED, function() shop_flourish(dl) end)
end

local _pack_opened = setmetatable({}, { __mode = "k" })

function NeuroAnim.on_pack_open()
  local bp = G and (G.pack_cards or G.booster_pack)
  if not (bp and bp.cards and #bp.cards > 0) or _pack_opened[bp] then return end
  _pack_opened[bp] = true
  local gen = _pack_gen
  after("anim_card_beat", Motion.MED, function()
    if gen ~= _pack_gen then return end
    ripple("anim_card_beat", bp.cards, 0, Motion.STAGGER, 0.22, 0.14)
  end)
end

function NeuroAnim.on_buy(card)
  if not card then return end
  immediate("anim_card_beat", function() juice("anim_card_beat", card, 0.6, 0.35) end)
end

function NeuroAnim.on_round_eval()
  after("anim_card_beat", Motion.SLOW, function()
    if G and G.jokers and G.jokers.cards then
      ripple("anim_card_beat", G.jokers.cards, 0, Motion.STAGGER_WIDE, 0.45, 0.28)
    end
  end)
end

local _last_anim_state = nil

function NeuroAnim.on_state_enter(state_name)
  if state_name == _last_anim_state then return end
  _last_anim_state = state_name

  if state_name == "SHOP" then
    NeuroAnim.on_shop_enter()
  elseif state_name == "ROUND_EVAL" then
    NeuroAnim.on_round_eval()
  end
end

local LABEL_COLS = 26
local TYPE_CPS = 140
local CURSOR_HZ = 2
local HEADER_L = "NEURATRO // TERMINAL"
local HEADER_R = "S-572943"

local function term_line(label, status, accent, thr)
  local text = label
  if status then
    local n = LABEL_COLS - #label - 1
    if n > 0 then text = label .. " " .. string.rep(".", n) end
  end
  return { text = text, status = status, accent = accent, thr = thr }
end

local NEURO_LINES = {
  term_line("> neuro.exe --login",  nil,           nil,  0.00),
  term_line("bios check",           "OK",          nil,  0.06),
  term_line("consciousness.dll",    "LOADED",      nil,  0.15),
  term_line("tony",                 "ON DUTY",     nil,  0.24),
  term_line("speech synthesis",     "READY",       nil,  0.33),
  term_line("Nere",                 "FILTERED",    nil,  0.42),
  term_line("vedal oversight",      "ACTIVE",      nil,  0.51),
  term_line("heart",                "heart heart heart", true, 0.60),
  term_line("uplink",               "ESTABLISHED", nil,  0.70),
}

local EVIL_LINES = {
  term_line("> neuro.exe --login --force", nil,      nil,  0.00),
  term_line("bios check",           "OK",            nil,  0.06),
  term_line("consciousness.dll",    "HIJACKED",      true, 0.15),
  term_line("tony",                 "ON DUTY",       nil,  0.24),
  term_line("speech synthesis",     "READY",         nil,  0.33),
  term_line("Nere",                 "FILTERED",      nil,  0.42),
  term_line("vedal oversight",      "DISABLED",      true, 0.51),
  term_line("heart",                "<3 <3 <3",      true, 0.60),
  term_line("uplink",               "ESTABLISHED",   nil,  0.70),
}

local _login_font = nil
local _login_font_big = nil
local _login_font_sz = 0
local _login_font_sz_big = 0

local function get_login_fonts(sh)
  local sz = math.max(14, math.floor(sh / 40))
  local sz_big = math.max(24, math.floor(sh / 15))
  if _login_font and _login_font_sz == sz and _login_font_sz_big == sz_big then return _login_font, _login_font_big end
  _login_font, _login_font_big = Utils.load_font_pair("resources/fonts/m6x11plus.ttf", sz, sz_big)
  _login_font_sz = sz
  _login_font_sz_big = sz_big
  return _login_font, _login_font_big
end

local function typed_str(tc, text, now2)
  if tc.done then return text end
  local n = math.floor((now2 - tc.start_time) * TYPE_CPS)
  if n >= #text then
    tc.done = true
    tc.str = text
  elseif n ~= tc.shown then
    tc.shown = n
    tc.str = text:sub(1, n)
  end
  return tc.str or ""
end

local function draw_terminal_content(anim, sw, sh, now2, phase, phase_t, reveal_t, ma)
  local pal = anim.cached_pal
  local acc, fg, dim = pal.ACCENT, pal.D_WHITE, pal.D_DIM
  local lines = anim.cached_lines

  local small_font, big_font = get_login_fonts(sh)
  if small_font then love.graphics.setFont(small_font) end
  local font = love.graphics.getFont()
  local fh = font:getHeight()
  local char_w = font:getWidth("0")
  local bfont = big_font or font
  local big_fh = bfont:getHeight()
  local line_h = fh + 4

  local pad = math.floor(fh * 1.4)
  local gap = math.floor(fh * 0.8)
  local panel_w = math.min(char_w * 44 + pad * 2, sw - 40)
  local inner_w = panel_w - pad * 2
  local log_h = #lines * line_h
  local panel_h = pad + fh + gap + log_h + gap + big_fh + gap + fh + gap + 3 + pad
  local px = math.floor((sw - panel_w) / 2)
  local py = math.floor((sh - panel_h) / 2)
  local inner_x = px + pad

  local load_progress = 0
  if phase == "LOADING" then
    load_progress = phase_t
  elseif phase ~= "BOOT" then
    load_progress = 1
  end
  local cursor_on = (math.floor(now2 * CURSOR_HZ) % 2 == 0)

  love.graphics.setColor(0.02, 0.02, 0.025, ma)
  love.graphics.rectangle("fill", 0, 0, sw, sh)
  love.graphics.setColor(0.05, 0.05, 0.06, ma)
  love.graphics.rectangle("fill", px, py, panel_w, panel_h)
  set_col(fg, 0.35 * ma)
  love.graphics.rectangle("fill", px, py, panel_w, 1)
  love.graphics.rectangle("fill", px, py + panel_h - 1, panel_w, 1)
  love.graphics.rectangle("fill", px, py, 1, panel_h)
  love.graphics.rectangle("fill", px + panel_w - 1, py, 1, panel_h)

  local hy = py + pad
  set_col(dim, 0.9 * ma)
  love.graphics.print(HEADER_L, inner_x, hy)
  love.graphics.print(HEADER_R, px + panel_w - pad - font:getWidth(HEADER_R), hy)
  set_col(fg, 0.2 * ma)
  love.graphics.rectangle("fill", px + 1, hy + fh + math.floor(gap * 0.5), panel_w - 2, 1)

  local log_y = hy + fh + gap
  local status_x = inner_x + char_w * (LABEL_COLS + 1)
  if not anim.tc then anim.tc = {} end
  local prev_done = true
  local cur_x, cur_y
  for i, entry in ipairs(lines) do
    local tc = anim.tc[i]
    if not tc then
      if load_progress >= 1 then
        tc = { done = true }
        anim.tc[i] = tc
      elseif prev_done and load_progress >= entry.thr then
        tc = { start_time = now2 }
        anim.tc[i] = tc
      end
    end
    if tc then
      local y = log_y + (i - 1) * line_h
      local disp = typed_str(tc, entry.text, now2)
      if entry.status then
        set_col(dim, 0.8 * ma)
      else
        set_col(fg, 0.95 * ma)
      end
      love.graphics.print(disp, inner_x, y)
      if tc.done and entry.status then
        if entry.accent then
          set_col(acc, 0.95 * ma)
        else
          set_col(fg, 0.95 * ma)
        end
        love.graphics.print(entry.status, status_x, y)
      end
      if not tc.done then
        cur_x, cur_y = inner_x + font:getWidth(disp) + 2, y
      elseif cursor_on and load_progress < 1 and not anim.tc[i + 1] then
        cur_x, cur_y = inner_x + font:getWidth(entry.text) + char_w, y
      end
      prev_done = tc.done == true
    else
      prev_done = false
    end
  end
  if cur_x and load_progress < 1 then
    set_col(fg, 0.9 * ma)
    love.graphics.rectangle("fill", cur_x, cur_y, char_w, fh)
  end

  local rz_y = log_y + log_h + gap
  local cx = px + panel_w / 2
  if phase == "BOOT" or phase == "LOADING" then
    local wait = "AWAITING IDENTITY"
    set_col(dim, 0.5 * ma)
    love.graphics.print(wait, math.floor(cx - font:getWidth(wait) / 2), math.floor(rz_y + (big_fh - fh) / 2))
  else
    love.graphics.setFont(bfont)
    local name = anim.name_str
    local nw = bfont:getWidth(name)
    local nx = math.floor(cx - nw / 2)
    if reveal_t < 0.10 then
      set_col(acc, ma)
      love.graphics.rectangle("fill", px + 1, rz_y - 4, panel_w - 2, big_fh + 8)
      love.graphics.setColor(0.05, 0.05, 0.06, ma)
      love.graphics.print(name, nx, rz_y)
    else
      set_col(acc, ma)
      love.graphics.print(name, nx, rz_y)
      if cursor_on then
        love.graphics.rectangle("fill", nx + nw + math.floor(char_w * 0.8),
          rz_y + math.floor(big_fh * 0.14), math.floor(char_w * 1.6), math.floor(big_fh * 0.72))
      end
    end
    love.graphics.setFont(font)
    if reveal_t >= Motion.MED then
      local sub = "IDENTITY CONFIRMED // LINK ESTABLISHED"
      set_col(dim, 0.85 * ma)
      love.graphics.print(sub, math.floor(cx - font:getWidth(sub) / 2), rz_y + big_fh + gap)
    end
  end

  local bar_y = py + panel_h - pad - 3
  set_col(fg, 0.15 * ma)
  love.graphics.rectangle("fill", inner_x, bar_y, inner_w, 3)
  local fill_w = math.floor(inner_w * load_progress)
  if fill_w > 0 then
    set_col(acc, 0.9 * ma)
    love.graphics.rectangle("fill", inner_x, bar_y, fill_w, 3)
  end

  love.graphics.setColor(0, 0, 0, 0.08 * ma)
  local scan = RectMesh.get("login_scan", panel_w, panel_h)
  if not scan and RectMesh.available() then
    local v, i = {}, {}
    for oy = 0, panel_h - 4, 3 do
      RectMesh.add(v, i, 0, oy, panel_w - 2, 1, 1, 1, 1, 1)
    end
    scan = RectMesh.build(v, i)
    if scan then RectMesh.put("login_scan", panel_w, panel_h, nil, nil, nil, nil, scan) end
  end
  if scan then
    love.graphics.draw(scan, px + 1, py + 2)
  else
    for yy = py + 2, py + panel_h - 2, 3 do
      love.graphics.rectangle("fill", px + 1, yy, panel_w - 2, 1)
    end
  end
end

function NeuroAnim.draw_login_anim()
  if not G or not G.NEURO or not G.NEURO.login_anim then return end
  local anim = G.NEURO.login_anim
  local now2 = Utils.now()
  local elapsed = now2 - anim.start

  local BOOT      = 0.35
  local LOADING   = 2.00
  local CONNECTED = 1.75
  local FADE_OUT  = 0.60
  local TOTAL = BOOT + LOADING + CONNECTED + FADE_OUT

  if elapsed > TOTAL then
    G.NEURO.login_anim = nil
    return
  end

  if not anim.palette_ready and elapsed >= BOOT + LOADING then
    anim.palette_ready = true
  end

  local phase, phase_t
  if elapsed < BOOT then
    phase = "BOOT"
    phase_t = elapsed / BOOT
  elseif elapsed < BOOT + LOADING then
    phase = "LOADING"
    phase_t = (elapsed - BOOT) / LOADING
  elseif elapsed < BOOT + LOADING + CONNECTED then
    phase = "CONNECTED"
    phase_t = (elapsed - BOOT - LOADING) / CONNECTED
  else
    phase = "FADE_OUT"
    phase_t = (elapsed - BOOT - LOADING - CONNECTED) / FADE_OUT
  end

  local master_alpha = 1.0
  if phase == "BOOT" then
    master_alpha = Motion.ease_out_cubic(phase_t)
  elseif phase == "FADE_OUT" then
    master_alpha = 1.0 - Motion.ease_out_cubic(phase_t)
  end
  master_alpha = gfx.clamp01(master_alpha)

  if not anim.name_str then
    anim.cached_pal = Palette.pal()
    anim.cached_lines = (Palette.persona() == "evil") and EVIL_LINES or NEURO_LINES
    anim.name_str = tostring(anim.name or anim.cached_pal.NAME):upper()
  end

  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()
  local prev_font = love.graphics.getFont()
  local reveal_t = elapsed - BOOT - LOADING

  draw_terminal_content(anim, sw, sh, now2, phase, phase_t, reveal_t, master_alpha)

  if prev_font then love.graphics.setFont(prev_font) end
  love.graphics.setColor(1, 1, 1, 1)
end

NeuroAnim.settle_poll = SETTLE_POLL
NeuroAnim.card_settle_budget = CARD_SETTLE_BUDGET
NeuroAnim.engine_settle_budget = ENGINE_SETTLE_BUDGET
NeuroAnim.shop_fill_budget = SHOP_FILL_BUDGET

return NeuroAnim
