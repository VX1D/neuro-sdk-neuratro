local State = {}
local StateKinds = require("core.state_kinds")

local state_rev
local state_rev_src

function State.get_state_name()
  if not G or not G.STATES or not G.STATE then return "UNKNOWN" end
  if state_rev_src ~= G.STATES then
    state_rev = {}
    for key, value in pairs(G.STATES) do state_rev[value] = tostring(key) end
    state_rev_src = G.STATES
  end
  local name = state_rev[G.STATE]
  if not name then
    for key, value in pairs(G.STATES) do
      if value == G.STATE then
        name = tostring(key)
        state_rev[value] = name
        break
      end
    end
  end
  if not name then return "UNKNOWN" end
  -- A run setup the game gives no way back from (the win screen's new run) is the screen, whatever lies beneath.
  if StateKinds.is_run_setup_overlay()
      and (name == "SPLASH" or name == "MENU" or name == "GAME_OVER" or not StateKinds.is_closable_overlay()) then
    return "RUN_SETUP"
  end
  return name
end

return State
