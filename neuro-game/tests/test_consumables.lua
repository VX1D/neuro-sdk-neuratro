-- Sweep over every base consumable (22 Tarot, 12 Planet, 18 Spectral): set classification, hand-target range, C: row render.
-- Locks the pack-ok fix: can_take_pack_card must evaluate usability with (any_state, skip_check) or takeable consumables show ok=N. luajit tests/test_consumables.lua
package.path = "./?.lua;;" .. package.path
_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local CardUtil = require("facts.card_util")
local CtxMisc = require("context.ctx_misc")

local fails, total = 0, 0
local function check(name, cond, detail)
  total = total + 1
  if cond then print("PASS  " .. name)
  else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- {center key, set, max_highlighted (0 = no hand targeting)}
local CONSUMABLES = {
  -- Tarot (22)
  {"c_fool","Tarot",0}, {"c_magician","Tarot",2}, {"c_high_priestess","Tarot",0}, {"c_empress","Tarot",2},
  {"c_emperor","Tarot",0}, {"c_heirophant","Tarot",2}, {"c_lovers","Tarot",1}, {"c_chariot","Tarot",1},
  {"c_justice","Tarot",1}, {"c_hermit","Tarot",0}, {"c_wheel_of_fortune","Tarot",0}, {"c_strength","Tarot",2},
  {"c_hanged_man","Tarot",2}, {"c_death","Tarot",2}, {"c_temperance","Tarot",0}, {"c_devil","Tarot",1},
  {"c_tower","Tarot",1}, {"c_star","Tarot",3}, {"c_moon","Tarot",3}, {"c_sun","Tarot",3},
  {"c_judgement","Tarot",0}, {"c_world","Tarot",3},
  -- Planet (12)
  {"c_mercury","Planet",0}, {"c_venus","Planet",0}, {"c_earth","Planet",0}, {"c_mars","Planet",0},
  {"c_jupiter","Planet",0}, {"c_saturn","Planet",0}, {"c_uranus","Planet",0}, {"c_neptune","Planet",0},
  {"c_pluto","Planet",0}, {"c_planet_x","Planet",0}, {"c_ceres","Planet",0}, {"c_eris","Planet",0},
  -- Spectral (18)
  {"c_familiar","Spectral",0}, {"c_grim","Spectral",0}, {"c_incantation","Spectral",0}, {"c_talisman","Spectral",1},
  {"c_aura","Spectral",0}, {"c_wraith","Spectral",0}, {"c_sigil","Spectral",0}, {"c_ouija","Spectral",0},
  {"c_ectoplasm","Spectral",0}, {"c_immolate","Spectral",0}, {"c_ankh","Spectral",0}, {"c_deja_vu","Spectral",1},
  {"c_hex","Spectral",0}, {"c_trance","Spectral",1}, {"c_medium","Spectral",1}, {"c_cryptid","Spectral",1},
  {"c_soul","Spectral",0}, {"c_black_hole","Spectral",0},
}

-- NAMED_TARGET: consumables that hand-target by name (no max_highlighted); Aura is the only base one, gated on ability.name
local NAMED_TARGET = { c_aura = 1 }

local function mk(key, set, mh)
  local cons = {}
  if mh and mh > 0 then cons.max_highlighted = mh end
  local name = (key:gsub("^c_", ""):gsub("_", " "))
  return { ability = { name = name, set = set, consumeable = cons }, config = { center = { key = key, set = set } } }
end

local by_set = { Tarot = 0, Planet = 0, Spectral = 0 }
for _, e in ipairs(CONSUMABLES) do
  local key, set, mh = e[1], e[2], e[3]
  by_set[set] = (by_set[set] or 0) + 1
  local card = mk(key, set, mh)

  check(key .. ": set classified", CardUtil.card_set(card) == set)

  local mn, mx = CardUtil.consumable_target_range(card)
  local exp_max = NAMED_TARGET[key] or (mh > 0 and mh or nil)
  if exp_max then
    check(key .. ": hand-target range = 1.." .. exp_max, mx == exp_max and type(mn) == "number" and mn >= 1, tostring(mn) .. "," .. tostring(mx))
  else
    check(key .. ": non-targeting -> nil range", mn == nil and mx == nil)
  end

  G.consumeables = { cards = { card }, config = { card_limit = 2 } }
  local s = CtxMisc.consumables_section() or ""
  check(key .. ": C row renders with set in t column", s:find("," .. set .. ",", 1, true) ~= nil, s)
end
check("sweep: 22/12/18 Tarot/Planet/Spectral covered",
  by_set.Tarot == 22 and by_set.Planet == 12 and by_set.Spectral == 18,
  string.format("T%d P%d S%d", by_set.Tarot, by_set.Planet, by_set.Spectral))

-- a hand-targeting consumable is always takeable (targets hand cards, not a consumable slot)
check("pack-ok: targeting consumable is takeable", CardUtil.can_take_pack_card(mk("c_death", "Tarot", 2)) == true)

-- Aura hand-targets by name; the mod must still mark it takeable or the model can never pick it (was ok=N)
do
  local aura = mk("c_aura", "Spectral", 0)
  local amn, amx = CardUtil.consumable_target_range(aura)
  check("aura: name-gated target range = 1..1", amn == 1 and amx == 1, tostring(amn) .. "," .. tostring(amx))
  check("aura: takeable from pack (was ok=N regression)", CardUtil.can_take_pack_card(aura) == true)
end

-- a booster-state-gated consumable still reads takeable: can_take_pack_card uses (any_state=true, skip_check=true) like handlers/use_card
local captured
local gated = mk("c_high_priestess", "Tarot", 0)
gated.can_use_consumeable = function(_self, any_state, skip_check)
  captured = { any_state = any_state, skip_check = skip_check }
  return any_state == true and skip_check == true  -- "usable" only once the transient state lock is skipped
end
check("pack-ok: state-gated consumable reads takeable", CardUtil.can_take_pack_card(gated) == true)
check("pack-ok: can_take_pack_card passes any_state=true", captured ~= nil and captured.any_state == true)
check("pack-ok: can_take_pack_card passes skip_check=true", captured ~= nil and captured.skip_check == true)

local unusable = mk("c_x", "Tarot", 0)
unusable.can_use_consumeable = function() return false end
check("pack-ok: unusable consumable not takeable", CardUtil.can_take_pack_card(unusable) == false)

-- fallback branch: no can_use_consumeable -> follows consumable-slot room
local plain = mk("c_plain", "Spectral", 0)
G.consumeables = { cards = {}, config = { card_limit = 2 } }
check("pack-ok: no-predicate consumable takeable with room", CardUtil.can_take_pack_card(plain) == true)
G.consumeables = { cards = { {}, {} }, config = { card_limit = 2 } }
check("pack-ok: no-predicate consumable blocked when slots full", CardUtil.can_take_pack_card(plain) == false)

-- Standard pack: any playing card (base.suit) is always takeable -- goes to the deck, not a capped slot
local playing = { base = { suit = "Hearts", value = "5" }, ability = { name = "5 of Hearts" } }
check("pack-ok: playing card always takeable (base.suit path)", CardUtil.can_take_pack_card(playing) == true)

-- Buffoon pack: a joker is takeable iff joker slots have room; a negative joker always is (it bumps the slot)
local function mk_joker(negative)
  return {
    ability = { set = "Joker", name = "j" },
    config = { center = { set = "Joker", key = "j_joker" } },
    edition = negative and { negative = true, key = "e_negative" } or nil,
  }
end
G.jokers = { cards = {}, config = { card_limit = 5 } }
check("pack-ok: joker takeable with joker room", CardUtil.can_take_pack_card(mk_joker(false)) == true)
G.jokers = { cards = { {}, {}, {}, {}, {} }, config = { card_limit = 5 } }
check("pack-ok: joker blocked when joker slots full", CardUtil.can_take_pack_card(mk_joker(false)) == false)
check("pack-ok: NEGATIVE joker takeable even when slots full", CardUtil.can_take_pack_card(mk_joker(true)) == true)

-- buy-side: a booster always has "room" to buy (it opens regardless of joker/consumable slots), every kind
for _, kind in ipairs({ "Buffoon", "Arcana", "Celestial", "Spectral", "Standard" }) do
  local booster = { ability = { set = "Booster", name = kind .. " Pack" }, config = { center = { set = "Booster", kind = kind } } }
  check("buy-space: " .. kind .. " booster always buyable slot-wise", CardUtil.can_buy_card_space(booster, "shop_booster") == true)
end

print(string.format("==== consumables: %d/%d PASS, %d FAIL ====", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
