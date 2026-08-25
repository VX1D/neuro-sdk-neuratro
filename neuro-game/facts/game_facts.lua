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
        .. tostring(enh) .. tostring(seal) .. tostring(ed)
        .. (c.debuff and "x" or "") .. (c.facing == "back" and "f" or "")
    end
  end
  sig[#sig + 1] = "h" .. table.concat(f.hl_indices, ".")
  sig[#sig + 1] = "d" .. f.deck_n
  if G and G.GAME then
    local gm = G.GAME
    sig[#sig + 1] = "$" .. tostring(gm.dollars or 0)
    sig[#sig + 1] = "S" .. tostring(gm.chips or 0)
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
  end
  if G and G.GAME and G.GAME.current_round then
    sig[#sig + 1] = "SR" .. tostring(G.GAME.current_round.reroll_cost_increase or 0)
  end
  f.content_sig = table.concat(sig, "|")
  return f
end

function M.hand_can_score()
  return require("core.state").get_state_name() == "SELECTING_HAND"
end

function M.hands_left() return (G and G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left) or 0 end
function M.discards_left() return (G and G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left) or 0 end

function M.visible_hand_names()
  local hands = G and G.GAME and G.GAME.hands
  if type(hands) ~= "table" then return nil end
  local out = {}
  for name, hand in pairs(hands) do
    if type(hand) == "table" and hand.visible == true and type(name) == "string" and name ~= "" then
      out[#out + 1] = name
    end
  end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end

-- A round of the mod is a blind the model resolved: the game counts only played blinds via
-- ease_round(1) in select_blind (dump functions/button_callbacks.lua:2576), while skip_blind
-- (:2801) bumps G.GAME.skips instead.
function M.round()
  local round = tonumber(G and G.GAME and G.GAME.round)
  if not round then return nil end
  return round + (tonumber(G.GAME.skips) or 0)
end

function M.ante(default) return (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or default end

function M.reserved_dollars() return tonumber(G and G.NEURO and G.NEURO.reserved_dollars or 0) or 0 end

function M.blind_reward()
  if not (G and G.NEURO) then return 0 end
  local stamped = tonumber(G.NEURO.blind_reward_round)
  local round = tonumber(G.GAME and G.GAME.round)
  if stamped and round and stamped ~= round then return 0 end
  return tonumber(G.NEURO.blind_reward_cache) or 0
end

return M
