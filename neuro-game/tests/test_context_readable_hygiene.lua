_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")
local CR = require("context.context_readable")

local fails, total = 0, 0
local MAX_REPORT = 15
local function check(name, cond, detail)
  total = total + 1
  if not cond then
    fails = fails + 1
    if fails <= MAX_REPORT then
      print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
    end
  end
end

local RID = require("tests.helpers").RID
local VALN = require("tests.helpers").VALN
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local function card(v, suit, opts)
  opts = opts or {}
  local id = RID[v]
  return {
    base = { value = VALN[v] or v, suit = suit },
    debuff = opts.debuff or nil,
    config = { center = { key = "c_base", set = "Default" } },
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end

local ALL_LEVELS = {}
for _, n in ipairs({ "High Card","Pair","Two Pair","Three of a Kind","Straight","Flush",
    "Full House","Four of a Kind","Straight Flush","Five of a Kind","Flush House","Flush Five" }) do
  ALL_LEVELS[n] = { level = 2, chips = 35, mult = 4 }
end

local function setup(cards, opts)
  opts = opts or {}
  G.hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = {
    current_round = { discards_left = opts.discards or 2, hands_left = 4 },
    hands = opts.levels or ALL_LEVELS,
    blind = opts.blind,
    chips = opts.chips or 0,
  }
  G.jokers = opts.jokers
  G.deck = opts.deck
  G.FUNCS = { get_poker_hand_info = function()
    local ph = {}
    if opts.ph then for k, v in pairs(opts.ph) do ph[k] = v end end
    return nil, nil, ph
  end }
end

local HIDDEN_ROSTER_BANNED = {
  "^%(J[%dJ,]+ appl%a+%)$",
  "^%(J[%dJ,]+ [%+x][%d%.%+cmx ]*%)$",
}
local TOKEN_WHITELIST = {
  "^%(lv[%d%.]+ [%d%.e%+]+c x[%d%.e%+]+%)$",
  "^%(J[%dJ,]+ appl%a+%)$",
  "^%(J[%dJ,]+ [%+x][%d%.%+cmx ]*%)$",
  "^%(jokers: .+%)$",
  "^%(draw %d+/%d+=%d+%%%)$",
  "^%(%d+ debuffed~0%)$",
  "^%(all debuffed~0%)$",
  "^%(play %d+%+ cards%)$",
  "^%(open draw%)$",
  "^%(inside draw%)$",
  "^%(they score 0%)$",
  "^%(s%)$",
  "^%(Splash%)$",
  "^%(discard at most %d+%)$",
  "^%(This boss draws",
  "^%(%a[%a ]*%)$",
  "^%(jokers%-always: .+%)$",
}
local function scan_compact(label, s, hidden_roster)
  check(label .. ": there is a compact summary to scan", type(s) == "string" and s ~= "", tostring(s))
  local banned = {}
  if hidden_roster then
    for _, p in ipairs(HIDDEN_ROSTER_BANNED) do banned[p] = true end
  end
  for tok in s:gmatch("%b()") do
    local ok = false
    for _, p in ipairs(TOKEN_WHITELIST) do
      if not banned[p] and tok:find(p) then ok = true break end
    end
    check(label .. ": known token " .. tok, ok, s)
  end
end

local RAW_PATTERNS = {
  "%(~", "p>=R", "keep%[", "/other%[", "%(draw ", "%(lv", "%(J%d",
  "debuffed~0", "%(play %d+%+ cards%)", "%(open draw%)", "%(inside draw%)",
  "pairs>=2", "suit_max:", "run_max:", "%[%d",
}
local function scan_prose(label, s)
  local p = CR.structure_prose(s)
  check(label .. ": structure_prose returned text to scan", type(p) == "string" and p ~= "", tostring(p))
  for _, pat in ipairs(RAW_PATTERNS) do
    check(label .. ": no raw " .. pat, p:find(pat) == nil, p)
  end
end

local function scan_both(label, s, hidden_roster)
  scan_compact(label, s, hidden_roster)
  scan_prose(label, s)
end

do
  local kh, ks = card("K","Hearts"), card("K","Spades")
  setup({ kh, ks, card("2","Clubs"), card("7","Diamonds") }, {
    ph = { Pair = { { kh, ks } } },
    blind = { chips = 100 }, chips = 90,
    jokers = { cards = {
      { ability = { name="A", type="Pair", t_mult=3 }, config = { center = { key="j_a" } } },
      { ability = { name="B", type="Pair", t_chips=20 }, config = { center = { key="j_b" } } },
    }, config = { card_limit = 5 } },
  })
  scan_both("multi-joker", HF.summary())
end

do
  local kh = card("K","Hearts", { debuff = true })
  local ks = card("K","Spades")
  local h = { kh, ks, card("5","Hearts"), card("6","Diamonds"), card("7","Spades"),
              card("8","Clubs"), card("2","Clubs"), card("Q","Diamonds") }
  setup(h, { ph = { Pair = { { kh, ks } } },
    deck = { cards = { card("4","Hearts"), card("9","Clubs"), card("J","Spades") } } })
  scan_both("debuff+near-straight", HF.summary())
end

do
  local kh, ks = card("K","Hearts"), card("K","Spades")
  setup({ kh, ks, card("2","Clubs"), card("7","Diamonds"), card("9","Spades"), card("4","Hearts") }, {
    ph = { Pair = { { kh, ks } } },
    blind = { name = "The Psychic", debuff = { h_size_ge = 5 } },
  })
  scan_both("size floor", HF.summary())
end

do
  local h = { card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
              card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades") }
  setup(h, { deck = { cards = { card("6","Hearts"), card("J","Hearts"), card("Q","Spades") } },
    jokers = { cards = { { config = { center = { key = "j_splash" } }, ability = {} } },
      config = { card_limit = 5 } },
    blind = { name = "The House", chips = 300 } })
  scan_both("near flush+splash+facedown", HF.summary())
end

do
  local h = { card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
              card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades") }
  setup(h, { deck = { cards = { card("Q","Spades"), card("J","Clubs"), card("10","Diamonds") } } })
  local s = HF.summary()
  check("0-outs near flush: the four-card suit draw really was measured",
    s:find("suit_max:4", 1, true) ~= nil, s)
  check("0-outs near flush suppressed", s:find("near Flush") == nil, s)
end

do
  local h = { card("5","Hearts"), card("6","Diamonds"), card("7","Spades"), card("9","Clubs"),
              card("K","Hearts"), card("2","Clubs"), card("Q","Diamonds"), card("A","Spades") }
  setup(h, { deck = { cards = { card("4","Hearts"), card("J","Clubs"), card("3","Diamonds") } } })
  local s = HF.summary()
  check("0-outs inside straight: the three-card run really was measured",
    s:find("run_max:3", 1, true) ~= nil, s)
  check("0-outs inside straight suppressed", s:find("near Straight") == nil, s)
end

-- Amber Acorn (game-dump/blind.lua:222-231) turns the whole row face down and shuffles it, so a
-- slot number is an identity claim. Same board twice: face up the J-index token is the expected
-- shape, face down it is not a shape the scan accepts at all.
do
  local function pair_board(face_down)
    local kh, ks = card("K","Hearts"), card("K","Spades")
    local function jk(name, ab, key)
      ab.name = name
      return { ability = ab, config = { center = { key = key } },
        facing = face_down and "back" or "front" }
    end
    setup({ kh, ks, card("2","Clubs"), card("7","Diamonds") }, {
      ph = { Pair = { { kh, ks } } },
      blind = { chips = 100 }, chips = 90,
      jokers = { cards = {
        jk("A", { type="Pair", t_mult=3 }, "j_a"),
        jk("B", { type="Pair", t_chips=20 }, "j_b"),
        jk("C", { mult=4 }, "j_c"),
      }, config = { card_limit = 5 } },
    })
    return HF.summary()
  end

  local visible = pair_board(false)
  scan_both("multi-joker face-up", visible)
  check("multi-joker face-up: a J-index token is what the public roster produces",
    visible:find("(J", 1, true) ~= nil, visible)

  scan_both("multi-joker face-down", pair_board(true), true)
end

math.randomseed(777)
local RANKS = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" }
for it = 1, 250 do
  local n = 5 + (it % 4)
  local h = {}
  for i = 1, n do
    h[i] = card(RANKS[math.random(13)], SUITS[math.random(4)],
      { debuff = math.random(100) <= 15 or nil })
  end
  local dk = {}
  for i = 1, math.random(12) do
    dk[i] = card(RANKS[math.random(13)], SUITS[math.random(4)])
  end
  local jokers
  if it % 3 == 0 then
    jokers = { cards = {
      { ability = { name="J", mult = 4 }, config = { center = { key="j_j" } } },
      { ability = { name="C", type = ({"Pair","Flush","Straight","Two Pair"})[math.random(4)],
        t_mult = 3 }, config = { center = { key="j_c" } } },
    }, config = { card_limit = 5 } }
  end
  local by_rank, by_suit = {}, {}
  for _, c in ipairs(h) do
    local id = c.get_id()
    by_rank[id] = by_rank[id] or {}; table.insert(by_rank[id], c)
  end
  for _, s in ipairs(SUITS) do
    local t = {}
    for _, c in ipairs(h) do if c:is_suit(s) then t[#t+1] = c end end
    if #t >= 5 then by_suit[s] = t end
  end
  local ph = {}
  for _, g in pairs(by_rank) do if #g >= 2 then ph.Pair = { { g[1], g[2] } } break end end
  for _, t in pairs(by_suit) do ph.Flush = { t } break end
  setup(h, { ph = ph, deck = { cards = dk },
    blind = (it % 2 == 0) and { chips = 200 + it } or nil, chips = it,
    jokers = jokers })
  local ok, s = pcall(HF.summary)
  check("fuzz#" .. it .. " summary builds", ok, s)
  if ok then scan_both("fuzz#" .. it, s) end
end

print(string.format("==== readable-hygiene: %d/%d PASS, %d FAIL ====", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
