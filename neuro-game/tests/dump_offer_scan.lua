
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local D = require("core.dispatcher")
local DW = require("core.decision_window")
local State = require("core.state")
local Config = require("core.config")
local TD = require("tests.test_deadlock")

local SEED  = tonumber(arg and arg[1]) or 20260723
local ITERS = tonumber(arg and arg[2]) or 4000
math.randomseed(SEED)
local function ri(a, b) return math.random(a, b) end
local function pick(t) return t[ri(1, #t)] end
local function chance(p) return math.random() < p end
local function contains(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

local STATE_ID, _next = {}, 0
local function ensure_state(name)
  if not STATE_ID[name] then _next = _next + 1; STATE_ID[name] = _next end
  return STATE_ID[name]
end

local WIPE = { "hand","jokers","consumeables","shop_jokers","shop_vouchers","shop_booster","shop",
               "pack_cards","booster_pack","blind_select_opts","blind_select","OVERLAY_MENU" }
local function fresh_g()
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0, _reservation_epoch = 0, shop_reroll_count = 0, _decision_windows = {},
  state_enter_serial = (tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0) + 5 }
end

local function usable_consumable()
  return { cost = 3, sell_cost = 2, ability = { name = "Pluto", set = "Planet", consumeable = {} },
    config = { center = { key = "c_pluto", name = "Pluto", set = "Planet",
      loc_txt = { name = "Pluto", description = "Levels up High Card" } } } }
end

local function mutate(state)
  local id = ensure_state(state)
  G.STATES = G.STATES or {}; G.STATES[state] = id; G.STATE = id
  if G.GAME then G.GAME.STOP_USE = nil end
  if state == "SHOP" then
    if chance(0.5) then G.NEURO.econ_plan_ok = false else G.NEURO.econ_plan_ok = true; G.NEURO.plan = { money = "x", money_scope = require("core.plan_gate").current_economy_scope() } end
    if chance(0.5) then G.NEURO.shop_plan_revision_required = { money = chance(0.5) or nil, build = chance(0.5) or nil } end
    if G.GAME and chance(0.4) then G.GAME.dollars = ri(0, 4) end
  elseif state == "BLIND_SELECT" then
    if chance(0.5) then G.NEURO.blind_plan_ok = false else G.NEURO.blind_plan_ok = true end
  end
  if state == "BLIND_SELECT" or state == "SELECTING_HAND" or state == "SHOP" then
    if chance(0.5) then
      G.consumeables = { cards = { usable_consumable() }, config = { card_limit = 2 } }
      if G.GAME and chance(0.5) then G.GAME.STOP_USE = 1 end
    end
  end
end

local function moveline_actions(query)
  local tail = tostring(query or ""):match("Your move:(.*)") or ""
  local out = {}
  for name in tail:gmatch("([%a_]+)|") do out[name] = true end
  return out
end

local function trigger_active(def)
  local t = def.trigger
  if not t then return true end
  if t.state and t.state ~= State.get_state_name() then return false end
  if type(t.condition) == "function" then
    local ok, r = pcall(t.condition)
    return ok and r and true or false
  end
  return true
end

local orphans, traps, crashes = {}, {}, 0
local ran, no_moveline = 0, 0
local defs = DW._test.get_definitions()

local function run_iteration(it)
  fresh_g()
  local sc = pick(TD.SCENARIOS)
  local state = sc.state
  local built = pcall(function()
    TD.apply_mock(sc.mock())
    G.NEURO.persona = G.NEURO.persona or "neuro"
    G.NEURO._decision_windows = G.NEURO._decision_windows or {}
    mutate(state)
  end)
  if not built then crashes = crashes + 1; return end

  local okf, force = pcall(D.get_force_for_state, state)
  if not okf then crashes = crashes + 1; return end
  if type(force) ~= "table" or type(force.actions) ~= "table" then return end
  ran = ran + 1

  local offered = {}
  for _, n in ipairs(force.actions) do offered[n] = true end
  if not tostring(force.query or ""):find("Your move:", 1, true) then no_moveline = no_moveline + 1 end
  local moves = moveline_actions(force.query)

  for name in pairs(moves) do
    if not offered[name] then
      orphans[#orphans + 1] = { it = it, state = state, action = name }
    end
  end

  for _, name in ipairs(force.actions) do
    local okr, rej = pcall(DW.would_reject, name)
    if okr and rej then
      for _, def in ipairs(defs) do
        if contains(def.blocks, name) and def.policy == "hard"
           and not contains(def.acknowledged_by, name) and trigger_active(def) then
          local surfaced = false
          for _, ack in ipairs(def.acknowledged_by or {}) do
            if moves[ack] then surfaced = true break end
          end
          if not surfaced then
            traps[#traps + 1] = { it = it, state = state, action = name,
              window = def.id, unlock = table.concat(def.acknowledged_by or {}, "/") }
          end
        end
      end
    end
  end
end
for it = 1, ITERS do run_iteration(it) end

local function banner(s) print(("="):rep(90)); print(s); print(("="):rep(90)) end
banner(string.format("OFFER-SCAN FUZZ  seed=%d iters=%d states=%d orphans=%d traps=%d crashes=%d",
  SEED, ITERS, ran, #orphans, #traps, crashes))
print(string.format(
  "ORPHAN detection ran on %d/%d states (%d had no 'Your move:' section in the query and were skipped, not clean)",
  ran - no_moveline, ran, no_moveline))
print("ORPHAN = an action in the 'Your move:' line that is NOT in the SDK force.actions set")
print("TRAP   = an SDK-offered action a HARD window blocks now with its unlock NOT surfaced in the move line\n")

local function summarize(list, label)
  if #list == 0 then return end
  banner(label)
  local seen = {}
  for _, f in ipairs(list) do
    local k = f.state .. " :: " .. f.action .. (f.window and (" [" .. f.window .. " -> " .. f.unlock .. "]") or "")
    seen[k] = (seen[k] or 0) + 1
  end
  for k, n in pairs(seen) do print(string.format("  %-70s x%d", k, n)) end
end
summarize(orphans, "ORPHAN MOVE BULLETS (move line names an unoffered action)")
summarize(traps, "TRAP OFFERS (offered + hard-blocked + unlock not in move line)")

print()
print(string.format("==== offer-scan: %d orphan(s), %d trap(s), %d crash(es), %d states ====",
  #orphans, #traps, crashes, ran))
if crashes > 0 then os.exit(1) end
if (#orphans > 0 or #traps > 0) and os.getenv("FAIL_ON_FINDINGS") == "1" then os.exit(1) end
