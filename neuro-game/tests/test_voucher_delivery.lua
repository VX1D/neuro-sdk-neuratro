_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("voucher-delivery")

local ContextCompact = require("context.context_compact")

local STATES = { SELECTING_HAND = 1, SHOP = 5, BLIND_SELECT = 7 }

local CENTERS = {
  v_clearance_sale = { key = "v_clearance_sale", name = "Clearance Sale", set = "Voucher",
    loc_txt = { name = "Clearance Sale", text = { "All cards and packs in shop are 25% off" } } },
  v_reroll_surplus = { key = "v_reroll_surplus", name = "Reroll Surplus", set = "Voucher",
    loc_txt = { name = "Reroll Surplus", text = { "Rerolls cost $2 less" } } },
  v_grabber = { key = "v_grabber", name = "Grabber", set = "Voucher",
    loc_txt = { name = "Grabber", text = { "Permanently gain +1 hand per round" } } },
}

local function world(state)
  _G.G = {
    STATE = STATES[state], STATES = STATES, P_CENTERS = CENTERS,
    GAME = { dollars = 12, chips = 0, bankrupt_at = 0, stake = 1, pack_choices = 1,
      used_vouchers = { v_clearance_sale = true, v_reroll_surplus = true, v_grabber = true },
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 2, blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }, boss_rerolled = false },
      probabilities = { normal = 1 }, modifiers = {}, blind_on_deck = "Small",
      blind = state == "SELECTING_HAND" and { name = "Small Blind", chips = 300, mult = 1 } or nil },
    NEURO = { reserved_dollars = 0, shop_reroll_count = 0 },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    shop = { reroll_cost = 5 },
  }
  ContextCompact.invalidate_cache()
end

local function build(state, split)
  world(state)
  local ok, out = pcall(ContextCompact.build, state, nil,
    { split = split, no_cache = true, return_list = true })
  if not ok then return tostring(out) end
  return table.concat(out, "\n")
end

local OWNED = "Vouchers you own:"

local function voucher_line(blob, prefix)
  for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, #prefix) == prefix then return line end
  end
  return nil
end

for _, state in ipairs({ "SHOP", "BLIND_SELECT" }) do
  local state_line = voucher_line(build(state, "state"), OWNED)
  check(state .. ": ephemeral state names repricing vouchers", state_line ~= nil
    and state_line:find("Clearance Sale", 1, true) ~= nil
    and state_line:find("Reroll Surplus", 1, true) ~= nil, tostring(state_line))
  check(state .. ": ephemeral state includes the complete owned roster",
    state_line ~= nil and state_line:find("Grabber", 1, true) ~= nil, tostring(state_line))
  check(state .. ": rule split carries no owned vouchers",
    voucher_line(build(state, "rule"), OWNED) == nil,
    tostring(voucher_line(build(state, "rule"), OWNED)))
end

local sh = voucher_line(build("SELECTING_HAND", "state"), OWNED)
check("the played-round force also carries the complete current voucher roster",
  sh ~= nil and sh:find("Grabber", 1, true) ~= nil, tostring(sh))

done()
