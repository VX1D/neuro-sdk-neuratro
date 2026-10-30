local CtxHelpers = require("context.ctx_helpers")
local CardUtil = require("facts.card_util")
local Utils = require("util.utils")
local Scoring = require("util.scoring")
local FactHints = require("facts.fact_hints")
local SemanticRegistry = require("core.semantic_registry")
local JokerObservations = require("facts.joker_observations")
local GameFacts = require("facts.game_facts")
local normalize_text = CtxHelpers.normalize_text
local clause_separators = CtxHelpers.clause_separators
local joker_tags = CtxHelpers.joker_tags
local safe_name_or = Utils.safe_name_or
local humanize_effect = CtxHelpers.humanize_effect
local humanize_flags = CtxHelpers.humanize_flags

local function sell_offered(card)
  local ok_b, blocked = pcall(require("facts.boss.legality").sell_blocked_now, card)
  return not (ok_b and blocked)
end

local function unsellable(flags)
  return type(flags) == "string" and flags:find("eternal(unsellable)", 1, true) ~= nil
end

local function provenance_mark(marks, provenance)
  marks[#marks + 1] = FactHints.plan_mark(provenance)
  return "\1" .. #marks .. "\2"
end

local function joker_row_prose(card, idx, name, effect_str, flags, sell, tag, note, bought, provenance, marks)
  local s = idx .. ". " .. name
  local he = (effect_str ~= "-" and effect_str ~= "") and humanize_effect(effect_str, true) or ""
  if he and he ~= "" then s = s .. " -- " .. he end
  local hf = humanize_flags(flags)
  if hf and hf ~= "" and hf ~= "-" then s = s .. " [" .. hf .. "]" end
  if sell_offered(card) and not unsellable(flags) then
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

local function copy_now_text(card)
  local kind = CardUtil.copy_joker_kind(card)
  if not kind then return nil end
  local now = require("facts.dynamic_jokers").copy_now(card, kind)
  local status = now.status
  local target = now.target and normalize_text(safe_name_or(now.target))
  local why
  if status == "copying" then return "copying now: " .. target end
  if status == "hidden" then return "copying now: a face-down joker" end
  if status == "debuffed_self" then
    why = "it is debuffed"
  elseif status == "none" then
    why = (kind == "brainstorm") and "it is your leftmost joker" or "no joker to its right"
  elseif status == "hidden_incompatible" then
    why = (kind == "brainstorm") and "the face-down leftmost joker can't be copied"
      or "the face-down joker to its right can't be copied"
  elseif status == "incompatible" then
    why = target .. " can't be copied"
  elseif status == "debuffed" then
    why = target .. " is debuffed"
  end
  return "copying now: nothing (" .. why .. ")"
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

local join = CtxHelpers.join

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
  local sources = CtxHelpers.ledger_gated_sources(led, function(g, figure)
    return why_restates_row(rows, g.name, figure, g.why)
  end)
  table.sort(sources)
  local s = "a further " .. join(parts, " and ")
    .. " more from jokers gated on something other than the hand type"
  if #sources > 0 then
    s = s .. " (" .. table.concat(sources, "; ") .. ")"
  end
  return s
end

local function dormant_sentence(led)
  local parts = {}
  for _, d in ipairs(led.dormant or {}) do
    parts[#parts + 1] = normalize_text(d.name) .. " " .. amount(d.kind, d.total.n)
      .. (d.why and (" -- its condition (" .. d.why .. ") does not hold") or "")
  end
  if #parts == 0 then return nil end
  table.sort(parts)
  return "not on this hand: " .. table.concat(parts, "; ")
end

local function met_sentence(led, rows)
  local named, parts = {}, {}
  for _, m in ipairs(led.met or {}) do named[m.name] = (named[m.name] or 0) + 1 end
  for _, m in ipairs(led.met) do
    local label = normalize_text(m.name) .. ((named[m.name] > 1 and m.slot) and (" (#" .. m.slot .. ")") or "")
    local figure = amount(m.kind, m.total.n)
    local cond = m.why
    if cond and why_restates_row(rows, normalize_text(m.name), figure, cond) then cond = nil end
    local why
    if m.rescored then why = cond else why = "its condition holds now" .. (cond and (": " .. cond) or "") end
    parts[#parts + 1] = label .. " " .. figure .. (why and (" -- " .. why) or "")
  end
  if #parts == 0 then return nil end
  table.sort(parts)
  return "also paid on the next hand you play, whatever it is: " .. table.concat(parts, "; ")
end

-- This ceiling must not reveal a hidden held card’s rank.
local function held_count_unreadable(ledger)
  if not (ledger.covered and ledger.covered.held_card) then return false end
  local cards = G and G.hand and G.hand.cards
  if type(cards) ~= "table" then return false end
  for _, card in ipairs(cards) do
    if CardUtil.is_hidden(card) then return true end
  end
  return false
end

local function bonus_list(m, c, x, xc)
  local out = {}
  if m ~= 0 then out[#out + 1] = Utils.signed(m) .. " Mult" end
  if c ~= 0 then out[#out + 1] = Utils.signed(c) .. " Chips" end
  if x ~= 1 then out[#out + 1] = Utils.fmt_xmult(x) .. " Mult" end
  if xc ~= 1 then out[#out + 1] = Utils.fmt_xmult(xc) .. " Chips" end
  return out
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
  local met = led and met_sentence(led, rows)
  if met then out[#out + 1] = met end

  local types = {}
  for t in pairs(agg.cond_by_type or {}) do types[#types + 1] = t end
  table.sort(types)
  for _, t in ipairs(types) do
    local b = agg.cond_by_type[t]
    local cp = bonus_list(b.con_mult or 0, b.con_chips or 0, b.con_xmult or 1, b.con_xchips or 1)
    if #cp > 0 and ((b.njokers or 0) >= 2 or not roster_only) then
      out[#out + 1] = "if the hand contains a " .. t .. ": " .. table.concat(cp, ", ")
    end
    if b.accumulator then
      local ap = bonus_list(b.acc_mult or 0, b.acc_chips or 0, b.acc_xmult or 1, b.acc_xchips or 1)
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

  if led and not roster_only then
    local dormant = dormant_sentence(led)
    if dormant then out[#out + 1] = dormant end
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
local function hands_paid(cond)
  if not cond then return "on every hand" end
  if cond.exact then return "on a " .. cond.hand_type end
  return "on hands that contain a " .. cond.hand_type
end

local UNIT = { mult = "Mult", chips = "Chips" }
local BOUND = { [""] = "", at_most = "up to ", at_least = "at least " }

local function group_prose(group)
  local unit = UNIT[group.add]
  local parts, clauses, by_cond = {}, {}, {}
  local pivot = normalize_text(safe_name_or(group.pivot.card))
  for _, b in ipairs(group.behind) do
    local name = normalize_text(safe_name_or(b.card))
    parts[#parts + 1] = name .. " (slot " .. b.index .. ") " .. BOUND[b.bound or ""] .. Utils.signed(b.amount) .. " " .. unit
    local cond = hands_paid(b.cond)
    if not by_cond[cond] then
      by_cond[cond] = { cond = cond, items = {} }
      clauses[#clauses + 1] = by_cond[cond]
    end
    local items = by_cond[cond].items
    items[#items + 1] = name .. " " .. BOUND[b.gain_bound or ""] .. Utils.signed(b.gain) .. " " .. unit
  end
  local many = #parts > 1
  local gains = {}
  for _, c in ipairs(clauses) do gains[#gains + 1] = join(c.items) .. " more " .. c.cond end
  local gain = many and ("they would add " .. table.concat(gains, "; "))
    or (normalize_text(safe_name_or(group.behind[1].card)) .. " would add "
      .. BOUND[group.behind[1].gain_bound or ""] .. Utils.signed(group.behind[1].gain) .. " " .. unit .. " more " .. clauses[1].cond)
  return table.concat(parts, "; ") .. (many and " sit" or " sits")
    .. " right of " .. pivot .. " (slot " .. group.pivot.index
    .. "), so its " .. Utils.fmt_xmult(group.pivot.factor) .. " " .. unit .. (group.pivot.floor and " or more" or "")
    .. " does not multiply "
    .. (many and "them" or "it") .. ". Left of " .. pivot .. ", " .. gain .. "."
end

local function order_gap_prose(gap)
  local out = {}
  for _, group in ipairs(gap.groups) do out[#out + 1] = group_prose(group) end
  return "Joker order: " .. table.concat(out, " ")
end

local function order_gap_text()
  if not (G and G.NEURO) then return nil end
  local gap = Scoring.joker_order_gap()
  if not gap then return nil end
  return (order_gap_prose(gap):gsub("%s+$", ""))
end

local function resolve_provenance(lines, first_row, marks)
  local top, top_n, hoist = FactHints.plan_mark_hoist(marks)
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

  for _, card in ipairs(G.jokers.cards) do Utils.refresh_dynamic_joker(card) end
  local head = "Your jokers (" .. CardUtil.slot_status_text(CardUtil.joker_slot_status()) .. "; "
    .. (tonumber(G.NEURO and G.NEURO.jokers_sold_run) or 0) .. " sold this run)"
  if #G.jokers.cards == 0 then return head .. ": none." end

  local lines = { "## " .. head:sub(1, -2) .. "; 1 = leftmost, they trigger left to right)" }
  local in_shop = require("core.state").get_state_name() == "SHOP"
  local has_hidden = false
  local rows = {}
  local marks = {}
  local first_row = #lines + 1
  for i, card in ipairs(G.jokers.cards) do
    if CardUtil.is_hidden(card) then
      has_hidden = true
      lines[#lines + 1] = i .. ". face-down (hidden)"
    else
      local name = normalize_text(safe_name_or(card))
      local effect_str = clause_separators(SemanticRegistry.render("owned_joker_row", card))
      local copied = copied_numbers(card)
      if copied then effect_str = effect_str .. "; copying " .. copied end
      local copy_now = copy_now_text(card)
      if copy_now then
        effect_str = (effect_str == "-" or effect_str == "") and copy_now or (effect_str .. "; " .. copy_now)
      end
      local flg = joker_tags(card)
      local entry = G.NEURO and G.NEURO.joker_intents and G.NEURO.joker_intents[card.sort_id]
      local tag = entry and entry.tag or nil
      local note = in_shop and entry and entry.note or nil
      local bought_cost = G.NEURO and G.NEURO.joker_bought_cost
        and G.NEURO.joker_bought_cost[card.sort_id]
      local bought = (bought_cost ~= nil) and Utils.money(bought_cost) or nil
      local row = joker_row_prose(card, i, name, effect_str, flg, Utils.money(card.sell_cost), tag, note,
        bought, entry and entry.provenance, marks)
      rows[name] = (rows[name] or "") .. " " .. row:gsub("\1%d+\2", ""):lower()
      lines[#lines + 1] = row
    end
  end

  local shared_provenance = resolve_provenance(lines, first_row, marks)
  if shared_provenance then lines[#lines + 1] = shared_provenance end

  local observed = JokerObservations.roster_line(G.jokers.cards)
  if observed then lines[#lines + 1] = observed end

  if (Scoring.owned_xmult_state() or "none") == "none" then
    lines[#lines + 1] = "- Of the jokers here, none is an xMult."
  end

  local hand_in_play = (state_name ~= nil) and (state_name == "SELECTING_HAND")
    or (state_name == nil and GameFacts.hand_can_score())
  local silent = state_name ~= nil and AGG_SILENT[state_name]
  local agg = (not silent) and Scoring.joker_summary(nil) or nil
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


local M = { jokers_section = jokers_section }


return M
