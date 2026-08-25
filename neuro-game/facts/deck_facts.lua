local DeckNames = require("facts.deck_names")
local Utils = require("util.utils")
local get_back_display_name = DeckNames.get_back_display_name

local M = {}

M.DECK_INFO = {
  ["Red Deck"]       = "+1 discard per round. ",
  ["Blue Deck"]      = "+1 hand per round. ",
  ["Yellow Deck"]    = "Started with +$10. Standard 52-card pool, no composition changes. ",
  ["Green Deck"]     = "At end of round: +$2 per remaining hand, +$1 per remaining discard. No interest. ",
  ["Black Deck"]     = "+1 joker slot (6 total), -1 hand per round. ",
  ["Magic Deck"]     = "Crystal Ball voucher active (+1 consumable slot). Started with 2 Fool tarots (copy last Tarot or Planet used). ",
  ["Nebula Deck"]    = "Telescope voucher active (Celestial packs always show your most played hand's planet), -1 consumable slot. ",
  ["Ghost Deck"]     = "Spectral cards may appear in shop and from packs. Started with Hex spectral (adds Polychrome to a random joker and destroys all your other jokers). ",
  ["Zodiac Deck"]    = "Tarot Merchant, Planet Merchant, and Overstock vouchers all active: the shop shows an extra item slot (Overstock) and Tarot/Planet cards appear in the shop more often. ",
  ["Plasma Deck"]    = "Chips and mult are each set to floor((chips+mult)/2) before scoring: score = floor((chips+mult)/2)^2. Blind targets are x2 base. ",
  ["Erratic Deck"]   = "All ranks and suits were randomized at start. ",
  ["Abandoned Deck"] = "No face cards (J/Q/K) in deck. 40 cards, 10 per suit. Straights only span A-5 through 6-10. ",
  ["Painted Deck"]   = "+2 hand size (see 10 cards), -1 joker slot. ",
  ["Checkered Deck"] = "Only Spades and Hearts (Clubs became Spades, Diamonds became Hearts): 4 copies of each rank -- 2 Spades and 2 Hearts (52 cards). ",
  ["Anaglyph Deck"]  = "Earn a Double Tag after every Boss Blind (gives copy of next tag). Standard 52-card pool. ",
}

M.HUD_INFO = {
  ["Red Deck"]       = "+1 discard per round",
  ["Blue Deck"]      = "+1 hand per round",
  ["Yellow Deck"]    = "started with +$10",
  ["Green Deck"]     = "cash per unused hand and discard, no interest",
  ["Black Deck"]     = "+1 joker slot, -1 hand",
  ["Magic Deck"]     = "+1 consumable slot, started with 2 Fools",
  ["Nebula Deck"]    = "Telescope active, -1 consumable slot",
  ["Ghost Deck"]     = "spectral cards can appear, started with Hex",
  ["Zodiac Deck"]    = "Tarot, Planet and Overstock vouchers active",
  ["Plasma Deck"]    = "chips and mult balance before scoring, x2 blind size",
  ["Erratic Deck"]   = "random ranks and suits",
  ["Abandoned Deck"] = "no face cards, 40 cards",
  ["Painted Deck"]   = "+2 hand size, -1 joker slot",
  ["Checkered Deck"] = "only Spades and Hearts",
  ["Anaglyph Deck"]  = "Double Tag after every Boss Blind",
}

function M.short_desc(b)
  if type(b) ~= "table" then return nil end
  local c = b.config or {}
  local parts = {}
  if c.discards and c.discards ~= 0 then parts[#parts+1] = string.format("%+d discard", c.discards) end
  if c.hands and c.hands ~= 0 then parts[#parts+1] = string.format("%+d hand", c.hands) end
  if c.dollars and c.dollars ~= 0 then parts[#parts+1] = string.format("%s$%d start", c.dollars > 0 and "+" or "-", math.abs(c.dollars)) end
  if c.extra_hand_bonus and c.extra_hand_bonus ~= 0 then parts[#parts+1] = string.format("+$%d per remaining hand", c.extra_hand_bonus) end
  if c.extra_discard_bonus and c.extra_discard_bonus ~= 0 then parts[#parts+1] = string.format("+$%d per remaining discard", c.extra_discard_bonus) end
  if c.joker_slot and c.joker_slot ~= 0 then parts[#parts+1] = string.format("%+d joker slot", c.joker_slot) end
  if c.hand_size and c.hand_size ~= 0 then parts[#parts+1] = string.format("%+d hand size", c.hand_size) end
  if c.consumable_slot and c.consumable_slot ~= 0 then parts[#parts+1] = string.format("%+d consumable slot", c.consumable_slot) end
  if c.ante_scaling and c.ante_scaling ~= 1 then parts[#parts+1] = string.format("x%s base blind size", tostring(c.ante_scaling)) end
  if c.remove_faces then parts[#parts+1] = "no face cards" end
  if c.randomize_rank_suit then parts[#parts+1] = "random ranks+suits" end
  if c.no_interest then parts[#parts+1] = "no interest" end
  if c.voucher then parts[#parts+1] = "starts with voucher" end
  if c.consumables then parts[#parts+1] = "starts with consumables" end
  if c.vouchers then parts[#parts+1] = "starts with vouchers" end
  if c.spectral_rate then parts[#parts+1] = "spectral cards in shop" end
  if #parts == 0 and b.loc_txt and type(b.loc_txt) == "table" then
    local desc = b.loc_txt.description or b.loc_txt.text
    if type(desc) == "table" then
      for _, line in ipairs(desc) do
        local clean = Utils.clean_plain(line)
        if clean and clean ~= "" then parts[#parts+1] = clean end
      end
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

local KEY_TO_NAME = {
  b_red = "Red Deck", b_blue = "Blue Deck", b_yellow = "Yellow Deck", b_green = "Green Deck",
  b_black = "Black Deck", b_magic = "Magic Deck", b_nebula = "Nebula Deck", b_ghost = "Ghost Deck",
  b_zodiac = "Zodiac Deck", b_plasma = "Plasma Deck", b_erratic = "Erratic Deck",
  b_abandoned = "Abandoned Deck", b_painted = "Painted Deck", b_checkered = "Checkered Deck",
  b_anaglyph = "Anaglyph Deck",
}

local function resolve(back)
  local center = DeckNames.deck_center_of(back)
  local key = (center and center.key) or (type(back) == "table" and back.key) or nil
  local name = (key and KEY_TO_NAME[key])
    or (center and get_back_display_name(center))
    or (type(back) == "table" and back.name) or ""
  return center, name
end

function M.describe_deck(back)
  local center, name = resolve(back)
  return M.DECK_INFO[name] or (center and M.short_desc(center)) or M.short_desc(back)
end

function M.describe_deck_hud(back)
  local center, name = resolve(back)
  return M.HUD_INFO[name]
    or (center and M.short_desc(center)) or M.short_desc(back)
    or M.DECK_INFO[name]
end

M.STAKE_INFO = {
  { key = "stake_white",  effect = "none (baseline difficulty)" },
  { key = "stake_red",    effect = "Small Blind pays no reward" },
  { key = "stake_green",  effect = "score requirements scale up faster each ante" },
  { key = "stake_black",  effect = "Eternal Jokers can appear in the shop" },
  { key = "stake_blue",   effect = "-1 discard per round" },
  { key = "stake_purple", effect = "score requirements scale up even faster" },
  { key = "stake_orange", effect = "Perishable Jokers can appear in the shop" },
  { key = "stake_gold",   effect = "Rental Jokers can appear in the shop" },
}

local STAKE_EFFECT_BY_KEY = {}
for _, s in ipairs(M.STAKE_INFO) do STAKE_EFFECT_BY_KEY[s.key] = s.effect end

function M.stake_effect_text(key)
  return key and STAKE_EFFECT_BY_KEY[key] or nil
end

function M.list_selectable_backs()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back
  if type(pool) ~= "table" then return {} end
  local rows = {}
  for _, deck in ipairs(pool) do
    if type(deck) == "table" and deck.unlocked ~= false then
      local key = tostring(deck.key or deck.name or "?")
      local name = deck.loc_txt and deck.loc_txt.name or deck.name
      name = tostring(name or key)
      local eff = M.describe_deck(deck) or Utils.safe_description(deck.loc_txt)
      rows[#rows + 1] = { key = key, name = name, eff = (eff ~= "" and eff) or nil }
    end
  end
  return rows
end

return M
