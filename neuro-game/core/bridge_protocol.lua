local P = {}

function P.startup(session_id, game)
  return { command = "startup", session_id = session_id, game = game }
end

function P.context(message, silent)
  return { command = "context", data = { message = message or "", silent = not not silent } }
end

function P.register(actions)
  return { command = "actions/register", data = { actions = actions } }
end

function P.unregister(action_names)
  return { command = "actions/unregister", data = { action_names = action_names } }
end

function P.force(state, query, action_names, opts)
  opts = opts or {}
  return { command = "actions/force", data = {
    state = state or "",
    query = query or "",
    ephemeral_context = opts.ephemeral_context,
    priority = opts.priority,
    action_names = action_names or {},
  } }
end

function P.result(id, success, message)
  return { command = "action/result", data = { id = id, success = not not success, message = message } }
end

return P
