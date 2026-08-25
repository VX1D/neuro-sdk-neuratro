local Paths = {}

local neuro_log = require("util.utils").neuro_log

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

function Paths.ensure_dir(dir)
  if not dir or dir == "" then return false end
  if love and love.filesystem and love.filesystem.createDirectory then
    local ok_fs, created = pcall(love.filesystem.createDirectory, dir)
    if ok_fs and created == true then return true end
  end
  if dir:find('["`$;|&<>\n]') then
    neuro_log("Refusing to shell-mkdir unsafe path:", dir)
    return false
  end
  if package.config:sub(1, 1) == "\\" then
    os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
  else
    os.execute('mkdir -p "' .. dir .. '"')
  end
  return true
end

local _cached_mod_path = nil
local _mod_path_resolved = false
function Paths.resolve_mod_path()
  if _mod_path_resolved then return _cached_mod_path end
  if SMODS and SMODS.current_mod and SMODS.current_mod.path then
    _cached_mod_path = SMODS.current_mod.path
    _mod_path_resolved = true
    return _cached_mod_path
  end
  if SMODS and SMODS.findModByID then
    local mod = SMODS.findModByID("neuro-game") or SMODS.findModByID("neuro_game")
    if mod and mod.path then
      _cached_mod_path = mod.path
      _mod_path_resolved = true
      return _cached_mod_path
    end
  end
  if SMODS and SMODS.Mods then
    for _, mod in pairs(SMODS.Mods) do
      local id = mod and (mod.id or mod.mod_id)
      if id == "neuro-game" or id == "neuro_game" then
        if mod.path then
          _cached_mod_path = mod.path
          _mod_path_resolved = true
          return _cached_mod_path
        end
      end
    end
  end
  return nil
end

function Paths.read_ipc_dir()
  local env = os.getenv("NEURO_IPC_DIR")
  if env then
    env = trim(env)
    if env ~= "" then
      neuro_log("Loaded IPC dir from env:", env)
      return env
    end
  end
  local mod_path = Paths.resolve_mod_path()
  if not mod_path and love and love.filesystem then
    local source_dir = love.filesystem.getSourceBaseDirectory()
    if source_dir then
      local source_file = debug.getinfo(1, "S").source
      if source_file then
        local file_path = source_file:gsub("^@", "")
        if file_path:find("neuro%-game%.lua$") then
          local dir_path = file_path:match("^(.*)[\\/][^\\/]-$")
          if dir_path then
            mod_path = dir_path
            neuro_log("Resolved mod path from debug info:", mod_path)
          end
        end
      end
    end
  end
  if mod_path then
    local sep = package.config:sub(1, 1)
    local last = mod_path:sub(-1)
    if last ~= sep and last ~= "/" and last ~= "\\" then
      mod_path = mod_path .. sep
    end
    local cfg_filename = "neuro_ipc_dir.txt"
    local full_path = mod_path .. cfg_filename
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
        local clean_path = trim(content)
        if clean_path ~= "" then
          loaded_path = clean_path
        end
      end
    else
      neuro_log("No neuro_ipc_dir.txt found at:", full_path)
    end
    if loaded_path then
      neuro_log("Loaded IPC dir from file:", loaded_path)
      return loaded_path
    end
    local appdata = os.getenv("APPDATA")
    local fallback_dir
    if appdata and appdata ~= "" then
      fallback_dir = appdata .. sep .. "Balatro" .. sep .. "neuro-ipc"
    else
      fallback_dir = mod_path .. "ipc"
    end
    Paths.ensure_dir(fallback_dir)
    local out = io.open(full_path, "w")
    if out then
      out:write(fallback_dir .. "\n")
      out:close()
      neuro_log("Wrote default IPC dir to file:", fallback_dir)
    end
    neuro_log("Using default IPC dir:", fallback_dir)
    return fallback_dir
  end
  print("[neuro-game] Error: could not determine IPC directory.")
  return nil
end

function Paths.write_ipc_marker(ipc_dir)
  if not ipc_dir or ipc_dir == "" then
    return
  end
  local sep = package.config:sub(1, 1)
  local last = ipc_dir:sub(-1)
  local suffix = (last == sep or last == "/" or last == "\\") and "" or sep
  local path = ipc_dir .. suffix .. "neuro_game_loaded.txt"
  local file = io.open(path, "w")
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

function Paths.cookie_path()
  return Paths.mod_relative("assets/cookie.png")
end

return Paths
