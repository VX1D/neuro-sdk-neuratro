local Paths = {}

local neuro_log = require("util.utils").neuro_log

local function trim(s)
  return tostring(s or ""):match("^%s*(.-)%s*$")
end
local function is_absolute_path(path)
  if path:sub(1, 1) == "/" then return true end
  if package.config:sub(1, 1) ~= "\\" then return false end
  return path:sub(1, 2) == "\\" .. "\\" or path:match("^%a:[\\/]") ~= nil
end

local function join(dir, name)
  local last = dir:sub(-1)
  if last == "/" or last == "\\" or last == package.config:sub(1, 1) then return dir .. name end
  return dir .. package.config:sub(1, 1) .. name
end

local function check_ipc_dir(value)
  local dir = trim(value)
  if dir == "" then return nil, "it is empty" end
  if not is_absolute_path(dir) then return nil, "it is not an absolute path" end
  if dir:find('[%c"`$;|&<>]') then return nil, "it contains a shell-unsafe character" end
  return dir
end

local function bounded(value)
  local text = tostring(value or "")
  if #text > 200 then return text:sub(1, 197) .. "..." end
  return text
end

local function dir_is_writable(dir)
  local probe = dir:gsub("[\\/]+$", "") .. "/.neuro_write_probe"
  local file = io.open(probe, "w")
  if not file then return false end
  local closed = file:close()
  os.remove(probe)
  return closed == true
end

local function prepared_ipc_dir(value, source)
  local dir, why = check_ipc_dir(value)
  if not dir then
    print("[neuro-game] Error: " .. source .. " is not an IPC directory ("
      .. why .. "): " .. bounded(value))
    return nil
  end
  if not dir_is_writable(dir) and not Paths.ensure_dir(dir) then
    print("[neuro-game] Error: could not create or write " .. source .. ": " .. dir)
    return nil
  end
  neuro_log("Loaded IPC dir from " .. source .. ":", dir)
  return dir
end


function Paths.ensure_dir(dir)
  if not dir or dir == "" or not is_absolute_path(dir) then return false end
  if love and love.filesystem and love.filesystem.createDirectory then
    local ok_fs, created = pcall(love.filesystem.createDirectory, dir)
    if ok_fs and created == true then return true end
  end
  if dir:find('[%c"`$;|&<>]') then
    neuro_log("Refusing to shell-mkdir unsafe path:", dir)
    return false
  end
  local ok
  if package.config:sub(1, 1) == "\\" then
    ok = os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
  else
    ok = os.execute('mkdir -p "' .. dir .. '"')
  end
  return ok == true or ok == 0
end

local _cached_mod_path = nil
local function absolute(path) return type(path) == "string" and is_absolute_path(path) end
function Paths.resolve_mod_path()
  if _cached_mod_path then return _cached_mod_path end
  local current = SMODS and SMODS.current_mod and SMODS.current_mod.path
  local installed = SMODS and SMODS.Mods and SMODS.Mods["neuro-game"]
  local path = (absolute(current) and current) or (installed and absolute(installed.path) and installed.path) or nil
  _cached_mod_path = path
  return path
end
function Paths.read_ipc_dir()
  local raw_env = trim(os.getenv("NEURO_IPC_DIR"))
  if raw_env ~= "" then
    return prepared_ipc_dir(raw_env, "NEURO_IPC_DIR")
  end
  local mod_path = Paths.resolve_mod_path()
  if not mod_path then
    print("[neuro-game] Error: could not determine installed mod path.")
    return nil
  end

  local sep = package.config:sub(1, 1)
  local cfg_filename = "neuro_ipc_dir.txt"
  local full_path = join(mod_path, cfg_filename)
  local file = io.open(full_path, "r")
  local loaded_path = nil
  if not file then
    file = io.open(full_path .. ".txt", "r")
    if file then
      print("[neuro-game] Warning: found " .. cfg_filename .. ".txt; please rename to " .. cfg_filename)
    end
  end
  if file then
    local content = file:read("*all")
    file:close()
    if content then
      loaded_path = trim(content)
    end
  else
    neuro_log("No neuro_ipc_dir.txt found at:", full_path)
  end
  if loaded_path and loaded_path ~= "" then
    return prepared_ipc_dir(loaded_path, "neuro_ipc_dir.txt")
  end

  local appdata = trim(os.getenv("APPDATA"))
  if appdata ~= "" then
    if not is_absolute_path(appdata) then
      print("[neuro-game] Error: APPDATA is not an absolute path for this runtime; "
        .. "set NEURO_IPC_DIR or create a marker with an absolute path.")
      return nil
    end
    local fallback_dir = appdata .. sep .. "Balatro" .. sep .. "neuro-ipc"
    local prepared_fallback = prepared_ipc_dir(fallback_dir, "default IPC directory")
    if prepared_fallback then
      local out = io.open(full_path, "w")
      if out then
        out:write(prepared_fallback .. "\n")
        out:close()
        neuro_log("Wrote default IPC dir to file:", prepared_fallback)
      end
      neuro_log("Using default IPC dir:", prepared_fallback)
      return prepared_fallback
    end
  end

  print("[neuro-game] Error: no usable IPC directory; set NEURO_IPC_DIR or create an absolute marker.")
  return nil
end

function Paths.write_ipc_marker(ipc_dir)
  if not ipc_dir or ipc_dir == "" then return end
  local file = io.open(join(ipc_dir, "neuro_game_loaded.txt"), "w")
  if file then
    file:write("neuro-game loaded\n")
    file:close()
  end
end

function Paths.mod_relative(suffix)
  suffix = tostring(suffix or "")
  local mod_path = Paths.resolve_mod_path()
  if mod_path then
    local norm = mod_path:gsub("\\", "/")
    local save_dir = love.filesystem.getSaveDirectory()
    if save_dir then
      local norm_save = save_dir:gsub("\\", "/")
      if not norm_save:match("/$") then norm_save = norm_save .. "/" end
      if norm:sub(1, #norm_save) == norm_save then
        norm = norm:sub(#norm_save + 1)
      end
    end
    return norm .. suffix
  end
  return "Mods/neuro-game/" .. suffix
end

return Paths
