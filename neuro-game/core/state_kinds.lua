local M = {}

local PACK_STATES = {
  TAROT_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true,
  STANDARD_PACK = true, BUFFOON_PACK = true, SMODS_BOOSTER_OPENED = true,
}
local MENU_STATES = { SPLASH = true, MENU = true, GAME_OVER = true, RUN_SETUP = true }

function M.is_pack_state(name)
  if type(name) ~= "string" then return false end
  return PACK_STATES[name] == true or name:find("_PACK$") ~= nil
end

function M.is_menu_state(name)
  return type(name) == "string" and MENU_STATES[name] == true
end

-- lives in this leaf module (not force_helpers) to avoid a core<->force require cycle
function M.is_run_setup_overlay()
  return G and G.OVERLAY_MENU
    and type(G.OVERLAY_MENU.get_UIE_by_ID) == "function"
    and G.OVERLAY_MENU:get_UIE_by_ID("run_setup_seed") ~= nil
end

function M.is_unlock_popup()
  return not not (G and G.OVERLAY_MENU and type(G.OVERLAY_MENU) == "table"
    and G.OVERLAY_MENU.joker_unlock_table ~= nil)
end

M.PACK_STATES = PACK_STATES
M.MENU_STATES = MENU_STATES
return M
