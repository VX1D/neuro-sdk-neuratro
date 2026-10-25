local M = {}

local Utils = require("util.utils")
local Metrics = require("util.metrics")
local Tx = require("core.bridge").tx
local ActionResult = require("core.action_result")
local CardUtil = require("facts.card_util")
local GameplayJournal = require("core.gameplay_journal")
local Gate = require("core.gate")
local PlanTransaction = require("core.plan_transaction")
local ContextDelivery = require("core.context_delivery")
local Staging = require("core.staging")
local Window = require("core.window")
local Lifecycle = require("core.neuro_lifecycle")

local job

local function validate() return require("core.validate") end

local function state_name()
  local ok, name = pcall(require("core.state").get_state_name)
  if ok then return name end
  return G and G.NEURO and G.NEURO.state
end

local function selected_blind_key(data)
  local kind = data.blind == "small" and "Small" or data.blind == "big" and "Big" or "Boss"
  return kind, G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
    and G.GAME.round_resets.blind_choices[kind]
end

local function requested_seed(data)
  local raw = data.seed
  if raw == nil or tostring(raw) == "" then
    if G and G.CLIPBOARD and tostring(G.CLIPBOARD) ~= "" then
      raw = G.CLIPBOARD
    elseif love and love.system and love.system.getClipboardText then
      local ok, value = pcall(love.system.getClipboardText)
      if ok then raw = value end
    end
  end
  if raw == nil then return nil end
  return require("core.filtered").sanitize(tostring(raw), true):upper():gsub("[^A-Z0-9]", ""):sub(1, 8)
end

local function snapshot(name, data)
  local n = G and G.NEURO or {}
  local game = G and G.GAME or {}
  local rr = game.round_resets or {}
  local snap = {
    state = state_name(),
    generation = tonumber(n.run_generation) or 0,
    overlay = G and G.OVERLAY_MENU,
    pack = CardUtil.pack_area(),
    pack_choices = tonumber(game.pack_choices) or 0,
    blind_on_deck = game.blind_on_deck,
    skips = tonumber(game.skips) or 0,
    boss_choice = rr.blind_choices and rr.blind_choices.Boss,
    rerolls = game.round_scores and game.round_scores.times_rerolled
      and tonumber(game.round_scores.times_rerolled.amt) or 0,
    plan_revision = tonumber(n.plan_revision) or 0,
    seeded = (require("facts.deck_facts").run_seed()),
  }
  if name == "set_joker_order" then snap.card = G and G.jokers and G.jokers.cards[data.from_index] end
  if name == "record_joker_roles" then
    snap.joker_roles = {}
    for _, entry in ipairs(data.intents or {}) do
      snap.joker_roles[#snap.joker_roles + 1] = {
        index = entry.index,
        card = G and G.jokers and G.jokers.cards and G.jokers.cards[entry.index],
      }
    end
  end
  if name == "select_blind" then snap.blind_kind, snap.blind_key = selected_blind_key(data) end
  if name == "paste_seed" then snap.requested_seed = requested_seed(data) end
  return snap
end

local function exact_goal(name, data, before)
  local n = G and G.NEURO or {}
  local game = G and G.GAME or {}
  local rr = game.round_resets or {}
  if name == "choose_persona" then return n.persona == data.persona end
  if name == "select_stake" then
    local profile = G and G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    return G and G.viewed_stake == data.to_key
      or profile and profile.MEMORY and profile.MEMORY.stake == data.to_key
  end
  if name == "select_deck" then return n.selected_back_key == data.back and n.deck_chosen == true end
  if name == "select_challenge" then
    local tab = G and G.challenge_tab
    return tab ~= nil and (tostring(tab.id) == tostring(data.id) or tostring(tab.name) == tostring(data.id)
      or type(data.id) == "number" and G.CHALLENGES and tab == G.CHALLENGES[data.id])
  end
  if name == "paste_seed" then
    return before.requested_seed ~= nil and before.requested_seed ~= ""
      and n.seed_pasted == before.requested_seed
      and select(2, require("facts.deck_facts").run_seed()) == before.requested_seed
  end
  if name == "toggle_seeded_run" then
    return (require("facts.deck_facts").run_seed()) ~= (not not before.seeded)
  end
  if name == "record_plan" then return (tonumber(n.plan_revision) or 0) > before.plan_revision end
  if name == "record_joker_roles" then
    for intent_index, entry in ipairs(data.intents or {}) do
      local card = G and G.jokers and G.jokers.cards and G.jokers.cards[entry.index]
      local before_entry = before.joker_roles and before.joker_roles[intent_index]
      if not before_entry or before_entry.index ~= entry.index or card ~= before_entry.card then
        return false
      end
      local intent = card and n.joker_intents and n.joker_intents[card.sort_id]
      if not intent or intent.tag ~= entry.tag then return false end
      if type(entry.note) == "string" then
        local expected = Utils.normalize_ws(entry.note)
        if expected == "" then expected = nil end
        if intent.note ~= expected then return false end
      end
    end
    return #(data.intents or {}) > 0
  end
  if name == "set_joker_order" then return G and G.jokers and G.jokers.cards[data.to_index] == before.card end
  if name == "exit_overlay_menu" then return G and G.OVERLAY_MENU == nil end
  if name == "open_run_setup" then
    return G and G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU ~= before.overlay
  end
  if name == "select_blind" then
    local states = rr.blind_states or {}
    local live_key = game.blind and game.blind.config and game.blind.config.blind
      and game.blind.config.blind.key
    return rr.blind == before.blind_key or live_key == before.blind_key
      or states[before.blind_kind] == "Current"
        and rr.blind_choices and rr.blind_choices[before.blind_kind] == before.blind_key
  end
  if name == "skip_blind" then
    return game.blind_on_deck ~= before.blind_on_deck or (tonumber(game.skips) or 0) > before.skips
  end
  if name == "reroll_boss" then
    return rr.boss_rerolled == true and rr.blind_choices and rr.blind_choices.Boss ~= before.boss_choice
  end
  if name == "reroll_shop" then
    local count = game.round_scores and game.round_scores.times_rerolled
      and tonumber(game.round_scores.times_rerolled.amt) or 0
    return count > before.rerolls
  end
  if name == "leave_shop" then
    local locked = G and G.CONTROLLER and G.CONTROLLER.locks and G.CONTROLLER.locks.leave_shop
    return G and G.shop == nil and state_name() ~= "SHOP" and not locked
  end
  if name == "cash_out" then return G and G.round_eval == nil and state_name() == "SHOP" end
  if name == "skip_pack" then
    return CardUtil.pack_area() == nil or CardUtil.pack_area() ~= before.pack
      or (tonumber(game.pack_choices) or 0) < before.pack_choices
  end
  if name == "start_run" or name == "start_challenge_run" then
    return (tonumber(n.run_generation) or 0) ~= before.generation
      or (state_name() ~= before.state and not require("core.state_kinds").is_menu_state(state_name()))
  end
  if name == "copy_seed" then
    local seed = game.pseudorandom and game.pseudorandom.seed
    if seed ~= nil and G and G.CLIPBOARD == seed then return true end
    if seed ~= nil and love and love.system and love.system.getClipboardText then
      local ok, value = pcall(love.system.getClipboardText)
      return ok and value == seed
    end
    return false
  end
  return false
end

local KNOWN = {
  buy_from_shop = "native", discard_hand = "native", play_hand = "native", sell_card = "native",
  use_consumable = "native", use_directional_consumable = "native", choose_pack_card = "native",
  choose_directional_pack_card = "native",
  cash_out = "async", exit_overlay_menu = "async", reroll_boss = "async", reroll_shop = "async",
  select_blind = "async", open_run_setup = "async", skip_blind = "async", skip_pack = "async",
  start_challenge_run = "async", start_run = "async", leave_shop = "async",
  select_challenge = "sync", select_deck = "sync", select_stake = "sync", choose_persona = "sync",
  copy_seed = "sync", paste_seed = "sync", record_joker_roles = "sync", set_joker_order = "sync",
  record_plan = "sync", toggle_seeded_run = "sync",
}
local RUN_STARTS = { start_run = true, start_challenge_run = true }

function M.wrap(name, data, exec)
  if type(exec) ~= "function" or not KNOWN[name] then return exec end
  local before = snapshot(name, data)
  return function()
    Utils.begin_text_build()
    local result, refusal = exec()
    if ActionResult.is_receipt(result) or ActionResult.is_outcome(result) then return result end
    if result == nil and refusal ~= nil then
      local reason = type(refusal) == "table" and refusal.message or refusal
      return ActionResult.outcome("failed", tostring(reason), { contract = KNOWN[name], goal = name, refused = true })
    end
    if KNOWN[name] == "native" or (result ~= nil and not ActionResult.is_done(result)) then return result end
    if exact_goal(name, data, before) then
      return ActionResult.outcome("applied", nil, { contract = KNOWN[name] })
    end
    if KNOWN[name] == "sync" then
      return ActionResult.outcome("failed",
        "It did not reach its requested state. Inspect the current screen and choose again.",
        { contract = "sync", goal = name })
    end
    return ActionResult.create({
      id = tostring(data._action_id),
      name = name,
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionResult.now() + (RUN_STARTS[name] and 15 or 6),
      timeout_outcome = "ambiguous",
      allow_generation_change = RUN_STARTS[name] == true,
      debug = { contract = "async", goal = name },
      probe = function()
        if exact_goal(name, data, before) then return "applied", { goal = name } end
        return "pending"
      end,
    })
  end
end

function M.busy()
  return job and job.phase or nil
end

function M.answer(bridge, id, name, success, message, code, group, window_id)
  local current = Window.current()
  local own_window = window_id == nil or (current ~= nil and current.id == window_id)
  local names = (success == true and own_window) and Window.withdrawal(name, group) or nil
  if names and bridge and type(bridge.withdraw_actions) == "function" then
    local ok, withdrawn = pcall(bridge.withdraw_actions, bridge, names)
    if not ok or withdrawn == false then
      local fault = ActionResult.internal_error()
      return M.answer(bridge, id, name, false, fault.message, fault.reason_code), false
    end
  end
  local delivered = true
  if bridge and type(bridge.send_action_result) == "function" then
    delivered = bridge:send_action_result(id, success, message, code) ~= false
  end
  if not delivered then
    -- The result remains owed for Bridge:answer_owed_results; withdraw any force it emptied.
    Metrics.incr("action_result_undelivered")
    print("[neuro-game] Action result for " .. tostring(name) .. " (" .. tostring(id) .. ") was not delivered.")
    if names then Window.on_undelivered(name, names) end
    return delivered, success
  end
  Tx.store(id)
  if own_window then Window.on_result(name, success) end
  return delivered, success
end

local function push_recent(name)
  local n = G and G.NEURO
  if not n then return end
  local recent = type(n.recent_actions) == "table" and n.recent_actions or {}
  recent[#recent + 1] = name
  while #recent > 10 do table.remove(recent, 1) end
  n.recent_actions = recent
end

-- Record an answered refusal as no change, or the next force repeats it verbatim.
function M.note_unchanged(name)
  push_recent(tostring(name) .. " (no change)")
end

local function clear_pack_exit(id)
  local n = G and G.NEURO
  if n and (n.pack_exit_pending == true or n.pack_exit_pending == tostring(id)) then n.pack_exit_pending = nil end
end

local function own_proposal(done)
  local tx = done.name == "resolve_play" and Gate.proposal()
  if tx and done.tx and tx.ref == done.tx.proposal_ref then return tx end
  return nil
end

local function restore(done)
  clear_pack_exit(done.id)
  local tx = own_proposal(done)
  if tx then Gate.rollback_commit(tx) end
  if G and G.NEURO then G.NEURO.weak_fired_serial = done.weak_fired end
end

local function steps(kind, done, list)
  local errors = {}
  for _, step in ipairs(list) do
    local ok, err = pcall(step[2])
    if not ok then errors[#errors + 1] = step[1] .. ": " .. Utils.safe_tostring(err) end
  end
  if #errors > 0 then
    Metrics.incr("action_finalize_error")
    print("[neuro-game] Warning: " .. kind .. " finalization for action " .. tostring(done.id)
      .. " had errors: " .. table.concat(errors, "; "))
  end
end

local function finalize_failed(done, outcome, details)
  if job == done then job = nil end
  Staging.finish(done, false)
  local declined = type(details) == "table" and details.terminal_class == "DECLINED_NOOP"
  steps("failed", done, {
    { "restore", function() restore(done) end },
    { "hand transaction", function()
      local tx = own_proposal(done)
      if tx then Gate.close_proposal(tx, "invalidated") end
    end },
    { "failure", function()
      if not declined then
        Lifecycle.record_failure(done.name, outcome == "ambiguous" and "execution outcome is ambiguous" or "action did not apply")
      end
    end },
  })
end

local CONTEXT_CHANGING = { play_hand = true, discard_hand = true, use_consumable = true,
  use_directional_consumable = true, choose_pack_card = true, choose_directional_pack_card = true,
  sell_card = true, set_joker_order = true }

local function finalize_applied(done, message, details)
  if job == done then job = nil end
  Staging.finish(done, true)
  local name = done.name
  steps("applied", done, {
    { "plan", function() PlanTransaction.settle(name, done.data, done.tx) end },
    { "gameplay journal", function()
      if not done.gameplay_event then return end
      local appended, reason = GameplayJournal.publish(done.gameplay_event)
      if not appended and reason ~= "duplicate" then error(reason, 0) end
    end },
    { "effect context", function()
      local used = type(details) == "table" and details.use_observed == true
      if used and type(message) == "string" and done.bridge then
        ContextDelivery.event_at("action_applied", ContextDelivery.here(),
          "Effect of your move (" .. require("core.action_registry").phrase(name):gsub("^%u", string.lower) .. "): " .. message,
          { bridge = done.bridge, occurrence = done.id })
      end
    end },
    { "hand transaction", function()
      local tx = done.data.answer == "yes" and own_proposal(done)
      if tx then
        Gate.close_proposal(tx, "settled")
        G.NEURO.decision_serial = (tonumber(G.NEURO.decision_serial) or 0) + 1
      end
      if CONTEXT_CHANGING[name] or name == "resolve_play" and done.data.answer == "yes" then
        Gate.observe_context_changed()
      end
    end },
    { "metric", function() Metrics.incr("action_ok") end },
    { "decision acknowledgement", function() Gate.acknowledge(done.ack_snapshot) end },
    { "settle latch", function() validate().note_applied(name) end },
    { "last action", function()
      if G and G.NEURO then G.NEURO.last_action_name = name end
      Window.hold_after_action()
    end },
  })
end

local function settle(done, now)
  if not ActionResult.settle(done.receipt, now, G and G.NEURO and G.NEURO.run_generation) then return end
  local receipt = done.receipt
  if receipt.phase == "applied" then
    finalize_applied(done, receipt.applied_message, receipt.details)
  else
    finalize_failed(done, receipt.phase, receipt.details)
  end
end

local function run(done)
  done.phase = "executing"
  Staging.take(done)
  Metrics.time_begin("action_exec")
  local ok, result = xpcall(done.exec, Utils.safe_tostring)
  Metrics.time_end("action_exec")
  if not ok then
    Metrics.incr("action_fail")
    return finalize_failed(done, "failed", { error = tostring(result) })
  end
  if ActionResult.is_receipt(result) then
    done.phase, done.receipt = "verifying", result
    return settle(done, ActionResult.now())
  end
  if ActionResult.is_outcome(result) then
    if result.status == "applied" then return finalize_applied(done) end
    return finalize_failed(done, result.status, result.details)
  end
  Metrics.incr("action_contract_violation")
  finalize_failed(done, "ambiguous", { reason = "missing_execution_evidence", result_type = type(result) })
end

function M.abort(reason)
  local done = job
  if not done then return false end
  job = nil
  Staging.finish(done, false)
  if done.receipt then ActionResult.finish(done.receipt, "ambiguous", { reason = reason }, true) end
  restore(done)
  Lifecycle.record_failure(done.name, reason)
  return true
end

function M.admit(done, staged)
  local bridge = done.bridge
  if done.ends_pack and G and G.NEURO then G.NEURO.pack_exit_pending = tostring(done.id) end
  local note = type(done.tx) == "table" and done.tx.ignored_note or nil
  if done.field_note then note = note and (note .. " " .. done.field_note) or done.field_note end
  local sent, delivered, admitted = pcall(M.answer, bridge, done.id, done.name, true, note, "ACTION_ACCEPTED",
    done.disposable)
  if sent and delivered and not admitted then return clear_pack_exit(done.id) end
  if not (sent and delivered) then
    Metrics.incr("action_admission_result_undelivered")
    restore(done)
    if not sent then error(delivered, 0) end
    return
  end
  push_recent(done.name)
  validate().note_accepted(done)
  if G and G.NEURO then G.NEURO.render_dirty_epoch = (tonumber(G.NEURO.render_dirty_epoch) or 0) + 1 end
  if done.gameplay_event ~= nil then
    local ok, sealed = pcall(GameplayJournal.seal, done.gameplay_event, tostring(done.id))
    done.gameplay_event = ok and sealed or nil
    if not (ok and sealed) then Metrics.incr("gameplay_journal_candidate_rejected") end
  end
  done.exec = M.wrap(done.name, done.data, done.exec)
  job = done
  done.phase = "staged"
  if staged and Staging.begin(done) and not Staging.ready(done) then return end
  local ok, err = xpcall(run, Utils.safe_tostring, done)
  if not ok then
    Metrics.incr("action_pipeline_fail")
    finalize_failed(done, "ambiguous", { error = err })
  end
end

function M.step(now)
  local done = job
  if not done then return end
  if done.phase == "staged" then
    local current = require("core.state").get_state_name()
    if (G and G.NEURO and G.NEURO.run_generation) ~= done.run_generation then
      return M.abort("transport generation changed")
    elseif current ~= done.state then
      return M.abort("Action cancelled: game state changed")
    elseif Staging.stalled(done) then
      return M.abort("Action cancelled: staging timeout")
    elseif Staging.ready(done) then
      local ok, err = xpcall(run, Utils.safe_tostring, done)
      if not ok then finalize_failed(done, "ambiguous", { error = err }) end
    end
  elseif done.phase == "verifying" then
    settle(done, now or ActionResult.now())
  end
end

return M
