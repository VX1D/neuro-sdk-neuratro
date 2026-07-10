local json = require("util.neuro_json")
local dotenv = require("util.dotenv")
local Metrics = require("util.metrics")

local Bridge = {}
Bridge.__index = Bridge

local function now_secs()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.time()
end

local function path_join(dir, file)
  local sep = package.config:sub(1, 1)
  if dir:sub(-1) == sep then
    return dir .. file
  end
  return dir .. sep .. file
end

local function is_truthy(value)
  if value == nil then return false end
  local v = tostring(value):lower()
  return v == "1" or v == "true" or v == "yes" or v == "y" or v == "on"
end

local function truthy_env(name)
  return is_truthy(dotenv.get(name))
end

local function table_is_empty(t)
  if type(t) ~= "table" then return false end
  return next(t) == nil
end

local function copy_schema_for_json(v, key)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, child in pairs(v) do
    out[k] = copy_schema_for_json(child, k)
  end
  if table_is_empty(v) and key ~= "required" and key ~= "enum" then
    return json.object(out)
  end
  return out
end

local function copy_actions_for_json(actions)
  local out = {}
  for i = 1, #(actions or {}) do
    local src = actions[i] or {}
    local dst = {}
    for k, v in pairs(src) do
      if k == "schema" then
        dst[k] = copy_schema_for_json(v, k)
      else
        dst[k] = v
      end
    end
    out[#out + 1] = dst
  end
  return out
end

local function gen_session_id()
  if not Bridge._sid_counter then
    local addr = tostring({}):match("(%x+)$")
    Bridge._sid_counter = (tonumber(addr or "", 16) or 0) % 997
  end
  Bridge._sid_counter = Bridge._sid_counter % 999 + 1
  return os.time() * 1000 + Bridge._sid_counter
end

function Bridge:new(opts)
  local o = setmetatable({}, self)
  o.game = opts.game or "Balatro"
  o.enabled = opts.enabled == true
  o.fs_dir = opts.fs_dir or os.getenv("NEURO_IPC_DIR")
  o.inbox_file = opts.inbox_file or "neuro_inbox.jsonl"
  o.outbox_file = opts.outbox_file or "neuro_outbox.jsonl"
  o.state_file = opts.state_file or "neuro_state.json"
  o.session_file = opts.session_file or "neuro_session.txt"
  o.inbox_pos = 0
  o.last_state_json = nil
  o.on_message = nil
  o.state_provider = nil
  o.state_name_provider = nil
  o.session_id = nil
  o.seq = 0
  o.started_at = now_secs()
  o.last_transition_at = 0
  o.last_state = nil
  o.last_context_full = nil
  o.last_context_spoken = false
  o._registered_set = {}
  return o
end

function Bridge:fs_path(file)
  if not self.fs_dir then
    return file
  end
  return path_join(self.fs_dir, file)
end

function Bridge:file_info(file)
  if not self.fs_dir then
    if love and love.filesystem then
      return love.filesystem.getInfo(file)
    end
    return nil
  end
  local f = io.open(self:fs_path(file), "rb")
  if not f then
    return nil
  end
  local size = f:seek("end")
  f:close()
  return { size = size }
end

function Bridge:read_file(file)
  if not self.fs_dir then
    if love and love.filesystem then
      return love.filesystem.read(file)
    end
    return nil
  end
  local f = io.open(self:fs_path(file), "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

function Bridge:write_file(file, data)
  if not self.fs_dir then
    if love and love.filesystem then
      return not not love.filesystem.write(file, data)
    end
    return false
  end
  local path = self:fs_path(file)
  local temp_path = path .. ".tmp"
  local f = io.open(temp_path, "wb")
  if not f then
    return false
  end
  f:write(data)
  f:flush()
  f:close()
  local ok = os.rename(temp_path, path)
  if not ok then
    -- never remove the destination first: a failed retry would leave it missing
    local dst = io.open(path, "wb")
    if not dst then
      os.remove(temp_path)   -- don't orphan the .tmp when both rename and fallback-open fail
      return false
    end
    dst:write(data)
    dst:flush()
    dst:close()
    os.remove(temp_path)
  end
  return true
end

function Bridge:append_file(file, data)
  if not self.fs_dir then
    if love and love.filesystem then
      local info = love.filesystem.getInfo(file)
      if info then
        love.filesystem.append(file, data)
      else
        love.filesystem.write(file, data)
      end
    end
    return
  end

  local path = self:fs_path(file)
  local f = io.open(path, "ab")
  if f then
    f:write(data)
    f:flush()
    f:close()
  else
    Metrics.incr("ipc_append_fail")
  end
end

function Bridge:set_message_handler(fn)
  self.on_message = fn
end

function Bridge:set_state_provider(fn)
  self.state_provider = fn
end

function Bridge:set_state_name_provider(fn)
  self.state_name_provider = fn
end

function Bridge:_decorate(message)
  message = message or {}

  if self.game and message.game == nil then
    message.game = self.game
  end

  if self.session_id and message.session_id == nil then
    message.session_id = self.session_id
  end

  self.seq = (self.seq or 0) + 1
  if message.seq == nil then
    message.seq = self.seq
  end

  return message
end

function Bridge:send(message)
  if not self.enabled then
    return
  end
  message = self:_decorate(message)
  local line = json.encode(message)
  self:append_file(self.outbox_file, line .. "\n")
  Metrics.incr("ipc_send")
  Metrics.set("ipc_seq", self.seq)
end

-- snapshot pos and rotation signature from one read so an append racing this is never destroyed
function Bridge:_reset_inbox_to_eof()
  if not self.enabled then
    return
  end
  if truthy_env("NEURO_INBOX_TRUNCATE_ON_STARTUP") then
    self:write_file(self.inbox_file, "")
    self.inbox_pos = 0
    self._inbox_sig = nil
    self._inbox_seen_size = nil
    return
  end

  local data = self:read_file(self.inbox_file)
  self.inbox_pos = (data and #data) or 0
  self._inbox_sig = (data and data ~= "") and data:sub(1, 64) or nil
  self._inbox_seen_size = nil
end

function Bridge:send_startup()
  if not self.enabled then
    return
  end

  self.session_id = gen_session_id()
  self.seq = 0
  self.last_state = nil
  self.last_context_full = nil
  self.last_context_spoken = false
  self._registered_set = {}
  self.last_transition_at = now_secs()

  self:write_file(self.session_file, tostring(self.session_id) .. "\n")

  self:_reset_inbox_to_eof()

  if dotenv.bool("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", true) then
    self:write_file(self.outbox_file, "")
  end

  do
    local ok_disp, Dispatcher = pcall(require, "core.dispatcher")
    if ok_disp and Dispatcher and Dispatcher.reset_tx then pcall(Dispatcher.reset_tx) end
  end

  self:send({ command = "startup", session_id = self.session_id, game = self.game })
end

function Bridge:send_context(message, silent)
  if self.llm_paused then return end
  message = message or ""
  silent = not not silent
  if message == self.last_context_full then
    if silent or self.last_context_spoken then
      return
    end
  else
    self.last_context_full = message
    self.last_context_spoken = false
  end
  if not silent then
    self.last_context_spoken = true
  end
  self:send({
    command = "context",
    data = { message = message, silent = silent }
  })
end

-- order-insensitive signature so a schema/description change under the same action name still re-registers
local function schema_sig(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. schema_sig(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function Bridge:register_actions(actions)
  local name_set = {}
  local cur_sig = {}
  local key_parts = {}
  for i = 1, #(actions or {}) do
    local a = actions[i]
    local n = a.name or ""
    name_set[n] = true
    cur_sig[n] = tostring(a.description or "") .. "\1" .. schema_sig(a.schema)
    key_parts[#key_parts + 1] = n .. "\1" .. cur_sig[n]
  end
  local key = table.concat(key_parts, "\2")
  if key == self._last_register_key then return end

  -- server ignores a register for an already-registered name, so a changed action must be unregistered first
  local prev_sig = self._registered_sigs or {}
  local stale = {}
  for n, oldsig in pairs(prev_sig) do
    if cur_sig[n] == nil or cur_sig[n] ~= oldsig then stale[#stale + 1] = n end
  end
  if #stale > 0 then
    self:send({
      command = "actions/unregister",
      data = { action_names = stale }
    })
  end

  self._last_register_key = key
  self._registered_set = name_set
  self._registered_sigs = cur_sig
  self:send({
    command = "actions/register",
    data = { actions = copy_actions_for_json(actions) }
  })
end

function Bridge:force_actions(state, query, action_names, opts)
  if self.llm_paused then return end
  opts = opts or {}
  self:send({
    command = "actions/force",
    data = {
      state = state or "",
      query = query or "",
      ephemeral_context = opts.ephemeral_context,
      priority = opts.priority,
      action_names = action_names or {}
    }
  })
end

function Bridge:send_action_result(id, success, message)
  self:send({
    command = "action/result",
    data = { id = id, success = not not success, message = message }
  })
end

function Bridge:write_state(state)
  if not self.enabled then
    return
  end
  if type(state) == "table" then
    state.session_id = self.session_id
    state.game = self.game
    state.seq = self.seq
    state.started_at = self.started_at
  end
  local encoded = json.encode(state or {})
  if encoded ~= self.last_state_json then
    if self:write_file(self.state_file, encoded) then
      self.last_state_json = encoded
    end
  end
end

function Bridge:_inbox_prefix()
  if not self.fs_dir then
    if love and love.filesystem then
      return love.filesystem.read(self.inbox_file, 64)
    end
    return nil
  end
  local f = io.open(self:fs_path(self.inbox_file), "rb")
  if not f then
    return nil
  end
  local s = f:read(64)
  f:close()
  return s
end

function Bridge:poll_inbox()
  if not self.enabled then
    return
  end
  local info = self:file_info(self.inbox_file)
  if not info then
    return
  end
  local file_size = info.size or 0
  if file_size == self._inbox_seen_size then
    return
  end
  if file_size <= 0 then
    self._inbox_seen_size = file_size
    self.inbox_pos = 0
    self._inbox_sig = nil
    return
  end

  local sig = self:_inbox_prefix()
  if self._inbox_sig and sig ~= self._inbox_sig then
    self.inbox_pos = 0
  elseif self.inbox_pos > file_size then
    -- truncated in place to a prefix of known content: skip, never blind-replay
    self._inbox_seen_size = file_size
    self.inbox_pos = file_size
    self._inbox_sig = sig
    return
  end
  self._inbox_sig = sig

  local chunk = nil
  if self.fs_dir then
    local f = io.open(self:fs_path(self.inbox_file), "rb")
    if not f then
      return
    end
    f:seek("set", self.inbox_pos)
    chunk = f:read("*a")
    f:close()
  else
    local data = self:read_file(self.inbox_file)
    if not data or data == "" then
      return
    end
    chunk = data:sub(self.inbox_pos + 1)
  end
  self._inbox_seen_size = file_size

  if not chunk or chunk == "" then
    return
  end
  local last_newline = chunk:find("\n[^\r\n]*$")
  if last_newline then
    self.inbox_pos = self.inbox_pos + last_newline
  else
    return
  end
  for line in chunk:sub(1, last_newline):gmatch("[^\r\n]+") do
    local ok, msg = pcall(json.decode, line)
    if not ok or not msg then
      Metrics.incr("ipc_decode_error")
    elseif self.on_message then
      Metrics.incr("ipc_inbox_msg")
      local handler_ok, handler_err = xpcall(function()
        return self.on_message(msg)
      end, debug.traceback)
      if not handler_ok then
        Metrics.incr("ipc_handler_error")
        print("[neuro-game] IPC handler error: " .. tostring(handler_err))
      end
    end
  end
end

local Tuning = require("core.tuning")

function Bridge:update(_dt)
  local _np = now_secs()
  if (_np - (self._last_poll or 0)) >= 0.005 then
    self._last_poll = _np
    self:poll_inbox()
  end
  if self.state_provider then
    local now = now_secs()
    local elapsed = now - (self._last_state_write or 0)

    local state_changed = false
    if self.state_name_provider then
      local ok_sn, sn = pcall(self.state_name_provider)
      if ok_sn and sn and sn ~= self.last_state then
        self.last_state = sn
        self.last_transition_at = now
        state_changed = true
      end
    end

    if state_changed or elapsed >= Tuning.get("NEURO_STATE_INTERVAL") then
      local ok, state = pcall(self.state_provider)
      if ok then
        if not self.state_name_provider then
          local sn = state and state.state or nil
          if sn and sn ~= self.last_state then
            self.last_state = sn
            self.last_transition_at = now
          end
        end
        self:write_state(state)
        self._last_state_write = now
        Metrics.incr("ipc_state_write")
      end
    end
  end
end

function Bridge:is_transition_cooldown()
  local now = now_secs()
  local elapsed = now - (self.last_transition_at or 0)
  return elapsed < Tuning.get("NEURO_TRANSITION_COOLDOWN")  -- Tuning.get applies the live cooldown-scale multiplier
end

return Bridge
