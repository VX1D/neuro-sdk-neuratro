local Rows = {}

function Rows.header(color, text)       return { kind = "header", color = color, text = text } end
function Rows.line(color, text, indent) return { kind = "line",   color = color, text = text, indent = indent or 8 } end
function Rows.sub(color, text, indent)  return { kind = "sub",    color = color, text = text, indent = indent or 14 } end
function Rows.sep()                     return { kind = "sep" } end
function Rows.carousel(cards, which)    return { kind = "carousel", cards = cards, which = which } end

function Rows.note(color, text, indent)     return { kind = "note",     color = color, text = text, indent = indent or 14 } end
function Rows.descwrap(color, text, indent) return { kind = "descwrap", color = color, text = text, indent = indent or 16 } end
function Rows.shopcard(color, text, card, cost, afford, indent)
  return { kind = "shopcard", color = color, text = text, card = card, cost = cost, afford = afford, indent = indent or 8 }
end

function Rows.height(r, m)
  local k = r.kind
  if k == "sep" then
    return m.sep_h
  elseif k == "carousel" then
    return m.card_line_h + m.small_line_h * 3 + m.carousel_pad
  elseif k == "shopcard" then
    return m.card_line_h
  elseif k == "note" then
    return m.small_line_h + 2
  elseif k == "descwrap" then
    local indent = r.indent or 0
    local lines = m.wrap(r.text or "", math.max(20, m.content_w - indent), m.small_font)
    local count = #lines > 0 and #lines or 1
    return (m.small_line_h * count) + 2
  elseif k == "sub" and m.font and m.wrap then
    local indent = r.indent or 0
    local lines = m.wrap(r.text or "", math.max(20, m.content_w - indent), m.font)
    local count = #lines > 0 and #lines or 1
    return m.line_h * count
  else
    return m.line_h
  end
end

return Rows
