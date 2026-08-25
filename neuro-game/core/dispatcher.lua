local json = require("util.neuro_json")
local Actions = require("core.actions")
local Enforce = require("core.enforce")
local Utils = require("util.utils")
local Metrics = require("util.metrics")
local TxCache = require("core.tx_cache")
local Staging = require("core.staging")
local PlanTransaction = require("core.plan_transaction")
local ActionReceipt = require("core.action_receipt")
local ActionExecution = require("core.action_execution")
local GameplayJournal = require("core.gameplay_journal")
local ConfirmationEvidence = require("core.confirmation_evidence")
local ContextDelivery = require("core.context_delivery")

local ActionRegistry = require("core.action_registry")
local ActionResult = require("core.action_result")
local Dispatcher = {}

local ActionPolicy = require("core.action_policy")
Dispatcher.NON_PROGRESS_FORCE_ACTIONS = ActionPolicy.NON_PROGRESS

local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local CtxEconomy = require("facts.economy_facts")
local CardUtil = require("facts.card_util")
local mock_UIBox = GameActions.mock_UIBox

local ShopHandlers = require("handlers.shop_handlers")
local handle_buy_from_shop = ShopHandlers.handle_buy_from_shop
local handle_sell_card = ShopHandlers.handle_sell_card

local handle_use_card = require("handlers.use_card").handle_use_card
local handle_directional_card = require("handlers.directional_card").handle

local MenuHandlers = require("handlers.menu_handlers")
local handle_change_stake = MenuHandlers.handle_change_stake
local handle_change_challenge_description = MenuHandlers.handle_change_challenge_description
local handle_change_selected_back = MenuHandlers.handle_change_selected_back

local SeedRunHandlers = require("handlers.seed_run_handlers")
local handle_toggle_seeded_run = SeedRunHandlers.handle_toggle_seeded_run
local handle_paste_seed = SeedRunHandlers.handle_paste_seed
local handle_start_challenge_run = SeedRunHandlers.handle_start_challenge_run

local ACTION_SCHEMAS = {}
do
  for _, contract in ipairs(ActionRegistry.all()) do
    ACTION_SCHEMAS[contract.name] = contract.schema or {}
  end
end

local prepared = {}
local awaiting_result_write = {}
local awaiting_disposable_write = {}

local DROP_LABELS = {
  route_no_message = true,
  route_abandoned_id = true,
  route_missing_action_id = true,
  route_staged = true,
  handle_no_command = true,
  handle_abandon_command = true,
  handle_abandoned_id = true,
  handle_missing_action_id = true,
  handle_prepared_generation_abort = true,
  handle_reregister_all = true,
  handle_reregister_no_state_actions = true,
  handle_startup = true,
  handle_non_action = true,
  handle_abandon_malformed = true,
  validate_message_non_action = true,
  validate_message_abandoned_id = true,
  validate_message_missing_action_id = true,
}
local drop_ledger = {}
local drop_undeclared = {}

local function drop(label)
  if DROP_LABELS[label] then
    drop_ledger[label] = (drop_ledger[label] or 0) + 1
  else
    drop_undeclared[label] = (drop_undeclared[label] or 0) + 1
  end
  Metrics.incr("dispatch_drop_" .. tostring(label))
end

local function drop_ledger_snapshot()
  local reached, undeclared = {}, {}
  for k, v in pairs(drop_ledger) do reached[k] = v end
  for k, v in pairs(drop_undeclared) do undeclared[k] = v end
  return reached, undeclared
end

local function reset_drop_ledger()
  drop_ledger = {}
  drop_undeclared = {}
end

local ABANDONED_MAX = 64
local abandoned = {}
local abandoned_order = {}

local function abandon_ids(msg)
  local data = msg and msg.data
  if type(data) ~= "table" then return nil end
  for key in pairs(data) do
    if key ~= "ids" then return nil end
  end
  local ids = data.ids
  if type(ids) ~= "table" then return nil end
  local n = #ids
  if n == 0 or n > ABANDONED_MAX then return nil end
  local entries = 0
  for _ in pairs(ids) do entries = entries + 1 end
  if entries ~= n then return nil end
  for i = 1, n do
    if type(ids[i]) ~= "string" or ids[i] == "" then return nil end
  end
  return ids
end

local function note_abandoned(msg)
  local ids = abandon_ids(msg)
  if not ids then
    Metrics.incr("abandon_frame_malformed")
    return false
  end
  for i = 1, #ids do
    local key = ids[i]
    if not abandoned[key] then
      abandoned[key] = true
      abandoned_order[#abandoned_order + 1] = key
      while #abandoned_order > ABANDONED_MAX do
        abandoned[table.remove(abandoned_order, 1)] = nil
      end
    end
    Dispatcher.abort_prepared(key, "abandoned by the transport")
  end
  return true
end

local function is_abandoned(id)
  return id ~= nil and abandoned[tostring(id)] == true
end

local function replay_if_settled(bridge, id)
  local prior = TxCache.get(id)
  if not prior then return false end
  if bridge then
    if bridge.replay_action_result then
      bridge:replay_action_result(id, prior.ok, prior.message, prior.reason_code)
    else
      bridge:send_action_result(id, prior.ok, prior.message, prior.reason_code)
    end
  end
  return true
end

function Dispatcher.reset_run_state()
  prepared = {}
  awaiting_result_write = {}
  awaiting_disposable_write = {}
  reset_drop_ledger()
  PlanTransaction.release()
  ActionReceipt.reset("dispatcher_reset")
end

function Dispatcher.reset_transport_state(reason)
  local ids = {}
  for id in pairs(prepared) do ids[#ids + 1] = id end
  table.sort(ids)
  for i = 1, #ids do Dispatcher.abort_prepared(ids[i], reason or "transport reconnected") end
  awaiting_result_write = {}
  awaiting_disposable_write = {}
  ActionReceipt.reset(reason or "transport_reconnect")
  PlanTransaction.release()
  if G and G.NEURO then
    G.NEURO.consumed_actions = nil
    G.NEURO.consumed_action_owner = nil
    G.NEURO.pack_exit_pending = nil
    G.NEURO.reserved_dollars = nil
  end
end

function Dispatcher.reset_tx()
  TxCache.reset()
  ActionRegistry.reset()
  abandoned = {}
  abandoned_order = {}
  Dispatcher.reset_run_state()
end

local function has_transport_scoped_work()
  if next(prepared) or next(awaiting_result_write) or next(awaiting_disposable_write) then return true end
  if #TxCache.outstanding(0) > 0 then return true end
  return ActionReceipt.has_active() == true
end

local AREA_ALIASES = CardArea.AREA_ALIASES

local is_forced_action = require("core.force_state").is_forced_action

local function belongs_to_force(bridge, id, name)
  if bridge and type(bridge.is_force_answer) == "function" then
    local ok, belongs = pcall(bridge.is_force_answer, bridge, id)
    if ok then return belongs == true end
  end
  return is_forced_action(name)
end

local clear_force_inflight = require("core.force_state").clear_force_state

local function generation_matches(msg)
  local current = G and G.NEURO and tonumber(G.NEURO.run_generation)
  if current == nil or not (msg and msg.command == "action") then return true end
  local asked = tonumber(G.NEURO.force_generation)
  if asked == nil then return true, current, nil end
  return asked == current, current, asked
end

local function push_recent_action(name)
  if not (G and G.NEURO and type(name) == "string" and name ~= "") then
    return
  end

  local recent = G.NEURO.recent_actions
  if type(recent) ~= "table" then recent = {} end
  recent[#recent + 1] = name
  while #recent > 10 do
    table.remove(recent, 1)
  end
  G.NEURO.recent_actions = recent
end

local ForceHelpers = require("force.force_helpers")
local ForceState = require("core.force_state")
local ForceWindow = require("core.force_window")
local Lifecycle = require("core.neuro_lifecycle")

local function mask_hidden_name(message, card_name)
  if type(message) ~= "string" or type(card_name) ~= "string" or card_name == "" then return message end
  local i = message:find(card_name, 1, true)
  if not i then return message end
  return message:sub(1, i - 1) .. "face-down card" .. message:sub(i + #card_name)
end

local function record_action_phase(bridge, id, name, phase, details)
  if not (bridge and bridge.record_action_phase) then return true end
  local ok, recorded = pcall(bridge.record_action_phase, bridge, id, name, phase, details)
  return ok and recorded ~= false
end

local CONFIRM_FIELDS = {
  "last_voucher_reject", "last_voucher_review_serial",
  "last_sell_reject", "last_sell_review_serial",
  "last_legality_reject", "last_legality_review_serial", "last_legality_content",
  "last_quality_reject", "last_quality_review_serial", "last_quality_content",
  "last_confirm_armed", "weak_fired_serial",
  "pending_confirmation", "confirmation_delivery",
}

local function snapshot_confirmations()
  local out = {}
  if G and G.NEURO then
    for i = 1, #CONFIRM_FIELDS do out[CONFIRM_FIELDS[i]] = G.NEURO[CONFIRM_FIELDS[i]] end
  end
  return out
end

local function restore_confirmations(snapshot)
  if not (G and G.NEURO and type(snapshot) == "table") then return end
  for i = 1, #CONFIRM_FIELDS do
    local key = CONFIRM_FIELDS[i]
    G.NEURO[key] = snapshot[key]
  end
end

local function rollback_prepared_acceptance(bridge, id, name, tx, ends_pack, disposable,
    confirm_snapshot)
  record_action_phase(bridge, id, name, "aborted", { reason = "action result send failed" })
  if G and G.NEURO then
    if G.NEURO.consumed_action_owner == nil
        or G.NEURO.consumed_action_owner == tostring(id) then
      G.NEURO.consumed_actions = nil
      G.NEURO.consumed_action_owner = nil
    end
    if ends_pack and (G.NEURO.pack_exit_pending == true
        or G.NEURO.pack_exit_pending == tostring(id)) then G.NEURO.pack_exit_pending = nil end
  end
  pcall(PlanTransaction.hold, tx)
  restore_confirmations(confirm_snapshot)
  pcall(Enforce.rollback_action)
  pcall(Enforce.post_action, bridge, false)
  if disposable then
    pcall(function()
      local Orch = require("core.orchestrator")
      if Orch and Orch.register_valid_actions then Orch.register_valid_actions(G.NEURO.state or "") end
    end)
  end
end

local function expire_failure_warning()
  if not (G and G.NEURO) then return end
  local lf_at = G.NEURO.last_failed_at
  if lf_at and (Lifecycle.failure_now() - lf_at) < Lifecycle.failure_defer_window() then return end
  G.NEURO.last_failed_action = nil
  G.NEURO.last_failed_reason = nil
  G.NEURO.last_failed_correction = nil
  G.NEURO.last_failed_at = nil
end

local function send_result(bridge, id, ok, message, name, opts)
  opts = opts or {}
  local answers_force = belongs_to_force(bridge, id, name)
  local confirm = ActionResult.acknowledges(opts.reason_code, opts)
  if confirm then ok = true end
  local enhanced_message = message
  local delivered
  if bridge then
    delivered, opts.delivery_receipt = bridge:send_action_result(id, ok, enhanced_message, opts.reason_code)
    if delivered == false then return false, opts.delivery_receipt end
  end
  if opts.reason_code == "CONFIRMATION_REQUIRED" and opts.confirmation_candidate then
    pcall(ConfirmationEvidence.stage, opts.confirmation_candidate, enhanced_message,
      opts.delivery_receipt, opts.confirmation_snapshot)
  end
  local transient = ActionResult.is_transient(opts.reason_code, opts)
  TxCache.store(id, ok, enhanced_message, name, opts.reason_code)
  if not transient then
    do
      pcall(Staging.mark_settled, id, ok)
    end
  end
  if ok and not confirm then
    push_recent_action(name)
    if not opts.no_verdict then
      expire_failure_warning()
    end
  elseif confirm and not opts.no_verdict then
    expire_failure_warning()
  elseif not ok and G and name and not opts.guard
    and opts.reason_code ~= "CONFIRMATION_REQUIRED" then
    ForceState.record_failure(name, message, opts.correction)
  end
  -- A refusal (success=false) leaves the offer untouched per SPECIFICATION.md:184; quiet_force short-circuits first since a paused game hasn't acted on the offer at all.
  if opts.quiet_force then return delivered end
  if opts.preserve_force then return delivered end
  local follow_up = ActionResult.safe_to_retry(opts.reason_code, opts)
  if ok and not confirm and not answers_force and ForceState.window_is_open() then
    -- An executed answer ends the exchange whatever it named; API/README.md:23 -- withdrawing the offered names is what makes Neuro drop the force she may still hold, and SPECIFICATION.md:136-137 forbids the re-ask landing on top of it.
    ForceState.invalidate("answered_outside_offer")
  elseif ok and answers_force then
    local phase = ForceState.window()
    phase = type(phase) == "table" and phase.phase or nil
    if confirm and not follow_up
      and (phase == ForceWindow.FORCED or phase == ForceWindow.ACKNOWLEDGED) then
      ForceState.acknowledge_offer()
    elseif confirm or Dispatcher.NON_PROGRESS_FORCE_ACTIONS[name] then
      Lifecycle.mark_force_dirty()
      clear_force_inflight()
    else
      if G and G.NEURO then
        G.NEURO.decision_serial = (tonumber(G.NEURO.decision_serial) or 0) + 1
      end
      clear_force_inflight()
    end
  elseif confirm and G and G.NEURO then
    Lifecycle.mark_force_dirty()
  end

  return delivered, opts.delivery_receipt
end
local TERMINAL_LEAD = "Nothing was executed; this decision has spent its retry budget. "
local TERMINAL_TAIL = " Inspect the current state and choose from the actions available now."

local INVALID_ID_STREAK_KEY = "<invalid-action-id>"

local function reject_invalid_action_id(msg, bridge)
  if not (msg and msg.command == "action") then return false end
  local id = msg.data and msg.data.id
  if type(id) == "string" and id ~= "" then return false end
  Metrics.incr("dispatch_action_missing_id")
  if id == nil then return "silent" end
  Metrics.incr("dispatch_action_invalid_id_answered")
  local name = msg.data and msg.data.name
  local ok_note, acknowledged = pcall(Enforce.note_rejection, INVALID_ID_STREAK_KEY,
    table.concat({ type(id), tostring(name) }, "\0"))
  acknowledged = ok_note and acknowledged == true
  local message =
    "Your action id must be a non-empty string; the game cannot address a result to the value you sent. Send the action again with a valid id."
  if acknowledged then message = TERMINAL_LEAD .. message end
  send_result(bridge, id, false, message, name,
    { reason_code = "SCHEMA_INVALID", guard = true, transient = not acknowledged,
      acknowledged = acknowledged })
  return "answered"
end

-- SPECIFICATION.md:165-167 owes exactly one result per delivered action, so an abandoned id may leave
-- without one only against proof in TxCache that it was already paid.
local function settle_abandoned(bridge, msg)
  local id = msg.data.id
  Metrics.incr("action_abandoned")
  Dispatcher.abort_prepared(id, "abandoned by the transport")
  if TxCache.get(id) ~= nil then return true end
  send_result(bridge, id, false,
    "This action was cancelled by the transport before it ran; the game state is unchanged -- choose again.",
    msg.data.name, { reason_code = "ACTION_UNAVAILABLE", guard = true,
      acknowledged = true, transient = false })
  return false
end

local function reject_stale_generation(msg, bridge)
  local matches, current, asked = generation_matches(msg)
  if matches then return false end
  local id = msg and msg.data and msg.data.id
  if replay_if_settled(bridge, id) then return true end
  local name = msg and msg.data and msg.data.name
  local shown = asked == nil and "missing" or tostring(asked)
  send_result(bridge, id, true,
    string.format("This answers a question asked in run generation %s; current generation is %s.",
      shown, tostring(current)),
    name, { reason_code = "STALE_GENERATION", no_verdict = true, preserve_force = true })
  return true
end

local function reject_stale_force_alias(msg, bridge)
  if not (msg and msg.command == "action" and type(msg.data) == "table"
      and msg.data.force_wire_stale == true) then return false end
  local id, name = msg.data.id, msg.data.name
  if replay_if_settled(bridge, id) then return true end
  send_result(bridge, id, true,
    "This action answers an expired force window; it was not executed. Choose from the current state.",
    name, { reason_code = "FORCE_EXPIRED", no_verdict = true, preserve_force = true })
  Metrics.incr("stale_force_alias_acknowledged")
  return true
end

local DISPOSABLE_ACTIONS = {
  play_hand = true,
  discard_hand = true,
  select_blind = true,
  skip_blind = true,
  cash_out = true,
}

local SchemaValidate = require("util.schema_validate")
local validate_value = SchemaValidate.validate_value
local is_object_table = SchemaValidate.is_object_table

local HandHandlers = require("handlers.hand_handlers")
local handle_play_hand = HandHandlers.handle_play_hand
local handle_discard_hand = HandHandlers.handle_discard_hand

local BoardHandlers = require("handlers.board_handlers")
local handle_select_blind = BoardHandlers.handle_select_blind
local handle_set_joker_order = BoardHandlers.handle_set_joker_order
local handle_skip_blind = BoardHandlers.handle_skip_blind
local handle_set_plan = require("handlers.plan_handlers").handle_set_plan
local handle_set_joker_intents = require("handlers.plan_handlers").handle_set_joker_intents

local function persona_display_name(persona)
  return persona == "evil" and "Evil Neuro" or "Neuro-sama"
end

local function apply_persona(persona)
  local display_name = persona_display_name(persona)
  if G and G.NEURO then
    local previous = G.NEURO.persona
    G.NEURO.persona = persona
    local StateKinds = require("core.state_kinds")
    local at_menu = StateKinds.is_menu_state(require("core.state").get_state_name())
    if at_menu and not G.NEURO.login_anim then
      G.NEURO.login_anim = {
        start = Utils.now(),
        name = display_name,
        palette_ready = false,
        from = previous,
      }
    end
  end
  return "Identity set: " .. display_name .. "! Let's play!"
end

local ACTION_PREFLIGHTS = {
  choose_persona = function(data)
    local persona = data.persona
    if persona ~= "neuro" and persona ~= "evil" then
      return nil, "Choose 'neuro' for Neuro-sama or 'evil' for Evil Neuro."
    end
    if G and G.NEURO and G.NEURO.persona ~= "hiyori" then
      if G.NEURO.persona == persona then
        local same = persona_display_name(persona)
        return function() return "Identity confirmed: " .. same .. "." end
      end
      local cur = persona_display_name(G.NEURO.persona)
      return nil, "Identity already set to " .. cur .. ". Cannot change mid-session."
    end
    return function() return apply_persona(persona) end
  end,
  play_hand = handle_play_hand,
  discard_hand = handle_discard_hand,
  use_card = handle_use_card,
  use_directional_card = handle_directional_card,
  buy_from_shop = handle_buy_from_shop,
  sell_card = handle_sell_card,
  select_blind = handle_select_blind,
  skip_blind = handle_skip_blind,
  set_joker_order = handle_set_joker_order,
  set_plan = handle_set_plan,
  set_joker_intents = handle_set_joker_intents,
  setup_run = function(_data)
    return function()
      G.NEURO.deck_chosen = false
      G.NEURO.seed_pasted = nil
      local fn = G.FUNCS and G.FUNCS.setup_run
      if fn then
        local orig = G.FUNCS.can_continue
        G.FUNCS.can_continue = function() return false end
        pcall(fn, { config = {}, UIBox = mock_UIBox })
        G.FUNCS.can_continue = orig
      end
      if G and G.SETTINGS then G.SETTINGS.current_setup = 'New Run' end
      return "Opened run setup screen"
    end
  end,
  change_stake = handle_change_stake,
  change_challenge_description = handle_change_challenge_description,
  change_selected_back = handle_change_selected_back,
  toggle_seeded_run = handle_toggle_seeded_run,
  paste_seed = handle_paste_seed,
  start_challenge_run = handle_start_challenge_run,
}

function Dispatcher.skip_booster_reject_reason()
  if not CardArea.get_area("booster_pack") then
    return "No booster pack is open. Wait for a pack screen."
  end
  if require("core.transition_guard").stop_use_active() then
    return "The pack is still resolving the last action. Wait a moment, then skip."
  end
  return nil
end

local is_run_setup_overlay = ForceHelpers.is_run_setup_overlay
local function handle_simple_action(name, _data)

local gameplay_event

if name == "start_setup_run" then
  if not is_run_setup_overlay() then
    return nil, "start_setup_run requires the run setup screen to be open. Use setup_run first."
  end
  if G.SETTINGS then G.SETTINGS.current_setup = 'New Run' end
end

if name == "reroll_boss" then
  if not (G and G.blind_select) then
    return nil, "Blind select is not open. Wait for the blind select screen."
  end
  local can, enabled = CtxEconomy.can_reroll_boss()
  if not enabled then
    return nil, "Boss reroll is not available (needs the Directors Cut or Retcon voucher)."
  end
  if not can then
    return nil, string.format("Can't afford the $%d boss reroll right now.", CtxEconomy.BOSS_REROLL_COST)
  end
end
if name == "skip_booster" then
  local reason = Dispatcher.skip_booster_reject_reason()
  if reason then return nil, reason end
end
if name == "reroll_shop" or name == "toggle_shop" then
  if not (G and G.shop) then
    return nil, "Shop is not open. Wait for the shop screen."
  end
end
if name == "exit_overlay_menu" then
  if not (G and G.OVERLAY_MENU) then
    return nil, "No overlay popup is open right now."
  end
  return function()
    if G.FUNCS and type(G.FUNCS.continue_unlock) == "function"
        and G.OVERLAY_MENU and G.OVERLAY_MENU.joker_unlock_table then
      G.FUNCS.continue_unlock()
      return "Closed unlock popup"
    end
    if G.FUNCS and type(G.FUNCS.exit_overlay_menu) == "function" then
      G.FUNCS.exit_overlay_menu()
      return "Closed overlay popup/menu"
    end
    if G.CONTROLLER and type(G.CONTROLLER.key_press) == "function" then
      pcall(function() G.CONTROLLER:key_press("escape") end)
      pcall(function() G.CONTROLLER:key_press("return") end)
      return "Tried to close overlay popup/menu"
    end
    return "Overlay close function unavailable"
  end
end
  if name == "reroll_shop" then
    local round = G and G.GAME and G.GAME.current_round or {}
    local cost = math.max(0, math.floor(tonumber(round.reroll_cost) or 0))
    local free_rerolls = tonumber(round.free_rerolls or 0) or 0
    if not Actions.is_action_valid("reroll_shop") then
      local money = CtxEconomy.spendable()
      if type(cost) == "number" and cost > 0 and free_rerolls <= 0 and money < cost then
        return nil, string.format("Cannot reroll shop: need $%d, have $%d.", cost, money)
      end
      return nil, "Shop reroll is not available right now."
    end
    gameplay_event = {
      kind = "shop_reroll",
      paid = free_rerolls > 0 and 0 or cost,
      used_free_reroll = free_rerolls > 0,
    }
  end
  if name == "cash_out" then
    if not (G and G.round_eval) then
      return nil, "Cash out is not available right now."
    end
  end
  local fn = G.FUNCS and G.FUNCS[name]
  if not fn then
    return nil, "This action is not available here. Choose a different action for this screen."
  end
  return function()
    local selected_center
    if name == "start_setup_run" then
      local key = G and G.NEURO and G.NEURO.selected_back_key
      local selected_name
      selected_name, selected_center = MenuHandlers.apply_selected_back(key)
      if key and not selected_name then
        error("selected deck is no longer available: " .. tostring(key))
      end
    end
    local start_run = name == "start_setup_run" and G.FUNCS and G.FUNCS.start_run
    if selected_center and type(start_run) == "function" then
      G.FUNCS.start_run = function(e, args)
        args = args or {}
        args.deck_choice = selected_center
        return start_run(e, args)
      end
      local ok, result = pcall(fn, { config = {}, UIBox = mock_UIBox })
      G.FUNCS.start_run = start_run
      if not ok then error(result, 0) end
      return result
    end
    return fn({ config = {}, UIBox = mock_UIBox })
  end, nil, gameplay_event
end
for name, handler in pairs(ACTION_PREFLIGHTS) do
  ActionRegistry.bind_preflight(name, handler)
end
for _, name in ipairs(ActionRegistry.names()) do
  local action_name = name
  local contract = ActionRegistry.get(name)
  if contract and not contract.preflight then
    ActionRegistry.bind_preflight(action_name, function(data)
      return handle_simple_action(action_name, data)
    end)
  end
end

function Dispatcher.preflight(name, data)
  return ActionRegistry.preflight(name, data or {})
end
local function add_candidate(out, name, payload, probe)
  if G and G.NEURO then G.NEURO._candidate_probe = true end
  local ok, exec = pcall(Dispatcher.preflight, name, probe or payload)
  if G and G.NEURO then G.NEURO._candidate_probe = nil end
  if ok and type(exec) == "function" then out[#out + 1] = payload end
end

ActionRegistry.bind_candidates("buy_from_shop", function()
  local out = {}
  for _, area_name in ipairs({ "shop_jokers", "shop_vouchers", "shop_booster" }) do
    local area = G and G[area_name]
    for index, card in ipairs((area and area.cards) or {}) do
      local before = #out
      add_candidate(out, "buy_from_shop", { area = area_name, index = index })
      if #out == before and card and card.ability and card.ability.consumeable then
        add_candidate(out, "buy_from_shop", { area = area_name, index = index, use = true })
      end
    end
  end
  return out
end)

ActionRegistry.bind_candidates("sell_card", function()
  local out = {}
  local ok_l, Legality = pcall(require, "facts.boss.legality")
  if ok_l and Legality and Legality.sell_blocked_now() then
    return out
  end
  for _, area_name in ipairs({ "jokers", "consumeables" }) do
    local area = G and G[area_name]
    for index in ipairs((area and area.cards) or {}) do
      add_candidate(out, "sell_card", { area = area_name, index = index })
    end
  end
  return out
end)

ActionRegistry.bind_candidates("use_card", function()
  local out = {}
  local pack = CardUtil.pack_area()
  for _, source in ipairs({
    { name = "consumeables", area = G and G.consumeables },
    { name = "booster_pack", area = pack },
  }) do
    for index, card in ipairs((source.area and source.area.cards) or {}) do
      if not require("facts.target_contracts").get(card) then
      local payload = { area = source.name, index = index }
      local probe = payload
      local minimum, maximum = CardUtil.consumable_target_range(card)
      if maximum and maximum > 0 and not Utils.is_playing_card(card) then
        local stand_in = {}
        local hand_count = G and G.hand and G.hand.cards and #G.hand.cards or 0
        for hand_index = 1, math.min(minimum or 1, hand_count) do
          stand_in[#stand_in + 1] = hand_index
        end
        probe = { area = source.name, index = index, hand_indices = stand_in }
      end
      add_candidate(out, "use_card", payload, probe)
      end
    end
  end
  return out
end)

ActionRegistry.bind_candidates("select_blind", function()
  local key = Actions.get_selectable_blind_key()
  if not key then return {} end
  local payload = { blind = key:lower() }
  local out = {}
  add_candidate(out, "select_blind", payload)
  return out
end)

for _, name in ipairs({ "buy_from_shop", "sell_card", "select_blind" }) do
  local candidate_name = name
  ActionRegistry.bind_availability(candidate_name, function()
    return #ActionRegistry.candidates(candidate_name) > 0
  end)
end

local reject_below_gate

local function reject_schema(bridge, id, name, message)
  reject_below_gate(bridge, id, name,
    ActionResult.error("SCHEMA_INVALID", message,
      { transient = false, no_gate_rollback = true }))
  Enforce.on_error(bridge)
end

reject_below_gate = function(bridge, id, name, rejection)
  local fault = table.concat({
    tostring(rejection.reason_code or ""),
    tostring(rejection.message or ""),
  }, "\0")
  local acknowledged = Enforce.note_rejection(name, fault)
  local message = rejection.message
  if rejection.reason_code == "CONFIRMATION_REQUIRED" then
    message = tostring(message) .. " Nothing was executed; confirmation is required."
  elseif acknowledged then
    message = TERMINAL_LEAD .. tostring(message) .. TERMINAL_TAIL
  end
  local delivered, receipt = send_result(bridge, id, false, message, name, {
    reason_code = rejection.reason_code,
    acknowledged = acknowledged == true,
    correction = Enforce.take_correction and Enforce.take_correction() or nil,
    transient = rejection.transient,
    confirmation_candidate = rejection.confirmation_candidate,
    confirmation_snapshot = rejection.confirmation_snapshot,
  })
  if not rejection.no_gate_rollback then Enforce.rollback_action() end
  Enforce.post_action(bridge, false)
  return delivered, receipt
end

local function reject_unregistered_action(bridge, id, name)
  if type(name) ~= "string" or name == "" then return false end
  if ForceState.cancel_blocks(name, ActionRegistry.now()) then
    Metrics.incr("action_expired_force")
    send_result(bridge, id, true,
      string.format("Action '%s' belonged to an expired force and was not executed. Inspect the current state and choose from the actions available now.", name),
      name, { guard = true, transient = false, reason_code = "FORCE_EXPIRED",
        acknowledged = true, quiet_force = true, preserve_force = true, no_verdict = true })
    return true
  end
  if ActionRegistry.is_registered(name) then return false end
  local now = ActionRegistry.now()
  ActionRegistry.prune(now)
  local message, code, metric
  if ActionRegistry.is_withdrawn(name) then
    if ActionRegistry.is_recently_unregistered(name, now) then
      message = "Action '%s' was withdrawn moments ago, so it did not run; the offer it belonged to is gone. Choose from the actions you have now."
      metric = "action_recently_unregistered"
    else
      message = "Action '%s' was withdrawn, so it did not run; the offer it belonged to is long gone. Choose from the actions you have now."
      metric = "action_withdrawn"
    end
    code = "ACTION_UNREGISTERED"
  else
    message = "Action failed. Unknown action '%s'."
    code, metric = "ACTION_UNKNOWN", "action_unknown"
  end
  Metrics.incr(metric)
  local withdrawn = code == "ACTION_UNREGISTERED"
  local prose = string.format(message, name)
  local terminal = withdrawn
  if not withdrawn then
    -- An unknown name gets its success=false so a mistyped one can be corrected, but it must share
    -- the same bounded circuit as every other refusal: core/action_result.lua:3-8 requires the
    -- terminal form once retrying has stopped being useful.
    local ok_note, spent = pcall(Enforce.note_rejection, name, code)
    terminal = ok_note and spent == true
    if terminal then prose = TERMINAL_LEAD .. prose .. TERMINAL_TAIL end
  end
  send_result(bridge, id, withdrawn, prose, name, {
    guard = true,
    transient = not terminal,
    acknowledged = terminal,
    reason_code = code,
    quiet_force = terminal,
    preserve_force = terminal,
    no_verdict = terminal,
  })
  return true
end

local function validate_action(msg, bridge)
  local id = msg.data.id
  local name = msg.data.name

  if replay_if_settled(bridge, id) then return nil end

  if type(name) ~= "string" or name == "" then
    reject_below_gate(bridge, id, "<missing-action-name>", ActionResult.error("SCHEMA_INVALID",
      "Action name must be a non-empty string; nothing was executed.",
      { transient = true, no_gate_rollback = true }))
    return nil
  end

  if reject_unregistered_action(bridge, id, name) then return nil end

  if ActionReceipt.has_active() then
    local answers_force = belongs_to_force(bridge, id, name)
    local prose = "The previous accepted action is still being verified. Wait for the updated game state."
    -- TRANSITION_PENDING is a success=false, so it retries the force; without a circuit a stuck
    -- receipt refused every send forever (SPECIFICATION.md:184).
    local ok_note, spent = pcall(Enforce.note_rejection, name, "TRANSITION_PENDING")
    local terminal = ok_note and spent == true
    if terminal then prose = TERMINAL_LEAD .. prose .. TERMINAL_TAIL end
    send_result(bridge, id, false, prose, name, {
      guard = true, transient = not terminal, acknowledged = terminal,
      reason_code = answers_force and "TRANSITION_ACKNOWLEDGED" or "TRANSITION_PENDING" })
    return nil
  end

  if G and G.NEURO then
    ForceState.set_action_phase("validating")
  end

  local payload = msg.data.data
  local data = {}
  if type(payload) == "table" then
    if not is_object_table(payload) then
      reject_schema(bridge, id, name, "Your action payload must be a JSON object (not an array).")
      return nil
    end
    data = payload
  elseif payload and payload ~= "" then
    local ok, decoded = pcall(json.decode, payload)
    if not ok then
      local prose = "Your action payload is invalid JSON. Fix the JSON and try again."
      if tostring(decoded):find("json semantic rejection", 1, true) then
        prose = "Your action payload is valid JSON, but a list in it contains null. Send that list without null entries."
      end
      reject_schema(bridge, id, name, prose)
      return nil
    end
    if type(decoded) ~= "table" then
      reject_schema(bridge, id, name, "Your action payload must be a JSON object.")
      return nil
    end
    if not is_object_table(decoded) then
      reject_schema(bridge, id, name, "Your action payload must be a JSON object (not an array).")
      return nil
    end
    data = decoded or {}
  end
  if type(data.area) == "string" then
    data.area = AREA_ALIASES[data.area] or data.area
  end
  local schema = ACTION_SCHEMAS[name]
  local ok_schema, schema_err = validate_value(schema, data, "parameters")
  if not ok_schema then
    reject_schema(bridge, id, name, "Invalid action parameters: " .. schema_err)
    return nil
  end
  local ok_guard_call, ok_guard, guard_err, guard_transient, guard_reason =
    pcall(Enforce.pre_action, bridge, name, data)
  if not ok_guard_call then
    reject_below_gate(bridge, id, name, ActionResult.error("INTERNAL_ERROR",
      "Action guard failed: " .. tostring(ok_guard), { transient = true }))
    return nil
  end
  if not ok_guard then
    reject_below_gate(bridge, id, name, ActionResult.error(guard_reason or "ACTION_REJECTED",
      guard_err, { transient = guard_transient == true }))
    return nil
  end
  local tx, tx_err = PlanTransaction.prepare(name, data)
  if tx_err then
    reject_below_gate(bridge, id, name, ActionResult.normalize(tx_err, "PRECONDITION_FAILED"))
    return nil
  end
  data._action_id = id
  local hidden_target_name
  if name == "sell_card" then
    local ok_target, _, target_card = pcall(CardArea.validate_area_card, data)
    if ok_target and CardUtil.is_face_down(target_card) then
      hidden_target_name = Utils.safe_name_or(target_card)
    end
  end
  local exec, err, gameplay_event
  local confirm_snapshot = snapshot_confirmations()
  local ok_validator, v_exec, v_err, v_event = pcall(Dispatcher.preflight, name, data)
  if not ok_validator then
    exec, err = nil, "Action validation failed: " .. tostring(v_exec)
  else
    exec, err, gameplay_event = v_exec, v_err, v_event
  end
  if not exec then
    local fallback_code = ok_validator and "ACTION_REJECTED" or "INTERNAL_ERROR"
    local rejection = ActionResult.normalize(
      err or "This action is not available here. Choose a different action for this screen.",
      fallback_code)
    rejection.message = mask_hidden_name(rejection.message, hidden_target_name)
    if rejection.reason_code == "CONFIRMATION_REQUIRED" then
      rejection.confirmation_snapshot = confirm_snapshot
    end
    PlanTransaction.hold(tx)
    local delivered = reject_below_gate(bridge, id, name, rejection)
    if delivered == false then restore_confirmations(confirm_snapshot) end
    return nil
  end
  exec = ActionExecution.wrap(name, data, exec)
  exec = PlanTransaction.wrap(name, data, exec, tx)

  local sealed_gameplay_event
  if gameplay_event ~= nil then
    local ok_seal, sealed, seal_err = pcall(GameplayJournal.seal, gameplay_event, tostring(id))
    if ok_seal and sealed then
      sealed_gameplay_event = sealed
    else
      Metrics.incr("gameplay_journal_candidate_rejected")
      print("[neuro-game] Warning: gameplay journal candidate rejected for action "
        .. tostring(id) .. ": " .. Utils.safe_tostring(ok_seal and seal_err or sealed))
    end
  end

  local ack_snapshot = {}
  do
    local ok_snapshot, snapshot = pcall(require("core.decision_window").snapshot, name)
    if ok_snapshot and type(snapshot) == "table" then ack_snapshot = snapshot end
  end
  if not record_action_phase(bridge, id, name, "prepared") then
    Metrics.incr("action_journal_prepare_failed")
    print("[neuro-game] Warning: action journal could not record prepared id " .. tostring(id))
  end

  local ends_pack = (name == "skip_booster")
    or ((name == "use_card" or name == "use_directional_card") and type(data) == "table" and data.area == "booster_pack"
      and (tonumber(G and G.GAME and G.GAME.pack_choices) or 0) <= 1)
  -- Claiming overwrites unconditionally while releasing is owner-gated: Staging.queue validates
  -- the successor (core/staging.lua:515) before cancelling the predecessor (:538), so the job
  -- whose claim is overwritten is the one about to be cancelled.
  if ends_pack and G and G.NEURO then G.NEURO.pack_exit_pending = tostring(id) end
  local disposable_names
  if ends_pack then
    disposable_names = { "use_card", "use_directional_card", "skip_booster" }
  elseif DISPOSABLE_ACTIONS[name] then
    disposable_names = { name }
  end
  local job = {
    id = id,
    name = name,
    data = data,
    exec = exec,
    hidden_target_name = hidden_target_name,
    ack_snapshot = ack_snapshot,
    ends_pack = ends_pack,
    disposable = disposable_names ~= nil,
    bridge = bridge,
    tx = tx,
    disposable_names = disposable_names,
    confirm_snapshot = confirm_snapshot,
    gameplay_event = sealed_gameplay_event,
    result_ack_recorded = false,
  }
  if disposable_names then
    local consumed_ok, consumed = true, true
    if bridge.consume_actions then
      consumed_ok, consumed = pcall(bridge.consume_actions, bridge, disposable_names, id)
    end
    local withdraw_ok, withdrawal
    if bridge.withdraw_actions_exact then
      withdraw_ok, withdrawal = pcall(bridge.withdraw_actions_exact, bridge, disposable_names)
    elseif bridge.unregister_actions then
      local ok_legacy, accepted = pcall(bridge.unregister_actions, bridge, disposable_names)
      withdraw_ok = ok_legacy and accepted ~= false
      withdrawal = withdraw_ok and {
        status = "written", kind = "actions_unregister", names = disposable_names,
      } or nil
    else
      withdraw_ok, withdrawal = true, { status = "written", kind = "observer_no_transport" }
    end
    if not consumed_ok or consumed == false or not withdraw_ok or type(withdrawal) ~= "table" then
      rollback_prepared_acceptance(bridge, id, name, tx, ends_pack, true, confirm_snapshot)
      reject_below_gate(bridge, id, name, ActionResult.error("INTERNAL_ERROR",
        "Action could not be safely committed; the game state is unchanged -- choose again.",
        { transient = true }))
      return nil
    end
    job.disposable_delivery_receipt = withdrawal
  end
  return job
end

local function reregister_after_failure(job)
  if not (G and G.NEURO) then return end
  if G.NEURO.pack_exit_pending == true
      or G.NEURO.pack_exit_pending == tostring(job.id) then G.NEURO.pack_exit_pending = nil end
  if job.ends_pack or job.disposable then
    pcall(function()
      local Orch = require("core.orchestrator")
      if Orch and Orch.register_valid_actions then Orch.register_valid_actions(G.NEURO.state or "") end
    end)
  end
end

local function finalizer_steps(kind, id, steps)
  local errors = {}
  for i = 1, #steps do
    local step = steps[i]
    local ok, err = pcall(step[2])
    if not ok then errors[#errors + 1] = tostring(step[1]) .. ": " .. Utils.safe_tostring(err) end
  end
  if #errors > 0 then
    Metrics.incr("action_finalize_error")
    print("[neuro-game] Warning: " .. tostring(kind) .. " finalization for action "
      .. tostring(id) .. " had errors: " .. table.concat(errors, "; "))
  end
  return #errors == 0, errors
end

local function release_consumed_actions(id)
  if G and G.NEURO and (G.NEURO.consumed_action_owner == nil
      or G.NEURO.consumed_action_owner == tostring(id)) then
    G.NEURO.consumed_actions = nil
    G.NEURO.consumed_action_owner = nil
  end
end

local function finalize_failed(job, bridge, outcome, details, message)
  local id, name = job.id, job.name
  local stray_receipt = ActionReceipt.get(id)
  if stray_receipt then
    pcall(ActionReceipt.abandon, stray_receipt, outcome, details)
  end
  local reason = outcome == "ambiguous" and "execution outcome is ambiguous" or "action did not apply"
  local correction = message or ("Your accepted action '" .. tostring(name)
    .. "' did not produce a verified result. Inspect the current state and choose again.")
  finalizer_steps("failed", id, {
    { "confirmation restore", function() restore_confirmations(job.confirm_snapshot) end },
    { "metric", function() Metrics.incr("action_not_applied") end },
    { "task mode", function() require("core.task_mode").on_action(name, false) end },
    { "force rearm", function() if G and G.NEURO then ForceState.rearm() end end },
    { "optimistic correction", function() ForceState.correct_optimistic(name, reason, id, correction) end },
    { "consumed action release", function() release_consumed_actions(id) end },
    { "completed phase", function()
      record_action_phase(bridge, id, name, "completed", {
        accepted = true,
        applied = false,
        outcome = outcome,
        details = details,
      })
    end },
    { "action reregister", function() reregister_after_failure(job) end },
    { "enforcement", function() Enforce.post_action(bridge, false) end },
  })
end

local RESTATED_BY_LIVE_STATE = { set_joker_intents = true }

local function finalize_applied(job, bridge, message, details)
  local id, name = job.id, job.name
  finalizer_steps("applied", id, {
    { "gameplay journal", function()
      if not job.gameplay_event then return end
      local appended, reason = GameplayJournal.publish(job.gameplay_event)
      if not appended and reason ~= "duplicate" then error(reason, 0) end
    end },
    { "result context", function()
      if type(message) == "string" and bridge and not RESTATED_BY_LIVE_STATE[name] then
        ContextDelivery.event_at("action_applied", ContextDelivery.here(),
          "After the completed action '" .. tostring(name) .. "': "
            .. mask_hidden_name(message, job.hidden_target_name), { bridge = bridge })
      end
    end },
    { "plan context", function()
      local plan_message = PlanTransaction.take_message()
      if type(plan_message) == "string" and bridge then
        ContextDelivery.event_at("plan_commit", ContextDelivery.here(),
          "After the completed action '" .. tostring(name) .. "': " .. plan_message,
          { bridge = bridge })
      end
    end },
    { "metric", function() Metrics.incr("action_ok") end },
    { "decision acknowledgement", function()
      require("core.decision_window").acknowledge(name, job.ack_snapshot)
    end },
    { "transition guard", function() require("core.transition_guard").mark(name) end },
    { "enforcement", function() Enforce.post_action(bridge, true) end },
    { "task mode", function() require("core.task_mode").on_action(name, true) end },
    { "force answer", function()
      if G and G.NEURO then
        ForceState.mark_answered()
        G.NEURO.last_action_name = name
        Lifecycle.mark_force_dirty()
        Lifecycle.mark_action_at()
      end
    end },
    { "consumed action release", function() release_consumed_actions(id) end },
    { "completed phase", function()
      record_action_phase(bridge, id, name, "completed", {
        accepted = true,
        applied = true,
        details = details,
      })
    end },
  })
end

local function execute_action_body(job, bridge)
  local id = job.id
  local name = job.name
  if G and G.NEURO then
    ForceState.set_action_phase("executing")
  end
  record_action_phase(bridge, id, name, "executing")
  Metrics.time_begin("action_exec")
  local exec_ok, exec_result = xpcall(job.exec, function(e)
    return tostring(e)
  end)
  if not exec_ok then
    Metrics.time_end("action_exec")
    Metrics.incr("action_fail")
    finalize_failed(job, bridge, "failed", { error = tostring(exec_result) },
      "Your accepted action '" .. tostring(name) .. "' failed during execution. Inspect the current state and choose again.")
    return
  end
  Metrics.time_end("action_exec")

  if ActionReceipt.is_receipt(exec_result) then
    ActionReceipt.chain_callbacks(exec_result,
      function(receipt, details)
        finalize_applied(job, bridge, receipt.applied_message, details)
      end,
      function(receipt, details)
        finalize_failed(job, bridge, receipt.phase, details, receipt.correction)
      end)
    ActionReceipt.transition(exec_result, "acknowledged")
    ActionReceipt.transition(exec_result, "executing")
    ActionReceipt.transition(exec_result, "verifying")
    ForceState.set_action_phase("verifying")
    record_action_phase(bridge, id, name, "verifying", ActionReceipt.debug_snapshot(exec_result))
    ActionReceipt.update(ActionReceipt.now(), G and G.NEURO and G.NEURO.run_generation)
    return
  end

  if ActionReceipt.is_outcome(exec_result) then
    if exec_result.status == "applied" then
      finalize_applied(job, bridge, exec_result.message, exec_result.details)
    else
      finalize_failed(job, bridge, exec_result.status, exec_result.details, exec_result.message)
    end
    return
  end

  Metrics.incr("action_contract_violation")
  finalize_failed(job, bridge, "ambiguous", {
    reason = "missing_execution_evidence",
    result_type = type(exec_result),
  }, "The accepted action returned without verifiable execution evidence. Inspect the current state and choose again.")
end

local function execute_action(job, bridge)
  local ok, err = xpcall(execute_action_body, Utils.safe_tostring, job, bridge)
  if ok then return end
  pcall(Metrics.time_end, "action_exec")
  pcall(Metrics.incr, "action_pipeline_fail")
  finalize_failed(job, bridge, "ambiguous", { error = Utils.safe_tostring(err) },
    "Your accepted action '" .. tostring(job and job.name)
      .. "' failed in the execution pipeline. Inspect the current state and choose again.")
end

local function execute_after_result_write(job, bridge)
  local receipt = job and job.result_delivery_receipt
  if receipt and receipt.status ~= "written" then
    awaiting_result_write[tostring(job.id)] = job
    Metrics.incr("action_execution_waiting_for_result_write")
    return false
  end
  if not job.result_ack_recorded then
    record_action_phase(bridge, job.id, job.name, "acknowledged")
    job.result_ack_recorded = true
  end
  execute_action(job, bridge)
  return true
end

local function advance_accepted_job(job, bridge)
  local withdrawal = job and job.disposable_delivery_receipt
  if withdrawal and withdrawal.status ~= "written" then
    if withdrawal.status == "rejected" then
      awaiting_disposable_write[tostring(job.id)] = nil
      rollback_prepared_acceptance(bridge, job.id, job.name, job.tx, job.ends_pack, job.disposable,
        job.confirm_snapshot)
      Metrics.incr("action_disposable_write_rejected")
      return false
    end
    awaiting_disposable_write[tostring(job.id)] = job
    Metrics.incr("action_waiting_for_disposable_write")
    return false
  end

  if withdrawal and not job.disposable_withdrawal_completed then
    if bridge and bridge.complete_action_withdrawal then
      local ok, completed = pcall(bridge.complete_action_withdrawal, bridge, job.disposable_names)
      if not ok or completed == false then
        rollback_prepared_acceptance(bridge, job.id, job.name, job.tx, job.ends_pack, job.disposable,
          job.confirm_snapshot)
        Metrics.incr("action_disposable_completion_failed")
        return false
      end
    end
    job.disposable_withdrawal_completed = true
  end

  if not job.result_sent then
    local note_ok, note_err = pcall(Enforce.note_accepted, job.name)
    if not note_ok then
      Metrics.incr("action_accept_observer_error")
      print("[neuro-game] Warning: accepted-action observer failed for " .. tostring(job.name)
        .. ": " .. tostring(note_err))
    end
    local result_ok, delivered, delivery_receipt = pcall(send_result,
      bridge, job.id, true, nil, job.name)
    if not result_ok then
      rollback_prepared_acceptance(bridge, job.id, job.name, job.tx, job.ends_pack, job.disposable,
        job.confirm_snapshot)
      error(delivered, 0)
    end
    if delivered == false then
      rollback_prepared_acceptance(bridge, job.id, job.name, job.tx, job.ends_pack, job.disposable,
        job.confirm_snapshot)
      return false
    end
    job.result_sent = true
    job.result_delivery_receipt = delivery_receipt
    job.result_ack_recorded = not delivery_receipt or delivery_receipt.status == "written"
    if job.result_ack_recorded then
      record_action_phase(bridge, job.id, job.name, "acknowledged")
    end
  end

  if job.execute_requested then return execute_after_result_write(job, bridge) end
  return true
end

function Dispatcher.update_receipts(now)
  local withdrawal_ready = {}
  for key, job in pairs(awaiting_disposable_write) do
    local receipt = job.disposable_delivery_receipt
    if receipt and (receipt.status == "written" or receipt.status == "rejected") then
      withdrawal_ready[#withdrawal_ready + 1] = key
    end
  end
  table.sort(withdrawal_ready)
  for i = 1, #withdrawal_ready do
    local key = withdrawal_ready[i]
    local job = awaiting_disposable_write[key]
    awaiting_disposable_write[key] = nil
    if job then advance_accepted_job(job, job.bridge) end
  end

  local ready = {}
  for key, job in pairs(awaiting_result_write) do
    local receipt = job.result_delivery_receipt
    if receipt and receipt.status == "written" then
      ready[#ready + 1] = key
    elseif receipt and receipt.status == "rejected" then
      awaiting_result_write[key] = nil
      rollback_prepared_acceptance(job.bridge, job.id, job.name, nil, job.ends_pack, job.disposable,
        job.confirm_snapshot)
      Metrics.incr("action_result_write_rejected")
    end
  end
  table.sort(ready)
  for i = 1, #ready do
    local key = ready[i]
    local job = awaiting_result_write[key]
    awaiting_result_write[key] = nil
    if job then execute_after_result_write(job, job.bridge) end
  end
  return ActionReceipt.update(tonumber(now) or ActionReceipt.now(),
    G and G.NEURO and G.NEURO.run_generation)
end

local function raw_handle_message(msg, bridge)
  if not msg or not msg.command then
    return drop("handle_no_command")
  end
  if msg.command == "neuro-bridge/abandon" then
    if not note_abandoned(msg) then return drop("handle_abandon_malformed") end
    return drop("handle_abandon_command")
  end
  if msg.command == "action" and msg.data and is_abandoned(msg.data.id) then
    if settle_abandoned(bridge, msg) then drop("handle_abandoned_id") end
    return
  end
  local handle_id_status = reject_invalid_action_id(msg, bridge)
  if handle_id_status then
    if handle_id_status == "silent" then drop("handle_missing_action_id") end
    return
  end
  if reject_stale_force_alias(msg, bridge) then return end
  if msg.command == "action" and msg.data then
    local key = tostring(msg.data.id)
    if prepared[key] then
      local matches, current, received = generation_matches(msg)
      if matches then
        local job = prepared[key]
        prepared[key] = nil
        job.execute_requested = true
        advance_accepted_job(job, bridge)
      else
        local shown = received == nil and "missing" or tostring(received)
        Dispatcher.abort_prepared(msg.data.id,
          string.format("run generation changed (action generation %s, current %s)", shown, tostring(current)))
        drop("handle_prepared_generation_abort")
      end
      return
    end
  end
  if reject_stale_generation(msg, bridge) then return end
  if msg.command == "actions/reregister_all" then
    Lifecycle.clear_pending_confirm()
    Lifecycle.reset_context_delivery()
    local transport_session = tonumber(msg.transport_session)
    local trusted_reconnect = transport_session ~= nil
      and (not msg.transport_session_unattributed or has_transport_scoped_work())
    if transport_session and G and G.NEURO
        and transport_session ~= G.NEURO.transport_session then
      G.NEURO.transport_session = transport_session
      if trusted_reconnect then
        Lifecycle.bump_run_generation("transport reconnected")
      end
    end
    if trusted_reconnect then
      ForceState.reconnect()
    elseif transport_session then
      clear_force_inflight()
      Lifecycle.mark_force_dirty()
    end
    local State = require("core.state")
    local state_name = State.get_state_name()
    if not Actions.state_has_actions(state_name) then return drop("handle_reregister_no_state_actions") end
    local valid_action_names = Actions.get_valid_actions_for_state(state_name)
    if bridge then
      local Orchestrator = require("core.orchestrator")
      bridge:register_actions(Orchestrator.build_valid_action_definitions(state_name, valid_action_names))
    end
    return drop("handle_reregister_all")
  end
  if msg.command == "startup" then
    local session = msg.data and msg.data.session
    if type(session) == "table" and G and G.NEURO then
      G.NEURO.startup_session = {
        session_id = session.sessionId,
        character_id = session.characterId,
        display_name = session.displayName,
      }
      local character_id = session.characterId
      if (character_id == "neuro" or character_id == "evil") and G.NEURO.persona == "hiyori" then
        apply_persona(character_id)
        ForceState.invalidate("persona_from_startup")
      end
    end
    return drop("handle_startup")
  end
  if msg.command ~= "action" or not msg.data then
    return drop("handle_non_action")
  end
  local job = validate_action(msg, bridge)
  if job then
    job.execute_requested = true
    advance_accepted_job(job, bridge)
  end
end

function Dispatcher.validate_message(msg, bridge)
  if not (msg and msg.command == "action" and msg.data) then
    drop("validate_message_non_action")
    return false
  end
  if is_abandoned(msg.data.id) then
    if settle_abandoned(bridge, msg) then drop("validate_message_abandoned_id") end
    return false
  end
  local staged_id_status = reject_invalid_action_id(msg, bridge)
  if staged_id_status then
    if staged_id_status == "silent" then drop("validate_message_missing_action_id") end
    return false
  end
  if reject_stale_force_alias(msg, bridge) then return false end
  if reject_stale_generation(msg, bridge) then return false end
  local job = validate_action(msg, bridge)
  if not job then return false end
  prepared[tostring(job.id)] = job
  advance_accepted_job(job, bridge)
  return true
end

function Dispatcher.report_validation_crash(bridge, id, name, err)
  reject_below_gate(bridge, id, name, ActionResult.error("INTERNAL_ERROR",
    "Action validation failed: " .. tostring(err), { transient = true }))
end

function Dispatcher.abort_prepared(id, reason)
  local key = tostring(id)
  local job = prepared[key] or awaiting_disposable_write[key] or awaiting_result_write[key]
  if not job then return false end
  prepared[key] = nil
  awaiting_disposable_write[key] = nil
  awaiting_result_write[key] = nil
  record_action_phase(job.bridge, job.id, job.name, "aborted",
    { reason = reason or "cancelled" })
  local name = job.name
  -- SPECIFICATION.md:165-167: a prepared job is answered at prepare time; this is the last place that result can still be paid if it was not.
  if TxCache.get(id) == nil then
    send_result(job.bridge, id, false,
      "Your action '" .. tostring(name) .. "' was cancelled (" .. tostring(reason or "cancelled")
        .. ") before it ran; the game state is unchanged -- choose again.",
      name, { reason_code = "INTERNAL_ERROR", guard = true,
        acknowledged = true, transient = false })
  end
  if G and G.NEURO then
    restore_confirmations(job.confirm_snapshot)
    release_consumed_actions(id)
    ForceState.correct_optimistic(name, reason or "the action was cancelled", id,
      "Your action '" .. tostring(name) .. "' was cancelled (" .. tostring(reason or "cancelled")
        .. ") before it ran; the game state is unchanged -- choose again.")
    if job.ends_pack and (G.NEURO.pack_exit_pending == true
        or G.NEURO.pack_exit_pending == tostring(id)) then
      G.NEURO.pack_exit_pending = nil
    end
    if job.ends_pack or job.disposable then
      pcall(function()
        local Orch = require("core.orchestrator")
        if Orch and Orch.register_valid_actions then
          Orch.register_valid_actions(G.NEURO.state or "")
        end
      end)
    end
  end
  return true
end

function Dispatcher.handle_message(msg, bridge)
  local is_action = msg and msg.command == "action" and msg.data ~= nil
  if not is_action then
    return raw_handle_message(msg, bridge)
  end
  local id = msg.data.id
  local name = msg.data.name
  local answered = false
  local own = bridge and rawget(bridge, "send_action_result") or nil
  if bridge then
    local inner = bridge.send_action_result
    bridge.send_action_result = function(self, rid, ok, message, reason_code)
      local sent, receipt = inner(self, rid, ok, message, reason_code)
      answered = sent ~= false
      return sent, receipt
    end
  end
  local ok_run = xpcall(raw_handle_message, debug.traceback, msg, bridge)
  if bridge then bridge.send_action_result = own end
  if not ok_run then
    Metrics.incr("dispatch_action_throw")
    if not answered and bridge and not (id ~= nil and TxCache.get(id)) then
      pcall(reject_below_gate, bridge, id, name, ActionResult.error("INTERNAL_ERROR",
        "Internal error while handling this action; the game state is unchanged -- choose again.",
        { transient = true }))
    end
  end
end

Dispatcher.get_force_for_state = require("force.force_router").get_force_for_state

function Dispatcher.route_message(msg, bridge)
  if not msg then return drop("route_no_message") end
  if msg.command == "action" and msg.data and is_abandoned(msg.data.id) then
    if settle_abandoned(bridge, msg) then drop("route_abandoned_id") end
    return
  end
  local route_id_status = reject_invalid_action_id(msg, bridge)
  if route_id_status then
    if route_id_status == "silent" then drop("route_missing_action_id") end
    return
  end
  if reject_stale_force_alias(msg, bridge) then return end
  if reject_stale_generation(msg, bridge) then return end

  if msg.command == "action" and msg.data then
    local id = msg.data.id
    local name = msg.data.name
    local handled = false
    local ok_route = xpcall(function()
      if replay_if_settled(bridge, id) then handled = true; return end

      if G and G.NEURO and G.NEURO.llm_paused then
        local paused_msg = "Paused by operator -- nothing happened. Wait; you will be asked again shortly."
        local answers_force = belongs_to_force(bridge, id, name)
        send_result(bridge, id, true, paused_msg, name, {
          reason_code = "TRANSITION_ACKNOWLEDGED",
          quiet_force = not answers_force,
          preserve_force = not answers_force,
          safe_to_retry = answers_force,
          transient = false,
          no_verdict = true,
        })
        handled = true
        return
      end

      if Staging.should_stage(msg) then
        Staging.queue(msg, bridge)
        drop("route_staged")
        handled = true
      end
    end, debug.traceback)
    if not ok_route then
      Metrics.incr("dispatch_route_throw")
      pcall(reject_below_gate, bridge, id, name, ActionResult.error("INTERNAL_ERROR",
        "Internal error while routing this action; the game state is unchanged -- choose again.",
        { transient = true }))
      return
    end
    if handled then return end
  end

  Dispatcher.handle_message(msg, bridge)
end

function Dispatcher.get_action_handler(name)
  local contract = ActionRegistry.get(name)
  return contract and contract.preflight or nil
end

local function get_action_schema(name)
  return ACTION_SCHEMAS[name]
end

if rawget(_G, "NEURO_TEST") then
  Dispatcher._test = {
    get_action_schema = get_action_schema,
    drop_labels = DROP_LABELS,
    drop_ledger = drop_ledger_snapshot,
    reset_drop_ledger = reset_drop_ledger,
    execute_action = execute_action,
    awaiting_result_write_count = function()
      local n = 0
      for _ in pairs(awaiting_result_write) do n = n + 1 end
      return n
    end,
    awaiting_disposable_write_count = function()
      local n = 0
      for _ in pairs(awaiting_disposable_write) do n = n + 1 end
      return n
    end,
  }
end

return Dispatcher
