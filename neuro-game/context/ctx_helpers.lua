local Utils = require("util.utils")
local CardUtil = require("facts.card_util")
local flatten_description = Utils.flatten_description

local function normalize_flat(value)
  if value == nil then return "" end
  local s = value
  if type(s) == "table" then
    s = flatten_description(s) or ""
  else
    s = tostring(s)
  end
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("|", "/")
  return s
end

local function tidy(s)
  s = s:gsub("%s+", " ")
  return s:match("^%s*(.-)%s*$") or s
end

local function normalize_text(value)
  return tidy(normalize_flat(value):gsub(",", ";"))
end

local function normalize_prose(value)
  return tidy(normalize_flat(value))
end

local NUMERIC_EFFECTS = require("facts.numeric_effects")
local function effect_parts(ability)
  local out = {}
  if type(ability) ~= "table" then return out end
  for _, e in ipairs(NUMERIC_EFFECTS) do
    out[#out + 1] = NUMERIC_EFFECTS.label(ability, e)
  end
  return out
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
  return normalize_text(table.concat(tags, "/"))
end

local function ability_signature(ability)
  if type(ability) ~= "table" then return "-" end
  local parts = {}
  for _, e in ipairs(NUMERIC_EFFECTS) do
    if not e.nest then
      local v = ability[e.field]
      if v and v ~= e.skip then parts[#parts + 1] = e.field .. "=" .. tostring(v) end
    end
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

local function money(v)
  local s = tostring(v or "?")
  local neg = s:match("^%-(.+)$")
  return neg and ("-$" .. neg) or ("$" .. s)
end

local function plural(n, w)
  return tostring(n) .. " " .. (tostring(n) == "1" and w or (w .. "s"))
end

local function strip_dot(s) return (tostring(s or "")):gsub("%s*%.%s*$", "") end

local function yn(v) return v and "yes" or "no" end

local function decode_payout(econ)
  if not econ then return nil end
  local n = require("util.utils").fmt_num
  return string.format("$%s (blind $%s + hands $%s + discards $%s + interest $%s); money jokers/tags add more",
    n(econ.projected_total or 0), n(econ.blind_reward or 0), n(econ.hands_bonus or 0),
    n(econ.discard_bonus or 0), n(econ.interest or 0))
end

local VALUE_LONG = { A = "Ace", K = "King", Q = "Queen", J = "Jack" }
local SUIT_LONG = { H = "Hearts", D = "Diamonds", C = "Clubs", S = "Spades" }

local function resolve(v)
  if type(v) == "function" then return v() end
  return v
end

local function mod_desc(short)
  if type(short) ~= "string" or short == "" then return nil end
  for _, r in pairs(CardUtil.ENHANCEMENTS) do
    if resolve(r.short) == short then return resolve(r.desc) end
  end
  for _, r in pairs(CardUtil.SEALS) do
    if resolve(r.short) == short then return resolve(r.desc) end
  end
  for _, e in ipairs(CardUtil.EDITIONS) do
    if resolve(e.tag) == short then return resolve(e.desc) end
  end
  return nil
end

local _edition_map = nil
local function edition_map()
  if _edition_map then return _edition_map end
  local m = {}
  for _, e in ipairs(CardUtil.EDITIONS) do
    local tag = resolve(e.tag)
    if type(tag) == "string" and tag ~= "" then
      local nm, d = resolve(e.name), resolve(e.desc)
      local labeled = (nm and d) and (nm .. ": " .. d) or d
      m[tag:match("^[%w]+%(") or tag] = labeled
    end
  end
  _edition_map = m
  return m
end

local function split_top(s, sep)
  local out, depth, cur = {}, 0, ""
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == sep and depth == 0 then
      out[#out + 1] = cur
      cur = ""
    else
      if ch == "(" then depth = depth + 1
      elseif ch == ")" then depth = depth - 1 end
      cur = cur .. ch
    end
  end
  out[#out + 1] = cur
  return out
end

local function split_plus(s) return split_top(s, "+") end

local function decode_card(tok)
  local segs = split_plus(tok)
  local head = segs[1] or tok
  local out
  local val, suit = head:match("^(.-)([HDCS])$")
  if head == "FD" then
    out = "face-down (hidden)"
  elseif val and suit and val ~= "" then
    out = (VALUE_LONG[val] or val) .. " of " .. (SUIT_LONG[suit] or suit)
  else
    local hd = mod_desc(head)
    out = hd and ((head:match("^[%w!]+") or "Special") .. " card (" .. hd .. ")") or (head:gsub("_", " "))
  end
  local mlist = {}
  for i = 2, #segs do
    local m = segs[i]
    if m == "DB" then mlist[#mlist + 1] = "debuffed, scores 0"
    elseif m == "LOCK" then mlist[#mlist + 1] = "forced/locked"
    elseif m == "USED" then mlist[#mlist + 1] = "played earlier this ante; debuffed by The Pillar this round"
    elseif m:match("^perma%d+c$") then
      mlist[#mlist + 1] = "permanently +" .. m:match("^perma(%d+)c$") .. " chips (already counted in the chips it scores)"
    else mlist[#mlist + 1] = mod_desc(m) or (m:gsub("_", " ")) end
  end
  if #mlist > 0 then out = out .. " (" .. table.concat(mlist, ", ") .. ")" end
  return out
end

local function expand_extra(inner)
  local n = 0
  local c
  inner, c = inner:gsub("xM=([%-%d%.]+)", "x%1 Mult"); n = n + c
  inner, c = inner:gsub("%+M=([%-%d%.]+)", "+%1 Mult"); n = n + c
  inner, c = inner:gsub("%+C=([%-%d%.]+)", "+%1 Chips"); n = n + c
  inner, c = inner:gsub("%+([%-%d%.]+)M/(%a+)%-card", "+%1 Mult per %2 card"); n = n + c
  inner, c = inner:gsub("%+([%-%d%.]+)C/(%a+)%-card", "+%1 Chips per %2 card"); n = n + c
  inner, c = inner:gsub("jh=([%-%d]+)", "+%1 hands"); n = n + c
  inner, c = inner:gsub("%$/r=([%-%d]+)", "$%1 per round"); n = n + c
  inner, c = inner:gsub("s=(%a+)", "suit %1"); n = n + c
  inner, c = inner:gsub("song=(%w+)", "song %1"); n = n + c
  if n == 0 then return "[" .. inner .. "]" end
  return inner
end

local function humanize_effect(s, strip_editions)
  if not s or s == "" or s == "-" then return s end
  s = s:gsub(" · ", ", "):gsub("·", ", "):gsub(";", ", ")
  s = s:gsub("%[(.-)%]", expand_extra)
  s = s:gsub("extra:(%S+)", "extra %1")
  s = s:gsub("Mult/card", "Mult per scoring card")
  s = s:gsub("Mult/discard", "Mult per discard")
  s = s:gsub("Mult/played", "Mult per played card")
  local em = edition_map()
  local out = {}
  for seg in (s .. ", "):gmatch("(.-), ") do
    local t = seg:match("^%s*(.-)%s*$")
    local head = t:match("^[%w]+%(")
    local e = head and em[head]
    if e then
      if not strip_editions then out[#out + 1] = e end
    elseif t ~= "" then
      out[#out + 1] = t
    end
  end
  local res = table.concat(out, ", "):gsub("%s+", " ")
  res = res:gsub("%s*[,;·-]%s*$", ""):gsub("^%s*[,;·-]%s*", "")
  return (res:match("^%s*(.-)%s*$"))
end

local function humanize_flag(t)
  if t == "eternal(unsellable)" then return "cannot be sold" end
  if t == "DEBUFFED(inactive)" then return "debuffed (inactive)" end
  if t == "perishable(DEBUFFED_END_OF_ROUND)" then return "perishable, debuffs at end of round" end
  if t == "perishable(DEBUFFED_now)" then return "perishable, debuffed now" end
  local n = t:match("^perishable%(rounds_left=(%d+)%)$")
  if n then return "perishable, " .. n .. " rounds left" end
  if t == "perishable" then return "perishable" end
  n = t:match("^rental%(%$(%d+)_per_round%)$")
  if n then return "rental, $" .. n .. " per round" end
  local ehead = t:match("^[%w]+%(")
  if ehead then
    local labeled = edition_map()[ehead]
    if labeled then return labeled end
  end
  return mod_desc(t) or (t:gsub("_", " "))
end

local function split_slash(s) return split_top(s, "/") end

local function humanize_flags(s)
  if not s or s == "" or s == "-" then return s end
  local parts = {}
  for _, t in ipairs(split_slash(s)) do
    if t ~= "" then parts[#parts + 1] = humanize_flag(t) end
  end
  return table.concat(parts, ", ")
end

local function has_action(action_set, name)
  if not action_set or not name then return false end
  return not not action_set[name]
end

local VALUE_SHORT = {
  Ace = "A", King = "K", Queen = "Q", Jack = "J",
  ["10"] = "10", ["9"] = "9", ["8"] = "8", ["7"] = "7",
  ["6"] = "6", ["5"] = "5", ["4"] = "4", ["3"] = "3", ["2"] = "2",
}

local SUIT_SHORT = {
  Hearts = "H", Diamonds = "D", Clubs = "C", Spades = "S",
}

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

local function short_seal(card)
  if not card then return "" end
  return CardUtil.seal_short(card.seal) or ""
end

local function short_edition(card)
  if not card then return "" end
  return CardUtil.edition_tag(card.edition)
end

local KIND_UNIT = { xmult = " Mult", mult = " Mult", chips = " Chips", xchips = " Chips" }

local function quantity_amount(kind, n)
  if kind == "xmult" or kind == "xchips" then return Utils.fmt_xmult(n) .. KIND_UNIT[kind] end
  return Utils.signed(n) .. KIND_UNIT[kind]
end

local function quantity_clause(kind, q)
  if not q or q.k == "unknown" then return nil end
  local s = quantity_amount(kind, q.n)
  if q.k == "at_most" then s = "at most " .. s end
  return s
end

local function ledger_gated_sources(led)
  local out = {}
  if not led then return out end
  for _, src in ipairs(led.sources) do
    out[#out + 1] = normalize_text(src.name) .. " " .. quantity_amount(src.kind, src.total.n)
      .. (src.why and (" -- " .. src.why) or "")
  end
  return out
end

return { normalize_text = normalize_text, normalize_prose = normalize_prose, effect_parts = effect_parts, ability_signature = ability_signature, joker_tags = joker_tags, has_action = has_action, short_value = short_value, short_suit = short_suit, short_enh = short_enh, short_seal = short_seal, short_edition = short_edition, money = money, plural = plural, strip_dot = strip_dot, yn = yn, decode_payout = decode_payout, decode_card = decode_card, VALUE_LONG = VALUE_LONG, humanize_effect = humanize_effect, humanize_flags = humanize_flags, quantity_amount = quantity_amount, quantity_clause = quantity_clause, ledger_gated_sources = ledger_gated_sources }
