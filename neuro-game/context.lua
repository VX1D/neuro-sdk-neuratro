local Context = {}
local Utils = require "utils"
local safe_name = Utils.safe_name

local function safe_description(loc_txt, card, max_len)
  return Utils.safe_description(loc_txt, card, max_len)
end

function Context.send(message, important)
  if sendDebugMessage then
    sendDebugMessage("Context sent: " .. tostring(message))
  end
  if important then
    if sendImportantMessage then
      sendImportantMessage(message)
    end
  else
    if sendContextMessage then
      sendContextMessage(message)
    end
  end
end

function Context.get_poker_hand_info()
  if not G or not G.GAME or not G.GAME.hands then
    Context.send("Game not available yet.")
    return {}
  end

  local context_hands = {}
  for name, hand in pairs(G.GAME.hands) do
    local description = string.format(
      "%s: level %s, chips %s, mult %s",
      name,
      tostring(hand.level),
      tostring(hand.chips),
      tostring(hand.mult)
    )
    table.insert(context_hands, description)
  end

  return context_hands
end

function Context.get_joker_info()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    Context.send("No jokers in inventory.")
    return {}
  end

  local jokers = {}
  for index, card in ipairs(G.jokers.cards) do
    local name = safe_name(card) or "Unknown"
    local ability = card.ability or {}
    local desc = Utils.card_description(card)

    local details = string.format("%d: %s", index, name)

    if ability.x_mult then
      details = details .. string.format(" [xMult: %s]", tostring(ability.x_mult))
    end
    if ability.h_mult then
      details = details .. string.format(" [+Mult: %s]", tostring(ability.h_mult))
    end
    if ability.h_mod then
      details = details .. string.format(" [+Chips: %s]", tostring(ability.h_mod))
    end
    if ability.blueprint then
      details = details .. " [Blueprint]"
    end
    if ability.perishable then
      details = details .. " [Perishable: " .. tostring(ability.perishable) .. "]"
    end
    if ability.rental then
      details = details .. " [Rental: " .. tostring(ability.rental) .. "]"
    end
    if ability.eternal then
      details = details .. " [Eternal]"
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
    Context.send("Game not available yet.")
    return {}
  end

  local modifiers = {}

  if G.GAME.edition then
    table.insert(modifiers, "Active edition: " .. G.GAME.edition)
  end

  if G.GAME.seal then
    table.insert(modifiers, "Active seal: " .. G.GAME.seal)
  end

  if G.GAME.modifiers then
    local mods = G.GAME.modifiers
    if mods.discard_cost then
      table.insert(modifiers, "Discard cost: " .. tostring(mods.discard_cost))
    end
    if mods.no_interest then
      table.insert(modifiers, "No interest enabled: " .. tostring(mods.no_interest))
    end
    if mods.scaling then
      table.insert(modifiers, "Scaling modifier: " .. tostring(mods.scaling))
    end
    if mods.hand_size then
      table.insert(modifiers, "Hand size modifier: " .. tostring(mods.hand_size))
    end
  end

  if #modifiers == 0 then
    return { "No active modifiers found." }
  end

  return modifiers
end

function Context.get_deck_types()
  if not G or not G.P_CENTER_POOLS or not G.P_CENTER_POOLS.Back then
    Context.send("Game not available yet.")
    return {}
  end

  local decks = {}
  for key, deck in pairs(G.P_CENTER_POOLS.Back) do
    if deck.set ~= "Back" and (deck.unlocked or false) then
      local name = deck.loc_txt and deck.loc_txt.name or deck.name
      decks[#decks + 1] = string.format("%s: %s", key, name)
    end
  end

  return decks
end

local function count_suits(cards)
  local suits = { Hearts = 0, Diamonds = 0, Clubs = 0, Spades = 0 }
  for _, card in ipairs(cards) do
    if card.base and card.base.suit then
      suits[card.base.suit] = (suits[card.base.suit] or 0) + 1
    end
  end
  return suits
end

local function count_ranks(cards)
  local ranks = {}
  for _, card in ipairs(cards) do
    if card.base and card.base.value then
      ranks[card.base.value] = (ranks[card.base.value] or 0) + 1
    end
  end
  return ranks
end

local function analyze_hand_potential(cards)
  if not cards or #cards == 0 then return nil end
  local suits = count_suits(cards)
  local ranks = count_ranks(cards)
  local max_suit_count = 0
  for _, count in pairs(suits) do
    if count > max_suit_count then max_suit_count = count end
  end
  local rank_counts = {}
  for _, count in pairs(ranks) do
    rank_counts[count] = (rank_counts[count] or 0) + 1
  end
  return {
    total_cards = #cards,
    max_same_suit = max_suit_count,
    has_pair = rank_counts[2] and rank_counts[2] > 0,
    has_three = rank_counts[3] and rank_counts[3] > 0,
    has_four = rank_counts[4] and rank_counts[4] > 0,
    unique_ranks = 0
  }
end

function Context.get_scoring_explanation()
  if not G or not G.GAME then
    Context.send("Game not available yet.")
    return {}
  end

  local explanation = {
    "=== SCORING FORMULA ===",
    "Score = (Base Chips + Joker Chips + Card Enhancements) × (Base Mult + Joker Mult) × (Joker XMult)",
    "",
    "=== BASE HAND VALUES ===",
  }

  if G.GAME.hands then
    for hand_name, hand_data in pairs(G.GAME.hands) do
      if hand_data.visible then
        table.insert(explanation, string.format("%s: Chips=%d, Mult=%d (Level %d)",
          hand_name,
          hand_data.chips,
          hand_data.mult,
          hand_data.level
        ))
      end
    end
  end

  if G.hand and G.hand.highlighted and #G.hand.highlighted > 0 then
    if G.FUNCS and G.FUNCS.get_poker_hand_info then
      local hand_info = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
      if hand_info and hand_info.type then
        local hand_data = G.GAME.hands[hand_info.type]
        if hand_data then
          table.insert(explanation, "")
          table.insert(explanation, "=== CURRENT HIGHLIGHTED HAND ===")
          table.insert(explanation, "Type: " .. hand_info.type)
          table.insert(explanation, "Level: " .. tostring(hand_data.level))
          table.insert(explanation, string.format("Base Chips: %d", hand_data.chips))
          table.insert(explanation, string.format("Base Mult: %d", hand_data.mult))
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
      if potential.max_same_suit >= 5 then
        table.insert(explanation, "Contains flush potential (5+ same suit)")
      elseif potential.max_same_suit >= 4 then
        table.insert(explanation, "Near flush (4 same suit)")
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
      local ability = card.ability or {}
      local name = safe_name(card) or "Unknown"

      local joker_info = string.format("%d: %s", index, name)

      if ability.x_mult then
        joker_info = joker_info .. string.format(" [xMult ×%s]", tostring(ability.x_mult))
      end
      if ability.h_mult then
        joker_info = joker_info .. string.format(" [+Mult +%s]", tostring(ability.h_mult))
      end
      if ability.h_mod then
        joker_info = joker_info .. string.format(" [+Chips +%s]", tostring(ability.h_mod))
      end
      if ability.c_mult then
        joker_info = joker_info .. string.format(" [CardMult +%s]", tostring(ability.c_mult))
      end
      if ability.d_mult then
        joker_info = joker_info .. string.format(" [DblMult +%s]", tostring(ability.d_mult))
      end
      if ability.t_mult then
        joker_info = joker_info .. string.format(" [TrumpMult +%s]", tostring(ability.t_mult))
      end

      table.insert(explanation, joker_info)
    end
  end

  return explanation
end

function Context.get_joker_strategy()
  if not G or not G.jokers then
    Context.send("Jokers not available yet.")
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

  local total_xmult = 1
  local total_mult = 0
  local total_chips = 0
  local xmult_count = 0
  local mult_count = 0
  local chip_count = 0

  for index, card in ipairs(G.jokers.cards) do
    local ability = card.ability or {}
    local center = card.config and card.config.center or {}
    local edition = card.edition or {}
    local rarity = center.rarity or "Common"
    local sell_value = card.sell_cost or 0

    local effects = {}

    if ability.x_mult then
      table.insert(effects, string.format("x%.1f Mult", ability.x_mult))
      total_xmult = total_xmult * (ability.x_mult or 1)
      xmult_count = xmult_count + 1
    end
    if ability.h_mult then
      table.insert(effects, string.format("+%d Mult", ability.h_mult))
      total_mult = total_mult + (ability.h_mult or 0)
      mult_count = mult_count + 1
    end
    if ability.h_mod then
      table.insert(effects, string.format("+%d Chips", ability.h_mod))
      total_chips = total_chips + (ability.h_mod or 0)
      chip_count = chip_count + 1
    end
    if ability.c_mult then
      table.insert(effects, string.format("+%d Mult/card", ability.c_mult))
      mult_count = mult_count + 1
    end
    if ability.d_mult then
      table.insert(effects, string.format("+%d Mult/discard", ability.d_mult))
    end
    if ability.t_mult then
      table.insert(effects, string.format("+%d Mult/suit card", ability.t_mult))
    end
    if ability.s_mult then
      table.insert(effects, string.format("+%d Mult scaling", ability.s_mult))
    end
    if ability.p_mult then
      table.insert(effects, string.format("+%d Mult/played hand", ability.p_mult))
    end

    local special = {}
    if ability.blueprint then table.insert(special, "Copies right joker") end
    if ability.brainstorm then table.insert(special, "Copies leftmost joker") end
    if ability.perishable then table.insert(special, string.format("Expires in %d hands", ability.perishable)) end
    if ability.rental then table.insert(special, string.format("Rental: -$%d/round", ability.rental)) end
    if ability.eternal then table.insert(special, "Eternal") end

    local edition_str = edition.name and string.format(" [%s]", edition.name) or ""
    local effect_str = #effects > 0 and " - " .. table.concat(effects, ", ") or ""
    local special_str = #special > 0 and " (" .. table.concat(special, ", ") .. ")" or ""

    table.insert(strategy, string.format("%d. %s%s (%s) [Sell: $%d]%s%s",
      index, safe_name(card) or "Unknown", edition_str, rarity, sell_value, effect_str, special_str))
  end

  table.insert(strategy, "")
  table.insert(strategy, "=== JOKER SUMMARY ===")
  if xmult_count > 0 then
    table.insert(strategy, string.format("Total XMult multiplier: x%.2f", total_xmult))
  end
  if mult_count > 0 then
    table.insert(strategy, string.format("Total +Mult from jokers: +%d", total_mult))
  end
  if chip_count > 0 then
    table.insert(strategy, string.format("Total +Chips from jokers: +%d", total_chips))
  end

  if #G.jokers.cards < (G.jokers.config and G.jokers.config.card_limit or 5) then
    table.insert(strategy, "")
    table.insert(strategy, string.format("Joker slots available: %d/%d",
      #G.jokers.cards, G.jokers.config and G.jokers.config.card_limit or 5))
  end

  local has_blueprint = false
  local has_brainstorm = false
  local has_trib = false
  local has_steel_joker = false

  for _, card in ipairs(G.jokers.cards) do
    local center = card.config and card.config.center or {}
    local key = center.key or ""
    if key:find("blueprint") or key:find("Blueprint") then has_blueprint = true end
    if key:find("brainstorm") or key:find("Brainstorm") then has_brainstorm = true end
    if key:find("trib") or key:find("Trib") then has_trib = true end
    if key:find("steel") or key:find("Steel") then has_steel_joker = true end
  end

  if has_blueprint or has_brainstorm or xmult_count > 1 then
    table.insert(strategy, "")
    table.insert(strategy, "=== JOKER INTERACTIONS ===")

    if has_blueprint and xmult_count > 0 then
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
      if G.deck then
        for _, c in ipairs(G.deck.cards) do
          if c.ability and c.ability.enhancement == "m_steel" then
            steel_count = steel_count + 1
          end
        end
      end
      table.insert(strategy, string.format("Steel Joker: %d Steel cards in deck", steel_count))
    end
  end

  table.insert(strategy, "")
  table.insert(strategy, "=== JOKER ORDERING RULES ===")
  table.insert(strategy, "Jokers evaluate left-to-right in order")
  table.insert(strategy, "Order affects how bonuses combine:")
  table.insert(strategy, "- +Chips and +Mult add to base first")
  table.insert(strategy, "- xMult multiplies the accumulated total")

  return strategy
end

function Context.get_shop_context()
  if not G or not G.GAME then
    Context.send("Game not available yet.")
    return {}
  end

  local context = {
    "=== SHOP ECONOMY ===",
    "",
    "Available Funds: $" .. tostring(G.GAME.dollars or 0),
    "Reroll Cost: $" .. tostring(G.GAME.current_round and G.GAME.current_round.reroll_cost or 5),
    "Joker Capacity: " .. tostring(G.jokers and G.jokers.cards and #G.jokers.cards or 0) .. "/" .. tostring(G.jokers and G.jokers.config and G.jokers.config.card_limit or 5),
    "",
  }

  if G.GAME.interest_cap then
    table.insert(context, string.format("Interest Cap: $%d (Rate: %.0f%%)",
      G.GAME.interest_cap,
      (G.GAME.interest_rate or 0.2) * 100
    ))
  end

  if G.shop_jokers and #G.shop_jokers.cards > 0 then
    table.insert(context, "")
    table.insert(context, "=== SHOP JOKERS ===")
    for i, card in ipairs(G.shop_jokers.cards) do
      local center = card.config and card.config.center or {}
      local ability = card.ability or {}
      local name = safe_name(card) or "Unknown"
      local cost = card.cost or 0
      local rarity = center.rarity or "Common"
      local can_afford = cost <= (G.GAME.dollars or 0)
      local status = can_afford and "$" .. tostring(cost) or "Cannot afford ($" .. tostring(cost) .. ")"

      local effects = {}
      if ability.x_mult then table.insert(effects, string.format("x%.1f Mult", ability.x_mult)) end
      if ability.h_mult then table.insert(effects, string.format("+%d Mult", ability.h_mult)) end
      if ability.h_mod then table.insert(effects, string.format("+%d Chips", ability.h_mod)) end
      if ability.c_mult then table.insert(effects, string.format("+%d Mult per card", ability.c_mult)) end
      if ability.d_mult then table.insert(effects, string.format("+%d Mult per discard", ability.d_mult)) end
      if ability.t_mult then table.insert(effects, string.format("+%d Mult per suit", ability.t_mult)) end
      if ability.s_mult then table.insert(effects, string.format("+%d Mult scaling", ability.s_mult)) end

      local effect_str = #effects > 0 and " - " .. table.concat(effects, ", ") or ""
      local desc = safe_description(center.loc_txt, card)
      if desc ~= "" then
        desc = " [" .. desc .. "]"
      end

      table.insert(context, string.format("%d: %s (%s) [%s]%s%s", i, name, rarity, status, effect_str, desc))
    end
  end

  if G.shop_vouchers and #G.shop_vouchers.cards > 0 then
    table.insert(context, "")
    table.insert(context, "=== SHOP VOUCHERS ===")
    for i, card in ipairs(G.shop_vouchers.cards) do
      local center = card.config and card.config.center or {}
      local name = safe_name(card) or "Unknown"
      local cost = card.cost or 0
      local can_afford = cost <= (G.GAME.dollars or 0)
      local status = can_afford and "$" .. tostring(cost) or "Cannot afford ($" .. tostring(cost) .. ")"
      local desc = safe_description(center.loc_txt, card)
      if desc ~= "" then
        table.insert(context, string.format("%d: %s [%s] - %s", i, name, status, desc))
      else
        table.insert(context, string.format("%d: %s [%s]", i, name, status))
      end
    end
  end

  if G.shop_booster and #G.shop_booster.cards > 0 then
    table.insert(context, "")
    table.insert(context, "=== SHOP BOOSTER PACKS ===")
    for i, card in ipairs(G.shop_booster.cards) do
      local center = card.config and card.config.center or {}
      local name = safe_name(card) or "Unknown"
      local cost = card.cost or 0
      local can_afford = cost <= (G.GAME.dollars or 0)
      local status = can_afford and "$" .. tostring(cost) or "Cannot afford ($" .. tostring(cost) .. ")"
      local desc = safe_description(center.loc_txt, card)
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
    Context.send("Game not available yet.")
    return {}
  end

  local blind = G.GAME.blind
  local blind_type = "Unknown"
  if blind.get_type then
    local ok_bt, bt = pcall(function() return blind:get_type() end)
    if ok_bt and bt then
      blind_type = tostring(bt)
    end
  end
  local target = (blind.chips or 0) * (blind.mult or 1)
  local hands_left = G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local discards_left = G.GAME.current_round and G.GAME.current_round.discards_left or 0

  local info = {
    "=== CURRENT BLIND ===",
    "",
    "Type: " .. blind_type,
    "Name: " .. (blind.name or "Unknown"),
    string.format("Target Score: %d", target),
  }

  if hands_left > 0 then
    local score_per_hand = math.ceil(target / hands_left)
    table.insert(info, string.format("Score needed per hand: ~%d (if using all hands)", score_per_hand))
  end

  table.insert(info, "")
  table.insert(info, "=== RESOURCES ===")
  table.insert(info, string.format("Hands Remaining: %d", hands_left))
  table.insert(info, string.format("Discards Remaining: %d", discards_left))
  table.insert(info, string.format("Current Money: $%d", G.GAME.dollars or 0))
  table.insert(info, string.format("Deck Size: %d", G.deck and #G.deck.cards or 0))
  table.insert(info, string.format("Cards in Hand: %d", G.hand and #G.hand.cards or 0))

  if blind.boss then
    table.insert(info, "")
    table.insert(info, "=== BOSS BLIND DEBUFF ===")
    local debuff_desc = safe_description(blind.loc_txt)
    if debuff_desc == "" then debuff_desc = "Unknown debuff" end
    table.insert(info, debuff_desc)

    if blind.debuff then
      table.insert(info, "")
      table.insert(info, "Status: Card debuffs are active")
    end
  end

  if G.jokers and #G.jokers.cards > 0 then
    table.insert(info, "")
    table.insert(info, "=== YOUR JOKER POWER ===")
    local total_xmult = 1
    local total_mult = 0
    local total_chips = 0

    for _, card in ipairs(G.jokers.cards) do
      local ability = card.ability or {}
      if ability.x_mult then total_xmult = total_xmult * ability.x_mult end
      if ability.h_mult then total_mult = total_mult + ability.h_mult end
      if ability.h_mod then total_chips = total_chips + ability.h_mod end
    end

    if total_xmult > 1 then table.insert(info, string.format("XMult: x%.2f", total_xmult)) end
    if total_mult > 0 then table.insert(info, string.format("+Mult: +%d", total_mult)) end
    if total_chips > 0 then table.insert(info, string.format("+Chips: +%d", total_chips)) end
  end

  return info
end

function Context.get_hand_levels_info()
  if not G or not G.GAME or not G.GAME.hands then
    Context.send("Game not available yet.")
    return {}
  end

  local levels = {
    "=== HAND LEVELS ===",
    "",
    "Hands level up when you play them. Higher levels = more chips & mult.",
    "",
  }

  local sorted_hands = {}
  for hand_name, hand_data in pairs(G.GAME.hands) do
    if hand_data.visible then
      table.insert(sorted_hands, {name = hand_name, data = hand_data})
    end
  end
  table.sort(sorted_hands, function(a, b)
    return (a.data.chips * a.data.mult) > (b.data.chips * b.data.mult)
  end)

  for _, entry in ipairs(sorted_hands) do
    local hand_data = entry.data
    local score = hand_data.chips * hand_data.mult
    local plays = hand_data.played or 0
    local level = hand_data.level or 1
    table.insert(levels, string.format("%s (L%d): %d chips × %d mult = %d base score [%d plays]",
      entry.name, level, hand_data.chips, hand_data.mult, score, plays))
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

local function detect_joker_synergies(jokers)
  local synergies = {}
  local has_blueprint = false
  local has_brainstorm = false
  local x_mult_count = 0
  local mult_add_count = 0
  local chip_add_count = 0

  for _, joker in ipairs(jokers) do
    local ability = joker.ability or {}
    if ability.blueprint then has_blueprint = true end
    if ability.brainstorm then has_brainstorm = true end
    if ability.x_mult then x_mult_count = x_mult_count + 1 end
    if ability.h_mult or ability.c_mult or ability.t_mult then mult_add_count = mult_add_count + 1 end
    if ability.h_mod then chip_add_count = chip_add_count + 1 end
  end

  if has_blueprint and x_mult_count > 0 then
    table.insert(synergies, "Blueprint can copy xMult jokers for exponential scaling")
  end
  if has_brainstorm and x_mult_count > 0 then
    table.insert(synergies, "Brainstorm copies leftmost joker - position xMult jokers leftmost")
  end
  if x_mult_count > 1 then
    table.insert(synergies, "Multiple xMult jokers provide multiplicative scaling")
  end
  if chip_add_count > 0 and mult_add_count > 0 and x_mult_count > 0 then
    table.insert(synergies, "Balanced build: Chips + Mult + xMult")
  end

  return synergies
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

  table.insert(info, string.format("Slots: %d/%d", #G.consumeables.cards, G.consumeables.config and G.consumeables.config.card_limit or 2))
  table.insert(info, "")

  for i, card in ipairs(G.consumeables.cards) do
    local center = card.config and card.config.center or {}
    local ability = card.ability or {}
    local name = safe_name(card) or "Unknown"
    local set = center.set or "Consumable"
    local desc = safe_description(center.loc_txt, card)

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

  table.insert(info, string.format("Cards: %d/%d", #G.hand.cards, G.hand.config and G.hand.config.card_limit or 8))
  table.insert(info, "")

  for i, card in ipairs(G.hand.cards) do
    local base = card.base or {}
    local ability = card.ability or {}
    local edition = card.edition or {}
    local seal = card.seal

    local card_name = (base.value or "?") .. " of " .. (base.suit or "?")
    local details = {}

    if ability.enhancement then
      local enh_name = ability.enhancement:gsub("^m_", ""):gsub("_", " ")
      table.insert(details, enh_name)
    end

    if edition.name then
      table.insert(details, edition.name .. " Edition")
    elseif edition.type then
      table.insert(details, edition.type .. " Edition")
    end

    if seal then
      table.insert(details, seal .. " Seal")
    end

    local detail_str = #details > 0 and " [" .. table.concat(details, ", ") .. "]" or ""
    table.insert(info, string.format("%d. %s%s", i, card_name, detail_str))
  end

  return info
end

function Context.get_deck_composition()
  if not G or not G.deck or not G.deck.cards then
    return {"Deck not available"}
  end

  local info = {"=== DECK COMPOSITION ===", ""}

  local suits = {Hearts = 0, Diamonds = 0, Clubs = 0, Spades = 0}
  local enhancements = {}
  local seals = {}
  local editions = {}

  for _, card in ipairs(G.deck.cards) do
    local base = card.base or {}
    local ability = card.ability or {}
    local edition = card.edition or {}

    if base.suit then
      suits[base.suit] = (suits[base.suit] or 0) + 1
    end

    if ability.enhancement then
      local enh = ability.enhancement:gsub("^m_", "")
      enhancements[enh] = (enhancements[enh] or 0) + 1
    end

    if card.seal then
      seals[card.seal] = (seals[card.seal] or 0) + 1
    end

    if edition.name or edition.type then
      local ed = edition.name or edition.type
      editions[ed] = (editions[ed] or 0) + 1
    end
  end

  table.insert(info, string.format("Total cards: %d", #G.deck.cards))
  table.insert(info, "")

  table.insert(info, "=== BY SUIT ===")
  for suit, count in pairs(suits) do
    if count > 0 then
      table.insert(info, string.format("%s: %d", suit, count))
    end
  end

  if next(enhancements) then
    table.insert(info, "")
    table.insert(info, "=== ENHANCEMENTS ===")
    for enh, count in pairs(enhancements) do
      table.insert(info, string.format("%s: %d", enh:gsub("_", " "), count))
    end
  end

  if next(seals) then
    table.insert(info, "")
    table.insert(info, "=== SEALS ===")
    for seal, count in pairs(seals) do
      table.insert(info, string.format("%s: %d", seal, count))
    end
  end

  if next(editions) then
    table.insert(info, "")
    table.insert(info, "=== EDITIONS ===")
    for ed, count in pairs(editions) do
      table.insert(info, string.format("%s: %d", ed, count))
    end
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
      local voucher = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Voucher and G.P_CENTER_POOLS.Voucher[voucher_key]
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

  if round.hands_played and #round.hands_played > 0 then
    table.insert(info, "")
    table.insert(info, "=== HANDS PLAYED ===")
    for i, hand in ipairs(round.hands_played) do
      table.insert(info, string.format("%d. %s", i, hand))
    end
  else
    table.insert(info, "")
    table.insert(info, "No hands played yet this round")
  end

  if round.discards_used and round.discards_used > 0 then
    table.insert(info, "")
    table.insert(info, string.format("Discards used: %d", round.discards_used))
  end

  return info
end

function Context.get_neuratro_info()
  local info = {"=== NEURATRO MOD ===", ""}

  local neuratro_loaded = false
  if SMODS and SMODS.Mods then
    for _, mod in pairs(SMODS.Mods) do
      if mod.id == "Neurocards" or mod.id == "Neuratro" then
        neuratro_loaded = true
        break
      end
    end
  end

  if not neuratro_loaded then
    table.insert(info, "Neuratro mod not detected")
    return info
  end

  table.insert(info, "Neuratro mod active")
  table.insert(info, "Custom jokers, consumables, and enhancements available")
  table.insert(info, "")

  local neuratro_reference = {
    jokers = {
      j_3heart = {name = "heartheartheart", desc = "X1 Mult, upgrades to X1.45 when playing Three of a Kind with all Hearts"},
      j_gimbag = {name = "Gym Bag", desc = "+1 hand size, Aces in hand give +12 Mult and +12 Chips (doubled for Hearts)"},
      j_plasma_globe = {name = "Plasma Globe", desc = "Gains +8 Chips per played hand, pays $2 per played hand"},
      j_btmc = {name = "BTMC", desc = "+100 Chips, +4 Mult per card above hand limit"},
      j_highlighted = {name = "Highlighted", desc = "Retriggers highlighted cards"},
      j_anny = {name = "Anny", desc = "Gains +10 Mult when scoring 5+ cards"},
      j_kyoto = {name = "Kyoto", desc = "+50 Chips, +15 Mult if played hand has a Spade"},
      j_pipes = {name = "Pipes", desc = "+30 Chips, upgrades by +10 when scoring with Clubs"},
      j_milc = {name = "MILC", desc = "X2 Mult if hand contains a Pair"},
      j_teru = {name = "Teru", desc = "+20 Chips per Diamond card scored"},
      j_schedule = {name = "Schedule", desc = "Gains +5 Mult when you skip a blind"},
      j_lavalamp = {name = "Lava Lamp", desc = "+8 Mult, increases by +2 per ante"},
      j_lucy = {name = "Lucy", desc = "Creates a random consumable when blind is selected"},
      j_queenpb = {name = "Queen PB", desc = "Queens give X1.5 Mult"},
      j_tutelsoup = {name = "Tutel Soup", desc = "Heals 1 discard when playing a hand"},
      j_layna = {name = "Layna", desc = "+50 Chips, retriggers if scoring card is enhanced"},
      j_forghat = {name = "Frog Hat", desc = "+15 Mult, creates a copy of scored face cards"},
      j_tiredtutel = {name = "Tired Tutel", desc = "Sleeps for 3 hands then gives +100 Chips"},
      j_hype = {name = "Hype", desc = "+20 Mult if scoring hand contains an Ace"},
      j_recbin = {name = "Recycle Bin", desc = "Gains +5 Chips per discarded card"},
      j_harpoon = {name = "Get Harpooned!", desc = "+30 Mult against boss blinds"},
      j_cfrb = {name = "CFRB", desc = "+15 Chips per consumable slot filled"},
      j_sispace = {name = "SISpace", desc = "+10 Mult per empty consumable slot"},
      j_allin = {name = "I'm All In", desc = "Doubles money interest cap"},
      j_camila = {name = "Camila", desc = "Hearts give +8 Mult when held in hand"},
      j_jokr = {name = "JOKR", desc = "Copies effect of rightmost joker"},
      j_xdx = {name = "xdx", desc = "Gains +5 Mult per round survived"},
      j_bday1 = {name = "Birthday 1", desc = "Creates a tarot when blind is skipped"},
      j_bday2 = {name = "Birthday 2", desc = "Creates a planet when blind is selected"},
      j_sistream = {name = "Sistream", desc = "+25 Chips per Spectral card used"},
      j_donowall = {name = "Donowall", desc = "Gains +10 Mult when you discard"},
      j_stocks = {name = "Stocks", desc = "Money gained is doubled"},
      j_techhard = {name = "Tech Hard", desc = "+40 Chips, -$1 per hand played"},
      j_void = {name = "Void", desc = "Destroys leftmost joker, gains its effect"},
      j_collab = {name = "Collab", desc = "+15 Mult per unique suit in scoring hand"},
      j_cavestream = {name = "Cave Stream", desc = "+30 Chips if scoring hand contains 6+ cards"},
      j_jorker = {name = "Jorker", desc = "Random joker effect each round"},
      j_roulette = {name = "Roulette", desc = "50% chance to give X3 Mult, 50% to give X0.5"},
      j_Vedds = {name = "Vedds", desc = "+20 Chips per Vedal card in deck"},
      j_ddos = {name = "DDOS", desc = "+50 Mult, disables shop for this round"},
      j_hiyori = {name = "Hiyori", desc = "Retriggers scored 7s"},
      j_Glorp = {name = "Glorp", desc = "Creates a Glorpy when scoring"},
      j_Emuz = {name = "Emuz", desc = "+25 Chips per Emuz card owned"},
      j_anteater = {name = "Anteater", desc = "Gains +20 Chips when defeating a boss blind"},
      j_drive = {name = "Drive", desc = "+35 Mult when scoring with exactly 4 cards"},
      j_deliv = {name = "Delivery", desc = "Creates a food joker when defeating boss"},
      j_fourtoes = {name = "Four Toes", desc = "4s are retriggered"},
      j_abandonedarchive = {name = "Abandoned Archive", desc = "+100 Chips if deck has 40+ cards"},
      j_minikocute = {name = "Miniko Cute", desc = "+15 Mult if scoring hand has 3 or fewer cards"},
      j_neurodog = {name = "Neurodog", desc = "+50 Chips, +10 Mult, retriggers"},
      j_ely = {name = "Ely", desc = "+30 Chips per face card held in hand"},
      j_cerbr = {name = "Cerber", desc = "+25 Mult, creates a copy of destroyed cards"},
      j_corpa = {name = "Corpa", desc = "Pays $5 when defeating a boss blind"},
      j_emojiman = {name = "Emojiman", desc = "+20 Chips per unique rank scored"},
      j_shoomimi = {name = "Shoomimi", desc = "Seals are retriggered"},
      j_plush = {name = "Plush", desc = "+40 Chips, +$2 at end of round"},
      j_vedalsdrink = {name = "Vedal's Drink", desc = "+15 Mult, pays $1 per scored card"},
      j_filtersister = {name = "Filter Sister", desc = "Debuffed cards give +30 Chips"},
      j_envy = {name = "Envious", desc = "+10 Mult per owned joker"},
      j_argirl = {name = "Argirl", desc = "+25 Chips, upgrades when scoring with Spades"},
    },
    consumables = {
      twins = {name = "The Twins", desc = "Enhance 2 selected cards to Twin Cards"},
      donation = {name = "The Bit", desc = "Enhance 1 selected card to Donation Card"},
      shomimi_set_seal = {name = "Mitosis", desc = "Add Shoomimi Seal to 1 selected card"},
    },
    enhancements = {
      m_twin = {name = "Twin", desc = "Retriggers this card"},
      m_dono = {name = "Donation", desc = "Pays $3 when scored"},
      m_bit = {name = "Bit", desc = "Gains +10 Chips per Bit card in deck"},
    }
  }

  if G.jokers and G.jokers.cards then
    local neuratro_jokers = {}
    for _, card in ipairs(G.jokers.cards) do
      local key = card.config and card.config.center and card.config.center.key
      if key then
        for ref_key, ref_data in pairs(neuratro_reference.jokers) do
          if key:find(ref_key) then
            table.insert(neuratro_jokers, {name = ref_data.name, desc = ref_data.desc})
            break
          end
        end
      end
    end

    if #neuratro_jokers > 0 then
      table.insert(info, "=== NEURATRO JOKERS ===")
      for _, joker in ipairs(neuratro_jokers) do
        table.insert(info, "• " .. joker.name)
        table.insert(info, "  " .. joker.desc)
      end
      table.insert(info, "")
    end
  end

  if G.consumeables and G.consumeables.cards then
    local neuratro_cons = {}
    for _, card in ipairs(G.consumeables.cards) do
      local key = card.config and card.config.center and card.config.center.key
      if key then
        for ref_key, ref_data in pairs(neuratro_reference.consumables) do
          if key:find(ref_key) then
            table.insert(neuratro_cons, {name = ref_data.name, desc = ref_data.desc})
            break
          end
        end
      end
    end

    if #neuratro_cons > 0 then
      table.insert(info, "=== NEURATRO CONSUMABLES ===")
      for _, cons in ipairs(neuratro_cons) do
        table.insert(info, "• " .. cons.name)
        table.insert(info, "  " .. cons.desc)
      end
      table.insert(info, "")
    end
  end

  local enhancement_counts = {}

  local function check_cards(cards)
    for _, card in ipairs(cards) do
      if card.ability and card.ability.enhancement then
        local enh = card.ability.enhancement
        if neuratro_reference.enhancements[enh] then
          enhancement_counts[enh] = (enhancement_counts[enh] or 0) + 1
        end
      end
    end
  end

  if G.hand and G.hand.cards then check_cards(G.hand.cards) end
  if G.deck and G.deck.cards then check_cards(G.deck.cards) end
  if G.play and G.play.cards then check_cards(G.play.cards) end

  if next(enhancement_counts) then
    table.insert(info, "=== NEURATRO ENHANCEMENTS ===")
    for enh_key, count in pairs(enhancement_counts) do
      local ref = neuratro_reference.enhancements[enh_key]
      table.insert(info, "• " .. ref.name .. " Cards: " .. count)
      table.insert(info, "  " .. ref.desc)
    end
  end

  return info
end

return Context
