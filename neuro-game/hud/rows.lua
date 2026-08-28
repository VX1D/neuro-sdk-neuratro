local ModifierBadges = require("render.modifier_badges")

local Rows = {}

Rows.DESC_MAX_LINES = 3
Rows.COMPACT_HYST = 24

local _badge_cache = setmetatable({}, { __mode = "k" })

local function badge_version(badges)
  return type(badges) == "table" and badges._v or nil
end

function Rows.badge_layout(key, badges, font, w, gap, max_rows)
  local version = badge_version(badges)
  if key == nil or version == nil then
    return ModifierBadges.layout(badges, font, w, gap, max_rows)
  end
  local per = _badge_cache[key]
  if not per then per = {}; _badge_cache[key] = per end
  local e = per[w]
  if e and e.font == font and e.gap == gap and e.max_rows == max_rows
    and e.version == version then
    return e.layout
  end
  local layout = ModifierBadges.layout(badges, font, w, gap, max_rows)
  per[w] = {
    font = font, gap = gap, max_rows = max_rows,
    version = version, layout = layout,
  }
  return layout
end

function Rows.header(color, text)       return { kind = "header", color = color, text = text } end
function Rows.line(color, text, indent) return { kind = "line",   color = color, text = text, indent = indent or 8 } end
function Rows.sub(color, text, indent)  return { kind = "sub",    color = color, text = text, indent = indent or 14 } end
function Rows.sep()                     return { kind = "sep" } end
function Rows.carousel(cards, which)    return { kind = "carousel", cards = cards, which = which } end
function Rows.emptyslots(limit, which)  return { kind = "emptyslots", limit = limit, which = which } end
function Rows.deckback(center, name, desc, color) return { kind = "deckback", center = center, text = name, desc = desc, color = color } end

function Rows.note(color, text, indent)     return { kind = "note",     color = color, text = text, indent = indent or 14 } end
function Rows.descwrap(color, text, indent) return { kind = "descwrap", color = color, text = text, indent = indent or 16 } end
function Rows.shopcard(color, text, card, cost, afford, indent, badges)
  return { kind = "shopcard", color = color, text = text, card = card, cost = cost, afford = afford,
    indent = indent or 8, badges = badges or {} }
end

function Rows.height(r, m)
  local k = r.kind
  if k == "sep" then
    return m.sep_h
  elseif k == "carousel" then
    return m.card_line_h + m.small_line_h * 3 + m.carousel_pad
  elseif k == "shopcard" then
    if r.badges and #r.badges > 0 then
      local unit = m.badge_unit or 1
      local bh = m.small_line_h * 2
      if m.small_font then
        local w = math.max(20, r.badge_w or (m.badge_w or m.content_w or 0) - (r.indent or 0))
        local ok, layout = pcall(Rows.badge_layout, r.card, r.badges, m.small_font, w, unit, 1)
        if ok and layout and layout.height and layout.height > 0 then bh = layout.height end
      end
      return m.card_line_h + bh + (m.badge_gap or 2)
    end
    return m.card_line_h
  elseif k == "note" then
    return m.small_line_h + 2
  elseif k == "descwrap" then
    local indent = r.indent or 0
    local lines = m.wrap(r.text or "", math.max(20, m.content_w - indent), m.small_font)
    local count = #lines > 0 and #lines or 1
    if count > Rows.DESC_MAX_LINES then count = Rows.DESC_MAX_LINES end
    return (m.small_line_h * count) + 2
  elseif k == "sub" and m.font and m.wrap then
    local indent = r.indent or 0
    local lines = m.wrap(r.text or "", math.max(20, m.content_w - indent), m.font)
    local count = #lines > 0 and #lines or 1
    return m.line_h * count
  elseif k == "header" then
    return m.header_line_h or m.line_h
  elseif k == "emptyslots" then
    return m.card_line_h
  elseif k == "deckback" then
    local h = m.card_line_h
    if r.desc and r.desc ~= "" and m.wrap and m.small_font then
      local lines = m.wrap(r.desc, math.max(20, m.content_w), m.small_font)
      local count = #lines > 0 and #lines or 1
      h = h + m.small_line_h * count + 4
    end
    return h
  else
    return m.line_h
  end
end

function Rows.want_compact(compact, total_h, pref_h)
  if compact and total_h < pref_h - Rows.COMPACT_HYST then compact = false end
  if total_h > pref_h then compact = true end
  return compact
end

function Rows.compact_metrics(m, small_text_h, n)
  m.line_h = small_text_h + n(3)
  m.small_line_h = small_text_h + n(1)
  m.card_line_h = n(26)
  m.sep_h = n(6)
  m.header_line_h = small_text_h + n(3)
end

Rows.H_GROW_SPEED, Rows.H_SHRINK_SPEED = 9.0, 6.0

function Rows.ease_height(cur, target, dt)
  local diff = target - cur
  if math.abs(diff) < 0.5 then return target end
  local spd = diff > 0 and Rows.H_GROW_SPEED or Rows.H_SHRINK_SPEED
  return cur + diff * math.min(1, spd * (dt or 0))
end

function Rows.pack_columns(rows, m, avail_data, max_cols, heights)
  local cols, col_h, max_col = 1, 0, 0
  for i = 1, #rows do
    local hh = heights and heights[i] or Rows.height(rows[i], m)
    if col_h > 0 and col_h + hh > avail_data then
      cols = cols + 1
      col_h = 0
    end
    col_h = col_h + hh
    if col_h > max_col then max_col = col_h end
  end
  if cols > max_cols then cols = max_cols end
  return cols, math.min(max_col, avail_data)
end

Rows.COLS_UNLATCH_STREAK = 180

function Rows.latch_columns(latch, want, sig, max_cols)
  want = math.max(1, math.min(tonumber(want) or 1, max_cols or 1))
  if type(latch) ~= "table" or latch.sig ~= sig then
    latch = { sig = sig, cols = want, low_streak = 0 }
    return latch, want
  end
  if want > latch.cols then
    latch.cols, latch.low_streak = want, 0
  elseif want < latch.cols then
    latch.low_streak = (latch.low_streak or 0) + 1
    if latch.low_streak >= Rows.COLS_UNLATCH_STREAK then
      latch.cols, latch.low_streak = want, 0
    end
  else
    latch.low_streak = 0
  end
  if latch.cols > max_cols then latch.cols = max_cols end
  return latch, latch.cols
end

return Rows
