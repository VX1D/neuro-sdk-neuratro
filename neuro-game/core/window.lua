local M = {}

local Utils = require("util.utils")
local Metrics = require("util.metrics")
local S = require("hud.state")
local Actions = require("core.actions")
local ActionRegistry = require("core.action_registry")
local ActionPolicy = require("core.action_policy")
local StateKinds = require("core.state_kinds")
local ContextDelivery = require("core.context_delivery")
local ContextCompact = require("context.context_compact")
local ContextReadable = require("context.context_readable")
local StateDoc = require("context.state_doc")
local ForceHelpers = require("force.force_helpers")
local Router = require("force.force_router")
local DecisionDelta = require("facts.decision_delta")
local TokenLegends = require("facts.token_legends")
local FactHints = require("facts.fact_hints")
local Once = require("util.once")

local REGISTERED, FORCED, ENDED = "registered", "forced", "ended"
M.LIVENESS_ESCALATE_AT = 2
M.LIVENESS_MAX_DOUBLINGS = 1
-- Refused forces are re-asked sooner because the server retries refusals only a limited number of times.
M.REFUSED_LIVENESS = 30

local ready_since

local function neuro() return G and G.NEURO end

function M.current()
  local n = neuro()
  local w = n and n.force_window
  if type(w) == "table" and w.phase ~= ENDED then return w end
  return nil
end

function M.forced(name)
  local w = M.current()
  return w ~= nil and w.phase == FORCED and w.set[name] == true
end

function M.state_name()
  local w = M.current()
  return w and w.state or nil
end

local function finish(reason)
  local w = M.current()
  if not w then return false end
  w.phase, w.ended_by = ENDED, reason
  require("core.bridge").release_force_lock(neuro())
  ready_since = nil
  return true
end

local function disposables(names)
  local out = {}
  for _, name in ipairs(names or {}) do
    if ActionPolicy.disposable_group(name) then out[#out + 1] = name end
  end
  return out
end

local function decisions(names)
  local out = {}
  for _, name in ipairs(names or {}) do
    if ActionPolicy.is_decision(name) then out[#out + 1] = name end
  end
  return out
end

local function registration_key(bridge)
  return "session:" .. tostring(bridge.session_id) .. ":transport:" .. tostring(bridge.transport_session or "")
end

function M.withdraw(reason)
  local w = M.current()
  if not w then return false end
  if w.phase == FORCED then
    local n = neuro()
    local ok, withdrawn = true, nil
    if type(n.withdraw_actions) == "function" then ok, withdrawn = pcall(n.withdraw_actions, n, w.names) end
    -- A failed unregister keeps this force active; retry next tick before opening another.
    if not ok or withdrawn == false then return false end
    Metrics.incr("force_cancel_reason_" .. tostring(reason))
  end
  return finish(reason)
end

local function answers(w, name)
  if not w then return false end
  if w.set[name] then return true end
  for _, member in ipairs(ActionPolicy.disposable_group(name) or {}) do
    if w.set[member] then return true end
  end
  return false
end

function M.withdrawal(name, group)
  local w = M.current()
  if not answers(w, name) then return group end
  local out, seen, offered = {}, {}, false
  for _, list in ipairs({ group or {}, disposables(w.names) }) do
    for _, member in ipairs(list) do
      if not seen[member] then seen[member], out[#out + 1] = true, member end
      offered = offered or w.set[member] == true
    end
  end
  -- A reusable answer can itself cancel the force when no offered action remains.
  if not offered and ActionPolicy.REUSABLE[name] then out[#out + 1] = name end
  return out
end

function M.on_result(name, success)
  local w = M.current()
  if success == true and answers(w, name) then return finish("answered") end
  if success == false and w and w.phase == FORCED and w.set[name] then
    w.answered_at = Utils.gate_now("force_liveness_timeout")
  end
end

function M.on_response()
  local n = neuro()
  if n then n.force_liveness = nil end
  local w = M.current()
  if w then w.answered_at = nil end
end

-- A spent decision re-asked with the same offer keeps its actions registered.
function M.offer_unchanged(name)
  local w = M.current()
  if not (w and w.phase == FORCED and answers(w, name)) then return false end
  if w.spent then return true end
  for _, member in ipairs(w.names) do
    if ActionPolicy.NON_PROGRESS[member] then return false end
  end
  return true
end

-- If a success cannot be delivered, withdraw the force: its actions are already gone.
function M.on_undelivered(name, withdrawn)
  local w = M.current()
  if not (w and w.phase == FORCED) then return false end
  for _, member in ipairs(withdrawn or {}) do
    if w.set[member] then return M.withdraw("result_undelivered") end
  end
  return false
end


local function catalogue_complete(bridge, definitions)
  for _, definition in ipairs(definitions) do
    if not bridge._registered_sigs[definition.name] then return false end
  end
  return true
end

function M.register_catalogue(offered)
  local bridge = neuro()
  if not bridge then return false end
  local ok, delivered = pcall(function()
    Actions.get_static_actions()
    local definitions = ActionRegistry.definitions()
    local held = bridge._withdrawn_held
    local offer = offered and Utils.list_to_set(offered) or {}
    if type(held) == "table" and next(held) then
      local kept = {}
      for _, definition in ipairs(definitions) do
        if not held[definition.name] or offer[definition.name] then kept[#kept + 1] = definition end
      end
      definitions = kept
    end
    local key = registration_key(bridge)
    local signature = Actions.catalogue_signature()
    if bridge._static_actions_registration_key == key and bridge._static_actions_catalogue_sig == signature
        and catalogue_complete(bridge, definitions) then
      return true
    end
    local result = bridge:register_actions(definitions)
    if result ~= false then
      bridge._static_actions_registration_key, bridge._static_actions_catalogue_sig = key, signature
      if type(held) == "table" then
        for name in pairs(offer) do held[name] = nil end
      end
    end
    return result
  end)
  if ok and delivered ~= false then return true end
  Metrics.incr("action_registration_failed")
  print("[neuro-game] Action registration failed: " .. tostring(delivered))
  return false
end

local STABLE_STATES = { SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true,
  MENU = true, RUN_SETUP = true, SPLASH = true, GAME_OVER = true, ROUND_EVAL = true }

function M.emit_rules(state_name)
  if not Utils.can_send() then return end
  if STABLE_STATES[state_name] or StateKinds.is_pack_state(state_name) then
    local ok, frames = pcall(ContextCompact.rule_frames, state_name)
    if ok and type(frames) == "table" then
      for _, frame in ipairs(frames) do
        ContextDelivery.rule("permanent_rule:" .. tostring(frame.key), ContextReadable.verbalize_stable(frame.text))
      end
    end
  end
  ContextDelivery.rule(TokenLegends.ACTION_SEMANTICS_V1.key, TokenLegends.ACTION_SEMANTICS_V1.text)
end

local function emit_glossary(state_name)
  if not Utils.can_send() then return false end
  local ok = ContextDelivery.rule("gloss:readable_common", TokenLegends.READABLE_COMMON) ~= false
  local state_text = TokenLegends.READABLE_STATE[state_name]
  if state_text and state_text ~= "" then
    ok = ContextDelivery.rule("gloss:readable_state:" .. state_name, state_text) ~= false and ok
  end
  if TokenLegends.has_jokers() then
    ok = ContextDelivery.rule("gloss:readable_joker_tags", TokenLegends.READABLE_JOKER_TAGS) ~= false and ok
  end
  return ok
end

function M.build_payload(state_name, force)
  local usable = force.actions or {}
  local blocks = ContextReadable.blocks(state_name, usable) or {}
  local delta, candidate = DecisionDelta.for_force(state_name)
  for _, extra in ipairs({ force.state_extra or false, delta or false }) do
    if type(extra) == "string" and extra ~= "" then blocks[#blocks + 1] = { heading = "History", text = extra } end
  end
  local context = StateDoc.render(blocks)
  return context ~= "" and context or nil, candidate
end


local function fingerprint(w)
  local names = {}
  for i, name in ipairs(w.names) do names[i] = tostring(name) end
  table.sort(names)
  return table.concat({ tostring(neuro().decision_serial or 0), tostring(w.state), table.concat(names, ",") }, "|")
end

function M.liveness_timeout(w)
  local base = Utils.gate_seconds("force_liveness_timeout", "NEURO_FORCE_LIVENESS_TIMEOUT")
  local record = neuro() and neuro().force_liveness
  if not (w and record and record.fingerprint == fingerprint(w)) then return base end
  return base * 2 ^ math.min(record.repeats, M.LIVENESS_MAX_DOUBLINGS)
end

function M.liveness_note(repeats)
  return "This decision has gone unanswered " .. tostring(repeats) .. " times: each unanswered force was "
    .. "withdrawn and the decision asked again. The game cannot continue until you answer one of the actions offered."
end

function M.liveness_repeats(state_name)
  local record = neuro() and neuro().force_liveness
  if not record or (state_name ~= nil and record.state ~= state_name) then return 0 end
  return record.repeats
end

local function liveness_expired(w)
  local n = neuro()
  if n.enabled == false or n.llm_paused or w.phase ~= FORCED then return false end
  local now = Utils.gate_now("force_liveness_timeout")
  if w.answered_at and now - w.answered_at >= M.REFUSED_LIVENESS then return true end
  return now - w.sent_at >= M.liveness_timeout(w)
end

local function liveness_timeout(w)
  local n = neuro()
  local print_key = fingerprint(w)
  if not M.withdraw("liveness_timeout") then return end
  local record = n.force_liveness
  local repeats = (record and record.fingerprint == print_key) and record.repeats + 1 or 1
  n.force_liveness = { fingerprint = print_key, repeats = repeats, state = w.state }
  Metrics.set("force_liveness_repeat", repeats)
  if repeats == M.LIVENESS_ESCALATE_AT then
    Metrics.incr("force_liveness_repeat_escalated")
    local occurrence = "decision " .. tostring(n.decision_serial or 0)
    ContextDelivery.event_at("force_liveness", ContextDelivery.here(occurrence),
      M.liveness_note(repeats), { occurrence = occurrence })
  end
end


function M.hold_after_action(extra)
  local n = neuro()
  if not n then return end
  local at = Utils.gate_now("action_cooldown") + (tonumber(extra) or 0)
  if not n.last_action_at or at > n.last_action_at then n.last_action_at = at end
end

function M.note_state_change()
  S.state_changed_at_game = Utils.gate_now("state_cooldown")
end

local PACK_ENTRY_KNOB = { Buffoon = "BUFFOON_PACK", Arcana = "TAROT_PACK", Celestial = "PLANET_PACK",
  Spectral = "SPECTRAL_PACK", Standard = "STANDARD_PACK" }

local function entry_knob(state_name)
  local smods = rawget(_G, "SMODS")
  local kind = state_name == "SMODS_BOOSTER_OPENED" and smods
    and PACK_ENTRY_KNOB[require("facts.card_util").booster_kind(smods.OPENED_BOOSTER)]
  return "NEURO_ENTRY_CD_" .. (kind or tostring(state_name))
end

-- Cash Out appearing means round-summary counting is done; otherwise use the timed entry cooldown.
local function entry_ready(state_name)
  if state_name ~= "ROUND_EVAL" then return false end
  local ok, button = pcall(require("facts.game_facts").cash_out_button)
  return ok and button ~= nil
end

-- A draw_hand pack deals in a separate event after the pack UI appears.
local function pack_deal_pending()
  local smods = rawget(_G, "SMODS")
  local booster = smods and smods.OPENED_BOOSTER
  local center = booster and booster.config and booster.config.center
  local pack, hand, deck = require("facts.card_util").pack_area(), G.hand, G.deck
  if not (center and center.draw_hand == true and pack and hand and hand.cards and deck and deck.cards) then
    return false
  end
  local untouched = #pack.cards >= (tonumber(pack.config and pack.config.card_limit) or math.huge)
  return untouched and #hand.cards == 0 and #deck.cards > 0
    and (tonumber(hand.config and hand.config.card_limit) or 0) > 0
end

local function settled(state_name)
  local n = neuro()
  local Validate = require("core.validate")
  local hand_settled = Validate.hand_settled()
  if not Validate.engine_ready() then return false end
  if state_name == "SELECTING_HAND" and not hand_settled then return false end
  if StateKinds.is_pack_state(state_name) and pack_deal_pending() then return false end
  if n:is_transition_cooldown() then return false end
  local entered_at = S.state_changed_at_game or 0
  local now = Utils.gate_now("state_cooldown")
  if now - entered_at < Utils.gate_seconds("state_cooldown") then return false end
  local entry = not entry_ready(state_name) and Utils.gate_seconds("state_entry_cooldown", entry_knob(state_name))
  if entry and Utils.gate_now("state_entry_cooldown") - entered_at < entry then return false end
  local acted = n.last_action_at
  return not (acted and Utils.gate_now("action_cooldown") - acted
    < Utils.gate_seconds("action_cooldown", "NEURO_ACTION_COOLDOWN"))
end

local function armable(state_name)
  local n = neuro()
  if not (n.enabled and n.persona) or n.llm_paused then return false end
  if n:is_transport_saturated() then return false end
  if require("core.execute").busy() then return false end
  -- Do not open another force while a result is owed; the server is still waiting on that action.
  if #require("core.bridge").tx.outstanding() > 0 then return false end
  local anim = n.login_anim
  if anim and anim.start and Utils.gate_now("login_anim_block") - anim.start
      < Utils.gate_seconds("login_anim_block", "NEURO_LOGIN_ANIM_BLOCK") then
    return false
  end
  local pack = StateKinds.is_pack_state(state_name) and require("facts.card_util").pack_area()
  if StateKinds.is_pack_state(state_name) and not (pack and pack.cards and #pack.cards > 0) then
    Router.observe_pack_exit(state_name)
    return false
  end
  if G.OVERLAY_MENU and Actions.is_action_valid("exit_overlay_menu") then return true end
  return not require("core.staging").is_busy() and settled(state_name)
end

local function stale(state_name, force)
  local ok, current = pcall(require("core.state").get_state_name)
  if ok and current and current ~= state_name then return true end
  if state_name == "BLIND_SELECT" and force.blind then
    local key = Actions.get_selectable_blind_key()
    return not key or key:lower() ~= tostring(force.blind)
  end
  return false
end

local function arm(state_name)
  local n = neuro()
  FactHints.reset_pending()
  local journal = Once.begin_journal()
  local function abandon() Once.rollback_journal(journal) end
  Utils.begin_text_build()
  local force = Router.get_force_for_state(state_name)
  if not force then return Once.rollback_journal(journal) end
  local context, candidate = M.build_payload(state_name, force)
  Router.report_missing_sections(state_name, force.query, context)
  local snapshot = state_name == "SELECTING_HAND" and force.decision_snapshot or nil
  if stale(state_name, force)
      or (snapshot and not require("core.gate").snapshot_is_current(snapshot))
      or not M.register_catalogue(force.actions) then
    return abandon()
  end
  M.emit_rules(state_name)
  if not ContextDelivery.essential_ready() or not emit_glossary(state_name) then return abandon() end
  FactHints.flush_pending()
  local w = { id = (tonumber(n.force_window_id) or 0) + 1, state = state_name, phase = REGISTERED,
    names = force.actions, set = Utils.list_to_set(force.actions), spent = require("core.validate").decision_spent(),
    legal = Utils.list_to_set(decisions(Actions.get_valid_actions_for_state(state_name))) }
  n.force_window_id, n.force_window = w.id, w
  local ok, sent = pcall(n.force_actions, n, Utils.trim_line_ends(context), Utils.trim_line_ends(force.query),
    force.actions, { priority = ForceHelpers.force_priority(), ephemeral_context = force.ephemeral_context ~= false,
      confirmation_proposal_ref = force.confirmation_proposal_ref })
  if not ok or sent == false then
    if not ok then print("[neuro-game] force send error: " .. Utils.safe_tostring(sent)) end
    finish("unsent")
    return Once.rollback_journal(journal)
  end
  w.phase, w.sent_at = FORCED, Utils.gate_now("force_liveness_timeout")
  Once.commit_journal(journal)
  DecisionDelta.commit(candidate)
end

local function widened(state_name, w)
  for _, name in ipairs(decisions(Actions.get_valid_actions_for_state(state_name))) do
    if not w.legal[name] then return true end
  end
  return false
end

function M.step(state_name)
  local n = neuro()
  if not n then return end
  local known = state_name ~= nil and state_name ~= ""
  local w = M.current()
  if w then
    if w.phase ~= FORCED then return end
    if known and state_name ~= "UNKNOWN" and state_name ~= w.state then return M.withdraw("state_changed") end
    if known and n.enabled and not n.llm_paused and widened(state_name, w) then return M.withdraw("widened") end
    if liveness_expired(w) then liveness_timeout(w) end
    return
  end
  if not known then return end
  if not armable(state_name) then
    ready_since = nil
    return
  end
  local now = Utils.gate_now("force_debounce")
  if not ready_since or now < ready_since then ready_since = now end
  if now - ready_since < Utils.gate_seconds("force_debounce", "NEURO_FORCE_DEBOUNCE") then return end
  ready_since = now
  arm(state_name)
end

function M.reset()
  local n = neuro()
  finish("reset")
  ready_since = nil
  if n then n.force_liveness = nil end
end

if rawget(_G, "NEURO_TEST") then
  M._test = { settled = settled, arm = arm, emit_glossary = emit_glossary,
    armable = armable }
end

return M
