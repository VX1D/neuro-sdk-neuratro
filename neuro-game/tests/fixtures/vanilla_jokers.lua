-- Data below is generated from Balatro's own game.lua P_CENTERS joker block and
-- localization/en-us.lua; build() is a line-for-line port of Card:set_ability (card.lua:344-416).
local CENTERS = {
  { blueprint_compat = true, config = { mult = 4 }, cost = 2, effect = "Mult", key = "j_joker", name = "Joker", order = 1, rarity = 1, set = "Joker", text = { "+#1# Mult" } },
  { blueprint_compat = true, config = { extra = { s_mult = 3, suit = "Diamonds" } }, cost = 5, effect = "Suit Mult", key = "j_greedy_joker", name = "Greedy Joker", order = 2, rarity = 1, set = "Joker", text = { "Played cards with", "#2# suit give", "+#1# Mult when scored" } },
  { blueprint_compat = true, config = { extra = { s_mult = 3, suit = "Hearts" } }, cost = 5, effect = "Suit Mult", key = "j_lusty_joker", name = "Lusty Joker", order = 3, rarity = 1, set = "Joker", text = { "Played cards with", "#2# suit give", "+#1# Mult when scored" } },
  { blueprint_compat = true, config = { extra = { s_mult = 3, suit = "Spades" } }, cost = 5, effect = "Suit Mult", key = "j_wrathful_joker", name = "Wrathful Joker", order = 4, rarity = 1, set = "Joker", text = { "Played cards with", "#2# suit give", "+#1# Mult when scored" } },
  { blueprint_compat = true, config = { extra = { s_mult = 3, suit = "Clubs" } }, cost = 5, effect = "Suit Mult", key = "j_gluttenous_joker", name = "Gluttonous Joker", order = 5, rarity = 1, set = "Joker", text = { "Played cards with", "#2# suit give", "+#1# Mult when scored" } },
  { blueprint_compat = true, config = { t_mult = 8, type = "Pair" }, cost = 3, effect = "Type Mult", key = "j_jolly", name = "Jolly Joker", order = 6, rarity = 1, set = "Joker", text = { "+#1# Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_mult = 12, type = "Three of a Kind" }, cost = 4, effect = "Type Mult", key = "j_zany", name = "Zany Joker", order = 7, rarity = 1, set = "Joker", text = { "+#1# Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_mult = 10, type = "Two Pair" }, cost = 4, effect = "Type Mult", key = "j_mad", name = "Mad Joker", order = 8, rarity = 1, set = "Joker", text = { "+#1# Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_mult = 12, type = "Straight" }, cost = 4, effect = "Type Mult", key = "j_crazy", name = "Crazy Joker", order = 9, rarity = 1, set = "Joker", text = { "+#1# Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_mult = 10, type = "Flush" }, cost = 4, effect = "Type Mult", key = "j_droll", name = "Droll Joker", order = 10, rarity = 1, set = "Joker", text = { "+#1# Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_chips = 50, type = "Pair" }, cost = 3, key = "j_sly", name = "Sly Joker", order = 11, rarity = 1, set = "Joker", text = { "+#1# Chips if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_chips = 100, type = "Three of a Kind" }, cost = 4, key = "j_wily", name = "Wily Joker", order = 12, rarity = 1, set = "Joker", text = { "+#1# Chips if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_chips = 80, type = "Two Pair" }, cost = 4, key = "j_clever", name = "Clever Joker", order = 13, rarity = 1, set = "Joker", text = { "+#1# Chips if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_chips = 100, type = "Straight" }, cost = 4, key = "j_devious", name = "Devious Joker", order = 14, rarity = 1, set = "Joker", text = { "+#1# Chips if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { t_chips = 80, type = "Flush" }, cost = 4, key = "j_crafty", name = "Crafty Joker", order = 15, rarity = 1, set = "Joker", text = { "+#1# Chips if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { extra = { mult = 20, size = 3 } }, cost = 5, effect = "Hand Size Mult", key = "j_half", name = "Half Joker", order = 16, rarity = 1, set = "Joker", text = { "+#1# Mult if played", "hand contains", "#2# or fewer cards" } },
  { blueprint_compat = true, config = {  }, cost = 8, effect = "Hand Size Mult", key = "j_stencil", name = "Joker Stencil", order = 17, rarity = 2, set = "Joker", text = { " X1  Mult for each", "empty Joker slot", "Joker Stencil included", "(Currently  X#1# )" } },
  { blueprint_compat = false, config = {  }, cost = 7, effect = "", key = "j_four_fingers", name = "Four Fingers", order = 18, rarity = 2, set = "Joker", text = { "All Flushes and", "Straights can be", "made with 4 cards" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 5, effect = "Hand card double", key = "j_mime", name = "Mime", order = 19, rarity = 2, set = "Joker", text = { "Retrigger all", "card held in", "hand abilities" } },
  { blueprint_compat = false, config = { extra = 20 }, cost = 1, effect = "Credit", key = "j_credit_card", name = "Credit Card", order = 20, rarity = 1, set = "Joker", text = { "Go up to", "-$#1# in debt" } },
  { blueprint_compat = true, config = { mult = 0 }, cost = 6, effect = "", key = "j_ceremonial", name = "Ceremonial Dagger", order = 21, rarity = 2, set = "Joker", text = { "When Blind is selected,", "destroy Joker to the right", "and permanently add double", "its sell value to this Mult", "(Currently +#1# Mult)" } },
  { blueprint_compat = true, config = { extra = 30 }, cost = 5, effect = "Discard Chips", key = "j_banner", name = "Banner", order = 22, rarity = 1, set = "Joker", text = { "+#1# Chips for", "each remaining", "discard" } },
  { blueprint_compat = true, config = { extra = { d_remaining = 0, mult = 15 } }, cost = 5, effect = "No Discard Mult", key = "j_mystic_summit", name = "Mystic Summit", order = 23, rarity = 1, set = "Joker", text = { "+#1# Mult when", "#2# discards", "remaining" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 6, effect = "Stone card hands", key = "j_marble", name = "Marble Joker", order = 24, rarity = 2, set = "Joker", text = { "Adds one Stone card", "to deck when", "Blind is selected" } },
  { blueprint_compat = true, config = { extra = { Xmult = 4, every = 5, remaining = "5 remaining" } }, cost = 5, effect = "1 in 10 mult", key = "j_loyalty_card", name = "Loyalty Card", order = 25, rarity = 2, set = "Joker", text = { " X#1#  Mult every", "#2# hands played", "#3#" } },
  { blueprint_compat = true, config = { extra = 4 }, cost = 5, effect = "Spawn Tarot", key = "j_8_ball", name = "8 Ball", order = 26, rarity = 1, set = "Joker", text = { "#1# in #2# chance for each", "played 8 to create a", "Tarot card when scored", "(Must have room)" } },
  { blueprint_compat = true, config = { extra = { max = 23, min = 0 } }, cost = 4, effect = "Random Mult", key = "j_misprint", name = "Misprint", order = 27, rarity = 1, set = "Joker", text = { "" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 5, effect = "", key = "j_dusk", name = "Dusk", order = 28, rarity = 2, set = "Joker", text = { "Retrigger all played", "cards in final", "hand of round" } },
  { blueprint_compat = true, config = {  }, cost = 5, effect = "Socialized Mult", key = "j_raised_fist", name = "Raised Fist", order = 29, rarity = 1, set = "Joker", text = { "Adds double the rank", "of lowest ranked card", "held in hand to Mult" } },
  { blueprint_compat = false, config = { extra = 1 }, cost = 4, effect = "Bonus Rerolls", key = "j_chaos", name = "Chaos the Clown", order = 30, rarity = 1, set = "Joker", text = { "#1# free Reroll", "per shop" } },
  { blueprint_compat = true, config = { extra = 8 }, cost = 8, effect = "Card Mult", key = "j_fibonacci", name = "Fibonacci", order = 31, rarity = 2, set = "Joker", text = { "Each played Ace,", "2, 3, 5, or 8 gives", "+#1# Mult when scored" } },
  { blueprint_compat = true, config = { extra = 0.2 }, cost = 7, effect = "Steel Card Buff", key = "j_steel_joker", name = "Steel Joker", order = 32, rarity = 2, set = "Joker", text = { "Gives  X#1#  Mult", "for each Steel Card", "in your full deck", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 30 }, cost = 4, effect = "Scary Face Cards", key = "j_scary_face", name = "Scary Face", order = 33, rarity = 1, set = "Joker", text = { "Played face cards", "give +#1# Chips", "when scored" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 4, effect = "Joker Mult", key = "j_abstract", name = "Abstract Joker", order = 34, rarity = 1, set = "Joker", text = { "+#1# Mult for", "each Joker card", "(Currently +#2# Mult)" } },
  { blueprint_compat = false, config = { extra = 2 }, cost = 4, effect = "Discard dollars", key = "j_delayed_grat", name = "Delayed Gratification", order = 35, rarity = 1, set = "Joker", text = { "Earn $#1# per discard if", "no discards are used", "by end of the round" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 6, effect = "Low Card double", key = "j_hack", name = "Hack", order = 36, rarity = 2, set = "Joker", text = { "Retrigger", "each played", "2, 3, 4, or 5" } },
  { blueprint_compat = false, config = {  }, cost = 5, effect = "All face cards", key = "j_pareidolia", name = "Pareidolia", order = 37, rarity = 2, set = "Joker", text = { "All cards are", "considered", "face cards" } },
  { blueprint_compat = true, config = { extra = { mult = 15, odds = 6 } }, cost = 5, effect = "", key = "j_gros_michel", name = "Gros Michel", order = 38, rarity = 1, set = "Joker", text = { "+#1# Mult", "#2# in #3# chance this", "card is destroyed", "at end of round" } },
  { blueprint_compat = true, config = { extra = 4 }, cost = 4, effect = "Even Card Buff", key = "j_even_steven", name = "Even Steven", order = 39, rarity = 1, set = "Joker", text = { "Played cards with", "even rank give", "+#1# Mult when scored", "(10, 8, 6, 4, 2)" } },
  { blueprint_compat = true, config = { extra = 31 }, cost = 4, effect = "Odd Card Buff", key = "j_odd_todd", name = "Odd Todd", order = 40, rarity = 1, set = "Joker", text = { "Played cards with", "odd rank give", "+#1# Chips when scored", "(A, 9, 7, 5, 3)" } },
  { blueprint_compat = true, config = { extra = { chips = 20, mult = 4 } }, cost = 4, effect = "Ace Buff", key = "j_scholar", name = "Scholar", order = 41, rarity = 1, set = "Joker", text = { "Played Aces", "give +#2# Chips", "and +#1# Mult", "when scored" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 4, effect = "Face Card dollar Chance", key = "j_business", name = "Business Card", order = 42, rarity = 1, set = "Joker", text = { "Played face cards have", "a #1# in #2# chance to", "give $2 when scored" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 5, effect = "Hand played mult", key = "j_supernova", name = "Supernova", order = 43, rarity = 1, set = "Joker", text = { "Adds the number of times", "poker hand has been", "played this run to Mult" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 6, effect = "", key = "j_ride_the_bus", name = "Ride the Bus", order = 44, rarity = 1, set = "Joker", text = { "This Joker gains +#1# Mult", "per consecutive hand", "played without a", "scoring face card", "(Currently +#2# Mult)" } },
  { blueprint_compat = true, config = { extra = 4 }, cost = 5, effect = "Upgrade Hand chance", key = "j_space", name = "Space Joker", order = 45, rarity = 2, set = "Joker", text = { "#1# in #2# chance to", "upgrade level of", "played poker hand" } },
  { blueprint_compat = false, config = { extra = 3 }, cost = 4, key = "j_egg", name = "Egg", order = 46, rarity = 1, set = "Joker", text = { "Gains $#1# of", "sell value at", "end of round" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 6, key = "j_burglar", name = "Burglar", order = 47, rarity = 2, set = "Joker", text = { "When Blind is selected,", "gain +#1# Hands and", "lose all discards" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 6, key = "j_blackboard", name = "Blackboard", order = 48, rarity = 2, set = "Joker", text = { " X#1#  Mult if all", "cards held in hand", "are #2# or #3#" } },
  { blueprint_compat = true, config = { extra = { chip_mod = 15, chips = 0 } }, cost = 5, key = "j_runner", name = "Runner", order = 49, rarity = 1, set = "Joker", text = { "Gains +#2# Chips", "if played hand", "contains a Straight", "(Currently +#1# Chips)" } },
  { blueprint_compat = true, config = { extra = { chip_mod = 5, chips = 100 } }, cost = 5, key = "j_ice_cream", name = "Ice Cream", order = 50, rarity = 1, set = "Joker", text = { "+#1# Chips", "-#2# Chips for", "every hand played" } },
  { blueprint_compat = true, config = {  }, cost = 8, key = "j_dna", name = "DNA", order = 51, rarity = 3, set = "Joker", text = { "If first hand of round", "has only 1 card, add a", "permanent copy to deck", "and draw it to hand" } },
  { blueprint_compat = false, config = {  }, cost = 3, key = "j_splash", name = "Splash", order = 52, rarity = 1, set = "Joker", text = { "Every played card", "counts in scoring" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 5, key = "j_blue_joker", name = "Blue Joker", order = 53, rarity = 1, set = "Joker", text = { "+#1# Chips for each", "remaining card in deck", "(Currently +#2# Chips)" } },
  { blueprint_compat = false, config = {  }, cost = 6, key = "j_sixth_sense", name = "Sixth Sense", order = 54, rarity = 2, set = "Joker", text = { "If first hand of round is", "a single 6, destroy it and", "create a Spectral card", "(Must have room)" } },
  { blueprint_compat = true, config = { Xmult = 1, extra = 0.1 }, cost = 6, key = "j_constellation", name = "Constellation", order = 55, rarity = 2, set = "Joker", text = { "This Joker gains", " X#1#  Mult every time", "a Planet card is used", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 5 }, cost = 5, key = "j_hiker", name = "Hiker", order = 56, rarity = 2, set = "Joker", text = { "Every played card", "permanently gains", "+#1# Chips when scored" } },
  { blueprint_compat = true, config = { extra = { dollars = 5, faces = 3 } }, cost = 4, key = "j_faceless", name = "Faceless Joker", order = 57, rarity = 1, set = "Joker", text = { "Earn $#1# if #2# or", "more face cards", "are discarded", "at the same time" } },
  { blueprint_compat = true, config = { extra = { discard_sub = 1, hand_add = 1 } }, cost = 4, key = "j_green_joker", name = "Green Joker", order = 58, rarity = 1, set = "Joker", text = { "+#1# Mult per hand played", "-#2# Mult per discard", "(Currently +#3# Mult)" } },
  { blueprint_compat = true, config = {  }, cost = 4, key = "j_superposition", name = "Superposition", order = 59, rarity = 1, set = "Joker", text = { "Create a Tarot card if", "poker hand contains an", "Ace and a Straight", "(Must have room)" } },
  { blueprint_compat = true, config = { extra = { dollars = 4, poker_hand = "High Card" } }, cost = 4, key = "j_todo_list", name = "To Do List", order = 60, rarity = 1, set = "Joker", text = { "Earn $#1# if poker hand", "is a #2#,", "poker hand changes", "at end of round" } },
  { blueprint_compat = true, config = { extra = { Xmult = 3, odds = 1000 } }, cost = 4, key = "j_cavendish", name = "Cavendish", order = 61, rarity = 1, set = "Joker", text = { " X#1#  Mult", "#2# in #3# chance this", "card is destroyed", "at end of round" } },
  { blueprint_compat = true, config = { extra = { Xmult = 3 } }, cost = 6, key = "j_card_sharp", name = "Card Sharp", order = 62, rarity = 2, set = "Joker", text = { " X#1#  Mult if played", "poker hand has already", "been played this round" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 5, key = "j_red_card", name = "Red Card", order = 63, rarity = 1, set = "Joker", text = { "This Joker gains", "+#1# Mult when any", "Booster Pack is skipped", "(Currently +#2# Mult)" } },
  { blueprint_compat = true, config = { extra = 0.5 }, cost = 7, key = "j_madness", name = "Madness", order = 64, rarity = 2, set = "Joker", text = { "When Small Blind or Big Blind", "is selected, gain  X#1#  Mult", "and destroy a random Joker", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = { chip_mod = 4, chips = 0 } }, cost = 4, key = "j_square", name = "Square Joker", order = 65, rarity = 1, set = "Joker", text = { "This Joker gains +#2# Chips", "if played hand has", "exactly 4 cards", "(Currently #1# Chips)" } },
  { blueprint_compat = true, config = { extra = { poker_hand = "Straight Flush" } }, cost = 6, key = "j_seance", name = "Seance", order = 66, rarity = 2, set = "Joker", text = { "If poker hand is a", "#1#, create a", "random Spectral card", "(Must have room)" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 6, key = "j_riff_raff", name = "Riff-raff", order = 67, rarity = 1, set = "Joker", text = { "When Blind is selected,", "create #1# Common Jokers", "(Must have room)" } },
  { blueprint_compat = true, config = { Xmult = 1, extra = 0.1 }, cost = 7, key = "j_vampire", name = "Vampire", order = 68, rarity = 2, set = "Joker", text = { "This Joker gains  X#1#  Mult", "per scoring Enhanced card played,", "removes card Enhancement", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = false, config = {  }, cost = 7, key = "j_shortcut", name = "Shortcut", order = 69, rarity = 2, set = "Joker", text = { "Allows Straights to be", "made with gaps of 1 rank", "(ex: 10 8 6 5 3)" } },
  { blueprint_compat = true, config = { Xmult = 1, extra = 0.25 }, cost = 7, key = "j_hologram", name = "Hologram", order = 70, rarity = 2, set = "Joker", text = { "This Joker gains  X#1#  Mult", "every time a playing card", "is added to your deck", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 4 }, cost = 8, key = "j_vagabond", name = "Vagabond", order = 71, rarity = 3, set = "Joker", text = { "Create a Tarot card", "if hand is played", "with $#1# or less" } },
  { blueprint_compat = true, config = { extra = 1.5 }, cost = 8, key = "j_baron", name = "Baron", order = 72, rarity = 3, set = "Joker", text = { "Each King", "held in hand", "gives  X#1#  Mult" } },
  { blueprint_compat = false, config = { extra = 1 }, cost = 7, key = "j_cloud_9", name = "Cloud 9", order = 73, rarity = 2, set = "Joker", text = { "Earn $#1# for each", "9 in your full deck", "at end of round", "(Currently $#2#)" } },
  { blueprint_compat = false, config = { extra = { dollars = 1, increase = 2 } }, cost = 6, key = "j_rocket", name = "Rocket", order = 74, rarity = 2, set = "Joker", text = { "Earn $#1# at end of round", "Payout increases by $#2#", "when Boss Blind is defeated" } },
  { blueprint_compat = true, config = { Xmult = 1, extra = 0.2 }, cost = 8, key = "j_obelisk", name = "Obelisk", order = 75, rarity = 3, set = "Joker", text = { "This Joker gains  X#1#  Mult", "per consecutive hand played", "without playing your", "most played poker hand", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = false, config = {  }, cost = 7, key = "j_midas_mask", name = "Midas Mask", order = 76, rarity = 2, set = "Joker", text = { "All played face cards", "become Gold cards", "when scored" } },
  { blueprint_compat = true, config = {  }, cost = 5, key = "j_luchador", name = "Luchador", order = 77, rarity = 2, set = "Joker", text = { "Sell this card to", "disable the current", "Boss Blind" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 5, key = "j_photograph", name = "Photograph", order = 78, rarity = 1, set = "Joker", text = { "First played face", "card gives  X#1#  Mult", "when scored" } },
  { blueprint_compat = false, config = { extra = 1 }, cost = 6, key = "j_gift", name = "Gift Card", order = 79, rarity = 2, set = "Joker", text = { "Add $#1# of sell value", "to every Joker and", "Consumable card at", "end of round" } },
  { blueprint_compat = false, config = { extra = { h_mod = 1, h_size = 5 } }, cost = 6, key = "j_turtle_bean", name = "Turtle Bean", order = 80, rarity = 2, set = "Joker", text = { "+#1# hand size,", "reduces by", "#2# every round" } },
  { blueprint_compat = true, config = { extra = 4 }, cost = 6, key = "j_erosion", name = "Erosion", order = 81, rarity = 2, set = "Joker", text = { "+#1# Mult for each", "card below #3#", "in your full deck", "(Currently +#2# Mult)" } },
  { blueprint_compat = true, config = { extra = { dollars = 1, odds = 2 } }, cost = 6, key = "j_reserved_parking", name = "Reserved Parking", order = 82, rarity = 1, set = "Joker", text = { "Each face card", "held in hand has", "a #2# in #3# chance", "to give $#1#" } },
  { blueprint_compat = true, config = { extra = 5 }, cost = 4, key = "j_mail", name = "Mail-In Rebate", order = 83, rarity = 1, set = "Joker", text = { "Earn $#1# for each", "discarded #2#, rank", "changes every round" } },
  { blueprint_compat = false, config = { extra = 1 }, cost = 5, key = "j_to_the_moon", name = "To the Moon", order = 84, rarity = 2, set = "Joker", text = { "Earn an extra $#1# of", "interest for every $5 you", "have at end of round" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 4, key = "j_hallucination", name = "Hallucination", order = 85, rarity = 1, set = "Joker", text = { "#1# in #2# chance to create", "a Tarot card when any", "Booster Pack is opened", "(Must have room)" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 6, effect = "", key = "j_fortune_teller", name = "Fortune Teller", order = 86, rarity = 1, set = "Joker", text = { "+#1# Mult per Tarot", "card used this run", "(Currently +#2#)" } },
  { blueprint_compat = false, config = { h_size = 1 }, cost = 4, effect = "Hand Size", key = "j_juggler", name = "Juggler", order = 87, rarity = 1, set = "Joker", text = { "+#1# hand size" } },
  { blueprint_compat = false, config = { d_size = 1 }, cost = 4, effect = "Discard Size", key = "j_drunkard", name = "Drunkard", order = 88, rarity = 1, set = "Joker", text = { "+#1# discard", "each round" } },
  { blueprint_compat = true, config = { extra = 25 }, cost = 6, effect = "Stone Card Buff", key = "j_stone", name = "Stone Joker", order = 89, rarity = 2, set = "Joker", text = { "Gives +#1# Chips for", "each Stone Card", "in your full deck", "(Currently +#2# Chips)" } },
  { blueprint_compat = false, config = { extra = 4 }, cost = 6, effect = "Bonus dollars", key = "j_golden", name = "Golden Joker", order = 90, rarity = 1, set = "Joker", text = { "Earn $#1# at", "end of round" } },
  { blueprint_compat = true, config = { Xmult = 1, extra = 0.25 }, cost = 6, key = "j_lucky_cat", name = "Lucky Cat", order = 91, rarity = 2, set = "Joker", text = { "This Joker gains  X#1#  Mult", "every time a Lucky card", "successfully triggers", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 1.5 }, cost = 8, key = "j_baseball", name = "Baseball Card", order = 92, rarity = 3, set = "Joker", text = { "Uncommon Jokers", "each give  X#1#  Mult" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 6, key = "j_bull", name = "Bull", order = 93, rarity = 2, set = "Joker", text = { "+#1# Chips for", "each $1 you have", "(Currently +#2# Chips)" } },
  { blueprint_compat = true, config = {  }, cost = 6, key = "j_diet_cola", name = "Diet Cola", order = 94, rarity = 2, set = "Joker", text = { "Sell this card to", "create a free", "#1#" } },
  { blueprint_compat = false, config = { extra = 3 }, cost = 6, key = "j_trading", name = "Trading Card", order = 95, rarity = 2, set = "Joker", text = { "If first discard of round", "has only 1 card, destroy", "it and earn $#1#" } },
  { blueprint_compat = true, config = { extra = 2, mult = 0 }, cost = 5, key = "j_flash", name = "Flash Card", order = 96, rarity = 2, set = "Joker", text = { "This Joker gains +#1# Mult", "per reroll in the shop", "(Currently +#2# Mult)" } },
  { blueprint_compat = true, config = { extra = 4, mult = 20 }, cost = 5, key = "j_popcorn", name = "Popcorn", order = 97, rarity = 1, set = "Joker", text = { "+#1# Mult", "-#2# Mult per", "round played" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 6, key = "j_trousers", name = "Spare Trousers", order = 98, rarity = 2, set = "Joker", text = { "This Joker gains +#1# Mult", "if played hand contains", "a #2#", "(Currently +#3# Mult)" } },
  { blueprint_compat = true, config = { extra = 1.5 }, cost = 8, key = "j_ancient", name = "Ancient Joker", order = 99, rarity = 3, set = "Joker", text = { "Each played card with", "#2# suit gives", " X#1#  Mult when scored,", "suit changes at end of round" } },
  { blueprint_compat = true, config = { Xmult = 2, extra = 0.01 }, cost = 6, key = "j_ramen", name = "Ramen", order = 100, rarity = 2, set = "Joker", text = { " X#1#  Mult,", "loses  X#2#  Mult", "per card discarded" } },
  { blueprint_compat = true, config = { extra = { chips = 10, mult = 4 } }, cost = 4, key = "j_walkie_talkie", name = "Walkie Talkie", order = 101, rarity = 1, set = "Joker", text = { "Each played 10 or 4", "gives +#1# Chips and", "+#2# Mult when scored" } },
  { blueprint_compat = true, config = { extra = 10 }, cost = 6, key = "j_selzer", name = "Seltzer", order = 102, rarity = 2, set = "Joker", text = { "Retrigger all", "cards played for", "the next #1# hands" } },
  { blueprint_compat = true, config = { extra = { chip_mod = 3, chips = 0 } }, cost = 6, key = "j_castle", name = "Castle", order = 103, rarity = 2, set = "Joker", text = { "This Joker gains +#1# Chips", "per discarded #2# card,", "suit changes every round", "(Currently +#3# Chips)" } },
  { blueprint_compat = true, config = { extra = 5 }, cost = 4, key = "j_smiley", name = "Smiley Face", order = 104, rarity = 1, set = "Joker", text = { "Played face cards", "give +#1# Mult", "when scored" } },
  { blueprint_compat = true, config = { extra = 0.25 }, cost = 9, key = "j_campfire", name = "Campfire", order = 105, rarity = 3, set = "Joker", text = { "This Joker gains X#1# Mult", "for each card sold, resets", "when Boss Blind is defeated", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 4 }, cost = 5, effect = "dollars for Gold cards", key = "j_ticket", name = "Golden Ticket", order = 106, rarity = 1, set = "Joker", text = { "Played Gold cards", "earn $#1# when scored" } },
  { blueprint_compat = false, config = {  }, cost = 5, effect = "Prevent Death", key = "j_mr_bones", name = "Mr. Bones", order = 107, rarity = 2, set = "Joker", text = { "Prevents Death", "if chips scored", "are at least 25%", "of required chips", "self destructs" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 6, effect = "Shop size", key = "j_acrobat", name = "Acrobat", order = 108, rarity = 2, set = "Joker", text = { " X#1#  Mult on final", "hand of round" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 6, effect = "Face card double", key = "j_sock_and_buskin", name = "Sock and Buskin", order = 109, rarity = 2, set = "Joker", text = { "Retrigger all", "played face cards" } },
  { blueprint_compat = true, config = { mult = 1 }, cost = 4, effect = "Set Mult", key = "j_swashbuckler", name = "Swashbuckler", order = 110, rarity = 1, set = "Joker", text = { "Adds the sell value", "of all other owned", "Jokers to Mult", "(Currently +#1# Mult)" } },
  { blueprint_compat = false, config = { extra = { h_plays = -1, h_size = 2 } }, cost = 6, effect = "Hand Size, Plays", key = "j_troubadour", name = "Troubadour", order = 111, rarity = 2, set = "Joker", text = { "+#1# hand size,", "-#2# hand each round" } },
  { blueprint_compat = true, config = {  }, cost = 6, effect = "", key = "j_certificate", name = "Certificate", order = 112, rarity = 2, set = "Joker", text = { "When round begins,", "add a random playing", "card with a random", "seal to your hand" } },
  { blueprint_compat = false, config = {  }, cost = 7, effect = "", key = "j_smeared", name = "Smeared Joker", order = 113, rarity = 2, set = "Joker", text = { "Hearts and Diamonds", "count as the same suit,", "Spades and Clubs", "count as the same suit" } },
  { blueprint_compat = true, config = { extra = 0.25 }, cost = 6, effect = "", key = "j_throwback", name = "Throwback", order = 114, rarity = 2, set = "Joker", text = { " X#1#  Mult for each", "Blind skipped this run", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 4, effect = "", key = "j_hanging_chad", name = "Hanging Chad", order = 115, rarity = 1, set = "Joker", text = { "Retrigger first played", "card used in scoring", "#1# additional times" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 7, effect = "", key = "j_rough_gem", name = "Rough Gem", order = 116, rarity = 2, set = "Joker", text = { "Played cards with", "Diamond suit earn", "$#1# when scored" } },
  { blueprint_compat = true, config = { extra = { Xmult = 1.5, odds = 2 } }, cost = 7, effect = "", key = "j_bloodstone", name = "Bloodstone", order = 117, rarity = 2, set = "Joker", text = { "#1# in #2# chance for", "played cards with", "Heart suit to give", " X#3#  Mult when scored" } },
  { blueprint_compat = true, config = { extra = 50 }, cost = 7, effect = "", key = "j_arrowhead", name = "Arrowhead", order = 118, rarity = 2, set = "Joker", text = { "Played cards with", "Spade suit give", "+#1# Chips when scored" } },
  { blueprint_compat = true, config = { extra = 7 }, cost = 7, effect = "", key = "j_onyx_agate", name = "Onyx Agate", order = 119, rarity = 2, set = "Joker", text = { "Played cards with", "Club suit give", "+#1# Mult when scored" } },
  { blueprint_compat = true, config = { Xmult = 1, extra = 0.75 }, cost = 6, effect = "Glass Card", key = "j_glass", name = "Glass Joker", order = 120, rarity = 2, set = "Joker", text = { "This Joker gains  X#1#  Mult", "for every Glass Card", "that is destroyed", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = false, config = {  }, cost = 5, effect = "", key = "j_ring_master", name = "Showman", order = 121, rarity = 2, set = "Joker", text = { "Joker, Tarot, Planet,", "and Spectral cards may", "appear multiple times" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 6, effect = "", key = "j_flower_pot", name = "Flower Pot", order = 122, rarity = 2, set = "Joker", text = { " X#1#  Mult if poker", "hand contains a", "Diamond card, Club card,", "Heart card, and Spade card" } },
  { blueprint_compat = true, config = {  }, cost = 10, effect = "Copycat", key = "j_blueprint", name = "Blueprint", order = 123, rarity = 3, set = "Joker", text = { "Copies ability of", "Joker to the right" } },
  { blueprint_compat = true, config = { extra = { chip_mod = 8, chips = 0 } }, cost = 8, effect = "", key = "j_wee", name = "Wee Joker", order = 124, rarity = 3, set = "Joker", text = { "This Joker gains", "+#2# Chips when each", "played 2 is scored", "(Currently +#1# Chips)" } },
  { blueprint_compat = false, config = { d_size = 3, h_size = -1 }, cost = 7, effect = "", key = "j_merry_andy", name = "Merry Andy", order = 125, rarity = 2, set = "Joker", text = { "+#1# discards", "each round,", "#2# hand size" } },
  { blueprint_compat = false, config = {  }, cost = 4, effect = "", key = "j_oops", name = "Oops! All 6s", order = 126, rarity = 2, set = "Joker", text = { "Doubles all listed", "probabilities", "(ex: 1 in 3 -> 2 in 3)" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 6, effect = "", key = "j_idol", name = "The Idol", order = 127, rarity = 2, set = "Joker", text = { "Each played #2#", "of #3# gives", " X#1#  Mult when scored", "Card changes every round" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 6, effect = "X1.5 Mult club 7", key = "j_seeing_double", name = "Seeing Double", order = 128, rarity = 2, set = "Joker", text = { " X#1#  Mult if played", "hand has a scoring", "Club card and a scoring", "card of any other suit" } },
  { blueprint_compat = true, config = { extra = 8 }, cost = 7, effect = "", key = "j_matador", name = "Matador", order = 129, rarity = 2, set = "Joker", text = { "Earn $#1# if played", "hand triggers the", "Boss Blind ability" } },
  { blueprint_compat = true, config = { extra = 0.5 }, cost = 8, effect = "Jack Discard Effect", key = "j_hit_the_road", name = "Hit the Road", order = 130, rarity = 3, set = "Joker", text = { "This Joker gains  X#1#  Mult", "for every Jack", "discarded this round", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { Xmult = 2, type = "Pair" }, cost = 8, effect = "X1.5 Mult", key = "j_duo", name = "The Duo", order = 131, rarity = 3, set = "Joker", text = { " X#1#  Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { Xmult = 3, type = "Three of a Kind" }, cost = 8, effect = "X2 Mult", key = "j_trio", name = "The Trio", order = 132, rarity = 3, set = "Joker", text = { " X#1#  Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { Xmult = 4, type = "Four of a Kind" }, cost = 8, effect = "X3 Mult", key = "j_family", name = "The Family", order = 133, rarity = 3, set = "Joker", text = { " X#1#  Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { Xmult = 3, type = "Straight" }, cost = 8, effect = "X3 Mult", key = "j_order", name = "The Order", order = 134, rarity = 3, set = "Joker", text = { " X#1#  Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { Xmult = 2, type = "Flush" }, cost = 8, effect = "X3 Mult", key = "j_tribe", name = "The Tribe", order = 135, rarity = 3, set = "Joker", text = { " X#1#  Mult if played", "hand contains", "a #2#" } },
  { blueprint_compat = true, config = { extra = { chip_mod = 250, h_size = 2 } }, cost = 7, effect = "", key = "j_stuntman", name = "Stuntman", order = 136, rarity = 3, set = "Joker", text = { "+#1# Chips,", "-#2# hand size" } },
  { blueprint_compat = false, config = { extra = 2 }, cost = 8, effect = "", key = "j_invisible", name = "Invisible Joker", order = 137, rarity = 3, set = "Joker", text = { "After #1# rounds,", "sell this card to", "Duplicate a random Joker", "(Currently #2#/#1#)" } },
  { blueprint_compat = true, config = {  }, cost = 10, effect = "Copycat", key = "j_brainstorm", name = "Brainstorm", order = 138, rarity = 3, set = "Joker", text = { "Copies the ability", "of leftmost Joker" } },
  { blueprint_compat = false, config = { extra = 1 }, cost = 6, effect = "", key = "j_satellite", name = "Satellite", order = 139, rarity = 2, set = "Joker", text = { "Earn $#1# at end of", "round per unique Planet", "card used this run", "(Currently $#2#)" } },
  { blueprint_compat = true, config = { extra = 13 }, cost = 5, effect = "", key = "j_shoot_the_moon", name = "Shoot the Moon", order = 140, rarity = 1, set = "Joker", text = { "Each Queen", "held in hand", "gives +#1# Mult" } },
  { blueprint_compat = true, config = { extra = 3 }, cost = 7, effect = "", key = "j_drivers_license", name = "Driver's License", order = 141, rarity = 3, set = "Joker", text = { " X#1#  Mult if you have", "at least 16 Enhanced", "cards in your full deck", "(Currently #2#)" } },
  { blueprint_compat = true, config = {  }, cost = 6, effect = "Tarot Buff", key = "j_cartomancer", name = "Cartomancer", order = 142, rarity = 2, set = "Joker", text = { "Create a Tarot card", "when Blind is selected", "(Must have room)" } },
  { blueprint_compat = false, config = {  }, cost = 8, effect = "", key = "j_astronomer", name = "Astronomer", order = 143, rarity = 2, set = "Joker", text = { "All Planet cards and", "Celestial Packs in", "the shop are free" } },
  { blueprint_compat = true, config = { extra = 4, h_size = 0 }, cost = 8, effect = "", key = "j_burnt", name = "Burnt Joker", order = 144, rarity = 3, set = "Joker", text = { "Upgrade the level of", "the first discarded", "poker hand each round" } },
  { blueprint_compat = true, config = { extra = { dollars = 5, mult = 2 } }, cost = 7, effect = "", key = "j_bootstraps", name = "Bootstraps", order = 145, rarity = 2, set = "Joker", text = { "+#1# Mult for every", "$#2# you have", "(Currently +#3# Mult)" } },
  { blueprint_compat = true, config = { extra = 1 }, cost = 20, effect = "", key = "j_caino", name = "Caino", order = 146, rarity = 4, set = "Joker", text = { "This Joker gains  X#1#  Mult", "when a face card", "is destroyed", "(Currently  X#2#  Mult)" } },
  { blueprint_compat = true, config = { extra = 2 }, cost = 20, effect = "", key = "j_triboulet", name = "Triboulet", order = 147, rarity = 4, set = "Joker", text = { "Played Kings and", "Queens each give", " X#1#  Mult when scored" } },
  { blueprint_compat = true, config = { extra = { discards = 23, xmult = 1 } }, cost = 20, effect = "", key = "j_yorick", name = "Yorick", order = 148, rarity = 4, set = "Joker", text = { "This Joker gains", " X#1#  Mult every #2# [#3#]", "cards discarded", "(Currently  X#4#  Mult)" } },
  { blueprint_compat = false, config = {  }, cost = 20, effect = "", key = "j_chicot", name = "Chicot", order = 149, rarity = 4, set = "Joker", text = { "Disables effect of", "every Boss Blind" } },
  { blueprint_compat = true, config = {  }, cost = 20, effect = "", key = "j_perkeo", name = "Perkeo", order = 150, rarity = 4, set = "Joker", text = { "Creates a Negative copy of", "1 random consumable", "card in your possession", "at the end of the shop" } },
}
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[copy(k)] = copy(val) end
  return out
end

local function set_ability(center)
  local cfg = center.config or {}
  local ability = {
    name = center.name,
    effect = center.effect,
    set = center.set,
    mult = cfg.mult or 0,
    h_mult = cfg.h_mult or 0,
    h_x_mult = cfg.h_x_mult or 0,
    h_dollars = cfg.h_dollars or 0,
    p_dollars = cfg.p_dollars or 0,
    t_mult = cfg.t_mult or 0,
    t_chips = cfg.t_chips or 0,
    x_mult = cfg.Xmult or cfg.x_mult or 1,
    h_chips = cfg.h_chips or 0,
    x_chips = cfg.x_chips or 1,
    h_x_chips = cfg.h_x_chips or 1,
    repetitions = cfg.repetitions or 0,
    h_size = cfg.h_size or 0,
    d_size = cfg.d_size or 0,
    extra = copy(cfg.extra),
    extra_value = 0,
    type = cfg.type or "",
    order = center.order,
    perma_bonus = 0, perma_x_chips = 0, perma_mult = 0, perma_x_mult = 0,
    perma_h_chips = 0, perma_h_x_chips = 0, perma_h_mult = 0, perma_h_x_mult = 0,
    perma_p_dollars = 0, perma_h_dollars = 0, perma_repetitions = 0,
    perma_score = 0, perma_h_score = 0, perma_x_score = 0, perma_h_x_score = 0,
    perma_blind_size = 0, perma_h_blind_size = 0, perma_x_blind_size = 0, perma_h_x_blind_size = 0,
    card_limit = 0,
    extra_slots_used = 0,
    debuff_sources = {},
  }
  ability.card_limit = ability.card_limit + (cfg.card_limit or 0)
  ability.extra_slots_used = ability.extra_slots_used + (cfg.extra_slots_used or 0)
  ability.bonus = (cfg.bonus or 0)
  for k, v in pairs(cfg) do
    if k ~= "bonus" then ability[k] = copy(v) end
  end
  if center.name == "Invisible Joker" then
    ability.invis_rounds = 0
  elseif center.name == "Caino" then
    ability.caino_xmult = 1
  elseif center.name == "Yorick" then
    ability.yorick_discards = ability.extra.discards
  elseif center.name == "Loyalty Card" then
    ability.burnt_hand = 0
    ability.loyalty_remaining = ability.extra.every
  elseif center.name == "To Do List" then
    ability.to_do_poker_hand = ability.extra.poker_hand
  end
  ability.hands_played_at_create = (_G.G and _G.G.GAME and _G.G.GAME.hands_played) or 0
  return ability
end

local function num(v) return (type(v) == "number") and v or 0 end
local function ph(hand) return tostring(hand or "") end            -- localize(x, 'poker_hands')
local function suitN(suit) return tostring(suit or "") end          -- localize(x, 'suits_plural')
local function suit1(suit)                                          -- localize(x, 'suits_singular')
  local s = tostring(suit or "")
  return (s:gsub("s$", ""))
end
local function loyalty(remaining)
  return (num(remaining) == 0) and "Active!" or (tostring(remaining) .. " remaining")
end
local function game() return (_G.G and _G.G.GAME) or {} end
local function dollars() return num(game().dollars) + num(game().dollar_buffer) end
local function deck_size()
  local d = _G.G and _G.G.deck
  return (d and d.cards and #d.cards) or 52
end
local function joker_count()
  local j = _G.G and _G.G.jokers
  return (j and j.cards and #j.cards) or 0
end
local function tarot_used()
  local t = game().consumeable_usage_total
  return (t and num(t.tarot)) or 0
end
local function planets_used()
  local n = 0
  for _, v in pairs(game().consumeable_usage or {}) do if v.set == "Planet" then n = n + 1 end end
  return n
end
local function starting_deck_size() return num(game().starting_deck_size) end
local function erosion_missing()
  local pc = _G.G and _G.G.playing_cards
  if not pc then return 0 end
  return starting_deck_size() - #pc
end
local function round_card(field, part, fallback)
  local cr = game().current_round or {}
  local rec = cr[field]
  return (rec and rec[part]) or fallback
end

local LOC_VARS = {
  j_joker              = function(a) return { a.mult } end,
  j_jolly              = function(a) return { a.t_mult, ph(a.type) } end,
  j_zany               = function(a) return { a.t_mult, ph(a.type) } end,
  j_mad                = function(a) return { a.t_mult, ph(a.type) } end,
  j_crazy              = function(a) return { a.t_mult, ph(a.type) } end,
  j_droll              = function(a) return { a.t_mult, ph(a.type) } end,
  j_sly                = function(a) return { a.t_chips, ph(a.type) } end,
  j_wily               = function(a) return { a.t_chips, ph(a.type) } end,
  j_clever             = function(a) return { a.t_chips, ph(a.type) } end,
  j_devious            = function(a) return { a.t_chips, ph(a.type) } end,
  j_crafty             = function(a) return { a.t_chips, ph(a.type) } end,
  j_half               = function(a) return { a.extra.mult, a.extra.size } end,
  j_fortune_teller     = function(a) return { a.extra, tarot_used() } end,
  j_steel_joker        = function(a) return { a.extra, 1 + a.extra * (a.steel_tally or 0) } end,
  j_chaos              = function(a) return { a.extra } end,
  j_space              = function(a) return { 1, a.extra } end,
  j_stone              = function(a) return { a.extra, a.extra * (a.stone_tally or 0) } end,
  j_drunkard           = function(a) return { a.d_size } end,
  j_green_joker        = function(a) return { a.extra.hand_add, a.extra.discard_sub, a.mult } end,
  j_credit_card        = function(a) return { a.extra } end,
  j_greedy_joker       = function(a) return { a.extra.s_mult, suit1(a.extra.suit) } end,
  j_lusty_joker        = function(a) return { a.extra.s_mult, suit1(a.extra.suit) } end,
  j_wrathful_joker     = function(a) return { a.extra.s_mult, suit1(a.extra.suit) } end,
  j_gluttenous_joker   = function(a) return { a.extra.s_mult, suit1(a.extra.suit) } end,
  j_blue_joker         = function(a) return { a.extra, a.extra * deck_size() } end,
  j_hack               = function(a) return { a.extra + 1 } end,
  j_faceless           = function(a) return { a.extra.dollars, a.extra.faces } end,
  j_juggler            = function(a) return { a.h_size } end,
  j_golden             = function(a) return { a.extra } end,
  j_stencil            = function(a) return { a.x_mult } end,
  j_ceremonial         = function(a) return { a.mult } end,
  j_banner             = function(a) return { a.extra } end,
  j_mystic_summit      = function(a) return { a.extra.mult, a.extra.d_remaining } end,
  j_loyalty_card       = function(a) return { a.extra.Xmult, a.extra.every + 1, loyalty(a.loyalty_remaining) } end,
  j_8_ball             = function(a) return { 1, a.extra } end,
  j_dusk               = function(a) return { a.extra + 1 } end,
  j_fibonacci          = function(a) return { a.extra } end,
  j_scary_face         = function(a) return { a.extra } end,
  j_abstract           = function(a) return { a.extra, joker_count() * a.extra } end,
  j_delayed_grat       = function(a) return { a.extra } end,
  j_gros_michel        = function(a) return { a.extra.mult, 1, a.extra.odds } end,
  j_even_steven        = function(a) return { a.extra } end,
  j_odd_todd           = function(a) return { a.extra } end,
  j_scholar            = function(a) return { a.extra.mult, a.extra.chips } end,
  j_business           = function(a) return { 1, a.extra } end,
  j_trousers           = function(a) return { a.extra, ph("Two Pair"), a.mult } end,
  j_superposition      = function(a) return { a.extra } end,
  j_ride_the_bus       = function(a) return { a.extra, a.mult } end,
  j_egg                = function(a) return { a.extra } end,
  j_burglar            = function(a) return { a.extra } end,
  j_blackboard         = function(a) return { a.extra, suitN("Spades"), suitN("Clubs") } end,
  j_runner             = function(a) return { a.extra.chips, a.extra.chip_mod } end,
  j_ice_cream          = function(a) return { a.extra.chips, a.extra.chip_mod } end,
  j_dna                = function(a) return { a.extra } end,
  j_constellation      = function(a) return { a.extra, a.x_mult } end,
  j_hiker              = function(a) return { a.extra } end,
  j_todo_list          = function(a) return { a.extra.dollars, ph(a.to_do_poker_hand) } end,
  j_astronomer         = function(a) return { a.extra } end,
  j_ticket             = function(a) return { a.extra } end,
  j_acrobat            = function(a) return { a.extra } end,
  j_sock_and_buskin    = function(a) return { a.extra + 1 } end,
  j_swashbuckler       = function(a) return { a.mult } end,
  j_troubadour         = function(a) return { a.extra.h_size, -a.extra.h_plays } end,
  j_certificate        = function(a) return { a.extra } end,
  j_throwback          = function(a) return { a.extra, a.x_mult } end,
  j_hanging_chad       = function(a) return { a.extra } end,
  j_rough_gem          = function(a) return { a.extra } end,
  j_bloodstone         = function(a) return { 1, a.extra.odds, a.extra.Xmult } end,
  j_arrowhead          = function(a) return { a.extra } end,
  j_onyx_agate         = function(a) return { a.extra } end,
  j_glass              = function(a) return { a.extra, a.x_mult } end,
  j_flower_pot         = function(a) return { a.extra } end,
  j_wee                = function(a) return { a.extra.chips, a.extra.chip_mod } end,
  j_merry_andy         = function(a) return { a.d_size, a.h_size } end,
  j_idol               = function(a) return { a.extra, round_card("idol_card", "rank", "Ace"), suitN(round_card("idol_card", "suit", "Spades")) } end,
  j_seeing_double      = function(a) return { a.extra } end,
  j_matador            = function(a) return { a.extra } end,
  j_hit_the_road       = function(a) return { a.extra, a.x_mult } end,
  j_duo                = function(a) return { a.x_mult, ph(a.type) } end,
  j_trio               = function(a) return { a.x_mult, ph(a.type) } end,
  j_family             = function(a) return { a.x_mult, ph(a.type) } end,
  j_order              = function(a) return { a.x_mult, ph(a.type) } end,
  j_tribe              = function(a) return { a.x_mult, ph(a.type) } end,
  j_cavendish          = function(a) return { a.extra.Xmult, 1, a.extra.odds } end,
  j_card_sharp         = function(a) return { a.extra.Xmult } end,
  j_red_card           = function(a) return { a.extra, a.mult } end,
  j_madness            = function(a) return { a.extra, a.x_mult } end,
  j_square             = function(a) return { a.extra.chips, a.extra.chip_mod } end,
  j_seance             = function(a) return { ph(a.extra.poker_hand) } end,
  j_riff_raff          = function(a) return { a.extra } end,
  j_vampire            = function(a) return { a.extra, a.x_mult } end,
  j_hologram           = function(a) return { a.extra, a.x_mult } end,
  j_vagabond           = function(a) return { a.extra } end,
  j_baron              = function(a) return { a.extra } end,
  j_cloud_9            = function(a) return { a.extra, a.extra * (a.nine_tally or 0) } end,
  j_rocket             = function(a) return { a.extra.dollars, a.extra.increase } end,
  j_obelisk            = function(a) return { a.extra, a.x_mult } end,
  j_photograph         = function(a) return { a.extra } end,
  j_gift               = function(a) return { a.extra } end,
  j_turtle_bean        = function(a) return { a.extra.h_size, a.extra.h_mod } end,
  j_erosion            = function(a) return { a.extra, math.max(0, a.extra * erosion_missing()), starting_deck_size() } end,
  j_reserved_parking   = function(a) return { a.extra.dollars, 1, a.extra.odds } end,
  j_mail               = function(a) return { a.extra, round_card("mail_card", "rank", "Ace") } end,
  j_to_the_moon        = function(a) return { a.extra } end,
  j_hallucination      = function(a) return { 1, a.extra } end,
  j_lucky_cat          = function(a) return { a.extra, a.x_mult } end,
  j_baseball           = function(a) return { a.extra } end,
  j_bull               = function(a) return { a.extra, a.extra * math.max(0, dollars()) } end,
  j_diet_cola          = function(a) return { "Double Tag" } end,
  j_trading            = function(a) return { a.extra } end,
  j_flash              = function(a) return { a.extra, a.mult } end,
  j_popcorn            = function(a) return { a.mult, a.extra } end,
  j_ramen              = function(a) return { a.x_mult, a.extra } end,
  j_ancient            = function(a) return { a.extra, suit1(round_card("ancient_card", "suit", "Spades")) } end,
  j_walkie_talkie      = function(a) return { a.extra.chips, a.extra.mult } end,
  j_selzer             = function(a) return { a.extra } end,
  j_castle             = function(a) return { a.extra.chip_mod, suit1(round_card("castle_card", "suit", "Spades")), a.extra.chips } end,
  j_smiley             = function(a) return { a.extra } end,
  j_campfire           = function(a) return { a.extra, a.x_mult } end,
  j_stuntman           = function(a) return { a.extra.chip_mod, a.extra.h_size } end,
  j_invisible          = function(a) return { a.extra, a.invis_rounds } end,
  j_satellite          = function(a) return { a.extra, planets_used() * a.extra } end,
  j_shoot_the_moon     = function(a) return { a.extra } end,
  j_drivers_license    = function(a) return { a.extra, a.driver_tally or "0" } end,
  j_bootstraps         = function(a) return { a.extra.mult, a.extra.dollars, a.extra.mult * math.floor(dollars() / a.extra.dollars) } end,
  j_caino              = function(a) return { a.extra, a.caino_xmult } end,
  j_triboulet          = function(a) return { a.extra } end,
  j_yorick             = function(a) return { a.extra.xmult, a.extra.discards, a.yorick_discards, a.x_mult } end,
  j_perkeo             = function(a) return { a.extra } end,
}

local M = {}

local BY_KEY = {}
for _, rec in ipairs(CENTERS) do BY_KEY[rec.key] = rec end

function M.keys()
  local out = {}
  for i, rec in ipairs(CENTERS) do out[i] = rec.key end
  return out
end

function M.card(key, sort_id)
  local rec = BY_KEY[key]
  if not rec then error("unknown vanilla joker key: " .. tostring(key)) end
  local center = {
    key = rec.key,
    name = rec.name,
    set = rec.set,
    effect = rec.effect,
    order = rec.order,
    cost = rec.cost,
    rarity = rec.rarity,
    blueprint_compat = rec.blueprint_compat,
    config = copy(rec.config),
    loc_txt = { name = rec.name, text = copy(rec.text) },
  }
  local vars = LOC_VARS[rec.key]
  if vars then
    center.loc_vars = function(_center, _info_queue, live)
      return { vars = vars(((live or {}).ability) or {}) }
    end
  end
  return {
    sort_id = sort_id or rec.order,
    sell_cost = math.max(1, math.floor((rec.cost or 2) / 2)),
    cost = rec.cost,
    ability = set_ability(center),
    config = { center = center },
  }
end

local PLAYED_STATE = {
  j_ceremonial = { mult = 6 }, j_trousers = { mult = 6 },
  j_ride_the_bus = { mult = 6 }, j_flash = { mult = 6 }, j_green_joker = { mult = 6 }, j_red_card = { mult = 6 },
  j_constellation = { x_mult = 1.5 }, j_vampire = { x_mult = 1.5 }, j_hologram = { x_mult = 1.5 },
  j_obelisk = { x_mult = 1.5 }, j_lucky_cat = { x_mult = 1.5 }, j_campfire = { x_mult = 1.5 },
  j_glass = { x_mult = 1.5 }, j_hit_the_road = { x_mult = 1.5 }, j_madness = { x_mult = 1.5 },
  j_throwback = { x_mult = 1.5 }, j_stencil = { x_mult = 1.5 }, j_yorick = { x_mult = 1.5 },
  j_caino = { caino_xmult = 2 },
  j_steel_joker = { steel_tally = 3 }, j_stone = { stone_tally = 3 },
  j_wee = { extra = { chips = 40 } }, j_square = { extra = { chips = 40 } },
  j_runner = { extra = { chips = 40 } }, j_castle = { extra = { chips = 40 } },
}

function M.played_keys()
  local out = {}
  for k in pairs(PLAYED_STATE) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function M.card_played(key, sort_id)
  local card = M.card(key, sort_id)
  local overlay = PLAYED_STATE[key]
  if overlay then
    for field, value in pairs(overlay) do
      if type(value) == "table" then
        card.ability[field] = card.ability[field] or {}
        for k, v in pairs(value) do card.ability[field][k] = v end
      else
        card.ability[field] = value
      end
    end
  end
  return card
end

return M
