local Orchestrator = {}

local Utils = require("util.utils")
local Metrics = require("util.metrics")
local S = require("hud.state")
local Rewards = require("core.rewards")
local CtxHand = require("context.ctx_hand")
local Staging = require("core.staging")
local NeuroState = require("core.state")
local StateKinds = require("core.state_kinds")
local Once = require("util.once")
local Window = require("core.window")
local Execute = require("core.execute")
local HUD = require("render.hud_overlay")
local BridgeInit = require("core.bridge_init")
local ContextDelivery = require("core.context_delivery")
local function anim() return Utils.lazy_require("render.neuro-anim") end
local neuro_now = Utils.now

local bridge_attempted = false
local LogThrottle = require("core.log_throttle")
local game_error_log = LogThrottle.new(function() return Utils.gate_now("game_error_log_cooldown") end)
local neuro_error_log = LogThrottle.new(function() return Utils.gate_now("neuro_error_log_cooldown") end)


local Lifecycle = require("core.neuro_lifecycle")
local Gate = require("core.gate")
local GameplayJournal = require("core.gameplay_journal")

local function _disable_neuro_after_boot_error()
  if G and G.NEURO then
    G.NEURO.enabled = false
    G.NEURO._bridge_init_complete = nil
  end
  Metrics.incr("neuro_disabled_after_boot_error")
  print("[neuro-game] LOAD ERROR (neuro setup): integration disabled; no startup reached the wire")
end
local function _bridge_init_retryable()
  if not (G and G.NEURO) then return false end
  local bridge = G.NEURO
  return bridge._startup_complete == true and bridge._bridge_init_complete ~= true
end

local function settle_boot(booted)
  bridge_attempted = booted or not _bridge_init_retryable()
  if not booted and bridge_attempted then _disable_neuro_after_boot_error() end
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

local function _step_game_update(dt, original_love_update)
  local update_success, update_err = true, nil
  if original_love_update then
    update_success, update_err = pcall(original_love_update, dt)
  end

  if not update_success then
    game_error_log.print("[neuro-game] Warning: Game update error: " .. tostring(update_err))
  end
end

local function _step_hook_card_draw()
  if S.neuro_card_draw_hooked then return end
  local hok, herr = pcall(HUD.hook_card_draw)
  if not hok then print("[neuro-game] UPDATE ERROR (hook_card_draw): " .. tostring(herr)) end
end

local function _step_bridge_init()
  if not bridge_attempted and G
      and not (G.NEURO and G.NEURO._reconnect_pending ~= nil) then
    local bok, initialized = pcall(BridgeInit.run)
    if not bok then
      print("[neuro-game] UPDATE ERROR (bridge setup): " .. tostring(initialized))
    else
      settle_boot(initialized ~= false)
    end
  end
  if G and G.NEURO and G.NEURO._reconnect_pending ~= nil
      and type(BridgeInit.retry_pending_reconnect) == "function" then
    pcall(BridgeInit.retry_pending_reconnect)
  end
end

local function _step_side_tasks(dt)
  if G.NEURO.input_buffer and G.NEURO.input_buffer ~= ""
    and not (G.CONTROLLER and G.CONTROLLER.text_input_hook) then
    G.NEURO.input_buffer = ""
  end
end

local function clear_shop_reservations()
  G.NEURO._reservation_epoch = (tonumber(G.NEURO._reservation_epoch) or 0) + 1
  G.NEURO.reserved_dollars = 0
end

local function _step_state_transition(state_name, state_changed, prev_state)
  if not state_changed then return end
  Gate.invalidate()
  local NA = anim()
  if NA and NA.on_state_enter then pcall(NA.on_state_enter, state_name) end
  if state_name == "BLIND_SELECT" then CtxHand.clear_last_play() end
  G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
  G.NEURO.decision_serial = (G.NEURO.decision_serial or 0) + 1
  Gate.begin_cycle()
  G.NEURO.pack_exit_pending = nil
  G.NEURO.pack_transition_stalled = nil
  G.NEURO.pack_transition_stall_key = nil
  S.state_changed_at = neuro_now()
  Window.note_state_change()
  if state_name == "SHOP" and prev_state ~= "SHOP" then
    G.NEURO.shop_pack_interrupt = nil
    Gate.arrive_in_shop()
    clear_shop_reservations()
  elseif prev_state == "SHOP" and state_name ~= "SHOP" then
    G.NEURO.shop_pack_interrupt = Gate.shop_visit_open() or nil
    clear_shop_reservations()
  end
  Lifecycle.clear_failure()
  G.NEURO.state = state_name
  if state_name == "SELECTING_HAND" and (prev_state == "SPLASH" or prev_state == "MENU" or prev_state == "RUN_SETUP") then
    G.NEURO.seed_pasted = nil
    CtxHand.clear_last_play()
  end
  if Utils.engine_settled() then Window.emit_rules(state_name) end
  local rmsg, rspoken, roccurrence = Rewards.outcome(prev_state, state_name)
  if rmsg and rspoken then
    ContextDelivery.prompt_at("outcome", {}, rmsg, { occurrence = roccurrence })
  elseif rmsg then
    ContextDelivery.event_at("outcome", {}, rmsg, { occurrence = roccurrence })
  end
end

local function _step_shop_entry_settle(state_name)
  if state_name ~= "SHOP" then return end
  Gate.bind_shop_visit()
  Gate.settle_shop_entry()
end

local function _step_joker_departures(state_name)
  for _, event in ipairs(Rewards.observe_self_expiring_jokers(state_name)) do
    ContextDelivery.event_at("joker_departure:" .. tostring(event.key), event.coords, event.text,
      { occurrence = event.occurrence })
  end
end

local function _step_showcase_anim(state_name, now)
  HUD.update_buy_showcase(now)
  HUD.update_joker_showcase(now)

  local NA = anim()
  if NA and NA.on_pack_open and StateKinds.is_pack_state(state_name) then pcall(NA.on_pack_open) end
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
  _neuro_guarded(errors, "staging", Staging.update, dt)
  _neuro_guarded(errors, "action", Execute.step)
  _neuro_guarded(errors, "side tasks", _step_side_tasks, dt)

  if G.NEURO.dev_preview_active then
    if G.FUNCS and NeuroState.get_state_name then
      _neuro_guarded(errors, "showcase", function() _step_showcase_anim(NeuroState.get_state_name(), neuro_now()) end)
    end
  else
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

      local ok_now, now = _neuro_guarded(errors, "neuro clock", neuro_now)
      if ok_now and now then _neuro_guarded(errors, "showcase", _step_showcase_anim, state_name, now) end
    end
    _neuro_guarded(errors, "force window", Window.step, state_name)
  end

  if #errors > 0 then error(table.concat(errors, "; "), 0) end
end

local function _step_track_neuro_error(neuro_success, neuro_err)
  if neuro_success then return neuro_error_log.reset() end
  neuro_error_log.print("[neuro-game] Warning: Neuro update error: " .. tostring(neuro_err))
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

  _outer_guard(outer_errors, "game update", _step_game_update, dt, original_love_update)
  _outer_guard(outer_errors, "card draw hook", _step_hook_card_draw)
  _outer_guard(outer_errors, "bridge init", _step_bridge_init)

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
  game_error_log.reset()
  neuro_error_log.reset()
  Once.rollback_journal()
end

if _G.NEURO_TEST then
  Orchestrator._step_clock_rewind = _step_clock_rewind
  Orchestrator._step_state_transition = _step_state_transition
  Orchestrator._step_shop_entry_settle = _step_shop_entry_settle
  Orchestrator._step_joker_departures = _step_joker_departures
  Orchestrator._step_neuro_frame = _step_neuro_frame
  Orchestrator._step_bridge_init = _step_bridge_init
  Orchestrator._reset_bridge_init = function() bridge_attempted = false end
end

return Orchestrator
