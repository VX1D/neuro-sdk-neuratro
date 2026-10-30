local CtxHelpers = require("context.ctx_helpers")
local GameFacts = require("facts.game_facts")
local CardUtil = require("facts.card_util")
local UseGate = require("facts.use_gate")
local Utils = require("util.utils")
local PublicCardIdentity = require("facts.public_card_identity")
local DisplayNames = require("facts.display_names")
local SemanticRegistry = require("core.semantic_registry")
local normalize_text = CtxHelpers.normalize_text
local safe_name_or = Utils.safe_name_or
local DebuffFacts = require("facts.debuff_facts")
local VoucherFacts = require("facts.voucher_facts")
local decode_card = CtxHelpers.decode_card
local humanize_effect = CtxHelpers.humanize_effect
local strip_dot = CtxHelpers.strip_dot
local yn = CtxHelpers.yn
local DeckFacts = require("facts.deck_facts")

local M = {}

local function setup_decks_section()
  if not (G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) then return nil end

  local run_deck = DeckFacts.run_deck_center()

  local decks = DeckFacts.deck_records()
  table.sort(decks, function(a, b) return a.key < b.key end)
  local effects = {}
  for _, d in ipairs(DeckFacts.list_selectable_backs()) do effects[d.key] = d.eff end

  local lines = {}
  lines[#lines + 1] = (run_deck and string.format("Selected deck: %s (key %s). ",
    normalize_text(DeckFacts.run_deck_name()), normalize_text(tostring(run_deck.key))) or "")
    .. string.format("%d decks are selectable, listed below.", #decks)

  if #decks > 0 then
    lines[#lines + 1] = "## Decks you can select"
    for i = 1, #decks do
      local d = decks[i]
      local key = normalize_text(d.key)
      local name = normalize_text(d.name)
      local eff = effects[d.key] and normalize_text(effects[d.key]) or nil
      local selected = run_deck and d.key == run_deck.key and ", selected now" or ""
      local s = i .. ". " .. name .. " (key " .. key .. ", " .. DeckFacts.record_text(d) .. selected .. ")"
      if eff and eff ~= "" then s = s .. " -- " .. eff end
      lines[#lines + 1] = s
    end
  end

  return table.concat(lines, "\n")
end

local function consumable_row_prose(idx, card)
  if not PublicCardIdentity.is_public(card) then return CtxHelpers.hidden_row(idx, card, "consumables") end

  local name = normalize_text(safe_name_or(card))
  local ability = card.ability or {}
  local set = normalize_text(ability.set or "?")
  local desc = SemanticRegistry.render("consumable_row", card)
  local ok = CardUtil.consumable_usable_now(card)
  local sell = Utils.money(card.sell_cost)

  local s = idx .. ". " .. name .. " (" .. set .. ")"
  if desc and desc ~= "-" and desc ~= "" then s = s .. " -- " .. strip_dot(desc) end
  local targets = CtxHelpers.target_count(card)
  if targets then s = CtxHelpers.end_sentence(s) .. " Targets " .. targets end
  s = CtxHelpers.end_sentence(s) .. " Usable now: " .. yn(ok)
  if not ok then s = s .. " (" .. UseGate.reason(card).text .. ")" end
  s = s .. ". Sell " .. sell
  local idle = CardUtil.idle_planet_note(card)
  if idle then s = s .. ". It " .. idle end
  return s .. "."
end

local function consumables_section()
  if not G or not G.consumeables or not G.consumeables.cards then return nil end
  if #G.consumeables.cards == 0 then
    return "Consumables (" .. CardUtil.slot_status_text(CardUtil.consumable_slot_status()) .. "): none."
  end
  local lines = { '## Consumables (area "consumables", '
    .. CardUtil.slot_status_text(CardUtil.consumable_slot_status()) .. ")" }
  for i, card in ipairs(G.consumeables.cards) do
    lines[#lines + 1] = consumable_row_prose(i, card)
  end
  return table.concat(lines, "\n")
end


local function named_effect(name, eff)
  return eff and (name .. " (" .. eff .. ")") or name
end

local function vouchers_section()
  if not (G and G.GAME and G.GAME.used_vouchers) then return nil end
  local keys = {}
  for k, v in pairs(G.GAME.used_vouchers) do
    if v then keys[#keys + 1] = k end
  end
  if #keys == 0 then return "Vouchers you own: none." end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local eff = VoucherFacts.effect_text(k)
    parts[#parts + 1] = named_effect(normalize_text(DisplayNames.center(k, "Voucher")),
      eff and eff ~= "" and strip_dot(normalize_text(eff)))
  end
  return "Vouchers you own: " .. table.concat(parts, "; ") .. "."
end

local function tags_section()
  if not (G and G.GAME and G.GAME.tags) then return nil end
  local parts = {}
  for _, tag in ipairs(G.GAME.tags) do
    local key = tag and tag.key
    if key then
      local eff = DebuffFacts.tag_effect_text(key, tag)
      parts[#parts + 1] = named_effect(normalize_text(DisplayNames.tag(key)), eff ~= "" and normalize_text(eff))
    end
  end
  if #parts == 0 then return nil end
  return "Held tags: " .. table.concat(parts, "; ") .. "."
end

local function pack_row_prose(idx, card)
  if not PublicCardIdentity.is_public(card) then return CtxHelpers.hidden_row(idx, card, "booster_pack") end

  local card_token = require("context.ctx_hand").card_token
  local name
  if card.base and card.base.value and card.base.suit then
    name = normalize_text(card_token(card, false))
  else
    name = normalize_text(safe_name_or(card))
  end
  local ability = card.ability or {}
  local set = normalize_text(ability.set or "?")
  local ok_take = CardUtil.can_take_pack_card(card)
  local raw_eff, suffix, desc = CtxHelpers.row_effect(card, "pack_card_row")

  local s = idx .. ". " .. decode_card(name)
  if set ~= "?" and not Utils.is_playing_card(card) then s = s .. " (" .. set .. ")" end
  local stickers = CtxHelpers.sticker_flags(card)
  if stickers then s = s .. " [" .. stickers .. "]" end
  local targets = CtxHelpers.target_count(card)
  if targets then s = s .. ". Targets " .. targets end
  s = s .. ". Takeable now: " .. yn(ok_take)
  if not ok_take and CardUtil.is_consumable_card(card) then s = s .. " (" .. UseGate.reason(card).text .. ")" end
  if Utils.is_playing_card(card) then return CtxHelpers.end_sentence(s) end
  local he = (raw_eff ~= "-" and raw_eff ~= "") and strip_dot(humanize_effect(raw_eff, false)) or ""
  return CtxHelpers.end_sentence(s .. CtxHelpers.effect_tail(he, suffix, desc))
end

local function pack_section()
  local bp = CardUtil.pack_area()
  if not bp or not bp.cards then
    return nil
  end
  local picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0
  local smods = rawget(_G, "SMODS")
  local key = CardUtil.center_key(smods and smods.OPENED_BOOSTER)
  local pack_name = key and (" (" .. normalize_text(DisplayNames.center(key, "Booster")) .. ")") or ""
  local lines = { string.format(
    "Opened a Booster pack%s: %d pick%s left from the cards below. It is already paid for and closes on its own "
    .. "after your pick(s).",
    pack_name, picks_left, picks_left == 1 and "" or "s") }
  if #bp.cards > 0 then
    lines[#lines + 1] = '## Cards in the pack (area "booster_pack")'
    for i, card in ipairs(bp.cards) do
      lines[#lines + 1] = pack_row_prose(i, card)
    end
  end
  return table.concat(lines, "\n")
end

local function stake_list_line()
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake
  if type(pool) ~= "table" or #pool == 0 then return nil end
  local parts, current = {}, DeckFacts.run_stake()
  for _, i in ipairs(DeckFacts.selectable_stakes()) do
    local st = pool[i]
    if type(st) == "table" then
      local name = DisplayNames.of("Stake", st.key, st)
      local eff = DeckFacts.stake_effect_text(st.key) or "-"
      parts[#parts + 1] = i .. ". " .. normalize_text(tostring(name)) .. (i == current and " (selected now)" or "")
        .. " -- " .. normalize_text(eff)
    end
  end
  if #parts == 0 then return nil end
  return "## Stakes (only those unlocked for this deck; cumulative, a higher stake keeps every "
    .. "lower stake's effect too)\n" .. table.concat(parts, "\n")
end

local function game_over_section()
  if not Utils.game_ready() then return nil end
  local outcome = GameFacts.run_progress().won and "WON" or "lost"
  local ante = GameFacts.ante("?")
  local round = G.GAME.round or "?"
  return string.format("Result: %s. Final ante %s, round %s.", outcome, tostring(ante), tostring(round))
end

local function run_section()
  if not Utils.game_ready() then return nil end
  local deck_name = DeckFacts.run_deck_name()
  local stake = DeckFacts.run_stake()
  local seeded, seed = DeckFacts.run_seed()

  local parts = { "Run setup: " .. (deck_name and (normalize_text(deck_name) .. ", ") or "")
    .. "stake " .. tostring(stake) }
  parts[#parts + 1] = seeded and (seed and ("seeded (seed " .. normalize_text(seed) .. ")")
    or "seeded (no seed pasted yet)") or (seed and ("not seeded (pasted seed " .. normalize_text(seed) .. ")")
    or "not seeded")
  return table.concat(parts, ", ") .. "."
end

local function discard_count_line()
  if not G or not G.deck or not G.deck.cards then return nil end
  local discard_count = G.discard and G.discard.cards and #G.discard.cards or 0
  return tostring(discard_count) .. " cards in the discard pile."
end

local function action_memory_section()
  if not Utils.neuro_ready() then return nil end

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
        tokens[#tokens + 1] = (count > 1) and (name .. " x" .. count) or name
      end
      i = i + count
    end
    if #tokens > 0 then
      local raw = normalize_text(table.concat(tokens, ">"))
      raw = raw:gsub(">", " then "):gsub("_", " ")
      return "Recent actions: " .. raw .. "."
    end
  end
  return nil
end

M.setup_decks_section = setup_decks_section
M.stake_list_line = stake_list_line
M.game_over_section = game_over_section
M.consumables_section = consumables_section
M.vouchers_section = vouchers_section
M.tags_section = tags_section
M.pack_section = pack_section
M.run_section = run_section
M.discard_count_line = discard_count_line
M.action_memory_section = action_memory_section

return M
