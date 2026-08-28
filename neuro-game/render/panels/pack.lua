local H = require("render.hud_shared")
local Prims, S, Motion = H.Prims, H.S, H.Motion
local round = Prims.round
local clamp, clamp01 = Prims.clamp, Prims.clamp01
local smoothstep01 = Prims.smoothstep01
local set_col, shadow_text = H.set_col, H.shadow_text
local push_clip, pop_clip = H.push_clip, H.pop_clip
local draw_card_mini, card_dimensions = H.draw_card_mini, H.card_dimensions

local function frame_fit(nominal, measured)
  if measured and measured > 0 and measured < nominal then return measured end
  return nominal
end
local frame_w = frame_fit
local layout_modifier_badges, draw_modifier_badges = H.layout_modifier_badges, H.draw_modifier_badges
local Cards = require("hud.cards")
local art_prefers_mini = Cards.art_prefers_mini
local Episode = require("hud.episode")
local PACK_CARD_APPEAR_D = H.PACK_CARD_APPEAR_D
local is_face_down = require("facts.card_util").is_face_down

local SIZING = {   -- cn units
  SP_MAX = 118, SP_MIN = 70, SLOT_PAD = 12,
  PANEL_PAD = 10, SLOT_GAP = 6,
  HERO_SCALE = 1.42, HERO_GAP = 18, ENV_PAD = 16,
  SP_ASPECT = 0.747, SP_DY = 6,
  EXIT_LIFT = 24, CLIP_PAD = 4, CLIP_TAIL = 28,
}

local function beats(t)
  t.REST = t.GLIDE + t.SHRINK + t.HOLD + t.EXIT
  t.TOTAL = t.ANOINT + t.REST
  return t
end

local TIMELINES = {
  soft    = beats({ ANOINT = 0.18, GLIDE = 0.40, CROWN = 0.28, SHRINK = 0.26, HOLD = 0.12, EXIT = 0.40, FOLD = 0.18 }),
}

local ANOINT_LATE = 0.08
local LOSER_D = 0.30
local LOSER_SPREAD = 0.11
local CROWN_LEAD = 0.85
local REFREEZE_D = 0.20
local PLUNGE_D = 0.15

local _hooks = {}
local function persona_hooks(pk)
  if pk == nil then return nil end
  local h = _hooks[pk]
  if h == nil then
    local ok, mod = pcall(require, "render.panels.pack_" .. tostring(pk))
    h = (ok and type(mod) == "table") and mod or false
    if h and h.TL and not h.TL.TOTAL then beats(h.TL) end
    if h and h.TL then TIMELINES[pk] = h.TL end
    _hooks[pk] = h
  end
  return h or nil
end
persona_hooks("evil")

local function center_badge_rows(layout, width)
  for _, item in ipairs(layout.items) do
    item.x = item.x + math.floor((width - (layout.row_widths[item.row] or width)) / 2)
  end
  return layout
end

local function by_pack_index(a, b) return (a.index or 0) < (b.index or 0) end

local _disp_pool = {}
local EMPTY_BADGES = {}
local function pooled(pool, n)
  local t = pool[n]
  if not t then t = {}; pool[n] = t end
  return t
end

local HCTX, GG, SG, HG = {}, {}, {}, {}
local FRAME_OPTS = { skip_body = true, quiet = true }
local DISSOLVE_A, DISSOLVE_B = { 0.95, 0.82, 0.35, 1 }, { 0.85, 0.60, 0.20, 1 }

local function reset_pack_state()
  S.pack_last_sn = nil
  S.pack_appear_t = 0
  S.pack_card_indices = {}
  S.pack_hidden_indices = {}
  S.pack_initial_count = 0
  S.pack_hl = false
  S.pack_hl_t = 0
  S.pack_leave_t = nil
  S.pack_leave_snap = nil
  S.pack_leave_n = 0
  S.pack_w_hi = nil
  S.pack_claim_at = nil
  S.pack_winners = {}
  S.pack_collapse_t = nil
  S.pack_collapse_snap = nil
  S.pack_collapse_req = nil
  S.pack_collapse_done = nil
  S.pack_losers = nil
  S.pack_exit_last = nil
  S.pack_env_last = nil
  S.pack_h_last = nil
  S.pack_settle_t = nil
  S.pack_settle_env = nil
  S.pack_settle_h = nil
  S.pack_disp = nil
end

local function neutral_slot(h, sg, st, scan)
  local cn = h.cn
  local CYAN = h.CYAN
  if st == "picked" then
    set_col(h.GOLD, 0.18 * sg.a)
    love.graphics.rectangle("fill", sg.x, sg.y, sg.w, sg.h)
    set_col(h.GOLD, (0.70 + 0.12 * scan) * sg.a)
    love.graphics.setLineWidth(cn(2))
    love.graphics.rectangle("line", sg.x, sg.y, sg.w, sg.h)
  elseif st == "highlighted" then
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], (0.12 + 0.05 * scan) * sg.a)
    love.graphics.rectangle("fill", sg.x, sg.y, sg.w, sg.h)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], (0.75 + 0.15 * scan) * sg.a)
    love.graphics.setLineWidth(cn(2))
    love.graphics.rectangle("line", sg.x, sg.y, sg.w, sg.h)
    set_col(h.WHITE, (0.18 + 0.10 * scan) * sg.a)
    love.graphics.setLineWidth(cn(1))
    love.graphics.rectangle("line", sg.x + 2, sg.y + 2, sg.w - 4, sg.h - 4)
    Prims.photo_corners(sg.x, sg.y, sg.w, sg.h, CYAN, (0.80 + 0.15 * scan) * sg.a, cn(11))
  else
    set_col(h.FRD, 0.45 * sg.a)
    love.graphics.rectangle("fill", sg.x, sg.y, sg.w, sg.h, cn(3), cn(3))
    set_col(sg.rc, (0.30 + 0.10 * h.pulse) * sg.a)
    love.graphics.setLineWidth(cn(1))
    love.graphics.rectangle("line", sg.x, sg.y, sg.w, sg.h, cn(3), cn(3))
  end
end

local function neutral_mark(h, sg, _, bob)
  local cn = h.cn
  local dpy = sg.y - cn(7) + bob
  set_col(h.CYAN, (0.85 + 0.15 * sg.scan) * sg.a)
  love.graphics.polygon("fill", sg.cx - cn(3), dpy, sg.cx, dpy - cn(3), sg.cx + cn(3), dpy, sg.cx, dpy + cn(3))
end

local function neutral_claim(h, sg, pe)
  local cn = h.cn
  if pe < PLUNGE_D then
    local pl = pe / PLUNGE_D
    local py0 = sg.y - cn(7)
    local dpy = py0 + (sg.cy - py0) * pl * pl
    set_col(h.CYAN, sg.a)
    love.graphics.polygon("fill", sg.cx - cn(3), dpy, sg.cx, dpy - cn(3), sg.cx + cn(3), dpy, sg.cx, dpy + cn(3))
  end
  if pe >= PLUNGE_D and pe < 0.40 then
    local fl = math.sin(math.pi * (pe - PLUNGE_D) / 0.25)
    love.graphics.setColor(1, 1, 1, 0.30 * fl * sg.a)
    love.graphics.rectangle("fill", sg.x, sg.y, sg.w, sg.h)
  end
end

local function neutral_crown(h, hg, cw01)
  local cn, now, GOLD = h.cn, h.now, h.GOLD
  local dy0 = hg.cy - math.floor(hg.h / 2) - cn(7)
  local drop = Motion.ease_out_back(clamp01(cw01 / 0.5))
  local dyy = dy0 - cn(12) * (1 - drop)
  local salpha = math.min(1, cw01 * 3) * hg.a
  Prims.draw_diamond(hg.cx, dyy - cn(3), cn(4), GOLD, salpha)
  Prims.draw_diamond(hg.cx - cn(9), dyy, cn(3), GOLD, 0.85 * salpha)
  Prims.draw_diamond(hg.cx + cn(9), dyy, cn(3), GOLD, 0.85 * salpha)
  if hg.cf > 0 then
    for k = 1, 3 do
      local ang = now * 1.6 + k * 2.0944
      local px = hg.cx + math.cos(ang) * hg.w * 0.60
      local py = hg.cy + math.sin(ang) * hg.h * 0.45
      Prims.draw_sparkle(px, py, cn(2), GOLD, (0.35 + 0.4 * Prims.twinkle01(now, k)) * hg.cf * hg.a)
    end
  end
end

local function entry_rise(now, cn, entry, t0)
  local el = t0 and (now - t0)
  if not el or el >= PACK_CARD_APPEAR_D then return 1, 0 end
  local ef = Motion.anim01(el, PACK_CARD_APPEAR_D)
  if entry then
    local bt3 = ef - 1
    return ef, math.floor((1 - (1 + bt3 * bt3 * (entry[1] * bt3 + entry[2]))) * cn(entry[3]))
  end
  return ef, math.floor((1 - ef) * cn(40))
end

local function glide_ease(ant, over, g01)
  if ant > 0 and g01 < ant then return -0.06 * math.sin(math.pi * g01 / ant) end
  local u2 = ant > 0 and ((g01 - ant) / (1 - ant)) or g01
  return smoothstep01(u2) + over * math.sin(math.pi * clamp01((u2 - 0.55) / 0.45))
end

local function collapse_deadline(TL)
  local sn0 = S.pack_collapse_snap
  local loser_max = sn0 and sn0.loser_max
  if not loser_max then
    loser_max = LOSER_D + math.max(0, (S.pack_initial_count or 1) - 1) * LOSER_SPREAD
  end
  local shrink_at = S.pack_collapse_t + TL.ANOINT + math.max(TL.GLIDE, loser_max)
  for _, w in ipairs(S.pack_winners) do
    local e = (w.t0 or S.pack_collapse_t) + (w._anoint or TL.ANOINT) + TL.GLIDE
    if e > shrink_at then shrink_at = e end
  end
  return shrink_at, shrink_at + TL.SHRINK + TL.HOLD + TL.EXIT
end

local function hero_cap_for(sn2, count, hero_scale, hero_gap, env_pad, dims)
  if count < 2 then return hero_scale end
  local wmax = 1
  for i = 1, count do
    local d = dims and dims[i]
    local ww = d and d.w or card_dimensions(S.pack_winners[i] and S.pack_winners[i].card, sn2.sp_h)
    if ww > wmax then wmax = ww end
  end
  return math.max(1, math.min(hero_scale,
    (sn2.pk_w - 2 * sn2.pk_pad - hero_gap - 2 * env_pad) / (2 * wmax)))
end

local function loser_span(sn2, sl)
  return LOSER_D + math.abs(sl.rank - sn2.primary_rank) * LOSER_SPREAD
end

local function hero_tx(ccx, count, i, w_lw, hsc, gap)
  if count == 1 then return ccx end
  local half = w_lw * hsc / 2 + gap / 2
  return (i == 1) and (ccx - half) or (ccx + half)
end

local function hero_xform(ocx, tx, cy0, cy1, hero_sc, gg2)
  return ocx + (tx - ocx) * gg2, cy0 + (cy1 - cy0) * gg2, 1 + (hero_sc - 1) * gg2
end

local function picks_owed()
  local claim = S.pack_winners[#S.pack_winners]
  if claim and claim.owed then return claim.owed end
  return (G.GAME and G.GAME.pack_choices) or 0
end

local function draw_pack_panel(ctx)
  local th, mo, me, da, dr = H.bind(ctx)
  local ACC, FRD, WHITE, CYAN, GOLD = th.ACC, th.FRD, th.WHITE, th.CYAN, th.GOLD
  local now, pulse = H.motion(mo)
  if (S.pack_leave_t and now < S.pack_leave_t - 0.001)
    or (S.pack_collapse_t and now < S.pack_collapse_t - 0.001) then
    reset_pack_state()
  end
  local hk = persona_hooks(th.pk)
  local TL = (hk and hk.TL) or TIMELINES.soft
  local font, panel_font_small = th.cfont or th.font, th.cfont_small or th.panel_font_small
  local cn, sw, U, GUT = me.cn, me.sw, me.U, me.GUT
  local text_h = me.c_text_h
  local line_h = text_h + cn(4)
  local small_line_h = me.c_small_text_h + cn(2)
  local pack_rows, sn = da.pack_rows, da.sn
  local trunc, wrapped_lines = dr.trunc, dr.wrapped_lines
  local draw_desc_lines = dr.draw_desc_lines
  local pack_has_cards = pack_rows.cards and #pack_rows.cards > 0
  local is_pack_state = sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED"
  local PACK_LEAVE_DUR = 0.40

  -- The engine destroys the pack CardArea >= 0.4 game-seconds before G.STATE leaves the pack state
  -- (dump functions/button_callbacks.lua:2620 vs :2656), so the episode ends at whichever of the two
  -- observables fires first; reading them as independent facts leaves the panel undrawn for the gap.
  local episode_live = (is_pack_state and pack_has_cards) and true or false

  if episode_live and S.pack_last_sn ~= sn then
    reset_pack_state()
  elseif S.pack_last_sn ~= nil and not episode_live then
    if not (S.pack_collapse_t or S.pack_collapse_done) then S.pack_leave_t = now end
    S.pack_card_indices = {}
  end
  S.pack_last_sn = episode_live and sn or nil

  local HERO_SCALE = SIZING.HERO_SCALE
  local HERO_GAP = cn(SIZING.HERO_GAP)
  local HERO_HEAD = cn((hk and hk.HEAD_UNITS) or 9)
  local mark_head = cn((hk and hk.MARK_HEAD_UNITS) or 0)

  local any_highlighted = false
  if pack_has_cards then
    for _, cd in ipairs(pack_rows.cards) do
      if G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[cd.card] then
        any_highlighted = true
        break
      end
    end
  end
  if any_highlighted ~= S.pack_hl then
    S.pack_hl = any_highlighted
    S.pack_hl_t = now
  end
  local hl_win = any_highlighted and Motion.FAST or Motion.MED
  local hl_ref = S.pack_collapse_t or now
  local hl_p   = Motion.anim01((S.pack_hl_t and (hl_ref - S.pack_hl_t)) or hl_win, hl_win)
  local hl_dim = any_highlighted and (1.0 - 0.5 * hl_p) or (0.5 + 0.5 * hl_p)

  local picks_left = picks_owed()
  local pending_picks = is_pack_state and pack_has_cards and picks_left > 0

  if #S.pack_winners > 0 and (S.pack_collapse_req or picks_left <= 0 or not is_pack_state) and not S.pack_collapse_t then
    S.pack_collapse_t = now
    S.pack_leave_t = nil
  end

  local collapse_end, shrink_at
  if S.pack_collapse_t then shrink_at, collapse_end = collapse_deadline(TL) end
  local collapsing = S.pack_collapse_t and now < collapse_end
  if S.pack_collapse_t and now >= collapse_end then
    local more = is_pack_state and pack_has_cards and picks_left > 0
    if S.pack_hl_t then S.pack_hl_t = S.pack_hl_t + (now - S.pack_collapse_t) end
    S.pack_collapse_t, S.pack_winners, S.pack_collapse_snap = nil, {}, nil
    S.pack_collapse_req, S.pack_losers, S.pack_exit_last = nil, nil, nil
    S.pack_collapse_done = (not more) or nil
    S.pack_leave_t, S.pack_leave_snap, S.pack_leave_n = nil, nil, 0
    if more then
      S.pack_initial_count = 0
      S.pack_settle_t = now
      S.pack_settle_env, S.pack_settle_h = S.pack_env_last, S.pack_h_last
    end
  end

  local leave_stag = Motion.STAGGER_WIDE
  local leave_span = PACK_LEAVE_DUR + math.max(0, (S.pack_leave_n or 0) - 1) * leave_stag
  local leaving = (not collapsing) and S.pack_leave_t ~= nil
    and S.pack_leave_snap ~= nil and S.pack_leave_snap.cards ~= nil
    and (now - S.pack_leave_t) < leave_span
  local leave01 = 1
  if leaving then leave01 = 1 - Motion.anim01(now - S.pack_leave_t, leave_span) end

  local on_screen = (episode_live and not S.pack_collapse_done) or leaving or collapsing
  Episode.claim_pack(on_screen and (S.pack_appear_t or 0) or false)

  if on_screen then
    local pk_pad = cn(SIZING.PANEL_PAD)
    local env_pad = cn(SIZING.ENV_PAD)
    local small_f = panel_font_small or font
    local center_cx = ctx.center_cx or math.floor(sw / 2)
    local latch = leaving and S.pack_leave_snap or nil

    local display_cards, n_cards
    local slot_gap, sp_dy, sp_w, sp_h, slot_w, stage_w, badge_max_h, slot_h
    local title_str_full, pk_w, pk_x

    if latch then
      display_cards, n_cards = latch.cards, latch.n
      slot_gap, sp_dy, sp_w, sp_h = latch.slot_gap, latch.sp_dy, latch.sp_w, latch.sp_h
      slot_w, stage_w, badge_max_h, slot_h =
        latch.slot_w, latch.stage_w, latch.badge_max_h, latch.slot_h
      title_str_full, pk_w, pk_x = latch.title, latch.pk_w, latch.pk_x
      hl_dim = latch.hl_dim
    else
      slot_gap = cn(SIZING.SLOT_GAP)
      sp_dy = cn(SIZING.SP_DY)
      local slot_pad = cn(SIZING.SLOT_PAD)

      display_cards = S.pack_disp or {}
      S.pack_disp = display_cards
      local dn = 0
      if pack_has_cards then
        for _, cd in ipairs(pack_rows.cards) do
          local is_hl = G.NEURO.ai_highlighted and G.NEURO.ai_highlighted[cd.card]
          dn = dn + 1
          local t = pooled(_disp_pool, dn)
          t.card, t.name, t.badges, t.desc, t.rc, t.index = cd.card, cd.name, cd.badges, cd.desc, cd.rc, cd.index
          t.hidden = is_face_down(cd.card)
          S.pack_hidden_indices = S.pack_hidden_indices or {}
          S.pack_hidden_indices[cd.index] = t.hidden
          t.state, t.alpha, t.pick_elapsed = is_hl and "highlighted" or "normal", 1.0, nil
          display_cards[dn] = t
        end
      end
      for i = #display_cards, dn + 1, -1 do display_cards[i] = nil end
      table.sort(display_cards, by_pack_index)

      if #display_cards > 0 then
        if not S.pack_appear_t or S.pack_appear_t == 0 then S.pack_appear_t = now end
        S.pack_initial_count = math.max(S.pack_initial_count, #display_cards)
      end
      n_cards = math.max(#display_cards, S.pack_initial_count)

      local center_max = math.min(ctx.center_max_w or (sw - 40), sw - 40)
      local n_eff = math.max(1, n_cards)
      sp_w = clamp(
        math.floor((center_max - 2 * pk_pad - (n_eff - 1) * slot_gap) / n_eff) - 2 * slot_pad,
        cn(SIZING.SP_MIN), cn(SIZING.SP_MAX))
      sp_h = math.floor(sp_w / SIZING.SP_ASPECT)
      slot_w = sp_w + 2 * slot_pad
      stage_w = n_eff * slot_w + (n_eff - 1) * slot_gap

      badge_max_h = 0
      local badge_w = math.max(1, slot_w - cn(8))
      local any_desc = false
      for _, dc in ipairs(display_cards) do
        local badges = dc.badges or EMPTY_BADGES
        local badge_version = badges._v
        if not dc.badge_layout
          or dc.badge_layout_card ~= dc.card
          or dc.badge_layout_width ~= badge_w
          or dc.badge_layout_hidden ~= dc.hidden
          or dc.badge_layout_badges ~= badges
          or dc.badge_layout_badges_v ~= badge_version
        then
          dc.badge_layout = center_badge_rows(
            layout_modifier_badges(dc.hidden and EMPTY_BADGES or badges, small_f, badge_w, cn(1), 1),
            badge_w)
          dc.badge_layout_card = dc.card
          dc.badge_layout_width = badge_w
          dc.badge_layout_hidden = dc.hidden
          dc.badge_layout_badges = badges
          dc.badge_layout_badges_v = badge_version
        end
        badge_max_h = math.max(badge_max_h, dc.badge_layout.height)
        if not dc.hidden and dc.desc and dc.desc ~= "" then any_desc = true end
      end
      local desc_h = any_desc and 2 * small_line_h or 0
      slot_h = sp_dy + sp_h + cn(4) + text_h + cn(2) + badge_max_h + desc_h + cn(6)

      title_str_full = pack_rows.title or "Pack"
      local pk_w_target = math.min(
        math.max(stage_w + 2 * pk_pad, math.floor(font:getWidth(title_str_full)) + cn(48)),
        sw - 40)
      S.pack_w_hi = math.max(S.pack_w_hi or 0, pk_w_target)
      pk_w = math.floor(S.pack_w_hi + 0.5)
      pk_x = math.floor(center_cx - pk_w / 2)
      pk_x = math.max(20, math.min(pk_x, sw - 20 - pk_w))
    end

    local hctx = HCTX
    hctx.GOLD, hctx.ACC, hctx.pg, hctx.bg, hctx.WHITE, hctx.CYAN, hctx.FRD =
      th.GOLD, th.ACC, th.pg, th.bg, th.WHITE, th.CYAN, th.FRD
    hctx.now, hctx.pulse, hctx.cn, hctx.U = now, pulse, cn, U
    local slot_fn = (hk and hk.slot) or neutral_slot
    local mark_fn = (hk and hk.slot_mark) or neutral_mark
    local claim_fn = (hk and hk.claim) or neutral_claim
    local crown_fn = (hk and hk.crown) or neutral_crown
    local ENTRY = hk and hk.ENTRY
    local GLIDE_ANT = (hk and hk.GLIDE_ANT) or 0
    local GLIDE_OVER = (hk and hk.GLIDE_OVER) or 0.10

    local prev_n_win, refroze_at, prev_exit, prev_env, prev_h
    if collapsing and S.pack_collapse_snap and S.pack_collapse_snap.n_win ~= #S.pack_winners then
      prev_n_win, refroze_at = S.pack_collapse_snap.n_win, now
      prev_exit, prev_env, prev_h = S.pack_exit_last, S.pack_env_last, S.pack_h_last
      S.pack_collapse_snap = nil
    end
    if collapsing and not S.pack_collapse_snap then
      local won = {}
      for _, w in ipairs(S.pack_winners) do if w.card then won[w.card] = true end end
      local by_card, slots = {}, {}
      for di, dc in ipairs(display_cards) do
        local sl = {
          entry_t0 = S.pack_appear_t + (di - 1) * Motion.STAGGER_WIDE,
          card = dc.card, name = dc.name, badges = dc.badges, desc = dc.desc, rc = dc.rc,
          index = dc.index, hidden = dc.hidden, badge_layout = dc.badge_layout,
          state = "normal", alpha = 1,
        }
        if dc.card then
          sl.mini = art_prefers_mini(dc.card)
          local ak, pos = Cards.card_sprite(dc.card)
          if ak then sl.ak, sl.pos = ak, pos end
          by_card[dc.card] = sl
        end
        slots[#slots + 1] = sl
      end
      for _, ls in ipairs(S.pack_losers or {}) do
        if ls.card and not by_card[ls.card] and not won[ls.card] then
          local sl = { card = ls.card, name = ls.name, index = ls.index,
            hidden = (S.pack_hidden_indices or {})[ls.index] or false,
            mini = art_prefers_mini(ls.card), rc = ls.rc or WHITE,
            badges = ls.badges, desc = ls.desc,
            ak = ls.ak, pos = ls.pos, state = "normal", alpha = 1 }
          slots[#slots + 1] = sl
          by_card[ls.card] = sl
        end
      end
      local late = (now - S.pack_collapse_t) >= (TL.ANOINT + TL.FOLD)
      for _, w in ipairs(S.pack_winners) do
        local sl = w.card and by_card[w.card]
        if not sl and w.card then
          sl = { card = w.card, name = w.name, index = w.slot or (#slots + 1),
            hidden = w.hidden or false, mini = w.mini or false, rc = WHITE,
            ak = w.ak, pos = w.pos, alpha = 1 }
          slots[#slots + 1] = sl
          by_card[w.card] = sl
        end
        if sl then
          sl.winner, sl.state = true, "picked"
          sl.pick_at = w.t0 or now
          sl.badges = sl.badges or w.badges
          w._entry_t0 = sl.entry_t0
        end
        w._anoint = w._anoint or (late and ANOINT_LATE or TL.ANOINT)
      end
      table.sort(slots, by_pack_index)
      for rank, sl in ipairs(slots) do sl.rank = rank end
      for _, w in ipairs(S.pack_winners) do
        local sl = w.card and by_card[w.card]
        w._rank = sl and sl.rank or (w.slot or 1)
      end
      local w1 = S.pack_winners[1]
      local primary_rank = (w1 and w1._rank) or 1
      local loser_max = LOSER_D
      for _, sl in ipairs(slots) do
        if not sl.winner then
          local d = LOSER_D + math.abs(sl.rank - primary_rank) * LOSER_SPREAD
          if d > loser_max then loser_max = d end
        end
      end
      S.pack_collapse_snap = { pk_x = pk_x, pk_w = pk_w, center_cx = center_cx,
        sx0 = pk_x + math.floor((pk_w - stage_w) / 2),
        slot_w = slot_w, slot_gap = slot_gap, pk_pad = pk_pad, slot_h = slot_h, slots = slots,
        n_win = #S.pack_winners, primary_rank = primary_rank, loser_max = loser_max,
        prev_n = prev_n_win, split_at = refroze_at, exit0 = prev_exit, env0 = prev_env, h0 = prev_h,
        cap_h = text_h + cn(6) + badge_max_h + cn((hk and hk.CAP_EXTRA_UNITS) or 0),
        sp_w = sp_w, sp_h = sp_h, sp_dy = sp_dy }
      shrink_at, collapse_end = collapse_deadline(TL)
      collapsing = S.pack_collapse_t and now < collapse_end
    end
    local snap = collapsing and S.pack_collapse_snap or nil

    local title_h2 = line_h + cn(6)
    local col_ct = collapsing and (now - S.pack_collapse_t) or 0
    local grow01 = 0
    if collapsing then
      grow01 = clamp01(glide_ease(GLIDE_ANT, GLIDE_OVER, clamp01((col_ct - TL.ANOINT) / TL.GLIDE)))
    end
    local col_exit = collapsing and Motion.anim01(now - (collapse_end - TL.EXIT), TL.EXIT) or 0
    if collapsing and snap and snap.exit0 and snap.split_at then
      local back = snap.exit0 * (1 - Motion.anim01(now - snap.split_at, REFREEZE_D))
      if back > col_exit then col_exit = back end
    end
    S.pack_exit_last = col_exit
    local panel_exit = pending_picks and 0 or col_exit
    local col_fold_max = (collapsing and not pending_picks)
      and (1 - Motion.anim01(col_ct - TL.ANOINT,
        math.max(TL.FOLD, (snap and snap.loser_max) or TL.FOLD))) or 1
    local col_fold01 = (collapsing and not pending_picks)
      and (1 - Motion.anim01(col_ct - TL.ANOINT, TL.FOLD)) or 1
    local col_dim = collapsing and (1 - 0.45 * Motion.anim01(col_ct, TL.ANOINT)) or 1
    local shrink01 = 0
    if collapsing and shrink_at and not pending_picks then
      shrink01 = clamp01((now - shrink_at) / TL.SHRINK)
    end

    local env_x, env_w, env_h
    local hero_hsc
    local hero_dims
    if collapsing and snap then
      local n_win = math.min(math.max(#S.pack_winners, 1), snap.n_win)
      local dims = {}
      for i = 1, n_win do
        local ww, wh, wsx, wsy = card_dimensions(S.pack_winners[i] and S.pack_winners[i].card, snap.sp_h)
        dims[i] = { w = ww, h = wh, sx = wsx, sy = wsy }
      end
      hero_dims = dims
      local hsc = hero_cap_for(snap, n_win, HERO_SCALE, HERO_GAP, env_pad, dims)
      hero_hsc = hsc
      local hero_h_max, tot_w = 0, 0
      for i = 1, n_win do
        local d = dims[i]
        local hh = d.h * hsc
        if hh > hero_h_max then hero_h_max = hh end
        tot_w = tot_w + d.w * hsc
      end
      hero_h_max = math.floor(hero_h_max)
      local hero_env_w = math.floor(tot_w + (n_win - 1) * HERO_GAP) + 2 * (pk_pad + env_pad)
      local env_h_slot = title_h2 + mark_head + snap.slot_h + cn(10)
      local env_h_hero = title_h2 + mark_head + cn(4) + HERO_HEAD + hero_h_max + cn(4) + snap.cap_h + cn(6) + cn(2)
      env_h = round(env_h_slot + (env_h_hero - env_h_slot) * grow01)
      env_w = round(snap.pk_w + (hero_env_w - snap.pk_w) * smoothstep01(shrink01))
      if snap.split_at and (snap.env0 or snap.h0) then
        local sp = Motion.anim01(now - snap.split_at, REFREEZE_D)
        if snap.env0 then env_w = round(snap.env0 + (env_w - snap.env0) * sp) end
        if snap.h0 then env_h = round(snap.h0 + (env_h - snap.h0) * sp) end
      end
      env_x = math.floor((snap.center_cx or center_cx) - env_w / 2)
      env_x = math.max(20, math.min(env_x, sw - 20 - env_w))
    elseif latch then
      env_x, env_w, env_h = latch.pk_x, latch.pk_w, latch.env_h
    else
      env_x, env_w, env_h = pk_x, pk_w, title_h2 + mark_head + slot_h + cn(10)
      if S.pack_settle_t then
        local sp = Motion.anim01(now - S.pack_settle_t, REFREEZE_D)
        if sp >= 1 then
          S.pack_settle_t, S.pack_settle_env, S.pack_settle_h = nil, nil, nil
        else
          if S.pack_settle_env then env_w = round(S.pack_settle_env + (env_w - S.pack_settle_env) * sp) end
          if S.pack_settle_h then env_h = round(S.pack_settle_h + (env_h - S.pack_settle_h) * sp) end
          env_x = math.max(20, math.min(math.floor(center_cx - env_w / 2), sw - 20 - env_w))
        end
      end
    end
    S.pack_env_last, S.pack_h_last = env_w, env_h

    if not (latch or collapsing) then
      local ls = S.pack_leave_snap
      if not ls or not ls.cards then ls = { cards = {} }; S.pack_leave_snap = ls end
      local lc = ls.cards
      for i, dc in ipairs(display_cards) do
        local t = lc[i]
        if not t then t = {}; lc[i] = t end
        t.card, t.name, t.badges, t.desc = dc.card, dc.name, dc.badges, dc.desc
        t.rc, t.index, t.hidden, t.state = dc.rc, dc.index, dc.hidden, dc.state
        t.alpha, t.pick_elapsed = 1.0, nil
        t.badge_layout, t.badge_layout_card = dc.badge_layout, dc.badge_layout_card
        t.badge_layout_width, t.badge_layout_hidden = dc.badge_layout_width, dc.badge_layout_hidden
        t.badge_layout_badges, t.badge_layout_badges_v = dc.badge_layout_badges, dc.badge_layout_badges_v
      end
      for i = #lc, #display_cards + 1, -1 do lc[i] = nil end
      ls.n, ls.title, ls.hl_dim = n_cards, title_str_full, hl_dim
      ls.pk_x, ls.pk_w, ls.env_h = pk_x, pk_w, env_h
      ls.slot_w, ls.slot_gap, ls.slot_h, ls.stage_w = slot_w, slot_gap, slot_h, stage_w
      ls.sp_w, ls.sp_h, ls.sp_dy, ls.badge_max_h = sp_w, sp_h, sp_dy, badge_max_h
      S.pack_leave_n = n_cards
    end
    local env_content_w = env_w - pk_pad * 2

    local pk_in = Motion.anim01(now - S.pack_appear_t, Motion.MED) * leave01 * (1 - panel_exit)

    local pk_base_top = ctx.center_top_y
    if leaving then ctx.center_top_y = pk_base_top + math.floor((1 - leave01) * 16) end
    local top_y = ctx.center_top_y
    local exit_ty = -round(cn(SIZING.EXIT_LIFT) * panel_exit)

    local clip0 = push_clip(env_x - cn(SIZING.CLIP_PAD), top_y + exit_ty - cn(SIZING.CLIP_PAD),
      env_w + 2 * cn(SIZING.CLIP_PAD), env_h + cn(SIZING.CLIP_TAIL))
    love.graphics.push()
    love.graphics.translate(0, exit_ty)

    FRAME_OPTS.a, FRAME_OPTS.rad, FRAME_OPTS.title_h = pk_in, cn(9), title_h2
    H.persona_frame(th, mo, env_x, top_y, env_w, env_h, cn(1), FRAME_OPTS)

    local pk_title_color = (pack_rows.pg or ACC)
    local g = GG
    g.x, g.y, g.w, g.h = env_x, top_y, env_w, env_h
    g.cx, g.title_h, g.a = env_x + math.floor(env_w / 2), title_h2, pk_in
    g.title_col = pk_title_color
    g.shimr, g.shimg, g.shimb = mo.shimr, mo.shimg, mo.shimb
    g.flare = clamp01((now - S.pack_appear_t) / 0.45)
    if hk and hk.frame then hk.frame(hctx, g) end
    if hk and hk.title_deco then
      hk.title_deco(hctx, g)
    else
      set_col(pk_title_color, (0.85 + 0.10 * pulse) * pk_in)
      love.graphics.rectangle("fill", env_x, top_y + title_h2 - 2, env_w, 2)
    end

    love.graphics.setFont(font)
    local pk_title_ty = top_y + math.floor((title_h2 - text_h) / 2)
    local pk_title_tx = env_x + GUT
    local title_right_reserve = cn(22 + ((hk and hk.TITLE_RIGHT_RESERVE_UNITS) or 0))
    local title_str = trunc(title_str_full, env_content_w - title_right_reserve)
    local title_a = pk_in
    if collapsing then
      title_a = pk_in * math.max(0, 1 - Motion.anim01(col_ct, TL.ANOINT) * 1.8)
    end
    if title_a > 0 then
      shadow_text(title_str, pk_title_tx, pk_title_ty, pk_title_color, 1.0 * title_a, 0.30 * title_a, 1)
    end

    local scan01 = 0.5 + 0.5 * math.sin(now * 2.4)
    local slot_y = top_y + title_h2 + cn(4) + mark_head

    local function draw_pack_slot(dc, slot_x, sy_slot, ca, appear_ef, scan, no_sprite, sw_o, sh_o, spw_o, sph_o)
      local sww = sw_o or slot_w
      local shh = sh_o or slot_h
      local sph = sph_o or sp_h
      local spw = spw_o or sp_w
      local sphc = sph
      if dc.card and not no_sprite and not dc.hidden then
        local cw, ch = card_dimensions(dc.card, sph)
        spw = frame_fit(spw, cw)
        sphc = frame_fit(sph, ch)
      end
      local st = dc.state
      local pe = dc.pick_elapsed or 0
      if st == "normal" and hl_dim < 1 then ca = ca * hl_dim end

      local sg = SG
      sg.x, sg.y, sg.w, sg.h, sg.u = slot_x, sy_slot, sww, shh, cn(2)
      sg.cx, sg.cy = slot_x + math.floor(sww / 2), sy_slot + math.floor(shh / 2)
      sg.a, sg.scan, sg.appear = ca, scan, appear_ef
      sg.shimr, sg.shimg, sg.shimb = mo.shimr, mo.shimg, mo.shimb
      sg.rc = dc.hidden and FRD or dc.rc
      sg.sp_x = slot_x + math.floor((sww - spw) / 2)
      sg.sp_y = sy_slot + sp_dy
      sg.sp_w, sg.sp_h = spw, sphc
      sg.burst_r = math.min(math.floor(sww * 0.5) + pk_pad, math.floor(shh * 0.5))

      slot_fn(hctx, sg, st, scan)

      if dc.card then
        local sprite_x2, sprite_y2 = sg.sp_x, sg.sp_y

        love.graphics.setColor(0, 0, 0, 0.30 * ca)
        love.graphics.ellipse("fill", sprite_x2 + spw / 2, sprite_y2 + sphc + 3, spw * 0.48, 3)
        love.graphics.setColor(0, 0, 0, 0.55 * ca)
        love.graphics.rectangle("fill", sprite_x2 - 1, sprite_y2 - 1, spw + 2, sphc + 2)
        local sb_col = dc.hidden and FRD or dc.rc
        if st == "picked" then sb_col = GOLD
        elseif st == "highlighted" then sb_col = (hk and hk.HL_GOLD) and GOLD or CYAN end
        set_col(sb_col, (0.45 + 0.15 * (st == "normal" and pulse or scan)) * ca)
        love.graphics.setLineWidth(cn(1))
        love.graphics.rectangle("line", sprite_x2 - 1, sprite_y2 - 1, spw + 2, sphc + 2)

        if not no_sprite and not dc.hidden then
          local ok_mini = pcall(draw_card_mini, dc.card, sprite_x2, sprite_y2, sph, ca)
          if not ok_mini then
            local role = dc.rank and (dc.winner and "winner" or "loser") or "slot"
            Cards._pack_mini_fail = (Cards._pack_mini_fail or 0) + 1
            Cards.diag_once("pack_mini_" .. role, "draw_card_mini failed for pack " .. role)
            Cards.draw_mini_fallback(dc.card, sprite_x2, sprite_y2, spw, sph, ca)
          end
          love.graphics.setColor(1, 1, 1, 0.06 * ca)
          love.graphics.rectangle("fill", sprite_x2, sprite_y2, spw, math.max(2, sphc * 0.10))
        end

        if st == "picked" then
          claim_fn(hctx, sg, pe)
        end

        local name_y = sprite_y2 + sph + cn(4)
        local rc2 = dc.hidden and WHITE or ((st == "picked" and GOLD) or (st == "highlighted" and CYAN) or dc.rc)
        local name_str = trunc(dc.hidden and "face-down (hidden)" or dc.name, sww - cn(8))
        local name_x = slot_x + math.floor((sww - font:getWidth(name_str)) / 2)
        shadow_text(name_str, name_x, name_y, rc2, 0.97 * ca, 0.35 * ca, cn(1))

        local dy = name_y + text_h + cn(2)
        if dc.badge_layout and dc.badge_layout.height > 0 then
          draw_modifier_badges(dc.badge_layout, slot_x + cn(4), dy, ca, th, mo)
          dy = dy + dc.badge_layout.height
        end
        if not dc.hidden and dc.desc and dc.desc ~= "" then
          if panel_font_small then love.graphics.setFont(panel_font_small) end
          local desc_lines = wrapped_lines(dc.desc, sww - cn(8), small_f)
          draw_desc_lines(desc_lines, math.min(#desc_lines, 2),
            slot_x + cn(4), dy, small_line_h, ca, small_f)
          if panel_font_small then love.graphics.setFont(font) end
        end
      elseif not (hk and hk.COVERS_PICKED and st == "picked") then
        local name_str = trunc(dc.hidden and "face-down (hidden)" or dc.name, sww - cn(16))
        local name_x = slot_x + math.floor((sww - font:getWidth(name_str)) / 2)
        local badge_h = dc.badge_layout and dc.badge_layout.height or 0
        local group_h = text_h + (badge_h > 0 and (cn(2) + badge_h) or 0)
        local name_y = sy_slot + math.floor((shh - group_h) / 2)
        shadow_text(name_str, name_x, name_y, GOLD, 0.97 * ca, 0.35 * ca, cn(1))
        if badge_h > 0 then
          draw_modifier_badges(dc.badge_layout, slot_x + cn(4), name_y + text_h + cn(2), ca, th, mo)
        end
      end

      if st == "highlighted" then
        local mk_bob = math.sin(now * 2.2) * 2
        mark_fn(hctx, sg, st, mk_bob)
      end

    end

    local exit_dist = cn((ENTRY and ENTRY[3]) or 40)

    local function loser_d01(sn2, sl)
      if pending_picks then return 0 end
      return Motion.anim01(col_ct - TL.ANOINT, loser_span(sn2, sl))
    end
    local function fold01_of(sn2, sl)
      if pending_picks or not collapsing then return 1 end
      if sl.winner then return col_fold01 end
      return 1 - Motion.anim01(col_ct - TL.ANOINT, math.max(TL.FOLD, loser_span(sn2, sl)))
    end

    local function draw_collapse(sn2)
      local sw2 = sn2.slot_w
      local xp = col_exit
      local a = 1 - xp
      local b1 = (hk and hk.DISSOLVE and hk.DISSOLVE[1]) or DISSOLVE_A
      local b2 = (hk and hk.DISSOLVE and hk.DISSOLVE[2]) or DISSOLVE_B

      for _, sl in ipairs(sn2.slots) do
        if not sl.winner and sl.card then
          local d = loser_d01(sn2, sl)
          if d > 0 and d < 1 then
            local lw, lh, lsx, lsy = card_dimensions(sl.card, sn2.sp_h)
            local lx = sn2.sx0 + (sl.rank - 1) * (sw2 + sn2.slot_gap) + math.floor((sw2 - lw) / 2)
            local l_ef, l_dy = entry_rise(now, cn, ENTRY, sl.entry_t0)
            local ly = slot_y + sn2.sp_dy + l_dy
            local la = col_dim * hl_dim * (1 - d) * a * l_ef
            local lak, lpos = sl.ak, sl.pos
            if not (lak and lpos) then
              local sak, spos = Cards.card_sprite(sl.card)
              lak, lpos = lak or sak, lpos or spos
            end
            if sl.hidden then
              love.graphics.setColor(0, 0, 0, 0.55 * la)
              love.graphics.rectangle("fill", lx - 1, ly - 1, lw + 2, sn2.sp_h + 2)
              set_col(FRD, 0.45 * la)
              love.graphics.setLineWidth(cn(1))
              love.graphics.rectangle("line", lx - 1, ly - 1, lw + 2, sn2.sp_h + 2)
            elseif lak and lpos and not sl.mini then
              Cards.draw_sprite_shaded(lak, lpos, lx, ly, lsx, lsy, la, d, b1, b2, 0)
            else
              local ok_loser = pcall(draw_card_mini, sl.card, lx, ly, sn2.sp_h, la)
              if not ok_loser then
                Cards._pack_mini_fail = (Cards._pack_mini_fail or 0) + 1
                Cards.diag_once("pack_mini_loser", "draw_card_mini failed for pack loser")
                Cards.draw_mini_fallback(sl.card, lx, ly, lw, lh, la)
              end
            end
            if d > 0.05 then
              love.graphics.setBlendMode("add")
              local mcx, mcy = lx + math.floor(lw / 2), ly + math.floor(sn2.sp_h * d)
              Prims.ember_bloom(mcx, mcy, sw2 * 0.42, cn(2), d, GOLD, 1 - d)
              love.graphics.setBlendMode("alpha")
            end
          end
        end
      end

      local n = math.min(#S.pack_winners, sn2.n_win)
      local hsc_n = hero_hsc or hero_cap_for(sn2, n, HERO_SCALE, HERO_GAP, env_pad, hero_dims)
      local ccx = sn2.center_cx or center_cx
      local split_sp, split_hsc0
      if sn2.split_at and sn2.prev_n and sn2.prev_n < n then
        split_sp = Motion.anim01(now - sn2.split_at, REFREEZE_D)
        if split_sp < 1 then
          split_hsc0 = hero_cap_for(sn2, sn2.prev_n, HERO_SCALE, HERO_GAP, env_pad, hero_dims)
        end
      end
      for i, w in ipairs(S.pack_winners) do
        if i > n then break end
        if w.card and not w.hidden then
          local t0 = w.t0 or S.pack_collapse_t
          local aw = now - t0 - (w._anoint or TL.ANOINT)
          if aw >= 0 or col_fold01 <= 0 then
            local w_lw, w_lh, wsx, wsy
            local dcache = hero_dims and hero_dims[i]
            if dcache then
              w_lw, w_lh, wsx, wsy = dcache.w, dcache.h, dcache.sx, dcache.sy
            else
              w_lw, w_lh, wsx, wsy = card_dimensions(w.card, sn2.sp_h)
            end
            local rank = w._rank or w.slot or i
            local ocx = sn2.sx0 + (rank - 1) * (sw2 + sn2.slot_gap) + math.floor(sw2 / 2)
            local w_ef, w_dy = entry_rise(now, cn, ENTRY, w._entry_t0)
            local w_sp_cy = slot_y + w_dy + sn2.sp_dy + math.floor(w_lh / 2)
            local hero_sc = hsc_n
            local tx = hero_tx(ccx, n, i, w_lw, hero_sc, HERO_GAP)
            if split_hsc0 and i <= sn2.prev_n then
              local tx0 = hero_tx(ccx, sn2.prev_n, i, w_lw, split_hsc0, HERO_GAP)
              tx = tx0 + (tx - tx0) * split_sp
              hero_sc = split_hsc0 + (hero_sc - split_hsc0) * split_sp
            end
            local hero_cy = slot_y + HERO_HEAD + math.floor(w_lh * hero_sc / 2)
            local g01 = clamp01(aw / TL.GLIDE)
            local cw01 = clamp01((aw - TL.GLIDE * CROWN_LEAD) / TL.CROWN)
            local cf = clamp01((aw - TL.GLIDE - TL.CROWN * 0.5) / 0.25)
            local cx, cy, sc, fade
            cx, cy, sc = hero_xform(ocx, tx, w_sp_cy, hero_cy, hero_sc, glide_ease(GLIDE_ANT, GLIDE_OVER, g01))
            fade = 1
            fade = fade * w_ef
            cy = cy + math.sin(now * 2.4) * cn(2) * cf * a
            if hk and hk.CROWN_JOLT and cw01 > 0 then
              local imp = (cw01 - 0.30) / 0.16
              if imp > 0 and imp < 1 then cy = cy + round(cn(2) * (1 - imp)) end
            end
            local squash = 0.05 * math.sin(math.pi * clamp01(aw / (TL.GLIDE * 0.5)))
            sc = sc * (1 - squash) * (1 + 0.012 * math.sin(now * 2.4 + 1) * cf)
            local hw, hh = w_lw * sc, w_lh * sc
            local glow = GOLD

            love.graphics.setBlendMode("add")
            do
              for k = 1, 3 do
                local pad = cn(4) * k
                love.graphics.setColor(glow[1], glow[2], glow[3],
                  (0.11 / k) * a * fade * (0.7 + 0.3 * pulse))
                love.graphics.rectangle("fill", cx - hw / 2 - pad, cy - hh / 2 - pad,
                  hw + pad * 2, hh + pad * 2, cn(6), cn(6))
              end
            end
            love.graphics.setBlendMode("alpha")

            local wak = (not w.mini) and w.ak or nil
            local wpos = (not w.mini) and w.pos or nil

            if aw > 0 and aw < TL.GLIDE then
              local tr = 1 - aw / TL.GLIDE
              for k = 2, 1, -1 do
                local tk = aw - k * 0.035
                if tk > 0 then
                  local gx, gy, gs = hero_xform(ocx, tx, w_sp_cy, hero_cy, hero_sc,
                    glide_ease(GLIDE_ANT, GLIDE_OVER, clamp01(tk / TL.GLIDE)))
                  love.graphics.push()
                  love.graphics.translate(gx, gy)
                  love.graphics.scale(gs, gs)
                  love.graphics.translate(-w_lw / 2, -w_lh / 2)
                  if wak and wpos then
                    Cards.draw_sprite_shaded(wak, wpos, 0, 0, wsx, wsy, 0.05 * (3 - k) * tr, 0, nil, nil, 0)
                  else
                    pcall(draw_card_mini, w.card, 0, 0, sn2.sp_h, 0.05 * (3 - k) * tr)
                  end
                  love.graphics.pop()
                end
              end
            end

            love.graphics.push()
            love.graphics.translate(cx, cy)
            love.graphics.scale(sc, sc)
            love.graphics.translate(-w_lw / 2, -w_lh / 2)
            if not (wak and wpos and Cards.draw_sprite_shaded(wak, wpos, 0, 0, wsx, wsy, a * fade, xp, b1, b2, 0)) then
              local ok_win = pcall(draw_card_mini, w.card, 0, 0, sn2.sp_h, a * fade)
              if not ok_win then
                Cards._pack_mini_fail = (Cards._pack_mini_fail or 0) + 1
                Cards.diag_once("pack_mini_winner", "draw_card_mini failed for pack winner")
                Cards.draw_mini_fallback(w.card, 0, 0, w_lw, w_lh, a * fade)
              end
            end
            love.graphics.pop()

            do
              local land = (aw - TL.GLIDE) / 0.18
              if land > 0 and land < 1 then
                love.graphics.setBlendMode("add")
                local pad = cn(4) + land * cn(10)
                love.graphics.setColor(glow[1], glow[2], glow[3], 0.5 * (1 - land))
                love.graphics.setLineWidth(cn(2))
                love.graphics.rectangle("line", cx - hw / 2 - pad, cy - hh / 2 - pad, hw + pad * 2, hh + pad * 2, cn(6), cn(6))
                love.graphics.setColor(1, 1, 1, 0.18 * (1 - land))
                love.graphics.rectangle("fill", cx - hw / 2, cy - hh / 2, hw, hh, cn(4), cn(4))
                love.graphics.setBlendMode("alpha")
              end
            end

            love.graphics.setBlendMode("add")
            love.graphics.setColor(glow[1], glow[2], glow[3], (0.35 + 0.25 * pulse) * a * fade)
            love.graphics.setLineWidth(cn(2))
            love.graphics.rectangle("line", cx - hw / 2, cy - hh / 2, hw, hh, cn(4), cn(4))
            love.graphics.setBlendMode("alpha")

            if cw01 > 0 then
              local hg = HG
              hg.cx, hg.cy, hg.w, hg.h = cx, cy, hw, hh
              hg.a, hg.cf, hg.u = a * fade, cf, U
              crown_fn(hctx, hg, cw01)
            end

            if w.name and w.name ~= "" then
              local nm = clamp01(aw / (TL.GLIDE * 0.5))
              local hero_text_w = math.min(math.floor(w_lw * hero_sc * 1.4), env_w - cn(8))
              if n > 1 then
                hero_text_w = math.min(hero_text_w, math.floor((env_w - HERO_GAP) / 2) - cn(4))
              end
              local nms = trunc(w.name, hero_text_w)
              local name_y = cy + math.floor(hh / 2) + cn(4) + cn((hk and hk.CAP_EXTRA_UNITS) or 0)
                + math.floor((1 - nm) * cn(6))
              shadow_text(nms, cx - math.floor(font:getWidth(nms) / 2), name_y,
                glow, nm * a, 0.35 * nm * a, cn(1))
              if w.badges and #w.badges > 0 then
                if not w.badge_layout or w.badge_layout_width ~= hero_text_w then
                  w.badge_layout = center_badge_rows(
                    layout_modifier_badges(w.badges, small_f, hero_text_w, cn(1), 1),
                    hero_text_w)
                  w.badge_layout_width = hero_text_w
                end
                draw_modifier_badges(w.badge_layout, cx - math.floor(hero_text_w / 2),
                  name_y + text_h + cn(2), nm * a, th, mo)
              end
            end
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end

    if collapsing and snap then
      if col_fold_max > 0 then
        for _, sl in ipairs(snap.slots) do
          local slot_x = snap.sx0 + (sl.rank - 1) * (snap.slot_w + snap.slot_gap)
          sl.pick_elapsed = sl.pick_at and (now - sl.pick_at) or nil
          local e_ef, e_dy = entry_rise(now, cn, ENTRY, sl.entry_t0)
          local ca = fold01_of(snap, sl) * e_ef * (sl.winner and 1 or col_dim)
          local no_sp
          if sl.winner then
            no_sp = (now - (sl.pick_at or now)) >= (TL.ANOINT - 0.001)
          else
            no_sp = loser_d01(snap, sl) > 0
          end
          draw_pack_slot(sl, slot_x, slot_y + e_dy, ca, e_ef, scan01, no_sp,
            snap.slot_w, snap.slot_h, snap.sp_w, snap.sp_h)
        end
      end
      draw_collapse(snap)
    else
      local sx0 = env_x + math.floor((env_w - stage_w) / 2)
      local clip = push_clip(env_x, top_y, env_w, env_h)
      for ci, dc in ipairs(display_cards) do
        local ca = dc.alpha
        local slide_y
        local appear_ef = 1
        if leaving then
          local lead = (#display_cards - ci) * leave_stag
          local le = 1 - Motion.anim01((now - S.pack_leave_t) - lead, PACK_LEAVE_DUR)
          ca = ca * le
          slide_y = math.floor((1 - le) * exit_dist)
        else
          appear_ef, slide_y = entry_rise(now, cn, ENTRY, S.pack_appear_t + (ci - 1) * Motion.STAGGER_WIDE)
          ca = ca * appear_ef
        end
        local slot_x = sx0 + (ci - 1) * (slot_w + slot_gap)
        draw_pack_slot(dc, slot_x, slot_y + slide_y, ca, appear_ef, scan01)
      end
      pop_clip(clip)
    end

    if hk and hk.exit and panel_exit > 0 then hk.exit(hctx, g, panel_exit) end

    love.graphics.pop()
    pop_clip(clip0)

    ctx.center_top_y = pk_base_top + env_h + cn(4)
  end
end

return { draw = draw_pack_panel, TIMELINES = TIMELINES, SIZING = SIZING, frame_w = frame_w,
  LOSER_D = LOSER_D, LOSER_SPREAD = LOSER_SPREAD, picks_owed = picks_owed }
