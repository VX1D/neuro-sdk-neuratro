local M = {}

local Utils = require("util.utils")
local NUMERIC_EFFECTS = require("facts.numeric_effects")
local NUMERIC_EFFECTS_BY_FIELD = {}
for _, e in ipairs(NUMERIC_EFFECTS) do NUMERIC_EFFECTS_BY_FIELD[e.field] = e end

local function live_area(a)
  return (a and a.cards and not a.REMOVED) and a or nil
end
local function pack_area()
  if not G then return nil end
  return live_area(G.pack_cards) or live_area(G.booster_pack)
end

local function center_of(card)
  return card and card.config and card.config.center or nil
end

local function center_key(card)
  local c = card and card.config and card.config.center
  return c and c.key
end

local function card_set(card)
  local ability = card and card.ability
  local center = card and card.config and card.config.center
  return (ability and ability.set) or (center and center.set) or ""
end

local CONSUMABLE_SETS_FALLBACK = { Tarot = true, Planet = true, Spectral = true }

local function live_consumable_type(set)
  local smods = rawget(_G, "SMODS")
  if type(smods) ~= "table" then return nil end
  local ctype = smods.ConsumableType
  local buffer = type(ctype) == "table" and ctype.obj_buffer or nil
  if type(buffer) == "table" and #buffer > 0 then
    for _, key in ipairs(buffer) do
      if key == set then return true end
    end
    return false
  end
  local types = smods.ConsumableTypes
  if type(types) == "table" and next(types) ~= nil then
    return types[set] ~= nil
  end
  return nil
end

local function is_consumable_set(set)
  if type(set) ~= "string" or set == "" then return false end
  local live = live_consumable_type(set)
  if live ~= nil then return live end
  return CONSUMABLE_SETS_FALLBACK[set] == true
end
local function is_consumable_card(card)
  return is_consumable_set(card_set(card))
    or type(card and card.ability and card.ability.consumeable) == "table"
end

local function booster_kind(card)
  local center = card and card.config and card.config.center
  return (center and center.kind) or ""
end

local function is_negative(card)
  return not not (card and card.edition and (card.edition.negative or card.edition.key == "e_negative"))
end

local function is_joker_like_card(card, area_name)
  local set = card_set(card)
  local center = card and card.config and card.config.center
  return area_name == "shop_jokers"
    or set == "Joker"
    or (center and center.set == "Joker")
end

local function joker_count()      return ((G and G.jokers and G.jokers.cards and #G.jokers.cards) or 0) + ((G and G.GAME and tonumber(G.GAME.joker_buffer)) or 0) end
local function consumable_count() return ((G and G.consumeables and G.consumeables.cards and #G.consumeables.cards) or 0) + ((G and G.GAME and tonumber(G.GAME.consumeable_buffer)) or 0) end

local function joker_limit()      return (G and G.jokers and G.jokers.config and G.jokers.config.card_limit) or 5 end
local function consumable_limit() return (G and G.consumeables and G.consumeables.config and G.consumeables.config.card_limit) or 2 end
local function hand_limit()       return (G and G.hand and G.hand.config and G.hand.config.card_limit) or 8 end
local function highlight_limit()  return (G and G.hand and G.hand.config and G.hand.config.highlighted_limit) or 5 end

local function score_per_hand(remaining, hands)
  if not hands or hands <= 0 then return nil end
  return math.ceil(remaining / hands)
end

local function has_joker_space_for(card)
  if is_negative(card) then return true end
  return joker_count() < joker_limit()
end

local function has_consumable_space()
  return consumable_count() < consumable_limit()
end

local function joker_slot_status()
  local count = joker_count()
  local limit = joker_limit()
  return { count = count, limit = limit, full = count >= limit }
end
local function consumable_slot_status()
  local count = consumable_count()
  local limit = consumable_limit()
  return { count = count, limit = limit, full = count >= limit }
end

local function slot_status_text(status)
  return string.format("slots %d/%d%s", status.count, status.limit, status.full and " FULL" or "")
end

local function can_buy_card_space(card, area_name)
  local set = card_set(card)
  if set == "Booster" or area_name == "shop_booster" or area_name == "shop_vouchers" then
    return true
  end
  if is_consumable_card(card) then
    if is_negative(card) or has_consumable_space() then return true end
    local _, max_t = M.consumable_target_range(card)
    if max_t and max_t > 0 then return false end
    if type(card.can_use_consumeable) == "function" then
      local ok, usable = pcall(card.can_use_consumeable, card, true, true)
      return ok and usable and true or false
    end
    return false
  end
  if is_joker_like_card(card, area_name) then
    return has_joker_space_for(card)
  end
  return true
end

local NAMED_HAND_TARGET = {
  c_aura = { min = 1, max = 1, needs = function(c) return not c.edition end },
}
local function named_hand_target(card)
  local key = center_key(card)
  return key and NAMED_HAND_TARGET[key] or nil
end

local function hand_card_count(predicate)
  local cards = (G and G.hand and G.hand.cards) or nil
  if type(cards) ~= "table" then return 0 end
  if not predicate then return #cards end
  local n = 0
  for _, c in ipairs(cards) do
    if type(c) == "table" and predicate(c) then n = n + 1 end
  end
  return n
end

local function consumable_usable_now(card)
  local min_h, max_h = M.consumable_target_range(card)
  if max_h and max_h > 0 then
    local named = named_hand_target(card)
    return hand_card_count(named and named.needs) >= (min_h or 1)
  end
  if type(card and card.can_use_consumeable) == "function" then
    local ok, usable = pcall(card.can_use_consumeable, card, true, true)
    if ok then return usable and true or false end
  end
  return has_consumable_space()
end

local function has_blocked_consumable()
  local cards = G and G.consumeables and G.consumeables.cards
  if not cards then return false end
  for _, c in ipairs(cards) do
    if not consumable_usable_now(c) then return true end
  end
  return false
end

local function can_take_pack_card(card)
  if card and card.base and card.base.suit then
    return true
  end
  if is_consumable_card(card) then
    local min_target, max_target = M.consumable_target_range(card)
    local named_target = named_hand_target(card)
    if max_target and max_target > 0
        and hand_card_count(named_target and named_target.needs) < (min_target or 1) then
      return has_consumable_space()
    end
    return consumable_usable_now(card)
  end
  if is_joker_like_card(card) then
    return has_joker_space_for(card)
  end
  return true
end

local function consumable_target_range(card)
  local nt = named_hand_target(card)
  if nt then return nt.min, nt.max end
  local c = card and card.ability and card.ability.consumeable
  if type(c) ~= "table" then return nil, nil end
  local max = tonumber(c.max_highlighted)
  if not max then return nil, nil end
  max = tonumber(c.mod_num) or math.min(5, max)
  local min = tonumber(c.min_highlighted) or 1
  return min, max
end

local function resolve_field(v)
  if type(v) == "function" then return v() end
  return v
end

local CENTER_CONFIG_FALLBACK = {
  m_bonus = { bonus = 30 },
  m_mult = { mult = 4 },
  m_wild = {},
  m_glass = { Xmult = 2, extra = 4 },
  m_steel = { h_x_mult = 1.5 },
  m_stone = { bonus = 50 },
  m_gold = { h_dollars = 3 },
  m_lucky = { mult = 20, p_dollars = 20 },
  e_foil = { extra = 50 },
  e_holo = { extra = 10 },
  e_polychrome = { extra = 1.5 },
  e_negative = { extra = 1 },
}

local function center_config(key)
  local center = G and G.P_CENTERS and G.P_CENTERS[key]
  local cfg = (type(center) == "table") and center.config or nil
  if type(cfg) == "table" then return cfg end
  return CENTER_CONFIG_FALLBACK[key] or {}
end

local function cfg_num(key, field)
  local v = tonumber(center_config(key)[field])
  if v == nil then v = tonumber((CENTER_CONFIG_FALLBACK[key] or {})[field]) end
  return v or 0
end

local function numtext(v)
  return Utils.fmt_num(v)
end

local LUCKY_MULT_ODDS = 5
local LUCKY_DOLLAR_ODDS = 15

local EDITIONS = {
  { test = function(e) return e.negative or e.key == "e_negative" end, name = "Negative",
    tag = "Negative(free_slot)",
    desc = function() return "Takes no slot (+" .. numtext(cfg_num("e_negative", "extra")) .. " joker/consumable slot)" end,
    fx = "" },
  { test = function(e) return e.polychrome end, name = "Polychrome",
    tag = function() return "Poly(x" .. numtext(cfg_num("e_polychrome", "extra")) .. "m)" end,
    desc = function() return "X" .. numtext(cfg_num("e_polychrome", "extra")) .. " Mult" end,
    fx = function() return "x" .. numtext(cfg_num("e_polychrome", "extra")) .. "m" end },
  { test = function(e) return e.holo end, name = "Holographic",
    tag = function() return "Holo(+" .. numtext(cfg_num("e_holo", "extra")) .. "m)" end,
    desc = function() return "+" .. numtext(cfg_num("e_holo", "extra")) .. " Mult" end,
    fx = function() return "+" .. numtext(cfg_num("e_holo", "extra")) .. "m" end },
  { test = function(e) return e.foil end, name = "Foil",
    tag = function() return "Foil(+" .. numtext(cfg_num("e_foil", "extra")) .. "c)" end,
    desc = function() return "+" .. numtext(cfg_num("e_foil", "extra")) .. " Chips" end,
    fx = function() return "+" .. numtext(cfg_num("e_foil", "extra")) .. "c" end },
}

local function find_test_match(list, subject)
  for _, e in ipairs(list) do
    if e.test(subject) then return e end
  end
  return nil
end

local function edition_desc(edition)
  if type(edition) ~= "table" then return nil end
  local e = find_test_match(EDITIONS, edition)
  return e and resolve_field(e.desc) or nil
end

local function edition_fx_short(edition)
  if type(edition) ~= "table" then return "" end
  local e = find_test_match(EDITIONS, edition)
  return (e and resolve_field(e.fx)) or ""
end

local function edition_name(edition)
  if type(edition) ~= "table" then return nil end
  local e = find_test_match(EDITIONS, edition)
  if e then return e.name end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  if edition.type and edition.type ~= "" then return tostring(edition.type) end
  if edition.key then return (tostring(edition.key):gsub("^e_", "")) end
  return nil
end

local function prob_odds(base)
  local p = tonumber(G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal) or 1
  return p, base
end
local function live_odds(base)
  local num, den = prob_odds(base)
  return numtext(num) .. " in " .. numtext(den)
end
local function odds_frac(base)
  local num, den = prob_odds(base)
  return numtext(num) .. "/" .. numtext(den)
end

local ENHANCEMENTS = {
  m_bonus = {
    name = "Bonus",
    short = function() return "Bonus(+" .. numtext(cfg_num("m_bonus", "bonus")) .. "c)" end,
    desc = function() return "+" .. numtext(cfg_num("m_bonus", "bonus")) .. " Chips" end,
    fx = function() return "+" .. numtext(cfg_num("m_bonus", "bonus")) .. "c" end,
  },
  m_mult = {
    name = "Mult",
    short = function() return "Mult(+" .. numtext(cfg_num("m_mult", "mult")) .. "m)" end,
    desc = function() return "+" .. numtext(cfg_num("m_mult", "mult")) .. " Mult" end,
    fx = function() return "+" .. numtext(cfg_num("m_mult", "mult")) .. "m" end,
  },
  m_wild = { name = "Wild", short = "Wild(counts_as_any_suit)", desc = "Can be used as any suit", fx = "" },
  m_glass = {
    name = "Glass",
    short = function()
      return "Glass(x" .. numtext(cfg_num("m_glass", "Xmult")) .. "m_always_then_"
        .. odds_frac(cfg_num("m_glass", "extra")) .. "_destroyed)"
    end,
    desc = function()
      return "x" .. numtext(cfg_num("m_glass", "Xmult")) .. " Mult, "
        .. live_odds(cfg_num("m_glass", "extra")) .. " chance to break"
    end,
    fx = function() return "x" .. numtext(cfg_num("m_glass", "Xmult")) .. "m" end,
  },
  m_steel = {
    name = "Steel",
    short = function() return "Steel(x" .. numtext(cfg_num("m_steel", "h_x_mult")) .. "m_per_copy_held_not_played)" end,
    desc = function() return "x" .. numtext(cfg_num("m_steel", "h_x_mult")) .. " Mult while in hand" end,
    fx = function() return "x" .. numtext(cfg_num("m_steel", "h_x_mult")) .. "m" end,
  },
  m_stone = {
    name = "Stone",
    short = function() return "Stone(no_suit_no_rank+" .. numtext(cfg_num("m_stone", "bonus")) .. "c_always)" end,
    desc = function() return "+" .. numtext(cfg_num("m_stone", "bonus")) .. " Chips, no rank/suit" end,
    fx = function() return "+" .. numtext(cfg_num("m_stone", "bonus")) .. "c" end,
  },
  m_gold = {
    name = "Gold",
    short = function() return "Gold(+$" .. numtext(cfg_num("m_gold", "h_dollars")) .. "_held_EOround)" end,
    desc = function() return "$" .. numtext(cfg_num("m_gold", "h_dollars")) .. " at end of round if held" end,
    fx = function() return "+$" .. numtext(cfg_num("m_gold", "h_dollars")) end,
  },
  m_lucky = {
    name = "Lucky",
    short = function()
      return "Lucky(" .. odds_frac(LUCKY_MULT_ODDS) .. ":+" .. numtext(cfg_num("m_lucky", "mult"))
        .. "m_or_" .. odds_frac(LUCKY_DOLLAR_ODDS) .. ":+" .. numtext(cfg_num("m_lucky", "p_dollars")) .. "$)"
    end,
    desc = function()
      return live_odds(LUCKY_MULT_ODDS) .. " for +" .. numtext(cfg_num("m_lucky", "mult")) .. " Mult, "
        .. live_odds(LUCKY_DOLLAR_ODDS) .. " for $" .. numtext(cfg_num("m_lucky", "p_dollars"))
    end,
    fx = "",
  },
}

local function edition_tag(edition)
  if type(edition) ~= "table" then
    return (edition ~= nil) and tostring(edition) or ""
  end
  local e = find_test_match(EDITIONS, edition)
  if e then return resolve_field(e.tag) end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  return ""
end

local function edition_readable(edition)
  if type(edition) ~= "table" then
    return (edition ~= nil) and tostring(edition) or ""
  end
  local e = find_test_match(EDITIONS, edition)
  if e then return e.name .. ": " .. resolve_field(e.desc) end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  return ""
end

local RARITY_NAMES = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Legendary" }

local function smods_rarity(rarity)
  local smods = rawget(_G, "SMODS")
  local rarities = type(smods) == "table" and smods.Rarities or nil
  if type(rarities) ~= "table" then return nil, nil end
  return rarities[rarity], smods
end

local function live_rarity_name(rarity)
  local rec, smods = smods_rarity(rarity)
  if not rec then return nil end
  local badge = smods.Rarity and smods.Rarity.get_rarity_badge
  if type(badge) == "function" then
    local ok, text = pcall(badge, smods.Rarity, rarity)
    if ok and type(text) == "string" and text ~= "" and not text:find("^k_") then return text end
  end
  local misc = G and G.localization and G.localization.misc
  local key = "k_" .. tostring(rarity):lower()
  local text = misc and ((misc.labels and misc.labels[key]) or (misc.dictionary and misc.dictionary[key]))
  if type(text) == "string" and text ~= "" then return text end
  return nil
end

local function humanized_rarity(rarity)
  local rec = smods_rarity(rarity)
  local s = tostring((type(rec) == "table" and rec.original_key) or rarity)
  s = s:gsub("_", " "):gsub("%f[%w][%w]", string.upper)
  return s
end
local COPY_JOKER_KEYS = { j_blueprint = "blueprint", j_brainstorm = "brainstorm" }
local function copy_joker_kind(card)
  local key = center_key(card)
  return key and COPY_JOKER_KEYS[key] or nil
end
local function rarity_name(rarity)
  if rarity == nil then return "Common" end
  return RARITY_NAMES[rarity] or live_rarity_name(rarity) or humanized_rarity(rarity)
end

local function lookup_field(tbl, key, field, fallback)
  local r = key and tbl[key]
  local v = r and resolve_field(r[field])
  if v then return v end
  return fallback and fallback(key) or nil
end
local function enhancement_record(key)
  local r = key and ENHANCEMENTS[key]
  if not r then return nil end
  return {
    name = resolve_field(r.name),
    short = resolve_field(r.short),
    desc = resolve_field(r.desc),
    fx = resolve_field(r.fx),
  }
end
local function identity(k) return k end
local function enhancement_name(key)
  return lookup_field(ENHANCEMENTS, key, "name", identity)
end
local function enhancement_short(key)
  return lookup_field(ENHANCEMENTS, key, "short", identity)
end
local function enhancement_fx_short(key)
  return lookup_field(ENHANCEMENTS, key, "fx", function() return "" end) or ""
end

local GOLD_SEAL_DOLLARS = 3

local function live_seal(seal)
  local defs = G and G.P_SEALS
  local obj = (type(defs) == "table") and defs[seal] or nil
  return (type(obj) == "table") and obj or nil
end

local function seal_dollars(seal)
  local obj = live_seal(seal)
  if obj and type(obj.get_p_dollars) == "function" then
    local ok, v = pcall(obj.get_p_dollars, obj)
    v = ok and tonumber(v) or nil
    if v and v ~= 0 then return v end
  end
  if seal == "Gold" then return GOLD_SEAL_DOLLARS end
  return nil
end

local function gold_dollars() return seal_dollars("Gold") or GOLD_SEAL_DOLLARS end

local SEALS = {
  Red               = { name = "Red", fx = "x2", short = "Red(x2_trigger_when_scored)", desc = "Retriggers when scored (this card scores twice)" },
  Blue              = { name = "Blue", fx = "Planet", short = "Blue(hold_in_hand=free_planet_EOround)", desc = "If held at end of round, creates the Planet for your last-played poker hand (needs a free consumable slot)" },
  Gold              = {
    name = "Gold",
    fx = function() return "+$" .. numtext(gold_dollars()) end,
    short = function() return "Gold(+$" .. numtext(gold_dollars()) .. "_when_scored)" end,
    desc = function() return "Earn $" .. numtext(gold_dollars()) .. " when this card is scored" end,
  },
  Purple            = { name = "Purple", fx = "Tarot", short = "Purple(discard=free_tarot)", desc = "Creates a Tarot card when discarded (needs a free consumable slot)" },
}

local function seal_label(seal)
  local misc = G and G.localization and G.localization.misc
  local key = tostring(seal):lower() .. "_seal"
  local text = misc and ((misc.labels and misc.labels[key]) or (misc.dictionary and misc.dictionary[key]))
  if type(text) == "string" and text ~= "" then return text end
  return nil
end

local function seal_record(seal)
  local r = SEALS[seal]
  if r then return r end
  if not live_seal(seal) then return nil end
  local name = seal_label(seal) or tostring(seal)
  local d = seal_dollars(seal)
  return {
    name = name,
    fx = d and ("+$" .. numtext(d)) or "",
    short = d and (name .. "(+$" .. numtext(d) .. "_when_scored)") or (name .. "(seal)"),
    desc = d and ("Earn $" .. numtext(d) .. " when this card is scored") or nil,
  }
end

local function seal_field(seal, field, fallback)
  local r = seal and seal_record(seal)
  local v = r and resolve_field(r[field])
  if v then return v end
  return fallback and fallback(seal) or nil
end

local function enhancement_key(card)
  if type(card) ~= "table" then return nil end
  local ab = card.ability
  if ab and ab.enhancement and ENHANCEMENTS[ab.enhancement] then return ab.enhancement end
  local key = center_key(card)
  if key and ENHANCEMENTS[key] then return key end
  return nil
end

-- Canonical no-rank predicate. Stone and every no_rank enhancement answer here: SMODS is the
-- authority when loaded, Card:get_id returns a large negative for them (card.lua:1174-1179), and
-- the centre key is the offline fallback.
local function has_no_rank(card)
  if type(card) ~= "table" then return false end
  local SM = rawget(_G, "SMODS")
  if SM and type(SM.has_no_rank) == "function" then
    local ok, v = pcall(SM.has_no_rank, card)
    if ok and v then return true end
  end
  if type(card.get_id) == "function" then
    local ok, id = pcall(card.get_id, card)
    if ok and type(id) == "number" and id < 0 then return true end
  end
  return center_key(card) == "m_stone"
end

-- The engine moves every highlighted card out of G.hand into G.play before any scoring pass runs
-- (functions/state_events.lua:493-500), so nothing that reads the hand at score time may see the
-- pending selection. Returns the remaining cards and whether that list is exact.
local function held_after_play(selection)
  local held = G and G.hand and G.hand.cards
  if type(held) ~= "table" or #held == 0 then return nil, false end
  if type(selection) ~= "table" or #selection == 0 then return held, false end
  local played = {}
  for _, card in ipairs(selection) do played[card] = true end
  local remaining = {}
  for _, card in ipairs(held) do
    if not played[card] then remaining[#remaining + 1] = card end
  end
  return remaining, true
end

local function deck_has_stone()
  local cards = G and G.playing_cards
  if type(cards) ~= "table" then return false end
  for _, c in ipairs(cards) do
    if enhancement_key(c) == "m_stone" then return true end
  end
  return false
end

local function normalize_seal_key(seal)
  if type(seal) == "table" then seal = seal.name or seal.key end
  return seal
end
local function seal_name(seal)
  seal = normalize_seal_key(seal)
  if not seal then return nil end
  return seal_field(seal, "name", tostring)
end
local function seal_fx_short(seal)
  seal = normalize_seal_key(seal)
  if not seal then return "" end
  return seal_field(seal, "fx", function() return "" end) or ""
end
local function rental_rate()
  return (G and G.GAME and tonumber(G.GAME.rental_rate)) or 3
end
local function sticker_fx_short(key)
  if key == "eternal" then return "no-sell" end
  if key == "rental" then return "-$" .. tostring(rental_rate()) .. "/rd" end
  if key == "perishable" then return "debuff" end
  return ""
end
local function seal_short(seal)
  seal = normalize_seal_key(seal)
  if not seal then return nil end
  return seal_field(seal, "short", tostring)
end
local function seal_desc(seal)
  seal = normalize_seal_key(seal)
  if not seal then return nil end
  return seal_field(seal, "desc", nil)
end

local function card_modifier_desc(card)
  if type(card) ~= "table" then return "" end
  local parts = {}
  local ek = enhancement_key(card)
  if ek then
    local rec = enhancement_record(ek)
    if rec and rec.name then
      parts[#parts + 1] = rec.desc and (rec.name .. ": " .. rec.desc) or rec.name
    end
  end
  if card.seal then
    local nm = seal_name(card.seal)
    if nm then
      local d = seal_desc(card.seal)
      parts[#parts + 1] = d and (nm .. " Seal: " .. d) or (nm .. " Seal")
    end
  end
  if card.edition then
    local nm = edition_name(card.edition)
    if nm then
      local d = edition_desc(card.edition)
      parts[#parts + 1] = d and (nm .. ": " .. d) or nm
    end
  end
  return table.concat(parts, "  ")
end

local function joker_template_ability(c)
  local key = center_key(c)
  local center = key and G and G.P_CENTERS and G.P_CENTERS[key]
  if not center then return {} end
  if type(center.ability) == "table" then return center.ability end
  local cfg = type(center.config) == "table" and center.config or {}
  return {
    x_mult = cfg.Xmult or cfg.x_mult or 1,
    h_mult = cfg.h_mult or 0,
    h_chips = cfg.h_chips or 0,
    t_mult = cfg.t_mult or 0,
    t_chips = cfg.t_chips or 0,
    extra = cfg.extra,
  }
end

local JOKER_FX_SPECS = {}
for _, field in ipairs({ "x_mult", "h_mult", "h_chips", "t_mult", "t_chips" }) do
  JOKER_FX_SPECS[#JOKER_FX_SPECS + 1] = NUMERIC_EFFECTS_BY_FIELD[field]
end

local dynamic_jokers
local function joker_registry()
  dynamic_jokers = dynamic_jokers or require("facts.dynamic_jokers")
  return dynamic_jokers
end

local function joker_fx(c)
  local center = c and c.config and c.config.center or {}
  local key = center.key
  if not (key and G and G.P_CENTERS and G.P_CENTERS[key]) then return "" end
  local ab = c and c.ability or {}
  local tb = joker_template_ability(c)
  for _, spec in ipairs(JOKER_FX_SPECS) do
    local field = spec.field
    if ab[field] == (tb[field] or spec.skip) then
      local label = NUMERIC_EFFECTS.label(ab, spec)
      if label then return label end
    end
  end
  if type(ab.extra) == "table" then
    local parts = {}
    for _, spec in ipairs(joker_registry().extra_specs(key)) do
      if NUMERIC_EFFECTS.read(ab, spec) == NUMERIC_EFFECTS.read(tb, spec) then
        parts[#parts + 1] = NUMERIC_EFFECTS.label(ab, spec)
      end
    end
    return table.concat(parts, "; ")
  end
  return ""
end

local function area_has_negative(area)
  if not (area and area.cards) then return false end
  for _, c in ipairs(area.cards) do
    if is_negative(c) then return true end
  end
  return false
end

local function area_has_negative_joker(area)
  if not (area and area.cards) then return false end
  for _, c in ipairs(area.cards) do
    if is_negative(c) and is_joker_like_card(c) then return true end
  end
  return false
end

local function joker_fx_line(card, description)
  if type(description) == "string" and description ~= "" then return "" end
  return joker_fx(card)
end

M.joker_fx = joker_fx
M.joker_fx_line = joker_fx_line
M.card_set = card_set
M.is_consumable_set = is_consumable_set
M.is_consumable_card = is_consumable_card
M.booster_kind = booster_kind
M.area_has_negative = area_has_negative
M.area_has_negative_joker = area_has_negative_joker
M.is_joker_like_card = is_joker_like_card
M.has_consumable_space = has_consumable_space
M.pack_area = pack_area
M.joker_limit = joker_limit
M.consumable_limit = consumable_limit
M.hand_limit = hand_limit
M.highlight_limit = highlight_limit
M.joker_slot_status = joker_slot_status
M.consumable_slot_status = consumable_slot_status
local function order_matters()
  if not (G and G.jokers and G.jokers.cards) then return false end
  local CardSemantics = require("facts.card_semantics")
  local has_xmult, has_flat_mult = false, false
  for _, card in ipairs(G.jokers.cards) do
    if type(card) == "table" and not card.debuff then
      if copy_joker_kind(card) then return true end
      if not has_xmult and CardSemantics.produces_xmult(card) then has_xmult = true end
      if not has_flat_mult and CardSemantics.produces_flat_mult(card) then has_flat_mult = true end
      if has_xmult and has_flat_mult then return true end
    end
  end
  return false
end

M.order_matters = order_matters
M.center_config_num = cfg_num
M.slot_status_text = slot_status_text
M.can_buy_card_space = can_buy_card_space
M.can_take_pack_card = can_take_pack_card
M.consumable_usable_now = consumable_usable_now
M.has_blocked_consumable = has_blocked_consumable
M.consumable_target_range = consumable_target_range
M.odds_frac = odds_frac
M.ENHANCEMENTS = ENHANCEMENTS
M.SEALS = SEALS
M.EDITIONS = EDITIONS
M.edition_name = edition_name
M.edition_tag = edition_tag
M.edition_fx_short = edition_fx_short
M.rarity_name = rarity_name
M.copy_joker_kind = copy_joker_kind
M.enhancement_record = enhancement_record
M.enhancement_key = enhancement_key
M.has_no_rank = has_no_rank
M.held_after_play = held_after_play
M.deck_has_stone = deck_has_stone
M.is_negative = is_negative
M.enhancement_name = enhancement_name
M.enhancement_short = enhancement_short
M.enhancement_fx_short = enhancement_fx_short
M.seal_fx_short = seal_fx_short
M.sticker_fx_short = sticker_fx_short
M.seal_name = seal_name
M.seal_short = seal_short
M.card_modifier_desc = card_modifier_desc
M.center = center_of
M.score_per_hand = score_per_hand

local function planet_run_state_suffix(card)
  if card_set(card) ~= "Planet" then return "" end
  local ht = card and card.ability and card.ability.consumeable and card.ability.consumeable.hand_type
  if not ht then
    local ctr = card and card.config and card.config.center
    ht = ctr and ctr.config and ctr.config.hand_type
  end
  local h = ht and G and G.GAME and type(G.GAME.hands) == "table" and G.GAME.hands[ht]
  if type(h) ~= "table" then return "" end
  return string.format("; played %s %dx this run (lvl %d)",
    tostring(ht), tonumber(h.played) or 0, tonumber(h.level) or 1)
end
M.planet_run_state_suffix = planet_run_state_suffix

function M.is_face_down(card)
  return not not (card and card.facing == "back")
end

function M.unplayed_pool()
  local dk = G and G.deck and G.deck.cards
  if type(dk) ~= "table" then return nil, 0 end
  local pool, flipped = {}, 0
  for _, c in ipairs(dk) do pool[#pool + 1] = c end
  for _, c in ipairs((G and G.hand and G.hand.cards) or {}) do
    if M.is_face_down(c) or (c and c.ability and c.ability.wheel_flipped) then
      pool[#pool + 1] = c
      flipped = flipped + 1
    end
  end
  return pool, flipped
end

function M.joker_composition_signature()
  if not (G and G.jokers and G.jokers.cards) then return "" end
  local keys = {}
  for _, card in ipairs(G.jokers.cards) do
    local center = card and card.config and card.config.center
    keys[#keys + 1] = tostring(center and (center.key or center.name) or "?")
  end
  table.sort(keys)
  return table.concat(keys, "|")
end

function M.untagged_joker_count()
  if not (G and G.jokers and G.jokers.cards) then return 0 end
  local tags = (G.NEURO and G.NEURO.joker_intents) or {}
  local count = 0
  for _, card in ipairs(G.jokers.cards) do
    local sid = card and card.sort_id
    if sid and not (tags[sid] and tags[sid].tag) then count = count + 1 end
  end
  return count
end

local EDITION_FLAGS = { "foil", "holo", "polychrome", "negative" }
local function card_edition_tag(card)
  local e = card and card.edition
  if not e then return "" end
  if e.key then return tostring(e.key) end
  for _, k in ipairs(EDITION_FLAGS) do
    if e[k] then return k end
  end
  return "ed"
end

function M.joker_build_signature()
  if not (G and G.jokers and G.jokers.cards) then return "" end
  local parts = {}
  for i, card in ipairs(G.jokers.cards) do
    local center = card and card.config and card.config.center
    parts[i] = tostring(center and (center.key or center.name) or "?") .. "#" .. card_edition_tag(card)
  end
  return table.concat(parts, "|")  -- order preserved: reordering changes the signature
end

if _G.NEURO_TEST then
  M.live_odds = live_odds
  M.edition_readable = edition_readable
end

return M
