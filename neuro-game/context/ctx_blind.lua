local Utils = require("util.utils")
local GameFacts = require("facts.game_facts")
local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("facts.economy_facts")
local DebuffFacts = require("facts.debuff_facts")
local CardUtil = require("facts.card_util")
local DisplayNames = require("facts.display_names")
local normalize_text = CtxHelpers.normalize_text
local normalize_prose = CtxHelpers.normalize_prose
local money = Utils.money
local plural = CtxHelpers.plural
local yn = CtxHelpers.yn
local economy_projection = CtxEconomy.economy_projection
local calc_interest = CtxEconomy.calc_interest
local calc_blind_target = CtxEconomy.calc_blind_target

local M = {}

local function cashout_payout(econ)
  local t = econ.tooth
  local function range(a, b) return (a == b) and money(a) or (money(a) .. "-" .. money(b)) end
  local no_int = CtxEconomy.no_interest()
  local total = range(econ.projected_total or 0, t and t.projected_max or econ.projected_total or 0)
  local interest = no_int and "" or (" + interest " .. range(econ.interest or 0, t and t.interest_max or econ.interest or 0))
  local notes = {}
  if t and not no_int then
    notes[#notes + 1] = string.format("interest is counted after The Tooth takes %s per card you play (%s)",
      money(t.per_card), (t.min_cards == t.max_cards) and range(t.per_card * t.min_cards, t.per_card * t.min_cards)
        or (range(t.per_card * t.min_cards, t.per_card * t.max_cards) .. " for " .. t.min_cards .. "-"
          .. t.max_cards .. " cards"))
  end
  if econ.ox_hand and not no_int then
    notes[#notes + 1] = "if that hand is a " .. tostring((DebuffFacts.loc_hand and DebuffFacts.loc_hand(econ.ox_hand)) or econ.ox_hand)
      .. ", interest is $0 (The Ox empties the bank first)"
  end
  return string.format("%s (blind %s + hands %s + discards %s%s)%s; money jokers/tags add more",
    total, money(econ.blind_reward), money(econ.hands_bonus), money(econ.discard_bonus), interest,
    (#notes > 0) and ("; " .. table.concat(notes, "; ")) or "")
end

local function blind_line()
  if not G or not G.GAME or not G.GAME.blind then return nil end
  local blind = G.GAME.blind
  local current_score = G.GAME.chips or 0
  local remaining = CtxEconomy.blind_remaining(blind) or 0
  local hands = GameFacts.hands_left()
  local discards = GameFacts.discards_left()
  local money_now = G.GAME.dollars or 0
  local econ = economy_projection({ selecting_hand = true })
  local name = DisplayNames.live_blind(blind) or "Unknown"
  local no_interest = CtxEconomy.no_interest()
  local discard_cost = G.GAME.modifiers and G.GAME.modifiers.discard_cost
  local scaling = G.GAME.modifiers and G.GAME.modifiers.scaling
  local ante_mult = G.GAME.starting_params and G.GAME.starting_params.ante_scaling
  local mod_parts = {}
  if no_interest then mod_parts[#mod_parts + 1] = "no interest" end
  if discard_cost and discard_cost > 0 then mod_parts[#mod_parts + 1] = "discard costs " .. money(discard_cost) end
  if scaling and scaling ~= 1 then mod_parts[#mod_parts + 1] = "harder blind scaling" end
  if ante_mult and ante_mult ~= 1 then mod_parts[#mod_parts + 1] = "blind targets x" .. tostring(ante_mult) end
  local need_per_hand = CardUtil.score_per_hand(remaining, hands) or 0
  local debt_floor = CtxEconomy.spend_floor()

  local p = { string.format("Blind: %s (%s).", normalize_text(name), GameFacts.ante_progress()) }
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
  p[#p + 1] = "Cash-out if this hand clears the blind: " .. cashout_payout(econ or {}) .. "."
  if #mod_parts > 0 then p[#p + 1] = "Modifiers: " .. table.concat(mod_parts, ", ") .. "." end
  return table.concat(p, "\n")
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
  if key then return nil end
  local up = BossRender.upcoming_boss_key()
  local rec = up and BossModel.get(up)
  if rec and rec.horizon and rec.horizon.ante then return BossRender.render("ante", up) end
  return nil
end

local BLIND_STATUS = {
  Select = "your current choice", Upcoming = "upcoming", Defeated = "defeated",
  Skipped = "skipped", Current = "in progress", Selected = "selected",
}
local function blind_status(s) return BLIND_STATUS[s] or (s and tostring(s):lower()) or "?" end

local function debuff_effect_text(key, blind_def)
  local txt = DebuffFacts.blind_effect_text(key, blind_def)
  if (txt == "" or not txt) and type(blind_def.debuff) == "table" and blind_def.debuff.text then
    txt = blind_def.debuff.text
  end
  if txt and txt ~= "" then return normalize_prose(txt) end
  return nil
end

local function boss_effect_text(key, blind_def)
  local curated = BossRender.render("select", key, { blind = blind_def, no_prefix = true })
  if curated then return normalize_prose(curated) end
  return debuff_effect_text(key, blind_def)
end

local function blind_row_name(btype, key)
  local nm = normalize_text(DisplayNames.blind(key))
  return nm:find("[Bb]lind") and nm or (btype .. " blind " .. nm)
end

local function upcoming_boss()
  local rr = G and G.GAME and G.GAME.round_resets
  local key = rr and rr.blind_choices and rr.blind_choices.Boss
  return key, key and G.P_BLINDS and G.P_BLINDS[key], rr
end

local function boss_row_label()
  local key, blind_def = upcoming_boss()
  if not blind_def or not boss_effect_text(key, blind_def) then return nil end
  return blind_row_name("Boss", key)
end

local function blind_select_section()
  if not G or not G.GAME then return nil end
  local money_now = G.GAME.dollars or 0
  local hands = GameFacts.hands_left()
  local discards = GameFacts.discards_left()
  local no_interest = CtxEconomy.no_interest()
  local skips = G.GAME.skips or 0

  local lines = {}
  local won = GameFacts.run_progress().won
  local p = { "Choosing a blind: " .. GameFacts.ante_progress()
    .. (won and "; blinds keep scaling and the run goes on until one beats you." or " (beat the final Boss to win)."),
    money(money_now) .. " in bank." }
  p[#p + 1] = string.format("%s and %s before effects triggered by selecting the blind (boss or Joker).",
    plural(hands, "hand"), plural(discards, "discard"))
  if normalize_text(G.GAME.blind_on_deck or "") == "Boss" then
    p[#p + 1] = "A boss blind can change that when it starts -- its row below states what it does."
  end
  p[#p + 1] = "Interest " .. (no_interest and "disabled" or "enabled") .. "."
  if skips > 0 then p[#p + 1] = tostring(skips) .. " blind(s) skipped so far." end
  lines[#lines + 1] = table.concat(p, "\n")

  if G.GAME.round_resets and G.GAME.round_resets.blind_states then
    local bs = G.GAME.round_resets.blind_states
    local on_deck = normalize_text(G.GAME.blind_on_deck or "?")
    lines[#lines + 1] = string.format("Blinds this ante: small is %s, big is %s, boss is %s (on deck: %s).",
      blind_status(normalize_text(bs.Small or "?")),
      blind_status(normalize_text(bs.Big or "?")),
      blind_status(normalize_text(bs.Boss or "?")),
      on_deck)
  end

  local can_skip = require("core.actions").is_action_valid("skip_blind")
  local reroll_cost = CtxEconomy.BOSS_REROLL_COST
  local can_reroll, reroll_enabled = CtxEconomy.can_reroll_boss()
  lines[#lines + 1] = string.format("You may skip this blind: %s.\nBoss reroll: %s (cost %s), reroll %s.",
    yn(can_skip), yn(can_reroll), money(reroll_cost), reroll_enabled and "enabled" or "disabled")

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
          debuff_text = debuff_effect_text(key, blind_def)
        end

        local tag_key = tags[btype]
        local tag_name, tag_effect = nil, nil
        if tag_key then
          tag_name = normalize_text(DisplayNames.tag(tag_key))
          local desc = DebuffFacts.tag_effect_text(tag_key, require("facts.tag_facts").blind_tag(btype, tag_key))
          if desc ~= "" then tag_effect = normalize_prose(desc) end
        end

        local target = calc_blind_target(key)
        local reward = blind_def.dollars or 0
        local nbr = G.GAME.modifiers and G.GAME.modifiers.no_blind_reward
        if nbr and nbr[btype] then reward = 0 end

        local s = blind_row_name(btype, key)
          .. " (" .. normalize_text(states[btype] or "?")
          .. "): needs " .. (target and Utils.fmt_num(target) or "?") .. " chips, reward " .. money(reward)
        if target and normalize_text(states[btype] or "") == "Select" then
          local round_hands = BossModel.round_hands(key, hands)
          local per = CardUtil.score_per_hand(target, round_hands)
          if per and per > 0 then
            s = s .. string.format(", about %s per hand over %s",
              Utils.fmt_num(per), plural(round_hands, "hand"))
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

  local result = GameFacts.round_outcome()
  local ended = (result and not result.beaten)
    and ("ended without beating the blind. " .. result.rescue .. ".") or "cleared."
  local p = { string.format("Round %s of ante %s %s %s in bank.", tostring(round), tostring(ante), ended, money(money_now)) }
  p[#p + 1] = CtxEconomy.interest_line(interest) .. "."
  local paid = GameFacts.cash_out_payout()
  if paid and econ then
    local parts = { "blind " .. money(econ.blind_reward), "hands " .. money(econ.hands_bonus),
      "discards " .. money(econ.discard_bonus) }
    if not CtxEconomy.no_interest() then parts[#parts + 1] = "interest " .. money(econ.interest) end
    local other = paid - econ.projected_total
    if other > 0 then parts[#parts + 1] = "jokers/tags " .. money(other) end
    p[#p + 1] = "Earnings: " .. money(paid)
      .. (other >= 0 and (" (" .. table.concat(parts, " + ") .. ")") or "") .. ", paid when you cash out."
  end
  return table.concat(p, "\n")
end

M.blind_line = blind_line
M.blind_debuff_line = blind_debuff_line
M.blind_select_section = blind_select_section
M.boss_row_label = boss_row_label
M.upcoming_boss = upcoming_boss
M.round_eval_section = round_eval_section

return M
