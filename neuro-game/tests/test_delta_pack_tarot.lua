require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("delta-pack-tarot")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local function since(force)
  return (force and force.state or ""):match("Since your last decision[^\n]*") or "(no delta line)"
end

local function pack_then_shop(seed, extra)
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local shop = { shop_jokers = G.shop_jokers, shop_vouchers = G.shop_vouchers, shop_booster = G.shop_booster }
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  for _, c in ipairs(G.deck.cards) do c.facing = "back" end
  check("fixture: the pack decision went out", FP.build("SMODS_BOOSTER_OPENED") ~= nil)
  local hand = {}
  for i, c in ipairs(G.hand.cards) do hand[i] = c end
  hand[1].base.suit = "Clubs"
  hand[2].base.suit = "Clubs"
  hand[3].config.center = G.P_CENTERS.m_mult
  hand[3].ability.set, hand[3].ability.name = "Enhanced", "Mult Card"
  if extra then extra(hand) end
  local kept = {}
  for _, c in ipairs(hand) do
    if c.ability.wheel_flipped then
      kept[#kept + 1] = c
    else
      c.area, c.facing = G.deck, "back"
      table.insert(G.deck.cards, 1, c)
    end
  end
  G.hand.cards, G.pack_cards = kept, nil
  if seed > 0 then
    local x = seed
    for i = #G.deck.cards, 2, -1 do
      x = (x * 1103515245 + 12345) % 2147483648
      local j = (x % i) + 1
      G.deck.cards[i], G.deck.cards[j] = G.deck.cards[j], G.deck.cards[i]
    end
  end
  for k, v in pairs(shop) do G[k] = v end
  G.NEURO.decision_serial = G.NEURO.decision_serial + 1
  G.NEURO.answered_decisions = (tonumber(G.NEURO.answered_decisions) or 0) + 1
  return since(FP.build("SHOP"))
end

do
  local line = pack_then_shop(0)
  check("a suit change made in the pack is reported after the cards return to the pile",
    line:find("King of Hearts to King of Clubs", 1, true) ~= nil
      and line:find("King of Spades to King of Clubs", 1, true) ~= nil, line)
  check("an enhancement made in the pack is reported", line:find("Queen of Hearts to Queen of Hearts (Mult", 1, true) ~= nil,
    line)
  check("unchanged cards are not listed", line:find("Jack of Hearts", 1, true) == nil, line)
  for _, seed in ipairs({ 7, 977, 31337 }) do
    local other = pack_then_shop(seed)
    check("the line does not depend on the draw pile's order (seed " .. seed .. ")", other == line,
      line .. "\nvs\n" .. other)
  end
end

do
  local line = pack_then_shop(0, function(hand)
    local unseen = G.deck.cards[#G.deck.cards]
    unseen.config.center = G.P_CENTERS.m_gold
    unseen.ability.set, unseen.ability.name = "Enhanced", "Gold Card"
    local flipped = hand[4]
    flipped.base.suit = "Spades"
    flipped.facing, flipped.ability.wheel_flipped = "back", true
  end)
  check("a card never seen face-up is not reported", line:find("Gold", 1, true) == nil, line)
  check("a seen card now face-down in hand is not reported", line:find("Jack of", 1, true) == nil, line)
  check("control: the seen changes still are", line:find("King of Hearts to King of Clubs", 1, true) ~= nil, line)
end

done()
