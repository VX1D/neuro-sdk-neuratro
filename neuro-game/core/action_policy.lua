local NON_PROGRESS = {
  set_joker_order = true, record_joker_roles = true, record_plan = true, copy_seed = true,
  select_deck = true, select_stake = true, toggle_seeded_run = true,
  paste_seed = true,
}

local FORFEIT = {
  skip_pack = true,
  skip_blind = true,
  leave_shop = true,
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
    record_joker_roles = true,
    record_plan = true,
    select_deck = true,
    select_stake = true,
    copy_seed = true,
  },
}
