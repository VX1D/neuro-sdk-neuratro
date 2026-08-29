local HUD = {}

local Palette = require("render.palette")
local CardUtil = require("facts.card_util")
local ModifierBadges = require("render.modifier_badges")
local DeckNames = require("facts.deck_names")
local DeckFacts = require("facts.deck_facts")
local Tuning = require("core.config")
local Utils = require("util.utils")
local Staging = require("core.staging")
local CtxEconomy = require("facts.economy_facts")
local S = require("hud.state")
local Episode = require("hud.episode")
local Paths = require("core.mod_paths")
local NeuroAnim = require("render.neuro-anim")

local H = require("render.hud_shared")
local Prims = require("hud.prims")
local round = Prims.round
local floor = math.floor
local TextColors = require("hud.text_colors")
local Assets = require("hud.assets")
local Emotes = require("hud.emotes")
local Showcase = require("hud.showcase")
local Cards = require("hud.cards")
local Vouchers = require("hud.vouchers")
local Motion = Prims.Motion
local DEFAULT_MOTION = Prims.DEFAULT_MOTION
local smoothstep01 = Prims.smoothstep01
local neuro_now = Prims.now

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
  SMODS_BOOSTER_OPENED = "OPENING PACK",
  GAME_OVER      = "GAME OVER",
  SPLASH         = "STARTING",
  MENU           = "MENU",
  RUN_SETUP      = "SETUP",
}

local get_panel_fonts = Assets.get_panel_fonts
local font_cache_id = Assets.font_cache_id

local _pcall_fails = {}
local function site_fail(site)
  _pcall_fails[site] = (_pcall_fails[site] or 0) + 1
  Utils.diag_once("hud_overlay:" .. site, "hud_overlay " .. site .. " failed")
end
HUD._pcall_fails = _pcall_fails

local card_display_name = Cards.card_display_name
local card_description = Cards.card_description
local rarity_color = Cards.rarity_color
local hook_card_draw = Cards.hook_card_draw

local get_panel_emote = Emotes.get
local pick_footer_emote = Emotes.pick_footer

local PANEL_Y_DEFAULT = 120
local PANEL_SLIDE_D = Motion.MED
local PANEL_FOLLOW_RATE = PANEL_SLIDE_D / 4
local PANEL_MARGIN = H.PANEL_MARGIN
local RP_OVERHANG = 8
local ANCHORS = {
  ["auto"]         = { side = "right", band = "auto" },
  ["top-left"]     = { side = "left",  band = "top" },
  ["middle-left"]  = { side = "left",  band = "middle" },
  ["bottom-left"]  = { side = "left",  band = "bottom" },
  ["top-right"]    = { side = "right", band = "top" },
  ["middle-right"] = { side = "right", band = "middle" },
  ["bottom-right"] = { side = "right", band = "bottom" },
}
local AUTO_ANCHOR = ANCHORS["auto"]
local function clamp_num(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
local function panel_available_height(anchor, offset_y, sh, reserve)
  local a = ANCHORS[anchor] or AUTO_ANCHOR
  reserve = math.max(0, tonumber(reserve) or 0)
  local dy = sh * (tonumber(offset_y) or 0) / 100
  if a.band == "auto" then
    local y = clamp_num(math.max(PANEL_Y_DEFAULT, floor(sh * 0.38)) + dy,
      PANEL_MARGIN, sh - PANEL_MARGIN - reserve)
    return math.max(1, sh - y - PANEL_MARGIN - reserve)
  end
  if a.band == "top" then
    local y = clamp_num(PANEL_MARGIN + dy, PANEL_MARGIN, sh - PANEL_MARGIN - reserve)
    return math.max(1, sh - y - PANEL_MARGIN - reserve)
  end
  return math.max(1, sh - PANEL_MARGIN * 2 - reserve)
end
local function panel_layout(anchor, offset_x, offset_y, sw, sh, panel_w, panel_h, reserve)
  local a = ANCHORS[anchor] or AUTO_ANCHOR
  reserve = math.max(0, tonumber(reserve) or 0)
  panel_w = math.max(1, tonumber(panel_w) or 1)
  panel_h = math.max(1, tonumber(panel_h) or 1)
  local side = a.side
  local inset = sw * (tonumber(offset_x) or 0) / 100
  local dy = sh * (tonumber(offset_y) or 0) / 100
  local x = side == "left"
    and PANEL_MARGIN + inset
    or sw - panel_w - PANEL_MARGIN - inset
  local max_x = math.max(PANEL_MARGIN, sw - panel_w - PANEL_MARGIN)
  x = clamp_num(x, PANEL_MARGIN, max_x)
  local max_y = math.max(PANEL_MARGIN, sh - panel_h - PANEL_MARGIN - reserve)
  local band = a.band
  local y
  if band == "auto" then
    y = math.max(PANEL_Y_DEFAULT, floor(sh * 0.38)) + dy
  elseif band == "top" then
    y = PANEL_MARGIN + dy
  elseif band == "middle" then
    y = (sh - reserve - panel_h) / 2 + dy
  else
    y = sh - reserve - panel_h - PANEL_MARGIN + dy
  end
  y = clamp_num(y, PANEL_MARGIN, max_y)
  return round(x), round(y), side, inset, side == "left" and -1 or 1
end
local FOOTER_CYCLE = Showcase.FOOTER_CYCLE
local update_buy_showcase = Showcase.update_buy
local update_joker_showcase = Showcase.update_joker
-- render_dirty_epoch only moves on accepted SDK actions; engine-driven changes are caught by this
-- net alone, so keep it short.
local PANEL_REBUILD_SAFETY_NET = 0.3

local Rows = require("hud.rows")
local DebugStats = require("render.debug_stats")

local _cols_sig = {}
local function cols_signature(sw, sh, anchor, offset_x, p_w)
  if _cols_sig[1] ~= sw or _cols_sig[2] ~= sh or _cols_sig[3] ~= anchor
    or _cols_sig[4] ~= offset_x or _cols_sig[5] ~= p_w then
    _cols_sig[1], _cols_sig[2], _cols_sig[3], _cols_sig[4], _cols_sig[5] =
      sw, sh, anchor, offset_x, p_w
    _cols_sig.s = table.concat(_cols_sig, ":", 1, 5)
  end
  return _cols_sig.s
end

local F = { font = nil, pal = nil, p = nil, pg = nil, persona_evil = false }
local ROW_METRICS = { carousel_pad = 0 }
local RP_ROW_HS = {}
local CTX = { theme = {}, motion = {}, metrics = {}, data = {}, draw = {} }
local FB = { base = false, rp_s = false, lp_s = false, c_s = false }
local VOUCHER_CTX = {}
local _voucher_err_last = nil

local function evict_tail(keys, limit, remove_one, map)
  if #keys < limit then return keys end
  local half = math.floor(limit / 2)
  for i = 1, half do remove_one(map, keys[i]) end
  local tail = {}
  for i = half + 1, #keys do tail[#tail + 1] = keys[i] end
  return tail
end

local function release_text(v)
  if v and v ~= false and v.release then pcall(v.release, v) end
end

local function drop_key(map, k)
  release_text(map[k])
  map[k] = nil
end

-- Assigned once _desc_id_cache exists: evicting a wrapped-lines array can drop the last strong
-- reference to a weak key there, so free its Texts explicitly.
local drop_lines_bucket

local function drop_key3(map, k)
  local f, w, t = k[1], k[2], k[3]
  local bw = map[f]
  local bt = bw and bw[w]
  if bt then
    if drop_lines_bucket then drop_lines_bucket(bt[t]) end
    bt[t] = nil
    if next(bt) == nil then
      bw[w] = nil
      if next(bw) == nil then map[f] = nil end
    end
  end
end

local function cache_put(map, keys, key, val, limit)
  limit = limit or 400
  map[key] = val
  keys[#keys + 1] = key
  return evict_tail(keys, limit, drop_key, map)
end

local function cache_get3(map, fid, max_w, text)
  local by_w = map[fid]
  if not by_w then return nil end
  local by_t = by_w[max_w]
  if not by_t then return nil end
  return by_t[text]
end

local function cache_put3(map, keys, fid, max_w, text, val, limit)
  limit = limit or 400
  local by_w = map[fid]
  if not by_w then by_w = {}; map[fid] = by_w end
  local by_t = by_w[max_w]
  if not by_t then by_t = {}; by_w[max_w] = by_t end
  by_t[text] = val
  keys[#keys + 1] = { fid, max_w, text }
  return evict_tail(keys, limit, drop_key3, map)
end

local drop_last_utf8 = Utils.drop_last_codepoint

local function trunc(s, max_w, f)
  if not s then return "" end
  f = f or F.font
  if not f or not max_w or max_w <= 0 then return s end
  local fid = font_cache_id(f)
  local cached = cache_get3(S.ov.trunc, fid, max_w, s)
  if cached ~= nil then return cached end
  local ok, w = pcall(f.getWidth, f, s)
  if not ok then
    site_fail("font_width")
    return s
  end
  local result = s
  if w > max_w then
    local t = s
    while w > max_w and #t > 0 do
      t = drop_last_utf8(t)
      local candidate = t .. ".."
      ok, w = pcall(f.getWidth, f, candidate)
      if not ok then
        site_fail("font_width")
        break
      end
      result = candidate
    end
  end
  S.ov.trunc_keys = cache_put3(S.ov.trunc, S.ov.trunc_keys, fid, max_w, s, result)
  return result
end

local function wrapped_lines(text, max_w, f)
  if not text or text == "" then return {} end
  f = f or F.font
  if not f or not max_w or max_w <= 0 then return { tostring(text) } end
  local fid = font_cache_id(f)
  local key_text = tostring(text)
  local cached = cache_get3(S.wrap_cache, fid, max_w, key_text)
  if cached then return cached end
  local out = {}
  local ok, _, lines = pcall(f.getWrap, f, key_text, max_w)
  if not ok then site_fail("font_wrap") end
  if ok and type(lines) == "table" and #lines > 0 then
    for i = 1, #lines do
      out[#out + 1] = lines[i]
    end
  else
    out[1] = key_text
  end
  S.wrap_cache_keys = cache_put3(S.wrap_cache, S.wrap_cache_keys, fid, max_w, key_text, out)
  return out
end

local function safe_showcase_desc(center, card)
  local ok, d = pcall(Utils.safe_description, center and center.loc_txt, card)
  if not ok then
    site_fail("safe_desc")
    return nil
  end
  if type(d) == "string" then return d end
  return nil
end

local _space_w = {}
local function spaces_width(f, n)
  local fid = font_cache_id(f)
  local per = _space_w[fid]
  if not per then per = {}; _space_w[fid] = per end
  local w = per[n]
  if not w then w = f:getWidth(string.rep(" ", n)); per[n] = w end
  return w
end

local function print_colored_desc(text, x, y, alpha, f)
  local pal = F.pal
  local cx = x
  local i = 1
  while i <= #text do
    local j = i
    while j <= #text and text:byte(j) == 32 do j = j + 1 end
    if j > i then cx = cx + spaces_width(f, j - i); i = j end
    j = i
    while j <= #text and text:byte(j) ~= 32 do j = j + 1 end
    if j > i then
      local word = text:sub(i, j - 1)
      local c = pal[TextColors.classify(word)]
      local r, g, b = c[1], c[2], c[3]
      love.graphics.setColor(0, 0, 0, 0.40 * alpha)
      love.graphics.print(word, cx + 1, y + 1)
      love.graphics.setColor(r, g, b, 0.94 * alpha)
      love.graphics.print(word, cx, y)
      cx = cx + f:getWidth(word)
      i = j
    elseif i == j then i = i + 1 end
  end
end

local DESC_TEXT_MAX = 96
local DESC_PAL_KEYS = { "D_RED", "D_CYAN", "D_MONEY", "D_MAROON", "D_GREEN", "D_WHITE" }
local _desc_pal_snap = {}
local _desc_one = {}

local _desc_id_cache = setmetatable({}, { __mode = "k" })
local _desc_id_n = 0

-- Interned once per (font, step, count); the concat runs on every drawn description block.
local DESC_SUBKEY_MAX = 256
local _desc_subkeys, _desc_subkeys_n = {}, 0
local function desc_subkey(f, step, count)
  local fid = font_cache_id(f)
  -- Every step in use is an integral font height; an eased one grows this and NaN is no key.
  if step ~= step then return fid .. "\0" .. tostring(step) .. "\0" .. count end
  if _desc_subkeys_n >= DESC_SUBKEY_MAX then
    _desc_subkeys, _desc_subkeys_n = {}, 0
  end
  local by_step = _desc_subkeys[fid]
  if not by_step then by_step = {}; _desc_subkeys[fid] = by_step end
  local by_count = by_step[step]
  if not by_count then by_count = {}; by_step[step] = by_count end
  local k = by_count[count]
  if not k then
    k = fid .. "\0" .. step .. "\0" .. count
    by_count[count] = k
    _desc_subkeys_n = _desc_subkeys_n + 1
  end
  return k
end

drop_lines_bucket = function(lines)
  if type(lines) ~= "table" then return end
  local per = _desc_id_cache[lines]
  if not per then return end
  for _, v in pairs(per) do release_text(v) end
  _desc_id_cache[lines] = nil
end

local function release_desc_id_cache()
  for _, sub in pairs(_desc_id_cache) do
    for _, v in pairs(sub) do release_text(v) end
  end
end

if S.on_release_text_caches then
  -- A reload swaps this chunk and replaces the entry below; drain the outgoing releaser first.
  local outgoing = S.text_cache_releasers and S.text_cache_releasers["hud_overlay"]
  if outgoing then pcall(outgoing) end
  S.on_release_text_caches("hud_overlay", function()
    release_desc_id_cache()
    _desc_id_cache = setmetatable({}, { __mode = "k" })
    _desc_id_n = 0
    _desc_subkeys, _desc_subkeys_n = {}, 0
    local Gfx = require("render.gfx")
    if Gfx.release_text_cache then Gfx.release_text_cache() end
    local vb = VOUCHER_CTX._text_blocks
    if type(vb) == "table" then
      for _, e in pairs(vb) do
        if type(e) == "table" and e.text and e.text.release then pcall(e.text.release, e.text) end
      end
      VOUCHER_CTX._text_blocks, VOUCHER_CTX._text_blocks_n = nil, 0
    end
  end)
end

local function desc_pal_check(pal)
  local changed = false
  for i = 1, #DESC_PAL_KEYS do
    local c = pal[DESC_PAL_KEYS[i]]
    local o = (i - 1) * 3
    local r, g, b = c and c[1], c and c[2], c and c[3]
    if _desc_pal_snap[o + 1] ~= r or _desc_pal_snap[o + 2] ~= g or _desc_pal_snap[o + 3] ~= b then
      changed = true
      _desc_pal_snap[o + 1], _desc_pal_snap[o + 2], _desc_pal_snap[o + 3] = r, g, b
    end
  end
  if changed then
    for _, v in pairs(S.desc_text) do release_text(v) end
    S.desc_text, S.desc_text_keys = {}, {}
    release_desc_id_cache()
    _desc_id_cache = setmetatable({}, { __mode = "k" })
    _desc_id_n = 0
  end
end

local DESC_SHADOW_SEG = { 0, 0, 0, 0.40 }
local function build_desc_text(lines, count, step, f, pal)
  local ok, text = pcall(love.graphics.newText, f)
  if not ok or not text or type(text.add) ~= "function" then return nil end
  ok = pcall(function()
    local dy = 0
    for li = 1, count do
      local s = lines[li]
      local cx = 0
      local i = 1
      while i <= #s do
        local j = i
        while j <= #s and s:byte(j) == 32 do j = j + 1 end
        if j > i then cx = cx + spaces_width(f, j - i); i = j end
        j = i
        while j <= #s and s:byte(j) ~= 32 do j = j + 1 end
        if j > i then
          local word = s:sub(i, j - 1)
          local c = pal[TextColors.classify(word)]
          text:add({ DESC_SHADOW_SEG, word }, cx + 1, dy + 1)
          text:add({ { c[1], c[2], c[3], 0.94 }, word }, cx, dy)
          cx = cx + f:getWidth(word)
          i = j
        elseif i == j then i = i + 1 end
      end
      dy = dy + step
    end
  end)
  if not ok then return nil end
  return text
end

local function draw_desc_lines(lines, count, x, y, step, alpha, f)
  if count <= 0 then return end
  local pal = F.pal
  if pal and type(love.graphics.newText) == "function" then
    local hit
    if lines == _desc_one then
      -- _desc_one is a shared scratch table mutated per call, so key on its text instead of identity.
      local key = font_cache_id(f) .. "\0" .. tostring(step) .. "\0" ..
        table.concat(lines, "\1", 1, count)
      hit = S.desc_text[key]
      if hit == nil then
        hit = build_desc_text(lines, count, step, f, pal) or false
        S.desc_text_keys = cache_put(S.desc_text, S.desc_text_keys, key, hit, DESC_TEXT_MAX)
      end
    else
      -- lines is wrapped_lines' own memoized table, so its identity alone is a valid cache key.
      local per = _desc_id_cache[lines]
      if not per then per = {}; _desc_id_cache[lines] = per end
      local subkey = desc_subkey(f, step, count)
      hit = per[subkey]
      if hit == nil then
        if _desc_id_n >= DESC_TEXT_MAX then
          -- The map is weak-keyed, so the counter over-reports once GC reaps entries. Recount
          -- before flushing, or cumulative allocations alone would wipe a live cache.
          local live = 0
          for _, sub in pairs(_desc_id_cache) do
            for _ in pairs(sub) do live = live + 1 end
          end
          _desc_id_n = live
          if live >= DESC_TEXT_MAX then
            release_desc_id_cache()
            _desc_id_cache = setmetatable({}, { __mode = "k" })
            _desc_id_n = 0
            per = {}
            _desc_id_cache[lines] = per
          end
        end
        hit = build_desc_text(lines, count, step, f, pal) or false
        per[subkey] = hit
        _desc_id_n = _desc_id_n + 1
      end
    end
    if hit then
      love.graphics.setColor(1, 1, 1, alpha)
      love.graphics.draw(hit, x, y)
      return
    end
  end
  local dy = y
  for i = 1, count do
    print_colored_desc(lines[i], x, dy, alpha, f)
    dy = dy + step
  end
end

local function draw_colored_desc(text, x, y, alpha, f)
  _desc_one[1] = text
  draw_desc_lines(_desc_one, 1, x, y, 0, alpha, f)
end

local SHOWCASE_COLORS = {
  neuro = {{0.50, 0.08, 0.15}, {0.95, 0.35, 0.55}},
  planet = {{0.10, 0.20, 0.55}, {0.40, 0.68, 1.00}},
  tarot = {{0.32, 0.06, 0.48}, {0.78, 0.38, 1.00}},
  spectral = {{0.06, 0.20, 0.32}, {0.45, 0.82, 1.00}},
  voucher = {{0.32, 0.22, 0.02}, {1.00, 0.82, 0.18}},
}
local EVIL_SHOWCASE_COLORS = {}
for kind, pair in pairs(SHOWCASE_COLORS) do
  local p, g = pair[1], pair[2]
  EVIL_SHOWCASE_COLORS[kind] = {
    {p[1] * 0.5 + 0.20, p[2] * 0.35 + 0.02, p[3] * 0.35 + 0.03},
    {g[1] * 0.6 + 0.902 * 0.4, g[2] * 0.6 + 0.224 * 0.4, g[3] * 0.6 + 0.271 * 0.4},
  }
end
local EVIL_FALLBACK = {{0, 0, 0}, {0, 0, 0}}

local function showcase_kind_of(label, card)
  local ctr = CardUtil.center(card)
  local set = ctr and ctr.set or ""
  local key = ctr and ctr.key or ""
  local slo, klo = set:lower(), key:lower()
  if slo:find("neuro") or klo:find("neuro") or klo:find("j_n_") then
    return "neuro"
  elseif label == "NEW PLANET" or slo == "planet" then
    return "planet"
  elseif label == "NEW TAROT" or slo == "tarot" then
    return "tarot"
  elseif label == "NEW SPECTRAL" or slo == "spectral" then
    return "spectral"
  elseif label == "VOUCHER" or slo == "voucher" then
    return "voucher"
  end
  return nil
end

-- The fallback returns a shared scratch pair, so it stays uncached to avoid cross-call bleed.
local _showcase_kind_cache = setmetatable({}, { __mode = "k" })

local function showcase_type_colors(label, card, persona_evil)
  local is_evil = persona_evil
  if is_evil == nil then is_evil = F.persona_evil end

  local per = card ~= nil and _showcase_kind_cache[card] or nil
  local kind
  if per and per.label == label then
    kind = per.kind
  else
    kind = showcase_kind_of(label, card)
    if card ~= nil then _showcase_kind_cache[card] = { label = label, kind = kind } end
  end

  if kind then
    local pair = is_evil and EVIL_SHOWCASE_COLORS[kind] or SHOWCASE_COLORS[kind]
    return pair[1], pair[2]
  end
  if not is_evil then return F.p, F.pg end

  local p, g = F.p, F.pg
  local ep, eg = EVIL_FALLBACK[1], EVIL_FALLBACK[2]
  ep[1], ep[2], ep[3] = p[1] * 0.5 + 0.20, p[2] * 0.35 + 0.02, p[3] * 0.35 + 0.03
  eg[1], eg[2], eg[3] = g[1] * 0.6 + 0.902 * 0.4, g[2] * 0.6 + 0.224 * 0.4, g[3] * 0.6 + 0.271 * 0.4
  return ep, eg
end

local function row_h(r) return Rows.height(r, ROW_METRICS) end

local _rp_s, _lp_s, _c_s = 1, 1, 1
local function rn(v)
  local r = floor(v * _rp_s + 0.5)
  return r < 1 and 1 or r
end
local function ln(v)
  local r = floor(v * _lp_s + 0.5)
  return r < 1 and 1 or r
end
local function cn(v)
  local r = floor((tonumber(v) or 0) * _c_s + 0.5)
  return r < 1 and 1 or r
end

-- The row emitters live at module scope over these; build_panel_rows runs on a 0.3s safety net.
local _prows, _srows
local GOLD, CYAN, RED, WHITE, DIM, ORANGE

local function hdr(color, text)      _prows[#_prows+1] = Rows.header(color, text) end
local function row(color, text)      _prows[#_prows+1] = Rows.line(color, text) end
local function sep()                 _prows[#_prows+1] = Rows.sep() end

local function desc_cycle(cards, which)
  local hidden = 0
  for _, card in ipairs(cards) do
    if CardUtil.is_face_down(card) then hidden = hidden + 1 end
  end
  if hidden == 0 then
    if #cards > 0 then _prows[#_prows+1] = Rows.carousel(cards, which) end
    return
  end
  if hidden >= #cards then
    row(DIM, "Cards are face-down (hidden)")
    return
  end
  -- Rows.carousel keeps this list, so it cannot come from a shared scratch.
  local visible = {}
  for _, card in ipairs(cards) do
    if not CardUtil.is_face_down(card) then visible[#visible+1] = card end
  end
  _prows[#_prows+1] = Rows.carousel(visible, which)
  row(DIM, hidden .. " face-down (hidden)")
end

local function tag_last(key, val)
  local r = _prows[#_prows]
  if r then r.key = key; r.flash_val = tostring(val) end
end

local function pick_desc_color(text)
  local t = (text or ""):lower()
  if t:find("mult")                          then return RED    end
  if t:find("chip")                          then return CYAN   end
  if t:find("%$") or t:find("gold") or t:find("money") then return GOLD end
  if t:find("hand") or t:find("discard")     then return WHITE  end
  return ORANGE
end

local function shdr(color, text)  _srows[#_srows+1] = Rows.header(color, text) end
local function ssub(color, text)  _srows[#_srows+1] = Rows.note(color, text) end
local function sdesc(color, text) _srows[#_srows+1] = Rows.descwrap(color, text) end
local function ssep()             _srows[#_srows+1] = Rows.sep() end
local function scard(color, name, card, cost, afford, badges)
  _srows[#_srows+1] = Rows.shopcard(color, name, card, cost, afford, nil, badges)
end

local SHOP_AREAS = {
  { tag = "Jokers",   label = "shop_jokers" },
  { tag = "Vouchers", label = "shop_vouchers" },
  { tag = "Packs",    label = "shop_booster" },
}

local function build_panel_rows(sn, panel_rows, shop_rows, pack_rows, colors, pg)
  _prows, _srows = panel_rows, shop_rows
  GOLD, CYAN, RED, WHITE, DIM, ORANGE =
    colors.D_GOLD, colors.D_CYAN,
    colors.D_RED, colors.D_WHITE, colors.D_DIM, colors.D_ORANGE

  local in_run = G.STAGE == (G.STAGES and G.STAGES.RUN)
  if in_run and G.GAME then
    local back = G.GAME.selected_back or G.GAME.back
    local deck_name = DeckNames.deck_name_of(back)
    if deck_name and deck_name ~= "" then
      local center = DeckNames.deck_center_of(back)
      local deck_desc = DeckFacts.describe_deck_hud(back)
      if deck_desc == deck_name then deck_desc = nil end
      panel_rows[#panel_rows + 1] = Rows.deckback(center, deck_name, deck_desc, GOLD)
    end
  end

  if G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
    sep()
    local jlimit = (G.jokers and G.jokers.config and G.jokers.config.card_limit)
      or (G.GAME and G.GAME.joker_limit) or 5
    hdr(GOLD, string.format("Jokers  %d/%d", #G.jokers.cards, jlimit))
    tag_last("jokers", #G.jokers.cards .. "/" .. jlimit)
    desc_cycle(G.jokers.cards)
  elseif G.jokers and G.jokers.cards and in_run then
    sep()
    local jlimit = (G.jokers and G.jokers.config and G.jokers.config.card_limit)
      or (G.GAME and G.GAME.joker_limit) or 5
    hdr(DIM, string.format("Jokers  0/%d", jlimit))
    tag_last("jokers", "0/" .. jlimit)
    panel_rows[#panel_rows + 1] = Rows.emptyslots(jlimit, "jokers")
  end

  if G.consumeables and G.consumeables.cards and #G.consumeables.cards > 0 then
    sep()
    local climit = (G.consumeables.config and G.consumeables.config.card_limit)
      or (G.GAME and G.GAME.consumeable_limit) or 2
    hdr(CYAN, string.format("Consumables  %d/%d", #G.consumeables.cards, climit))
    tag_last("cons", #G.consumeables.cards .. "/" .. climit)
    desc_cycle(G.consumeables.cards, "cons")
  elseif G.consumeables and G.consumeables.cards and in_run then
    sep()
    local climit = (G.consumeables.config and G.consumeables.config.card_limit)
      or (G.GAME and G.GAME.consumeable_limit) or 2
    hdr(DIM, string.format("Consumables  0/%d", climit))
    tag_last("cons", "0/" .. climit)
    panel_rows[#panel_rows + 1] = Rows.emptyslots(climit, "cons")
  end

  if sn == "SHOP" then
    local spendable = CtxEconomy.spendable()
    SHOP_AREAS[1].area, SHOP_AREAS[2].area, SHOP_AREAS[3].area =
      G.shop_jokers, G.shop_vouchers, G.shop_booster
    local shop_areas = SHOP_AREAS
    for _, sa in ipairs(shop_areas) do
      if sa.area and sa.area.cards and #sa.area.cards > 0 then
        ssep()
        shdr(pg, "Shop: " .. sa.tag)
        for _, c in ipairs(sa.area.cards) do
          local n = card_display_name(c)
          local cost = c.cost or 0
          local afford = CtxEconomy.item_afford_status(c, sa.label, spendable).ok
          scard(afford and WHITE or DIM, n, c, cost, afford, ModifierBadges.collect(c))
          local desc = card_description(c)
          if (not desc or desc == "") and c and c.config and c.config.center then
            desc = Utils.safe_description(c.config.center.loc_txt, c)
          end
          if sa.tag == "Jokers" then
            local jfx = CardUtil.joker_fx_line(c, desc)
            if jfx ~= "" then ssub(pick_desc_color(jfx), jfx) end
          end
          if desc and desc ~= "" then sdesc(DIM, desc) end
        end
      end
    end
  end

  local _bp2 = CardUtil.pack_area()
  if (sn:find("_PACK") or sn == "SMODS_BOOSTER_OPENED") and _bp2 and _bp2.cards and #_bp2.cards > 0 then
    local pack_picks = G.GAME and G.GAME.pack_choices or 0
    local pack_count = #_bp2.cards
    pack_rows.title = string.format("Pack Contents  (%d/%d pick)", math.max(0, math.floor(pack_picks)), pack_count)
    pack_rows.pg = pg
    pack_rows.cards = {}
    for i, c in ipairs(_bp2.cards) do
      local n = card_display_name(c)
      local badges = ModifierBadges.collect(c)
      local rc = rarity_color(c) or WHITE
      local desc
      if (Utils.is_playing_card(c) or CardUtil.enhancement_key(c)) and #badges > 0 then
        desc = ""
      elseif Utils.is_playing_card(c) or CardUtil.enhancement_key(c) then
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
        badges = badges,
        desc = desc or "",
        rc = rc,
        index = S.pack_card_indices[c],
      }
    end
  end
  -- Released with the row handles so a module-scope table does not pin the shop's CardAreas.
  SHOP_AREAS[1].area, SHOP_AREAS[2].area, SHOP_AREAS[3].area = nil, nil, nil
  _prows, _srows = nil, nil
end

local draw_shop_panel = require("render.panels.shop").draw

local draw_pack_panel = require("render.panels.pack").draw
local draw_acquire = require("render.panels.acquire").draw
local _rp = require("render.panels.right_panel")
local draw_rp_frame, draw_rp_header, draw_rp_rows, draw_rp_footer = _rp.frame, _rp.header, _rp.rows, _rp.footer
local STAT_FLASH_DUR = 0.55
local function stamp_stat_flash(now, panel_rows)
  local st = S.ov.stat
  if not st then st = { seen = {}, at = {} }; S.ov.stat = st end
  for i = 1, #panel_rows do
    local r = panel_rows[i]
    local key = r.key
    if key then
      local prev = st.seen[key]
      if prev == nil then
        st.seen[key] = r.flash_val
      elseif prev ~= r.flash_val then
        st.seen[key] = r.flash_val
        st.at[key] = now
      end
      local at = st.at[key]
      if at then
        local f = 1 - Motion.anim01(now - at, STAT_FLASH_DUR)
        r.flash = (f > 0.01) and f or nil
      end
    end
  end
end

local function draw_neuro_indicator()
  if not G then return end

  local U        = 4
  local GUT      = 12
  local PAD_TOP  = 8
  local ACCENT_W = 3
  local TRACK    = 2
  local TRACK_SM = 1

  local now = neuro_now()
  local sw = love.graphics.getWidth()
  local sh = love.graphics.getHeight()
  local panel_font, panel_font_small = get_panel_fonts()
  local font = panel_font or love.graphics.getFont()
  if not font then return end
  F.font = font
  local prev_font = love.graphics.getFont()
  if panel_font then love.graphics.setFont(panel_font) end

  local hud_s = math.max(0.5, floor((sh / 1080) / 0.05 + 0.5) * 0.05)
  local rp_s = (Tuning.get("NEURO_OVERLAY_SCALE_RIGHT") or 1) * hud_s
  local lp_s = (Tuning.get("NEURO_OVERLAY_SCALE_LEFT") or 1) * hud_s
  local c_s = (Tuning.get("NEURO_CENTER_SCALE") or 1) * hud_s
  _rp_s, _lp_s, _c_s = rp_s, lp_s, c_s
  if FB.base ~= panel_font or FB.rp_s ~= rp_s or FB.lp_s ~= lp_s or FB.c_s ~= c_s then
    FB.base, FB.rp_s, FB.lp_s, FB.c_s = panel_font, rp_s, lp_s, c_s
    FB.rfont, FB.rfont_small = get_panel_fonts(rp_s)
    FB.lfont, FB.lfont_small = get_panel_fonts(lp_s)
    FB.rfont_title, FB.rfont_display = Assets.role_font("title", rp_s), Assets.role_font("display", rp_s)
    FB.lfont_title = Assets.role_font("title", lp_s)
    FB.font_title = Assets.role_font("title", 1)
    FB.cfont, FB.cfont_small = get_panel_fonts(c_s)
    FB.cfont_title = Assets.role_font("title", c_s)
    FB.cfont_micro = Assets.role_font("micro", c_s)
  end
  local rfont, rfont_small = FB.rfont, FB.rfont_small
  local lfont, lfont_small = FB.lfont, FB.lfont_small
  local rfont_title, rfont_display = FB.rfont_title, FB.rfont_display
  local lfont_title, font_title = FB.lfont_title, FB.font_title
  local cfont, cfont_small = FB.cfont, FB.cfont_small
  local cfont_title, cfont_micro = FB.cfont_title, FB.cfont_micro
  local rp_sh = rp_s < 0.75 and 1 or 2
  local lp_sh = lp_s < 0.75 and 1 or 2

  if G.NEURO then
    local logo = get_neuro_logo()
    local state_name = G.NEURO.state or ""
    local _pal = Palette.displayed_pal()
    local _motion = _pal.MOTION or DEFAULT_MOTION
    local persona_key = Palette.displayed_persona()
    local persona_evil = persona_key == "evil"
    local persona_neuro = persona_key == "neuro"
    local pulse = Motion.pulse(now, _motion.pulse_hz)
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
    local p = _pal.PRIMARY
    local pg = _pal.GLOW
    local bg = _pal.PANEL_BG or _pal.BG
    local ACC = _pal.ACCENT
    local FR = _pal.FRAME or p
    local FRD = _pal.FRAME_DIM or p
    F.pal, F.p, F.pg, F.persona_evil = _pal, p, pg, persona_evil
    desc_pal_check(_pal)
    Vouchers.update(now, rn, sw, sh)

    local logo_h = rn(20)
    local logo_w = 0
    local logo_scale = 1
    if logo then
      logo_scale = logo_h / logo:getHeight()
      logo_w = logo:getWidth() * logo_scale
    end

    local sn = state_name

    local ORANGE  = _pal.D_ORANGE
    local GREEN   = _pal.D_GREEN
    local DIM     = _pal.D_DIM
    local WHITE   = _pal.D_WHITE
    local CYAN    = _pal.D_CYAN
    local GOLD    = _pal.D_GOLD

    local dirty_epoch = (G.NEURO and tonumber(G.NEURO.render_dirty_epoch)) or 0
    if S.ov.built_sn ~= sn or S.ov.built_epoch ~= dirty_epoch
        or (now - S.ov.built_at) >= PANEL_REBUILD_SAFETY_NET then
      for k in pairs(S.ov.panel) do S.ov.panel[k] = nil end
      for k in pairs(S.ov.shop) do S.ov.shop[k] = nil end
      for k in pairs(S.ov.pack) do S.ov.pack[k] = nil end
      build_panel_rows(sn, S.ov.panel, S.ov.shop, S.ov.pack, _pal, pg)
      S.ov.built_at = now
      S.ov.built_sn = sn
      S.ov.built_epoch = dirty_epoch
    end
    local panel_rows = S.ov.panel
    local shop_rows = S.ov.shop
    local pack_rows = S.ov.pack

    stamp_stat_flash(now, panel_rows)

    local p_w = rn(320)
    local p_pad_x = rn(GUT)
    local r_U = rn(U)
    local r_accw = rn(ACCENT_W)
    local p_x, p_y

    local anchor = Tuning.get("NEURO_OVERLAY_ANCHOR") or "auto"
    local offset_x = Tuning.get("NEURO_OVERLAY_OFFSET_X") or 0
    local offset_y = Tuning.get("NEURO_OVERLAY_OFFSET_Y") or 0
    local shop_anchor = Tuning.get("NEURO_SHOP_ANCHOR") or "auto"
    local shop_offset_x = Tuning.get("NEURO_SHOP_OFFSET_X") or 0
    local shop_offset_y = Tuning.get("NEURO_SHOP_OFFSET_Y") or 0
    local drawer_reserve = S.drawer_reserve or 0
    local drawer_reserve_target = S.drawer_reserve_target or drawer_reserve
    local avail_h = panel_available_height(anchor, offset_y, sh, drawer_reserve_target)
    local frame_time = now
    local dt = 0
    if S.panel_y_last_time > 0 and frame_time > S.panel_y_last_time then
      dt = math.min(frame_time - S.panel_y_last_time, 0.1)
    end
    S.panel_y_last_time = frame_time
    local pack_state_active = state_name:find("_PACK") ~= nil or state_name == "SMODS_BOOSTER_OPENED"
    local booster_active = Episode.pack_on_screen()
    if booster_active == nil then
      booster_active = pack_state_active and pack_rows.cards ~= nil and #pack_rows.cards > 0
    end
    local rp_target = booster_active and 1 or 0
    S.right_panel_slide_frac = Motion.tween(S, "rp_slide", rp_target, now, PANEL_SLIDE_D)
    local lp_target = (booster_active or pack_state_active) and 1 or 0
    S.left_panel_slide_frac = Motion.tween(S, "lp_slide", lp_target, now, PANEL_SLIDE_D)
    local line_h = text_h + 4
    local small_text_h = panel_font_small and panel_font_small:getHeight() or text_h
    local small_line_h = small_text_h + 2
    local card_line_h = 32
    local sep_h = 8
    local content_w = p_w - p_pad_x * 2
    local r_text_h = rfont:getHeight()
    local r_small_text_h = rfont_small and rfont_small:getHeight() or r_text_h
    local c_text_h = cfont:getHeight()
    local c_small_text_h = cfont_small and cfont_small:getHeight() or c_text_h
    local rp_font, rp_text_h = rfont, r_text_h
    local rp_line_h, rp_small_line_h = r_text_h + rn(4), r_small_text_h + rn(2)
    local rp_card_line_h, rp_sep_h = rn(card_line_h), rn(sep_h)
    local rp_title_text_h = rfont_title:getHeight()
    local rp_display_text_h = rfont_display:getHeight()
    local rp_hdr_line_h = rp_title_text_h + rn(4)

    local title_h = rn(8) + rp_display_text_h + rn(4) + rp_title_text_h + rn(6)
    ROW_METRICS.line_h, ROW_METRICS.small_line_h = rp_line_h, rp_small_line_h
    ROW_METRICS.header_line_h = rp_hdr_line_h
    ROW_METRICS.card_line_h, ROW_METRICS.sep_h = rp_card_line_h, rp_sep_h
    ROW_METRICS.carousel_pad = rn(18)
    ROW_METRICS.content_w = content_w
    ROW_METRICS.small_font = rfont_small
    ROW_METRICS.font = rp_font
    ROW_METRICS.wrap = wrapped_lines

    local data_h = 0
    if #panel_rows > 0 then
      data_h = rn(12)
      for i, r in ipairs(panel_rows) do
        local h = row_h(r)
        RP_ROW_HS[i] = h
        data_h = data_h + h
      end
    end

    local pk = persona_key
    local quip_display = ""
    local footer_emote_name = pick_footer_emote(pk, sn)
    local footer_emote = get_panel_emote(footer_emote_name)

    local dev_footer = G.NEURO and G.NEURO.dev_footer
    local footer_slot = (dev_footer and dev_footer.dur)
      and math.floor(now / dev_footer.dur) or H.footer_slot(now)
    local footer_phase = (dev_footer and dev_footer.phase) or (footer_slot % FOOTER_CYCLE)
    local footer_is_emote = footer_emote and footer_phase == (FOOTER_CYCLE - 1)
    local run_seed = (G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed) or (G.NEURO and G.NEURO.seed_pasted)
    if run_seed ~= S.seed_quip_src then
      S.seed_quip_src = run_seed
      S.seed_quip = run_seed and ("SEED: " .. tostring(run_seed)) or nil
    end
    local quip = S.seed_quip
    if quip then
      quip_display = pk == "evil" and ("// " .. quip .. " //") or ("~ " .. quip .. " ~")
    end

    local footer_legend, footer_legend_entry, footer_legend_n, footer_legend_i
    if not footer_is_emote and (footer_phase == 1 or footer_phase == 2) then
      local deck = S.ov.legend_deck
      if not deck or S.ov.legend_deck_epoch ~= dirty_epoch
          or (now - (S.ov.legend_deck_at or -1)) >= PANEL_REBUILD_SAFETY_NET then
        deck = ModifierBadges.legend_deck()
        S.ov.legend_deck, S.ov.legend_deck_at, S.ov.legend_deck_epoch = deck, now, dirty_epoch
      end
      local ordinal = (dev_footer and dev_footer.phase) and footer_slot
        or (math.floor(footer_slot / FOOTER_CYCLE) * 2 + (footer_phase == 2 and 1 or 0))
      footer_legend, footer_legend_entry = ModifierBadges.legend(ordinal, deck)
      if footer_legend_entry then
        footer_legend_n = #deck
        footer_legend_i = (ordinal % #deck) + 1
        quip_display = footer_legend_entry.text .. "  " .. (footer_legend_entry.tip or "")
      end
    end
    local footer_h = 0
    if footer_is_emote or quip_display ~= "" then footer_h = rn(80) end
    local footer_sig = footer_is_emote and ("e:" .. footer_slot)
      or (footer_legend_entry and ("l:" .. footer_slot))
      or (quip_display or "")
    if footer_sig ~= S.ov.footer_sig then
      S.ov.footer_prev_emote = S.ov.footer_last_emote
      S.ov.footer_prev_quip = S.ov.footer_last_quip
      S.ov.footer_prev_legend = S.ov.footer_last_legend
      S.ov.footer_prev_legend_meta = S.ov.footer_last_legend_meta
      S.ov.footer_sig = footer_sig
      S.ov.footer_at = now
    end
    S.ov.footer_last_emote = footer_is_emote and footer_emote or nil
    S.ov.footer_last_quip = quip_display
    S.ov.footer_last_legend = footer_legend
    if footer_legend_entry then
      -- The cross-fade holds the previous table, so reuse only when nothing in it moved.
      local meta = S.ov.footer_last_legend_meta
      if not meta or meta.entry ~= footer_legend_entry
        or meta.n ~= footer_legend_n or meta.i ~= footer_legend_i then
        meta = { entry = footer_legend_entry, n = footer_legend_n, i = footer_legend_i }
      end
      S.ov.footer_last_legend_meta = meta
    else
      S.ov.footer_last_legend_meta = nil
    end
    local footer_fade = smoothstep01(math.min(1, (now - (S.ov.footer_at or now)) / 0.25))

    local total_h = title_h + data_h + footer_h
    local pref_h = math.min(avail_h, math.floor(sh * 0.58))
    local n_cols = 1
    S.rp_compact = Rows.want_compact(S.rp_compact, total_h, pref_h)
    if S.rp_compact then
      rp_font, rp_text_h = rfont_small, r_small_text_h
      Rows.compact_metrics(ROW_METRICS, r_small_text_h, rn)
      rp_line_h, rp_small_line_h = ROW_METRICS.line_h, ROW_METRICS.small_line_h
      rp_card_line_h, rp_sep_h = ROW_METRICS.card_line_h, ROW_METRICS.sep_h
      rp_hdr_line_h = ROW_METRICS.header_line_h
      ROW_METRICS.font = rp_font
      data_h = 0
      if #panel_rows > 0 then
        data_h = rn(12)
        for i, r in ipairs(panel_rows) do
          local h = row_h(r)
          RP_ROW_HS[i] = h
          data_h = data_h + h
        end
      end
      total_h = title_h + data_h + footer_h
      if total_h > avail_h then
        local avail_data = math.max(rp_card_line_h, avail_h - title_h - footer_h - rn(12))
        local used_h
        n_cols, used_h = Rows.pack_columns(panel_rows, ROW_METRICS, avail_data, 3, RP_ROW_HS)
        total_h = title_h + rn(12) + used_h + footer_h
        if total_h > avail_h then total_h = avail_h end
      end
    end
    local n_cols_used = n_cols
    local cols_sig = cols_signature(sw, sh, anchor, offset_x, p_w)
    local hard_cap = math.max(1, math.floor((sw - 2 * PANEL_MARGIN) / math.max(1, p_w)))
    S.rp_cols_latch, n_cols =
      Rows.latch_columns(S.rp_cols_latch, n_cols, cols_sig, math.min(3, hard_cap))
    local pw_total = p_w * n_cols
    local panel_h_target = total_h
    if S.panel_h_current <= 0 then S.panel_h_current = math.min(total_h, title_h) end
    S.panel_h_current = Rows.ease_height(S.panel_h_current, total_h, dt)
    total_h = round(S.panel_h_current)
    local p_x_target, p_y_target, main_side, offset_x_px, main_slide_dir =
      panel_layout(anchor, offset_x, offset_y, sw, sh, pw_total, total_h, drawer_reserve)
    local _, p_y_target_stable =
      panel_layout(anchor, offset_x, offset_y, sw, sh, pw_total, panel_h_target, drawer_reserve_target)
    Motion.snap(S, "panel_x", p_x_target)
    Motion.approach(S, "panel_y", p_y_target, dt, PANEL_FOLLOW_RATE)
    p_x, p_y = round(S.panel_x_current), round(S.panel_y_current)
    local ctx = CTX
    local th = ctx.theme
    th.p, th.pg, th.bg, th.ACC, th.FR, th.FRD = p, pg, bg, ACC, FR, FRD
    th.ROW, th.SEL = _pal.ROW_BG or bg, _pal.SEL_BG or _pal.FRAME_DIM or bg
    th.ORANGE, th.GREEN, th.DIM, th.WHITE, th.CYAN, th.GOLD = ORANGE, GREEN, DIM, WHITE, CYAN, GOLD
    th._pal, th.persona_evil, th.persona_neuro, th.persona_name, th.pk = _pal, persona_evil, persona_neuro, persona_name, pk
    th.boss = (G.GAME and G.GAME.blind and G.GAME.blind.boss) and true or false
    th.is_round_eval = sn == "ROUND_EVAL"
    th.font, th.panel_font_small, th.rfont, th.rfont_small, th.lfont, th.lfont_small, th.rp_font =
      font, panel_font_small, rfont, rfont_small, lfont, lfont_small, rp_font
    th.rfont_title, th.rfont_display, th.lfont_title = rfont_title, rfont_display, lfont_title
    th.font_title = font_title
    th.cfont, th.cfont_small, th.cfont_title, th.cfont_micro = cfont, cfont_small, cfont_title, cfont_micro
    local mo = ctx.motion
    mo.now, mo.pulse, mo.dt, mo.shimr, mo.shimg, mo.shimb = now, pulse, dt, shimr, shimg, shimb
    local me = ctx.metrics
    me.rn, me.ln, me.rp_sh, me.lp_sh, me.sw, me.sh, me.U = rn, ln, rp_sh, lp_sh, sw, sh, U
    me.cn = cn
    me.GUT, me.PAD_TOP, me.ACCENT_W, me.TRACK, me.TRACK_SM = GUT, PAD_TOP, ACCENT_W, TRACK, TRACK_SM
    me.p_x, me.p_y, me.p_w, me.p_pad_x, me.r_U, me.r_accw, me.pw_total = p_x, p_y, p_w, p_pad_x, r_U, r_accw, pw_total
    me.main_side, me.main_slide_dir, me.offset_x_px = main_side, main_slide_dir, offset_x_px
    me.anchor, me.offset_y = anchor, offset_y
    me.shop_anchor, me.shop_offset_x, me.shop_offset_y = shop_anchor, shop_offset_x, shop_offset_y
    me.total_h, me.content_w, me.n_cols, me.title_h, me.footer_h = total_h, content_w, n_cols, title_h, footer_h
    me.panel_h_target = panel_h_target
    me.row_hs = RP_ROW_HS
    me.p_y_target_stable = p_y_target_stable
    me.n_cols_used = n_cols_used
    me.rp_text_h, me.rp_line_h, me.rp_small_line_h, me.rp_card_line_h, me.rp_sep_h = rp_text_h, rp_line_h, rp_small_line_h, rp_card_line_h, rp_sep_h
    me.r_text_h, me.r_small_text_h, me.line_h, me.small_line_h, me.small_text_h, me.card_line_h = r_text_h, r_small_text_h, line_h, small_line_h, small_text_h, card_line_h
    me.c_text_h, me.c_small_text_h = c_text_h, c_small_text_h
    me.sep_h, me.text_h = sep_h, text_h
    me.rp_title_text_h, me.rp_display_text_h, me.rp_hdr_line_h = rp_title_text_h, rp_display_text_h, rp_hdr_line_h
    local da = ctx.data
    da.panel_rows, da.shop_rows, da.pack_rows, da.sn, da.state_name = panel_rows, shop_rows, pack_rows, sn, state_name
    da.showcase_alpha, da.quip_display, da.footer_emote, da.footer_is_emote = 0, quip_display, footer_emote, footer_is_emote
    da.footer_fade = footer_fade
    da.footer_prev_emote, da.footer_prev_quip = S.ov.footer_prev_emote, S.ov.footer_prev_quip
    da.footer_prev_legend = S.ov.footer_prev_legend or false
    da.footer_legend = footer_legend or false
    da.footer_legend_meta = S.ov.footer_last_legend_meta or false
    da.footer_prev_legend_meta = S.ov.footer_prev_legend_meta or false
    da.state_label, da.is_thinking, da.logo, da.logo_w, da.logo_h, da.logo_scale = state_label, is_thinking, logo, logo_w, logo_h, logo_scale
    da.booster_active, da.pack_state_active = booster_active, pack_state_active
    local dr = ctx.draw
    dr.trunc, dr.wrapped_lines, dr.draw_colored_desc, dr.row_h, dr.showcase_type_colors =
      trunc, wrapped_lines, draw_colored_desc, row_h, showcase_type_colors
    dr.draw_desc_lines, dr.print_colored_desc = draw_desc_lines, print_colored_desc
    local rp_shift = round(main_slide_dir * (pw_total + 20) * S.right_panel_slide_frac)
    local eff_px = p_x + rp_shift
    ctx.occ_left, ctx.occ_right = nil, nil
    draw_shop_panel(ctx)
    local settled_px = p_x_target
      + round(main_slide_dir * (pw_total + 20) * (S.rp_slide_target or 0))
    H.corridor(ctx, sw, main_side, settled_px, pw_total, now, dt, cn)

    ctx.center_top_y = 8
    draw_acquire(ctx)

    draw_pack_panel(ctx)

    local rp_on_screen = (eff_px - RP_OVERHANG) < sw and (eff_px + pw_total + RP_OVERHANG) > 0
    if rp_on_screen then
      if S.right_panel_slide_frac > 0 then
        love.graphics.push()
        love.graphics.translate(rp_shift, 0)
      end
      draw_rp_frame(ctx)

      draw_rp_header(ctx)

      draw_rp_rows(ctx)

      draw_rp_footer(ctx)
      if S.right_panel_slide_frac > 0 then love.graphics.pop() end
    end
    local rp_off = S.right_panel_slide_frac > 0 and rp_shift or 0
    if rp_on_screen then
      local vctx = VOUCHER_CTX
      vctx.now, vctx.p_x, vctx.p_y, vctx.panel_h, vctx.pw = now, p_x + rp_off, p_y, total_h, pw_total
      vctx.sw, vctx.sh, vctx.rn, vctx.pal, vctx.pulse = sw, sh, rn, _pal, pulse
      vctx.font, vctx.font_small, vctx.trunc = rfont, rfont_small, trunc
      vctx.static_text = math.abs((S.panel_y_current or p_y) - p_y_target) < 0.001
        and math.abs((S.panel_h_current or panel_h_target) - panel_h_target) < 0.001
        and math.abs((S.right_panel_slide_frac or 0) - (S.rp_slide_target or 0)) < 0.001
        and math.abs((S.drawer_slide_current or 0) - (S.drawer_slide_target or 0)) < 0.001
      local vok, verr = pcall(Vouchers.draw, vctx)
      if not vok then
        love.graphics.setScissor()
        pcall(love.graphics.pop)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
        local vmsg = tostring(verr)
        if vmsg ~= _voucher_err_last then
          _voucher_err_last = vmsg
          print("[neuro-game] VOUCHER DRAWER ERROR: " .. vmsg)
        end
      end
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
  if neuro_now() > G.NEURO.egg.expires_at then
    local img = G.NEURO.egg.img
    if img and img ~= false and img.release then pcall(img.release, img) end
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

function HUD.draw_indicator()
  local t0 = (love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
  local a, b = draw_neuro_indicator()
  if t0 then
    if DebugStats.note_hud_ms then
      DebugStats.note_hud_ms((love.timer.getTime() - t0) * 1000)
    end
    if DebugStats.note_draw_stats and DebugStats.wants_draw_stats() then
      DebugStats.note_draw_stats()
    end
  end
  return a, b
end
HUD.draw_login = draw_login_animation
HUD.draw_cookie = draw_neuro_cookie
HUD.hook_card_draw = hook_card_draw
HUD.update_joker_showcase = update_joker_showcase
HUD.update_buy_showcase = update_buy_showcase
HUD.panel_layout = panel_layout
HUD.panel_available_height = panel_available_height
HUD.trunc = trunc
HUD.wrapped_lines = wrapped_lines
HUD.PANEL_BASE_W = 320
HUD.PANEL_MARGIN = PANEL_MARGIN
if rawget(_G, "NEURO_TEST") then
  HUD.safe_showcase_desc = safe_showcase_desc
  HUD._test = {
    panel_layout = panel_layout,
    panel_available_height = panel_available_height,
    build_panel_rows = build_panel_rows,
  }
end

return HUD
