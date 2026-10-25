local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("zeroed-hand-report")

local function mouth() return { name = "The Mouth", key = "bl_mouth", boss = true, chips = 9000,
  config = { blind = { key = "bl_mouth" } }, only_hand = "Flush" } end

local function line(force, pattern)
  return (force and force.state or ""):match(pattern) or "(missing)"
end

local function play_and_settle(chips_gain)
  H.on_play = function()
    for _, selected in ipairs(G.hand.highlighted) do
      for i = #G.hand.cards, 1, -1 do
        if G.hand.cards[i] == selected then table.remove(G.hand.cards, i) break end
      end
      G.play.cards[#G.play.cards + 1] = selected
    end
    G.hand.highlighted = {}
    G.GAME.current_round.hands_left = G.GAME.current_round.hands_left - 1
    G.STATE = H.STATES.HAND_PLAYED
  end
  H.send("play_hand", { indices = { 1 }, plan = { boss_plan = "Only Flushes score now." } }); H.tick(2)
  G.GAME.chips = (G.GAME.chips or 0) + chips_gain
  G.play.cards = {}
  G.STATE = H.STATES.DRAW_TO_HAND; H.tick(1)
  G.STATE = H.STATES.SELECTING_HAND
  return H.wait_force(20)
end

do
  H.board({ confirm_hand = false, blind = mouth(), phi = require("tests.engine_hand_info").stub("High Card") })
  G.GAME.chips = 6928
  check("fixture: the first hand force is out", H.wait_force(10), H.phase())
  check("fixture: the next force came", play_and_settle(0), H.phase())
  check("fixture: the hand was played", H.calls.play == 1, H.calls.play)
  local force = H.last_force()
  local last = line(force, "Last hand:[^\n]*")
  check("a hand The Mouth zeroed is not reported as scoring cards", not last:find("1 scored", 1, true), last)
  check("it says nothing scored and why", last:find("0 scored", 1, true) and last:find("The Mouth", 1, true), last)
  check("it reports the +0 chips the game added", last:find("+0 chips", 1, true) ~= nil, last)
  local history = line(force, "Recent actual hand results[^\n]*")
  check("the history records the zero result", history:find("High Card lv.1 scored 0", 1, true) ~= nil, history)
end

do
  H.board({ confirm_hand = false, blind = { name = "Small Blind", chips = 300 },
    phi = require("tests.engine_hand_info").stub("High Card") })
  G.GAME.chips = 0
  check("fixture: the first hand force is out", H.wait_force(10), H.phase())
  check("fixture: the next force came", play_and_settle(16), H.phase())
  local last = line(H.last_force(), "Last hand:[^\n]*")
  check("an unblocked hand still reports what scored", last:find("1 scored, +16 chips", 1, true) ~= nil, last)
end

H.finish(check, done)
