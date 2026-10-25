local DeckNames = require("facts.deck_names")
local Utils = require("util.utils")
local StateKinds = require("core.state_kinds")
local get_back_display_name = DeckNames.get_back_display_name

local M = {}

local DECK_INFO = {
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
  ["Abandoned Deck"] = "Starts with no face cards (J/Q/K): 40 cards, 10 per suit. That filter runs once at the start of the run; face cards added later (Standard packs, Familiar, Strength on a 10) stay in the deck. While the deck holds none, straights only span A-5 through 6-10. ",
  ["Painted Deck"]   = "+2 hand size (see 10 cards), -1 joker slot. ",
  ["Checkered Deck"] = "Starts with only Spades and Hearts (Clubs became Spades, Diamonds became Hearts): 4 copies of each rank -- 2 Spades and 2 Hearts (52 cards). That conversion runs once at the start of the run; Clubs and Diamonds added later (Standard packs, The Star, The Moon, Familiar/Grim/Incantation) stay in the deck. ",
  ["Anaglyph Deck"]  = "Earn a Double Tag after every Boss Blind (gives copy of next tag). Standard 52-card pool. ",
}

local HUD_TEXT = {
  ["Red Deck"]       = function(c) return string.format("%+d discard per round", c.discards or 1) end,
  ["Blue Deck"]      = function(c) return string.format("%+d hand per round", c.hands or 1) end,
  ["Yellow Deck"]    = function(c) return "Started with " .. Utils.money_change(c.dollars or 10) end,
  ["Green Deck"]     = function(c)
    return string.format("%s per unused hand, %s per unused discard, no interest",
      Utils.money(c.extra_hand_bonus or 2), Utils.money(c.extra_discard_bonus or 1))
  end,
  ["Black Deck"]     = function(c) return string.format("%+d joker slot, %+d hand", c.joker_slot or 1, c.hands or -1) end,
  ["Magic Deck"]     = "+1 consumable slot, started with 2 Fools",
  ["Nebula Deck"]    = function(c) return string.format("Telescope active, %+d consumable slot", c.consumable_slot or -1) end,
  ["Ghost Deck"]     = "Spectral cards can appear, started with Hex",
  ["Zodiac Deck"]    = "Tarot, Planet and Overstock vouchers active",
  ["Plasma Deck"]    = function(c)
    return "Chips and mult balance before scoring, x" .. tostring(c.ante_scaling or 2) .. " blind size"
  end,
  ["Erratic Deck"]   = "Random ranks and suits",
  ["Abandoned Deck"] = "No face cards, 40 cards",
  ["Painted Deck"]   = function(c)
    return string.format("%+d hand size, %+d joker slot", c.hand_size or 2, c.joker_slot or -1)
  end,
  ["Checkered Deck"] = "Only Spades and Hearts",
  ["Anaglyph Deck"]  = "Double Tag after every Boss Blind",
}

local function hud_text(name, config)
  local entry = HUD_TEXT[name]
  if type(entry) == "function" then return entry(config or {}) end
  return entry
end

local function short_desc(b)
  if type(b) ~= "table" then return nil end
  local c = b.config or {}
  local parts = {}
  if c.discards and c.discards ~= 0 then parts[#parts+1] = string.format("%+d discard", c.discards) end
  if c.hands and c.hands ~= 0 then parts[#parts+1] = string.format("%+d hand", c.hands) end
  if c.dollars and c.dollars ~= 0 then parts[#parts+1] = Utils.money_change(c.dollars) .. " start" end
  if c.extra_hand_bonus and c.extra_hand_bonus ~= 0 then parts[#parts+1] = Utils.money_change(c.extra_hand_bonus) .. " per remaining hand" end
  if c.extra_discard_bonus and c.extra_discard_bonus ~= 0 then parts[#parts+1] = Utils.money_change(c.extra_discard_bonus) .. " per remaining discard" end
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

local START_FILTER = {
  b_abandoned = { what = "face card", reads = "rank", test = function(c)
    local id = c.base and c.base.id
    return id ~= nil and id >= 11 and id <= 13
  end },
  b_checkered = { what = "Club or Diamond card", reads = "suit", test = function(c)
    local suit = c.base and c.base.suit
    return suit == "Clubs" or suit == "Diamonds"
  end },
}

function M.start_filter_count(back)
  local center = resolve(back)
  local key = (center and center.key) or (type(back) == "table" and back.key) or nil
  local rule = key and START_FILTER[key]
  local cards = G and G.playing_cards
  if not rule or type(cards) ~= "table" then return nil end
  local CardUtil = require("facts.card_util")
  local PublicCard = require("facts.public_card_identity")
  local n = 0
  for _, c in ipairs(cards) do
    if type(c) == "table" and (PublicCard.is_public(c) or CardUtil.is_composition_public(c))
        and not (rule.reads == "rank" and CardUtil.has_no_rank(c))
        and not (rule.reads == "suit" and CardUtil.has_no_suit(c)) and rule.test(c) then
      n = n + 1
    end
  end
  return n, rule.what
end

function M.describe_deck(back)
  local center, name = resolve(back)
  return DECK_INFO[name] or (center and short_desc(center)) or short_desc(back)
end

local function sentence_case(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("^%l", string.upper))
end

function M.describe_deck_hud(back)
  local center, name = resolve(back)
  return sentence_case(hud_text(name, center and center.config)
    or (center and short_desc(center)) or short_desc(back)
    or DECK_INFO[name])
end

local STAKE_INFO = {
  { key = "stake_white",  effect = "none (baseline difficulty)" },
  { key = "stake_red",    effect = "Small Blind pays no reward" },
  { key = "stake_green",  effect = "score requirements scale up faster each ante" },
  { key = "stake_black",  effect = "Eternal Jokers can appear in the shop" },
  { key = "stake_blue",   effect = "-1 discard per round" },
  { key = "stake_purple", effect = "score requirements scale up even faster" },
  { key = "stake_orange", effect = "Perishable Jokers can appear in the shop (debuffed after 5 rounds)" },
  { key = "stake_gold",   effect = "Rental Jokers can appear in the shop (cost $3 per round)" },
}

local STAKE_EFFECT_BY_KEY = {}
for _, s in ipairs(STAKE_INFO) do STAKE_EFFECT_BY_KEY[s.key] = s.effect end

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
      local name = get_back_display_name(deck)
      local eff = M.describe_deck(deck) or Utils.safe_description(deck.loc_txt)
      rows[#rows + 1] = { key = key, name = name, eff = (eff ~= "" and eff) or nil }
    end
  end
  return rows
end

local function current_profile()
  return G and G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
end

local function back_by_key(key)
  local center = key ~= nil and G and G.P_CENTERS and G.P_CENTERS[key]
  return type(center) == "table" and center.set == "Back" and center or nil
end

function M.run_select_choices()
  if not StateKinds.is_run_setup_overlay() then return nil end
  return SMODS.RunSelect.Setup.choices
end

function M.run_deck_center()
  local picked = back_by_key(G and G.NEURO and G.NEURO.selected_back_key)
  if picked then return picked end
  if not (G and G.GAME) then return nil end
  local profile = current_profile()
  local choices = M.run_select_choices()
  local last = profile and profile.last_choices
  return back_by_key(choices and choices.deck_choice)
    or back_by_key(last and last.deck_choice)
    or back_by_key("b_red")
end

function M.run_seed()
  local choices = M.run_select_choices()
  local on, seed
  if choices then on, seed = choices.enable_seed, choices.seed end
  seed = type(seed) == "string" and seed ~= "" and seed or nil
  return on and true or false, seed
end

local function stake_on_screen()
  local profile = current_profile()
  local choices = M.run_select_choices()
  local last = profile and profile.last_choices
  return tonumber(choices and choices.stake_choice) or tonumber(last and last.stake_choice)
end

function M.run_stake()
  local forced = tonumber(G and G.forced_stake)
  if forced then return forced end
  local stake = tonumber(G and G.NEURO and G.NEURO.selected_stake) or stake_on_screen() or 1
  local selectable = M.selectable_stakes()
  if #selectable == 0 then return stake end
  for _, index in ipairs(selectable) do if index == stake then return stake end end
  return 1
end

function M.run_deck_name()
  local center = M.run_deck_center()
  return center and get_back_display_name(center) or nil
end

local function viewed_deck_key()
  local center = M.run_deck_center()
  return center and center.key or nil
end

function M.selectable_stakes()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  local out = {}
  if type(pool) ~= "table" then return out end
  local profile = current_profile()
  local all_unlocked = profile and profile.all_unlocked
  local usage = profile and profile.deck_usage and profile.deck_usage[viewed_deck_key()]
    or { wins_by_key = {} }
  for index, stake in ipairs(pool) do
    if all_unlocked or SMODS.check_applied_stakes(stake, usage) then out[#out + 1] = index end
  end
  return out
end

function M.challenge_unlocked(challenge, index)
  local check = SMODS and SMODS.challenge_is_unlocked
  if type(check) ~= "function" then return true end
  local ok, verdict = pcall(check, challenge, index)
  return ok and verdict and true or false
end

function M.selectable_challenges()
  local out = {}
  local pool = G and G.CHALLENGES
  if type(pool) ~= "table" then return out end
  for index, entry in ipairs(pool) do
    if type(entry) == "table" and M.challenge_unlocked(entry, index) then
      local id = type(entry.id) == "string" and entry.id ~= "" and entry.id or tostring(index)
      out[#out + 1] = { index = index, id = id,
        name = require("facts.display_names").challenge(entry) or id }
    end
  end
  return out
end

function M.selected_challenge()
  local tab = G and G.challenge_tab or nil
  local pool = G and G.CHALLENGES
  if not (tab and type(pool) == "table") then return nil end
  if type(tab) == "number" then return pool[tab] and tab or nil, pool[tab] end
  if type(tab) == "table" then
    for index, entry in ipairs(pool) do
      if entry == tab or (tab.id and entry.id == tab.id) then return index, entry end
    end
  end
  return nil
end

function M.selectable_challenge_ids()
  local ids = {}
  for _, entry in ipairs(M.selectable_challenges()) do ids[#ids + 1] = entry.id end
  return ids
end

function M.deck_records()
  local profile = current_profile()
  local usage = profile and profile.deck_usage or {}
  local rows = {}
  for _, deck in ipairs(M.list_selectable_backs()) do
    local entry = usage[deck.key]
    local losses, best_win = 0, nil
    for _, n in pairs(entry and entry.losses or {}) do losses = losses + (tonumber(n) or 0) end
    for stake, n in pairs(entry and entry.wins or {}) do
      if type(stake) == "number" and (tonumber(n) or 0) > 0 then best_win = math.max(best_win or 0, stake) end
    end
    rows[#rows + 1] = { key = deck.key, name = deck.name, recorded = entry ~= nil, losses = losses, best_win = best_win }
  end
  return rows
end

function M.record_text(row)
  if not row.recorded then return "no finished run on record" end
  local parts = { row.losses == 1 and "1 loss on record" or (tostring(row.losses) .. " losses on record") }
  if row.best_win then parts[#parts + 1] = "won up to stake " .. tostring(row.best_win) end
  return table.concat(parts, ", ")
end

local VARIETY_LIST_LIMIT = 4

function M.variety_advice(current_key)
  local rows = M.deck_records()
  if #rows < 2 then return "" end
  table.sort(rows, function(a, b) return a.key < b.key end)
  local current, fresh = nil, {}
  for _, row in ipairs(rows) do
    if row.key == current_key then current = row end
    if not row.recorded and #fresh < VARIETY_LIST_LIMIT then
      fresh[#fresh + 1] = row.name .. " (key " .. row.key .. ")"
    end
  end
  if #fresh == 0 then return "" end
  if current and not current.recorded then
    return "Deck variety: " .. current.name .. " has no finished run on record -- a good pick. "
  end
  local played = current and (current.name .. " has " .. M.record_text(current) .. "; ") or ""
  return "Deck variety: " .. played .. "no finished run on record yet: " .. table.concat(fresh, ", ")
    .. ". Select one of them -- a new deck each run keeps the stream fresh. "
end

M.viewed_deck_key = viewed_deck_key

return M
