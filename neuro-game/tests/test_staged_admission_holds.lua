local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("staged-admission-holds")

local function joker(id, name)
  return { sort_id = 100 + id, cost = 4, sell_cost = 2, ability = { set = "Joker", name = name, mult = 4 },
    config = { center = { key = "j_" .. id, name = name, set = "Joker",
      loc_txt = { name = name, description = "+4 Mult" } } },
    juice_up = function() end, highlight = function() end }
end

local result_for = H.result_for

for _, second in ipairs({
  { "set_joker_order", { from_index = 1, to_index = 2 } },
  { "sell_card", { area = "jokers", index = 2, name = "Greedy Joker" } },
  { "discard_hand", { indices = { 3, 4 } } },
}) do
  local name = second[1]
  H.board({ confirm_hand = false })
  G.jokers.cards = { joker(1, "Joker"), joker(2, "Greedy Joker") }
  G.FUNCS.sell_card = function() end
  H.tick(8)
  local play_id = H.send("play_hand", { indices = { 1, 2 } })
  H.tick(0.5)
  local admitted = result_for(play_id)
  check(name .. ": the play is admitted and still hovering",
    admitted and admitted.success == true and H.calls.play == 0 and require("core.execute").busy() == "staged",
    tostring(admitted and admitted.success) .. "/" .. H.calls.play)
  local second_id = H.send(name, second[2])
  H.tick(0.3)
  local refused = result_for(second_id)
  check(name .. ": the later action is refused as transient",
    refused and refused.success == false,
    refused and refused.message)
  H.tick(10)
  check(name .. ": the admitted play still runs", H.calls.play == 1 and H.calls.discard == 0,
    H.calls.play .. "/" .. H.calls.discard)
  check(name .. ": a force is open afterwards", H.phase() == "forced" and G.NEURO._force_open == true,
    H.phase())
end

H.finish(check, done)
