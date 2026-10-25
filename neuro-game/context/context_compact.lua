local ContextCompact = {}

local Metrics = require("util.metrics")
local Utils = require("util.utils")
local Lifecycle = require("core.neuro_lifecycle")
local StateKinds = require("core.state_kinds")
local CtxHelpers = require("context.ctx_helpers")
local CtxMisc = require("context.ctx_misc")
local CtxBlind = require("context.ctx_blind")
local CtxHand = require("context.ctx_hand")
local CtxJokers = require("context.ctx_jokers")
local CtxShop = require("context.ctx_shop")
local GameRules = require("context.game_rules")

local has_action = CtxHelpers.has_action

local function append_consumables(add, ctx)
  local set = ctx.action_set
  if (not ctx.has_filters) or has_action(set, "use_consumable") or has_action(set, "use_directional_consumable")
    or has_action(set, "sell_card") then
    add(CtxMisc.consumables_section(), "Consumables")
  end
end

local function append_frame_sections(add, state_name, split)
  if split ~= "state" then
    for _, frame in ipairs(ContextCompact.rule_frames()) do
      add({ text = frame.text, lifetime = "rule" })
    end
  end
  if split ~= "rule" then
    local ok_t, txt = pcall(GameRules.run_frame_text, state_name)
    if ok_t and type(txt) == "string" and txt ~= "" then add("RUN|" .. txt, "Run") end
  end
end

local function assemble_selecting_hand(add, ctx)
  local has_filters, action_set = ctx.has_filters, ctx.action_set
  add(CtxMisc.vouchers_section(), "Run")
  add(CtxMisc.tags_section(), "Run")
  add(CtxBlind.blind_line(), "Blind")
  add(CtxBlind.blind_debuff_line(), "Boss")
  add(CtxHand.last_play_section(ctx.state_name), "Round")
  add(CtxMisc.discard_count_line(), "Round")
  add(CtxHand.play_area_section(), "Round")
  add(CtxHand.hand_limits_section(has_filters and action_set or nil), "Your hand")
  add(CtxHand.hand_section(), "Your hand")
  ctx.anchor("Hand options")
  add(CtxJokers.jokers_section(ctx.state_name), "Your jokers")
  if (not has_filters) or has_action(action_set, "play_hand") or has_action(action_set, "discard_hand")
      or has_action(action_set, "use_consumable") then
    add(CtxHand.levels_section(), "Hand levels")
  end
  append_consumables(add, ctx)
  ctx.anchor("Constraints")
  add(CtxHand.deck_cards_section(), "Deck")
  add(CtxHand.draw_composition_section(), "Deck")
  add(CtxHand.deck_modifiers_section(), "Deck")
end

local function assemble_shop(add, ctx)
  local has_filters, action_set = ctx.has_filters, ctx.action_set
  add(CtxMisc.vouchers_section(), "Run")
  add(CtxMisc.tags_section(), "Run")
  add(CtxShop.shop_section(), "Shop")
  add(CtxShop.legality_section(ctx.state_name, action_set), "Legality")
  ctx.anchor("Constraints")
  ctx.anchor("Upcoming boss")
  ctx.anchor("Blinds ahead")
  ctx.anchor("Skip rules")
  add(CtxJokers.jokers_section(ctx.state_name), "Your jokers")
  append_consumables(add, ctx)
  if (not has_filters) or has_action(action_set, "use_consumable") or has_action(action_set, "use_directional_consumable") then
    add(CtxHand.hand_section(), "Your hand")
  end
  add(CtxHand.levels_section(), "Hand levels")
  add(CtxHand.deck_modifiers_section(), "Deck")
  add(CtxMisc.action_memory_section(ctx.state_name), "History")
  add(CtxHand.last_play_section(ctx.state_name), "History")
end

local function assemble_blind_select(add, ctx)
  add(CtxMisc.vouchers_section(), "Run")
  add(CtxMisc.tags_section(), "Run")
  add(CtxBlind.blind_select_section(), "Blinds")
  ctx.anchor("Boss")
  ctx.anchor("Blinds ahead")
  ctx.anchor("Skip rules")
  add(CtxHand.levels_section(), "Hand levels")
  add(CtxHand.hand_focus_options_section(), "Hand levels")
  add(CtxJokers.jokers_section(ctx.state_name), "Your jokers")
  append_consumables(add, ctx)
  add(CtxHand.deck_modifiers_section(), "Deck")
end

local function assemble_round_eval(add, ctx)
  add(CtxBlind.round_eval_section(), "Round")
  add(CtxHand.last_play_section(ctx.state_name), "Round")
  add(CtxJokers.jokers_section(ctx.state_name), "Your jokers")
end

local function assemble_pack(add, ctx)
  local state_name = ctx.state_name
  add(CtxMisc.vouchers_section(), "Run")
  add(CtxMisc.pack_section(), "Pack")
  ctx.anchor("Constraints")
  ctx.anchor("Skip rules")
  add(CtxJokers.jokers_section(state_name), "Your jokers")
  append_consumables(add, ctx)
  add(CtxHand.levels_section(), "Hand levels")
  local CU = require("facts.card_util")
  local bp = CU.pack_area()
  local has_playing, has_hand_target = false, false
  for _, card in ipairs((bp and bp.cards) or {}) do
    if not CU.is_hidden(card) then
      local set = CU.card_set(card)
      if set == "Tarot" or set == "Spectral" then has_hand_target = true end
      if card.base and card.base.suit and card.base.value then has_playing = true end
    end
  end
  if has_hand_target then add(CtxHand.hand_section(), "Your hand") end
  if has_playing then add(CtxHand.deck_cards_section(), "Deck") end
  add(CtxHand.deck_modifiers_section(), "Deck")
end

local STATE_ASSEMBLERS = {
  SELECTING_HAND = assemble_selecting_hand,
  SHOP = assemble_shop,
  BLIND_SELECT = assemble_blind_select,
  ROUND_EVAL = assemble_round_eval,
  SMODS_BOOSTER_OPENED = assemble_pack,
}

local IN_MOTION = {
  HAND_PLAYED = "The hand you played is being scored.",
  DRAW_TO_HAND = "Cards are being drawn into your hand.",
  NEW_ROUND = "The round is ending.",
  PLAY_TAROT = "A consumable's effect is resolving.",
  SMODS_REDEEM_VOUCHER = "A voucher is being redeemed.",
}
local IN_MOTION_OTHER = "The game is between screens; no decision is open on it."
local OWN_SCREEN = { MENU = true, RUN_SETUP = true, GAME_OVER = true, SPLASH = true }

local SPLIT_ALIAS = { stable = "rule", volatile = "state" }

function ContextCompact.build(state_name, allowed_actions, opts)
  opts = opts or {}
  Lifecycle.sync_joker_intent_revision()
  Metrics.incr("ctx_build_calls")
  Metrics.time_begin("ctx_build")
  local action_set = Utils.list_to_set(allowed_actions)
  local has_filters = allowed_actions ~= nil
  local split = SPLIT_ALIAS[opts.split] or opts.split

  local sections = {}
  local function add(section, heading)
    if type(section) == "string" then section = { text = section, heading = heading } end
    sections[#sections + 1] = section
  end
  local function anchor(heading) add({ text = "", heading = heading, anchor = true }) end
  append_frame_sections(add, state_name, split)
  add("STATE:" .. state_name)
  if state_name ~= "SELECTING_HAND" and state_name ~= "SHOP" then
    add(CtxMisc.action_memory_section(state_name), "History")
  end

  local setup_state = (state_name == "MENU" or state_name == "RUN_SETUP")
  if setup_state then add(CtxMisc.run_section(), "Run setup") end
  local function offers(name) return not has_filters or action_set[name] end
  if StateKinds.is_menu_state(state_name) and offers("select_deck") then
    add(CtxMisc.setup_decks_section(), "Run setup")
  end
  if setup_state and offers("select_stake") then add(CtxMisc.stake_list_line(), "Run setup") end
  if state_name == "GAME_OVER" then add(CtxMisc.game_over_section(), "Result") end
  if state_name == "SPLASH" then
    add("The game is on its splash screen: no run is in progress and nothing is in play yet.", "Game")
  end

  local assembler = STATE_ASSEMBLERS[state_name]
  if assembler then
    assembler(add, { state_name = state_name, has_filters = has_filters, action_set = action_set, anchor = anchor })
  elseif not (OWN_SCREEN[state_name] or StateKinds.is_pack_state(state_name)) then
    add(IN_MOTION[state_name] or IN_MOTION_OTHER, "Game")
  end

  local output = {}
  for _, section in ipairs(sections) do
    local text = section.text
    local lifetime = section.lifetime or "state"
    if text and (opts.blocks or not section.anchor) and ((split ~= "state" and split ~= "rule") or lifetime == split) then
      output[#output + 1] = opts.blocks and { heading = section.heading, text = text } or text
    end
  end

  local result = opts.return_list and output or table.concat(output, "\n")
  Metrics.time_end("ctx_build")
  return result
end

function ContextCompact.rule_frames()
  local out = {}
  local ok_f, txt = pcall(GameRules.invariant_frame)
  if ok_f and type(txt) == "string" and txt ~= "" then
    out[#out + 1] = { key = "frame", text = "FRAME|" .. txt }
  end
  for _, reference in ipairs({ GameRules.deck_reference, GameRules.challenge_reference }) do
    local ok, name, txt = pcall(reference)
    if ok and type(name) == "string" and type(txt) == "string" and txt ~= "" then
      out[#out + 1] = { key = name, text = txt }
    end
  end
  return out
end

return ContextCompact
