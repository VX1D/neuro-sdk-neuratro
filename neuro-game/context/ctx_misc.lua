local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local Utils = require("util.utils")
local compact_text = CtxHelpers.compact_text
local card_effect_summary = CtxHelpers.card_effect_summary
local join_rows = CtxHelpers.join_rows
local safe_name_or = Utils.safe_name_or
local safe_description = Utils.safe_description
local DebuffFacts = require("facts.debuff_facts")

local M = {}

local function setup_decks_section()
  if not (G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) then return nil end

  local selected_key = "-"
  local selected_name = "-"
  if G.GAME and G.GAME.selected_back then
    local sb = G.GAME.selected_back
    selected_key = tostring(sb.key or sb.name or "-")
    selected_name = tostring(sb.name or sb.key or "-")
  elseif G.GAME and G.GAME.back then
    local b = G.GAME.back
    selected_key = tostring(b.key or b.name or "-")
    selected_name = tostring(b.name or b.key or "-")
  end

  local decks = require("facts.deck_facts").list_selectable_backs()
  table.sort(decks, function(a, b) return a.key < b.key end)

  local lines = {}
  lines[#lines + 1] = string.format("SD|K:%s|N:%s|U:%d",
    compact_text(selected_key, 18), compact_text(selected_name, 24), #decks)

  -- k must stay a typeable change_selected_back key, so it is never ellipsis-cut short
  lines[#lines + 1] = "SDC:i,k,n,e"
  local max_rows = math.min(#decks, 24)
  for i = 1, max_rows do
    local d = decks[i]
    lines[#lines + 1] = string.format("%d,%s,%s,%s",
      i, compact_text(d.key, 40), compact_text(d.name, 28), d.eff and compact_text(d.eff, 70) or "-")
  end

  return table.concat(lines, "\n")
end

local function consumables_section()
  if not G or not G.consumeables or not G.consumeables.cards or #G.consumeables.cards == 0 then
    return nil
  end
  local rows = {}
  for i, card in ipairs(G.consumeables.cards) do
    local name = compact_text(safe_name_or(card), 28)
    local ability = card.ability or {}
    local set = compact_text(ability.set or "?", 20)
    local desc = compact_text(Utils.card_description_with_fallback(card, 140), 140)
    if not desc or desc == "" then desc = "-" end
    local min_h, max_h = CardUtil.consumable_target_range(card)
    local sel = max_h and (tostring(min_h) .. "-" .. tostring(max_h)) or "-"
    -- ok=N can mean a full output slot, not just an unusable card
    local ok = CardUtil.consumable_usable_now(card) and "Y" or "N"
    rows[#rows + 1] = { tostring(i), name, set, Utils.money(card.sell_cost), sel, ok, desc }
  end
  local chdr = "C[" .. CardUtil.slot_status_text(CardUtil.consumable_slot_status()) .. "]:i,n,t,$,sel,ok,d"
  return join_rows(chdr, rows)
end

local function vouchers_section()
  if not (G and G.GAME and G.GAME.used_vouchers) then return nil end
  local keys = {}
  for k, v in pairs(G.GAME.used_vouchers) do
    if v then keys[#keys + 1] = k end
  end
  if #keys == 0 then return nil end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local center = G.P_CENTERS and G.P_CENTERS[k]
    -- V| legend promises "name:effect" format, so this must resolve to a display name, not the raw key
    local short = (center and center.loc_txt and center.loc_txt.name)
      or (center and center.name)
      or (k:gsub("^v_", ""))
    local eff = DebuffFacts.voucher_effect_text(k)
    if eff == "" then
      eff = (center and safe_description(center.loc_txt, nil, 120)) or ""
    end
    short = compact_text(short, 24)
    if eff and eff ~= "" then
      parts[#parts + 1] = short .. ":" .. compact_text(eff, 120)
    else
      parts[#parts + 1] = short
    end
  end
  return "V|" .. table.concat(parts, "|")
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
        eff = (def and safe_description(def.loc_txt, nil, 120)) or ""
      end
      if eff and eff ~= "" then
        parts[#parts + 1] = compact_text(name, 24) .. ":" .. compact_text(eff, 120)
      else
        parts[#parts + 1] = compact_text(name, 24)
      end
    end
  end
  if #parts == 0 then return nil end
  return "TAGS|" .. table.concat(parts, "|")
end

local function pack_section(state_name)
  local bp = CardUtil.pack_area()  -- SMODS uses G.pack_cards
  if not bp or not bp.cards then
    return nil
  end
  local pack_type = (state_name == "SMODS_BOOSTER_OPENED") and "BOOSTER" or state_name:gsub("_PACK", "")
  local picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0
  local card_token = require("context.ctx_hand").card_token
  local lines = {}
  lines[#lines + 1] = "PK:" .. pack_type .. "|PICKS:" .. tostring(picks_left)
  local rows = {}
  for i, card in ipairs(bp.cards) do
    local name
    if card.base and card.base.value and card.base.suit then
      name = compact_text(card_token(card, false, true), 60)
    else
      name = compact_text(safe_name_or(card), 28)
    end
    local ability = card.ability or {}
    local set = compact_text(ability.set or "?", 20)
    local ok_take = CardUtil.can_take_pack_card(card) and "Y" or "N"
    rows[#rows + 1] = { tostring(i), name, set, card_effect_summary(card), ok_take }
  end
  lines[#lines + 1] = join_rows("PC:i,n,t,f,ok", rows)
  return table.concat(lines, "\n")
end

-- header is STK, not SK -- SK is already used for can-skip in the BLIND_SELECT BA-line
local function stake_list_line()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  if type(pool) ~= "table" or #pool == 0 then return nil end
  local parts = {}
  for i, st in ipairs(pool) do
    if type(st) == "table" then
      local name = (st.loc_txt and st.loc_txt.name) or st.name or st.key or "?"
      parts[#parts + 1] = tostring(i) .. "=" .. compact_text(tostring(name), 20)
    end
  end
  if #parts == 0 then return nil end
  return "STK[change_stake to_key]:" .. table.concat(parts, ",")
end

local function game_over_section()
  if not Utils.game_ready() then return nil end
  local outcome = G.GAME.won and "WON" or "lost"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local round = G.GAME.round or "?"
  return string.format("GO|%s|A:%s|R:%s", outcome, tostring(ante), tostring(round))
end

local function run_section()
  if not Utils.game_ready() then return nil end
  local game = G.GAME
  local deck_name = "-"
  local _bobj = game.back or game.selected_back
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
  local seeded = game.seeded and "Y" or "N"
  -- G.GAME.challenge is a plain id STRING (game.lua:2119), not a table -- indexing .name/.id on it yields nil
  local ch = game.challenge
  local challenge = "N"
  if type(ch) == "table" then
    challenge = ch.name or ch.id or "Y"
  elseif type(ch) == "string" and ch ~= "" then
    challenge = ch
  end
  local seed = (game.pseudorandom and game.pseudorandom.seed) or "-"
  return string.format("R|D:%s|K:%s|SEEDED:%s|CH:%s|SE:%s",
    compact_text(deck_name, 24), tostring(stake), seeded, compact_text(challenge, 24), compact_text(seed, 16))
end

local function deck_size_line()
  if not G or not G.deck or not G.deck.cards then return nil end
  local deck_name = ""
  local ok_dn, DeckNames = pcall(require, "facts.deck_names")
  if ok_dn and DeckNames then
    local pc = DeckNames.current_deck_center()
    if pc then
      deck_name = DeckNames.get_back_display_name(pc) or ""
    else
      local back = G.GAME and (G.GAME.selected_back or G.GAME.back)
      if back and back.name then deck_name = tostring(back.name) end
    end
  end
  local discard_count = G.discard and G.discard.cards and #G.discard.cards or 0
  -- draw-pile size lives in DC:<n>, not here -- DK only carries deck name + discard-pile size
  local out = "DK"
  if deck_name ~= "" then out = out .. "|N:" .. compact_text(deck_name, 24) end
  out = out .. "|DP:" .. tostring(discard_count)
  return out
end

local function action_memory_section(state_name)
  if not Utils.neuro_ready() then return nil end

  local parts = {}
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
      parts[#parts + 1] = "last:" .. compact_text(table.concat(tokens, ">"), 84)
    end
  end

  if state_name == "SHOP" then
    local rr = tonumber(G.NEURO.shop_reroll_count or 0) or 0
    parts[#parts + 1] = "SR:" .. tostring(math.max(0, math.floor(rr)))
  end

  if #parts == 0 then return nil end
  return "ACTS|" .. table.concat(parts, "|")
end

M.setup_decks_section = setup_decks_section
M.stake_list_line = stake_list_line
M.game_over_section = game_over_section
M.consumables_section = consumables_section
M.vouchers_section = vouchers_section
M.tags_section = tags_section
M.pack_section = pack_section
M.run_section = run_section
M.deck_size_line = deck_size_line
M.action_memory_section = action_memory_section

return M
