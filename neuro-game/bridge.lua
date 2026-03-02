local json = require("neuro_json")
local dotenv = require("dotenv")

local Bridge = {}
Bridge.__index = Bridge

local function now_secs()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function path_join(dir, file)
  local sep = package.config:sub(1, 1)
  if dir:sub(-1) == sep then
    return dir .. file
  end
  return dir .. sep .. file
end

local function truthy_env(name)
  local v = os.getenv(name)
  if not v then return false end
  v = tostring(v):lower()
  return v == "1" or v == "true" or v == "yes" or v == "y" or v == "on"
end

local function is_truthy(value)
  if value == nil then return false end
  local v = tostring(value):lower()
  return v == "1" or v == "true" or v == "yes" or v == "y" or v == "on"
end

local function extract_state_name(message)
  if type(message) ~= "string" then return nil end
  return message:match("STATE:([A-Z_]+)")
end

local function split_lines(text)
  local out = {}
  if type(text) ~= "string" or text == "" then return out end
  for line in text:gmatch("[^\n]+") do
    out[#out + 1] = line
  end
  return out
end

local function line_set(lines)
  local s = {}
  for _, line in ipairs(lines) do
    s[line] = true
  end
  return s
end

local function gen_session_id()
  local t = os.time() * 1000
  Bridge._sid_counter = (Bridge._sid_counter or 0) + 1
  if Bridge._sid_counter > 999 then Bridge._sid_counter = 1 end
  return t + Bridge._sid_counter
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
  o.last_context_state = nil
  o.delta_context = not truthy_env("NEURO_DISABLE_CONTEXT_DELTA")
  o.transition_cooldown = dotenv.num("NEURO_TRANSITION_COOLDOWN", 0.15)
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
      love.filesystem.write(file, data)
    end
    return
  end
  local path = self:fs_path(file)
  local temp_path = path .. ".tmp"
  local f = io.open(temp_path, "wb")
  if not f then
    return
  end
  f:write(data)
  f:flush()
  f:close()
  local ok, err = os.rename(temp_path, path)
  if not ok then
    os.remove(path)
    os.rename(temp_path, path)
  end
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
end

function Bridge:_reset_inbox_to_eof()
  if not self.enabled then
    return
  end
  local truncate = os.getenv("NEURO_INBOX_TRUNCATE_ON_STARTUP")
  if truncate and is_truthy(truncate) then
    self:write_file(self.inbox_file, "")
    self.inbox_pos = 0
    return
  end

  local info = self:file_info(self.inbox_file)
  if info and info.size then
    self.inbox_pos = info.size
  else
    self.inbox_pos = 0
  end

  local data = self:read_file(self.inbox_file)
  if data and #data > 0 then
    local session_id = tostring(self.session_id or "")
    for line in data:gmatch("[^\r\n]+") do
      local ok, msg = pcall(json.decode, line)
      if ok and msg then
        local msg_session = nil
        if msg.session_id ~= nil then
          msg_session = tostring(msg.session_id)
        elseif type(msg.data) == "table" and msg.data.session_id ~= nil then
          msg_session = tostring(msg.data.session_id)
        end
        if msg_session ~= nil and msg_session ~= session_id then
          self:write_file(self.inbox_file, "")
          self.inbox_pos = 0
          return
        end
      end
    end
  end
end

function Bridge:_write_initial_state()
  local s = {
    state = "UNKNOWN",
    game = self.game,
    session_id = self.session_id,
    seq = self.seq,
    started_at = self.started_at,
  }
  local encoded = json.encode(s)
  self:write_file(self.state_file, encoded)
  self.last_state_json = encoded
end

function Bridge:send_startup()
  if not self.enabled then
    return
  end

  local prev_session = self.session_id

  self.session_id = gen_session_id()
  self.seq = 0
  self.last_state = nil
  self.last_context_full = nil
  self.last_context_state = nil
  self.last_transition_at = now_secs()

  self:write_file(self.session_file, tostring(self.session_id) .. "\n")

  self:_reset_inbox_to_eof()

  if truthy_env("NEURO_OUTBOX_TRUNCATE_ON_STARTUP") then
    self:write_file(self.outbox_file, "")
  end

  self:send({
    command = "outbox/reset",
    data = {
      reason = "startup",
      previous_session_id = prev_session,
    }
  })

  self:send({ command = "startup", session_id = self.session_id, game = self.game })
end

function Bridge:send_context(message, silent)
  message = message or ""

  if message == self.last_context_full then
    return
  end

  local out_message = message
  local state_name = extract_state_name(message)

  if self.delta_context and self.last_context_full and self.last_context_state and state_name == self.last_context_state then
    local curr_lines = split_lines(message)
    local prev_lines = split_lines(self.last_context_full)
    local curr_set = line_set(curr_lines)
    local prev_set = line_set(prev_lines)

    local delta = {}
    delta[#delta + 1] = "CTX_DELTA:1"
    delta[#delta + 1] = "STATE:" .. tostring(state_name or "UNKNOWN")

    for _, line in ipairs(curr_lines) do
      if line:find("^CTX_VER:") then
        delta[#delta + 1] = line
      end
    end

    local added = 0
    local removed = 0
    for _, line in ipairs(curr_lines) do
      if not prev_set[line] and not line:find("^STATE:") and not line:find("^CTX_VER:") then
        delta[#delta + 1] = "+" .. line
        added = added + 1
      end
    end
    for _, line in ipairs(prev_lines) do
      if not curr_set[line] and not line:find("^STATE:") and not line:find("^CTX_VER:") then
        delta[#delta + 1] = "-" .. line
        removed = removed + 1
      end
    end

    local delta_text = table.concat(delta, "\n")
    if (added + removed) > 0 and #delta_text < #message then
      out_message = delta_text
    end
  end

  self.last_context_full = message
  self.last_context_state = state_name

  self:send({
    command = "context",
    data = { message = out_message, silent = not not silent }
  })
end

function Bridge:register_actions(actions)
  local names = {}
  for i = 1, #(actions or {}) do
    names[#names + 1] = actions[i].name or ""
  end
  local key = table.concat(names, ",")
  if key == self._last_register_key then return end
  self._last_register_key = key
  self:send({
    command = "actions/register",
    data = { actions = actions or {} }
  })
end

function Bridge:unregister_actions(action_names)
  self:send({
    command = "actions/unregister",
    data = { action_names = action_names or {} }
  })
end

function Bridge:force_actions(state, query, action_names, opts)
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
    self:write_file(self.state_file, encoded)
    self.last_state_json = encoded
  end
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
  if file_size <= 0 then
    return
  end

  if self.inbox_pos > file_size then
    self.inbox_pos = 0
  end

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
    if ok and msg and self.on_message then
      self.on_message(msg)
    end
  end
end

local STATE_WRITE_INTERVAL = 0.25

function Bridge:update(dt)
  self:poll_inbox()
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

    if state_changed or elapsed >= STATE_WRITE_INTERVAL then
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
      end
    end
  end
end

function Bridge:is_transition_cooldown()
  local now = now_secs()
  local elapsed = now - (self.last_transition_at or 0)
  return elapsed < (self.transition_cooldown or 0.3)
end

return Bridge
