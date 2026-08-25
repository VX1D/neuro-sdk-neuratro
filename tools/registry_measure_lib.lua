local json = require("util.neuro_json")

local M = {}

function M.canon(v)
  local t = type(v)
  if t == "table" then
    if json.is_array(v) then
      local parts = {}
      for i = 1, #v do parts[i] = M.canon(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, k in ipairs(keys) do
      parts[i] = json.encode(tostring(k)) .. ":" .. M.canon(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return json.encode(v)
end

function M.new_aggregate()
  return {
    frames = 0,
    malformed = 0,
    sessions = 0,
    register_frames = 0,
    unregister_frames = 0,
    force_frames = 0,
    result_frames = 0,
    a_redundant_register_frames = 0,
    b_overlapping_forces = 0,
    c_instances = 0,
    c_instance_bytes = 0,
    c_unique = {},
  }
end

function M.new_run()
  return { agg = M.new_aggregate(), sessions = {}, files = {} }
end

local function session_state()
  return { live = {}, open_force = nil }
end

function M.process_frame(run, frame, sid)
  local agg = run.agg
  if sid == nil then
    error("registry_measure: no session key resolved for frame (command=" .. tostring(frame.command) .. ")")
  end
  local st = run.sessions[sid]
  if not st then
    st = session_state()
    run.sessions[sid] = st
    agg.sessions = agg.sessions + 1
  end

  local cmd = frame.command
  if cmd == "actions/register" then
    agg.register_frames = agg.register_frames + 1
    local actions = frame.data and frame.data.actions
    local new_count, total = 0, 0
    if type(actions) == "table" then
      for i = 1, #actions do
        local act = actions[i]
        local name = act.name
        local c = M.canon(act)
        local bytes = #c
        total = total + 1
        agg.c_instances = agg.c_instances + 1
        agg.c_instance_bytes = agg.c_instance_bytes + bytes
        local key = tostring(name) .. "\0" .. c
        if agg.c_unique[key] == nil then agg.c_unique[key] = bytes end
        if st.live[name] ~= c then
          new_count = new_count + 1
          st.live[name] = c
        end
      end
    end
    if total > 0 and new_count == 0 then
      agg.a_redundant_register_frames = agg.a_redundant_register_frames + 1
    end
  elseif cmd == "actions/unregister" then
    agg.unregister_frames = agg.unregister_frames + 1
    local names = frame.data and frame.data.action_names
    if type(names) == "table" then
      for i = 1, #names do
        st.live[names[i]] = nil
        if st.open_force then st.open_force[names[i]] = nil end
      end
      if st.open_force and next(st.open_force) == nil then st.open_force = nil end
    end
  elseif cmd == "actions/force" then
    agg.force_frames = agg.force_frames + 1
    if st.open_force then
      agg.b_overlapping_forces = agg.b_overlapping_forces + 1
    end
    st.open_force = {}
    local names = frame.data and frame.data.action_names
    if type(names) == "table" then
      for i = 1, #names do st.open_force[names[i]] = true end
    end
  elseif cmd == "action/result" then
    agg.result_frames = agg.result_frames + 1
    st.open_force = nil
  end
end

local function resolve_fallback_sid(decoded, label)
  local startups_without_sid = 0
  for _, frame in ipairs(decoded) do
    if frame.session_id == nil and frame.command == "startup" then
      startups_without_sid = startups_without_sid + 1
    end
  end
  if startups_without_sid > 1 then
    error(string.format(
      "registry_measure: %s has %d startup frames with no session_id -- "
        .. "refusing to guess session boundaries, this looks like a genuinely "
        .. "multi-session file",
      tostring(label), startups_without_sid))
  end
  return "file:" .. tostring(label)
end

function M.process_lines(run, lines, label)
  run = run or M.new_run()
  local frames_before = run.agg.frames

  local decoded = {}
  local malformed = 0
  for _, line in ipairs(lines) do
    local trimmed = line:gsub("%s+$", "")
    if trimmed ~= "" then
      local ok, frame = pcall(json.decode, trimmed)
      if ok and type(frame) == "table" and frame.command then
        decoded[#decoded + 1] = frame
      else
        malformed = malformed + 1
      end
    end
  end

  local fallback_sid = resolve_fallback_sid(decoded, label)

  for _, frame in ipairs(decoded) do
    run.agg.frames = run.agg.frames + 1
    M.process_frame(run, frame, frame.session_id ~= nil and frame.session_id or fallback_sid)
  end
  run.agg.malformed = run.agg.malformed + malformed

  run.files[#run.files + 1] = { label = label, frames = run.agg.frames - frames_before }
  return run
end

function M.process_file(run, path)
  run = run or M.new_run()
  local fh, err = io.open(path, "r")
  if not fh then
    error("registry_measure: cannot open " .. tostring(path) .. ": " .. tostring(err))
  end
  local lines = {}
  for line in fh:lines() do lines[#lines + 1] = line end
  fh:close()
  return M.process_lines(run, lines, path)
end

function M.finalize(run)
  local agg = run.agg
  local unique_count, unique_bytes = 0, 0
  for _, bytes in pairs(agg.c_unique) do
    unique_count = unique_count + 1
    unique_bytes = unique_bytes + bytes
  end
  agg.c_unique_count = unique_count
  agg.c_unique_bytes = unique_bytes
  agg.c_multiplicity_count = unique_count > 0 and (agg.c_instances / unique_count) or 0
  agg.c_multiplicity_bytes = unique_bytes > 0 and (agg.c_instance_bytes / unique_bytes) or 0
  return agg
end

return M
