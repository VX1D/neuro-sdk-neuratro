local json = require("util.neuro_json")
local Metrics = require("util.metrics")
local ActionSchema = require("core.action_schema")
local Utils = require("util.utils")

local Bridge = {}
Bridge.__index = Bridge


local W = {}
Bridge.wire = W
W.COMMANDS = {
  STARTUP = "startup",
  CONTEXT = "context",
  REGISTER = "actions/register",
  UNREGISTER = "actions/unregister",
  FORCE = "actions/force",
  RESULT = "action/result",
}
local C = W.COMMANDS
W.WIRE_FIELDS = { "command", "game", "data" }
W.RESULT_DATA_FIELDS = { "id", "success", "message" }
W.DATA_FIELDS = {
  [C.CONTEXT] = { "message", "silent" },
  [C.REGISTER] = { "actions" },
  [C.UNREGISTER] = { "action_names" },
  [C.FORCE] = { "state", "query", "ephemeral_context", "priority", "action_names" },
  [C.RESULT] = W.RESULT_DATA_FIELDS,
}
W.TRANSPORT_FIELDS = { "session_id", "run_generation", "seq", "reason_code", "transport_session" }
W.CONTROL_PREFIX = "neuro-bridge/"
W.STARTUP_ANSWER = W.CONTROL_PREFIX .. "startup_answer"
W.INVALID_ACTION_NAME = "\0neuro-invalid-action-name"
W.MAX_ACTION_ID_BYTES = 1024 * 1024
W.valid_action_name = ActionSchema.valid_action_name

local MAX_ACTION_NAMES = 256
local FORCE_PRIORITIES = { low = true, medium = true, high = true, critical = true }
local REREGISTER_ALL = W.CONTROL_PREFIX .. "reregister_all"

function W.is_transport_control(command)
  return type(command) == "string" and command:sub(1, #W.CONTROL_PREFIX) == W.CONTROL_PREFIX
end

function W.valid_action_id(value)
  return type(value) == "string" and value ~= "" and json.is_valid_utf8(value)
    and #json.encode(value) <= W.MAX_ACTION_ID_BYTES
end

local function valid_game(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function dense(value, item_valid, key, max_count)
  if type(value) ~= "table" then return false end
  local count, max, seen = 0, 0, {}
  for k, item in pairs(value) do
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) or not item_valid(item) then return false end
    count = count + 1
    if max_count and count > max_count then return false end
    if k > max then max = k end
    if key then
      local id = key(item)
      if seen[id] then return false end
      seen[id] = true
    end
  end
  return count > 0 and max == count
end

local function itself(v) return v end
local function def_name(def) return def.name end

function W.valid_action_names(value)
  return dense(value, W.valid_action_name, itself, MAX_ACTION_NAMES)
end

local VALID_DATA = {
  [C.CONTEXT] = function(d) return type(d.message) == "string" and type(d.silent) == "boolean" end,
  [C.REGISTER] = function(d) return dense(d.actions, ActionSchema.valid_definition, def_name) end,
  [C.UNREGISTER] = function(d) return W.valid_action_names(d.action_names) end,
  [C.FORCE] = function(d)
    return type(d.query) == "string" and (d.state == nil or type(d.state) == "string")
      and W.valid_action_names(d.action_names)
      and (d.ephemeral_context == nil or type(d.ephemeral_context) == "boolean")
      and (d.priority == nil or FORCE_PRIORITIES[d.priority] == true)
  end,
  [C.RESULT] = function(d)
    return W.valid_action_id(d.id) and type(d.success) == "boolean"
      and (d.message == nil or type(d.message) == "string")
  end,
}

local function project_definition(def)
  local out = { name = def.name, description = def.description }
  if def.schema ~= nil then out.schema = ActionSchema.copy_schema_for_json(def.schema, "schema") end
  return out
end

local function copy_list(list, map)
  local out = {}
  for i = 1, #list do out[i] = map and map(list[i]) or list[i] end
  return out
end

local function frame(command, data)
  if not VALID_DATA[command](data) then return nil end
  return { command = command, data = data }
end

function W.startup(game)
  if not valid_game(game) then return nil end
  return { command = C.STARTUP, game = game }
end

function W.startup_answer(game, transport_session)
  local session = transport_session ~= nil and tostring(transport_session) or ""
  if not valid_game(game) or session == "" then return nil end
  return { command = W.STARTUP_ANSWER, game = game, transport_session = session }
end

function W.context(message, silent)
  if silent == nil then silent = false end
  return frame(C.CONTEXT, { message = message, silent = silent })
end

function W.register(actions)
  if not VALID_DATA[C.REGISTER]({ actions = actions }) then return nil end
  return { command = C.REGISTER, data = { actions = copy_list(actions, project_definition) } }
end

function W.unregister(action_names)
  if not W.valid_action_names(action_names) then return nil end
  return { command = C.UNREGISTER, data = { action_names = copy_list(action_names) } }
end

function W.force(state, query, action_names, opts)
  if opts ~= nil and type(opts) ~= "table" then return nil end
  opts = opts or {}
  if type(state) == "string" then state = json.scrub_utf8(state) end
  if type(query) == "string" then query = json.scrub_utf8(query) end
  local data = { state = state, query = query, ephemeral_context = opts.ephemeral_context,
    priority = opts.priority, action_names = action_names }
  if not VALID_DATA[C.FORCE](data) then return nil end
  data.action_names = copy_list(action_names)
  return { command = C.FORCE, data = data }
end

function W.result(id, success, message)
  if type(message) == "string" then message = json.scrub_utf8(message) end
  return frame(C.RESULT, { id = id, success = success, message = message })
end


local TX = {}
Bridge.tx = TX
-- Remember answered ids for the transport session so a resent id cannot receive a second result.
local owed, answered = {}, {}

function TX.open(id, name, at)
  if type(id) ~= "string" or id == "" or owed[id] or answered[id] then return false end
  local window = G and G.NEURO and G.NEURO.force_window
  owed[id] = { key = id, name = name, opened_at = tonumber(at) or 0,
    window_id = type(window) == "table" and window.id or nil }
  return true
end

function TX.store(id)
  if type(id) ~= "string" or id == "" then return false end
  answered[id] = true
  owed[id] = nil
  return true
end

function TX.get(id) return answered[id] end

function TX.outstanding(now, deadline)
  local out, cutoff = {}, tonumber(deadline)
  for _, entry in pairs(owed) do
    if cutoff == nil or (tonumber(now) or 0) - entry.opened_at >= cutoff then out[#out + 1] = entry end
  end
  table.sort(out, function(a, b)
    if a.opened_at == b.opened_at then return a.key < b.key end
    return a.opened_at < b.opened_at
  end)
  return out
end

function TX.reset()
  owed, answered = {}, {}
end


local MAX_LINE_BYTES = 8 * 1024 * 1024
local INBOX_ANCHOR_BYTES = 256
Bridge.MAX_OUTBOX_FILE_BYTES = 64 * 1024 * 1024
Bridge.MAX_OUTBOUND_LINE_BYTES = MAX_LINE_BYTES
Bridge.MAX_ACTION_ID_BYTES = W.MAX_ACTION_ID_BYTES
Bridge.HEARTBEAT_INTERVAL_SECS = 1
Bridge.RESULT_DEADLINE_SECS = 5
Bridge.SERVER_RESULT_WINDOW_SECS = 20
Bridge.OWED_DEADLINE_MESSAGE =
  "The game never produced a result for this action within its own deadline; it was not executed and nothing happened in game. Inspect the current state and choose again."
Bridge.OWED_SHUTDOWN_MESSAGE =
  "The game is shutting down and never executed this action; nothing happened in game."
local OVERSIZED_RESULT_MESSAGE =
  "The game returned an oversized result message; inspect the current state and choose again."

local function note_registry(fn_name, names)
  local ok, registry = pcall(require, "core.action_registry")
  if ok and type(registry[fn_name]) == "function" then pcall(registry[fn_name], names) end
end

local function read_from(path, offset)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  local data
  if type(size) == "number" and size >= offset and f:seek("set", offset) then
    data = f:read(size - offset) or ""
  end
  f:close()
  return data
end

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local size = f:seek("end")
  f:close()
  return size
end

local function pending(self)
  self._fifo = self._fifo or {}
  return self._fifo
end

local function mirror(self)
  self._registered_sigs = self._registered_sigs or {}
end

function Bridge:new(opts)
  opts = type(opts) == "table" and opts or {}
  local o = setmetatable({}, self)
  o.game = opts.game or "Balatro"
  assert(valid_game(o.game), "game name is required")
  o.enabled = opts.enabled == true
  o.fs_dir = opts.fs_dir or os.getenv("NEURO_IPC_DIR")
  o.inbox_file = opts.inbox_file or "neuro_inbox.jsonl"
  o.outbox_file = opts.outbox_file or "neuro_outbox.jsonl"
  o.heartbeat_file = opts.heartbeat_file or "neuro_heartbeat.txt"
  o.inbox_pos = 0
  o._inbox_anchor = ""
  o.seq = 0
  o.last_transition_at = 0
  mirror(o)
  local outbox = o:fs_path(o.outbox_file)
  local tail = o.enabled and o.fs_dir and read_from(outbox, math.max(0, file_size(outbox) - 1))
  if tail and tail ~= "" and tail ~= "\n" then
    pending(o)[1] = "\n"
    o._torn = true
  end
  return o
end

function Bridge:fs_path(file)
  if not self.fs_dir then return file end
  local sep = package.config:sub(1, 1)
  if self.fs_dir:sub(-1) == sep then return self.fs_dir .. file end
  return self.fs_dir .. sep .. file
end

function Bridge:set_message_handler(fn) self.on_message = fn end
function Bridge:set_state_name_provider(fn) self.state_name_provider = fn end

local bit = require("bit")
local ffi = require("ffi")
local U64 = ffi.typeof("uint64_t")
local WORDS = ffi.typeof("uint64_t[?]")
local LITTLE_ENDIAN = ffi.abi("le")
local FNV_OFFSET = U64(0xcbf29ce4) * 0x100000000 + 0x84222325
local FNV_PRIME = U64(0x100000000) * 0x100 + 0x1b3
local FENCE_CHUNK = 64 * 1024
local CURSOR_WORDS = 7

-- os.time has whole seconds only; the outbox timestamps need milliseconds.
local wall_ms = function() return os.time() * 1000 end
pcall(function()
  if ffi.os == "Windows" then
    pcall(ffi.cdef, "void GetSystemTimeAsFileTime(uint64_t *filetime);")
    local filetime = ffi.new("uint64_t[1]")
    ffi.C.GetSystemTimeAsFileTime(filetime)
    wall_ms = function()
      ffi.C.GetSystemTimeAsFileTime(filetime)
      return tonumber(filetime[0] / 10000) - 11644473600000
    end
  else
    pcall(ffi.cdef, "typedef struct { long tv_sec; long tv_usec; } neuro_timeval; int gettimeofday(neuro_timeval *tv, void *tz);")
    local tv = ffi.new("neuro_timeval")
    ffi.C.gettimeofday(tv, nil)
    wall_ms = function()
      ffi.C.gettimeofday(tv, nil)
      return tonumber(tv.tv_sec) * 1000 + math.floor(tonumber(tv.tv_usec) / 1000)
    end
  end
end)

local function utc_timestamp()
  local ms = wall_ms()
  return os.date("!%Y-%m-%dT%H:%M:%S", math.floor(ms / 1000)) .. string.format(".%03dZ", ms % 1000)
end

local function mix(hash, word) return bit.bxor(hash, word) * FNV_PRIME end

local function words_of(bytes)
  local n = math.ceil(#bytes / 8)
  local words = WORDS(n)
  ffi.copy(words, bytes, #bytes)
  if not LITTLE_ENDIAN then
    for i = 0, n - 1 do words[i] = bit.bswap(words[i]) end
  end
  return words, n
end

local function mix_words(hash, bytes)
  hash = mix(hash, U64(#bytes))
  local words, n = words_of(bytes)
  for i = 0, n - 1 do hash = mix(hash, words[i]) end
  return hash
end

local CURSOR_MAGIC = words_of("NBCURSOR")[0]

local function fence_fingerprint(path, pos, len)
  local f = io.open(path, "rb")
  if not f then return nil end
  local hash = mix(mix(FNV_OFFSET, U64(pos)), U64(len))
  local samples = len <= 2 * FENCE_CHUNK and { { 0, len } } or { { 0, FENCE_CHUNK }, { len - FENCE_CHUNK, FENCE_CHUNK } }
  for _, s in ipairs(samples) do
    local buf = f:seek("set", s[1]) and f:read(s[2]) or ""
    if #buf ~= s[2] then f:close(); return nil end
    hash = mix_words(mix(hash, U64(s[1])), buf)
  end
  f:close()
  return hash
end

local function decode_cursor(record)
  if #record ~= CURSOR_WORDS * 8 then return nil end
  local w = words_of(record)
  local sum = FNV_OFFSET
  for i = 0, CURSOR_WORDS - 2 do sum = mix(sum, w[i]) end
  if w[0] ~= CURSOR_MAGIC or w[CURSOR_WORDS - 1] ~= sum then return nil end
  return tonumber(w[1]), tonumber(w[2]), w[5]
end

local function relay_draining_rotated(self, path)
  local rotated = path .. ".1"
  local record = read_from(path .. ".cursor", 0)
  if not record then return false end
  local size = file_size(rotated)
  local key = record .. "\0" .. size
  if self._rotation_fence and self._rotation_fence.key == key then return self._rotation_fence.draining end
  local pos, len, want = decode_cursor(record)
  local draining = false
  if pos and len and want and pos <= len and pos < size and size >= len then
    draining = fence_fingerprint(rotated, pos, len) == want
  end
  if draining then Metrics.incr("ipc_outbox_rotation_deferred") end
  self._rotation_fence = { key = key, draining = draining }
  return draining
end

function Bridge:_append(data)
  local path = self:fs_path(self.outbox_file)
  local before = file_size(path)
  if not before then return 0 end
  if not self._torn and before > 0 and before + #data > self.MAX_OUTBOX_FILE_BYTES
      and not relay_draining_rotated(self, path) then
    os.remove(path .. ".1")
    if os.rename(path, path .. ".1") then
      before = 0
      Metrics.incr("ipc_outbox_rotated")
    end
  end
  local f = io.open(path, "ab")
  local ok = f ~= nil and f:write(data) ~= nil and f:flush() ~= nil
  local closed = f ~= nil and f:close() == true
  if ok and closed then return #data end
  return math.max(0, math.min(#data, (file_size(path) or before) - before))
end

function Bridge:flush_outbox()
  local fifo = pending(self)
  while fifo[1] do
    local line = fifo[1]
    local landed = self:_append(line)
    if landed < #line then
      Metrics.incr("ipc_append_fail")
      if landed > 0 then
        fifo[1] = line:sub(landed + 1)
        self._torn = true
      end
      return false
    end
    table.remove(fifo, 1)
    self._torn = false
  end
  return true
end

function Bridge:is_transport_saturated()
  return pending(self)[1] ~= nil
end

local function refuse(receipt, metric)
  if receipt then
    receipt.status = "rejected"
    receipt.reason = metric
  end
  if metric then Metrics.incr(metric) end
  return false
end

local function encode(self, message)
  if message.game ~= nil and message.game ~= self.game then return nil, "ipc_game_mismatch_rejected" end
  local ok, encoded = pcall(json.encode,
    { ts = utc_timestamp(), command = message.command, game = self.game, data = message.data })
  if not ok or type(encoded) ~= "string" then return nil, "ipc_unencodable_frame_rejected" end
  if #encoded + 1 > MAX_LINE_BYTES then return nil, "ipc_oversized_frame_rejected" end
  return encoded .. "\n"
end

local function enqueue(self, line, receipt)
  self.seq = (self.seq or 0) + 1
  local fifo = pending(self)
  fifo[#fifo + 1] = line
  self:flush_outbox()
  if receipt then
    receipt.status = "written"
    receipt.written_at = Utils.now()
  end
  Metrics.incr("ipc_send")
  return true
end

local PROSE_FIELDS = { [C.CONTEXT] = { "message" }, [C.FORCE] = { "state", "query" }, [C.RESULT] = { "message" } }
local function assert_no_action_names(message)
  local catalog = {}
  for _, name in ipairs(require("core.action_registry").names()) do catalog[name] = true end
  for _, field in ipairs(PROSE_FIELDS[message.command] or {}) do
    local text = message.data and message.data[field]
    -- The reference SDK's unknown-action reply echoes the name she sent.
    if message.command == C.RESULT and type(text) == "string" and text:find("^Action failed%. Unknown action '") then
      text = nil
    end
    local named = require("force.force_references").named_actions(text, catalog)
    if #named > 0 then
      error(message.command .. " " .. field .. " names the action " .. table.concat(named, ", ") .. ": "
        .. tostring(message.data[field]), 3)
    end
  end
end

function Bridge:send(message, receipt)
  if not self.enabled then return refuse(receipt) end
  if rawget(_G, "NEURO_TEST") and type(message) == "table" then assert_no_action_names(message) end
  if type(message) ~= "table" or (message.command ~= C.STARTUP and not VALID_DATA[message.command]) then
    return refuse(receipt, "ipc_invalid_frame_rejected")
  end
  local command = message.command
  if (command == C.REGISTER or command == C.UNREGISTER) and not self._catalogue_send then
    return refuse(receipt, "ipc_catalogue_bypass_rejected")
  end
  if command == C.FORCE and self._force_open then return refuse(receipt, "ipc_force_overlap_rejected") end
  local line, fault = encode(self, message)
  if not line then return refuse(receipt, fault) end
  if command == C.FORCE then self._force_open = true end
  return enqueue(self, line, receipt)
end

function Bridge:_skip_stale_inbox()
  local data = read_from(self:fs_path(self.inbox_file), 0) or ""
  local pos = 0
  for line, stop in data:gmatch("([^\n]*)\n()") do
    pos = stop - 1
    if line:find(REREGISTER_ALL, 1, true) then
      local ok, msg = pcall(json.decode, line)
      if ok and type(msg) == "table" and msg.command == REREGISTER_ALL
          and msg.transport_session ~= nil and tostring(msg.transport_session) ~= "" then
        self.transport_session = tostring(msg.transport_session)
      end
    end
  end
  self.inbox_pos = pos
  self._inbox_anchor = data:sub(math.max(1, pos - INBOX_ANCHOR_BYTES + 1), pos)
end

function Bridge:reset_delivery_memory()
  self._last_register_key = nil
  self._force_full_register = true
  self._withdrawn_held = nil
  self:release_force_lock()
end

function Bridge:release_force_lock()
  if type(self) ~= "table" then return end
  self._force_open = nil
  self._active_force_proposal_ref = nil
end

function Bridge:send_startup(opts)
  if not self.enabled then return end
  opts = type(opts) == "table" and opts or {}
  if not opts.reconnect and not self._startup_complete then self:_skip_stale_inbox() end
  local line = encode(self, W.startup(self.game))
  local answer = W.startup_answer(self.game, self.transport_session)
  if answer then
    answer.ts = utc_timestamp()
    line = json.encode(answer) .. "\n" .. line
  end
  self.session_id = (self.session_id or 0) + 1
  self.last_state = nil
  self.last_transition_at = Utils.gate_now("bridge_transition_cooldown")
  enqueue(self, line)
  self:reset_delivery_memory()
  self._registered_sigs = {}
  if not opts.reconnect then
    local ok, Dispatcher = pcall(require, "core.dispatcher")
    if ok and Dispatcher and Dispatcher.reset_tx then pcall(Dispatcher.reset_tx) end
  end
  self._startup_complete = true
  return true
end

function Bridge:send_context(message, silent, receipt)
  receipt = receipt or {}
  if self.llm_paused or not self.enabled then return refuse(receipt), false, receipt end
  local frame_out = W.context(message, silent)
  if not frame_out then return refuse(receipt, "context_invalid_frame"), false, receipt end
  return self:send(frame_out, receipt), false, receipt
end

function Bridge:beat()
  if not self.fs_dir then return false end
  local now = Utils.gate_now("game_heartbeat")
  if self._beat_at and now >= self._beat_at and now - self._beat_at < Bridge.HEARTBEAT_INTERVAL_SECS then
    return false
  end
  self._beat_at = now
  self._beat_count = (self._beat_count or 0) + 1
  local f = io.open(self:fs_path(self.heartbeat_file), "wb")
  if not f then return false end
  local ok = f:write(tostring(self._beat_count) .. "\n") ~= nil
  return f:close() == true and ok
end

function Bridge:update(_dt)
  if self.enabled then
    self:beat()
    self:flush_outbox()
    local now = Utils.gate_now("inbox_poll")
    if now - (self._last_poll or 0) >= 0.005 then
      self._last_poll = now
      self:poll_inbox()
    end
    self:answer_owed_results(Bridge.RESULT_DEADLINE_SECS)
  end
  if self.state_name_provider then
    local ok, name = pcall(self.state_name_provider)
    if ok and name and name ~= self.last_state then
      self.last_state = name
      self.last_transition_at = Utils.gate_now("bridge_transition_cooldown")
    end
  end
end

function Bridge:is_transition_cooldown()
  local elapsed = Utils.gate_now("bridge_transition_cooldown") - (self.last_transition_at or 0)
  return elapsed < Utils.gate_seconds("bridge_transition_cooldown")
end


local function send_catalogue(self, frame_out, receipt)
  self._catalogue_send = true
  local sent = self:send(frame_out, receipt)
  self._catalogue_send = nil
  return sent ~= false and receipt.status ~= "rejected"
end

local function schema_sig(schema)
  local ok, encoded = pcall(function()
    return json.encode(ActionSchema.copy_schema_for_json(schema, "schema"))
  end)
  return ok and type(encoded) == "string" and encoded or nil
end

function Bridge:register_actions(actions)
  if next(actions) == nil then return false end
  mirror(self)
  local prev_sig, full = self._registered_sigs, self._force_full_register == true
  local cur_sig = {}
  for name, sig in pairs(prev_sig) do cur_sig[name] = sig end
  local key_parts, fresh = {}, {}
  for _, incoming in ipairs(actions) do
    local encoded_schema = schema_sig(incoming.schema)
    if not encoded_schema then
      Metrics.incr("actions_register_unencodable_definition")
      return false
    end
    local name = incoming.name
    local sig = tostring(incoming.description or "") .. "\1" .. encoded_schema
    if full or prev_sig[name] ~= sig then fresh[#fresh + 1] = incoming end
    cur_sig[name] = sig
    key_parts[#key_parts + 1] = name .. "\1" .. sig
  end
  local key = table.concat(key_parts, "\2")
  local live_names = {}
  for name in pairs(cur_sig) do live_names[#live_names + 1] = name end
  if not full and key == self._last_register_key then fresh = {} end
  if #fresh > 0 then
    local frame_out = W.register(fresh)
    if not frame_out or not send_catalogue(self, frame_out, { status = "sending", kind = "actions_register" }) then
      Metrics.incr("actions_register_catalogue_capacity")
      return false
    end
    note_registry("note_registered", copy_list(fresh, def_name))
  end
  self._last_register_key = key
  self._force_full_register = nil
  self._registered_sigs = cur_sig
  note_registry("note_registered", live_names)
  return true
end

function Bridge:withdraw_actions(action_names)
  local seen, names = {}, {}
  for _, name in ipairs(action_names or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)
  mirror(self)
  local wire_names = {}
  for _, name in ipairs(names) do
    if self._registered_sigs[name] then wire_names[#wire_names + 1] = name end
  end
  if #wire_names > 0 and not send_catalogue(self, W.unregister(wire_names), { status = "sending" }) then
    return false
  end
  local held = self._withdrawn_held or {}
  for _, name in ipairs(names) do
    self._registered_sigs[name] = nil
    held[name] = true
  end
  self._last_register_key = nil
  self._withdrawn_held = held
  note_registry("note_unregistered", names)
  return true
end

function Bridge:unregister_all()
  mirror(self)
  local list = {}
  for name in pairs(self._registered_sigs) do list[#list + 1] = name end
  if #list > 0 then self:withdraw_actions(list) end
end

function Bridge:force_actions(state, query, action_names, opts)
  if self.llm_paused or self.enabled == false then return false end
  if self._force_open then
    Metrics.incr("force_send_while_open_rejected")
    return false
  end
  mirror(self)
  local function forceable(name)
    return self._registered_sigs[name] ~= nil
  end
  if not dense(action_names, forceable, itself) then
    Metrics.incr("force_send_invalid_actions")
    return false
  end
  opts = opts or {}
  local frame_out = W.force(state, query, action_names, opts)
  if not frame_out then
    Metrics.incr("force_send_invalid_context")
    return false, { status = "rejected", kind = "actions_force" }
  end
  local receipt = { kind = "actions_force", actions = action_names }
  if not self:send(frame_out, receipt) then return false, receipt end
  self._active_force_proposal_ref = opts.confirmation_proposal_ref
  Metrics.incr("force_sent")
  Metrics.set("force_available_actions", #action_names)
  Metrics.set("force_context_bytes", #(state or "") + #query)
  return true, receipt
end

function Bridge:confirmation_proposal_ref(_id)
  return self._active_force_proposal_ref
end


function Bridge:send_action_result(id, success, message)
  if not W.valid_action_id(id) or type(success) ~= "boolean"
      or (message ~= nil and type(message) ~= "string") then
    Metrics.incr("action_result_invalid_payload")
    return false
  end
  if TX.get(id) then
    Metrics.incr("action_result_refused_duplicate")
    return false
  end
  local receipt = { kind = "action_result" }
  if not self:send(W.result(id, success, message), receipt) then
    if receipt.reason ~= "ipc_oversized_frame_rejected" then return false end
    Metrics.incr("action_result_message_replaced")
    message = OVERSIZED_RESULT_MESSAGE
    if not self:send(W.result(id, success, message), receipt) then return false end
  end
  TX.store(id)
  return true
end

function Bridge:answer_owed_results(deadline, message)
  if not self.enabled then return 0 end
  local paid = 0
  local Execute = require("core.execute")
  local now = Utils.gate_now("result_deadline")
  for _, entry in ipairs(TX.outstanding(now, deadline)) do
    if Execute.answer(self, entry.key, entry.name, true, message or Bridge.OWED_DEADLINE_MESSAGE, nil, nil, entry.window_id or false) then
      Metrics.incr("action_result_owed_paid")
      paid = paid + 1
    elseif now - entry.opened_at >= Bridge.SERVER_RESULT_WINDOW_SECS then
      -- Once the server’s result window expires, discard the late result and withdraw its force.
      Metrics.incr("action_result_owed_abandoned")
      TX.store(entry.key)
      local Window = require("core.window")
      local current = Window.current()
      if current and current.id == entry.window_id then Window.withdraw("result_lost") end
    else
      Metrics.incr("action_result_owed_retry")
    end
  end
  return paid
end


function Bridge:_deliver_inbox_message(msg, handler)
  Metrics.incr("ipc_inbox_msg")
  local session = W.is_transport_control(msg.command) and msg.transport_session or nil
  for _, field in ipairs(W.TRANSPORT_FIELDS) do msg[field] = nil end
  msg.transport_session = session
  if msg.command == "action" and type(msg.data) == "string" then
    local ok, decoded = pcall(json.decode, msg.data)
    if ok and type(decoded) == "table" then msg.data = decoded end
  end
  local data = msg.command == "action" and type(msg.data) == "table" and msg.data or nil
  if data and type(data.id) == "string" and data.id ~= "" then
    if not TX.open(data.id, data.name, Utils.gate_now("result_deadline")) then
      Metrics.incr("action_result_duplicate_suppressed")
      return false
    end
  end
  local on_message = handler or self.on_message
  if not on_message then
    Metrics.incr("ipc_inbox_undelivered")
    return false
  end
  local ok, result = xpcall(function() return on_message(msg) end, debug.traceback)
  if not ok then
    Metrics.incr("ipc_handler_error")
    print("[neuro-game] IPC handler error (details redacted)")
    return false
  end
  return result
end

local function advance(self, bytes)
  self.inbox_pos = self.inbox_pos + #bytes
  self._inbox_anchor = (self._inbox_anchor .. bytes):sub(-INBOX_ANCHOR_BYTES)
end

local function discard(bytes)
  Metrics.incr("ipc_line_oversize")
  print("[neuro-game] IPC inbox line discarded (exceeds " .. MAX_LINE_BYTES .. " bytes; received "
    .. bytes .. " bytes)")
end

function Bridge:_consume(data)
  local start = 1
  while true do
    if pending(self)[1] then return false end
    local newline = data:find("\n", start, true)
    if not newline then
      if #data - start + 1 > MAX_LINE_BYTES then
        discard(#data - start + 1)
        advance(self, data:sub(start))
        self._inbox_skipping = true
      end
      return true
    end
    local line = data:sub(start, newline - 1)
    advance(self, data:sub(start, newline))
    start = newline + 1
    line = line:gsub("\r$", "")
    if self._inbox_skipping then
      self._inbox_skipping = nil
    elseif #line > MAX_LINE_BYTES then
      discard(#line)
    elseif line ~= "" then
      local ok, msg = pcall(json.decode, line)
      if ok and type(msg) == "table" and type(msg.command) == "string" then
        if not pcall(self._deliver_inbox_message, self, msg) then Metrics.incr("ipc_handler_error") end
      else
        Metrics.incr("ipc_decode_error")
        print("[neuro-game] IPC inbox line discarded (not a message; received " .. #line .. " bytes)")
      end
    end
  end
end

function Bridge:poll_inbox()
  if not self.enabled or pending(self)[1] then return end
  local path = self:fs_path(self.inbox_file)
  local anchor = self._inbox_anchor
  local data = read_from(path, self.inbox_pos - #anchor)
  if self.inbox_pos > 0 and (data == nil or data:sub(1, #anchor) ~= anchor) then
    local old = read_from(path .. ".1", self.inbox_pos - #anchor)
    if old and old:sub(1, #anchor) == anchor then
      if not self:_consume(old:sub(#anchor + 1)) then return end
      Metrics.incr("ipc_inbox_rotation_drain")
    else
      Metrics.incr("ipc_inbox_rotation_lost")
    end
    self.inbox_pos, self._inbox_anchor, anchor = 0, "", ""
    data = read_from(path, 0)
  end
  if data then self:_consume(data:sub(#anchor + 1)) end
end

return Bridge
