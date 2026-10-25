local M = {}

local Utils = require("util.utils")
local GameplayJournal = require("core.gameplay_journal")
local PublicCard = require("facts.public_card_identity")
local DisplayNames = require("facts.display_names")
local DestructionLog = require("core.destruction_log")

local function tally(area, names)
  local out = {}
  local cards = area and area.cards
  if type(cards) ~= "table" then return out end
  local area_name = area == (G and G.jokers) and "jokers" or "consumables"
  for index, c in ipairs(cards) do
    local key = PublicCard.multiset_key(c, area_name, index)
    out[key] = (out[key] or 0) + 1
    if names[key] == nil then names[key] = PublicCard.label(c, area_name, index) end
  end
  return out
end

local function playing_cards()
  local out = {}
  if type(G.playing_cards) ~= "table" then return out end
  for _, card in ipairs(G.playing_cards) do
    if type(card) == "table" and card.sort_id ~= nil and Utils.is_playing_card(card) then
      local shown = (card.area == G.hand or card.area == G.play) and PublicCard.is_public(card)
      -- The deck view exposes pile cards except for one dealt face-down card.
      local piled = (card.area == G.deck or card.area == G.discard)
        and not (type(card.ability) == "table" and card.ability.wheel_flipped)
      local ok_l, face = pcall(DestructionLog.card_face, card)
      if (shown or piled) and ok_l and type(face) == "string" then
        out[tostring(card.sort_id)] = { face = face, shown = shown }
      end
    end
  end
  return out
end

local function capture()
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
      voucher_names[key] = DisplayNames.center(key, "Voucher")
    end
  end
  local hands = {}
  for key, hand in pairs(G.GAME.hands or {}) do
    if type(hand) == "table" and hand.visible ~= false then
      hands[key] = { level = tonumber(hand.level) or 1 }
    end
  end
  local joker_slots, consumable_slots
  local CardUtil = require("facts.card_util")
  local ok_j, js = pcall(CardUtil.joker_slot_status)
  if ok_j and type(js) == "table" then
    joker_slots = { count = tonumber(js.count) or 0, limit = tonumber(js.limit) or 0 }
  end
  local ok_c, cs = pcall(CardUtil.consumable_slot_status)
  if ok_c and type(cs) == "table" then
    consumable_slots = { count = tonumber(cs.count) or 0, limit = tonumber(cs.limit) or 0 }
  end
  return {
    dollars = tonumber(G.GAME.dollars) or 0,
    deck = (type(G.playing_cards) == "table") and #G.playing_cards or nil,
    cards = playing_cards(),
    jokers = tally(G.jokers, names),
    joker_instances = joker_instances,
    consumables = tally(G.consumeables, names),
    names = names,
    vouchers = vouchers,
    voucher_names = voucher_names,
    hands = hands,
    joker_slots = joker_slots,
    consumable_slots = consumable_slots,
    destroyed_through = DestructionLog.cursor(),
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

local MAX_CARD_CHANGES = 8

local function card_changes(prev, cur, out)
  local before, after = prev.cards or {}, cur.cards or {}
  local ids = {}
  for id, now in pairs(after) do
    local was = before[id]
    if type(was) == "table" and type(now) == "table" and was.shown and was.face ~= now.face then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids, function(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb and na ~= nb then return na < nb end
    return a < b
  end)
  for i, id in ipairs(ids) do
    if i > MAX_CARD_CHANGES then
      out[#out + 1] = tostring(#ids - MAX_CARD_CHANGES) .. " more playing card(s) changed"
      break
    end
    out[#out + 1] = before[id].face .. " to " .. after[id].face
  end
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
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

local function sorted_keys(a, b)
  local keys, ordered = {}, {}
  for k in pairs(a) do keys[k] = true end
  for k in pairs(b) do keys[k] = true end
  for k in pairs(keys) do ordered[#ordered + 1] = k end
  table.sort(ordered)
  return ordered
end

local function collection_change(prev, cur, key_field, gained_word, lost_word, out)
  local a, b = prev[key_field] or {}, cur[key_field] or {}
  local gained, lost = {}, {}
  for _, k in ipairs(sorted_keys(a, b)) do
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

local function changes(prev, cur)
  if not (type(prev) == "table" and type(cur) == "table") then return nil end
  local out = {}

  local dd = (cur.dollars or 0) - (prev.dollars or 0)
  if dd ~= 0 then
    out[#out + 1] = "money " .. Utils.money(prev.dollars or 0) .. " to " .. Utils.money(cur.dollars or 0)
      .. " (" .. (dd > 0 and "+" or "") .. Utils.money(dd) .. ")"
  end

  collection_change(prev, cur, "jokers", "jokers gained", "jokers lost", out)
  sell_value_changes(prev, cur, out)
  collection_change(prev, cur, "consumables", "consumables gained", "consumables removed", out)
  collection_change(prev, cur, "vouchers", "vouchers gained", "vouchers lost", out)

  for _, key in ipairs(sorted_keys(prev.hands or {}, cur.hands or {})) do
    local before, after = prev.hands and prev.hands[key], cur.hands and cur.hands[key]
    if type(before) == "table" and type(after) == "table" and before.level ~= after.level then
      out[#out + 1] = string.format("%s level %d to %d", tostring(key),
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

  card_changes(prev, cur, out)

  local destroyed = DestructionLog.between(prev.destroyed_through, cur.destroyed_through)
  for _, text in ipairs(destroyed or {}) do out[#out + 1] = text end

  if prev.deck and cur.deck and prev.deck ~= cur.deck then
    out[#out + 1] = "deck " .. tostring(prev.deck) .. " to " .. tostring(cur.deck) .. " cards"
  end

  if #out == 0 then return nil end
  return table.concat(out, "; ")
end

local function labelled(text)
  return text and ("Since your last decision: " .. text .. ".") or nil
end

local function render(prev, cur) return labelled(changes(prev, cur)) end

local function answered()
  return tonumber(G.NEURO.answered_decisions) or 0
end

local function replayed(committed)
  if committed.answered == answered() or not committed.changes then return committed.rendered_delta end
  return "Since your last decision: nothing changed. Most recent change, from before it: "
    .. committed.changes .. "."
end

local function combine(delta, journal)
  if delta and delta ~= "" and journal and journal ~= "" then return delta .. "\n" .. journal end
  return (delta and delta ~= "") and delta or journal
end

local minted = 0

function M.for_force(state_name)
  local n = G and G.NEURO
  if not n then return nil, nil end
  local committed = n.decision_snapshot
  local serial = tonumber(n.decision_serial) or 0
  local board = capture()
  if not board then return nil, nil end
  local cursor = type(committed) == "table" and type(committed.journal) == "table"
    and tonumber(committed.journal.through_sequence) or 0
  local changed = (type(committed) == "table") and changes(committed.board, board) or nil
  local text = labelled(changed)
  local journal_text, through = GameplayJournal.render(state_name, cursor, board)
  if type(committed) == "table" and committed.window == serial and through == cursor
      and same(committed.board, board) then
    local journal = type(committed.journal) == "table" and committed.journal.rendered_text or nil
    return combine(replayed(committed), journal), nil
  end
  minted = minted + 1
  return combine(text, journal_text), {
    window = serial,
    mint = minted,
    run_generation = tonumber(n.run_generation) or 0,
    board = board,
    rendered_delta = text,
    changes = changed,
    answered = answered(),
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
    local cw, nw = tonumber(committed.window) or 0, tonumber(candidate.window) or 0
    if cw > nw or (cw == nw and (tonumber(committed.mint) or 0) >= (tonumber(candidate.mint) or 0)) then
      return
    end
    local old_cursor = type(committed.journal) == "table"
      and tonumber(committed.journal.through_sequence) or 0
    local new_cursor = type(candidate.journal) == "table"
      and tonumber(candidate.journal.through_sequence) or 0
    if new_cursor < old_cursor then return end
  end
  G.NEURO.decision_snapshot = candidate
  pcall(GameplayJournal.prune_delivered, candidate)
end

if _G.NEURO_TEST then
  M.capture = capture
  M.render = render
end

return M
