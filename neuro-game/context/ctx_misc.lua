local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("facts.economy_facts")
local GameFacts = require("facts.game_facts")
local CardUtil = require("facts.card_util")
local Utils = require("util.utils")
local SemanticRegistry = require("core.semantic_registry")
local normalize_text = CtxHelpers.normalize_text
local safe_name_or = Utils.safe_name_or
local safe_description = Utils.safe_description
local DebuffFacts = require("facts.debuff_facts")
local decode_card = CtxHelpers.decode_card
local humanize_effect = CtxHelpers.humanize_effect
local strip_dot = CtxHelpers.strip_dot
local yn = CtxHelpers.yn

local M = {}

local function setup_decks_section(with_effects)
  if not (G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) then return nil end

  local selected_key = "-"
  local selected_name = "-"
  local back = G.GAME and (G.GAME.selected_back or G.GAME.back)
  if back then
    local ok_dn, DeckNames = pcall(require, "facts.deck_names")
    local center = ok_dn and DeckNames and DeckNames.deck_center_of(back) or nil
    selected_key = tostring((center and center.key) or back.key or back.name or "-")
    selected_name = tostring(back.name or (center and center.key) or "-")
  end

  local decks = require("facts.deck_facts").list_selectable_backs()
  table.sort(decks, function(a, b) return a.key < b.key end)

  local lines = {}
  lines[#lines + 1] = string.format("Selected deck: %s (key %s). %d decks are selectable, listed below.",
    normalize_text(selected_name), normalize_text(selected_key), #decks)

  if #decks > 0 then
    lines[#lines + 1] = "Decks you can select (pass the key as change_selected_back back):"
    for i = 1, #decks do
      local d = decks[i]
      local key = normalize_text(d.key)
      local name = normalize_text(d.name)
      local eff = d.eff and normalize_text(d.eff) or nil
      local s = i .. ". " .. name .. " (key " .. key .. ")"
      if with_effects and eff and eff ~= "" then s = s .. " -- " .. eff end
      lines[#lines + 1] = s
    end
  end

  return table.concat(lines, "\n")
end

local function consumable_row_prose(idx, card)
  local name = normalize_text(safe_name_or(card))
  local ability = card.ability or {}
  local set = normalize_text(ability.set or "?")
  local desc = SemanticRegistry.render("consumable_row", card)
  local min_h, max_h = CardUtil.consumable_target_range(card)
  local ok = CardUtil.consumable_usable_now(card)
  local sell = Utils.money(card.sell_cost)

  local s = idx .. ". " .. name .. " (" .. set .. ")"
  if desc and desc ~= "-" and desc ~= "" then s = s .. " -- " .. strip_dot(desc) end
  if max_h then
    local n = (min_h == max_h) and tostring(min_h) or (tostring(min_h) .. " to " .. tostring(max_h))
    s = s .. ". Targets " .. n .. (n == "1" and " card" or " cards")
  end
  s = s .. ". Usable now: " .. yn(ok)
  if not ok then
    if max_h then
      s = s .. " (needs hand cards selected -- normal while shopping, becomes usable once you're dealt a hand)"
    else
      s = s .. " (blocked by a full joker/consumable output slot -- free a slot to use it)"
    end
  end
  s = s .. ". Sell " .. sell
  return s .. "."
end

local function consumables_section()
  if not G or not G.consumeables or not G.consumeables.cards then return nil end
  if #G.consumeables.cards == 0 then
    return "Consumables (" .. CardUtil.slot_status_text(CardUtil.consumable_slot_status()) .. "): none."
  end
  local lines = { 'Consumables (area "consumeables", '
    .. CardUtil.slot_status_text(CardUtil.consumable_slot_status()) .. "):" }
  for i, card in ipairs(G.consumeables.cards) do
    lines[#lines + 1] = consumable_row_prose(i, card)
  end
  return table.concat(lines, "\n")
end

local PRICING_VOUCHERS = {
  v_clearance_sale = true, v_liquidation = true,
  v_reroll_surplus = true, v_reroll_glut = true,
  v_overstock_norm = true, v_overstock_plus = true,
}

local function vouchers_section(only_keys)
  if not (G and G.GAME and G.GAME.used_vouchers) then return nil end
  local keys = {}
  for k, v in pairs(G.GAME.used_vouchers) do
    if v and (not only_keys or only_keys[k]) then keys[#keys + 1] = k end
  end
  if #keys == 0 then
    return only_keys and nil or "Vouchers you own: none."
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local center = G.P_CENTERS and G.P_CENTERS[k]
    local short = (center and center.loc_txt and center.loc_txt.name)
      or (center and center.name)
      or (k:gsub("^v_", ""))
    local eff = DebuffFacts.voucher_effect_text(k)
    if eff == "" then
      eff = (center and safe_description(center.loc_txt)) or ""
    end
    short = normalize_text(short)
    if eff and eff ~= "" then
      parts[#parts + 1] = short .. " (" .. strip_dot(normalize_text(eff)) .. ")"
    else
      parts[#parts + 1] = short
    end
  end
  local head = only_keys and "Pricing vouchers active: " or "Vouchers you own: "
  return head .. table.concat(parts, "; ") .. "."
end

local function tags_section()
  if not (G and G.GAME and G.GAME.tags) then return nil end
  local parts = {}
  for _, tag in ipairs(G.GAME.tags) do
    local key = tag and tag.key
    if key then
      local def = G.P_TAGS and G.P_TAGS[key]
      local name = (def and def.name) or (key:gsub("^tag_", ""))
      local eff = DebuffFacts.tag_effect_text(key, tag)
      if eff == "" then
        eff = (def and safe_description(def.loc_txt)) or ""
      end
      name = normalize_text(name)
      if eff and eff ~= "" then
        parts[#parts + 1] = name .. " (" .. normalize_text(eff) .. ")"
      else
        parts[#parts + 1] = name
      end
    end
  end
  if #parts == 0 then return nil end
  return "Held tags: " .. table.concat(parts, "; ") .. "."
end

local PACK_KIND = {
  TAROT = "Arcana (Tarot)", PLANET = "Celestial (Planet)", SPECTRAL = "Spectral",
  STANDARD = "Standard (playing cards)", BUFFOON = "Buffoon (Jokers)", BOOSTER = "Booster",
}

local function pack_row_prose(idx, card)
  local card_token = require("context.ctx_hand").card_token
  local name
  if card.base and card.base.value and card.base.suit then
    name = normalize_text(card_token(card, false, true))
  else
    name = normalize_text(safe_name_or(card))
  end
  local ability = card.ability or {}
  local set = normalize_text(ability.set or "?")
  local ok_take = CardUtil.can_take_pack_card(card)
  local raw_eff = SemanticRegistry.render("pack_card_row", card)
  local suffix = CardUtil.planet_run_state_suffix(card):gsub("^; ", "")
  local desc = SemanticRegistry.render("card_description_full", card)
  if desc == "" or desc == raw_eff then desc = nil end

  local s = idx .. ". " .. decode_card(name)
  if set ~= "?" then s = s .. " (" .. set .. ")" end
  s = s .. ". Takeable now: " .. yn(ok_take)
  local he = (raw_eff ~= "-" and raw_eff ~= "") and strip_dot(humanize_effect(raw_eff, false)) or ""
  if suffix ~= "" then he = (he ~= "" and (he .. "; " .. suffix)) or suffix end
  if he ~= "" then s = s .. " -- " .. he end
  if desc and desc ~= "" then
    if not (he ~= "" and he:find(desc, 1, true)) then s = s .. ". " .. desc end
  end
  return s .. "."
end

local function pack_section(state_name)
  local bp = CardUtil.pack_area()
  if not bp or not bp.cards then
    return nil
  end
  local pack_type = (state_name == "SMODS_BOOSTER_OPENED") and "BOOSTER" or state_name:gsub("_PACK", "")
  local picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0
  local kind_name = PACK_KIND[pack_type] or (pack_type:gsub("_", " ")) or "booster"
  local art = kind_name:match("^[AEIOUaeiou]") and "an" or "a"
  local lines = { string.format(
    "Opened %s %s pack -- pick %d card%s below (it is already paid for, so taking beats skipping). "
    .. "It closes on its own after your pick(s); use skip_booster to forfeit the rest.",
    art, kind_name, picks_left, picks_left == 1 and "" or "s") }
  if #bp.cards > 0 then
    lines[#lines + 1] = 'Cards in the pack (area "booster_pack"):'
    for i, card in ipairs(bp.cards) do
      lines[#lines + 1] = pack_row_prose(i, card)
    end
  end
  return table.concat(lines, "\n")
end

local function stake_list_line()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  if type(pool) ~= "table" or #pool == 0 then return nil end
  local stake_effect_text = require("facts.deck_facts").stake_effect_text
  local parts = {}
  for i, st in ipairs(pool) do
    if type(st) == "table" then
      local name = (st.loc_txt and st.loc_txt.name) or st.name or st.key or "?"
      local eff = stake_effect_text(st.key) or "-"
      parts[#parts + 1] = i .. ") " .. normalize_text(tostring(name)) .. " -- " .. normalize_text(eff)
    end
  end
  if #parts == 0 then return nil end
  return "Stakes (pass the number as change_stake to_key; cumulative, a higher stake keeps every "
    .. "lower stake's effect too): " .. table.concat(parts, "; ") .. "."
end

local function game_over_section()
  if not Utils.game_ready() then return nil end
  local outcome = G.GAME.won and "WON" or "lost"
  local ante = GameFacts.ante("?")
  local round = G.GAME.round or "?"
  return string.format("Result: %s. Final ante %s, round %s.", outcome, tostring(ante), tostring(round))
end

local function run_section()
  if not Utils.game_ready() then return nil end
  local game = G.GAME
  local deck_name = "-"
  local _bobj = game.selected_back or game.back
  if _bobj then
    local bkey = _bobj.key or _bobj.name
    if bkey and G.P_CENTERS and G.P_CENTERS[bkey] then
      local pc = G.P_CENTERS[bkey]
      deck_name = (pc.loc_txt and pc.loc_txt.name) or pc.name or bkey
    else
      deck_name = bkey or "-"
    end
    if type(deck_name) == "string" and deck_name:find("_") and not deck_name:find(" ") then
      deck_name = Utils.humanize_identifier(deck_name)
    end
  end
  local stake = game.stake or 1
  local seeded = not not game.seeded
  local ch = game.challenge
  local challenge = "N"
  if type(ch) == "table" then
    challenge = ch.name or ch.id or "Y"
  elseif type(ch) == "string" and ch ~= "" then
    challenge = ch
  end
  local seed = (game.pseudorandom and game.pseudorandom.seed) or "-"

  local d = normalize_text(deck_name)
  if not d:lower():find("deck$") then d = d .. " deck" end
  local parts = { "Run setup: " .. d .. ", stake " .. tostring(stake) }
  parts[#parts + 1] = seeded and ("seeded (seed " .. normalize_text(seed) .. ")") or "not seeded"
  if challenge ~= "N" then parts[#parts + 1] = "challenge: " .. normalize_text(challenge) end
  return table.concat(parts, ", ") .. "."
end

local function deck_size_line()
  if not G or not G.deck or not G.deck.cards then return nil end
  local discard_count = G.discard and G.discard.cards and #G.discard.cards or 0
  return tostring(discard_count) .. " cards in the discard pile."
end

local function action_memory_section(state_name)
  if not Utils.neuro_ready() then return nil end

  local p = {}
  local recent = G.NEURO.recent_actions
  if type(recent) == "table" and #recent > 0 then
    local from = math.max(1, #recent - 3)
    local tokens = {}
    local i = from
    while i <= #recent do
      local name = tostring(recent[i] or "")
      local count = 1
      while (i + count) <= #recent and recent[i + count] == name do
        count = count + 1
      end
      if name ~= "" then
        tokens[#tokens + 1] = (count > 1) and (name .. "x" .. count) or name
      end
      i = i + count
    end
    if #tokens > 0 then
      local raw = normalize_text(table.concat(tokens, ">"))
      raw = raw:gsub(">", " then "):gsub("_", " "):gsub("([%w])x(%d+)", "%1 x%2")
      p[#p + 1] = "recent actions " .. raw
    end
  end

  if state_name == "SHOP" then
    local rf = CtxEconomy.reroll_facts()
    local now_cost, next_cost = rf and rf.effective, rf and rf.next
    if type(now_cost) == "number" and type(next_cost) == "number" then
      p[#p + 1] = "reroll costs $" .. tostring(now_cost) .. " now, $" .. tostring(next_cost) .. " after that"
    end
  end

  if #p == 0 then return nil end
  return "History: " .. table.concat(p, "; ") .. "."
end

M.setup_decks_section = setup_decks_section
M.stake_list_line = stake_list_line
M.game_over_section = game_over_section
M.consumables_section = consumables_section
M.vouchers_section = vouchers_section
M.PRICING_VOUCHERS = PRICING_VOUCHERS
M.tags_section = tags_section
M.pack_section = pack_section
M.run_section = run_section
M.deck_size_line = deck_size_line
M.action_memory_section = action_memory_section

return M
