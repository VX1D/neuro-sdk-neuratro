local M = {}

local Utils = require("util.utils")
local PublicCard = require("facts.public_card_identity")

local MAX_PUBLIC_LABEL_BYTES = 160
local MAX_RENDERED_EVENTS = 16
local MAX_HAND_OUTCOMES = 12
local MAX_RENDERED_HAND_OUTCOMES = 6

local BUY_AREAS = { shop_jokers = true, shop_vouchers = true, shop_booster = true }
local SELL_AREAS = { jokers = true, consumeables = true }
local PURCHASE_KINDS = {
  joker = true, consumable = true, voucher = true, booster = true, buy_and_use = true, other = true,
}

local function integer(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function truncate_utf8(text, max_bytes)
  if #text <= max_bytes then return text end
  local i, complete_through = 1, 0
  while i <= #text and i <= max_bytes do
    local b = text:byte(i)
    local width = (b < 0x80 and 1)
      or (b >= 0xC2 and b <= 0xDF and 2)
      or (b >= 0xE0 and b <= 0xEF and 3)
      or (b >= 0xF0 and b <= 0xF4 and 4)
      or 1
    if i + width - 1 > max_bytes then break end
    local valid = true
    for j = i + 1, i + width - 1 do
      local continuation = text:byte(j)
      if not continuation or continuation < 0x80 or continuation > 0xBF then
        valid = false
        break
      end
    end
    if not valid then width = 1 end
    complete_through = i + width - 1
    i = complete_through + 1
  end
  return text:sub(1, complete_through)
end

local function public_label(value)
  local text = Utils.normalize_ws(value or "item")
  if text == "" then text = "item" end
  return truncate_utf8(text, MAX_PUBLIC_LABEL_BYTES)
end

function M.public_card_label(card, area, index)
  return public_label(PublicCard.label(card, area, index))
end

local function validate_body(body)
  if type(body) ~= "table" then return nil, "event body must be a table" end
  if body.kind == "shop_buy" then
    if not BUY_AREAS[body.area] then return nil, "invalid shop_buy area" end
    if not PURCHASE_KINDS[body.purchase_kind] then return nil, "invalid purchase kind" end
    if not integer(body.paid) then return nil, "invalid paid value" end
    return {
      kind = body.kind,
      public_subject = public_label(body.public_subject),
      area = body.area,
      purchase_kind = body.purchase_kind,
      paid = body.paid,
    }
  elseif body.kind == "shop_sell" then
    if not SELL_AREAS[body.area] then return nil, "invalid shop_sell area" end
    if not integer(body.received) then return nil, "invalid received value" end
    return {
      kind = body.kind,
      public_subject = public_label(body.public_subject),
      area = body.area,
      received = body.received,
    }
  elseif body.kind == "shop_reroll" then
    if not integer(body.paid) then return nil, "invalid reroll paid value" end
    if type(body.used_free_reroll) ~= "boolean" then return nil, "invalid free-reroll flag" end
    if body.used_free_reroll and body.paid ~= 0 then return nil, "free reroll must cost zero" end
    return { kind = body.kind, paid = body.paid, used_free_reroll = body.used_free_reroll }
  end
  return nil, "unknown event kind"
end

local function read_store()
  local journal = G and G.NEURO and G.NEURO.gameplay_journal
  if type(journal) ~= "table" or type(journal.ordered) ~= "table"
      or type(journal.by_action_id) ~= "table" then
    return nil
  end
  return journal
end

local function ensure_store()
  if not (G and G.NEURO) then return nil end
  local journal = G.NEURO.gameplay_journal
  if type(journal) ~= "table" then
    journal = { next_sequence = 1, by_action_id = {}, ordered = {}, hand_outcomes = {} }
    G.NEURO.gameplay_journal = journal
  end
  journal.next_sequence = math.max(1, math.floor(tonumber(journal.next_sequence) or 1))
  journal.by_action_id = type(journal.by_action_id) == "table" and journal.by_action_id or {}
  journal.ordered = type(journal.ordered) == "table" and journal.ordered or {}
  journal.hand_outcomes = type(journal.hand_outcomes) == "table" and journal.hand_outcomes or {}
  return journal
end

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function validate_hand_outcome(body)
  if type(body) ~= "table" then return nil, "hand outcome must be a table" end
  if type(body.action_id) ~= "string" or body.action_id == "" then return nil, "action id required" end
  if type(body.hand_type) ~= "string" or body.hand_type == "" then return nil, "hand type required" end
  if not integer(body.hand_level) or body.hand_level < 1 then return nil, "invalid hand level" end
  if not integer(body.played_count) then return nil, "invalid played count" end
  if not integer(body.scored_count) then return nil, "invalid scored count" end
  if not finite_nonnegative(body.chips_delta) then return nil, "invalid chips delta" end
  return {
    kind = "hand_result",
    action_id = body.action_id,
    run_generation = tonumber(body.run_generation) or 0,
    ante = tonumber(body.ante) or 0,
    round = tonumber(body.round) or 0,
    blind_key = public_label(body.blind_key or "unknown blind"),
    hand_type = public_label(body.hand_type),
    hand_level = body.hand_level,
    played_count = body.played_count,
    scored_count = body.scored_count,
    chips_delta = body.chips_delta,
  }
end

function M.publish_hand_outcome(body)
  local clean, err = validate_hand_outcome(body)
  if not clean then return false, err end
  if not (G and G.NEURO) then return false, "journal unavailable" end
  local generation = tonumber(G.NEURO.run_generation) or 0
  if clean.run_generation ~= generation then return false, "stale generation" end
  local journal = ensure_store()
  if not journal then return false, "journal unavailable" end
  if journal.by_action_id[clean.action_id] then return false, "duplicate" end
  journal.by_action_id[clean.action_id] = true
  journal.hand_outcomes[#journal.hand_outcomes + 1] = clean
  while #journal.hand_outcomes > MAX_HAND_OUTCOMES do table.remove(journal.hand_outcomes, 1) end
  return true, clean
end

function M.observe_settled(state_name)
  local n = G and G.NEURO
  local lp = n and n.last_play
  if type(lp) ~= "table" or lp.kind ~= "play" or lp.outcome_observed then return false end
  if type(lp.action_id) ~= "string" or lp.action_id == "" then return false end
  if tonumber(lp.run_generation) ~= (tonumber(n.run_generation) or 0) then
    lp.outcome_observed = true
    return false
  end
  if not Utils.engine_settled() then return false end
  if G and G.play and type(G.play.cards) == "table" and #G.play.cards > 0 then return false end
  local current = tonumber(G and G.GAME and G.GAME.chips)
  local before = tonumber(lp.pre_chips)
  if not (current and before) then return false end
  if current < before then
    lp.outcome_observed = true
    return false
  end
  if current == before and state_name ~= "ROUND_EVAL" then return false end
  local ok, reason = M.publish_hand_outcome({
    action_id = lp.action_id,
    run_generation = lp.run_generation,
    ante = lp.ante,
    round = lp.round,
    blind_key = lp.blind_key,
    hand_type = lp.hand_type,
    hand_level = lp.hand_level,
    played_count = lp.played or 0,
    scored_count = lp.scored or 0,
    chips_delta = current - before,
  })
  if ok or reason == "duplicate" then lp.outcome_observed = true end
  return ok
end

function M.seal(body, action_id)
  local clean, err = validate_body(body)
  if not clean then return nil, err end
  if type(action_id) ~= "string" or action_id == "" then return nil, "action id required" end
  if not (G and G.NEURO) then return nil, "Neuro run state unavailable" end
  clean.action_id = action_id
  clean.run_generation = tonumber(G.NEURO.run_generation) or 0
  clean.shop_visit_epoch = tonumber(G.NEURO.shop_visit_epoch) or 0
  return clean
end

function M.publish(event)
  if type(event) ~= "table" then return false, "event missing" end
  local clean, err = validate_body(event)
  if not clean then return false, err end
  local id = event.action_id
  if type(id) ~= "string" or id == "" then return false, "action id required" end
  if not (G and G.NEURO) then return false, "journal unavailable" end
  local generation = tonumber(G.NEURO.run_generation) or 0
  if tonumber(event.run_generation) ~= generation then return false, "stale generation" end
  local journal = ensure_store()
  if not journal then return false, "journal unavailable" end
  if journal.by_action_id[id] then return false, "duplicate" end

  clean.action_id = id
  clean.run_generation = generation
  clean.shop_visit_epoch = tonumber(event.shop_visit_epoch) or 0
  clean.sequence = journal.next_sequence
  journal.next_sequence = clean.sequence + 1
  journal.by_action_id[id] = true -- tombstone survives body pruning until run reset
  journal.ordered[#journal.ordered + 1] = clean
  return true, clean
end

local function event_text(event)
  if event.kind == "shop_buy" then
    return "bought " .. event.public_subject .. " for " .. Utils.money(event.paid)
  elseif event.kind == "shop_sell" then
    return "sold " .. event.public_subject .. " for " .. Utils.money(event.received)
  elseif event.kind == "shop_reroll" then
    return event.used_free_reroll and "rerolled for $0 (free reroll)"
      or ("rerolled for " .. Utils.money(event.paid))
  end
  return nil
end

local function tail_text(events)
  local first = math.max(1, #events - MAX_RENDERED_EVENTS + 1)
  local parts = {}
  if first > 1 then parts[#parts + 1] = tostring(first - 1) .. " earlier transaction(s) omitted" end
  for i = first, #events do
    local text = event_text(events[i])
    if text then parts[#parts + 1] = text end
  end
  return table.concat(parts, "; ")
end

local function in_shop_scope(state_name)
  if state_name == "SHOP" then return true end
  local ok, StateKinds = pcall(require, "core.state_kinds")
  return ok and StateKinds.is_pack_state(state_name)
    and G and G.NEURO and G.NEURO.shop_pack_interrupt == true
end

local function hand_history_scope(state_name)
  if state_name == "SELECTING_HAND" or state_name == "SHOP" or state_name == "BLIND_SELECT" then
    return true
  end
  local ok, StateKinds = pcall(require, "core.state_kinds")
  return ok and StateKinds.is_pack_state(state_name)
end

local function hand_history_text(journal)
  local events = type(journal.hand_outcomes) == "table" and journal.hand_outcomes or {}
  if #events == 0 then return nil end
  local first = math.max(1, #events - MAX_RENDERED_HAND_OUTCOMES + 1)
  local parts = {}
  for i = first, #events do
    local event = events[i]
    parts[#parts + 1] = string.format("%s lv.%d scored %s", event.hand_type,
      event.hand_level, Utils.fmt_num(event.chips_delta))
  end
  return "Recent actual hand results (history, not forecasts): " .. table.concat(parts, "; ") .. "."
end

function M.render(state_name, delivered_through, board)
  local journal = read_store()
  if not journal then return nil, tonumber(delivered_through) or 0 end
  local cursor = tonumber(delivered_through) or 0
  local undelivered, current = {}, {}
  local through = cursor
  local epoch = tonumber(G and G.NEURO and G.NEURO.shop_visit_epoch) or 0
  local shop_scope = in_shop_scope(state_name)
  for _, event in ipairs(journal.ordered) do
    if event.sequence > cursor then
      if not (shop_scope and event.shop_visit_epoch == epoch) then
        undelivered[#undelivered + 1] = event
      end
      if event.sequence > through then through = event.sequence end
    end
    if shop_scope and event.shop_visit_epoch == epoch then current[#current + 1] = event end
  end
  local lines = {}
  if #undelivered > 0 then
    lines[#lines + 1] = "Applied since the last delivered decision: " .. tail_text(undelivered) .. "."
  end
  if #current > 0 then
    local suffix = ""
    if type(board) == "table" then
      if type(board.dollars) == "number" then suffix = suffix .. "; current money " .. Utils.money(board.dollars) end
      if type(board.joker_slots) == "table" then
        suffix = suffix .. string.format("; Joker slots %d/%d", board.joker_slots.count or 0,
          board.joker_slots.limit or 0)
      end
    end
    lines[#lines + 1] = "This shop visit: " .. tail_text(current) .. suffix .. "."
  end
  if hand_history_scope(state_name) then
    local history = hand_history_text(journal)
    if history then lines[#lines + 1] = history end
  end
  if #lines == 0 then return nil, through end
  return "Recent verified history:\n" .. table.concat(lines, "\n"), through
end

function M.prune_delivered(candidate)
  local journal = read_store()
  local delivery = candidate and candidate.journal
  if not (journal and type(delivery) == "table") then return end
  local through = tonumber(delivery.through_sequence) or 0
  local delivered_epoch = tonumber(delivery.shop_visit_epoch)
  if not delivered_epoch then return end
  local kept = {}
  for _, event in ipairs(journal.ordered) do
    if not (event.sequence <= through and event.shop_visit_epoch < delivered_epoch) then
      kept[#kept + 1] = event
    end
  end
  journal.ordered = kept
end

M.MAX_PUBLIC_LABEL_BYTES = MAX_PUBLIC_LABEL_BYTES
M.MAX_RENDERED_EVENTS = MAX_RENDERED_EVENTS
M.MAX_HAND_OUTCOMES = MAX_HAND_OUTCOMES
M.MAX_RENDERED_HAND_OUTCOMES = MAX_RENDERED_HAND_OUTCOMES
if rawget(_G, "NEURO_TEST") then
  M._test = {
    validate_body = validate_body,
    validate_hand_outcome = validate_hand_outcome,
    public_label = public_label,
  }
end

return M
