_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = {} }
_G.localize = function() return "" end

local DUMP = os.getenv("BALATRO_DUMP")

local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local text = fh:read("*a")
  fh:close()
  return text
end

local LOST_IF_SKIPPED = 118

local function bail(reason)
  require("tests.skip_ledger").bail("live-game-source", LOST_IF_SKIPPED,
    reason .. "; set BALATRO_DUMP to the lovely dump directory to run it")
end

local game_src = read_file(DUMP .. "/game.lua")
local card_src = read_file(DUMP .. "/card.lua")
local blind_src = read_file(DUMP .. "/blind.lua")
local state_src = read_file(DUMP .. "/functions/state_events.lua")
if not game_src then bail("game dump not readable at " .. DUMP .. "/game.lua") end
if not card_src then bail("game dump not readable at " .. DUMP .. "/card.lua") end
if not blind_src then bail("game dump not readable at " .. DUMP .. "/blind.lua") end
if not state_src then bail("game dump not readable at " .. DUMP .. "/functions/state_events.lua") end

local loadchunk = loadstring or load

local function dump_entry(src, key)
  local body = src:match("\n%s*" .. key .. "%s*=%s*(%b{})")
  if not body then return nil end
  local chunk = loadchunk("local HEX = function(s) return s end "
    .. "local localize = function() return '' end return " .. body)
  if not chunk then return nil end
  local ok, tbl = pcall(chunk)
  if not ok then return nil end
  return tbl
end

local function dump_number(src, field)
  local hits = 0
  local value
  for v in src:gmatch("\n%s*" .. field .. "%s*=%s*(%-?[%d%.]+),") do
    hits = hits + 1
    value = tonumber(v)
  end
  if hits ~= 1 then return nil, hits end
  return value, 1
end

local raw_check, done = require("tests.helpers").harness("live-game-source")
local ran = 0
local function check(...) ran = ran + 1 return raw_check(...) end
local CardUtil = require("facts.card_util")
local BossModel = require("facts.boss.model")
local BossRender = require("facts.boss.render")
local EF = require("facts.economy_facts")
local CtxHelpers = require("context.ctx_helpers")

local function n(v)
  if v == nil then return "<nil>" end
  if v % 1 == 0 then return string.format("%d", v) end
  return (tostring(v):gsub("0+$", ""))
end

local prob_block = game_src:match("\n%s*probabilities%s*=%s*(%b{})")
local dump_prob = prob_block and tonumber(prob_block:match("normal%s*=%s*([%d%.]+)"))
check("the dump states the base probability numerator", dump_prob ~= nil, tostring(prob_block))
dump_prob = dump_prob or 1

local lucky_mult_odds = tonumber(card_src:match("'lucky_mult'%s*,%s*%d+%s*,%s*(%d+)"))
local lucky_money_odds = tonumber(card_src:match("'lucky_money'%s*,%s*%d+%s*,%s*(%d+)"))
check("the dump states the Lucky Card odds", lucky_mult_odds ~= nil and lucky_money_odds ~= nil,
  tostring(lucky_mult_odds) .. "/" .. tostring(lucky_money_odds))

local function short(key) return function() return CardUtil.enhancement_short(key) end end
local function desc(key) return function() return CardUtil.enhancement_record(key).desc end end
local function fx(key) return function() return CardUtil.enhancement_record(key).fx end end

local PROBES = {
  { key = "m_bonus", what = "short", render = short("m_bonus"),
    expect = function(c) return "Bonus(+" .. n(c.bonus) .. "c)" end },
  { key = "m_bonus", what = "desc", render = desc("m_bonus"),
    expect = function(c) return "+" .. n(c.bonus) .. " Chips" end },
  { key = "m_mult", what = "short", render = short("m_mult"),
    expect = function(c) return "Mult(+" .. n(c.mult) .. "m)" end },
  { key = "m_mult", what = "fx", render = fx("m_mult"),
    expect = function(c) return "+" .. n(c.mult) .. "m" end },
  { key = "m_glass", what = "short", render = short("m_glass"),
    expect = function(c)
      return "Glass(x" .. n(c.Xmult) .. "m_always_then_" .. n(dump_prob) .. "/" .. n(c.extra)
        .. "_destroyed)"
    end },
  { key = "m_glass", what = "desc", render = desc("m_glass"),
    expect = function(c)
      return "x" .. n(c.Xmult) .. " Mult, " .. n(dump_prob) .. " in " .. n(c.extra)
        .. " chance to break"
    end },
  { key = "m_steel", what = "short", render = short("m_steel"),
    expect = function(c) return "Steel(x" .. n(c.h_x_mult) .. "m_per_copy_held_not_played)" end },
  { key = "m_steel", what = "desc", render = desc("m_steel"),
    expect = function(c) return "x" .. n(c.h_x_mult) .. " Mult while in hand" end },
  { key = "m_stone", what = "short", render = short("m_stone"),
    expect = function(c) return "Stone(no_suit_no_rank+" .. n(c.bonus) .. "c_always)" end },
  { key = "m_stone", what = "desc", render = desc("m_stone"),
    expect = function(c) return "+" .. n(c.bonus) .. " Chips, no rank/suit" end },
  { key = "m_gold", what = "short", render = short("m_gold"),
    expect = function(c) return "Gold(+$" .. n(c.h_dollars) .. "_held_EOround)" end },
  { key = "m_gold", what = "fx", render = fx("m_gold"),
    expect = function(c) return "+$" .. n(c.h_dollars) end },
  { key = "m_lucky", what = "short", render = short("m_lucky"),
    expect = function(c)
      return "Lucky(" .. n(dump_prob) .. "/" .. n(lucky_mult_odds) .. ":+" .. n(c.mult)
        .. "m_or_" .. n(dump_prob) .. "/" .. n(lucky_money_odds) .. ":+" .. n(c.p_dollars) .. "$)"
    end },
  { key = "m_lucky", what = "desc", render = desc("m_lucky"),
    expect = function(c)
      return n(dump_prob) .. " in " .. n(lucky_mult_odds) .. " for +" .. n(c.mult) .. " Mult, "
        .. n(dump_prob) .. " in " .. n(lucky_money_odds) .. " for $" .. n(c.p_dollars)
    end },
  { key = "e_foil", what = "tag",
    render = function() return CardUtil.edition_tag({ foil = true }) end,
    expect = function(c) return "Foil(+" .. n(c.extra) .. "c)" end },
  { key = "e_foil", what = "readable",
    render = function() return CardUtil.edition_readable({ foil = true }) end,
    expect = function(c) return "Foil: +" .. n(c.extra) .. " Chips" end },
  { key = "e_holo", what = "tag",
    render = function() return CardUtil.edition_tag({ holo = true }) end,
    expect = function(c) return "Holo(+" .. n(c.extra) .. "m)" end },
  { key = "e_holo", what = "fx_short",
    render = function() return CardUtil.edition_fx_short({ holo = true }) end,
    expect = function(c) return "+" .. n(c.extra) .. "m" end },
  { key = "e_polychrome", what = "tag",
    render = function() return CardUtil.edition_tag({ polychrome = true }) end,
    expect = function(c) return "Poly(x" .. n(c.extra) .. "m)" end },
  { key = "e_polychrome", what = "fx_short",
    render = function() return CardUtil.edition_fx_short({ polychrome = true }) end,
    expect = function(c) return "x" .. n(c.extra) .. "m" end },
  { key = "e_negative", what = "readable",
    render = function() return CardUtil.edition_readable({ negative = true }) end,
    expect = function(c)
      return "Negative: Takes no slot (+" .. n(c.extra) .. " joker/consumable slot)"
    end },
}

local dump_cfg = {}
for _, probe in ipairs(PROBES) do
  if dump_cfg[probe.key] == nil then
    local entry = dump_entry(game_src, probe.key)
    dump_cfg[probe.key] = (type(entry) == "table" and type(entry.config) == "table")
      and entry.config or false
  end
end

for key, cfg in pairs(dump_cfg) do
  check("" .. key .. " has a config block in the game dump", cfg ~= false)
end

_G.G = { GAME = {} }
for _, probe in ipairs(PROBES) do
  local cfg = dump_cfg[probe.key]
  if cfg then
    local want = probe.expect(cfg)
    local got = probe.render()
    check("" .. probe.key .. "." .. probe.what .. " fallback literal matches the game's own value",
      got == want, tostring(got) .. " ~= " .. tostring(want))
  end
end

local function mutate(cfg)
  local out = {}
  for k, v in pairs(cfg) do
    if type(v) == "number" then out[k] = v * 2 + 1 else out[k] = v end
  end
  return out
end

for _, probe in ipairs(PROBES) do
  local cfg = dump_cfg[probe.key]
  if cfg then
    local m = mutate(cfg)
    _G.G = { GAME = {}, P_CENTERS = { [probe.key] = { config = m } } }
    local want = probe.expect(m)
    local got = probe.render()
    check("" .. probe.key .. "." .. probe.what .. " follows a changed value in G.P_CENTERS",
      got == want, tostring(got) .. " ~= " .. tostring(want))
    check("" .. probe.key .. "." .. probe.what .. " is not a frozen literal",
      want ~= probe.expect(cfg), want)
  end
end

_G.G = { GAME = {} }
check("the odds numerator falls back to the game's own default",
  CardUtil.live_odds(4) == n(dump_prob) .. " in 4", CardUtil.live_odds(4))
_G.G = { GAME = { probabilities = { normal = dump_prob + 2 } } }
check("a run-time numerator (Oops! All 6s) moves the odds",
  CardUtil.live_odds(4) == n(dump_prob + 2) .. " in 4", CardUtil.live_odds(4))
check("the fraction form uses the same numerator",
  CardUtil.odds_frac(4) == n(dump_prob + 2) .. "/4", CardUtil.odds_frac(4))

local smods_calls = 0
_G.SMODS = { get_probability_vars = function() smods_calls = smods_calls + 1 return 9, 99 end }
_G.G = { GAME = { probabilities = { normal = dump_prob } } }
local guarded = CardUtil.live_odds(4)
check("the odds never route through SMODS.get_probability_vars",
  smods_calls == 0 and guarded == n(dump_prob) .. " in 4",
  guarded .. " (SMODS calls: " .. tostring(smods_calls) .. ")")
_G.SMODS = nil

local dump_rental = dump_number(game_src, "rental_rate")
check("the dump states a rental rate", dump_rental ~= nil, tostring(dump_rental))
if dump_rental then
  _G.G = { GAME = {} }
  check("the rental sticker literal matches the game's rate",
    CardUtil.sticker_fx_short("rental") == "-$" .. n(dump_rental) .. "/rd",
    CardUtil.sticker_fx_short("rental"))
  _G.G = { GAME = { rental_rate = dump_rental + 4 } }
  check("and follows a run that changed it",
    CardUtil.sticker_fx_short("rental") == "-$" .. n(dump_rental + 4) .. "/rd",
    CardUtil.sticker_fx_short("rental"))
end

local P_BLINDS_SRC = game_src:match("self%.P_BLINDS%s*=%s*(%b{})")
check("the dump exposes P_BLINDS", P_BLINDS_SRC ~= nil)

local live_blinds = {}
if P_BLINDS_SRC then
  local chunk = loadchunk("local HEX = function(s) return s end "
    .. "local localize = function() return '' end return " .. P_BLINDS_SRC)
  local ok, tbl = pcall(chunk)
  if ok and type(tbl) == "table" then live_blinds = tbl end
end
check("P_BLINDS loads from the dump", next(live_blinds) ~= nil)

local name_bad, missing, not_boss = {}, {}, {}
for key, our_name in pairs(BossModel.BOSS_NAMES) do
  local def = live_blinds[key]
  if type(def) ~= "table" then
    missing[#missing + 1] = key
  else
    if not def.boss then not_boss[#not_boss + 1] = key end
    if def.name ~= our_name then
      name_bad[#name_bad + 1] = key .. ": ours '" .. tostring(our_name) .. "' vs game '"
        .. tostring(def.name) .. "'"
    end
  end
end
check("every key in BOSS_NAMES exists in the game's P_BLINDS",
  #missing == 0, table.concat(missing, ", "))
check("every key in BOSS_NAMES is a boss blind in the game",
  #not_boss == 0, table.concat(not_boss, ", "))
check("every BOSS_NAMES literal matches the game's name",
  #name_bad == 0, table.concat(name_bad, " | "))

local unknown = {}
for key, def in pairs(live_blinds) do
  if type(def) == "table" and def.boss and not BossModel.BOSS_NAMES[key] then
    unknown[#unknown + 1] = key
  end
end
check("the game has no boss blind our table does not know",
  #unknown == 0, table.concat(unknown, ", "))

check("C5a The Mark still turns every drawn face card face down",
  blind_src:find("self.name == 'The Mark' and card:is_face(true)", 1, true) ~= nil)
check("C5b The House still applies only before the first play or discard",
  blind_src:find("self.name == 'The House' and G.GAME.current_round.hands_played == 0 and G.GAME.current_round.discards_used == 0", 1, true) ~= nil)
check("C5c The Serpent still replaces an activated draw with min(deck, 3)",
  state_src:find("G.GAME.blind.name == 'The Serpent'", 1, true) ~= nil
    and state_src:find("G.GAME.current_round.hands_played > 0", 1, true) ~= nil
    and state_src:find("G.GAME.current_round.discards_used > 0", 1, true) ~= nil
    and state_src:find("hand_space = math.min(#G.deck.cards, 3)", 1, true) ~= nil)
local ox_snapshot = state_src:match(
  "if G%.GAME%.blind:get_type%(%) == 'Boss' then.-G%.GAME%.current_round%.most_played_poker_hand%s*=%s*_handname")
check("C5d The Ox still spends the snapshot written only when a boss round ends",
  ox_snapshot ~= nil
    and blind_src:find("handname == G.GAME.current_round.most_played_poker_hand", 1, true) ~= nil)
check("C5e The Needle still subtracts to one base hand and uses the Small-Blind target multiplier",
  blind_src:find("self.hands_sub = G.GAME.round_resets.hands - 1", 1, true) ~= nil
    and live_blinds.bl_needle and live_blinds.bl_needle.mult == 1)

local function copy_blinds(overrides)
  local out = {}
  for k, v in pairs(live_blinds) do
    local e = {}
    for k2, v2 in pairs(v) do e[k2] = v2 end
    out[k] = e
  end
  for k, name in pairs(overrides or {}) do
    if out[k] then out[k].name = name end
  end
  return out
end

_G.G = { GAME = {}, P_BLINDS = copy_blinds() }
check("a real non-boss entry never becomes a boss name",
  BossModel.boss_name("bl_small") == nil, tostring(BossModel.boss_name("bl_small")))
check("and a real non-boss name never resolves to a key",
  BossModel.resolve_key({ name = live_blinds.bl_small and live_blinds.bl_small.name }) == nil,
  tostring(BossModel.resolve_key({ name = live_blinds.bl_small and live_blinds.bl_small.name })))
check("a boss name from the game resolves to its key",
  BossModel.resolve_key({ name = live_blinds.bl_ox and live_blinds.bl_ox.name }) == "bl_ox",
  tostring(BossModel.resolve_key({ name = live_blinds.bl_ox and live_blinds.bl_ox.name })))

_G.G = { GAME = {}, P_BLINDS = copy_blinds({
  bl_ox = "The Bull", bl_eye = "The Cyclops", bl_mouth = "The Maw",
}) }
check("a renamed boss is read from the game, not from our table",
  BossModel.boss_name("bl_ox") == "The Bull", BossModel.boss_name("bl_ox"))
check("resolve_key finds the key by the game's renamed name",
  BossModel.resolve_key({ name = "The Bull" }) == "bl_ox",
  tostring(BossModel.resolve_key({ name = "The Bull" })))
local ox_status = BossRender.render("status", "bl_ox", { blind = G.P_BLINDS.bl_ox })
check("the rendered boss prefix uses the game's name",
  type(ox_status) == "string" and ox_status:sub(1, 17) == "Boss (The Bull): ", tostring(ox_status))
check("and does not leak our frozen name",
  type(ox_status) == "string" and ox_status:find("The Ox", 1, true) == nil, tostring(ox_status))

local eye_reject = BossRender.render("rejection", "bl_eye",
  { blind = G.P_BLINDS.bl_eye, vars = { handname = "Pair" } })
check("the Eye rejection template uses the game's name",
  type(eye_reject) == "string" and eye_reject:sub(1, 20) == "BOSS (The Cyclops): ", tostring(eye_reject))
check("and does not leak our frozen name",
  type(eye_reject) == "string" and eye_reject:find("The Eye", 1, true) == nil, tostring(eye_reject))

local mouth_reject = BossRender.render("rejection", "bl_mouth",
  { blind = G.P_BLINDS.bl_mouth, vars = { handname = "Pair" } })
check("the Mouth rejection template uses the game's name",
  type(mouth_reject) == "string" and mouth_reject:sub(1, 16) == "BOSS (The Maw): ", tostring(mouth_reject))
check("and does not leak our frozen name",
  type(mouth_reject) == "string" and mouth_reject:find("The Mouth", 1, true) == nil,
  tostring(mouth_reject))

local dump_cap = dump_number(game_src, "interest_cap")
local dump_amount = dump_number(game_src, "interest_amount")
check("the dump states the interest defaults",
  dump_cap ~= nil and dump_amount ~= nil,
  tostring(dump_cap) .. " / " .. tostring(dump_amount))

if dump_cap and dump_amount then
  _G.G = { GAME = {} }
  check("our interest cap fallback matches the game's default",
    EF.interest_cap() == dump_cap, tostring(EF.interest_cap()))
  check("our interest amount fallback matches the game's default",
    EF.interest_amount() == dump_amount, tostring(EF.interest_amount()))

  _G.G = { GAME = { dollars = 20, interest_cap = dump_cap, interest_amount = dump_amount } }
  check("interest counts $5 steps at the game's rate",
    EF.calc_interest(20) == dump_amount * 4, tostring(EF.calc_interest(20)))
  _G.G = { GAME = { dollars = 20, interest_cap = dump_cap, interest_amount = dump_amount + 2 } }
  check("a raised interest_amount (Seed Money/Money Tree) is honoured",
    EF.calc_interest(20) == (dump_amount + 2) * 4, tostring(EF.calc_interest(20)))
  _G.G = { GAME = { dollars = 1000, interest_cap = dump_cap, interest_amount = dump_amount } }
  check("the cap bounds the payout",
    EF.calc_interest(1000) == dump_amount * (dump_cap / 5), tostring(EF.calc_interest(1000)))
  _G.G = { GAME = { dollars = 20, interest_cap = dump_cap, interest_amount = dump_amount,
    modifiers = { no_interest = true } } }
  check("the Green Deck no_interest modifier zeroes it",
    EF.calc_interest(20) == 0, tostring(EF.calc_interest(20)))
end

_G.G = { NEURO = {}, GAME = {
  dollars = 100, chips = 0, interest_amount = 1, interest_cap = 27,
  blind = { in_blind = true, dollars = 5 },
  current_round = { hands_left = 0, discards_left = 0, dollars_to_be_earned = "" },
  modifiers = {},
} }
local econ = EF.economy_projection()
check("a cap that is not a multiple of five yields a fractional interest",
  econ.interest == 5.4, tostring(econ.interest))
check("the payout token keeps the fraction instead of truncating it",
  EF.payout_token(econ) == "B5+hr0+dr0+I5.4=T10.4", EF.payout_token(econ))
local payout = CtxHelpers.decode_payout and CtxHelpers.decode_payout(econ)
if payout then
  check("the cash-out sentence keeps it too",
    payout:find("interest $5.4", 1, true) ~= nil, payout)
end

_G.G = { GAME = {}, P_CENTERS = { m_bonus = { config = { bonus = 1000000 } } } }
check("a large chip value never renders in exponent notation",
  CardUtil.enhancement_short("m_bonus") == "Bonus(+1000000c)",
  CardUtil.enhancement_short("m_bonus"))
_G.G = { GAME = {}, P_CENTERS = { m_steel = { config = { h_x_mult = 1.5 } } } }
check("a fractional multiplier keeps its fraction",
  CardUtil.enhancement_record("m_steel").fx == "x1.5m",
  CardUtil.enhancement_record("m_steel").fx)
_G.G = { GAME = {}, P_CENTERS = { m_steel = { config = { h_x_mult = 2 } } } }
check("and an integral one drops the decimal point",
  CardUtil.enhancement_record("m_steel").fx == "x2m",
  CardUtil.enhancement_record("m_steel").fx)

local ran_before_audit = ran
check("the suite ran the " .. LOST_IF_SKIPPED .. " checks its skip notice claims",
  ran_before_audit >= LOST_IF_SKIPPED, ran_before_audit)

done()
