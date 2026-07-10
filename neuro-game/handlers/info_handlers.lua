local Utils = require("util.utils")
local Scoring = require("util.scoring")
local CtxEconomy = require("context.ctx_economy")
local CardUtil = require("facts.card_util")

local function safe_context_result(fetch_fn, fallback)
  local ok, value = pcall(fetch_fn)
  if not ok then
    return fallback or ("Context unavailable: " .. tostring(value))
  end
  if type(value) == "table" then
    local lines = {}
    local has_array = false
    for _, v in ipairs(value) do
      has_array = true
      lines[#lines + 1] = tostring(v)
    end
    if not has_array then
      local keys = {}
      for k in pairs(value) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        lines[#lines + 1] = tostring(k) .. ": " .. tostring(value[k])
      end
    end
    return table.concat(lines, "\n")
  end
  if value == nil then
    return fallback or "Context unavailable"
  end
  return tostring(value)
end

-- These context handlers share one shape: guard G/G.GAME (plus an optional extra field),
-- then defer to a Context getter with a fallback string.
local function make_context_handler(getter, fallback, extra_guard)
  return function(_data)
    if not G or not G.GAME or (extra_guard and not extra_guard()) then
      return nil, "Game not available yet."
    end
    return function()
      local Context = require("context.context")
      return safe_context_result(Context[getter], fallback)
    end
  end
end

local handle_scoring_explanation = make_context_handler("get_scoring_explanation", "Scoring explanation unavailable")
local handle_shop_context        = make_context_handler("get_shop_context", "Shop context unavailable")
local handle_blind_info          = make_context_handler("get_blind_info", "Blind info unavailable", function() return G.GAME.blind end)
local handle_hand_levels_info    = make_context_handler("get_hand_levels_info", "Hand levels unavailable", function() return G.GAME.hands end)
local handle_full_game_context   = make_context_handler("get_full_game_context", "Full game context unavailable")

local function handle_quick_status(_data)
  if not G or not G.GAME then
    return nil, "Game not available yet."
  end

  local status = {}

  table.insert(status, "=== QUICK STATUS ===")
  table.insert(status, "")

  if G.GAME.blind then
    local blind = G.GAME.blind
    local target = CtxEconomy.blind_target(blind) or 0
    table.insert(status, string.format("Blind: %s (Target: %s)", blind.name or "Unknown", Utils.fmt_num(target)))
  end

  table.insert(status, string.format("Money: $%d", G.GAME.dollars or 0))

  if G.GAME.current_round then
    table.insert(status, string.format("Hands: %d | Discards: %d",
      G.GAME.current_round.hands_left or 0,
      G.GAME.current_round.discards_left or 0))
  end

  if G.jokers and G.jokers.cards then
    local joker_count = #G.jokers.cards
    local joker_limit = CardUtil.joker_limit()
    table.insert(status, string.format("Jokers: %d/%d", joker_count, joker_limit))
    local agg = Scoring.joker_summary()
    if agg then
      local effects = {}
      if agg.xmult > 1 then table.insert(effects, string.format("x%.1f", agg.xmult)) end
      if agg.mult > 0 then table.insert(effects, "+" .. Utils.fmt_num(agg.mult) .. " Mult") end
      if agg.chips > 0 then table.insert(effects, "+" .. Utils.fmt_num(agg.chips) .. " Chips") end
      if #effects > 0 then table.insert(status, "Joker Power: " .. table.concat(effects, ", ")) end
    end
  end

  if G.hand and G.hand.cards and #G.hand.cards > 0 then
    table.insert(status, string.format("Hand: %d cards", #G.hand.cards))
  end

  local result = table.concat(status, "\n")
  return function()
    return result
  end
end

local function resolve_selection(data)
  if data and type(data.indices) == "table" and #data.indices > 0 then
    if not (G and G.hand and G.hand.cards) then
      return nil, "Hand is not available."
    end
    local sel, invalid, dup, seen = {}, {}, {}, {}
    for _, idx in ipairs(data.indices) do
      local n = tonumber(idx)
      local c = n and G.hand.cards[n]
      if c then
        if seen[n] then
          dup[#dup + 1] = tostring(idx)
        else
          seen[n] = true
          sel[#sel + 1] = c
        end
      else
        invalid[#invalid + 1] = tostring(idx)
      end
    end
    if #sel == 0 then
      return nil, string.format("No valid indices: hand has %d cards, use 1-%d.", #G.hand.cards, #G.hand.cards)
    end
    local notes = {}
    if #invalid > 0 then
      notes[#notes + 1] = string.format("%d index(es) out of range 1-%d ignored (%s)",
        #invalid, #G.hand.cards, table.concat(invalid, ","))
    end
    if #dup > 0 then
      notes[#notes + 1] = string.format("duplicate index(es) ignored (%s): each card counts once", table.concat(dup, ","))
    end
    local limit = CardUtil.highlight_limit()
    if #sel > limit then
      notes[#notes + 1] = string.format("%d cards selected but at most %d can be played in one hand", #sel, limit)
    end
    local note = (#notes > 0) and ("NOTE: " .. table.concat(notes, "; ") .. ".") or nil
    return sel, nil, note
  end
  -- never fall back to engine UI-highlight state: no persistent selection exists in this interface
  return nil, "Provide indices from the H: hand list (e.g. {\"indices\":[1,3,5]})."
end

-- effective scoring set per engine final_scoring_hand (state_events.lua:596)
local function effective_scoring_set(sel, poker)
  local in_poker = {}
  if type(poker) == "table" then for _, c in ipairs(poker) do in_poker[c] = true end end
  local splash = false
  if type(find_joker) == "function" then
    local ok, r = pcall(find_joker, "Splash")
    splash = ok and type(r) == "table" and next(r) ~= nil
  end
  local function flag(fn, c)
    if type(fn) == "function" then local ok, v = pcall(fn, c); return ok and v and true or false end
    return false
  end
  local never_fn = SMODS and SMODS.never_scores
  local always_fn = SMODS and SMODS.always_scores
  local out = {}
  for _, c in ipairs(sel) do
    if not flag(never_fn, c) and (splash or in_poker[c] or flag(always_fn, c)) then
      out[#out + 1] = c
    end
  end
  return out
end

local function handle_simulate_hand(data)
  if not (G and G.hand and G.hand.cards) then
    return nil, "Hand not available yet."
  end
  local sel, serr, snote = resolve_selection(data)
  if not sel then return nil, serr end
  if #sel == 0 then
    return nil, "Provide indices from the H: hand list (e.g. {\"indices\":[1,3,5]})."
  end
  if not G.FUNCS or not G.FUNCS.get_poker_hand_info then
    return nil, "Poker hand info function is not available."
  end

  local ok, hand_info, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, sel)
  local ht = ok and ((type(hand_info) == "string" and hand_info ~= "" and hand_info)
    or (type(hand_info) == "table" and hand_info.type)) or nil
  if not ht then
    return nil, "Could not evaluate the provided cards."
  end

  local DebuffFacts = require("facts.debuff_facts")
  local results = { "=== SELECTED HAND ===", "" }
  if snote then table.insert(results, snote) end
  table.insert(results, "Hand Type: " .. ht)

  local hand_data = G.GAME and G.GAME.hands and G.GAME.hands[ht] or nil
  if hand_data then
    local chips, mult = hand_data.chips or 0, hand_data.mult or 0
    if DebuffFacts.flint_active() then
      chips, mult = DebuffFacts.flint_halve(chips, mult)
      table.insert(results, string.format("Base (Level %s; The Flint HALVES base): %s chips x %s mult",
        tostring(hand_data.level), Utils.fmt_num(chips), Utils.fmt_num(mult)))
    else
      table.insert(results, string.format("Base (Level %s): %s chips x %s mult",
        tostring(hand_data.level), Utils.fmt_num(chips), Utils.fmt_num(mult)))
    end
  end

  local eff = effective_scoring_set(sel, scoring_hand)
  local scoring = {}
  for _, c in ipairs(eff) do
    if c and c.base then scoring[#scoring + 1] = Utils.playing_card_label(c) end
  end
  if #scoring > 0 then
    table.insert(results, "Scoring cards: " .. table.concat(scoring, ", "))
  end

  local ndeb = DebuffFacts.count(eff)
  if ndeb > 0 then
    table.insert(results, string.format("WARNING: %d of the scoring cards are DEBUFFED (they score 0); the Base figure ignores debuffs, so the real result is far lower.", ndeb))
  end

  table.insert(results, "")
  table.insert(results, "No final score is computed: your jokers (incl. retrigger/copy/conditional/random) "
    .. "and card editions decide the real result. Judge it yourself from the base value above, the L: level "
    .. "table, and your jokers.")

  local result = table.concat(results, "\n")
  return function()
    return result
  end
end

return {
  safe_context_result = safe_context_result,
  handle_scoring_explanation = handle_scoring_explanation,
  handle_shop_context = handle_shop_context,
  handle_blind_info = handle_blind_info,
  handle_hand_levels_info = handle_hand_levels_info,
  handle_full_game_context = handle_full_game_context,
  handle_quick_status = handle_quick_status,
  handle_simulate_hand = handle_simulate_hand,
}
