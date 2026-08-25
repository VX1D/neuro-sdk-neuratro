local Utils = require("util.utils")
local GameFacts = require("facts.game_facts")
local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("facts.economy_facts")
local DebuffFacts = require("facts.debuff_facts")
local CardUtil = require("facts.card_util")
local normalize_text = CtxHelpers.normalize_text
local normalize_prose = CtxHelpers.normalize_prose
local money = CtxHelpers.money
local plural = CtxHelpers.plural
local yn = CtxHelpers.yn
local decode_payout = CtxHelpers.decode_payout
local safe_description = Utils.safe_description
local economy_projection = CtxEconomy.economy_projection
local calc_interest = CtxEconomy.calc_interest
local calc_blind_target = CtxEconomy.calc_blind_target

local M = {}

local function blind_line()
  if not G or not G.GAME or not G.GAME.blind then return nil end
  local blind = G.GAME.blind
  local current_score = G.GAME.chips or 0
  local remaining = CtxEconomy.blind_remaining(blind) or 0
  local hands = GameFacts.hands_left()
  local discards = GameFacts.discards_left()
  local money_now = G.GAME.dollars or 0
  local econ = economy_projection({ selecting_hand = true })
  local name = blind.name or "Unknown"
  local ante = GameFacts.ante("?")
  local win_ante = G.GAME.win_ante or 8
  local no_interest = CtxEconomy.no_interest()
  local discard_cost = G.GAME.modifiers and G.GAME.modifiers.discard_cost
  local scaling = G.GAME.modifiers and G.GAME.modifiers.scaling
  local ante_mult = G.GAME.starting_params and G.GAME.starting_params.ante_scaling
  local mod_parts = {}
  if no_interest then mod_parts[#mod_parts + 1] = "no interest" end
  if discard_cost and discard_cost > 0 then mod_parts[#mod_parts + 1] = "discard costs $" .. tostring(discard_cost) end
  if scaling and scaling ~= 1 then mod_parts[#mod_parts + 1] = "harder blind scaling" end
  if ante_mult and ante_mult ~= 1 then mod_parts[#mod_parts + 1] = "blind targets x" .. tostring(ante_mult) end
  local need_per_hand = CardUtil.score_per_hand(remaining, hands) or 0
  local debt_floor = CtxEconomy.spend_floor()

  local p = { string.format("Blind: %s (ante %s/%s).", normalize_text(name), tostring(ante), tostring(win_ante)) }
  if hands == 0 and remaining ~= 0 then
    p[#p + 1] = string.format("Score %s, %s to go -- no hands left, so the target cannot be cleared this round.",
      Utils.fmt_num(current_score), Utils.fmt_num(remaining))
  else
    p[#p + 1] = string.format("Score %s, %s to go, about %s needed per hand.",
      Utils.fmt_num(current_score), Utils.fmt_num(remaining), Utils.fmt_num(need_per_hand))
  end
  local bank_note = money(money_now) .. " in the bank"
  if debt_floor ~= 0 then bank_note = bank_note .. " (spend floor " .. money(debt_floor) .. ")" end
  local below_floor = CtxEconomy.below_spend_floor_reason(money_now)
  if below_floor then bank_note = bank_note .. "; " .. below_floor end
  if hands == 0 then
    p[#p + 1] = string.format("%s left. %s.", plural(discards, "discard"), bank_note)
  else
    p[#p + 1] = string.format("%s and %s left. %s.", plural(hands, "hand"), plural(discards, "discard"), bank_note)
  end
  p[#p + 1] = "Cash-out if this hand clears the blind: " .. decode_payout(econ or {}) .. "."
  if #mod_parts > 0 then p[#p + 1] = "Modifiers: " .. table.concat(mod_parts, ", ") .. "." end
  return table.concat(p, " ")
end

local BossRender = require("facts.boss.render")
local BossModel = require("facts.boss.model")

local function blind_debuff_line()
  if not (G and G.GAME and G.GAME.blind) then return nil end
  local blind = G.GAME.blind
  local key = BossModel.resolve_key(blind)
  if not blind.disabled and (key or blind.boss) then
    return BossRender.boss_line("status", key, blind)
  end
  if not key then
    local up = BossRender.upcoming_boss_key()
    local rec = up and BossModel.get(up)
    if rec and rec.horizon and rec.horizon.ante then
      return BossRender.render("ante", up)
    end
    return nil
  end
  return nil
end

local BLIND_STATUS = {
  Select = "your current choice", Upcoming = "upcoming", Defeated = "defeated",
  Skipped = "skipped", Current = "in progress", Selected = "selected",
}
local function blind_status(s) return BLIND_STATUS[s] or (s and tostring(s):lower()) or "?" end

local function boss_effect_text(key, blind_def)
  local curated = BossRender.render("select", key, { blind = blind_def, no_prefix = true })
  if curated then return normalize_prose(curated) end
  local txt = DebuffFacts.blind_effect_text(key, blind_def)
  if (txt == "" or not txt) and type(blind_def.debuff) == "table" and blind_def.debuff.text then
    txt = blind_def.debuff.text
  end
  if txt and txt ~= "" then return normalize_prose(txt) end
  return nil
end

local function blind_row_name(btype, key, blind_def)
  local nm = normalize_text(blind_def.name or key)
  return nm:find("[Bb]lind") and nm or (btype .. " blind " .. nm)
end

local function boss_row_label()
  local rr = G and G.GAME and G.GAME.round_resets
  local key = rr and rr.blind_choices and rr.blind_choices.Boss
  local blind_def = key and G.P_BLINDS and G.P_BLINDS[key]
  if not blind_def or not boss_effect_text(key, blind_def) then return nil end
  return blind_row_name("Boss", key, blind_def)
end

local function blind_select_section()
  if not G or not G.GAME then return nil end
  local ante = GameFacts.ante("?")
  local money_now = G.GAME.dollars or 0
  local hands = GameFacts.hands_left()
  local discards = GameFacts.discards_left()
  local no_interest = CtxEconomy.no_interest()
  local econ = economy_projection({ exclude_action_bonus = true })
  local skips = G.GAME.skips or 0

  local lines = {}
  local p = { string.format("Choosing a blind (ante %s). %s in bank.", tostring(ante), money(money_now)) }
  p[#p + 1] = string.format("%s and %s before effects triggered by selecting the blind (boss or Joker).",
    plural(hands, "hand"), plural(discards, "discard"))
  if normalize_text(G.GAME.blind_on_deck or "") == "Boss" then
    p[#p + 1] = "A boss blind can change that when it starts -- its row below states what it does."
  end
  p[#p + 1] = "Interest " .. (no_interest and "disabled" or "enabled") .. "."
  p[#p + 1] = "Cash-out if the round ended now: " .. decode_payout(econ or {}) .. "."
  if skips > 0 then p[#p + 1] = tostring(skips) .. " blind(s) skipped so far." end
  lines[#lines + 1] = table.concat(p, " ")

  if G.GAME.round_resets and G.GAME.round_resets.blind_states then
    local bs = G.GAME.round_resets.blind_states
    local on_deck = normalize_text(G.GAME.blind_on_deck or "?")
    lines[#lines + 1] = string.format("Blinds this ante: small is %s, big is %s, boss is %s (on deck: %s).",
      blind_status(normalize_text(bs.Small or "?")),
      blind_status(normalize_text(bs.Big or "?")),
      blind_status(normalize_text(bs.Boss or "?")),
      on_deck)
  end

  local can_skip = false
  do
    local ok_a, Actions = pcall(require, "core.actions")
    if ok_a and Actions and Actions.is_action_valid and Actions.is_action_valid("skip_blind") then
      can_skip = true
    end
  end
  local reroll_cost = CtxEconomy.BOSS_REROLL_COST
  local can_reroll, reroll_enabled = CtxEconomy.can_reroll_boss()
  lines[#lines + 1] = string.format("You may skip this blind: %s. Boss reroll: %s (cost $%s), reroll %s.",
    yn(can_skip), yn(can_reroll), tostring(reroll_cost), reroll_enabled and "enabled" or "disabled")

  if G.GAME.round_resets and G.GAME.round_resets.blind_choices then
    local choices = G.GAME.round_resets.blind_choices
    local states = G.GAME.round_resets.blind_states or {}
    local tags = G.GAME.round_resets.blind_tags or {}
    for _, btype in ipairs({ "Small", "Big", "Boss" }) do
      local key = choices[btype]
      if key and G.P_BLINDS and G.P_BLINDS[key] then
        local blind_def = G.P_BLINDS[key]
        local debuff_text = nil
        if btype == "Boss" then
          debuff_text = boss_effect_text(key, blind_def)
        elseif type(blind_def.debuff) == "table" and next(blind_def.debuff) ~= nil then
          local txt = DebuffFacts.blind_effect_text(key, blind_def)
          if (txt == "" or not txt) and blind_def.debuff.text then
            txt = blind_def.debuff.text
          end
          if txt and txt ~= "" then debuff_text = normalize_prose(txt) end
        end

        local tag_key = tags[btype]
        local tag_name, tag_effect = nil, nil
        if tag_key then
          local tag_def = G.P_TAGS and G.P_TAGS[tag_key]
          tag_name = normalize_text((tag_def and tag_def.name) or tag_key)
          local desc = DebuffFacts.tag_effect_text(tag_key)
          if (not desc or desc == "") and tag_def then
            desc = safe_description(tag_def.loc_txt)
            if not desc or desc == "" then
              local rt = tag_def.config and tag_def.config.ref_table
              if rt and rt.loc_txt then desc = safe_description(rt.loc_txt) end
            end
          end
          if desc and desc ~= "" then tag_effect = normalize_prose(desc) end
        end

        local target = calc_blind_target(key)
        local reward = blind_def.dollars or 0
        local nbr = G.GAME.modifiers and G.GAME.modifiers.no_blind_reward
        if nbr and nbr[btype] then reward = 0 end

        local s = blind_row_name(btype, key, blind_def)
          .. " (" .. normalize_text(states[btype] or "?")
          .. "): needs " .. (target and Utils.fmt_num(target) or "?") .. " chips, reward $" .. reward
        if target and normalize_text(states[btype] or "") == "Select" then
          local per = CardUtil.score_per_hand(target, hands)
          if per and per > 0 then
            s = s .. string.format(", about %s per hand over %s",
              Utils.fmt_num(per), plural(hands, "hand"))
          end
        end
        if tag_name then
          s = s .. ". Skip tag " .. tag_name
          if tag_effect then s = s .. " (" .. tag_effect .. ")" end
          local class = require("facts.tag_facts").class_prose(tag_key)
          if class ~= "" then s = s .. " -- " .. class end
        end
        if debuff_text then s = s .. ". Effect: " .. debuff_text end
        lines[#lines + 1] = s:match("[%.!%?]$") and s or (s .. ".")
      end
    end
  end

  return table.concat(lines, "\n")
end

local function round_eval_section()
  if not G or not G.GAME then return nil end
  local money_now = G.GAME.dollars or 0
  local interest = calc_interest(money_now)
  local ante = (G.GAME.round_resets and G.GAME.round_resets.blind_ante) or GameFacts.ante("?")
  local round = G.GAME.round or "?"
  local econ = economy_projection({ round_eval = true })

  local p = { string.format("Round %s of ante %s cleared. %s in bank.", tostring(round), tostring(ante), money(money_now)) }
  p[#p + 1] = CtxEconomy.interest_line(interest) .. "."
  if econ and (econ.blind_reward > 0 or econ.hands_bonus > 0 or econ.discard_bonus > 0 or econ.interest > 0) then
    p[#p + 1] = "Earnings: " .. decode_payout(econ) .. "."
  end
  return table.concat(p, " ")
end

M.blind_line = blind_line
M.blind_debuff_line = blind_debuff_line
M.blind_select_section = blind_select_section
M.boss_row_label = boss_row_label
M.round_eval_section = round_eval_section

return M
