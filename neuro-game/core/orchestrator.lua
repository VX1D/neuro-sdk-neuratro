local Orchestrator = {}

local Utils = require("util.utils")
local Metrics = require("util.metrics")
local S = require("hud.state")
local Tuning = require("core.config")
local ContextCompact = require("context.context_compact")
local ContextReadable = require("context.context_readable")
local Rewards = require("core.rewards")
local CtxHand = require("context.ctx_hand")
local Staging = require("core.staging")
local NeuroState = require("core.state")
local StateKinds = require("core.state_kinds")
local NeuroActions = require("core.actions")
local NeuroDispatcher = require("core.dispatcher")
local ForceHelpers = require("force.force_helpers")
local ForceState = require("core.force_state")
local ForceWindow = require("core.force_window")
local DebugStats = require("render.debug_stats")
local HUD = require("render.hud_overlay")
local BridgeInit = require("core.bridge_init")
local ContextDelivery = require("core.context_delivery")
local function anim() return Utils.lazy_require("render.neuro-anim") end
local TransitionGuard = require("core.transition_guard")
local neuro_now = Utils.now

Staging.set_executor(NeuroDispatcher.handle_message)

local bridge_attempted = false
local last_neuro_error = nil
local _neuro_err_cd = 0
local _game_err_cd = 0
local _game_err_last_msg = nil

local _neuro_autotest = false
do
  local cli = rawget(_G, "arg") or {}
  for _, v in ipairs(cli) do
    if v == "--test" then _neuro_autotest = true break end
  end
end

local neuro_last_force_attempt_at = 0
local neuro_seen_action_at = 0
local neuro_cancel_quarantined = false
local neuro_force_delivery = nil
local function _boot_flag(key)
  local v = os.getenv(key)
  if v then
    v = tostring(v):lower()
    if v == "1" or v == "on" or v == "true" or v == "yes" then return true end
    if v == "0" or v == "off" or v == "false" or v == "no" then return false end
  end
  return Tuning.bool(key)
end

local _selftest_on_boot = nil
local _selftest_pack_on_boot = nil
local _tasks_on_boot = nil
local _card_dex_on_boot = nil

local Lifecycle = require("core.neuro_lifecycle")
local function mark_force_dirty() Lifecycle.mark_force_dirty() end

local DecisionDelta = require("facts.decision_delta")
local ConfirmationEvidence = require("core.confirmation_evidence")
local GameplayJournal = require("core.gameplay_journal")

local TokenLegends = require("facts.token_legends")
local FactHints = require("facts.fact_hints")
local Once = require("util.once")
local function send_glossary(key, text)
  ContextDelivery.rule(key, text)
end
local function emit_state_glossary(state_name)
  if not Utils.can_send() then return end
  send_glossary("gloss:readable_common", TokenLegends.READABLE_COMMON)
  local state_text = TokenLegends.READABLE_STATE[state_name]
  if state_text and state_text ~= "" then
    send_glossary("gloss:readable_state:" .. state_name, state_text)
  end
  if TokenLegends.has_jokers() then
    send_glossary("gloss:readable_joker_tags", TokenLegends.READABLE_JOKER_TAGS)
  end
end

local force_arm = require("core.force_state").arm
local force_supersede = require("core.force_state").supersede
local force_window_is_open = require("core.force_state").window_is_open

local function force_state_moved(state_name)
  if not (G and G.NEURO) then return false end
  if not (state_name and state_name ~= "" and state_name ~= "UNKNOWN") then return false end
  local win = ForceState.window()
  local open = ForceWindow.is_open(win)
  if not (G.NEURO.force_inflight or open) then return false end
  local built = (open and win.state) or G.NEURO.force_state
  return not not (built and built ~= state_name)
end

local STABLE_STATES = { SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true,
  MENU = true, RUN_SETUP = true, SPLASH = true, GAME_OVER = true }
local function maybe_emit_permanent_rules(state_name)
  if not Utils.can_send() then return end
  if not (STABLE_STATES[state_name] or StateKinds.is_pack_state(state_name)) then return end
  local ok, frames = pcall(ContextCompact.rule_frames, state_name)
  if not ok or type(frames) ~= "table" or #frames == 0 then
    return
  end
  for _, frame in ipairs(frames) do
    ContextDelivery.rule("permanent_rule:" .. tostring(frame.key),
      ContextReadable.verbalize_stable(frame.text))
  end
end

local function build_valid_action_definitions(state_name, valid)
  valid = valid or NeuroActions.get_valid_actions_for_state(state_name)
  local valid_set = Utils.list_to_set(valid)
  local filtered = {}
  for _, def in ipairs(require("core.action_registry").definitions()) do
    if valid_set[def.name] then filtered[#filtered + 1] = def end
  end
  return filtered
end

local function register_valid_actions(state_name)
  local valid = NeuroActions.get_valid_actions_for_state(state_name)
  if not NeuroActions.state_is_modelled(state_name) then return valid, true end
  if not (G and G.NEURO and G.NEURO.register_actions) then return valid, false end
  local ok, delivered = pcall(function()
    return G.NEURO:register_actions(build_valid_action_definitions(state_name, valid))
  end)
  if not ok or delivered == false then
    Metrics.incr("action_registration_failed")
    print("[neuro-game] Action registration failed for " .. tostring(state_name)
      .. ": " .. tostring(ok and delivered or delivered))
    return valid, false
  end
  return valid, true
end

local function neuro_can_act()
  if not Utils.neuro_ready() then return false end
  if not TransitionGuard.engine_ready() then return false end
  if (tonumber(G.NEURO.reserved_dollars) or 0) > 0 then return false end
  local entered_at = S.state_changed_at_game or 0
  local settled = Utils.gate_now("state_cooldown")
  if (settled - entered_at) < Utils.gate_seconds("state_cooldown") then
    return false
  end
  local state_name = G.NEURO.state or ""
  local entry_cd = Utils.gate_seconds("state_entry_cooldown", "NEURO_ENTRY_CD_" .. tostring(state_name))
  if entry_cd and (Utils.gate_now("state_entry_cooldown") - entered_at) < entry_cd then
    return false
  end
  local acted = Lifecycle.action_now()
  if G.NEURO.last_action_at and (acted - G.NEURO.last_action_at) < Lifecycle.action_cooldown() then
    return false
  end
  return true
end

local force_is_stale = require("core.force_state").force_is_stale
local snapshot_once_serials = require("core.force_state").snapshot_once_serials
local restore_once_serials = require("core.force_state").restore_once_serials

local build_action_set = Utils.list_to_set

local function desired_action_names()
  local state_name = (G and G.NEURO and G.NEURO.state) or ""
  if not NeuroActions.state_is_modelled(state_name) then return nil end
  local names = {}
  for _, def in ipairs(build_valid_action_definitions(state_name)) do
    names[def.name] = true
  end
  return names
end

local _init_deps = {
  mark_force_dirty = mark_force_dirty,
  register_valid_actions = register_valid_actions,
}
Orchestrator.build_valid_action_definitions = build_valid_action_definitions
Orchestrator.register_valid_actions = register_valid_actions

function Orchestrator.init()
  local ok, initialized = pcall(BridgeInit.run, _init_deps)
  if not ok then
    print("[neuro-game] LOAD ERROR (neuro setup): " .. tostring(initialized))
  end
  if G and G.NEURO and G.NEURO.set_desired_action_names then
    G.NEURO:set_desired_action_names(desired_action_names)
  end
  bridge_attempted = ok and initialized ~= false
end

local AREA_GLOBAL_KEYS = {"hand", "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster", "pack_cards", "booster_pack"}

local function area_is_tombstoned(area)
  if area.REMOVED then return true end
  return area.cards == nil and area.children == nil
end

local function _step_area_nil_guard()
  if not G then return end
  for i = 1, #AREA_GLOBAL_KEYS do
    local key = AREA_GLOBAL_KEYS[i]
    local area = G[key]
    if area then
      if area_is_tombstoned(area) then
        G[key] = nil
      elseif area.cards == nil then
        area.cards = {}
      end
    end
  end
end

local function _step_autotest()
  if not _neuro_autotest then return false end
  _neuro_autotest = false
  local tok, result = pcall(function() return require("tests.test_deadlock").run() end)
  if not tok then
    print("[test] Error: " .. tostring(result))
    love.event.quit(1)
  else
    love.event.quit((result or 0) > 0 and 1 or 0)
  end
  return true
end

local function _step_game_update(dt, original_love_update)
  local update_success, update_err = true, nil
  if original_love_update then
    update_success, update_err = pcall(original_love_update, dt)
  end

  if not update_success then
    local now = Utils.gate_now("game_error_log_cooldown")
    local msg = tostring(update_err)
    if now > _game_err_cd or msg ~= _game_err_last_msg then
      print("[neuro-game] Warning: Game update error: " .. msg)
      _game_err_last_msg = msg
      _game_err_cd = now + 5
    end
  else
    if _game_err_cd > 0 and Utils.gate_now("game_error_log_cooldown") > _game_err_cd then
      _game_err_cd = 0
      _game_err_last_msg = nil
    end
  end
end

local function _step_hook_card_draw()
  if not S.neuro_card_draw_hooked then
    local hok, herr = pcall(HUD.hook_card_draw)
    if not hok then
      print("[neuro-game] UPDATE ERROR (hook_card_draw): " .. tostring(herr))
    end
  end
end

local function _step_bridge_init()
  if not bridge_attempted and G then
    local bok, initialized = pcall(BridgeInit.run, _init_deps)
    if not bok then
      print("[neuro-game] UPDATE ERROR (bridge setup): " .. tostring(initialized))
    end
    bridge_attempted = bok and initialized ~= false
  end
end

local function _step_side_tasks(dt)
  if _selftest_on_boot == nil then
    _selftest_on_boot = _boot_flag("NEURO_SELFTEST_ON_BOOT")
    _selftest_pack_on_boot = _boot_flag("NEURO_SELFTEST_PACK")
    _tasks_on_boot = _boot_flag("NEURO_SMALL_REGRESSION")
    _card_dex_on_boot = _boot_flag("NEURO_CARD_DEX_ON_BOOT")
  end

  if _selftest_on_boot or _selftest_pack_on_boot or (G.NEURO and G.NEURO.selftest_active) then
    local SelfTest = require("core.selftest")
    if SelfTest.running() then
      SelfTest.tick(dt)
    elseif (_selftest_on_boot or _selftest_pack_on_boot) and SelfTest.available() then
      local pack_only = _selftest_pack_on_boot
      _selftest_on_boot = false
      _selftest_pack_on_boot = false
      local opts
      if pack_only then
        local ok_c, Cases = pcall(require, "core.selftest_cases")
        if ok_c and Cases.build_pack then opts = { cases = Cases.build_pack(), reset = Cases.reset } end
      end
      local st_ok, st_err = SelfTest.start(opts)
      if not st_ok then
        print("[neuro-game] selftest on boot failed: " .. tostring(st_err))
      else
        print("[neuro-game] selftest on boot STARTED")
      end
    end
    return
  end

  if _tasks_on_boot or (G.NEURO and G.NEURO.task_mode_active) then
    local TaskMode = require("core.task_mode")
    if TaskMode.running() then
      TaskMode.tick(dt)
    elseif _tasks_on_boot and TaskMode.available() then
      _tasks_on_boot = false
      TaskMode.start()
    end
  end
  if _card_dex_on_boot then
    if require("hud.card_dex").boot_done() then
      _card_dex_on_boot = false
    else
      require("hud.card_dex").boot_tick()
    end
  end
  if G.NEURO.input_buffer and G.NEURO.input_buffer ~= ""
    and not (G.CONTROLLER and G.CONTROLLER.text_input_hook) then
    G.NEURO.input_buffer = ""
  end
end

local function _step_context_refresh(state_name)
  maybe_emit_permanent_rules(state_name)
end

local function clear_shop_reservations()
  G.NEURO._reservation_epoch = (tonumber(G.NEURO._reservation_epoch) or 0) + 1
  G.NEURO.reserved_dollars = 0
end

local function _step_state_transition(state_name, state_changed, prev_state)
  if not state_changed then return end
  Staging.on_state_change()
  local NA = anim()
  if NA and NA.on_state_enter then
    pcall(NA.on_state_enter, state_name)
  end
  if state_name == "BLIND_SELECT" then
    CtxHand.clear_last_play()
  end
  G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
  G.NEURO.decision_serial = (G.NEURO.decision_serial or 0) + 1
  require("core.plan_gate").begin_cycle()
  G.NEURO.pack_exit_pending = nil
  G.NEURO.pack_transition_stalled = nil
  G.NEURO.pack_transition_stall_key = nil
  S.state_changed_at = neuro_now()
  S.state_changed_at_game = Utils.gate_now("state_cooldown")
  if state_name == "SHOP" and prev_state ~= "SHOP" then
    local resumed = G.NEURO.shop_pack_interrupt and StateKinds.is_shop_interlude(prev_state)
    G.NEURO.shop_pack_interrupt = nil
    if not resumed then
      require("core.plan_gate").enter_shop()
    end
    clear_shop_reservations()
  elseif prev_state == "SHOP" and state_name ~= "SHOP" then
    G.NEURO.shop_pack_interrupt = StateKinds.is_shop_interlude(state_name) or nil
    clear_shop_reservations()
  end
  Lifecycle.clear_failure()
  ForceState.ack_scope_reset()
  G.NEURO.state = state_name
  if state_name == "SELECTING_HAND" and (prev_state == "SPLASH" or prev_state == "MENU" or prev_state == "RUN_SETUP") then
    ContextCompact.invalidate_cache()
    G.NEURO.seed_pasted = nil
    G.NEURO.setup_acknowledged = false
    CtxHand.clear_last_play()
  end
  if state_name == "SELECTING_HAND" and prev_state == "BLIND_SELECT" then
    ContextCompact.invalidate_cache()
  end
  register_valid_actions(state_name)
  if Utils.engine_settled() then
    _step_context_refresh(state_name)
  end
  local rmsg, rspoken = Rewards.outcome(prev_state, state_name)
  if rmsg then
    local coords = {}
    if rspoken then
      ContextDelivery.prompt_at("outcome", coords, rmsg)
    else
      ContextDelivery.event_at("outcome", coords, rmsg)
    end
  end
  mark_force_dirty()
end

local function _step_shop_entry_settle(state_name)
  if state_name ~= "SHOP" then return end
  require("core.plan_gate").settle_shop_entry()
end

local function _step_joker_departures(state_name)
  for _, event in ipairs(Rewards.observe_self_expiring_jokers(state_name)) do
    ContextDelivery.event_at("joker_departure:" .. tostring(event.key), event.coords, event.text)
  end
end

local function _step_showcase_anim(state_name, now)
  HUD.update_buy_showcase(now)
  HUD.update_joker_showcase(now)

  local NA_pack = anim()
  if NA_pack and NA_pack.on_pack_open
    and StateKinds.is_pack_state(state_name) then
    pcall(NA_pack.on_pack_open)
  end
end

local function build_force_payload(state_name, force)
  local context = ContextReadable.build(state_name, force.actions)
  if not context then
    context = ContextCompact.build(state_name, force.actions, {
      force_phase = true,
      split = "state",
    })
  end
  local delta, candidate = DecisionDelta.for_force(state_name)
  if delta and delta ~= "" then
    context = (context and context ~= "") and (context .. "\n" .. delta) or delta
  end
  return context, candidate
end

local function force_send_blocked()
  if not (G and G.NEURO) then return true end
  if not G.NEURO.enabled then return true end
  if G.NEURO.llm_paused then return true end
  if type(G.NEURO.force_actions) ~= "function" then return true end
  return false
end

local function window_awaiting_send()
  local win = ForceState.window()
  if ForceWindow.is_open(win) and win.phase == ForceWindow.REGISTERED then return win end
  return nil
end

local function send_armed_window()
  local win = window_awaiting_send()
  local p = win and win.payload
  if not p then return false end
  if force_send_blocked() then return false end
  local ok, sent, receipt = pcall(G.NEURO.force_actions, G.NEURO, p.context, p.query, p.actions,
    { priority = p.priority or "low", ephemeral_context = p.ephemeral_context ~= false })
  if not ok or sent == false then
    ForceState.invalidate("force_send_throw")
    print("[neuro-game] force send error: " .. Utils.safe_tostring(sent))
    return false
  end
  local physically_written = not receipt or receipt.status == "written"
  local marked = physically_written and ForceState.mark_sent(receipt and receipt.written_at)
    or ForceState.mark_queued()
  if not marked then
    ForceState.invalidate("force_queue_state_error")
    return false
  end
  neuro_force_delivery = {
    receipt = receipt,
    actions = p.actions,
    window = win,
    queued_at = ForceState.delivery_queued_at(),
    decision_candidate = p.decision_candidate,
  }
  if physically_written then
    DecisionDelta.commit(p.decision_candidate)
    neuro_force_delivery = nil
  end
  return true
end

local function step_force_delivery()
  local pending = neuro_force_delivery
  if not pending then return end
  local receipt = pending.receipt
  if receipt and receipt.status == "rejected" then
    neuro_force_delivery = nil
    if ForceState.window() == pending.window then ForceState.invalidate("force_delivery_rejected") end
    return
  end
  if not receipt or receipt.status ~= "written" then
    if ForceState.delivery_liveness_expired(pending.queued_at) then
      neuro_force_delivery = nil
      if ForceState.window() == pending.window then
        Metrics.incr("force_delivery_timeout")
        ForceState.invalidate("force_delivery_timeout")
      end
    end
    return
  end
  neuro_force_delivery = nil
  if ForceState.window() ~= pending.window then return end
  ForceState.mark_written(receipt.written_at)
  DecisionDelta.commit(pending.decision_candidate)
end

local function _step_unsent_window_guard()
  if window_awaiting_send() then
    ForceState.invalidate("unsent")
  end
end

local _armed_window, _armed_legal = nil, nil

local function _step_force_widened(state_name)
  local win = ForceState.window()
  if not (ForceWindow.is_open(win) and G.NEURO.enabled and not G.NEURO.llm_paused
    and state_name and state_name ~= "" and win.state == state_name) then
    _armed_window, _armed_legal = nil, nil
    return nil
  end
  local legal = NeuroActions.get_valid_actions_for_state(state_name)
  if win ~= _armed_window then
    _armed_window, _armed_legal = win, Utils.list_to_set(legal)
    return nil
  end
  local widened = nil
  for i = 1, #legal do
    if not _armed_legal[legal[i]] then widened = legal[i] break end
  end
  if not widened then return nil end
  _armed_window, _armed_legal = nil, nil
  force_supersede()
  register_valid_actions(state_name)
  mark_force_dirty()
  return widened
end

-- NaN never equals itself, and this gate is the last-resort stall escape.
local function same_field(a, b)
  return a == b or (a ~= a and b ~= b)
end

local _stall_sent, _stall_acted, _stall_changed, _stall_gen, _stall_state
local _stall_since = nil
local function _stall_disarm()
  _stall_sent, _stall_acted, _stall_changed, _stall_gen, _stall_state = nil, nil, nil, nil, nil
  _stall_since = nil
end

local function _step_force_stall()
  if not (G.NEURO.enabled and G.NEURO.persona) or G.NEURO.llm_paused then
    _stall_disarm()
    return false
  end
  if force_window_is_open() or G.NEURO.force_inflight
    or require("core.action_receipt").has_active() or Staging.is_busy() then
    _stall_disarm()
    return false
  end
  -- Runs on every idle frame.
  local sent, acted = G.NEURO.force_sent_at, G.NEURO.last_action_at
  local changed, gen, state = S.state_changed_at, G.NEURO.run_generation, G.NEURO.state
  local now = Utils.gate_now("force_stall")
  if not (same_field(sent, _stall_sent) and same_field(acted, _stall_acted)
    and same_field(changed, _stall_changed) and same_field(gen, _stall_gen)
    and same_field(state, _stall_state))
    or _stall_since == nil or now < _stall_since then
    _stall_sent, _stall_acted, _stall_changed = sent, acted, changed
    _stall_gen, _stall_state = gen, state
    _stall_since = now
    return false
  end
  if (now - _stall_since) < Utils.gate_seconds("force_stall", "NEURO_FORCE_STALL") then return false end
  _stall_since = now
  if (tonumber(G.NEURO.reserved_dollars) or 0) > 0 then
    local orphaned = tonumber(G.NEURO.reserved_dollars) or 0
    clear_shop_reservations()
    Metrics.incr("orphaned_dollar_reservation_recovered")
    print("[neuro-game] Recovered orphaned dollar reservation after force stall: "
      .. tostring(orphaned))
  end
  ForceState.clear_cancel_pending()
  neuro_cancel_quarantined = false
  Lifecycle.mark_force_dirty()
  return true
end

local function _step_force_liveness()
  if ForceState.liveness_expired() then
    ForceState.liveness_timeout()
  end
end

local function _step_transport_fault()
  ForceState.transport_fault_step()
end

local function _step_force_arming(state_name, now)
  -- Superseding runs above the staged-delivery gate: a state that moved underneath a buffered
  -- receipt must still tear the stale window down.
  if force_state_moved(state_name) then
    force_supersede()
    register_valid_actions(state_name)
  end
  if ConfirmationEvidence.has_staged_delivery() then return end
  if ForceState.reask_due() then
    ForceState.reask()
  end
  local cancel_entry = ForceState.cancel_pending()
  local quarantined = cancel_entry ~= nil

  if require("core.action_receipt").has_active() then return end

  local _overlay_block = G.OVERLAY_MENU and NeuroActions.is_action_valid("exit_overlay_menu")
  local _act_at = G.NEURO.last_action_at or 0
  if _act_at ~= neuro_seen_action_at and not G.NEURO.force_inflight then
    neuro_seen_action_at = _act_at
    mark_force_dirty()
  end
  if quarantined then
    neuro_cancel_quarantined = true
    return
  end
  if neuro_cancel_quarantined then
    neuro_cancel_quarantined = false
    register_valid_actions(state_name)
  end
  local _login_block = false
  if G.NEURO.login_anim and G.NEURO.login_anim.start then
    _login_block = (Utils.gate_now("login_anim_block") - G.NEURO.login_anim.start)
      < Utils.gate_seconds("login_anim_block", "NEURO_LOGIN_ANIM_BLOCK")
  end
  if not (not force_window_is_open() and G.NEURO.persona and not G.NEURO.llm_paused
    and not (G.NEURO.is_transport_saturated and G.NEURO:is_transport_saturated())
    and not _login_block) then
    return
  end
  if not (not G.NEURO.force_inflight and (_overlay_block or (not Staging.is_busy() and neuro_can_act()))) then
    return
  end
  local dirty_at = G.NEURO.force_dirty_at or S.state_changed_at_game or 0
  local debounce_now = Lifecycle.force_debounce_now()
  if neuro_last_force_attempt_at > debounce_now then
    neuro_last_force_attempt_at = debounce_now
  end
  if dirty_at > debounce_now then
    dirty_at = debounce_now
    G.NEURO.force_dirty_at = debounce_now
  end
  if neuro_last_force_attempt_at > dirty_at then
    dirty_at = neuro_last_force_attempt_at
  end
  local _bp3 = require("facts.card_util").pack_area()
  local pack_not_ready = StateKinds.is_pack_state(state_name)
    and not (_bp3 and _bp3.cards and #_bp3.cards > 0)
  if pack_not_ready then require("force.force_router").observe_pack_exit(state_name) end
  if not ((debounce_now - dirty_at) >= Lifecycle.force_debounce() and not pack_not_ready) then
    return
  end
  local hint_snapshot = snapshot_once_serials()
  FactHints.reset_pending()
  Once.begin_journal()
  local _, registration_ok = register_valid_actions(state_name)
  if not registration_ok then
    Once.rollback_journal()
    restore_once_serials(hint_snapshot)
    mark_force_dirty()
    neuro_last_force_attempt_at = debounce_now
    return
  end
  local force = NeuroDispatcher.get_force_for_state(state_name)
  if not force then
    Once.rollback_journal()
    neuro_last_force_attempt_at = debounce_now
    return
  end
  maybe_emit_permanent_rules(state_name)
  local force_context, decision_candidate = build_force_payload(state_name, force)

  if force_is_stale(state_name, force) then
    restore_once_serials(hint_snapshot)
    Once.commit_journal()
    mark_force_dirty()
    neuro_last_force_attempt_at = debounce_now
    return
  end

  emit_state_glossary(state_name)
  FactHints.flush_pending()
  neuro_last_force_attempt_at = debounce_now
  do
    local registrable = Utils.list_to_set(NeuroActions.get_valid_actions_for_state(state_name) or {})
    local kept = {}
    for _, name in ipairs(force.actions or {}) do
      if registrable[name] then kept[#kept + 1] = name end
    end
    if #kept > 0 and #kept < #force.actions then
      Metrics.incr("force_actions_narrowed_to_registered")
      force.actions = kept
    end
  end
  local payload = {
    context = force_context,
    query = force.query,
    actions = force.actions,
    priority = ForceHelpers.force_priority(state_name, _overlay_block),
    -- SPECIFICATION.md:156 lets each force decide whether its state/query outlive it. The default
    -- stays ephemeral -- corrections ride the decision they belong to -- but a builder may set
    -- force.ephemeral_context = false to have the question remembered.
    ephemeral_context = force.ephemeral_context ~= false,
    decision_candidate = decision_candidate,
  }
  if not force_arm(state_name, force.actions, build_action_set(force.actions), now, payload) then
    Once.rollback_journal()
  elseif send_armed_window() then
    Once.commit_journal()
  else
    Once.rollback_journal()
    ForceState.invalidate("unsent")
  end
end

local _neuro_frame_errors = {}
local function make_guard(prefix)
  local keys = {}
  return function(errors, label, fn, ...)
    local key = keys[label]
    if not key then
      key = prefix .. tostring(label)
      keys[label] = key
    end
    Metrics.time_begin(key)
    local ok, value = pcall(fn, ...)
    Metrics.time_end(key)
    if not ok then
      errors[#errors + 1] = tostring(label) .. ": " .. Utils.safe_tostring(value)
    end
    return ok, value
  end
end

local _neuro_guarded = make_guard("frame.neuro.")

local function clear_list(t)
  for i = #t, 1, -1 do t[i] = nil end
end

local function _step_neuro_frame(dt)
  local errors = _neuro_frame_errors
  clear_list(errors)

  _neuro_guarded(errors, "bridge update", G.NEURO.update, G.NEURO, dt)
  _neuro_guarded(errors, "context delivery", ContextDelivery.step)
  _neuro_guarded(errors, "confirmation evidence delivery", ConfirmationEvidence.step_delivery)
  _neuro_guarded(errors, "force delivery", step_force_delivery)
  _neuro_guarded(errors, "staging", Staging.update, dt)
  _neuro_guarded(errors, "receipts", NeuroDispatcher.update_receipts)
  _neuro_guarded(errors, "side tasks", _step_side_tasks, dt)

  if G.NEURO.dev_preview_active then
    if G.FUNCS and NeuroState.get_state_name then
      _neuro_guarded(errors, "showcase", function() _step_showcase_anim(NeuroState.get_state_name(), neuro_now()) end)
    end
  else
    _neuro_guarded(errors, "unsent force", _step_unsent_window_guard)
    _neuro_guarded(errors, "transport fault", _step_transport_fault)
    _neuro_guarded(errors, "force liveness", _step_force_liveness)
    _neuro_guarded(errors, "force stall", _step_force_stall)

    local state_name
    if G.FUNCS and NeuroState.get_state_name then
      local ok, sn = _neuro_guarded(errors, "state name", NeuroState.get_state_name)
      if ok then state_name = sn end
    end
    if state_name then
      local state_changed = state_name ~= G.NEURO.state
      local prev_state = G.NEURO.state
      _neuro_guarded(errors, "settled hand outcome", GameplayJournal.observe_settled, state_name)
      _neuro_guarded(errors, "joker departures", _step_joker_departures, state_name)
      _neuro_guarded(errors, "state transition", _step_state_transition, state_name, state_changed, prev_state)
      _neuro_guarded(errors, "shop settle", _step_shop_entry_settle, state_name)

      local now
      local ok_now, now_val = _neuro_guarded(errors, "neuro clock", neuro_now)
      if ok_now then now = now_val end
      if now then _neuro_guarded(errors, "showcase", _step_showcase_anim, state_name, now) end
      _neuro_guarded(errors, "force widening", _step_force_widened, state_name)
      if now then _neuro_guarded(errors, "force arming", _step_force_arming, state_name, now) end
    end
  end

  if #errors > 0 then error(table.concat(errors, "; "), 0) end
end

local function _step_track_neuro_error(neuro_success, neuro_err)
  if not neuro_success then
    local err_str = tostring(neuro_err)
    local now = Utils.gate_now("neuro_error_log_cooldown")
    if now > _neuro_err_cd or err_str ~= last_neuro_error then
      print("[neuro-game] Warning: Neuro update error: " .. err_str)
      last_neuro_error = err_str
      _neuro_err_cd = now + 5
    end
  else
    last_neuro_error = nil
    _neuro_err_cd = 0
  end
end

local _clock_epoch_seen = Utils.clock_epoch()
local function _step_clock_rewind()
  local epoch = Utils.observe_clock()
  if epoch == _clock_epoch_seen then return false end
  _clock_epoch_seen = epoch
  if not Utils.neuro_ready() then return false end
  if G.NEURO.dev_preview_active then return false end
  Lifecycle.reset_run_state()
  return true
end

local _outer_errors_buf = {}
local _outer_guard = make_guard("frame.")

function Orchestrator.update(dt, original_love_update)
  local outer_errors = _outer_errors_buf
  clear_list(outer_errors)

  _outer_guard(outer_errors, "area repair", _step_area_nil_guard)
  _outer_guard(outer_errors, "clock rewind", _step_clock_rewind)

  local autotest_ok, autotest_done = _outer_guard(outer_errors, "autotest", _step_autotest)
  if autotest_ok and autotest_done then return end

  _outer_guard(outer_errors, "game update", _step_game_update, dt, original_love_update)
  _outer_guard(outer_errors, "card draw hook", _step_hook_card_draw)
  _outer_guard(outer_errors, "bridge init", _step_bridge_init)

  -- Must stay above the error consumers below, or a persistent failure here lands in a buffer
  -- nothing reads before it is cleared.
  _outer_guard(outer_errors, "debug stats", DebugStats.sample, dt)
  _outer_guard(outer_errors, "metrics flush", Metrics.flush)

  if G and G.NEURO and G.NEURO.enabled and NeuroState then
    local neuro_success, neuro_err = pcall(_step_neuro_frame, dt)
    if #outer_errors > 0 then
      neuro_success = false
      local outer_err = table.concat(outer_errors, "; ")
      neuro_err = neuro_err and (outer_err .. "; neuro frame: " .. tostring(neuro_err)) or outer_err
    end
    _step_track_neuro_error(neuro_success, neuro_err)
  elseif #outer_errors > 0 then
    print("[neuro-game] Warning: update maintenance error: " .. table.concat(outer_errors, "; "))
  end

end

function Orchestrator.reset_run_state()
  neuro_last_force_attempt_at = 0
  neuro_seen_action_at = 0
  neuro_cancel_quarantined = false
  _stall_disarm()
  _armed_window, _armed_legal = nil, nil
  _neuro_err_cd, _game_err_cd, _game_err_last_msg = 0, 0, nil
end

if _G.NEURO_TEST then
  Orchestrator.desired_action_names = desired_action_names
  Orchestrator._neuro_can_act = neuro_can_act
  Orchestrator._step_force_arming = _step_force_arming
  Orchestrator._step_unsent_window_guard = _step_unsent_window_guard
  Orchestrator._step_force_stall = _step_force_stall
  Orchestrator._step_force_widened = _step_force_widened
  Orchestrator._step_clock_rewind = _step_clock_rewind
  Orchestrator._maybe_emit_stable_context = maybe_emit_permanent_rules
  Orchestrator._emit_state_glossary = emit_state_glossary
  Orchestrator._step_state_transition = _step_state_transition
  Orchestrator._step_shop_entry_settle = _step_shop_entry_settle
  Orchestrator._step_joker_departures = _step_joker_departures
  Orchestrator._step_area_nil_guard = _step_area_nil_guard
  Orchestrator._step_neuro_frame = _step_neuro_frame
  Orchestrator._step_bridge_init = _step_bridge_init
  Orchestrator._reset_bridge_init = function() bridge_attempted = false end
end

return Orchestrator
