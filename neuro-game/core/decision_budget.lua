local ActionPolicy = require("core.action_policy")

-- Every success ends the window and re-arms a force, so moves that leave the decision where it was are bounded per decision.
local M = {}

M.CAP = 3

local spent, told = {}, {}

-- Opening run setup only navigates: it neither spends nor ends the decision, so closing it again is what is bounded.
local NAVIGATION = { open_run_setup = true }

local function counted(name, state_name)
  return ActionPolicy.NON_PROGRESS[name] == true or (name == "exit_overlay_menu" and state_name == "RUN_SETUP")
end

function M.reset()
  spent, told = {}, {}
end

-- Only an accepted move (ACTION_ACCEPTED) applied anything; acknowledged or waiting successes do not count.
function M.on_applied(name, state_name)
  if counted(name, state_name) then
    spent[name] = (spent[name] or 0) + 1
  elseif not NAVIGATION[name] then
    M.reset()
  end
end

-- A no-op re-pick still uses the move, but it moved nothing on, so it never resets the budget.
function M.on_unchanged(name, state_name)
  if counted(name, state_name) then spent[name] = (spent[name] or 0) + 1 end
end

function M.spent(name, state_name)
  return counted(name, state_name) and (spent[name] or 0) >= M.CAP
end

function M.reason(name)
  return string.format("%s was already used %d times since your last move that moved the game on, so it is not "
    .. "offered again until you make one.", require("core.action_registry").phrase(name), M.CAP)
end

-- The reason for each newly withheld move, said once; commit marks it said once the force carrying it is sent.
function M.pending_note(state_name, names)
  local parts, marks = {}, {}
  for _, name in ipairs(names) do
    if not told[name] and M.spent(name, state_name) then
      parts[#parts + 1], marks[#marks + 1] = M.reason(name), name
    end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, " "), function()
    for _, name in ipairs(marks) do told[name] = true end
  end
end

return M
