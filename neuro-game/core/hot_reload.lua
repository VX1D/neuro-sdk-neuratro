local HotReload = {}

local ARK = {
  ["core.actions"] = true,
  ["core.bridge"] = true,
  ["core.bridge_init"] = true,
  ["core.config"] = true,
  ["core.crash_guards"] = true,
  ["core.dispatcher"] = true,
  ["core.force_state"] = true,
  ["core.hot_reload"] = true,
  ["core.lifecycle_registry"] = true,
  ["core.orchestrator"] = true,
  ["core.staging"] = true,
  ["core.trace"] = true,
  ["core.tx_cache"] = true,
  ["hud.state"] = true,
  ["util.utils"] = true,
}
HotReload.ARK = ARK

local SEP = package.config:sub(1, 1)
local POLL_INTERVAL = 0.25
local SCAN_CHUNK = 48

local _base = nil
local _content = {}
local _not_mod = {}
local _names = {}
local _cursor = 1
local _accum = 0

local _status = {
  base = nil,
  err = nil,
  at = 0,
  swapped = 0,
  summary = nil,
  ark_seen = {},
  ark_order = {},
  locked_seen = {},
  replaced = {},
}

local function rel_of(name)
  return (name:gsub("%.", SEP)) .. ".lua"
end

local function read_rel(rel)
  if not _base then return nil end
  local f = io.open(_base .. rel, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function with_sep(dir)
  local last = dir:sub(-1)
  if last == "/" or last == "\\" or last == SEP then return dir end
  return dir .. SEP
end

local function detect_base()
  local cands = {}

  local ok_paths, Paths = pcall(require, "core.mod_paths")
  if ok_paths and Paths and Paths.resolve_mod_path then
    local ok_p, p = pcall(Paths.resolve_mod_path)
    if ok_p and p and p ~= "" then cands[#cands + 1] = p end
  end

  local src = debug.getinfo(1, "S").source
  if src then
    local file = src:gsub("^@", "")
    local dir = file:match("^(.*)[\\/]core[\\/]hot_reload%.lua$")
    if dir then cands[#cands + 1] = dir end
  end

  local appdata = os.getenv("APPDATA")
  if appdata and appdata ~= "" then
    cands[#cands + 1] = table.concat({ appdata, "Balatro", "Mods", "neuro-game" }, SEP)
  end

  for i = 1, #cands do
    local b = with_sep(cands[i])
    local f = io.open(b .. "neuro-game.lua", "rb")
    if f then
      f:close()
      return b
    end
  end
  return nil
end

local function track(name)
  if _content[name] ~= nil then return true end
  if _not_mod[name] then return false end
  local body = read_rel(rel_of(name))
  if body then
    _content[name] = body
    return true
  end
  _not_mod[name] = true
  return false
end

local _loaded_seen = -1

local function refresh_names()
  local total = 0
  for _ in pairs(package.loaded) do total = total + 1 end
  if total == _loaded_seen and #_names > 0 then return #_names end
  _loaded_seen = total

  local out, n = {}, 0
  for name in pairs(package.loaded) do
    if type(name) == "string" and track(name) then
      n = n + 1
      out[n] = name
    end
  end
  table.sort(out)
  _names = out
  if _cursor > n then _cursor = 1 end
  return n
end

local function shallow_copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function overwrite(dst, src)
  for k in pairs(dst) do dst[k] = nil end
  for k, v in pairs(src) do dst[k] = v end
end

local function map_pair(old, new, remap, depth, seen)
  if depth > 3 or type(old) ~= "table" or type(new) ~= "table" or seen[old] then return end
  seen[old] = true
  for k, ov in pairs(old) do
    local nv = new[k]
    if nv ~= nil and nv ~= ov then
      local to, tn = type(ov), type(nv)
      if to == "function" and tn == "function" then
        remap[ov] = nv
      elseif to == "table" and tn == "table" then
        remap[ov] = nv
        map_pair(ov, nv, remap, depth + 1, seen)
      end
    end
  end
end

local function flush_traces()
  local J = rawget(_G, "jit")
  if type(J) == "table" and type(J.flush) == "function" then pcall(J.flush) end
end

local function rebind(remap)
  if not (debug and debug.getupvalue and debug.setupvalue) then return 0 end
  local hits, seen, budget_seen = 0, {}, {}

  local visit_fn, visit_tbl

  visit_fn = function(f)
    if seen[f] then return end
    seen[f] = true
    local i = 1
    while true do
      local ok, name, val = pcall(debug.getupvalue, f, i)
      if not ok or not name then break end
      if name ~= "_ENV" then
        local rep = remap[val]
        if rep ~= nil then
          if pcall(debug.setupvalue, f, i, rep) then hits = hits + 1 end
        elseif type(val) == "function" then
          visit_fn(val)
        elseif type(val) == "table" then
          visit_tbl(val, 3)
        end
      end
      i = i + 1
    end
  end

  visit_tbl = function(t, depth)
    if depth > 4 then return end
    local before = budget_seen[t]
    if before and before <= depth then return end
    budget_seen[t] = depth
    for _, v in pairs(t) do
      local ty = type(v)
      if ty == "function" then
        visit_fn(v)
      elseif ty == "table" then
        visit_tbl(v, depth + 1)
      end
    end
  end

  for name in pairs(_content) do
    local m = package.loaded[name]
    if type(m) == "table" then
      visit_tbl(m, 0)
    elseif type(m) == "function" then
      visit_fn(m)
    end
  end

  if hits > 0 then flush_traces() end

  return hits
end

local function apply(names)
  local order, chunks = {}, {}

  for i = 1, #names do
    local name = names[i]
    local chunk, err = loadfile(_base .. rel_of(name))
    if not chunk then
      return false, tostring(err), 0
    end
    order[#order + 1] = name
    chunks[name] = chunk
  end

  local undo = {}
  local remap, remap_seen = {}, {}
  for i = 1, #order do
    local name = order[i]
    local old = package.loaded[name]
    if type(old) == "table" then
      undo[#undo + 1] = { name = name, tbl = old, snap = shallow_copy(old), meta = getmetatable(old) }
    else
      undo[#undo + 1] = { name = name, prev = old }
    end

    local ok, new = pcall(chunks[name], name)
    if not ok then
      for j = #undo, 1, -1 do
        local u = undo[j]
        if u.tbl then
          overwrite(u.tbl, u.snap)
          setmetatable(u.tbl, u.meta)
          package.loaded[u.name] = u.tbl
        else
          package.loaded[u.name] = u.prev
        end
      end
      return false, tostring(new), 0
    end

    if type(old) == "table" and type(new) == "table" then
      -- The outgoing chunk's upvalues die with its functions: one call to free what they hold.
      local release = rawget(old, "_hot_reload_release")
      if type(release) == "function" then pcall(release) end
      map_pair(undo[#undo].snap, new, remap, 0, remap_seen)
      overwrite(old, new)
      setmetatable(old, getmetatable(new))
      package.loaded[name] = old
    else
      package.loaded[name] = new
      _status.replaced[name] = true
    end
  end

  local rebound = 0
  if next(remap) then
    local ok_rb, res = pcall(rebind, remap)
    if ok_rb then rebound = res end
  end

  return true, nil, #order, rebound
end

local function note_ark(name)
  if _status.ark_seen[name] then return end
  _status.ark_seen[name] = true
  _status.ark_order[#_status.ark_order + 1] = name
end

local function locked(name)
  local m = package.loaded[name]
  if type(m) ~= "table" then return false end
  local v = rawget(m, "_hot_reload_locked")
  if type(v) == "function" then
    local ok, res = pcall(v)
    return ok and res == true
  end
  return v == true
end

local function note_locked(name)
  if _status.locked_seen[name] then return end
  _status.locked_seen[name] = true
  print("[neuro-game] hot reload: " .. name .. " is locked by its own state; the edit applies when it releases")
end

local function build_summary(count, rebound)
  local parts = { "reloaded " .. count }
  if rebound and rebound > 0 then
    parts[#parts + 1] = "rebound " .. rebound .. " pinned"
  end
  if #_status.ark_order > 0 then
    parts[#parts + 1] = "RESTART NEEDED for " .. table.concat(_status.ark_order, ", ")
  end
  return table.concat(parts, "  |  ")
end

function HotReload.reload(force)
  if not _base then
    _status.err = "mod base path unresolved"
    return false
  end

  refresh_names()

  local changed, bodies, ark_changed = {}, {}, 0
  for i = 1, #_names do
    local name = _names[i]
    local body = read_rel(rel_of(name))
    if body then
      if ARK[name] then
        if body ~= _content[name] then
          _content[name] = body
          ark_changed = ark_changed + 1
          note_ark(name)
        end
      elseif locked(name) then
        if body ~= _content[name] then note_locked(name) end
      elseif force or body ~= _content[name] then
        changed[#changed + 1] = name
        bodies[name] = body
        _status.locked_seen[name] = nil
      end
    end
  end

  if #changed == 0 then
    if ark_changed > 0 then
      _status.summary = build_summary(0, 0)
      print("[neuro-game] hot reload: " .. _status.summary)
    end
    return true
  end

  local ok, err, count, rebound = apply(changed)
  if not ok then
    _status.err = err
    print("[neuro-game] RELOAD FAILED (keeping last good): " .. err)
    return false
  end

  for i = 1, #changed do
    _content[changed[i]] = bodies[changed[i]]
  end

  local S = package.loaded["hud.state"]
  if S and type(S.invalidate_caches) == "function" then
    pcall(S.invalidate_caches)
  end

  _status.err = nil
  _status.swapped = count
  _status.rebound = rebound
  _status.summary = build_summary(count, rebound)
  print("[neuro-game] hot reload: " .. _status.summary)
  return true
end

function HotReload.poll(dt)
  if not _base then return end
  _accum = _accum + (dt or 0)
  if _accum < POLL_INTERVAL then return end
  _accum = 0

  local n = refresh_names()
  if n == 0 then return end

  local dirty = false
  local budget = SCAN_CHUNK
  if budget > n then budget = n end
  for _ = 1, budget do
    local name = _names[_cursor]
    _cursor = _cursor + 1
    if _cursor > n then _cursor = 1 end
    if name then
      local body = read_rel(rel_of(name))
      if body and body ~= _content[name] then
        dirty = true
        break
      end
    end
  end

  if dirty then HotReload.reload(false) end
end

function HotReload.init()
  _base = detect_base()
  _status.base = _base
  if not _base then return false end
  refresh_names()
  return true
end

function HotReload.status()
  return _status
end

function HotReload.base()
  return _base
end

if rawget(_G, "NEURO_TEST") then HotReload._test = {
  rel_of = rel_of,
  apply = apply,
  is_ark = function(name) return ARK[name] == true end,
  watched = function()
    local out = {}
    for i = 1, #_names do out[i] = _names[i] end
    return out
  end,
  set_base = function(b) _base = b and with_sep(b) or nil; _status.base = _base end,
  reset = function()
    _content, _not_mod, _names, _cursor, _accum = {}, {}, {}, 1, 0
    _loaded_seen = -1
    _status.err, _status.summary, _status.swapped = nil, nil, 0
    _status.ark_seen, _status.ark_order, _status.replaced = {}, {}, {}
    _status.locked_seen = {}
  end,
} end

return HotReload
