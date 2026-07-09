local Utils = require("util.utils")
local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("context.ctx_economy")
local DebuffFacts = require("facts.debuff_facts")
local compact_text = CtxHelpers.compact_text
local safe_description = Utils.safe_description
local economy_projection = CtxEconomy.economy_projection
local calc_interest = CtxEconomy.calc_interest
local calc_blind_target = CtxEconomy.calc_blind_target

local M = {}

local function blind_line()
  if not G or not G.GAME or not G.GAME.blind then return nil end
  local blind = G.GAME.blind
  local target = CtxEconomy.blind_target(blind) or 0
  local current_score = G.GAME.chips or 0
  local remaining = CtxEconomy.blind_remaining(blind) or 0
  local hands = G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local discards = G.GAME.current_round and G.GAME.current_round.discards_left or 0
  local money = G.GAME.dollars or 0
  local econ = economy_projection({ selecting_hand = true })
  local name = blind.name or "Unknown"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local win_ante = G.GAME.win_ante or 8
  local ante_str = tostring(ante) .. "/" .. tostring(win_ante)
  local no_interest = CtxEconomy.no_interest() and "Y" or "N"
  local discard_cost = G.GAME.modifiers and G.GAME.modifiers.discard_cost
  local scaling = G.GAME.modifiers and G.GAME.modifiers.scaling
  local ante_mult = G.GAME.starting_params and G.GAME.starting_params.ante_scaling
  local mod_parts = {}
  if no_interest == "Y" then mod_parts[#mod_parts+1] = "no_interest" end
  if discard_cost and discard_cost > 0 then mod_parts[#mod_parts+1] = "discard_costs_$"..tostring(discard_cost) end
  if scaling and scaling ~= 1 then mod_parts[#mod_parts+1] = "harder_blind_scaling" end
  if ante_mult and ante_mult ~= 1 then mod_parts[#mod_parts+1] = "blind_targets_x"..tostring(ante_mult) end
  local mod_str = #mod_parts > 0 and ("|MOD:"..table.concat(mod_parts, ",")) or ""
  local ern = tonumber(econ and econ.end_round_earnings) or 0
  local b = tonumber(econ and econ.blind_reward) or 0
  local ern_str = (ern > 0 and ern ~= b) and ("|ERN:" .. tostring(ern)) or ""
  local need_per_hand = hands > 0 and math.ceil(remaining / hands) or 0
  local debt_floor = CtxEconomy.spend_floor()
  return string.format("B|N:%s|A:%s|S:%s/%s|R:%s|NPH:%s|H:%d|D:%d|$:%d|DF:%d|PY:%s",
    compact_text(name, 28), ante_str, Utils.fmt_num(current_score), Utils.fmt_num(target), Utils.fmt_num(remaining),
    Utils.fmt_num(need_per_hand), hands, discards, money, debt_floor, CtxEconomy.payout_token(econ)) .. ern_str .. mod_str
end

local function blind_debuff_line()
  if not (G and G.GAME and G.GAME.blind) then return nil end
  local blind = G.GAME.blind
  local debuff = DebuffFacts.blind_debuff(blind)

  local rules = {}
  if debuff.suit then rules[#rules + 1] = "suit=" .. tostring(debuff.suit) end
  if debuff.is_face == "face" then rules[#rules + 1] = "face=Y" end
  if debuff.h_size_ge then rules[#rules + 1] = "min_cards=" .. tostring(debuff.h_size_ge) end
  if debuff.h_size_le then rules[#rules + 1] = "max_cards=" .. tostring(debuff.h_size_le) end
  if debuff.value then rules[#rules + 1] = "value=" .. tostring(debuff.value) end
  if debuff.nominal then rules[#rules + 1] = "nominal=" .. tostring(debuff.nominal) end

  local bname = tostring(blind.name or "")
  if bname == "The Pillar" then rules[#rules + 1] = "played_this_ante=Y" end
  if bname == "The Eye" then rules[#rules + 1] = "repeat_hand_type=N" end
  if bname == "The Mouth" then rules[#rules + 1] = "single_hand_type=Y" end
  if bname == "The Ox" then
    rules[#rules + 1] = "most_played=" .. tostring(DebuffFacts.most_played_hand() or "?")
  end
  if bname == "The Eye" or bname == "The Mouth" then
    local played = {}
    if G.GAME.hands then
      for hname, hd in pairs(G.GAME.hands) do
        if type(hd) == "table" and (tonumber(hd.played_this_round) or 0) > 0 then
          played[#played + 1] = hname
        end
      end
    end
    table.sort(played)
    rules[#rules + 1] = "played_this_round=" .. (#played > 0 and table.concat(played, "+") or "none")
  end

  local debuffed_cards = DebuffFacts.count(G.hand and G.hand.cards)

  local txt = DebuffFacts.boss_debuff_text(blind)

  if #rules == 0 and txt == "" and debuffed_cards == 0 then
    return nil
  end

  return string.format("BD|R:%s|DB:%d|TXT:%s",
    compact_text((#rules > 0 and table.concat(rules, "/") or "-"), 88),
    debuffed_cards,
    compact_text((txt ~= "" and txt or "-"), 120)
  )
end

local function blind_select_section()
  if not G or not G.GAME then return nil end
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local money = G.GAME.dollars or 0
  local hands = G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local discards = G.GAME.current_round and G.GAME.current_round.discards_left or 0
  local no_interest = CtxEconomy.no_interest() and "Y" or "N"
  local econ = economy_projection({ exclude_action_bonus = true })

  local skips = G.GAME.skips or 0

  local lines = {}
  local bs_line = string.format("BS|A:%s|$:%d|H:%d|D:%d|NI:%s|PY:%s",
    tostring(ante), money, hands, discards, no_interest,
    CtxEconomy.payout_token(econ))
  if skips > 0 then bs_line = bs_line .. "|SKP:" .. tostring(skips) end
  lines[#lines + 1] = bs_line

  if type(G.GAME.bosses_used) == "table" then
    local bu = G.GAME.bosses_used
    local boss_counts = type(rawget(bu, "boss")) == "table" and rawget(bu, "boss") or bu
    local boss_names = {}
    for k, v in pairs(boss_counts) do
      if (tonumber(v) or 0) > 0 then boss_names[#boss_names + 1] = tostring(k):gsub("^bl_", "") end
    end
    if #boss_names > 0 then
      table.sort(boss_names)
      lines[#lines + 1] = "BU|" .. table.concat(boss_names, ",")
    end
  end

  if G.GAME.round_resets and G.GAME.round_resets.blind_states then
    local bs = G.GAME.round_resets.blind_states
    local on_deck = G.GAME.blind_on_deck or "?"
    lines[#lines + 1] = string.format("BP|OD:%s|SM:%s|BG:%s|BOSS:%s",
      compact_text(on_deck, 12),
      compact_text(bs.Small or "?", 12),
      compact_text(bs.Big or "?", 12),
      compact_text(bs.Boss or "?", 12))
  end

  local can_skip = "N"
  do
    local ok_a, Actions = pcall(require, "core.actions")
    if ok_a and Actions and Actions.is_action_valid and Actions.is_action_valid("skip_blind") then
      can_skip = "Y"
    end
  end
  local reroll_cost = CtxEconomy.BOSS_REROLL_COST
  local can_reroll, reroll_enabled = CtxEconomy.can_reroll_boss()
  lines[#lines + 1] = string.format("BA|SK:%s|RB:%s|RC:%d|RE:%s",
    can_skip, can_reroll and "Y" or "N", reroll_cost, (reroll_enabled and "Y" or "N"))

  if G.GAME.round_resets and G.GAME.round_resets.blind_choices then
    local choices = G.GAME.round_resets.blind_choices
    local states = G.GAME.round_resets.blind_states or {}
    local tags = G.GAME.round_resets.blind_tags or {}
    lines[#lines + 1] = "BO:type,key,name,state,target,reward,tagname,tageff,debuff"
    for _, btype in ipairs({"Small", "Big", "Boss"}) do
      local key = choices[btype]
      if key and G.P_BLINDS and G.P_BLINDS[key] then
        local blind_def = G.P_BLINDS[key]
        local debuff_text = "-"
        if blind_def.debuff or btype == "Boss" then
          local txt = DebuffFacts.blind_effect_text(key, blind_def)
          if (txt == "" or not txt) and blind_def.debuff and blind_def.debuff.text then
            txt = blind_def.debuff.text
          end
          if txt and txt ~= "" then debuff_text = compact_text(txt, 120) end
        end

        local tag_key = tags[btype]
        local tag_name = "-"
        local tag_effect = "-"
        if tag_key then
          local tag_def = G.P_TAGS and G.P_TAGS[tag_key]
          tag_name = compact_text((tag_def and tag_def.name) or tag_key, 24)
          local desc = DebuffFacts.tag_effect_text(tag_key)
          if (not desc or desc == "") and tag_def then
            desc = safe_description(tag_def.loc_txt, nil, 120)
            if not desc or desc == "" then
              local rt = tag_def.config and tag_def.config.ref_table
              if rt and rt.loc_txt then desc = safe_description(rt.loc_txt, nil, 120) end
            end
          end
          if desc and desc ~= "" then
            tag_effect = compact_text(desc, 120)
          end
        end

        local target = calc_blind_target(key)
        local reward = blind_def.dollars or 0
        lines[#lines + 1] = string.format("%s,%s,%s,%s,%s,$%d,%s,%s,%s",
          btype,
          compact_text(key, 24),
          compact_text(blind_def.name or key, 30),
          compact_text(states[btype] or "?", 16),
          target and tostring(target) or "?",
          reward,
          tag_name,
          tag_effect,
          debuff_text)
      end
    end
  end

  return table.concat(lines, "\n")
end

local function round_eval_section()
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local interest = calc_interest(money)
  local no_interest = CtxEconomy.no_interest() and "Y" or "N"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local round = G.GAME.round or "?"
  local interest_cap = CtxEconomy.interest_cap()
  -- round is already over: unused hands/discards were paid, so do not project them as pending income
  local econ = economy_projection({ exclude_action_bonus = true })
  return string.format("RE|A:%s|RND:%s|$:%d|IN:+%d|CAP:%d|NI:%s|ERN:%d|PY:%s",
    tostring(ante), tostring(round), money, interest, interest_cap, no_interest,
    econ and econ.end_round_earnings or 0,
    CtxEconomy.payout_token(econ))
end

M.blind_line = blind_line
M.blind_debuff_line = blind_debuff_line
M.blind_select_section = blind_select_section
M.round_eval_section = round_eval_section

return M
