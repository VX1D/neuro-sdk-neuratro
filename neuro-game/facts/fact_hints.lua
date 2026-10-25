local M = {}

local GameFacts = require("facts.game_facts")
local CardUtil = require("facts.card_util")

local Utils = require("util.utils")
local Once = require("util.once")
local HintRegistry = require("facts.hint_registry")

local pending, pending_seen = {}, {}

local CHANNEL = {
  session = "shint:",
  run = "rhint:",
}

local function reset_pending()
  pending, pending_seen = {}, {}
end

local function queue_hint(key, epoch, text)
  if not (G and G.NEURO and text and text ~= "") then
    return ""
  end
  if pending_seen[key] or not Once.peek(key, epoch) then
    return ""
  end
  pending_seen[key] = true
  pending[#pending + 1] = { key = key, epoch = epoch, text = text }
  return ""
end


local function once_per_run_hint(tag, text)
  if not (G and G.NEURO) then return "" end
  return queue_hint(CHANNEL.run .. tostring(tag or "hint"), "run", text)
end

local function gate_for(tag, cadence)
  if not (G and G.NEURO) then return nil, nil end
  if cadence == "session" then
    return CHANNEL.session .. tostring(tag), "session"
  elseif cadence == "run" then
    return CHANNEL.run .. tostring(tag), "run"
  end
  return nil, nil
end

local function emit(tag, text)
  if type(text) ~= "string" or text == "" then return "" end
  local entry = HintRegistry.lookup(tag)
  if not entry then
    require("util.metrics").incr("hint_unregistered")
    if rawget(_G, "NEURO_TEST") then
      error("hint tag not registered in facts/hint_registry.lua: " .. tostring(tag), 2)
    end
    print("[neuro-game] unregistered hint tag routed to the context channel: " .. tostring(tag))
    return once_per_run_hint(tag, text)
  end
  if not (G and G.NEURO) then return "" end
  local key, epoch = gate_for(tag, entry.cadence)
  if not key then return "" end
  return queue_hint(key, epoch, text)
end


local function flush_pending()
  if #pending == 0 then return 0 end
  local queued = pending
  reset_pending()
  if not Utils.can_send() then return 0 end
  local Delivery = require("core.context_delivery")
  local accepted = 0
  for _, h in ipairs(queued) do
    local key, epoch = h.key, h.epoch
    local ok = Delivery.rule("hint:" .. h.key .. "@" .. tostring(h.epoch), h.text, {
      on_written = function() Once.book(key, epoch) end,
    })
    if ok then accepted = accepted + 1 end
  end
  return accepted
end

local function chain_visible(card, target)
  if CardUtil.is_hidden(card) then return false end
  return not (target and CardUtil.is_hidden(target))
end

function M.copy_chain()
  if not (G and G.jokers and G.jokers.cards) then return nil end
  local cards = G.jokers.cards
  local chain_parts = {}
  for i, card in ipairs(cards) do
    local kind = CardUtil.copy_joker_kind(card)
    if kind then
      local target = (kind == "brainstorm") and cards[1] or cards[i + 1]
      if target == card then target = nil end
      if chain_visible(card, target) then
        local nm = Utils.safe_name_or(card)
        local target_nm = target and Utils.safe_name_or(target) or "none"
        local where = (kind == "brainstorm") and "the leftmost joker" or "the joker to its right"
        chain_parts[#chain_parts + 1] = string.format("%s (slot %d) copies %s (%s)", nm, i, where, target_nm)
      end
    end
  end
  if #chain_parts == 0 then return nil end
  return table.concat(chain_parts, "; ")
end

function M.voucher_chains()
  local chains = {}
  for key, up in pairs(G and G.P_CENTERS or {}) do
    local base_key = type(up) == "table" and up.set == "Voucher" and type(up.requires) == "table" and up.requires[1]
    local base = base_key and G.P_CENTERS[base_key]
    if base then
      chains[#chains + 1] = { base = base_key, upgrade = key, base_name = base.name, up_name = up.name,
        order = tonumber(base.order) or 0 }
    end
  end
  table.sort(chains, function(x, y)
    if x.order ~= y.order then return x.order < y.order end
    return x.upgrade < y.upgrade
  end)
  return chains
end

function M.voucher_chain_hint()
  if not (G and G.GAME) then return "" end
  local owned = G.GAME.used_vouchers or {}
  local chains = M.voucher_chains()
  local shop_keys = {}
  if G.shop_vouchers and G.shop_vouchers.cards then
    for _, card in ipairs(G.shop_vouchers.cards) do
      if not CardUtil.is_hidden(card) then
        local key = CardUtil.center_key(card) or ""
        if key ~= "" then shop_keys[key] = true end
      end
    end
  end
  local out = {}
  for _, pair in ipairs(chains) do
    local relevant = (shop_keys[pair.base] and not owned[pair.base])
      or (shop_keys[pair.upgrade] and owned[pair.base])
    local sentence = relevant and require("facts.voucher_facts").unlock_sentence(pair.base)
    if sentence then out[#out + 1] = emit("voucher_chain:" .. pair.base, sentence .. ". ") end
  end
  return table.concat(out, "")
end

function M.voucher_basics_hint()
  if not (G and G.shop_vouchers and G.shop_vouchers.cards and G.shop_vouchers.cards[1]) then return "" end
  return emit("voucher_basics_run",
    "A voucher is a permanent, run-wide upgrade that lasts the rest of the run once bought. Rerolling the shop never replaces a voucher on offer -- a reroll only redraws the cards for sale. The vouchers a shop is offering are listed with that shop. ")
end

function M.shop_edition_hint()
  for _, c in ipairs((G and G.shop_jokers and G.shop_jokers.cards) or {}) do
    if not CardUtil.is_hidden(c) and c.edition and CardUtil.card_set(c) == "Joker" then
      local tag = CardUtil.edition_name(c.edition)
      if tag and tag ~= "" then
        return "A shop joker's edition is attached to that Joker; its listed edition effect applies alongside the card text and occupies no separate Joker slot. "
          .. "Editions are permanent and stack on the base effect, and are hard to add later (only a few consumables can). Worth taking when a joker slot is open. "
      end
    end
  end
  return ""
end

function M.plan_mark(provenance)
  local mark = {}
  if type(provenance) == "table" then
    mark.ante = tostring(provenance.ante or "?")
    mark.decision = tostring(provenance.decision_serial or "?")
    local write = tonumber(provenance.write)
    if write and write > 1 then mark.decision = mark.decision .. ", write " .. write end
    mark.sig = mark.ante .. "@" .. mark.decision
    mark.label = string.format(" (written by you, Ante %s, decision %s)", mark.ante, mark.decision)
  end
  return mark
end

function M.plan_mark_hoist(marks)
  local counts, top, top_n, unattributed = {}, nil, 0, false
  for _, m in ipairs(marks) do
    if m.sig then
      counts[m.sig] = (counts[m.sig] or 0) + 1
      if counts[m.sig] > top_n then top, top_n = m, counts[m.sig] end
    else
      unattributed = true
    end
  end
  return top, top_n, (not unattributed) and top_n >= 2
end

local PLAN_WINDOWS = {
  shop = { order = { "build", "hand", "money" },
    lead = "Your plan notes (Your plan, above) are not a snapshot: current shop rows and facts win; revise only fields changed by your action. " },
  pack = { order = { "build", "hand" },
    lead = "Pick to advance the weakness your plan notes (Your plan, above) diagnose; current pack contents and game facts are authoritative. " },
  blind = { order = { "hand", "build" },
    lead = "Facts win over your plan notes (Your plan, above); revise your plan if your intended line changed. " },
  hand = { order = { "boss", "hand", "build" },
    lead = "Facts win over your plan notes (Your plan, above); the hand and build lines cannot be revised until the shop or next blind select. " },
}

local PLAN_FIELDS = {
  build = { now = "Build focus", last = "Your build last shop", earlier = "Your earlier build plan",
    changed = "Roster changed -- continue this direction, iterate on it, or change it (build_plan)." },
  hand = { now = "Hand decision", last = "Your hand plan last blind", earlier = "Your earlier hand plan",
    changed = "Blind changed -- keep this line, adapt it, or set a new one (hand_plan)." },
  money = { now = "Economy decision", last = "Your last economy call", earlier = "Your earlier economy call",
    changed = "Shop/economy changed -- hold it or revise (money_plan)." },
}

local function plan_parts(window)
  local spec = PLAN_WINDOWS[window]
  local p = G and G.NEURO and G.NEURO.plan
  if not spec or not p or not (p.hand or p.build or p.money or p.hand_focus or p.boss) then return nil end
  local Gate = require("core.gate")
  local cur = GameFacts.ante(0)
  local can_amend = (window == "shop" or window == "blind")
  local lines, asks, marks = {}, {}, {}
  local stale_any = false
  local function provenance(field)
    local rec = p.provenance and p.provenance[field]
    local source_ante = type(rec) == "table" and tonumber(rec.ante) or tonumber(p.ante)
    marks[#marks + 1] = M.plan_mark(rec)
    local stale = ""
    if source_ante and cur > source_ante then
      local d = cur - source_ante
      stale_any = true
      stale = string.format(" [set %d ante%s ago]", d, d == 1 and "" or "s")
    end
    return "\1" .. #marks .. "\2" .. stale
  end
  local function add_plan(field)
    if not p[field] then return end
    local f = PLAN_FIELDS[field]
    if Gate[field .. "_plan_is_current"](p) then
      lines[#lines + 1] = f.now .. provenance(field) .. ": " .. p[field]
    elseif can_amend then
      lines[#lines + 1] = f.last .. provenance(field) .. ": '" .. p[field] .. "'"
      asks[#asks + 1] = f.changed
    else
      lines[#lines + 1] = f.earlier .. provenance(field) .. ": '" .. p[field] .. "'"
    end
  end
  local function add_focus()
    if type(p.hand_focus) == "table" and Gate.hand_focus_is_current(p) then
      local focus = "Declared hand focus" .. provenance("focus") .. ": primary " .. tostring(p.hand_focus.primary)
      if p.hand_focus.fallback then focus = focus .. ", fallback " .. tostring(p.hand_focus.fallback) end
      lines[#lines + 1] = focus
    end
  end
  for _, field in ipairs(spec.order) do
    if field == "boss" then
      local blind = G.GAME and G.GAME.blind
      if p.boss and blind and blind.boss and Gate.boss_plan_is_current(p) then
        lines[#lines + 1] = "Your boss-round plan" .. provenance("boss") .. ": '" .. tostring(p.boss) .. "'"
      end
    else
      add_plan(field)
      if field == "hand" then add_focus() end
    end
  end
  if #lines == 0 then return nil end
  local top, top_n, hoist = M.plan_mark_hoist(marks)
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("\1(%d+)\2", function(n)
      local m = marks[tonumber(n)]
      return (hoist and m.sig == top.sig) and "" or (m.label or "")
    end)
  end
  if hoist then
    lines[#lines + 1] = string.format("%s written by you, Ante %s, decision %s.",
      (top_n == #marks) and "All" or "The rest", top.ante, top.decision)
  end
  if stale_any then asks[#asks + 1] = "Update any note set in an earlier ante if it no longer fits." end
  return { lines = lines, asks = asks, lead = spec.lead }
end

function M.plan_state(window)
  local parts = plan_parts(window)
  if not parts then return "" end
  return "## Your plan\n" .. table.concat(parts.lines, "\n")
end

function M.plan_note(window)
  local parts = plan_parts(window)
  if not parts then return "" end
  return parts.lead .. (#parts.asks > 0 and (table.concat(parts.asks, " ") .. " ") or "")
end

local function visit_sales(create)
  local N = G and G.NEURO
  if not N then return nil end
  local epoch = tonumber(N.shop_visit_epoch) or 0
  local rec = N.jokers_sold
  if type(rec) ~= "table" or rec.epoch ~= epoch then
    if not create then return nil end
    rec = { epoch = epoch, count = 0, unreplaced = 0 }
    N.jokers_sold = rec
  end
  return rec
end

function M.note_joker_sold()
  local rec = visit_sales(true)
  if not rec then return end
  rec.count = (rec.count or 0) + 1
  rec.unreplaced = (tonumber(rec.unreplaced) or 0) + 1
  G.NEURO.jokers_sold_run = (tonumber(G.NEURO.jokers_sold_run) or 0) + 1
end

function M.note_joker_gained()
  local rec = visit_sales(false)
  if rec then rec.unreplaced = math.max(0, (tonumber(rec.unreplaced) or 0) - 1) end
end

local function joker_sales_this_visit()
  local rec = visit_sales(false)
  if not rec then return 0, 0 end
  return tonumber(rec.count) or 0, tonumber(rec.unreplaced) or 0
end

function M.joker_churn_note()
  local sold, unreplaced = joker_sales_this_visit()
  if unreplaced < 1 then return "" end
  return string.format(
    "You have sold %d joker%s this shop visit -- jokers are your scoring engine; do not keep selling them for cash, only for a specific planned buy. ",
    sold, sold == 1 and "" or "s")
end

M.joker_sales_this_visit = joker_sales_this_visit
M.reset_pending = reset_pending
M.flush_pending = flush_pending
M.emit = emit
if _G.NEURO_TEST then
  M.pending_count = function() return #pending end
  M.once_per_run_hint = once_per_run_hint
end


return M
