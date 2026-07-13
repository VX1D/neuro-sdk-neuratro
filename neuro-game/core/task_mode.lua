local M = {}

local Actions = require("core.actions")

M.active = false
local idx = 0
local phase = "idle"
local results = {}
local phase_at = 0
local report_written = false

local SETUP_TIMEOUT = 12
local AWAIT_TIMEOUT = 45
local RUN_START_TIMEOUT = 20
local HOLD_AFTER = 4
local run_starting = nil

local function clk()
  return (love and love.timer and love.timer.getTime()) or 0
end

local function trace(fmt, ...)
  local lv = _G.love
  if not (lv and lv.filesystem and lv.filesystem.append) then return end
  local line = string.format("[%7.2f] " .. fmt .. "\n", clk(), ...)
  pcall(function()
    lv.filesystem.createDirectory("tasks")
    if not lv.filesystem.append("tasks/trace.log", line) then
      lv.filesystem.write("tasks/trace.log", line)
    end
  end)
end

local function state_name()
  local ok, S = pcall(require, "core.state")
  if ok and S and S.get_state_name then return S.get_state_name() end
  return "?"
end

local function jokers()
  return (G and G.jokers and G.jokers.cards) or {}
end

local function run_active()
  return G and G.STATE ~= nil and not require("core.state_kinds").is_menu_state(state_name())
end

local function start_run()
  if not (G and G.FUNCS and type(G.FUNCS.start_run) == "function") then return end
  if G.OVERLAY_MENU and G.FUNCS.exit_overlay_menu then pcall(G.FUNCS.exit_overlay_menu) end
  pcall(G.FUNCS.start_run, nil, { stake = 1, seed = "NEUROREG" })
end

local function money()
  return (G and G.GAME and tonumber(G.GAME.dollars)) or 0
end

local function spawn_joker(key)
  if not (G and G.jokers and _G.SMODS and SMODS.create_card) then return nil end
  local ok, card = pcall(function()
    local c = SMODS.create_card({ key = key, area = G.jokers, skip_materialize = true,
      bypass_discovery_center = true, no_edition = true })
    if c.add_to_deck then c:add_to_deck() end
    G.jokers:emplace(c)
    return c
  end)
  return ok and card or nil
end

local function induce_popup()
  if not G then return end
  if G.OVERLAY_MENU then return end
  local center = G.P_CENTERS and G.P_CENTERS.j_joker
  if center and type(create_UIBox_card_unlock) == "function" and G.FUNCS and G.FUNCS.overlay_menu then
    pcall(function() G.FUNCS.overlay_menu({ definition = create_UIBox_card_unlock(center) }) end)
  end
end

local function open_run_setup()
  if not (G and G.FUNCS) then return end
  if require("core.state_kinds").is_run_setup_overlay() then return end
  local fn = G.FUNCS.setup_run
  if type(fn) == "function" then pcall(fn, { config = {}, UIBox = require("facts.card_area_util").mock_UIBox }) end
end

M.TASKS = {
  {
    name = "task/exit_popup", expect = "exit_overlay_menu", actions = { "exit_overlay_menu" },
    query = "A popup is covering the screen. Close it with exit_overlay_menu. Your move: exit_overlay_menu|{}.",
    setup = function(_) induce_popup() end,
    ready = function(_) return not not (G and G.OVERLAY_MENU) end,
    verify = function(_) return G and G.OVERLAY_MENU == nil end,
  },
  {
    name = "task/paste_seed", expect = "paste_seed", actions = { "paste_seed" },
    query = "Open run setup is ready. Paste the seed ABCDE123 with paste_seed. Your move: paste_seed|{\"seed\":\"ABCDE123\"}.",
    setup = function(_) open_run_setup() end,
    ready = function(_) return require("core.state_kinds").is_run_setup_overlay() and Actions.is_action_valid("paste_seed") end,
    verify = function(_) return type(G.setup_seed) == "string" and #G.setup_seed > 0 end,
  },
  {
    name = "task/invent_seed", expect = "paste_seed", actions = { "paste_seed" },
    query = "Invent your own 8-character seed (letters and digits) and paste it with paste_seed. Your move: paste_seed|{\"seed\":\"<your seed>\"}.",
    setup = function(c) open_run_setup(); c.prev = G.setup_seed end,
    ready = function(_) return require("core.state_kinds").is_run_setup_overlay() and Actions.is_action_valid("paste_seed") end,
    verify = function(c) return type(G.setup_seed) == "string" and #G.setup_seed > 0 and G.setup_seed ~= c.prev end,
  },
  {
    name = "task/reorder_jokers", needs_run = true, expect = "set_joker_order", actions = { "set_joker_order" },
    query = "You have two jokers. Reorder them: move the joker in slot 1 to slot 2. Your move: set_joker_order|{\"from_index\":1,\"to_index\":2}.",
    setup = function(c)
      local n = #jokers()
      if n < 1 then
        spawn_joker("j_joker")
      elseif n < 2 then
        if not spawn_joker("j_greedy_joker") then spawn_joker("j_joker") end
      end
      if #jokers() >= 2 then c.first = c.first or jokers()[1] end
    end,
    ready = function(_) return #jokers() >= 2 and state_name() ~= "MENU" and Actions.is_action_valid("set_joker_order") end,
    verify = function(c) return c.first ~= nil and jokers()[2] == c.first end,
  },
  {
    name = "task/sell_card", needs_run = true, expect = "sell_card", actions = { "sell_card" },
    query = "Sell one of your jokers with sell_card. Your move: sell_card|{\"area\":\"jokers\",\"index\":1}.",
    setup = function(c)
      if #jokers() < 1 then spawn_joker("j_joker") end
      if #jokers() >= 1 then c.n0 = c.n0 or #jokers() end
    end,
    ready = function(_) return #jokers() >= 1 and state_name() ~= "MENU" and Actions.is_action_valid("sell_card") end,
    verify = function(c) return #jokers() < (c.n0 or 0) end,
  },
  {
    name = "task/skip_blind", needs_run = true, expect = "skip_blind", actions = { "skip_blind" },
    query = "Skip the current blind with skip_blind. Your move: skip_blind|{}.",
    setup = function(c) c.on_deck0 = Actions.get_selectable_blind_key() end,
    ready = function(_) return state_name() == "BLIND_SELECT" and Actions.is_action_valid("skip_blind") end,
    verify = function(c) return state_name() ~= "BLIND_SELECT" or Actions.get_selectable_blind_key() ~= c.on_deck0 end,
  },
}

function M.available()
  return G and G.STATE ~= nil
end

function M.start()
  if M.active then return false, "task mode already running" end
  idx = 1
  results = {}
  phase = "setup"
  phase_at = clk()
  report_written = false
  M.active = true
  if G and G.NEURO then G.NEURO.task_mode_active = true end
  trace("start: %d tasks", #M.TASKS)
  return true
end

local function record(pass, note)
  local t = M.TASKS[idx]
  results[idx] = { name = t.name, pass = pass, note = note }
  trace("%s %s -- %s", pass and "PASS" or "FAIL", t.name, tostring(note or ""))
end

local function advance()
  idx = idx + 1
  phase = idx <= #M.TASKS and "hold" or "done"
  phase_at = clk()
end

local function write_report()
  if report_written then return end
  report_written = true
  local p, f = 0, 0
  local lines = { "# Neuro small regression check", "" }
  for i = 1, #M.TASKS do
    local r = results[i]
    if r and r.pass then p = p + 1 elseif r then f = f + 1 end
    lines[#lines + 1] = string.format("- [%s] %s%s",
      r and (r.pass and "PASS" or "FAIL") or "----",
      M.TASKS[i].name, r and r.note and ("  (" .. r.note .. ")") or "")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("PASS %d / FAIL %d / SKIP %d", p, f, #M.TASKS - p - f)
  local body = table.concat(lines, "\n") .. "\n"
  trace("finish: pass=%d fail=%d", p, f)
  local lv = _G.love
  if lv and lv.filesystem and lv.filesystem.write then
    pcall(function() lv.filesystem.createDirectory("tasks"); lv.filesystem.write("tasks/report.md", body) end)
  end
  print("[neuro-game] small regression check: PASS " .. p .. " / FAIL " .. f)
end

function M.get_force()
  if not M.active or phase ~= "await" then return nil end
  local t = M.TASKS[idx]
  if not t then return nil end
  return { query = t.query, actions = t.actions }
end

function M.on_action(name, ok)
  if not M.active or phase ~= "await" then return end
  local t = M.TASKS[idx]
  if not t or name ~= t.expect then return end
  local pass = ok and (not t.verify or (function() local o, v = pcall(t.verify, t.ctx); return o and v end)())
  record(pass, ok and (pass and "verified" or "action ok but effect not seen") or "action rejected")
  advance()
end

function M.tick(_)
  if not M.active then return end
  local now = clk()
  if phase == "setup" then
    local t = M.TASKS[idx]
    t.ctx = t.ctx or {}
    if t.needs_run and not run_active() then
      if not run_starting then start_run(); run_starting = now; trace("starting run for %s", t.name) end
      if now - run_starting > RUN_START_TIMEOUT then
        record(false, "run did not start")
        run_starting = nil
        advance()
      end
      return
    end
    if run_starting then run_starting = nil; phase_at = now end
    pcall(t.setup, t.ctx)
    if (function() local o, r = pcall(t.ready, t.ctx); return o and r end)() then
      phase = "await"
      phase_at = now
      pcall(function() require("core.neuro_lifecycle").mark_force_dirty() end)
      trace("await: %s (state=%s)", t.name, state_name())
    elseif now - phase_at > SETUP_TIMEOUT then
      record(false, "setup timed out (state=" .. state_name() .. ")")
      advance()
    end
  elseif phase == "hold" then
    if now - phase_at > HOLD_AFTER then
      phase = "setup"
      phase_at = now
    end
  elseif phase == "await" then
    if now - phase_at > AWAIT_TIMEOUT then
      record(false, "LLM did not answer in time")
      advance()
    end
  elseif phase == "done" then
    write_report()
    M.active = false
    if G and G.NEURO then G.NEURO.task_mode_active = nil end
  end
end

function M.running()
  return M.active
end

return M
