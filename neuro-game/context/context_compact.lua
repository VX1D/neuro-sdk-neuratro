local ContextCompact = {}
local Metrics = require "util.metrics"
local GameFacts = require "facts.game_facts"
local Utils = require "util.utils"
local safe_name = Utils.safe_name
local flatten_description = Utils.flatten_description

local _gf = nil

local CtxHelpers = require("context.ctx_helpers")

local function to_set(list)
  local out = {}
  if not list then return out end
  for _, key in ipairs(list) do out[key] = true end
  return out
end

local has_action = CtxHelpers.has_action

local FP_KEYS = {
  -- ACTS excluded: it churns every action and would defeat force dedup
  SELECTING_HAND = { B = true, BD = true, HL = true, H = true, J = true, L = true, LP = true },
  SHOP = { SH = true, I = true, H = true, L = true },
  BLIND_SELECT = { BS = true, BA = true, BO = true },
  ROUND_EVAL = { RE = true, LP = true },
  TAROT_PACK = { PK = true, PC = true, H = true },
  PLANET_PACK = { PK = true, PC = true, L = true },
  SPECTRAL_PACK = { PK = true, PC = true, H = true },
  STANDARD_PACK = { PK = true, PC = true, H = true, DC = true },
  BUFFOON_PACK = { PK = true, PC = true },
  SMODS_BOOSTER_OPENED = { PK = true, PC = true, H = true, L = true, DC = true },
  MENU = { SD = true, SDC = true },
  RUN_SETUP = { SD = true, SDC = true },
}

FP_KEYS.SHOP.LA = true

FP_KEYS.SELECTING_HAND.JK_ALL = true
FP_KEYS.SHOP.JK_ALL = true

FP_KEYS.SELECTING_HAND.JORD = true
FP_KEYS.SHOP.JORD = true
FP_KEYS.SELECTING_HAND.TAGS = true
FP_KEYS.SHOP.TAGS = true
FP_KEYS.BLIND_SELECT.TAGS = true
FP_KEYS.SELECTING_HAND.C = true
FP_KEYS.SHOP.C = true
FP_KEYS.BLIND_SELECT.C = true
FP_KEYS.MENU.STK = true
FP_KEYS.RUN_SETUP.STK = true
FP_KEYS.GAME_OVER = { GO = true }
FP_KEYS.SELECTING_HAND.PB = true
FP_KEYS.SHOP.PB = true
FP_KEYS.SHOP.J = true
FP_KEYS.BLIND_SELECT.J = true

local function get_pack_fallback(tbl, state_name)
  if tbl[state_name] then return tbl[state_name] end
  if state_name and (state_name:find("_PACK$") or state_name == "SMODS_BOOSTER_OPENED") then
    return tbl["BUFFOON_PACK"]
  end
  return nil
end

local KNOWN_SECTION_IDS = {}
for _, allow in pairs(FP_KEYS) do
  for id in pairs(allow) do KNOWN_SECTION_IDS[id] = true end
end
for _, id in ipairs({ "AVAIL", "V", "DK", "TAGS", "BU", "BP", "JD", "PB", "R", "DC", "PLAY", "LA", "JORD", "JK_ALL", "STK", "GO", "ACTS" }) do
  KNOWN_SECTION_IDS[id] = true
end

local function line_header_id(line)
  if line:find("^STATE:") then return "STATE" end
  return line:match("^([A-Z][A-Z_0-9]*)[:|%[%(]")
end

local function concat_sections(sections)
  local out = {}
  for _, section in ipairs(sections) do
    if section then out[#out + 1] = section end
  end
  return table.concat(out, "\n")
end

local function enforce_budget(_state_name, sections, _split)
  return sections
end
if rawget(_G, "NEURO_TEST") then ContextCompact._enforce_budget = enforce_budget end

local function jokers_signature()
  local parts = {}
  local function scan(area, tag)
    if not (area and area.cards) then return end
    for i, card in ipairs(area.cards) do
      local center = card.config and card.config.center or {}
      local ability = card.ability or {}
      local key = center.key or center.name or safe_name(card) or "?"
      local extra = ability.extra
      if type(extra) == "table" then
        extra = flatten_description(extra) or "table"
      end
      parts[#parts + 1] = table.concat({
        tag .. tostring(i),
        tostring(key),
        tostring(extra or "-"),
        -- mutable scaling fields (Ride the Bus mult growth) must move the signature or full descriptions never refresh
        CtxHelpers.ability_signature(ability),
        ability.eternal and "E" or "-",
        ability.perishable and "P" or "-",
        ability.rental and "R" or "-",
      }, ":")
    end
  end
  scan(G and G.jokers, "")
  scan(G and G.playbook_extra, "pb")
  if #parts == 0 then return "none" end
  return table.concat(parts, "|")
end

local function header_section(state_name)
  return "STATE:" .. state_name
end

local CtxMisc = require("context.ctx_misc")
local setup_decks_section = CtxMisc.setup_decks_section
local stake_list_line = CtxMisc.stake_list_line
local game_over_section = CtxMisc.game_over_section
local consumables_section = CtxMisc.consumables_section
local vouchers_section = CtxMisc.vouchers_section
local tags_section = CtxMisc.tags_section
local pack_section = CtxMisc.pack_section
local run_section = CtxMisc.run_section
local deck_size_line = CtxMisc.deck_size_line
local action_memory_section = CtxMisc.action_memory_section

local CtxBlind = require("context.ctx_blind")
local blind_line = CtxBlind.blind_line
local blind_debuff_line = CtxBlind.blind_debuff_line
local blind_select_section = CtxBlind.blind_select_section
local round_eval_section = CtxBlind.round_eval_section

local CtxHand = require("context.ctx_hand")
local hand_section = CtxHand.hand_section
local hand_limits_section = CtxHand.hand_limits_section
local levels_section = CtxHand.levels_section
local deck_cards_section = CtxHand.deck_cards_section
local play_area_section = CtxHand.play_area_section
local last_play_section = CtxHand.last_play_section

local CtxJokers = require("context.ctx_jokers")
local jokers_section = CtxJokers.jokers_section
local joker_descriptions_section = CtxJokers.joker_descriptions_section
local playbook_section = CtxJokers.playbook_section

local function append_joker_sections(sections, include_full_jokers, opts)
  sections[#sections + 1] = jokers_section()
  if include_full_jokers and opts.split ~= "volatile" then
    sections[#sections + 1] = joker_descriptions_section()
  end
  sections[#sections + 1] = playbook_section(include_full_jokers)
end

local function append_consumables(sections, has_filters, action_set)
  if (not has_filters) or has_action(action_set, "consumables_info") or has_action(action_set, "use_card")
    or has_action(action_set, "sell_card") then
    sections[#sections + 1] = consumables_section()
  end
end

local CtxShop = require("context.ctx_shop")
local legality_section = CtxShop.legality_section

local shop_section = CtxShop.shop_section

-- DC is NOT stable: it shrinks each draw, would re-emit joker descs every hand
local STABLE_PREFIXES = { "V|", "JD:", "FRAME|", "RUN|" }

local function frame_section()
  local ok, GameRules = pcall(require, "context.game_rules")
  if not ok or not GameRules or type(GameRules.invariant_frame) ~= "function" then return nil end
  local txt = GameRules.invariant_frame()
  if type(txt) ~= "string" or txt == "" then return nil end
  return "FRAME|" .. txt
end

local function run_frame_section()
  local ok, GameRules = pcall(require, "context.game_rules")
  if not ok or not GameRules or type(GameRules.run_frame_text) ~= "function" then return nil end
  local ok_t, txt = pcall(GameRules.run_frame_text)
  if not ok_t or type(txt) ~= "string" or txt == "" then return nil end
  return "RUN|" .. txt
end
local function is_stable_line(s)
  for i = 1, #STABLE_PREFIXES do
    local p = STABLE_PREFIXES[i]
    if s:sub(1, #p) == p then return true end
  end
  return false
end

local _ctx_cache = nil
local _ctx_cache_key = nil
local _ctx_cache_at = 0
local CTX_CACHE_TTL = 0.20
local _last_joker_sig_force = nil
local now_time = Utils.now

function ContextCompact.build(state_name, allowed_actions, opts)
  opts = opts or {}
  _gf = GameFacts.build()
  Metrics.incr("ctx_build_calls")
  Metrics.time_begin("ctx_build")
  local action_set = to_set(allowed_actions)
  local has_filters = allowed_actions ~= nil

  local action_key = "*"
  if has_filters then
    local parts = {}
    for _, a in ipairs(allowed_actions) do parts[#parts + 1] = tostring(a) end
    table.sort(parts)
    action_key = table.concat(parts, ",")
  end

  local joker_sig = jokers_signature()
  local jokers_changed_for_force = joker_sig ~= _last_joker_sig_force
  if opts.force_phase and jokers_changed_for_force then
    _last_joker_sig_force = joker_sig
  end
  local include_full_jokers = opts.full_jokers or (opts.force_phase and jokers_changed_for_force)

  local cache_key = table.concat({
    tostring(state_name or "?"),
    action_key,
    include_full_jokers and "J1" or "J0",
    joker_sig,
    _gf.content_sig or "",
    opts.split or "full",
  }, "|")

  local t = now_time()
  if not opts.no_cache and _ctx_cache and _ctx_cache_key == cache_key and (t - _ctx_cache_at) < CTX_CACHE_TTL then
    Metrics.incr("ctx_cache_hit")
    Metrics.time_end("ctx_build")
    return _ctx_cache
  end

  local include_stable = opts.split ~= "volatile"

  local sections = {}
  if include_stable then
    sections[#sections + 1] = frame_section()
    sections[#sections + 1] = run_frame_section()
  end
  sections[#sections + 1] = header_section(state_name)
  if not opts.force_phase then
    -- AVAIL must render from the same final action list this context ships with; a separate re-derivation disagreed live
    local ok_a, Actions = pcall(require, "core.actions")
    local avail
    if has_filters then
      local info = (ok_a and Actions and Actions.INFO_ACTIONS) or {}
      avail = {}
      for _, name in ipairs(allowed_actions) do
        if not info[name] then avail[#avail + 1] = name end
      end
    elseif ok_a and Actions and Actions.get_available_actions_for_state then
      avail = Actions.get_available_actions_for_state(state_name)
    end
    if avail and #avail > 0 then sections[#sections + 1] = "AVAIL:" .. table.concat(avail, ",") end
  end
  sections[#sections + 1] = legality_section(state_name, action_set)
  sections[#sections + 1] = action_memory_section(state_name)

  if state_name == "MENU" or state_name == "RUN_SETUP" then
    sections[#sections + 1] = run_section()
    sections[#sections + 1] = setup_decks_section()
    sections[#sections + 1] = stake_list_line()
  end

  if state_name == "GAME_OVER" then
    sections[#sections + 1] = game_over_section()
  end

  if state_name == "SELECTING_HAND" then
    sections[#sections + 1] = blind_line()
    sections[#sections + 1] = blind_debuff_line()
    sections[#sections + 1] = last_play_section(state_name)
    sections[#sections + 1] = deck_size_line()
    sections[#sections + 1] = play_area_section()
    if include_stable then sections[#sections + 1] = vouchers_section() end
    sections[#sections + 1] = tags_section()
    sections[#sections + 1] = hand_limits_section()
    sections[#sections + 1] = hand_section()
    if (not has_filters) or has_action(action_set, "play_hand") or has_action(action_set, "discard_hand")
      or has_action(action_set, "joker_info") or has_action(action_set, "quick_status") then
      append_joker_sections(sections, include_full_jokers, opts)
    end
    if (not has_filters) or has_action(action_set, "hand_levels_info") or has_action(action_set, "get_poker_hand_information")
      or has_action(action_set, "play_hand") or has_action(action_set, "discard_hand") then
      sections[#sections + 1] = levels_section()
    end
    append_consumables(sections, has_filters, action_set)
    sections[#sections + 1] = deck_cards_section()

  elseif state_name == "SHOP" then
    if include_stable then sections[#sections + 1] = vouchers_section() end
    sections[#sections + 1] = tags_section()
    sections[#sections + 1] = shop_section()
    if (not has_filters) or has_action(action_set, "buy_from_shop") or has_action(action_set, "sell_card")
      or has_action(action_set, "set_joker_order") or has_action(action_set, "joker_info") then
      append_joker_sections(sections, include_full_jokers, opts)
    end
    append_consumables(sections, has_filters, action_set)
    if (not has_filters) or has_action(action_set, "use_card") then
      sections[#sections + 1] = hand_section()
    end
    local shop_wants_levels = false
    local sj = G and G.shop_jokers and G.shop_jokers.cards
    if sj then
      local CU = require("facts.card_util")
      for _, c in ipairs(sj) do
        if CU.card_set(c) == "Planet" then shop_wants_levels = true break end
      end
    end
    if not shop_wants_levels then
      local ok_sc, Scoring = pcall(require, "util.scoring")
      if ok_sc and Scoring and Scoring.joker_summary then
        local ok_sum, agg = pcall(Scoring.joker_summary)
        if ok_sum and agg and agg.cond_by_type and next(agg.cond_by_type) then shop_wants_levels = true end
      end
    end
    if shop_wants_levels then sections[#sections + 1] = levels_section() end

  elseif state_name == "BLIND_SELECT" then
    if include_stable then sections[#sections + 1] = vouchers_section() end
    sections[#sections + 1] = tags_section()
    sections[#sections + 1] = blind_select_section()
    if (not has_filters) or has_action(action_set, "joker_info") or has_action(action_set, "sell_card")
      or has_action(action_set, "set_joker_order") then
      append_joker_sections(sections, include_full_jokers, opts)
    end
    append_consumables(sections, has_filters, action_set)

  elseif state_name == "ROUND_EVAL" then
    sections[#sections + 1] = round_eval_section()
    sections[#sections + 1] = last_play_section(state_name)

  elseif state_name == "TAROT_PACK" or state_name == "PLANET_PACK" or
         state_name == "SPECTRAL_PACK" or state_name == "STANDARD_PACK" or
         state_name == "BUFFOON_PACK" or state_name == "SMODS_BOOSTER_OPENED" or
         (state_name and state_name:find("_PACK$")) then
    sections[#sections + 1] = pack_section(state_name)
    if (not has_filters) or has_action(action_set, "joker_info") or has_action(action_set, "sell_card")
      or has_action(action_set, "set_joker_order") then
      append_joker_sections(sections, include_full_jokers, opts)
    end
    append_consumables(sections, has_filters, action_set)
    if state_name == "TAROT_PACK" or state_name == "SPECTRAL_PACK" then
      sections[#sections + 1] = hand_section()
    end
    if state_name == "PLANET_PACK" then
      sections[#sections + 1] = levels_section()
    end
    if state_name == "STANDARD_PACK" then
      sections[#sections + 1] = hand_section()
      sections[#sections + 1] = deck_cards_section()
    end
    -- under SMODS all packs arrive as SMODS_BOOSTER_OPENED; branches above never fire live, so detect kind from cards
    if state_name == "SMODS_BOOSTER_OPENED" then
      local CU = require("facts.card_util")
      local bp = CU.pack_area()
      local has_planet, has_playing, has_hand_target = false, false, false
      if bp and bp.cards then
        for _, card in ipairs(bp.cards) do
          local set = CU.card_set(card)
          if set == "Planet" then has_planet = true end
          -- only Tarot/Spectral packs deal into G.hand; H: for other sets would be stale
          if set == "Tarot" or set == "Spectral" then has_hand_target = true end
          if card and card.base and card.base.suit and card.base.value then has_playing = true end
        end
      end
      if has_hand_target then sections[#sections + 1] = hand_section() end
      if has_planet then sections[#sections + 1] = levels_section() end
      if has_playing then sections[#sections + 1] = deck_cards_section() end
    end

  end

  local output = {}
  for _, section in ipairs(sections) do
    if section then
      if opts.split == "volatile" then
        if not is_stable_line(section) then output[#output + 1] = section end
      elseif opts.split == "stable" then
        if is_stable_line(section) then output[#output + 1] = section end
      else
        output[#output + 1] = section
      end
    end
  end

  output = enforce_budget(state_name, output, opts.split)
  local result = concat_sections(output)
  if not opts.no_cache then
    _ctx_cache = result
    _ctx_cache_key = cache_key
    _ctx_cache_at = t
  end
  Metrics.incr("ctx_cache_miss")
  Metrics.time_end("ctx_build")
  return result
end

function ContextCompact.invalidate_cache()
  _ctx_cache = nil
  _ctx_cache_key = nil
end

function ContextCompact.decision_fingerprint(state_name, payload)
  local source = payload
  if type(source) ~= "string" or source == "" then
    local allowed_actions = nil
    local ok_actions, Actions = pcall(require, "core.actions")
    if ok_actions and Actions and Actions.get_valid_actions_for_state then
      local ok_list, list = pcall(Actions.get_valid_actions_for_state, state_name)
      if ok_list and type(list) == "table" then
        allowed_actions = list
      end
    end
    -- volatile split only: stable FRAME|/RUN|/V/JD could evict the volatile sections the fingerprint depends on
    source = ContextCompact.build(state_name, allowed_actions, { split = "volatile" })
  end

  local allow = get_pack_fallback(FP_KEYS, state_name) or {}
  local kept = {}
  local keep_current = false
  for line in tostring(source):gmatch("[^\n]+") do
    local id = line_header_id(line)
    if id == "STATE" then
      kept[#kept + 1] = line
      keep_current = false
    elseif id and (allow[id] or KNOWN_SECTION_IDS[id]) then
      keep_current = not not allow[id]
      if keep_current then kept[#kept + 1] = line end
    elseif keep_current then
      kept[#kept + 1] = line
    end
  end

  if #kept == 0 then
    return tostring(source)
  end
  return table.concat(kept, "\n")
end

return ContextCompact
