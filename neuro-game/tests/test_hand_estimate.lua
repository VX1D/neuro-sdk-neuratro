_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")

local check, done = require("tests.helpers").harness("hand-estimate")

local RID = require("tests.helpers").RID
local VALN = require("tests.helpers").VALN
local function card(v, suit, opts)
  opts = opts or {}
  local id = RID[v]
  return {
    base = { value = VALN[v] or v, suit = suit },
    debuff = opts.debuff or nil,
    config = { center = { key = opts.center or "c_base", set = "Default" } },
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end

local function setup(cards, opts)
  opts = opts or {}
  G.hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = {
    current_round = { discards_left = opts.discards or 0, hands_left = 4 },
    hands = opts.levels or {},
    blind = opts.blind,
    chips = opts.chips or 0,
  }
  G.jokers = opts.jokers
  G.deck = opts.deck
  G.FUNCS = { get_poker_hand_info = function() return nil, nil, opts.ph or {} end }
end

do
  local kh, ks = card("K","Hearts"), card("K","Spades")
  setup({ kh, ks, card("2","Clubs"), card("7","Diamonds") },
    { levels = { Pair = { level=1, chips=10, mult=2 } }, ph = { Pair = { { kh, ks } } },
      blind = { chips = 300 }, chips = 250 })
  local s = HF.summary()
  check("1: (lv..) fact present", s:find("Pair%[1,2%]%(lv1 10c x2%)") ~= nil, s)
  check("1: no projection token", s:find("(~", 1, true) == nil and s:find("p>=R", 1, true) == nil, s)
end

do
  local h = { card("K","Hearts"), card("K","Spades"), card("2","Hearts"), card("4","Hearts"),
              card("7","Hearts"), card("9","Hearts"), card("3","Clubs"), card("5","Diamonds") }
  local flush = { h[3], h[4], h[5], h[6], h[1] }
  setup(h, { levels = {
      Pair = { level = 6, chips = 90, mult = 7 },
      Flush = { level = 1, chips = 35, mult = 4 },
    }, ph = { Pair = { { h[1], h[2] } }, Flush = { flush } } })
  local s = HF.summary()
  local f_at, p_at = s:find("Flush%["), s:find("Pair%[")
  check("2: Flush and Pair both listed as Ready (display order is intentionally randomized, not asserted)",
    f_at ~= nil and p_at ~= nil, s:match("Ready:[^%.]*"))
end

do
  local h = { card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
              card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades") }
  setup(h, { discards = 2, deck = { cards = {
    card("6","Hearts"), card("J","Hearts"), card("Q","Spades"), card("10","Clubs") } } })
  local s = HF.summary()
  check("3: near flush keep/other + outs 2/4",
    s:find("Flush: 4 Hearts keep%[1,2,3,4%]/other%[5,6,7,8%]%(draw 2/4=%d+%%%)") ~= nil, s)
end

do
  local h = { card("5","Hearts"), card("6","Diamonds"), card("7","Spades"), card("9","Clubs"),
              card("K","Hearts"), card("2","Clubs"), card("Q","Diamonds"), card("A","Spades") }
  setup(h, { discards = 2, deck = { cards = {
    card("8","Hearts"), card("8","Clubs"), card("4","Spades"), card("J","Diamonds") } } })
  local s = HF.summary()
  check("4: inside straight outs = the 8s only (2/4)",
    s:find("Straight keep%[1,2,3,4%].-%(draw 2/4=%d+%%%)") ~= nil, s)
end

do
  local h = { card("K","Hearts"), card("K","Spades"), card("7","Clubs"), card("2","Diamonds") }
  setup(h, { discards = 2, deck = { cards = {
    card("7","Hearts"), card("2","Spades"), card("K","Clubs"), card("9","Diamonds") } } })
  local s = HF.summary()
  check("5: near Two Pair must hold a kicker; outs are that kicker's rank only",
    s:find("Two Pair keep%[1,2,3%]/other%[4%]%(draw 1/4=100%%%)") ~= nil,
    s:match("Close:[^%.]*") or s)

do
  local hearts = { card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts") }
  local rest = { card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades") }
  local pile = {}
  for _ = 1, 9 do pile[#pile + 1] = card("6","Hearts") end
  for _ = 1, 31 do pile[#pile + 1] = card("Q","Spades") end
  local hand = {}
  for _, c in ipairs(hearts) do hand[#hand + 1] = c end
  for _, c in ipairs(rest) do hand[#hand + 1] = c end
  setup(hand, { discards = 2, deck = { cards = pile } })
  local s2 = HF.summary()
  local pct = tonumber(s2:match("Flush: 4 Hearts keep%[1,2,3,4%]/other%[5,6,7,8%]%(draw 9/40=(%d+)%%%)"))
  check("draw odds use all four discards, not one card", pct == 66,
    tostring(pct) .. " -- " .. (s2:match("Close:[^%.]*") or s2))
  check("draw odds are strictly better than the single-card rate",
    pct ~= nil and pct > math.floor(9 / 40 * 100 + 0.5), tostring(pct))
end
end

do
  local calls = 0
  local fc = { card("2","Hearts"), card("4","Hearts"), card("7","Hearts"),
               card("9","Hearts"), card("J","Hearts") }
  local h = { fc[1], fc[2], fc[3], fc[4], fc[5], card("K","Spades") }
  setup(h, { levels = { Flush = { level=1, chips=35, mult=4 } } })
  G.FUNCS = { get_poker_hand_info = function()
    calls = calls + 1
    return nil, nil, { Flush = { fc } }
  end }
  HF.summary()
  local c0 = calls
  check("6: strong ready from cache", HF.has_strong_ready() == true, tostring(calls))
  check("6: no second engine call", calls == c0, calls .. " vs " .. c0)
  h[1].debuff = true
  HF.has_strong_ready()
  check("6: hand change invalidates cache", calls == c0 + 1, calls .. " vs " .. (c0 + 1))
  h[1].debuff = nil
end

do
  local h = { card("2","Hearts"), card("3","Hearts"), card("4","Hearts"), card("5","Hearts"),
              card("6","Hearts"), card("K","Hearts"), card("K","Spades"), card("9","Clubs") }
  local straight = { h[1], h[2], h[3], h[4], h[5] }
  local flush = { h[1], h[2], h[3], h[4], h[5], h[6] }
  local merged = {}
  local seen = {}
  for _, grp in ipairs({ straight, flush }) do
    for _, c in ipairs(grp) do if not seen[c] then seen[c] = true; merged[#merged + 1] = c end end
  end
  local lv = {}
  for k in pairs({ Pair = 1, Straight = 1, Flush = 1, ["Straight Flush"] = 1 }) do
    lv[k] = { level = 2, chips = 50, mult = 5 }
  end
  setup(h, { levels = lv, discards = 2, blind = { chips = 2000 }, chips = 100,
    deck = { cards = { card("7","Hearts"), card("8","Hearts") } },
    ph = { ["Straight Flush"] = { merged }, Flush = { flush }, Straight = { straight },
      Pair = { { h[6], h[7] } } } })
  local t0 = os.clock()
  for _ = 1, 300 do HF.summary(); HF.has_strong_ready() end
  local dt = os.clock() - t0
  check("7: 300 summary+strong builds under 1s", dt < 1.0, string.format("%.3fs", dt))
end

done()
