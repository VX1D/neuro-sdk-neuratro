local json = require("util.neuro_json")
local Tuning = require("core.config")
local Metrics = require("util.metrics")
local Protocol = require("core.bridge_protocol")
local TxCache = require("core.tx_cache")
local Utils = require("util.utils")

local Bridge = {}
Bridge.__index = Bridge
local temp_write_seq = 0

local function temp_path_for(path, owner)
  temp_write_seq = temp_write_seq + 1
  local owner_id = tostring(owner.session_id or owner):gsub("%W", "")
  return string.format("%s.tmp.%s.%d", path, owner_id, temp_write_seq)
end

local INBOX_ANCHOR_BYTES = 256

local RESULT_DEADLINE_SECS = 5
local OWED_DEADLINE_MESSAGE =
  "The game never produced a result for this action within its own deadline; it was not executed and nothing happened in game. Inspect the current state and choose again."
local OWED_SHUTDOWN_MESSAGE =
  "The game is shutting down and never executed this action; nothing happened in game."

local action_registry_mod = nil
local function action_registry()
  if action_registry_mod == nil then
    local ok, mod = pcall(require, "core.action_registry")
    action_registry_mod = (ok and type(mod) == "table") and mod or false
  end
  return action_registry_mod or nil
end

local function note_registry(fn_name, ...)
  local reg = action_registry()
  if not reg then return end
  local fn = reg[fn_name]
  if type(fn) == "function" then pcall(fn, ...) end
end

local function write_and_close(f, data)
  local ok = pcall(function()
    if not f:write(data) then error("write failed") end
    if not f:flush() then error("flush failed") end
  end)
  pcall(f.close, f)
  return ok
end

local function path_join(dir, file)
  local sep = package.config:sub(1, 1)
  if dir:sub(-1) == sep then
    return dir .. file
  end
  return dir .. sep .. file
end

local function table_is_empty(t)
  if type(t) ~= "table" then return false end
  return next(t) == nil
end

local UNSUPPORTED_SCHEMA_KEYS = {}
for _, keyword in ipairs({
  "$anchor", "$comment", "$defs", "$dynamicAnchor", "$dynamicRef", "$id", "$ref", "$schema",
  "$vocabulary", "additionalProperties", "allOf", "anyOf", "contentEncoding", "contentMediaType",
  "contentSchema", "dependentRequired", "dependentSchemas", "deprecated", "description", "else",
  "if", "maxProperties", "minProperties", "multipleOf", "not", "oneOf", "patternProperties",
  "readOnly", "then", "title", "unevaluatedItems", "unevaluatedProperties", "writeOnly",
}) do
  UNSUPPORTED_SCHEMA_KEYS[keyword] = true
end

local function copy_schema_for_json(v, key)
  if type(v) ~= "table" then return v end
  local out = {}
  local names_only = (key == "properties")
  for k, child in pairs(v) do
    if names_only or not UNSUPPORTED_SCHEMA_KEYS[k] then
      out[k] = copy_schema_for_json(child, k)
    end
  end
  if table_is_empty(out) and key ~= "required" and key ~= "enum" then
    return json.object(out)
  end
  return out
end

-- SPECIFICATION.md:41-55: name and description are required strings, and a schema, when present,
-- must be an object -- and :53 makes the name the action's unique identifier, which an empty string
-- cannot be. Read on the wire projection, so the keywords :58 strips are judged as Neuro sees them.
local function wire_valid_definition(def)
  if type(def) ~= "table" then return false end
  if type(def.name) ~= "string" or def.name == "" then return false end
  if type(def.description) ~= "string" then return false end
  if def.schema == nil then return true end
  if type(def.schema) ~= "table" then return false end
  local schema = copy_schema_for_json(def.schema, "schema")
  return table_is_empty(schema) or schema.type == "object"
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
  o.session_file = opts.session_file or "neuro_session.txt"
  o.action_journal_file = opts.action_journal_file or "neuro_action_journal.json"
  o.inbox_pos = 0
  o._inbox_anchor = ""
  o.on_message = nil
  o.state_name_provider = nil
  o.session_id = nil
  o.seq = 0
  o.last_transition_at = 0
  o.last_state = nil
  o._registered_set = {}
  o._registered_sigs = {}
  o._canonical_defs = {}
  o._force_alias_epoch = 0
  o._force_alias_to_canonical = {}
  o._registered_force_aliases = {}
  o._force_alias_retirement_pending = nil
  o._force_answer_ids = {}
  return o
end

function Bridge:_wire_action_names(names)
  local out = {}
  for i = 1, #(names or {}) do out[i] = names[i] end
  return out
end

function Bridge:_wire_action_definitions(defs)
  return copy_actions_for_json(defs)
end

local function force_wire_text(value, active)
  if type(value) ~= "string" or type(active) ~= "table" then return value end
  local names = {}
  for canonical in pairs(active) do names[#names + 1] = canonical end
  table.sort(names, function(a, b)
    if #a ~= #b then return #a > #b end
    return a < b
  end)
  for i = 1, #names do
    local canonical = names[i]
    local escaped = canonical:gsub("([^%w])", "%%%1")
    value = value:gsub("%f[%w_]" .. escaped .. "%f[^%w_]", active[canonical])
  end
  return value
end

function Bridge:fs_path(file)
  if not self.fs_dir then
    return file
  end
  return path_join(self.fs_dir, file)
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
  local temp_path = temp_path_for(path, self)
  local f = io.open(temp_path, "wb")
  if not f then
    return false
  end
  if not write_and_close(f, data) then
    os.remove(temp_path)
    return false
  end
  local ok = os.rename(temp_path, path)
  if not ok then
    local dst = io.open(path, "wb")
    if not dst then
      os.remove(temp_path)
      return false
    end
    local wok = write_and_close(dst, data)
    os.remove(temp_path)
    if not wok then
      return false
    end
  end
  return true
end

-- A handle that errors cannot say how many of its bytes reached the disk, so the file is asked
-- instead. Re-sending a line that already landed is what puts a byte-identical duplicate frame on
-- the wire, and for actions/force that is the one-force-at-a-time violation of SPECIFICATION.md:136-137.
function Bridge:_appended_length(file, before)
  local size
  if self.fs_dir then
    local f = io.open(self:fs_path(file), "rb")
    if f then
      size = f:seek("end")
      f:close()
    end
  elseif love and love.filesystem then
    local info = love.filesystem.getInfo(file)
    size = info and info.size
  end
  if not (tonumber(size) and tonumber(before)) then return nil end
  return size - before
end

function Bridge:_file_size(file)
  if self.fs_dir then
    local f = io.open(self:fs_path(file), "rb")
    if not f then return 0 end
    local size = f:seek("end") or 0
    f:close()
    return size
  end
  if love and love.filesystem then
    local info = love.filesystem.getInfo(file)
    return (info and info.size) or 0
  end
  return nil
end

function Bridge:append_file(file, data)
  local before = self:_file_size(file)
  local ok
  if not self.fs_dir then
    if not (love and love.filesystem) then return false, data end
    local info = love.filesystem.getInfo(file)
    if info then
      ok = love.filesystem.append(file, data)
    else
      ok = love.filesystem.write(file, data)
    end
    ok = not not ok
  else
    local f = io.open(self:fs_path(file), "ab")
    ok = (f ~= nil) and write_and_close(f, data)
  end
  if ok then return true end

  local landed = self:_appended_length(file, before)
  if landed and landed >= #data then return true end
  Metrics.incr("ipc_append_fail")
  if landed and landed > 0 then
    Metrics.incr("ipc_append_torn")
    return false, data:sub(landed + 1)
  end
  return false, data
end
function Bridge:record_action_phase(id, name, phase, details)
  if id == nil or type(phase) ~= "string" then return false end
  local entry = {
    id = tostring(id),
    name = tostring(name or ""),
    phase = phase,
    session_id = self.session_id,
    run_generation = G and G.NEURO and G.NEURO.run_generation or nil,
    updated_at = os.time(),
  }
  for k, v in pairs(details or {}) do entry[k] = v end
  if phase == "prepared" then
    self._committing_action = entry.name
  elseif phase == "completed" or phase == "aborted" then
    self._committing_action = nil
    if G and G.NEURO and (G.NEURO.consumed_action_owner == nil
        or G.NEURO.consumed_action_owner == tostring(id)) then
      G.NEURO.consumed_actions = nil
      G.NEURO.consumed_action_owner = nil
    end
  end
  return self:write_file(self.action_journal_file, json.encode(entry))
end

function Bridge:recover_action_journal()
  local raw = self:read_file(self.action_journal_file)
  if not raw or raw == "" then return nil end
  local ok, entry = pcall(json.decode, raw)
  if not ok or type(entry) ~= "table" or entry.id == nil then
    self:write_file(self.action_journal_file, "{}")
    return nil
  end
  self:write_file(self.action_journal_file, "{}")
  if entry.phase == "completed" or entry.phase == "aborted" then return nil end
  return entry
end

function Bridge:set_message_handler(fn)
  self.on_message = fn
end

function Bridge:set_state_name_provider(fn)
  self.state_name_provider = fn
end

function Bridge:_decorate(message)
  message = message or {}

  if self.game and message.game == nil then
    message.game = self.game
  end

  return message
end

local OUTBOX_BACKLOG_MAX = 256          -- soft cap: only droppable tiers are trimmed here
local OUTBOX_BACKLOG_SATURATION = 1024  -- stop reading new actions; never drop protected frames
local OUTBOX_BACKLOG_HARD = 2048        -- reject new protected debt instead of growing RAM forever
Bridge.OUTBOX_BACKLOG_HARD = OUTBOX_BACKLOG_HARD

local OUTBOX_TIER_SILENT_CONTEXT = 0
local OUTBOX_TIER_CONTEXT = 1
local OUTBOX_TIER_PROTECTED = 2

local function outbox_tier(message)
  if type(message) ~= "table" or message.command ~= "context" then
    return OUTBOX_TIER_PROTECTED
  end
  local data = message.data
  if type(data) == "table" and data.silent then
    return OUTBOX_TIER_SILENT_CONTEXT
  end
  return OUTBOX_TIER_CONTEXT
end

local function droppable_index(bl)
  local victim, victim_tier = nil, nil
  for i = 1, #bl do
    local tier = bl[i].tier
    if tier < OUTBOX_TIER_PROTECTED and (victim_tier == nil or tier < victim_tier) then
      victim, victim_tier = i, tier
      if tier == OUTBOX_TIER_SILENT_CONTEXT then break end
    end
  end
  return victim
end

function Bridge:_outbox_can_accept_protected(count)
  local protected = 0
  for i = 1, #(self._outbox_backlog or {}) do
    if self._outbox_backlog[i].tier >= OUTBOX_TIER_PROTECTED then protected = protected + 1 end
  end
  return protected + (tonumber(count) or 1) <= OUTBOX_BACKLOG_HARD
end

function Bridge:is_transport_saturated()
  return not not self._transport_saturated
end

local function update_transport_saturation(self, backlog_size)
  local saturated = backlog_size >= OUTBOX_BACKLOG_SATURATION
  if saturated and not self._transport_saturated then
    self._transport_saturated = true
    Metrics.incr("ipc_outbox_saturated")
    print("[neuro-game] IPC outbox saturated -- pausing new actions until protected frames flush")
  elseif self._transport_saturated and backlog_size < OUTBOX_BACKLOG_MAX then
    self._transport_saturated = nil
    print("[neuro-game] IPC outbox below the soft cap -- resuming actions")
  end
end

local function discard_frame(entry)
  if entry and entry.receipt then entry.receipt.status = "rejected" end
end

function Bridge:_outbox_push(line, message, receipt, torn_remainder)
  local bl = self._outbox_backlog
  if not bl then bl = {}; self._outbox_backlog = bl end
  local tier = torn_remainder and OUTBOX_TIER_PROTECTED or outbox_tier(message)
  if tier == OUTBOX_TIER_PROTECTED then
    while #bl >= OUTBOX_BACKLOG_HARD do
      local victim = droppable_index(bl)
      if not victim then
        if receipt then receipt.status = "rejected" end
        Metrics.incr("ipc_outbox_protected_rejected")
        update_transport_saturation(self, #bl)
        return false
      end
      discard_frame(table.remove(bl, victim))
      Metrics.incr("ipc_outbox_dropped")
    end
  end
  bl[#bl + 1] = {
    line = line,
    tier = tier,
    receipt = receipt,
  }
  if receipt then receipt.status = "buffered" end
  while #bl > OUTBOX_BACKLOG_MAX do
    local victim = droppable_index(bl)
    if not victim then break end
    discard_frame(table.remove(bl, victim))
    Metrics.incr("ipc_outbox_dropped")
  end
  update_transport_saturation(self, #bl)
  return true
end

function Bridge:_outbox_flush()
  local bl = self._outbox_backlog
  if not bl then
    update_transport_saturation(self, 0)
    return true
  end
  while #bl > 0 do
    local entry = bl[1]
    local ok, remainder = self:append_file(self.outbox_file, entry.line)
    if not ok then
      if remainder then
        if #remainder < #entry.line then entry.tier = OUTBOX_TIER_PROTECTED end
        entry.line = remainder
      end
      return false
    end
    self._last_sent_line = entry.line
    if entry.receipt then
      entry.receipt.status = "written"
      entry.receipt.written_at = Utils.now()
      if entry.receipt.action_id ~= nil then TxCache.mark_delivered(entry.receipt.action_id) end
    end
    table.remove(bl, 1)
    update_transport_saturation(self, #bl)
  end
  return true
end

function Bridge:send(message, receipt)
  if not self.enabled then
    if receipt then receipt.status = "rejected" end
    return false
  end
  -- SPECIFICATION.md:67 -- startup is the very first message. A failed send_startup leaves the
  -- bridge polling until bridge_init retries it, so the window has to refuse every other frame
  -- instead of letting one precede startup and then be erased by the retry's truncate.
  if self._startup_pending and (message or {}).command ~= "startup" then
    if receipt then receipt.status = "rejected" end
    Metrics.incr("ipc_startup_window_rejected")
    return false
  end
  message = Protocol.sanitize_for_wire(self:_decorate(message))
  self.seq = (self.seq or 0) + 1
  local line = json.encode(message) .. "\n"
  if self._last_sent_line == line then
    Metrics.incr("ipc_duplicate_frame")
    if not self._duplicate_frame_logged then
      self._duplicate_frame_logged = true
      print("[neuro-game] IPC duplicate frame on the wire: " .. tostring(message.command)
        .. " -- byte-identical to the frame before it (metric ipc_duplicate_frame)")
    end
  end
  if message.command == "actions/force" and self._force_open then
    if receipt then receipt.status = "rejected" end
    Metrics.incr("ipc_force_overlap_rejected")
    return false
  end
  local sent, remainder
  if self:_outbox_flush() then
    sent, remainder = self:append_file(self.outbox_file, line)
  end
  if sent then
    self._last_sent_line = line
    if receipt then
      receipt.status = "written"
      receipt.written_at = Utils.now()
    end
    if self._send_failed then
      self._send_failed = nil
      print("[neuro-game] IPC outbox recovered -- buffered results flushed")
    end
  else
    local buffered = self:_outbox_push(remainder or line, message, receipt,
      remainder ~= nil and #remainder < #line)
    if not buffered then
      Metrics.incr("ipc_send_rejected")
      return false
    end
    if not self._send_failed then
      self._send_failed = true
      print("[neuro-game] IPC outbox append failed -- buffering (context dropped first, protocol frames kept)")
    end
  end
  if message.command == "actions/force" then self._force_open = true end
  Metrics.incr("ipc_send")
  Metrics.set("ipc_seq", self.seq)
  return sent
end

local SESSION_INDEPENDENT_COMMANDS = {
  ["actions/reregister_all"] = true,
}

local function session_independent_frames(data)
  local frames, index = {}, {}
  if not data or data == "" then
    return frames
  end
  for raw in data:gmatch("[^\n]+") do
    local line = raw:gsub("\r$", "")
    if line ~= "" then
      local ok, msg = pcall(json.decode, line)
      if ok and type(msg) == "table" and SESSION_INDEPENDENT_COMMANDS[msg.command] then
        local slot = index[msg.command]
        if not slot then
          slot = #frames + 1
          index[msg.command] = slot
        end
        frames[slot] = msg
      end
    end
  end
  return frames
end

function Bridge:_carry_over_inbox()
  if not self.enabled then
    return {}
  end
  local data = self:read_file(self.inbox_file)
  local carried = session_independent_frames(data)
  if Tuning.bool("NEURO_INBOX_TRUNCATE_ON_STARTUP") then
    self:write_file(self.inbox_file, "")
    self.inbox_pos = 0
    self._inbox_anchor = ""
    return carried
  end

  self.inbox_pos = (data and #data) or 0
  self._inbox_anchor = data and data:sub(-INBOX_ANCHOR_BYTES) or ""
  return carried
end

function Bridge:reset_delivery_memory(preserve_force_aliases)
  self._last_register_key = nil
  self._force_full_register = true
  self._last_sent_line = nil
  self._duplicate_frame_logged = nil
  if not preserve_force_aliases then
    self._force_open = nil
    self._active_force_wire_by_canonical = nil
  end
  self._force_answer_ids = {}
end

function Bridge:retire_force_aliases()
  local aliases = {}
  for name in pairs(self._registered_force_aliases or {}) do aliases[#aliases + 1] = name end
  table.sort(aliases)
  if #aliases > 0 and self:_unregister_now(aliases) == false then
    self._force_alias_retirement_pending = true
    return false
  end
  self._force_alias_retirement_pending = nil
  self._force_open = nil
  self._active_force_wire_by_canonical = nil
  return true
end

function Bridge:retire_run_force()
  local aliases = self._registered_force_aliases or {}
  if not self._force_open and next(aliases) == nil then return true end
  if next(aliases) == nil then
    Metrics.incr("force_run_retire_missing_alias")
    return false
  end
  self._force_alias_retirement_pending = true
  return self:retire_force_aliases()
end

function Bridge:send_startup()
  if not self.enabled then
    return
  end

  local retry = self._startup_pending == true
  self._startup_complete = nil
  self._startup_pending = true

  if not retry then
    self.session_id = gen_session_id()
    self.seq = 0
    self.last_state = nil
    self._transport_saturated = nil
    self._send_failed = nil
    self:reset_delivery_memory()
    self._registered_set = {}
    self._registered_sigs = {}
    self._canonical_defs = {}
    self._force_alias_epoch = 0
    self._force_alias_to_canonical = {}
    self._registered_force_aliases = {}
    self._force_alias_retirement_pending = nil
    self.last_transition_at = Utils.gate_now("bridge_transition_cooldown")

    self:write_file(self.session_file, tostring(self.session_id) .. "\n")

    -- Before the first byte that can fail: a wipe placed after the failure point would take the
    -- obligations booked while the retry was pending, and would clear prepared/awaiting jobs
    -- without walking abort_prepared (core/dispatcher.lua:169-171).
    do
      local ok_disp, Dispatcher = pcall(require, "core.dispatcher")
      if ok_disp and Dispatcher and Dispatcher.reset_tx then pcall(Dispatcher.reset_tx) end
    end

    self._startup_carried = self:_carry_over_inbox()
  end

  local prior_backlog = self._outbox_backlog
  local carried = self._startup_carried or {}
  self._outbox_backlog = nil

  if Tuning.bool("NEURO_OUTBOX_TRUNCATE_ON_STARTUP") then
    pcall(function()
      local prev = self:read_file(self.outbox_file)
      if prev and #prev > 0 then
        self:write_file(self.outbox_file .. ".prev", prev)
      end
    end)
    if not self:write_file(self.outbox_file, "") then
      self._outbox_backlog = prior_backlog
      Metrics.incr("ipc_startup_truncate_failed")
      print("[neuro-game] IPC startup aborted -- stale outbox could not be truncated")
      return false
    end
  end

  if prior_backlog and self._outbox_backlog ~= prior_backlog then
    for i = 1, #prior_backlog do
      discard_frame(prior_backlog[i])
    end
  end

  local startup_receipt = { status = "sending", kind = "startup" }
  self:send(Protocol.startup(self.game), startup_receipt)
  if startup_receipt.status == "rejected" then return false end

  -- The window closes where the startup frame is admitted, not where the carried backlog drains:
  -- those deliveries answer actions, and SPECIFICATION.md:67 is already satisfied by the frame above.
  self._startup_carried = nil
  self._startup_pending = nil
  self._startup_complete = true

  for _, msg in ipairs(carried) do
    self:_deliver_inbox_message(msg)
  end
  return true
end

function Bridge:send_context(message, silent, receipt)
  if self.llm_paused or not self.enabled then
    if receipt then receipt.status = "rejected" end
    return false, false, receipt
  end
  receipt = receipt or {}
  if self:send(Protocol.context(message, silent), receipt) then return true, false, receipt end
  local queued = receipt.status == "buffered"
  return queued, queued, receipt
end

function Bridge:discard_backlog_context()
  local bl = self._outbox_backlog
  if not bl then return 0 end
  local kept, dropped = {}, 0
  for i = 1, #bl do
    local entry = bl[i]
    if entry.tier < OUTBOX_TIER_PROTECTED then
      discard_frame(entry)
      dropped = dropped + 1
    else
      kept[#kept + 1] = entry
    end
  end
  self._outbox_backlog = kept
  if dropped > 0 then Metrics.incr("ipc_backlog_context_discarded", dropped) end
  update_transport_saturation(self, #kept)
  return dropped
end

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
    self._canonical_defs = self._canonical_defs or {}
    self._canonical_defs[n] = a
    name_set[n] = true
    cur_sig[n] = tostring(a.description or "") .. "\1" .. schema_sig(a.schema)
    key_parts[#key_parts + 1] = n .. "\1" .. cur_sig[n]
  end
  local key = table.concat(key_parts, "\2")
  local live_names = {}
  for n in pairs(name_set) do live_names[#live_names + 1] = n end
  local full = self._force_full_register == true
  if not full and key == self._last_register_key then
    note_registry("note_registered", live_names)
    self._registered_set = self._registered_set or {}
    self._registered_sigs = self._registered_sigs or {}
    for name, sig in pairs(cur_sig) do
      self._registered_set[name] = true
      self._registered_sigs[name] = sig
    end
    return true
  end

  local prev_sig = self._registered_sigs or {}
  local stale = {}
  for n, oldsig in pairs(prev_sig) do
    if cur_sig[n] == nil or cur_sig[n] ~= oldsig then stale[#stale + 1] = n end
  end
  if #stale > 0 then
    if self:_unregister_now(stale) == false then return false end
  end

  local fresh = {}
  for i = 1, #(actions or {}) do
    local a = actions[i]
    local n = a.name or ""
    if full or prev_sig[n] ~= cur_sig[n] then
      fresh[#fresh + 1] = a
    end
  end

  if #fresh > 0 then
    local receipt = { status = "sending", kind = "actions_register" }
    self:send(Protocol.register(self:_wire_action_definitions(fresh)), receipt)
    if receipt.status == "rejected" then return false end
    local fresh_names = {}
    for i = 1, #fresh do fresh_names[#fresh_names + 1] = fresh[i].name or "" end
    note_registry("note_registered", fresh_names)
  end
  self._last_register_key = key
  self._registered_set = name_set
  self._registered_sigs = cur_sig
  self._force_full_register = nil
  return true
end

function Bridge:set_desired_action_names(provider)
  self._desired_action_names = provider
end

function Bridge:_unregister_now(action_names)
  local sigs = self._registered_sigs or {}
  local set = self._registered_set or {}
  local force_aliases = self._registered_force_aliases or {}
  local send_list = {}
  for _, n in ipairs(action_names) do
    if set[n] or sigs[n] or force_aliases[n] then
      send_list[#send_list + 1] = n
    end
  end
  if #send_list == 0 then return true end
  local receipt = { status = "sending", kind = "actions_unregister" }
  self:send(Protocol.unregister(self:_wire_action_names(send_list)), receipt)
  if receipt.status == "rejected" then return false end
  for _, n in ipairs(send_list) do
    set[n] = nil
    sigs[n] = nil
    force_aliases[n] = nil
  end
  self._last_register_key = nil
  note_registry("note_unregistered", send_list)
  return true
end

function Bridge:cancel_force_actions(action_names)
  local seen, names = {}, {}
  for _, name in ipairs(action_names or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local wire_names = {}
  local active = self._active_force_wire_by_canonical or {}
  for i = 1, #names do wire_names[i] = active[names[i]] or names[i] end
  local receipt = {
    status = "sending", kind = "force_cancel_unregister", names = names, wire_names = wire_names,
  }
  if #names == 0 then
    receipt.status = "written"
    receipt.written_at = Utils.now()
    return receipt
  end
  self:send(Protocol.unregister(wire_names), receipt)
  return receipt
end

function Bridge:complete_force_cancellation(action_names)
  local active = self._active_force_wire_by_canonical
  if type(active) == "table" then
    local aliases = self._registered_force_aliases or {}
    for _, wire_name in pairs(active) do aliases[wire_name] = nil end
    self._force_open = nil
    self._active_force_wire_by_canonical = nil
    return true
  end
  local set = self._registered_set or {}
  local sigs = self._registered_sigs or {}
  for _, name in ipairs(action_names or {}) do
    set[name] = nil
    sigs[name] = nil
  end
  self._last_register_key = nil
  note_registry("note_unregistered", action_names or {})
  return true
end

function Bridge:withdraw_actions_exact(action_names)
  local seen, names = {}, {}
  for _, name in ipairs(action_names or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local wire_names = {}
  local active = self._active_force_wire_by_canonical or {}
  for i = 1, #names do
    wire_names[#wire_names + 1] = names[i]
  end
  local aliases = {}
  for _, wire_name in pairs(active) do aliases[#aliases + 1] = wire_name end
  table.sort(aliases)
  for i = 1, #aliases do wire_names[#wire_names + 1] = aliases[i] end
  local receipt = {
    status = "sending", kind = "actions_unregister", names = names, wire_names = wire_names,
  }
  if #names == 0 then
    receipt.status = "written"
    receipt.written_at = Utils.now()
    return receipt
  end
  self:send(Protocol.unregister(wire_names), receipt)
  return receipt
end

function Bridge:complete_action_withdrawal(action_names)
  local set = self._registered_set or {}
  local sigs = self._registered_sigs or {}
  for _, name in ipairs(action_names or {}) do
    set[name] = nil
    sigs[name] = nil
  end
  self._last_register_key = nil
  note_registry("note_unregistered", action_names or {})
  local active = self._active_force_wire_by_canonical or {}
  local aliases = self._registered_force_aliases or {}
  for _, wire_name in pairs(active) do aliases[wire_name] = nil end
  self._force_open = nil
  self._active_force_wire_by_canonical = nil
  return true
end

-- API/README.md:19-21 -- the names a commit consumes must leave the offer before its result. The
-- consumption is run state, not wire state: core/actions.lua reads it back when it computes what is
-- on offer, so the set and the registry agree instead of one stripping behind the other's back.
function Bridge:consume_actions(action_names, action_id)
  if not (G and G.NEURO) then return false end
  local set = nil
  for i = 1, #(action_names or {}) do
    local n = action_names[i]
    if type(n) == "string" and n ~= "" then
      set = set or {}
      set[n] = true
    end
  end
  G.NEURO.consumed_actions = set
  G.NEURO.consumed_action_owner = action_id ~= nil and tostring(action_id) or nil
  return set ~= nil
end

function Bridge:_retraction_filter(action_names)
  local provider = self._desired_action_names
  if not provider then return nil end
  local committing = self._committing_action
  if committing then
    for _, n in ipairs(action_names) do
      if n == committing then return nil end
    end
  end
  local ok, desired = pcall(provider)
  if not ok or type(desired) ~= "table" then return nil end
  return desired
end

-- The retraction half of the reconcile, derived instead of dictated: whatever the offer no longer
-- contains leaves the wire. It is how a commit's consumed names go before its result
-- (API/README.md:19-21) without any caller naming them, so the computed set and the registry cannot
-- disagree the way an imperative strip made them.
function Bridge:retract_undesired()
  local provider = self._desired_action_names
  if not provider then return false end
  local ok, desired = pcall(provider)
  if not ok or type(desired) ~= "table" then return false end
  local drop = {}
  for n in pairs(self._registered_sigs or {}) do
    if not desired[n] then drop[#drop + 1] = n end
  end
  table.sort(drop)
  if #drop == 0 then return false end
  self:_unregister_now(drop)
  return true
end

function Bridge:unregister_actions(action_names)
  if not (action_names and #action_names > 0) then return end
  local desired = self:_retraction_filter(action_names)
  if not desired then return self:_unregister_now(action_names) end
  local keep = {}
  for _, n in ipairs(action_names) do
    if not desired[n] then keep[#keep + 1] = n end
  end
  if #keep == 0 then return end
  return self:_unregister_now(keep)
end

function Bridge:unregister_all()
  local list = {}
  local set = self._registered_set or {}
  local sigs = self._registered_sigs or {}
  for n in pairs(set) do list[#list + 1] = n end
  for n in pairs(sigs) do
    if not set[n] then list[#list + 1] = n end
  end
  for n in pairs(self._registered_force_aliases or {}) do list[#list + 1] = n end
  table.sort(list)
  if #list > 0 then
    self:_unregister_now(list)
  end
end

function Bridge:force_actions(state, query, action_names, opts)
  if self.llm_paused or self.enabled == false then return false end
  if self._force_open then
    if self._force_alias_retirement_pending then self:retire_force_aliases() end
    if self._force_open then
      Metrics.incr("force_send_while_open_rejected")
      return false
    end
  end
  local pending_cancel = G and G.NEURO and G.NEURO.force_cancel_pending or nil
  if type(pending_cancel) == "table" then
    Metrics.incr("force_send_cancel_blocked")
    return false
  end
  local seen = {}
  local registered = self._registered_set or {}
  if type(action_names) ~= "table" or #action_names == 0 then
    Metrics.incr("force_send_invalid_actions")
    return false
  end
  self:_outbox_flush()
  if not self:_outbox_can_accept_protected(2) then
    Metrics.incr("force_atomic_capacity_rejected")
    return false, { status = "rejected", kind = "force_atomic_reservation" }
  end
  for i = 1, #action_names do
    local name = action_names[i]
    if type(name) ~= "string" or name == "" or seen[name] or not registered[name] then
      Metrics.incr("force_send_unregistered_action")
      return false
    end
    seen[name] = true
  end
  local backlog_size = self._outbox_backlog and #self._outbox_backlog or 0
  if backlog_size >= OUTBOX_BACKLOG_HARD - 1 then
    Metrics.incr("force_send_insufficient_outbox_capacity")
    return false
  end
  self._force_alias_epoch = (tonumber(self._force_alias_epoch) or 0) + 1
  local epoch = self._force_alias_epoch
  local wire_names, alias_defs, active = {}, {}, {}
  local defs = self._canonical_defs or {}
  for i = 1, #action_names do
    local canonical = action_names[i]
    local src = defs[canonical]
    if type(src) ~= "table" then
      Metrics.incr("force_send_missing_definition")
      return false
    end
    local alias = canonical .. "_force_" .. tostring(epoch)
    wire_names[#wire_names + 1] = alias
    active[canonical] = alias
  end
  for i = 1, #action_names do
    local canonical = action_names[i]
    local src = defs[canonical]
    local def = {}
    for k, v in pairs(src) do def[k] = v end
    def.name = active[canonical]
    def.description = force_wire_text(def.description, active)
    alias_defs[#alias_defs + 1] = def
  end
  for i = 1, #alias_defs do
    if not wire_valid_definition(alias_defs[i]) then
      Metrics.incr("force_send_unwireable_definition")
      return false
    end
  end
  local register_receipt = { status = "sending", kind = "force_alias_register" }
  self:send(Protocol.register(self:_wire_action_definitions(alias_defs)), register_receipt)
  if register_receipt.status == "rejected" then return false, register_receipt end
  self._registered_force_aliases = self._registered_force_aliases or {}
  for i = 1, #wire_names do self._registered_force_aliases[wire_names[i]] = true end
  self._force_alias_to_canonical = self._force_alias_to_canonical or {}
  for canonical, alias in pairs(active) do self._force_alias_to_canonical[alias] = canonical end
  self._active_force_wire_by_canonical = active
  opts = opts or {}
  if G and G.NEURO then G.NEURO.force_generation = tonumber(G.NEURO.run_generation) end
  local receipt = { status = "sending", kind = "actions_force", actions = action_names }
  self:send(Protocol.force(force_wire_text(state, active), force_wire_text(query, active),
    wire_names, opts), receipt)
  if receipt.status == "rejected" then
    self:_unregister_now(wire_names)
    self._active_force_wire_by_canonical = nil
    return false, receipt
  end
  return true, receipt
end

function Bridge:send_action_result(id, success, message)
  local force_wire_name = self._force_answer_ids and self._force_answer_ids[tostring(id)]
  local close_force = success == true and type(force_wire_name) == "string" and force_wire_name ~= ""
  local committed, receipt = TxCache.settle(id, function()
    if close_force then
      local wire_names = {}
      for _, wire_name in pairs(self._active_force_wire_by_canonical or {}) do
        if (self._registered_force_aliases or {})[wire_name] then wire_names[#wire_names + 1] = wire_name end
      end
      table.sort(wire_names)
      local unregister_receipt = { status = "sending", kind = "force_alias_unregister" }
      if #wire_names > 0 then
        local unregister_ok = pcall(self.send, self, Protocol.unregister(wire_names),
          unregister_receipt)
        if not unregister_ok or unregister_receipt.status == "rejected" then
          Metrics.incr("force_alias_unregister_rejected")
          return nil, unregister_receipt
        end
      end
    end
    local result_receipt = { status = "sending", kind = "action_result", action_id = id }
    local ok, sent = pcall(self.send, self, Protocol.result(id, success, message), result_receipt)
    if not ok then
      Metrics.incr("action_result_send_throw")
      error(sent, 0)
    end
    if result_receipt.status == "rejected" then
      Metrics.incr("action_result_send_rejected")
      return nil, result_receipt
    end
    return { ok = success, message = message }, result_receipt
  end)
  if committed == nil then
    Metrics.incr("action_result_refused_duplicate")
    return false
  end
  if not committed then return false, receipt end
  if close_force then
    self._force_answer_ids[tostring(id)] = nil
    local aliases = self._registered_force_aliases or {}
    for _, wire_name in pairs(self._active_force_wire_by_canonical or {}) do aliases[wire_name] = nil end
    self._force_open = nil
    self._active_force_wire_by_canonical = nil
  end
  TxCache.note_result_session(id, G and G.NEURO and G.NEURO.transport_session)
  if receipt and receipt.status == "written" then
    TxCache.mark_delivered(id)
  else
    TxCache.hold_undelivered(id, receipt, Utils.gate_now("result_deadline"))
  end
  return true, receipt
end

function Bridge:is_force_answer(id)
  return self._force_answer_ids ~= nil
    and type(self._force_answer_ids[tostring(id)]) == "string"
end

function Bridge:replay_action_result(id, success, message)
  local session = G and G.NEURO and G.NEURO.transport_session
  if not TxCache.replay_due(id, session) then return false end
  local receipt = { status = "sending", kind = "action_result_replay", action_id = id }
  self:send(Protocol.result(id, success, message), receipt)
  if receipt.status == "rejected" then
    Metrics.incr("action_result_replay_rejected")
    return false
  end
  TxCache.note_result_session(id, session)
  return true, receipt
end

Bridge.RESULT_DEADLINE_SECS = RESULT_DEADLINE_SECS
Bridge.OWED_SHUTDOWN_MESSAGE = OWED_SHUTDOWN_MESSAGE

function Bridge:answer_owed_results(deadline, message)
  if not self.enabled then return 0 end
  -- SPECIFICATION.md:67 -- nothing may precede `startup` on the wire, so a sweep inside the startup
  -- window could only produce rejected frames; the obligations stay booked for the next one.
  if self._startup_pending then return 0 end
  local now = Utils.gate_now("result_deadline")
  local due = TxCache.outstanding(now, deadline)
  local paid = 0
  for i = 1, #due do
    local key = due[i].key
    local frame = TxCache.pending_frame_state(key)
    if frame == "delivered" then
      TxCache.mark_delivered(key)
    elseif frame ~= "queued" then
      Metrics.incr("action_result_owed_paid")
      paid = paid + 1
      -- An id whose verdict was committed and whose frame is gone owes THAT answer, not a fresh one:
      -- SPECIFICATION.md:165-167 permits exactly one result, and the mod already decided what it says.
      local undelivered = TxCache.undelivered_verdict(key)
      if undelivered then
        local receipt = { status = "sending", kind = "action_result", action_id = key }
        self:send(Protocol.result(key, undelivered.ok, undelivered.message), receipt)
        if receipt.status == "written" then
          TxCache.mark_delivered(key)
        else
          TxCache.hold_undelivered(key, receipt, now)
        end
      else
        -- SPECIFICATION.md:184,188: false retries the entire force. A watchdog/shutdown answer is a
        -- terminal transport acknowledgement -- the action did not run and retrying it against an
        -- unresponsive or departing game only creates another orphan.
        local verdict = message or OWED_DEADLINE_MESSAGE
        self:send_action_result(key, true, verdict)
      end
    end
  end
  return paid
end

local function is_inbox_message(msg)
  return type(msg) == "table" and type(msg.command) == "string"
end

local function drop_looped_fields(msg)
  for _, field in ipairs(Protocol.TRANSPORT_FIELDS) do
    if msg[field] ~= nil then
      msg[field] = nil
      Metrics.incr("ipc_inbox_looped_field")
    end
  end
end

function Bridge:_deliver_inbox_message(msg)
  Metrics.incr("ipc_inbox_msg")
  drop_looped_fields(msg)
  if msg.transport_session ~= nil and not Protocol.is_transport_control(msg.command) then
    msg.transport_session_unattributed = true
    Metrics.incr("ipc_inbox_unattributed_session")
  end
  if msg.command == "action" and type(msg.data) == "table" then
    local wire_name = msg.data.name
    local canonical = self._force_alias_to_canonical and self._force_alias_to_canonical[wire_name]
    if canonical then
      msg.data.name = canonical
      msg.data.force_wire_name = wire_name
      msg.data.force_wire_stale = not (self._active_force_wire_by_canonical
        and self._active_force_wire_by_canonical[canonical] == wire_name)
      if msg.data.id ~= nil and not msg.data.force_wire_stale then
        self._force_answer_ids = self._force_answer_ids or {}
        self._force_answer_ids[tostring(msg.data.id)] = wire_name
      end
    end
  end
  -- The obligation is booked before anything can decline the frame, so neither a missing handler nor
  -- a throw can leave the action without the one result SPECIFICATION.md:165-167 requires.
  if msg.command == "action" and type(msg.data) == "table" and msg.data.id ~= nil then
    TxCache.open(msg.data.id, msg.data.name, Utils.gate_now("result_deadline"))
  end
  if not self.on_message then
    Metrics.incr("ipc_inbox_undelivered")
    return
  end
  if msg.command == "actions/reregister_all" then
    local retired = self:retire_force_aliases()
    self:reset_delivery_memory(retired == false)
  end
  local handler_ok, handler_err = xpcall(function()
    return self.on_message(msg)
  end, debug.traceback)
  if not handler_ok then
    Metrics.incr("ipc_handler_error")
    print("[neuro-game] IPC handler error: " .. tostring(handler_err))
  end
end

function Bridge:_inbox_region(pos, anchor_len)
  if self.fs_dir then
    local f = io.open(self:fs_path(self.inbox_file), "rb")
    if not f then
      return nil, nil
    end
    local size = f:seek("end")
    if size < pos then
      f:close()
      return nil, ""
    end
    f:seek("set", pos - anchor_len)
    local anchor = anchor_len > 0 and (f:read(anchor_len) or "") or ""
    local chunk = f:read("*a") or ""
    f:close()
    return anchor, chunk
  end
  local data = self:read_file(self.inbox_file)
  if data == nil then
    return nil, nil
  end
  if #data < pos then
    return nil, ""
  end
  return data:sub(pos - anchor_len + 1, pos), data:sub(pos + 1)
end

function Bridge:poll_inbox()
  if not self.enabled then
    return
  end
  if self:is_transport_saturated() then return end
  local pos = self.inbox_pos or 0
  local carried = self._inbox_anchor or ""
  local anchor, chunk = self:_inbox_region(pos, #carried)
  if chunk == nil then
    return
  end
  if anchor ~= carried then
    pos, carried = 0, ""
    chunk = select(2, self:_inbox_region(0, 0))
    if chunk == nil then
      return
    end
  end

  local consumed = 0
  local last_newline = chunk:find("\n[^\r\n]*$")
  while last_newline and consumed < last_newline do
    local newline = chunk:find("\n", consumed + 1, true)
    if not newline or newline > last_newline then break end
    local line = chunk:sub(consumed + 1, newline - 1):gsub("\r$", "")
    local delta = chunk:sub(consumed + 1, newline)
    consumed = newline
    self.inbox_pos = pos + consumed
    carried = (carried .. delta):sub(-INBOX_ANCHOR_BYTES)
    self._inbox_anchor = carried
    if line ~= "" then
      local line_ok, line_err = pcall(function()
        local ok, msg = pcall(json.decode, line)
        if not ok or not is_inbox_message(msg) then
          Metrics.incr("ipc_decode_error")
          print("[neuro-game] IPC inbox line discarded (not a message): " .. line:sub(1, 200))
        else
          self:_deliver_inbox_message(msg)
        end
      end)
      if not line_ok then
        Metrics.incr("ipc_handler_error")
        print("[neuro-game] IPC line handling error: " .. tostring(line_err))
      end
      if self:is_transport_saturated() then break end
    end
  end
end

function Bridge:update(_dt)
  if self.enabled and self._outbox_backlog and #self._outbox_backlog > 0 then
    self:_outbox_flush()
  end
  local _np = Utils.gate_now("inbox_poll")
  if (_np - (self._last_poll or 0)) >= 0.005 then
    self._last_poll = _np
    self:poll_inbox()
  end
  self:answer_owed_results(RESULT_DEADLINE_SECS)
  if self.state_name_provider then
    local now = Utils.gate_now("bridge_transition_cooldown")
    local ok_sn, sn = pcall(self.state_name_provider)
    if ok_sn and sn and sn ~= self.last_state then
      self.last_state = sn
      self.last_transition_at = now
    end
  end
end

function Bridge:is_transition_cooldown()
  local now = Utils.gate_now("bridge_transition_cooldown")
  local elapsed = now - (self.last_transition_at or 0)
  return elapsed < Utils.gate_seconds("bridge_transition_cooldown")
end

return Bridge
