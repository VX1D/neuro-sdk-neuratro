local M = {}

local Utils = require("util.utils")
local NUMERIC_EFFECTS = require("facts.numeric_effects")
local NUMERIC_EFFECTS_BY_FIELD = {}
for _, e in ipairs(NUMERIC_EFFECTS) do NUMERIC_EFFECTS_BY_FIELD[e.field] = e end

local function live_area(a)
  return (a and a.cards and not a.REMOVED) and a or nil
end
function M.pack_area()
  if not G then return nil end
  return live_area(G.pack_cards)
end

local function center_of(card)
  return card and card.config and card.config.center or nil
end

local function center_key(card)
  local c = center_of(card)
  return c and c.key
end

local function card_set(card)
  local ability = card and card.ability
  local center = center_of(card)
  return (ability and ability.set) or (center and center.set) or ""
end

local function is_consumable_set(set)
  if type(set) ~= "string" or set == "" then return false end
  return SMODS.ConsumableTypes[set] ~= nil
end
local function is_consumable_card(card)
  return is_consumable_set(card_set(card))
    or type(card and card.ability and card.ability.consumeable) == "table"
end

function M.booster_kind(card)
  local center = center_of(card)
  return (center and center.kind) or ""
end

local function is_negative(card)
  return not not (card and card.edition and (card.edition.negative or card.edition.key == "e_negative"))
end

local function is_joker_like_card(card, area_name)
  local center = center_of(card)
  return area_name == "shop_jokers" or card_set(card) == "Joker" or (center and center.set == "Joker")
end

local function joker_count()      return ((G and G.jokers and G.jokers.cards and #G.jokers.cards) or 0) + ((G and G.GAME and tonumber(G.GAME.joker_buffer)) or 0) end
local function consumable_count() return ((G and G.consumeables and G.consumeables.cards and #G.consumeables.cards) or 0) + ((G and G.GAME and tonumber(G.GAME.consumeable_buffer)) or 0) end

local function joker_limit()      return (G and G.jokers and G.jokers.config and G.jokers.config.card_limit) or 5 end
local function consumable_limit() return (G and G.consumeables and G.consumeables.config and G.consumeables.config.card_limit) or 2 end
function M.hand_limit()       return (G and G.hand and G.hand.config and G.hand.config.card_limit) or 8 end
function M.highlight_limit()  return (G and G.hand and G.hand.config and G.hand.config.highlighted_limit) or 5 end

function M.score_per_hand(remaining, hands)
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

local function slot_status(count, limit) return { count = count, limit = limit, full = count >= limit } end
function M.joker_slot_status() return slot_status(joker_count(), joker_limit()) end
local function consumable_slot_status() return slot_status(consumable_count(), consumable_limit()) end

function M.slot_status_text(status)
  return string.format("slots %d/%d%s", status.count, status.limit, status.full and " FULL" or "")
end

function M.can_buy_card_space(card, area_name)
  local set = card_set(card)
  if set == "Booster" or area_name == "shop_booster" or area_name == "shop_vouchers" then
    return true
  end
  if is_consumable_card(card) then
    if is_negative(card) or has_consumable_space() then return true end
    local _, max_t = M.consumable_target_range(card)
    if max_t and max_t > 0 then return false end
    local ok, usable = pcall(card.can_use_consumeable, card, true, true)
    return ok and usable and true or false
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

local function consumable_usable_now(card)
  return require("facts.use_gate").usable(card)
end

function M.can_take_pack_card(card)
  if card and card.base and card.base.suit then
    return true
  end
  if is_consumable_card(card) then
    return consumable_usable_now(card)
  end
  if is_joker_like_card(card) then
    return has_joker_space_for(card)
  end
  return true
end

function M.consumable_target_range(card)
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

local function center_config(key)
  local center = G and G.P_CENTERS and G.P_CENTERS[key]
  local cfg = (type(center) == "table") and center.config or nil
  return type(cfg) == "table" and cfg or {}
end

local function cfg_num(key, field)
  return tonumber(center_config(key)[field]) or 0
end

local function numtext(v) return Utils.fmt_num(v) end
local function cfg_text(key, field) return numtext(cfg_num(key, field)) end

local function stat(rec, label_field, label, key, field, sign, unit, desc_sign)
  rec[label_field] = function() return label .. "(" .. sign .. cfg_text(key, field) .. unit .. ")" end
  rec.desc = function() return (desc_sign or sign) .. cfg_text(key, field) .. (unit == "c" and " Chips" or " Mult") end
  rec.fx = function() return sign .. cfg_text(key, field) .. unit end
  return rec
end

local LUCKY_MULT_ODDS = 5
local LUCKY_DOLLAR_ODDS = 15

-- Negative edition adds capacity according to card type: joker/consumable slots or hand size.
local NEGATIVE_EFFECT = {
  joker = function() return "Takes no slot (+" .. cfg_text("e_negative", "extra") .. " Joker slot)" end,
  consumable = function() return "Takes no slot (+" .. cfg_text("e_negative", "extra") .. " consumable slot)" end,
  playing = function() return "+" .. cfg_text("e_negative", "extra") .. " hand size" end,
}

local EDITIONS = {
  { test = function(e) return e.negative or e.key == "e_negative" end, name = "Negative",
    tag = "Negative(free_slot)",
    desc = function(kind) return NEGATIVE_EFFECT[kind or "joker"]() end,
    fx = "" },
  stat({ test = function(e) return e.polychrome end, name = "Polychrome" }, "tag", "Poly", "e_polychrome", "extra", "x", "m", "X"),
  stat({ test = function(e) return e.holo end, name = "Holographic" }, "tag", "Holo", "e_holo", "extra", "+", "m"),
  stat({ test = function(e) return e.foil end, name = "Foil" }, "tag", "Foil", "e_foil", "extra", "+", "c"),
}

local function find_test_match(list, subject)
  for _, e in ipairs(list) do
    if e.test(subject) then return e end
  end
  return nil
end

local function record_field(r, field, fallback, key)
  local v = r and resolve_field(r[field])
  if v then return v end
  return fallback and fallback(key) or nil
end

local function edition_record(edition)
  return type(edition) == "table" and find_test_match(EDITIONS, edition) or nil
end

local function edition_kind(card)
  if card and card.base and card.base.suit then return "playing" end
  if is_consumable_card(card) then return "consumable" end
  return "joker"
end

local function edition_desc(edition, kind)
  local r = edition_record(edition)
  local d = r and r.desc
  if type(d) == "function" then return d(kind) end
  return d
end

function M.edition_fx_short(edition) return record_field(edition_record(edition), "fx") or "" end

local function edition_name(edition)
  if type(edition) ~= "table" then return nil end
  local e = find_test_match(EDITIONS, edition)
  if e then return e.name end
  if type(edition.key) == "string" then return require("facts.display_names").center(edition.key, "Edition") end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  if edition.type and edition.type ~= "" then return require("facts.display_names").humanize_key(edition.type) end
  return nil
end

function M.edition_prose(card)
  local edition = card and card.edition
  local nm = edition_name(edition)
  if not nm then return "" end
  local d = edition_desc(edition, edition_kind(card))
  return d and (nm .. ": " .. d) or nm
end

local function odds_text(base, sep)
  local p = tonumber(G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal) or 1
  return numtext(p) .. sep .. numtext(base)
end
local function live_odds(base) return odds_text(base, " in ") end
local function odds_frac(base) return odds_text(base, "/") end

local REWRITERS = {
  { key = "j_vampire", short = "Vampire_strips_it", desc = "Vampire strips it" },
  { key = "j_midas_mask", short = "Midas_Mask_turns_a_face_card_Gold", desc = "Midas Mask turns a face card Gold" },
}

function M.owns_live_joker(key)
  local PublicCard = require("facts.public_card_identity")
  local concealed = false
  for i, j in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    if not PublicCard.is_public(j) then
      concealed = true
    elseif PublicCard.multiset_key(j, "jokers", i) == "center:" .. key and not j.debuff then
      return true
    end
  end
  if concealed then return nil end
  return false
end

local function scoring_rewriters()
  local out = {}
  for _, r in ipairs(REWRITERS) do
    if M.owns_live_joker(r.key) then out[#out + 1] = r end
  end
  return out
end

local function rewriter_list(field, sep)
  local parts = {}
  for _, r in ipairs(scoring_rewriters()) do parts[#parts + 1] = r[field] end
  return #parts > 0 and table.concat(parts, sep) or nil
end

local ENHANCEMENTS = {
  m_bonus = stat({ name = "Bonus", scored = true }, "short", "Bonus", "m_bonus", "bonus", "+", "c"),
  m_mult = stat({ name = "Mult", scored = true }, "short", "Mult", "m_mult", "mult", "+", "m"),
  m_wild = { name = "Wild", short = "Wild(counts_as_any_suit)", desc = "Can be used as any suit", fx = "" },
  m_glass = {
    name = "Glass", scored = true,
    short = function()
      return "Glass(x" .. cfg_text("m_glass", "Xmult") .. "m"
        .. (rewriter_list("short", "") and "" or "_always") .. "_then_"
        .. odds_frac(cfg_num("m_glass", "extra")) .. "_destroyed)"
    end,
    desc = function()
      return "x" .. cfg_text("m_glass", "Xmult") .. " Mult, "
        .. live_odds(cfg_num("m_glass", "extra")) .. " chance to break"
    end,
    fx = function() return "x" .. cfg_text("m_glass", "Xmult") .. "m" end,
  },
  m_steel = {
    name = "Steel",
    short = function() return "Steel(x" .. cfg_text("m_steel", "h_x_mult") .. "m_per_copy_held_not_played)" end,
    desc = function() return "x" .. cfg_text("m_steel", "h_x_mult") .. " Mult while in hand" end,
    fx = function() return "x" .. cfg_text("m_steel", "h_x_mult") .. "m" end,
  },
  m_stone = {
    name = "Stone", scored = true,
    short = function() return "Stone(no_suit_no_rank+" .. cfg_text("m_stone", "bonus") .. "c_always)" end,
    desc = function() return "+" .. cfg_text("m_stone", "bonus") .. " Chips, no rank/suit" end,
    fx = function() return "+" .. cfg_text("m_stone", "bonus") .. "c" end,
  },
  m_gold = {
    name = "Gold",
    short = function() return "Gold(" .. Utils.money_change(cfg_num("m_gold", "h_dollars")) .. "_held_EOround)" end,
    desc = function() return Utils.money(cfg_num("m_gold", "h_dollars")) .. " at end of round if held" end,
    fx = function() return Utils.money_change(cfg_num("m_gold", "h_dollars")) end,
  },
  m_lucky = {
    name = "Lucky", scored = true,
    short = function()
      return "Lucky(" .. odds_frac(LUCKY_MULT_ODDS) .. ":+" .. cfg_text("m_lucky", "mult")
        .. "m_and_" .. odds_frac(LUCKY_DOLLAR_ODDS) .. ":+" .. cfg_text("m_lucky", "p_dollars") .. "$)"
    end,
    desc = function()
      return live_odds(LUCKY_MULT_ODDS) .. " for +" .. cfg_text("m_lucky", "mult") .. " Mult, "
        .. live_odds(LUCKY_DOLLAR_ODDS) .. " for " .. Utils.money(cfg_num("m_lucky", "p_dollars"))
    end,
    fx = "",
  },
}

for _, r in pairs(ENHANCEMENTS) do
  if r.scored then
    local short, desc = r.short, r.desc
    r.short = function()
      local base, who = resolve_field(short), rewriter_list("short", "_and_")
      if not who then return base end
      return (base:gsub("%)$", ";if_played_" .. who .. "_first)"))
    end
    r.desc = function()
      local base, who = resolve_field(desc), rewriter_list("desc", " and ")
      if not who then return base end
      return base .. " -- if played, " .. who .. " before it scores"
    end
  end
end

function M.edition_tag(edition)
  if type(edition) ~= "table" then
    return (edition ~= nil) and tostring(edition) or ""
  end
  local e = find_test_match(EDITIONS, edition)
  if e then return resolve_field(e.tag) end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  return ""
end


local RARITY_NAMES = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Legendary" }

local function misc_label(key)
  local misc = G and G.localization and G.localization.misc
  local text = misc and ((misc.labels and misc.labels[key]) or (misc.dictionary and misc.dictionary[key]))
  if type(text) == "string" and text ~= "" then return text end
  return nil
end

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
  return misc_label("k_" .. tostring(rarity):lower())
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
function M.rarity_name(rarity)
  if rarity == nil then return "Common" end
  return RARITY_NAMES[rarity] or live_rarity_name(rarity) or humanized_rarity(rarity)
end

local function enh_field(key, field, fallback)
  return record_field(key and ENHANCEMENTS[key], field, fallback, key)
end
function M.enhancement_name(key)
  return enh_field(key, "name", function(k)
    return type(k) == "string" and require("facts.display_names").center(k, "Enhanced") or nil
  end)
end
function M.enhancement_short(key) return enh_field(key, "short", function(k) return k end) end
function M.enhancement_fx_short(key) return enh_field(key, "fx") or "" end

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

local function gold_dollars() return seal_dollars("Gold") end
M.gold_seal_dollars = gold_dollars

local SEALS = {
  Red               = { name = "Red", fx = "x2", short = "Red(x2_trigger_scored_and_held)", desc = "Retriggers this card once: it scores twice, and its held-in-hand effects (Steel xMult, Gold Card's end-of-round $) also fire twice" },
  Blue              = { name = "Blue", fx = "Planet", short = "Blue(hold_in_hand=free_planet_EOround)", desc = "If held at end of round, creates the Planet for your last-played poker hand (needs a free consumable slot)" },
  Gold              = {
    name = "Gold",
    fx = function() return Utils.money_change(gold_dollars()) end,
    short = function() return "Gold(" .. Utils.money_change(gold_dollars()) .. "_when_scored)" end,
    desc = function() return "Earn " .. Utils.money(gold_dollars()) .. " when this card is scored" end,
  },
  Purple            = { name = "Purple", fx = "Tarot", short = "Purple(discard=free_tarot)", desc = "Creates a Tarot card when discarded (needs a free consumable slot)" },
}

local function seal_label(seal)
  return misc_label(tostring(seal):lower() .. "_seal")
end

local function seal_record(seal)
  local r = SEALS[seal]
  if r then return r end
  if not live_seal(seal) then return nil end
  local name = seal_label(seal) or tostring(seal)
  local d = seal_dollars(seal)
  return {
    name = name,
    fx = d and Utils.money_change(d) or "",
    short = d and (name .. "(" .. Utils.money_change(d) .. "_when_scored)") or (name .. "(seal)"),
    desc = d and ("Earn " .. Utils.money(d) .. " when this card is scored") or nil,
  }
end


local function enhancement_key(card)
  if type(card) ~= "table" then return nil end
  local ab = card.ability
  if ab and ab.enhancement and ENHANCEMENTS[ab.enhancement] then return ab.enhancement end
  local key = center_key(card)
  if key and ENHANCEMENTS[key] then return key end
  return nil
end

local function has_no_rank(card)
  if type(card) ~= "table" then return false end
  local ok, v = pcall(SMODS.has_no_rank, card)
  return ok and v and true or false
end

function M.has_no_suit(card)
  if type(card) ~= "table" then return false end
  local ok, v = pcall(SMODS.has_no_suit, card)
  return ok and v and true or false
end

local VALUE_ID = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  ["10"] = 10, Jack = 11, Queen = 12, King = 13, Ace = 14,
}
-- Rankless cards return a fresh random negative id each call, so their ids cannot be compared.
function M.rank_id(card)
  if type(card) ~= "table" or has_no_rank(card) then return nil end
  if type(card.get_id) == "function" then
    local ok, id = pcall(card.get_id, card)
    if ok and type(id) == "number" then return id end
  end
  return card.base and VALUE_ID[tostring(card.base.value)] or nil
end

function M.held_after_play(selection)
  local held = G and G.hand and G.hand.cards
  if type(held) ~= "table" or #held == 0 then return nil, false end
  if type(selection) ~= "table" or #selection == 0 then return held, false end
  local played = {}
  for _, card in ipairs(selection) do played[card] = true end
  local remaining = {}
  for _, card in ipairs(held) do
    if not played[card] then remaining[#remaining + 1] = card end
  end
  -- The Hook discards two random held cards before scoring, making this list only a ceiling.
  if require("facts.boss.model").active_key() == "bl_hook" then
    return remaining, false
  end
  return remaining, true
end

function M.deck_has_stone()
  local cards = G and G.playing_cards
  if type(cards) ~= "table" then return false end
  for _, c in ipairs(cards) do
    if enhancement_key(c) == "m_stone" then return true end
  end
  return false
end

local function seal_getter(field, fallback, none)
  return function(seal)
    if type(seal) == "table" then seal = seal.name or seal.key end
    if not seal then return none end
    return record_field(seal_record(seal), field, fallback, seal) or none
  end
end
local seal_name = seal_getter("name", tostring)
M.seal_short = seal_getter("short", tostring)
local seal_desc = seal_getter("desc")
M.seal_fx_short = seal_getter("fx", nil, "")
local function rental_rate()
  return (G and G.GAME and tonumber(G.GAME.rental_rate)) or 3
end
function M.sticker_fx_short(key)
  if key == "eternal" then return "no-sell" end
  if key == "rental" then return Utils.money(-rental_rate()) .. "/rd" end
  if key == "perishable" then return "debuff" end
  return ""
end

function M.card_modifier_desc(card)
  if type(card) ~= "table" then return "" end
  local parts = {}
  local ek = enhancement_key(card)
  if ek then
    local nm = enh_field(ek, "name")
    if nm then
      local d = enh_field(ek, "desc")
      parts[#parts + 1] = d and (nm .. ": " .. d) or nm
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
      local d = edition_desc(card.edition, edition_kind(card))
      parts[#parts + 1] = d and (nm .. ": " .. d) or nm
    end
  end
  return table.concat(parts, "  ")
end

local _template_ability = setmetatable({}, { __mode = "k" })

local function joker_template_ability(c)
  local key = center_key(c)
  local center = key and G and G.P_CENTERS and G.P_CENTERS[key]
  if not center then return {} end
  if type(center.ability) == "table" then return center.ability end
  local built = _template_ability[center]
  if built then return built end
  local cfg = type(center.config) == "table" and center.config or {}
  built = {
    x_mult = cfg.Xmult or cfg.x_mult or 1,
    h_mult = cfg.h_mult or 0,
    h_chips = cfg.h_chips or 0,
    t_mult = cfg.t_mult or 0,
    t_chips = cfg.t_chips or 0,
    extra = cfg.extra,
  }
  _template_ability[center] = built
  return built
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

local _fx_parts = {}

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
    local parts, n = _fx_parts, 0
    for _, spec in ipairs(joker_registry().extra_specs(key)) do
      if NUMERIC_EFFECTS.read(ab, spec) == NUMERIC_EFFECTS.read(tb, spec) then
        local label = NUMERIC_EFFECTS.label(ab, spec)
        if label ~= nil then n = n + 1; parts[n] = label end
      end
    end
    return table.concat(parts, "; ", 1, n)
  end
  return ""
end

local function area_has_negative(area, joker_only)
  for _, c in ipairs(area and area.cards or {}) do
    if not M.is_hidden(c) and is_negative(c) and (not joker_only or is_joker_like_card(c)) then return true end
  end
  return false
end

function M.joker_fx_line(card, description)
  if type(description) == "string" and description ~= "" then return "" end
  return joker_fx(card)
end

M.joker_fx = joker_fx
M.card_set = card_set
M.is_consumable_set = is_consumable_set
M.is_consumable_card = is_consumable_card
M.area_has_negative = area_has_negative
M.area_has_negative_joker = function(area) return area_has_negative(area, true) end
M.is_joker_like_card = is_joker_like_card
M.joker_limit = joker_limit
M.consumable_slot_status = consumable_slot_status
function M.order_matters()
  if not (G and G.jokers and G.jokers.cards) then return false end
  local PublicCard = require("facts.public_card_identity")
  for _, card in ipairs(G.jokers.cards) do
    if type(card) == "table" and not PublicCard.is_public(card) then return false end
  end
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

M.center_config_num = cfg_num
M.consumable_usable_now = consumable_usable_now
M.has_consumable_space = has_consumable_space
M.odds_frac = odds_frac
M.ENHANCEMENTS = ENHANCEMENTS
M.SEALS = SEALS
M.EDITIONS = EDITIONS
M.edition_name = edition_name
M.edition_desc = edition_desc
M.copy_joker_kind = copy_joker_kind
M.enhancement_key = enhancement_key
M.has_no_rank = has_no_rank
M.is_negative = is_negative
M.seal_name = seal_name
M.center = center_of
M.center_key = center_key
M.resolve_field = resolve_field

local function planet_hand(card)
  local ht = card and card.ability and card.ability.consumeable and card.ability.consumeable.hand_type
  if not ht then
    local ctr = center_of(card)
    ht = ctr and ctr.config and ctr.config.hand_type
  end
  return ht, ht and require("facts.hand_facts").hand_values(ht)
end

function M.planet_run_state_suffix(card)
  if card_set(card) ~= "Planet" then return "" end
  local ht, h = planet_hand(card)
  if not h then return "" end
  return string.format("; played %s %dx this run (lvl %d)", tostring(ht), h.played, h.level)
end

function M.idle_planet_note(card)
  if M.is_hidden(card) or card_set(card) ~= "Planet" or not consumable_slot_status().full then return nil end
  local ht, h = planet_hand(card)
  if not h or h.played > 0 then return nil end
  return string.format("levels %s, which you have not played this run; selling it (%s) frees a consumable slot",
    tostring(ht), Utils.money(card.sell_cost))
end

local function is_face_down(card)
  return not not (card and card.facing == "back")
end

function M.is_hidden(card)
  return is_face_down(card) or not not (card and card.ability and card.ability.wheel_flipped)
end

local function is_unplayed(card)
  if type(card) ~= "table" then return false end
  if G and G.deck and card.area == G.deck then return true end
  return not not (type(card.ability) == "table" and card.ability.wheel_flipped)
end

local function unplayed_off_pile(card)
  if type(card) ~= "table" or (G and G.deck and card.area == G.deck) then return false end
  return is_unplayed(card) or (G and G.hand and card.area == G.hand and is_face_down(card)) or false
end

function M.is_aggregate_public(card)
  local area = type(card) == "table" and card.area or nil
  if not (G and area) then return false end
  if not (area == G.deck or area == G.discard or area == G.play) then return false end
  return not unplayed_off_pile(card)
end

function M.is_composition_public(card)
  local area = type(card) == "table" and card.area or nil
  if not (G and area) then return false end
  return area == G.deck or area == G.discard or area == G.play or area == G.hand
end

function M.unplayed_pool()
  local dk = G and G.deck and G.deck.cards
  if type(dk) ~= "table" then return nil, 0, {} end
  local pool, concealed, where = {}, 0, { hand = 0, discard = 0, other = 0 }
  for _, c in ipairs(dk) do pool[#pool + 1] = c end
  for _, area in ipairs({ G.hand, G.discard, G.play }) do
    for _, c in ipairs((type(area) == "table" and area.cards) or {}) do
      if unplayed_off_pile(c) or (area == G.hand and is_face_down(c)) then
        pool[#pool + 1] = c
        concealed = concealed + 1
        local k = (area == G.hand and "hand") or (area == G.discard and "discard") or "other"
        where[k] = where[k] + 1
      end
    end
  end
  return pool, concealed, where
end

local function center_id(card)
  local center = center_of(card)
  return tostring(center and (center.key or center.name) or "?")
end

local function untagged_joker_indices()
  local out = {}
  if not (G and G.jokers and type(G.jokers.cards) == "table") then return out end
  local tags = (G.NEURO and G.NEURO.joker_intents) or {}
  for i, card in ipairs(G.jokers.cards) do
    local sid = card and card.sort_id
    if sid and not (tags[sid] and tags[sid].tag) then out[#out + 1] = i end
  end
  return out
end

M.untagged_joker_indices = untagged_joker_indices

function M.untagged_joker_count()
  return #untagged_joker_indices()
end

function M.untagged_joker_prose()
  local ix = untagged_joker_indices()
  if #ix == 0 then return nil end
  local list = tostring(ix[1])
  for i = 2, #ix do list = list .. (i == #ix and " and " or ", ") .. ix[i] end
  return "Jokers that carry no tag: " .. list
end

local function card_edition_tag(card)
  local e = card and card.edition
  return e and tostring(e.key) or ""
end

local function joker_signature(build)
  if not (G and G.jokers and G.jokers.cards) then return "" end
  local PublicCard = require("facts.public_card_identity")
  local parts = {}
  for i, card in ipairs(G.jokers.cards) do
    if type(card) == "table" and not PublicCard.is_public(card) then
      parts[i] = "hidden:" .. tostring(i)
    else
      parts[i] = build and (center_id(card) .. "#" .. card_edition_tag(card)) or center_id(card)
    end
  end
  if not build then table.sort(parts) end
  return table.concat(parts, "|")
end
function M.joker_build_signature() return joker_signature(true) end
function M.joker_composition_signature() return joker_signature(false) end

if _G.NEURO_TEST then
  M.is_face_down = is_face_down
end

local RARITY_TIER = {}
for tier, name in pairs(RARITY_NAMES) do RARITY_TIER[name] = tier end
function M.rarity_tier(rarity)
  if type(rarity) == "string" then return RARITY_TIER[rarity] or tonumber(rarity) end
  return tonumber(rarity)
end

return M
