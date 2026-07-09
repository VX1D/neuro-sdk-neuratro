local M = {}

function M.build()
  local f = {
    hl_indices = {},
    deck_n = 0,
  }
  if G and G.hand then
    local hi = G.hand.highlighted
    local hc = G.hand.cards
    if hi then
      if hc then
        for _, c in ipairs(hi) do
          for i, hcard in ipairs(hc) do
            if hcard == c then f.hl_indices[#f.hl_indices + 1] = i; break end
          end
        end
      end
    end
  end
  if G and G.deck and G.deck.cards then
    f.deck_n = #G.deck.cards
  end
  local sig = {}
  if G and G.hand and G.hand.cards then
    for _, c in ipairs(G.hand.cards) do
      local b = c.base or {}
      local ab = c.ability or {}
      local enh = ab.enhancement or (c.config and c.config.center and c.config.center.key) or ""
      local seal = c.seal or ""
      local ed = (c.edition and (c.edition.key or c.edition.type)) or ""
      sig[#sig + 1] = tostring(b.value or "?") .. (b.suit and tostring(b.suit) or "?")
        .. tostring(enh) .. tostring(seal) .. tostring(ed) .. (c.debuff and "x" or "")
    end
  end
  sig[#sig + 1] = "h" .. table.concat(f.hl_indices, ".")
  sig[#sig + 1] = "d" .. f.deck_n
  if G and G.GAME then
    local gm = G.GAME
    sig[#sig + 1] = "$" .. tostring(gm.dollars or 0)
    local cr = gm.current_round or {}
    sig[#sig + 1] = "H" .. tostring(cr.hands_left or 0) .. "D" .. tostring(cr.discards_left or 0)
    sig[#sig + 1] = "R" .. tostring(cr.reroll_cost or 0) .. "F" .. tostring(cr.free_rerolls or 0)
    sig[#sig + 1] = "P" .. tostring(gm.pack_choices or 0)
    local bl = gm.blind or {}
    sig[#sig + 1] = "B" .. tostring(bl.chips or 0) .. "x" .. tostring(bl.mult or 0)
  end
  if G and G.consumeables and G.consumeables.cards then
    local ck = {}
    for _, c in ipairs(G.consumeables.cards) do
      ck[#ck + 1] = (c.config and c.config.center and c.config.center.key) or "?"
    end
    sig[#sig + 1] = "co" .. #ck .. ":" .. table.concat(ck, ".")
  end
  if G and G.GAME and G.GAME.hands then
    local lv = 0
    for _, hd in pairs(G.GAME.hands) do
      if type(hd) == "table" then lv = lv + (tonumber(hd.level) or 0) end
    end
    sig[#sig + 1] = "LV" .. lv
  end
  if G and G.NEURO then
    sig[#sig + 1] = "RES" .. tostring(G.NEURO.reserved_dollars or 0)
    sig[#sig + 1] = "SR" .. tostring(G.NEURO.shop_reroll_count or 0)
  end
  f.content_sig = table.concat(sig, "|")
  return f
end

return M
