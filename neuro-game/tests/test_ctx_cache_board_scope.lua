require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("ctx-cache-board-scope")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local PACK = "SMODS_BOOSTER_OPENED"

LB.load(PACK, "Has pack cards")
check("the pack board is served on the force path",
  require("force.force_router").get_force_for_state(PACK) ~= nil, "no force for " .. PACK)

local function board_text(s) return (tostring(s or ""):gsub("Since your last decision:[^\n]*", "")) end

local function drives(label, mutate, gone)
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  local before = FP.build(PACK)
  check(label .. ": the first payload states the fact",
    before and before.state:find(gone, 1, true) ~= nil, gone .. " was never in the payload")
  mutate()
  local after = FP.build(PACK)
  check(label .. ": the second payload is not the first one served again",
    after and before and after.state ~= before.state, "byte-identical payload across the change")
  check(label .. ": and it no longer states the retired fact",
    after and board_text(after.state):find(gone, 1, true) == nil, "still states " .. gone)
end

drives("a pack card taken", function()
  local pa = G.pack_cards or G.booster_pack
  table.remove(pa.cards, 1)
end, "3. 10 of Hearts")

drives("a voucher list change", function()
  G.GAME.used_vouchers = { grabber = true }
end, "Overstock")

done()
