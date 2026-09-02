_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local A = require("core.actions")
local GameRules = require("context.game_rules")
local FSH = require("force.force_selecting_hand")
local FShop = require("force.force_shop")
local FBlind = require("force.force_blind_select")
local FPack = require("force.force_pack")
local ContextReadable = require("context.context_readable")

local fails, total = 0, 0
local first_fail_detail = nil
local function check(name, cond, detail)
  total = total + 1
  if cond then return true end
  fails = fails + 1
  if not first_fail_detail then first_fail_detail = name .. "  -- " .. tostring(detail) end
  if fails <= 12 then print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
  return false
end

local seed = 0x1234567
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local function ri(n) return math.floor(rnd() * n) + 1 end
local function pick(t) return t[ri(#t)] end
local function chance(p) return rnd() < p end

local MOD_TOKENS = { "glorp", "gleeb", "glorpy", "shoomin", "osu_seal", "bloody", "neurjoker",
  "m_twin", "m_dono", "m_glorp", "m_blood", "invader deck", "twin deck", "euchre deck" }
local function scan_mod(txt)
  local lc = txt:lower()
  for _, t in ipairs(MOD_TOKENS) do if lc:find(t, 1, true) then return t end end
  return nil
end
local JARGON = { "Bonus(", "Steel(", "Glass(", "Stone(", "Poly(", "Holo(", "Foil(", "xM=", "+M=",
  "+C=", "jh=", "$/r=", "song=", "min_cards", "max_cards", "_per_round", "_EOround", "no_suit_no_rank",
  "h_size_ge", "repeat_hand_type", "single_hand_type", "|DB", "+DB " }
local function scan_jargon(txt)
  for _, t in ipairs(JARGON) do if txt:find(t, 1, true) then return t end end
  return nil
end

local SUITS = { "Hearts", "Diamonds", "Clubs", "Spades" }
local RANKS = { "2","3","4","5","6","7","8","9","10","Jack","Queen","King","Ace" }
local BASE_ENH = { nil, "m_bonus", "m_glass", "m_steel", "m_gold", "m_stone", "m_lucky", "m_mult", "m_wild" }
local SUIT_BOSSES = { { key="bl_head", suit="Hearts" }, { key="bl_club", suit="Clubs" },
  { key="bl_goad", suit="Spades" }, { key="bl_window", suit="Diamonds" } }

local function gen_card(enh, debuffed)
  local suit = pick(SUITS)
  local c = {
    base = { value = pick(RANKS), suit = suit },
    ability = { name = "", set = "Default", effect = "" },
    config = { center = { key = enh or "c_base", set = "Default" } },
    debuff = debuffed or nil,
    get_id = function() return 10 end,
    is_suit = function(_, s) return s == suit end,
  }
  if enh then c.ability.enhancement = enh end
  return c
end

local function gen_hand(n, void_suit, any_enh)
  local cards = {}
  for i = 1, n do
    local enh = (any_enh and chance(0.25)) and pick(BASE_ENH) or nil
    local c = gen_card(enh, false)
    if void_suit and c.base.suit == void_suit then c.debuff = true end
    c.index = i
    cards[i] = c
  end
  return cards
end

local BASE_JOKERS = { "j_joker", "j_greedy_joker", "j_wily_joker", "j_blueprint", "j_brainstorm",
  "j_credit_card", "j_splash", "j_rocket", "j_banner" }
local function gen_jokers()
  local n = ri(4) - 1
  local cards = {}
  for i = 1, n do
    local key = pick(BASE_JOKERS)
    local card = { ability = { name = key, set = "Joker", extra = {} },
      config = { center = { key = key, set = "Joker" } }, sell_cost = 3, cost = 5 }
    if chance(0.2) then card.edition = { polychrome = true, key = "e_polychrome" } end
    cards[i] = card
  end
  return { cards = cards, config = { card_limit = 5 } }
end

local function gen_consumables(kind)
  local cards = {}
  if kind == "planet" then
    cards[1] = { ability = { name = "Mercury", set = "Planet" }, config = { center = { key = "c_mercury", set = "Planet" } }, sell_cost = 1 }
  elseif kind == "tarot" then
    cards[1] = { ability = { name = "The Lovers", set = "Tarot", consumeable = { max_highlighted = 1, min_highlighted = 1 } },
      config = { center = { key = "c_lovers", set = "Tarot" } }, sell_cost = 1 }
  end
  return { cards = cards, config = { card_limit = 2 } }
end

local function base_GAME(opts)
  return {
    dollars = opts.money, bankrupt_at = 0, chips = opts.chips or 0,
    current_round = { hands_left = opts.hands, discards_left = opts.discards,
      reroll_cost = 5, free_rerolls = opts.free_rerolls or 0 },
    round_resets = { ante = opts.ante, blind_choices = opts.blind_choices or {},
      blind_states = opts.blind_states or {} },
    blind = opts.blind or { chips = 300, mult = 1, debuff = {} },
    used_vouchers = opts.used_vouchers or {}, tags = opts.tags or {},
    probabilities = { normal = opts.prob or 1 }, perishable_rounds = 5,
    interest_cap = 25, discount_percent = opts.discount or 0, inflation = opts.inflation or 0,
    win_ante = 8, stake = 1, pack_choices = 1, modifiers = {},
    bosses_used = opts.bosses_used or {}, skips = opts.skips or 0,
    blind_on_deck = opts.blind_on_deck or "Small",
  }
end

local function set_playing_cards(with_enh)
  local pc = {}
  for i = 1, 8 do pc[i] = gen_card(with_enh and i == 1 and "m_glass" or nil, false) end
  _G.G.playing_cards = pc
end

local function gen_world(state)
  local money = ri(40) - 5
  local jk = gen_jokers()
  local cons_kind = pick({ "none", "none", "planet", "tarot" })
  local cons = gen_consumables(cons_kind)
  local has_voucher = chance(0.3)
  local has_tag = chance(0.3)
  local with_enh = chance(0.4)
  local prob = chance(0.25) and 2 or 1

  local boss_kind = "none"
  local blind = { chips = 300 + ri(20) * 50, mult = 1, debuff = {} }
  local void_suit = nil
  if state == "SELECTING_HAND" and chance(0.45) then
    local r = rnd()
    if r < 0.5 then
      local b = pick(SUIT_BOSSES); boss_kind = "suit"; void_suit = b.suit
      blind = { name = "Boss", boss = true, chips = blind.chips, debuff = { suit = b.suit }, key = b.key }
    elseif r < 0.75 then
      boss_kind = "handtype"
      blind = { name = "The Eye", boss = true, chips = blind.chips, debuff = {},
        debuff_hand = function() return false end, key = "bl_eye" }
    else
      boss_kind = "size"; blind = { name = "The Psychic", boss = true, chips = blind.chips, debuff = { h_size_ge = 5 }, key = "bl_psychic" }
    end
  end

  _G.G = { NEURO = { persona = "neuro", once_serials = {}, reserved_dollars = 0, shop_reroll_count = 0 },
    FUNCS = {}, P_BLINDS = {}, P_TAGS = {} }
  _G.G.GAME = base_GAME({
    money = money, ante = ri(8), hands = ri(4), discards = ri(4) - 1,
    blind = blind, prob = prob,
    used_vouchers = has_voucher and { v_grabber = true } or {},
    tags = has_tag and { { key = "tag_charm" } } or {},
    free_rerolls = chance(0.15) and 1 or 0, discount = chance(0.15) and 25 or 0, inflation = chance(0.15) and 2 or 0,
    bosses_used = chance(0.4) and { boss = { bl_hook = 1 } } or {},
    skips = chance(0.3) and 2 or 0,
    blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
    blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
    blind_on_deck = pick({ "Small", "Big", "Boss" }),
  })
  _G.G.jokers = jk
  _G.G.consumeables = cons
  _G.G.hand = { cards = gen_hand(8, void_suit, with_enh), highlighted = {}, config = { highlighted_limit = 5, card_limit = 8 } }
  set_playing_cards(with_enh)

  if state == "SHOP" then
    local jokers_row = {}
    for i = 1, ri(3) do jokers_row[i] = { ability = { name = "J", set = "Joker" }, config = { center = { key = "j_joker", set = "Joker" } }, cost = ri(8) } end
    if chance(0.4) then jokers_row[#jokers_row + 1] = { ability = { name = "The Fool", set = "Tarot" }, config = { center = { key = "c_fool", set = "Tarot" } }, cost = 3 } end
    _G.G.shop_jokers = { cards = jokers_row }
    _G.G.shop_vouchers = { cards = chance(0.3) and { { ability = { name = "V", set = "Voucher" }, config = { center = { key = "v_x", set = "Voucher" } }, cost = 10 } } or {} }
    _G.G.shop_booster = { cards = chance(0.6) and { { ability = { name = "Buffoon Pack" }, config = { center = { key = "p_buffoon", kind = "Buffoon" } }, cost = 4 } } or {} }
  end
  if state:find("PACK") then
    local pc = {}
    local targeting = chance(0.4)
    for i = 1, 3 do
      if targeting and i == 1 then
        pc[i] = { ability = { name = "The Lovers", set = "Tarot", consumeable = { max_highlighted = 1, min_highlighted = 1 } }, config = { center = { key = "c_lovers", set = "Tarot" } } }
      else
        pc[i] = { ability = { name = "Mercury", set = "Planet" }, config = { center = { key = "c_mercury", set = "Planet" } } }
      end
    end
    _G.G.pack_cards = { cards = pc }
  end

  return {
    state = state, boss_kind = boss_kind, void_suit = void_suit, prob = prob,
    has_jokers = #jk.cards > 0, has_cons = cons_kind ~= "none", cons_kind = cons_kind,
    has_voucher_or_tag = has_voucher or has_tag, has_enh = with_enh,
    is_boss = (blind.boss == true),
  }
end

A.is_action_valid = function() return true end

local function build_force(state)
  if state == "SELECTING_HAND" then return FSH.build()
  elseif state == "SHOP" then return FShop.build()
  elseif state == "BLIND_SELECT" then return FBlind.build()
  else return FPack.build(state) end
end

local function dangling_header(txt)
  for _, hdr in ipairs({ "PC:i,n,t,ok,f,d", "BO:type,key,name", "SDC:i,k,n,e" }) do
    local s = txt:find(hdr, 1, true)
    if s then
      local after = txt:sub(s + #hdr)
      local nl = after:find("\n")
      local rest = nl and after:sub(nl + 1) or ""
      if not rest:match("^%s*%d") then return hdr end
    end
  end
  return nil
end

local STATES = { "SELECTING_HAND", "SELECTING_HAND", "SELECTING_HAND", "SHOP", "SHOP", "BLIND_SELECT", "BUFFOON_PACK" }
local ITERS = 700
local cov = { boss = 0, suitvoid = 0, tarot = 0, planet = 0, enh = 0, prob2 = 0, voucher = 0, jokers = 0 }

for it = 1, ITERS do
  local state = pick(STATES)
  local ok_world, w = pcall(gen_world, state)
  if not check("INV7 world-gen no crash (#" .. it .. " " .. state .. ")", ok_world, w) then break end
  if w.is_boss then cov.boss = cov.boss + 1 end
  if w.void_suit then cov.suitvoid = cov.suitvoid + 1 end
  if w.cons_kind == "tarot" then cov.tarot = cov.tarot + 1 elseif w.cons_kind == "planet" then cov.planet = cov.planet + 1 end
  if w.has_enh then cov.enh = cov.enh + 1 end
  if w.prob == 2 then cov.prob2 = cov.prob2 + 1 end
  if w.has_voucher_or_tag then cov.voucher = cov.voucher + 1 end
  if w.has_jokers then cov.jokers = cov.jokers + 1 end

  local outputs = {}
  local ok_f, force = pcall(build_force, state)
  check("INV7 force build no crash (#" .. it .. " " .. state .. ")", ok_f, force)
  local q = (ok_f and type(force) == "table" and force.query) or ""
  outputs[#outputs + 1] = { text = q, readable = true }
  if ok_f then
    local ok_c, ctx = pcall(ContextReadable.build, state, (type(force) == "table" and force.actions) or {})
    if ok_c and type(ctx) == "string" then outputs[#outputs + 1] = { text = ctx, readable = true } end
  end

  local ok_fr, frame = pcall(GameRules.invariant_frame)
  check("INV7 frame no crash (#" .. it .. ")", ok_fr, frame)
  frame = (ok_fr and frame) or ""

  check("INV0 frame carries text to scan (#" .. it .. ")", frame ~= "", frame)
  check("INV0 the state produced outputs to scan (#" .. it .. " " .. state .. ")", #outputs > 0)
  for _, o in ipairs(outputs) do
    check("INV0 output carries text to scan (#" .. it .. " " .. state .. ")",
      type(o.text) == "string" and o.text ~= "", tostring(o.text))
  end

  for _, o in ipairs(outputs) do
    local m = scan_mod(o.text)
    check("INV1 no mod token in output (#" .. it .. " " .. state .. ")", m == nil, (m or "?") .. " | " .. o.text:sub(1, 120))
  end
  check("INV1 no mod token in FRAME (#" .. it .. ")", scan_mod(frame) == nil, scan_mod(frame or ""))

  for _, o in ipairs(outputs) do
    check("INV2 no jargon leak in readable (#" .. it .. " " .. state .. ")", scan_jargon(o.text) == nil, (scan_jargon(o.text) or "") .. " | " .. o.text:sub(1, 140))
  end

  check("INV3 FRAME has no generic boss-debuff prose (#" .. it .. ")",
    not frame:find("invalidate card groups or hand shapes", 1, true), frame:sub(1, 80))

  if state == "SELECTING_HAND" then
    local hand_query = (build_force("SELECTING_HAND") or {}).query or ""
    local use_bit = hand_query:match("use_consumable[^;]*") or ""
    local ad = use_bit:find("hand_indices", 1, true) ~= nil
    check("INV4 hand_indices iff targeting consumable (#" .. it .. ")", ad == (w.cons_kind == "tarot"),
      "advertised=" .. tostring(ad) .. " cons=" .. w.cons_kind)
  end

  for _, o in ipairs(outputs) do
    check("INV5 no dangling CSV header (#" .. it .. " " .. state .. ")", dangling_header(o.text) == nil, dangling_header(o.text))
  end

  if state == "SELECTING_HAND" and not w.is_boss then
    local nonboss_query = (build_force("SELECTING_HAND") or {}).query or ""
    check("INV9 non-boss hand force has no debuff prose (#" .. it .. ")", nonboss_query:lower():find("debuff", 1, true) == nil, nonboss_query:sub(1, 120))
  end
end

if first_fail_detail then print("first failure: " .. first_fail_detail) end
print(string.format("coverage: boss=%d (suit-void=%d) tarot=%d planet=%d enh=%d oops!odds=%d voucher/tag=%d jokers=%d",
  cov.boss, cov.suitvoid, cov.tarot, cov.planet, cov.enh, cov.prob2, cov.voucher, cov.jokers))
print(string.format("==== synthetic-game: %d/%d PASS, %d FAIL (seed=0x1234567, %d iters) ====",
  total - fails, total, fails, ITERS))
os.exit(fails == 0 and 0 or 1)
