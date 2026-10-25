require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("tool-contract-frames")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Policy = require("core.action_policy")
local Actions = require("core.actions")
local Registry = require("core.action_registry")
local Window = require("core.window")
local TxCache = require("core.bridge").tx
local Helpers = require("tests.helpers")

do
  Actions.get_static_actions()
  local bad = {}
  for name in pairs(Policy.TOOLS) do
    if not Registry.get(name) then bad[#bad + 1] = name end
  end
  check("every tool is a registered action", #bad == 0, table.concat(bad, "; "))
end

local FORMER_OFFER = {
  SHOP = { "sell_card", "reroll_shop", "use_consumable", "use_directional_consumable", "set_joker_order",
    "record_plan", "record_joker_roles" },
  BLIND_SELECT = { "reroll_boss", "sell_card", "use_consumable", "use_directional_consumable", "set_joker_order",
    "record_plan" },
  SMODS_BOOSTER_OPENED = { "use_consumable", "use_directional_consumable", "sell_card" },
  SELECTING_HAND = { "use_consumable", "use_directional_consumable", "sell_card", "set_joker_order" },
  MENU = { "select_deck", "select_stake", "copy_seed" },
  RUN_SETUP = { "select_deck", "toggle_seeded_run", "paste_seed", "copy_seed", "select_stake" },
  GAME_OVER = { "select_deck", "copy_seed" },
  ROUND_EVAL = {},
}

local function formerly_offered(state, name)
  if state == "SMODS_BOOSTER_OPENED" and name == "sell_card" then
    local CardUtil = require("facts.card_util")
    return CardUtil.joker_slot_status().full or CardUtil.consumable_slot_status().full
  end
  if state == "SELECTING_HAND" and name == "set_joker_order" then
    return require("facts.boss.legality").boss_names_reorder()
  end
  if state == "MENU" and name == "copy_seed" then return Actions.is_action_valid("copy_seed") end
  return true
end

local tools_block = Helpers.tools_block

local boards = {}
for _, list in ipairs({ LB.BOARDS, LB.BLOCKED, LB.OUT_OF_RUN }) do
  for _, b in ipairs(list) do boards[#boards + 1] = b end
end

local missing, unnamed_bits, shapes, pinned = {}, {}, {}, 0
for _, board in ipairs(boards) do
  local key = board.state .. "/" .. board.desc
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  if not payload then
    missing[#missing + 1] = key .. ": no force"
  else
    local offered = {}
    for _, name in ipairs(payload.actions) do offered[name] = true end
    local opts = payload.opts or {}
    if opts.priority ~= "low" or opts.ephemeral_context ~= true then
      shapes[#shapes + 1] = key .. " priority=" .. tostring(opts.priority)
        .. " ephemeral=" .. tostring(opts.ephemeral_context)
    end
    local block = tools_block(payload.query)
    local state_set = Actions.get_state_action_set(board.state)
    for _, name in ipairs(FORMER_OFFER[board.state] or {}) do
      if state_set[name] and Actions.is_action_valid(name) and formerly_offered(board.state, name) then
        pinned = pinned + 1
        if not offered[name] then
          missing[#missing + 1] = key .. ": " .. name .. " is legal but not in action_names"
        end
      end
    end
    local force = require("force.force_router").get_force_for_state(board.state) or {}
    for name, text in pairs(force.tool_bits or {}) do
      local first = text:match("^(.-) or %u") or text
      if Policy.is_tool(name) and Actions.is_action_valid(name) and not block:find(first, 1, true) then
        unnamed_bits[#unnamed_bits + 1] = key .. ": the builder's " .. name .. " move never reached the query"
      end
    end
  end
end
check("every force stays low priority with ephemeral state (BEST_PRACTICES.md:37, :39)",
  #shapes == 0, table.concat(shapes, "; "))
check("every tool a builder offers is forced in the same frame",
  #missing == 0, table.concat(missing, "; "))
check("the sweep pinned tools on the boards, not nothing", pinned >= 30, tostring(pinned))
check("every move a builder writes for a tool is delivered verbatim in the query",
  #unnamed_bits == 0, table.concat(unnamed_bits, "; "))

local PAYLOADS = {
  record_plan = function() return { hand_plan = "Pairs", build_plan = "Mult", money_plan = "Hold" } end,
  set_joker_order = function() return { from_index = 1, to_index = 2 } end,
  select_stake = function() return { to_key = 1 } end,
  copy_seed = function() return {} end,
  select_deck = function() return { back = "b_red" } end,
}
local PREFERENCE = { "set_joker_order", "record_plan", "sell_card", "use_consumable", "select_stake", "copy_seed",
  "select_deck" }

local function tool_and_payload(offered)
  for _, name in ipairs(PREFERENCE) do
    if offered[name] then
      if PAYLOADS[name] then return name, PAYLOADS[name]() end
      local candidate = Registry.candidates(name)[1]
      if candidate then return name, candidate end
    end
  end
end

local covered, resolved, broken, per_state = 0, 0, {}, {}
for n, board in ipairs(boards) do
  local key = board.state .. "/" .. board.desc
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  local name, data
  if payload then
    local offered = {}
    for _, offer in ipairs(payload.actions) do offered[offer] = true end
    name, data = tool_and_payload(offered)
  end
  if payload and name then
    local w = Window.current()
    local results, withdrawn = {}, {}
    local bridge = G.NEURO
    local real_result, real_withdraw = bridge.send_action_result, bridge.withdraw_actions
    bridge.send_action_result = Helpers.result_log(results, { "id", "ok", "message", "code" }, true)
    bridge.withdraw_actions = function(_, names)
      for _, x in ipairs(names or {}) do withdrawn[#withdrawn + 1] = x end
      return true
    end
    local id = "tool-" .. n
    Helpers.stage_registered(nil, { name })
    TxCache.open(id, name, G.TIMERS.REAL)
    local ok = pcall(require("core.dispatcher").handle_message, Helpers.inbound_action(name, id, data), bridge)
    pcall(require("core.execute").step, G.TIMERS.REAL)
    local offered = w and w.set[name] == true
    local mine, success = 0, nil
    for _, r in ipairs(results) do
      if r.id == id then mine, success = mine + 1, r.ok end
    end
    local settled = success == true and Window.current() == nil and w.ended_by == "answered"
      or success == false and Window.current() == w and w.phase == "forced"
    local decisions = {}
    for _, offer in ipairs(w.names) do
      if Policy.disposable_group(offer) then decisions[#decisions + 1] = offer end
    end
    local whole = success == true and table.concat(decisions, ",") or ""
    if not ok or not offered or mine ~= 1 or not settled or table.concat(withdrawn, ",") ~= whole then
      broken[#broken + 1] = string.format("%s: %s -> offered=%s results=%d success=%s ended_by=%s withdrawn=%s",
        key, name, tostring(offered), mine, tostring(success), tostring(w and w.ended_by), table.concat(withdrawn, ","))
    else
      covered = covered + 1
      if success then resolved = resolved + 1 end
      per_state[board.state] = true
    end
    pcall(require("core.execute").abort, "test")
    bridge.send_action_result, bridge.withdraw_actions = real_result, real_withdraw
  end
end
check("a tool answering any force gets one result, and on success unregisters only the offer's disposable decisions and resolves it",
  #broken == 0, table.concat(broken, "; "))
local states = {}
for state in pairs(per_state) do states[#states + 1] = state end
table.sort(states)
check("that holds in every force state of the corpus that offers a tool",
  #states >= 7, table.concat(states, ","))
check("and on most boards, not a handful", covered >= 15 and resolved >= 12, covered .. "/" .. resolved)

done()
