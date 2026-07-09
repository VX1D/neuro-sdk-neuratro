local INFO_ACTIONS = require("core.actions").INFO_ACTIONS
local NON_PROGRESS = {
  set_joker_order = true, copy_seed = true,
  change_selected_back = true, change_stake = true, toggle_seeded_run = true,
  paste_seed = true, change_viewed_back = true, change_viewed_collab = true,
  sort_hand_suit = true, sort_hand_value = true,
}
for name in pairs(INFO_ACTIONS) do NON_PROGRESS[name] = true end

return {
  NON_PROGRESS = NON_PROGRESS,
  RIDE_ALONG = {
    set_joker_order = true,
    simulate_hand = true,
    sort_hand_suit = true,
    sort_hand_value = true,
    change_selected_back = true,
    change_stake = true,
    copy_seed = true,
  },
}
