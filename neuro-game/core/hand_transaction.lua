-- Hand confirmations have one terminal lifecycle.
local M = {}

local TERMINAL = {
  settled = true, cancelled = true, invalidated = true, superseded = true,
}

local function neuro()
  return G and G.NEURO
end

local function number(value, fallback)
  local n = tonumber(value)
  return n ~= nil and n or fallback
end

local function decision()
  local n = neuro()
  if not n then return nil end
  n.hand_decision = type(n.hand_decision) == "table" and n.hand_decision or {}
  local d = n.hand_decision
  d.epoch = number(d.epoch, 0)
  d.context_revision = number(d.context_revision, number(n.hand_context_revision, 0))
  n.hand_context_revision = d.context_revision
  return d
end

local function current()
  local n = neuro()
  local tx = n and n.hand_transaction
  return type(tx) == "table" and tx or nil
end

local function clear_if(tx)
  local n = neuro()
  if n and n.hand_transaction == tx then
    n.hand_transaction = nil
    n.hand_last_transaction = tx
  end
  pcall(function()
    require("core.confirmation_evidence").clear(tx.id)
  end)
  if tx.phase ~= "settled" then
    pcall(function()
      require("core.plan_transaction").release_hand_proposal(tx.id)
    end)
  end
end

local function copy_list(list)
  local out = {}
  for i, value in ipairs(list or {}) do out[i] = value end
  return out
end

local function prompt_reason(value)
  if type(value) ~= "string" then return nil end
  local out = value:gsub("[%c%s]+", " "):match("^%s*(.-)%s*$")
  if out == "" then return nil end
  if #out > 600 then out = out:sub(1, 597) .. "..." end
  return out
end

local function value_key(value, depth, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
    return tostring(value)
  end
  if kind ~= "table" then return kind end
  depth = depth or 0
  if depth >= 3 then return "{...}" end
  seen = seen or {}
  if seen[value] then return "<cycle>" end
  seen[value] = true
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. value_key(value[key], depth + 1, seen)
  end
  seen[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

local function card_key(card)
  if type(card) ~= "table" then return "?" end
  local base, center, ability = card.base or {}, card.config and card.config.center or {}, card.ability or {}
  local edition = card.edition
  local edition_key = type(edition) == "table"
    and table.concat({ tostring(edition.foil), tostring(edition.holo), tostring(edition.polychrome), tostring(edition.negative) }, ",")
    or tostring(edition)
  return table.concat({
    tostring(card.sort_id), tostring(base.value), tostring(base.suit), tostring(center.key),
    tostring(card.enhancement), tostring(card.seal), edition_key, tostring(card.debuff),
    tostring(ability.name), tostring(ability.effect), value_key(ability.extra),
  }, "/")
end

local function context_key()
  local n = neuro()
  if not n then return nil end
  local game, round = G and G.GAME or {}, G and G.GAME and G.GAME.current_round or {}
  local parts = {
    tostring(n.state), tostring(n.state_enter_serial), tostring(n.decision_serial),
    tostring(round.hands_left), tostring(round.discards_left), tostring(round.discards_used),
    tostring(game.chips), tostring(game.dollars),
  }
  local hand = G and G.hand and G.hand.cards or {}
  for i, card in ipairs(hand) do parts[#parts + 1] = "h" .. tostring(i) .. ":" .. card_key(card) end
  local jokers = G and G.jokers and G.jokers.cards or {}
  for i, card in ipairs(jokers) do parts[#parts + 1] = "j" .. tostring(i) .. ":" .. card_key(card) end
  local blind = game.blind or {}
  parts[#parts + 1] = table.concat({
    "b", tostring(blind.name), tostring(blind.disabled), tostring(blind.block_play), value_key(blind.debuff),
    tostring(blind.config and blind.config.blind and blind.config.blind.key),
  }, ":")
  local levels = game.hands or {}
  local level_names = {}
  for name in pairs(levels) do level_names[#level_names + 1] = tostring(name) end
  table.sort(level_names)
  for _, name in ipairs(level_names) do
    local h = levels[name] or {}
    parts[#parts + 1] = table.concat({ "l", name, tostring(h.level), tostring(h.chips), tostring(h.mult), tostring(h.played) }, ":")
  end
  return table.concat(parts, "|")
end

local function generation()
  return number(neuro() and neuro().run_generation, 0)
end

function M.current()
  return current()
end

function M.phase()
  local tx = current()
  return tx and tx.phase or "idle"
end

function M.mode()
  local phase = M.phase()
  if phase == "publishing" then return "publishing" end
  if phase == "ready" or phase == "committing" then return "resolution" end
  return "proposal"
end

function M.context_revision()
  M.observe_context()
  local d = decision()
  return d and number(d.context_revision, 0) or 0
end

function M.observe_context()
  local n = neuro()
  local d = decision()
  if not (n and d) then return false end
  local key = context_key()
  if n.hand_context_key == nil then
    n.hand_context_key = key
    return false
  end
  if key == n.hand_context_key then return false end
  n.hand_context_key = key
  d.context_revision = d.context_revision + 1
  n.hand_context_revision = d.context_revision
  d.final_play_revision = nil
  d.last_decline = nil
  local tx = current()
  if tx and not TERMINAL[tx.phase] then M.invalidate(tx, "context_changed") end
  return true
end

function M.transaction_id()
  local tx = current()
  return tx and tx.id or nil
end

function M.snapshot(tx)
  tx = tx or current()
  if not tx then return nil end
  return {
    transaction_id = tx.id,
    phase = tx.phase,
    signature = tx.signature,
    content = tx.content,
    indices = copy_list(tx.indices),
    decision_serial = tx.decision_serial,
    state_enter_serial = tx.state_enter_serial,
    run_generation = tx.run_generation,
    context_revision = tx.context_revision,
    hand_type = tx.hand_type,
    dominant_alt = tx.dominant_alt,
  }
end

function M.snapshot_is_current(snapshot)
  local n = neuro()
  if type(snapshot) ~= "table" or not n then return false end
  if tonumber(snapshot.run_generation) ~= generation()
      or tonumber(snapshot.state_enter_serial) ~= number(n.state_enter_serial, 0)
      or tonumber(snapshot.context_revision) ~= M.context_revision() then
    return false
  end
  local tx = current()
  if snapshot.transaction_id == nil then
    return tx == nil and snapshot.phase == "proposal"
  end
  return tx ~= nil and tonumber(snapshot.transaction_id) == tonumber(tx.id)
    and snapshot.phase == tx.phase
end

local function identity_matches(tx, id)
  return type(tx) == "table" and number(id, nil) ~= nil and tx.id == number(id, nil)
end

function M.is_current_id(id)
  return identity_matches(current(), id)
end

function M.fast_valid(tx, expected_revision)
  local n = neuro()
  local d = decision()
  if not (n and d and type(tx) == "table" and current() == tx) then return false end
  if tx.run_generation ~= generation() then return false end
  if tx.state_enter_serial ~= number(n.state_enter_serial, 0) then return false end
  if tx.decision_serial ~= number(n.decision_serial, 0) then return false end
  if tx.context_revision ~= number(expected_revision, d.context_revision) then return false end
  return tx.phase == "ready"
end

function M.create(fields)
  local n = neuro()
  local d = decision()
  if not (n and d and type(fields) == "table") then return nil, "no_neuro" end
  local old = current()
  if old and not TERMINAL[old.phase] then return nil, "active_transaction" end
  local run_gen = generation()
  M.observe_context()
  if n.hand_transaction_id_generation ~= run_gen then
    n.hand_transaction_id_generation = run_gen
    n.hand_transaction_next_id = 0
  end
  n.hand_transaction_next_id = number(n.hand_transaction_next_id, 0) + 1

  local tx = {
    id = n.hand_transaction_next_id,
    kind = "hand",
    phase = "publishing",
    created_at = os.clock(),
    decision_serial = number(n.decision_serial, 0),
    state_enter_serial = number(n.state_enter_serial, 0),
    run_generation = run_gen,
    context_revision = number(fields.context_revision, d.context_revision),
    signature = fields.signature,
    content = fields.content,
    indices = copy_list(fields.indices),
    hand_type = fields.hand_type,
    dominant_alt = fields.dominant_alt,
    proposal_action_names = copy_list(fields.proposal_action_names),
  }
  n.hand_transaction = tx
  return tx
end

function M.transition(tx, next_phase)
  if not (type(tx) == "table" and type(next_phase) == "string") then return false end
  if current() ~= tx then return false end
  if TERMINAL[tx.phase] then return false end
  local allowed = {
    publishing = { ready = true, invalidated = true, superseded = true },
    ready = { committing = true, cancelled = true, invalidated = true, superseded = true },
    committing = { settled = true, invalidated = true },
  }
  if not (allowed[tx.phase] and allowed[tx.phase][next_phase]) then return false end
  tx.phase = next_phase
  if TERMINAL[next_phase] then clear_if(tx) end
  return true
end

function M.promote_ready(tx)
  if not (type(tx) == "table" and current() == tx and tx.phase == "publishing") then return false end
  local n = neuro()
  local d = decision()
  if not (n and d) then return false end
  if tx.run_generation ~= generation()
      or tx.state_enter_serial ~= number(n.state_enter_serial, 0)
      or tx.decision_serial ~= number(n.decision_serial, 0)
      or tx.context_revision ~= d.context_revision then
    return M.invalidate(tx, "stale_before_ready")
  end
  return M.transition(tx, "ready")
end

function M.begin_commit(tx, expected_id, expected_revision, expected_generation)
  if not (type(tx) == "table" and current() == tx and tx.phase == "ready") then
    return false, "not_ready"
  end
  M.observe_context()
  if expected_id == nil or not identity_matches(tx, expected_id) then return false, "transaction_id" end
  if expected_generation == nil or tx.run_generation ~= number(expected_generation, nil) then
    return false, "run_generation"
  end
  if not M.fast_valid(tx, expected_revision) then return false, "stale" end
  if not M.transition(tx, "committing") then return false, "transition" end
  return true
end

-- Recheck the transaction at the execution boundary.
function M.commit_is_current(tx)
  local n = neuro()
  local d = decision()
  if not (n and d and type(tx) == "table") then return false, "no_neuro" end
  M.observe_context()
  if current() ~= tx then return false, "stale_transaction" end
  if tx.phase ~= "committing" then return false, "not_committing" end
  if tx.run_generation ~= generation() then return false, "run_generation" end
  if tx.state_enter_serial ~= number(n.state_enter_serial, 0) then return false, "state" end
  if tx.decision_serial ~= number(n.decision_serial, 0) then return false, "decision" end
  if tx.context_revision ~= number(d.context_revision, 0) then return false, "context" end
  return true
end

function M.rollback_commit(tx)
  local n = neuro()
  local d = decision()
  if not (n and d and type(tx) == "table" and current() == tx
      and tx.phase == "committing") then return false end
  M.observe_context()
  if current() ~= tx or tx.phase ~= "committing"
      or tx.run_generation ~= generation()
      or tx.state_enter_serial ~= number(n.state_enter_serial, 0)
      or tx.decision_serial ~= number(n.decision_serial, 0)
      or tx.context_revision ~= number(d.context_revision, 0) then
    if current() == tx then M.invalidate(tx, "stale_commit_rollback") end
    return false
  end
  tx.phase = "ready"
  return true
end

function M.settle(tx)
  return M.transition(tx, "settled")
end

function M.cancel(tx, decline)
  if not (type(tx) == "table" and current() == tx and tx.phase == "ready") then return false end
  local d = decision()
  if not d then return false end
  if not M.transition(tx, "cancelled") then return false end
  d.epoch = number(d.epoch, 0) + 1
  d.final_play_revision = d.context_revision
  decline = type(decline) == "table" and decline or {}
  d.last_decline = {
    context_revision = d.context_revision,
    transaction_id = tx.id,
    indices = copy_list(tx.indices),
    hand_type = tx.hand_type,
    dominant_alt = copy_list(tx.dominant_alt),
    reason = type(decline.reason) == "string" and decline.reason or nil,
  }
  return true
end

function M.invalidate(tx, _reason)
  tx = tx or current()
  if not (type(tx) == "table" and current() == tx) then return false end
  if TERMINAL[tx.phase] then return false end
  return M.transition(tx, "invalidated")
end

function M.supersede(tx)
  tx = tx or current()
  if not (type(tx) == "table" and current() == tx) then return false end
  if TERMINAL[tx.phase] then return false end
  return M.transition(tx, "superseded")
end

function M.observe_context_changed()
  local n = neuro()
  local d = decision()
  if not (n and d) then return false end

  d.context_revision = number(d.context_revision, 0) + 1
  n.hand_context_revision = d.context_revision
  d.final_play_revision = nil
  d.last_decline = nil
  n.hand_context_key = context_key()

  local tx = current()
  if tx and not TERMINAL[tx.phase] then M.invalidate(tx, "context_changed") end
  return true
end

function M.final_play_required()
  local d = decision()
  return d ~= nil and d.final_play_revision == d.context_revision
end

function M.decline_context()
  M.observe_context()
  local d = decision()
  local rec = d and d.last_decline
  if type(rec) ~= "table" or rec.context_revision ~= d.context_revision
      or d.final_play_revision ~= d.context_revision then
    return nil
  end
  return {
    context_revision = rec.context_revision,
    transaction_id = rec.transaction_id,
    indices = copy_list(rec.indices),
    hand_type = rec.hand_type,
    dominant_alt = copy_list(rec.dominant_alt),
    reason = prompt_reason(rec.reason),
  }
end

function M.blocks_mutating_actions()
  local phase = M.phase()
  return phase == "publishing" or phase == "ready" or phase == "committing"
end

local HAND_MUTATORS = {
  play_hand = true, discard_hand = true, use_consumable = true,
  use_directional_consumable = true, choose_pack_card = true,
  choose_directional_pack_card = true,
  sell_card = true, set_joker_order = true, record_joker_roles = true, record_plan = true,
  buy_from_shop = true, reroll_shop = true, leave_shop = true,
  select_blind = true, skip_blind = true, skip_pack = true, cash_out = true,
}

function M.is_hand_decision_mutator(name)
  return HAND_MUTATORS[name] == true
end

function M.stale_mutator(name)
  return M.blocks_mutating_actions() and M.is_hand_decision_mutator(name)
end

-- Invalidate open transactions when confirmation is disabled.
function M.confirmation_mode_changed(enabled)
  local n = neuro()
  if not n then return false end
  local changed = false
  if enabled ~= true then
    local tx = current()
    if tx and (tx.phase == "publishing" or tx.phase == "ready") then
      changed = M.invalidate(tx, "confirmation_disabled") or changed
    elseif not tx then
      pcall(function() require("core.confirmation_evidence").clear() end)
    end
    local d = decision()
    if d then
      d.final_play_revision = nil
      d.last_decline = nil
    end
  end
  pcall(function() require("core.force_state").invalidate("confirmation_mode_changed") end)
  pcall(function() require("core.neuro_lifecycle").mark_force_dirty() end)
  return changed
end

function M.reset()
  local n = neuro()
  if not n then return end
  n.hand_transaction = nil
  n.hand_last_transaction = nil
  n.hand_decision = nil
  n.hand_context_revision = nil
  n.hand_context_key = nil
end

if rawget(_G, "NEURO_TEST") then
  M._test = { terminal = TERMINAL }
end

return M
