local LABEL = "item-context-fuzz"
local LOST_IF_SKIPPED = 11
local skip = require("tests.skip_ledger")
local DUMP = os.getenv("BALATRO_DUMP")
if not DUMP or DUMP == "" then skip.bail(LABEL, LOST_IF_SKIPPED, "BALATRO_DUMP is unset") end

require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })
local H = require("tests.helpers")
local EU = require("tests.engine_ui").load(LABEL, LOST_IF_SKIPPED)
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local DecisionDelta = require("facts.decision_delta")
local json = require("util.neuro_json")
local check, done = H.harness(LABEL)

EU.install(G)
local CENTERS = EU.install_centers(G.P_CENTERS)
local P_SEALS = EU.install_seals(EU.proto("P_SEALS"))
local P_TAGS = EU.proto("P_TAGS")
local P_BLINDS = EU.proto("P_BLINDS")
local P_STAKES = EU.proto("P_STAKES")
local HANDS = assert((loadstring or load)("return " .. EU.src.game:match("\n%s*hands = (%b{})")))()

local seed = 20261007
local function rnd(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  if n then return math.floor(seed / 65536) % n + 1 end
  return (math.floor(seed / 65536) % 10000) / 10000
end
local function pick(list) return list[rnd(#list)] end

local function sorted_keys(t, pred)
  local out = {}
  for k, v in pairs(t) do if not pred or pred(k, v) then out[#out + 1] = k end end
  table.sort(out)
  return out
end
local function by_order(set)
  local keys = sorted_keys(CENTERS, function(_, c) return type(c) == "table" and c.set == set end)
  table.sort(keys, function(a, b)
    local oa, ob = CENTERS[a].order or 0, CENTERS[b].order or 0
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  return keys
end

local KEYS = {
  joker = by_order("Joker"), tarot = by_order("Tarot"), planet = by_order("Planet"),
  spectral = by_order("Spectral"), voucher = by_order("Voucher"), booster = by_order("Booster"),
  enhancement = by_order("Enhanced"), edition = by_order("Edition"), back = by_order("Back"),
  tag = sorted_keys(P_TAGS), seal = { "Red", "Blue", "Gold", "Purple" },
  sticker = { "eternal", "perishable", "rental" },
  blind = sorted_keys(P_BLINDS), stake = sorted_keys(P_STAKES),
}
KEYS.consumable = {}
for _, k in ipairs({ "tarot", "planet", "spectral" }) do
  for _, key in ipairs(KEYS[k]) do KEYS.consumable[#KEYS.consumable + 1] = key end
end
local KIND_OF_SET = { Joker = "joker", Tarot = "tarot", Planet = "planet", Spectral = "spectral",
  Voucher = "voucher", Booster = "booster" }

local function squash(s) return (tostring(s or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

local function gt_clean(s)
  s = tostring(s or "")
  s = s:gsub("#@%w+", "")
  s = s:gsub("rand%(%)", "")
  s = s:gsub("(%-?%d+)|[%d|]*|(%-?%d+)", "%1 to %2")
  s = s:gsub("|", " ")
  return squash(s)
end

local WORD_NUMBERS = { one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8,
  nine = 9, ten = 10, single = 1, once = 1, twice = 2, first = 1, double = 2 }
local function numbers(s)
  local out = {}
  s = tostring(s or ""):gsub("(%d),(%d%d%d)", "%1%2")
  for n in s:gmatch("%d+%.?%d*") do
    local v = tonumber((n:gsub("%.$", "")))
    if v then out[#out + 1] = v end
  end
  for w in s:lower():gmatch("%a+") do
    if WORD_NUMBERS[w] then out[#out + 1] = WORD_NUMBERS[w] end
  end
  return out
end

local function digits(s)
  local out = {}
  s = tostring(s or ""):gsub("(%d),(%d%d%d)", "%1%2")
  for n in s:gmatch("%d+%.?%d*") do
    local v = tonumber((n:gsub("%.$", "")))
    if v then out[#out + 1] = v end
  end
  return out
end

local function has_number(list, v)
  for _, x in ipairs(list) do if math.abs(x - v) < 1e-9 then return true end end
  return false
end

local function missing_numbers(gt_text, model, excused)
  local have, miss, seen = numbers(model), {}, {}
  for _, v in ipairs(digits(gt_text)) do
    if not has_number(have, v) and not seen[v] and not (excused and excused(v)) then
      seen[v] = true
      miss[#miss + 1] = tostring(v)
    end
  end
  return miss
end

local function lower_words(s)
  local out = {}
  for w in tostring(s or ""):lower():gmatch("%a+") do if #w >= 3 then out[w] = true end end
  return out
end

local function tooltip(card)
  return EU.tooltip(card:generate_UIBox_ability_table())
end
local function info_text(tt)
  local parts = {}
  for _, b in ipairs(tt.info) do
    parts[#parts + 1] = tostring(b.name) .. ": " .. table.concat(b.rows, " ")
  end
  return table.concat(parts, " | ")
end

local FAILS = {}
local COUNTS = {}
local function fail(inv, e, quote, expected, where)
  FAILS[#FAILS + 1] = { inv = inv, kind = e.kind, key = e.key, surface = e.surface, state = e.state,
    quote = quote, expected = expected, where = where }
end

local CORPUS_DIR = os.getenv("FUZZ_CORPUS_DIR")
local CORPUS = {}
local COVER = {}
local function cover(kind, key, surface, state)
  COVER[kind] = COVER[kind] or { keys = {}, surfaces = {}, states = {} }
  local c = COVER[kind]
  c.keys[key] = true
  c.surfaces[surface] = true
  c.states[key .. "|" .. surface .. "|" .. state] = true
end

local ENTRIES = {}
local function ability_snapshot(card)
  if type(card) ~= "table" or type(card.ability) ~= "table" then return {} end
  local out = {}
  for k, v in pairs(card.ability) do
    local t = type(v)
    if (t == "number" and v ~= 0) or t == "string" or t == "boolean" then out[k] = v end
  end
  if type(card.ability.extra) == "table" then
    out.extra = {}
    for k, v in pairs(card.ability.extra) do
      if type(v) ~= "table" and type(v) ~= "function" then out.extra[k] = v end
    end
  end
  out.consumeable, out.debuff_sources, out.set = nil, nil, nil
  if card.edition then out.edition = card.edition.key end
  if card.seal then out.seal = card.seal end
  if card.debuff then out.debuffed = true end
  if card.facing == "back" then out.face_down = true end
  return out
end

local function record(e)
  ENTRIES[#ENTRIES + 1] = e
  cover(e.kind, e.key, e.surface, e.state)
  if CORPUS_DIR then
    CORPUS[e.kind] = CORPUS[e.kind] or {}
    local line = json.encode({ kind = e.kind, key = e.key, name = e.name or "", surface = e.surface,
      state = e.state, ability = e.ability or {}, ground_truth_text = e.gt or "",
      ground_truth_info = e.gt_info or "", model_text = e.model or "" })
    table.insert(CORPUS[e.kind], line)
  end
end

local HYGIENE = {
  { "#%d+#", "unresolved #n# placeholder" },
  { "{%a+:", "unresolved {X:...} markup" },
  { "%f[%w]nil%f[%W]", "nil" },
  { "%f[%w]None%f[%W]", "None" },
  { "%f[%w][Nn]a[Nn]%f[%W]", "NaN" },
  { "%f[%w]%-?inf%f[%W]", "inf" },
  { "table: 0x", "table address" },
  { "%f[%w]ERROR%f[%W]", "ERROR" },
  { "  ", "doubled space" },
  { "%.%.", "doubled period" },
  { ",,", "doubled comma" },
  { "%s[,%.;:]", "space before punctuation" },
  { "[,;:][,;:%.]", "doubled punctuation" },
  { "[%?!]%.", "period after ? or !" },
  { "%( ", "space after (" },
  { " %)", "space before )" },
  { "%l%u%l", "run-together words", allow = "%f[%w]x%u" },
}
local RAW_KEY = "%f[%w_]([jcvmeb]l?_[%l%d_]+)"
local RAW_TAG = "%f[%w_](tag_[%l%d_]+)"
local RAW_STAKE = "%f[%w_](stake_[%l%d_]+)"

local function hygiene(e, text)
  for _, h in ipairs(HYGIENE) do
    local from = 1
    while true do
      local at = text:find(h[1], from)
      if not at then break end
      local ok = h.allow and text:find(h.allow, math.max(1, at - 1)) == at
      if not ok then
        fail("hygiene: " .. h[2], e, text:sub(math.max(1, at - 40), at + 40), "no " .. h[2])
        break
      end
      from = at + 1
    end
  end
  local function raw(pat)
    for key in text:gmatch(pat) do
      local before = text:find("key " .. key, 1, true)
      local known = CENTERS[key] or P_TAGS[key] or P_BLINDS[key] or P_STAKES[key]
      if known and not before then fail("hygiene: raw key", e, key, "the item's name, not its key") end
    end
  end
  raw(RAW_KEY); raw(RAW_TAG); raw(RAW_STAKE)
  for at, word in text:gmatch("()%f[%w_]([%a]+_[%a_]+)") do
    local quoted = text:sub(at - 1, at - 1) == '"'
    local keyed = text:sub(math.max(1, at - 4), at - 1) == "key "
    if not quoted and not keyed and not (CENTERS[word] or P_TAGS[word] or P_BLINDS[word] or P_STAKES[word]) then
      fail("hygiene: internal identifier", e, text:sub(math.max(1, at - 40), at + #word + 20), "prose, not " .. word)
    end
  end
end

local function count_plain(hay, needle)
  local n, from = 0, 1
  while true do
    local at = hay:find(needle, from, true)
    if not at then return n end
    n, from = n + 1, at + 1
  end
end

local HAND_NAMES = {}
for name in pairs(HANDS) do HAND_NAMES[name:lower()] = true end
local function duplicates(e, model, rows)
  local m = model:lower():gsub("%b[]", "")
  local cut = m:find(". owning ", 1, true)
  if cut then m = m:sub(1, cut) end
  local gt = squash(table.concat(rows, " ")):lower()
  for _, row in ipairs(rows) do
    local r = squash(gt_clean(row)):lower():gsub("[%.,;:]+$", "")
    local nwords = select(2, r:gsub("%S+", ""))
    if nwords >= 3 and not HAND_NAMES[r] and count_plain(m, r) > count_plain(gt, r) then
      fail("duplicated text", e, r, "each clause once, as the game prints it")
      return
    end
  end
end

local CONTINUES = {}
for w in ("a an the and or to of for each every with by when if per give gives gain gains earn earns cost costs"
  .. " up at in on is are be from into than all any your this that other current owned random played scoring"
  .. " selected held discarded destroyed most first last next same one two free"):gmatch("%S+") do CONTINUES[w] = true end
local TERMS = {}
for w in ("Joker Jokers Tarot Tarots Planet Planets Spectral Booster Boosters Blind Blinds Boss Mult Chips"
  .. " Ace Aces King Kings Queen Queens Jack Jacks Club Clubs Spade Spades Heart Hearts Diamond Diamonds"
  .. " Steel Stone Glass Gold Lucky Wild Bonus Enhanced Foil Holographic Polychrome Negative Celestial"
  .. " Arcana Standard Buffoon Legendary Rare Uncommon Common Straight Straights Flush Flushes Pair Two"
  .. " Three Four Five Full High Double Seal Seals Red Blue Purple Tag Tags Small Big Packs Pack Hand Hands"
  .. " Reroll Rerolls Voucher Vouchers Card Cards Ante Antes Kind Discard Discards Interest House"
  .. " Hierophant Lovers Chariot Justice Hermit Wheel Fortune Strength Hanged Death Temperance Devil"
  .. " Tower Star Moon Sun Judgement World Fool Magician Priestess Empress Emperor Soul Black Hole"
  .. " Telescope Crystal Ball Overstock Merchant Tycoon Planet Seed Money Clearance Sale Liquidation"
  .. " Investment Juggle Handy Garbage Orbital Economy Coupon Charm Meteor Ethereal Uncommon"
  .. " Top Skip D6 Edition Editions Shop Shops Round Rounds Score Poker Mr Mega Jumbo"):gmatch("%S+") do TERMS[w] = true end

local function runons(e, rows, model)
  for i = 1, #rows - 1 do
    local last = rows[i]:match("(%a+)%s*$")
    local first = rows[i + 1]:match("^%s*(%u%a*)")
    if last and first and not rows[i]:find("[%.,;:!%?%(%)]%s*$") and not CONTINUES[last:lower()]
        and not TERMS[first] then
      local joined = last .. " " .. first
      if model:find(joined, 1, true) then
        fail("run-on join", e, joined, rows[i] .. " / " .. rows[i + 1] .. " (separate rows in the game)")
      end
    end
  end
end

local function check_row(e)
  local model = e.model or ""
  if model == "" then
    fail("not rendered", e, "(no row)", "a row naming " .. tostring(e.name))
    return
  end
  if e.name and e.name ~= "" and not model:find(squash(e.name), 1, true) then
    fail("item not named", e, model, squash(e.name))
  end
  hygiene(e, model)
  if e.gt and e.gt ~= "" and not e.no_numbers then
    local miss = missing_numbers(e.gt, model, e.excused)
    if #miss > 0 then
      fail("number missing or wrong", e, model, table.concat(miss, ", ") .. " from: " .. e.gt)
    end
  end
  if e.rows then runons(e, e.rows, model) end
  local main = e.card and e.tt and e.tt.main
  if main then duplicates(e, model, main) end
end

local POKER_HANDS = {}
for name, h in pairs(HANDS) do POKER_HANDS[#POKER_HANDS + 1] = name end
table.sort(POKER_HANDS, function(a, b) return HANDS[a].order < HANDS[b].order end)
local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function game_context(opts)
  opts = opts or {}
  local g = G.GAME
  g.probabilities = { normal = opts.oops and 2 or 1 }
  g.dollars = opts.dollars or (rnd(60) - 1)
  g.skips = rnd(6) - 1
  g.hands_played = rnd(30) - 1
  g.unused_discards = rnd(10) - 1
  g.consumeable_usage_total = { tarot = rnd(8) - 1, planet = rnd(8) - 1 }
  g.consumeable_usage = {}
  for i = 1, rnd(4) - 1 do g.consumeable_usage[KEYS.planet[i]] = { count = 1, set = "Planet" } end
  g.rental_rate, g.perishable_rounds = 3, 5
  g.modifiers = g.modifiers or {}
  g.round_resets = g.round_resets or {}
  g.round_resets.ante = g.round_resets.ante or 1
  g.ecto_minus = 1
  g.last_tarot_planet = (rnd(3) > 1) and pick({ "c_jupiter", "c_hermit", "c_pluto", "c_strength" }) or nil
  local cr = g.current_round or {}
  g.current_round = cr
  cr.idol_card = { rank = pick(RANKS), suit = pick(SUITS) }
  cr.mail_card = { rank = pick(RANKS) }
  cr.ancient_card = { suit = pick(SUITS) }
  cr.castle_card = { suit = pick(SUITS) }
  cr.most_played_poker_hand = pick(POKER_HANDS)
  g.hands = {}
  for name, h in pairs(HANDS) do
    local hh = copy(h)
    hh.example = nil
    if hh.visible then
      hh.level = rnd(5)
      hh.played = rnd(6) - 1
    end
    hh.chips = hh.s_chips + (hh.level - 1) * hh.l_chips
    hh.mult = hh.s_mult + (hh.level - 1) * hh.l_mult
    g.hands[name] = hh
  end
  g.starting_deck_size = (G.playing_cards and #G.playing_cards or 52) + rnd(9) - 1
end

local function install_tables()
  EU.install(G)
  G.P_CENTERS, G.P_SEALS, G.P_TAGS, G.P_BLINDS, G.P_STAKES = CENTERS, P_SEALS, P_TAGS, P_BLINDS, P_STAKES
  G.P_CENTER_POOLS = G.P_CENTER_POOLS or {}
  G.P_CENTER_POOLS.Back = G.P_CENTER_POOLS.Back or {}
  G.P_CENTER_POOLS.Stake = {}
  for _, k in ipairs(KEYS.stake) do G.P_CENTER_POOLS.Stake[P_STAKES[k].order] = P_STAKES[k] end
  G.P_CENTER_POOLS.Tag = {}
  for _, k in ipairs(KEYS.tag) do G.P_CENTER_POOLS.Tag[#G.P_CENTER_POOLS.Tag + 1] = P_TAGS[k] end
end

local function prep(state, desc, opts)
  LB.load(state, desc)
  install_tables()
  if G.jokers then G.jokers.config.negative_info = "joker" end
  if G.consumeables then G.consumeables.config.negative_info = "consumable" end
  if G.hand then G.hand.config = G.hand.config or {}; G.hand.config.negative_info = "playing_card" end
  local bp = G.pack_cards or G.booster_pack
  if bp then bp.config = bp.config or {}; bp.config.negative_info = true end
  game_context(opts)
  local b = G.GAME.blind
  if type(b) == "table" and not b.get_type then
    b.get_type = function(self) return self.boss and "Boss" or "Small" end
  end
end

local function area_of(name)
  if name == "pack" then return G.pack_cards or G.booster_pack end
  if name == "shop_vouchers" and not G.shop_vouchers then G.shop_vouchers = { cards = {}, config = {} } end
  return G[name]
end

local function place(area_name, cards, limit)
  local area = area_of(area_name)
  area.cards = cards
  area.config = area.config or {}
  if limit then area.config.card_limit = math.max(limit, #cards) end
  for _, c in ipairs(cards) do c.area = area end
end

local function refresh_all()
  for _, name in ipairs({ "jokers", "consumeables", "shop_jokers", "shop_vouchers", "shop_booster", "pack_cards",
      "booster_pack", "hand" }) do
    local area = G[name]
    for _, c in ipairs(area and area.cards or {}) do
      if getmetatable(c) == EU.Card then
        EU.refresh(c)
        if c.ability.blueprint_compat then
          c.ability.blueprint_compat_ui = " " .. EU.localize("k_" .. c.ability.blueprint_compat) .. " "
        end
      end
    end
  end
end

local function build(state)
  refresh_all()
  local ok, payload = pcall(FP.build, state)
  if not ok then return nil, tostring(payload) end
  return payload and payload.message or nil
end

local function section(message, prefix)
  local out, inside = {}, false
  for line in (message .. "\n"):gmatch("(.-)\n") do
    local h = line:match("^## (.+)$")
    if h then
      inside = h:sub(1, #prefix) == prefix
    elseif inside then
      out[#out + 1] = line
    end
  end
  return out
end

local function numbered_row(message, prefix, index)
  for _, line in ipairs(section(message, prefix)) do
    local n, rest = line:match("^(%d+)%. (.*)$")
    if tonumber(n) == index then return line end
  end
  return nil
end

local function line_with(message, needle)
  for line in (message .. "\n"):gmatch("(.-)\n") do
    if line:find(needle, 1, true) then return line end
  end
  return nil
end

local function list_part(message, label, name)
  local line = line_with(message, label)
  if not line then return nil end
  local body = line:sub((line:find(label, 1, true)) + #label)
  local depth, start = 0, 1
  local parts = {}
  for i = 1, #body do
    local ch = body:sub(i, i)
    if ch == "(" then depth = depth + 1 elseif ch == ")" then depth = depth - 1 end
    if ch == ";" and depth == 0 then parts[#parts + 1] = body:sub(start, i - 1); start = i + 1 end
  end
  parts[#parts + 1] = body:sub(start)
  for _, p in ipairs(parts) do
    p = squash(p):gsub("%.$", "")
    if p:sub(1, #name) == name then return p end
  end
  return nil
end

local EDITIONS = {
  { key = "e_foil", type = "foil", foil = true, chips = 50 },
  { key = "e_holo", type = "holo", holo = true, mult = 10 },
  { key = "e_polychrome", type = "polychrome", polychrome = true, x_mult = 1.5 },
  { key = "e_negative", type = "negative", negative = true, card_limit = 1 },
}
local function edition(key)
  for _, e in ipairs(EDITIONS) do if e.key == key then return copy(e) end end
end

local SCALE = {
  j_ceremonial = function(a) a.mult = 2 * rnd(12) end,
  j_green_joker = function(a) a.mult = rnd(20) - 1 end,
  j_ride_the_bus = function(a) a.mult = rnd(15) - 1 end,
  j_red_card = function(a) a.mult = 3 * (rnd(8) - 1) end,
  j_flash = function(a) a.mult = 2 * (rnd(10) - 1) end,
  j_trousers = function(a) a.mult = 2 * (rnd(8) - 1) end,
  j_fortune_teller = function() end,
  j_runner = function(a) a.extra.chips = 15 * (rnd(8) - 1) end,
  j_ice_cream = function(a) a.extra.chips = 100 - 5 * (rnd(15) - 1) end,
  j_square = function(a) a.extra.chips = 4 * (rnd(10) - 1) end,
  j_wee = function(a) a.extra.chips = 8 * (rnd(10) - 1) end,
  j_castle = function(a) a.extra.chips = 3 * (rnd(20) - 1) end,
  j_constellation = function(a) a.x_mult = 1 + 0.1 * (rnd(15) - 1) end,
  j_hologram = function(a) a.x_mult = 1 + 0.25 * (rnd(10) - 1) end,
  j_vampire = function(a) a.x_mult = 1 + 0.1 * (rnd(15) - 1) end,
  j_obelisk = function(a) a.x_mult = 1 + 0.2 * (rnd(10) - 1) end,
  j_lucky_cat = function(a) a.x_mult = 1 + 0.25 * (rnd(10) - 1) end,
  j_campfire = function(a) a.x_mult = 1 + 0.25 * (rnd(8) - 1) end,
  j_glass = function(a) a.x_mult = 1 + 0.75 * (rnd(5) - 1) end,
  j_hit_the_road = function(a) a.x_mult = 1 + 0.5 * (rnd(6) - 1) end,
  j_madness = function(a) a.x_mult = 1 + 0.5 * (rnd(6) - 1) end,
  j_caino = function(a) a.caino_xmult = rnd(4) end,
  j_yorick = function(a) a.yorick_discards = rnd(23); a.x_mult = rnd(3) end,
  j_ramen = function(a) a.x_mult = 2 - 0.01 * (rnd(60) - 1) end,
  j_popcorn = function(a) a.mult = 20 - 4 * (rnd(5) - 1) end,
  j_turtle_bean = function(a) a.extra.h_size = 5 - (rnd(5) - 1) end,
  j_selzer = function(a) a.extra = rnd(10) end,
  j_loyalty_card = function(a) a.loyalty_remaining = rnd(6) - 1 end,
  j_invisible = function(a) a.invis_rounds = rnd(3) - 1 end,
  j_rocket = function(a) a.extra.dollars = 1 + 2 * (rnd(5) - 1) end,
  j_todo_list = function(a) a.to_do_poker_hand = pick(POKER_HANDS) end,
  j_mystic_summit = function() end,
  j_egg = function(_, card) card.ability.extra_value = 3 * (rnd(5) - 1); card.sell_cost = card.sell_cost + card.ability.extra_value end,
}

local function sticker_state(card, owned)
  local c = card.config.center
  local s = rnd(5)
  if s == 2 and c.eternal_compat ~= false then card.ability.eternal = true end
  if s == 3 and c.perishable_compat ~= false then
    card.ability.perishable = true
    card.ability.perish_tally = owned and (rnd(6) - 1) or G.GAME.perishable_rounds
  end
  if s == 4 then card.ability.rental = true end
end

local function state_summary(card, base)
  local parts = { base }
  if card.edition then parts[#parts + 1] = card.edition.type end
  for _, k in ipairs({ "eternal", "perishable", "rental" }) do
    if card.ability[k] then parts[#parts + 1] = k .. (k == "perishable" and ("=" .. card.ability.perish_tally) or "") end
  end
  if card.debuff then parts[#parts + 1] = "debuffed" end
  if card.facing == "back" then parts[#parts + 1] = "face-down" end
  if G.GAME.probabilities.normal ~= 1 then parts[#parts + 1] = "probabilities x" .. G.GAME.probabilities.normal end
  return table.concat(parts, ",")
end

local SORT = 5000
local function new_card(key)
  SORT = SORT + 1
  return EU.card(key, { sort_id = SORT })
end

local function scaled_joker(key)
  local card = new_card(key)
  if SCALE[key] then SCALE[key](card.ability, card) end
  return card
end

local function entry_for(kind, card, surface, state, model)
  local tt = tooltip(card)
  local main = gt_clean(table.concat(tt.main, " "))
  return {
    kind = kind, key = card.config.center.key, name = squash(tt.name), surface = surface, state = state,
    ability = ability_snapshot(card), gt = main, gt_info = info_text(tt), rows = tt.main,
    tt = tt, card = card, model = model and squash(model) or nil,
  }
end

local function check_modifiers(e)
  local card, model = e.card, e.model or ""
  if card.edition and card.facing ~= "back" then
    local label = ({ foil = "Foil", holo = "Holographic", polychrome = "Polychrome", negative = "Negative" })[card.edition.type]
    if e.kind ~= "edition" and not model:find(label, 1, true) then fail("edition not shown", e, model, label) end
    for _, b in ipairs(e.tt.info) do
      if squash(b.name) == label then
        local text = gt_clean(table.concat(b.rows, " "))
        local miss = missing_numbers(text, model)
        if #miss > 0 then fail("edition value missing", e, model, table.concat(miss, ", ") .. " from: " .. text) end
        -- Edition text can describe area slots generically; it does not always mean Joker slots.
        local lm = model:lower()
        for w in text:lower():gmatch("%a+") do
          if #w >= 4 and w ~= "area" and not lm:find(w, 1, true) then
            fail("edition effect wrong", e, model, label .. ": " .. text)
            break
          end
        end
      end
    end
  end
  if card.ability.eternal and not (model:lower():find("eternal", 1, true) or model:find("cannot be sold", 1, true)) then
    fail("sticker not shown", e, model, "eternal")
  end
  if card.ability.perishable then
    local m, tally = model:lower(), card.ability.perish_tally
    -- At zero, Card:calculate_perishable debuffs the card instead of showing its count.
    local said = has_number(numbers(model), tally)
      or (tally == 0 and m:find("debuffed now", 1, true)) or (tally == 1 and m:find("debuffs at end of round", 1, true))
    if not m:find("perish", 1, true) then fail("sticker not shown", e, model, "perishable")
    elseif not said then
      fail("sticker value missing", e, model, "perishable rounds remaining " .. tally)
    end
  end
  if card.ability.rental then
    if not model:lower():find("rental", 1, true) then fail("sticker not shown", e, model, "rental")
    elseif not has_number(numbers(model), G.GAME.rental_rate) then
      fail("sticker value missing", e, model, "rental $" .. G.GAME.rental_rate .. " per round")
    end
  end
  if card.debuff and not model:lower():find("debuff", 1, true) then
    fail("debuff not shown", e, model, "debuffed (the game shows: " .. e.gt .. ")")
  end
end

local function check_card_entry(e)
  if e.card.debuff then
    -- Debuffed cards replace their normal text with “All abilities are disabled”.
    e.no_numbers = true
  end
  if e.card.base and e.card.base.value then
    -- The displayed rank chips include both the enhancement and permanent bonus.
    local a, nominal = e.card.ability, e.card.base.nominal
    local model_nums = numbers(e.model)
    e.excused = function(v)
      if v == nominal then return true end
      local bonus, perma = a.bonus or 0, a.perma_bonus or 0
      return perma ~= 0 and v == bonus + perma and has_number(model_nums, perma)
        and (bonus == 0 or has_number(model_nums, bonus))
    end
  end
  check_row(e)
  check_modifiers(e)
  record(e)
end

local function sticker_entries(e)
  local card = e.card
  for _, k in ipairs(KEYS.sticker) do
    if card.ability[k] then
      local gt = ""
      for _, b in ipairs(e.tt.info) do
        if squash(b.name):lower() == k then gt = gt_clean(table.concat(b.rows, " ")) end
      end
      record({ kind = "sticker", key = k, name = k, surface = e.surface, state = e.state .. " on " .. e.key,
        ability = e.ability, gt = gt, model = e.model })
    end
  end
  if card.edition then
    local gt = ""
    for _, b in ipairs(e.tt.info) do
      if b.name and not b.name:find("Eternal") and not b.name:find("Perishable") and not b.name:find("Rental") then
        gt = gt .. gt_clean(table.concat(b.rows, " ")) .. " "
      end
    end
    record({ kind = "edition", key = card.edition.key, name = card.edition.type, surface = e.surface,
      state = e.state .. " on " .. e.key, ability = e.ability, gt = squash(gt), model = e.model })
  end
end

local BOARD = {
  shop = { "SHOP", "Normal: affordable joker, affordable booster, $10" },
  hand = { "SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards" },
  pack = { "SMODS_BOOSTER_OPENED", "Has pack cards" },
  blind = { "BLIND_SELECT", "Small blind selectable" },
  setup = { "RUN_SETUP", "Run setup overlay active" },
}

local BUILD_ERRORS = {}
local function board_message(board, label)
  local msg, err = build(BOARD[board][1])
  if not msg then
    BUILD_ERRORS[#BUILD_ERRORS + 1] = label .. ": " .. tostring(err)
    return nil
  end
  local want = os.getenv("FUZZ_DUMP")
  if want and want ~= "" and label:find(want, 1, true) then print("===== " .. label .. "\n" .. msg) end
  return msg
end

local function chunks(list, n)
  local out = {}
  for i = 1, #list, n do
    local c = {}
    for j = i, math.min(i + n - 1, #list) do c[#c + 1] = list[j] end
    out[#out + 1] = c
  end
  return out
end

local OWNED_PREFIX = { joker = "Your jokers", consumable = "Consumables" }

local function run_shop(keys, state_name, dress)
  for _, batch in ipairs(chunks(keys, 3)) do
    local oops = rnd(4) == 1
    prep(BOARD.shop[1], BOARD.shop[2], { oops = oops })
    if oops then
      local o = new_card("j_oops")
      place("jokers", { o, G.jokers.cards[1], G.jokers.cards[2] }, 5)
    end
    local cards = {}
    for i, key in ipairs(batch) do cards[i] = dress(new_card(key)) end
    place("shop_jokers", cards)
    local msg = board_message("shop", "shop " .. table.concat(batch, ","))
    if msg then
      for i, card in ipairs(cards) do
        local kind = KIND_OF_SET[card.ability.set]
        local e = entry_for(kind, card, "shop_offer", state_summary(card, state_name), numbered_row(msg, "Shop jokers", i))
        check_card_entry(e)
        sticker_entries(e)
      end
    end
  end
end

local function run_owned(kind, keys, state_name, dress, per_board, board, force_oops)
  board = board or "shop"
  for _, batch in ipairs(chunks(keys, per_board)) do
    local oops = force_oops or (kind == "joker" and rnd(4) == 1)
    prep(BOARD[board][1], BOARD[board][2], { oops = oops })
    if oops and kind ~= "joker" then place("jokers", { new_card("j_oops") }, 5) end
    local cards = {}
    for i, key in ipairs(batch) do
      local scaled = kind == "joker" and state_name ~= "base"
      cards[i] = dress(scaled and scaled_joker(key) or new_card(key), i)
    end
    if kind == "joker" then
      local roster = {}
      for _, c in ipairs(cards) do roster[#roster + 1] = c end
      if oops then roster[#roster + 1] = new_card("j_oops") end
      place("jokers", roster, #roster)
    else
      place("consumeables", cards, #cards)
    end
    local msg = board_message(board, "owned " .. table.concat(batch, ","))
    if msg then
      for i, card in ipairs(cards) do
        local e = entry_for(KIND_OF_SET[card.ability.set], card, "owned_" .. kind, state_summary(card, state_name),
          numbered_row(msg, OWNED_PREFIX[kind], i))
        check_card_entry(e)
        sticker_entries(e)
      end
    end
  end
end

local function run_pack(keys, state_name, dress)
  for _, batch in ipairs(chunks(keys, 3)) do
    prep(BOARD.pack[1], BOARD.pack[2])
    local cards = {}
    for i, key in ipairs(batch) do cards[i] = dress(new_card(key)) end
    place("pack", cards)
    local msg = board_message("pack", "pack " .. table.concat(batch, ","))
    if msg then
      for i, card in ipairs(cards) do
        local e = entry_for(KIND_OF_SET[card.ability.set], card, "pack", state_summary(card, state_name),
          numbered_row(msg, "Cards in the pack", i))
        check_card_entry(e)
        sticker_entries(e)
      end
    end
  end
end

local function plain(card) return card end
local function shop_dressed(card)
  if card.ability.set == "Joker" then
    local r = rnd(10)
    if r <= 4 then card.edition = copy(EDITIONS[r]) end
    sticker_state(card)
  end
  return card
end
local function owned_dressed(card)
  local r = rnd(8)
  if card.ability.set == "Joker" then
    if r <= 4 then card.edition = copy(EDITIONS[r]) end
    sticker_state(card, true)
    if card.ability.perishable and card.ability.perish_tally == 0 then card.debuff = true end
  elseif r <= 2 then
    card.edition = edition("e_negative")
  end
  return card
end
local function debuffed(card) card.debuff = true; return card end

run_shop(KEYS.joker, "base", plain)
run_shop(KEYS.joker, "shop-random", shop_dressed)
run_shop(KEYS.consumable, "base", plain)
run_owned("joker", KEYS.joker, "base", plain, 5)
run_owned("joker", KEYS.joker, "scaled", owned_dressed, 5)
run_owned("joker", KEYS.joker, "debuffed", debuffed, 5, "hand")
run_owned("consumable", KEYS.consumable, "base", plain, 2)
run_owned("consumable", KEYS.consumable, "context-random", owned_dressed, 2, "hand")
run_pack(KEYS.joker, "base", plain)
run_pack(KEYS.joker, "pack-random", shop_dressed)
run_pack(KEYS.consumable, "base", plain)

local PROBABILITY_JOKERS = { "j_8_ball", "j_gros_michel", "j_business", "j_space", "j_cavendish",
  "j_bloodstone", "j_reserved_parking", "j_hallucination" }
run_owned("joker", PROBABILITY_JOKERS, "oops", plain, 4, "shop", true)
run_owned("consumable", { "c_wheel_of_fortune" }, "oops", plain, 1, "shop", true)

local FD_BASELINE = "j_credit_card"
local function facedown_message(key)
  seed = 4242
  prep(BOARD.hand[1], BOARD.hand[2])
  local fixed = { "j_joker", "j_scary_face", "j_baron", "j_banner" }
  local roster = {}
  for i, k in ipairs(fixed) do roster[i] = new_card(k) end
  local hidden = new_card(key)
  hidden.facing = "back"
  table.insert(roster, 3, hidden)
  place("jokers", roster, 5)
  for _, c in ipairs(roster) do c.sort_id = 7000 + _ end
  for i, c in ipairs(roster) do c.sort_id = 7000 + i end
  return board_message("hand", "face-down " .. key), hidden
end

local HAND_RULE = { j_four_fingers = true, j_shortcut = true, j_smeared = true, j_pareidolia = true, j_splash = true }
local HAND_RULE_LINES = { "^%- Ready", "^%- Shape", "^%- One card away", "^%- No hand", "^%- Hand card indices",
  "^%- Joker bonuses", "^Spread the target" }
local function hand_rule_line(l)
  if l == "" then return true end
  for _, p in ipairs(HAND_RULE_LINES) do if l:find(p) then return true end end
  return false
end

local function diff_lines(a, b)
  local count = {}
  for l in (a .. "\n"):gmatch("(.-)\n") do count[l] = (count[l] or 0) + 1 end
  for l in (b .. "\n"):gmatch("(.-)\n") do count[l] = (count[l] or 0) - 1 end
  local only_a, only_b = {}, {}
  for l in (a .. "\n"):gmatch("(.-)\n") do
    if (count[l] or 0) > 0 then only_a[#only_a + 1] = l; count[l] = count[l] - 1 end
  end
  for l in (b .. "\n"):gmatch("(.-)\n") do
    if (count[l] or 0) < 0 then only_b[#only_b + 1] = l; count[l] = count[l] + 1 end
  end
  local out = {}
  for i = 1, math.max(#only_a, #only_b) do out[#out + 1] = { only_a[i] or "", only_b[i] or "" } end
  return out
end

do
  local base = facedown_message(FD_BASELINE)
  for _, key in ipairs(KEYS.joker) do
    local msg, card = facedown_message(key)
    local e = { kind = "joker", key = key, surface = "owned_joker", state = "face-down",
      ability = ability_snapshot(card), name = "", gt = "(hidden)", model = msg and numbered_row(msg, "Your jokers", 3) }
    record(e)
    if base and msg then
      for _, d in ipairs(diff_lines(base, msg)) do
        local allowed = HAND_RULE[key] and hand_rule_line(d[1]) and hand_rule_line(d[2])
        if not allowed then
          fail("hidden information: face-down joker", e, d[2], "same text as with " .. FD_BASELINE .. " face down: " .. d[1])
        end
      end
      local name = squash(tooltip(card).name)
      if #name >= 4 and msg:find(name, 1, true) and not base:find(name, 1, true) then
        fail("hidden information: face-down joker named", e, name, "the face-down joker is not named")
      end
    end
  end
end

do
  for _, key in ipairs(KEYS.joker) do
    prep(BOARD.shop[1], BOARD.shop[2])
    local before = DecisionDelta.capture()
    local card = new_card(key)
    local roster = {}
    for i, c in ipairs(G.jokers.cards) do roster[i] = c end
    roster[#roster + 1] = card
    place("jokers", roster, #roster)
    refresh_all()
    local text = DecisionDelta.render(before, DecisionDelta.capture()) or ""
    local e = entry_for("joker", card, "delta", "acquired", text)
    e.no_numbers = true
    check_row(e)
    record(e)
  end
  for _, key in ipairs(KEYS.consumable) do
    prep(BOARD.shop[1], BOARD.shop[2])
    place("consumeables", { new_card(key == "c_fool" and "c_hermit" or "c_fool") }, 2)
    local before = DecisionDelta.capture()
    local card = new_card(key)
    place("consumeables", { G.consumeables.cards[1], card }, 2)
    refresh_all()
    local text = DecisionDelta.render(before, DecisionDelta.capture()) or ""
    local e = entry_for(KIND_OF_SET[card.ability.set], card, "delta", "acquired", text)
    e.no_numbers = true
    check_row(e)
    record(e)
  end
end

do
  for _, batch in ipairs(chunks(KEYS.voucher, 2)) do
    prep(BOARD.shop[1], BOARD.shop[2])
    local cards = {}
    for i, key in ipairs(batch) do cards[i] = new_card(key) end
    place("shop_vouchers", cards)
    local msg = board_message("shop", "vouchers " .. table.concat(batch, ","))
    if msg then
      for i, card in ipairs(cards) do
        check_card_entry(entry_for("voucher", card, "shop_offer", "base", numbered_row(msg, "Shop vouchers", i)))
      end
    end
  end
  for _, batch in ipairs(chunks(KEYS.voucher, 4)) do
    prep(BOARD.shop[1], BOARD.shop[2])
    G.GAME.used_vouchers = {}
    for _, key in ipairs(batch) do G.GAME.used_vouchers[key] = true end
    local msg = board_message("shop", "owned vouchers " .. table.concat(batch, ","))
    if msg then
      for _, key in ipairs(batch) do
        local card = new_card(key)
        local name = squash(tooltip(card).name)
        check_card_entry(entry_for("voucher", card, "owned_voucher", "base", list_part(msg, "Vouchers you own: ", name)))
      end
    end
  end
  for _, key in ipairs(KEYS.voucher) do
    prep(BOARD.shop[1], BOARD.shop[2])
    G.GAME.used_vouchers = {}
    local before = DecisionDelta.capture()
    G.GAME.used_vouchers[key] = true
    local text = DecisionDelta.render(before, DecisionDelta.capture()) or ""
    local e = entry_for("voucher", new_card(key), "delta", "redeemed", text)
    e.no_numbers = true
    check_row(e)
    record(e)
  end
end

local PACK_GROUP = { Arcana = "k_arcana_pack", Celestial = "k_celestial_pack", Spectral = "k_spectral_pack",
  Standard = "k_standard_pack", Buffoon = "k_buffoon_pack" }
do
  for _, batch in ipairs(chunks(KEYS.booster, 2)) do
    prep(BOARD.shop[1], BOARD.shop[2])
    local cards = {}
    for i, key in ipairs(batch) do cards[i] = new_card(key) end
    place("shop_booster", cards)
    local msg = board_message("shop", "boosters " .. table.concat(batch, ","))
    if msg then
      for i, card in ipairs(cards) do
        check_card_entry(entry_for("booster", card, "shop_offer", "base", numbered_row(msg, "Shop boosters", i)))
      end
    end
  end
  for _, key in ipairs(KEYS.booster) do
    prep(BOARD.pack[1], BOARD.pack[2])
    local card = new_card(key)
    SMODS.OPENED_BOOSTER = card
    G.GAME.pack_choices = card.ability.choose
    local msg = board_message("pack", "open " .. key)
    SMODS.OPENED_BOOSTER = nil
    if msg then
      local group = EU.localize(PACK_GROUP[card.config.center.kind] or "k_booster_group")
      local e = entry_for("booster", card, "pack_open", "base", line_with(msg, "Opened a"))
      e.name = group
      e.no_numbers = true
      check_row(e)
      record(e)
    end
  end
end

local function playing(enh, ed, seal)
  SORT = SORT + 1
  local c = EU.playing(pick(RANKS), pick(SUITS), { enhancement = enh, sort_id = SORT })
  if ed then c.edition = edition(ed) end
  c.seal = seal
  return c
end

local function playing_entry(kind, key, card, surface, state, model)
  local e = entry_for(kind, card, surface, state, model)
  e.key = key
  if kind == "seal" then
    local box = nil
    for _, b in ipairs(e.tt.info) do if b.name and b.name:find("Seal") then box = b end end
    e.name = box and squash(box.name) or (key .. " Seal")
    e.gt = box and gt_clean(table.concat(box.rows, " ")) or ""
  elseif kind == "edition" then
    local box = nil
    for _, b in ipairs(e.tt.info) do if b.name and not b.name:find("Seal") then box = b end end
    e.name = box and squash(box.name) or key
    e.gt = box and gt_clean(table.concat(box.rows, " ")) or ""
  end
  return e
end

local MODIFIERS = {}
for _, k in ipairs(KEYS.enhancement) do MODIFIERS[#MODIFIERS + 1] = { "enhancement", k, function() return playing(k) end } end
for _, ed in ipairs(EDITIONS) do MODIFIERS[#MODIFIERS + 1] = { "edition", ed.key, function() return playing(nil, ed.key) end } end
for _, s in ipairs(KEYS.seal) do MODIFIERS[#MODIFIERS + 1] = { "seal", s, function() return playing(nil, nil, s) end } end

local ODDS = { m_glass = true, m_lucky = true }
do
  for _, m in ipairs(MODIFIERS) do
    for round = 1, ODDS[m[2]] and 3 or 2 do
      local state = ({ "base", "perma-bonus", "probabilities x2" })[round]
      local oops = round == 3
      prep(BOARD.pack[1], BOARD.pack[2], { oops = oops })
      if oops then place("jokers", { new_card("j_oops"), G.jokers.cards[1] }, 5) end
      local card = m[3]()
      if round == 2 then
        card.ability.perma_bonus = 5 * rnd(6)
      end
      place("pack", { card })
      local msg = board_message("pack", "pack " .. m[2])
      if msg then
        check_card_entry(playing_entry(m[1], m[2], card, "pack", state, numbered_row(msg, "Cards in the pack", 1)))
      end
      prep(BOARD.hand[1], BOARD.hand[2], { oops = oops })
      if oops then place("jokers", { new_card("j_oops"), G.jokers.cards[1] }, 5) end
      local held = m[3]()
      if round == 2 then held.ability.perma_bonus = 5 * rnd(6) end
      local hand = {}
      for i, c in ipairs(G.hand.cards) do hand[i] = c end
      hand[1] = held
      place("hand", hand)
      msg = board_message("hand", "hand " .. m[2])
      if msg then
        check_card_entry(playing_entry(m[1], m[2], held, "hand", state, numbered_row(msg, "Your hand", 1)))
      end
    end
  end
end

local function tag_object(key, btype)
  local def = P_TAGS[key]
  return { key = key, name = def.name, config = copy(def.config), ability = { blind_type = btype,
    orbital_hand = key == "tag_orbital" and pick(POKER_HANDS) or nil } }
end
local function tag_truth(tag)
  local sprite = {}
  EU.Tag.get_uibox_table(tag, sprite)
  local tt = EU.tooltip(sprite.ability_UIBox_table)
  return squash(tt.name), gt_clean(table.concat(tt.main, " ")), tt.main
end
do
  for _, key in ipairs(KEYS.tag) do
    prep(BOARD.blind[1], BOARD.blind[2])
    local rr = G.GAME.round_resets
    rr.blind_tags = rr.blind_tags or {}
    rr.blind_tags.Small = key
    local tag = tag_object(key, "Small")
    G.GAME.orbital_choices = { [rr.ante or 1] = { Small = tag.ability.orbital_hand } }
    if rr.blind_choices then rr.blind_choices.Small = rr.blind_choices.Small or "bl_small" end
    local msg = board_message("blind", "skip tag " .. key)
    if msg then
      local name, gt, rows = tag_truth(tag)
      local row = nil
      for _, l in ipairs(section(msg, "Blinds")) do if l:find("Skip tag", 1, true) and l:find("Small", 1, true) then row = l end end
      local e = { kind = "tag", key = key, name = name, surface = "blind_skip_tag", state = "base", gt = gt,
        rows = rows, ability = { orbital_hand = tag.ability.orbital_hand }, model = row and squash(row) }
      check_row(e)
      record(e)
    end
  end
  for _, batch in ipairs(chunks(KEYS.tag, 4)) do
    prep(BOARD.shop[1], BOARD.shop[2])
    local tags = {}
    for i, key in ipairs(batch) do tags[i] = tag_object(key) end
    G.GAME.tags = tags
    local msg = board_message("shop", "held tags " .. table.concat(batch, ","))
    if msg then
      for _, tag in ipairs(tags) do
        local name, gt, rows = tag_truth(tag)
        local e = { kind = "tag", key = tag.key, name = name, surface = "held_tags", state = "base", gt = gt,
          rows = rows, ability = { orbital_hand = tag.ability.orbital_hand }, model = list_part(msg, "Held tags: ", name) }
        check_row(e)
        record(e)
      end
    end
  end
end

local function blind_truth(key)
  local def = P_BLINDS[key]
  local vars = def.vars
  if def.name == "The Ox" then vars = { EU.localize(G.GAME.current_round.most_played_poker_hand, "poker_hands") } end
  local lines = EU.localize({ type = "raw_descriptions", key = key, set = "Blind", vars = vars or {} })
  if def.name == "The Wheel" and lines[1] then lines[1] = tostring(G.GAME.probabilities.normal) .. lines[1] end
  local name = EU.localize({ type = "name_text", key = key, set = "Blind" })
  return squash(name), gt_clean(table.concat(lines, " ")), lines
end
local function live_blind(key)
  local def = P_BLINDS[key]
  return { name = def.name, key = key, config = { blind = def }, debuff = copy(def.debuff or {}), mult = def.mult,
    dollars = def.dollars, boss = def.boss and true or nil, chips = 300, in_blind = true, disabled = false,
    get_type = function() return def.boss and "Boss" or (key == "bl_big" and "Big" or "Small") end }
end
do
  for _, key in ipairs(KEYS.blind) do
    local def = P_BLINDS[key]
    prep(BOARD.blind[1], BOARD.blind[2])
    local rr = G.GAME.round_resets
    rr.blind_choices = rr.blind_choices or {}
    local slot = def.boss and "Boss" or (key == "bl_big" and "Big" or "Small")
    rr.blind_choices[slot] = key
    local msg = board_message("blind", "blind select " .. key)
    if msg then
      local name, gt, rows = blind_truth(key)
      local row = nil
      for _, l in ipairs(section(msg, "Blinds")) do if l:find(name, 1, true) and l:find("needs", 1, true) then row = l end end
      local e = { kind = "blind", key = key, name = name, surface = "blind_select", state = "base", gt = gt,
        rows = rows, ability = { probabilities = G.GAME.probabilities.normal,
          most_played = G.GAME.current_round.most_played_poker_hand }, model = row and squash(row) }
      check_row(e)
      record(e)
    end
    if def.boss then
      local passes = key == "bl_wheel" and { false, true } or { rnd(3) == 1 }
      for _, oops in ipairs(passes) do
        prep(BOARD.hand[1], BOARD.hand[2], { oops = oops })
        if oops then place("jokers", { new_card("j_oops"), G.jokers.cards[1] }, 5) end
        G.GAME.blind = live_blind(key)
        if key == "bl_final_bell" then G.hand.cards[rnd(#G.hand.cards)].ability.forced_selection = true end
        msg = board_message("hand", "live blind " .. key)
        if msg then
          local name, gt, rows = blind_truth(key)
          local text = table.concat(section(msg, "Blind"), " ") .. " " .. table.concat(section(msg, "Boss"), " ")
          local e = { kind = "blind", key = key, name = name, surface = "in_round",
            state = oops and "probabilities x2" or "base", gt = gt, rows = rows,
            ability = { probabilities = G.GAME.probabilities.normal }, model = squash(text) }
          check_row(e)
          record(e)
        end
      end
      prep(BOARD.shop[1], BOARD.shop[2])
      G.GAME.round_resets.blind_choices = G.GAME.round_resets.blind_choices or {}
      G.GAME.round_resets.blind_choices.Boss = key
      msg = board_message("shop", "upcoming boss " .. key)
      if msg then
        local name, gt, rows = blind_truth(key)
        local text = table.concat(section(msg, "Upcoming boss"), " ")
        local e = { kind = "blind", key = key, name = name, surface = "shop_upcoming_boss", state = "base",
          gt = gt, rows = rows, ability = {}, model = squash(text) }
        check_row(e)
        record(e)
      end
    end
  end
  local hidden_base = nil
  for _, key in ipairs({ "bl_hook", "bl_wall", "bl_final_leaf", "bl_ox" }) do
    seed = 999
    prep(BOARD.shop[1], BOARD.shop[2])
    local rr = G.GAME.round_resets
    rr.blind_choices = rr.blind_choices or {}
    rr.blind_states = rr.blind_states or {}
    rr.blind_choices.Boss, rr.blind_states.Boss = key, "Hide"
    local msg = board_message("shop", "hidden boss " .. key)
    local e = { kind = "blind", key = key, surface = "shop_upcoming_boss", state = "hidden (Hide)", gt = "(hidden)",
      model = msg and table.concat(section(msg, "Upcoming boss"), " ") }
    record(e)
    if msg then
      hidden_base = hidden_base or msg
      for _, d in ipairs(diff_lines(hidden_base, msg)) do
        fail("hidden information: unrevealed boss", e, d[2], "same text whichever boss is hidden: " .. d[1])
      end
    end
  end
end

local DECK_EQUIVALENT = {
  b_checkered = function(v) return v == 26 end,
}
local function back_truth(key)
  local center = CENTERS[key]
  G.CHALLENGES = G.CHALLENGES or {}
  local ui = EU.Back.generate_UI({ name = center.name, effect = { center = center, config = center.config } }, center)
  local rows = EU.rows_text(ui.nodes[1].nodes)
  return squash(EU.localize({ type = "name_text", key = key, set = "Back" })), gt_clean(table.concat(rows, " ")), rows
end
local function stake_truth(key)
  local nodes = {}
  EU.localize({ type = "descriptions", key = key, set = "Stake", nodes = nodes, vars = {} })
  local rows = EU.rows_text(nodes)
  return squash(EU.localize({ type = "name_text", key = key, set = "Stake" })), gt_clean(table.concat(rows, " ")), rows
end
do
  prep(BOARD.setup[1], BOARD.setup[2])
  G.P_CENTER_POOLS.Back = {}
  for _, k in ipairs(KEYS.back) do
    if k ~= "b_challenge" then G.P_CENTER_POOLS.Back[#G.P_CENTER_POOLS.Back + 1] = CENTERS[k] end
  end
  G.PROFILES = { { all_unlocked = true, deck_usage = {} } }
  G.SETTINGS = G.SETTINGS or {}
  G.SETTINGS.profile = 1
  local msg = board_message("setup", "run setup")
  if msg then
    for _, key in ipairs(KEYS.back) do
      local name, gt, rows = back_truth(key)
      local row = nil
      for _, l in ipairs(section(msg, "Decks you can select")) do
        if l:find("key " .. key .. ",", 1, true) then row = l end
      end
      local e = { kind = "back", key = key, name = name, surface = "run_setup", state = "base", gt = gt, rows = rows,
        ability = copy(CENTERS[key].config), model = row and squash(row), excused = DECK_EQUIVALENT[key] }
      if key == "b_challenge" then
        e.state = "not selectable"
        record(e)
      else
        check_row(e)
        record(e)
      end
    end
    for _, key in ipairs(KEYS.stake) do
      local name, gt, rows = stake_truth(key)
      local row = nil
      for _, l in ipairs(section(msg, "Stakes")) do if l:find(name, 1, true) then row = l end end
      local e = { kind = "stake", key = key, name = name, surface = "run_setup", state = "base", gt = gt, rows = rows,
        ability = { stake_level = P_STAKES[key].stake_level }, model = row and squash(row) }
      check_row(e)
      record(e)
    end
  end
  for _, key in ipairs(KEYS.back) do
    if key ~= "b_challenge" then
      prep(BOARD.hand[1], BOARD.hand[2])
      G.NEURO.selected_back_key = key
      G.GAME.selected_back = { name = CENTERS[key].name, effect = { center = CENTERS[key], config = copy(CENTERS[key].config) } }
      G.GAME.selected_back_key = { key = key }
      local m = board_message("hand", "in-run deck " .. key)
      local name, gt, rows = back_truth(key)
      if m then
        local line = line_with(m, "Your deck:")
        local e = { kind = "back", key = key, name = name, surface = "in_run_state", state = "base", gt = gt,
          ability = copy(CENTERS[key].config), model = line and squash(line), no_numbers = true }
        check_row(e)
        record(e)
      end
      local stages, stage = G.STAGES, G.STAGE
      G.STAGES = stages or { RUN = 2 }
      G.STAGE = G.STAGES.RUN
      local frame = nil
      for _, f in ipairs(require("context.context_compact").rule_frames()) do
        if tostring(f.text):find("Deck rules", 1, true) then frame = f.text end
      end
      G.STAGES, G.STAGE = stages, stage
      local e = { kind = "back", key = key, name = name, surface = "in_run_rules", state = "base", gt = gt, rows = rows,
        ability = copy(CENTERS[key].config), model = frame and squash(frame), excused = DECK_EQUIVALENT[key] }
      check_row(e)
      record(e)
    end
  end
end

do
  seed = 31337
  prep(BOARD.hand[1], BOARD.hand[2])
  for _, n in ipairs({ "Five of a Kind", "Flush House", "Flush Five" }) do
    G.GAME.hands[n].visible = false
    G.GAME.hands[n].played = 0
  end
  local msg = board_message("hand", "secret hands")
  for _, n in ipairs({ "Five of a Kind", "Flush House", "Flush Five" }) do
    local e = { kind = "hand", key = n, surface = "hand_levels", state = "secret", model = msg }
    if msg and msg:find(n, 1, true) then
      fail("hidden information: secret hand", e, line_with(msg, n), n .. " is not visible until played")
    end
  end
  seed = 31337
  prep(BOARD.hand[1], BOARD.hand[2])
  local first = board_message("hand", "deck order a")
  seed = 31337
  prep(BOARD.hand[1], BOARD.hand[2])
  local d = G.deck.cards
  for i = #d, 2, -1 do local j = rnd(i); d[i], d[j] = d[j], d[i] end
  local second = board_message("hand", "deck order b")
  if first and second then
    for _, dl in ipairs(diff_lines(first, second)) do
      fail("hidden information: deck order", { kind = "deck", key = "draw pile", surface = "hand", state = "shuffled" },
        dl[2], "same text whatever the draw order: " .. dl[1])
    end
  end
end

local function rule_part(model)
  local at = model:find(" -- ", 1, true)
  local s = at and model:sub(at + 4) or model
  for _, stop in ipairs({ ". Targets", ". Usable now", ". Takeable now", " [", " (sell", ". Sell $" }) do
    local cut = s:find(stop, 1, true)
    if cut then s = s:sub(1, cut - 1) end
  end
  return s
end
do
  local groups = {}
  for _, e in ipairs(ENTRIES) do
    if e.card and e.model and e.gt and e.gt ~= "" and not e.card.debuff and e.card.facing ~= "back"
        and not (e.card.base and e.card.base.value)
        and (e.surface == "shop_offer" or e.surface == "pack" or e.surface:find("^owned")) then
      local id = e.kind .. "|" .. e.key .. "|" .. e.gt
      groups[id] = groups[id] or {}
      table.insert(groups[id], e)
    end
  end
  for _, id in ipairs(sorted_keys(groups)) do
    local list = groups[id]
    local ref, ref_words = nil, nil
    for _, e in ipairs(list) do
      local gw = lower_words(e.gt)
      local mw = lower_words(rule_part(e.model))
      local got = {}
      for w in pairs(gw) do if mw[w] then got[#got + 1] = w end end
      for _, v in ipairs(digits(e.gt)) do
        if has_number(numbers(rule_part(e.model)), v) then got[#got + 1] = tostring(v) end
      end
      table.sort(got)
      local sig = table.concat(got, " ")
      if not ref then
        ref, ref_words = e, sig
      elseif sig ~= ref_words then
        fail("inconsistent across surfaces", e, e.surface .. ": " .. e.model,
          ref.surface .. " carries the same rule words: " .. ref.model)
      end
    end
  end
end

if CORPUS_DIR then
  os.execute("mkdir -p '" .. CORPUS_DIR:gsub("'", "") .. "'")
  for kind, lines in pairs(CORPUS) do
    local fh = assert(io.open(CORPUS_DIR .. "/" .. kind .. ".jsonl", "w"))
    fh:write(table.concat(lines, "\n"), "\n")
    fh:close()
  end
  local fh = assert(io.open(CORPUS_DIR .. "/coverage.txt", "w"))
  for _, kind in ipairs(sorted_keys(COVER)) do
    local c = COVER[kind]
    local nk, ns = 0, 0
    for _ in pairs(c.keys) do nk = nk + 1 end
    for _ in pairs(c.states) do ns = ns + 1 end
    fh:write(string.format("%s\t%d items\t%d item-surface-states\tsurfaces: %s\n", kind, nk, ns,
      table.concat(sorted_keys(c.surfaces), ", ")))
  end
  fh:close()
end

for _, f in ipairs(FAILS) do
  COUNTS[f.inv] = (COUNTS[f.inv] or 0) + 1
  print(string.format("FAIL  [%s] %s %s @%s (%s): %q -- expected %s", f.inv, f.kind, f.key, f.surface,
    tostring(f.state), tostring(f.quote), tostring(f.expected)))
end

local function covered(kind, keys)
  local c = COVER[kind]
  local miss = {}
  for _, k in ipairs(keys) do if not (c and c.keys[k]) then miss[#miss + 1] = k end end
  return miss
end
for _, kind in ipairs({ "joker", "tarot", "planet", "spectral", "voucher", "booster", "tag", "enhancement",
    "edition", "seal", "sticker", "blind", "back", "stake" }) do
  local keys = KEYS[kind]
  if kind == "edition" then keys = { "e_foil", "e_holo", "e_polychrome", "e_negative" } end
  local miss = covered(kind, keys)
  check(kind .. ": every item exercised (" .. #keys .. ")", #miss == 0, table.concat(miss, ", "))
end
check("every board assembled", #BUILD_ERRORS == 0, table.concat(BUILD_ERRORS, " | "))
check("item texts match the game (" .. #ENTRIES .. " item renders)", #FAILS == 0, (function()
  local parts = {}
  for _, k in ipairs(sorted_keys(COUNTS)) do parts[#parts + 1] = k .. " x" .. COUNTS[k] end
  return table.concat(parts, "; ")
end)())

done()
