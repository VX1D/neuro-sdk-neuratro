local Scoring = {}

function Scoring.joker_summary()
  if not (G and G.jokers and G.jokers.cards) then return nil end
  local chips, mult, xmult, c_mult = 0, 0, 1, 0
  local by_type = {}
  local function bucket(t)
    by_type[t] = by_type[t] or { mult = 0, chips = 0, xmult = 1 }
    return by_type[t]
  end
  for _, card in ipairs(G.jokers.cards) do
    if not card.debuff then
      local a = card.ability or {}
      local t = a.type
      if t == "" then t = nil end
      chips = chips + (tonumber(a.h_mod) or 0) + (tonumber(a.chips) or 0)
      mult = mult + (tonumber(a.h_mult) or 0) + (tonumber(a.mult) or 0)
      if card.edition and type(card.edition) == "table" then
        if card.edition.chips then chips = chips + card.edition.chips end
        if card.edition.mult then mult = mult + card.edition.mult end
        if card.edition.x_mult then xmult = xmult * card.edition.x_mult end
      end
      local xm = tonumber(a.x_mult)
      if xm and xm ~= 1 then
        if not t then
          xmult = xmult * xm
        else
          bucket(t).xmult = bucket(t).xmult * xm
        end
      end
      c_mult = c_mult + (tonumber(a.c_mult) or 0)
      local tm = tonumber(a.t_mult) or 0
      local tc = tonumber(a.t_chips) or 0
      if t and (tm ~= 0 or tc ~= 0) then
        bucket(t).mult = bucket(t).mult + tm
        bucket(t).chips = bucket(t).chips + tc
      end
    end
  end
  if chips == 0 and mult == 0 and xmult == 1 and c_mult == 0 and not next(by_type) then return nil end
  return { chips = chips, mult = mult, xmult = xmult, c_mult = c_mult,
    cond_by_type = by_type }
end

return Scoring
