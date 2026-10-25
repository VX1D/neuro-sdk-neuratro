-- A debuffed held card emits only the Debuffed notice, so it must not count as a paid hand.
require("tests.stubs").setup({ love = "lazy" })
local check, done = require("tests.helpers").harness("joker-hits-debuffed-notice")
local JokerHits = require("core.joker_hits")

local DICTIONARY = { k_debuffed = "Debuffed" }
_G.localize = function(key) return DICTIONARY[key] or "ERROR" end

local fist = { sort_id = 41, ability = { set = "Joker", name = "Raised Fist", extra = 0 } }
require("tests.helpers").joker_hits_board({ fist })
fist.config = { center = G.P_CENTERS.j_raised_fist }
local Fake = require("tests.fake_cards")
local held = { cards = { Fake.ranked("9", "Spades"), Fake.ranked("2", "Clubs") } }
G.hand = held
check("fixture: Raised Fist reads as a conditional joker",
  require("facts.card_semantics").is_conditional(fist) == true)

local function play_hand(fist_effect)
  JokerHits.note_eval(fist, { before = true }, nil)
  JokerHits.note_eval(fist, { cardarea = held, other_card = {} }, fist_effect and { jokers = fist_effect } or nil)
  JokerHits.note_eval(fist, { after = true }, nil)
end

play_hand({ h_mult = 8, card = fist })
play_hand({ message = "Debuffed", colour = { 1, 0, 0, 1 }, card = fist })
play_hand({ h_mult = 4, card = fist })
play_hand({ message = "Debuffed", colour = { 1, 0, 0, 1 }, card = fist })
play_hand({ h_mult = 4, card = fist })

local hits, hands, label = JokerHits.condition_counts(fist)
check("hands with a debuffed held card are not counted as payouts", hits == 3 and hands == 5 and label == "paid",
  tostring(hits) .. "/" .. tostring(hands) .. " " .. tostring(label))

done()
