-- On-demand verbose info actions; keep separate from the per-turn surface (context_compact.lua)
local Context = {}
local Utils = require "util.utils"
local Scoring = require "util.scoring"
local CardUtil = require "facts.card_util"
local CtxEconomy = require "context.ctx_economy"
local HandFacts = require "facts.hand_facts"
local DebuffFacts = require "facts.debuff_facts"
local CtxHelpers = require "context.ctx_helpers"
local safe_name_or = Utils.safe_name_or

local function safe_description(loc_txt, card, max_len)
  return Utils.safe_description(loc_txt, card, max_len)
end

function Context.get_poker_hand_info()
  local context_hands = {}
  for _, h in ipairs(HandFacts.levels()) do
    table.insert(context_hands, string.format(
      "%s: level %s, chips %s, mult %s", h.name, tostring(h.level), tostring(h.chips), tostring(h.mult)))
  end
  return context_hands
end

function Context.get_joker_info()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    return { "No jokers owned." }
  end

  local jokers = {}
  for index, card in ipairs(G.jokers.cards) do
    local name = safe_name_or(card)
    local ability = card.ability or {}
    local desc = Utils.card_description(card)

    local details = string.format("%d: %s", index, name)

    for _, p in ipairs(CtxHelpers.effect_parts(ability)) do
      details = details .. " [" .. p .. "]"
    end
    local tags = CtxHelpers.joker_tags(card)
    if tags ~= "-" then
      details = details .. " [" .. tags .. "]"
    end

    if desc and desc ~= "" then
      details = details .. " - " .. desc
    end

    table.insert(jokers, details)
  end

  return jokers
end

function Context.get_card_modifiers()
  if not G or not G.GAME then
    return {}
  end

  -- editions/seals/enhancements are per-card, not fields on G.GAME (G.GAME.edition etc never exist)
  local counts = { Editions = {}, Seals = {}, Enhancements = {} }
  local function tally(t, k)
    if not k or k == "" then return end
    k = tostring(k)
    t[k] = (t[k] or 0) + 1
  end
  local function scan_cards(cards)
    if not cards then return end
    for _, c in ipairs(cards) do
      tally(counts.Editions, CardUtil.edition_name(c.edition))
      tally(counts.Seals, CardUtil.seal_name(c.seal))
      tally(counts.Enhancements, CardUtil.enhancement_name(CardUtil.enhancement_key(c)))
    end
  end
  -- prefer G.playing_cards or play/discard cards get undercounted; fall back to hand+draw when unpopulated
  if type(G.playing_cards) == "table" and #G.playing_cards > 0 then
    scan_cards(G.playing_cards)
  else
    scan_cards(G.hand and G.hand.cards)
    scan_cards(G.deck and G.deck.cards)
  end

  local modifiers = {}
  for _, label in ipairs({ "Editions", "Seals", "Enhancements" }) do
    local parts = {}
    for k, n in pairs(counts[label]) do parts[#parts + 1] = k .. "x" .. n end
    if #parts > 0 then table.insert(modifiers, label .. " on cards (full deck): " .. table.concat(parts, ", ")) end
  end

  if #modifiers == 0 then
    return { "No card modifiers (editions/seals/enhancements) on any card in the deck." }
  end
  return modifiers
end

function Context.get_deck_types()
  local decks = {}
  for _, r in ipairs(require("facts.deck_facts").list_selectable_backs()) do
    decks[#decks + 1] = string.format("%s: %s", r.key, r.name)
  end
  return decks
end

local function analyze_hand_potential(cards)
  if not cards or #cards == 0 then return nil end
  local sh = HandFacts.shape(cards)
  return {
    total_cards = #cards,
    max_same_suit = sh.max_suit,
    flush_ready = sh.flush_ready, near_flush = sh.near_flush,
    straight_ready = sh.straight_ready, near_straight = sh.near_straight,
    has_pair = sh.pairs > 0,
    has_three = sh.trips > 0,
    has_four = sh.quads > 0,
  }
end

function Context.get_scoring_explanation(sel)
  if not G or not G.GAME then
    return {}
  end
  sel = sel or (G.hand and G.hand.highlighted) or {}

  local explanation = {
    "=== SCORING FORMULA ===",
    CtxHelpers.SCORING_FORMULA,
    "Played card rank chips: 2-10 = face value, J/Q/K = 10, A = 11.",
    "",
    "=== BASE HAND VALUES ===",
  }

  if DebuffFacts.flint_active() then
    table.insert(explanation, "(The Flint is active: these base chips/mult are already HALVED.)")
  end

  for _, h in ipairs(HandFacts.levels()) do
    table.insert(explanation, string.format("%s: Chips=%s, Mult=%s (Level %d)",
      h.name, Utils.fmt_num(h.chips), Utils.fmt_num(h.mult), h.level))
  end

  if #sel > 0 then
    if G.FUNCS and G.FUNCS.get_poker_hand_info then
      local ok, hand_info, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, sel)
      local ht = ok and type(hand_info) == "string" and hand_info ~= "" and hand_info or nil
      if ht then
        local hand_data = G.GAME.hands and G.GAME.hands[ht]
        if hand_data then
          table.insert(explanation, "")
          table.insert(explanation, "=== SELECTED HAND ===")
          table.insert(explanation, "Type: " .. ht)
          table.insert(explanation, "Level: " .. tostring(hand_data.level))
          local base_chips, base_mult = hand_data.chips, hand_data.mult
          if DebuffFacts.flint_active() then
            base_chips, base_mult = DebuffFacts.flint_halve(base_chips, base_mult)
            table.insert(explanation, "The Flint HALVES base chips and mult:")
          end
          table.insert(explanation, "Base Chips: " .. Utils.fmt_num(base_chips))
          table.insert(explanation, "Base Mult: " .. Utils.fmt_num(base_mult))
          local ndeb = DebuffFacts.count(scoring_hand)
          if ndeb > 0 then
            table.insert(explanation, string.format("WARNING: %d of the scoring cards are DEBUFFED (they score 0); the Base figures above ignore debuffs, so the real result is far lower.", ndeb))
          end
        end
      end
    end
  end

  if G.hand and G.hand.cards and #G.hand.cards > 0 then
    local potential = analyze_hand_potential(G.hand.cards)
    if potential then
      table.insert(explanation, "")
      table.insert(explanation, "=== HAND COMPOSITION ===")
      table.insert(explanation, string.format("Total cards: %d", potential.total_cards))
      if potential.flush_ready then
        table.insert(explanation, string.format("Flush ready (%d same suit)", potential.max_same_suit))
      elseif potential.near_flush then
        table.insert(explanation, string.format("Near flush (%d same suit)", potential.max_same_suit))
      end
      if potential.straight_ready then
        table.insert(explanation, "Straight ready")
      elseif potential.near_straight then
        table.insert(explanation, "Near straight")
      end
      if potential.has_four then
        table.insert(explanation, "Contains four of a kind")
      elseif potential.has_three then
        table.insert(explanation, "Contains three of a kind")
      elseif potential.has_pair then
        table.insert(explanation, "Contains at least one pair")
      end
    end
  end

  if G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
    table.insert(explanation, "")
    table.insert(explanation, "=== JOKER EFFECTS (Left to Right) ===")
    for index, card in ipairs(G.jokers.cards) do
      local joker_info = string.format("%d: %s", index, safe_name_or(card))
      for _, p in ipairs(CtxHelpers.effect_parts(card.ability)) do
        joker_info = joker_info .. " [" .. p .. "]"
      end
      if card.debuff then joker_info = joker_info .. " [DEBUFFED: contributes nothing]" end
      table.insert(explanation, joker_info)
    end
  end

  return explanation
end

function Context.get_joker_strategy()
  if not G or not G.jokers or not G.jokers.cards then
    return {}
  end

  local strategy = {
    "=== JOKER SNAPSHOT ===",
    "",
  }

  if #G.jokers.cards == 0 then
    table.insert(strategy, "No jokers owned.")
    return strategy
  end

  local xmult_count = 0

  for index, card in ipairs(G.jokers.cards) do
    local ability = card.ability or {}
    local center = card.config and card.config.center or {}
    local rarity = CardUtil.rarity_name(center.rarity)
    local sell_value = card.sell_cost or 0

    if ability.x_mult and ability.x_mult ~= 1 then
      xmult_count = xmult_count + 1
    end

    local effects = CtxHelpers.effect_parts(ability)
    local tags = CtxHelpers.joker_tags(card)

    local effect_str = #effects > 0 and " - " .. table.concat(effects, ", ") or ""
    local special_str = tags ~= "-" and " (" .. tags .. ")" or ""

    table.insert(strategy, string.format("%d. %s (%s) [Sell: $%d]%s%s",
      index, safe_name_or(card), rarity, sell_value, effect_str, special_str))
  end

  table.insert(strategy, "")
  table.insert(strategy, "=== JOKER SUMMARY ===")
  local js = Scoring.joker_summary()
  if js then
    if js.xmult > 1 then table.insert(strategy, string.format("Total XMult multiplier: x%.2f", js.xmult)) end
    if js.mult > 0 then table.insert(strategy, "Total +Mult from jokers: +" .. Utils.fmt_num(js.mult)) end
    if js.chips > 0 then table.insert(strategy, "Total +Chips from jokers: +" .. Utils.fmt_num(js.chips)) end
    if js.c_mult > 0 then table.insert(strategy, "Total +Mult/card from jokers: +" .. Utils.fmt_num(js.c_mult)) end
    for _, line in ipairs(CtxHelpers.conditional_joker_lines(js)) do table.insert(strategy, line) end
  end

  do
    local limit = CardUtil.joker_limit()
    if #G.jokers.cards < limit then
      table.insert(strategy, "")
      table.insert(strategy, string.format("Joker slots free: %d (%d/%d used)",
        limit - #G.jokers.cards, #G.jokers.cards, limit))
    end
  end

  local has_blueprint = false
  local has_brainstorm = false
  local has_trib = false
  local has_steel_joker = false

  for _, card in ipairs(G.jokers.cards) do
    local center = card.config and card.config.center or {}
    local key = center.key or ""
    if key == "j_blueprint" then has_blueprint = true end
    if key == "j_brainstorm" then has_brainstorm = true end
    if key == "j_triboulet" then has_trib = true end
    if key == "j_steel_joker" then has_steel_joker = true end
  end

  if has_blueprint or has_brainstorm or xmult_count > 1 or has_trib or has_steel_joker then
    table.insert(strategy, "")
    table.insert(strategy, "=== JOKER INTERACTIONS ===")

    if has_blueprint then
      table.insert(strategy, "Blueprint: Copies effect of joker to its right")
    end
    if has_brainstorm then
      table.insert(strategy, "Brainstorm: Copies effect of leftmost joker")
    end
    if xmult_count > 1 then
      table.insert(strategy, "Multiple xMult: Multipliers stack multiplicatively")
    end
    if has_trib then
      table.insert(strategy, "Triboulet: Affected by Kings and Queens played")
    end
    if has_steel_joker then
      local steel_count = 0
      local pool = (type(G.playing_cards) == "table" and G.playing_cards)
        or (G.deck and G.deck.cards) or {}
      for _, c in ipairs(pool) do
        if CardUtil.enhancement_key(c) == "m_steel" then
          steel_count = steel_count + 1
        end
      end
      table.insert(strategy, string.format("Steel Joker: %d Steel cards in deck", steel_count))
    end
  end

  table.insert(strategy, "")
  table.insert(strategy, "=== JOKER ORDERING RULES ===")
  table.insert(strategy, "Jokers evaluate left-to-right in order")
  table.insert(strategy, "Order affects how bonuses combine:")
  table.insert(strategy, "- each joker's full effect resolves before the next is applied")
  table.insert(strategy, "- an xMult multiplies the running total at the moment its slot is reached")
  table.insert(strategy, "- so a +Chips/+Mult joker to the RIGHT of an xMult is added after that multiply and is NOT multiplied by it")

  return strategy
end

function Context.get_shop_context()
  if not G or not G.GAME then
    return {}
  end

  local context = {
    "=== SHOP ECONOMY ===",
    "",
    "Available Funds: $" .. tostring(G.GAME.dollars or 0),
    "Reroll Cost: $" .. (function() local e = CtxEconomy.reroll_facts().effective; return type(e) == "number" and tostring(e) or "?" end)(),
    "Joker Capacity: " .. tostring(CardUtil.joker_count()) .. "/" .. tostring(CardUtil.joker_limit()),
    "",
  }

  if CtxEconomy.no_interest() then
    table.insert(context, "Interest: disabled this run")
  elseif G.GAME.interest_cap then
    table.insert(context, string.format("Interest: %.0f%% on the first $%d held (max +$%d/round)",
      CtxEconomy.rate_pct(),
      CtxEconomy.interest_cap(),
      CtxEconomy.max_interest()
    ))
  end

  if G.shop_jokers and G.shop_jokers.cards and #G.shop_jokers.cards > 0 then
    table.insert(context, "")
    table.insert(context, "=== SHOP JOKERS ===")
    for i, card in ipairs(G.shop_jokers.cards) do
      local center = card.config and card.config.center or {}
      local ability = card.ability or {}
      local name = safe_name_or(card)
      local cost = card.cost or 0
      local rarity = CardUtil.rarity_name(center.rarity)
      local af = CtxEconomy.item_afford_status(card, "shop_jokers")
      local status
      if not af.afford then status = "Cannot afford ($" .. tostring(cost) .. ")"
      elseif not af.has_space then status = "$" .. tostring(cost) .. " (no joker slot)"
      else status = "$" .. tostring(cost) end

      local effects = CtxHelpers.effect_parts(ability)

      local effect_str = #effects > 0 and " - " .. table.concat(effects, ", ") or ""
      local desc = Utils.card_description(card) or ""
      if desc ~= "" then
        desc = " [" .. desc .. "]"
      end

      table.insert(context, string.format("%d: %s (%s) [%s]%s%s", i, name, rarity, status, effect_str, desc))
    end
  end

  if G.shop_vouchers and G.shop_vouchers.cards and #G.shop_vouchers.cards > 0 then
    table.insert(context, "")
    table.insert(context, "=== SHOP VOUCHERS ===")
    for i, card in ipairs(G.shop_vouchers.cards) do
      local name = safe_name_or(card)
      local cost = card.cost or 0
      local can_afford = CtxEconomy.item_afford_status(card, "shop_vouchers").ok
      local status = can_afford and "$" .. tostring(cost) or "Cannot afford ($" .. tostring(cost) .. ")"
      local desc = Utils.card_description(card) or ""
      if desc ~= "" then
        table.insert(context, string.format("%d: %s [%s] - %s", i, name, status, desc))
      else
        table.insert(context, string.format("%d: %s [%s]", i, name, status))
      end
    end
  end

  if G.shop_booster and G.shop_booster.cards and #G.shop_booster.cards > 0 then
    table.insert(context, "")
    table.insert(context, "=== SHOP BOOSTER PACKS ===")
    for i, card in ipairs(G.shop_booster.cards) do
      local center = card.config and card.config.center or {}
      local name = safe_name_or(card)
      local cost = card.cost or 0
      local can_afford = CtxEconomy.item_afford_status(card, "shop_booster").ok
      local status = can_afford and "$" .. tostring(cost) or "Cannot afford ($" .. tostring(cost) .. ")"
      local desc = Utils.card_description(card) or ""
      local set = center.set or "Booster"
      if desc ~= "" then
        table.insert(context, string.format("%d: %s (%s) [%s] - %s", i, name, set, status, desc))
      else
        table.insert(context, string.format("%d: %s (%s) [%s]", i, name, set, status))
      end
    end
  end

  return context
end

function Context.get_blind_info()
  if not G or not G.GAME or not G.GAME.blind then
    return {}
  end

  local blind = G.GAME.blind
  local blind_type = CtxEconomy.blind_type(blind)
  blind_type = blind_type and tostring(blind_type) or "Unknown"
  local target = CtxEconomy.blind_target(blind) or 0
  local hands_left = G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local discards_left = G.GAME.current_round and G.GAME.current_round.discards_left or 0

  local info = {
    "=== CURRENT BLIND ===",
    "",
    "Type: " .. blind_type,
    "Name: " .. (blind.name or "Unknown"),
    "Target Score: " .. Utils.fmt_num(target),
  }

  if hands_left > 0 then
    local remaining = CtxEconomy.blind_remaining(blind) or target
    local score_per_hand = math.ceil(remaining / hands_left)
    table.insert(info, "Score needed per hand: ~" .. Utils.fmt_num(score_per_hand) .. " (over remaining hands)")
  end

  table.insert(info, "")
  table.insert(info, "=== RESOURCES ===")
  table.insert(info, string.format("Hands Remaining: %d", hands_left))
  table.insert(info, string.format("Discards Remaining: %d", discards_left))
  table.insert(info, string.format("Current Money: $%d", G.GAME.dollars or 0))
  table.insert(info, string.format("Cards in Draw Pile: %d", G.deck and G.deck.cards and #G.deck.cards or 0))
  table.insert(info, string.format("Cards in Hand: %d", G.hand and G.hand.cards and #G.hand.cards or 0))

  if blind.boss then
    table.insert(info, "")
    table.insert(info, "=== BOSS BLIND DEBUFF ===")
    local debuff_desc = DebuffFacts.boss_debuff_text(blind)
    if debuff_desc == "" then debuff_desc = "Unknown debuff" end
    table.insert(info, debuff_desc)

    if blind.debuff then
      table.insert(info, "")
      table.insert(info, "Status: Card debuffs are active")
    end
  end

  local js = Scoring.joker_summary()
  if js then
    table.insert(info, "")
    table.insert(info, "=== YOUR JOKER POWER ===")
    if js.xmult > 1 then table.insert(info, string.format("XMult: x%.2f", js.xmult)) end
    if js.mult > 0 then table.insert(info, "+Mult: +" .. Utils.fmt_num(js.mult)) end
    if js.chips > 0 then table.insert(info, "+Chips: +" .. Utils.fmt_num(js.chips)) end
    if js.c_mult > 0 then table.insert(info, "+Mult/card: +" .. Utils.fmt_num(js.c_mult)) end
    for _, line in ipairs(CtxHelpers.conditional_joker_lines(js)) do table.insert(info, line) end
  end

  return info
end

function Context.get_hand_levels_info()
  if not G or not G.GAME or not G.GAME.hands then
    return {}
  end

  local levels = {
    "=== HAND LEVELS ===",
    "",
    "Hands level up when you play them. Higher levels = more chips & mult.",
    "",
  }

  local rows = HandFacts.levels()
  table.sort(rows, function(a, b)
    return (a.chips * a.mult) > (b.chips * b.mult)
  end)

  for _, row in ipairs(rows) do
    table.insert(levels, string.format("%s (L%d): %s chips x %s mult = %s base score [%d plays]",
      row.name, row.level, Utils.fmt_num(row.chips), Utils.fmt_num(row.mult),
      Utils.fmt_num(row.chips * row.mult), row.played or 0))
  end

  return levels
end

function Context.get_full_game_context()
  local all_info = {}

  local scoring = Context.get_scoring_explanation()
  for _, line in ipairs(scoring) do
    table.insert(all_info, line)
  end

  table.insert(all_info, "")
  local blind = Context.get_blind_info()
  for _, line in ipairs(blind) do
    table.insert(all_info, line)
  end

  table.insert(all_info, "")
  local joker_strategy = Context.get_joker_strategy()
  for _, line in ipairs(joker_strategy) do
    table.insert(all_info, line)
  end

  table.insert(all_info, "")
  local shop = Context.get_shop_context()
  for _, line in ipairs(shop) do
    table.insert(all_info, line)
  end

  table.insert(all_info, "")
  local modifiers = Context.get_card_modifiers()
  for _, line in ipairs(modifiers) do
    table.insert(all_info, line)
  end

  return all_info
end

function Context.get_consumables_info()
  if not G or not G.consumeables then
    return {"Consumables area not available"}
  end

  local info = {"=== CONSUMABLES ===", ""}

  if not G.consumeables.cards or #G.consumeables.cards == 0 then
    table.insert(info, "No consumable cards")
    return info
  end

  table.insert(info, string.format("Slots: %d/%d", #G.consumeables.cards, CardUtil.consumable_limit()))
  table.insert(info, "")

  for i, card in ipairs(G.consumeables.cards) do
    local center = card.config and card.config.center or {}
    local name = safe_name_or(card)
    local set = center.set or "Consumable"
    local desc = Utils.card_description_with_fallback(card)

    table.insert(info, string.format("%d. %s (%s)", i, name, set))
    if desc ~= "" then
      table.insert(info, "   " .. desc)
    end
  end

  return info
end

function Context.get_hand_details()
  if not G or not G.hand or not G.hand.cards then
    return {"Hand not available"}
  end

  local info = {"=== HAND CARDS ===", ""}

  if #G.hand.cards == 0 then
    table.insert(info, "No cards in hand")
    return info
  end

  table.insert(info, string.format("Cards: %d/%d", #G.hand.cards, CardUtil.hand_limit()))
  table.insert(info, "")

  for i, card in ipairs(G.hand.cards) do
    local edition = card.edition or {}
    local seal = card.seal

    local card_name = Utils.playing_card_label(card)
    local details = {}

    local enh_key = CardUtil.enhancement_key(card)
    if enh_key then
      table.insert(details, CardUtil.enhancement_name(enh_key))
    end

    local ed_name = CardUtil.edition_name(edition)
    if ed_name then
      table.insert(details, ed_name .. " Edition")
    end

    if seal then
      table.insert(details, (CardUtil.seal_name(seal) or tostring(seal)) .. " Seal")
    end

    local detail_str = #details > 0 and " [" .. table.concat(details, ", ") .. "]" or ""
    table.insert(info, string.format("%d. %s%s", i, card_name, detail_str))
  end

  return info
end

function Context.get_owned_vouchers()
  if not G or not G.GAME or not G.GAME.used_vouchers then
    return {"No vouchers data available"}
  end

  local info = {"=== OWNED VOUCHERS ===", ""}

  local has_vouchers = false
  for voucher_key, used in pairs(G.GAME.used_vouchers) do
    if used then
      has_vouchers = true
      local voucher = G.P_CENTERS and G.P_CENTERS[voucher_key]
      if voucher then
        local name = Utils.safe_description(voucher.loc_txt and voucher.loc_txt.name, nil, 60)
        if not name or name == "" then
          name = voucher.name or Utils.humanize_identifier(voucher_key) or voucher_key
        end
        local desc = safe_description(voucher.loc_txt)
        table.insert(info, name)
        if desc ~= "" then
          table.insert(info, "  " .. desc)
        end
      else
        table.insert(info, voucher_key)
      end
    end
  end

  if not has_vouchers then
    table.insert(info, "No vouchers owned")
  end

  return info
end

function Context.get_round_history()
  if not G or not G.GAME or not G.GAME.current_round then
    return {"Round data not available"}
  end

  local info = {"=== ROUND HISTORY ===", ""}

  local round = G.GAME.current_round

  table.insert(info, string.format("Ante: %d | Round: %d",
    G.GAME.round_resets and G.GAME.round_resets.ante or 0,
    G.GAME.round or 0))

  -- current_round.hands_played is an integer counter (not a list); # / ipairs would crash
  local hp = tonumber(round.hands_played) or 0
  table.insert(info, "")
  if hp > 0 then
    table.insert(info, string.format("Hands played this round: %d", hp))
  else
    table.insert(info, "No hands played yet this round")
  end

  if round.discards_used and round.discards_used > 0 then
    table.insert(info, "")
    table.insert(info, string.format("Discards used: %d", round.discards_used))
  end

  return info
end

return Context
