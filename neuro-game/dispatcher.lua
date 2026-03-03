local json = require("neuro_json")
local Filtered = require("filtered")
local Actions = require("actions")
local Enforce = require("enforce")
local Utils = require("utils")
local dotenv = require("dotenv")
local safe_name = Utils.safe_name
local ok_anim, NeuroAnim = pcall(require, "neuro-anim")
if not ok_anim then NeuroAnim = {} end

local Dispatcher = {}

local mock_UIBox = {
  get_UIE_by_ID = function() return nil end,
  set_role = function() end,
  recalculate = function() end,
  add_child = function() end
}

local ACTION_SCHEMAS = {}
do
  local defs = Actions.get_static_actions()
  for i = 1, #defs do
    ACTION_SCHEMAS[defs[i].name] = defs[i].schema or {}
  end
end

local TX_CACHE_MAX = 256
local HAND_CONFIRM_DELAY = dotenv.num("NEURO_HAND_CONFIRM_DELAY", 0.6)
local tx_settled = {}
local tx_settled_order = {}
local _last_reregister_at = nil

local function tx_key(action_id)
  if action_id == nil then return nil end
  return tostring(action_id)
end

local function tx_get(action_id)
  local k = tx_key(action_id)
  if not k then return nil end
  return tx_settled[k]
end

local function tx_store(action_id, ok, message, name)
  local k = tx_key(action_id)
  if not k then return end
  if not tx_settled[k] then
    tx_settled_order[#tx_settled_order + 1] = k
  end
  tx_settled[k] = {
    ok = not not ok,
    message = message,
    name = name,
  }
  while #tx_settled_order > TX_CACHE_MAX do
    local drop = table.remove(tx_settled_order, 1)
    tx_settled[drop] = nil
  end
end

local function tx_clear()
  tx_settled = {}
  tx_settled_order = {}
end

local function session_matches(bridge, msg)
  if not bridge or not bridge.session_id then
    return true
  end
  if not msg then
    return true
  end
  local sid = msg.session_id
  if sid == nil and msg.data and msg.data.session_id ~= nil then
    sid = msg.data.session_id
  end
  if sid == nil then
    return true
  end
  return tostring(sid) == tostring(bridge.session_id)
end

local function get_area(area_name)
  if not area_name then
    return nil
  end
  if area_name == "booster_pack" then
    return G.pack_cards or G.booster_pack  -- SMODS uses G.pack_cards; vanilla uses G.booster_pack
  end
  return G[area_name]
end

local function get_card(area, index)
  if not area or not area.cards then
    return nil
  end
  return area.cards[index]
end

local function is_forced_action(name)
  if not (G and G.NEURO.force_inflight and name) then
    return false
  end
  local set = G.NEURO.force_action_set
  if set then
    return not not set[name]
  end
  local list = G.NEURO.force_action_names
  if list then
    for i = 1, #list do
      if list[i] == name then
        return true
      end
    end
  end
  return false
end

local function clear_force_inflight()
  if not G then
    return
  end
  G.NEURO.force_inflight = false
  G.NEURO.force_state = nil
  G.NEURO.force_action_names = nil
  G.NEURO.force_action_set = nil
  G.NEURO.force_sent_at = nil
end

local function push_recent_action(name)
  if not (G and type(name) == "string" and name ~= "") then
    return
  end

  local recent = G.NEURO.recent_actions
  if type(recent) ~= "table" then recent = {} end
  recent[#recent + 1] = name
  while #recent > 10 do
    table.remove(recent, 1)
  end
  G.NEURO.recent_actions = recent

  local hist = G.NEURO.action_history
  if type(hist) ~= "table" then hist = {} end
  hist[#hist + 1] = name
  while #hist > 20 do
    table.remove(hist, 1)
  end
  G.NEURO.action_history = hist
end

local function recent_actions_summary(limit)
  if not (G and type(G.NEURO.recent_actions) == "table" and #G.NEURO.recent_actions > 0) then
    return ""
  end

  local list = G.NEURO.recent_actions
  local n = #list
  local keep = tonumber(limit) or 4
  keep = math.max(1, math.floor(keep))
  local start_i = math.max(1, n - keep + 1)

  local parts = {}
  local i = start_i
  while i <= n do
    local name = tostring(list[i] or "")
    local count = 1
    while (i + count) <= n and list[i + count] == name do
      count = count + 1
    end
    if name ~= "" then
      parts[#parts + 1] = (count > 1) and (name .. "x" .. count) or name
    end
    i = i + count
  end

  if #parts == 0 then return "" end
  return "Recent actions: " .. table.concat(parts, " -> ") .. ". "
end

local function once_per_state_entry_hint(tag, text)
  if not (G and text and text ~= "") then
    return ""
  end
  local serial = tonumber(G.NEURO.state_enter_serial or 0) or 0
  local seen = G.NEURO.query_hint_serials
  if type(seen) ~= "table" then seen = {} end
  local key = tostring(tag or "hint")
  if seen[key] == serial then
    return ""
  end
  seen[key] = serial
  G.NEURO.query_hint_serials = seen
  return text
end

local HAND_VALUE_RANK = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6,
  ["7"] = 7, ["8"] = 8, ["9"] = 9, ["10"] = 10,
  Jack = 11, Queen = 12, King = 13, Ace = 14,
}

local HAND_RANK_LABEL = {
  [14] = "A", [13] = "K", [12] = "Q", [11] = "J", [10] = "10",
  [9] = "9", [8] = "8", [7] = "7", [6] = "6", [5] = "5",
  [4] = "4", [3] = "3", [2] = "2",
}

local function hand_structure_summary()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then
    return ""
  end

  local value_counts = {}
  local suit_counts = {}
  local rank_present = {}

  for _, card in ipairs(G.hand.cards) do
    local base = card and card.base or {}
    local value = tostring(base.value or "?")
    local suit = tostring(base.suit or "?")
    value_counts[value] = (value_counts[value] or 0) + 1
    suit_counts[suit] = (suit_counts[suit] or 0) + 1

    local r = HAND_VALUE_RANK[value]
    if r then
      rank_present[r] = true
      if r == 14 then rank_present[1] = true end
    end
  end

  local pair_count = 0
  local trips_count = 0
  local high_pair_rank = 0
  for value, count in pairs(value_counts) do
    local r = HAND_VALUE_RANK[value] or 0
    if count >= 2 then
      pair_count = pair_count + 1
      if r > high_pair_rank then high_pair_rank = r end
    end
    if count >= 3 then
      trips_count = trips_count + 1
    end
  end

  local max_suit = 0
  for _, count in pairs(suit_counts) do
    if count > max_suit then max_suit = count end
  end

  local max_run = 0
  local run = 0
  for r = 1, 14 do
    if rank_present[r] then
      run = run + 1
      if run > max_run then max_run = run end
    else
      run = 0
    end
  end

  local high_pair = high_pair_rank > 0 and (HAND_RANK_LABEL[high_pair_rank] or tostring(high_pair_rank)) or "-"
  return string.format("Structure: pairs=%d trips=%d top_pair=%s suit_max=%d run_max=%d. ", pair_count, trips_count, high_pair, max_suit, max_run)
end

local function active_blind_debuff_summary()
  if not (G and G.GAME and G.GAME.blind) then
    return ""
  end
  local blind = G.GAME.blind
  local debuff = (type(blind.debuff) == "table") and blind.debuff or {}
  local parts = {}
  if debuff.suit then parts[#parts + 1] = "suit=" .. tostring(debuff.suit) end
  if debuff.is_face == "face" then parts[#parts + 1] = "face=Y" end
  if debuff.h_size_ge then parts[#parts + 1] = "min_cards=" .. tostring(debuff.h_size_ge) end
  if debuff.h_size_le then parts[#parts + 1] = "max_cards=" .. tostring(debuff.h_size_le) end
  if debuff.value then parts[#parts + 1] = "value=" .. tostring(debuff.value) end
  if debuff.nominal then parts[#parts + 1] = "nominal=" .. tostring(debuff.nominal) end
  if #parts == 0 then
    return ""
  end
  return "Active debuff: " .. table.concat(parts, "/") .. ". "
end

local function blind_strategy_hint()
  if not (G and G.GAME and G.GAME.blind) then return "" end
  local name = G.GAME.blind.name or ""
  local hints = {
    ["The Needle"]    = "MAX 1 CARD PER HAND. Play exactly 1 card. Ignore all multi-card combo advice.",
    ["The Eye"]       = "NO REPEAT HAND TYPES. Every hand this round must be a different poker hand type. Plan across hands (Pair then Flush then Straight etc.).",
    ["The Mouth"]     = "SINGLE HAND TYPE ONLY. The first hand type you played is the only legal type this round. Only play that type.",
    ["The Water"]     = "EACH HAND COSTS 1 DISCARD. Every hand you play reduces your discards by 1. Treat discards as double-precious.",
    ["Verdant Leaf"]  = "ALL CARDS DEBUFFED until you sell a joker. Use sell_card on a joker immediately — scoring is impossible until you do.",
    ["Amber Acorn"]   = "JOKER ORDER SHUFFLED after each hand. Do not rely on position-sensitive jokers (Blueprint, Brainstorm).",
    ["Crimson Heart"] = "RANDOM JOKER DISABLED each hand. Do not count on any single joker firing every play.",
    ["The Ox"]        = "OX WARNING: Playing your most-played hand type this run resets your money to $0. Vary your hand types.",
    ["The Mark"]      = "MARK BLIND: Face cards (J/Q/K) drawn face-down but visible in hand — no mechanical impact.",
    ["The Fish"]      = "FISH BLIND: Cards drawn face-down each hand. Plan with what you can see in hand.",
    ["The Serpent"]   = "SERPENT BLIND: 3 cards auto-drawn after each play or discard. You have no control over drawing.",
    ["The Pillar"]    = "PILLAR BLIND: Cards already played this ante score 0 chips. Prefer cards not yet played this ante.",
  }
  local hint = hints[name]
  if not hint then return "" end
  return once_per_state_entry_hint("blind_strategy", "BOSS BLIND RULE — " .. hint .. " ")
end

local function tarot_target_advice(nm, deck_name)
  if nm == "The Twins" and deck_name == "Twin deck" then
    return "Target your 2 best Kings. "
  elseif nm == "The Twins" and deck_name == "Euchre deck" then
    return "Target your 2 best Jacks. "
  elseif nm == "The Twins" and deck_name == "Checkered Deck" then
    return "Target 2 high-value cards of same suit. "
  elseif nm == "The Bit" and deck_name == "Twin deck" then
    return "Target your best King. "
  elseif nm == "The Bit" and deck_name == "Euchre deck" then
    return "Target your best Jack. "
  elseif nm == "The Bit" and deck_name == "Checkered Deck" then
    return "Target your best high-value card. "
  end
  local t = {
    ["The Twins"]       = "Target your 2 highest-value cards you play most often. Enhanced = +15chips +2mult. ",
    ["The Bit"]         = "Target 1 card — Donation enhancement ($2 when scored). Best on frequently played cards. ",
    ["The Empress"]     = "Target up to 2 cards — Mult enhancement (+4 mult). Best on Aces or face cards. ",
    ["The Hierophant"]  = "Target up to 2 cards — Bonus enhancement (+30 chips). Best on high-chip cards played often. ",
    ["The Lovers"]      = "Target 1 card — Wild enhancement (counts as any suit). Best on rank needed for straights/flushes. ",
    ["The Chariot"]     = "Target 1 card — Steel enhancement (+0.5x mult while held). Best on a card you rarely play. ",
    ["Justice"]         = "Target 1 card — Glass enhancement (x2 mult, 1-in-4 shatters). Best on Aces/high scorers. ",
    ["Strength"]        = "Target up to 2 cards — increases rank by 1 (2→3, Q→K). Best on 2s or 3s. ",
    ["The Hanged Man"]  = "Target up to 2 cards to DESTROY permanently. Best on weakest cards to shrink deck. ",
    ["Death"]           = "Select 2 cards: LEFT = template to copy FROM, RIGHT = card to overwrite. ",
    ["The Devil"]       = "Target 1 card — Gold enhancement (+3 money when scored). Best on frequently played cards. ",
    ["The Tower"]       = "Target 1 card — Stone enhancement (+50 chips, no rank/suit). Best on unused-suit cards. ",
    ["The Star"]        = "Target up to 3 cards — converts to Spades. Use if Spade joker synergy active. ",
    ["The Moon"]        = "Target up to 3 cards — converts to Clubs. Use if Club joker synergy active. ",
    ["The Sun"]         = "Target up to 3 cards — converts to Hearts. Use if Heart joker synergy active. ",
    ["The World"]       = "Target up to 3 cards — converts to Diamonds. Use if Diamond joker synergy active. ",
    ["The Magician"]    = "Target up to 2 cards — Lucky enhancement (chance for mult bonus). Best on low-rank cards played often. ",
    ["Mitosis"]         = "Target 1 card — Shoomimi seal (when destroyed, spawns 2 copies). Best on a high-value card you play often to grow your deck. ",
    ["Rhythm"]          = "Target up to 2 cards — Osu! seal (+5 Mult each time played, resets on discard). NEVER discard these cards. Best on cards you play every hand. ",
    ["Familiar"]        = "Target 2 cards to DESTROY — adds 3 random enhanced face cards to deck. Best on your 2 weakest non-face cards. ",
    ["Grim"]            = "Target 2 cards to DESTROY — adds 2 random Aces to deck. Best on your 2 weakest cards. ",
    ["Incantation"]     = "Target 2 cards to DESTROY — adds 4 random numbered cards (2-10) to deck. Best on your 2 weakest face/high cards if you need more numbered cards. ",
    ["Talisman"]        = "Target 1 card — adds Gold Seal (+$3 when hand containing it is played). Best on a card you play every hand. ",
    ["Aura"]            = "Target 1 card — adds foil/holo/polychrome edition randomly. Best on your highest-scoring card. ",
    ["Deja Vu"]         = "Target 1 card — adds Red Seal (plays card twice). Best on your highest chip/mult card. ",
    ["Trance"]          = "Target 1 card — adds Blue Seal (creates a planet card when held in hand at end of round). Best on a card you rarely play. ",
    ["Medium"]          = "Target 1 card — adds Purple Seal (creates a tarot card when discarded). Best on a card you discard often. ",
    ["Cryptid"]         = "Target 1 card — creates 2 copies of it in your deck. Best on your strongest scoring card. ",
  }
  return t[nm] or ""
end

local function blueprint_chain_hint()
  if not (G and G.jokers and G.jokers.cards) then return "" end
  local cards = G.jokers.cards
  local chain_parts = {}
  for i, card in ipairs(cards) do
    local nm = card and card.ability and card.ability.name or ""
    if nm == "Blueprint" or nm == "Brainstorm" then
      local target = cards[i + 1]
      local target_nm = target and target.ability and target.ability.name or "none"
      local xm = target and target.ability and target.ability.x_mult or 1
      local suffix = (xm and xm > 1) and string.format("(xMult=%.1f)", xm) or ""
      chain_parts[#chain_parts + 1] = string.format("%s[%d]→copies %s%s", nm, i, target_nm, suffix)
    end
  end
  if #chain_parts == 0 then return "" end
  return once_per_state_entry_hint("bp_chain",
    "JOKER CHAIN: " .. table.concat(chain_parts, "; ") .. ". Position-sensitive — use set_joker_order if needed. ")
end

local function voucher_chain_hint()
  if not (G and G.GAME) then return "" end
  local owned = G.GAME.used_vouchers or {}
  local chains = {
    {base="v_overstock",       upgrade="v_overstock_plus",  base_name="Overstock",       up_name="Overstock Plus"},
    {base="v_clearance_sale",  upgrade="v_liquidation",     base_name="Clearance Sale",  up_name="Liquidation"},
    {base="v_hone",            upgrade="v_glow_up",         base_name="Hone",            up_name="Glow Up"},
    {base="v_reroll_surplus",  upgrade="v_reroll_glut",     base_name="Reroll Surplus",  up_name="Reroll Glut"},
    {base="v_crystal_ball",    upgrade="v_omen_globe",      base_name="Crystal Ball",    up_name="Omen Globe"},
    {base="v_telescope",       upgrade="v_observatory",     base_name="Telescope",       up_name="Observatory"},
    {base="v_grabber",         upgrade="v_nacho_tong",      base_name="Grabber",         up_name="Nacho Tong"},
    {base="v_wasteful",        upgrade="v_recyclomancy",    base_name="Wasteful",        up_name="Recyclomancy"},
    {base="v_tarot_merchant",  upgrade="v_tarot_tycoon",    base_name="Tarot Merchant",  up_name="Tarot Tycoon"},
    {base="v_planet_merchant", upgrade="v_planet_tycoon",   base_name="Planet Merchant", up_name="Planet Tycoon"},
    {base="v_seed_money",      upgrade="v_money_tree",      base_name="Seed Money",      up_name="Money Tree"},
    {base="v_blank",           upgrade="v_antimatter",      base_name="Blank",           up_name="Antimatter"},
    {base="v_magic_trick",     upgrade="v_illusion",        base_name="Magic Trick",     up_name="Illusion"},
    {base="v_hieroglyph",      upgrade="v_petroglyph",      base_name="Hieroglyph",      up_name="Petroglyph"},
    {base="v_directors_cut",   upgrade="v_retcon",          base_name="Director's Cut",  up_name="Retcon"},
    {base="v_paint_brush",     upgrade="v_palette",         base_name="Paint Brush",     up_name="Palette"},
  }
  local shop_keys = {}
  if G.shop_vouchers and G.shop_vouchers.cards then
    for _, card in ipairs(G.shop_vouchers.cards) do
      local center = card.config and card.config.center
      local key = center and center.key or ""
      if key ~= "" then shop_keys[key] = true end
    end
  end
  local hints = {}
  for _, pair in ipairs(chains) do
    if shop_keys[pair.base] and not owned[pair.base] then
      hints[#hints + 1] = string.format("Buy %s now → unlocks %s next ante", pair.base_name, pair.up_name)
    elseif shop_keys[pair.upgrade] and owned[pair.base] then
      hints[#hints + 1] = string.format("CHAIN UPGRADE: you own %s, buy %s", pair.base_name, pair.up_name)
    end
  end
  if #hints == 0 then return "" end
  return once_per_state_entry_hint("voucher_chain",
    "VOUCHER CHAINS: " .. table.concat(hints, "; ") .. ". ")
end

local function shop_money_projection()
  if not (G and G.GAME) then return "" end
  local m = G.GAME.dollars or 0
  local no_int = G.GAME.modifiers and G.GAME.modifiers.no_interest
  local amt = G.GAME.interest_amount or 1
  local cap = G.GAME.interest_cap or 25
  local blind_reward = (G.GAME.blind and G.GAME.blind.dollars) or 3
  local function int_for(x)
    if no_int then return 0 end
    return amt * math.min(math.floor(x / 5), math.floor(cap / 5))
  end
  local cur_int = int_for(m)
  local after_r1 = m + blind_reward + cur_int
  local int_r2 = int_for(after_r1)
  return once_per_state_entry_hint("money_proj", string.format(
    "MONEY PROJECTION (if $0 spent): blind reward +$%d, interest +$%d → $%d after round. Next round interest: +$%d. Each $5 saved = +$%d/rd interest (cap $%d). ",
    blind_reward, cur_int, after_r1, int_r2, amt, cap))
end

local function failed_action_warning()
  if not (G and G.NEURO.last_failed_action) then return "" end
  return "Your last action (" .. G.NEURO.last_failed_action .. ") FAILED. Do NOT repeat it — choose a different action. "
end

local function send_result(bridge, id, ok, message, name)
  local enhanced_message = message
  if bridge then
    if ok and not message then
      enhanced_message = "Action executed successfully"
      if name == "play_cards_from_highlighted" and G and G.GAME then
        local hands_left = G.GAME.current_round and G.GAME.current_round.hands_left
        if hands_left then
          enhanced_message = enhanced_message .. string.format(". Hands remaining: %d", hands_left - 1)
        end
      elseif name == "discard_cards_from_highlighted" and G and G.GAME then
        local discards_left = G.GAME.current_round and G.GAME.current_round.discards_left
        if discards_left then
          enhanced_message = enhanced_message .. string.format(". Discards remaining: %d", discards_left - 1)
        end
      elseif name == "buy_from_shop" and G and G.GAME then
        enhanced_message = enhanced_message .. string.format(". Money: $%d", G.GAME.dollars or 0)
      elseif name == "sell_card" and G and G.GAME then
        enhanced_message = enhanced_message .. string.format(". Money: $%d", G.GAME.dollars or 0)
      end
    end
    bridge:send_action_result(id, ok, enhanced_message)
  end
  tx_store(id, ok, enhanced_message, name)
  do
    local ok_stage, Staging = pcall(require, "staging")
    if ok_stage and Staging and Staging.mark_settled then
      pcall(Staging.mark_settled, id, ok)
    end
  end
  if ok then
    push_recent_action(name)
    if G then G.NEURO.last_failed_action = nil end
  elseif G and name then
    G.NEURO.last_failed_action = name
  end
  if is_forced_action(name) then
    if ok then
      if name == "start_run" and G then
        local State = require("state")
        local cur = State.get_state_name()
        if cur == "SPLASH" or cur == "MENU" or cur == "RUN_SETUP" then
          G.NEURO.in_run_setup = true
        else
          G.NEURO.in_run_setup = nil
        end
      end
    else
      G.NEURO.last_force_fingerprint = nil
      G.NEURO.force_dirty = true
      G.NEURO.force_dirty_at = (G and G.TIMERS and G.TIMERS.REAL) or os.clock()
    end
    clear_force_inflight()
  end
end

local function is_object_table(value)
  if type(value) ~= "table" then
    return false
  end
  for k, _ in pairs(value) do
    if type(k) ~= "string" then
      return false
    end
  end
  return true
end

local function is_array_table(value)
  if type(value) ~= "table" then
    return false
  end
  for k, _ in pairs(value) do
    if type(k) ~= "number" then
      return false
    end
  end
  return true
end

local function is_integer(value)
  return type(value) == "number" and math.floor(value) == value
end

local function enum_contains(enum, value)
  if not enum then
    return true
  end
  for i = 1, #enum do
    if enum[i] == value then
      return true
    end
  end
  return false
end

local function validate_value(schema, value, label)
  if not schema then
    return true
  end
  local t = schema.type
  if t == "object" then
    if not is_object_table(value) then
      return false, label .. " must be an object."
    end
    local required = schema.required or {}
    for i = 1, #required do
      local key = required[i]
      if value[key] == nil then
        return false, "Missing required parameter: " .. key
      end
    end
    local props = schema.properties or {}
    for key, prop in pairs(props) do
      if value[key] ~= nil then
        local ok, err = validate_value(prop, value[key], key)
        if not ok then
          return false, err
        end
      end
    end
  elseif t == "array" then
    if not is_array_table(value) then
      return false, label .. " must be an array."
    end
    if schema.items then
      for i = 1, #value do
        local ok, err = validate_value(schema.items, value[i], label .. "[" .. i .. "]")
        if not ok then
          return false, err
        end
      end
    end
  elseif t == "string" then
    if type(value) ~= "string" then
      return false, label .. " must be a string."
    end
  elseif t == "integer" then
    if not is_integer(value) then
      return false, label .. " must be an integer."
    end
  elseif t == "number" then
    if type(value) ~= "number" then
      return false, label .. " must be a number."
    end
  elseif t == "boolean" then
    if type(value) ~= "boolean" then
      return false, label .. " must be a boolean."
    end
  end
  if schema.enum and not enum_contains(schema.enum, value) then
    return false, label .. " must be one of: " .. table.concat(schema.enum, ", ")
  end
  if schema.minimum and type(value) == "number" and value < schema.minimum then
    return false, label .. " must be >= " .. tostring(schema.minimum)
  end
  return true
end

local function find_uie_by_id(id)
  if not id then
    return nil
  end
  local containers = {
    G.OVERLAY_MENU,
    G.HUD,
    G.buttons,
    G.shop,
    G.blind_select,
    G.blind_prompt_box,
    G.booster_pack,
    G.shop_jokers,
    G.shop_vouchers,
    G.shop_booster,
  }
  for _, obj in ipairs(containers) do
    if obj and obj.get_UIE_by_ID then
      local found = obj:get_UIE_by_ID(id)
      if found then
        return found
      end
    end
  end
  return nil
end

local function resolve_ref_table(data, config)
  if not data then
    return
  end
  local ref = data.ref
  if ref then
    if ref.id then
      config.ref_table = find_uie_by_id(ref.id)
    elseif ref.area and ref.index then
      local area = get_area(ref.area)
      config.ref_table = get_card(area, ref.index)
    end
  end
  if not config.ref_table and data.ref_id then
    config.ref_table = find_uie_by_id(data.ref_id)
  end
  if not config.ref_table and data.ref_area and data.ref_index then
    local area = get_area(data.ref_area)
    config.ref_table = get_card(area, data.ref_index)
  end
end

local function clear_area_highlight(area)
  if not area then return end

  if type(area.unhighlight_all) == "function" then
    pcall(function() area:unhighlight_all() end)
    return
  end

  local highlighted = area.highlighted
  if type(highlighted) ~= "table" then
    area.highlighted = {}
    return
  end

  if type(area.remove_from_highlighted) == "function" then
    for i = #highlighted, 1, -1 do
      local card = highlighted[i]
      if card then
        pcall(function() area:remove_from_highlighted(card) end)
      end
    end
  else
    for i = 1, #highlighted do
      local card = highlighted[i]
      if card then
        card.highlighted = false
      end
    end
    area.highlighted = {}
  end
end

local function add_area_highlight(area, card)
  if not area or not card then return false end
  if type(area.add_to_highlighted) == "function" then
    local ok = pcall(function() area:add_to_highlighted(card) end)
    return ok
  end
  area.highlighted = area.highlighted or {}
  card.highlighted = true
  if G and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
  table.insert(area.highlighted, card)
  return true
end

local function normalize_indices(indices, max_cards)
  local out = {}
  local seen = {}
  if type(indices) ~= "table" then return out end
  for i = 1, #indices do
    local idx = tonumber(indices[i])
    if idx then
      idx = math.floor(idx)
      if idx >= 1 and idx <= max_cards and not seen[idx] then
        out[#out + 1] = idx
        seen[idx] = true
        if #out >= 5 then break end
      end
    end
  end
  return out
end

local function estimate_selected_score(selected_cards, hand_info)
  if not (selected_cards and hand_info and hand_info.type and G and G.GAME and G.GAME.hands) then
    return 0
  end
  local hand_entry = G.GAME.hands[hand_info.type]
  if type(hand_entry) ~= "table" then
    return 0
  end

  local base_chips = tonumber(hand_entry.chips) or 0
  local base_mult = tonumber(hand_entry.mult) or 0
  local joker_chips = 0
  local joker_mult = 0
  local joker_xmult = 1
  local scoring_cards = #selected_cards

  if G.jokers and G.jokers.cards then
    for _, joker in ipairs(G.jokers.cards) do
      local ab = joker and joker.ability or {}
      if type(ab.h_mod) == "number" then joker_chips = joker_chips + ab.h_mod end
      if type(ab.h_mult) == "number" then joker_mult = joker_mult + ab.h_mult end
      if type(ab.x_mult) == "number" and ab.x_mult > 0 then
        joker_xmult = joker_xmult * ab.x_mult
      end
      if type(ab.c_mult) == "number" and scoring_cards > 0 then
        joker_mult = joker_mult + (ab.c_mult * scoring_cards)
      end
    end
  end

  local chips = math.max(0, base_chips + joker_chips)
  local mult = math.max(0, base_mult + joker_mult)
  local est = math.floor(chips * mult * math.max(0, joker_xmult))
  if est < 0 then return 0 end
  return est
end

local function get_blind_play_limits()
  local min_cards, max_cards = 1, 5
  local blind = G and G.GAME and G.GAME.blind
  local debuff = blind and blind.debuff
  if type(debuff) == "table" then
    local min_raw = tonumber(debuff.h_size_ge or 0) or 0
    local max_raw = tonumber(debuff.h_size_le or 0) or 0
    if min_raw > 0 then
      min_cards = math.max(min_cards, math.floor(min_raw))
    end
    if max_raw > 0 then
      max_cards = math.min(max_cards, math.floor(max_raw))
    end
  end
  return min_cards, max_cards
end

local function best_legal_play_snapshot()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0 and G.FUNCS and G.FUNCS.get_poker_hand_info) then
    return nil
  end

  local cards = G.hand.cards
  local n = #cards
  local min_cards, max_cards = get_blind_play_limits()
  max_cards = math.min(max_cards, n)
  if min_cards > max_cards then
    return nil
  end

  local hand_has_non_debuffed = false
  for i = 1, n do
    if cards[i] and not cards[i].debuff then
      hand_has_non_debuffed = true
      break
    end
  end

  local picks = {}
  local best = { score = -1, indices = nil, hand_type = nil }

  local function consider_current()
    local selected = {}
    local all_debuffed = true
    for i = 1, #picks do
      local c = cards[picks[i]]
      if c then
        selected[#selected + 1] = c
        if not c.debuff then all_debuffed = false end
      end
    end
    if #selected == 0 then return end
    if hand_has_non_debuffed and all_debuffed then return end

    local ok_info, hand_info = pcall(G.FUNCS.get_poker_hand_info, selected)
    if not (ok_info and type(hand_info) == "table" and hand_info.type) then
      return
    end

    local est = estimate_selected_score(selected, hand_info)
    local dominated = false
    if best.score >= 0 then
      if best.hand_type == tostring(hand_info.type) then
        -- Same hand type: prefer fewer cards, then higher score
        if #picks < #best.indices then
          dominated = true
        elseif #picks == #best.indices and est > best.score then
          dominated = true
        end
      else
        -- Different hand type: prefer higher score
        if est > best.score then
          dominated = true
        end
      end
    else
      dominated = true  -- first candidate always wins
    end
    if dominated then
      local idx = {}
      for i = 1, #picks do idx[#idx + 1] = picks[i] end
      best.score = est
      best.indices = idx
      best.hand_type = tostring(hand_info.type)
    end
  end

  local function rec(start_idx, need)
    if need == 0 then
      consider_current()
      return
    end
    for i = start_idx, n - need + 1 do
      picks[#picks + 1] = i
      rec(i + 1, need - 1)
      picks[#picks] = nil
    end
  end

  for k = min_cards, max_cards do
    rec(1, k)
  end

  if best.score < 0 then return nil end

  local target = 0
  local score_now = 0
  if G.GAME and G.GAME.blind then
    target = (G.GAME.blind.chips or 0) * (G.GAME.blind.mult or 1)
    score_now = G.GAME.chips or 0
  end
  local remaining = math.max(0, target - score_now)

  return {
    remaining = remaining,
    best_score = best.score,
    best_indices = best.indices,
    best_hand_type = best.hand_type,
    can_clear = (remaining > 0 and best.score >= remaining),
  }
end

local function shop_affordable_snapshot()
  local out = {
    money = (G and G.GAME and G.GAME.dollars) or 0,
    jokers = 0,
    boosters = 0,
    vouchers = 0,
    total = 0,
    buyable_good = false,
  }
  if not G then return out end

  local function scan(area, key)
    if not (area and area.cards) then return end
    for _, card in ipairs(area.cards) do
      local cost = card and card.cost
      if type(cost) == "number" and cost >= 0 and cost <= out.money then
        out[key] = out[key] + 1
        out.total = out.total + 1
      end
    end
  end

  scan(G.shop_jokers, "jokers")
  scan(G.shop_booster, "boosters")
  scan(G.shop_vouchers, "vouchers")

  local joker_space = true
  if G.jokers and G.jokers.cards and G.jokers.config and G.jokers.config.card_limit then
    joker_space = #G.jokers.cards < (G.jokers.config.card_limit or 0)
  end

  out.buyable_good = (out.boosters > 0) or (out.jokers > 0 and joker_space)
  return out
end

local function handle_set_hand_highlight(data)
  if not G.hand or not G.hand.cards then
    return nil, "Hand is not available yet. Wait for the hand screen, then select cards."
  end
  local indices = normalize_indices(data.indices, #G.hand.cards)
  local action = data.action

  if #indices == 0 then
    return nil, "No valid card indices provided. Hand has " .. #G.hand.cards .. " cards, use indices 1-" .. #G.hand.cards .. "."
  end

  if action == "discard" then
    local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
    if discards_left <= 0 then
      return nil, "No discards remaining. Use action='play' instead."
    end

    local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
    if hands_left > 0 then
      local snap = best_legal_play_snapshot()
      if snap and snap.can_clear and hands_left <= 1 then
        return nil, string.format(
          "Win-now discard rejected: remaining %d, best legal play estimates %d (%s). Play now to clear blind.",
          math.max(0, math.floor(snap.remaining or 0)),
          math.max(0, math.floor(snap.best_score or 0)),
          tostring(snap.best_hand_type or "best line")
        )
      end
    end
  elseif action == "play" then
    local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
    if hands_left <= 0 then
      return nil, "No hands remaining. You cannot play cards right now."
    end

    local selected_cards = {}
    for i = 1, #indices do
      local card = G.hand.cards[indices[i]]
      if card then
        selected_cards[#selected_cards + 1] = card
      end
    end

    local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
    local blind = G.GAME and G.GAME.blind or nil
    local debuff = blind and blind.debuff or nil
    if type(debuff) == "table" and #selected_cards > 0 then
      local min_cards = tonumber(debuff.h_size_ge or 0) or 0
      if min_cards > 0 and #selected_cards < min_cards then
        return nil, string.format(
          "Blind rule requires at least %d played cards. Selected %d. Use more cards or discard first.",
          min_cards,
          #selected_cards
        )
      end

      local selected_debuffed = 0
      for i = 1, #selected_cards do
        if selected_cards[i] and selected_cards[i].debuff then
          selected_debuffed = selected_debuffed + 1
        end
      end

      local hand_debuffed = 0
      if G.hand and G.hand.cards then
        for i = 1, #G.hand.cards do
          if G.hand.cards[i] and G.hand.cards[i].debuff then
            hand_debuffed = hand_debuffed + 1
          end
        end
      end

      local can_retry = (discards_left > 0) or (hands_left > 1)
      if can_retry and selected_debuffed == #selected_cards and hand_debuffed < #G.hand.cards then
        return nil, "Debuffed-only play rejected: selected cards are all debuffed by current blind. Prefer discard or choose non-debuffed cards."
      end
    end

    if discards_left > 0 and hands_left > 1 and #selected_cards > 0 and G.FUNCS and G.FUNCS.get_poker_hand_info then
      local ok_info, hand_info = pcall(G.FUNCS.get_poker_hand_info, selected_cards)
      if ok_info and type(hand_info) == "table" then
        local hand_type = tostring(hand_info.type or ""):lower()
        local target = 0
        local score_now = 0
        if G.GAME and G.GAME.blind then
          target = (G.GAME.blind.chips or 0) * (G.GAME.blind.mult or 1)
          score_now = G.GAME.chips or 0
        end
        local remaining = math.max(0, target - score_now)
        if hand_type:find("high", 1, true) and remaining > 0 then
          local est = estimate_selected_score(selected_cards, hand_info)
          local threshold = math.max(120, math.floor(remaining * 0.55))
          local is_five_card = #selected_cards >= 5
          local clears_target = est >= remaining
          local reject_five_high = is_five_card and not clears_target
          local reject_weak_high = est > 0 and est < threshold
          if reject_five_high or reject_weak_high then
            return nil, string.format(
              "Low-value play rejected: high-card line estimates %d vs remaining %d with %d discard(s) left. Do not force High Card here; prefer action='discard' or stronger combo.",
              est,
              remaining,
              discards_left
            )
          end
        end
      end
    end
  end

  return function()
    clear_area_highlight(G.hand)
    local selected_cards = {}
    for i = 1, #indices do
      local idx = indices[i]
      local card = G.hand.cards[idx]
      if card then
        add_area_highlight(G.hand, card)
        local card_name = "Card"
        if card.base then
          local v = tostring(card.base.value or "?")
          local s = tostring(card.base.suit or "?")
          card_name = v .. " of " .. s
        end
        table.insert(selected_cards, idx .. ":" .. card_name)
      end
    end

    if #selected_cards == 0 then
      return "Cleared selection (no valid indices)"
    end

    local msg = "Selected cards: " .. table.concat(selected_cards, ", ")

    if action == "play" then
      if #G.hand.highlighted == 0 then
        return msg .. ". No valid cards to play."
      end
      local fn_play = G.FUNCS and G.FUNCS.play_cards_from_highlighted
      if fn_play then fn_play({ config = {}, UIBox = mock_UIBox }) end
      local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
      return msg .. string.format(". Playing hand! Hands remaining: %d", hands_left - 1)
    elseif action == "discard" then
      if #G.hand.highlighted == 0 then
        return msg .. ". No valid cards to discard."
      end
      local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
      if discards_left <= 0 then
        return msg .. ". Cannot discard: no discards remaining. Use action='play' instead."
      end
      local fn_discard = G.FUNCS and G.FUNCS.discard_cards_from_highlighted
      if fn_discard then fn_discard({ config = {}, UIBox = mock_UIBox }) end
      return msg .. string.format(". Discarding! Discards remaining: %d", discards_left - 1)
    end

    return msg
  end
end

local function validate_area_card(data)
  local area = get_area(data.area)
  if not area or not area.cards then
    return nil, nil, "Area '" .. tostring(data.area) .. "' is not available right now."
  end
  if type(data.index) ~= "number" or data.index < 1 or data.index > #area.cards then
    return nil, nil, "Index " .. tostring(data.index) .. " out of bounds ('" .. tostring(data.area) .. "' has " .. #area.cards .. " cards). Use 1-" .. #area.cards .. "."
  end
  local card = area.cards[data.index]
  if not card then
    return nil, nil, "Card at index " .. tostring(data.index) .. " is nil in '" .. tostring(data.area) .. "'."
  end
  return area, card, nil
end

local function handle_use_card(data)
  local area, card, err = validate_area_card(data)
  if err then return nil, err end
  local card_name = safe_name(card) or "Unknown"

  local function snapshot_booster_options(selected_card)
    local bp = G and (G.pack_cards or G.booster_pack)
    if not (bp and bp.cards and #bp.cards > 0) then
      return nil
    end
    local options = {}
    local selected_index = 1
    for i, opt in ipairs(bp.cards) do
      local nm = safe_name(opt) or ("Card " .. tostring(i))
      local ds = Utils.card_description(opt)
      if (not ds or ds == "") and opt and opt.config and opt.config.center then
        ds = Utils.safe_description(opt.config.center.loc_txt, opt)
      end
      options[#options + 1] = {
        card = opt,
        name = tostring(nm),
        desc = tostring(ds or "-"),
      }
      if opt == selected_card then
        selected_index = i
      end
    end
    return {
      selected_index = selected_index,
      options = options,
      picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0,
    }
  end

  local function queue_pick_showcase(tag, shown_cost, extra)
    if not G then return end
    local q = G.NEURO.purchase_showcase_queue
    if type(q) ~= "table" then q = {} end

    local desc = Utils.card_description(card)
    if (not desc or desc == "") and card and card.config and card.config.center then
      desc = Utils.safe_description(card.config.center.loc_txt, card)
    end
    if not desc or desc == "" then desc = "-" end

    q[#q + 1] = {
      card = card,
      name = card_name,
      desc = tostring(desc),
      cost = tonumber(shown_cost) or 0,
      area = tostring(tag or "pick"),
      at = (G.TIMERS and G.TIMERS.REAL) or os.clock(),
      options = extra and extra.options or nil,
      selected_index = extra and extra.selected_index or nil,
      picks_left = extra and extra.picks_left or nil,
    }
    while #q > 2 do
      table.remove(q, 1)
    end
    G.NEURO.purchase_showcase_queue = q
  end

  local is_playing_card = card.base ~= nil and card.base.suit ~= nil

  local hand_indices = nil
  if data.hand_indices and type(data.hand_indices) == "table" and #data.hand_indices > 0 then
    if not G.hand or not G.hand.cards then
      return nil, "Hand is not available. Cannot highlight cards for consumable use."
    end
    hand_indices = normalize_indices(data.hand_indices, #G.hand.cards)
    if #hand_indices == 0 then
      return nil, "No valid hand_indices provided. Hand has " .. #G.hand.cards .. " cards, use indices 1-" .. #G.hand.cards .. "."
    end
    local mh = card.ability and card.ability.consumeable and card.ability.consumeable.max_highlighted
    local mn = card.ability and card.ability.consumeable and card.ability.consumeable.min_highlighted or 1
    if mh and #hand_indices > mh then
      return nil, string.format("Too many cards: '%s' needs at most %d highlighted, you provided %d.", card_name, mh, #hand_indices)
    end
    if mh and #hand_indices < mn then
      return nil, string.format("Too few cards: '%s' needs at least %d highlighted, you provided %d.", card_name, mn, #hand_indices)
    end
  end

  return function()
    local pack_snapshot = nil
    local bp = G and (G.pack_cards or G.booster_pack)
    local is_pack_pick = (area == bp)

    if is_pack_pick then
      pack_snapshot = snapshot_booster_options(card)

      -- Glow + highlight the chosen card so the AI overlay fires
      pcall(function()
        card.highlighted = true
        if G and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
      end)
      -- Hover animation immediately
      if NeuroAnim and NeuroAnim.hover_pack_card then
        pcall(function() NeuroAnim.hover_pack_card(card, bp) end)
      end

      -- Delay the actual pick so the highlight is visible
      local pack_pick_block = dotenv.num("NEURO_PACK_PICK_BLOCK", 3.0)
      local pack_pick_delay = dotenv.num("NEURO_PACK_PICK_DELAY", 2.2)
      local t = (G.TIMERS and G.TIMERS.REAL) or os.clock()
      G.NEURO.last_action_at = t + pack_pick_block

      -- Does this pack card need hand card selection? (Tarots like "change N to suit")
      local needs_hand_sel = (not is_playing_card)
        and card.ability and card.ability.consumeable
        and card.ability.consumeable.max_highlighted
        and card.ability.consumeable.max_highlighted > 0
      local captured_hand_indices = (needs_hand_sel and hand_indices) or nil

      if G.E_MANAGER and Event then
        local fn = G.FUNCS and G.FUNCS.use_card
        G.E_MANAGER:add_event(Event({
          trigger = "after",
          delay   = pack_pick_delay,
          func    = function()
            pcall(function()
              card.highlighted = false
              if NeuroAnim and NeuroAnim.pick_pack_card then NeuroAnim.pick_pack_card(card, bp) end
              -- Pre-highlight hand cards for Tarots that need selection
              if captured_hand_indices and G.hand and G.hand.cards then
                clear_area_highlight(G.hand)
                for _, idx in ipairs(captured_hand_indices) do
                  local hcard = G.hand.cards[idx]
                  if hcard then add_area_highlight(G.hand, hcard) end
                end
              end
              if is_playing_card then
                pcall(function() card:click() end)
              elseif fn then
                fn({ config = { ref_table = card }, UIBox = mock_UIBox })
              end
            end)
            -- Auto-confirm hand selection after a short delay
            if captured_hand_indices then
              G.E_MANAGER:add_event(Event({
                trigger = "after",
                delay   = HAND_CONFIRM_DELAY,
                func    = function()
                  pcall(function()
                    local end_fn = G.FUNCS and G.FUNCS.end_consumeable
                    if end_fn then end_fn() end
                  end)
                  return true
                end,
              }))
            end
            return true
          end,
        }))
      else
        -- Fallback: immediate if E_MANAGER unavailable
        local fn = G.FUNCS and G.FUNCS.use_card
        if captured_hand_indices and G.hand and G.hand.cards then
          clear_area_highlight(G.hand)
          for _, idx in ipairs(captured_hand_indices) do
            local hcard = G.hand.cards[idx]
            if hcard then add_area_highlight(G.hand, hcard) end
          end
        end
        if is_playing_card then
          pcall(function() card:click() end)
        elseif fn then
          fn({ config = { ref_table = card }, UIBox = mock_UIBox })
        end
        if captured_hand_indices then
          pcall(function()
            local end_fn = G.FUNCS and G.FUNCS.end_consumeable
            if end_fn then end_fn() end
          end)
        end
      end

      G.NEURO.pack_best = nil
      -- Signal the winner index so the live pack_browse panel flips to winner mode immediately.
      if pack_snapshot and pack_snapshot.selected_index then
        G.NEURO.pack_winner_index = pack_snapshot.selected_index
      end
      if pack_snapshot and pack_snapshot.options and #pack_snapshot.options >= 2 then
        queue_pick_showcase("booster_choice", 0, pack_snapshot)
      else
        queue_pick_showcase("booster_pick", 0)
      end
    else
      if hand_indices and G.hand and G.hand.cards then
        clear_area_highlight(G.hand)
        for _, idx in ipairs(hand_indices) do
          local hcard = G.hand.cards[idx]
          if hcard then add_area_highlight(G.hand, hcard) end
        end
      end
      local fn = G.FUNCS and G.FUNCS.use_card
      if fn then fn({ config = { ref_table = card }, UIBox = mock_UIBox }) end
    end

    return "Used: " .. card_name
  end
end

local function handle_buy_from_shop(data)
  local area, card, err = validate_area_card(data)
  if err then return nil, err end
  local card_name = safe_name(card) or "Unknown"
  local cost = card.cost or 0
  local dollars = G.GAME and G.GAME.dollars or 0
  local reserved = tonumber(G.NEURO.reserved_dollars or 0) or 0
  local available = (tonumber(dollars) or 0) - reserved
  if cost > available then
    if reserved > 0 then
      return nil, string.format("Can't afford %s ($%d). You have $%d but $%d is reserved for pending purchases.", card_name, cost, tonumber(dollars) or 0, reserved)
    else
      return nil, string.format("Can't afford %s ($%d). You only have $%d.", card_name, cost, tonumber(dollars) or 0)
    end
  end
  local cfg = { ref_table = card }
  local is_booster = card and card.ability and card.ability.set == "Booster"
  if data.use or is_booster then
    cfg.id = "buy_and_use"
  end

  if cfg.id ~= "buy_and_use" and G and G.FUNCS and type(G.FUNCS.check_for_buy_space) == "function" then
    local ok_space, has_space = pcall(G.FUNCS.check_for_buy_space, card)
    if ok_space and has_space == false then
      return nil, string.format("No slot space to buy %s now. Sell/use something first or choose another shop item.", card_name)
    end
  end

  local function queue_purchase_showcase()
    if not G then return end
    local q = G.NEURO.purchase_showcase_queue
    if type(q) ~= "table" then q = {} end

    local desc = Utils.card_description(card)
    if (not desc or desc == "") and card and card.config and card.config.center then
      desc = Utils.safe_description(card.config.center.loc_txt, card)
    end
    if not desc or desc == "" then desc = "-" end

    q[#q + 1] = {
      card = card,
      name = card_name,
      desc = tostring(desc),
      cost = cost,
      area = tostring(data.area or "shop"),
      at = (G.TIMERS and G.TIMERS.REAL) or os.clock(),
    }
    while #q > 2 do
      table.remove(q, 1)
    end
    G.NEURO.purchase_showcase_queue = q
  end

  -- Reserve the cost now so concurrent purchases see reduced available budget
  G.NEURO.reserved_dollars = (tonumber(G.NEURO.reserved_dollars or 0) or 0) + cost

  return function()
    -- Glow + highlight the card so the AI overlay fires
    pcall(function()
      card.highlighted = true
      if G and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
    end)
    local shop_buy_block = dotenv.num("NEURO_SHOP_BUY_BLOCK", 2.2)
    local shop_buy_delay = dotenv.num("NEURO_SHOP_BUY_DELAY", 2.2)
    local t = (G and G.TIMERS and G.TIMERS.REAL) or os.clock()
    G.NEURO.last_action_at = t + shop_buy_block
    queue_purchase_showcase()  -- show panel immediately
    if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
        trigger   = "after",
        delay     = shop_buy_delay,
        blockable = false,
        func      = function()
          pcall(function()
            card.highlighted = false
            -- NEURO_AI_HIGHLIGHTED auto-clears when highlighted=false; glow fades naturally
            G.NEURO.reserved_dollars = math.max(0, (tonumber(G.NEURO.reserved_dollars or 0) or 0) - cost)
            local cur_dollars = G.GAME and G.GAME.dollars or 0
            if cost > cur_dollars then return end  -- money changed during highlight window, abort
            local fn = G.FUNCS and G.FUNCS.buy_from_shop
            if fn then fn({ config = cfg, UIBox = mock_UIBox }) end
            if NeuroAnim and NeuroAnim.on_buy then NeuroAnim.on_buy(card) end
          end)
          return true
        end,
      }))
    else
      G.NEURO.reserved_dollars = math.max(0, (tonumber(G.NEURO.reserved_dollars or 0) or 0) - cost)
      local cur_dollars = G.GAME and G.GAME.dollars or 0
      if cost <= cur_dollars then
        local fn = G.FUNCS and G.FUNCS.buy_from_shop
        if fn then fn({ config = cfg, UIBox = mock_UIBox }) end
        if NeuroAnim and NeuroAnim.on_buy then NeuroAnim.on_buy(card) end
      end
    end
    return string.format("Buying: %s for $%d", card_name, cost)
  end
end

local function handle_sell_card(data)
  local area, card, err = validate_area_card(data)
  if err then return nil, err end
  local card_name = safe_name(card) or "Unknown"
  local sell_value = card.sell_cost or 0
  return function()
    local fn = G.FUNCS and G.FUNCS.sell_card
    if fn then fn({ config = { ref_table = card }, UIBox = mock_UIBox }) end
    return string.format("Sold: %s for $%d", card_name, sell_value)
  end
end

local function handle_card_click(data)
  local area, card, err = validate_area_card(data)
  if err then return nil, err end
  return function()
    if data and data.area == "booster_pack" then
      local is_pc = card.base ~= nil and card.base.suit ~= nil
      if is_pc then
        pcall(function() card:click() end)
      elseif G and G.FUNCS and type(G.FUNCS.use_card) == "function" then
        G.FUNCS.use_card({ config = { ref_table = card }, UIBox = mock_UIBox })
      end
      return "Picked booster card"
    end
    card:click()
  end
end

local function handle_highlight_card(data)
  local area, card, err = validate_area_card(data)
  if err then return nil, err end
  if not area.add_to_highlighted then
    return nil, "This area cannot be highlighted. Choose a different area."
  end
  local card_name = card.base and (card.base.value .. " of " .. card.base.suit) or
                    safe_name(card) or "Card"
  return function()
    area:add_to_highlighted(card)
    return "Highlighted: " .. card_name
  end
end

local function handle_unhighlight_all(data)
  local area = get_area(data.area)
  if not area then
    return nil, "That area is not available right now. Choose a different area."
  end
  local count = area.highlighted and #area.highlighted or 0
  return function()
    clear_area_highlight(area)
    return string.format("Unhighlighted %d cards", count)
  end
end

local function handle_play_cards_from_highlighted(data)
  if not G.hand or not G.hand.highlighted or #G.hand.highlighted == 0 then
    return nil, "No cards are highlighted. Highlight cards first, then play or discard."
  end
  local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
  if hands_left <= 0 then
    return nil, "No hands remaining. You cannot play cards right now."
  end
  return function()
    local highlighted = G.hand.highlighted
    local card_count = #highlighted
    if NeuroAnim and NeuroAnim.pre_play then pcall(function() NeuroAnim.pre_play(highlighted) end) end
    local fn = G.FUNCS and G.FUNCS.play_cards_from_highlighted
    if fn then fn({ config = {}, UIBox = mock_UIBox }) end
    return string.format("Playing %d card(s). Hands remaining: %d", card_count, hands_left - 1)
  end
end

local function handle_discard_cards_from_highlighted(data)
  if not G.hand or not G.hand.highlighted or #G.hand.highlighted == 0 then
    return nil, "No cards are highlighted. Highlight cards first, then play or discard."
  end
  local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
  if discards_left <= 0 then
    return nil, "No discards remaining. You cannot discard right now."
  end
  return function()
    local highlighted = G.hand.highlighted
    local card_count = #highlighted
    if NeuroAnim and NeuroAnim.pre_discard then pcall(function() NeuroAnim.pre_discard(highlighted) end) end
    local fn = G.FUNCS and G.FUNCS.discard_cards_from_highlighted
    if fn then fn({ config = {}, UIBox = mock_UIBox }) end
    return string.format("Discarding %d card(s). Discards remaining: %d", card_count, discards_left - 1)
  end
end

local function handle_clear_hand_highlight(data)
  if not G.hand then
    return nil, "Hand is not available yet. Wait for the hand screen, then select cards."
  end
  local count = G.hand.highlighted and #G.hand.highlighted or 0
  return function()
    clear_area_highlight(G.hand)
    return string.format("Cleared selection (%d cards)", count)
  end
end

local function handle_select_blind(data)
  local blind = data.blind
  if not G or not G.P_BLINDS then
    return nil, "Game is not ready yet."
  end
  local bs = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states
  local function is_selectable(key)
    return bs and bs[key] == "Select"
  end
  local current = (is_selectable("Small") and "small") or (is_selectable("Big") and "big") or (is_selectable("Boss") and "boss") or nil

  if blind == "small" then
    if not is_selectable("Small") then
      return nil, "Small blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local bl_small = G.P_BLINDS.bl_small
    if not bl_small then
      return nil, "Small blind definition not found."
    end
    local blind_name = bl_small.name or "Small Blind"
    return function()
      local fn = G.FUNCS and G.FUNCS.select_blind
      if fn then fn({ config = { ref_table = bl_small }, UIBox = mock_UIBox }) end
      return "Selected: " .. blind_name
    end
  elseif blind == "big" then
    if not is_selectable("Big") then
      return nil, "Big blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local bl_big = G.P_BLINDS.bl_big
    if not bl_big then
      return nil, "Big blind definition not found."
    end
    local blind_name = bl_big.name or "Big Blind"
    return function()
      local fn = G.FUNCS and G.FUNCS.select_blind
      if fn then fn({ config = { ref_table = bl_big }, UIBox = mock_UIBox }) end
      return "Selected: " .. blind_name
    end
  elseif blind == "boss" then
    if not is_selectable("Boss") then
      return nil, "Boss blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local boss_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices and
      G.GAME.round_resets.blind_choices.Boss
    local boss = boss_key and G.P_BLINDS[boss_key] or nil
    if boss then
      local boss_name = boss.name or "Boss Blind"
      return function()
        local fn = G.FUNCS and G.FUNCS.select_blind
        if fn then fn({ config = { ref_table = boss }, UIBox = mock_UIBox }) end
        return "Selected: " .. boss_name
      end
    end
    return nil, "Boss blind definition not found."
  end
  return nil, "Blind must be one of: small, big, boss. Currently selectable: " .. tostring(current or "none") .. "."
end

local function handle_change_stake(data)
  if type(data.to_key) ~= "number" then
    return nil, "Stake key is required. Provide a numeric stake id."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_stake
    if fn then fn({ to_key = data.to_key, UIBox = mock_UIBox }) end
  end
end

local function handle_change_challenge_list_page(data)
  if type(data.page) ~= "number" then
    return nil, "Challenge page is required. Provide a page number."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_challenge_list_page
    if fn then fn({ cycle_config = { current_option = data.page }, UIBox = mock_UIBox }) end
  end
end

local function handle_change_challenge_description(data)
  if type(data.id) ~= "string" then
    return nil, "Challenge id is required. Provide a valid challenge id."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_challenge_description
    if fn then fn({ config = { id = data.id }, UIBox = mock_UIBox }) end
  end
end

local function handle_change_selected_back(data)
  if type(data.back) ~= "string" then
    return nil, "Back key is required. Provide a valid back key."
  end
  -- Resolve string key (e.g. "b_red") to numeric pool index
  local pool = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back
  local target_idx, target_name = nil, nil
  if pool then
    for i, v in ipairs(pool) do
      if v.key == data.back then
        target_idx = i
        target_name = v.name
        break
      end
    end
  end
  if not target_idx then
    return nil, "Deck key '" .. data.back .. "' not found. Use a key like b_red, b_blue."
  end
  return function()
    local center = G.P_CENTER_POOLS.Back[target_idx]
    if not center then return "Deck not found at index" end
    -- Directly update viewed_back (what start_setup_run reads for new runs)
    if G.GAME and G.GAME.viewed_back and G.GAME.viewed_back.change_to then
      G.GAME.viewed_back:change_to(center)
    end
    -- Also update selected_back
    if G.GAME and G.GAME.selected_back and G.GAME.selected_back.change_to then
      G.GAME.selected_back:change_to(center)
    end
    -- Save to profile memory so the choice persists
    if G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile] then
      G.PROFILES[G.SETTINGS.profile].MEMORY.deck = target_name
    end
    -- Update deck preview visuals in the overlay (pcall for safety)
    pcall(function()
      if G.sticker_card then
        G.sticker_card.sticker = get_deck_win_sticker(G.GAME.viewed_back.effect.center)
        if G.sticker_card.area and G.sticker_card.area.cards then
          for _, card in pairs(G.sticker_card.area.cards) do
            card.children.back = false
            card:set_ability(card.config.center, true)
          end
        end
      end
    end)
    G.NEURO.deck_chosen = true
    return "Deck changed to " .. target_name
  end
end

local function handle_change_viewed_back(data)
  if type(data.to_key) ~= "string" then
    return nil, "Back key is required. Provide a valid back key."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_viewed_back
    if fn then fn({ to_key = data.to_key, to_val = data.to_key, UIBox = mock_UIBox }) end
  end
end

local function handle_change_viewed_collab(data)
  if type(data.to_key) ~= "string" then
    return nil, "Collab key is required. Provide a valid collab key."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.change_viewed_collab
    if fn then fn({ to_key = data.to_key, to_val = data.to_key, UIBox = mock_UIBox }) end
  end
end

local function handle_change_contest_name(data)
  if type(data.text) ~= "string" then
    return nil, "Text is required. Provide the full text string."
  end
  local text = Filtered.sanitize(data.text)
  return function()
    local fn = G.FUNCS and G.FUNCS.text_input_key
    if not fn then return end
    for i = 1, #text do
      local c = text:sub(i, i)
      fn({ key = c, UIBox = mock_UIBox })
    end
    fn({ key = "return", UIBox = mock_UIBox })
  end
end

local function handle_set_joker_order(data)
  if not G.jokers or not G.jokers.cards then
    return nil, "Jokers are not available yet."
  end
  local from_idx = data.from_index
  local to_idx = data.to_index
  if not from_idx or not to_idx then
    return nil, "Both from_index and to_index are required."
  end
  if type(from_idx) ~= "number" or from_idx < 1 or from_idx > #G.jokers.cards then
    return nil, "from_index " .. tostring(from_idx) .. " out of range (you have " .. #G.jokers.cards .. " jokers). Use 1-" .. #G.jokers.cards .. "."
  end
  if type(to_idx) ~= "number" or to_idx < 1 or to_idx > #G.jokers.cards then
    return nil, "to_index " .. tostring(to_idx) .. " out of range (you have " .. #G.jokers.cards .. " jokers). Use 1-" .. #G.jokers.cards .. "."
  end
  if from_idx == to_idx then
    return nil, "from_index and to_index are the same."
  end
  return function()
    local card = G.jokers.cards[from_idx]
    local card_name = safe_name(card) or "Unknown"
    table.remove(G.jokers.cards, from_idx)
    table.insert(G.jokers.cards, to_idx, card)
    G.jokers:recalculate()
    return string.format("Moved %s from position %d to %d", card_name, from_idx, to_idx)
  end
end

local function handle_reorder_hand_cards(data)
  if not G.hand or not G.hand.cards then
    return nil, "Hand is not available yet."
  end
  local order = data.order or {}
  if #order ~= #G.hand.cards then
    return nil, "Order array length (" .. #order .. ") must match hand size (" .. #G.hand.cards .. "). Provide exactly " .. #G.hand.cards .. " indices."
  end
  local valid = true
  local bad_idx = nil
  local used = {}
  for i, idx in ipairs(order) do
    if type(idx) ~= "number" or idx < 1 or idx > #G.hand.cards then
      valid = false
      bad_idx = idx
      break
    end
    if used[idx] then
      valid = false
      bad_idx = idx
      break
    end
    used[idx] = true
  end
  if not valid then
    return nil, "Order array contains invalid or duplicate index " .. tostring(bad_idx) .. ". Use each index 1-" .. #G.hand.cards .. " exactly once."
  end
  return function()
    local reordered = {}
    for _, idx in ipairs(order) do
      reordered[#reordered + 1] = G.hand.cards[idx]
    end
    G.hand.cards = reordered
    return string.format("Reordered %d cards to new positions", #reordered)
  end
end

local function handle_simulate_hand(data)
  if not G or not G.hand or not G.hand.highlighted or #G.hand.highlighted == 0 then
    return nil, "No cards are highlighted. Highlight cards first."
  end
  if not G.FUNCS or not G.FUNCS.get_poker_hand_info then
    return nil, "Poker hand info function is not available."
  end

  local hand_info = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
  local results = {
    "=== HAND SIMULATION ===",
    "",
  }

  local target_score = 0
  if G.GAME and G.GAME.blind then
    target_score = (G.GAME.blind.chips or 0) * (G.GAME.blind.mult or 1)
    table.insert(results, string.format("Target Score: %d", target_score))
    table.insert(results, "")
  end

  if hand_info then
    table.insert(results, "Hand Type: " .. (hand_info.type or "Unknown"))

    local card_names = {}
    for _, card in ipairs(G.hand.highlighted) do
      if card.base then
        table.insert(card_names, (card.base.value or "?") .. " of " .. (card.base.suit or "?"))
      end
    end
    if #card_names > 0 then
      table.insert(results, "Cards: " .. table.concat(card_names, ", "))
    end

    table.insert(results, "Scoring Cards: " .. #G.hand.highlighted)

    if hand_info.type and G.GAME and G.GAME.hands and G.GAME.hands[hand_info.type] then
      local hand_data = G.GAME.hands[hand_info.type]
      table.insert(results, "")
      table.insert(results, "=== BASE VALUES ===")
      table.insert(results, "Level: " .. tostring(hand_data.level))
      table.insert(results, "Base Chips: " .. tostring(hand_data.chips))
      table.insert(results, "Base Mult: " .. tostring(hand_data.mult))
      table.insert(results, string.format("Base Score: %d", hand_data.chips * hand_data.mult))
    end

    if G.jokers and G.jokers.cards and #G.jokers.cards > 0 then
      table.insert(results, "")
      table.insert(results, "=== JOKER CONTRIBUTIONS ===")
      local total_chips = 0
      local total_mult = 0
      local total_xmult = 1
      local scoring_card_count = #G.hand.highlighted

      for i, card in ipairs(G.jokers.cards) do
        local ability = card.ability or {}
        local name = safe_name(card) or "Unknown"
        local contrib = {}
        local local_chips = 0
        local local_mult = 0
        local local_xmult = 1

        if ability.h_mod then
          total_chips = total_chips + (ability.h_mod or 0)
          local_chips = ability.h_mod or 0
          table.insert(contrib, "+" .. tostring(ability.h_mod) .. " chips")
        end
        if ability.h_mult then
          total_mult = total_mult + (ability.h_mult or 0)
          local_mult = ability.h_mult or 0
          table.insert(contrib, "+" .. tostring(ability.h_mult) .. " mult")
        end
        if ability.x_mult then
          total_xmult = total_xmult * (ability.x_mult or 1)
          local_xmult = ability.x_mult or 1
          table.insert(contrib, "x" .. tostring(ability.x_mult) .. " mult")
        end
        if ability.c_mult then
          local card_mult = (ability.c_mult or 0) * scoring_card_count
          total_mult = total_mult + card_mult
          table.insert(contrib, "+" .. tostring(card_mult) .. " mult (" .. tostring(ability.c_mult) .. "/card)")
        end

        if #contrib > 0 then
          table.insert(results, string.format("%d. %s: %s", i, name, table.concat(contrib, ", ")))
        end
      end

      table.insert(results, "")
      table.insert(results, "=== SCORE BREAKDOWN ===")
      local hand_data_entry = G.GAME and G.GAME.hands and hand_info.type and G.GAME.hands[hand_info.type]
      local base_chips = hand_data_entry and hand_data_entry.chips or 0
      local base_mult = hand_data_entry and hand_data_entry.mult or 0
      table.insert(results, string.format("Base Chips: %d", base_chips))
      table.insert(results, string.format("+ Joker Chips: %d", total_chips))
      table.insert(results, string.format("= Total Chips: %d", base_chips + total_chips))
      table.insert(results, "")
      table.insert(results, string.format("Base Mult: %d", base_mult))
      table.insert(results, string.format("+ Joker Mult: %d", total_mult))
      table.insert(results, string.format("= Total Mult: %d", base_mult + total_mult))
      table.insert(results, "")
      table.insert(results, string.format("XMult Multiplier: x%.2f", total_xmult))

      local final_chips = base_chips + total_chips
      local final_mult = base_mult + total_mult
      local estimated_score = math.floor(final_chips * final_mult * total_xmult)

      table.insert(results, "")
      table.insert(results, string.format("=== ESTIMATED SCORE: %d ===", estimated_score))

      if target_score > 0 then
        local diff = estimated_score - target_score
        table.insert(results, string.format("Target: %d | Difference: %+d", target_score, diff))
      end
    else
      local base_score = hand_info.type and G.GAME and G.GAME.hands[hand_info.type] and
        G.GAME.hands[hand_info.type].chips * G.GAME.hands[hand_info.type].mult or 0
      table.insert(results, "")
      table.insert(results, string.format("=== ESTIMATED SCORE: %d ===", base_score))
      if target_score > 0 then
        local diff = base_score - target_score
        table.insert(results, string.format("Target: %d | Difference: %+d", target_score, diff))
      end
    end
  end

  local result = table.concat(results, "\n")
  return function()
    return result
  end
end

local function handle_draw_from_deck(data)
  if not G or not G.deck or not G.deck.cards then
    return nil, "Deck is not available yet."
  end
  if not G or not G.hand then
    return nil, "Hand is not available yet."
  end
  local count = data.count or 1
  if count < 1 then
    return nil, "Count must be at least 1."
  end
  if #G.deck.cards < count then
    return nil, "Not enough cards in deck."
  end
  if #G.hand.cards >= G.hand.config.card_limit then
    return nil, "Hand is full."
  end
  return function()
    local to_draw = math.min(count, #G.deck.cards, G.hand.config.card_limit - #G.hand.cards)
    local drawn_cards = {}
    for i = 1, to_draw do
      if #G.deck.cards > 0 then
        local card = G.deck.cards[#G.deck.cards]
        table.remove(G.deck.cards)
        G.hand:add_card(card)
        table.insert(drawn_cards, card.base and (card.base.value .. " of " .. card.base.suit) or "Unknown card")
      end
    end
    return string.format("Drew %d card(s): %s. Hand: %d/%d, Deck: %d remaining.",
      to_draw,
      table.concat(drawn_cards, ", "),
      #G.hand.cards,
      G.hand.config.card_limit,
      #G.deck.cards
    )
  end
end

local function safe_context_result(fetch_fn, fallback)
  local ok, value = pcall(fetch_fn)
  if not ok then
    return fallback or ("Context unavailable: " .. tostring(value))
  end
  if type(value) == "table" then
    local lines = {}
    local has_array = false
    for i, v in ipairs(value) do
      has_array = true
      lines[#lines + 1] = tostring(v)
    end
    if not has_array then
      for k, v in pairs(value) do
        lines[#lines + 1] = tostring(k) .. ": " .. tostring(v)
      end
    end
    return table.concat(lines, "\n")
  end
  if value == nil then
    return fallback or "Context unavailable"
  end
  return tostring(value)
end

local function handle_scoring_explanation(data)
  if not G or not G.GAME then
    return nil, "Game not available yet."
  end
  return function()
    local Context = require("context")
    return safe_context_result(Context.get_scoring_explanation, "Scoring explanation unavailable")
  end
end

local function handle_joker_strategy(data)
  if not G or not G.jokers then
    return nil, "Jokers not available yet."
  end
  return function()
    local Context = require("context")
    return safe_context_result(Context.get_joker_strategy, "Joker strategy unavailable")
  end
end

local function handle_shop_context(data)
  if not G or not G.GAME then
    return nil, "Game not available yet."
  end
  return function()
    local Context = require("context")
    return safe_context_result(Context.get_shop_context, "Shop context unavailable")
  end
end

local function handle_blind_info(data)
  if not G or not G.GAME or not G.GAME.blind then
    return nil, "Game not available yet."
  end
  return function()
    local Context = require("context")
    return safe_context_result(Context.get_blind_info, "Blind info unavailable")
  end
end

local function handle_hand_levels_info(data)
  if not G or not G.GAME or not G.GAME.hands then
    return nil, "Game not available yet."
  end
  return function()
    local Context = require("context")
    return safe_context_result(Context.get_hand_levels_info, "Hand levels unavailable")
  end
end

local function handle_full_game_context(data)
  if not G or not G.GAME then
    return nil, "Game not available yet."
  end
  return function()
    local Context = require("context")
    return safe_context_result(Context.get_full_game_context, "Full game context unavailable")
  end
end

local function handle_quick_status(data)
  if not G or not G.GAME then
    return nil, "Game not available yet."
  end

  local status = {}

  table.insert(status, "=== QUICK STATUS ===")
  table.insert(status, "")

  if G.GAME.blind then
    local blind = G.GAME.blind
    local target = (blind.chips or 0) * (blind.mult or 1)
    table.insert(status, string.format("Blind: %s (Target: %d)", blind.name or "Unknown", target))
  end

  table.insert(status, string.format("Money: $%d", G.GAME.dollars or 0))

  if G.GAME.current_round then
    table.insert(status, string.format("Hands: %d | Discards: %d",
      G.GAME.current_round.hands_left or 0,
      G.GAME.current_round.discards_left or 0))
  end

  if G.jokers and G.jokers.cards then
    local joker_count = #G.jokers.cards
    local joker_limit = G.jokers.config and G.jokers.config.card_limit or 5
    local total_xmult = 1
    local total_mult = 0
    local total_chips = 0

    for _, card in ipairs(G.jokers.cards) do
      local ability = card.ability or {}
      if ability.x_mult then total_xmult = total_xmult * ability.x_mult end
      if ability.h_mult then total_mult = total_mult + ability.h_mult end
      if ability.h_mod then total_chips = total_chips + ability.h_mod end
    end

    table.insert(status, string.format("Jokers: %d/%d", joker_count, joker_limit))
    if total_xmult > 1 or total_mult > 0 or total_chips > 0 then
      local effects = {}
      if total_xmult > 1 then table.insert(effects, string.format("x%.1f", total_xmult)) end
      if total_mult > 0 then table.insert(effects, string.format("+%d Mult", total_mult)) end
      if total_chips > 0 then table.insert(effects, string.format("+%d Chips", total_chips)) end
      table.insert(status, "Joker Power: " .. table.concat(effects, ", "))
    end
  end

  if G.hand and #G.hand.cards > 0 then
    table.insert(status, string.format("Hand: %d cards", #G.hand.cards))
  end

  local result = table.concat(status, "\n")
  return function()
    return result
  end
end

local function handle_evaluate_play(data)
  if not G or not G.play or not G.play.cards or #G.play.cards == 0 then
    if G and G.hand and G.hand.highlighted and #G.hand.highlighted > 0 then
      local Context = require("context")
      local scoring = Context.get_scoring_explanation()
      local result = table.concat(scoring, "\n")
      return function()
        return result
      end
    end
    return nil, "No cards in play area or highlighted. Select cards first."
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.evaluate_play
    if fn then fn({ config = {} }) end
    return "Play evaluated successfully"
  end
end

local function handle_toggle_seeded_run(data)
  return function()
    if G and G.run_setup_seed == nil then
      G.run_setup_seed = false
    end
    if G then
      G.run_setup_seed = not G.run_setup_seed
    end

    local fn = G and G.FUNCS and G.FUNCS.toggle_seeded_run
    local target = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("run_setup_seed") or nil
    if fn and target and target.config and target.config.object then
      pcall(fn, { config = { object = target.config.object }, UIBox = G.OVERLAY_MENU })
    end

    return string.format("Seeded mode: %s", (G and G.run_setup_seed) and "ON" or "OFF")
  end
end

local function handle_paste_seed(data)
  local raw = data and data.seed
  if raw == nil or tostring(raw) == "" then
    if G and G.CLIPBOARD and tostring(G.CLIPBOARD) ~= "" then
      raw = tostring(G.CLIPBOARD)
    elseif love and love.system and love.system.getClipboardText then
      raw = tostring(love.system.getClipboardText() or "")
    else
      raw = ""
    end
  end

  local seed_val = tostring(raw or ""):upper():gsub("[^A-Z0-9]", ""):sub(1, 8)
  if seed_val == "" then
    return nil, "No valid seed provided. Provide seed parameter or clipboard value."
  end

  return function()
    if G then
      G.run_setup_seed = true
      G.setup_seed = seed_val
      G.NEURO.seed_pasted = seed_val
      G.CLIPBOARD = seed_val
    end
    if love and love.system and love.system.setClipboardText then
      pcall(function() love.system.setClipboardText(seed_val) end)
    end

    local fn = G and G.FUNCS and G.FUNCS.paste_seed
    if fn and G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID then
      pcall(fn, { UIBox = G.OVERLAY_MENU, config = {} })
    end

    return "Seed set to: " .. seed_val
  end
end

local function handle_start_challenge_run(data)
  local challenge_id = G and G.challenge_tab or nil
  if not (challenge_id and G and G.CHALLENGES and G.CHALLENGES[challenge_id]) then
    return nil, "No challenge selected. Choose challenge first, then start_challenge_run."
  end

  return function()
    local fn = G and G.FUNCS and G.FUNCS.start_challenge_run
    if fn then
      fn({ config = { id = challenge_id }, UIBox = mock_UIBox })
    else
      local fallback = G and G.FUNCS and G.FUNCS.start_run
      if fallback then
        fallback(nil, { stake = 1, challenge = G.CHALLENGES[challenge_id] })
      end
    end
    return "Starting challenge run: " .. tostring(challenge_id)
  end
end

local function handle_skip_blind(data)
  if not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states) then
    return nil, "Blind selection is not ready yet."
  end

  local on_deck = G.GAME.blind_on_deck
  if on_deck ~= "Small" and on_deck ~= "Big" then
    local bs = G.GAME.round_resets.blind_states
    if bs.Small == "Select" then on_deck = "Small"
    elseif bs.Big == "Select" then on_deck = "Big"
    elseif bs.Boss == "Select" then on_deck = "Boss"
    end
  end

  if on_deck == "Boss" then
    return nil, "Skipping boss blind is not supported. Select the boss blind instead."
  end
  if on_deck ~= "Small" and on_deck ~= "Big" then
    return nil, "No skippable blind is currently selectable."
  end

  local opt = G.blind_select_opts and G.blind_select_opts[string.lower(on_deck)]
  if not (opt and type(opt.get_UIE_by_ID) == "function") then
    return nil, "Blind UI option is unavailable; cannot skip right now."
  end

  local tag = opt:get_UIE_by_ID("tag_container")
  if not (tag and tag.config and tag.config.ref_table) then
    return nil, "Skip reward tag is unavailable; cannot skip right now."
  end

  return function()
    local before = G.GAME and G.GAME.blind_on_deck or on_deck
    local fn = G.FUNCS and G.FUNCS.skip_blind
    if fn then fn({ UIBox = opt, config = {} }) end
    local after = G.GAME and G.GAME.blind_on_deck or before
    return string.format("Skipped %s blind. Next selectable: %s", tostring(before), tostring(after))
  end
end

local PARAM_VALIDATORS = {
  choose_persona = function(data)
    local persona = data.persona
    if persona ~= "neuro" and persona ~= "evil" then
      return nil, "Choose 'neuro' for Neuro-sama or 'evil' for Evil Neuro."
    end
    return function()
      if G then
        local display_name = persona == "evil" and "Evil Neuro" or "Neuro-sama"
        G.NEURO.persona = persona
        G.NEURO.login_anim = {
          start = (G.TIMERS and G.TIMERS.REAL) or love.timer.getTime(),
          name = display_name,
          palette_ready = false,
        }
      end
      local name = persona == "evil" and "Evil Neuro" or "Neuro-sama"
      return "Identity set: " .. name .. "! Let's play!"
    end
  end,
  set_hand_highlight = handle_set_hand_highlight,
  clear_hand_highlight = handle_clear_hand_highlight,
  use_card = handle_use_card,
  buy_from_shop = handle_buy_from_shop,
  sell_card = handle_sell_card,
  card_click = handle_card_click,
  highlight_card = handle_highlight_card,
  unhighlight_all = handle_unhighlight_all,
  play_cards_from_highlighted = handle_play_cards_from_highlighted,
  discard_cards_from_highlighted = handle_discard_cards_from_highlighted,
  select_blind = handle_select_blind,
  skip_blind = handle_skip_blind,
  set_joker_order = handle_set_joker_order,
  reorder_hand_cards = handle_reorder_hand_cards,
  simulate_hand = handle_simulate_hand,
  draw_from_deck = handle_draw_from_deck,
  scoring_explanation = handle_scoring_explanation,
  joker_strategy = handle_joker_strategy,
  shop_context = handle_shop_context,
  blind_info = handle_blind_info,
  hand_levels_info = handle_hand_levels_info,
  full_game_context = handle_full_game_context,
  quick_status = handle_quick_status,
  consumables_info = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_consumables_info or function() return {"Consumables info not available"} end, "Consumables info not available")
    end
  end,
  hand_details = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_hand_details or function() return {"Hand details not available"} end, "Hand details not available")
    end
  end,
  deck_composition = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_deck_composition or function() return {"Deck composition not available"} end, "Deck composition not available")
    end
  end,
  owned_vouchers = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_owned_vouchers or function() return {"Vouchers info not available"} end, "Vouchers info not available")
    end
  end,
  round_history = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_round_history or function() return {"Round history not available"} end, "Round history not available")
    end
  end,
  neuratro_info = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_neuratro_info or function() return {"Neuratro info not available"} end, "Neuratro info not available")
    end
  end,
  help = function(data)
    local help_text = {
      "=== AVAILABLE COMMANDS ===",
      "",
      "=== CARD ACTIONS ===",
      "set_hand_highlight - Select cards by index",
      "clear_hand_highlight - Clear selection",
      "play_cards_from_highlighted - Play selected cards",
      "discard_cards_from_highlighted - Discard selected cards",
      "reorder_hand_cards - Reorder hand",
      "simulate_hand - Preview score for selection",
      "",
      "=== INFO COMMANDS ===",
      "scoring_explanation - How scoring works",
      "joker_strategy - Your jokers and effects",
      "blind_info - Current blind target and resources",
      "hand_levels_info - All hand types and levels",
      "shop_context - Shop items and prices",
      "consumables_info - Tarot/Planet/Spectral cards",
      "hand_details - Cards in hand with enhancements",
      "deck_composition - Deck analysis by suit/type",
      "owned_vouchers - Active vouchers",
      "round_history - This round's progress",
      "neuratro_info - Neuratro mod content",
      "quick_status - Fast summary",
      "full_game_context - Complete game state",
      "",
      "=== SHOP ACTIONS ===",
      "buy_from_shop - Purchase item",
      "sell_card - Sell joker/consumable",
      "reroll_shop - Refresh shop",
      "",
      "=== BLIND ACTIONS ===",
      "select_blind - Choose small/big/boss",
      "skip_blind - Skip for tag",
    }
    return function()
      return table.concat(help_text, "\n")
    end
  end,
  text_input_key = function(data)
    local key = data.key
    if type(key) ~= "string" then
      return nil, "Key is required. Provide a single key string."
    end
    return function()
      local fn = G.FUNCS and G.FUNCS.text_input_key
      if fn then fn({ key = key, UIBox = mock_UIBox }) end
    end
  end,
  setup_run = function(data)
    return function()
      G.NEURO.deck_chosen = false  -- reset for fresh overlay session
      local fn = G.FUNCS and G.FUNCS.setup_run
      if fn then
        -- Patch can_continue to false so Balatro always opens the 'New Run'
        -- tab, never the 'Continue' tab (which would load the save instead).
        local orig = G.FUNCS.can_continue
        G.FUNCS.can_continue = function() return false end
        fn({ config = {}, UIBox = mock_UIBox })
        G.FUNCS.can_continue = orig
      end
      -- Belt-and-suspenders: ensure current_setup is 'New Run'.
      if G and G.SETTINGS then G.SETTINGS.current_setup = 'New Run' end
      return "Opened run setup screen"
    end
  end,
  change_stake = handle_change_stake,
  change_challenge_list_page = handle_change_challenge_list_page,
  change_challenge_description = handle_change_challenge_description,
  change_selected_back = handle_change_selected_back,
  change_viewed_back = handle_change_viewed_back,
  change_viewed_collab = handle_change_viewed_collab,
  change_contest_name = handle_change_contest_name,
  toggle_seeded_run = handle_toggle_seeded_run,
  paste_seed = handle_paste_seed,
  start_challenge_run = handle_start_challenge_run,
  evaluate_play = handle_evaluate_play,
  get_poker_hand_information = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_poker_hand_info or function() return {"Poker hand info not available"} end, "Poker hand info not available")
    end
  end,
  joker_info = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_joker_info or function() return {"Joker info not available"} end, "Joker info not available")
    end
  end,
  card_modifiers_information = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_card_modifiers or function() return {"Card modifiers info not available"} end, "Card modifiers info not available")
    end
  end,
  deck_type = function(data)
    return function()
      local Context = require("context")
      return safe_context_result(Context.get_deck_types or function() return {"Deck type info not available"} end, "Deck type info not available")
    end
  end,
}

local function is_run_setup_overlay()
  return G and G.OVERLAY_MENU
    and type(G.OVERLAY_MENU.get_UIE_by_ID) == "function"
    and G.OVERLAY_MENU:get_UIE_by_ID("run_setup_seed") ~= nil
end

local function handle_simple_action(name, data)

local State = require("state")
local current_state = State.get_state_name and State.get_state_name() or (G and G.NEURO.state) or "UNKNOWN"

if name == "start_setup_run" then
  if not is_run_setup_overlay() then
    return nil, "start_setup_run requires the run setup screen to be open. Use setup_run first."
  end
  -- Ensure we start a New Run, never Continue (current_setup may drift)
  if G.SETTINGS then G.SETTINGS.current_setup = 'New Run' end
end

if name == "skip_blind" or name == "reroll_boss" then
  if not (G and G.blind_select) then
    return nil, "Blind select is not open. Wait for the blind select screen."
  end
end
if name == "skip_booster" then
  local bp = G and (G.pack_cards or G.booster_pack)
  if not bp then
    return nil, "No booster pack is open. Wait for a pack screen."
  end
end
if name == "end_consumeable" then
  local bp = G and (G.pack_cards or G.booster_pack)
  if not (bp and bp.cards) then
    return nil, "No booster pack is open. Wait for a pack screen."
  end
  if G.GAME and G.GAME.current_round and G.GAME.current_round.consumeables_remaining ~= nil then
    local remaining = G.GAME.current_round.consumeables_remaining
    if remaining <= 0 then
      return nil, "No consumeables remaining. Use skip_booster instead."
    end
  end
end
if name == "reroll_shop" or name == "toggle_shop" then
  if not (G and G.shop) then
    return nil, "Shop is not open. Wait for the shop screen."
  end
end
if name == "exit_overlay_menu" then
  if not (G and G.OVERLAY_MENU) then
    return nil, "No overlay popup is open right now."
  end
  return function()
    -- Use continue_unlock for unlock/deck reveal overlays — it also advances
    -- the unlock event queue so subsequent unlocks appear correctly.
    if G.FUNCS and type(G.FUNCS.continue_unlock) == "function"
        and G.OVERLAY_MENU and G.OVERLAY_MENU.joker_unlock_table then
      G.FUNCS.continue_unlock()
      return "Closed unlock popup"
    end
    if G.FUNCS and type(G.FUNCS.exit_overlay_menu) == "function" then
      G.FUNCS.exit_overlay_menu()
      return "Closed overlay popup/menu"
    end
    if G.CONTROLLER and type(G.CONTROLLER.key_press) == "function" then
      pcall(function() G.CONTROLLER:key_press("escape") end)
      pcall(function() G.CONTROLLER:key_press("return") end)
      return "Tried to close overlay popup/menu"
    end
    return "Overlay close function unavailable"
  end
end
if name == "reroll_shop" then
  local dollars = (G and G.GAME and G.GAME.dollars) or 0
  local bankrupt_at = (G and G.GAME and G.GAME.bankrupt_at) or 0
  local money = (tonumber(dollars) or 0) - (tonumber(bankrupt_at) or 0)
  local cost = (G and G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost) or 0
  if type(cost) ~= "number" or cost < 0 then
    return nil, "Shop reroll is not available right now."
  end
  if money < cost then
    return nil, string.format("Cannot reroll shop: need $%d, have $%d.", cost, money)
  end
end
  if name == "cash_out" then
    if not (G and G.round_eval) then
      return nil, "Cash out is not available right now."
    end
  end
  if name == "paste_seed" and data and data.seed then
    local seed_val = tostring(data.seed):upper():sub(1, 8)
    if love and love.system and love.system.setClipboardText then
      love.system.setClipboardText(seed_val)
    end
    G.CLIPBOARD = seed_val
    G.NEURO.seed_pasted = seed_val
  end

  local fn = G.FUNCS and G.FUNCS[name]
  if not fn then
    return nil, "This action is not available here. Choose a different action for this screen."
  end
  if data and data.args then
    return function()
      fn(data.args)
    end
  end
  local config = data and data.config or {}
  resolve_ref_table(data, config)
  return function()
    fn({ config = config, UIBox = mock_UIBox })
  end
end

function Dispatcher.handle_message(msg, bridge)
  if not msg or not msg.command then
    return
  end
  if not session_matches(bridge, msg) then
    return
  end
  if msg.command == "actions/reregister_all" then
    local now = os.clock()
    if _last_reregister_at and (now - _last_reregister_at) < 2.0 then
      return
    end
    _last_reregister_at = now
    tx_clear()
    if bridge then
      local State = require("state")
      local state_name = State.get_state_name()
      local valid_action_names = Actions.get_valid_actions_for_state(state_name)

      local all_actions = Actions.get_static_actions()
      local filtered_actions = {}
      local valid_set = {}
      for _, name in ipairs(valid_action_names) do
        valid_set[name] = true
      end

      for _, action_def in ipairs(all_actions) do
        if valid_set[action_def.name] then
          table.insert(filtered_actions, action_def)
        end
      end

      bridge:register_actions(filtered_actions)
    end
    return
  end
  if msg.command ~= "action" or not msg.data then
    return
  end
  local id = msg.data.id
  local name = msg.data.name

  local prior = tx_get(id)
  if prior then
    if bridge then
      bridge:send_action_result(id, prior.ok, prior.message)
    end
    return
  end

  if G then
    G.NEURO.action_phase = "validating"
    G.NEURO.action_phase_at = (G.TIMERS and G.TIMERS.REAL) or (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
  end

  local ok_guard_call, ok_guard, guard_err = pcall(Enforce.pre_action, bridge, name)
  if not ok_guard_call then
    send_result(bridge, id, false, "Action guard failed: " .. tostring(ok_guard), name)
    return
  end
  if not ok_guard then
    send_result(bridge, id, false, guard_err, name)
    return
  end
  local payload = msg.data.data
  local data = {}
  if payload and payload ~= "" then
    local ok, decoded = pcall(json.decode, payload)
    if not ok then
      send_result(bridge, id, false, "Your action payload is invalid JSON. Fix the JSON and try again.", name)
      Enforce.on_error(bridge)
      return
    end
    if type(decoded) ~= "table" then
      send_result(bridge, id, false, "Your action payload must be a JSON object.", name)
      Enforce.on_error(bridge)
      return
    end
    if not is_object_table(decoded) then
      send_result(bridge, id, false, "Your action payload must be a JSON object (not an array).", name)
      Enforce.on_error(bridge)
      return
    end
    data = decoded or {}
  end
  local schema = ACTION_SCHEMAS[name]
  local ok_schema, schema_err = validate_value(schema, data, "parameters")
  if not ok_schema then
    send_result(bridge, id, false, "Invalid action parameters: " .. schema_err, name)
    Enforce.post_action(bridge, false)
    return
  end
  local validator = PARAM_VALIDATORS[name]
  local exec, err
  if validator then
    local ok_validator, v_exec, v_err = pcall(validator, data)
    if not ok_validator then
      exec, err = nil, "Action validation failed: " .. tostring(v_exec)
    else
      exec, err = v_exec, v_err
    end
  elseif G.FUNCS and G.FUNCS[name] then
    exec, err = handle_simple_action(name, data)
  else
    exec, err = nil, "This action is not available here. Choose a different action for this screen."
  end
  if not exec then
    send_result(bridge, id, false, err or "This action is not available here. Choose a different action for this screen.", name)
    Enforce.post_action(bridge, false)
    return
  end

  -- Unblock Neuro immediately after validation, before execution (per spec)
  send_result(bridge, id, true, nil, name)

  if G then
    G.NEURO.action_phase = "executing"
    G.NEURO.action_phase_at = (G.TIMERS and G.TIMERS.REAL) or (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
  end
  local exec_ok, exec_result = xpcall(exec, function(err)
    return tostring(err)
  end)
  if not exec_ok then
    -- can't send a second result; log and move on (exec crash, not a param error)
    Enforce.post_action(bridge, false)
    return
  end
  -- Send execution feedback as silent context so Neuro sees it without blocking
  if type(exec_result) == "string" and bridge then
    bridge:send_context(exec_result, true)
  end
  Enforce.post_action(bridge, true)
  G.NEURO.last_action_name = name
  if name == "exit_overlay_menu" then
    G.NEURO.last_force_fingerprint = nil
  end
  local current_state = G.NEURO.state or ""
  if current_state == "SHOP" then
    if name == "reroll_shop" then
      G.NEURO.shop_reroll_count = (G.NEURO.shop_reroll_count or 0) + 1
    elseif name == "toggle_shop" then
      G.NEURO.shop_reroll_count = nil
    end
  end
  if current_state == "BLIND_SELECT" and name == "blind_info" then
    G.NEURO.blind_info_seen = true
  elseif current_state ~= "BLIND_SELECT" then
    G.NEURO.blind_info_seen = nil
    G.NEURO.blind_info_sig = nil
  end
  G.NEURO.force_dirty = true
  if G.TIMERS and G.TIMERS.REAL then
    G.NEURO.force_dirty_at = G.TIMERS.REAL
  elseif love and love.timer then
    G.NEURO.force_dirty_at = love.timer.getTime()
  else
    G.NEURO.force_dirty_at = os.clock()
  end
  local setup_states = { MENU = true, RUN_SETUP = true, SPLASH = true }
  if setup_states[current_state] then
    G.NEURO.reforce_count = (G.NEURO.reforce_count or 0) + 1
    if G.NEURO.reforce_count <= 5 then
      G.NEURO.force_inflight = false
      G.NEURO.force_state = nil
      G.NEURO.force_action_names = nil
      G.NEURO.force_action_set = nil
      G.NEURO.force_sent_at = nil
    end
  else
    G.NEURO.reforce_count = 0
  end
  if G.TIMERS and G.TIMERS.REAL then
    G.NEURO.last_action_at = G.TIMERS.REAL
  elseif love and love.timer then
    G.NEURO.last_action_at = love.timer.getTime()
  else
    G.NEURO.last_action_at = os.clock()
  end
end

-- Resolve a human-readable name for a Back center object.
-- Tries: localize() → loc_txt.name → .name → .key
local function get_back_display_name(b)
  -- 1. Canonical Balatro localization
  if b.key and localize then
    local ok, loc = pcall(localize, {type = 'name_text', set = 'Back', key = b.key})
    if ok and type(loc) == "string" and loc ~= "" and loc ~= "ERROR" then
      return loc
    end
  end
  -- 2. SMODS loc_txt
  if b.loc_txt and type(b.loc_txt) == "table" and b.loc_txt.name and b.loc_txt.name ~= "" then
    return tostring(b.loc_txt.name)
  end
  -- 3. Direct name field (may be internal key for modded decks)
  if b.name and b.name ~= "" and b.name ~= b.key then
    return tostring(b.name)
  end
  -- 4. Fallback: humanize the key (b_glorpdeck → Glorpdeck)
  if b.key then
    local humanized = b.key:gsub("^b_", ""):gsub("_", " ")
    return humanized:sub(1,1):upper() .. humanized:sub(2)
  end
  return "Unknown Deck"
end

-- Short description of a deck's effect from its config table.
local function get_deck_short_desc(b)
  local c = b.config or {}
  local parts = {}
  if c.discards and c.discards ~= 0 then parts[#parts+1] = string.format("%+d discard", c.discards) end
  if c.hands and c.hands ~= 0 then parts[#parts+1] = string.format("%+d hand", c.hands) end
  if c.dollars and c.dollars ~= 0 then parts[#parts+1] = string.format("+$%d start", c.dollars) end
  if c.joker_slot and c.joker_slot ~= 0 then parts[#parts+1] = string.format("%+d joker slot", c.joker_slot) end
  if c.hand_size and c.hand_size ~= 0 then parts[#parts+1] = string.format("%+d hand size", c.hand_size) end
  if c.consumable_slot and c.consumable_slot ~= 0 then parts[#parts+1] = string.format("%+d consumable slot", c.consumable_slot) end
  if c.ante_scaling then parts[#parts+1] = "balanced chips/mult" end
  if c.remove_faces then parts[#parts+1] = "no face cards" end
  if c.randomize_rank_suit then parts[#parts+1] = "random ranks+suits" end
  if c.no_interest then parts[#parts+1] = "no interest" end
  if c.voucher then parts[#parts+1] = "starts with voucher" end
  if c.consumables then parts[#parts+1] = "starts with consumables" end
  if c.vouchers then parts[#parts+1] = "starts with vouchers" end
  if c.spectral_rate then parts[#parts+1] = "spectral cards in shop" end
  -- Modded decks: try loc_txt description
  if #parts == 0 and b.loc_txt and type(b.loc_txt) == "table" then
    local desc = b.loc_txt.description or b.loc_txt.text
    if type(desc) == "table" then
      for _, line in ipairs(desc) do
        local clean = tostring(line):gsub("{.-}", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
        if clean and clean ~= "" then parts[#parts+1] = clean end
      end
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

local function build_game_rules_text()
  local interest_amount = (G and G.GAME and G.GAME.interest_amount) or 1
  local interest_cap = (G and G.GAME and G.GAME.interest_cap) or 25
  local no_interest = G and G.GAME and G.GAME.modifiers and G.GAME.modifiers.no_interest
  local economy_line = string.format(
    "Economy: every $5 held gives +$%d interest up to cap $%d%s.",
    interest_amount,
    interest_cap,
    no_interest and " (disabled this run)" or "")

  -- Current deck info
  local deck_info = ""
  local back = G and G.GAME and (G.GAME.back or G.GAME.selected_back)
  if back then
    local center = back.effect and back.effect.center
    local deck_name = center and get_back_display_name(center) or back.name or "Unknown"
    local ok, desc = pcall(function() return center and get_deck_short_desc(center) end)
    if not ok then desc = nil end
    if desc then
      deck_info = string.format("Your deck: %s (%s). ", deck_name, desc)
    else
      deck_info = string.format("Your deck: %s. ", deck_name)
    end
  end

  return "You are an expert Balatro AI. Maximize EV every decision: chips x mult, joker synergies, discard-to-redraw value. "
      .. deck_info
      .. "RULES: Score = Chips x Mult (xMult multiplies total). "
      .. "Clear blind target before hands reach 0. "
      .. "Discards redraw selected cards. "
      .. "Boss debuffs can invalidate card groups or hand shapes; always respect active debuff rules. "
      .. "General play: preserve strong anchors (high pairs/trips and clear 4-card draws), discard low isolated cards first, and avoid low-value commits when redraw EV is higher. "
      .. economy_line .. " "
      .. "Blinds: Small/Big/Boss (Boss has debuff).\n\n"
end

local RULE_QUERY_STATES = {
  SELECTING_HAND = true,
  SHOP = true,
  BLIND_SELECT = true,
  TAROT_PACK = true,
  PLANET_PACK = true,
  SPECTRAL_PACK = true,
  STANDARD_PACK = true,
  BUFFOON_PACK = true,
  SMODS_BOOSTER_OPENED = true,
  ROUND_EVAL = true,
}

local function get_game_rules(state_name)
  if not RULE_QUERY_STATES[state_name] and not (state_name and state_name:find("_PACK$")) then
    return ""
  end
  if G and G.NEURO.rules_sent then
    return ""
  end
  if G then
    G.NEURO.rules_sent = true
  end
  return build_game_rules_text()
end

local function hiyori_persona_gate()
  if G and G.NEURO.persona == "hiyori" then
    return {
      query = "Identity not selected. Use choose_persona with persona='neuro' for Neuro-sama or 'evil' for Evil Neuro.",
      actions = { "choose_persona" }
    }
  end
  return nil
end

local function count_unlocked_decks()
  local count = 0
  if G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back then
    for _, b in ipairs(G.P_CENTER_POOLS.Back) do
      if b.unlocked ~= false then count = count + 1 end
    end
  end
  return count
end

-- Returns an inline string listing every unlocked deck as "key=Name (effect)" so Neuro
-- can pass the key directly to change_selected_back and understand what each deck does.
local function list_unlocked_decks()
  if not (G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) then return "" end
  local parts = {}
  local current_key = G.GAME and G.GAME.selected_back and G.GAME.selected_back.key
  for _, b in ipairs(G.P_CENTER_POOLS.Back) do
    if b.unlocked ~= false and b.key then
      local name = get_back_display_name(b)
      local ok, desc = pcall(get_deck_short_desc, b)
      if not ok then desc = nil end
      local entry = b.key .. "=" .. tostring(name)
      if desc then entry = entry .. " (" .. desc .. ")" end
      if b.key == current_key then entry = entry .. " [current]" end
      parts[#parts + 1] = entry
    end
  end
  return table.concat(parts, ", ")
end

-- is_run_setup_overlay moved earlier (before handle_simple_action) to avoid forward-ref error

local function seed_info_query()
  local query = ""
  local seed = G and G.GAME and G.GAME.pseudorandom and G.GAME.pseudorandom.seed
  local seeded = G and G.GAME and G.GAME.seeded
  local seed_pasted = G.NEURO.seed_pasted
  if seed then query = query .. string.format("Current seed: %s. ", seed) end
  if seeded then query = query .. "Seeded run: ON. " end
  return query, seeded, seed_pasted
end

local function menu_action_tree_query(seeded, seed_pasted)
  local parts = {
    "Action tree:",
    "MENU -> setup_run (opens run setup screen to choose deck, stake, seed).",
    "MENU -> start_challenge_run (challenge run path).",
    "MENU -> change_stake (adjust stake).",
  }
  parts[#parts + 1] = "Contest name path: confirm_contest_name confirms current text input."
  return table.concat(parts, " ")
end

local function run_setup_action_tree_query(seeded, seed_pasted)
  local parts = {
    "Action tree:",
    "RUN_SETUP -> change_selected_back/change_stake/toggle_seeded_run/paste_seed/change_contest_name (optional setup edits).",
    "RUN_SETUP -> start_setup_run (begin normal run with current setup).",
    "RUN_SETUP -> start_challenge_run (challenge run path).",
    "RUN_SETUP -> confirm_contest_name (confirm contest name input).",
  }

  if seeded and not seed_pasted then
    parts[#parts + 1] = "Seeded mode is ON with no pasted seed yet; paste_seed is available before start_setup_run."
  end

  return table.concat(parts, " ")
end

local function blind_select_signature()
  if not (G and G.GAME and G.GAME.round_resets) then return "none" end
  local rr = G.GAME.round_resets or {}
  local bs = rr.blind_states or {}
  local bc = rr.blind_choices or {}
  local on_deck = G.GAME.blind_on_deck or "-"
  local ante = rr.ante or "?"
  return table.concat({
    tostring(ante),
    tostring(on_deck),
    tostring(bs.Small or "-"),
    tostring(bs.Big or "-"),
    tostring(bs.Boss or "-"),
    tostring(bc.Small or "-"),
    tostring(bc.Big or "-"),
    tostring(bc.Boss or "-"),
  }, "|")
end

local FORCE_HANDLERS = {}

local DECK_INFO = {
  ["Red Deck"]       = "+1 discard per round. Use extra discards aggressively to fish for better hands. Discard weak cards early, chase straights and flushes more freely. Priority: Pairs/Trips > Flush > Straight. ",
  ["Blue Deck"]      = "+1 hand per round. Extra hand lets you play one exploratory or low-value hand safely. Use the spare hand to test combos or clear weak cards, save strong hands for scoring. ",
  ["Yellow Deck"]    = "Started with +$10. Buy a strong joker or booster on round 1. Standard 52-card pool, no composition changes. Play normally but leverage early economy lead. ",
  ["Green Deck"]     = "+$1 per hand played, +$1 per discard used, no interest. Use ALL hands and ALL discards every round for max income. Even weak plays and throwaway discards earn money. Never save discards. ",
  ["Black Deck"]     = "+1 joker slot (6 total), -1 hand per round. Every play must count with fewer hands. Always pick your strongest hand, never explore. Extra joker slot means prioritize buying jokers in shop. ",
  ["Magic Deck"]     = "Crystal Ball voucher active (+1 consumable slot). Started with 2 Fool tarots (copy last tarot used). Use tarots aggressively since you have extra slot. Buy and use consumables more freely than normal. ",
  ["Nebula Deck"]    = "Telescope voucher active (levels up most played hand on blind defeat), +1 consumable slot, -1 hand per round. Fewer hands so every play matters. Focus on one hand type to maximize Telescope leveling. ",
  ["Ghost Deck"]     = "Spectral cards may appear in shop and from packs. Started with Hex spectral (add Polychrome to a random joker). Spectral cards are powerful but risky. Buy spectral packs when available. ",
  ["Zodiac Deck"]    = "Tarot Merchant, Planet Merchant, and Overstock vouchers all active. Shop has extra consumable slots and better consumable rates. Buy planets to level your best hand type, buy tarots to enhance key cards. ",
  ["Plasma Deck"]    = "Chips and mult are averaged together: score = ((chips+mult)/2)^2. Balanced hands outscore lopsided ones. A high-chip pair can beat low-chip trips. Avoid hands with extreme chip/mult imbalance. ",
  ["Erratic Deck"]   = "All ranks and suits were randomized at start. Unusual distributions everywhere. Check your actual hand for unexpected pairs, flushes, or combos. Do not assume standard distributions. ",
  ["Abandoned Deck"] = "No face cards (J/Q/K) in deck. 40 cards, 10 per suit. Flushes are more concentrated (fewer cards = higher flush chance). Straights only span A-5 through 6-10. Priority: Pairs/Trips > Flush > Straight. ",
  ["Painted Deck"]   = "+2 hand size (see 10 cards), -1 joker slot. You see more cards so flushes and straights appear naturally. Pick the strongest 5-card combo from your 10. Fewer joker slots means each joker must be high impact. ",
  ["Checkered Deck"] = "Only Spades and Hearts, 2 copies of each rank (52 cards). ~50%% flush chance per hand. Priority: Flush >>> Pairs > Full House. Always check for flush first. Two-pair and full house also more common with duplicate ranks. ",
  ["Anaglyph Deck"]  = "Earn a Double Tag after every Boss Blind (gives copy of next tag). Standard 52-card pool. Play normally but always defeat Boss Blinds for double tag value. Skip small/big blinds only if tags are worth doubling. ",
  ["Twin deck"]      = "8 Kings in 48 cards (16.7%%). King pairs/trips near-guaranteed. Priority: King Pairs/Trips first. Start: 2 'The Twins' tarots. Use them ASAP on your best Kings to add Twin enhancement (+15 chips +2 mult each). ",
  ["Invader deck"]   = "6 random Gleeb (Glorpsuit) cards added each blind. Gleeb cards give 10x base chips when scored but BREAK at end of round. Play them NOW, they vanish anyway. Deck grows each round so specific draws get harder. Envious Joker (+6 mult per Gleeb scored) is a must-buy. Mix hands (5 different suits) possible with Gleeb as 5th suit. ",
  ["Euchre deck"]    = "Only 9-K and Aces, 28 cards total, 8 Jacks (4 wild). Hand size 5, 7 cards per suit. Flush chance ~18%%. Wild Jacks count as any suit for flushes. Priority: Jack Pairs/Trips > Flush > Straight (only 9-K or 10-A runs). ",
}

local function deck_strategy_info()
  local back = G and G.GAME and (G.GAME.back or G.GAME.selected_back)
  if not back then return "" end
  local center = back.effect and back.effect.center
  local name = center and get_back_display_name(center) or back.name or ""
  return DECK_INFO[name] or ""
end

FORCE_HANDLERS["SELECTING_HAND"] = function(rules)
  local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local disc = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
  local current_score = G.GAME and G.GAME.chips or 0
  local target = 0
  if G.GAME and G.GAME.blind then
    target = (G.GAME.blind.chips or 0) * (G.GAME.blind.mult or 1)
  end
  local remaining = math.max(0, target - current_score)

  local mode = "NORMAL"
  local hunt_cutoff = (target > 0) and math.max(160, math.floor(target * 0.55)) or 200
  if hands_left <= 0 then
    mode = "DESPERATE"
  elseif hands_left <= 1 and disc > 0 and remaining > 0 then
    mode = "CLUTCH"
  elseif disc > 0 and hands_left > 1 and remaining > hunt_cutoff then
    mode = "HUNT"
  end

  local mode_hint = "NORMAL: standard play. "
  if mode == "DESPERATE" then
    mode_hint = "DESPERATE: no hands left, blind is lost. Use remaining discards to cycle cards for future rounds, or take no action. Do NOT play cards. "
  elseif mode == "CLUTCH" then
    mode_hint = "CLUTCH: last hand remaining, high stakes. "
  elseif mode == "HUNT" then
    mode_hint = "HUNT: large gap to target, hand may not be strong enough. "
  end

  local structure = hand_structure_summary()
  local debuff_summary = active_blind_debuff_summary()
  local blind_hint = blind_strategy_hint()
  local bp_chain = blueprint_chain_hint()
  local token_legend = once_per_state_entry_hint(
    "selecting_tokens",
    "Tokens: WIN=remaining/best/clear; SIM1/SIM2=lines(idx~hand~score); SIMD=discard bias(Y-WEAK/N-OK); Q=quality(WIN/GOOD/WEAK/POOR); DR=discard/keep anchors; BD=debuff; +DB=debuffed card. "
  )
  local recent = recent_actions_summary(4)

  local dr = G and G.NEURO.dr_top
  local dr_discard_str = dr and #dr.discard > 0 and table.concat(dr.discard, ",") or nil
  local dr_keep_str = dr and #dr.keep > 0 and table.concat(dr.keep, ",") or nil

  local sim1 = G and G.NEURO.sim1_play
  local sim1_str = sim1 and #sim1.indices > 0 and table.concat(sim1.indices, ",") or nil
  local sim1_hand = sim1 and sim1.hand_type or nil

  local strategy_hint = once_per_state_entry_hint(
    "selecting_strategy",
    'Ex: set_hand_highlight|{"indices":[1,3,5],"action":"play"}. '
    .. 'Ex: set_hand_highlight|{"indices":[2,4,7],"action":"discard"}. '
  )

  local debuff_info = ""
  if debuff_summary ~= "" then
    debuff_info = debuff_summary .. "Cards marked +DB are debuffed by the boss blind and score 0 chips. Non-debuffed cards score normally. "
  end

  local deck_strategy = once_per_state_entry_hint("deck_strategy", deck_strategy_info())

  local consumable_hint = ""
  local has_usable_consumable = false
  if G.consumeables and G.consumeables.cards then
    local deck_name = ""
    local back = G.GAME and (G.GAME.back or G.GAME.selected_back)
    local center = back and back.effect and back.effect.center
    if center then deck_name = get_back_display_name(center) or "" end

    for i, c in ipairs(G.consumeables.cards) do
      local nm = c and c.ability and c.ability.name or ""
      local mh = c and c.ability and c.ability.consumeable and c.ability.consumeable.max_highlighted
      if mh then
        local highlighted_count = G.hand and G.hand.highlighted and #G.hand.highlighted or 0
        local min_h = c.ability.consumeable.min_highlighted or 1
        local target_advice = tarot_target_advice(nm, deck_name)
        consumable_hint = consumable_hint .. string.format(
          "CONSUMABLE slot %d: '%s' (select %d-%d hand cards). %sUSE NOW: use_card|{\"area\":\"consumeables\",\"index\":%d,\"hand_indices\":[i,j]} where i,j are 1-indexed hand card positions. ",
          i, nm, min_h, mh, target_advice, i
        )
        has_usable_consumable = true
      elseif c and c.ability and c.ability.consumeable and c.ability.consumeable.hand_type then
        consumable_hint = consumable_hint .. string.format(
          "Consumable slot %d: '%s' (planet card, levels up a hand type). Use: use_card|{\"area\":\"consumeables\",\"index\":%d}. ",
          i, nm, i
        )
        has_usable_consumable = true
      elseif nm == "The Fool" or nm == "Temperance" or nm == "The Hermit"
          or nm == "The High Priestess" or nm == "The Emperor"
          or nm == "The Wheel of Fortune" or nm == "Judgement"
          or nm == "Wraith" or nm == "Sigil" or nm == "Ouija"
          or nm == "Ectoplasm" or nm == "Immolate" or nm == "Ankh" or nm == "Hex" then
        local direct_hints = {
          ["The Fool"]             = "Copies the last tarot/planet used. No card selection needed. ",
          ["Temperance"]           = "Gives money = total sell value of all jokers. No card selection needed. ",
          ["The Hermit"]           = "Doubles your current money (up to $20). No card selection needed. ",
          ["The High Priestess"]   = "Adds 2 random planet cards to hand. No card selection needed. ",
          ["The Emperor"]          = "Adds 2 random tarot cards to hand. No card selection needed. ",
          ["The Wheel of Fortune"] = "1-in-4 chance to add foil/holo/polychrome to random joker. No card selection needed. ",
          ["Judgement"]            = "Creates a random joker. No card selection needed (requires free joker slot). ",
          ["Wraith"]               = "Creates a random Rare joker but sets your money to $0. Only use if you can afford losing all cash. ",
          ["Sigil"]                = "Converts ALL cards in hand to the same random suit. No card selection needed. ",
          ["Ouija"]                = "Converts ALL cards in hand to the same random rank, permanently -1 hand size. High risk — only use if hand size is expendable. ",
          ["Ectoplasm"]            = "Adds Negative edition to a random joker (no cost joker slot), permanently -1 hand size. Only use if hand size is expendable. ",
          ["Immolate"]             = "Destroys 5 random cards in hand, gives +$20. Use to thin weak cards from deck while gaining money. ",
          ["Ankh"]                 = "Copies one random joker and DESTROYS all other jokers. Extremely risky — only use if you have 1-2 jokers or one is clearly best. ",
          ["Hex"]                  = "Adds Polychrome to a random joker (x1.5 mult), DESTROYS all other jokers. Extremely risky — only use if you have 1 joker. ",
        }
        consumable_hint = consumable_hint .. string.format(
          "CONSUMABLE slot %d: '%s'. %sUSE: use_card|{\"area\":\"consumeables\",\"index\":%d}. ",
          i, nm, direct_hints[nm] or "Use directly. ", i)
        has_usable_consumable = true
      end
    end
  end

  local enhanced_in_hand = ""
  if G.hand and G.hand.cards then
    local enh_cards = {}
    for idx, card in ipairs(G.hand.cards) do
      local enh = card.ability and card.ability.enhancement
      if enh and enh ~= "" then
        local rank = card.base and card.base.value or "?"
        local suit = card.base and card.base.suit or "?"
        local enh_name = ({m_twin="Twin",m_bonus="Bonus",m_gold="Gold",m_steel="Steel",m_glass="Glass",m_mult="Mult",m_dono="Donation",m_glorp="Glorpy"})[enh] or enh
        enh_cards[#enh_cards + 1] = string.format("%d=%s %s(%s)", idx, rank, suit:sub(1,1), enh_name)
      end
    end
    if #enh_cards > 0 then
      local has_glorp = false
      for _, s in ipairs(enh_cards) do
        if s:find("Glorpy") then has_glorp = true break end
      end
      local enh_advice = "Prioritize hands that include these cards for bonus scoring. "
      if has_glorp then
        enh_advice = "Glorpy cards give 10x chips but BREAK at end of round — play them NOW, they vanish anyway. "
      end
      enhanced_in_hand = "Enhanced cards in hand: [" .. table.concat(enh_cards, ", ") .. "]. " .. enh_advice
    end
  end

  local query = rules .. "State: SELECTING_HAND. "
    .. "MODE: " .. mode .. ". "
    .. mode_hint
    .. blind_hint
    .. bp_chain
    .. "(Score/target/hands/discards in B+WIN lines.) "
    .. structure
    .. deck_strategy
    .. consumable_hint
    .. enhanced_in_hand
    .. debuff_info
    .. token_legend
    .. strategy_hint
    .. recent
  if dr_discard_str and dr_keep_str then
    query = query .. "Card strength (DR): strongest=[" .. dr_keep_str .. "] weakest=[" .. dr_discard_str .. "]. "
  elseif dr_discard_str then
    query = query .. "Card strength (DR): weakest=[" .. dr_discard_str .. "]. "
  end
  query = query .. failed_action_warning()
  local sim1_score = sim1 and tonumber(sim1.score) or 0
  local hand_actions = { "set_hand_highlight" }
  if has_usable_consumable then hand_actions[#hand_actions + 1] = "use_card" end

  if sim1_str then
    query = query .. "Strongest hand found: " .. (sim1_hand or "best") .. " at indices [" .. sim1_str .. "] (~" .. tostring(math.floor(sim1_score)) .. " chips estimated). "
  end
  if has_usable_consumable then
    query = query .. "You have usable consumables. Consider using them BEFORE playing. "
    query = query .. "Return: use_card|{...} to use a consumable, OR set_hand_highlight|{\"indices\":[...],\"action\":\"play\"|\"discard\"} to play/discard."
  else
    query = query .. "Use the information above to decide: play your best hand, or discard weak cards to draw better ones. "
    query = query .. "Return: set_hand_highlight|{\"indices\":[...],\"action\":\"play\"|\"discard\"}."
  end

  if hands_left <= 0 and disc <= 0 then
    return nil
  end

  return {
    query = query,
    actions = hand_actions
  }
end

FORCE_HANDLERS["SHOP"] = function(rules)
  local function quick_rank(card)
    if not card then return "C" end
    local ab = card.ability or {}
    local score = 0
    if ab.x_mult and ab.x_mult > 1 then score = score + 40 end
    if ab.h_mult and ab.h_mult > 0 then score = score + math.min(20, ab.h_mult * 2) end
    if ab.t_mult and ab.t_mult > 0 then score = score + 15 end
    local ed = card.edition
    if ed and type(ed) == "table" then
      if ed.polychrome then score = score + 35 end
      if ed.holo then score = score + 20 end
      if ed.foil then score = score + 10 end
    end
    if ab.set == "Booster" then score = score + 15 end
    if ab.set == "Voucher" then score = score + 25 end
    if score >= 35 then return "S"
    elseif score >= 20 then return "A"
    elseif score >= 10 then return "B"
    else return "C" end
  end
  local money = (G and G.GAME and G.GAME.dollars) or 0
  local ante = tonumber(G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante or 0) or 0
  local early_shop = ante > 0 and ante <= 2
  local shop_snap = shop_affordable_snapshot()
  local reroll_cost = G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost or 5
  local reroll_count = math.max(0, math.floor((G and G.NEURO.shop_reroll_count) or 0))
  local can_reroll = (type(reroll_cost) == "number" and reroll_cost > 0 and money >= reroll_cost)
  local affordable_count = 0
  local affordable_jokers = 0
  local affordable_packs = 0
  local affordable_vouchers = 0
  local seen_items = {}
  local item_lines = {}
  local buy_candidates = {}
  local first_buy_area = nil
  local first_buy_index = nil
  local function scan(area, label)
    if not (area and area.cards) then return end
    for i, card in ipairs(area.cards) do
      local c = card and card.cost
      if type(c) == "number" and c >= 0 then
        if c <= money then
          affordable_count = affordable_count + 1
          if label == "shop_jokers" then
            affordable_jokers = affordable_jokers + 1
          elseif label == "shop_booster" then
            affordable_packs = affordable_packs + 1
          elseif label == "shop_vouchers" then
            affordable_vouchers = affordable_vouchers + 1
          end
        end
        local nm = Utils.safe_name(card) or "Unknown"
        local key = label .. ":" .. tostring(i)
        if not seen_items[key] then
          seen_items[key] = true
          item_lines[#item_lines + 1] = string.format("%s[%d] %s $%d %s", label, i, nm, c, (c <= money and "(afford)" or "(no cash)"))
          if c <= money and (label == "shop_booster" or label == "shop_jokers" or label == "shop_vouchers") then
            buy_candidates[#buy_candidates + 1] = string.format("%s[%d]=%s($%d,R=%s)", label, i, nm, c, quick_rank(card))
            if not first_buy_area then
              first_buy_area = label
              first_buy_index = i
            end
          end
        end
      end
    end
  end
  local cheapest = nil
  local function scan_cheapest(area)
    if not (area and area.cards) then return end
    for _, card in ipairs(area.cards) do
      local c = card and card.cost
      if type(c) == "number" and c >= 0 then
        if not cheapest or c < cheapest then
          cheapest = c
        end
      end
    end
  end
  scan(G and G.shop_jokers, "shop_jokers")
  scan(G and G.shop_vouchers, "shop_vouchers")
  scan(G and G.shop_booster, "shop_booster")
  scan_cheapest(G and G.shop_jokers)
  scan_cheapest(G and G.shop_vouchers)
  scan_cheapest(G and G.shop_booster)

  local cons_planet, cons_tarot, cons_spectral = 0, 0, 0
  if G and G.consumeables and G.consumeables.cards then
    for _, c in ipairs(G.consumeables.cards) do
      local set = c and c.ability and c.ability.set
      if set == "Planet" then cons_planet = cons_planet + 1
      elseif set == "Tarot" then cons_tarot = cons_tarot + 1
      elseif set == "Spectral" then cons_spectral = cons_spectral + 1
      end
    end
  end

  local reroll_safe = "unknown"
  if type(cheapest) == "number" then
    reroll_safe = ((money - reroll_cost) >= cheapest) and "YES" or "NO"
  end

  table.sort(item_lines)
  local items_summary = "none"
  if #item_lines > 0 then
    local max_lines = math.min(8, #item_lines)
    local tmp = {}
    for i = 1, max_lines do
      tmp[#tmp + 1] = item_lines[i]
    end
    items_summary = table.concat(tmp, "; ")
  end
  local buy_hint = (#buy_candidates > 0) and table.concat(buy_candidates, "; ") or "none"
  local buy_example = ""
  if first_buy_area and first_buy_index then
    buy_example = string.format(' Example payload: buy_from_shop|{"area":"%s","index":%d}.', tostring(first_buy_area), tonumber(first_buy_index) or 1)
  end

  local can_buy_now = affordable_count > 0
  local shop_advice = can_buy_now and "You can afford at least one item now." or "No affordable items now; reroll only if safety check is YES, else leave shop."
  local affordable_good = (affordable_jokers + affordable_packs) > 0

  local force_actions = {}
  local can_buy_action = Actions.is_action_valid("buy_from_shop")
  local can_sell_action = Actions.is_action_valid("sell_card")
  local can_use_action = Actions.is_action_valid("use_card")
  local can_reroll_action = Actions.is_action_valid("reroll_shop")
  local can_reorder_action = Actions.is_action_valid("set_joker_order")
  local can_toggle_action = Actions.is_action_valid("toggle_shop")
  local must_buy_phase = early_shop and shop_snap.buyable_good and can_buy_action

  local shop_mode = "VALUE"
  if affordable_good then
    shop_mode = "HARVEST"
  elseif can_reroll_action and can_reroll then
    shop_mode = "REFRESH"
  else
    shop_mode = "EXIT_CHECK"
  end

  if can_buy_action then force_actions[#force_actions + 1] = "buy_from_shop" end
  if not must_buy_phase then
    if can_sell_action then force_actions[#force_actions + 1] = "sell_card" end
    if can_reroll_action then
      force_actions[#force_actions + 1] = "reroll_shop"
    end
  end
  if can_use_action then force_actions[#force_actions + 1] = "use_card" end
  if can_toggle_action then force_actions[#force_actions + 1] = "toggle_shop" end
  if #force_actions == 0 and can_reorder_action then force_actions[#force_actions + 1] = "set_joker_order" end

  if #force_actions == 0 then
    return nil
  end

  local token_legend = once_per_state_entry_hint(
    "shop_tokens",
    "Token legend: SH=shop economy line, LA=legality flags, I=items rows (area,index,name,cost,afford,rank,effect,desc). "
  )
  local shop_strategy = once_per_state_entry_hint(
    "shop_strategy",
    "Priority: buy jokers/packs > use/sell > reroll (if board weak) > leave. I lines have rank S>A>B>C; buy S/A first. "
  )
  local shop_heuristics = once_per_state_entry_hint(
    "shop_heuristics",
    "SELL: only rental jokers you can't afford, perishable at 1 turn left, or weakest joker when slots full and rank-S/A available. Never sell eternal. "
    .. "USE: planets to level best hand type, tarots to enhance before next blind, spectrals only if you understand the effect. "
    .. "EXIT: leave shop (toggle_shop) when nothing affordable AND reroll unsafe, or after buying S/A items and reroll won't improve. "
    .. "Vouchers are one-time offers — buy before rerolling. "
  )
  -- #7: Joker slot full warning
  local joker_count = G.jokers and G.jokers.cards and #G.jokers.cards or 0
  local joker_limit = G.jokers and G.jokers.config and G.jokers.config.card_limit or 5
  local joker_slot_warn = ""
  if joker_count >= joker_limit then
    joker_slot_warn = string.format("Joker slots FULL (%d/%d). Must sell a joker first to buy a new one, or skip jokers. ", joker_count, joker_limit)
  end
  -- #14: Joker order hint when Blueprint/Brainstorm present
  local joker_order_hint = ""
  if G.jokers and G.jokers.cards then
    for _, card in ipairs(G.jokers.cards) do
      local nm = card and card.ability and card.ability.name or ""
      if nm == "Blueprint" or nm == "Brainstorm" then
        joker_order_hint = once_per_state_entry_hint(
          "joker_order",
          "Joker order matters: leftmost triggers first. Blueprint/Brainstorm copy the joker to their right. Use set_joker_order if needed. "
        )
        break
      end
    end
  end
  local deck_shop_hint = once_per_state_entry_hint("shop_deck", deck_strategy_info())
  local money_proj = shop_money_projection()
  local voucher_chains = voucher_chain_hint()
  local recent = recent_actions_summary(5)

  local query = rules .. "State: SHOP. "
    .. "MODE: " .. shop_mode .. ". "
    .. (early_shop and "Early game (ante 1-2): prioritize immediate power so blind 2 is survivable. " or "")
    .. "Use SH/LA/I lines from STATE for prices and legality. "
    .. token_legend
    .. shop_strategy
    .. shop_heuristics
    .. deck_shop_hint
    .. money_proj
    .. voucher_chains
    .. joker_slot_warn
    .. joker_order_hint
    .. "Buy payload must use area exactly one of: shop_jokers, shop_vouchers, shop_booster and index from current items. "
    .. "Strong buy candidates now: " .. buy_hint .. ". "
    .. buy_example
    .. string.format("Inventory consumables: Planet=%d Tarot=%d Spectral=%d. ", cons_planet, cons_tarot, cons_spectral)
    .. string.format("Affordable now: jokers=%d packs=%d vouchers=%d. ", affordable_jokers, affordable_packs, affordable_vouchers)
    .. "Reroll cost: $" .. tostring(reroll_cost) .. ". "
    .. (can_reroll and "Reroll is currently affordable." or "Reroll is currently NOT affordable.") .. " "
    .. string.format("Rerolls used this shop visit: %d. ", reroll_count)
    .. "Cheapest visible shop item costs $" .. tostring(cheapest or "?") .. ". "
    .. "Reroll safety check (money after reroll >= cheapest visible item): " .. reroll_safe .. ". "
    .. "If any affordable joker or booster exists, prefer buy_from_shop over reroll_shop. "
    .. (must_buy_phase and "Early buy priority active: affordable booster/joker exists. First action should be buy_from_shop, not reroll or leave. " or "")
    .. recent
    .. failed_action_warning()
    .. shop_advice
  return {
    query = query,
    actions = force_actions
  }
end

FORCE_HANDLERS["BLIND_SELECT"] = function(rules)
  local bs = G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states
  local current_blind = "unknown"
  if bs then
    if bs.Small == "Select" then current_blind = "small"
    elseif bs.Big == "Select" then current_blind = "big"
    elseif bs.Boss == "Select" then current_blind = "boss"
    end
  end

  local blind_sig = blind_select_signature()
  if G then
    if G.NEURO.blind_info_sig ~= blind_sig then
      G.NEURO.blind_info_sig = blind_sig
      G.NEURO.blind_info_seen = false
    end
  end

  local info_seen = (G and G.NEURO.blind_info_seen) and true or false

  local can_select = Actions.is_action_valid("select_blind")
  local can_skip = Actions.is_action_valid("skip_blind")
  local can_reroll = Actions.is_action_valid("reroll_boss")

  local progress_actions = {}
  if can_select then progress_actions[#progress_actions + 1] = "select_blind" end
  if can_skip then progress_actions[#progress_actions + 1] = "skip_blind" end
  if can_reroll then progress_actions[#progress_actions + 1] = "reroll_boss" end

  if #progress_actions == 0 then
    return nil
  end

  -- #9: Read tag name for current blind
  local tag_hint = ""
  if current_blind ~= "unknown" and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_tags then
    local btype_map = { small = "Small", big = "Big", boss = "Boss" }
    local btype = btype_map[current_blind]
    if btype then
      local tag_key = G.GAME.round_resets.blind_tags[btype]
      if tag_key then
        local tag_name = tag_key
        if G.P_TAGS and G.P_TAGS[tag_key] and G.P_TAGS[tag_key].name then
          tag_name = G.P_TAGS[tag_key].name
        end
        local skip_patterns = { "Economy", "Negative", "Voucher", "Rare", "Ethereal" }
        local is_skip_tag = false
        for _, pat in ipairs(skip_patterns) do
          if tag_name:find(pat) then
            is_skip_tag = true
            break
          end
        end
        if is_skip_tag then
          tag_hint = "Current tag: " .. tag_name .. ". This is a valuable skip tag — RULE says skip. "
        else
          tag_hint = "Current tag: " .. tag_name .. ". "
        end
      end
    end
  end

  -- #10: Boss debuff inline text
  local boss_debuff_hint = ""
  if current_blind == "boss" then
    local choices = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
    local boss_key = choices and choices.Boss
    if boss_key and G.P_BLINDS and G.P_BLINDS[boss_key] then
      local bdef = G.P_BLINDS[boss_key]
      local bname = bdef.name or boss_key
      local desc = ""
      if bdef.loc_txt and type(bdef.loc_txt) == "table" and bdef.loc_txt.text and type(bdef.loc_txt.text) == "table" then
        desc = table.concat(bdef.loc_txt.text, " ")
      end
      if desc ~= "" then
        boss_debuff_hint = "Boss: " .. bname .. " — " .. desc .. ". "
      else
        boss_debuff_hint = "Boss: " .. bname .. ". "
      end
    end
  end

  local query = rules .. "State: BLIND_SELECT. "
  if current_blind ~= "unknown" then
    query = query .. "Currently selectable: " .. current_blind .. ". "
    .. tag_hint
    .. boss_debuff_hint
    if can_select then
      query = query .. 'Use select_blind|{"blind": "' .. current_blind .. '"} to fight it. '
    end
    if can_skip then
      query = query .. "skip_blind is available for tag reward. "
    end
    if can_reroll then
      query = query .. "reroll_boss is available. "
    end
  else
    query = query .. "Blind choice is transitioning; choose any currently valid blind action now. "
  end
  local blind_rule = ""
  if current_blind == "small" then
    blind_rule = "RULE: Skip small ONLY if tag is Economy/Negative/Voucher/Rare/Ethereal. Otherwise fight. Default=fight. "
  elseif current_blind == "big" then
    blind_rule = "RULE: Always fight big blind. Default=fight. "
  elseif current_blind == "boss" then
    blind_rule = "RULE: Boss is mandatory. Select it. Only reroll if reroll_boss is available AND boss debuff completely blocks your scoring (all cards debuffed, no playable hand). Default=select. "
  end
  query = query
    .. blind_rule

  return {
    query = query,
    actions = { "select_blind", "skip_blind", "reroll_boss" }
  }
end

local function pack_hand_list()
  if not (G and G.hand and G.hand.cards and #G.hand.cards > 0) then return "" end
  local parts = {}
  for i, c in ipairs(G.hand.cards) do
    local v = c.base and c.base.value or "?"
    local s = c.base and c.base.suit or "?"
    parts[#parts + 1] = tostring(i) .. "=" .. tostring(v) .. tostring(s:sub(1,1))
  end
  return "Hand[" .. table.concat(parts, ",") .. "]. "
end

local function force_pack(rules, state_name)
  local pack_type = (state_name == "SMODS_BOOSTER_OPENED") and "BOOSTER" or state_name:gsub("_PACK", "")
  local picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0
  local actions = { "use_card", "end_consumeable" }
  if picks_left <= 0 then
    actions[#actions + 1] = "skip_booster"
  end

  -- Detect "tarot awaiting hand selection" sub-state
  local cons_remaining = G and G.GAME and G.GAME.current_round
    and G.GAME.current_round.consumeables_remaining or 0
  if cons_remaining and cons_remaining > 0 then
    -- A tarot has been activated and is waiting for hand card selection
    actions = { "card_click", "end_consumeable" }
    local hand_info = pack_hand_list()
    local highlighted = ""
    if G.hand and G.hand.highlighted and #G.hand.highlighted > 0 then
      local hl = {}
      for i, c in ipairs(G.hand.cards or {}) do
        for _, h in ipairs(G.hand.highlighted) do
          if h == c then hl[#hl + 1] = tostring(i) end
        end
      end
      if #hl > 0 then highlighted = "Already selected: [" .. table.concat(hl, ",") .. "]. " end
    end
    return {
      query = rules .. pack_type .. " pack. TAROT ACTIVATED — waiting for hand card selection. "
        .. hand_info .. highlighted
        .. 'Select cards: card_click|{"area":"hand","index":N} for each target card. '
        .. "Then end_consumeable to confirm effect. "
        .. "Check tarot_target_advice: " .. pack_type .. " tarot needs specific targeting.",
      actions = actions,
    }
  end

  local pack_best = G and G.NEURO.pack_best
  local pick_hint = ""
  if pack_best then
    pick_hint = "Best card is index " .. pack_best.index .. " (rank " .. pack_best.rank .. "). Pick it. "
  end
  local all_c_hint = ""
  if pack_best and pack_best.rank == "C" then
    all_c_hint = "All cards rank C (weak). Consider skip_booster instead. "
  end
  local slot_warn = ""
  local is_consumable_pack = (pack_type == "TAROT" or pack_type == "PLANET" or pack_type == "SPECTRAL")
  if is_consumable_pack and G and G.consumeables then
    local cons_count = G.consumeables.cards and #G.consumeables.cards or 0
    local cons_limit = G.consumeables.config and G.consumeables.config.card_limit
    if cons_limit and cons_count >= cons_limit then
      slot_warn = string.format("Consumable slots FULL (%d/%d). Picking a card will FAIL unless you use/sell one first. ", cons_count, cons_limit)
    end
  end

  -- Build per-card selection hints for Tarots that need hand selection
  local sel_hints = ""
  local bp = G and (G.pack_cards or G.booster_pack)
  if is_consumable_pack and bp and bp.cards then
    local hand_info = pack_hand_list()
    local needs_sel = {}
    for i, c in ipairs(bp.cards) do
      local mh = c.ability and c.ability.consumeable and c.ability.consumeable.max_highlighted
      local mn = (c.ability and c.ability.consumeable and c.ability.consumeable.min_highlighted) or 1
      if mh and mh > 0 then
        local nm = c.ability and c.ability.name or "Tarot"
        local advice = tarot_target_advice(nm, "")
        needs_sel[#needs_sel + 1] = string.format(
          "Card %d (%s) needs %d-%d hand cards: %s"
          .. 'use_card|{"area":"booster_pack","index":%d,"hand_indices":[i,j,...]}.',
          i, nm, mn, mh, advice ~= "" and advice or "", i)
      end
    end
    if #needs_sel > 0 then
      sel_hints = hand_info .. table.concat(needs_sel, " ") .. " "
    end
  end

  return {
    query = rules .. pack_type .. " pack. Picks left: " .. tostring(math.max(0, math.floor(picks_left))) .. ". "
      .. pick_hint .. all_c_hint .. slot_warn .. sel_hints .. "PC rows rank: S>A>B>C. "
      .. 'Pick: use_card|{"area":"booster_pack","index":N} (add "hand_indices":[i,j] if card needs hand selection). '
      .. "If done: skip_booster.",
    actions = actions
  }
end
FORCE_HANDLERS["TAROT_PACK"] = function(rules, sn) return force_pack(rules, sn) end
FORCE_HANDLERS["PLANET_PACK"] = function(rules, sn) return force_pack(rules, sn) end
FORCE_HANDLERS["SPECTRAL_PACK"] = function(rules, sn) return force_pack(rules, sn) end
FORCE_HANDLERS["STANDARD_PACK"] = function(rules, sn) return force_pack(rules, sn) end
FORCE_HANDLERS["BUFFOON_PACK"] = function(rules, sn) return force_pack(rules, sn) end
FORCE_HANDLERS["SMODS_BOOSTER_OPENED"] = function(rules, sn) return force_pack(rules, sn) end

FORCE_HANDLERS["ROUND_EVAL"] = function(rules)
  return {
    query = rules .. "State: ROUND_EVAL. Round complete. Cash out now — use cash_out action immediately.",
    actions = { "cash_out" }
  }
end

FORCE_HANDLERS["GAME_OVER"] = function(rules)
  local hg = hiyori_persona_gate()
  if hg then return hg end
  return {
    query = rules .. "State: GAME_OVER. Use setup_run to open the run setup screen and start a new run.",
    actions = { "setup_run", "exit_overlay_menu", "help" }
  }
end

FORCE_HANDLERS["SPLASH"] = function(rules)
  local hg = hiyori_persona_gate()
  if hg then return hg end
  return {
    query = rules .. "State: SPLASH/MENU. Use setup_run to open the run setup screen.",
    actions = { "setup_run", "help" }
  }
end

FORCE_HANDLERS["MENU"] = function(rules)
  local hg = hiyori_persona_gate()
  if hg then return hg end
  local query = "Main menu. "
  if G and G.GAME then
    query = query .. string.format("Current stake: %d. ", G.GAME.stake or 1)
  end
  local deck_name = "Red Deck"
  if G and G.GAME and G.GAME.selected_back and G.GAME.selected_back.effect and G.GAME.selected_back.effect.center then
    deck_name = get_back_display_name(G.GAME.selected_back.effect.center)
  end
  query = query .. string.format("Current deck: %s. ", deck_name)
  query = query .. "Use setup_run to open the run setup screen where you will choose your deck and optionally a seed. "
  query = query .. menu_action_tree_query(false, nil)
  return {
    query = query,
    actions = { "setup_run", "start_challenge_run", "copy_seed", "change_stake", "confirm_contest_name", "help" }
  }
end


function Dispatcher.get_force_for_state(state_name)
  -- Run setup overlay: deck/seed/stake selection screen (sits on top of MENU state).
  -- Must be checked before the generic exit_overlay_menu intercept.
  if is_run_setup_overlay() then
    local deck_list = list_unlocked_decks()
    local must_pick = deck_list ~= "" and not G.NEURO.deck_chosen
    local query = "Run setup screen is open. "
    if must_pick then
      query = query .. "Pick a deck — try something different for variety! Available: " .. deck_list .. ". Use change_selected_back with a key from this list. "
      return { query = query, actions = { "change_selected_back", "help" } }
    else
      -- Deck chosen — go straight to starting (no seed: seeded runs block unlocks)
      local deck_name = "Red Deck"
      if G.GAME and G.GAME.viewed_back and G.GAME.viewed_back.effect and G.GAME.viewed_back.effect.center then
        deck_name = get_back_display_name(G.GAME.viewed_back.effect.center)
      elseif G.GAME and G.GAME.viewed_back then
        deck_name = G.GAME.viewed_back.loc_name or G.GAME.viewed_back.name or "Red Deck"
      end
      query = query .. "Deck chosen: " .. deck_name .. ". Call start_setup_run now to begin the run. "
      return { query = query, actions = { "start_setup_run", "help" } }
    end
  end

  -- Check for blocking overlay before anything else, even if the current state
  -- has no handler (unlock popups fire during transitions/animations).
  if Actions.is_action_valid("exit_overlay_menu") then
    local overlay_actions = { "exit_overlay_menu" }
    if state_name == "GAME_OVER" or state_name == "MENU" or state_name == "SPLASH" then
      overlay_actions[#overlay_actions + 1] = "setup_run"
    end
    return {
      query = "A popup is blocking the game. Close it using exit_overlay_menu, or use setup_run to start a new run.",
      actions = overlay_actions,
    }
  end

  local handler = FORCE_HANDLERS[state_name]
  if not handler and state_name and state_name:find("_PACK$") then
    handler = function(rules, sn) return force_pack(rules, sn) end
  end
  if not handler then return nil end

  local rules = get_game_rules(state_name)
  local force = handler(rules, state_name)
  if type(force) ~= "table" then return nil end

  local actions = force.actions or {}
  local state_set = Actions.get_state_action_set(state_name)
  local seen = {}
  local filtered = {}

  for _, name in ipairs(actions) do
    if type(name) == "string" and not seen[name] and state_set[name] and Actions.is_action_valid(name) then
      filtered[#filtered + 1] = name
      seen[name] = true
    end
  end

  if #filtered == 0 then
    local fallback = Actions.get_valid_actions_for_state(state_name)
    for _, name in ipairs(fallback) do
      if type(name) == "string" and not seen[name] then
        filtered[#filtered + 1] = name
        seen[name] = true
      end
    end
  end

  local NON_PROGRESS_FORCE_ACTIONS = {
    help = true,
    quick_status = true,
    shop_context = true,
    deck_composition = true,
    owned_vouchers = true,
    round_history = true,
    neuratro_info = true,
    scoring_explanation = true,
    joker_strategy = true,
    consumables_info = true,
    blind_info = true,
    hand_levels_info = true,
    hand_details = true,
    get_poker_hand_information = true,
    joker_info = true,
    card_modifiers_information = true,
    deck_type = true,
    full_game_context = true,
    evaluate_play = true,
    simulate_hand = true,
    clear_hand_highlight = true,
    reorder_hand_cards = true,
    set_joker_order = true,
    copy_seed = true,
  }

  local progress = {}
  for _, name in ipairs(filtered) do
    if not NON_PROGRESS_FORCE_ACTIONS[name] then
      progress[#progress + 1] = name
    end
  end

  if #progress > 0 then
    filtered = progress
  end

  if #filtered == 0 then return nil end
  force.actions = filtered
  return force
end

function Dispatcher.route_message(msg, bridge)
  if not msg then return end

  if msg.command == "action" and msg.data then
    local id = msg.data.id
    local prior = tx_get(id)
    if prior then
      if bridge then
        bridge:send_action_result(id, prior.ok, prior.message)
      end
      return
    end

    local ok_stage, Staging = pcall(require, "staging")
    if ok_stage and Staging and Staging.should_stage and Staging.should_stage(msg) then
      Staging.queue(msg, bridge)
      return
    end
  end

  Dispatcher.handle_message(msg, bridge)
end

return Dispatcher
