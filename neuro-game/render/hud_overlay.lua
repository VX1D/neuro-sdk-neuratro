local HUD = {}

local Palette = require "render.palette"
local CardUtil = require "facts.card_util"
local Tuning = require "core.tuning"
local Utils = require "util.utils"
local Staging = require "core.staging"
local CtxEconomy = require "context.ctx_economy"
local S = require("hud.state")
local Paths = require "core.mod_paths"
local NeuroAnim = require("render.neuro-anim")

local Prims = require "hud.prims"
local TextColors = require "hud.text_colors"
local Assets = require "hud.assets"
local Emotes = require "hud.emotes"
local Showcase = require "hud.showcase"
local Cards = require "hud.cards"
local Vouchers = require "hud.vouchers"
local Motion = Prims.Motion
local DEFAULT_MOTION = Prims.DEFAULT_MOTION
local smoothstep01 = Prims.smoothstep01
local ease_out_cubic01 = Prims.ease_out_cubic01
local NEURO_PERSONA = Prims.NEURO_PERSONA
local neuro_now = Prims.now

local neuro_log = Utils.neuro_log

local get_neuro_logo = Assets.get_neuro_logo

local STATE_LABELS = {
  SELECTING_HAND = "PLAYING HAND",
  BLIND_SELECT   = "CHOOSING BLIND",
  SHOP           = "SHOPPING",
  ROUND_EVAL     = "CASHING OUT",
  TAROT_PACK     = "OPENING PACK",
  PLANET_PACK    = "OPENING PACK",
  SPECTRAL_PACK  = "OPENING PACK",
  STANDARD_PACK  = "OPENING PACK",
  BUFFOON_PACK   = "OPENING PACK",
  -- SMODS routes every booster through one state; label it like the vanilla packs (else it falls to THINKING/IDLE)
  SMODS_BOOSTER_OPENED = "OPENING PACK",
  GAME_OVER      = "GAME OVER",
  SPLASH         = "STARTING",
  MENU           = "MENU",
  RUN_SETUP      = "SETUP",
}

local get_panel_fonts = Assets.get_panel_fonts
local font_cache_id = Assets.font_cache_id

local card_edition_tag = Cards.card_edition_tag
local card_display_name = Cards.card_display_name
local card_description = Cards.card_description
local rarity_color = Cards.rarity_color
local hook_card_draw = Cards.hook_card_draw

local get_panel_emote = Emotes.get
local pick_footer_emote = Emotes.pick_footer

local PANEL_Y_DEFAULT = 120
local PANEL_H_LERP_SPEED = 6.0
local PANEL_H_GROW_SPEED = 9.0   -- growth animates too (unfold), slightly quicker than the shrink
local PANEL_SLIDE_D = Motion.dur(Motion.MED)
local FOOTER_SLOT_DURATION = Showcase.FOOTER_SLOT_DURATION
local FOOTER_EMOTE_EVERY = Showcase.FOOTER_EMOTE_EVERY
local JOKER_SHOWCASE_DURATION = Showcase.JOKER_SHOWCASE_DURATION
local JOKER_SHOWCASE_FADE_IN = Showcase.JOKER_SHOWCASE_FADE_IN
local JOKER_SHOWCASE_FADE_OUT = Showcase.JOKER_SHOWCASE_FADE_OUT
local update_buy_showcase = Showcase.update_buy
local card_set_label = Showcase.card_set_label
local update_joker_showcase = Showcase.update_joker

local joker_fx = CardUtil.joker_fx

local Rows = require "hud.rows"

local F = { font = nil, pal = nil, p = nil, pg = nil, persona_evil = false }
local ROW_METRICS = { carousel_pad = 0 }
local CTX = { theme = {}, motion = {}, metrics = {}, data = {}, draw = {} }

local function cache_put(map, keys, key, val)
  map[key] = val
  keys[#keys + 1] = key
  if #keys >= 400 then
    for i = 1, 200 do map[keys[i]] = nil end
    local tail = {}
    for i = 201, #keys do tail[#tail + 1] = keys[i] end
    return tail
  end
  return keys
end

local function trunc(s, max_w, f)
  if not s then return "" end
  f = f or F.font
  if not f or not max_w or max_w <= 0 then return s end
  local fid = font_cache_id(f)
  local ck = fid .. tostring(max_w) .. "\0" .. tostring(s)
  local cached = S.ov.trunc[ck]
  if cached ~= nil then return cached end
  local ok, w = pcall(f.getWidth, f, s)
  if not ok then return s end
  local result = s
  if w > max_w then
    local t = s
    while w > max_w and #t > 3 do
      t = t:sub(1, #t - 3) .. ".."
      ok, w = pcall(f.getWidth, f, t)
      if not ok then break end
    end
    result = t
  end
  S.ov.trunc_keys = cache_put(S.ov.trunc, S.ov.trunc_keys, ck, result)
  return result
end

local function wrapped_lines(text, max_w, f)
  local out = {}
  if not text or text == "" then return out end
  f = f or F.font
  if not f or not max_w or max_w <= 0 then
    out[1] = tostring(text)
    return out
  end
  local fid = font_cache_id(f)
  local ck = fid .. tostring(max_w) .. "\0" .. tostring(text)
  local cached = S.wrap_cache[ck]
  if cached then return cached end
  -- f.getWrap returns (width, lines)
  local ok, _, lines = pcall(f.getWrap, f, tostring(text), max_w)
  if ok and type(lines) == "table" and #lines > 0 then
    for i = 1, #lines do
      out[#out + 1] = lines[i]
    end
  else
    out[1] = tostring(text)
  end
  S.wrap_cache_keys = cache_put(S.wrap_cache, S.wrap_cache_keys, ck, out)
  return out
end

local function draw_colored_desc(text, x, y, alpha, f)
  local pal = F.pal
  local cx = x
  local i = 1
  while i <= #text do
    local j = i
    while j <= #text and text:sub(j,j) == " " do j = j + 1 end
    if j > i then cx = cx + f:getWidth(string.rep(" ", j - i)); i = j end
    j = i
    while j <= #text and text:sub(j,j) ~= " " do j = j + 1 end
    if j > i then
      local word = text:sub(i, j - 1)
      local c = pal[TextColors.classify(word)]
      local r, g, b = c[1], c[2], c[3]
      love.graphics.setColor(0, 0, 0, 0.20 * alpha)
      love.graphics.print(word, cx + 1, y + 1)
      love.graphics.setColor(r, g, b, 0.88 * alpha)
      love.graphics.print(word, cx, y)
      cx = cx + f:getWidth(word)
      i = j
    elseif i == j then i = i + 1 end
  end
end

local function showcase_type_colors(label, card, persona_evil)
  local set = card and card.config and card.config.center and card.config.center.set or ""
  local key = card and card.config and card.config.center and card.config.center.key or ""
  local slo = set:lower(); local klo = key:lower()
  local is_evil = persona_evil; if is_evil == nil then is_evil = F.persona_evil end

  local sp, sg
  if slo:find("neuro") or klo:find("neuro") or klo:find("j_n_") then
    sp = {0.50, 0.08, 0.15}; sg = {0.95, 0.35, 0.55}
  elseif label == "NEW PLANET" or slo == "planet" then
    sp = {0.10, 0.20, 0.55}; sg = {0.40, 0.68, 1.00}
  elseif label == "NEW TAROT" or slo == "tarot" then
    sp = {0.32, 0.06, 0.48}; sg = {0.78, 0.38, 1.00}
  elseif label == "NEW SPECTRAL" or slo == "spectral" then
    sp = {0.06, 0.20, 0.32}; sg = {0.45, 0.82, 1.00}
  elseif label == "VOUCHER" or slo == "voucher" then
    sp = {0.32, 0.22, 0.02}; sg = {1.00, 0.82, 0.18}
  else
    sp = F.p; sg = F.pg
  end

  if is_evil then
    sp = {sp[1] * 0.5 + 0.20, sp[2] * 0.35 + 0.02, sp[3] * 0.35 + 0.03}
    sg = {sg[1] * 0.6 + 0.902 * 0.4, sg[2] * 0.6 + 0.224 * 0.4, sg[3] * 0.6 + 0.271 * 0.4}
  end

  return sp, sg
end

local function row_h(r) return Rows.height(r, ROW_METRICS) end

local function build_panel_rows(sn, panel_rows, shop_rows, pack_rows, colors, pg)
  local GOLD, CYAN, MONEY, RED, WHITE, DIM, ORANGE =
    colors.D_GOLD, colors.D_CYAN, colors.D_MONEY,
    colors.D_RED, colors.D_WHITE, colors.D_DIM, colors.D_ORANGE

  local function hdr(color, text)      panel_rows[#panel_rows+1] = Rows.header(color, text) end
  local function row(color, text)      panel_rows[#panel_rows+1] = Rows.line(color, text) end
  local function sub(color, text)      panel_rows[#panel_rows+1] = Rows.sub(color, text) end
  local function sep()                 panel_rows[#panel_rows+1] = Rows.sep() end
  local function desc_cycle(cards, which)
    if #cards > 0 then panel_rows[#panel_rows+1] = Rows.carousel(cards, which) end
  end

  if G.GAME then
    local money = G.GAME.dollars or 0
    local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
    local round = G.GAME.round or "?"
    hdr(MONEY, string.format("$%d", money))
    row(CYAN, string.format("Ante %s  Round %s", tostring(ante), tostring(round)))
    local seed = G.GAME.seeded and G.GAME.pseudorandom and G.GAME.pseudorandom.seed
    if not seed and G.NEURO.seed_pasted then seed = G.NEURO.seed_pasted end
    if seed then
      row(DIM, "Seed: " .. tostring(seed))
    end
    local deck_name = nil
    local ok_fh, FH = pcall(require, "force.force_helpers")
    if ok_fh and FH then deck_name = FH.deck_name_of(G.GAME.selected_back or G.GAME.back) end
    if deck_name and deck_name ~= "" then
      row(DIM, "Deck: " .. tostring(deck_name))
    end
  end

  local _in_round = G.GAME and G.GAME.blind and G.GAME.blind.in_blind and
    (tonumber(G.GAME.blind.chips) or 0) > 0 and
    sn ~= "SHOP" and sn ~= "BLIND_SELECT" and sn ~= "MENU" and
    sn ~= "SPLASH" and sn ~= "RUN_SETUP" and sn ~= "ROUND_EVAL" and
    sn ~= "SMODS_BOOSTER_OPENED" and not sn:find("_PACK", 1, true)
  if _in_round then
    local debuff_text = ""
    local blind = G.GAME.blind
    if blind and type(blind.get_loc_debuff_text) == "function" then
      local ok, txt = pcall(blind.get_loc_debuff_text, blind)
      if ok and type(txt) == "string" then debuff_text = txt end
    end
    if debuff_text == "" and blind and type(blind.loc_debuff_text) == "string" then
      debuff_text = blind.loc_debuff_text
    end
    if debuff_text and debuff_text ~= "" then
      sep()
      sub(RED, "Debuff: " .. tostring(debuff_text))
    end
  end

  if G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
    sep()
    local jlimit = (G.jokers and G.jokers.config and G.jokers.config.card_limit)
      or (G.GAME and G.GAME.joker_limit) or 5
    hdr(GOLD, string.format("Jokers  %d/%d", #G.jokers.cards, jlimit))
    desc_cycle(G.jokers.cards)
  end

  if G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 then
    sep()
    local climit = (G.consumeables.config and G.consumeables.config.card_limit)
      or (G.GAME and G.GAME.consumeable_limit) or 2
    hdr(CYAN, string.format("Consumables  %d/%d", #G.consumeables.cards, climit))
    desc_cycle(G.consumeables.cards, "cons")
  end

  local function pick_desc_color(text)
    local t = (text or ""):lower()
    if t:find("mult")                          then return RED    end
    if t:find("chip")                          then return CYAN   end
    if t:find("%$") or t:find("gold") or t:find("money") then return GOLD end
    if t:find("hand") or t:find("discard")     then return WHITE  end
    return ORANGE
  end

  if sn == "SHOP" then
    -- afford coloring goes through the canonical helper (cash + open slot + free-item rule) so a row
    -- never shows buyable while the action validator would reject it for full joker/consumable slots
    local function shdr(color, text)        shop_rows[#shop_rows+1] = Rows.header(color, text) end
    local function ssub(color, text)        shop_rows[#shop_rows+1] = Rows.note(color, text) end
    local function sdesc(color, text)       shop_rows[#shop_rows+1] = Rows.descwrap(color, text) end
    local function ssep()                   shop_rows[#shop_rows+1] = Rows.sep() end
    local function scard(color, name, card, cost, afford) shop_rows[#shop_rows+1] = Rows.shopcard(color, name, card, cost, afford) end

    local shop_areas = {
      {area = G.shop_jokers,   tag = "Jokers",   label = "shop_jokers"},
      {area = G.shop_vouchers, tag = "Vouchers", label = "shop_vouchers"},
      {area = G.shop_booster,  tag = "Packs",    label = "shop_booster"},
    }
    for _, sa in ipairs(shop_areas) do
      if sa.area and sa.area.cards and #sa.area.cards > 0 then
        ssep()
        shdr(pg, "Shop: " .. sa.tag)
        for _, c in ipairs(sa.area.cards) do
          local n = card_display_name(c)
          local cost = c.cost or 0
          local afford = CtxEconomy.item_afford_status(c, sa.label).ok
          scard(afford and WHITE or DIM, n, c, cost, afford)
          if sa.tag == "Jokers" then
            local jfx = joker_fx(c)
            if jfx ~= "" then ssub(pick_desc_color(jfx), jfx) end
          end
          local desc = card_description(c)
          if (not desc or desc == "") and c and c.config and c.config.center then
            desc = Utils.safe_description(c.config.center.loc_txt, c)
          end
          if desc and desc ~= "" then sdesc(DIM, desc) end
        end
      end
    end
  end

  if sn == "BLIND_SELECT" and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices then
    sep()
    hdr(pg, "Choose Blind")
    local choices = G.GAME.round_resets.blind_choices
    for _, btype in ipairs({"Small", "Big", "Boss"}) do
      local key = choices[btype]
      if key and G.P_BLINDS and G.P_BLINDS[key] then
        local b = G.P_BLINDS[key]
        local bname = b.name or key
        if b.mult then
          row(btype == "Boss" and RED or WHITE, btype .. ": " .. bname)
          sub(DIM, "x" .. b.mult .. " chips")
        else
          row(btype == "Boss" and RED or WHITE, btype .. ": " .. bname)
        end
      end
    end
  end

  local _bp2 = CardUtil.pack_area()
  if (sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED") and _bp2 and _bp2.cards and #_bp2.cards > 0 then
    local pack_picks = G.GAME and G.GAME.pack_choices or 0
    local pack_count = #_bp2.cards
    pack_rows.title = string.format("Pack Contents  (%d/%d pick)", math.max(0, math.floor(pack_picks)), pack_count)
    pack_rows.picks_left = pack_picks
    pack_rows.total = pack_count
    pack_rows.pg = pg
    pack_rows.cards = {}
    for i, c in ipairs(_bp2.cards) do
      local n = card_display_name(c)
      if n == "?" and c.base then n = (c.base.value or "?") .. " " .. (c.base.suit or "") end
      local etag = card_edition_tag(c)
      if etag ~= "" then
        local ename = etag:match("%[(.-)%]") or ""
        if ename ~= "" then n = ename .. " " .. n end
      end
      local rc = rarity_color(c) or WHITE
      -- runtime tooltip drops seals/editions on freshly-spawned pack cards, so compose deterministically instead.
      -- enhancement_key also catches suitless Stone, which is_playing_card misses (it requires a suit).
      local desc
      if Utils.is_playing_card(c) or CardUtil.enhancement_key(c) then
        desc = CardUtil.card_modifier_desc(c)
      else
        desc = card_description(c)
        if (not desc or desc == "") and c and c.config and c.config.center then
          desc = Utils.safe_description(c.config.center.loc_txt, c)
        end
        if (not desc or desc == "") and c and c.ability then
          desc = Utils.safe_description(c.ability.loc_txt, c)
        end
      end
      if not S.pack_card_indices[c] then
        S.pack_card_indices[c] = i
      end
      pack_rows.cards[#pack_rows.cards + 1] = {
        card = c,
        name = n,
        desc = desc or "",
        rc = rc,
        index = S.pack_card_indices[c],
      }
    end
  end
end

local draw_shop_panel = require("render.panels.shop").draw

local draw_center_showcase = require("render.panels.center_showcase").draw
local draw_pack_panel = require("render.panels.pack").draw
local draw_buy_toast = require("render.panels.buy_toast").draw
local _rp = require("render.panels.right_panel")
local draw_rp_frame, draw_rp_header, draw_rp_rows, draw_rp_footer = _rp.frame, _rp.header, _rp.rows, _rp.footer
local function draw_neuro_indicator()
  if not G then return end

  local U        = 4    -- grid unit, all rhythm snaps to multiples
  local GUT      = 12
  local PAD_TOP  = 8
  local ACCENT_W = 3
  local TRACK    = 2
  local TRACK_SM = 1

  local now = (G.TIMERS and G.TIMERS.REAL) or 0
  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()
  local panel_font, panel_font_small = get_panel_fonts()
  local font = panel_font or love.graphics.getFont()
  if not font then return end
  F.font = font   -- the hoisted trunc/wrapped_lines use this as their default font
  local prev_font = love.graphics.getFont()
  if panel_font then love.graphics.setFont(panel_font) end

  local rp_s = Tuning.get("NEURO_OVERLAY_SCALE_RIGHT") or 1
  local lp_s = Tuning.get("NEURO_OVERLAY_SCALE_LEFT") or 1
  local rfont, rfont_small = get_panel_fonts(rp_s)
  local lfont, lfont_small = get_panel_fonts(lp_s)
  local function rn(v)
    local r = math.floor(v * rp_s + 0.5)
    return r < 1 and 1 or r
  end
  local function ln(v)
    local r = math.floor(v * lp_s + 0.5)
    return r < 1 and 1 or r
  end
  local rp_sh = rp_s < 0.75 and 1 or 2
  local lp_sh = lp_s < 0.75 and 1 or 2

  if G.NEURO then
    local logo = get_neuro_logo()
    local state_name = G.NEURO.state or ""
    local _pal = Palette.pal()
    local _motion = _pal.MOTION or DEFAULT_MOTION
    local persona_key = Palette.persona()
    local persona_evil = persona_key == "evil"
    local persona_neuro = persona_key == "neuro"
    local pulse
    if Motion.reduced then
      pulse = 0.5
    else
      pulse = 0.5 + 0.5 * math.sin(now * _motion.pulse_hz)
    end
    local shimr, shimg, shimb = 0, 0, 0
    if persona_neuro then
      local st2 = Motion.pulse(now, 1.25)
      local an, gn = _pal.ACCENT, _pal.GLOW
      shimr = an[1] + (gn[1] - an[1]) * st2
      shimg = an[2] + (gn[2] - an[2]) * st2
      shimb = an[3] + (gn[3] - an[3]) * st2
    elseif persona_evil then
      local st2 = Motion.pulse(now, 1.1)
      local gd, em = _pal.D_GOLD, _pal.ACCENT
      shimr = gd[1] + (em[1] - gd[1]) * st2
      shimg = gd[2] + (em[2] - gd[2]) * st2
      shimb = gd[3] + (em[3] - gd[3]) * st2
    end
    local persona_name = _pal.NAME
    local is_thinking = (G.NEURO.force_inflight or Staging.is_busy()) and true or false
    local state_label
    if is_thinking then
      state_label = STATE_LABELS[state_name] or "THINKING"
    else
      state_label = STATE_LABELS[state_name] or "IDLE"
    end
    local text_h = font:getHeight()
    local action_text = Staging.get_overlay_text()
    local p = _pal.PRIMARY
    local pg = _pal.GLOW
    local bg = _pal.PANEL_BG or _pal.BG
    local ACC = _pal.ACCENT
    local FR = _pal.FRAME or p
    local FRD = _pal.FRAME_DIM or p
    F.pal, F.p, F.pg, F.persona_evil = _pal, p, pg, persona_evil
    update_buy_showcase(now)
    Vouchers.update(now, rn, sw, sh)

    local logo_h = rn(20)
    local logo_w = 0
    local logo_scale = 1
    if logo then
      logo_scale = logo_h / logo:getHeight()
      logo_w = logo:getWidth() * logo_scale
    end

    local panel_rows = {}
    local sn = G.NEURO.state or ""

    local ORANGE  = _pal.D_ORANGE
    local GREEN   = _pal.D_GREEN
    local DIM     = _pal.D_DIM
    local WHITE   = _pal.D_WHITE
    local CYAN    = _pal.D_CYAN
    local GOLD    = _pal.D_GOLD

    local now_rows = neuro_now()
    if S.ov.built_sn ~= sn or (now_rows - S.ov.built_at) >= 0.15 then
      for k in pairs(S.ov.panel) do S.ov.panel[k] = nil end
      for k in pairs(S.ov.shop) do S.ov.shop[k] = nil end
      for k in pairs(S.ov.pack) do S.ov.pack[k] = nil end
      build_panel_rows(sn, S.ov.panel, S.ov.shop, S.ov.pack, _pal, pg)
      S.ov.built_at = now_rows
      S.ov.built_sn = sn
    end
    panel_rows = S.ov.panel
    local shop_rows = S.ov.shop
    local pack_rows = S.ov.pack

    do
      local MONEY_COUNT_DUR = 0.35
      local money_now = (G.GAME and G.GAME.dollars) or 0
      if S.ov.money_target == nil then
        S.ov.money_target = money_now
        S.ov.money_disp = money_now
      elseif money_now ~= S.ov.money_target then
        S.ov.money_from = S.ov.money_disp or money_now
        S.ov.money_target = money_now
        S.ov.money_start_at = now
      end
      local mt = math.min(1, (now - S.ov.money_start_at) / MONEY_COUNT_DUR)
      local from, to = S.ov.money_from or money_now, S.ov.money_target
      S.ov.money_disp = from + (to - from) * ease_out_cubic01(mt)
      if panel_rows[1] and panel_rows[1].kind == "header" then
        panel_rows[1].text = string.format("$%d", math.floor(S.ov.money_disp + 0.5))
      end
    end

    local p_w = rn(320)
    local p_pad_x = rn(GUT)
    local r_U = rn(U)
    local r_accw = rn(ACCENT_W)
    local p_x = sw - p_w - 8

    local jokers_on_screen = G.jokers and G.jokers.cards and #G.jokers.cards > 0
        and state_name ~= "SPLASH" and state_name ~= "MENU"
        and state_name ~= "GAME_OVER" and state_name ~= "RUN_SETUP"
    local p_y_target = math.max(PANEL_Y_DEFAULT, math.floor(sh * 0.38))
    local frame_time = now
    local dt = 0
    if S.panel_y_last_time > 0 and frame_time > S.panel_y_last_time then
      dt = math.min(frame_time - S.panel_y_last_time, 0.1)
    end
    S.panel_y_last_time = frame_time
    if p_y_target ~= S.panel_y_target then
      S.panel_y_from = S.panel_y_current
      S.panel_y_target = p_y_target
      S.panel_y_at = now
    end
    S.panel_y_current = S.panel_y_from
      + (S.panel_y_target - S.panel_y_from) * Motion.anim01(now - S.panel_y_at, PANEL_SLIDE_D)
    local booster_active = S.buy_showcase and S.buy_showcase.area == "booster_choice"
    local rp_target = booster_active and 1 or 0
    if rp_target ~= S.rp_slide_target then
      S.rp_slide_from = S.right_panel_slide_frac
      S.rp_slide_target = rp_target
      S.rp_slide_at = now
    end
    S.right_panel_slide_frac = S.rp_slide_from
      + (S.rp_slide_target - S.rp_slide_from) * Motion.anim01(now - S.rp_slide_at, PANEL_SLIDE_D)
    local pack_state_active = state_name:find("_PACK") ~= nil or state_name == "SMODS_BOOSTER_OPENED"
    local lp_target = (booster_active or pack_state_active) and 1 or 0
    if lp_target ~= S.lp_slide_target then
      S.lp_slide_from = S.left_panel_slide_frac
      S.lp_slide_target = lp_target
      S.lp_slide_at = now
    end
    S.left_panel_slide_frac = S.lp_slide_from
      + (S.lp_slide_target - S.lp_slide_from) * Motion.anim01(now - S.lp_slide_at, PANEL_SLIDE_D)
    local p_y = S.panel_y_current
    local line_h = text_h + 4
    local small_text_h = panel_font_small and panel_font_small:getHeight() or text_h
    local small_line_h = small_text_h + 2
    local card_line_h = 32
    local sep_h = 8
    local content_w = p_w - p_pad_x * 2
    local r_text_h = rfont:getHeight()
    local r_small_text_h = rfont_small and rfont_small:getHeight() or r_text_h
    local rp_font, rp_text_h = rfont, r_text_h
    local rp_line_h, rp_small_line_h = r_text_h + rn(4), r_small_text_h + rn(2)
    local rp_card_line_h, rp_sep_h = rn(card_line_h), rn(sep_h)

    local title_h = rn(44)
    local action_row_h = r_text_h + rn(12)  -- fixed height so banner appearing/clearing never resizes the panel
    ROW_METRICS.line_h, ROW_METRICS.small_line_h = rp_line_h, rp_small_line_h
    ROW_METRICS.card_line_h, ROW_METRICS.sep_h = rp_card_line_h, rp_sep_h
    ROW_METRICS.carousel_pad = rn(18)
    ROW_METRICS.content_w = content_w
    ROW_METRICS.small_font = rfont_small
    ROW_METRICS.font = rp_font
    ROW_METRICS.wrap = wrapped_lines

    local data_h = 0
    if #panel_rows > 0 then
      data_h = rn(12)
      for _, r in ipairs(panel_rows) do data_h = data_h + row_h(r) end
    end

    local pk = G.NEURO.persona or NEURO_PERSONA
    local quip_display = ""
    local footer_emote_name = pick_footer_emote(pk, sn)
    local footer_emote = get_panel_emote(footer_emote_name)

    local showcase_card = nil
    local showcase_name = nil
    local showcase_label = nil
    local showcase_fx = nil
    local showcase_desc = nil
    local showcase_alpha = 0
    local showcase_slide = 0
    if S.joker_showcase and S.joker_showcase.card then
      local jsc = S.joker_showcase
      local pack_choosing = (sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED")
        and (pack_rows.cards and #pack_rows.cards > 0)
      if pack_choosing then
        jsc.hold_elapsed = jsc.hold_elapsed or (now - (jsc.started or now))
        jsc.started = now - jsc.hold_elapsed
      else
        jsc.hold_elapsed = nil
        local elapsed = now - (jsc.started or now)
        if elapsed >= JOKER_SHOWCASE_DURATION then
          S.joker_showcase = nil
          if #S.joker_showcase_q > 0 then
            local _nxt = table.remove(S.joker_showcase_q, 1)
            S.joker_showcase = {card = _nxt.card, label = _nxt.label, started = now}
          end
        else
          showcase_card  = jsc.card
          showcase_label = jsc.label or card_set_label(showcase_card)
          showcase_name  = card_display_name(showcase_card)
          -- joker_fx misreports CONDITIONAL/random mult as unconditional; omit, desc carries it
          showcase_fx = nil
          if Utils.is_playing_card(showcase_card) or CardUtil.enhancement_key(showcase_card) then
            showcase_desc = CardUtil.card_modifier_desc(showcase_card)
          else
            showcase_desc = card_description(showcase_card)
            if (not showcase_desc or showcase_desc == "") and showcase_card and showcase_card.config and showcase_card.config.center then
              local ok, d = pcall(Utils.safe_description, showcase_card.config.center.loc_txt, showcase_card)
              if ok and type(d) == "string" then showcase_desc = d end
            end
          end
          showcase_alpha = 1
          if elapsed < JOKER_SHOWCASE_FADE_IN then
            showcase_alpha = smoothstep01(elapsed / JOKER_SHOWCASE_FADE_IN)
          elseif elapsed > (JOKER_SHOWCASE_DURATION - JOKER_SHOWCASE_FADE_OUT) then
            showcase_alpha = smoothstep01((JOKER_SHOWCASE_DURATION - elapsed) / JOKER_SHOWCASE_FADE_OUT)
          end
          showcase_slide = (1 - showcase_alpha) * 10
        end
      end
    end

    local footer_slot = math.floor(now / FOOTER_SLOT_DURATION)
    local footer_is_emote = footer_emote and (footer_slot % FOOTER_EMOTE_EVERY == (FOOTER_EMOTE_EVERY - 1))
    local run_seed = (G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed) or (G.NEURO and G.NEURO.seed_pasted)
    if run_seed ~= S.seed_quip_src then
      S.seed_quip_src = run_seed
      S.seed_quip = run_seed and ("SEED: " .. tostring(run_seed)) or nil
    end
    local quip = S.seed_quip
    if quip then
      quip_display = pk == "evil" and ("// " .. quip .. " //") or ("~ " .. quip .. " ~")
    end
    if S.drawer_slide_target == 1 then
      quip_display = ""
      footer_is_emote = false
    end
    local footer_h = ((footer_is_emote and footer_emote.img) or quip_display ~= "") and rn(80) or 0

    local total_h = title_h + action_row_h + data_h + footer_h
    local avail_h = sh - p_y - 10 - (S.drawer_reserve or 0)
    local pref_h = math.min(avail_h, math.floor(sh * 0.58))
    local n_cols = 1
    -- sticky compact: release only 24px below trigger so boundary content cannot flicker
    if S.rp_compact and total_h < pref_h - 24 then S.rp_compact = false end
    if total_h > pref_h then S.rp_compact = true end
    if S.rp_compact then
      rp_font, rp_text_h = rfont_small, r_small_text_h
      rp_line_h = r_small_text_h + rn(3)
      rp_small_line_h = r_small_text_h + rn(1)
      rp_card_line_h = rn(26)
      rp_sep_h = rn(6)
      ROW_METRICS.line_h, ROW_METRICS.small_line_h = rp_line_h, rp_small_line_h
      ROW_METRICS.card_line_h, ROW_METRICS.sep_h = rp_card_line_h, rp_sep_h
      ROW_METRICS.font = rp_font
      data_h = 0
      if #panel_rows > 0 then
        data_h = rn(12)
        for _, r in ipairs(panel_rows) do data_h = data_h + row_h(r) end
      end
      total_h = title_h + action_row_h + data_h + footer_h
      if total_h > avail_h then
        local avail_data = math.max(rp_card_line_h, avail_h - title_h - action_row_h - footer_h - rn(12))
        local col_h, max_col = 0, 0
        for _, r in ipairs(panel_rows) do
          local hh = row_h(r)
          if col_h > 0 and col_h + hh > avail_data then
            n_cols = n_cols + 1
            col_h = 0
          end
          col_h = col_h + hh
          if col_h > max_col then max_col = col_h end
        end
        if n_cols > 3 then n_cols = 3 end
        total_h = title_h + action_row_h + rn(12) + math.min(max_col, avail_data) + footer_h
        if total_h > avail_h then total_h = avail_h end
      end
    end
    local pw_total = p_w * n_cols
    p_x = sw - pw_total - 8
    if S.panel_h_current <= 0 then S.panel_h_current = total_h end
    local ph_diff = total_h - S.panel_h_current
    if math.abs(ph_diff) < 0.5 then
      S.panel_h_current = total_h
    else
      local ph_spd = ph_diff > 0 and PANEL_H_GROW_SPEED or PANEL_H_LERP_SPEED
      S.panel_h_current = S.panel_h_current + ph_diff * math.min(1, ph_spd * dt)
    end
    total_h = math.floor(S.panel_h_current + 0.5)

    local ctx = CTX
    local th = ctx.theme
    th.p, th.pg, th.bg, th.ACC, th.FR, th.FRD = p, pg, bg, ACC, FR, FRD
    th.ORANGE, th.GREEN, th.DIM, th.WHITE, th.CYAN, th.GOLD = ORANGE, GREEN, DIM, WHITE, CYAN, GOLD
    th._pal, th.persona_evil, th.persona_neuro, th.persona_name, th.pk = _pal, persona_evil, persona_neuro, persona_name, pk
    th.boss = (G.GAME and G.GAME.blind and G.GAME.blind.boss) and true or false
    th.is_round_eval = sn == "ROUND_EVAL"
    th.font, th.panel_font_small, th.rfont, th.rfont_small, th.lfont, th.lfont_small, th.rp_font =
      font, panel_font_small, rfont, rfont_small, lfont, lfont_small, rp_font
    local mo = ctx.motion
    mo.now, mo.pulse, mo.dt, mo.shimr, mo.shimg, mo.shimb = now, pulse, dt, shimr, shimg, shimb
    local me = ctx.metrics
    me.rn, me.ln, me.rp_sh, me.lp_sh, me.sw, me.sh, me.U = rn, ln, rp_sh, lp_sh, sw, sh, U
    me.GUT, me.PAD_TOP, me.ACCENT_W, me.TRACK, me.TRACK_SM = GUT, PAD_TOP, ACCENT_W, TRACK, TRACK_SM
    me.p_x, me.p_y, me.p_w, me.p_pad_x, me.r_U, me.r_accw, me.pw_total = p_x, p_y, p_w, p_pad_x, r_U, r_accw, pw_total
    me.total_h, me.content_w, me.n_cols, me.title_h, me.action_row_h, me.footer_h = total_h, content_w, n_cols, title_h, action_row_h, footer_h
    me.rp_text_h, me.rp_line_h, me.rp_small_line_h, me.rp_card_line_h, me.rp_sep_h = rp_text_h, rp_line_h, rp_small_line_h, rp_card_line_h, rp_sep_h
    me.r_text_h, me.r_small_text_h, me.line_h, me.small_line_h, me.small_text_h, me.card_line_h = r_text_h, r_small_text_h, line_h, small_line_h, small_text_h, card_line_h
    me.sep_h, me.text_h = sep_h, text_h
    local da = ctx.data
    da.panel_rows, da.shop_rows, da.pack_rows, da.sn, da.state_name = panel_rows, shop_rows, pack_rows, sn, state_name
    da.showcase_card, da.showcase_name, da.showcase_label, da.showcase_fx, da.showcase_desc = showcase_card, showcase_name, showcase_label, showcase_fx, showcase_desc
    da.showcase_alpha, da.showcase_slide, da.quip_display, da.footer_emote, da.footer_is_emote, da.jokers_on_screen = showcase_alpha, showcase_slide, quip_display, footer_emote, footer_is_emote, jokers_on_screen
    da.state_label, da.is_thinking, da.action_text, da.logo, da.logo_w, da.logo_h, da.logo_scale = state_label, is_thinking, action_text, logo, logo_w, logo_h, logo_scale
    da.booster_active, da.pack_state_active = booster_active, pack_state_active
    -- print_tracked/tracked_width/caps_label are NOT in ctx.draw; panels import them from H directly.
    local dr = ctx.draw
    dr.trunc, dr.wrapped_lines, dr.draw_colored_desc, dr.row_h, dr.showcase_type_colors =
      trunc, wrapped_lines, draw_colored_desc, row_h, showcase_type_colors
    draw_shop_panel(ctx)

    ctx.center_top_y = 8
    -- must draw before showcase/pack: they flow below its reserved band, otherwise it swaps places with them
    draw_buy_toast(ctx)

    draw_center_showcase(ctx)

    draw_pack_panel(ctx)

    if S.right_panel_slide_frac > 0 then
      love.graphics.push()
      love.graphics.translate(math.floor((pw_total + 20) * S.right_panel_slide_frac + 0.5), 0)
    end
    draw_rp_frame(ctx)

    draw_rp_header(ctx)

    draw_rp_rows(ctx)

    draw_rp_footer(ctx)
    if S.right_panel_slide_frac > 0 then love.graphics.pop() end
    -- owned-voucher ledger drawer, below the right panel (after the panel's slide pop so it doesn't ride it)
    local vok, verr = pcall(Vouchers.draw, {
      now = now, p_x = p_x, p_y = p_y, panel_h = total_h, pw = pw_total,
      sw = sw, sh = sh, rn = rn, pal = _pal, pulse = pulse,
      font = rfont, font_small = rfont_small, trunc = trunc,
      jokers_on_screen = jokers_on_screen,
    })
    if not vok then
      -- drawer pushed+scissored before it threw; restore graphics state here or it leaks every frame
      love.graphics.setScissor()
      pcall(love.graphics.pop)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setLineWidth(1)
      neuro_log("VOUCHER DRAWER ERROR:", verr)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setLineWidth(1)
  if prev_font then love.graphics.setFont(prev_font) end
end

local function draw_login_animation()
  if type(NeuroAnim) ~= "table" or type(NeuroAnim.draw_login_anim) ~= "function" then
    if G and G.NEURO then G.NEURO.login_anim = nil end
    return
  end
  local anim = G and G.NEURO and G.NEURO.login_anim
  if anim then
    local now = neuro_now()
    if now - (anim.start or now) > 6 then
      G.NEURO.login_anim = nil
      return
    end
  end
  NeuroAnim.draw_login_anim()
end
local function draw_neuro_cookie()
  if not G or not G.NEURO or not G.NEURO.egg or not G.NEURO.egg.expires_at then
    return
  end
  if G.TIMERS and G.TIMERS.REAL and G.TIMERS.REAL > G.NEURO.egg.expires_at then
    G.NEURO.egg = nil
    return
  end
  if G.NEURO.egg.img == nil and G.NEURO.egg.img_tried ~= true then
    G.NEURO.egg.img_tried = true
    local ok, img = pcall(love.graphics.newImage, Paths.cookie_path())
    if ok then
      G.NEURO.egg.img = img
    else
      G.NEURO.egg.img = false
    end
  end

  local text = G.NEURO.egg.text or ""
  local y = (love.graphics.getHeight() * 0.5) - 20
  if G.NEURO.egg.img and G.NEURO.egg.img ~= false then
    local img = G.NEURO.egg.img
    local w, h = img:getWidth(), img:getHeight()
    local scale = math.min(love.graphics.getWidth() / (w * 6), love.graphics.getHeight() / (h * 6))
    local x = (love.graphics.getWidth() - w * scale) / 2
    y = (love.graphics.getHeight() - h * scale) / 2 - 40
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y, 0, scale, scale)
    y = y + h * scale + 10
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(text, 0, y, love.graphics.getWidth(), "center")
end

HUD.draw_indicator = draw_neuro_indicator
HUD.draw_login = draw_login_animation
HUD.draw_cookie = draw_neuro_cookie
HUD.hook_card_draw = hook_card_draw
HUD.update_joker_showcase = update_joker_showcase

return HUD
