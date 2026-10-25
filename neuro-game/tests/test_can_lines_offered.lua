require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })
local check, done = require("tests.helpers").harness("can-lines-offered")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local ALL_BOARDS = require("tests.force_section_rows").ALL_BOARDS

local CAN = {
  play = { names = { "play_hand" } },
  discard = { names = { "discard_hand" } },
  ["buy something"] = { names = { "buy_from_shop" }, narrows = true },
  reroll = { names = { "reroll_shop" }, narrows = true },
  sell = { names = { "sell_card" } },
  ["use a consumable"] = { names = { "use_consumable", "use_directional_consumable" } },
}

local function offered_set(payload)
  local set = {}
  for _, a in ipairs(payload.actions or {}) do
    set[type(a) == "table" and (a.name or a[1]) or a] = true
  end
  return set
end

local function check_frame(key, payload)
  local offered, lines = offered_set(payload), 0
  for label, verdict in payload.state:gmatch("Can ([%a ]-): (%a+)") do
    lines = lines + 1
    local spec = CAN[label]
    check(key .. ": 'Can " .. label .. "' maps to an action", spec ~= nil)
    if spec then
      local any = false
      for _, name in ipairs(spec.names) do any = any or offered[name] == true end
      local ok = (verdict == "yes" and any) or (verdict == "no" and (not any or spec.narrows))
      check(key .. ": 'Can " .. label .. ": " .. verdict .. "' agrees with the offer", ok)
    end
  end
  return lines
end

local total = 0
for _, board in ipairs(ALL_BOARDS) do
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  if payload then total = total + check_frame(board.state .. "/" .. board.desc, payload) end
end
check("the boards carry Can-lines at all", total >= 10, total)

LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
G.GAME.dollars, G.GAME.current_round.reroll_cost = 9, 5
for _, area in ipairs({ G.shop_booster, G.shop_vouchers }) do
  for _, c in ipairs((area and area.cards) or {}) do c.cost = 5 end
end
local payload = FP.build("SHOP")
check("withdrawn reroll: reroll_shop is not offered", not offered_set(payload).reroll_shop)
check_frame("SHOP/withdrawn reroll", payload)
check("withdrawn reroll: the state says no and why",
  payload.state:find("Can reroll: no", 1, true) ~= nil, payload.state)

done()
