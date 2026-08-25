_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local HF = require("facts.hand_facts")

local fails, total = 0, 0
local MAX_REPORT = 12
local function check(name, cond, detail)
  total = total + 1
  if not cond then
    fails = fails + 1
    if fails <= MAX_REPORT then
      print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or ""))
    end
  end
end

local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local COLOR = { Hearts = "r", Diamonds = "r", Spades = "b", Clubs = "b" }

local function card(rid, suit, opts)
  opts = opts or {}
  local c = {
    rid = opts.stone and -1 or rid, suit = suit,
    debuff = opts.debuff or nil,
    edition = opts.edition,
    config = { center = { key = opts.stone and "m_stone" or (opts.enh or "c_base") } },
  }
  c.get_id = function(self) return self.rid end
  if opts.stone then
    c.is_suit = function() return false end
  elseif opts.wild then
    c.is_suit = function() return true end
  elseif opts.smeared then
    c.is_suit = function(self, s) return COLOR[self.suit] == COLOR[s] end
  else
    c.is_suit = function(self, s) return self.suit == s end
  end
  return c
end

local RANK_NAME = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
local function hand_str(cards)
  local t = {}
  for _, c in ipairs(cards) do
    local r = c.rid < 0 and "St" or (RANK_NAME[c.rid] or tostring(c.rid))
    t[#t + 1] = r .. c.suit:sub(1, 1) .. (c.debuff and "!" or "")
  end
  return table.concat(t, " ")
end

local function eng_flush(cards, thr)
  for _, s in ipairs(SUITS) do
    local t = {}
    for _, c in ipairs(cards) do if c:is_suit(s) then t[#t + 1] = c end end
    if #t >= thr then return t end
  end
  return nil
end

local function eng_straight(cards, thr, shortcut)
  local by = {}
  for _, c in ipairs(cards) do
    local id = c:get_id()
    if id and id >= 2 and id <= 14 then by[id] = by[id] or {}; table.insert(by[id], c) end
  end
  local present = {}
  for r in pairs(by) do present[r] = true end
  if by[14] then present[1] = true end
  local best
  for start = 1, 14 do
    if present[start] then
      local chain, r = { start }, start
      while r < 14 do
        if present[r + 1] then r = r + 1
        elseif shortcut and r + 2 <= 14 and present[r + 2] then r = r + 2
        else break end
        chain[#chain + 1] = r
      end
      if #chain >= thr and (not best or #chain > #best) then best = chain end
    end
  end
  if not best then return nil end
  local out = {}
  for _, r in ipairs(best) do
    local key = r
    if r == 1 then key = 14 end
    local grp = by[key]
    if grp then
      for _, c in ipairs(grp) do out[#out + 1] = c end
    end
  end
  return out
end

do
  local ok, jit = pcall(require, "jit")
  if ok and jit and jit.off then pcall(jit.off, eng_straight) end
end

local function eng_same(cards, num)
  local by = {}
  for _, c in ipairs(cards) do
    local id = c:get_id()
    if id and id >= 2 then by[id] = by[id] or {}; table.insert(by[id], c) end
  end
  local rids = {}
  for r, g in pairs(by) do if #g >= num then rids[#rids + 1] = r end end
  table.sort(rids, function(a, b) return a > b end)
  local groups = {}
  for _, r in ipairs(rids) do groups[#groups + 1] = by[r] end
  return groups
end

local function merge(...)
  local ret, seen = {}, {}
  for _, grp in ipairs({ ... }) do
    for _, v in ipairs(grp) do if not seen[v] then seen[v] = true; ret[#ret + 1] = v end end
  end
  return ret
end

local function eng_eval(cards, cfg)
  local _5 = eng_same(cards, 5)
  local _4 = eng_same(cards, 4)
  local _3 = eng_same(cards, 3)
  local _2 = eng_same(cards, 2)
  local fl = eng_flush(cards, cfg.fthr)
  local st = eng_straight(cards, cfg.sthr, cfg.shortcut)
  local all_pairs = {}
  for _, g in ipairs(_2) do all_pairs = merge(all_pairs, g) end
  local highest
  for _, c in ipairs(cards) do
    local id = c:get_id()
    if id and id >= 2 and (not highest or id > highest:get_id()) then highest = c end
  end
  local ph = {}
  local function put(name, grp) if grp and #grp > 0 then ph[name] = { grp } end end
  if #_5 > 0 and fl then put("Flush Five", merge(_5[1], fl)) end
  if #_3 >= 1 and #_2 >= 2 and fl then put("Flush House", merge(all_pairs, fl)) end
  if #_5 > 0 then put("Five of a Kind", _5[1]) end
  if st and fl then put("Straight Flush", merge(st, fl)) end
  if #_4 > 0 then put("Four of a Kind", _4[1]) end
  if #_3 >= 1 and #_2 >= 2 then put("Full House", all_pairs) end
  if fl then put("Flush", fl) end
  if st then put("Straight", st) end
  if #_3 > 0 then put("Three of a Kind", _3[1]) end
  if #_2 >= 2 then put("Two Pair", all_pairs) end
  if #_2 > 0 then put("Pair", _2[1]) end
  if highest then put("High Card", { highest }) end
  return ph
end

local function realizable_names(cards, cfg, cap)
  local names = {}
  local n = #cards
  local idx = {}
  local function rec(start, depth)
    if depth == 0 then return end
    for i = start, n do
      idx[#idx + 1] = i
      local sub = {}
      for _, j in ipairs(idx) do sub[#sub + 1] = cards[j] end
      for name in pairs(eng_eval(sub, cfg)) do names[name] = true end
      rec(i + 1, depth - 1)
      idx[#idx] = nil
    end
  end
  rec(1, cap)
  return names
end

local HAND_ORDER = {
  ["High Card"] = 1, ["Pair"] = 2, ["Two Pair"] = 3, ["Three of a Kind"] = 4,
  ["Straight"] = 5, ["Flush"] = 6, ["Full House"] = 7, ["Four of a Kind"] = 8,
  ["Straight Flush"] = 9, ["Five of a Kind"] = 10, ["Flush House"] = 11, ["Flush Five"] = 12,
}

local function set_mods(cfg)
  if cfg.fthr ~= 5 or cfg.sthr ~= 5 or cfg.shortcut then
    _G.SMODS = {
      four_fingers = function(kind) return (kind == "flush") and cfg.fthr or cfg.sthr end,
      shortcut = cfg.shortcut and function() return true end or nil,
    }
  else
    _G.SMODS = nil
  end
end

local function run_summary(cards, cfg)
  G.hand = { cards = cards, config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = 0, hands_left = 4 }, hands = {} }
  G.jokers = nil
  local ph = eng_eval(cards, cfg)
  G.FUNCS = { get_poker_hand_info = function() return nil, nil, ph end }
  return HF.summary()
end

local function parse_ready(s)
  local out = {}
  local seg = s:match("Ready: (.-)%.")
  if not seg then return out end
  for name, list in seg:gmatch("([%a][%a ]-)%[([%d,]+)%]") do
    local ix = {}
    for v in list:gmatch("%d+") do ix[#ix + 1] = tonumber(v) end
    out[#out + 1] = { name = name, ix = ix }
  end
  return out
end

math.randomseed(12345)
local function rnd(n) return math.random(n) end

local function gen(profile, opts)
  local n = opts.n or 8
  local cards = {}
  local pool, base_suit
  if profile == "dupes" then
    pool = { rnd(13) + 1, rnd(13) + 1, rnd(13) + 1 }
  elseif profile == "runny" or profile == "runsuit" then
    base_suit = SUITS[rnd(4)]
  end
  local run_base = rnd(9) + 1
  for _ = 1, n do
    local rid, suit
    if profile == "dupes" then
      rid = pool[rnd(#pool)]
      suit = SUITS[rnd(4)]
    elseif profile == "suited" then
      rid = rnd(13) + 1
      suit = (rnd(100) <= 65) and "Hearts" or SUITS[rnd(4)]
    elseif profile == "runny" then
      rid = math.min(14, run_base + rnd(6) - 1)
      suit = SUITS[rnd(4)]
    elseif profile == "runsuit" then
      rid = math.min(14, run_base + rnd(6) - 1)
      suit = (rnd(100) <= 70) and base_suit or SUITS[rnd(4)]
    else
      rid = rnd(13) + 1
      suit = SUITS[rnd(4)]
    end
    local o = {}
    if opts.wild_p and rnd(100) <= opts.wild_p then o.wild = true end
    if opts.stone_p and rnd(100) <= opts.stone_p then o.stone = true end
    if opts.debuff_p and rnd(100) <= opts.debuff_p then o.debuff = true end
    if opts.smeared then o.smeared = true end
    if opts.enh_p and rnd(100) <= opts.enh_p then
      local e = { "m_bonus", "m_mult", "m_gold", "m_steel", "m_lucky" }
      o.enh = e[rnd(#e)]
    end
    if opts.ed_p and rnd(100) <= opts.ed_p then
      o.edition = ({ { foil = true }, { holo = true }, { polychrome = true } })[rnd(3)]
    end
    cards[#cards + 1] = card(rid, suit, o)
  end
  return cards
end

local CFGS = {
  { name = "vanilla", fthr = 5, sthr = 5, shortcut = false },
  { name = "four_fingers", fthr = 4, sthr = 4, shortcut = false },
  { name = "shortcut", fthr = 5, sthr = 5, shortcut = true },
  { name = "ff+shortcut", fthr = 4, sthr = 4, shortcut = true },
}
local PROFILES = { "uniform", "suited", "dupes", "runny", "runsuit" }
local CAP = 5

local T1_ITERS = 300
for _, cfg in ipairs(CFGS) do
  set_mods(cfg)
  for _, profile in ipairs(PROFILES) do
    for it = 1, T1_ITERS do
      local hostile = (it % 4 == 0)
      local cards = gen(profile, {
        n = 5 + (it % 4),
        wild_p = 6, stone_p = hostile and 8 or 0, debuff_p = 18,
        enh_p = 15, ed_p = 10, smeared = (it % 7 == 0),
      })
      local s = run_summary(cards, cfg)
      local rows = parse_ready(s)
      check("t1 " .. cfg.name .. "/" .. profile .. "#" .. it .. ": <=4 rows", #rows <= 4, s)
      for _, row in ipairs(rows) do
        local label = "t1 " .. cfg.name .. "/" .. profile .. "#" .. it .. " " .. row.name
        local ok_ix, seen = true, {}
        for _, i in ipairs(row.ix) do
          if type(i) ~= "number" or i < 1 or i > #cards or seen[i] then ok_ix = false end
          seen[i] = true
        end
        check(label .. ": indices valid", ok_ix and #row.ix >= 1 and #row.ix <= CAP,
          hand_str(cards) .. " -> " .. s)
        if ok_ix then
          local sub = {}
          for _, i in ipairs(row.ix) do sub[#sub + 1] = cards[i] end
          check(label .. ": played set forms the claim", eng_eval(sub, cfg)[row.name] ~= nil,
            hand_str(cards) .. " ix=" .. table.concat(row.ix, ",") .. " -> " .. s)
        end
      end
    end
  end
end

local T2_ITERS = 150
for _, cfg in ipairs(CFGS) do
  set_mods(cfg)
  for _, profile in ipairs(PROFILES) do
    for it = 1, T2_ITERS do
      local cards = gen(profile, { n = 5 + (it % 4), wild_p = 5 })
      local s = run_summary(cards, cfg)
      local rows = parse_ready(s)
      local realizable = realizable_names(cards, cfg, CAP)
      local expected = {}
      for name in pairs(realizable) do
        if (HAND_ORDER[name] or 0) >= 2 then expected[#expected + 1] = name end
      end
      table.sort(expected, function(a, b) return HAND_ORDER[a] > HAND_ORDER[b] end)
      while #expected > 4 do table.remove(expected) end
      local got = {}
      for i, row in ipairs(rows) do got[i] = row.name end
      local function canon(t)
        local c = {}
        for i, v in ipairs(t) do c[i] = v end
        table.sort(c)
        return c
      end
      local got_c, expected_c = canon(got), canon(expected)
      check("t2 " .. cfg.name .. "/" .. profile .. "#" .. it .. ": same 4 hands as realizable top4 (order not asserted -- display order is randomized)",
        #got_c == #expected_c and table.concat(got_c, "|") == table.concat(expected_c, "|"),
        hand_str(cards) .. "  got={" .. table.concat(got, ",") .. "} want={"
          .. table.concat(expected, ",") .. "}  " .. (s:match("Ready:[^%.]*%.") or "(no Ready)"))
    end
  end
end

_G.SMODS = nil
print(string.format("==== hand-perfect: %d/%d PASS, %d FAIL ====", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
