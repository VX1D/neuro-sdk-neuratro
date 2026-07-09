local State = {}
local Utils = require "util.utils"
local CardUtil = require("facts.card_util")
local CtxEconomy = require("context.ctx_economy")
local CtxHelpers = require("context.ctx_helpers")
local StateKinds = require("core.state_kinds")
local HandFacts = require("facts.hand_facts")
local DebuffFacts = require("facts.debuff_facts")
local is_run_setup_overlay = StateKinds.is_run_setup_overlay
local safe_name = Utils.safe_name
local card_description = Utils.card_description
local has_playbook_extra = Utils.has_playbook_extra

local Tuning = require("core.tuning")  -- NEURO_STATE_VERBOSE read live (panel checkbox)

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
  -- suit/straight readiness from hand_facts (modifier-aware) so this cannot contradict the compact structure
  local sh = HandFacts.shape(cards)

  local analysis = {
    total_cards = #cards,
    ranks = {},
    pairs = 0,
    three_of_a_kind = 0,
    four_of_a_kind = 0,
    flush_potential = false,
    straight_potential = false,
    potential_hands = {},
  }

  for _, card in ipairs(cards) do
    if card.base and card.base.value then
      analysis.ranks[card.base.value] = (analysis.ranks[card.base.value] or 0) + 1
    end
  end

  -- suits + exact-count buckets come from the owner (modifier-aware: wild/stone/smeared), so this cannot contradict the Structure line
  analysis.suits = HandFacts.count_suits(cards)
  analysis.max_same_suit = sh.max_suit
  analysis.flush_potential = sh.flush_ready or sh.near_flush
  analysis.straight_potential = sh.straight_ready or sh.near_straight

  local rank_counts = HandFacts.count_ranks(cards)
  for _, count in pairs(rank_counts) do
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
  if sh.flush_ready then
    table.insert(analysis.potential_hands, "Flush")
  elseif sh.near_flush then
    table.insert(analysis.potential_hands, "Near Flush")
  end

  return analysis
end

local function safe_card(card)
  if not card then
    return nil
  end
  local base = card.base or {}
  local ability = card.ability or {}
  local center = card.config and card.config.center or {}
  local enhancement = CardUtil.enhancement_key(card)

  local card_info = {
    name = safe_name(card),
    value = base.value,
    suit = base.suit,
    id = base.id,
    rank = base.value or base.rank,
    highlighted = not not card.highlighted,
    debuff = not not card.debuff,
    cost = card.cost,
    sell_cost = card.sell_cost,
    edition = CardUtil.edition_name(card.edition),
    enhancement = enhancement,
    seal = CardUtil.seal_name(card.seal),
    set = ability.set or nil,
    ability_name = safe_name(card),
  }

  local enh = CardUtil.enhancement_record(enhancement)
  if enh then
    card_info.enhancement = enh.name
    card_info.enhancement_desc = enh.desc
    if enh.bonus_chips then card_info.bonus_chips = enh.bonus_chips end
    if enh.x_mult then card_info.x_mult = enh.x_mult end
  end

  if center.effect then
    card_info.effect = center.effect
  end
  if center.config and Tuning.bool("NEURO_STATE_VERBOSE") then
    card_info.config = deep_copy_safe(center.config, 6)
  end

  if ability.set == "Joker" then
    card_info.joker_type = "joker"
    if Tuning.bool("NEURO_STATE_VERBOSE") then
      card_info.extra = deep_copy_safe(ability.extra, 6)
    end
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
      local rank = card.rank or (card.base and card.base.value)
      if rank ~= nil then res[#res + 1] = rank end
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

    local joker_data = {
      index = i,
      name = safe_name(card),
      id = center.key or center.id or "unknown",
      set = ability.set or "Joker",
      rarity = CardUtil.rarity_name(center.rarity),
      cost = card.cost,
      sell_cost = card.sell_cost,
      edition = CardUtil.edition_name(card.edition),
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
      visible = HandFacts.hand_visible(hand_data),
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
    formula = CtxHelpers.SCORING_FORMULA,
    base_chips = 0,
    base_mult = 0,
    hand_type = nil,
    scoring_cards = 0,
    held_cards = 0,
  }

  if G.hand and G.hand.highlighted and #G.hand.highlighted > 0 then
    if G.FUNCS and G.FUNCS.get_poker_hand_info then
      local ok, hand_type, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, G.hand.highlighted)
      if ok and type(hand_type) == "string" and hand_type ~= "" then
        local hand_data = G.GAME.hands[hand_type]
        if hand_data then
          scoring_data.base_chips = hand_data.chips
          scoring_data.base_mult = hand_data.mult
          scoring_data.hand_type = hand_type
          scoring_data.scoring_cards = (type(scoring_hand) == "table" and #scoring_hand) or #G.hand.highlighted
          scoring_data.held_cards = math.max(0, (G.hand.cards and #G.hand.cards or 0) - (#G.hand.highlighted))
        end
      end
    end
  end

  return scoring_data
end

local function shop_item(card, itype, i, area_name)
  local center = card.config and card.config.center or {}
  local item = {
    type = itype,
    index = i,
    name = safe_name(card),
    id = center.key or center.id or "unknown",
    cost = card.cost,
    can_afford = CtxEconomy.item_afford_status(card, area_name).ok,
    description = card_description(card),
    config = deep_copy_safe(center.config, 6),
  }
  if itype == "joker" then
    item.rarity = CardUtil.rarity_name(center.rarity)
    item.sell_cost = card.sell_cost
  end
  return item
end

local function get_shop_data()
  local shop_info = {
    available_funds = G.GAME and G.GAME.dollars or 0,
    reroll_cost = CtxEconomy.reroll_cost(),
    reroll_level = (G.NEURO and tonumber(G.NEURO.shop_reroll_count)) or 0,
    joker_limit = CardUtil.joker_limit(),
    current_jokers = G.jokers and #G.jokers.cards or 0,
    can_buy_joker = false,
    interest_cap = CtxEconomy.interest_cap(),
    interest_amount = CtxEconomy.interest_amount(),
    no_interest = CtxEconomy.no_interest(),
  }
  shop_info.can_buy_joker = shop_info.current_jokers < shop_info.joker_limit

  shop_info.items = {}
  local areas = {
    { area = G.shop_jokers, type = "joker", label = "shop_jokers" },
    { area = G.shop_vouchers, type = "voucher", label = "shop_vouchers" },
    { area = G.shop_booster, type = "booster", label = "shop_booster" },
  }
  for _, a in ipairs(areas) do
    if a.area and a.area.cards then
      for i, card in ipairs(a.area.cards) do
        shop_info.items[#shop_info.items + 1] = shop_item(card, a.type, i, a.label)
      end
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
      local ok, hand_type, loc_disp_text = pcall(G.FUNCS.get_poker_hand_info, G.play.cards)
      if ok and type(hand_type) == "string" and hand_type ~= "" then
        play_data.hand_type = hand_type
        play_data.hand_name = loc_disp_text
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
  local blind_type = CtxEconomy.blind_type(blind) or "Unknown"
  local current_score = G.GAME.chips or 0
  local target_score = CtxEconomy.blind_target(blind) or 0
  local blind_data = {
    name = blind.name or "Unknown",
    key = blind.key or "unknown",
    type = blind_type,
    chips = blind.chips or 0,
    mult = blind.mult or (blind.config and blind.config.mult) or 1,
    target_score = target_score,
    current_score = current_score,
    remaining_score = CtxEconomy.blind_remaining(blind) or 0,
    reward_dollars = blind.dollars or 0,  -- clear reward, not difficulty
    boss = blind.boss or nil,
    description = (function()
      local t = DebuffFacts.boss_debuff_text(blind)
      return t ~= "" and t or Utils.safe_description(blind.loc_txt, nil, 220)
    end)(),
    loc_text = deep_copy_safe(blind.loc_txt, 4),
    passive = blind.passive or nil,
  }

  return blind_data
end

local _state_rev = nil
local _state_rev_src = nil
local function state_name()
  if not G or not G.STATES or not G.STATE then
    return "UNKNOWN"
  end
  if _state_rev_src ~= G.STATES then
    _state_rev = {}
    for k, v in pairs(G.STATES) do _state_rev[v] = tostring(k) end
    _state_rev_src = G.STATES
  end
  local raw = _state_rev[G.STATE]
  if not raw then
    for k, v in pairs(G.STATES) do
      if v == G.STATE then raw = tostring(k); _state_rev[v] = raw; break end
    end
  end
  if not raw then
    return "UNKNOWN"
  end

  if (raw == "SPLASH" or raw == "MENU" or raw == "GAME_OVER") and is_run_setup_overlay() then
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

  local is_menu = StateKinds.is_menu_state(current_state)
  local is_pack = StateKinds.is_pack_state(current_state)
  local is_shop = current_state == "SHOP"
  local is_blind_select = current_state == "BLIND_SELECT"
  local is_game = current_state ~= "UNKNOWN" and not is_menu and not is_shop and not is_blind_select and not is_pack

  if is_game or is_shop or is_blind_select then
    local blind_type = CtxEconomy.blind_type(G.GAME and G.GAME.blind)
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
    if Tuning.bool("NEURO_STATE_VERBOSE") then
      s.deck = { cards = collect_cards(G.deck) }
      s.discard = { cards = collect_cards(G.discard) }
      s.jokers_detailed = collect_joker_details()
    else
      s.deck = { count = (G.deck and G.deck.cards and #G.deck.cards) or 0 }
      s.discard = { count = (G.discard and G.discard.cards and #G.discard.cards) or 0 }
    end
    s.jokers = collect_cards(G.jokers)
    s.consumeables = collect_cards(G.consumeables)

    if has_playbook_extra() then
      s.playbook_extra = collect_cards(G.playbook_extra)
    end

    s.hand_levels = get_hand_levels()
    s.scoring = get_scoring_data()
    s.blind = get_blind_data()

    if s.round and s.round.hands_left ~= nil and s.round.discards_left ~= nil and s.blind and s.blind.target_score ~= nil then
      s.resources = {
        hands_remaining = s.round.hands_left,
        discards_remaining = s.round.discards_left,
        total_actions = s.round.hands_left + s.round.discards_left,
        target_score = s.blind.target_score,
      }
    end

    s.flags = {
      in_shop = false,
      in_blind_select = is_blind_select,
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
      booster = collect_cards(CardUtil.pack_area()),
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

  if G and G.hand and G.hand.cards and #G.hand.cards > 0 then
    s.hand_analysis = analyze_hand_cards(G.hand.cards)
  end

  if G and G.GAME and G.GAME.dollars ~= nil then
    local interest_cap = CtxEconomy.interest_cap()
    local interest_amount = CtxEconomy.interest_amount()
    local no_interest = CtxEconomy.no_interest()
    -- owned by ctx_economy which has the max(0,..) guard this missed under debt
    local max_interest = CtxEconomy.calc_interest(G.GAME.dollars)
    s.economy = {
      current_money = G.GAME.dollars,
      interest_cap = interest_cap,
      interest_amount = interest_amount,
      no_interest = not not no_interest,
      max_interest = max_interest,
      potential_income = max_interest,
    }
  end

  if G and G.GAME and G.GAME.current_round then
    -- per-round maxima live on round_resets (current_round only tracks *_left); current_round.max_* do not exist
    local resets = G.GAME.round_resets or {}
    local max_hands = tonumber(resets.hands) or 4
    local max_discards = tonumber(resets.discards) or 3
    local max_actions = max_hands + max_discards
    local actions_left = (G.GAME.current_round.hands_left or 0) + (G.GAME.current_round.discards_left or 0)
    s.round_progress = {
      -- clamp >=0: mid-round hand/discard grants push *_left above the reset baseline (negative "used" otherwise)
      hands_used = math.max(0, max_hands - (G.GAME.current_round.hands_left or 0)),
      discards_used = math.max(0, max_discards - (G.GAME.current_round.discards_left or 0)),
      hands_remaining = G.GAME.current_round.hands_left or 0,
      discards_remaining = G.GAME.current_round.discards_left or 0,
      total_actions_remaining = actions_left,
      action_efficiency = max_actions > 0 and (actions_left / max_actions) or 0,
    }
  end

  if G and G.NEURO and G.NEURO.action_history then
    s.last_action_results = {}
    for i = 1, #G.NEURO.action_history do
      s.last_action_results[i] = G.NEURO.action_history[i]
    end
  end

  return s
end

return State
