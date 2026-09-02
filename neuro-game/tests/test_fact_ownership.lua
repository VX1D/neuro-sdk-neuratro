-- One fact, one author. Two windows that teach the same sentence must book the same gate, or the
-- model holds it twice forever: silent context never expires (dev/neuro-sdk-docs/API/SPECIFICATION.md).
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function(a)
  if type(a) == "table" and a.type == "raw_descriptions" then return { "All Heart cards are debuffed" } end
  return ""
end
_G.get_blind_amount = function(a) return 300 * a end

local check, done = require("tests.helpers").harness("fact-ownership")
local H = require("tests.helpers")
local C = require("tests.cadence_contract")
local FactHints = require("facts.fact_hints")
local Actions = require("core.actions")
local FBS = require("force.force_blind_select")
local FS = require("force.force_shop")

local BLUEPRINT = { config = { center = { key = "j_blueprint", set = "Joker", name = "Blueprint" } },
  ability = { name = "Blueprint", set = "Joker", mult = 0 }, sell_cost = 2 }
local PLAIN = { config = { center = { key = "j_joker", set = "Joker", name = "Joker" } },
  ability = { name = "Joker", set = "Joker", mult = 4 }, sell_cost = 2 }
local HONE = { cost = 10, ability = { set = "Voucher", name = "Hone" },
  config = { center = { key = "v_hone", name = "Hone", set = "Voucher" } } }
local SHOP_JOKER = { ability = { name = "Baron", set = "Joker", mult = 0 }, cost = 5,
  edition = { polychrome = true }, config = { center = { key = "j_baron", set = "Joker" } } }

local function neuro()
  return { once_serials = {}, session_once_serials = {}, run_generation = 1,
    state_enter_serial = 1, decision_serial = 1 }
end

local function blind_board(o)
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = {},
    GAME = { win_ante = 8, dollars = 20, round = o.round, skips = o.skips or 0,
      blind_on_deck = o.blind or "Small", starting_params = {},
      round_resets = { ante = o.ante,
        blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" } } },
    NEURO = o.neuro or neuro(), jokers = { cards = {} }, consumeables = { cards = {} },
  }
  G.GAME.round_resets.blind_states[G.GAME.blind_on_deck] = "Select"
end

local function shop_board(o)
  _G.G = {
    P_BLINDS = {},
    GAME = { round = o.round, dollars = 8, interest_cap = 25, interest_amount = 1, win_ante = 8,
      skips = o.skips or 0, used_vouchers = {}, modifiers = {}, probabilities = { normal = 1 },
      starting_params = {}, round_resets = { ante = o.ante, discards = 3, blind_choices = {} },
      current_round = { hands_left = 0, discards_left = 0, discards_used = 3, free_rerolls = 0,
        reroll_cost = 5, most_played_poker_hand = "High Card" },
      hands = { ["High Card"] = { visible = true, level = 1, chips = 5, mult = 1, played = 3 } },
      blind = { name = "Small Blind", chips = 300 } },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = o.neuro or neuro(),
    hand = { cards = {}, config = { highlighted_limit = 5 }, highlighted = {} },
    jokers = { cards = { BLUEPRINT, PLAIN }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { SHOP_JOKER } }, shop_vouchers = { cards = { HONE } },
    shop_booster = { cards = {} }, playing_cards = {}, deck = { cards = {} }, play = nil,
  }
end

local BLIND = { name = "BLIND_SELECT", build = FBS.build, board = blind_board,
  valid = function(n) return n == "select_blind" or n == "skip_blind" end }
local SHOP = { name = "SHOP", build = FS.build, board = shop_board,
  valid = function(n) return n == "leave_shop" or n == "buy_from_shop"
    or n == "set_joker_order" or n == "sell_card" end }

local function authored(w, o)
  Actions.is_action_valid = w.valid
  local function frame(drop)
    w.board(o)
    FactHints.reset_pending()
    w.build()
    if drop then FactHints.drop_hint(drop) end
    return H.drain_hints()
  end
  w.board(o)
  local cap = C.capture(w.build)
  local out = {}
  for _, rec in ipairs(cap.booked) do
    out[#out + 1] = { window = w.name, tag = rec.tag, key = rec.key, text = C.isolate(frame, rec.tag) }
  end
  return out
end

local a = authored(BLIND, { ante = 3, round = 5 })
local b = authored(SHOP, { ante = 3, round = 6 })
local Registry = require("facts.hint_registry")
local function claim_of(tag)
  local e = Registry.lookup(tag) or Registry.lookup(tostring(tag) .. ":")
  return e and e.claim or nil
end
local retained_mutable = {}
for _, rec in ipairs(a) do
  if claim_of(rec.tag) ~= "rule" then retained_mutable[#retained_mutable + 1] = "BLIND:" .. tostring(rec.tag) end
end
for _, rec in ipairs(b) do
  if claim_of(rec.tag) ~= "rule" then retained_mutable[#retained_mutable + 1] = "SHOP:" .. tostring(rec.tag) end
end
check("mutable window facts have no retained authors",
  #retained_mutable == 0, table.concat(retained_mutable, ", "))

local dup = {}
for _, ra in ipairs(a) do
  for _, rb in ipairs(b) do
    if ra.text ~= "" and ra.text == rb.text and ra.key ~= rb.key then
      dup[#dup + 1] = string.format("%s/%s (%s) and %s/%s (%s) author the same %d bytes",
        ra.window, ra.tag, ra.key, rb.window, rb.tag, rb.key, #ra.text)
    end
  end
end
check("no sentence is authored by two windows under two gates", #dup == 0, table.concat(dup, " | "))

local N = neuro()
local function frame_of(w, o)
  Actions.is_action_valid = w.valid
  o.neuro = N
  w.board(o)
  FactHints.reset_pending()
  w.build()
  return H.drain_hints()
end
local function curve_of(text) return text:match("Requirement climbs.-%(boss about 2x that%)%. ") end

require("core.context_delivery").reset_transport()

local function query_of(w, o)
  Actions.is_action_valid = w.valid
  o.neuro = N
  w.board(o)
  FactHints.reset_pending()
  local built = w.build()
  local q = (type(built) == "table" and built.query) or ""
  return q, H.drain_hints()
end

local blind3, blind3_retained = query_of(BLIND, { ante = 3, round = 5 })
local shop3 = frame_of(SHOP, { ante = 3, round = 6 })
N.decision_serial = N.decision_serial + 1
N.state_enter_serial = N.state_enter_serial + 1
local blind4 = query_of(BLIND, { ante = 4, round = 7 })

check("the ante's requirement curve rides the force that asks against it",
  curve_of(blind3) ~= nil, blind3)
check("and never the retained channel, which cannot retract it on the next run",
  curve_of(blind3_retained) == nil and curve_of(shop3) == nil,
  tostring(curve_of(blind3_retained)) .. " | " .. tostring(curve_of(shop3)))
check("the next ante states its own curve, not the previous one",
  curve_of(blind4) ~= nil and curve_of(blind4) ~= curve_of(blind3),
  tostring(curve_of(blind3)) .. " -> " .. tostring(curve_of(blind4)))

local curve_keys = {}
for key in pairs(N.once_serials) do
  if key:find("curve", 1, true) then curve_keys[#curve_keys + 1] = key end
end
check("an always-cadence claim reserves no gate key at all",
  #curve_keys == 0, table.concat(curve_keys, " | "))

local function list_lua_files(dir)
  local out = {}
  local p = io.popen('find "' .. dir .. '" -name "*.lua" -type f 2>/dev/null')
  if p then
    for line in p:lines() do out[#out + 1] = line end
    p:close()
  end
  return out
end

local PROD_ROOTS = { "core", "context", "force", "facts", "handlers", "hud", "render", "util" }
local prod_src = {}
for _, dir in ipairs(PROD_ROOTS) do
  for _, f in ipairs(list_lua_files(dir)) do
    local fh = io.open(f, "r")
    if fh then prod_src[f] = fh:read("*a") fh:close() end
  end
end

local reusable_constants = {}
for f, text in pairs(prod_src) do
  for name, value in text:gmatch('[%w_]+%.([A-Z][A-Z0-9_]*)%s*=%s*"([^"\n]*)"') do
    if #value >= 40 then
      reusable_constants[#reusable_constants + 1] = { name = name, value = value, def_file = f }
    end
  end
end

local multi_authored = {}
for _, c in ipairs(reusable_constants) do
  local authors = {}
  for f, text in pairs(prod_src) do
    if f ~= c.def_file and text:find("%f[%w_]" .. c.name .. "%f[^%w_]") then
      authors[#authors + 1] = f
    end
  end
  if #authors > 1 then
    table.sort(authors)
    multi_authored[#multi_authored + 1] = string.format("%s (%dB, defined in %s) embedded by: %s",
      c.name, #c.value, c.def_file, table.concat(authors, ", "))
  end
end

check("a reusable prose constant has at most one producer that embeds it",
  #multi_authored == 0, table.concat(multi_authored, " | "))

done()
