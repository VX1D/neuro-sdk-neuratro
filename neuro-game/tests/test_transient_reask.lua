local H = require("tests.hand_pipeline_harness")
local check, done = require("tests.helpers").harness("transient-reask")

local function busy(on)
  G.E_MANAGER.queues.base = on and { {} } or {}
end

do
  H.board({ confirm_hand = false }); H.tick(8)
  G.play.cards = { {} }; busy(true)
  local before = H.count("actions/force")
  H.send("play_hand", { indices = { 1, 2 } })
  H.tick(3)
  check("A: a hand still resolving acknowledges the force",
    H.results()[#H.results()].success == true and H.phase() == "ended", H.phase())
  check("A: nothing is re-asked while the engine is busy", H.count("actions/force") == before,
    before .. "->" .. H.count("actions/force"))
  G.play.cards = {}; busy(false)
  H.tick(3)
  check("A: the decision is asked again once it settles", H.count("actions/force") == before + 1
    and H.phase() == "forced", before .. "->" .. H.count("actions/force") .. " " .. H.phase())
  check("A: the acknowledgement unregistered the offer once and the re-ask registered it once",
    H.count("actions/unregister") == 1 and H.count("actions/register") == 2,
    H.count("actions/unregister") .. "/" .. H.count("actions/register"))
end

do
  H.board({ confirm_hand = false }); H.tick(8)
  G.GAME.blind.block_play = true; busy(true)
  local before = H.count("actions/force")
  H.send("play_hand", { indices = { 1, 2 } })
  H.tick(3)
  check("B: the boss banner acknowledges the force",
    H.results()[#H.results()].success == true and H.phase() == "ended", H.phase())
  G.GAME.blind.block_play = nil; busy(false)
  H.tick(3)
  check("B: the decision is asked again once the banner settles",
    H.count("actions/force") == before + 1, before .. "->" .. H.count("actions/force"))
end

do
  H.board(); H.tick(8)
  local before = H.count("actions/force")
  require("core.window").on_result("play_hand", true)
  check("C: a success=true answer ends the window", H.phase() == "ended", H.phase())
  H.tick(3)
  check("C: and a settled game asks again at once, as the reference opens its next window",
    H.count("actions/force") == before + 1 and H.phase() == "forced",
    before .. "->" .. H.count("actions/force") .. " " .. H.phase())
end

H.finish(check, done)
