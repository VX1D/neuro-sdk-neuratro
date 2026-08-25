local NON_PROGRESS = {
  set_joker_order = true, set_joker_intents = true, set_plan = true, copy_seed = true,
  change_selected_back = true, change_stake = true, toggle_seeded_run = true,
  paste_seed = true,
}

local FORFEIT = {
  skip_booster = true,
  skip_blind = true,
  toggle_shop = true,
}

local SETTLING_NONPROGRESS = {
  sell_card = true,
}

return {
  NON_PROGRESS = NON_PROGRESS,
  FORFEIT = FORFEIT,
  SETTLING_NONPROGRESS = SETTLING_NONPROGRESS,
  RIDE_ALONG = {
    set_joker_order = true,
    set_joker_intents = true,
    set_plan = true,
    change_selected_back = true,
    change_stake = true,
    copy_seed = true,
  },
}
