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
    if type(G.NEURO) == "table" then
      push_restore(G.NEURO, "llm_paused", true)
    end
  end
end

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

local function fail_log(line, overwrite)
  local lv = rawget(_G, "love")
  if not (lv and lv.filesystem) then return end
  pcall(function()
    lv.filesystem.createDirectory("selftest")
    if overwrite or not lv.filesystem.append("selftest/failures.log", line .. "\n") then
      lv.filesystem.write("selftest/failures.log", line .. "\n")
    end
  end)
end

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
  if not ok then
    fail_log(string.format("%3d/%d  FAIL  %s  (%.2fs)  -- %s",
      S.idx, #S.cases, tostring(name), S.clock - S.case_t0, tostring(detail or "")))
  end
end

function M.engine_settled()
  return require("util.utils").engine_settled()
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
  fail_log(string.format("=== DONE: %d pass, %d fail  (report: %s) ===", S.pass, S.fail, tostring(S.report_path or "n/a")))
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
  local cleanup_errors = {}
  if c and c.teardown then
    local ok, err = pcall(c.teardown, S.ctx)
    if not ok then cleanup_errors[#cleanup_errors + 1] = "teardown error: " .. tostring(err) end
  end
  if S.reset then
    local ok, err = pcall(S.reset, S.ctx)
    if not ok then cleanup_errors[#cleanup_errors + 1] = "reset error: " .. tostring(err) end
  end
  if #cleanup_errors > 0 then
    record((c and c.name or "selftest") .. "/cleanup", false, table.concat(cleanup_errors, "; "))
  end
  S.ctx = nil
  S.phase = "case_next"
end

local function describe_error(err)
  if type(err) == "string" then return err end
  if type(err) ~= "table" then return tostring(err) end
  if err.__action_error and err.reason_code then
    local extra = ""
    if err.state_mutated then extra = " [state mutated]" end
    return string.format("%s: %s%s", tostring(err.reason_code),
      tostring(err.message), extra)
  end
  if type(err.message) == "string" then return err.message end
  if type(err.reason) == "string" then return err.reason end
  local keys = {}
  for k, v in pairs(err) do
    if type(v) ~= "table" and type(v) ~= "function" then
      keys[#keys + 1] = tostring(k) .. "=" .. tostring(v)
    else
      keys[#keys + 1] = tostring(k) .. "=<" .. type(v) .. ">"
    end
    if #keys >= 8 then break end
  end
  table.sort(keys)
  if #keys == 0 then return "empty table error" end
  return "table error {" .. table.concat(keys, ", ") .. "}"
end

local function traced_pcall(fn, arg)
  local trace_text
  local ok, err = xpcall(function() return fn(arg) end, function(e)
    if type(e) == "string" and debug and debug.traceback then
      trace_text = debug.traceback(e, 2)
    end
    return e
  end)
  if ok then return true end
  local detail = describe_error(err)
  if trace_text then
    local head = trace_text:match("([^\n]*\n[^\n]*\n[^\n]*)") or trace_text
    detail = detail .. " | " .. head:gsub("%s+", " ")
  end
  return false, detail
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
    local ok, err = traced_pcall(c.setup, S.ctx)
    if not ok then
      fail_case("setup error: " .. err)
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
      local ok, err = traced_pcall(c.act, S.ctx)
      if not ok then
        fail_case("act error: " .. err)
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
    local filt = os.getenv("NEURO_SELFTEST_FILTER")
    if filt == nil or filt == "" then filt = ok_de and Config.get("NEURO_SELFTEST_FILTER") or "" end
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
      for name in pairs(SCAFFOLD) do
        if not present[name] then trace("filter WARNING: scaffold case '%s' not found (state threading may break)", name) end
      end
      local function matches(c)
        for _, p in ipairs(pats) do
          if tostring(c.name):find(p, 1, true) then return true end
        end
        return false
      end
      local needs_scaffold = false
      for _, c in ipairs(S.cases) do
        if not SCAFFOLD[c.name] and matches(c) and not c.standalone then needs_scaffold = true; break end
      end
      for _, c in ipairs(S.cases) do
        local keep = (SCAFFOLD[c.name] and needs_scaffold) or false
        if not keep and matches(c) then keep = true end
        if keep then kept[#kept + 1] = c end
      end
      if #kept > 0 then
        S.cases = kept
        if not needs_scaffold then sandbox = false; S.sandbox = false end
      else
        trace("filter WARNING: '%s' matched no cases -- running the FULL suite", tostring(filt))
      end
      trace("filter '%s' -> %d/%d cases (scaffold=%s)", tostring(filt), #S.cases, total0, tostring(needs_scaffold))
    end
  end
  S.opts.gamespeed = opts.gamespeed or (sandbox and 4 or nil)
  install_guards()
  S.running = true
  if G and G.NEURO then G.NEURO.selftest_active = true end
  trace("start: %d cases, sandbox=%s, state=%s", #S.cases, tostring(sandbox),
    tostring(G and G.STATE))
  fail_log(string.format("=== self-test started %s: %d cases ===", os.date("%Y-%m-%d %H:%M:%S"), #S.cases), true)
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
    if S.ctx then end_case() end
    record("selftest/internal", false, tostring(err))
    finish()
  end
end

function M.abort()
  if not S.running then return end
  local detail = string.format("aborted at case %d/%d", S.idx, #S.cases)
  if S.ctx then end_case() end
  record("selftest/abort", false, detail)
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

function M.draw_banner()
  local lv = rawget(_G, "love")
  if not (lv and lv.graphics) then return end
  local g = lv.graphics
  local sw = g.getWidth()
  if S.running then
    g.setColor(0, 0, 0, 0.7)
    g.rectangle("fill", 0, 0, sw, 22)
    g.setColor(1, 0.85, 0.3, 1)
    g.print(string.format("SELF-TEST running  %d/%d  (pass %d / fail %d)  -- do not close",
      math.min(S.idx, #S.cases), #S.cases, S.pass, S.fail), 12, 5)
    return
  end
  if S.phase ~= "done" then return end
  local ok = (S.fail == 0)
  g.setColor(ok and 0.05 or 0.32, ok and 0.32 or 0.03, 0.05, 0.95)
  g.rectangle("fill", 0, 0, sw, 70)
  g.setColor(ok and 0.35 or 1.0, ok and 1.0 or 0.5, ok and 0.45 or 0.3, 1)
  g.rectangle("fill", 0, 70, sw, 4)
  g.setColor(1, 1, 1, 1)
  g.push()
  g.translate(16, 12)
  g.scale(2, 2)
  g.print(string.format("SELF-TEST DONE   %d PASS / %d FAIL", S.pass, S.fail), 0, 0)
  g.pop()
  g.setColor(ok and 0.7 or 1, 1, ok and 0.8 or 0.6, 1)
  g.print(ok and "ALL PASS -- SAFE TO CLOSE THE APP"
    or "FAILURES -- see selftest/failures.log -- SAFE TO CLOSE THE APP", 18, 48)
end

return M
