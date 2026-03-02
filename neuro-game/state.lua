local State = {}
local Utils = require "utils"
local safe_name = Utils.safe_name
local card_description = Utils.card_description
local has_playbook_extra = Utils.has_playbook_extra

local function deep_copy_safe(val, max_depth, _depth, _seen)
  if val == nil then return nil end
  local t = type(val)
  if t == "function" or t == "userdata" or t == "thread" then
    return nil
  end
  if t ~= "table" then
    return val
  end
  _depth = _depth or 0
  if _depth >= (max_depth or 8) then return nil end
  _seen = _seen or {}
  if _seen[val] then return nil end
  _seen[val] = true
  local copy = {}
  for k, v in pairs(val) do
    local kt = type(k)
    if kt == "string" or kt == "number" then
      copy[k] = deep_copy_safe(v, max_depth, _depth + 1, _seen)
    end
  end
  _seen[val] = nil
  return copy
end

local function analyze_hand_cards(cards)
  local analysis = {
    total_cards = #cards,
    suits = { Hearts = 0, Diamonds = 0, Clubs = 0, Spades = 0 },
    ranks = {},
    pairs = 0,
    three_of_a_kind = 0,
    four_of_a_kind = 0,
    flush_potential = false,
    straight_potential = false,
    potential_hands = {},
  }

  for _, card in ipairs(cards) do
    if card.base then
      if card.base.suit then
        analysis.suits[card.base.suit] = (analysis.suits[card.base.suit] or 0) + 1
      end
      if card.base.value then
        analysis.ranks[card.base.value] = (analysis.ranks[card.base.value] or 0) + 1
      end
    end
  end

  local max_suit = 0
  for suit, count in pairs(analysis.suits) do
    if count > max_suit then max_suit = count end
  end
  analysis.flush_potential = max_suit >= 4
  analysis.max_same_suit = max_suit

  local unique_ranks = {}
  for rank, count in pairs(analysis.ranks) do
    table.insert(unique_ranks, rank)
    if count == 2 then
      analysis.pairs = analysis.pairs + 1
    elseif count == 3 then
      analysis.three_of_a_kind = analysis.three_of_a_kind + 1
    elseif count == 4 then
      analysis.four_of_a_kind = analysis.four_of_a_kind + 1
    end
  end

  if analysis.four_of_a_kind > 0 then
    table.insert(analysis.potential_hands, "Four of a Kind")
  end
  if analysis.three_of_a_kind > 0 and analysis.pairs > 0 then
    table.insert(analysis.potential_hands, "Full House")
  end
  if analysis.three_of_a_kind > 0 then
    table.insert(analysis.potential_hands, "Three of a Kind")
  end
  if analysis.pairs >= 2 then
    table.insert(analysis.potential_hands, "Two Pair")
  end
  if analysis.pairs == 1 then
    table.insert(analysis.potential_hands, "Pair")
  end
  if max_suit >= 5 then
    table.insert(analysis.potential_hands, "Flush")
  elseif max_suit >= 4 then
    table.insert(analysis.potential_hands, "Near Flush")
  end

  return analysis
end

local ENHANCEMENT_LOOKUP = {
  m_bonus = { name = "Bonus", desc = "+30 Chips", bonus_chips = 30 },
  m_mult = { name = "Mult", desc = "+4 Mult" },
  m_wild = { name = "Wild", desc = "Can be used as any suit" },
  m_glass = { name = "Glass", desc = "x2 Mult, 1 in 4 chance to break", x_mult = 2 },
  m_steel = { name = "Steel", desc = "x1.5 Mult while in hand", x_mult = 1.5 },
  m_stone = { name = "Stone", desc = "+50 Chips, no rank/suit", bonus_chips = 50 },
  m_gold = { name = "Gold", desc = "$3 at end of round if held" },
  m_lucky = { name = "Lucky", desc = "1 in 5 for +20 Mult, 1 in 15 for $20" },
}

local function safe_card(card)
  if not card then
    return nil
  end
  local base = card.base or {}
  local ability = card.ability or {}
  local center = card.config and card.config.center or {}
  local edition = card.edition or {}
  local enhancement = ability.enhancement or nil
  local seal = card.seal or {}

  local card_info = {
    name = safe_name(card),
    value = base.value,
    suit = base.suit,
    id = base.id,
    rank = base.value or base.rank,
    highlighted = not not card.highlighted,
    cost = card.cost,
    sell_cost = card.sell_cost,
    edition = edition.name or nil,
    enhancement = enhancement or nil,
    seal = seal.name or nil,
    set = ability.set or nil,
    ability_name = safe_name(card),
  }

  local enh = ENHANCEMENT_LOOKUP[enhancement]
  if enh then
    card_info.enhancement = enh.name
    card_info.enhancement_desc = enh.desc
    if enh.bonus_chips then card_info.bonus_chips = enh.bonus_chips end
    if enh.x_mult then card_info.x_mult = enh.x_mult end
  end

  if center.effect then
    card_info.effect = center.effect
  end
  if center.config then
    card_info.config = deep_copy_safe(center.config, 6)
  end

  if ability.set == "Joker" then
    card_info.joker_type = "joker"
    card_info.extra = deep_copy_safe(ability.extra, 6)
    if ability.extra_value then
      card_info.extra_value = ability.extra_value
    end
  end

  return card_info
end

local function collect_cards(area)
  if not area or not area.cards then
    return {}
  end
  local res = {}
  for i = 1, #area.cards do
    res[i] = safe_card(area.cards[i])
  end
  return res
end

local function collect_highlighted(area)
  if not area or not area.highlighted then
    return {}
  end
  local res = {}
  for i = 1, #area.highlighted do
    local card = area.highlighted[i]
    if card then
      res[i] = card.rank or (card.base and card.base.value) or i
    end
  end
  return res
end

local function collect_joker_details()
  if not G or not G.jokers or not G.jokers.cards then
    return {}
  end
  local jokers = {}
  for i, card in ipairs(G.jokers.cards) do
    local ability = card.ability or {}
    local center = card.config and card.config.center or {}
    local edition = card.edition or {}
    local edition_name = edition.name or nil

    local joker_data = {
      index = i,
      name = safe_name(card),
      id = center.key or center.id or "unknown",
      set = ability.set or "Joker",
      rarity = center.rarity or "Common",
      cost = card.cost,
      sell_cost = card.sell_cost,
      edition = edition_name,
      ability_name = safe_name(card),
      extra = type(ability.extra) == "table" and deep_copy_safe(ability.extra, 4) or ability.extra,
      extra_value = ability.extra_value or nil,
      config = type(ability.config) == "table" and deep_copy_safe(ability.config, 4) or nil,
      x_mult = ability.x_mult or nil,
      h_mult = ability.h_mult or nil,
      h_mod = ability.h_mod or nil,
      t_mult = ability.t_mult or nil,
      c_mult = ability.c_mult or nil,
      d_mult = ability.d_mult or nil,
      s_mult = ability.s_mult or nil,
      p_mult = ability.p_mult or nil,
      x_chips = ability.x_chips or nil,
      effect_type = (ability.x_mult and "multiplicative") or
                    ((ability.h_mult or ability.c_mult or ability.t_mult or ability.d_mult or ability.s_mult or ability.p_mult) and "additive_mult") or
                    (ability.h_mod and "additive_chips") or "other",
      description = card_description(card),
      blueprint = ability.blueprint or nil,
      perishable = ability.perishable or nil,
      rental = ability.rental or nil,
      eternal = ability.eternal or nil,
      buffoon = ability.buffoon or nil,
      pinned = ability.pinned or nil,
      soul_pos = ability.soul_pos or nil,
    }

    jokers[i] = joker_data
  end
  return jokers
end

local function get_hand_levels()
  if not G.GAME or not G.GAME.hands then
    return {}
  end
  local levels = {}
  for hand_name, hand_data in pairs(G.GAME.hands) do
    levels[hand_name] = {
      name = hand_name,
      level = hand_data.level or 1,
      chips = hand_data.chips or 0,
      mult = hand_data.mult or 0,
      visible = hand_data.visible or true,
      example = hand_data.example or nil,
    }
  end
  return levels
end

local function get_scoring_data()
  if not G.GAME then
    return nil
  end

  local scoring_data = {
    formula = "Score = (Base Chips + Joker Chips + Card Enhancements) × (Base Mult + Joker Mult) × (Joker XMult)",
    base_chips = 0,
    base_mult = 0,
    hand_type = nil,
    scoring_cards = 0,
    held_cards = 0,
  }

  if G.hand and G.hand.highlighted and #G.hand.highlighted > 0 then
    if G.FUNCS and G.FUNCS.get_poker_hand_info then
      local hand_info = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
      if hand_info and hand_info.type then
        local hand_data = G.GAME.hands[hand_info.type]
        if hand_data then
          scoring_data.base_chips = hand_data.chips
          scoring_data.base_mult = hand_data.mult
          scoring_data.hand_type = hand_info.type
          scoring_data.scoring_cards = hand_info.scoring_hands or #G.hand.highlighted
          scoring_data.held_cards = hand_info.playing_cards or 0
        end
      end
    end
  end

  return scoring_data
end

local function get_shop_data()
  local shop_info = {
    available_funds = G.GAME and G.GAME.dollars or 0,
    reroll_cost = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost or 5,
    reroll_level = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_diff or 0,
    joker_limit = G.jokers and G.jokers.config and G.jokers.config.card_limit or 5,
    current_jokers = G.jokers and #G.jokers.cards or 0,
    can_buy_joker = false,
    interest_cap = G.GAME and G.GAME.interest_cap or 25,
    interest_amount = G.GAME and G.GAME.interest_amount or 1,
    no_interest = G.GAME and G.GAME.modifiers and G.GAME.modifiers.no_interest or false,
  }
  shop_info.can_buy_joker = shop_info.current_jokers < shop_info.joker_limit

  shop_info.items = {}

  if G.shop_jokers and G.shop_jokers.cards then
    for i, card in ipairs(G.shop_jokers.cards) do
      local center = card.config and card.config.center or {}
      shop_info.items[#shop_info.items + 1] = {
        type = "joker",
        index = i,
        name = safe_name(card),
        id = center.key or center.id or "unknown",
        rarity = center.rarity or "Common",
        cost = card.cost,
        can_afford = card.cost <= shop_info.available_funds,
        sell_cost = card.sell_cost,
        description = card_description(card),
        config = deep_copy_safe(center.config, 6),
      }
    end
  end

  if G.shop_vouchers and G.shop_vouchers.cards then
    for i, card in ipairs(G.shop_vouchers.cards) do
      local center = card.config and card.config.center or {}
      shop_info.items[#shop_info.items + 1] = {
        type = "voucher",
        index = i,
        name = safe_name(card),
        id = center.key or center.id or "unknown",
        cost = card.cost,
        can_afford = card.cost <= shop_info.available_funds,
        description = card_description(card),
        config = deep_copy_safe(center.config, 6),
      }
    end
  end

  if G.shop_booster and G.shop_booster.cards then
    for i, card in ipairs(G.shop_booster.cards) do
      local center = card.config and card.config.center or {}
      shop_info.items[#shop_info.items + 1] = {
        type = "booster",
        index = i,
        name = safe_name(card),
        id = center.key or center.id or "unknown",
        cost = card.cost,
        can_afford = card.cost <= shop_info.available_funds,
        description = card_description(card),
        config = deep_copy_safe(center.config, 6),
      }
    end
  end

  return shop_info
end

local function get_play_data()
  if not G or not G.play or not G.play.cards then
    return {}
  end

  local play_data = {
    cards = collect_cards(G.play),
    scoring_cards = collect_highlighted(G.play),
    held_cards = collect_highlighted(G.hand),
    hand_count = G.hand and #G.hand.cards or 0,
  }

  if G.play and #G.play.cards > 0 then
    if G.FUNCS and G.FUNCS.get_poker_hand_info then
      local hand_info = G.FUNCS.get_poker_hand_info(G.play.cards)
      if hand_info then
        play_data.hand_type = hand_info.type
        play_data.hand_name = hand_info.name
        play_data.s_text = hand_info.s_text
        play_data.best_chips = hand_info.best_chips
        play_data.best_chips_text = hand_info.best_chips_text
      end
    end
  end

  return play_data
end

local function get_blind_data()
  if not G.GAME or not G.GAME.blind then
    return nil
  end

  local blind = G.GAME.blind
  local blind_type = "Unknown"
  if blind.get_type then
    local ok_bt, bt = pcall(function() return blind:get_type() end)
    if ok_bt and bt then
      blind_type = bt
    end
  end
  local current_score = G.GAME.chips or 0
  local target_score = (blind.chips or 0) * (blind.mult or 1)
  local blind_data = {
    name = blind.name or "Unknown",
    key = blind.key or "unknown",
    type = blind_type,
    chips = blind.chips or 0,
    mult = blind.mult or 1,
    target_score = target_score,
    current_score = current_score,
    remaining_score = math.max(0, target_score - current_score),
    difficulty = blind.dollars or 0,
    boss = blind.boss or nil,
    description = Utils.safe_description(blind.loc_txt, nil, 220),
    loc_text = deep_copy_safe(blind.loc_txt, 4),
    passive = blind.passive or nil,
  }

  return blind_data
end

local function state_name()
  if not G or not G.STATES or not G.STATE then
    return "UNKNOWN"
  end
  local raw = nil
  for k, v in pairs(G.STATES) do
    if v == G.STATE then
      raw = tostring(k)
      break
    end
  end
  if not raw then
    return "UNKNOWN"
  end

  if (raw == "SPLASH" or raw == "MENU") and G.NEURO_IN_RUN_SETUP then
    return "RUN_SETUP"
  end

  return raw
end

function State.get_state_name()
  return state_name()
end

function State.build()
  local s = {}
  local current_state = state_name()
  s.state = current_state
  s.stage = G and G.STAGE or nil
  s.paused = G and G.SETTINGS and G.SETTINGS.paused or false

  local is_menu = current_state == "SPLASH" or current_state == "MENU" or current_state == "GAME_OVER" or current_state == "RUN_SETUP"
  local is_game = not is_menu and current_state ~= "SHOP" and not current_state:find("_PACK")
  local is_shop = current_state == "SHOP"
  local is_pack = current_state:find("_PACK")
  local is_blind_select = current_state == "BLIND_SELECT"

  if is_game or is_shop or is_blind_select then
    local blind_type = nil
    if G.GAME and G.GAME.blind and G.GAME.blind.get_type then
      local ok_bt, bt = pcall(function() return G.GAME.blind:get_type() end)
      if ok_bt then blind_type = bt end
    end
    s.round = {
      ante = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or nil,
      round = G.GAME and G.GAME.round or nil,
      blind = G.GAME and G.GAME.blind and G.GAME.blind.name or nil,
      blind_type = blind_type,
      hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or nil,
      discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or nil,
      reroll_cost = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost or nil,
    }

  end

  if is_blind_select then
    s.blind_choices = {}
    if G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices then
      s.blind_choices.small = G.GAME.round_resets.blind_choices.Small
      s.blind_choices.big = G.GAME.round_resets.blind_choices.Big
      s.blind_choices.boss = G.GAME.round_resets.blind_choices.Boss
    end
  end

  s.money = G.GAME and G.GAME.dollars or nil

  if is_game then
    s.hand = {
      cards = collect_cards(G.hand),
      highlighted = collect_highlighted(G.hand),
      limit = G.hand and G.hand.config and G.hand.config.highlighted_limit or nil,
      hand_limit = G.hand and G.hand.config and G.hand.config.card_limit or nil,
    }
    s.play = get_play_data()
    s.deck = { cards = collect_cards(G.deck) }
    s.discard = { cards = collect_cards(G.discard) }
    s.jokers = collect_cards(G.jokers)
    s.jokers_detailed = collect_joker_details()
    s.consumeables = collect_cards(G.consumeables)

    if has_playbook_extra() then
      s.playbook_extra = collect_cards(G.playbook_extra)
    end

    s.hand_levels = get_hand_levels()
    s.scoring = get_scoring_data()
    s.blind = get_blind_data()

    if s.round and s.round.hands_left and s.round.discards_left and s.blind and s.blind.target_score then
      s.resources = {
        hands_remaining = s.round.hands_left,
        discards_remaining = s.round.discards_left,
        total_actions = s.round.hands_left + s.round.discards_left,
        target_score = s.blind.target_score,
      }
    end

    s.flags = {
      in_shop = false,
      in_blind_select = false,
      in_pack = false,
    }
  end

  if is_shop then
    s.shop = {
      jokers = collect_cards(G.shop_jokers),
      vouchers = collect_cards(G.shop_vouchers),
      booster = collect_cards(G.shop_booster),
    }
    s.shop_details = get_shop_data()
    s.jokers = collect_cards(G.jokers)
    s.flags = {
      in_shop = true,
      in_blind_select = false,
      in_pack = false,
    }
  end

  if is_pack then
    s.pack = {
      booster = collect_cards(G.booster_pack),
    }
    s.flags = {
      in_shop = false,
      in_blind_select = false,
      in_pack = true,
    }
  end

  if is_game then
    s.game_modifiers = {
      discard_cost = G.GAME and G.GAME.modifiers and G.GAME.modifiers.discard_cost or nil,
      no_interest = G.GAME and G.GAME.modifiers and G.GAME.modifiers.no_interest or nil,
      scaling = G.GAME and G.GAME.modifiers and G.GAME.modifiers.scaling or nil,
      hand_size = G.GAME and G.GAME.modifiers and G.GAME.modifiers.hand_size or nil,
    }
  end

  s.deck_info = {
    name = G.GAME and G.GAME.back and G.GAME.back.name or "unknown",
    id = G.GAME and G.GAME.back and G.GAME.back.id or "unknown",
  }

  if G.hand and G.hand.cards and #G.hand.cards > 0 then
    s.hand_analysis = analyze_hand_cards(G.hand.cards)
  end

  if G.GAME and G.GAME.dollars ~= nil then
    local interest_cap = G.GAME.interest_cap or 25
    local interest_amount = G.GAME.interest_amount or 1
    local no_interest = G.GAME.modifiers and G.GAME.modifiers.no_interest
    local interest_units = math.min(math.floor((G.GAME.dollars or 0) / 5), math.floor(interest_cap / 5))
    local max_interest = no_interest and 0 or (interest_amount * interest_units)
    s.economy = {
      current_money = G.GAME.dollars,
      interest_cap = interest_cap,
      interest_amount = interest_amount,
      no_interest = not not no_interest,
      max_interest = max_interest,
      potential_income = max_interest,
    }
  end

  if G.GAME and G.GAME.current_round then
    local max_hands = G.GAME.current_round.max_hands or 4
    local max_discards = G.GAME.current_round.max_discards or 3
    s.round_progress = {
      hands_used = max_hands - (G.GAME.current_round.hands_left or 0),
      discards_used = max_discards - (G.GAME.current_round.discards_left or 0),
      hands_remaining = G.GAME.current_round.hands_left or 0,
      discards_remaining = G.GAME.current_round.discards_left or 0,
      total_actions_remaining = (G.GAME.current_round.hands_left or 0) + (G.GAME.current_round.discards_left or 0),
      action_efficiency = ((G.GAME.current_round.hands_left or 0) + (G.GAME.current_round.discards_left or 0)) / (max_hands + max_discards),
    }
  end

  if G.NEURO_ACTION_HISTORY then
    s.last_action_results = {}
    for i = 1, #G.NEURO_ACTION_HISTORY do
      s.last_action_results[i] = G.NEURO_ACTION_HISTORY[i]
    end
  end

  return s
end

return State
