require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("noop-tool-feedback")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local Window = require("core.window")
local TxCache = require("core.bridge").tx

local STAKES = {
  { key = "stake_white", name = "White Stake", applied_stakes = {} },
  { key = "stake_red", name = "Red Stake", applied_stakes = { "white" } },
}

local function board(state, desc)
  LB.load(state, desc)
  G.P_CENTER_POOLS = G.P_CENTER_POOLS or {}
  G.P_CENTER_POOLS.Stake = STAKES
  G.SETTINGS = G.SETTINGS or {}
  G.SETTINGS.profile = 1
  G.PROFILES = { [1] = { all_unlocked = true, MEMORY = {}, deck_usage = {} } }
  SMODS.RunSelect.Setup.choices = { deck_choice = "b_red", stake_choice = 1, enable_seed = true, seed = "ABC123" }
  G.NEURO.selected_back_key = "b_red"
  G.GAME.pseudorandom = { seed = "ABC123" }
  G.F_LOCAL_CLIPBOARD, G.CLIPBOARD = true, "ABC123"
  local calls = {}
  local function spy(label, fn)
    return function(...)
      calls[#calls + 1] = label
      if fn then return fn(...) end
    end
  end
  G.FUNCS.change_stake = spy("change_stake", function(args) G.viewed_stake = args.to_key end)
  G.FUNCS.run_select_paste_seed = spy("run_select_paste_seed")
  G.FUNCS.copy_seed = spy("copy_seed", function() G.CLIPBOARD = G.GAME.pseudorandom.seed end)
  if G.GAME.selected_back then G.GAME.selected_back.change_to = spy("change_to") end
  FP.build(state)
  return calls
end

local sends = 0
local function send(name, data)
  sends = sends + 1
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  local w = Window.current()
  local results = {}
  local bridge = G.NEURO
  bridge.send_action_result = Helpers.result_log(results, { "id", "ok", "message" }, true)
  bridge.withdraw_actions = Helpers.yes
  local id = "noop-" .. sends
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), bridge)
  require("core.execute").step(G.TIMERS.REAL)
  local answered = w ~= nil and w.set[name] == true and Window.current() == nil and w.ended_by == "answered"
  return results, answered, w ~= nil and Window.current() == w
end

local function only(results)
  return #results == 1 and results[1] or {}
end

local CASES = {
  { name = "select_stake", state = "RUN_SETUP", desc = "Run setup overlay active",
    same = { to_key = 1 }, change = { to_key = 2 }, engine = "change_stake",
    value = "White Stake" },
  { name = "select_deck", state = "RUN_SETUP", desc = "Run setup overlay active",
    same = { back = "b_red" }, change = { back = "b_blue" }, engine = "change_to",
    value = "Red Deck" },
  { name = "paste_seed", state = "RUN_SETUP", desc = "Run setup overlay active",
    same = { seed = "abc123" }, change = { seed = "XYZ789" }, engine = "run_select_paste_seed",
    value = "ABC123" },
  { name = "copy_seed", state = "RUN_SETUP", desc = "Run setup overlay active",
    engine = "copy_seed", before_change = function() G.CLIPBOARD = "OTHER" end,
    value = "ABC123" },
  { name = "set_joker_order", state = "SHOP", desc = "Normal: affordable joker, affordable booster, $10",
    same = { from_index = 2, to_index = 2 }, change = { from_index = 1, to_index = 2 },
    setup = function() G.jokers.cards = { LB.joker("j_joker", 901), LB.joker("j_greedy_joker", 902) } end,
    value = "Greedy Joker" },
}

for _, case in ipairs(CASES) do
  local calls = board(case.state, case.desc)
  if case.setup then case.setup() end
  local order = G.jokers and G.jokers.cards and { G.jokers.cards[1], G.jokers.cards[2] }
  for round = 1, 2 do
    local results, answered = send(case.name, case.same)
    local r = only(results)
    check(case.name .. " no-op #" .. round .. ": a success naming the current value, nothing to retry (SPECIFICATION.md:191-192)",
      #results == 1 and r.ok == true and tostring(r.message):find(case.value, 1, true) ~= nil,
      tostring(r.ok) .. " " .. tostring(r.message))
    check(case.name .. " no-op #" .. round .. ": it runs nothing", #calls == 0, table.concat(calls, ","))
    check(case.name .. " no-op #" .. round .. ": it answers the force", answered)
    FP.build(case.state)
  end
  if case.name == "set_joker_order" then
    check("set_joker_order no-op leaves the row in place",
      G.jokers.cards[1] == order[1] and G.jokers.cards[2] == order[2])
  end
  if case.before_change then case.before_change() end
  local results, answered = send(case.name, case.change)
  local r = only(results)
  check(case.name .. " real change: an empty success", #results == 1 and r.ok == true and r.message == nil,
    tostring(r.ok) .. " " .. tostring(r.message))
  check(case.name .. " real change: it answers the force", answered)
  if case.engine then
    check(case.name .. " real change: it runs", #calls == 1 and calls[1] == case.engine, table.concat(calls, ","))
  else
    check(case.name .. " real change: it runs", G.jokers.cards[2] == order[1], tostring(G.jokers.cards[2]))
  end
end

do
  board("RUN_SETUP", "Run setup overlay active")
  G.F_LOCAL_CLIPBOARD, G.CLIPBOARD = nil, nil
  local system = love.system
  love.system = { getClipboardText = function() return "ABC123" end, setClipboardText = function() end }
  local r = only((send("copy_seed")))
  love.system = system
  check("copy_seed reads the system clipboard the engine writes without F_LOCAL_CLIPBOARD",
    r.ok == true and tostring(r.message):find("ABC123", 1, true) ~= nil,
    tostring(r.message))
end

do
  local calls = board("MENU", "Normal: has G.GAME")
  G.P_CENTER_POOLS.Stake = { STAKES[1] }
  G.PROFILES[1].all_unlocked = nil
  G.GAME.pseudorandom = nil
  FP.build("MENU")
  local offer = table.concat((Window.current() or { names = {} }).names, ",")
  check("replay: the MENU force omits the stake choice that has no alternative",
    offer == "open_run_setup,select_deck", offer)
  local LOOP = { "d", "s", "s", "s", "s", "d", "s", "s", "s", "s", "s", "s", "s", "d", "d", "s", "s", "s", "s", "d", "d" }
  G.NEURO.recent_actions = {}
  local Actions = require("core.actions")
  local lost_progress = {}
  for i, step in ipairs(LOOP) do
    local name, data
    if step == "d" then
      name, data = "select_deck", { back = "b_red" }
    else
      name, data = "select_stake", { to_key = 1 }
    end
    send(name, data)
    if not Actions.is_action_valid("open_run_setup") then lost_progress[#lost_progress + 1] = i end
  end
  check("replay: repeated no-ops are bounded per decision, then withheld",
    not Actions.is_action_valid("select_deck") and not Actions.registrable("select_deck"))
  check("replay: the move that progresses stays usable throughout", #lost_progress == 0, table.concat(lost_progress, "; "))
  check("replay: the loop never reached the engine", #calls == 0, table.concat(calls, ","))
end

do
  board("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.jokers.cards = { LB.joker("j_joker", 901), LB.joker("j_greedy_joker", 902) }
  local frame = FP.build("SHOP")
  check("shop replay: the first offer carries the reorder tool",
    frame and table.concat(frame.actions, ","):find("set_joker_order", 1, true) ~= nil,
    frame and table.concat(frame.actions, ","))
  for _ = 1, 10 do send("set_joker_order", { from_index = 2, to_index = 2 }) end
  local Actions = require("core.actions")
  check("shop replay: repeated reorder no-ops are withheld after the cap, leaving the shop stays usable",
    not Actions.registrable("set_joker_order") and Actions.is_action_valid("leave_shop"))
end

done()
