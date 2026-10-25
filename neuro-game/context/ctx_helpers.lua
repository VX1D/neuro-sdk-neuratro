local Utils = require("util.utils")
local CardUtil = require("facts.card_util")
local flatten_description = Utils.flatten_description

local function normalize_flat(value)
  if value == nil then return "" end
  local s = type(value) == "table" and (flatten_description(value) or "") or tostring(value)
  return (s:gsub("[\r\n]+", " "):gsub("|", "/"))
end

local function tidy(s)
  s = s:gsub("%s+", " ")
  return s:match("^%s*(.-)%s*$") or s
end

local function clause_separators(s)
  local prev
  repeat prev = s; s = s:gsub("(%d),(%d%d%d)", "%1\3%2") until s == prev
  return (s:gsub(",", ";"):gsub("\3", ","))
end

local function normalize_text(value)
  return tidy(clause_separators(normalize_flat(value)))
end

local function normalize_prose(value)
  return tidy(normalize_flat(value))
end

local function sticker_tags(card, tags)
  local ability = card.ability or {}
  if ability.eternal then tags[#tags + 1] = "eternal(unsellable)" end
  if ability.perishable then
    local tally = ability.perish_tally
    if tally <= 0 then
      tags[#tags + 1] = "perishable(DEBUFFED_now)"
    elseif tally == 1 then
      tags[#tags + 1] = "perishable(DEBUFFED_END_OF_ROUND)"
    else
      tags[#tags + 1] = "perishable(rounds_left=" .. tostring(tally) .. ")"
    end
  end
  if ability.rental then
    local rate = (G and G.GAME and tonumber(G.GAME.rental_rate)) or 3
    tags[#tags + 1] = "rental(" .. Utils.money(rate) .. "_per_round)"
  end
  return tags
end

local function joker_tags(card)
  if not card then return "-" end
  local tags = {}
  if card.debuff then tags[#tags + 1] = "DEBUFFED(inactive)" end
  sticker_tags(card, tags)
  local et = CardUtil.edition_tag(card.edition)
  if et ~= "" then tags[#tags + 1] = et end
  if #tags == 0 then return "-" end
  return normalize_text(table.concat(tags, "/"))
end


local plural = require("facts.text").plural

local function strip_dot(s) return (tostring(s or "")):gsub("%s*%.%s*$", "") end
local function end_sentence(s)
  s = tostring(s or "")
  return s:find("[%.%?!]$") and s or (s .. ".")
end

local function yn(v) return v and "yes" or "no" end

local VALUE_LONG = { A = "Ace", K = "King", Q = "Queen", J = "Jack" }

local resolve = CardUtil.resolve_field

local function mod_desc(short)
  if type(short) ~= "string" or short == "" then return nil end
  for _, registry in ipairs({ CardUtil.ENHANCEMENTS, CardUtil.SEALS }) do
    for _, r in pairs(registry) do
      if resolve(r.short) == short then return resolve(r.desc) end
    end
  end
  for _, e in ipairs(CardUtil.EDITIONS) do
    if resolve(e.tag) == short then return resolve(e.desc) end
  end
  return nil
end

local function modifier_desc(short)
  for _, r in pairs(CardUtil.SEALS) do
    if resolve(r.short) == short then
      local d = resolve(r.desc)
      return r.name .. " Seal" .. (d and (": " .. d) or "")
    end
  end
  for _, e in ipairs(CardUtil.EDITIONS) do
    if resolve(e.tag) == short then
      local d = type(e.desc) == "function" and e.desc("playing") or e.desc
      return e.name .. (d and (": " .. d) or "")
    end
  end
  return mod_desc(short)
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

local function decode_card(tok)
  local segs = split_top(tok, "+")
  local head = segs[1] or tok
  local hd = mod_desc(head)
  local out = hd and ((head:match("^[%w!]+") or "Special") .. " Card (" .. hd .. ")") or (head:gsub("_", " "))
  local mlist = {}
  for i = 2, #segs do
    local m = segs[i]
    if m == "DB" then mlist[#mlist + 1] = "debuffed, scores 0"
    elseif m == "LOCK" then mlist[#mlist + 1] = "forced/locked"
    elseif m == "USED" then mlist[#mlist + 1] = "played earlier this ante; debuffed by The Pillar this round"
    elseif m:match("^perma%d+c$") then
      mlist[#mlist + 1] = "permanently +" .. m:match("^perma(%d+)c$") .. " chips (already counted in the chips it scores)"
    else mlist[#mlist + 1] = modifier_desc(m) or (m:gsub("_", " ")) end
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
  inner, c = inner:gsub("%$/r=([%-%d]+)", function(v) return Utils.money(v) .. " per round" end); n = n + c
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
  res = res:gsub("%s*[,;·%-]+%s*$", "")
  res = res:gsub("^%s*[,;·]+%s*", "")
  if not res:match("^%-%d") then
    res = res:gsub("^%s*%-+%s*", "")
  end
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
  if n then return "rental, " .. Utils.money(n) .. " per round" end
  local ehead = t:match("^[%w]+%(")
  if ehead then
    local labeled = edition_map()[ehead]
    if labeled then return labeled end
  end
  return mod_desc(t) or (t:gsub("_", " "))
end

local function humanize_flags(s)
  if not s or s == "" or s == "-" then return s end
  local parts = {}
  for _, t in ipairs(split_top(s, "/")) do
    if t ~= "" then parts[#parts + 1] = humanize_flag(t) end
  end
  return table.concat(parts, ", ")
end

local function sticker_flags(card)
  if type(card) ~= "table" then return nil end
  local tags = sticker_tags(card, {})
  if #tags == 0 then return nil end
  return humanize_flags(normalize_text(table.concat(tags, "/")))
end

local function has_action(action_set, name)
  return not not (action_set and name and action_set[name])
end

local function offers(action_set, name)
  if type(action_set) == "table" and next(action_set) then return has_action(action_set, name) end
  return not not require("core.actions").is_action_valid(name)
end

local function can_line(label, action_set, names, fact)
  for _, name in ipairs(names) do
    if offers(action_set, name) then return "Can " .. label .. ": " .. yn(fact ~= false) end
  end
  local Actions = require("core.actions")
  -- An overlay blocks every action; state its blocker once per frame rather than on each line.
  if Actions.overlay_block_reason(names[1]) then return "Can " .. label .. ": no" end
  local reason = Actions.unavailable_reason(names[1])
  reason = type(reason) == "string" and strip_dot(reason:match("^[^;]*")) or ""
  if reason == "" then return "Can " .. label .. ": no" end
  return "Can " .. label .. ": no -- " .. reason:sub(1, 1):lower() .. reason:sub(2)
end

local function short_enh(card)
  local enh = CardUtil.enhancement_key(card)
  if not enh then return "" end
  return CardUtil.enhancement_short(enh)
end

local function short_seal(card) return card and CardUtil.seal_short(card.seal) or "" end

local function short_edition(card)
  if not card then return "" end
  return CardUtil.edition_tag(card.edition)
end

local function hidden_row(idx, card, area)
  return idx .. ". " .. require("facts.public_card_identity").label(card, area, idx) .. " -- identity and effect hidden."
end

local function effect_tail(eff, suffix, desc)
  if suffix ~= "" then eff = (eff ~= "" and (eff .. "; " .. suffix)) or suffix end
  local out = (eff ~= "") and (" -- " .. eff) or ""
  if desc and desc ~= "" and not (eff ~= "" and eff:find(desc, 1, true)) then out = end_sentence(out) .. " " .. desc end
  return out
end

local function row_effect(card, kind)
  local SemanticRegistry = require("core.semantic_registry")
  local raw_eff = SemanticRegistry.render(kind, card)
  local suffix = CardUtil.planet_run_state_suffix(card):gsub("^; ", "")
  local desc = SemanticRegistry.render("card_description_full", card)
  if desc == "" or desc == raw_eff then
    desc = nil
  else
    local nd = desc:lower():gsub("[^%w]", "")
    local ne = raw_eff:lower():gsub("[^%w]", "")
    if nd ~= "" and ne:find(nd, 1, true) then desc = nil end
  end
  return raw_eff, suffix, desc
end

local function join(list, last)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. (last or " and ") .. list[#list]
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

local function ledger_source_groups(led)
  local out, by_key, named = {}, {}, {}
  for _, src in ipairs(led and led.sources or {}) do
    local key = table.concat({ src.name, src.kind, tostring(src.total.n), tostring(src.why) }, "|")
    local group = by_key[key]
    if not group then
      group = { name = normalize_text(src.name), kind = src.kind, total = src.total, why = src.why, slots = {} }
      by_key[key], out[#out + 1] = group, group
      named[group.name] = (named[group.name] or 0) + 1
    end
    if src.slot then group.slots[#group.slots + 1] = src.slot end
  end
  for _, group in ipairs(out) do
    group.label, group.each = group.name, #group.slots > 1
    if group.each or named[group.name] > 1 then
      table.sort(group.slots)
      group.label = group.name .. " (" .. table.concat(group.slots, ", ") .. ")"
    end
  end
  return out
end

local function ledger_gated_sources(led, drop_why)
  local out = {}
  for _, g in ipairs(ledger_source_groups(led)) do
    local figure = quantity_amount(g.kind, g.total.n)
    local why = g.why
    if why and drop_why and drop_why(g, figure) then why = nil end
    out[#out + 1] = g.label .. " " .. figure .. (g.each and " each" or "") .. (why and (" -- " .. why) or "")
  end
  return out
end

local function target_count(card)
  local lo, hi = CardUtil.consumable_target_range(card)
  if not (hi and hi > 0) then return nil end
  local n = (lo == hi) and tostring(lo) or (tostring(lo) .. " to " .. tostring(hi))
  return n .. (n == "1" and " card" or " cards")
end

local M = { target_count = target_count, row_effect = row_effect, join = join, hidden_row = hidden_row, effect_tail = effect_tail, clause_separators = clause_separators, normalize_text = normalize_text, normalize_prose = normalize_prose, joker_tags = joker_tags, sticker_flags = sticker_flags, has_action = has_action, offers = offers, can_line = can_line, short_enh = short_enh, short_seal = short_seal, short_edition = short_edition, plural = plural, strip_dot = strip_dot, end_sentence = end_sentence, yn = yn, decode_card = decode_card, VALUE_LONG = VALUE_LONG, humanize_effect = humanize_effect, humanize_flags = humanize_flags, quantity_amount = quantity_amount, quantity_clause = quantity_clause, ledger_gated_sources = ledger_gated_sources }
return M
