local M = {}

local S

local function fresh_state()
  return {
    running = false, phase = "idle", clock = 0,
    cases = {}, idx = 0, results = {}, restores = {},
    pass = 0, fail = 0, status_str = "selftest: idle",
    reset = nil, opts = {}, ctx = nil,
    deadline = 0, act_at = 0, case_t0 = 0,
    sandbox = false, sandbox_deadline = 0,
    last_result = "", report_path = nil,
  }
end
S = fresh_state()

-- stat/unlock/save suppression: sandbox run must leave zero trace on the profile (save_run also honors G.F_NO_SAVING)
local GUARD_NOOP = {
  "inc_career_stat", "check_for_unlock", "unlock_card", "win_game",
  "save_run", "save_with_action",
}

local function push_restore(tbl, key, val)
  S.restores[#S.restores + 1] = { tbl = tbl, key = key, val = rawget(tbl, key) }
  rawset(tbl, key, val)
end

local function install_guards()
  for _, name in ipairs(GUARD_NOOP) do
    if type(rawget(_G, name)) == "function" then
      push_restore(_G, name, function() end)
    end
  end
  if type(G) == "table" then
    push_restore(G, "F_NO_SAVING", true)
    push_restore(G, "save_settings", function() end)
    push_restore(G, "save_progress", function() end)
    if type(G.SETTINGS) == "table" and S.opts.gamespeed then
      push_restore(G.SETTINGS, "GAMESPEED", S.opts.gamespeed)
    end
    -- llm_paused gates dispatcher intake, stall watchdog and force sending so the live loop can't drive the sandbox
    if type(G.NEURO) == "table" then
      push_restore(G.NEURO, "llm_paused", true)
    end
  end
end

-- trace file in LOVE save dir, open/append/close per line so a crash loses nothing
local function trace(fmt, ...)
  if S.opts.trace == false then return end
  local lv = rawget(_G, "love")
  if not (lv and lv.filesystem and lv.filesystem.append) then return end
  local line = string.format("[%8.2f] ", S.clock) .. string.format(fmt, ...) .. "\n"
  pcall(function()
    lv.filesystem.createDirectory("selftest")
    if not lv.filesystem.append("selftest/trace.log", line) then
      lv.filesystem.write("selftest/trace.log", line)
    end
  end)
end
M.trace = trace

local function restore_all()
  for i = #S.restores, 1, -1 do
    local r = S.restores[i]
    pcall(rawset, r.tbl, r.key, r.val)
  end
  S.restores = {}
end

local function set_status(detail)
  S.status_str = string.format("selftest %d/%d  pass:%d fail:%d  %s",
    math.min(S.idx, #S.cases), #S.cases, S.pass, S.fail, tostring(detail or S.phase))
end

local function record(name, ok, detail)
  S.results[#S.results + 1] = {
    name = tostring(name), ok = not not ok,
    detail = tostring(detail or ""), t = S.clock - S.case_t0,
  }
  if ok then S.pass = S.pass + 1 else S.fail = S.fail + 1 end
  S.last_result = (ok and "PASS " or "FAIL ") .. tostring(name)
  set_status(S.last_result)
  trace("%s %s -- %s", ok and "PASS" or "FAIL", tostring(name), tostring(detail or ""))
end

-- permanent cosmetic events (game.lua:2381) are blocking=false + blockable=false and never complete, so they don't count as engine activity
function M.engine_settled()
  local em = G and G.E_MANAGER
  if not (em and em.queues) then return true end
  for k, q in pairs(em.queues) do
    if k ~= "unlock" and type(q) == "table" then
      for i = 1, #q do
        local e = q[i]
        if not (type(e) == "table" and e.blocking == false and e.blockable == false) then
          return false
        end
      end
    end
  end
  return true
end

local function mod_dir()
  local src = ""
  if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    src = tostring(info and info.source or "")
  end
  src = src:gsub("^@", "")
  return src:match("^(.*)[/\\][^/\\]+$") or "."
end

function M.render_report(results)
  local lines = {
    "# Neuratro in-game self-test report",
    "",
    string.format("Date: %s", os.date("%Y-%m-%d %H:%M:%S")),
    string.format("Cases: %d  PASS: %d  FAIL: %d", #results, S.pass, S.fail),
    "",
  }
  for i, r in ipairs(results) do
    lines[#lines + 1] = string.format("%3d. %s  %6.2fs  %s%s",
      i, r.ok and "PASS" or "FAIL", tonumber(r.t) or 0, r.name,
      r.detail ~= "" and ("  -- " .. r.detail) or "")
  end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_report()
  if S.opts.report == false then return end
  local body = M.render_report(S.results)
  local fname = os.date("%Y-%m-%d") .. "-report.md"
  -- prefer LOVE save storage so a normal in-game run doesn't write into the source checkout
  local lv = rawget(_G, "love")
  if lv and lv.filesystem then
    local ok = pcall(function()
      lv.filesystem.createDirectory("selftest")
      lv.filesystem.write("selftest/" .. fname, body)
    end)
    if ok then
      S.report_path = "love-save://selftest/" .. fname
      return
    end
  end
  -- offline harness (no love): fall back to the gitignored dev/selftest tree
  local dir = mod_dir() .. "/dev/selftest"
  local path = dir .. "/" .. fname
  local f = io.open(path, "w")
  if not f then
    pcall(function() require("core.mod_paths").ensure_dir(dir) end)
    f = io.open(path, "w")
  end
  if f then
    f:write(body)
    f:close()
    S.report_path = path
  end
end

local function finish(note)
  if note then record("selftest/finish", false, note) end
  trace("finish: %s  pass=%d fail=%d", tostring(note or "ok"), S.pass, S.fail)
  restore_all()
  pcall(write_report)
  -- sandbox=false mutates the live run; restore_all re-enables saving, so leave the trashed run or autosave persists corruption
  if G and G.FUNCS and type(G.FUNCS.go_to_menu) == "function" then
    pcall(G.FUNCS.go_to_menu)
  end
  S.running = false
  if G and G.NEURO then G.NEURO.selftest_active = false end
  S.phase = "done"
  set_status(string.format("done (report: %s)", tostring(S.report_path or "not written")))
end

local function end_case()
  local c = S.cases[S.idx]
  if c and c.teardown then pcall(c.teardown, S.ctx) end
  if S.reset then pcall(S.reset, S.ctx) end
  S.phase = "case_next"
end

local function fail_case(detail)
  record(S.cases[S.idx].name, false, detail)
  end_case()
end

local function begin_case()
  S.idx = S.idx + 1
  if S.idx > #S.cases then
    S.phase = "finish"
    return
  end
  local c = S.cases[S.idx]
  S.ctx = {}
  S.case_t0 = S.clock
  S.deadline = S.clock + (c.timeout_s or 15)
  S.act_at = S.clock + (c.act_delay or 0.1)
  set_status("running: " .. tostring(c.name))
  trace("case %d/%d begin: %s", S.idx, #S.cases, tostring(c.name))
  if c.setup then
    local ok, err = pcall(c.setup, S.ctx)
    if not ok then
      fail_case("setup error: " .. tostring(err))
      return
    end
  end
  S.phase = "case_act"
end

local function state_name_of(v)
  if not (G and G.STATES) then return tostring(v) end
  for k, s in pairs(G.STATES) do
    if s == v then return k end
  end
  return tostring(v)
end

local function step()
  if S.phase == "sandbox_enter" then
    if S.clock >= (S.trace_at or 0) then
      S.trace_at = S.clock + 1
      local qinfo = {}
      local em = G and G.E_MANAGER
      if em and em.queues then
        for k, q in pairs(em.queues) do
          if type(q) == "table" and #q > 0 then
            local e = q[1]
            local src = ""
            if e and type(e.func) == "function" and debug and debug.getinfo then
              local info = debug.getinfo(e.func, "S")
              src = tostring(info and info.short_src or "?") .. ":" .. tostring(info and info.linedefined or "?")
            end
            qinfo[#qinfo + 1] = string.format("%s=%d(trig=%s,nodel=%s,blocking=%s,src=%s)",
              k, #q, tostring(e and e.trigger), tostring(e and e.no_delete), tostring(e and e.blocking), src)
          end
        end
      end
      trace("sandbox_enter: state=%s blind_select=%s settled=%s overlay=%s queues[%s]",
        state_name_of(G and G.STATE), tostring(not not (G and G.blind_select)),
        tostring(M.engine_settled()), tostring(not not (G and G.OVERLAY_MENU)),
        table.concat(qinfo, " "))
    end
    if G and G.STATES and G.STATE == G.STATES.BLIND_SELECT and G.blind_select and M.engine_settled() then
      trace("sandbox ready at BLIND_SELECT, %d cases queued", #S.cases)
      S.phase = "case_next"
    elseif S.clock > S.sandbox_deadline then
      finish("sandbox run never reached BLIND_SELECT")
    end
  elseif S.phase == "case_next" then
    begin_case()
  elseif S.phase == "case_act" then
    if S.clock < S.act_at then return end
    local c = S.cases[S.idx]
    if c.act then
      local ok, err = pcall(c.act, S.ctx)
      if not ok then
        fail_case("act error: " .. tostring(err))
        return
      end
    end
    S.phase = "case_wait"
  elseif S.phase == "case_wait" then
    local c = S.cases[S.idx]
    local ok, done
    if c.wait_for then
      ok, done = pcall(c.wait_for, S.ctx)
      if not ok then
        fail_case("wait_for error: " .. tostring(done))
        return
      end
    else
      done = M.engine_settled()
    end
    if done then
      S.phase = "case_assert"
    elseif S.clock > S.deadline then
      fail_case(string.format("timeout after %.1fs", S.clock - S.case_t0))
    end
  elseif S.phase == "case_assert" then
    local c = S.cases[S.idx]
    if not c.assert then
      record(c.name, true, "")
      end_case()
      return
    end
    local ok, verdict, detail = pcall(c.assert, S.ctx)
    if not ok then
      fail_case("assert error: " .. tostring(verdict))
      return
    end
    record(c.name, not not verdict, detail or (verdict and "" or "assertion failed"))
    end_case()
  elseif S.phase == "finish" then
    finish()
  end
end

function M.available()
  if S.running then return false end
  if not (G and G.STATES and G.STATE) then return false end
  if G.STAGES and G.STAGE and G.STAGES.RUN and G.STAGE == G.STAGES.RUN then return false end
  return G.STATE == G.STATES.MENU or G.STATE == G.STATES.SPLASH
end

function M.start(opts)
  opts = opts or {}
  if S.running then return false, "selftest already running" end
  local sandbox = opts.sandbox ~= false
  if sandbox and not M.available() then
    return false, "selftest can only start from the main menu with no active run"
  end
  S = fresh_state()
  S.opts = opts
  S.sandbox = sandbox
  if opts.cases then
    S.cases, S.reset = opts.cases, opts.reset
  else
    local ok, Cases = pcall(require, "core.selftest_cases")
    if not ok then return false, "selftest_cases failed to load: " .. tostring(Cases) end
    local ok_b, built = pcall(Cases.build)
    if not ok_b then return false, "case build failed: " .. tostring(built) end
    S.cases, S.reset = built, Cases.reset
  end
  if type(S.cases) ~= "table" or #S.cases == 0 then return false, "no cases to run" end
  do
    local ok_de, Config = pcall(require, "core.config")
    local filt = ok_de and Config.get("NEURO_SELFTEST_FILTER") or ""
    if filt ~= "" then
      local pats = {}
      for p in tostring(filt):gmatch("[^,]+") do pats[#pats + 1] = p end
      local SCAFFOLD = {
        ["blind/select_small+burglar"] = true,
        ["edge/rental+perishable_at_round_end"] = true,
        ["shop/cash_out_reaches_shop"] = true,
        ["blind2/toggle_shop_exits_to_blind_select"] = true,
        ["edge/blueprint_copies_right_neighbor"] = true,
      }
      local total0, kept, present = #S.cases, {}, {}
      for _, c in ipairs(S.cases) do present[c.name] = true end
      -- rename guard: a scaffold that no longer resolves would silently break state threading
      for name in pairs(SCAFFOLD) do
        if not present[name] then trace("filter WARNING: scaffold case '%s' not found (state threading may break)", name) end
      end
      for _, c in ipairs(S.cases) do
        local keep = SCAFFOLD[c.name] or false
        if not keep then
          for _, p in ipairs(pats) do
            if tostring(c.name):find(p, 1, true) then keep = true; break end
          end
        end
        if keep then kept[#kept + 1] = c end
      end
      if #kept > 0 then
        S.cases = kept
      else
        trace("filter WARNING: '%s' matched no cases -- running the FULL suite", tostring(filt))
      end
      trace("filter '%s' -> %d/%d cases", tostring(filt), #S.cases, total0)
    end
  end
  S.opts.gamespeed = opts.gamespeed or (sandbox and 4 or nil)
  install_guards()
  S.running = true
  -- mirrored to G.NEURO so the orchestrator can check selftest_active without requiring this module
  if G and G.NEURO then G.NEURO.selftest_active = true end
  trace("start: %d cases, sandbox=%s, state=%s", #S.cases, tostring(sandbox),
    tostring(G and G.STATE))
  if sandbox then
    local ok_run, err = pcall(function()
      if G.OVERLAY_MENU and G.FUNCS.exit_overlay_menu then G.FUNCS.exit_overlay_menu() end
      G.FUNCS.start_run(nil, { stake = 1, seed = opts.seed or "SELFTEST" })
    end)
    if not ok_run then
      restore_all()
      S.running = false
      if G and G.NEURO then G.NEURO.selftest_active = false end
      return false, "failed to start sandbox run: " .. tostring(err)
    end
    S.phase = "sandbox_enter"
    S.sandbox_deadline = S.clock + (opts.sandbox_timeout_s or 60)
  else
    S.phase = "case_next"
  end
  set_status("starting")
  return true
end

function M.tick(dt)
  if not S.running then return end
  S.clock = S.clock + (tonumber(dt) or 0)
  local ok, err = pcall(step)
  if not ok then
    record("selftest/internal", false, tostring(err))
    finish()
  end
end

function M.abort()
  if not S.running then return end
  record("selftest/abort", false, string.format("aborted at case %d/%d", S.idx, #S.cases))
  finish()
end

function M.running()
  return S.running
end

function M.status()
  return S.status_str
end

function M.results()
  return S.results
end

function M.report_path()
  return S.report_path
end

return M
