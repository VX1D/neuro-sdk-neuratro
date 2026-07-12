local json = require("util.neuro_json")
local Actions = require("core.actions")
local Enforce = require("core.enforce")
local Utils = require("util.utils")
local Metrics = require("util.metrics")
local safe_name_or = Utils.safe_name_or

local Dispatcher = {}

local ActionPolicy = require("core.action_policy")
Dispatcher.NON_PROGRESS_FORCE_ACTIONS = ActionPolicy.NON_PROGRESS

local CardArea = require("facts.card_area_util")
local CtxEconomy = require("context.ctx_economy")
local mock_UIBox = CardArea.mock_UIBox

local ShopHandlers = require("handlers.shop_handlers")
local handle_buy_from_shop = ShopHandlers.handle_buy_from_shop
local handle_sell_card = ShopHandlers.handle_sell_card

local handle_use_card = require("handlers.use_card").handle_use_card

local MenuHandlers = require("handlers.menu_handlers")
local handle_change_stake = MenuHandlers.handle_change_stake
local handle_change_challenge_description = MenuHandlers.handle_change_challenge_description
local handle_change_selected_back = MenuHandlers.handle_change_selected_back
local handle_change_viewed_back = MenuHandlers.handle_change_viewed_back
local handle_change_viewed_collab = MenuHandlers.handle_change_viewed_collab

local InfoHandlers = require("handlers.info_handlers")
local safe_context_result = InfoHandlers.safe_context_result

local function context_info(getter, label)
  return function(_)
    return function()
      local Context = require("context.context")
      return safe_context_result(Context[getter] or function() return { label } end, label)
    end
  end
end
local handle_scoring_explanation = InfoHandlers.handle_scoring_explanation
local handle_shop_context = InfoHandlers.handle_shop_context
local handle_blind_info = InfoHandlers.handle_blind_info
local handle_hand_levels_info = InfoHandlers.handle_hand_levels_info
local handle_full_game_context = InfoHandlers.handle_full_game_context
local handle_quick_status = InfoHandlers.handle_quick_status
local handle_simulate_hand = InfoHandlers.handle_simulate_hand

local SeedRunHandlers = require("handlers.seed_run_handlers")
local handle_toggle_seeded_run = SeedRunHandlers.handle_toggle_seeded_run
local handle_paste_seed = SeedRunHandlers.handle_paste_seed
local handle_start_challenge_run = SeedRunHandlers.handle_start_challenge_run

local ACTION_SCHEMAS = {}
do
  local defs = Actions.get_static_actions()
  for i = 1, #defs do
    ACTION_SCHEMAS[defs[i].name] = defs[i].schema or {}
  end
end

local TX_CACHE_MAX = 256

-- defer window protects a just-set deferred failure from a later success; divides by game speed (delays fire on the TOTAL clock)
local _Tuning = require("core.tuning")
local function defer_window()
  local sp = _Tuning.game_speed()
  return math.max(3,
    _Tuning.get("NEURO_SHOP_BUY_DELAY") / sp + 1,
    _Tuning.get("NEURO_PACK_PICK_DELAY") / sp + 1)
end
local tx_settled = {}
local tx_settled_order = {}
local _last_reregister_at = nil
local _last_reregister_sig = nil

local function tx_key(action_id)
  if action_id == nil then return nil end
  return tostring(action_id)
end

local function tx_get(action_id)
  local k = tx_key(action_id)
  if not k then return nil end
  return tx_settled[k]
end

local function replay_if_settled(bridge, id)
  local prior = tx_get(id)
  if not prior then return false end
  if bridge then bridge:send_action_result(id, prior.ok, prior.message) end
  return true
end

local function tx_store(action_id, ok, message, name)
  local k = tx_key(action_id)
  if not k then return end
  if not tx_settled[k] then
    tx_settled_order[#tx_settled_order + 1] = k
  end
  tx_settled[k] = {
    ok = not not ok,
    message = message,
    name = name,
  }
  while #tx_settled_order > TX_CACHE_MAX do
    local drop = table.remove(tx_settled_order, 1)
    tx_settled[drop] = nil
  end
end

-- let staging record its own results in the shared idempotency cache so a retry short-circuits instead of re-executing
function Dispatcher.record_tx(id, ok, message, name)
  tx_store(id, ok, message, name)
end

function Dispatcher.reset_tx()
  for k in pairs(tx_settled) do tx_settled[k] = nil end
  for i = #tx_settled_order, 1, -1 do tx_settled_order[i] = nil end
  _last_reregister_at = nil
  _last_reregister_sig = nil
end

local function session_matches(bridge, msg)
  if not bridge or not bridge.session_id then
    return true
  end
  if not msg then
    return true
  end
  local sid = msg.session_id
  if sid == nil and msg.data and msg.data.session_id ~= nil then
    sid = msg.data.session_id
  end
  if sid == nil then
    return true
  end
  return tostring(sid) == tostring(bridge.session_id)
end

local AREA_ALIASES = CardArea.AREA_ALIASES

local is_forced_action = require("force.force_helpers").is_forced_action

local clear_force_inflight = require("force.force_helpers").clear_force_state

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

  local hist = G.NEURO.action_history
  if type(hist) ~= "table" then hist = {} end
  hist[#hist + 1] = name
  while #hist > 20 do
    table.remove(hist, 1)
  end
  G.NEURO.action_history = hist
end

local ForceHelpers = require("force.force_helpers")
local Lifecycle = require("core.neuro_lifecycle")
local function send_result(bridge, id, ok, message, name, opts)
  opts = opts or {}
  local enhanced_message = message
  if bridge then
    if ok and not message then
      enhanced_message = "Action executed successfully"
      if name == "buy_from_shop" and G and G.GAME then
        local reserved = tonumber(G.NEURO and G.NEURO.reserved_dollars or 0) or 0
        enhanced_message = enhanced_message .. string.format(". Money after purchase: $%d", (G.GAME.dollars or 0) - reserved)
      end
    end
    bridge:send_action_result(id, ok, enhanced_message)
  end
  -- transient rejections are retryable; caching one replays the stale "please wait" on a same-id retry
  if not opts.transient then
    tx_store(id, ok, enhanced_message, name)
    do
      local ok_stage, Staging = pcall(require, "core.staging")
      if ok_stage and Staging and Staging.mark_settled then
        pcall(Staging.mark_settled, id, ok)
      end
    end
  end
  if ok then
    push_recent_action(name)
    if G and G.NEURO then
      -- do not wipe a just-set deferred failure (buy/use fails ~2.2s later) before its warning surfaces
      local now = Utils.now()
      local lf_at = G.NEURO.last_failed_at
      if not (lf_at and (now - lf_at) < defer_window()) then
        G.NEURO.last_failed_action = nil
        G.NEURO.last_failed_reason = nil
        G.NEURO.last_failed_at = nil
      end
    end
  elseif G and name and not opts.guard then
    ForceHelpers.record_failure(name, message)
  end
  if is_forced_action(name) then
    -- a non-progress (info/preview) answer leaves the decision pending: drop the fingerprint or the unchanged force is deduped and never re-sent
    if not ok or Dispatcher.NON_PROGRESS_FORCE_ACTIONS[name] then
      Lifecycle.mark_force_dirty()
    end
    clear_force_inflight()
  elseif not ok and opts.guard and G and G.NEURO then
    -- rejected out-of-set answer (stale reply after the state moved): re-arm now, don't wait 12s for the stall watchdog
    Lifecycle.mark_force_dirty()
    clear_force_inflight()
  end
end

local SchemaValidate = require("util.schema_validate")
local validate_value = SchemaValidate.validate_value
local is_object_table = SchemaValidate.is_object_table

local HandHandlers = require("handlers.hand_handlers")
local handle_play_hand = HandHandlers.handle_play_hand
local handle_discard_hand = HandHandlers.handle_discard_hand

local function handle_select_blind(data)
  local blind = data.blind
  if not G or not G.P_BLINDS then
    return nil, "Game is not ready yet."
  end
  local sel_key = Actions.get_selectable_blind_key()   -- "Small"/"Big"/"Boss" or nil
  local function is_selectable(key)
    return sel_key == key
  end
  local current = sel_key and sel_key:lower() or nil

  if current and blind ~= current then
    return nil, string.format("'%s' is not selectable right now. Currently selectable: %s — use select_blind with blind='%s'.", tostring(blind), current, current)
  end

  if blind == "small" then
    if not is_selectable("Small") then
      return nil, "Small blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local small_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
      and G.GAME.round_resets.blind_choices.Small
    local bl_small = (small_key and G.P_BLINDS[small_key]) or G.P_BLINDS.bl_small
    if not bl_small then
      return nil, "Small blind definition not found."
    end
    local blind_name = bl_small.name or "Small Blind"
    return function()
      local fn = G.FUNCS and G.FUNCS.select_blind
      if fn then fn({ config = { ref_table = bl_small }, UIBox = mock_UIBox }) end
      return "Selected: " .. blind_name
    end
  elseif blind == "big" then
    if not is_selectable("Big") then
      return nil, "Big blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local big_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices
      and G.GAME.round_resets.blind_choices.Big
    local bl_big = (big_key and G.P_BLINDS[big_key]) or G.P_BLINDS.bl_big
    if not bl_big then
      return nil, "Big blind definition not found."
    end
    local blind_name = bl_big.name or "Big Blind"
    return function()
      local fn = G.FUNCS and G.FUNCS.select_blind
      if fn then fn({ config = { ref_table = bl_big }, UIBox = mock_UIBox }) end
      return "Selected: " .. blind_name
    end
  elseif blind == "boss" then
    if not is_selectable("Boss") then
      return nil, "Boss blind is not available right now. Current selectable: " .. tostring(current or "none") .. "."
    end
    local boss_key = G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_choices and
      G.GAME.round_resets.blind_choices.Boss
    local boss = boss_key and G.P_BLINDS[boss_key] or nil
    if boss then
      local boss_name = boss.name or "Boss Blind"
      return function()
        local fn = G.FUNCS and G.FUNCS.select_blind
        if fn then fn({ config = { ref_table = boss }, UIBox = mock_UIBox }) end
        return "Selected: " .. boss_name
      end
    end
    return nil, "Boss blind definition not found."
  end
  return nil, "Blind must be one of: small, big, boss. Currently selectable: " .. tostring(current or "none") .. "."
end

local function handle_set_joker_order(data)
  if not G or not G.jokers or not G.jokers.cards then
    return nil, "Jokers are not available yet."
  end
  local from_idx = data.from_index
  local to_idx = data.to_index
  if not from_idx or not to_idx then
    return nil, "Both from_index and to_index are required."
  end
  local njok = #G.jokers.cards
  local ok_from, err_from = CardArea.validate_index(from_idx, njok, "from_index", "jokers")
  if not ok_from then return nil, err_from end
  local ok_to, err_to = CardArea.validate_index(to_idx, njok, "to_index", "jokers")
  if not ok_to then return nil, err_to end
  if from_idx == to_idx then
    return nil, "from_index and to_index are the same."
  end
  return function()
    local card = G.jokers.cards[from_idx]
    local card_name = safe_name_or(card)
    table.remove(G.jokers.cards, from_idx)
    table.insert(G.jokers.cards, to_idx, card)
    if G.jokers.set_ranks then G.jokers:set_ranks() end
    if G.jokers.align_cards then G.jokers:align_cards() end
    return string.format("Moved %s from position %d to %d", card_name, from_idx, to_idx)
  end
end

local function handle_skip_blind(_data)
  if not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.blind_states) then
    return nil, "Blind selection is not ready yet."
  end

  local on_deck = Actions.get_selectable_blind_key()

  if on_deck == "Boss" then
    return nil, "Skipping boss blind is not supported. Select the boss blind instead."
  end
  if on_deck ~= "Small" and on_deck ~= "Big" then
    return nil, "No skippable blind is currently selectable."
  end

  local opt = G.blind_select_opts and G.blind_select_opts[string.lower(on_deck)]
  if not (opt and type(opt.get_UIE_by_ID) == "function") then
    return nil, "Blind UI option is unavailable; cannot skip right now."
  end

  local tag = opt:get_UIE_by_ID("tag_container")
  if not (tag and tag.config and tag.config.ref_table) then
    return nil, "Skip reward tag is unavailable; cannot skip right now."
  end

  return function()
    local before = G.GAME and G.GAME.blind_on_deck or on_deck
    local fn = G.FUNCS and G.FUNCS.skip_blind
    if fn then fn({ UIBox = opt, config = {} }) end
    local after = G.GAME and G.GAME.blind_on_deck or before
    return string.format("Skipped %s blind. Next selectable: %s", tostring(before), tostring(after))
  end
end

local PARAM_VALIDATORS = {
  choose_persona = function(data)
    local persona = data.persona
    if persona ~= "neuro" and persona ~= "evil" then
      return nil, "Choose 'neuro' for Neuro-sama or 'evil' for Evil Neuro."
    end
    if G and G.NEURO and G.NEURO.persona ~= "hiyori" then
      local cur = G.NEURO.persona == "evil" and "Evil Neuro" or "Neuro-sama"
      return nil, "Identity already set to " .. cur .. ". Cannot change mid-session."
    end
    return function()
      if G and G.NEURO then
        local display_name = persona == "evil" and "Evil Neuro" or "Neuro-sama"
        G.NEURO.persona = persona
        local StateKinds = require("core.state_kinds")
        local at_menu = StateKinds.is_menu_state(require("core.state").get_state_name())
        if at_menu and not G.NEURO.login_anim then
          G.NEURO.login_anim = {
            start = Utils.now(),
            name = display_name,
            palette_ready = false,
          }
        end
      end
      local name = persona == "evil" and "Evil Neuro" or "Neuro-sama"
      return "Identity set: " .. name .. "! Let's play!"
    end
  end,
  play_hand = handle_play_hand,
  discard_hand = handle_discard_hand,
  use_card = handle_use_card,
  buy_from_shop = handle_buy_from_shop,
  sell_card = handle_sell_card,
  select_blind = handle_select_blind,
  skip_blind = handle_skip_blind,
  set_joker_order = handle_set_joker_order,
  scoring_explanation = handle_scoring_explanation,
  simulate_hand = handle_simulate_hand,
  shop_context = handle_shop_context,
  blind_info = handle_blind_info,
  hand_levels_info = handle_hand_levels_info,
  full_game_context = handle_full_game_context,
  quick_status = handle_quick_status,
  consumables_info = context_info("get_consumables_info", "Consumables info not available"),
  hand_details = context_info("get_hand_details", "Hand details not available"),
  owned_vouchers = context_info("get_owned_vouchers", "Vouchers info not available"),
  round_history = context_info("get_round_history", "Round history not available"),
  help = function(_data)
    return function()
      local state_name = require("core.state").get_state_name()
      local descs = {}
      for _, d in ipairs(Actions.get_static_actions()) do descs[d.name] = d.description end
      local names = Actions.get_action_names_for_state(state_name) or {}
      local lines = { "=== AVAILABLE COMMANDS (" .. tostring(state_name) .. ") ===" }
      for _, name in ipairs(names) do
        lines[#lines + 1] = name .. (descs[name] and (" - " .. descs[name]) or "")
      end
      return table.concat(lines, "\n")
    end
  end,
  setup_run = function(_data)
    return function()
      G.NEURO.deck_chosen = false
      local fn = G.FUNCS and G.FUNCS.setup_run
      if fn then
        local orig = G.FUNCS.can_continue
        G.FUNCS.can_continue = function() return false end
        fn({ config = {}, UIBox = mock_UIBox })
        G.FUNCS.can_continue = orig
      end
      if G and G.SETTINGS then G.SETTINGS.current_setup = 'New Run' end
      return "Opened run setup screen"
    end
  end,
  change_stake = handle_change_stake,
  change_challenge_description = handle_change_challenge_description,
  change_selected_back = handle_change_selected_back,
  change_viewed_back = handle_change_viewed_back,
  change_viewed_collab = handle_change_viewed_collab,
  toggle_seeded_run = handle_toggle_seeded_run,
  paste_seed = handle_paste_seed,
  start_challenge_run = handle_start_challenge_run,
  get_poker_hand_information = context_info("get_poker_hand_info", "Poker hand info not available"),
  joker_info = context_info("get_joker_info", "Joker info not available"),
  card_modifiers_information = context_info("get_card_modifiers", "Card modifiers info not available"),
  deck_type = context_info("get_deck_types", "Deck type info not available"),
}

local is_run_setup_overlay = ForceHelpers.is_run_setup_overlay
local function handle_simple_action(name, _data)

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
  local bp = CardArea.get_area("booster_pack")
  if not bp then
    return nil, "No booster pack is open. Wait for a pack screen."
  end
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
    -- is_action_valid owns the full rule; only add a money-specific reason here, don't duplicate it
    if not Actions.is_action_valid("reroll_shop") then
      local money = CtxEconomy.spendable()
      local cost = (G and G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost) or 0
      local free_rerolls = tonumber(G and G.GAME and G.GAME.current_round and G.GAME.current_round.free_rerolls or 0) or 0
      if type(cost) == "number" and cost >= 0 and free_rerolls <= 0 and money < cost then
        return nil, string.format("Cannot reroll shop: need $%d, have $%d.", cost, money)
      end
      return nil, "Shop reroll is not available right now."
    end
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
  -- never forward client-supplied args/config/ref_*: they aim engine callbacks at arbitrary UI, crashing after ok=true is sent
  return function()
    fn({ config = {}, UIBox = mock_UIBox })
  end
end

local function raw_handle_message(msg, bridge)
  if not msg or not msg.command then
    return
  end
  if not session_matches(bridge, msg) then
    return
  end
  if msg.command == "actions/reregister_all" then
    local now = Utils.now()
    local State = require("core.state")
    local state_name = State.get_state_name()
    local valid_action_names = Actions.get_valid_actions_for_state(state_name)
    -- throttle only repeat re-syncs with the same state and validity; a real state or validity change must always pass or stale actions stay registered
    local reregister_sig = state_name .. "|" .. table.concat(valid_action_names, ",")
    if _last_reregister_at and (now - _last_reregister_at) < 2.0 and reregister_sig == _last_reregister_sig then
      return
    end
    _last_reregister_at = now
    _last_reregister_sig = reregister_sig
    if bridge then
      local all_actions = Actions.get_static_actions()
      local filtered_actions = {}
      local valid_set = {}
      for _, name in ipairs(valid_action_names) do
        valid_set[name] = true
      end

      for _, action_def in ipairs(all_actions) do
        if valid_set[action_def.name] then
          table.insert(filtered_actions, action_def)
        end
      end

      bridge:register_actions(filtered_actions)
    end
    return
  end
  if msg.command ~= "action" or not msg.data then
    return
  end
  local id = msg.data.id
  local name = msg.data.name
  -- hook so a deferred failure (buy/use ~2.2s later) drops its own optimistic ok=true so a retry re-executes
  if G and G.NEURO and not G.NEURO.invalidate_tx then
    G.NEURO.invalidate_tx = function(aid)
      if aid == nil then return end
      local k = tostring(aid)
      tx_settled[k] = nil
      -- also drop from the LRU order list, else phantom keys count toward the cap and shrink the cache
      for i = #tx_settled_order, 1, -1 do
        if tx_settled_order[i] == k then table.remove(tx_settled_order, i); break end
      end
    end
  end

  if replay_if_settled(bridge, id) then return end

  if G and G.NEURO then
    ForceHelpers.set_action_phase("validating")
  end

  local ok_guard_call, ok_guard, guard_err, guard_transient = pcall(Enforce.pre_action, bridge, name)
  if not ok_guard_call then
    -- transient=true: a guard THROW must not be cached, or a redelivery replays the stale rejection forever
    send_result(bridge, id, false, "Action guard failed: " .. tostring(ok_guard), name, { guard = true, transient = true })
    return
  end
  if not ok_guard then
    send_result(bridge, id, false, guard_err, name, { guard = true, transient = guard_transient })
    return
  end
  local payload = msg.data.data
  local data = {}
  if type(payload) == "table" then
    -- tolerate an already-parsed object: other SDK bridges may hand the parsed object, not a JSON string
    if not is_object_table(payload) then
      send_result(bridge, id, false, "Your action payload must be a JSON object (not an array).", name)
      Enforce.on_error(bridge)
      return
    end
    data = payload
  elseif payload and payload ~= "" then
    local ok, decoded = pcall(json.decode, payload)
    if not ok then
      send_result(bridge, id, false, "Your action payload is invalid JSON. Fix the JSON and try again.", name)
      Enforce.on_error(bridge)
      return
    end
    if type(decoded) ~= "table" then
      send_result(bridge, id, false, "Your action payload must be a JSON object.", name)
      Enforce.on_error(bridge)
      return
    end
    if not is_object_table(decoded) then
      send_result(bridge, id, false, "Your action payload must be a JSON object (not an array).", name)
      Enforce.on_error(bridge)
      return
    end
    data = decoded or {}
  end
  -- normalize area spelling (consumables -> consumeables) before validation so a correct-english name is not rejected
  if type(data.area) == "string" then
    data.area = AREA_ALIASES[data.area] or data.area
  end
  local schema = ACTION_SCHEMAS[name]
  local ok_schema, schema_err = validate_value(schema, data, "parameters")
  if not ok_schema then
    send_result(bridge, id, false, "Invalid action parameters: " .. schema_err, name)
    Enforce.post_action(bridge, false)
    return
  end
  data._action_id = id
  local validator = PARAM_VALIDATORS[name]
  local exec, err
  if validator then
    local ok_validator, v_exec, v_err = pcall(validator, data)
    if not ok_validator then
      exec, err = nil, "Action validation failed: " .. tostring(v_exec)
    else
      exec, err = v_exec, v_err
    end
  elseif G and G.FUNCS and G.FUNCS[name] then
    exec, err = handle_simple_action(name, data)
  else
    exec, err = nil, "This action is not available here. Choose a different action for this screen."
  end
  if not exec then
    send_result(bridge, id, false, err or "This action is not available here. Choose a different action for this screen.", name)
    Enforce.post_action(bridge, false)
    return
  end

  send_result(bridge, id, true, nil, name)

  if G and G.NEURO then
    ForceHelpers.set_action_phase("executing")
  end
  Metrics.time_begin("action_exec")
  local exec_ok, exec_result = xpcall(exec, function(e)
    return tostring(e)
  end)
  if not exec_ok then
    -- cannot send a second result; log and move on (exec crash, not a param error)
    Metrics.time_end("action_exec")
    Metrics.incr("action_fail")
    if G and G.NEURO then
      G.NEURO.force_dirty = true
      G.NEURO.last_force_fingerprint = nil
      ForceHelpers.record_failure(name, "internal error during execution")
      -- drop the optimistic ok=true from the tx cache so a resend re-executes instead of replaying a success for a crashed action
      if G.NEURO.invalidate_tx then G.NEURO.invalidate_tx(id) end
      -- clear inflight like the success path, else a throwing action strands force_inflight until the ~12s watchdog
      clear_force_inflight()
    end
    if bridge and bridge.send_context then
      pcall(bridge.send_context, bridge,
        "Your last action '" .. tostring(name) .. "' failed to apply (internal error); game state is unchanged — choose again.", true)
    end
    Enforce.post_action(bridge, false)
    return
  end
  -- pcall so a send throw can't skip the time_end below and leak the perf timer
  if type(exec_result) == "string" and bridge then
    pcall(bridge.send_context, bridge, exec_result, true)
  end
  Metrics.time_end("action_exec")
  Metrics.incr("action_ok")
  Enforce.post_action(bridge, true)
  if not (G and G.NEURO) then
    return
  end
  if G.NEURO.force_inflight then
    G.NEURO.force_last_result = "answered"
  end
  G.NEURO.last_action_name = name
  if name == "exit_overlay_menu" then
    G.NEURO.last_force_fingerprint = nil
  end
  local current_state = G.NEURO.state or ""
  if current_state == "SHOP" then
    if name == "reroll_shop" then
      G.NEURO.shop_reroll_count = (G.NEURO.shop_reroll_count or 0) + 1
    elseif name == "toggle_shop" then
      G.NEURO.shop_reroll_count = nil
    end
  end
  Lifecycle.mark_force_dirty(false)  -- bump only; this path intentionally keeps the fingerprint
  local setup_states = { MENU = true, RUN_SETUP = true, SPLASH = true }
  if setup_states[current_state] then
    G.NEURO.reforce_count = (G.NEURO.reforce_count or 0) + 1
    clear_force_inflight()
  else
    G.NEURO.reforce_count = 0
    if G.NEURO.force_inflight then
      -- clear inflight and fingerprint so a preview answering outside the force set does not strand it until the stall watchdog
      if Dispatcher.NON_PROGRESS_FORCE_ACTIONS[name] then
        G.NEURO.last_force_fingerprint = nil
      end
      clear_force_inflight()
    end
  end
  -- never lower a future-scheduled last_action_at (pack pick sets now+3.0); overwriting with now causes duplicate picks
  local new_lat = Utils.now()
  if not G.NEURO.last_action_at or new_lat > G.NEURO.last_action_at then
    G.NEURO.last_action_at = new_lat
  end
end

-- SDK contract: every inbound action must emit EXACTLY ONE result; convert any throw into one terminal result (emit iff none emitted, never propagate)
function Dispatcher.handle_message(msg, bridge)
  local is_action = msg and msg.command == "action" and msg.data ~= nil
  if not is_action then
    -- non-action commands never emit action/result; run directly
    return raw_handle_message(msg, bridge)
  end
  local id = msg.data.id
  local name = msg.data.name
  local answered = false
  local own = bridge and rawget(bridge, "send_action_result") or nil
  if bridge then
    local inner = bridge.send_action_result
    bridge.send_action_result = function(self, rid, ok, message)
      answered = true
      return inner(self, rid, ok, message)
    end
  end
  local ok_run = xpcall(raw_handle_message, debug.traceback, msg, bridge)
  if bridge then bridge.send_action_result = own end
  if not ok_run then
    Metrics.incr("dispatch_action_throw")
    if not answered and bridge then
      -- zero-result would hang Neuro forever: emit the single terminal result here
      pcall(send_result, bridge, id, false,
        "Internal error while handling this action; the game state is unchanged -- choose again.", name)
    end
    -- if already answered: swallow, or a propagating error lets Staging.update emit a duplicate result
  end
end

Dispatcher.get_force_for_state = require("force.force_router").get_force_for_state

function Dispatcher.route_message(msg, bridge)
  if not msg then return end
  if not session_matches(bridge, msg) then return end

  if msg.command == "action" and msg.data then
    local id = msg.data.id
    local name = msg.data.name
    local handled = false
    local ok_route = xpcall(function()
      if replay_if_settled(bridge, id) then handled = true; return end

      -- operator pause (F8 panel): reject without settling the id so a post-resume retry runs normally
      if G and G.NEURO and G.NEURO.llm_paused then
        if bridge and bridge.send_action_result then
          bridge:send_action_result(id, false, "Paused by operator — retry shortly.")
        end
        handled = true; return
      end

      local ok_stage, Staging = pcall(require, "core.staging")
      if ok_stage and Staging and Staging.should_stage and Staging.should_stage(msg) then
        Staging.queue(msg, bridge)
        handled = true
      end
    end, debug.traceback)
    if not ok_route then
      Metrics.incr("dispatch_route_throw")
      pcall(send_result, bridge, id, false,
        "Internal error while routing this action; the game state is unchanged -- choose again.", name)
      return
    end
    if handled then return end
  end

  Dispatcher.handle_message(msg, bridge)
end

function Dispatcher.get_action_handler(name)
  return PARAM_VALIDATORS[name]
end

return Dispatcher
