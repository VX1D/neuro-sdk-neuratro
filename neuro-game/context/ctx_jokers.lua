local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local Utils = require("util.utils")
local Scoring = require("util.scoring")
local FactHints = require("facts.fact_hints")
local SemanticRegistry = require("core.semantic_registry")
local JokerObservations = require("facts.joker_observations")
local GameFacts = require("facts.game_facts")
local normalize_text = CtxHelpers.normalize_text
local joker_tags = CtxHelpers.joker_tags
local safe_name_or = Utils.safe_name_or
local humanize_effect = CtxHelpers.humanize_effect
local humanize_flags = CtxHelpers.humanize_flags
local strip_dot = CtxHelpers.strip_dot

local function sell_offered()
  local ok, Legality = pcall(require, "facts.boss.legality")
  if not (ok and Legality and Legality.sell_blocked_now) then return true end
  local ok_b, blocked = pcall(Legality.sell_blocked_now)
  return not (ok_b and blocked)
end

local function unsellable(flags)
  return type(flags) == "string" and flags:find("eternal(unsellable)", 1, true) ~= nil
end

local function provenance_mark(marks, provenance)
  local mark = {}
  if type(provenance) == "table" then
    mark.ante = tostring(provenance.ante or "?")
    mark.decision = tostring(provenance.decision_serial or "?")
    mark.sig = mark.ante .. "@" .. mark.decision
    mark.label = string.format(" (written by you, Ante %s, decision %s)", mark.ante, mark.decision)
  end
  marks[#marks + 1] = mark
  return "\1" .. #marks .. "\2"
end

local function joker_row_prose(idx, name, effect_str, flags, sell, tag, note, bought, provenance, marks)
  local s = idx .. ". " .. name
  local he = (effect_str ~= "-" and effect_str ~= "") and humanize_effect(effect_str, true) or ""
  if he and he ~= "" then s = s .. " -- " .. he end
  local hf = humanize_flags(flags)
  if hf and hf ~= "" and hf ~= "-" then s = s .. " [" .. hf .. "]" end
  if sell_offered() and not unsellable(flags) then
    if bought and bought ~= "" then
      s = s .. " (bought " .. bought .. ", sell " .. sell .. ")"
    else
      s = s .. " (sell " .. sell .. ")"
    end
  end
  if tag and tag ~= "" then
    s = s .. " -- your plan: " .. tag
    if marks then s = s .. provenance_mark(marks, provenance) end
  end
  if note and note ~= "" then s = s .. " -- your note: \"" .. note .. "\"" end
  return s
end

local function copied_numbers(card)
  if not CardUtil.copy_joker_kind(card) then return nil end
  local info = Utils.card_info_text(card)
  if type(info) ~= "string" or info == "" then return nil end
  return normalize_text(info)
end

local RETRIGGER_SUBJECT = {
  face = "played face cards",
  first = "the first scoring card",
  every = "every scoring card",
  low_rank = "played 2s, 3s, 4s and 5s",
  held_score = "the cards you hold in hand that score there",
}

local function more_times(n)
  return (n == 1) and "1 more time" or (Utils.fmt_num(n) .. " more times")
end

local function retrigger_clause(e, roster_only)
  local subject = RETRIGGER_SUBJECT[e.subject]
  if not subject then return nil end
  local name = normalize_text(safe_name_or(e.card))
  if not roster_only and e.cards and e.live ~= false then
    local passes = e.passes or 0
    return name .. " re-scores " .. Utils.fmt_num(e.cards) .. " of them " .. more_times(e.reps)
      .. " each -- " .. Utils.fmt_num(passes)
      .. ((passes == 1) and " extra scoring pass" or " extra scoring passes") .. " on this hand"
  end
  local s = name .. " re-scores " .. subject .. " " .. more_times(e.reps)
  if (roster_only and e.gated) or e.live == false then
    s = s .. ", but " .. (e.gate_text or "only when its condition is active")
  end
  return s
end

local CEILING_ORDER = { "xmult", "xchips", "mult", "chips" }
local amount = CtxHelpers.quantity_amount
local quantity_clause = CtxHelpers.quantity_clause

local function append_sorted(out, list)
  table.sort(list)
  for _, s in ipairs(list) do out[#out + 1] = s end
end

local function join(list, last)
  if #list <= 1 then return list[1] or "" end
  return table.concat(list, ", ", 1, #list - 1) .. (last or " and ") .. list[#list]
end

local function preamble(led, has_ceiling, partial_roster)
  local scopes = {}
  if has_ceiling then
    if led.covered.scoring_card then scopes[#scopes + 1] = "per scoring card" end
    if led.covered.held_card then scopes[#scopes + 1] = "per card you hold" end
    if led.covered.other_joker then scopes[#scopes + 1] = "per other joker" end
  end
  local s = "Joker bonuses" .. (partial_roster and " from the jokers you can see" or "")
    .. " (current values"
  if #scopes > 0 then
    s = s .. "; ceilings below already count what pays " .. join(scopes)
    if led.covered.retrigger then s = s .. ", retrigger passes included" end
  end
  return s .. "): "
end

local function why_restates_row(rows, name, figure, why)
  if why:find("%d") then return false end
  local row = rows and rows[name]
  return row ~= nil and row:find(figure:lower(), 1, true) ~= nil
end

local function ceiling_sentence(led, rows)
  local parts = {}
  for _, kind in ipairs(CEILING_ORDER) do
    local q = led.gated[kind]
    if not Scoring.Q.is_identity(kind, q) then
      local clause = quantity_clause(kind, q)
      if clause then parts[#parts + 1] = clause end
    end
  end
  if #parts == 0 then return nil end
  local sources = {}
  for _, src in ipairs(led.sources) do
    local name = normalize_text(src.name)
    local figure = amount(src.kind, src.total.n)
    local why = src.why
    if why and why_restates_row(rows, name, figure, why) then why = nil end
    sources[#sources + 1] = name .. " " .. figure .. (why and (" -- " .. why) or "")
  end
  table.sort(sources)
  local s = "a further " .. join(parts, " and ")
    .. " more from jokers gated on something other than the hand type"
  if #sources > 0 then
    s = s .. " (" .. table.concat(sources, "; ") .. ")"
  end
  return s
end

local function held_count_unreadable(led)
  if not (led.covered and led.covered.held_card) then return false end
  local cards = G and G.hand and G.hand.cards
  if type(cards) ~= "table" then return false end
  for _, card in ipairs(cards) do
    if CardUtil.is_face_down(card) then return true end
  end
  return false
end

local function jk_all_prose(agg, roster_only, rows)
  local led = agg.ledger
  local out = {}

  do
    local up = {}
    for _, kind in ipairs({ "chips", "mult", "xmult", "xchips" }) do
      local n = led and led.always[kind].n or agg[kind]
      if n and n ~= ((kind == "xmult" or kind == "xchips") and 1 or 0) then
        up[#up + 1] = amount(kind, n)
      end
    end
    if #up > 0 then out[#out + 1] = "always on " .. table.concat(up, ", ") end
  end

  local types = {}
  for t in pairs(agg.cond_by_type or {}) do types[#types + 1] = t end
  table.sort(types)
  for _, t in ipairs(types) do
    local b = agg.cond_by_type[t]
    local acc_m, acc_c = b.acc_mult or 0, b.acc_chips or 0
    local acc_x = (tonumber(b.acc_xmult) or 0) ~= 0 and b.acc_xmult or 1
    local acc_xc = (tonumber(b.acc_xchips) or 0) ~= 0 and b.acc_xchips or 1
    local con_m = (b.mult or 0) - acc_m
    local con_c = (b.chips or 0) - acc_c
    local con_x = (b.xmult or 1) / acc_x
    local con_xc = (b.xchips or 1) / acc_xc
    local cp = {}
    if con_m ~= 0 then cp[#cp + 1] = Utils.signed(con_m) .. " Mult" end
    if con_c ~= 0 then cp[#cp + 1] = Utils.signed(con_c) .. " Chips" end
    if con_x ~= 1 then cp[#cp + 1] = Utils.fmt_xmult(con_x) .. " Mult" end
    if con_xc ~= 1 then cp[#cp + 1] = Utils.fmt_xmult(con_xc) .. " Chips" end
    if #cp > 0 and ((b.njokers or 0) >= 2 or not roster_only) then
      out[#out + 1] = "if the hand contains a " .. t .. ": " .. table.concat(cp, ", ")
    end
    if b.accumulator then
      local ap = {}
      if acc_m ~= 0 then ap[#ap + 1] = Utils.signed(acc_m) .. " Mult" end
      if acc_c ~= 0 then ap[#ap + 1] = Utils.signed(acc_c) .. " Chips" end
      if acc_x ~= 1 then ap[#ap + 1] = Utils.fmt_xmult(acc_x) .. " Mult" end
      if acc_xc ~= 1 then ap[#ap + 1] = Utils.fmt_xmult(acc_xc) .. " Chips" end
      if #ap > 0 then
        out[#out + 1] = "if the hand you play is exactly " .. t
          .. " (containing one is not enough): " .. table.concat(ap, ", ")
      end
    end
  end

  local has_ceiling = false
  if led and not roster_only and not held_count_unreadable(led) then
    local ceiling = ceiling_sentence(led, rows)
    if ceiling then
      out[#out + 1] = ceiling
      has_ceiling = true
    end
  end

  local retrig = {}
  for _, e in ipairs(agg.retriggers or {}) do
    local clause = retrigger_clause(e, roster_only)
    if clause then retrig[#retrig + 1] = clause end
  end
  append_sorted(out, retrig)

  if not roster_only then
    local refused = {}
    for _, r in ipairs(led and led.refused or {}) do
      refused[#refused + 1] = "no number for " .. normalize_text(r.name)
        .. " -- it depends on " .. tostring(r.reason)
    end
    append_sorted(out, refused)
  end

  if #out == 0 then return nil end
  return preamble(led or { covered = {}, refused = {} }, has_ceiling, agg.hidden_jokers)
    .. table.concat(out, "; ") .. "."
end

local function order_gap_prose(gap)
  local parts = {}
  for _, b in ipairs(gap.behind) do
    parts[#parts + 1] = normalize_text(safe_name_or(b.card)) .. " (" .. b.index .. ") "
      .. Utils.signed(b.mult) .. " Mult"
  end
  local many = #parts > 1
  return "Joker order: " .. table.concat(parts, "; ") .. (many and " sit" or " sits")
    .. " right of " .. normalize_text(safe_name_or(gap.pivot.card)) .. " (" .. gap.pivot.index
    .. "), so its " .. Utils.fmt_xmult(gap.pivot.xmult) .. " Mult does not multiply "
    .. (many and "them." or "it.")
end

local function order_gap_text()
  if not (G and G.NEURO) then return nil end
  local gap = Scoring.joker_order_gap()
  if not gap then return nil end
  local round = tonumber(G.GAME and G.GAME.round) or 0
  local text = FactHints.emit(
    "joker_order_gap:" .. gap.signature .. "@" .. round,
    order_gap_prose(gap) .. " ")
  if type(text) ~= "string" or text == "" then return nil end
  return (text:gsub("%s+$", ""))
end

local function resolve_provenance(lines, first_row, marks)
  local counts, top, top_n, unattributed = {}, nil, 0, false
  for _, m in ipairs(marks) do
    if m.sig then
      counts[m.sig] = (counts[m.sig] or 0) + 1
      if counts[m.sig] > top_n then top, top_n = m, counts[m.sig] end
    else
      unattributed = true
    end
  end
  local hoist = (not unattributed) and top_n >= 2
  for i = first_row, #lines do
    lines[i] = lines[i]:gsub("\1(%d+)\2", function(n)
      local m = marks[tonumber(n)] or {}
      if hoist and m.sig == top.sig then return "" end
      return m.label or ""
    end)
  end
  if not hoist then return nil end
  return string.format("%s plan tags above written by you, Ante %s, decision %s.",
    (top_n == #marks) and "All" or "The rest of the", top.ante, top.decision)
end

local AGG_SILENT = { ROUND_EVAL = true }
local function jokers_section(state_name)
  if not G or not G.jokers or not G.jokers.cards then return nil end

  if #G.jokers.cards == 0 then
    local slots = CardUtil.slot_status_text(CardUtil.joker_slot_status())
    local sold_run = tonumber(G.NEURO and G.NEURO.jokers_sold_run) or 0
    return "Your jokers (" .. slots .. "; " .. sold_run .. " sold this run): none."
  end

  for _, card in ipairs(G.jokers.cards) do Utils.refresh_dynamic_joker(card) end

  local slots = CardUtil.slot_status_text(CardUtil.joker_slot_status())
  local sold_run = tonumber(G.NEURO and G.NEURO.jokers_sold_run) or 0
  local lines = { "Your jokers (" .. slots .. "; " .. sold_run .. " sold this run):" }
  local in_shop = require("core.state").get_state_name() == "SHOP"
  local has_hidden = false
  local rows = {}
  local marks = {}
  local first_row = #lines + 1
  for i, card in ipairs(G.jokers.cards) do
    if CardUtil.is_face_down(card) then
      has_hidden = true
      lines[#lines + 1] = i .. ". face-down (hidden)"
    else
      local name = normalize_text(safe_name_or(card))
      local effect_str = SemanticRegistry.render("owned_joker_row", card):gsub(",", ";")
      local copied = copied_numbers(card)
      if copied then effect_str = effect_str .. "; copying " .. copied end
      local flg = joker_tags(card)
      local entry = G.NEURO and G.NEURO.joker_intents and G.NEURO.joker_intents[card.sort_id]
      local tag = entry and entry.tag or nil
      local note = in_shop and entry and entry.note or nil
      local bought_cost = G.NEURO and G.NEURO.joker_bought_cost
        and G.NEURO.joker_bought_cost[card.sort_id]
      local bought = (bought_cost ~= nil) and Utils.money(bought_cost) or nil
      local row = joker_row_prose(i, name, effect_str, flg, Utils.money(card.sell_cost), tag, note,
        bought, entry and entry.provenance, marks)
      rows[name] = (rows[name] or "") .. " " .. row:gsub("\1%d+\2", ""):lower()
      lines[#lines + 1] = row
    end
  end

  local shared_provenance = resolve_provenance(lines, first_row, marks)
  if shared_provenance then lines[#lines + 1] = shared_provenance end

  local observed = JokerObservations.roster_line(G.jokers.cards)
  if observed then lines[#lines + 1] = observed end

  local hand_in_play = (state_name ~= nil) and (state_name == "SELECTING_HAND")
    or (state_name == nil and GameFacts.hand_can_score())
  local silent = state_name ~= nil and AGG_SILENT[state_name]
  local agg = (not silent) and Scoring.joker_summary(nil, { public_only = true }) or nil
  if agg then
    local prose = jk_all_prose(agg, not hand_in_play, rows)
    if prose and prose ~= "" then lines[#lines + 1] = prose end
  end
  if not has_hidden then
    local order_gap = order_gap_text()
    if order_gap then lines[#lines + 1] = order_gap end
  end

  return table.concat(lines, "\n")
end

local function joker_descriptions_section()
  if not G or not G.jokers or not G.jokers.cards or #G.jokers.cards == 0 then
    return nil
  end
  local lines = { "Joker details:" }
  for i, card in ipairs(G.jokers.cards) do
    if CardUtil.is_face_down(card) then
      lines[#lines + 1] = i .. ". face-down (hidden)"
    else
      local name = normalize_text(safe_name_or(card))
      local desc = SemanticRegistry.render("card_description_full", card)
      local s = i .. ". " .. name
      if desc and desc ~= "-" and desc ~= "" then s = s .. " -- " .. strip_dot(desc:gsub(";%s*", ", ")) end
      lines[#lines + 1] = s .. "."
    end
  end
  return table.concat(lines, "\n")
end

local function playbook_section(include_full_desc)
  if not (G and G.playbook_extra and G.playbook_extra.cards and #G.playbook_extra.cards > 0) then
    return nil
  end

  local lines = { "Playbook jokers:" }
  for i, card in ipairs(G.playbook_extra.cards) do
    local name = normalize_text(safe_name_or(card))
    local effect_str = SemanticRegistry.render("readable_joker", card):gsub(",", ";")
    local row = joker_row_prose(i, name, effect_str, joker_tags(card), Utils.money(card.sell_cost))
    if include_full_desc then
      local desc = SemanticRegistry.render("card_description_full", card)
      if desc and desc ~= "-" and desc ~= "" then
        local desc_h = desc:gsub(";%s*", ", ")
        if not row:find(desc_h, 1, true) then row = row .. ". " .. desc_h end
      end
    end
    lines[#lines + 1] = row
  end

  return table.concat(lines, "\n")
end

local M = { jokers_section = jokers_section, playbook_section = playbook_section }

if rawget(_G, "NEURO_TEST") then
  M.joker_descriptions_section = joker_descriptions_section
end

return M
