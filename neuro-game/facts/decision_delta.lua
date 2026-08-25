local M = {}

local Utils = require("util.utils")
local GameplayJournal = require("core.gameplay_journal")
local PublicCard = require("facts.public_card_identity")

local function tally(area, names)
  local out = {}
  local cards = area and area.cards
  if type(cards) ~= "table" then return out end
  local area_name = area == (G and G.jokers) and "jokers" or "consumeables"
  for index, c in ipairs(cards) do
    local key = PublicCard.multiset_key(c, area_name, index)
    out[key] = (out[key] or 0) + 1
    if names[key] == nil then names[key] = PublicCard.label(c, area_name, index) end
  end
  return out
end

-- Counts per centre key, not a set: selling one of two identical jokers is a real change and a set
-- difference cannot see it. This writes no game state and no snapshot, but it is not free of side
-- effects: safe_name_or goes through the UI text cache (util/utils.lua:498).
function M.capture()
  if not (G and G.GAME) then return nil end
  local names = {}
  local joker_instances = {}
  local joker_cards = G.jokers and G.jokers.cards
  if type(joker_cards) == "table" then
    for index, card in ipairs(joker_cards) do
      if type(card) == "table" and card.sort_id ~= nil then
        joker_instances[tostring(card.sort_id)] = {
          name = PublicCard.label(card, "jokers", index), index = index, sell = tonumber(card.sell_cost),
        }
      end
    end
  end
  local vouchers, voucher_names = {}, {}
  for key, owned in pairs(G.GAME.used_vouchers or {}) do
    if owned then
      vouchers[key] = 1
      local center = G.P_CENTERS and G.P_CENTERS[key]
      voucher_names[key] = center and center.loc_txt and center.loc_txt.name or key
    end
  end
  local hands = {}
  for key, hand in pairs(G.GAME.hands or {}) do
    if type(hand) == "table" and hand.visible ~= false then
      hands[key] = { level = tonumber(hand.level) or 1, name = tostring(hand.name or key) }
    end
  end
  local joker_slots, consumable_slots
  local ok_slots, CardUtil = pcall(require, "facts.card_util")
  if ok_slots then
    local ok_j, js = pcall(CardUtil.joker_slot_status)
    if ok_j and type(js) == "table" then
      joker_slots = { count = tonumber(js.count) or 0, limit = tonumber(js.limit) or 0 }
    end
    local ok_c, cs = pcall(CardUtil.consumable_slot_status)
    if ok_c and type(cs) == "table" then
      consumable_slots = { count = tonumber(cs.count) or 0, limit = tonumber(cs.limit) or 0 }
    end
  end
  return {
    dollars = tonumber(G.GAME.dollars) or 0,
    deck = (type(G.playing_cards) == "table") and #G.playing_cards or nil,
    jokers = tally(G.jokers, names),
    joker_instances = joker_instances,
    consumables = tally(G.consumeables, names),
    names = names,
    vouchers = vouchers,
    voucher_names = voucher_names,
    hands = hands,
    joker_slots = joker_slots,
    consumable_slots = consumable_slots,
  }
end

local function sell_value_changes(prev, cur, out)
  local before, after = prev.joker_instances or {}, cur.joker_instances or {}
  local changed, counts = {}, {}
  for _, rec in pairs(after) do
    local name = tostring(rec.name or "Joker")
    counts[name] = (counts[name] or 0) + 1
  end
  for id, now in pairs(after) do
    local was = before[id]
    if type(was) == "table" and type(was.sell) == "number" and type(now.sell) == "number"
      and was.sell ~= now.sell then
      changed[#changed + 1] = { id = id, was = was, now = now }
    end
  end
  table.sort(changed, function(a, b)
    local ai, bi = tonumber(a.now.index) or math.huge, tonumber(b.now.index) or math.huge
    return ai == bi and a.id < b.id or ai < bi
  end)
  for _, item in ipairs(changed) do
    local name = tostring(item.now.name or item.was.name or "Joker")
    if (counts[name] or 0) > 1 then name = name .. " (#" .. tostring(item.now.index or "?") .. ")" end
    out[#out + 1] = "joker sell value " .. name .. " " .. Utils.money(item.was.sell)
      .. " to " .. Utils.money(item.now.sell)
  end
end

local function name_of(prev, cur, key)
  return (cur.names and cur.names[key]) or (prev.names and prev.names[key])
    or (cur.voucher_names and cur.voucher_names[key]) or (prev.voucher_names and prev.voucher_names[key])
    or key
end

local function phrase(list)
  local parts = {}
  for _, e in ipairs(list) do
    parts[#parts + 1] = (e.n > 1) and (e.name .. " x" .. e.n) or e.name
  end
  return table.concat(parts, ", ")
end

local function collection_change(prev, cur, key_field, gained_word, lost_word, out)
  local a, b = prev[key_field] or {}, cur[key_field] or {}
  local keys = {}
  for k in pairs(a) do keys[k] = true end
  for k in pairs(b) do keys[k] = true end
  local gained, lost = {}, {}
  local ordered = {}
  for k in pairs(keys) do ordered[#ordered + 1] = k end
  table.sort(ordered)
  for _, k in ipairs(ordered) do
    local d = (b[k] or 0) - (a[k] or 0)
    if d > 0 then
      gained[#gained + 1] = { name = name_of(prev, cur, k), n = d }
    elseif d < 0 then
      lost[#lost + 1] = { name = name_of(prev, cur, k), n = -d }
    end
  end
  if #gained > 0 then out[#out + 1] = gained_word .. " " .. phrase(gained) end
  if #lost > 0 then out[#out + 1] = lost_word .. " " .. phrase(lost) end
end

function M.render(prev, cur)
  if not (type(prev) == "table" and type(cur) == "table") then return nil end
  local out = {}

  local dd = (cur.dollars or 0) - (prev.dollars or 0)
  if dd ~= 0 then
    out[#out + 1] = "money " .. Utils.money(prev.dollars or 0) .. " to " .. Utils.money(cur.dollars or 0)
      .. " (" .. (dd > 0 and "+" or "") .. Utils.money_signed(dd) .. ")"
  end

  collection_change(prev, cur, "jokers", "jokers gained", "jokers lost", out)
  sell_value_changes(prev, cur, out)
  collection_change(prev, cur, "consumables", "consumables gained", "consumables removed", out)
  collection_change(prev, cur, "vouchers", "vouchers gained", "vouchers lost", out)

  local hand_keys = {}
  for key in pairs(prev.hands or {}) do hand_keys[key] = true end
  for key in pairs(cur.hands or {}) do hand_keys[key] = true end
  local ordered_hands = {}
  for key in pairs(hand_keys) do ordered_hands[#ordered_hands + 1] = key end
  table.sort(ordered_hands)
  for _, key in ipairs(ordered_hands) do
    local before, after = prev.hands and prev.hands[key], cur.hands and cur.hands[key]
    if type(before) == "table" and type(after) == "table" and before.level ~= after.level then
      out[#out + 1] = string.format("%s level %d to %d", tostring(after.name or before.name or key),
        before.level or 0, after.level or 0)
    end
  end

  local function slot_change(field, label)
    local before, after = prev[field], cur[field]
    if type(before) == "table" and type(after) == "table" and before.limit ~= after.limit then
      out[#out + 1] = string.format("%s capacity %d to %d", label, before.limit or 0, after.limit or 0)
    end
  end
  slot_change("joker_slots", "Joker slots")
  slot_change("consumable_slots", "consumable slots")

  if prev.deck and cur.deck and prev.deck ~= cur.deck then
    out[#out + 1] = "deck " .. tostring(prev.deck) .. " to " .. tostring(cur.deck) .. " cards"
  end

  if #out == 0 then return nil end
  return "Since your last decision: " .. table.concat(out, "; ") .. "."
end

local function combine(delta, journal)
  if delta and delta ~= "" and journal and journal ~= "" then return delta .. "\n" .. journal end
  return (delta and delta ~= "") and delta or journal
end

function M.for_force(state_name)
  local n = G and G.NEURO
  if not n then return nil, nil end
  local committed = n.decision_snapshot
  local serial = tonumber(n.decision_serial) or 0
  if type(committed) == "table" and committed.window == serial then
    local journal = type(committed.journal) == "table" and committed.journal.rendered_text or nil
    return combine(committed.rendered_delta, journal), nil
  end
  local board = M.capture()
  if not board then return nil, nil end
  local text = (type(committed) == "table") and M.render(committed.board, board) or nil
  local cursor = type(committed) == "table" and type(committed.journal) == "table"
    and tonumber(committed.journal.through_sequence) or 0
  local journal_text, through = GameplayJournal.render(state_name, cursor, board)
  return combine(text, journal_text), {
    window = serial,
    run_generation = tonumber(n.run_generation) or 0,
    board = board,
    rendered_delta = text,
    journal = {
      through_sequence = through,
      rendered_text = journal_text,
      shop_visit_epoch = tonumber(n.shop_visit_epoch) or 0,
    },
  }
end

function M.commit(candidate)
  if not (type(candidate) == "table" and G and G.NEURO) then return end
  if tonumber(candidate.run_generation) ~= (tonumber(G.NEURO.run_generation) or 0) then return end
  local committed = G.NEURO.decision_snapshot
  if type(committed) == "table" then
    if (tonumber(committed.window) or 0) >= (tonumber(candidate.window) or 0) then return end
    local old_cursor = type(committed.journal) == "table"
      and tonumber(committed.journal.through_sequence) or 0
    local new_cursor = type(candidate.journal) == "table"
      and tonumber(candidate.journal.through_sequence) or 0
    if new_cursor < old_cursor then return end
  end
  G.NEURO.decision_snapshot = candidate
  pcall(GameplayJournal.prune_delivered, candidate)
end

return M
