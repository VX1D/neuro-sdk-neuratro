local Actions = require("core.actions")
local ActionPolicy = require("core.action_policy")
local StateKinds = require("core.state_kinds")
local ForceHelpers = require("force.force_helpers")
local MenuFlow = require("force.menu_flow")
local Utils = require("util.utils")
local CardUtil = require("facts.card_util")
local Metrics = require("util.metrics")
local ActionRegistry = require("core.action_registry")
local ContextDelivery = require("core.context_delivery")
local ForceReferences = require("force.force_references")

local M = {}

local function prepend(query, note)
  return note .. (query or "")
end

local function defer_window(prefix, state_name, now, seconds)
  local generation = tonumber(G and G.NEURO and G.NEURO.run_generation) or 0
  local at = M[prefix .. "_at"]
  if M[prefix .. "_state"] ~= state_name or not at or M[prefix .. "_generation"] ~= generation or now < at then
    M[prefix .. "_at"], M[prefix .. "_state"], M[prefix .. "_generation"] = now, state_name, generation
    at = now
  end
  return (now - at) < seconds, now, generation
end

local function clear_defer(prefix)
  M[prefix .. "_at"], M[prefix .. "_state"], M[prefix .. "_generation"] = nil, nil, nil
end

local function pack_exit_suppresses(state_name)
  if not (StateKinds.is_pack_state(state_name)
      and G and G.NEURO and G.NEURO.pack_exit_pending) then
    clear_defer("_pack_exit")
    return false
  end
  local open, now, generation = defer_window("_pack_exit", nil, Utils.gate_now("router_pack_exit_defer"),
    Utils.gate_seconds("router_pack_exit_defer", "NEURO_ROUTER_DEFER_FAILSAFE"))
  if open then return true end
  local pack_area = CardUtil.pack_area()
  if not (pack_area and pack_area.cards and #pack_area.cards > 0) then
    local stalled_exit = G.NEURO.pack_exit_pending
    G.NEURO.pack_exit_pending = nil
    local diagnostic_key = tostring(generation) .. ":" .. tostring(state_name)
    if G.NEURO.pack_transition_stall_key ~= diagnostic_key then
      G.NEURO.pack_transition_stall_key = diagnostic_key
      G.NEURO.pack_transition_stalled = { state = state_name, at = now }
      Metrics.incr("pack_transition_stalled")
      print("[neuro-game] Pack area disappeared but the engine remained in "
        .. tostring(state_name) .. " past the transition deadline")
      ContextDelivery.event_at("pack_transition_stall", ContextDelivery.here("state " .. tostring(state_name)),
        "Engine transition stalled after the booster pack closed. While that condition remains, no pack action is executable and the game waits for Balatro to leave the pack state.",
        { occurrence = "exit " .. tostring(stalled_exit) })
    end
    clear_defer("_pack_exit")
    return true
  end
  G.NEURO.pack_exit_pending = nil
  clear_defer("_pack_exit")
  return false
end

M.observe_pack_exit = pack_exit_suppresses

local force_pack = require("force.force_pack").build
local FORCE_HANDLERS = {
  SELECTING_HAND = require("force.force_selecting_hand").build,
  SHOP = require("force.force_shop").build,
  BLIND_SELECT = require("force.force_blind_select").build,
  ROUND_EVAL = function()
    return { query = "Round complete. Cash out to collect the round payout.", actions = { "cash_out" } }
  end,
  GAME_OVER = MenuFlow.game_over,
  MENU = MenuFlow.menu,
}

local reported = {}
local function report(metric, state_name, detail)
  Metrics.incr(metric)
  if rawget(_G, "NEURO_TEST") then error("force query for " .. tostring(state_name) .. detail, 3) end
  local key = metric .. ":" .. tostring(state_name) .. ":" .. detail
  if not reported[key] then
    reported[key] = true
    print("[neuro-game] Force query for " .. tostring(state_name) .. detail)
  end
end

function M.report_missing_sections(state_name, query, state)
  for _, phrase in ipairs(ForceReferences.missing_sections(query, state)) do
    report("force_query_missing_section", state_name, " cites '" .. phrase .. "', which its state does not carry")
  end
end

local function report_action_names(state_name, text)
  local catalog = {}
  for _, name in ipairs(ActionRegistry.names()) do catalog[name] = true end
  for _, name in ipairs(ForceReferences.named_actions(text, catalog)) do
    local at = ForceReferences.mentions(text, name)[1][1]
    report("force_text_action_name", state_name, " names the action " .. name .. ": ..."
      .. text:sub(math.max(1, at - 80), at + #name + 40) .. "...")
  end
end

local offer

local function any_progress(list)
  for _, name in ipairs(list) do
    if not ActionPolicy.FORFEIT[name] then return true end
  end
  return false
end

local function build_force(state_name)
  if state_name == "SPLASH" then return nil end
  if pack_exit_suppresses(state_name) then
    return nil
  end
  if StateKinds.is_unlock_popup() and Actions.is_action_valid("exit_overlay_menu") then
    return {
      query = "An unlock popup is blocking the game. Close the overlay to dismiss it "
        .. "(this also unblocks starting a new run).",
      actions = { "exit_overlay_menu" },
    }
  end
  if not StateKinds.is_progression_overlay() and Actions.is_action_valid("exit_overlay_menu")
      and state_name ~= "RUN_SETUP" then
    local overlay_actions = { "exit_overlay_menu" }
    if state_name == "MENU" and Actions.is_action_valid("open_run_setup") then
      overlay_actions[#overlay_actions + 1] = "open_run_setup"
    end
    local overlay_tail = "Close the overlay"
    if overlay_actions[2] == "open_run_setup" then overlay_tail = overlay_tail .. "; opening run setup is also available" end
    local popup = "A popup is blocking the game. "
    if ForceHelpers.is_win_overlay() then
      local win_ante = require("facts.game_facts").run_progress().win_ante
      popup = string.format("You WON this run: the Ante %d Boss is beaten and the win screen is up. ", win_ante)
      overlay_tail = overlay_tail .. string.format(
        " to keep playing this same run in Endless mode, where blinds keep scaling past Ante %d until one beats you",
        win_ante)
    end
    return {
      query = popup .. overlay_tail .. ".",
      actions = overlay_actions,
    }
  end

  local handler = state_name == "RUN_SETUP" and MenuFlow.run_setup or FORCE_HANDLERS[state_name]
  if not handler and StateKinds.is_pack_state(state_name) then
    handler = force_pack
  end
  if not handler then return nil end
  return offer(state_name, handler(state_name))
end

offer = function(state_name, force)
  if type(force) ~= "table" then return nil end

  local actions = force.actions or {}
  local state_set = Actions.get_state_action_set(state_name)
  local seen = {}
  local filtered = {}
  local guard_pruned = {}
  local tools = {}

  local function take_tool(name)
    if not seen[name] then
      seen[name] = true
      tools[#tools + 1] = name
    end
  end

  for _, name in ipairs(actions) do
    if type(name) == "string" and not seen[name] and state_set[name] and Actions.is_action_valid(name) then
      if ActionPolicy.is_tool(name) then
        take_tool(name)
      elseif require("core.validate").settling(name) then
        guard_pruned[#guard_pruned + 1] = name
      else
        filtered[#filtered + 1] = name
        seen[name] = true
      end
    end
  end

  local fallback
  local absorbed = {}
  local function absorb_fallback(respect_guard)
    fallback = fallback or Actions.get_valid_actions_for_state(state_name)
    for _, name in ipairs(fallback) do
      if type(name) == "string" and not seen[name] then
        if ActionPolicy.is_tool(name) then
          take_tool(name)
        elseif not (respect_guard and require("core.validate").settling(name)) then
          filtered[#filtered + 1] = name
          seen[name] = true
          absorbed[name] = true
        end
      end
    end
  end

  local deferring = false
  local guard_note = false

  if state_name == "SELECTING_HAND" then
    local blind = G and G.GAME and G.GAME.blind
    if blind and blind.block_play and not blind.disabled then deferring = true end
  end
  if #guard_pruned > 0 then
    if #filtered > 0 and not (any_progress(guard_pruned) and not any_progress(filtered)) then
      guard_note = true
    else
      deferring = true
    end
  end

  if #filtered == 0 then
    absorb_fallback(true)
    if #filtered == 0 then deferring = true end
  end

  local guard_overridden = false
  if deferring then
    if defer_window("_guard_defer", state_name, Utils.gate_now("router_guard_defer"),
        Utils.gate_seconds("router_guard_defer", "NEURO_ROUTER_DEFER_FAILSAFE")) then
      return nil
    end
    if #filtered == 0 then
      for _, name in ipairs(guard_pruned) do
        if not seen[name] then
          filtered[#filtered + 1] = name
          seen[name] = true
        end
      end
      absorb_fallback(false)
      guard_overridden = true
    elseif #guard_pruned > 0 then
      guard_note = true
    end
  else
    clear_defer("_guard_defer")
  end

  -- A force lists every action usable in its window, named by its builder or not (action_window.gd _send_force).
  absorb_fallback(true)
  if #filtered == 0 then return nil end
  local offered, accepted, settling, listed = {}, {}, {}, {}
  for _, name in ipairs(guard_pruned) do
    if not listed[name] then listed[name] = true; settling[#settling + 1] = name end
  end
  for _, name in ipairs(filtered) do offered[#offered + 1], accepted[#accepted + 1] = name, name end
  for _, name in ipairs(tools) do
    offered[#offered + 1] = name
    local list = require("core.validate").settling(name) and settling or accepted
    list[#list + 1] = name
  end

  if guard_note and not guard_overridden then
    force.query = prepend(force.query, ForceReferences.settling_note(accepted, settling))
  end

  force.actions = offered
  force.tools = tools
  force.tools_text = ForceHelpers.tools_section(tools, force.tool_bits)
  local reviewed = require("core.gate").review_note(offered)
  if reviewed ~= "" then force.query = prepend(force.query, reviewed) end
  local StateDoc = require("context.state_doc")
  force.state_extra = StateDoc.lines(StateDoc.section("Review", ForceHelpers.review_markers(offered)),
    force.state_extra)
  if next(absorbed) and not force.query:find("Your move:", 1, true) then
    local bits = {}
    for _, name in ipairs(filtered) do
      if absorbed[name] and not force.query:find(ActionRegistry.phrase(name), 1, true) then
        bits[#bits + 1] = ActionRegistry.prompt(name)
      end
    end
    force.query = force.query .. ForceHelpers.your_move(bits)
  end
  force.query = ForceHelpers.with_tools(force.query, force.tools_text)
  local Window = require("core.window")
  local stalled = Window.liveness_repeats(state_name)
  if stalled >= Window.LIVENESS_ESCALATE_AT then
    force.query = prepend(force.query, "NOTE: " .. Window.liveness_note(stalled) .. " ")
  end
  return force
end

function M.get_force_for_state(state_name)
  local force = build_force(state_name)
  if type(force) == "table" then
    report_action_names(state_name, force.query)
    report_action_names(state_name, force.tools_text)
    report_action_names(state_name, force.state_extra)
  end
  return force
end

return M
