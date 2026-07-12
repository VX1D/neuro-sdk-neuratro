local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local Utils = require("util.utils")
local Scoring = require("util.scoring")
local compact_text = CtxHelpers.compact_text
local card_effect_summary = CtxHelpers.card_effect_summary
local card_description_full = CtxHelpers.card_description_full
local joker_tags = CtxHelpers.joker_tags
local safe_name = Utils.safe_name
local safe_name_or = Utils.safe_name_or

local function jokers_section()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    return nil
  end

  local jhdr = "J:i,n,f,flg,$"
    .. " [" .. CardUtil.slot_status_text(CardUtil.joker_slot_status()) .. "]"
  local lines = { jhdr }
  for i, card in ipairs(G.jokers.cards) do
    local name = compact_text(safe_name_or(card), 40)
    local effect_str = card_effect_summary(card)
    local row = {
      tostring(i),
      name,
      compact_text(effect_str, 80),
      joker_tags(card),
      Utils.money(card.sell_cost),
    }
    lines[#lines + 1] = table.concat(row, ",")
  end

  if #G.jokers.cards >= 2 then
    local order = {}
    for _, card in ipairs(G.jokers.cards) do
      local nm = safe_name(card)
      if not nm or nm == "" then
        nm = (card.config and card.config.center and card.config.center.key) or "?"
      end
      order[#order + 1] = compact_text(nm, 24)
    end
    lines[#lines + 1] = "JORD:" .. table.concat(order, ">")
  end

  local agg = Scoring.joker_summary()
  if agg then
    local parts = {}
    local function signed(n, suf) return (n < 0 and "" or "+") .. Utils.fmt_num(n) .. suf end
    local function fmt_x(n) return "x" .. tostring(tonumber(string.format("%.2f", n))) end
    if agg.chips ~= 0 then parts[#parts + 1] = signed(agg.chips, "c") end
    if agg.mult ~= 0 then parts[#parts + 1] = signed(agg.mult, "m") end
    if agg.xmult ~= 1 then parts[#parts + 1] = fmt_x(agg.xmult) end
    if agg.c_mult ~= 0 then parts[#parts + 1] = signed(agg.c_mult, "m/card") end
    local types = {}
    for t in pairs(agg.cond_by_type or {}) do types[#types + 1] = t end
    table.sort(types)
    for _, t in ipairs(types) do
      local b = agg.cond_by_type[t]
      local cp = {}
      if (b.mult or 0) ~= 0 then cp[#cp + 1] = signed(b.mult, "m") end
      if (b.chips or 0) ~= 0 then cp[#cp + 1] = signed(b.chips, "c") end
      if (b.xmult or 1) ~= 1 then cp[#cp + 1] = fmt_x(b.xmult) end
      if #cp > 0 then
        parts[#parts + 1] = string.format("COND(only if hand has %s):%s", t, table.concat(cp, " "))
      end
    end
    if #parts > 0 then
      lines[#lines + 1] = "JK_ALL(current top-level totals):" .. table.concat(parts, " ")
    end
  end

  return table.concat(lines, "\n")
end

local function joker_descriptions_section()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    return nil
  end
  local lines = { "JD:i,n,d" }
  for i, card in ipairs(G.jokers.cards) do
    local name = compact_text(safe_name_or(card), 40)
    lines[#lines + 1] = table.concat({
      tostring(i),
      name,
      compact_text(card_description_full(card, 320), 320),
    }, ",")
  end
  return table.concat(lines, "\n")
end

local function playbook_section(include_full_desc)
  if not (G and G.playbook_extra and G.playbook_extra.cards and #G.playbook_extra.cards > 0) then
    return nil
  end

  local lines = { include_full_desc and "PB(playbook):i,n,f,flg,$,d" or "PB(playbook):i,n,f,flg,$" }
  for i, card in ipairs(G.playbook_extra.cards) do
    local name = compact_text(safe_name_or(card), 40)
    local effect_str = card_effect_summary(card)
    local row = {
      tostring(i),
      name,
      compact_text(effect_str, 80),
      joker_tags(card),
      Utils.money(card.sell_cost),
    }
    if include_full_desc then
      row[#row + 1] = compact_text(card_description_full(card, 320), 320)
    end
    lines[#lines + 1] = table.concat(row, ",")
  end

  return table.concat(lines, "\n")
end

return { jokers_section = jokers_section, joker_descriptions_section = joker_descriptions_section, playbook_section = playbook_section }
