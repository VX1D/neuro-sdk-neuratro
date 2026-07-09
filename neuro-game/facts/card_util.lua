local M = {}

local function pack_area()
  return G and (G.pack_cards or G.booster_pack)
end

local function card_set(card)
  local ability = card and card.ability
  local center = card and card.config and card.config.center
  return (ability and ability.set) or (center and center.set) or ""
end

-- booster_kind reads game-native center.kind (card_set collapses every pack to "Booster")
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
  local pools = center and center.pools
  return area_name == "shop_jokers"
    or set == "Joker"
    or set == "neurJoker"
    or (center and center.set == "Joker")
    or (type(pools) == "table" and pools.neurJoker)
end

local function joker_count()      return (G and G.jokers and G.jokers.cards and #G.jokers.cards) or 0 end
local function consumable_count() return (G and G.consumeables and G.consumeables.cards and #G.consumeables.cards) or 0 end

local function joker_limit()      return (G and G.jokers and G.jokers.config and G.jokers.config.card_limit) or 5 end
local function consumable_limit() return (G and G.consumeables and G.consumeables.config and G.consumeables.config.card_limit) or 2 end
local function hand_limit()       return (G and G.hand and G.hand.config and G.hand.config.card_limit) or 8 end
local function highlight_limit()  return (G and G.hand and G.hand.config and G.hand.config.highlighted_limit) or 5 end

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
  if set == "Tarot" or set == "Planet" or set == "Spectral" then
    -- a negative consumable bumps consumeables card_limit on add, so it never needs a free slot
    if is_negative(card) or has_consumable_space() then return true end
    -- full board still buyable via buy-and-use (shop_handlers.lua skips the slot check), but only non-hand-targeting consumables usable now qualify
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

-- Aura hand-targets by center key (card.lua:1865), not consumeable.max_highlighted; without this it looks non-targeting and gets skipped in packs
local NAMED_HAND_TARGET = {
  c_aura = { min = 1, max = 1 },
}
local function named_hand_target(card)
  local key = card and card.config and card.config.center and card.config.center.key
  return key and NAMED_HAND_TARGET[key] or nil
end

local function consumable_usable_now(card)
  if named_hand_target(card) then return true end
  local c = card and card.ability and card.ability.consumeable
  local max_h = (type(c) == "table") and tonumber(c.max_highlighted) or nil
  if max_h and max_h > 0 then return true end
  if type(card.can_use_consumeable) == "function" then
    -- (true, true) skips the transient booster-open state lock, else a usable creator reads as unusable while a pack is open
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
  local set = card_set(card)
  if set == "Tarot" or set == "Planet" or set == "Spectral" then
    return consumable_usable_now(card)
  end
  if is_joker_like_card(card) then
    return has_joker_space_for(card)
  end
  return true
end

local function consumable_target_range(card)
  -- Aura declares no max_highlighted, so surface its real min/max here too
  local nt = named_hand_target(card)
  if nt then return nt.min, nt.max end
  local c = card and card.ability and card.ability.consumeable
  if type(c) ~= "table" then return nil, nil end
  local max = tonumber(c.max_highlighted)
  -- no max means no hand selection: min is meaningless, so don't imply "select 1"
  if not max then return nil, nil end
  local min = tonumber(c.min_highlighted) or 1
  return min, max
end

local EDITIONS = {
  { test = function(e) return e.negative or e.key == "e_negative" end, name = "Negative",     tag = "Negative(free_slot)", desc = "Takes no slot (+1 joker/consumable slot)" },
  { test = function(e) return e.polychrome end,                        name = "Polychrome",   tag = "Poly(x1.5m)", desc = "X1.5 Mult" },
  { test = function(e) return e.holo end,                              name = "Holographic",  tag = "Holo(+10m)", desc = "+10 Mult" },
  { test = function(e) return e.foil end,                              name = "Foil",         tag = "Foil(+50c)", desc = "+50 Chips" },
  { test = function(e) return e.filtered end,                          name = "Filtered",     tag = "Filtered(50/50:retrigger_or_debuff_EOround)", desc = "50/50 to retrigger or debuff at end of round" },
}

local function edition_desc(edition)
  if type(edition) ~= "table" then return nil end
  for _, e in ipairs(EDITIONS) do if e.test(edition) then return e.desc end end
  return nil
end

local function edition_name(edition)
  if type(edition) ~= "table" then return nil end
  for _, e in ipairs(EDITIONS) do if e.test(edition) then return e.name end end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  if edition.type and edition.type ~= "" then return tostring(edition.type) end
  if edition.key then return (tostring(edition.key):gsub("^e_", "")) end
  return nil
end

local function prob_numerator()
  return (G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal) or 1
end
local function live_odds(base)
  return tostring(prob_numerator()) .. " in " .. tostring(base)
end
local function odds_frac(base)
  return tostring(prob_numerator()) .. "/" .. tostring(base)
end

local ENHANCEMENTS = {
  m_bonus = { name = "Bonus", short = "Bonus(+30c)", desc = "+30 Chips", bonus_chips = 30 },
  m_mult  = { name = "Mult", short = "Mult(+4m)", desc = "+4 Mult" },
  m_wild  = { name = "Wild", short = "Wild(counts_as_any_suit)", desc = "Can be used as any suit" },
  m_glass = {
    name = "Glass",
    short = function() return "Glass(x2m_always_then_" .. odds_frac(4) .. "_destroyed)" end,
    desc = function() return "x2 Mult, " .. live_odds(4) .. " chance to break" end,
    x_mult = 2,
  },
  m_steel = { name = "Steel", short = "Steel(x1.5m_per_copy_held_not_played)", desc = "x1.5 Mult while in hand", x_mult = 1.5 },
  m_stone = { name = "Stone", short = "Stone(no_suit_no_rank+50c_always)", desc = "+50 Chips, no rank/suit", bonus_chips = 50 },
  m_gold  = { name = "Gold", short = "Gold(+$3_held_EOround)", desc = "$3 at end of round if held" },
  m_lucky = {
    name = "Lucky",
    short = function() return "Lucky(" .. odds_frac(5) .. ":+20m_or_" .. odds_frac(15) .. ":+20$)" end,
    desc = function() return live_odds(5) .. " for +20 Mult, " .. live_odds(15) .. " for $20" end,
  },
  m_twin  = { name = "Twin", short = "Twin(+15c+2m)", desc = "+15 Chips, +2 Mult" },
  m_dono  = { name = "Donation", short = "Dono($2_scored_or_xmult_if_Highlighted)", desc = "$2 scored or xmult if highlighted" },
  m_glorp = { name = "Glorpy", short = "Glorpy(breaks_EOround)", desc = "Breaks at end of round" },
  m_blood = { name = "Bloody", short = "Bloody(1/3_spread_to_adjacent_when_played)", desc = "1-in-3 chance to spread to adjacent cards after being played" },
}

local function edition_tag(edition)
  if type(edition) ~= "table" then
    return (edition ~= nil) and tostring(edition) or ""
  end
  for _, e in ipairs(EDITIONS) do if e.test(edition) then return e.tag end end
  if edition.name and edition.name ~= "" then return tostring(edition.name) end
  return ""
end

local RARITY_NAMES = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Legendary" }
-- key-based, not name matching (which mislabels localized/renamed jokers)
local COPY_JOKER_KEYS = { j_blueprint = "blueprint", j_brainstorm = "brainstorm" }
local function copy_joker_kind(card)
  local key = card and card.config and card.config.center and card.config.center.key
  return key and COPY_JOKER_KEYS[key] or nil
end
local function is_copy_joker(card)
  return copy_joker_kind(card) ~= nil
end

local function rarity_name(rarity)
  if rarity == nil then return "Common" end
  return RARITY_NAMES[rarity] or tostring(rarity)
end

local function resolve_field(v)
  if type(v) == "function" then return v() end
  return v
end
local function enhancement_record(key)
  local r = key and ENHANCEMENTS[key]
  if not r then return nil end
  if type(r.short) ~= "function" and type(r.desc) ~= "function" then return r end
  return {
    name = r.name,
    short = resolve_field(r.short),
    desc = resolve_field(r.desc),
    bonus_chips = r.bonus_chips,
    x_mult = r.x_mult,
  }
end
local function enhancement_name(key)
  local r = key and ENHANCEMENTS[key]
  return r and r.name or key
end
local function enhancement_short(key)
  local r = key and ENHANCEMENTS[key]
  return r and resolve_field(r.short) or key
end

local SEALS = {
  Red               = { name = "Red", short = "Red(x2_trigger_when_scored)", desc = "Retriggers when scored (this card scores twice)" },
  Blue              = { name = "Blue", short = "Blue(hold_in_hand=free_planet_EOround)", desc = "Creates a Planet card if held at end of round" },
  Gold              = { name = "Gold", short = "Gold(+$3_when_scored)", desc = "Earn $3 when this card is scored" },
  Purple            = { name = "Purple", short = "Purple(discard=free_tarot)", desc = "Creates a Tarot card when discarded" },
  shoomiminion_seal = { name = "Shoominion", short = "Shoominion(destroyed=spawns_2_copies)", desc = "When destroyed, spawns 2 copies" },
  osu_seal          = { name = "Osu!", short = "Osu!(+5m_per_play_reset_on_discard)", desc = "+5 Mult each play, resets on discard" },
}

local function enhancement_key(card)
  if type(card) ~= "table" then return nil end
  local ab = card.ability
  if ab and ab.enhancement and ENHANCEMENTS[ab.enhancement] then return ab.enhancement end
  local key = card.config and card.config.center and card.config.center.key
  if key and ENHANCEMENTS[key] then return key end
  return nil
end

local function seal_name(seal)
  if type(seal) == "table" then seal = seal.name or seal.key end
  if not seal then return nil end
  local r = SEALS[seal]
  return r and r.name or tostring(seal)
end
local function seal_short(seal)
  if type(seal) == "table" then seal = seal.name or seal.key end
  if not seal then return nil end
  local r = SEALS[seal]
  return r and r.short or tostring(seal)
end
local function seal_desc(seal)
  if type(seal) == "table" then seal = seal.name or seal.key end
  if not seal then return nil end
  local r = SEALS[seal]
  return r and r.desc or nil
end

-- our own tables, not the game tooltip: generate_UIBox_ability_table drops seal/edition on freshly-spawned pack/deck cards
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
  local key = c and c.config and c.config.center and c.config.center.key
  local center = key and G and G.P_CENTERS and G.P_CENTERS[key]
  if not center then return {} end
  if type(center.ability) == "table" then return center.ability end
  local cfg = type(center.config) == "table" and center.config or {}
  return {
    x_mult = cfg.Xmult or cfg.x_mult or 1,
    h_mult = cfg.h_mult or 0,
    h_mod = cfg.h_mod or 0,
    t_mult = cfg.t_mult or 0,
    t_chips = cfg.t_chips or 0,
    d_mult = cfg.d_mult or 0,
    extra = cfg.extra,
  }
end

local function joker_fx(c)
  local center = c and c.config and c.config.center or {}
  local key = center.key
  if not (key and G and G.P_CENTERS and G.P_CENTERS[key]) then return "" end
  local ab = c and c.ability or {}
  local tb = joker_template_ability(c)
  if ab.x_mult and ab.x_mult > 1 then
    if ab.x_mult == (tb.x_mult or 1) then return "x" .. ab.x_mult end
  end
  if ab.h_mult and ab.h_mult > 0 then
    local base = tb.h_mult or 0
    if ab.h_mult == base then return "+" .. ab.h_mult .. " Mult" end
  end
  if ab.h_mod and ab.h_mod > 0 then
    local base = tb.h_mod or 0
    if ab.h_mod == base then return "+" .. ab.h_mod .. " Chips" end
  end
  if ab.t_mult and ab.t_mult > 0 then
    local base = tb.t_mult or 0
    if ab.t_mult == base then return "+" .. ab.t_mult .. " Mult" end
  end
  if ab.t_chips and ab.t_chips > 0 then
    local base = tb.t_chips or 0
    if ab.t_chips == base then return "+" .. ab.t_chips .. " Chips" end
  end
  if ab.d_mult and ab.d_mult > 0 then
    local base = tb.d_mult or 0
    if ab.d_mult == base then return "+" .. ab.d_mult .. " Mult" end
  end
  if ab.extra and type(ab.extra) == "table" then
    local te = type(tb.extra) == "table" and tb.extra or {}
    if ab.extra.x_mult and ab.extra.x_mult > 1 and ab.extra.x_mult == (te.x_mult or 1) then
      return "x" .. ab.extra.x_mult
    end
    if ab.extra.mult and ab.extra.mult > 0 and ab.extra.mult == (te.mult or 0) then
      return "+" .. ab.extra.mult .. " Mult"
    end
    if ab.extra.chips and ab.extra.chips > 0 and ab.extra.chips == (te.chips or 0) then
      return "+" .. ab.extra.chips .. " Chips"
    end
    if ab.extra.money and ab.extra.money > 0 and ab.extra.money == (te.money or 0) then
      return "+$" .. ab.extra.money
    end
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

M.joker_fx = joker_fx
M.card_set = card_set
M.booster_kind = booster_kind
M.is_negative = is_negative
M.area_has_negative = area_has_negative
M.is_joker_like_card = is_joker_like_card
M.has_consumable_space = has_consumable_space
M.pack_area = pack_area
M.joker_count = joker_count
M.consumable_count = consumable_count
M.joker_limit = joker_limit
M.consumable_limit = consumable_limit
M.hand_limit = hand_limit
M.highlight_limit = highlight_limit
M.joker_slot_status = joker_slot_status
M.consumable_slot_status = consumable_slot_status
M.slot_status_text = slot_status_text
M.can_buy_card_space = can_buy_card_space
M.can_take_pack_card = can_take_pack_card
M.consumable_usable_now = consumable_usable_now
M.has_blocked_consumable = has_blocked_consumable
M.consumable_target_range = consumable_target_range
M.live_odds = live_odds
M.ENHANCEMENTS = ENHANCEMENTS
M.SEALS = SEALS
M.edition_name = edition_name
M.edition_tag = edition_tag
M.rarity_name = rarity_name
M.is_copy_joker = is_copy_joker
M.copy_joker_kind = copy_joker_kind
M.enhancement_record = enhancement_record
M.enhancement_key = enhancement_key
M.enhancement_name = enhancement_name
M.enhancement_short = enhancement_short
M.seal_name = seal_name
M.seal_short = seal_short
M.seal_desc = seal_desc
M.edition_desc = edition_desc
M.card_modifier_desc = card_modifier_desc

return M
