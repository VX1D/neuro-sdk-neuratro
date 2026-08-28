local ContextCompact = {}
local Metrics = require("util.metrics")
local GameFacts = require("facts.game_facts")
local Utils = require("util.utils")
local safe_name = Utils.safe_name
local flatten_description = Utils.flatten_description

local _gf = nil

local CtxHelpers = require("context.ctx_helpers")

local to_set = Utils.list_to_set

local has_action = CtxHelpers.has_action

local function concat_sections(sections)
  local out = {}
  for _, section in ipairs(sections) do
    if section then out[#out + 1] = section end
  end
  return table.concat(out, "\n")
end

local BOARD_AREAS = { "jokers", "playbook_extra", "consumeables", "hand", "play",
  "shop_jokers", "shop_vouchers", "shop_booster", "pack_cards", "booster_pack" }

local function card_fingerprint(card)
  local center = card.config and card.config.center or {}
  local ability = card.ability or {}
  local base = card.base or {}
  local extra = ability.extra
  if type(extra) == "table" then extra = flatten_description(extra) or "table" end
  return table.concat({
    tostring(center.key or center.name or safe_name(card) or "?"),
    tostring(ability.name or "-"), tostring(ability.set or "-"),
    tostring(extra or "-"),
    CtxHelpers.ability_signature(ability),
    tostring(ability.enhancement or "-"),
    tostring(card.seal or "-"),
    tostring((card.edition and (card.edition.key or card.edition.type)) or "-"),
    tostring(base.value or "-"), tostring(base.suit or "-"),
    tostring(card.cost or "-"), tostring(card.sell_cost or "-"),
    (ability.eternal and "E" or "-") .. (ability.perishable and "P" or "-")
      .. (ability.rental and "R" or "-") .. (card.debuff and "D" or "-")
      .. (card.facing == "back" and "F" or "-"),
  }, ":")
end

local function board_signature()
  if not G then return "none" end
  local parts = {}
  for _, name in ipairs(BOARD_AREAS) do
    local area = rawget(G, name)
    local cards = type(area) == "table" and area.cards
    if type(cards) == "table" then
      parts[#parts + 1] = name .. "#" .. #cards
      for i, card in ipairs(cards) do
        parts[#parts + 1] = i .. "=" .. card_fingerprint(card)
      end
      local limit = area.config and area.config.card_limit
      if limit then parts[#parts + 1] = "L" .. tostring(limit) end
    end
  end
  local gm = G.GAME
  if type(gm) == "table" then
    local used = {}
    for key in pairs(gm.used_vouchers or {}) do used[#used + 1] = tostring(key) end
    table.sort(used)
    parts[#parts + 1] = "V:" .. table.concat(used, ",")
    local tags = {}
    for _, tag in ipairs(gm.tags or {}) do
      tags[#tags + 1] = tostring((type(tag) == "table" and (tag.key or tag.name)) or tag)
    end
    parts[#parts + 1] = "T:" .. table.concat(tags, ",")
  end
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
local blind_select_section = CtxBlind.blind_select_section
local round_eval_section = CtxBlind.round_eval_section

local CtxHand = require("context.ctx_hand")
local hand_section = CtxHand.hand_section
local hand_limits_section = CtxHand.hand_limits_section
local levels_section = CtxHand.levels_section
local deck_cards_section = CtxHand.deck_cards_section
local draw_composition_section = CtxHand.draw_composition_section
local deck_modifiers_section = CtxHand.deck_modifiers_section
local play_area_section = CtxHand.play_area_section
local deck_content_signature = CtxHand.deck_content_signature
local hand_focus_options_section = CtxHand.hand_focus_options_section
local last_play_section = CtxHand.last_play_section

local CtxJokers = require("context.ctx_jokers")
local jokers_section = CtxJokers.jokers_section
local playbook_section = CtxJokers.playbook_section

local function owned_section(lifetime, text, name)
  if not text then return nil end
  return { text = text, lifetime = lifetime, name = name }
end

local function append_joker_sections(sections, state_name)
  sections[#sections + 1] = jokers_section(state_name)
  sections[#sections + 1] = playbook_section(true)
end

local function append_consumables(sections, has_filters, action_set)
  if (not has_filters) or has_action(action_set, "use_card") or has_action(action_set, "use_directional_card")
    or has_action(action_set, "sell_card") then
    sections[#sections + 1] = consumables_section()
  end
end

local CtxShop = require("context.ctx_shop")
local StateKinds = require("core.state_kinds")
local legality_section = CtxShop.legality_section

local shop_section = CtxShop.shop_section

local function append_frame_sections(sections, state_name, split)
  local ok, GameRules = pcall(require, "context.game_rules")
  if not ok or type(GameRules) ~= "table" then return end

  if split ~= "state" then
    if type(GameRules.invariant_frame) == "function" then
      local ok_f, txt = pcall(GameRules.invariant_frame)
      if ok_f and type(txt) == "string" and txt ~= "" then
        sections[#sections + 1] = owned_section("rule", "FRAME|" .. txt, "frame")
      end
    end

    if type(GameRules.deck_reference) == "function" then
      local ok_d, name, txt = pcall(GameRules.deck_reference)
      if ok_d and type(name) == "string" and type(txt) == "string" and txt ~= "" then
        sections[#sections + 1] = owned_section("rule", txt, name)
      end
    end
  end

  if split ~= "rule" then
    if type(GameRules.run_frame_text) == "function" then
      local ok_t, txt = pcall(GameRules.run_frame_text, state_name)
      if ok_t and type(txt) == "string" and txt ~= "" then
        sections[#sections + 1] = owned_section("state", "RUN|" .. txt)
      end
    end
  end
end

local _ctx_cache = nil
local _ctx_cache_key = nil
local _ctx_cache_at = 0
local now_time = function() return Utils.gate_now("ctx_cache_ttl") end

local function assemble_selecting_hand(sections, ctx)
  local has_filters, action_set = ctx.has_filters, ctx.action_set
  sections[#sections + 1] = blind_line()
  sections[#sections + 1] = last_play_section(ctx.state_name)
  sections[#sections + 1] = deck_size_line()
  sections[#sections + 1] = play_area_section()
  sections[#sections + 1] = vouchers_section()
  sections[#sections + 1] = tags_section()
  sections[#sections + 1] = hand_limits_section()
  sections[#sections + 1] = hand_section()
  append_joker_sections(sections, ctx.state_name)
  if (not has_filters) or has_action(action_set, "play_hand") or has_action(action_set, "discard_hand") then
    sections[#sections + 1] = levels_section()
  end
  append_consumables(sections, has_filters, action_set)
  sections[#sections + 1] = deck_cards_section()
  sections[#sections + 1] = draw_composition_section()
  sections[#sections + 1] = deck_modifiers_section()
end

local function assemble_shop(sections, ctx)
  local has_filters, action_set = ctx.has_filters, ctx.action_set
  local stock = shop_section()
  if stock then sections[#sections + 1] = stock end
  sections[#sections + 1] = legality_section(ctx.state_name, action_set)
  sections[#sections + 1] = action_memory_section(ctx.state_name)
  sections[#sections + 1] = vouchers_section()
  sections[#sections + 1] = tags_section()
  append_joker_sections(sections, ctx.state_name)
  append_consumables(sections, has_filters, action_set)
  if (not has_filters) or has_action(action_set, "use_card") or has_action(action_set, "use_directional_card") then
    sections[#sections + 1] = hand_section()
  end
  sections[#sections + 1] = levels_section()
  sections[#sections + 1] = deck_modifiers_section()
  local lp = last_play_section(ctx.state_name)
  if lp then sections[#sections + 1] = lp end
end

local function assemble_blind_select(sections, ctx)
  local has_filters, action_set = ctx.has_filters, ctx.action_set
  sections[#sections + 1] = vouchers_section()
  sections[#sections + 1] = tags_section()
  sections[#sections + 1] = blind_select_section()
  sections[#sections + 1] = levels_section()
  sections[#sections + 1] = hand_focus_options_section()
  append_joker_sections(sections, ctx.state_name)
  append_consumables(sections, has_filters, action_set)
  sections[#sections + 1] = deck_modifiers_section()
end

local function assemble_round_eval(sections, ctx)
  sections[#sections + 1] = round_eval_section()
  sections[#sections + 1] = last_play_section(ctx.state_name)
  append_joker_sections(sections, ctx.state_name)
end

local function assemble_pack(sections, ctx)
  local state_name, has_filters, action_set = ctx.state_name, ctx.has_filters, ctx.action_set
  sections[#sections + 1] = pack_section(state_name)
  sections[#sections + 1] = vouchers_section()
  append_joker_sections(sections, ctx.state_name)
  append_consumables(sections, has_filters, action_set)
  if state_name == "TAROT_PACK" or state_name == "SPECTRAL_PACK" then
    sections[#sections + 1] = hand_section()
  end

  local levels_emitted = false
  local function emit_levels_once()
    if levels_emitted then return end
    levels_emitted = true
    sections[#sections + 1] = levels_section()
  end

  emit_levels_once()
  if state_name == "STANDARD_PACK" then
    sections[#sections + 1] = hand_section()
    sections[#sections + 1] = deck_cards_section()
  end
  if state_name == "SMODS_BOOSTER_OPENED" then
    local CU = require("facts.card_util")
    local bp = CU.pack_area()
    local has_planet, has_playing, has_hand_target = false, false, false
    if bp and bp.cards then
      for _, card in ipairs(bp.cards) do
        local set = CU.card_set(card)
        if set == "Planet" then has_planet = true end
        if set == "Tarot" or set == "Spectral" then has_hand_target = true end
        if card and card.base and card.base.suit and card.base.value then has_playing = true end
      end
    end
    if has_hand_target then sections[#sections + 1] = hand_section() end
    if has_planet then emit_levels_once() end
    if has_playing then sections[#sections + 1] = deck_cards_section() end
  end
  sections[#sections + 1] = deck_modifiers_section()
end

local STATE_ASSEMBLERS = {
  SELECTING_HAND = assemble_selecting_hand,
  SHOP = assemble_shop,
  BLIND_SELECT = assemble_blind_select,
  ROUND_EVAL = assemble_round_eval,
  TAROT_PACK = assemble_pack,
  PLANET_PACK = assemble_pack,
  SPECTRAL_PACK = assemble_pack,
  STANDARD_PACK = assemble_pack,
  BUFFOON_PACK = assemble_pack,
  SMODS_BOOSTER_OPENED = assemble_pack,
}

function ContextCompact.build(state_name, allowed_actions, opts)
  opts = opts or {}
  Metrics.incr("ctx_build_calls")
  Metrics.time_begin("ctx_build")
  local action_set = to_set(allowed_actions)
  local has_filters = allowed_actions ~= nil

  local cache_key, t, cache_dt
  if not opts.no_cache then
    local action_key = "*"
    if has_filters then
      local parts = {}
      for _, a in ipairs(allowed_actions) do parts[#parts + 1] = tostring(a) end
      table.sort(parts)
      action_key = table.concat(parts, ",")
    end
    _gf = GameFacts.build()
    cache_key = table.concat({
      tostring(state_name or "?"),
      action_key,
      board_signature(),
      _gf.content_sig or "",
      deck_content_signature(),
      opts.split or "full",
    }, "|")

    t = now_time()
    cache_dt = t - _ctx_cache_at
    -- Game:main_menu rewinds the clock (dump game.lua:1556-1558), which happens on every return
    -- to the menu; without the dt >= 0 guard a rewind makes cache_dt negative, trivially "fresh",
    -- and a stale cache from before the rewind survives it (util/utils.lua:213's cache_is_fresh
    -- is the same pattern, guarded).
    if _ctx_cache and _ctx_cache_key == cache_key
        and cache_dt >= 0 and cache_dt < Utils.gate_seconds("ctx_cache_ttl") then
      Metrics.incr("ctx_cache_hit")
      Metrics.time_end("ctx_build")
      return _ctx_cache
    end
  end

  local split = opts.split
  if split == "stable" then split = "rule" end
  if split == "volatile" then split = "state" end

  local sections = {}
  append_frame_sections(sections, state_name, split)
  sections[#sections + 1] = header_section(state_name)
  if state_name ~= "SHOP" and not StateKinds.is_menu_state(state_name) then
    sections[#sections + 1] = legality_section(state_name, action_set)
  end
  if state_name ~= "SELECTING_HAND" and state_name ~= "SHOP" then
    sections[#sections + 1] = action_memory_section(state_name)
  end

  local setup_state = (state_name == "MENU" or state_name == "RUN_SETUP")
  if setup_state then
    sections[#sections + 1] = run_section()
  end
  if StateKinds.is_menu_state(state_name) then
    sections[#sections + 1] = setup_decks_section(setup_state)
  end
  if setup_state then
    sections[#sections + 1] = stake_list_line()
  end

  if state_name == "GAME_OVER" then
    sections[#sections + 1] = game_over_section()
  end

  if state_name == "SPLASH" then
    sections[#sections + 1] =
      "The game is on its splash screen: no run is in progress and nothing is in play yet."
  end

  local assembler = STATE_ASSEMBLERS[state_name]
  if not assembler and state_name and state_name:find("_PACK$") then assembler = assemble_pack end
  if assembler then
    assembler(sections, {
      state_name = state_name,
      has_filters = has_filters,
      action_set = action_set,
      opts = opts,
    })
  end

  local keyed = opts.keyed and opts.return_list
  local output = {}
  for _, section in ipairs(sections) do
    local text = (type(section) == "table") and section.text or section
    if text then
      local lifetime = (type(section) == "table" and section.lifetime) or "state"
      local entry = text
      if keyed then
        entry = { key = (type(section) == "table" and section.name) or text, text = text }
      end
      if split == "state" then
        if lifetime == "state" then output[#output + 1] = entry end
      elseif split == "rule" then
        if lifetime == "rule" then output[#output + 1] = entry end
      else
        output[#output + 1] = entry
      end
    end
  end

  if opts.return_list then
    Metrics.time_end("ctx_build")
    return output
  end
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

function ContextCompact.rule_frames(_state_name)
  local ok, GameRules = pcall(require, "context.game_rules")
  if not ok or type(GameRules) ~= "table" then return {} end

  local out = {}
  if type(GameRules.invariant_frame) == "function" then
    local ok_f, txt = pcall(GameRules.invariant_frame)
    if ok_f and type(txt) == "string" and txt ~= "" then
      out[#out + 1] = { key = "frame", text = "FRAME|" .. txt }
    end
  end

  if type(GameRules.deck_reference) == "function" then
    local ok_d, name, txt = pcall(GameRules.deck_reference)
    if ok_d and type(name) == "string" and type(txt) == "string" and txt ~= "" then
      out[#out + 1] = { key = name, text = txt }
    end
  end

  return out
end

return ContextCompact
