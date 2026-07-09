local Utils = require("util.utils")
local CardUtil = require("facts.card_util")
local flatten_description = Utils.flatten_description
local card_description = Utils.card_description

-- byte cut that never splits a UTF-8 sequence
local function utf8_cut(s, n)
  local cut = s:sub(1, math.max(0, n))
  local i = #cut
  while i > 0 do
    local b = cut:byte(i)
    if b < 0x80 then break end
    if b >= 0xC0 then
      local len = (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or 2
      if i + len - 1 > #cut then cut = cut:sub(1, i - 1) end
      break
    end
    i = i - 1
  end
  return cut
end

local function compact_text(value, max_len)
  if value == nil then return "" end
  local s = value
  if type(s) == "table" then
    s = flatten_description(s) or ""
  else
    s = tostring(s)
  end
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("|", "/")
  s = s:gsub(",", ";")
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  if max_len and #s > max_len then
    if max_len <= 3 then
      return utf8_cut(s, max_len)
    end
    return utf8_cut(s, max_len - 3) .. "..."
  end
  return s
end

-- in facts/numeric_effects so facts/* can require it without an upward facts->context dep
local NUMERIC_EFFECTS = require("facts.numeric_effects")
local function effect_parts(ability)
  local out = {}
  if type(ability) ~= "table" then return out end
  local htype = ability.type
  if htype == "" then htype = nil end
  for _, e in ipairs(NUMERIC_EFFECTS) do
    local v = ability[e.field]
    if v and v ~= e.skip then
      local num = tonumber(v)
      local pre = (e.pre == "+" and num and num < 0) and "" or e.pre
      local part = pre .. tostring(v) .. e.suf
      if e.cond then
        part = part .. (htype and ("(only if hand has " .. tostring(htype) .. ")") or "(conditional)")
      elseif e.type_cond and htype then
        part = part .. "(only if hand has " .. tostring(htype) .. ")"
      end
      out[#out + 1] = part
    end
  end
  return out
end

local function card_effect_summary(card)
  if not card then return "-" end
  local ability = card.ability or {}
  local effects = effect_parts(ability)
  local opaque_extra = nil
  if ability.extra then
    if type(ability.extra) ~= "table" then
      opaque_extra = "extra:" .. tostring(ability.extra)
    else
      local ex = ability.extra
      local ep = {}
      local htype = (ability.type ~= "" and ability.type) or nil
      local xm = tonumber(ex.xmult or ex.Xmult or ex.x_mult)
      if xm and xm ~= 1 then
        local tag = "xM=" .. tostring(tonumber(string.format("%.2f", xm)))
        if htype then tag = tag .. "(only if hand has " .. tostring(htype) .. ")" end
        ep[#ep+1] = tag
      end
      local em = tonumber(ex.mult)
      if em and em ~= 0 then ep[#ep+1] = "+M=" .. tostring(em) end
      local ec = tonumber(ex.chips)
      if ec and ec ~= 0 then ep[#ep+1] = "+C=" .. tostring(ec) end
      local esm = tonumber(ex.s_mult)
      if esm and esm ~= 0 and ex.suit then ep[#ep+1] = "+" .. tostring(esm) .. "M/" .. tostring(ex.suit) .. "-card" end
      local esc = tonumber(ex.s_chips)
      if esc and esc ~= 0 and ex.suit then ep[#ep+1] = "+" .. tostring(esc) .. "C/" .. tostring(ex.suit) .. "-card" end
      local eh = tonumber(ex.hands)
      if eh and eh ~= 0 then ep[#ep+1] = "jh=" .. tostring(eh) end
      if ex.suit and not (esm and esm ~= 0) and not (esc and esc ~= 0) then ep[#ep+1] = "s=" .. tostring(ex.suit) end
      local egain = tonumber(ex.gain)
      if egain and egain ~= 0 then ep[#ep+1] = "$/r=" .. tostring(egain) end
      if ex.song then ep[#ep+1] = "song=" .. tostring(ex.song) end
      if #ep > 0 then effects[#effects + 1] = "[" .. table.concat(ep, ",") .. "]" end
    end
  end
  if ability.eternal    then effects[#effects + 1] = "eternal"    end
  if ability.perishable then effects[#effects + 1] = "perishable" end
  if ability.rental     then effects[#effects + 1] = "rental"     end

  local non_edition = #effects
  local et = CardUtil.edition_tag(card.edition)
  if et ~= "" then effects[#effects + 1] = compact_text(et, 20) end

  -- bare numeric extra or edition tag alone must not suppress the description fallback
  if non_edition > 0 then
    if opaque_extra then effects[#effects + 1] = opaque_extra end
    return compact_text(table.concat(effects, " · "), 64)
  end

  local desc = card_description(card, 140)
  if desc then
    local prefix = (opaque_extra and (opaque_extra .. " · ") or "")
    if #effects > 0 then prefix = table.concat(effects, " · ") .. " · " .. prefix end
    return compact_text(prefix .. desc, 140)
  end
  if #effects > 0 then
    if opaque_extra then effects[#effects + 1] = opaque_extra end
    return compact_text(table.concat(effects, " · "), 64)
  end
  return (opaque_extra and compact_text(opaque_extra, 64)) or "-"
end

local function card_description_full(card, max_len)
  if not card then return "-" end
  local t = card_description(card, max_len)
  if t and t ~= "" then return compact_text(t, max_len) end
  return "-"
end

local function joker_tags(card)
  if not card then return "-" end
  local ability = card.ability or {}
  local tags = {}
  if card.debuff then tags[#tags + 1] = "DEBUFFED(inactive)" end
  if ability.eternal then tags[#tags + 1] = "eternal(unsellable)" end
  if ability.perishable then
    local tally = ability.perish_tally
    if tally and tally <= 0 then
      tags[#tags + 1] = "perishable(DEBUFFED_now)"
    elseif tally and tally == 1 then
      tags[#tags + 1] = "perishable(DEBUFFED_END_OF_ROUND)"
    elseif tally then
      tags[#tags + 1] = "perishable(rounds_left=" .. tostring(tally) .. ")"
    else
      tags[#tags + 1] = "perishable"
    end
  end
  if ability.rental then
    local rate = (G and G.GAME and tonumber(G.GAME.rental_rate)) or 3
    tags[#tags + 1] = "rental($" .. rate .. "_per_round)"
  end
  local et = CardUtil.edition_tag(card.edition)
  if et ~= "" then tags[#tags + 1] = et end
  if #tags == 0 then return "-" end
  return compact_text(table.concat(tags, "/"))
end

local function ability_signature(ability)
  if type(ability) ~= "table" then return "-" end
  local parts = {}
  for _, e in ipairs(NUMERIC_EFFECTS) do
    local v = ability[e.field]
    if v and v ~= e.skip then parts[#parts + 1] = e.field .. "=" .. tostring(v) end
  end
  if type(ability.extra) == "table" then
    local xkeys = {}
    for k, v in pairs(ability.extra) do if type(v) == "number" then xkeys[#xkeys + 1] = k end end
    table.sort(xkeys)
    for _, k in ipairs(xkeys) do parts[#parts + 1] = "x." .. k .. "=" .. tostring(ability.extra[k]) end
  elseif type(ability.extra) == "number" then
    parts[#parts + 1] = "x=" .. tostring(ability.extra)
  end
  if ability.perish_tally then parts[#parts + 1] = "pt=" .. tostring(ability.perish_tally) end
  if #parts == 0 then return "-" end
  return table.concat(parts, ";")
end

local function has_action(action_set, name)
  if not action_set or not name then return false end
  return not not action_set[name]
end

local function join_rows(header, rows)
  local out = { header }
  for _, row in ipairs(rows) do out[#out + 1] = table.concat(row, ",") end
  return table.concat(out, "\n")
end

local VALUE_SHORT = {
  Ace = "A", King = "K", Queen = "Q", Jack = "J",
  ["10"] = "10", ["9"] = "9", ["8"] = "8", ["7"] = "7",
  ["6"] = "6", ["5"] = "5", ["4"] = "4", ["3"] = "3", ["2"] = "2",
}

local SUIT_SHORT = {
  Hearts = "H", Diamonds = "D", Clubs = "C", Spades = "S",
}

-- enhancement/seal compact strings owned by card_util (do not duplicate here)
local function short_value(v)
  if not v then return "?" end
  return VALUE_SHORT[v] or v
end

local function short_suit(s)
  if not s then return "?" end
  return SUIT_SHORT[s] or s
end

local function short_enh(card)
  local enh = CardUtil.enhancement_key(card)
  if not enh then return "" end
  return CardUtil.enhancement_short(enh)
end

-- seal compact strings owned by card_util; delegate so the two never drift
local function short_seal(card)
  if not card then return "" end
  return CardUtil.seal_short(card.seal) or ""
end

local function short_edition(card)
  if not card then return "" end
  return CardUtil.edition_tag(card.edition)
end

local SCORING_FORMULA = "Score = (Base Chips + Played Card Chips (rank value + enhancements/editions) + Joker Chips) x (Base Mult + Card Mult + Joker Mult) x (all XMult sources in play order: card Glass x2, Polychrome x1.5, Steel x1.5 while held, then Joker XMult)"

local function conditional_joker_lines(js)
  local out = {}
  local ctypes = {}
  for t in pairs(js and js.cond_by_type or {}) do ctypes[#ctypes + 1] = t end
  table.sort(ctypes)
  for _, t in ipairs(ctypes) do
    local b = js.cond_by_type[t]
    if (b.xmult or 1) > 1 then out[#out + 1] = string.format("Conditional XMult (only if hand has %s): x%s", t, tostring(tonumber(string.format("%.2f", b.xmult)))) end
    if (b.mult or 0) > 0 then out[#out + 1] = string.format("Conditional +Mult (only if hand has %s): +%s", t, Utils.fmt_num(b.mult)) end
    if (b.chips or 0) > 0 then out[#out + 1] = string.format("Conditional +Chips (only if hand has %s): +%s", t, Utils.fmt_num(b.chips)) end
  end
  return out
end

return { compact_text = compact_text, NUMERIC_EFFECTS = NUMERIC_EFFECTS, SCORING_FORMULA = SCORING_FORMULA, effect_parts = effect_parts, ability_signature = ability_signature, card_effect_summary = card_effect_summary, card_description_full = card_description_full, joker_tags = joker_tags, has_action = has_action, join_rows = join_rows, short_value = short_value, short_suit = short_suit, short_enh = short_enh, short_seal = short_seal, short_edition = short_edition, conditional_joker_lines = conditional_joker_lines }
