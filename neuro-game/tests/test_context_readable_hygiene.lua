require("tests.stubs").setup({ love = "lazy", G = "hand" })

local HF = require("facts.hand_facts")
local CR = require("context.context_readable")

local check, done = require("tests.helpers").quiet_harness("readable-hygiene", 15)

local VALN = require("tests.helpers").VALN
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local function card(v, suit, opts)
  return require("tests.engine_cards").playing(VALN[v] or v, suit, { debuff = (opts or {}).debuff or nil })
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

local SLOT_CHAIN = {
  "^%(as the cards score: joker %d.*%)$",
  "^%(then jokers left to right: joker %d.*%)$",
}
local HIDDEN_ROSTER_BANNED = { "as the cards score: joker %d", "jokers left to right: joker %d" }
local TOKEN_WHITELIST = {
  "^%(cards [%d, ]+%)$",
  "^%(level [%d%.]+, [%d%.e%+]+ chips x[%d%.e%+]+ mult%)$",
  SLOT_CHAIN[1],
  SLOT_CHAIN[2],
  "^%(%d+ of the %d+ draw%-pile cards complete it; %d+%% chance to hit one[^()]*%)$",
  "^%(%d+ cards? debuffed, adding nothing%)$",
  "^%(all cards debuffed, adding nothing%)$",
  "^%(this boss needs %d+%+ cards played %- add spare cards%)$",
  "^%(completes on either end%)$",
  "^%(needs one exact rank%)$",
  "^%(they score 0%)$",
  "^%(s%)$",
  "^%(Splash%)$",
  "^%(you may discard at most %d+ of them%)$",
  "^%(This boss draws",
  "^%(%a[%a ]*%)$",
}

local RAW_PATTERNS = {
  "%(~", "p>=R", "keep%[", "/other%[", "%(draw ", "%(lv", "%(J%d",
  "debuffed~0", "%(play %d+%+ cards%)", "%(open draw%)", "%(inside draw%)",
  "pairs>=2", "suit_max:", "run_max:", "%[%d",
}
local function prose() return CR.structure_prose(HF.structure()) end

local function scan(label, hidden_roster)
  local p = prose()
  check(label .. ": structure_prose returned text to scan", type(p) == "string" and p ~= "", tostring(p))
  for _, pat in ipairs(RAW_PATTERNS) do
    check(label .. ": no raw " .. pat, p:find(pat) == nil, p)
  end
  for tok in p:gmatch("%b()") do
    local ok = false
    for _, pat in ipairs(TOKEN_WHITELIST) do
      if not (hidden_roster and (pat == SLOT_CHAIN[1] or pat == SLOT_CHAIN[2])) and tok:find(pat) then ok = true break end
    end
    check(label .. ": known token " .. tok, ok, p)
  end
  if hidden_roster then
    for _, pat in ipairs(HIDDEN_ROSTER_BANNED) do
      check(label .. ": no slot chain " .. pat, p:find(pat) == nil, p)
    end
  end
  return p
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
  scan("multi-joker")
end

do
  local kh = card("K","Hearts", { debuff = true })
  local ks = card("K","Spades")
  local h = { kh, ks, card("5","Hearts"), card("6","Diamonds"), card("7","Spades"),
              card("8","Clubs"), card("2","Clubs"), card("Q","Diamonds") }
  setup(h, { ph = { Pair = { { kh, ks } } },
    deck = { cards = { card("4","Hearts"), card("9","Clubs"), card("J","Spades") } } })
  scan("debuff+near-straight")
end

do
  local kh, ks = card("K","Hearts"), card("K","Spades")
  setup({ kh, ks, card("2","Clubs"), card("7","Diamonds"), card("9","Spades"), card("4","Hearts") }, {
    ph = { Pair = { { kh, ks } } },
    blind = { name = "The Psychic", debuff = { h_size_ge = 5 } },
  })
  scan("size floor")
end

do
  local h = { card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
              card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades") }
  setup(h, { deck = { cards = { card("6","Hearts"), card("J","Hearts"), card("Q","Spades") } },
    jokers = { cards = { { config = { center = { key = "j_splash" } }, ability = {} } },
      config = { card_limit = 5 } },
    blind = { name = "The House", chips = 300 } })
  scan("near flush+splash+facedown")
end

do
  local h = { card("2","Hearts"), card("5","Hearts"), card("8","Hearts"), card("K","Hearts"),
              card("3","Spades"), card("7","Clubs"), card("9","Diamonds"), card("4","Spades") }
  setup(h, { deck = { cards = { card("Q","Spades"), card("J","Clubs"), card("10","Diamonds") } } })
  local s = prose()
  check("0-outs near flush: the four-card suit draw really was measured",
    s:find("most cards of one suit 4;", 1, true) ~= nil, s)
  check("0-outs near flush suppressed", s:find("Flush: %d") == nil, s)
end

do
  local h = { card("5","Hearts"), card("6","Diamonds"), card("7","Spades"), card("9","Clubs"),
              card("K","Hearts"), card("2","Clubs"), card("Q","Diamonds"), card("A","Spades") }
  setup(h, { deck = { cards = { card("4","Hearts"), card("J","Clubs"), card("3","Diamonds") } } })
  local s = prose()
  check("0-outs inside straight: the three-card run really was measured",
    s:find("longest run 3.", 1, true) ~= nil, s)
  check("0-outs inside straight suppressed", (s:match("One card away: [^\n]*") or ""):find("Straight", 1, true) == nil, s)
end

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
  end

  pair_board(false)
  local visible = scan("multi-joker face-up")
  check("multi-joker face-up: a slot chain is what the public roster produces",
    visible:find("jokers left to right: joker 1 ", 1, true) ~= nil, visible)

  pair_board(true)
  scan("multi-joker face-down", true)
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
    local id = c:get_id()
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
  local ok, s = pcall(prose)
  check("fuzz#" .. it .. " prose builds", ok, s)
  if ok then scan("fuzz#" .. it) end
end

done()
