local P = {}

P.WIRE_FIELDS = { "command", "game", "data" }
P.RESULT_DATA_FIELDS = { "id", "success", "message" }
-- Mod-local bookkeeping. SPECIFICATION.md:3-21 defines no such field in either direction, so these
-- names may never be emitted onto a frame nor read back off one.
P.TRANSPORT_FIELDS = { "session_id", "run_generation", "seq", "reason_code", "transport_session_unattributed" }

P.CONTROL_PREFIX = "neuro-bridge/"

function P.is_transport_control(command)
  return type(command) == "string" and command:sub(1, #P.CONTROL_PREFIX) == P.CONTROL_PREFIX
end
P.COMMANDS = {
  STARTUP = "startup",
  CONTEXT = "context",
  REGISTER = "actions/register",
  UNREGISTER = "actions/unregister",
  FORCE = "actions/force",
  RESULT = "action/result",
}
P.C2S_COMMANDS = {
  P.COMMANDS.STARTUP,
  P.COMMANDS.CONTEXT,
  P.COMMANDS.REGISTER,
  P.COMMANDS.UNREGISTER,
  P.COMMANDS.FORCE,
  P.COMMANDS.RESULT,
}

P.DATA_FIELDS = {
  [P.COMMANDS.CONTEXT] = { "message", "silent" },
  [P.COMMANDS.REGISTER] = { "actions" },
  [P.COMMANDS.UNREGISTER] = { "action_names" },
  [P.COMMANDS.FORCE] = { "state", "query", "ephemeral_context", "priority", "action_names" },
  [P.COMMANDS.RESULT] = P.RESULT_DATA_FIELDS,
}

function P.sanitize_for_wire(message)
  if type(message) ~= "table" then return message end
  local out = {}
  for _, field in ipairs(P.WIRE_FIELDS) do
    local value = message[field]
    if value ~= nil then out[field] = value end
  end
  local allowed = P.DATA_FIELDS[out.command]
  if allowed and type(out.data) == "table" then
    local data = {}
    for _, field in ipairs(allowed) do
      local value = out.data[field]
      if value ~= nil then data[field] = value end
    end
    out.data = data
  end
  return out
end

function P.startup(game)
  return { command = P.COMMANDS.STARTUP, game = game }
end

function P.context(message, silent)
  return { command = P.COMMANDS.CONTEXT, data = { message = message or "", silent = not not silent } }
end

function P.register(actions)
  return { command = P.COMMANDS.REGISTER, data = { actions = actions } }
end

function P.unregister(action_names)
  return { command = P.COMMANDS.UNREGISTER, data = { action_names = action_names } }
end

function P.force(state, query, action_names, opts)
  opts = opts or {}
  local data = {
    query = query or "",
    ephemeral_context = opts.ephemeral_context,
    priority = opts.priority,
    action_names = action_names or {},
  }
  if type(state) == "string" and state ~= "" then
    data.state = state
  end
  return { command = P.COMMANDS.FORCE, data = data }
end

function P.result(id, success, message)
  -- SPECIFICATION.md:222 types `id` as string; a delivered id of any other JSON type is still owed an answer, so it is coerced here rather than left to fail the wire contract.
  return {
    command = P.COMMANDS.RESULT,
    data = { id = tostring(id), success = not not success, message = message },
  }
end

return P
