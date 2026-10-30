local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("overlay-transitional")

for _, state in ipairs({ "HAND_PLAYED", "NEW_ROUND", "DRAW_TO_HAND" }) do
  H.board({ confirm_hand = false })
  check(state .. ": fixture forced", H.wait_force(), H.phase())
  H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.5)
  G.STATE = H.STATES[state]
  G.SETTINGS = G.SETTINGS or {}
  G.SETTINGS.paused = true
  G.OVERLAY_MENU = { config = {} }
  G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil; G.SETTINGS.paused = false end
  check(state .. ": the open overlay is forced", H.wait_force(10)
    and table.concat(H.last_force().action_names, ",") == "exit_overlay_menu", H.phase())
  local id = H.send("exit_overlay_menu", "{}")
  H.tick(0.3)
  local r = H.result_for(id) or {}
  check(state .. ": closing the overlay is not held behind the screen change; the first answer closes it",
    r.success == true and G.OVERLAY_MENU == nil, tostring(r.success) .. " " .. tostring(r.message))
end

H.finish(check, done)
