local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("unprompted-between-forces")

do
  H.board({ confirm_hand = false })
  local function joker(sid, key, name)
    return { sort_id = sid, ability = { set = "Joker", name = name }, sell_cost = 2,
      config = { center = { key = key, name = name, set = "Joker" } } }
  end
  local first, second = joker(801, "j_joker", "Joker"), joker(802, "j_greedy_joker", "Greedy Joker")
  G.jokers.cards = { first, second }
  H.tick(8)
  H.send("play_hand", { indices = { 1, 2 } })
  for _ = 1, 60 do H.tick(0.1) if H.calls.play > 0 then break end end
  H.tick(0.3)
  check("the played hand has ended its force", H.calls.play == 1 and H.phase() == "ended",
    H.calls.play .. "/" .. H.phase())
  local id = H.send("set_joker_order", { from_index = 1, to_index = 2 })
  H.tick(6)
  local result
  for _, r in ipairs(H.results()) do if r.id == id then result = r end end
  check("an unprompted tool in the gap is executed", result and result.success == true and G.jokers.cards[2] == first,
    result and tostring(result.message))
end

H.finish(check, done)
